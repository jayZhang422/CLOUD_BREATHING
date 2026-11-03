`timescale 1ns/1ps
// 【文件类型：.sv】DDR清单自主调度；复用原RPC算子引擎和官方DDR缓存。
// 0x26启动64B VOL1/VOL2头；VOL1 kind=2/3，VOL2另支持连续视图kind=4。
module op_volume_service #(parameter logic [31:0] COMPUTE_HZ=32'd125000000,
    parameter logic [18:0] TRANSFORM_PIXELS=19'd262144,
    parameter logic [9:0] TRANSFORM_WIDTH=10'd512,
    parameter logic [9:0] TRANSFORM_HEIGHT=10'd512)(
    input logic clk_i,
    input logic rst_n_i,
    input logic storage_idle_i,
    input logic image_ready_i,
    input logic req_valid_i,
    output logic req_ready_o,
    output logic resp_valid_o,
    output logic claim_o,
    output logic mem_valid_o,
    input logic mem_ready_i,
    output logic mem_write_o,
    input logic mem_rsp_valid_i,
    output logic mem_rsp_ready_o,
    input logic mem_rsp_error_i,
    input logic [30:0] image_base_i,
    input logic [31:0] image_slices_i,
    input logic [7:0] req_msg_i,
    input logic [31:0] req_id_i,
    input logic [15:0] req_len_i,
    input logic [511:0] req_body_i,
    output logic [4:0] req_data_addr_o,
    output logic req_data_en_o,
    input logic [255:0] req_data_i,
    output logic [15:0] resp_len_o,
    output logic [127:0] resp_body_o,
    output logic resp_data_we_o,
    output logic [4:0] resp_data_addr_o,
    output logic [255:0] resp_data_o,
    output logic [30:0] mem_addr_o,
    output logic [255:0] mem_data_o,
    output logic [31:0] mem_mask_o,
    input logic [255:0] mem_rsp_data_i
);
    typedef enum logic [4:0] {V_IDLE,V_FETCH,V_RETURN,V_DECODE,V_RUN,V_RUN_REPLY,
        V_POLL,V_POLL_REPLY,V_RELEASE,V_RELEASE_REPLY,V_GAP,V_TRANSFORM,V_TRANSFORM_WAIT,
        V_FENCE,V_FENCE_REPLY,V_COMPLETE,V_MUL,V_VALIDATE} volume_state_t;
    typedef enum logic [2:0] {R_IDLE,R_CHECK,R_DECODE,R_FORWARD,R_REPLY,R_WAIT,R_INNER} rpc_state_t;
    // kind-4 源视图的 DDR 上限（含）：结果区之后可一直放到 768MiB（物理 DDR 为 2GiB，AXI 地址 31 位）。
    // 原上限 0x20000000 在 334 层整卷下放不下 native_t，airway/tumor 的 gather 退化为全未命中。
    // 0x1E000000..0x20000000 仍由 op_engine 的 decoder concat 兼容映射占用，主机侧布局须避开。
    localparam logic [63:0] VIEW_TOP=64'h30000000;
    volume_state_t v_r,v_nxt,gap_next_r;
    rpc_state_t r_r,r_nxt;
    logic held_r,done_r,error_r,abort_r,seen_r,start_go_r;
    // START 合法性检查（约 17 级比较链）与扇出 1000+ 触发器的清零/装载使能分在两拍：
    // R_CHECK 把结果存入寄存器，R_DECODE 只使用该寄存器。body_r/length_r/id_r/identity_r
    // 在 R_IDLE 锁存后至 R_DECODE 结束均保持不变，因此寄存值与组合值逐位等价。
    logic start_ok_r,id_match_r;
    logic [31:0] identity_r,result_base_r,result_size_r,result_limit_r,count_r,index_r,script_r,volume_depth_r;
    logic vol2_r;
    logic [31:0] volume_slices_w;
    // 阶段周期计数 64 位：250MHz 下 32 位约 17s 即回绕，整卷推理远超该时长。
    logic [63:0] fetch_cycles_r,operator_cycles_r,gather_cycles_r,classify_cycles_r;
    logic [511:0] start_header_r,body_r,command_r;
    logic [7:0] msg_r,status_r,kind_r;
    logic [31:0] id_r;
    logic [15:0] length_r;
    logic [1:0] beat_r;
    logic [30:0] cursor_r;
    logic [127:0] reply_r;
    logic [15:0] reply_length_r;
    logic active_w,start_check_w,read_range_w,forward_w,volume_read_r,valid_transform_w,exhausted_w;
    logic inner_req_w,inner_ready_w,inner_resp_w,inner_claim_w,inner_response_r;
    logic [7:0] inner_msg_w;
    logic [31:0] inner_id_w;
    logic [15:0] inner_len_w,inner_resp_len_w;
    logic [511:0] inner_body_w;
    logic [127:0] inner_resp_body_w;
    logic inner_mem_w,inner_write_w,inner_rsp_ready_w;
    logic [30:0] inner_addr_w;
    logic [255:0] inner_data_w;
    logic [31:0] inner_mask_w;
    logic [1:0] source_ready_w,response_valid_w;
    logic transform_busy_w,transform_done_w,transform_error_w,transform_mem_w,transform_write_w,transform_rsp_ready_w;
    logic [30:0] transform_addr_w;
    logic [255:0] transform_data_w;
    logic [31:0] transform_mask_w;
    logic scheduler_mem_w,scheduler_write_w,scheduler_rsp_ready_w;
    logic [30:0] scheduler_addr_w;
    logic [31:0] scheduler_mask_w;
    logic [63:0] read_end_w,command_view_end_w,command_planes_bytes_w,command_plane_bytes_w;
    logic [40:0] plane_mul_accum_r,plane_mul_value_r;
    logic [21:0] row_mul_accum_r,row_mul_value_r;
    logic [9:0] plane_mul_shift_r,row_mul_shift_r;
    logic [3:0] mul_bit_r;
    logic vol2_fields_valid_w,vol2_products_valid_w;
    logic [95:0] inner_debug_w;
    logic [63:0] transform_read_count_r,transform_write_count_r;
    logic [31:0] transform_stall_count_r;
    logic [63:0] transform_response_wait_r,transform_response_count_r;
    logic [31:0] transform_cache_hit_w,transform_cache_miss_w;
    logic [31:0] transform_cache_hit_total_r,transform_cache_miss_total_r;
    logic [63:0] transform_kind4_cycles_r;
    logic [3:0] transform_pending_peak_r;
    logic [3:0] transform_pending_r;
    logic inner_data_we_w,query_debug_w,query_debug_tail_w,query_debug_ext_r;
    logic [4:0] inner_data_addr_w;
    logic [255:0] inner_reply_data_w;
    logic [255:0] query_debug_low_w,query_debug_high_w,query_debug_ext_w;
    assign query_debug_w=r_r==R_DECODE&&msg_r==8'h27&&length_r==16'd0&&held_r&&id_r==identity_r;
    assign query_debug_tail_w=r_r==R_REPLY&&msg_r==8'h27&&length_r==16'd0&&held_r&&id_r==identity_r;
    assign resp_data_we_o=query_debug_w||query_debug_tail_w||query_debug_ext_r||inner_data_we_w;
    assign resp_data_addr_o=query_debug_ext_r ? 5'd2 : query_debug_tail_w ? 5'd1 : query_debug_w ? 5'd0 : inner_data_addr_w;
    // QUERY VDG4: 三个 RAM 字。前两字与 VDG3 布局相同（计数取低 32 位），
    // 第三字携带各 64 位计数的高 32 位，PC 端组合后不再回绕。
    assign query_debug_low_w={operator_cycles_r[31:0],fetch_cycles_r[31:0],transform_response_wait_r[31:0],
        transform_stall_count_r,transform_write_count_r[31:0],transform_read_count_r[31:0],
        {19'd0,v_r[4],inner_debug_w[71:68],v_r[3:0],inner_debug_w[67:64]},32'h34474456};
    assign query_debug_high_w={transform_response_count_r[31:0],
        {24'd0,transform_pending_peak_r,transform_pending_r},
        transform_cache_miss_total_r+(kind_r==8'd4&&v_r==V_TRANSFORM_WAIT ? transform_cache_miss_w : 32'd0),
        transform_cache_hit_total_r+(kind_r==8'd4&&v_r==V_TRANSFORM_WAIT ? transform_cache_hit_w : 32'd0),
        transform_kind4_cycles_r[63:32],transform_kind4_cycles_r[31:0],classify_cycles_r[31:0],gather_cycles_r[31:0]};
    assign query_debug_ext_w={transform_response_count_r[63:32],transform_write_count_r[63:32],
        transform_read_count_r[63:32],transform_response_wait_r[63:32],classify_cycles_r[63:32],
        gather_cycles_r[63:32],operator_cycles_r[63:32],fetch_cycles_r[63:32]};
    assign resp_data_o=query_debug_ext_r ? query_debug_ext_w : query_debug_tail_w ? query_debug_high_w :
        query_debug_w ? query_debug_low_w : inner_reply_data_w;
    assign active_w=held_r&&!done_r;
    assign req_ready_o=r_r==R_IDLE;
    assign resp_valid_o=r_r==R_REPLY;
    assign resp_len_o=reply_length_r;
    assign resp_body_o=reply_r;
    assign claim_o=held_r||inner_claim_w||r_r!=R_IDLE;
    assign read_end_w={32'd0,body_r[31:0]}+{48'd0,body_r[47:32]};
    // VOL2 START 自带本卷深度；VOL1 继续使用旧 IMAGE_BEGIN 快照。
    assign volume_slices_w=vol2_r ? volume_depth_r : image_slices_i;
    assign read_range_w=done_r&&!error_r&&!abort_r&&id_r==identity_r&&
        length_r==16'd8&&body_r[63:48]==16'd0&&
        body_r[4:0]==5'd0&&body_r[47:32]>=16'd32&&body_r[47:32]<=16'd1024&&body_r[36:32]==5'd0&&
        body_r[31:0]>=result_base_r&&read_end_w<={32'd0,result_base_r}+{32'd0,result_size_r};
    // Decode the registered request body after op_board has updated its metadata snapshot.
    assign start_check_w=length_r==16'd64&&storage_idle_i&&body_r[95:64]==32'h08200000&&
        body_r[127:96]>=32'd1&&body_r[127:96]<=32'd65536&&body_r[159:128]==32'h00400000&&
        body_r[191:160]>=32'd1&&body_r[191:160]<=32'd480&&body_r[223:192]==32'h10000000&&
        body_r[255:224]==(body_r[191:160]<<19)&&body_r[511:288]==224'd0&&
        ((body_r[31:0]==32'h314c4f56&&body_r[63:32]==32'd1&&image_ready_i&&
          image_base_i==31'h00400000&&body_r[191:160]==image_slices_i&&body_r[287:256]==32'd0) ||
         (body_r[31:0]==32'h324c4f56&&body_r[63:32]==32'd2&&body_r[132:128]==5'd0&&body_r[287:256]==32'd0));
    assign exhausted_w=beat_r==2'd0&&index_r>=count_r;
    // 固定DDR分区；变换只读输入/坐标/特征，只写独立特征或结果区。
    assign command_view_end_w={32'd0,command_r[63:32]}+{32'd0,command_r[159:128]};
    assign command_planes_bytes_w={23'd0,plane_mul_accum_r};
    assign command_plane_bytes_w={42'd0,row_mul_accum_r};
    assign vol2_fields_valid_w=command_r[7:0]==8'd4&&vol2_r&&(command_r[15:8]&8'hf8)==8'd0&&(command_r[15:8]&8'h03)<=8'd2&&
            command_r[23:16]<=8'd1&&command_r[31:24]==8'd0&&
            command_r[127:96]>=32'd1&&command_r[127:96]<=32'd480&&
            command_r[175:160]>=16'd1&&command_r[175:160]<=16'd512&&
            command_r[191:176]>=16'd1&&command_r[191:176]<=16'd512&&
            command_r[223:192]>=command_r[175:160]&&command_r[223:192]<=32'd4096&&
            command_r[287:256]<command_r[127:96]&&command_r[319:288]<command_r[127:96]&&
            command_r[351:320]<command_r[127:96]&&command_r[36:32]==5'd0&&
            command_view_end_w[63:32]==32'd0&&
            (((command_r[63:32]>=32'h00400000&&command_view_end_w<=64'h08000000))||
             (command_r[63:32]>=result_base_r+result_size_r&&command_view_end_w<=VIEW_TOP))&&
            command_r[95:64]>=32'h0a000000&&command_r[95:64]<=32'h0fc00000&&
            command_r[68:64]==5'd0&&command_r[511:352]==160'd0;
    assign vol2_products_valid_w=command_r[159:128]>=command_planes_bytes_w[31:0]&&
            command_planes_bytes_w[63:32]==32'd0&&command_r[255:224]>=command_plane_bytes_w[31:0]&&
            command_plane_bytes_w[63:32]==32'd0;
    assign valid_transform_w=command_r[7:0]==kind_r&&
        (kind_r==8'd4 ? vol2_fields_valid_w&&vol2_products_valid_w :
        command_r[15:8]<=8'd2&&
        ((command_r[23:16]==8'd5&&command_r[31:24]==8'd0)||
         (command_r[23:16]==8'd1&&(command_r[31:24]==8'd5||command_r[31:24]==8'd8))||
         (command_r[23:16]==8'd2&&command_r[31:24]==8'd6))&&
        command_r[127:96]==volume_slices_w&&command_r[159:128]==32'd0&&command_r[511:352]==160'd0&&
        command_r[175:160]>=16'd1&&command_r[175:160]<=16'd512&&
        command_r[191:176]>=16'd1&&command_r[191:176]<=16'd512&&
        command_r[223:192]>=32'h08800000&&command_r[223:192]<=32'h08fff800&&command_r[196:192]==5'd0&&
        command_r[255:224]>=32'h08800000&&command_r[255:224]<=32'h08fff800&&command_r[228:224]==5'd0&&
        (kind_r==8'd2 ?
            (command_r[63:32]==32'h00400000&&command_r[95:64]>=32'h0a000000&&
             command_r[95:64]<=32'h0fc00000&&command_r[68:64]==5'd0&&
             command_r[287:256]<(volume_slices_w<<16)&&command_r[319:288]<(volume_slices_w<<16)&&
             command_r[351:320]<(volume_slices_w<<16)) :
            (command_r[63:32]>=32'h0a000000&&command_r[63:32]<=32'h0fc00000&&command_r[36:32]==5'd0&&
             command_r[95:64]>=32'h10000000&&command_r[95:64]<=result_limit_r&&
             command_r[82:64]==19'd0&&command_r[175:160]==16'd512&&command_r[191:176]==16'd512)));
    assign forward_w=r_r==R_FORWARD;
    always_comb begin
        inner_req_w=forward_w||v_r==V_RUN||v_r==V_POLL||v_r==V_RELEASE;
        inner_msg_w=msg_r;inner_id_w=id_r;inner_len_w=length_r;inner_body_w=body_r;
        if (volume_read_r) begin inner_id_w=32'd0;inner_body_w[63:48]=16'd1;end
        case(v_r)
            V_RUN,V_RUN_REPLY: begin
                inner_msg_w=8'h21;inner_id_w=identity_r+index_r+32'd1;inner_len_w=16'd64;
                inner_body_w=command_r;inner_body_w[415:384]=identity_r+index_r+32'd1;
            end
            V_POLL,V_POLL_REPLY: begin inner_msg_w=8'h22;inner_id_w=identity_r+index_r+32'd1;inner_len_w=16'd0;end
            V_RELEASE,V_RELEASE_REPLY: begin inner_msg_w=8'h24;inner_id_w=identity_r+index_r+32'd1;inner_len_w=16'd0;end
            default: ;
        endcase
        scheduler_mem_w=(v_r==V_FETCH&&!exhausted_w)||v_r==V_FENCE||transform_mem_w;
        scheduler_write_w=v_r==V_FENCE||transform_write_w;
        scheduler_addr_w=v_r==V_FETCH ? cursor_r : v_r==V_FENCE ? 31'd0 : transform_addr_w;
        scheduler_mask_w=v_r==V_FENCE ? 32'd0 : transform_mask_w;
        scheduler_rsp_ready_w=v_r==V_RETURN||v_r==V_FENCE_REPLY||transform_rsp_ready_w;
        r_nxt=r_r;
        case(r_r)
            R_IDLE: if(req_valid_i) r_nxt=R_CHECK;
            R_CHECK: r_nxt=R_DECODE;
            R_DECODE: begin
                r_nxt=R_REPLY;
                if(msg_r<8'h26&&(!held_r||(msg_r==8'h23&&read_range_w))) r_nxt=R_FORWARD;
            end
            R_FORWARD: if(inner_ready_w) r_nxt=R_INNER;
            R_INNER: if(inner_response_r) r_nxt=R_REPLY;
            R_REPLY: r_nxt=R_WAIT;
            R_WAIT: if(!req_valid_i) r_nxt=R_IDLE;
            default:r_nxt=R_IDLE;
        endcase
        v_nxt=v_r;
        case(v_r)
            V_IDLE: if(r_r==R_REPLY&&msg_r==8'h26&&start_go_r) v_nxt=V_FETCH;
            V_FETCH: if(exhausted_w)v_nxt=V_FENCE;else if(source_ready_w[1]) v_nxt=V_RETURN;
            V_RETURN: if(response_valid_w[1]) v_nxt=mem_rsp_error_i ? V_FENCE : beat_r==2'd2 ? V_DECODE : V_FETCH;
            V_DECODE: begin
                case(kind_r)
                    8'd1:v_nxt=abort_r ? V_FENCE : V_RUN;
                    8'd2,8'd3:v_nxt=abort_r||!valid_transform_w ? V_FENCE : V_TRANSFORM;
                    8'd4:v_nxt=abort_r||!vol2_fields_valid_w ? V_FENCE : V_MUL;
                    default:v_nxt=V_FENCE;
                endcase
            end
            V_RUN:if(inner_ready_w)v_nxt=V_RUN_REPLY;
            V_RUN_REPLY:if(inner_response_r)v_nxt=inner_resp_body_w[7:0]==8'd0 ? V_GAP : V_FENCE;
            V_POLL:if(inner_ready_w)v_nxt=V_POLL_REPLY;
            V_POLL_REPLY:if(inner_response_r)v_nxt=V_GAP;
            V_RELEASE:if(inner_ready_w)v_nxt=V_RELEASE_REPLY;
            V_RELEASE_REPLY:if(inner_response_r)v_nxt=inner_resp_body_w[7:0]==8'd0 ? V_GAP : V_FENCE;
            V_GAP:v_nxt=gap_next_r;
            V_MUL: if(abort_r) v_nxt=V_FENCE; else if(mul_bit_r==4'd9) v_nxt=V_VALIDATE;
            V_VALIDATE: v_nxt=abort_r||!vol2_products_valid_w ? V_FENCE : V_TRANSFORM;
            V_TRANSFORM:v_nxt=V_TRANSFORM_WAIT;
            V_TRANSFORM_WAIT:if(transform_done_w)v_nxt=transform_error_w||abort_r ? V_FENCE : V_FETCH;
            V_FENCE:if(source_ready_w[1])v_nxt=V_FENCE_REPLY;
            V_FENCE_REPLY:if(response_valid_w[1])v_nxt=V_COMPLETE;
            V_COMPLETE:v_nxt=V_IDLE;
            default:v_nxt=V_IDLE;
        endcase
    end
    op_service #(.COMPUTE_HZ(COMPUTE_HZ)) u_operator(
        .clk_i(clk_i),.rst_n_i(rst_n_i),.storage_idle_i(storage_idle_i),
        .image_ready_i(image_ready_i),.image_base_i(image_base_i),.image_slices_i(image_slices_i),
        .req_valid_i(inner_req_w),.req_ready_o(inner_ready_w),.req_msg_i(inner_msg_w),
        .req_id_i(inner_id_w),.req_len_i(inner_len_w),.req_body_i(inner_body_w),
        .resp_valid_o(inner_resp_w),.resp_len_o(inner_resp_len_w),.resp_body_o(inner_resp_body_w),
        .req_data_addr_o(req_data_addr_o),.req_data_en_o(req_data_en_o),.req_data_i(req_data_i),
        .resp_data_we_o(inner_data_we_w),.resp_data_addr_o(inner_data_addr_w),.resp_data_o(inner_reply_data_w),
        .claim_o(inner_claim_w),.mem_valid_o(inner_mem_w),.mem_ready_i(source_ready_w[0]),
        .mem_write_o(inner_write_w),.mem_addr_o(inner_addr_w),.mem_data_o(inner_data_w),.mem_mask_o(inner_mask_w),
        .mem_rsp_valid_i(response_valid_w[0]),.mem_rsp_ready_o(inner_rsp_ready_w),
        .mem_rsp_data_i(mem_rsp_data_i),.mem_rsp_error_i(mem_rsp_error_i),.debug_o(inner_debug_w));
    op_volume_transform #(.PIXELS(TRANSFORM_PIXELS),.OUTPUT_WIDTH(TRANSFORM_WIDTH),.OUTPUT_HEIGHT(TRANSFORM_HEIGHT)) u_transform(
        .clk_i(clk_i),.rst_n_i(rst_n_i),.start_i(v_r==V_TRANSFORM),.command_i(command_r),
        .busy_o(transform_busy_w),.done_o(transform_done_w),.error_o(transform_error_w),
        .mem_valid_o(transform_mem_w),.mem_ready_i(source_ready_w[1]&&v_r==V_TRANSFORM_WAIT),
        .mem_write_o(transform_write_w),.mem_addr_o(transform_addr_w),.mem_data_o(transform_data_w),.mem_mask_o(transform_mask_w),
        .mem_rsp_valid_i(response_valid_w[1]&&v_r==V_TRANSFORM_WAIT),.mem_rsp_ready_o(transform_rsp_ready_w),
        .mem_rsp_data_i(mem_rsp_data_i),.mem_rsp_error_i(mem_rsp_error_i),
        .compact_hit_count_o(transform_cache_hit_w),.compact_miss_count_o(transform_cache_miss_w));
    op_mem_arbiter u_memory(
        .clk_i(clk_i),.rst_n_i(rst_n_i),.req_valid_i({scheduler_mem_w,inner_mem_w}),.req_ready_o(source_ready_w),
        .req_write_i({scheduler_write_w,inner_write_w}),.req_addr_i({scheduler_addr_w,inner_addr_w}),
        .req_data_i({transform_data_w,inner_data_w}),.req_mask_i({scheduler_mask_w,inner_mask_w}),
        .rsp_valid_o(response_valid_w),.rsp_ready_i({scheduler_rsp_ready_w,inner_rsp_ready_w}),.pending_o(),
        .mem_valid_o(mem_valid_o),.mem_ready_i(mem_ready_i),.mem_write_o(mem_write_o),
        .mem_addr_o(mem_addr_o),.mem_data_o(mem_data_o),.mem_mask_o(mem_mask_o),
        .mem_rsp_valid_i(mem_rsp_valid_i),.mem_rsp_ready_o(mem_rsp_ready_o));
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if(!rst_n_i) begin
            r_r<=R_IDLE;v_r<=V_IDLE;inner_response_r<=1'b0;held_r<=1'b0;done_r<=1'b0;error_r<=1'b0;abort_r<=1'b0;seen_r<=1'b0;start_go_r<=1'b0;
            start_ok_r<=1'b0;id_match_r<=1'b0;
            identity_r<=32'd0;index_r<=32'd0;beat_r<=2'd0;volume_read_r<=1'b0;result_size_r<=32'd0;result_limit_r<=32'd0;volume_depth_r<=32'd0;
            vol2_r<=1'b0;
            fetch_cycles_r<=64'd0;operator_cycles_r<=64'd0;gather_cycles_r<=64'd0;classify_cycles_r<=64'd0;
            transform_read_count_r<=64'd0;transform_write_count_r<=64'd0;transform_stall_count_r<=32'd0;
            transform_response_wait_r<=64'd0;transform_response_count_r<=64'd0;query_debug_ext_r<=1'b0;
            transform_kind4_cycles_r<=64'd0;transform_pending_r<=4'd0;transform_pending_peak_r<=4'd0;
            transform_cache_hit_total_r<=32'd0;transform_cache_miss_total_r<=32'd0;
            plane_mul_accum_r<=41'd0;row_mul_accum_r<=22'd0;
            plane_mul_value_r<=41'd0;row_mul_value_r<=22'd0;
            plane_mul_shift_r<=10'd0;row_mul_shift_r<=10'd0;mul_bit_r<=4'd0;
        end else begin
            r_r<=r_nxt;v_r<=v_nxt;inner_response_r<=inner_resp_w;
            if(r_r==R_IDLE&&req_valid_i) begin
                msg_r<=req_msg_i;id_r<=req_id_i;length_r<=req_len_i;body_r<=req_body_i;volume_read_r<=1'b0;
            end
            start_go_r<=1'b0;
            if(r_r==R_CHECK) begin start_ok_r<=start_check_w; id_match_r<=id_r==identity_r; end
            query_debug_ext_r<=query_debug_tail_w; // R_REPLY 后一拍写第三个诊断字。
            if (v_r==V_FETCH || v_r==V_RETURN) fetch_cycles_r<=fetch_cycles_r+64'd1;
            if (v_r==V_RUN || v_r==V_RUN_REPLY || v_r==V_POLL || v_r==V_POLL_REPLY ||
                v_r==V_RELEASE || v_r==V_RELEASE_REPLY || v_r==V_GAP)
                operator_cycles_r<=operator_cycles_r+64'd1;
            if ((v_r==V_TRANSFORM || v_r==V_TRANSFORM_WAIT) && (kind_r==8'd2 || kind_r==8'd4))
                gather_cycles_r<=gather_cycles_r+64'd1;
            if ((v_r==V_TRANSFORM || v_r==V_TRANSFORM_WAIT) && kind_r==8'd4)
                transform_kind4_cycles_r<=transform_kind4_cycles_r+64'd1;
            if ((v_r==V_TRANSFORM || v_r==V_TRANSFORM_WAIT) && kind_r==8'd3)
                classify_cycles_r<=classify_cycles_r+64'd1;
            if (v_r==V_TRANSFORM_WAIT && transform_mem_w && source_ready_w[1]) begin
                if (transform_write_w) transform_write_count_r<=transform_write_count_r+64'd1;
                else transform_read_count_r<=transform_read_count_r+64'd1;
            end
            if (v_r==V_TRANSFORM_WAIT && transform_mem_w && !source_ready_w[1])
                transform_stall_count_r<=transform_stall_count_r+32'd1;
            if (v_r==V_TRANSFORM_WAIT && transform_pending_r!=4'd0 && !response_valid_w[1])
                transform_response_wait_r<=transform_response_wait_r+64'd1;
            if (v_r==V_TRANSFORM_WAIT && response_valid_w[1] && transform_rsp_ready_w)
                transform_response_count_r<=transform_response_count_r+64'd1;
            if (v_r==V_TRANSFORM_WAIT && transform_done_w && kind_r==8'd4) begin
                transform_cache_hit_total_r<=transform_cache_hit_total_r+transform_cache_hit_w;
                transform_cache_miss_total_r<=transform_cache_miss_total_r+transform_cache_miss_w;
            end
            if (v_r==V_TRANSFORM_WAIT && transform_mem_w && source_ready_w[1] &&
                !(response_valid_w[1] && transform_rsp_ready_w) && transform_pending_r>=transform_pending_peak_r)
                transform_pending_peak_r<=transform_pending_r+4'd1;
            case ({v_r==V_TRANSFORM_WAIT&&transform_mem_w&&source_ready_w[1],
                   v_r==V_TRANSFORM_WAIT&&response_valid_w[1]&&transform_rsp_ready_w})
                2'b10: transform_pending_r<=transform_pending_r+4'd1;
                2'b01: transform_pending_r<=transform_pending_r-4'd1;
                default: ;
            endcase
            if(r_r==R_DECODE) begin
                reply_length_r<=16'd16;
                if(query_debug_w)reply_length_r<=16'd112;
                reply_r<={index_r,result_size_r,identity_r,8'd0,8'hfe,(held_r ? (done_r ? (error_r||abort_r ? 8'd3 : 8'd2) : 8'd1) : 8'd0),8'd0};
                case(msg_r)
                    8'h26:begin
                        if(held_r) begin
                            if(!id_match_r)reply_r[7:0]<=8'd1;
                            else if(length_r!=16'd64||body_r!=start_header_r)reply_r[7:0]<=8'd2;
                        end else if(seen_r&&id_match_r)reply_r[7:0]<=8'd6;
                        else if(inner_claim_w)reply_r[7:0]<=8'd1;
                        else if(!start_ok_r)reply_r[7:0]<=8'd2;
                        else begin
                            held_r<=1'b1;done_r<=1'b0;error_r<=1'b0;abort_r<=1'b0;seen_r<=1'b1;identity_r<=id_r;start_header_r<=body_r;
                            start_go_r<=1'b1;
                            fetch_cycles_r<=64'd0;operator_cycles_r<=64'd0;gather_cycles_r<=64'd0;classify_cycles_r<=64'd0;
                            transform_read_count_r<=64'd0;transform_write_count_r<=64'd0;transform_stall_count_r<=32'd0;
                            transform_response_wait_r<=64'd0;transform_response_count_r<=64'd0;
                            transform_kind4_cycles_r<=64'd0;transform_pending_r<=4'd0;transform_pending_peak_r<=4'd0;
                            transform_cache_hit_total_r<=32'd0;transform_cache_miss_total_r<=32'd0;
                            script_r<=body_r[95:64];cursor_r<=body_r[94:64];count_r<=body_r[127:96];volume_depth_r<=body_r[191:160];index_r<=32'd0;beat_r<=2'd0;
                            result_base_r<=body_r[223:192];result_size_r<=body_r[255:224];
                            result_limit_r<=body_r[255:224]+32'h0ff80000;
                            vol2_r<=body_r[31:0]==32'h324c4f56;
                            reply_r<={32'd0,body_r[255:224],id_r,8'd0,8'hfe,8'd1,8'd0};
                        end
                    end
                    8'h22,8'h27:begin
                        if(length_r!=16'd0)reply_r[7:0]<=8'd2;
                        else if(msg_r==8'h27&&(!held_r||id_r!=identity_r))reply_r[7:0]<=8'd6;
                    end
                    8'h24,8'h28:begin
                        if(length_r!=16'd0)reply_r[7:0]<=8'd2;
                        else if(id_r!=identity_r||(!held_r&&!seen_r))reply_r[7:0]<=8'd6;
                        else if(!held_r)reply_r[7:0]<=8'd0; // 丢失ACK后允许同身份重复释放。
                        else if(!done_r)reply_r[7:0]<=8'd1;
                        else held_r<=1'b0;
                    end
                    8'h25,8'h29:begin
                        if(length_r!=16'd0)reply_r[7:0]<=8'd2;
                        else if(!held_r||id_r!=identity_r)reply_r[7:0]<=8'd6;
                        else if(!done_r)abort_r<=1'b1;
                    end
                    8'h23:begin if(held_r&&read_range_w)volume_read_r<=1'b1;else if(held_r)reply_r[7:0]<=active_w ? 8'd1 : 8'd6;end
                    default:if(held_r)reply_r[7:0]<=8'd1;
                endcase
            end
            if(r_r==R_INNER&&inner_response_r)begin
                reply_r<=inner_resp_body_w;reply_length_r<=inner_resp_len_w;
                if(volume_read_r)begin reply_r[63:32]<=identity_r;reply_r[95:64]<=result_size_r;end
            end
            if(v_r==V_RETURN&&response_valid_w[1])begin
                cursor_r<=cursor_r+31'd32;beat_r<=beat_r==2'd2 ? 2'd0 : beat_r+2'd1;
                case(beat_r)
                    2'd0:kind_r<=mem_rsp_data_i[7:0];
                    2'd1:command_r[255:0]<=mem_rsp_data_i;
                    default:command_r[511:256]<=mem_rsp_data_i;
                endcase
                if(mem_rsp_error_i)error_r<=1'b1;
            end
            if(v_r==V_FETCH&&exhausted_w)error_r<=1'b1;
            if(v_r==V_DECODE)begin
                if(!(kind_r==8'd1||((kind_r==8'd2||kind_r==8'd3)&&valid_transform_w)||
                    (kind_r==8'd4&&vol2_fields_valid_w)||
                    (kind_r==8'hff&&index_r+32'd1==count_r&&command_r==512'd0)))error_r<=1'b1;
                if(kind_r==8'hff)index_r<=index_r+32'd1;
            end
            if(v_r==V_DECODE&&kind_r==8'd4&&vol2_fields_valid_w) begin
                // 仅控制校验使用10拍移位累加；保留完整乘积，不能截断非法长度。
                plane_mul_accum_r<=41'd0;row_mul_accum_r<=22'd0;
                plane_mul_value_r<={9'd0,command_r[255:224]};row_mul_value_r<=command_r[213:192];
                plane_mul_shift_r<=command_r[105:96];row_mul_shift_r<=command_r[185:176];
                mul_bit_r<=4'd0;
            end
            if(v_r==V_MUL) begin
                if(plane_mul_shift_r[0]) plane_mul_accum_r<=plane_mul_accum_r+plane_mul_value_r;
                if(row_mul_shift_r[0]) row_mul_accum_r<=row_mul_accum_r+row_mul_value_r;
                plane_mul_value_r<=plane_mul_value_r<<1'b1;row_mul_value_r<=row_mul_value_r<<1'b1;
                plane_mul_shift_r<=plane_mul_shift_r>>1'b1;row_mul_shift_r<=row_mul_shift_r>>1'b1;
                mul_bit_r<=mul_bit_r+4'd1;
            end
            if(v_r==V_VALIDATE&&!vol2_products_valid_w) error_r<=1'b1;
            if(v_r==V_RUN_REPLY&&inner_response_r)begin gap_next_r<=V_POLL;if(inner_resp_body_w[7:0]!=8'd0)error_r<=1'b1;end
            if(v_r==V_POLL_REPLY&&inner_response_r)begin
                gap_next_r<=inner_resp_body_w[15:8]==8'd1 ? V_POLL : V_RELEASE;
                if(inner_resp_body_w[7:0]!=8'd0||inner_resp_body_w[15:8]==8'd3)error_r<=1'b1;
            end
            if(v_r==V_RELEASE_REPLY&&inner_response_r)begin
                index_r<=index_r+32'd1;gap_next_r<=error_r||abort_r ? V_FENCE : V_FETCH;
                if(inner_resp_body_w[7:0]!=8'd0)error_r<=1'b1;
            end
            if(v_r==V_TRANSFORM_WAIT&&transform_done_w)begin index_r<=index_r+32'd1;if(transform_error_w)error_r<=1'b1;end
            if(v_r==V_FENCE_REPLY&&response_valid_w[1]&&mem_rsp_error_i)error_r<=1'b1;
            if(v_r==V_COMPLETE)done_r<=1'b1;
        end
    end
endmodule
