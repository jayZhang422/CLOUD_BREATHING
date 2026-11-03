`timescale 1ns/1ps
// 【文件类型：.sv】共享整卷预处理/标签合并单元；单笔保序DDR，八行32B寄存缓存。
// kind=2：Q16三线性采样至P16；kind=3：INT16分类并合并原生网格UINT16。
// 坐标表由PC离线生成，数学计算、方向变换、分类及结果写入均在FPGA执行。
// kind=3 且朝向为 1/2、像素数为 8192 的整数倍时走 16x16 分块路径：
//   朝向 1/2 的头特征地址 = {head_y,head_x}，相邻像素 x 变化使地址跨 8KB，逐像素必然完整未命中；
//   分块后列内走 16 行，同一列的 16 个头像素落在连续 256B，列首背靠背预取这些 32B 行，其后像素全部命中。
//   预取只是性能提示：像素查表仍走 READ_LOOKUP，漏预取或被淘汰只会变慢，不影响结果。
//   结果行在片上 16x16 槽缓冲中累积（旧结果与新类别按位或），整块 16 行写回，旧值/类别规则与逐像素路径一致。
module op_volume_transform #(
    parameter logic [18:0] PIXELS=19'd262144,
    parameter logic [9:0] OUTPUT_WIDTH=10'd512,
    parameter logic [9:0] OUTPUT_HEIGHT=10'd512,
    parameter bit TILE_ENABLE=1'b1) (
    input logic clk_i, // 计算时钟
    input logic rst_n_i, // 控制复位
    input logic start_i, // 命令启动
    input logic [511:0] command_i, // 64B变换命令
    output logic busy_o, // 事务占用
    output logic done_o, // 全部写响应已返回
    output logic error_o, // DDR或参数错误
    output logic mem_valid_o, // 保序请求
    input logic mem_ready_i, // 请求许可
    output logic mem_write_o, // 写标志
    output logic [30:0] mem_addr_o, // 32B对齐地址
    output logic [255:0] mem_data_o, // 写数据
    output logic [31:0] mem_mask_o, // 字节写使能
    input logic mem_rsp_valid_i, // 返回有效
    output logic mem_rsp_ready_o, // 返回许可
    input logic [255:0] mem_rsp_data_i, // 返回数据
    input logic mem_rsp_error_i, // 返回错误
    output logic [31:0] compact_hit_count_o, // compact行缓存命中
    output logic [31:0] compact_miss_count_o // compact行缓存未命中
);
    typedef enum logic [6:0] {IDLE, PIXEL, X_GET, X_HAVE, Y_GET, Y_HAVE,
        SAMPLE_ADDR, SAMPLE_GET, SAMPLE_HAVE, X_MUL, X_ADD, Y_MUL, Y_ADD,
        Z_MUL, Z_ADD, ROUND_VALUE, NEXT_CHANNEL, GATHER_WRITE,
        PACK_OLD, PACK_OLD_HAVE, HEAD_ADDR, HEAD_GET, HEAD_HAVE, CLASSIFY,
        PACK_SET, NEXT_PIXEL, WRITE_REQ, WRITE_RSP, READ_LOOKUP, READ_REQ,
        READ_RSP, GATHER_DRAIN, FINISH, MUL_PIPE, MUL_RESULT,
        PMUL_LOAD, PMUL_STEP, PMUL_STORE, ROW_MUL, ROW_MUL2, ROW_ADD,
        TX_GET, TX_HAVE, TY_GET, TY_HAVE, TO_INIT, TO_ZERO, TO_GET, TO_HAVE,
        TC_INIT, TC_SET, TC_ADDR, TC_CHK, TC_DEC, TC_ISSUE, TC_NEXT, TC_COLLECT,
        TP_SET, TP_MERGE, TP_NEXT, TW_SET, TW_NEXT} state_t;
    state_t state_r, state_nxt, return_r, arithmetic_return_r;
    // ---- 分块 classify 路径 ----
    localparam bit TILE_OK = TILE_ENABLE && PIXELS != 19'd0 && PIXELS[12:0] == 13'd0 && PIXELS <= 19'd262144;
    localparam logic [4:0] TILE_ROWS_LAST = 5'((PIXELS >> 13) - 19'd1);
    logic tile_start_w, tile_r;
    logic [4:0] ty_r, tx_r;       // 块行/块列：y=16*ty+r，x=16*tx+c
    logic [3:0] c_r, r_r;         // 块内列/行
    logic [8:0] i_r;              // xmap 载入序号
    (* ram_style = "distributed" *) logic [8:0] xmap_ram_r [0:511];
    logic [8:0] ytile_r [0:15];
    logic [3:0] pf_n_r, pf_recv_r; // 预取已发/已收（至多 8，等于缓存行数）
    logic [25:0] pf_tag_r [0:7];
    logic [25:0] pf_last_r;
    logic pf_any_r;
    logic [15:0] tile_rd_w [0:15];
    logic [255:0] tile_line_w;
    logic tile_line_we_w, tile_pix_we_w;
    logic [31:0] map_value_w;
    logic map_bad_w;
    logic [511:0] cmd_r;
    logic [18:0] pixel_r;
    logic [1:0] channel_r;
    logic [2:0] corner_r, pair_r, best_r;
    logic [3:0] scan_r;
    logic signed [15:0] maximum_r;
    logic [15:0] class_bits_r;
    logic [31:0] xq_r, yq_r, zq_r;
    logic [9:0] native_x_w, native_y_w;
    logic [9:0] grid_w_w, grid_h_w;
    logic padding_w, gather_w, compact_w;
    logic [30:0] read_address_r, sample_address_r, write_address_r;
    logic [255:0] read_data_r, write_data_r, result_r;
    logic [31:0] write_mask_r;
    logic [127:0] gathered_r,gather_even_r;
    logic [286:0] gather_fifo_r[0:1];
    logic [1:0] gather_count_r;
    logic gather_head_r,gather_tail_r,gather_push_w,gather_pop_w;
    logic [2:0] response_tag_head_r,response_tag_tail_r;
    logic [7:0] response_tag_r;
    logic [3:0] response_tag_count_r;
    logic request_accept_w,response_accept_w,response_read_w,response_write_w;
    logic signed [7:0] samples_r[0:7];
    logic signed [25:0] xvalue_r[0:3];
    logic signed [42:0] yvalue_r[0:1];
    logic signed [57:0] zvalue_r;
    logic signed [57:0] base_r;
    logic signed [43:0] difference_r;
    logic signed [16:0] fraction_r;
    logic signed [60:0] product_r, product_pipe_r;
    logic [57:0] magnitude_w;
    logic [9:0] rounded_w;
    logic [255:0] cache_data_r[0:7];
    logic [25:0] cache_tag_r[0:7];
    logic [7:0] cache_valid_r;
    logic [2:0] replace_r, hit_slot_w;
    logic hit_w;
    // 命中统计晚一拍寄存，比较结果不再进入计数器使能。
    logic lookup_count_r, lookup_hit_r;
    logic [8:0] head_x_w, head_y_w;
    logic [31:0] source_z_w;
    logic [15:0] logit_w;
    // compact 地址 = 视图基址 + 平面偏移[channel] + 行偏移 + 列。
    // 平面偏移每条命令只算一次（移位累加，不用宽乘法器）；行偏移每像素算一次（寄存输入的小乘法）。
    logic [31:0] plane_off_r[0:2];
    logic [31:0] pmul_acc_r, pmul_val_r;
    logic [8:0] pmul_idx_r;
    logic [3:0] pmul_cnt_r;
    logic [1:0] pmul_ch_r;
    logic [9:0] row_nx_r, row_ny_r;
    logic [22:0] row_prod_r, row_prod_pipe_r;
    logic [30:0] pixel_base_r;
    assign compact_w = cmd_r[7:0] == 8'd4;
    assign gather_w = cmd_r[7:0] == 8'd2 || compact_w;
    assign grid_w_w = cmd_r[169:160];
    assign grid_h_w = cmd_r[185:176];
    always_comb begin
        native_x_w = {1'b0,pixel_r[8:0]};
        native_y_w = {1'b0,pixel_r[17:9]};
        if (compact_w) begin
            if (OUTPUT_WIDTH==10'd512 && OUTPUT_HEIGHT==10'd512) begin
                native_x_w={1'b0,pixel_r[8:0]};native_y_w={1'b0,pixel_r[17:9]};
            end else begin
                native_x_w=10'(pixel_r%OUTPUT_WIDTH);native_y_w=10'(pixel_r/OUTPUT_WIDTH);
            end
            case (cmd_r[15:8]&8'h03)
                8'd1: begin native_x_w={1'b0,pixel_r[17:9]};native_y_w={1'b0,pixel_r[8:0]};end
                8'd2: begin native_x_w=OUTPUT_WIDTH-10'd1-{1'b0,pixel_r[17:9]};
                            native_y_w=OUTPUT_HEIGHT-10'd1-{1'b0,pixel_r[8:0]};end
                default: ;
            endcase
            native_x_w=native_x_w-((OUTPUT_WIDTH-grid_w_w)>>1);
            native_y_w=native_y_w-((OUTPUT_HEIGHT-grid_h_w)>>1);
        end else begin
            case (cmd_r[15:8])
                8'd1: begin native_x_w = {1'b0,pixel_r[17:9]}; native_y_w = {1'b0,pixel_r[8:0]}; end
                8'd2: begin native_x_w = 10'd511-{1'b0,pixel_r[17:9]}; native_y_w = 10'd511-{1'b0,pixel_r[8:0]}; end
                default: ;
            endcase
            native_x_w = native_x_w - ((10'd512-grid_w_w)>>1);
            native_y_w = native_y_w - ((10'd512-grid_h_w)>>1);
        end
        padding_w = native_x_w >= grid_w_w || native_y_w >= grid_h_w;
        head_x_w = xq_r[8:0]; head_y_w = yq_r[8:0];
        case (cmd_r[15:8])
            8'd1: begin head_x_w = yq_r[8:0]; head_y_w = xq_r[8:0]; end
            8'd2: begin head_x_w = 9'd511-yq_r[8:0]; head_y_w = 9'd511-xq_r[8:0]; end
            default: ;
        endcase
        source_z_w = zq_r >> 16;
        if (corner_r[2] && source_z_w+32'd1 < cmd_r[127:96]) source_z_w = source_z_w+32'd1;
        hit_w = 1'b0; hit_slot_w = 3'd0;
        for (int k=0;k<8;k++) begin
            if (cache_valid_r[k] && cache_tag_r[k] == read_address_r[30:5]) begin hit_w=1'b1; hit_slot_w=3'(k); end
        end
        magnitude_w = zvalue_r[57] ? $unsigned(-zvalue_r) : $unsigned(zvalue_r);
        rounded_w = magnitude_w[57:48] + 10'((magnitude_w[47:0] > 48'h800000000000) ||
            (magnitude_w[47:0] == 48'h800000000000 && magnitude_w[48]));
        logit_w = read_data_r[(sample_address_r[4] ? 128 : 0)+scan_r*16 +: 16];
        busy_o = state_r != IDLE; done_o = state_r == FINISH;
        mem_valid_o = response_tag_count_r < 4'd8 && (gather_w ?
            (gather_count_r != 2'd0 || state_r == READ_REQ) : state_r == READ_REQ || state_r == WRITE_REQ ||
            state_r == TC_ISSUE);
        mem_write_o = gather_w ? (gather_count_r != 2'd0) : state_r == WRITE_REQ;
        mem_addr_o = gather_w && gather_count_r != 2'd0 ? gather_fifo_r[gather_head_r][286:256] :
            mem_write_o ? write_address_r : {read_address_r[30:5],5'd0};
        mem_data_o = gather_w && gather_count_r != 2'd0 ? gather_fifo_r[gather_head_r][255:0] :
            gather_w ? write_data_r : result_r;
        mem_mask_o = gather_w && gather_count_r != 2'd0 ? 32'hffffffff :
            mem_write_o ? write_mask_r : compact_w && state_r == READ_REQ ? 32'd6 : 32'd0;
        mem_rsp_ready_o = response_tag_count_r != 4'd0 &&
            (response_tag_r[response_tag_head_r] || state_r == READ_RSP || state_r == WRITE_RSP ||
             state_r == TC_COLLECT);
        request_accept_w = mem_valid_o && mem_ready_i && response_tag_count_r < 4'd8;
        response_accept_w = mem_rsp_valid_i && mem_rsp_ready_o;
        response_write_w = response_accept_w && response_tag_r[response_tag_head_r];
        response_read_w = response_accept_w && !response_tag_r[response_tag_head_r];
        gather_pop_w = gather_w && gather_count_r != 2'd0 && request_accept_w;
        gather_push_w = state_r == GATHER_WRITE && pixel_r[0] &&
            (gather_count_r < 2'd2 || gather_pop_w);
        tile_start_w = TILE_OK && command_i[7:0] == 8'd3 && (command_i[15:8] == 8'd1 || command_i[15:8] == 8'd2);
        // 查表值：32 位字取自 32B 行；> 511 为非法。
        map_value_w = read_data_r[read_address_r[4:2]*32 +: 32];
        map_bad_w = map_value_w > 32'd511;
        for (int k=0;k<16;k++) tile_line_w[k*16 +: 16] = tile_rd_w[k];
        tile_line_we_w = state_r == TO_ZERO || state_r == TO_HAVE;
        tile_pix_we_w = state_r == TP_MERGE;
        state_nxt = state_r;
        case (state_r)
            IDLE: if (start_i) state_nxt=command_i[7:0]==8'd4 ? PMUL_LOAD : tile_start_w ? TX_GET : PIXEL;
            PMUL_LOAD: state_nxt=PMUL_STEP;
            PMUL_STEP: if (pmul_cnt_r==4'd8) state_nxt=PMUL_STORE;
            PMUL_STORE: state_nxt=pmul_ch_r==2'd2 ? PIXEL : PMUL_LOAD;
            ROW_MUL: state_nxt=ROW_MUL2;
            ROW_MUL2: state_nxt=ROW_ADD;
            ROW_ADD: state_nxt=SAMPLE_ADDR;
            PIXEL: state_nxt=gather_w && padding_w ? GATHER_WRITE : compact_w ? ROW_MUL :
                (!gather_w && pixel_r[3:0]==4'd0 && cmd_r[31:24]!=8'd0 ? PACK_OLD : X_GET);
            X_GET: state_nxt=READ_LOOKUP;
            X_HAVE: state_nxt=read_data_r[read_address_r[4:2]*32 +: 32]>(gather_w ? 32'h01ff0000 : 32'd511) ? FINISH : Y_GET;
            Y_GET: state_nxt=READ_LOOKUP;
            Y_HAVE: state_nxt=read_data_r[read_address_r[4:2]*32 +: 32]>(gather_w ? 32'h01ff0000 : 32'd511) ? FINISH : gather_w ? SAMPLE_ADDR : HEAD_ADDR;
            SAMPLE_ADDR: state_nxt=SAMPLE_GET;
            SAMPLE_GET: state_nxt=READ_LOOKUP;
            SAMPLE_HAVE: state_nxt=compact_w ? (channel_r==2'd2 ? GATHER_WRITE : SAMPLE_ADDR) :
                (xq_r[15:0]==16'd0 && yq_r[15:0]==16'd0 && zq_r[15:0]==16'd0) ? NEXT_CHANNEL : corner_r==3'd7 ? X_MUL : SAMPLE_ADDR;
            X_MUL,Y_MUL,Z_MUL: state_nxt=MUL_PIPE;
            MUL_PIPE: state_nxt=MUL_RESULT; MUL_RESULT: state_nxt=arithmetic_return_r;
            X_ADD: state_nxt=pair_r==3'd3 ? Y_MUL : X_MUL;
            Y_ADD: state_nxt=pair_r==3'd1 ? Z_MUL : Y_MUL;
            Z_ADD: state_nxt=ROUND_VALUE;
            ROUND_VALUE: state_nxt=NEXT_CHANNEL;
            NEXT_CHANNEL: state_nxt=channel_r==2'd2 ? GATHER_WRITE : SAMPLE_ADDR;
            GATHER_WRITE: state_nxt=pixel_r[0] ?
                (gather_count_r < 2'd2 || gather_pop_w ?
                    (pixel_r==PIXELS-19'd1 ? GATHER_DRAIN : NEXT_PIXEL) : GATHER_WRITE) : NEXT_PIXEL;
            PACK_OLD: state_nxt=READ_LOOKUP; PACK_OLD_HAVE: state_nxt=X_GET;
            HEAD_ADDR: state_nxt=HEAD_GET; HEAD_GET: state_nxt=READ_LOOKUP;
            HEAD_HAVE: state_nxt=CLASSIFY;
            CLASSIFY: state_nxt=scan_r+4'd1 >= {1'b0,cmd_r[18:16]} ? PACK_SET : CLASSIFY;
            PACK_SET: state_nxt=tile_r ? TP_MERGE : NEXT_PIXEL;
            NEXT_PIXEL: state_nxt=gather_w ? PIXEL : pixel_r[3:0]==4'd15 ? WRITE_REQ : PIXEL;
            WRITE_REQ: if (request_accept_w) state_nxt=tile_r ? TW_NEXT : WRITE_RSP;
            WRITE_RSP: if (response_write_w) state_nxt=mem_rsp_error_i || pixel_r==PIXELS-19'd1 ? FINISH : PIXEL;
            READ_LOOKUP: state_nxt=hit_w ? return_r : READ_REQ;
            READ_REQ: if (request_accept_w) state_nxt=READ_RSP;
            READ_RSP: if (response_read_w) state_nxt=mem_rsp_error_i ? (tile_r ? GATHER_DRAIN : FINISH) : return_r;
            GATHER_DRAIN: if (gather_count_r == 2'd0 && response_tag_count_r == 4'd0) state_nxt=FINISH;
            // ---- 分块路径：载入 xmap(512) → 每块行载入 ymap(16) → 每块：旧结果行 → 逐列(预取+16像素) → 写回 16 行 ----
            TX_GET: state_nxt=READ_LOOKUP;
            TX_HAVE: state_nxt=map_bad_w ? GATHER_DRAIN : i_r == 9'd511 ? TY_GET : TX_GET; // 出错先排空在途写响应
            TY_GET: state_nxt=READ_LOOKUP;
            TY_HAVE: state_nxt=map_bad_w ? GATHER_DRAIN : r_r == 4'd15 ? TO_INIT : TY_GET;
            TO_INIT: state_nxt=cmd_r[31:24] == 8'd0 ? TO_ZERO : TO_GET;
            TO_ZERO: state_nxt=r_r == 4'd15 ? TC_INIT : TO_ZERO;
            TO_GET: state_nxt=READ_LOOKUP;
            TO_HAVE: state_nxt=r_r == 4'd15 ? TC_INIT : TO_GET;
            TC_INIT: state_nxt=TC_SET;
            TC_SET: state_nxt=TC_ADDR;
            TC_ADDR: state_nxt=TC_CHK;
            TC_CHK: state_nxt=TC_DEC;
            TC_DEC: state_nxt=(pf_n_r < 4'd8 && !hit_w && !(pf_any_r && read_address_r[30:5] == pf_last_r)) ? TC_ISSUE : TC_NEXT;
            TC_ISSUE: if (request_accept_w) state_nxt=TC_NEXT;
            TC_NEXT: state_nxt=r_r == 4'd15 ? TC_COLLECT : TC_SET;
            TC_COLLECT: state_nxt=pf_recv_r == pf_n_r ? TP_SET : TC_COLLECT;
            TP_SET: state_nxt=HEAD_ADDR;
            TP_MERGE: state_nxt=TP_NEXT;
            TP_NEXT: state_nxt=r_r != 4'd15 ? TP_SET : c_r != 4'd15 ? TC_INIT : TW_SET;
            TW_SET: state_nxt=WRITE_REQ;
            TW_NEXT: state_nxt=r_r != 4'd15 ? TW_SET : tx_r != 5'd31 ? TO_INIT :
                ty_r == TILE_ROWS_LAST ? GATHER_DRAIN : TY_GET;
            FINISH: state_nxt=IDLE;
            default: state_nxt=IDLE;
        endcase
    end
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r<=IDLE; cache_valid_r<=8'd0; replace_r<=3'd0; error_o<=1'b0;
            pixel_r<=19'd0; channel_r<=2'd0; corner_r<=3'd0; pair_r<=3'd0; scan_r<=4'd0;
            gather_count_r<=2'd0; gather_head_r<=1'b0; gather_tail_r<=1'b0;
            response_tag_head_r<=3'd0; response_tag_tail_r<=3'd0; response_tag_count_r<=4'd0;
            compact_hit_count_o<=32'd0; compact_miss_count_o<=32'd0; lookup_count_r<=1'b0;
            tile_r<=1'b0; ty_r<=5'd0; tx_r<=5'd0; c_r<=4'd0; r_r<=4'd0; i_r<=9'd0;
            pf_n_r<=4'd0; pf_recv_r<=4'd0; pf_any_r<=1'b0;
        end else begin
            state_r<=state_nxt;
            if (state_r==IDLE && start_i) begin
                cmd_r<=command_i; pixel_r<=19'd0; channel_r<=2'd0; corner_r<=3'd0; pmul_ch_r<=2'd0;
                tile_r<=tile_start_w; ty_r<=5'd0; tx_r<=5'd0; c_r<=4'd0; r_r<=4'd0; i_r<=9'd0;
                pf_n_r<=4'd0; pf_recv_r<=4'd0; pf_any_r<=1'b0;
                cache_valid_r<=8'd0; replace_r<=3'd0; error_o<=1'b0;
                gather_count_r<=2'd0; gather_head_r<=1'b0; gather_tail_r<=1'b0;
                response_tag_head_r<=3'd0; response_tag_tail_r<=3'd0; response_tag_count_r<=4'd0;
                compact_hit_count_o<=32'd0; compact_miss_count_o<=32'd0;
            end
            lookup_count_r<=state_r==READ_LOOKUP && compact_w && return_r==SAMPLE_HAVE;
            lookup_hit_r<=hit_w;
            if (lookup_count_r) begin
                if (lookup_hit_r) compact_hit_count_o<=compact_hit_count_o+32'd1;
                else compact_miss_count_o<=compact_miss_count_o+32'd1;
            end
            if (response_accept_w && mem_rsp_error_i) error_o<=1'b1;
            if((state_r==X_HAVE||state_r==Y_HAVE)&&state_nxt==FINISH)error_o<=1'b1;
            if((state_r==TX_HAVE||state_r==TY_HAVE)&&map_bad_w)error_o<=1'b1;
            if (state_r==READ_RSP && response_read_w && !mem_rsp_error_i) begin
                cache_data_r[replace_r]<=mem_rsp_data_i; cache_tag_r[replace_r]<=read_address_r[30:5];
                cache_valid_r[replace_r]<=1'b1; replace_r<=replace_r+3'd1;
            end
            // 只失效同址行，保留独立输入和坐标表；合并结果仍可读到最新写值。
            if (request_accept_w && mem_write_o && !(gather_w && gather_count_r != 2'd0)) begin
                for (int k=0;k<8;k++)
                    if(cache_tag_r[k]==write_address_r[30:5])cache_valid_r[k]<=1'b0;
            end
            if (state_r==PIXEL) begin
                channel_r<=2'd0; corner_r<=3'd0;
                gathered_r<=padding_w ? {104'd0,24'h808080} : 128'd0;
                zq_r<=cmd_r[287:256];
                if (!gather_w && pixel_r[3:0]==4'd0 && cmd_r[31:24]==8'd0) result_r<=256'd0;
            end
            if (state_r==X_GET) begin
                read_address_r<=cmd_r[222:192]+(gather_w ? {19'd0,native_x_w,2'd0} : {20'd0,pixel_r[8:0],2'd0}); return_r<=X_HAVE;
            end
            if (state_r==X_HAVE) xq_r<=read_data_r[read_address_r[4:2]*32 +: 32];
            if (state_r==Y_GET) begin
                read_address_r<=cmd_r[254:224]+(gather_w ? {19'd0,native_y_w,2'd0} : {20'd0,pixel_r[17:9],2'd0}); return_r<=Y_HAVE;
            end
            if (state_r==Y_HAVE) yq_r<=read_data_r[read_address_r[4:2]*32 +: 32];
            // 平面偏移：idx(9位)×平面字节数，逐位移位累加；乘积保持 32 位截断语义。
            if (state_r==PMUL_LOAD) begin
                pmul_acc_r<=32'd0; pmul_val_r<=cmd_r[255:224]; pmul_cnt_r<=4'd0;
                pmul_idx_r<=pmul_ch_r==2'd0 ? cmd_r[264:256] : pmul_ch_r==2'd1 ? cmd_r[296:288] : cmd_r[328:320];
            end
            if (state_r==PMUL_STEP) begin
                if (pmul_idx_r[0]) pmul_acc_r<=pmul_acc_r+pmul_val_r;
                pmul_val_r<={pmul_val_r[30:0],1'b0}; pmul_idx_r<={1'b0,pmul_idx_r[8:1]};
                pmul_cnt_r<=pmul_cnt_r+4'd1;
            end
            if (state_r==PMUL_STORE) begin
                plane_off_r[pmul_ch_r]<=pmul_acc_r; pmul_ch_r<=pmul_ch_r+2'd1;
            end
            // PIXEL 拍寄存本像素的行/列，其后三拍完成 行×步长 并并入像素基址。
            if (state_r==PIXEL) begin row_nx_r<=native_x_w; row_ny_r<=native_y_w; end
            if (state_r==ROW_ADD)
                pixel_base_r<=cmd_r[62:32]+31'(row_prod_pipe_r)+{21'd0,row_nx_r};
            if (state_r==SAMPLE_ADDR) begin
                if (compact_w) sample_address_r<=pixel_base_r+plane_off_r[channel_r][30:0];
                else sample_address_r<=cmd_r[62:32]+{source_z_w[12:0],18'd0}+
                    ({22'd0,yq_r[24:16]}+31'(corner_r[1] && yq_r[31:16]<16'd511))*31'd512+
                    {15'd0,xq_r[31:16]}+31'(corner_r[0] && xq_r[31:16]<16'd511);
            end
            if (state_r==SAMPLE_GET) begin read_address_r<=sample_address_r; return_r<=SAMPLE_HAVE; end
            if (state_r==SAMPLE_HAVE) begin
                if (compact_w) begin
                    gathered_r[channel_r*8 +: 8]<=read_data_r[sample_address_r[4:0]*8 +: 8];
                    if (channel_r!=2'd2) channel_r<=channel_r+2'd1;
                end else begin
                    samples_r[corner_r]<=read_data_r[sample_address_r[4:0]*8 +: 8];
                end
                if (!compact_w && xq_r[15:0]==16'd0 && yq_r[15:0]==16'd0 && zq_r[15:0]==16'd0)
                    gathered_r[channel_r*8 +: 8]<=read_data_r[sample_address_r[4:0]*8 +: 8];
                if (!compact_w) corner_r<=corner_r+3'd1;
                pair_r<=3'd0;
            end
            // 差分乘法和加法分拍，数据寄存器无异步复位以便DSP吸收。
            if (state_r==X_MUL) begin
                difference_r<=44'($signed({samples_r[pair_r*2+1][7],samples_r[pair_r*2+1]})-
                    $signed({samples_r[pair_r*2][7],samples_r[pair_r*2]}));
                fraction_r<=$signed({1'b0,xq_r[15:0]});arithmetic_return_r<=X_ADD;
                base_r<=$signed(samples_r[pair_r*2])*58'sd65536;
            end
            if (state_r==X_ADD) begin xvalue_r[pair_r]<=26'(base_r+product_pipe_r); pair_r<=pair_r==3'd3 ? 3'd0 : pair_r+3'd1; end
            if (state_r==Y_MUL) begin
                difference_r<=44'($signed({xvalue_r[pair_r*2+1][25],xvalue_r[pair_r*2+1]})-
                    $signed({xvalue_r[pair_r*2][25],xvalue_r[pair_r*2]}));
                fraction_r<=$signed({1'b0,yq_r[15:0]});arithmetic_return_r<=Y_ADD;
                base_r<=$signed(xvalue_r[pair_r*2])*58'sd65536;
            end
            if (state_r==Y_ADD) begin yvalue_r[pair_r]<=43'(base_r+product_pipe_r); pair_r<=pair_r==3'd1 ? 3'd0 : pair_r+3'd1; end
            if (state_r==Z_MUL) begin
                difference_r<=$signed({yvalue_r[1][42],yvalue_r[1]})-$signed({yvalue_r[0][42],yvalue_r[0]});
                fraction_r<=$signed({1'b0,zq_r[15:0]});arithmetic_return_r<=Z_ADD;
                base_r<=$signed(yvalue_r[0])*58'sd65536;
            end
            if (state_r==Z_ADD) zvalue_r<=58'(base_r+product_pipe_r);
            if (state_r==ROUND_VALUE) gathered_r[channel_r*8 +: 8]<=zvalue_r[57] ? 8'(-$signed(rounded_w)) : rounded_w[7:0];
            if (state_r==NEXT_CHANNEL && channel_r!=2'd2) begin
                channel_r<=channel_r+2'd1; corner_r<=3'd0;
                case (channel_r)
                    2'd0: zq_r<=cmd_r[319:288];
                    default: zq_r<=cmd_r[351:320];
                endcase
            end
            if (state_r==GATHER_WRITE) begin
                if (pixel_r[0]) begin
                    write_address_r<=cmd_r[94:64]+{9'd0,pixel_r[17:1],5'd0};
                    write_mask_r<=32'hffffffff;
                    write_data_r<={gathered_r,gather_even_r};
                end else gather_even_r<=gathered_r;
            end
            if (gather_push_w) begin
                gather_fifo_r[gather_tail_r]<={cmd_r[94:64]+{9'd0,pixel_r[17:1],5'd0},gathered_r,gather_even_r};
                gather_tail_r<=!gather_tail_r;
            end
            if (gather_pop_w) gather_head_r<=!gather_head_r;
            case ({gather_push_w,gather_pop_w})
                2'b10: gather_count_r<=gather_count_r+2'd1;
                2'b01: gather_count_r<=gather_count_r-2'd1;
                default: ;
            endcase
            if (request_accept_w) begin
                response_tag_r[response_tag_tail_r]<=mem_write_o;
                response_tag_tail_r<=response_tag_tail_r+3'd1;
            end
            if (response_accept_w) response_tag_head_r<=response_tag_head_r+3'd1;
            case ({request_accept_w,response_accept_w})
                2'b10: response_tag_count_r<=response_tag_count_r+4'd1;
                2'b01: response_tag_count_r<=response_tag_count_r-4'd1;
                default: ;
            endcase
            if (state_r==PACK_OLD) begin
                read_address_r<=cmd_r[94:64]+{13'd0,pixel_r[17:4],5'd0}; return_r<=PACK_OLD_HAVE;
            end
            if (state_r==PACK_OLD_HAVE) result_r<=cmd_r[31:24]==8'd0 ? 256'd0 : read_data_r;
            if (state_r==HEAD_ADDR||state_r==TC_ADDR) sample_address_r<=cmd_r[62:32]+{9'd0,head_y_w,head_x_w,4'd0};
            if (state_r==HEAD_GET) begin read_address_r<=sample_address_r; return_r<=HEAD_HAVE; end
            if (state_r==HEAD_HAVE) begin scan_r<=4'd0; maximum_r<=16'sh8000; best_r<=3'd0; end
            if (state_r==CLASSIFY) begin
                if ($signed(logit_w)>maximum_r) begin maximum_r<=$signed(logit_w); best_r<=scan_r[2:0]; end
                scan_r<=scan_r+4'd1;
            end
            if (state_r==PACK_SET) begin
                class_bits_r<=maximum_r>=16'sd0 ? (16'd1 << (cmd_r[27:24]+best_r)) : 16'd0;
            end
            if (state_r==NEXT_PIXEL) begin
                result_r[pixel_r[3:0]*16 +: 16]<=result_r[pixel_r[3:0]*16 +: 16] | class_bits_r;
                write_address_r<=cmd_r[94:64]+{13'd0,pixel_r[17:4],5'd0}; write_mask_r<=32'hffffffff;
            end
            if (state_r==NEXT_PIXEL && gather_w) pixel_r<=pixel_r+19'd1;
            else if (state_r==NEXT_PIXEL && pixel_r[3:0]!=4'd15) pixel_r<=pixel_r+19'd1;
            if (state_r==WRITE_RSP && response_write_w) pixel_r<=pixel_r+19'd1;
            if (state_r==READ_LOOKUP && hit_w) read_data_r<=cache_data_r[hit_slot_w];
            if (state_r==READ_RSP && response_read_w) read_data_r<=mem_rsp_data_i;
            // ---- 分块路径 ----
            if (state_r==TX_GET) begin
                read_address_r<=cmd_r[222:192]+{20'd0,i_r,2'd0}; return_r<=TX_HAVE;
            end
            if (state_r==TX_HAVE) begin
                i_r<=i_r+9'd1;            // 511 后回绕为 0
                if (i_r==9'd511) r_r<=4'd0;
            end
            if (state_r==TY_GET) begin
                read_address_r<=cmd_r[254:224]+{20'd0,ty_r,r_r,2'd0}; return_r<=TY_HAVE;
            end
            if (state_r==TY_HAVE) r_r<=r_r+4'd1;
            if (state_r==TO_INIT) begin r_r<=4'd0; c_r<=4'd0; end
            if (state_r==TO_GET) begin
                read_address_r<=cmd_r[94:64]+{13'd0,ty_r,r_r,tx_r,5'd0}; return_r<=TO_HAVE;
            end
            if (state_r==TO_ZERO||state_r==TO_HAVE) r_r<=r_r+4'd1;
            if (state_r==TC_INIT) begin pf_n_r<=4'd0; pf_recv_r<=4'd0; pf_any_r<=1'b0; r_r<=4'd0; end
            if (state_r==TC_SET||state_r==TP_SET) begin
                xq_r<={23'd0,xmap_ram_r[{tx_r,c_r}]}; yq_r<={23'd0,ytile_r[r_r]};
            end
            if (state_r==TC_CHK) read_address_r<=sample_address_r;
            if (state_r==TC_ISSUE && request_accept_w) begin
                pf_n_r<=pf_n_r+4'd1; pf_last_r<=read_address_r[30:5]; pf_any_r<=1'b1;
            end
            if (state_r==TC_NEXT) r_r<=r_r+4'd1;
            if (state_r==TC_COLLECT && response_read_w) begin
                pf_recv_r<=pf_recv_r+4'd1;
                if (!mem_rsp_error_i) begin
                    cache_data_r[replace_r]<=mem_rsp_data_i; cache_tag_r[replace_r]<=pf_tag_r[pf_recv_r[2:0]];
                    cache_valid_r[replace_r]<=1'b1; replace_r<=replace_r+3'd1;
                end
            end
            if (state_r==TP_NEXT) begin
                r_r<=r_r+4'd1;
                if (r_r==4'd15) c_r<=c_r+4'd1;
            end
            if (state_r==TW_SET) begin
                result_r<=tile_line_w;
                write_address_r<=cmd_r[94:64]+{13'd0,ty_r,r_r,tx_r,5'd0};
                write_mask_r<=32'hffffffff;
            end
            if (state_r==TW_NEXT) begin
                r_r<=r_r+4'd1;
                if (r_r==4'd15) begin
                    if (tx_r==5'd31) begin tx_r<=5'd0; ty_r<=ty_r+5'd1; end
                    else tx_r<=tx_r+5'd1;
                end
            end
        end
    end
    // 片上 RAM 写口单独成块（无复位），便于推断分布式 RAM。
    always_ff @(posedge clk_i) begin
        if (state_r==TX_HAVE) xmap_ram_r[i_r]<=map_value_w[8:0];
        if (state_r==TY_HAVE) ytile_r[r_r]<=map_value_w[8:0];
        if (state_r==TC_ISSUE && request_accept_w) pf_tag_r[pf_n_r[2:0]]<=read_address_r[30:5];
    end
    // 结果块缓冲：16 列各一块 16 深x16 位 RAM（地址=块内行 r_r）。整行装载（旧结果/清零）或单槽按位或合并。
    generate
        for (genvar gc=0; gc<16; gc++) begin : g_tile_col
            (* ram_style = "distributed" *) logic [15:0] mem_r [0:15];
            always_ff @(posedge clk_i) begin
                if (tile_line_we_w) mem_r[r_r] <= state_r==TO_ZERO ? 16'd0 : read_data_r[gc*16 +: 16];
                else if (tile_pix_we_w && c_r==4'(gc)) mem_r[r_r] <= mem_r[r_r] | class_bits_r;
            end
            assign tile_rd_w[gc] = mem_r[r_r];
        end
    endgenerate
    // XYZ分时复用一个乘法器；输入、乘积、输出三级寄存，不增加DDR事务。
    always_ff @(posedge clk_i) begin
        product_r<=difference_r*fraction_r;
        product_pipe_r<=product_r;
        // 行偏移：10 位行号 × 13 位步长（VOL2 校验保证 ≤4096），输入/乘积/输出三级寄存。
        row_prod_r<=row_ny_r*cmd_r[204:192];
        row_prod_pipe_r<=row_prod_r;
    end
endmodule
