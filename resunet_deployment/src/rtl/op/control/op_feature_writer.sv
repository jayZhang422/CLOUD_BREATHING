`timescale 1ns/1ps
// 【文件类型：.sv】生产写回最多32B；窗口导出仅在编译期调试构建中保留。
// 对齐后进入官方FIFO；done表示载荷已独立保存，idle表示所有写响应已交付。
module op_feature_writer #(
    parameter bit ENABLE_WIDE_DEBUG = 1'b0,
    parameter int PENDING_MAX = 8 // 最多在途写请求数
) (
    input logic clk_i, // 时钟域输入
    input logic rst_n_i, // 异步低有效控制复位
    input logic clear_i, // 新任务清除延迟错误，须在旧任务排空后使用
    input logic req_valid_i, // 握手有效，阻塞期间保持载荷
    output logic req_ready_o, // 握手接收许可
    output logic done_o, // 完成通知，须遵守排空条件
    output logic error_o, // 本次操作错误状态
    output logic idle_o, // 请求、队列和写响应均排空
    output logic mem_valid_o, // 握手有效，阻塞期间保持载荷
    input logic mem_ready_i, // 握手接收许可
    input logic mem_rsp_valid_i, // 握手有效，阻塞期间保持载荷
    output logic mem_rsp_ready_o, // 握手接收许可
    input logic mem_rsp_error_i, // 本次操作错误状态
    input logic [30:0] req_addr_i, // 地址字段，单位按模块接口约定
    input logic [(ENABLE_WIDE_DEBUG ? 3200 : 256)-1:0] req_data_i, // 首字节位于低位
    input logic [8:0] req_bytes_i, // 有效字节数或接口长度
    output logic [30:0] mem_addr_o, // 地址字段，单位按模块接口约定
    output logic [255:0] mem_data_o, // 数据载荷，低位承载首字节或首 lane
    output logic [31:0] mem_mask_o // DDR 事务接口字段
);
    typedef enum logic [2:0] {IDLE, FETCH, SHIFT, ALIGN, REQUEST, RETURN, FINISH} state_t;
    state_t state_r, state_nxt;
    logic [511:0] pair_r;
    logic [255:0] selected_r, mem_data_r, extract_w;
    logic [31:0] mem_mask_r;
    logic [8:0] cursor_r;
    logic [30:0] addr_r;
    logic [8:0] left_r;
    logic [5:0] count_w;
    logic error_r;
    logic [319:0] queue_data_w;
    logic queue_full_w, queue_empty_w, queue_push_w, queue_pop_w;
    logic [$clog2(PENDING_MAX):0] pending_r;
    logic [5:0] queued_r;
    assign queue_push_w = state_r == REQUEST && !queue_full_w;
    assign queue_pop_w = mem_valid_o && mem_ready_i;
    op_write_queue_fifo u_write_queue (
        .clk(clk_i), .rst(!rst_n_i), .din({1'b1,{addr_r[30:5],5'd0},mem_mask_r,mem_data_r}),
        .wr_en(queue_push_w), .rd_en(queue_pop_w), .dout(queue_data_w),
        .full(queue_full_w), .empty(queue_empty_w)
    );
    assign extract_w = 256'(pair_r >> {cursor_r[4:0],3'd0});
    always_comb begin
        count_w = 6'd32 - {1'b0,addr_r[4:0]};
        if (left_r < {3'd0,count_w}) count_w = left_r[5:0];
        mem_data_o = queue_data_w[255:0]; mem_mask_o = queue_data_w[287:256];
        req_ready_o = state_r == IDLE;
        done_o = state_r == FINISH; error_o = error_r;
        mem_valid_o = !queue_empty_w && pending_r < ($clog2(PENDING_MAX)+1)'(PENDING_MAX);
        mem_addr_o = queue_data_w[318:288];
        mem_rsp_ready_o = 1'b1;
        // FWFT的empty取消可能晚于写入；本域入/出队计数才能作为完成屏障。
        idle_o = state_r == IDLE && queued_r == 6'd0 && pending_r == '0;
        state_nxt = state_r;
        case (state_r)
            IDLE: if (req_valid_i) state_nxt = FETCH;
            FETCH: state_nxt = SHIFT;
            SHIFT: state_nxt = ALIGN;
            ALIGN: state_nxt = REQUEST;
            REQUEST: if (!queue_full_w) state_nxt = left_r == {3'd0,count_w} ? FINISH : FETCH;
            FINISH: state_nxt = IDLE;
            default: state_nxt = IDLE;
        endcase
    end
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= IDLE; addr_r <= 31'd0; left_r <= 9'd0; cursor_r <= 9'd0;
            error_r <= 1'b0; pending_r <= '0; queued_r <= 6'd0;
        end else begin
            state_r <= state_nxt;
            if (state_r == IDLE && req_valid_i) begin
                addr_r <= req_addr_i; left_r <= req_bytes_i;
                cursor_r <= 9'd0;
            end
            if (queue_push_w) begin
                addr_r <= addr_r + {25'd0,count_w};
                left_r <= left_r - {3'd0,count_w};
                cursor_r <= cursor_r + {3'd0,count_w};
            end
            if (clear_i) error_r <= 1'b0;
            else if (mem_rsp_valid_i && mem_rsp_error_i) error_r <= 1'b1;
            case ({queue_pop_w,mem_rsp_valid_i})
                2'b10: pending_r <= pending_r + 1'b1;
                2'b01: pending_r <= pending_r - 1'b1;
                default: ;
            endcase
            case ({queue_push_w,queue_pop_w})
                2'b10: queued_r <= queued_r + 6'd1;
                2'b01: queued_r <= queued_r - 6'd1;
                default: ;
            endcase
        end
    end
    generate
        if (ENABLE_WIDE_DEBUG) begin : g_wide_debug
            logic [255:0] chunks_r [0:12];
            always_ff @(posedge clk_i) begin
                if (state_r == IDLE && req_valid_i) begin
                    for (int c=0; c<12; c++) chunks_r[c] <= req_data_i[c*256 +: 256];
                    chunks_r[12] <= {128'd0,req_data_i[3199:3072]};
                end
                if (state_r == FETCH)
                    pair_r <= {(cursor_r[8:5] < 4'd12 ? chunks_r[cursor_r[8:5]+4'd1] : 256'd0),chunks_r[cursor_r[8:5]]};
            end
        end else begin : g_production
            logic [255:0] block_r;
            always_ff @(posedge clk_i) begin
                if (state_r == IDLE && req_valid_i) block_r <= req_data_i;
                if (state_r == FETCH) pair_r <= {256'd0,block_r};
            end
        end
    endgenerate
    always_ff @(posedge clk_i) begin
        if (state_r == SHIFT)
            for (int b=0; b<32; b++) selected_r[b*8 +: 8] <= 6'(b) < count_w ? extract_w[b*8 +: 8] : 8'd0;
        if (state_r == ALIGN) begin
            mem_data_r <= selected_r << {addr_r[4:0],3'd0};
            mem_mask_r <= (32'hffffffff >> (6'd32-count_w)) << addr_r[4:0];
        end
    end
endmodule
