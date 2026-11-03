`timescale 1ns/1ps
// 【文件类型：.sv】复用 DW 核心：将连续 OIHW 权重的16B读返回拼成一组，接现有窗口流。
// 仅输出原始 P16 INT32 MAC；冻结双分支量化统一由后级 ElementAdd 执行。
module op_dw_adapter #(
    parameter integer K = 32'd3
) (
    input  logic                  clk_i,          // 计算时钟
    input  logic                  rst_n_i,        // 异步低有效控制复位
    input  logic                  cfg_valid_i,    // 任务配置有效
    output logic                  cfg_ready_o,    // 任务配置许可
    input  logic [5:0]            groups_i,       // P16组数
    input  logic [9:0]            width_i,        // 图像宽度
    input  logic                  weights_valid_i,// 16B权重有效
    output logic                  weights_ready_o,// 16B权重许可
    input  logic [127:0]          weights_i,      // 连续OIHW字节
    input  logic                  valid_i,        // 窗口有效
    output logic                  ready_o,        // 窗口许可
    input  logic [K*K*128-1:0]    window_i,       // 行优先窗口，低位为左上角
    input  logic [5:0]            group_i,        // 窗口组号
    input  logic                  group_last_i,   // 本组最后像素
    input  logic                  last_i,         // 本任务最后像素
    output logic                  valid_o,        // MAC有效
    input  logic                  ready_i,        // MAC许可
    output logic [511:0]          mac_o,          // lane0在低位的16路INT32
    output logic                  last_o,         // 末输出标记
    output logic                  done_o          // 末输出握手后完成
);
    localparam integer TAPS = K*K;
    logic [K*K*128-1:0] weights_r;
    logic [4:0] beat_r;
    logic weights_valid_r, weights_ready_w;
    logic [9:0] row_r, col_r;
    assign weights_ready_o = !weights_valid_r && weights_ready_w;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            beat_r <= 5'd0; weights_valid_r <= 1'b0;
            row_r <= 10'd0; col_r <= 10'd0;
        end else begin
            if (cfg_valid_i && cfg_ready_o) begin
                beat_r <= 5'd0; weights_valid_r <= 1'b0;
                row_r <= 10'd0; col_r <= 10'd0;
            end
            if (weights_valid_r && weights_ready_w) weights_valid_r <= 1'b0;
            if (weights_valid_i && weights_ready_o) begin
                if (beat_r == 5'(TAPS-1)) begin
                    beat_r <= 5'd0; weights_valid_r <= 1'b1;
                end else beat_r <= beat_r + 5'd1;
            end
            if (valid_i && ready_o) begin
                if (group_last_i) begin row_r <= 10'd0; col_r <= 10'd0; end
                else if (col_r + 10'd1 == width_i) begin
                    row_r <= row_r + 10'd1; col_r <= 10'd0;
                end else col_r <= col_r + 10'd1;
            end
        end
    end
    always_ff @(posedge clk_i) begin
        if (weights_valid_i && weights_ready_o)
            weights_r[beat_r*128 +: 128] <= weights_i;
    end
    generate
        if (K == 32'd3) begin : g_dw3
            Dw3x3 u_dw (
                .io_cfg_i_valid(cfg_valid_i),
                .io_cfg_i_ready(cfg_ready_o),
                .io_cfg_i_payload_groups(groups_i),
                .io_cfg_i_payload_raw(1'b1),
                .io_weights_i_valid(weights_valid_r),
                .io_weights_i_ready(weights_ready_w),
                .io_weights_i_payload(weights_r),
                .io_params_i_valid(1'b1),
                .io_params_i_ready(),
                .io_params_i_payload(2048'd0),
                .io_input_i_valid(valid_i),
                .io_input_i_ready(ready_o),
                .io_input_i_payload_window_0_0(window_i[0 +: 128]),
                .io_input_i_payload_window_0_1(window_i[128 +: 128]),
                .io_input_i_payload_window_0_2(window_i[256 +: 128]),
                .io_input_i_payload_window_1_0(window_i[384 +: 128]),
                .io_input_i_payload_window_1_1(window_i[512 +: 128]),
                .io_input_i_payload_window_1_2(window_i[640 +: 128]),
                .io_input_i_payload_window_2_0(window_i[768 +: 128]),
                .io_input_i_payload_window_2_1(window_i[896 +: 128]),
                .io_input_i_payload_window_2_2(window_i[1024 +: 128]),
                .io_input_i_payload_tag_group(group_i),
                .io_input_i_payload_tag_row(row_r),
                .io_input_i_payload_tag_col(col_r),
                .io_input_i_payload_tag_group_last(group_last_i),
                .io_input_i_payload_tag_last(last_i),
                .io_output_o_valid(valid_o),
                .io_output_o_ready(ready_i),
                .io_output_o_payload_tag_group(),
                .io_output_o_payload_tag_row(),
                .io_output_o_payload_tag_col(),
                .io_output_o_payload_tag_group_last(),
                .io_output_o_payload_tag_last(last_o),
                .io_output_o_payload_mac_0(mac_o[0 +: 32]),
                .io_output_o_payload_mac_1(mac_o[32 +: 32]),
                .io_output_o_payload_mac_2(mac_o[64 +: 32]),
                .io_output_o_payload_mac_3(mac_o[96 +: 32]),
                .io_output_o_payload_mac_4(mac_o[128 +: 32]),
                .io_output_o_payload_mac_5(mac_o[160 +: 32]),
                .io_output_o_payload_mac_6(mac_o[192 +: 32]),
                .io_output_o_payload_mac_7(mac_o[224 +: 32]),
                .io_output_o_payload_mac_8(mac_o[256 +: 32]),
                .io_output_o_payload_mac_9(mac_o[288 +: 32]),
                .io_output_o_payload_mac_10(mac_o[320 +: 32]),
                .io_output_o_payload_mac_11(mac_o[352 +: 32]),
                .io_output_o_payload_mac_12(mac_o[384 +: 32]),
                .io_output_o_payload_mac_13(mac_o[416 +: 32]),
                .io_output_o_payload_mac_14(mac_o[448 +: 32]),
                .io_output_o_payload_mac_15(mac_o[480 +: 32]),
                .io_output_o_payload_q_0(),
                .io_output_o_payload_q_1(),
                .io_output_o_payload_q_2(),
                .io_output_o_payload_q_3(),
                .io_output_o_payload_q_4(),
                .io_output_o_payload_q_5(),
                .io_output_o_payload_q_6(),
                .io_output_o_payload_q_7(),
                .io_output_o_payload_q_8(),
                .io_output_o_payload_q_9(),
                .io_output_o_payload_q_10(),
                .io_output_o_payload_q_11(),
                .io_output_o_payload_q_12(),
                .io_output_o_payload_q_13(),
                .io_output_o_payload_q_14(),
                .io_output_o_payload_q_15(),
                .io_busy_o(),
                .io_done_o(done_o),
                .clk(clk_i),
                .resetn(rst_n_i)
            );
        end
        else if (K == 32'd5) begin : g_dw5
            Dw5x5 u_dw (
                .io_cfg_i_valid(cfg_valid_i),
                .io_cfg_i_ready(cfg_ready_o),
                .io_cfg_i_payload_groups(groups_i),
                .io_cfg_i_payload_raw(1'b1),
                .io_weights_i_valid(weights_valid_r),
                .io_weights_i_ready(weights_ready_w),
                .io_weights_i_payload(weights_r),
                .io_params_i_valid(1'b1),
                .io_params_i_ready(),
                .io_params_i_payload(2048'd0),
                .io_input_i_valid(valid_i),
                .io_input_i_ready(ready_o),
                .io_input_i_payload_window_0_0(window_i[0 +: 128]),
                .io_input_i_payload_window_0_1(window_i[128 +: 128]),
                .io_input_i_payload_window_0_2(window_i[256 +: 128]),
                .io_input_i_payload_window_0_3(window_i[384 +: 128]),
                .io_input_i_payload_window_0_4(window_i[512 +: 128]),
                .io_input_i_payload_window_1_0(window_i[640 +: 128]),
                .io_input_i_payload_window_1_1(window_i[768 +: 128]),
                .io_input_i_payload_window_1_2(window_i[896 +: 128]),
                .io_input_i_payload_window_1_3(window_i[1024 +: 128]),
                .io_input_i_payload_window_1_4(window_i[1152 +: 128]),
                .io_input_i_payload_window_2_0(window_i[1280 +: 128]),
                .io_input_i_payload_window_2_1(window_i[1408 +: 128]),
                .io_input_i_payload_window_2_2(window_i[1536 +: 128]),
                .io_input_i_payload_window_2_3(window_i[1664 +: 128]),
                .io_input_i_payload_window_2_4(window_i[1792 +: 128]),
                .io_input_i_payload_window_3_0(window_i[1920 +: 128]),
                .io_input_i_payload_window_3_1(window_i[2048 +: 128]),
                .io_input_i_payload_window_3_2(window_i[2176 +: 128]),
                .io_input_i_payload_window_3_3(window_i[2304 +: 128]),
                .io_input_i_payload_window_3_4(window_i[2432 +: 128]),
                .io_input_i_payload_window_4_0(window_i[2560 +: 128]),
                .io_input_i_payload_window_4_1(window_i[2688 +: 128]),
                .io_input_i_payload_window_4_2(window_i[2816 +: 128]),
                .io_input_i_payload_window_4_3(window_i[2944 +: 128]),
                .io_input_i_payload_window_4_4(window_i[3072 +: 128]),
                .io_input_i_payload_tag_group(group_i),
                .io_input_i_payload_tag_row(row_r),
                .io_input_i_payload_tag_col(col_r),
                .io_input_i_payload_tag_group_last(group_last_i),
                .io_input_i_payload_tag_last(last_i),
                .io_output_o_valid(valid_o),
                .io_output_o_ready(ready_i),
                .io_output_o_payload_tag_group(),
                .io_output_o_payload_tag_row(),
                .io_output_o_payload_tag_col(),
                .io_output_o_payload_tag_group_last(),
                .io_output_o_payload_tag_last(last_o),
                .io_output_o_payload_mac_0(mac_o[0 +: 32]),
                .io_output_o_payload_mac_1(mac_o[32 +: 32]),
                .io_output_o_payload_mac_2(mac_o[64 +: 32]),
                .io_output_o_payload_mac_3(mac_o[96 +: 32]),
                .io_output_o_payload_mac_4(mac_o[128 +: 32]),
                .io_output_o_payload_mac_5(mac_o[160 +: 32]),
                .io_output_o_payload_mac_6(mac_o[192 +: 32]),
                .io_output_o_payload_mac_7(mac_o[224 +: 32]),
                .io_output_o_payload_mac_8(mac_o[256 +: 32]),
                .io_output_o_payload_mac_9(mac_o[288 +: 32]),
                .io_output_o_payload_mac_10(mac_o[320 +: 32]),
                .io_output_o_payload_mac_11(mac_o[352 +: 32]),
                .io_output_o_payload_mac_12(mac_o[384 +: 32]),
                .io_output_o_payload_mac_13(mac_o[416 +: 32]),
                .io_output_o_payload_mac_14(mac_o[448 +: 32]),
                .io_output_o_payload_mac_15(mac_o[480 +: 32]),
                .io_output_o_payload_q_0(),
                .io_output_o_payload_q_1(),
                .io_output_o_payload_q_2(),
                .io_output_o_payload_q_3(),
                .io_output_o_payload_q_4(),
                .io_output_o_payload_q_5(),
                .io_output_o_payload_q_6(),
                .io_output_o_payload_q_7(),
                .io_output_o_payload_q_8(),
                .io_output_o_payload_q_9(),
                .io_output_o_payload_q_10(),
                .io_output_o_payload_q_11(),
                .io_output_o_payload_q_12(),
                .io_output_o_payload_q_13(),
                .io_output_o_payload_q_14(),
                .io_output_o_payload_q_15(),
                .io_busy_o(),
                .io_done_o(done_o),
                .clk(clk_i),
                .resetn(rst_n_i)
            );
        end
    endgenerate
endmodule
