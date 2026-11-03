`timescale 1ns/1ps
// 【文件类型：.sv】RX协议、独立计算、DDR UI三域；RPC稳定总线握手，DDR异步FIFO。
module op_board_wstream_before #(
    parameter logic [31:0] COMPUTE_HZ = 32'd125000000 // 性能记录频率，与输入时钟一致
)(
    input logic rx_clk_i, // 时钟域输入
    input logic compute_clk_i, // 官方Clock Wizard产生的独立计算时钟
    input logic ui_clk_i, // 时钟域输入
    input logic compute_locked_i, // Clock Wizard锁定；失锁异步清空事务链
    input logic rx_rst_n_i, // 异步低有效控制复位
    input logic ui_rst_n_i, // 异步低有效控制复位
    output logic compute_rst_n_o, // 计算域同步释放复位，供外部参数ROM使用
    input logic legacy_idle_rx_i, // 任务配置或协议控制字段
    input logic storage_idle_ui_i, // 任务配置或协议控制字段
    input logic image_ready_rx_i, // 握手接收许可
    input logic frame_valid_i, // 握手有效，阻塞期间保持载荷
    input logic body_en_i, // 数据载荷，低位承载首字节或首 lane
    output logic accept_o, // 任务配置或协议控制字段
    output logic block_rx_o, // 阶段占用与流控状态
    output logic claim_ui_o, // 阶段占用与流控状态
    output logic tx_start_o, // 任务配置或协议控制字段
    input logic tx_req_i, // 任务配置或协议控制字段
    input logic tx_done_i, // 完成通知，须遵守排空条件
    output logic wr_start_o, // 任务配置或协议控制字段
    input logic wr_ready_i, // 握手接收许可
    input logic wr_done_i, // 完成通知，须遵守排空条件
    input logic wr_error_i, // 本次操作错误状态
    input logic wr_fifo_re_i, // 任务配置或协议控制字段
    output logic wr_fifo_empty_o, // 任务配置或协议控制字段
    output logic rd_start_o, // 任务配置或协议控制字段
    input logic rd_ready_i, // 握手接收许可
    input logic rd_done_i, // 完成通知，须遵守排空条件
    input logic rd_error_i, // 本次操作错误状态
    input logic rd_fifo_we_i, // 任务配置或协议控制字段
    output logic rd_fifo_full_o, // 任务配置或协议控制字段
    input logic [30:0] image_base_rx_i, // 地址字段，单位按模块接口约定
    input logic [31:0] image_slices_rx_i, // 任务配置或协议控制字段
    input logic [7:0] msg_i, // 任务配置或协议控制字段
    input logic [31:0] id_i, // 任务配置或协议控制字段
    input logic [31:0] sequence_i, // 任务配置或协议控制字段
    input logic [15:0] body_len_i, // 数据载荷，低位承载首字节或首 lane
    input logic [15:0] body_count_i, // 数据载荷，低位承载首字节或首 lane
    input logic [7:0] body_data_i, // 数据载荷，低位承载首字节或首 lane
    output logic [7:0] tx_data_o, // 数据载荷，低位承载首字节或首 lane
    output logic [15:0] tx_len_o, // 有效字节数或接口长度
    output logic [30:0] wr_addr_o, // 地址字段，单位按模块接口约定
    output logic [31:0] wr_len_o, // 有效字节数或接口长度
    output logic [255:0] wr_fifo_data_o, // 数据载荷，低位承载首字节或首 lane
    output logic [30:0] rd_addr_o, // 地址字段，单位按模块接口约定
    output logic [31:0] rd_len_o, // 有效字节数或接口长度
    input logic [255:0] rd_fifo_data_i, // 数据载荷，低位承载首字节或首 lane
    output logic coeff_req_valid_o, // 独立 ROM 读取请求
    input logic coeff_req_ready_i, // ROM 请求接收许可
    output logic [30:0] coeff_req_addr_o, // ROM 参数空间字节地址
    input logic coeff_rsp_valid_i, // ROM 返回有效
    output logic coeff_rsp_ready_o, // ROM 返回接收许可
    input logic [255:0] coeff_rsp_data_i, // ROM 参数数据
    input logic coeff_rsp_error_i // ROM 地址错误
);
    logic req_valid_w, req_ready_w, resp_valid_w;
    logic [7:0] req_msg_w;
    logic [31:0] req_id_w, req_sequence_w;
    logic [15:0] req_len_w, resp_len_w;
    logic [511:0] req_body_w;
    logic [127:0] resp_body_w;
    logic [4:0] req_data_addr_w, resp_data_addr_w;
    logic [255:0] req_data_w, resp_data_w;
    logic req_data_en_w, resp_data_we_w;
    logic mem_valid_w, mem_ready_w, mem_write_w, mem_rsp_valid_w, mem_rsp_ready_w, mem_error_w, port_active_w;
    logic [30:0] mem_addr_w; logic [255:0] mem_data_w, mem_rsp_data_w; logic [31:0] mem_mask_w;
    logic request_full_w, request_empty_w, request_ready_w;
    logic [319:0] request_data_w;
    logic claim_w, port_ready_w;
    logic ddr_req_valid_w, ddr_rsp_valid_w, ddr_rsp_ready_w, ddr_error_w;
    logic [255:0] ddr_rsp_data_w;
    logic common_rst_n_w, cdc_active_w, ui_req_w, ui_ready_w, ui_write_w;
    logic ui_rsp_w, ui_rsp_ready_w, ui_error_w;
    logic [30:0] ui_addr_w;
    logic [255:0] ui_data_w, ui_rsp_data_w;
    logic [31:0] ui_mask_w;
    (* ASYNC_REG="TRUE" *) logic compute_reset_sync1_r, compute_reset_sync2_r;
    (* ASYNC_REG="TRUE" *) logic rx_reset_sync1_r, rx_reset_sync2_r;
    (* ASYNC_REG="TRUE" *) logic ui_reset_sync1_r, ui_reset_sync2_r;
    (* ASYNC_REG="TRUE" *) logic claim_sync1_r, claim_sync2_r;
    (* ASYNC_REG="TRUE" *) logic storage_idle_sync1_r, storage_idle_sync2_r;
    assign common_rst_n_w = rx_rst_n_i && ui_rst_n_i && compute_locked_i;
    assign compute_rst_n_o = compute_reset_sync2_r;
    // 任一侧复位都清空整条Op事务链，避免队列与响应标签残留。
    always_ff @(posedge compute_clk_i or negedge common_rst_n_w)
        if (!common_rst_n_w) begin compute_reset_sync1_r <= 1'b0; compute_reset_sync2_r <= 1'b0; end
        else begin compute_reset_sync1_r <= 1'b1; compute_reset_sync2_r <= compute_reset_sync1_r; end
    always_ff @(posedge rx_clk_i or negedge common_rst_n_w)
        if (!common_rst_n_w) begin rx_reset_sync1_r <= 1'b0; rx_reset_sync2_r <= 1'b0; end
        else begin rx_reset_sync1_r <= 1'b1; rx_reset_sync2_r <= rx_reset_sync1_r; end
    always_ff @(posedge ui_clk_i or negedge common_rst_n_w)
        if (!common_rst_n_w) begin ui_reset_sync1_r <= 1'b0; ui_reset_sync2_r <= 1'b0; end
        else begin ui_reset_sync1_r <= 1'b1; ui_reset_sync2_r <= ui_reset_sync1_r; end
    always_ff @(posedge ui_clk_i or negedge ui_reset_sync2_r)
        if (!ui_reset_sync2_r) begin claim_sync1_r <= 1'b0; claim_sync2_r <= 1'b0; end
        else begin claim_sync1_r <= claim_w; claim_sync2_r <= claim_sync1_r; end
    always_ff @(posedge compute_clk_i or negedge compute_rst_n_o)
        if (!compute_rst_n_o) begin storage_idle_sync1_r <= 1'b0; storage_idle_sync2_r <= 1'b0; end
        else begin storage_idle_sync1_r <= storage_idle_ui_i; storage_idle_sync2_r <= storage_idle_sync1_r; end
    logic image_ready_snapshot_r, image_ready_r;
    logic [30:0] image_base_snapshot_r;
    logic [31:0] image_slices_snapshot_r;
    logic [30:0] image_base_r;
    logic [31:0] image_slices_r;
    // 与transport请求toggle同拍保存；直到UDP回复完成禁止复用，计算域在握手后取快照。
    always_ff @(posedge rx_clk_i) begin
        if (accept_o) begin
            image_ready_snapshot_r <= image_ready_rx_i;
            image_base_snapshot_r <= image_base_rx_i;
            image_slices_snapshot_r <= image_slices_rx_i;
        end
    end
    always_ff @(posedge compute_clk_i or negedge compute_rst_n_o)
        if (!compute_rst_n_o) image_ready_r <= 1'b0;
        else if (req_valid_w && req_ready_w) image_ready_r <= image_ready_snapshot_r;
    always_ff @(posedge compute_clk_i) begin
        if (req_valid_w && req_ready_w) begin
            image_base_r <= image_base_snapshot_r;
            image_slices_r <= image_slices_snapshot_r;
        end
    end
    assign claim_ui_o = claim_sync2_r || cdc_active_w || port_active_w;
    op_transport u_transport (
        .rx_clk_i(rx_clk_i), .rx_rst_n_i(rx_reset_sync2_r), .ui_clk_i(compute_clk_i), .ui_rst_n_i(compute_rst_n_o),
        .legacy_idle_i(legacy_idle_rx_i), .block_ui_i(claim_w),
        .frame_valid_i(frame_valid_i), .msg_i(msg_i), .id_i(id_i), .sequence_i(sequence_i),
        .body_len_i(body_len_i), .body_en_i(body_en_i), .body_count_i(body_count_i), .body_data_i(body_data_i),
        .accept_o(accept_o), .block_rx_o(block_rx_o), .tx_start_o(tx_start_o), .tx_data_o(tx_data_o),
        .tx_len_o(tx_len_o), .tx_req_i(tx_req_i), .tx_done_i(tx_done_i),
        .req_valid_o(req_valid_w), .req_ready_i(req_ready_w), .req_msg_o(req_msg_w), .req_id_o(req_id_w),
        .req_sequence_o(req_sequence_w), .req_len_o(req_len_w), .req_body_o(req_body_w),
        .req_data_addr_i(req_data_addr_w), .req_data_en_i(req_data_en_w), .req_data_o(req_data_w),
        .resp_valid_i(resp_valid_w), .resp_len_i(resp_len_w), .resp_body_i(resp_body_w),
        .resp_data_we_i(resp_data_we_w), .resp_data_addr_i(resp_data_addr_w), .resp_data_i(resp_data_w)
    );
    op_service_wstream_before #(.COMPUTE_HZ(COMPUTE_HZ)) u_service (
        .clk_i(compute_clk_i), .rst_n_i(compute_rst_n_o), .storage_idle_i(storage_idle_sync2_r),
        .image_ready_i(image_ready_r), .image_base_i(image_base_r), .image_slices_i(image_slices_r),
        .req_valid_i(req_valid_w), .req_ready_o(req_ready_w), .req_msg_i(req_msg_w), .req_id_i(req_id_w),
        .req_len_i(req_len_w), .req_body_i(req_body_w), .resp_valid_o(resp_valid_w),
        .req_data_addr_o(req_data_addr_w), .req_data_en_o(req_data_en_w), .req_data_i(req_data_w),
        .resp_data_we_o(resp_data_we_w), .resp_data_addr_o(resp_data_addr_w), .resp_data_o(resp_data_w),
        .resp_len_o(resp_len_w), .resp_body_o(resp_body_w), .claim_o(claim_w),
        .mem_valid_o(mem_valid_w), .mem_ready_i(mem_ready_w), .mem_write_o(mem_write_w),
        .mem_addr_o(mem_addr_w), .mem_data_o(mem_data_w), .mem_mask_o(mem_mask_w),
        .mem_rsp_valid_i(mem_rsp_valid_w), .mem_rsp_ready_o(mem_rsp_ready_w),
        .mem_rsp_data_i(mem_rsp_data_w), .mem_rsp_error_i(mem_error_w)
    );
    // 复用官方FWFT请求FIFO，切断两级仲裁→地址分类→ready返回的组合长链。
    // 请求标签仍在service内按入队顺序保存；数据与地址必须作为同一拍缓存。
    assign mem_ready_w = !request_full_w;
    op_write_queue_fifo u_request_queue (
        .clk(compute_clk_i), .rst(!compute_rst_n_o),
        .din({mem_write_w,mem_addr_w,mem_mask_w,mem_data_w}),
        .wr_en(mem_valid_w && mem_ready_w),
        .rd_en(!request_empty_w && request_ready_w),
        .dout(request_data_w), .full(request_full_w), .empty(request_empty_w)
    );
    op_coeff_split u_split (
        .clk_i(compute_clk_i), .rst_n_i(compute_rst_n_o),
        .req_valid_i(!request_empty_w), .req_ready_o(request_ready_w),
        .req_write_i(request_data_w[319]), .req_addr_i(request_data_w[318:288]),
        .rsp_valid_o(mem_rsp_valid_w), .rsp_ready_i(mem_rsp_ready_w),
        .rsp_data_o(mem_rsp_data_w), .rsp_error_o(mem_error_w),
        .ddr_req_valid_o(ddr_req_valid_w), .ddr_req_ready_i(ui_ready_w),
        .ddr_rsp_valid_i(ddr_rsp_valid_w), .ddr_rsp_ready_o(ddr_rsp_ready_w),
        .ddr_rsp_data_i(ddr_rsp_data_w), .ddr_rsp_error_i(ddr_error_w),
        .coeff_req_valid_o(coeff_req_valid_o), .coeff_req_ready_i(coeff_req_ready_i),
        .coeff_req_addr_o(coeff_req_addr_o), .coeff_rsp_valid_i(coeff_rsp_valid_i),
        .coeff_rsp_ready_o(coeff_rsp_ready_o), .coeff_rsp_data_i(coeff_rsp_data_i),
        .coeff_rsp_error_i(coeff_rsp_error_i)
    );
    op_mem_cdc_wstream_before u_mem_cdc (
        .compute_clk_i(compute_clk_i), .compute_rst_n_i(compute_rst_n_o),
        .ui_clk_i(ui_clk_i), .ui_rst_n_i(ui_reset_sync2_r),
        .req_valid_i(ddr_req_valid_w), .req_ready_o(ui_ready_w),
        .req_write_i(request_data_w[319]), .req_addr_i(request_data_w[318:288]),
        .req_data_i(request_data_w[255:0]), .req_mask_i(request_data_w[287:256]),
        .rsp_valid_o(ddr_rsp_valid_w), .rsp_ready_i(ddr_rsp_ready_w), .rsp_data_o(ddr_rsp_data_w),
        .rsp_error_o(ddr_error_w), .active_ui_o(cdc_active_w),
        .ui_req_valid_o(ui_req_w), .ui_req_ready_i(port_ready_w && storage_idle_ui_i),
        .ui_req_write_o(ui_write_w), .ui_req_addr_o(ui_addr_w), .ui_req_data_o(ui_data_w), .ui_req_mask_o(ui_mask_w),
        .ui_rsp_valid_i(ui_rsp_w), .ui_rsp_ready_o(ui_rsp_ready_w),
        .ui_rsp_data_i(ui_rsp_data_w), .ui_rsp_error_i(ui_error_w)
    );
    op_ddr_port_wstream_before u_port (
        .clk_i(ui_clk_i), .rst_n_i(ui_reset_sync2_r),
        .cache_clear_i(!claim_sync2_r),
        .req_valid_i(ui_req_w && storage_idle_ui_i), .req_ready_o(port_ready_w),
        .req_write_i(ui_write_w), .req_addr_i(ui_addr_w), .req_data_i(ui_data_w), .req_mask_i(ui_mask_w),
        .rsp_valid_o(ui_rsp_w), .rsp_ready_i(ui_rsp_ready_w), .rsp_data_o(ui_rsp_data_w),
        .rsp_error_o(ui_error_w), .active_o(port_active_w),
        .wr_start_o(wr_start_o), .wr_addr_o(wr_addr_o), .wr_len_o(wr_len_o), .wr_ready_i(wr_ready_i),
        .wr_done_i(wr_done_i), .wr_error_i(wr_error_i), .wr_fifo_re_i(wr_fifo_re_i),
        .wr_fifo_empty_o(wr_fifo_empty_o), .wr_fifo_data_o(wr_fifo_data_o),
        .rd_start_o(rd_start_o), .rd_addr_o(rd_addr_o), .rd_len_o(rd_len_o), .rd_ready_i(rd_ready_i),
        .rd_done_i(rd_done_i), .rd_error_i(rd_error_i), .rd_fifo_we_i(rd_fifo_we_i),
        .rd_fifo_data_i(rd_fifo_data_i), .rd_fifo_full_o(rd_fifo_full_o)
    );
endmodule
