`timescale 1ns/1ps
// 【文件类型：.sv】已验收算子统一接线；生成 RTL 保持原样，配置与握手由调度器管理。
module op_core_bank (
    input logic clk_i, // 时钟域输入
    input logic rst_n_i, // 异步低有效控制复位
    input logic cfg_valid_i, // 握手有效，阻塞期间保持载荷
    output logic cfg_ready_o, // 握手接收许可
    input logic raw_i, // 任务配置或协议控制字段
    input logic int16_i, // 任务配置或协议控制字段
    input logic add_last_i, // 任务配置或协议控制字段
    input logic weights_valid_i, // 握手有效，阻塞期间保持载荷
    output logic weights_ready_o, // 握手接收许可
    input logic params_valid_i, // 握手有效，阻塞期间保持载荷
    output logic params_ready_o, // 握手接收许可
    input logic start_valid_i, // 握手有效，阻塞期间保持载荷
    output logic start_ready_o, // 握手接收许可
    input logic in_valid_i, // 握手有效，阻塞期间保持载荷
    output logic in_ready_o, // 握手接收许可
    input logic in_b_valid_i, // 握手有效，阻塞期间保持载荷
    output logic in_b_ready_o, // 握手接收许可
    output logic rd_valid_o, // 握手有效，阻塞期间保持载荷
    input logic rd_ready_i, // 握手接收许可
    output logic rd_source_o, // 任务配置或协议控制字段
    input logic rsp_valid_i, // 握手有效，阻塞期间保持载荷
    output logic rsp_ready_o, // 握手接收许可
    output logic out_valid_o, // 握手有效，阻塞期间保持载荷
    input logic out_ready_i, // 握手接收许可
    output logic out_last_o, // 任务配置或协议控制字段
    output logic done_o, // 完成通知，须遵守排空条件
    input logic [7:0] op_i, // 任务配置或协议控制字段
    input logic [9:0] cin_i, // PW 输入通道数，1..768
    input logic [9:0] cout_i, // PW 输出通道数，1..512
    input logic [18:0] pixels_i, // 任务配置或协议控制字段
    input logic [9:0] width_i, // 任务配置或协议控制字段
    input logic [9:0] height_i, // 任务配置或协议控制字段
    input logic [5:0] groups_i, // P16 通道组数，1..32
    input logic [31:0] words_b_i, // 任务配置或协议控制字段
    input logic [5:0] shift_i, // 任务配置或协议控制字段
    input logic [7:0] clamp_min_i, // 任务配置或协议控制字段
    input logic [7:0] clamp_max_i, // 任务配置或协议控制字段
    input logic [5:0] add_group_i, // Add 当前组号，0..31
    input logic [2047:0] add_params_i, // 任务配置或协议控制字段
    input logic [511:0] load_data_i, // 数据载荷，低位承载首字节或首 lane
    input logic [511:0] in_data_i, // 数据载荷，低位承载首字节或首 lane
    input logic [511:0] in_b_data_i, // 数据载荷，低位承载首字节或首 lane
    output logic [31:0] rd_addr_o, // 地址字段，单位按模块接口约定
    input logic [127:0] rsp_data_i, // 数据载荷，低位承载首字节或首 lane
    output logic [3199:0] out_data_o, // 数据载荷，低位承载首字节或首 lane
    output logic [127:0] out_mac_o, // 任务配置或协议控制字段
    output logic [18:0] out_pixel_o, // 任务配置或协议控制字段
    output logic [6:0] out_group_o, // PW 的 P4 输出组号，0..127
    output logic [3:0] out_mask_o // 任务配置或协议控制字段
);
 logic [7:1] cfg_ready_w, in_ready_w, valid_w, last_w, done_w;
 logic [3199:0] data_w [1:7];
 logic pw_rd_valid_w, pw_rsp_ready_w, concat_rd_valid_w, concat_rsp_ready_w, concat_source_w;
 logic [31:0] pw_addr_w, concat_addr_w;
 logic [18:0] pw_pixel_w; logic [6:0] pw_group_w; logic [3:0] pw_mask_w;
 logic [127:0] pw_mac_w;
 logic [63:0] pw_q_w;
 PwMac u_pw (
  .io_cfg_i_valid(cfg_valid_i && op_i == 8'd1),
  .io_cfg_i_ready(cfg_ready_w[1]),
  .io_cfg_i_payload_cin(cin_i),
  .io_cfg_i_payload_cout(cout_i),
  .io_cfg_i_payload_pixels(pixels_i),
  .io_cfg_i_payload_shift(shift_i),
  .io_cfg_i_payload_raw(raw_i),
  .io_cfg_i_payload_int16(int16_i),
  .io_weights_i_valid(weights_valid_i),
  .io_weights_i_ready(weights_ready_o),
  .io_weights_i_payload(load_data_i),
  .io_params_i_valid(params_valid_i),
  .io_params_i_ready(params_ready_o),
  .io_params_i_payload(load_data_i),
  .io_start_i_valid(start_valid_i),
  .io_start_i_ready(start_ready_o),
  .io_start_i_payload(1'b1),
  .io_busy_o(),
  .io_done_o(done_w[1]),
  .io_rd_o_valid(pw_rd_valid_w),
  .io_rd_o_ready(rd_ready_i && op_i == 8'd1),
  .io_rd_o_payload(pw_addr_w),
  .io_rsp_i_valid(rsp_valid_i && op_i == 8'd1),
  .io_rsp_i_ready(pw_rsp_ready_w),
  .io_rsp_i_payload(rsp_data_i),
  .io_output_o_valid(valid_w[1]),
  .io_output_o_ready(out_ready_i && op_i == 8'd1),
  .io_output_o_payload_pixel(pw_pixel_w),
  .io_output_o_payload_group(pw_group_w),
  .io_output_o_payload_mask(pw_mask_w),
  .io_output_o_payload_last(last_w[1]),
  .io_output_o_payload_raw(),
  .io_output_o_payload_int16(),
  .io_output_o_payload_mac_0(pw_mac_w[0 +: 32]),
  .io_output_o_payload_mac_1(pw_mac_w[32 +: 32]),
  .io_output_o_payload_mac_2(pw_mac_w[64 +: 32]),
  .io_output_o_payload_mac_3(pw_mac_w[96 +: 32]),
  .io_output_o_payload_q_0(pw_q_w[0 +: 16]),
  .io_output_o_payload_q_1(pw_q_w[16 +: 16]),
  .io_output_o_payload_q_2(pw_q_w[32 +: 16]),
  .io_output_o_payload_q_3(pw_q_w[48 +: 16]),
  .clk(clk_i),
  .resetn(rst_n_i)
 );
 assign data_w[1] = {3136'd0,pw_q_w}; assign in_ready_w[1] = 1'b0;
 assign data_w[2][3199:128] = 3072'd0;
 MaxPool2d_512x512_c16 u_core_2 (
  .io_cfg_i_valid(cfg_valid_i && op_i == 8'd2),
  .io_cfg_i_ready(cfg_ready_w[2]),
  .io_cfg_i_payload_width(width_i),
  .io_cfg_i_payload_height(height_i),
  .io_cfg_i_payload_groups(groups_i),
  .io_busy_o(),
  .io_done_o(done_w[2]),
  .io_input_i_valid(in_valid_i && op_i == 8'd2),
  .io_input_i_ready(in_ready_w[2]),
  .io_input_i_payload(in_data_i[127:0]),
  .io_output_o_valid(valid_w[2]),
  .io_output_o_ready(out_ready_i && op_i == 8'd2),
  .io_output_o_payload_last(last_w[2]),
  .io_output_o_payload_fragment_data(data_w[2][127:0]),
  .io_output_o_payload_fragment_group(),
  .io_output_o_payload_fragment_group_last(),
  .clk(clk_i),
  .resetn(rst_n_i)
 );
 assign data_w[3][3199:1152] = 2048'd0;
 LineBuffer_3x3 u_core_3 (
  .io_cfg_i_valid(cfg_valid_i && op_i == 8'd3),
  .io_cfg_i_ready(cfg_ready_w[3]),
  .io_cfg_i_payload_width(width_i),
  .io_cfg_i_payload_height(height_i),
  .io_cfg_i_payload_groups(groups_i),
  .io_busy_o(),
  .io_done_o(done_w[3]),
  .io_input_i_valid(in_valid_i && op_i == 8'd3),
  .io_input_i_ready(in_ready_w[3]),
  .io_input_i_payload(in_data_i[127:0]),
  .io_output_o_valid(valid_w[3]),
  .io_output_o_ready(out_ready_i && op_i == 8'd3),
  .io_output_o_payload_last(last_w[3]),
  .io_output_o_payload_fragment_window_0_0(data_w[3][0 +: 128]),
  .io_output_o_payload_fragment_window_0_1(data_w[3][128 +: 128]),
  .io_output_o_payload_fragment_window_0_2(data_w[3][256 +: 128]),
  .io_output_o_payload_fragment_window_1_0(data_w[3][384 +: 128]),
  .io_output_o_payload_fragment_window_1_1(data_w[3][512 +: 128]),
  .io_output_o_payload_fragment_window_1_2(data_w[3][640 +: 128]),
  .io_output_o_payload_fragment_window_2_0(data_w[3][768 +: 128]),
  .io_output_o_payload_fragment_window_2_1(data_w[3][896 +: 128]),
  .io_output_o_payload_fragment_window_2_2(data_w[3][1024 +: 128]),
  .io_output_o_payload_fragment_group(),
  .io_output_o_payload_fragment_group_last(),
  .clk(clk_i),
  .resetn(rst_n_i)
 );
 LineBuffer_5x5 u_core_4 (
  .io_cfg_i_valid(cfg_valid_i && op_i == 8'd4),
  .io_cfg_i_ready(cfg_ready_w[4]),
  .io_cfg_i_payload_width(width_i),
  .io_cfg_i_payload_height(height_i),
  .io_cfg_i_payload_groups(groups_i),
  .io_busy_o(),
  .io_done_o(done_w[4]),
  .io_input_i_valid(in_valid_i && op_i == 8'd4),
  .io_input_i_ready(in_ready_w[4]),
  .io_input_i_payload(in_data_i[127:0]),
  .io_output_o_valid(valid_w[4]),
  .io_output_o_ready(out_ready_i && op_i == 8'd4),
  .io_output_o_payload_last(last_w[4]),
  .io_output_o_payload_fragment_window_0_0(data_w[4][0 +: 128]),
  .io_output_o_payload_fragment_window_0_1(data_w[4][128 +: 128]),
  .io_output_o_payload_fragment_window_0_2(data_w[4][256 +: 128]),
  .io_output_o_payload_fragment_window_0_3(data_w[4][384 +: 128]),
  .io_output_o_payload_fragment_window_0_4(data_w[4][512 +: 128]),
  .io_output_o_payload_fragment_window_1_0(data_w[4][640 +: 128]),
  .io_output_o_payload_fragment_window_1_1(data_w[4][768 +: 128]),
  .io_output_o_payload_fragment_window_1_2(data_w[4][896 +: 128]),
  .io_output_o_payload_fragment_window_1_3(data_w[4][1024 +: 128]),
  .io_output_o_payload_fragment_window_1_4(data_w[4][1152 +: 128]),
  .io_output_o_payload_fragment_window_2_0(data_w[4][1280 +: 128]),
  .io_output_o_payload_fragment_window_2_1(data_w[4][1408 +: 128]),
  .io_output_o_payload_fragment_window_2_2(data_w[4][1536 +: 128]),
  .io_output_o_payload_fragment_window_2_3(data_w[4][1664 +: 128]),
  .io_output_o_payload_fragment_window_2_4(data_w[4][1792 +: 128]),
  .io_output_o_payload_fragment_window_3_0(data_w[4][1920 +: 128]),
  .io_output_o_payload_fragment_window_3_1(data_w[4][2048 +: 128]),
  .io_output_o_payload_fragment_window_3_2(data_w[4][2176 +: 128]),
  .io_output_o_payload_fragment_window_3_3(data_w[4][2304 +: 128]),
  .io_output_o_payload_fragment_window_3_4(data_w[4][2432 +: 128]),
  .io_output_o_payload_fragment_window_4_0(data_w[4][2560 +: 128]),
  .io_output_o_payload_fragment_window_4_1(data_w[4][2688 +: 128]),
  .io_output_o_payload_fragment_window_4_2(data_w[4][2816 +: 128]),
  .io_output_o_payload_fragment_window_4_3(data_w[4][2944 +: 128]),
  .io_output_o_payload_fragment_window_4_4(data_w[4][3072 +: 128]),
  .io_output_o_payload_fragment_group(),
  .io_output_o_payload_fragment_group_last(),
  .clk(clk_i),
  .resetn(rst_n_i)
 );
 concat u_concat (
 .clk_i(clk_i), .rst_n_i(rst_n_i), .cfg_valid_i(cfg_valid_i && op_i == 8'd5),
 .cfg_ready_o(cfg_ready_w[5]), .busy_o(), .done_o(done_w[5]),
 .cfg_base1_i(32'd0), .cfg_base2_i(32'd0),
 .cfg_words1_i({13'd0,pixels_i} * {26'd0,groups_i}), .cfg_words2_i(words_b_i),
 .rd_valid_o(concat_rd_valid_w), .rd_ready_i(rd_ready_i && op_i == 8'd5),
 .rd_source_o(concat_source_w), .rd_addr_o(concat_addr_w),
 .rsp_valid_i(rsp_valid_i && op_i == 8'd5), .rsp_ready_o(concat_rsp_ready_w),
 .rsp_data_i(rsp_data_i), .valid_o(valid_w[5]), .ready_i(out_ready_i && op_i == 8'd5),
 .last_o(last_w[5]), .data_o(data_w[5][127:0])
 );
 assign data_w[5][3199:128] = 3072'd0; assign in_ready_w[5] = 1'b0;
 ElementAdd_p16 u_add (
  .io_cfg_i_valid(cfg_valid_i && op_i == 8'd6),
  .io_cfg_i_ready(cfg_ready_w[6]),
  .io_cfg_i_payload_words(pixels_i),
  .io_cfg_i_payload_group(add_group_i),
  .io_cfg_i_payload_last_group(add_last_i),
  .io_cfg_i_payload_multiplier_a_0(add_params_i[0 +: 22]),
  .io_cfg_i_payload_multiplier_a_1(add_params_i[128 +: 22]),
  .io_cfg_i_payload_multiplier_a_2(add_params_i[256 +: 22]),
  .io_cfg_i_payload_multiplier_a_3(add_params_i[384 +: 22]),
  .io_cfg_i_payload_multiplier_a_4(add_params_i[512 +: 22]),
  .io_cfg_i_payload_multiplier_a_5(add_params_i[640 +: 22]),
  .io_cfg_i_payload_multiplier_a_6(add_params_i[768 +: 22]),
  .io_cfg_i_payload_multiplier_a_7(add_params_i[896 +: 22]),
  .io_cfg_i_payload_multiplier_a_8(add_params_i[1024 +: 22]),
  .io_cfg_i_payload_multiplier_a_9(add_params_i[1152 +: 22]),
  .io_cfg_i_payload_multiplier_a_10(add_params_i[1280 +: 22]),
  .io_cfg_i_payload_multiplier_a_11(add_params_i[1408 +: 22]),
  .io_cfg_i_payload_multiplier_a_12(add_params_i[1536 +: 22]),
  .io_cfg_i_payload_multiplier_a_13(add_params_i[1664 +: 22]),
  .io_cfg_i_payload_multiplier_a_14(add_params_i[1792 +: 22]),
  .io_cfg_i_payload_multiplier_a_15(add_params_i[1920 +: 22]),
  .io_cfg_i_payload_multiplier_b_0(add_params_i[32 +: 22]),
  .io_cfg_i_payload_multiplier_b_1(add_params_i[160 +: 22]),
  .io_cfg_i_payload_multiplier_b_2(add_params_i[288 +: 22]),
  .io_cfg_i_payload_multiplier_b_3(add_params_i[416 +: 22]),
  .io_cfg_i_payload_multiplier_b_4(add_params_i[544 +: 22]),
  .io_cfg_i_payload_multiplier_b_5(add_params_i[672 +: 22]),
  .io_cfg_i_payload_multiplier_b_6(add_params_i[800 +: 22]),
  .io_cfg_i_payload_multiplier_b_7(add_params_i[928 +: 22]),
  .io_cfg_i_payload_multiplier_b_8(add_params_i[1056 +: 22]),
  .io_cfg_i_payload_multiplier_b_9(add_params_i[1184 +: 22]),
  .io_cfg_i_payload_multiplier_b_10(add_params_i[1312 +: 22]),
  .io_cfg_i_payload_multiplier_b_11(add_params_i[1440 +: 22]),
  .io_cfg_i_payload_multiplier_b_12(add_params_i[1568 +: 22]),
  .io_cfg_i_payload_multiplier_b_13(add_params_i[1696 +: 22]),
  .io_cfg_i_payload_multiplier_b_14(add_params_i[1824 +: 22]),
  .io_cfg_i_payload_multiplier_b_15(add_params_i[1952 +: 22]),
  .io_cfg_i_payload_bias_fixed_0(add_params_i[64 +: 64]),
  .io_cfg_i_payload_bias_fixed_1(add_params_i[192 +: 64]),
  .io_cfg_i_payload_bias_fixed_2(add_params_i[320 +: 64]),
  .io_cfg_i_payload_bias_fixed_3(add_params_i[448 +: 64]),
  .io_cfg_i_payload_bias_fixed_4(add_params_i[576 +: 64]),
  .io_cfg_i_payload_bias_fixed_5(add_params_i[704 +: 64]),
  .io_cfg_i_payload_bias_fixed_6(add_params_i[832 +: 64]),
  .io_cfg_i_payload_bias_fixed_7(add_params_i[960 +: 64]),
  .io_cfg_i_payload_bias_fixed_8(add_params_i[1088 +: 64]),
  .io_cfg_i_payload_bias_fixed_9(add_params_i[1216 +: 64]),
  .io_cfg_i_payload_bias_fixed_10(add_params_i[1344 +: 64]),
  .io_cfg_i_payload_bias_fixed_11(add_params_i[1472 +: 64]),
  .io_cfg_i_payload_bias_fixed_12(add_params_i[1600 +: 64]),
  .io_cfg_i_payload_bias_fixed_13(add_params_i[1728 +: 64]),
  .io_cfg_i_payload_bias_fixed_14(add_params_i[1856 +: 64]),
  .io_cfg_i_payload_bias_fixed_15(add_params_i[1984 +: 64]),
  .io_cfg_i_payload_shift(shift_i),
  .io_cfg_i_payload_clamp_min(clamp_min_i),
  .io_cfg_i_payload_clamp_max(clamp_max_i),
  .io_busy_o(),
  .io_done_o(done_w[6]),
  .io_a_i_valid(in_valid_i && op_i == 8'd6),
  .io_a_i_ready(in_ready_w[6]),
  .io_a_i_payload(in_data_i),
  .io_b_i_valid(in_b_valid_i && op_i == 8'd6),
  .io_b_i_ready(in_b_ready_o),
  .io_b_i_payload(in_b_data_i),
  .io_output_o_valid(valid_w[6]),
  .io_output_o_ready(out_ready_i && op_i == 8'd6),
  .io_output_o_payload_last(last_w[6]),
  .io_output_o_payload_fragment_data(data_w[6][127:0]),
  .io_output_o_payload_fragment_group(),
  .io_output_o_payload_fragment_group_last(),
  .clk(clk_i),
  .resetn(rst_n_i)
 );
 assign data_w[6][3199:128] = 3072'd0;
 channel_shuffle #(.C(16)) u_shuffle (.data_i(in_data_i[127:0]), .data_o(data_w[7][127:0]));
 assign data_w[7][3199:128] = 3072'd0;
 assign cfg_ready_w[7] = 1'b1;
 assign in_ready_w[7] = out_ready_i;
 assign valid_w[7] = in_valid_i && op_i == 8'd7;
 assign last_w[7] = 1'b0; assign done_w[7] = 1'b0;
 always_comb begin
  cfg_ready_o = 1'b0; in_ready_o = 1'b0; out_valid_o = 1'b0;
  out_data_o = 3200'd0; out_last_o = 1'b0; done_o = 1'b0;
  if (op_i >= 8'd1 && op_i <= 8'd7) begin
   cfg_ready_o = cfg_ready_w[op_i]; in_ready_o = in_ready_w[op_i];
   out_valid_o = valid_w[op_i]; out_data_o = data_w[op_i];
   out_last_o = last_w[op_i]; done_o = done_w[op_i];
  end
  rd_valid_o = 1'b0; rd_addr_o = 32'd0; rd_source_o = 1'b0; rsp_ready_o = 1'b0;
  case (op_i)
   8'd1: begin rd_valid_o = pw_rd_valid_w; rd_addr_o = pw_addr_w; rsp_ready_o = pw_rsp_ready_w; end
   8'd5: begin rd_valid_o = concat_rd_valid_w; rd_addr_o = concat_addr_w;
    rd_source_o = concat_source_w; rsp_ready_o = concat_rsp_ready_w; end
   default: ;
  endcase
  out_mac_o = pw_mac_w; out_pixel_o = pw_pixel_w;
  out_group_o = pw_group_w; out_mask_o = pw_mask_w;
 end
endmodule
