`timescale 1ns/1ps
// 【文件类型：.sv】已验收算子统一接线；生成 RTL 保持原样，配置与握手由调度器管理。
module op_core_bank_batch2_before (
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
    input logic rsp_source_i, // opcode12 DDR返回属于skip分支
    output logic rsp_ready_o, // 握手接收许可
    output logic out_valid_o, // 握手有效，阻塞期间保持载荷
    input logic out_ready_i, // 握手接收许可
    output logic out_last_o, // 任务配置或协议控制字段
    output logic done_o, // 完成通知，须遵守排空条件
    input logic [7:0] op_i, // 任务配置或协议控制字段
    input logic [9:0] cin_i, // PW 输入通道数，1..768
    input logic [9:0] cin_b_i, // opcode12第二支PW输入通道数
    input logic [9:0] cout_i, // PW 输出通道数，1..512
    input logic [18:0] pixels_i, // 任务配置或协议控制字段
    input logic [18:0] tile_base_i, // opcode12当前16像素tile首像素
    input logic [4:0] tile_words_i, // opcode12当前tile像素数，1..16
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
 logic [12:1] cfg_ready_w, in_ready_w, valid_w, last_w, done_w;
 logic [3199:0] data_w [1:12];
 logic pw_rd_valid_w, pw_rsp_ready_w, concat_rd_valid_w, concat_rsp_ready_w, concat_source_w;
 logic [31:0] pw_addr_w, concat_addr_w;
 logic [18:0] pw_pixel_w; logic [6:0] pw_group_w; logic [3:0] pw_mask_w;
 logic [127:0] pw_mac_w;
 logic [63:0] pw_q_w;
 logic pw_weights_ready_w, pw_params_ready_w, pw_start_ready_w, pw_cfg_ready_w;
 logic p12_pw_cfg_ready_w, p12_pw_weights_ready_w, p12_pw_params_ready_w, p12_pw_start_ready_w;
 logic p12_pw_rd_valid_w, p12_pw_rsp_ready_w;
 logic [31:0] p12_pw_addr_w, p12_weight_a_beats_w, p12_weight_b_beats_w, p12_weight_count_r;
 logic [127:0] p12_pw_mac_w, p12_pw_skip_mac_w;
 logic [18:0] p12_pw_pixel_w, p12_pw_skip_pixel_w;
 logic [6:0] p12_pw_group_w, p12_pw_skip_group_w;
 logic [3:0] p12_pw_mask_w, p12_pw_skip_mask_w;
 logic p12_pw_valid_w, p12_pw_skip_valid_w, p12_pw_last_w, p12_pw_skip_last_w;
 logic p12_pw_configured_r, p12_pw_started_r;
 logic p12_pw_cfg_fire_w, p12_add_cfg_w;
 logic p12_project_tile_last_w, p12_skip_tile_last_w, p12_add_inputs_done_r;
 logic p12_project_fire_w, p12_skip_fire_w, p12_add_input_fire_w;
 logic p12_add_valid_r;
 logic [1:0] p12_phase_r, p12_add_part_r;
 logic [4:0] p12_add_pixel_r, p12_add_output_pixel_idx_r;
 logic [10:0] p12_project_addr_w, p12_skip_addr_w, p12_read_addr_w;
 logic p12_read_en_w;
 logic [127:0] p12_project_data_w, p12_skip_data_w;
 logic [383:0] p12_add_a_low_r, p12_add_b_low_r;
 logic [511:0] p12_add_a_data_w, p12_add_b_data_w;
 logic [18:0] p12_add_output_pixel_w;
 logic [6:0] p12_add_output_group_w;
 logic dw3_weights_ready_w, dw5_weights_ready_w;
 logic dw3_cfg_ready_w, dw5_cfg_ready_w, lb3_ready_w, lb5_ready_w;
 logic [5:0] lb3_group_w, lb5_group_w;
 logic lb3_group_last_w, lb5_group_last_w;
 logic fused_window_ready_w, fused_dw3_align_valid_r, fused_dw3_align_ready_w;
 logic fused_configured_r, fused_core_cfg_w, fused_add_cfg_w;
 logic [1151:0] fused_window3_w;
 logic [511:0] fused_dw3_align_data_r;
 logic fused_add_a_ready_w, fused_add_b_ready_w;
 logic fused_weight_dw3_w;
 logic [31:0] fused_weight_count_r;
 logic [31:0] fused_dw3_weight_beats_w;
 assign p12_weight_a_beats_w = (({22'd0,cout_i} + 32'd3) >> 2) *
                               (({22'd0,cin_i} + 32'd15) >> 4);
 assign p12_weight_b_beats_w = (({22'd0,cout_i} + 32'd3) >> 2) *
                               (({22'd0,cin_b_i} + 32'd15) >> 4);
 assign weights_ready_o = op_i == 8'd8 ? dw3_weights_ready_w :
                          op_i == 8'd9 ? dw5_weights_ready_w :
                          op_i == 8'd11 ? (fused_weight_dw3_w ? dw3_weights_ready_w : dw5_weights_ready_w) :
                           op_i == 8'd12 ?
                             (p12_weight_count_r < p12_weight_a_beats_w ? pw_weights_ready_w :
                              (p12_weight_count_r < p12_weight_a_beats_w + p12_weight_b_beats_w ?
                               p12_pw_weights_ready_w : 1'b0)) : pw_weights_ready_w;
 assign params_ready_o = op_i == 8'd12 ? (pw_params_ready_w && p12_pw_params_ready_w) : pw_params_ready_w;
 assign start_ready_o = op_i == 8'd12 ? (pw_start_ready_w && p12_pw_start_ready_w) : pw_start_ready_w;
 assign cfg_ready_w[8] = cfg_ready_w[3] && dw3_cfg_ready_w;
 assign cfg_ready_w[9] = cfg_ready_w[4] && dw5_cfg_ready_w;
 // 首次只配置窗口和 DW；权重、参数到齐后及每组结束后只配置 Add。
 assign cfg_ready_w[11] = fused_configured_r ? cfg_ready_w[6] :
                          (cfg_ready_w[4] && dw3_cfg_ready_w && dw5_cfg_ready_w);
 assign cfg_ready_w[12] = p12_pw_configured_r ? cfg_ready_w[6] :
                           (pw_cfg_ready_w && p12_pw_cfg_ready_w);
 assign fused_core_cfg_w = cfg_valid_i && op_i == 8'd11 && !fused_configured_r && cfg_ready_w[11];
 assign fused_add_cfg_w = cfg_valid_i && op_i == 8'd11 && fused_configured_r && cfg_ready_w[11];
 assign p12_pw_cfg_fire_w = cfg_valid_i && op_i == 8'd12 && !p12_pw_configured_r && cfg_ready_w[12];
 assign p12_add_cfg_w = cfg_valid_i && op_i == 8'd12 && p12_pw_configured_r && cfg_ready_w[12];
 assign in_ready_w[8] = in_ready_w[3];
 assign in_ready_w[9] = in_ready_w[4];
 assign in_ready_w[11] = in_ready_w[4];
 assign in_ready_w[12] = 1'b0;
 assign data_w[8][3199:512] = 2688'd0;
 assign data_w[9][3199:512] = 2688'd0;
 assign data_w[11][3199:128] = 3072'd0;
 assign data_w[12][3199:128] = 3072'd0;
 assign valid_w[11] = valid_w[6];
 assign last_w[11] = last_w[6];
 assign done_w[11] = done_w[6];
 assign data_w[11][127:0] = data_w[6][127:0];
 assign data_w[12][127:0] = data_w[6][127:0];
 assign valid_w[12] = valid_w[6];
 assign last_w[12] = last_w[6];
 assign done_w[12] = done_w[6];
 assign p12_project_addr_w = {p12_pw_group_w,4'd0} + {7'd0,p12_pw_pixel_w[3:0]};
 assign p12_skip_addr_w = {p12_pw_skip_group_w,4'd0} + {7'd0,p12_pw_skip_pixel_w[3:0]};
 assign p12_read_addr_w = {add_group_i[4:0],p12_add_part_r,4'd0} + {7'd0,p12_add_pixel_r[3:0]};
 // 官方 URAM 一拍读；最后一段由停读后的 doutb 保持，沿用四拍拼接节奏。
 assign p12_read_en_w = p12_phase_r == 2'd2 && !p12_add_valid_r && !p12_add_inputs_done_r;
 assign p12_add_a_data_w = {p12_project_data_w,p12_add_a_low_r};
 assign p12_add_b_data_w = {p12_skip_data_w,p12_add_b_low_r};
 p12_tile_uram u_p12_project_mem (
  .clka(clk_i), .ena(p12_project_fire_w), .wea(p12_project_fire_w),
  .addra(p12_project_addr_w), .dina(p12_pw_mac_w),
  .clkb(clk_i), .enb(p12_read_en_w), .addrb(p12_read_addr_w), .doutb(p12_project_data_w)
 );
 p12_tile_uram u_p12_skip_mem (
  .clka(clk_i), .ena(p12_skip_fire_w), .wea(p12_skip_fire_w),
  .addra(p12_skip_addr_w), .dina(p12_pw_skip_mac_w),
  .clkb(clk_i), .enb(p12_read_en_w), .addrb(p12_read_addr_w), .doutb(p12_skip_data_w)
 );
 assign p12_add_input_fire_w = p12_add_valid_r && in_ready_w[6] && in_b_ready_o;
 assign p12_add_output_pixel_w = tile_base_i + {14'd0,p12_add_output_pixel_idx_r};
 assign p12_add_output_group_w = {1'b0,add_group_i};
 assign p12_project_fire_w = op_i == 8'd12 && p12_phase_r == 2'd0 && p12_pw_valid_w;
 assign p12_skip_fire_w = op_i == 8'd12 && p12_phase_r == 2'd1 && p12_pw_skip_valid_w;
 assign p12_project_tile_last_w = p12_project_fire_w &&
      p12_pw_group_w == ((({6'd0,cout_i} + 16'd3) >> 2) - 16'd1) &&
     p12_pw_pixel_w + 19'd1 == tile_base_i + {14'd0,tile_words_i};
 assign p12_skip_tile_last_w = p12_skip_fire_w &&
      p12_pw_skip_group_w == ((({6'd0,cout_i} + 16'd3) >> 2) - 16'd1) &&
     p12_pw_skip_pixel_w + 19'd1 == tile_base_i + {14'd0,tile_words_i};
 assign fused_dw3_weight_beats_w = {26'd0,groups_i} * 32'd9;
 assign fused_weight_dw3_w = fused_weight_count_r < fused_dw3_weight_beats_w;
 // 同一 5x5 窗口的中心 3x3；每路各消费一次，允许两路独立反压。
 assign fused_window_ready_w = lb3_ready_w && lb5_ready_w;
 for (genvar y=0; y<3; y=y+1) begin : g_fused_row
   for (genvar x=0; x<3; x=x+1) begin : g_fused_col
     assign fused_window3_w[(y*3+x)*128 +: 128] = data_w[4][((y+1)*5+x+1)*128 +: 128];
   end
 end
 // 控制状态异步复位；数据寄存器由有效位保护，不加入复位网络。
 always_ff @(posedge clk_i or negedge rst_n_i) begin
   if (!rst_n_i) begin
     fused_configured_r <= 1'b0;
   end else if (op_i != 8'd11) begin
     fused_configured_r <= 1'b0;
   end else begin
     if (fused_core_cfg_w) fused_configured_r <= 1'b1;
   end
 end
 assign fused_dw3_align_ready_w = !fused_dw3_align_valid_r || fused_add_a_ready_w;
 PwMac u_pw (
  .io_cfg_i_valid(cfg_valid_i && (op_i == 8'd1 || (op_i == 8'd12 && !p12_pw_configured_r))),
  .io_cfg_i_ready(pw_cfg_ready_w),
  .io_cfg_i_payload_cin(cin_i),
  .io_cfg_i_payload_cout(cout_i),
  .io_cfg_i_payload_pixels(pixels_i),
  .io_cfg_i_payload_shift(shift_i),
  .io_cfg_i_payload_raw(op_i == 8'd12 ? 1'b1 : raw_i),
  .io_cfg_i_payload_int16(op_i == 8'd12 ? 1'b0 : int16_i),
  .io_weights_i_valid(weights_valid_i && (op_i == 8'd1 ||
                         (op_i == 8'd12 && p12_weight_count_r < p12_weight_a_beats_w))),
  .io_weights_i_ready(pw_weights_ready_w),
  .io_weights_i_payload(load_data_i),
  .io_params_i_valid(params_valid_i && (op_i == 8'd1 || op_i == 8'd12)),
  .io_params_i_ready(pw_params_ready_w),
  .io_params_i_payload(op_i == 8'd12 ? 512'd0 : load_data_i),
  .io_start_i_valid(start_valid_i && (op_i == 8'd1 || op_i == 8'd12)),
  .io_start_i_ready(pw_start_ready_w),
  .io_start_i_payload(1'b1),
  .io_busy_o(),
  .io_done_o(done_w[1]),
  .io_rd_o_valid(pw_rd_valid_w),
  .io_rd_o_ready((rd_ready_i && op_i == 8'd1) ||
                 (rd_ready_i && op_i == 8'd12 && p12_phase_r == 2'd0)),
  .io_rd_o_payload(pw_addr_w),
  .io_rsp_i_valid(rsp_valid_i && (op_i == 8'd1 || (op_i == 8'd12 && !rsp_source_i))),
  .io_rsp_i_ready(pw_rsp_ready_w),
  .io_rsp_i_payload(rsp_data_i),
  .io_output_o_valid(valid_w[1]),
  .io_output_o_ready((out_ready_i && op_i == 8'd1) || (op_i == 8'd12 && p12_phase_r == 2'd0)),
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
 assign cfg_ready_w[1] = pw_cfg_ready_w;
 assign data_w[1] = {3136'd0,pw_q_w}; assign in_ready_w[1] = 1'b0;
 PwMac u_pw_skip (
  .io_cfg_i_valid(cfg_valid_i && op_i == 8'd12 && !p12_pw_configured_r),
  .io_cfg_i_ready(p12_pw_cfg_ready_w),
  .io_cfg_i_payload_cin(cin_b_i),
  .io_cfg_i_payload_cout(cout_i),
  .io_cfg_i_payload_pixels(pixels_i),
  .io_cfg_i_payload_shift(shift_i),
  .io_cfg_i_payload_raw(1'b1),
  .io_cfg_i_payload_int16(1'b0),
   .io_weights_i_valid(weights_valid_i && op_i == 8'd12 &&
                       p12_weight_count_r >= p12_weight_a_beats_w &&
                       p12_weight_count_r < p12_weight_a_beats_w + p12_weight_b_beats_w),
  .io_weights_i_ready(p12_pw_weights_ready_w),
  .io_weights_i_payload(load_data_i),
  .io_params_i_valid(params_valid_i && op_i == 8'd12),
  .io_params_i_ready(p12_pw_params_ready_w),
  .io_params_i_payload(512'd0),
  .io_start_i_valid(start_valid_i && op_i == 8'd12),
  .io_start_i_ready(p12_pw_start_ready_w),
  .io_start_i_payload(1'b1),
  .io_busy_o(), .io_done_o(),
  .io_rd_o_valid(p12_pw_rd_valid_w),
  .io_rd_o_ready(rd_ready_i && op_i == 8'd12 && p12_phase_r == 2'd1),
  .io_rd_o_payload(p12_pw_addr_w),
  .io_rsp_i_valid(rsp_valid_i && op_i == 8'd12 && rsp_source_i),
  .io_rsp_i_ready(p12_pw_rsp_ready_w),
  .io_rsp_i_payload(rsp_data_i),
  .io_output_o_valid(p12_pw_skip_valid_w),
  .io_output_o_ready(op_i == 8'd12 && p12_phase_r == 2'd1),
  .io_output_o_payload_pixel(p12_pw_skip_pixel_w),
  .io_output_o_payload_group(p12_pw_skip_group_w),
  .io_output_o_payload_mask(p12_pw_skip_mask_w),
  .io_output_o_payload_last(p12_pw_skip_last_w),
  .io_output_o_payload_raw(), .io_output_o_payload_int16(),
  .io_output_o_payload_mac_0(p12_pw_skip_mac_w[0 +: 32]),
  .io_output_o_payload_mac_1(p12_pw_skip_mac_w[32 +: 32]),
  .io_output_o_payload_mac_2(p12_pw_skip_mac_w[64 +: 32]),
  .io_output_o_payload_mac_3(p12_pw_skip_mac_w[96 +: 32]),
  .io_output_o_payload_q_0(), .io_output_o_payload_q_1(),
  .io_output_o_payload_q_2(), .io_output_o_payload_q_3(),
  .clk(clk_i), .resetn(rst_n_i)
 );
 assign p12_pw_mac_w = pw_mac_w;
 assign p12_pw_pixel_w = pw_pixel_w;
 assign p12_pw_group_w = pw_group_w;
 assign p12_pw_mask_w = pw_mask_w;
 assign p12_pw_valid_w = valid_w[1];
 assign p12_pw_last_w = last_w[1];
 always_ff @(posedge clk_i or negedge rst_n_i) begin
   if (!rst_n_i) begin
     p12_pw_configured_r <= 1'b0;
     p12_pw_started_r <= 1'b0;
     p12_weight_count_r <= 32'd0;
     p12_phase_r <= 2'd0;
     p12_add_part_r <= 2'd0;
     p12_add_pixel_r <= 5'd0;
     p12_add_output_pixel_idx_r <= 5'd0;
     p12_add_valid_r <= 1'b0;
     p12_add_inputs_done_r <= 1'b0;
   end else if (op_i != 8'd12) begin
     p12_pw_configured_r <= 1'b0;
     p12_pw_started_r <= 1'b0;
     p12_weight_count_r <= 32'd0;
     p12_phase_r <= 2'd0;
     p12_add_part_r <= 2'd0;
     p12_add_pixel_r <= 5'd0;
     p12_add_output_pixel_idx_r <= 5'd0;
     p12_add_valid_r <= 1'b0;
     p12_add_inputs_done_r <= 1'b0;
   end else begin
     if (p12_pw_cfg_fire_w) begin
       p12_pw_configured_r <= 1'b1;
       p12_weight_count_r <= 32'd0;
     end
     if (weights_valid_i && weights_ready_o) p12_weight_count_r <= p12_weight_count_r + 32'd1;
     if (start_valid_i && start_ready_o) begin
       p12_pw_started_r <= 1'b1;
       p12_phase_r <= 2'd0;
     end
     if (p12_project_tile_last_w) p12_phase_r <= 2'd1;
     if (p12_skip_tile_last_w) p12_phase_r <= 2'd2;
     if (p12_add_cfg_w) begin
       p12_add_part_r <= 2'd0;
       p12_add_pixel_r <= 5'd0;
       p12_add_output_pixel_idx_r <= 5'd0;
       p12_add_valid_r <= 1'b0;
       p12_add_inputs_done_r <= 1'b0;
     end
     if (p12_phase_r == 2'd2 && !p12_add_valid_r && !p12_add_inputs_done_r) begin
       if (p12_add_part_r == 2'd3) begin
         p12_add_part_r <= 2'd0;
         p12_add_valid_r <= 1'b1;
       end else p12_add_part_r <= p12_add_part_r + 2'd1;
     end
     if (p12_add_input_fire_w) begin
       p12_add_valid_r <= 1'b0;
       if (p12_add_pixel_r + 5'd1 == tile_words_i) p12_add_inputs_done_r <= 1'b1;
       else p12_add_pixel_r <= p12_add_pixel_r + 5'd1;
     end
     if (valid_w[6] && out_ready_i && op_i == 8'd12)
       p12_add_output_pixel_idx_r <= p12_add_output_pixel_idx_r + 5'd1;
     if (done_w[6] && add_last_i && p12_phase_r == 2'd2 &&
         tile_base_i + {14'd0,tile_words_i} < pixels_i)
       p12_phase_r <= 2'd0;
   end
 end
 always_ff @(posedge clk_i) begin
   // 当前发出第 1/2/3 段读请求时，锁存上一拍返回的第 0/1/2 段。
   // 第 3 段在 valid 拉高后保持在 URAM 输出，反压期间读口关闭。
   if (p12_read_en_w) begin
    case (p12_add_part_r)
     2'd1: begin p12_add_a_low_r[127:0] <= p12_project_data_w; p12_add_b_low_r[127:0] <= p12_skip_data_w; end
     2'd2: begin p12_add_a_low_r[255:128] <= p12_project_data_w; p12_add_b_low_r[255:128] <= p12_skip_data_w; end
     2'd3: begin p12_add_a_low_r[383:256] <= p12_project_data_w; p12_add_b_low_r[383:256] <= p12_skip_data_w; end
     default: ;
    endcase
   end
 end
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
 // 已验证的Spinal核心；输出已按[group][row][col]排序，沿用引擎16B递增写址。
 assign data_w[10][3199:128] = 3072'd0;
 Upsample u_upsample (
  .clk(clk_i), .resetn(rst_n_i),
  .io_cfg_i_valid(cfg_valid_i && op_i == 8'd10),
  .io_cfg_i_ready(cfg_ready_w[10]),
  .io_cfg_i_payload_width(width_i[8:0]),
  .io_cfg_i_payload_height(height_i[8:0]),
  .io_cfg_i_payload_groups(groups_i),
  .io_busy_o(), .io_done_o(done_w[10]),
  .io_input_i_valid(in_valid_i && op_i == 8'd10),
  .io_input_i_ready(in_ready_w[10]), .io_input_i_payload(in_data_i[127:0]),
  .io_output_o_valid(valid_w[10]), .io_output_o_ready(out_ready_i && op_i == 8'd10),
  .io_output_o_payload_last(last_w[10]),
  .io_output_o_payload_fragment_data(data_w[10][127:0]),
  .io_output_o_payload_fragment_group(), .io_output_o_payload_fragment_row(),
  .io_output_o_payload_fragment_col(), .io_output_o_payload_fragment_group_last()
 );
 assign data_w[3][3199:1152] = 2048'd0;
 LineBuffer_3x3 u_core_3 (
   .io_cfg_i_valid(cfg_valid_i && (op_i == 8'd3 || (op_i == 8'd8 && cfg_ready_w[8]))),
  .io_cfg_i_ready(cfg_ready_w[3]),
  .io_cfg_i_payload_width(width_i),
  .io_cfg_i_payload_height(height_i),
  .io_cfg_i_payload_groups(groups_i),
  .io_busy_o(),
  .io_done_o(done_w[3]),
   .io_input_i_valid(in_valid_i && (op_i == 8'd3 || op_i == 8'd8)),
  .io_input_i_ready(in_ready_w[3]),
  .io_input_i_payload(in_data_i[127:0]),
  .io_output_o_valid(valid_w[3]),
   .io_output_o_ready((out_ready_i && op_i == 8'd3) ||
                      (lb3_ready_w && op_i == 8'd8)),
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
  .io_output_o_payload_fragment_group(lb3_group_w),
  .io_output_o_payload_fragment_group_last(lb3_group_last_w),
  .clk(clk_i),
  .resetn(rst_n_i)
 );
 LineBuffer_5x5 u_core_4 (
   .io_cfg_i_valid((cfg_valid_i && (op_i == 8'd4 || (op_i == 8'd9 && cfg_ready_w[9]))) || fused_core_cfg_w),
  .io_cfg_i_ready(cfg_ready_w[4]),
  .io_cfg_i_payload_width(width_i),
  .io_cfg_i_payload_height(height_i),
  .io_cfg_i_payload_groups(groups_i),
  .io_busy_o(),
  .io_done_o(done_w[4]),
   .io_input_i_valid(in_valid_i && (op_i == 8'd4 || op_i == 8'd9 || op_i == 8'd11)),
  .io_input_i_ready(in_ready_w[4]),
  .io_input_i_payload(in_data_i[127:0]),
  .io_output_o_valid(valid_w[4]),
   .io_output_o_ready((out_ready_i && op_i == 8'd4) ||
                      (lb5_ready_w && op_i == 8'd9) || (op_i == 8'd11 && fused_window_ready_w)),
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
  .io_output_o_payload_fragment_group(lb5_group_w),
  .io_output_o_payload_fragment_group_last(lb5_group_last_w),
  .clk(clk_i),
  .resetn(rst_n_i)
 );

 op_dw_adapter #(.K(32'd3)) u_dw3 (
  .clk_i(clk_i), .rst_n_i(rst_n_i),
   .cfg_valid_i((cfg_valid_i && op_i == 8'd8) || fused_core_cfg_w),
  .cfg_ready_o(dw3_cfg_ready_w), .groups_i(groups_i), .width_i(width_i),
   .weights_valid_i(weights_valid_i && (op_i == 8'd8 || (op_i == 8'd11 && fused_weight_dw3_w))),
  .weights_ready_o(dw3_weights_ready_w), .weights_i(load_data_i[127:0]),
   .valid_i((valid_w[3] && op_i == 8'd8) || (valid_w[4] && op_i == 8'd11)), .ready_o(lb3_ready_w),
  .window_i(op_i == 8'd11 ? fused_window3_w : data_w[3][1151:0]),
  .group_i(op_i == 8'd11 ? lb5_group_w : lb3_group_w),
  .group_last_i(op_i == 8'd11 ? lb5_group_last_w : lb3_group_last_w),
  .last_i(op_i == 8'd11 ? last_w[4] : last_w[3]),
   .valid_o(valid_w[8]), .ready_i((out_ready_i && op_i == 8'd8) ||
                                   (fused_dw3_align_ready_w && op_i == 8'd11)),
  .mac_o(data_w[8][511:0]), .last_o(last_w[8]), .done_o(done_w[8])
 );

 op_dw_adapter #(.K(32'd5)) u_dw5 (
  .clk_i(clk_i), .rst_n_i(rst_n_i),
   .cfg_valid_i((cfg_valid_i && op_i == 8'd9) || fused_core_cfg_w),
  .cfg_ready_o(dw5_cfg_ready_w), .groups_i(groups_i), .width_i(width_i),
   .weights_valid_i(weights_valid_i && (op_i == 8'd9 || (op_i == 8'd11 && !fused_weight_dw3_w))),
  .weights_ready_o(dw5_weights_ready_w), .weights_i(load_data_i[127:0]),
   .valid_i(valid_w[4] && (op_i == 8'd9 || op_i == 8'd11)), .ready_o(lb5_ready_w),
  .window_i(data_w[4][3199:0]), .group_i(lb5_group_w),
  .group_last_i(lb5_group_last_w), .last_i(last_w[4]),
   .valid_o(valid_w[9]), .ready_i((out_ready_i && op_i == 8'd9) ||
                                   (fused_add_b_ready_w && op_i == 8'd11)),
  .mac_o(data_w[9][511:0]), .last_o(last_w[9]), .done_o(done_w[9])
 );
 // DW3比DW5少一拍；一深度弹性寄存器只对齐数据，不把组合路径拉回LineBuffer。
 always_ff @(posedge clk_i or negedge rst_n_i) begin
   if (!rst_n_i) begin
     fused_dw3_align_valid_r <= 1'b0;
   end else if (op_i != 8'd11) begin
     fused_dw3_align_valid_r <= 1'b0;
   end else if (fused_dw3_align_ready_w) begin
     fused_dw3_align_valid_r <= valid_w[8];
   end
 end
 always_ff @(posedge clk_i) begin
   if (op_i == 8'd11 && fused_dw3_align_ready_w && valid_w[8])
     fused_dw3_align_data_r <= data_w[8][511:0];
 end
 assign fused_add_a_ready_w = in_ready_w[6];
 assign fused_add_b_ready_w = in_b_ready_o;
 always_ff @(posedge clk_i or negedge rst_n_i) begin
   if (!rst_n_i) fused_weight_count_r <= 32'd0;
   else if (op_i != 8'd11) fused_weight_count_r <= 32'd0;
   else if (fused_core_cfg_w) fused_weight_count_r <= 32'd0;
   else if (weights_valid_i && weights_ready_o) fused_weight_count_r <= fused_weight_count_r + 32'd1;
 end
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
  .io_cfg_i_valid((cfg_valid_i && op_i == 8'd6) || fused_add_cfg_w || p12_add_cfg_w),
  .io_cfg_i_ready(cfg_ready_w[6]),
  .io_cfg_i_payload_words(op_i == 8'd12 ? {14'd0,tile_words_i} : pixels_i),
  .io_cfg_i_payload_group(add_group_i),
  .io_cfg_i_payload_last_group(op_i == 8'd12 ?
      (add_last_i && tile_base_i + {14'd0,tile_words_i} >= pixels_i) : add_last_i),
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
  .io_a_i_valid((in_valid_i && op_i == 8'd6) ||
                (fused_dw3_align_valid_r && op_i == 8'd11) || (p12_add_valid_r && op_i == 8'd12)),
  .io_a_i_ready(in_ready_w[6]),
  .io_a_i_payload(op_i == 8'd6 ? in_data_i : op_i == 8'd11 ? fused_dw3_align_data_r : p12_add_a_data_w),
  // ElementAdd 自己根据 A/B 同时有效产生 ready；B valid 不能再反过来依赖 ready。
  // 原来的 valid_w[9] && in_b_ready_o 形成组合自锁，融合任务会永远等不到输出。
  .io_b_i_valid((in_b_valid_i && op_i == 8'd6) ||
                (valid_w[9] && op_i == 8'd11) || (p12_add_valid_r && op_i == 8'd12)),
  .io_b_i_ready(in_b_ready_o),
  .io_b_i_payload(op_i == 8'd6 ? in_b_data_i : op_i == 8'd11 ? data_w[9][511:0] : p12_add_b_data_w),
  .io_output_o_valid(valid_w[6]),
  .io_output_o_ready(out_ready_i && (op_i == 8'd6 || op_i == 8'd11 || op_i == 8'd12)),
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
   if (op_i >= 8'd1 && op_i <= 8'd12) begin
   cfg_ready_o = cfg_ready_w[op_i]; in_ready_o = in_ready_w[op_i];
   out_valid_o = valid_w[op_i]; out_data_o = data_w[op_i];
   out_last_o = last_w[op_i]; done_o = done_w[op_i];
  end
  rd_valid_o = 1'b0; rd_addr_o = 32'd0; rd_source_o = 1'b0; rsp_ready_o = 1'b0;
  case (op_i)
   8'd1: begin rd_valid_o = pw_rd_valid_w; rd_addr_o = pw_addr_w; rsp_ready_o = pw_rsp_ready_w; end
   8'd5: begin rd_valid_o = concat_rd_valid_w; rd_addr_o = concat_addr_w;
    rd_source_o = concat_source_w; rsp_ready_o = concat_rsp_ready_w; end
   8'd12: begin
    rd_source_o = p12_phase_r == 2'd1;
    if (p12_phase_r == 2'd0) begin rd_valid_o = pw_rd_valid_w; rd_addr_o = pw_addr_w; end
    else if (p12_phase_r == 2'd1) begin rd_valid_o = p12_pw_rd_valid_w; rd_addr_o = p12_pw_addr_w; end
    rsp_ready_o = rsp_source_i ? p12_pw_rsp_ready_w : pw_rsp_ready_w;
   end
   default: ;
  endcase
   out_mac_o = pw_mac_w;
   out_pixel_o = op_i == 8'd12 ? p12_add_output_pixel_w : pw_pixel_w;
   out_group_o = op_i == 8'd12 ? p12_add_output_group_w : pw_group_w;
   out_mask_o = op_i == 8'd12 ? 4'hF : pw_mask_w;
 end
endmodule
