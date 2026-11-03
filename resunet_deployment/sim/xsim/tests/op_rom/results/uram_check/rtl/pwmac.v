// Generator : SpinalHDL v1.12.3    git head : 591e64062329e5e2e2b81f4d52422948053edb97
// Component : PwMac
// Git hash  : 61491ca5e30687cffa35f30468de14ff9f05eb4c

`timescale 1ns/1ps

module PwMac (
  input  wire          io_cfg_i_valid,
  output wire          io_cfg_i_ready,
  input  wire [9:0]    io_cfg_i_payload_cin,
  input  wire [9:0]    io_cfg_i_payload_cout,
  input  wire [18:0]   io_cfg_i_payload_pixels,
  input  wire [5:0]    io_cfg_i_payload_shift,
  input  wire          io_cfg_i_payload_raw,
  input  wire          io_cfg_i_payload_int16,
  input  wire          io_weights_i_valid,
  output wire          io_weights_i_ready,
  input  wire [511:0]  io_weights_i_payload,
  input  wire          io_params_i_valid,
  output wire          io_params_i_ready,
  input  wire [511:0]  io_params_i_payload,
  input  wire          io_start_i_valid,
  output wire          io_start_i_ready,
  input  wire          io_start_i_payload,
  output wire          io_busy_o,
  output wire          io_done_o,
  output wire          io_rd_o_valid,
  input  wire          io_rd_o_ready,
  output wire [31:0]   io_rd_o_payload,
  input  wire          io_rsp_i_valid,
  output wire          io_rsp_i_ready,
  input  wire [127:0]  io_rsp_i_payload,
  output wire          io_output_o_valid,
  input  wire          io_output_o_ready,
  output wire [18:0]   io_output_o_payload_pixel,
  output wire [6:0]    io_output_o_payload_group,
  output wire [3:0]    io_output_o_payload_mask,
  output wire          io_output_o_payload_last,
  output wire          io_output_o_payload_raw,
  output wire          io_output_o_payload_int16,
  output wire [31:0]   io_output_o_payload_mac_0,
  output wire [31:0]   io_output_o_payload_mac_1,
  output wire [31:0]   io_output_o_payload_mac_2,
  output wire [31:0]   io_output_o_payload_mac_3,
  output wire [15:0]   io_output_o_payload_q_0,
  output wire [15:0]   io_output_o_payload_q_1,
  output wire [15:0]   io_output_o_payload_q_2,
  output wire [15:0]   io_output_o_payload_q_3,
  input  wire          clk,
  input  wire          resetn
);

  wire       [0:0]    pwWeightUram_wea;
  reg        [127:0]  inputMem_spinal_port1;
  reg        [127:0]  paramMem_0_spinal_port1;
  reg        [127:0]  paramMem_1_spinal_port1;
  reg        [127:0]  paramMem_2_spinal_port1;
  reg        [127:0]  paramMem_3_spinal_port1;
  wire       [511:0]  pwWeightUram_doutb;
  wire                requant_io_input_i_ready;
  wire                requant_io_output_o_valid;
  wire       [18:0]   requant_io_output_o_payload_pixel;
  wire       [6:0]    requant_io_output_o_payload_group;
  wire       [3:0]    requant_io_output_o_payload_mask;
  wire                requant_io_output_o_payload_last;
  wire                requant_io_output_o_payload_raw;
  wire                requant_io_output_o_payload_int16;
  wire       [31:0]   requant_io_output_o_payload_mac_0;
  wire       [31:0]   requant_io_output_o_payload_mac_1;
  wire       [31:0]   requant_io_output_o_payload_mac_2;
  wire       [31:0]   requant_io_output_o_payload_mac_3;
  wire       [15:0]   requant_io_output_o_payload_q_0;
  wire       [15:0]   requant_io_output_o_payload_q_1;
  wire       [15:0]   requant_io_output_o_payload_q_2;
  wire       [15:0]   requant_io_output_o_payload_q_3;
  wire       [9:0]    _zz_cfgIg_w;
  wire       [9:0]    _zz_cfgOg_w;
  wire       [13:0]   _zz_weightTotal_r;
  wire       [4:0]    _zz_tileCount_r_1;
  wire       [24:0]   _zz_io_rd_o_payload;
  wire       [24:0]   _zz_io_rd_o_payload_1;
  wire       [24:0]   _zz_io_rd_o_payload_2;
  wire       [24:0]   _zz_io_rd_o_payload_3;
  wire       [24:0]   _zz_io_rd_o_payload_4;
  wire       [10:0]   _zz_fillAddress_w;
  wire       [10:0]   _zz_fillAddress_w_1;
  wire       [10:0]   _zz_fillAddress_w_2;
  wire       [4:0]    _zz_when_PwMac_l204;
  wire       [5:0]    _zz_when_PwMac_l206;
  wire       [18:0]   _zz_request_payload_tag_pixel;
  wire       [12:0]   _zz_request_payload_tag_mask;
  wire       [12:0]   _zz_request_payload_tag_mask_1;
  wire       [9:0]    _zz_request_payload_tag_mask_2;
  wire       [12:0]   _zz_request_payload_tag_mask_3;
  wire       [12:0]   _zz_request_payload_tag_mask_4;
  wire       [12:0]   _zz_request_payload_tag_mask_5;
  wire       [9:0]    _zz_request_payload_tag_mask_6;
  wire       [12:0]   _zz_request_payload_tag_mask_7;
  wire       [12:0]   _zz_request_payload_tag_mask_8;
  wire       [12:0]   _zz_request_payload_tag_mask_9;
  wire       [9:0]    _zz_request_payload_tag_mask_10;
  wire       [12:0]   _zz_request_payload_tag_mask_11;
  wire       [12:0]   _zz_request_payload_tag_mask_12;
  wire       [12:0]   _zz_request_payload_tag_mask_13;
  wire       [9:0]    _zz_request_payload_tag_mask_14;
  wire       [12:0]   _zz_request_payload_tag_mask_15;
  wire       [5:0]    _zz_request_payload_tag_finalInput;
  wire       [7:0]    _zz_request_payload_tag_tileLast;
  wire       [7:0]    _zz_request_payload_tag_tileLast_1;
  wire       [4:0]    _zz_request_payload_tag_tileLast_2;
  wire       [18:0]   _zz_request_payload_tag_last;
  wire       [18:0]   _zz_request_payload_tag_last_1;
  wire       [10:0]   _zz_inputAddress_w;
  wire       [10:0]   _zz_inputAddress_w_1;
  wire       [10:0]   _zz_inputAddress_w_2;
  wire       [12:0]   _zz_weightAddress_w;
  wire       [12:0]   _zz_weightAddress_w_1;
  wire       [4:0]    _zz_when_PwMac_l252;
  wire       [5:0]    _zz_when_PwMac_l254;
  wire       [7:0]    _zz_when_PwMac_l256;
  wire       [7:0]    _zz_when_PwMac_l256_1;
  wire       [7:0]    _zz_products_w_values_0_0;
  wire       [14:0]   _zz_products_w_values_0_0_1;
  wire       [14:0]   _zz_products_w_values_0_0_2;
  wire       [9:0]    _zz_products_w_values_0_0_3;
  wire       [14:0]   _zz_products_w_values_0_0_4;
  wire       [7:0]    _zz_products_w_values_0_0_5;
  wire       [7:0]    _zz_products_w_values_0_0_6;
  wire       [7:0]    _zz_products_w_values_0_1;
  wire       [14:0]   _zz_products_w_values_0_1_1;
  wire       [14:0]   _zz_products_w_values_0_1_2;
  wire       [9:0]    _zz_products_w_values_0_1_3;
  wire       [14:0]   _zz_products_w_values_0_1_4;
  wire       [7:0]    _zz_products_w_values_0_1_5;
  wire       [7:0]    _zz_products_w_values_0_1_6;
  wire       [7:0]    _zz_products_w_values_0_2;
  wire       [14:0]   _zz_products_w_values_0_2_1;
  wire       [14:0]   _zz_products_w_values_0_2_2;
  wire       [9:0]    _zz_products_w_values_0_2_3;
  wire       [14:0]   _zz_products_w_values_0_2_4;
  wire       [7:0]    _zz_products_w_values_0_2_5;
  wire       [7:0]    _zz_products_w_values_0_2_6;
  wire       [7:0]    _zz_products_w_values_0_3;
  wire       [14:0]   _zz_products_w_values_0_3_1;
  wire       [14:0]   _zz_products_w_values_0_3_2;
  wire       [9:0]    _zz_products_w_values_0_3_3;
  wire       [14:0]   _zz_products_w_values_0_3_4;
  wire       [7:0]    _zz_products_w_values_0_3_5;
  wire       [7:0]    _zz_products_w_values_0_3_6;
  wire       [7:0]    _zz_products_w_values_0_4;
  wire       [14:0]   _zz_products_w_values_0_4_1;
  wire       [14:0]   _zz_products_w_values_0_4_2;
  wire       [9:0]    _zz_products_w_values_0_4_3;
  wire       [14:0]   _zz_products_w_values_0_4_4;
  wire       [7:0]    _zz_products_w_values_0_4_5;
  wire       [7:0]    _zz_products_w_values_0_4_6;
  wire       [7:0]    _zz_products_w_values_0_5;
  wire       [14:0]   _zz_products_w_values_0_5_1;
  wire       [14:0]   _zz_products_w_values_0_5_2;
  wire       [9:0]    _zz_products_w_values_0_5_3;
  wire       [14:0]   _zz_products_w_values_0_5_4;
  wire       [7:0]    _zz_products_w_values_0_5_5;
  wire       [7:0]    _zz_products_w_values_0_5_6;
  wire       [7:0]    _zz_products_w_values_0_6;
  wire       [14:0]   _zz_products_w_values_0_6_1;
  wire       [14:0]   _zz_products_w_values_0_6_2;
  wire       [9:0]    _zz_products_w_values_0_6_3;
  wire       [14:0]   _zz_products_w_values_0_6_4;
  wire       [7:0]    _zz_products_w_values_0_6_5;
  wire       [7:0]    _zz_products_w_values_0_6_6;
  wire       [7:0]    _zz_products_w_values_0_7;
  wire       [14:0]   _zz_products_w_values_0_7_1;
  wire       [14:0]   _zz_products_w_values_0_7_2;
  wire       [9:0]    _zz_products_w_values_0_7_3;
  wire       [14:0]   _zz_products_w_values_0_7_4;
  wire       [7:0]    _zz_products_w_values_0_7_5;
  wire       [7:0]    _zz_products_w_values_0_7_6;
  wire       [7:0]    _zz_products_w_values_0_8;
  wire       [14:0]   _zz_products_w_values_0_8_1;
  wire       [14:0]   _zz_products_w_values_0_8_2;
  wire       [9:0]    _zz_products_w_values_0_8_3;
  wire       [14:0]   _zz_products_w_values_0_8_4;
  wire       [7:0]    _zz_products_w_values_0_8_5;
  wire       [7:0]    _zz_products_w_values_0_8_6;
  wire       [7:0]    _zz_products_w_values_0_9;
  wire       [14:0]   _zz_products_w_values_0_9_1;
  wire       [14:0]   _zz_products_w_values_0_9_2;
  wire       [9:0]    _zz_products_w_values_0_9_3;
  wire       [14:0]   _zz_products_w_values_0_9_4;
  wire       [7:0]    _zz_products_w_values_0_9_5;
  wire       [7:0]    _zz_products_w_values_0_9_6;
  wire       [7:0]    _zz_products_w_values_0_10;
  wire       [14:0]   _zz_products_w_values_0_10_1;
  wire       [14:0]   _zz_products_w_values_0_10_2;
  wire       [9:0]    _zz_products_w_values_0_10_3;
  wire       [14:0]   _zz_products_w_values_0_10_4;
  wire       [7:0]    _zz_products_w_values_0_10_5;
  wire       [7:0]    _zz_products_w_values_0_10_6;
  wire       [7:0]    _zz_products_w_values_0_11;
  wire       [14:0]   _zz_products_w_values_0_11_1;
  wire       [14:0]   _zz_products_w_values_0_11_2;
  wire       [9:0]    _zz_products_w_values_0_11_3;
  wire       [14:0]   _zz_products_w_values_0_11_4;
  wire       [7:0]    _zz_products_w_values_0_11_5;
  wire       [7:0]    _zz_products_w_values_0_11_6;
  wire       [7:0]    _zz_products_w_values_0_12;
  wire       [14:0]   _zz_products_w_values_0_12_1;
  wire       [14:0]   _zz_products_w_values_0_12_2;
  wire       [9:0]    _zz_products_w_values_0_12_3;
  wire       [14:0]   _zz_products_w_values_0_12_4;
  wire       [7:0]    _zz_products_w_values_0_12_5;
  wire       [7:0]    _zz_products_w_values_0_12_6;
  wire       [7:0]    _zz_products_w_values_0_13;
  wire       [14:0]   _zz_products_w_values_0_13_1;
  wire       [14:0]   _zz_products_w_values_0_13_2;
  wire       [9:0]    _zz_products_w_values_0_13_3;
  wire       [14:0]   _zz_products_w_values_0_13_4;
  wire       [7:0]    _zz_products_w_values_0_13_5;
  wire       [7:0]    _zz_products_w_values_0_13_6;
  wire       [7:0]    _zz_products_w_values_0_14;
  wire       [14:0]   _zz_products_w_values_0_14_1;
  wire       [14:0]   _zz_products_w_values_0_14_2;
  wire       [9:0]    _zz_products_w_values_0_14_3;
  wire       [14:0]   _zz_products_w_values_0_14_4;
  wire       [7:0]    _zz_products_w_values_0_14_5;
  wire       [7:0]    _zz_products_w_values_0_14_6;
  wire       [7:0]    _zz_products_w_values_0_15;
  wire       [14:0]   _zz_products_w_values_0_15_1;
  wire       [14:0]   _zz_products_w_values_0_15_2;
  wire       [9:0]    _zz_products_w_values_0_15_3;
  wire       [14:0]   _zz_products_w_values_0_15_4;
  wire       [7:0]    _zz_products_w_values_0_15_5;
  wire       [7:0]    _zz_products_w_values_0_15_6;
  wire       [7:0]    _zz_products_w_values_1_0;
  wire       [14:0]   _zz_products_w_values_1_0_1;
  wire       [14:0]   _zz_products_w_values_1_0_2;
  wire       [9:0]    _zz_products_w_values_1_0_3;
  wire       [14:0]   _zz_products_w_values_1_0_4;
  wire       [7:0]    _zz_products_w_values_1_0_5;
  wire       [7:0]    _zz_products_w_values_1_0_6;
  wire       [7:0]    _zz_products_w_values_1_1;
  wire       [14:0]   _zz_products_w_values_1_1_1;
  wire       [14:0]   _zz_products_w_values_1_1_2;
  wire       [9:0]    _zz_products_w_values_1_1_3;
  wire       [14:0]   _zz_products_w_values_1_1_4;
  wire       [7:0]    _zz_products_w_values_1_1_5;
  wire       [7:0]    _zz_products_w_values_1_1_6;
  wire       [7:0]    _zz_products_w_values_1_2;
  wire       [14:0]   _zz_products_w_values_1_2_1;
  wire       [14:0]   _zz_products_w_values_1_2_2;
  wire       [9:0]    _zz_products_w_values_1_2_3;
  wire       [14:0]   _zz_products_w_values_1_2_4;
  wire       [7:0]    _zz_products_w_values_1_2_5;
  wire       [7:0]    _zz_products_w_values_1_2_6;
  wire       [7:0]    _zz_products_w_values_1_3;
  wire       [14:0]   _zz_products_w_values_1_3_1;
  wire       [14:0]   _zz_products_w_values_1_3_2;
  wire       [9:0]    _zz_products_w_values_1_3_3;
  wire       [14:0]   _zz_products_w_values_1_3_4;
  wire       [7:0]    _zz_products_w_values_1_3_5;
  wire       [7:0]    _zz_products_w_values_1_3_6;
  wire       [7:0]    _zz_products_w_values_1_4;
  wire       [14:0]   _zz_products_w_values_1_4_1;
  wire       [14:0]   _zz_products_w_values_1_4_2;
  wire       [9:0]    _zz_products_w_values_1_4_3;
  wire       [14:0]   _zz_products_w_values_1_4_4;
  wire       [7:0]    _zz_products_w_values_1_4_5;
  wire       [7:0]    _zz_products_w_values_1_4_6;
  wire       [7:0]    _zz_products_w_values_1_5;
  wire       [14:0]   _zz_products_w_values_1_5_1;
  wire       [14:0]   _zz_products_w_values_1_5_2;
  wire       [9:0]    _zz_products_w_values_1_5_3;
  wire       [14:0]   _zz_products_w_values_1_5_4;
  wire       [7:0]    _zz_products_w_values_1_5_5;
  wire       [7:0]    _zz_products_w_values_1_5_6;
  wire       [7:0]    _zz_products_w_values_1_6;
  wire       [14:0]   _zz_products_w_values_1_6_1;
  wire       [14:0]   _zz_products_w_values_1_6_2;
  wire       [9:0]    _zz_products_w_values_1_6_3;
  wire       [14:0]   _zz_products_w_values_1_6_4;
  wire       [7:0]    _zz_products_w_values_1_6_5;
  wire       [7:0]    _zz_products_w_values_1_6_6;
  wire       [7:0]    _zz_products_w_values_1_7;
  wire       [14:0]   _zz_products_w_values_1_7_1;
  wire       [14:0]   _zz_products_w_values_1_7_2;
  wire       [9:0]    _zz_products_w_values_1_7_3;
  wire       [14:0]   _zz_products_w_values_1_7_4;
  wire       [7:0]    _zz_products_w_values_1_7_5;
  wire       [7:0]    _zz_products_w_values_1_7_6;
  wire       [7:0]    _zz_products_w_values_1_8;
  wire       [14:0]   _zz_products_w_values_1_8_1;
  wire       [14:0]   _zz_products_w_values_1_8_2;
  wire       [9:0]    _zz_products_w_values_1_8_3;
  wire       [14:0]   _zz_products_w_values_1_8_4;
  wire       [7:0]    _zz_products_w_values_1_8_5;
  wire       [7:0]    _zz_products_w_values_1_8_6;
  wire       [7:0]    _zz_products_w_values_1_9;
  wire       [14:0]   _zz_products_w_values_1_9_1;
  wire       [14:0]   _zz_products_w_values_1_9_2;
  wire       [9:0]    _zz_products_w_values_1_9_3;
  wire       [14:0]   _zz_products_w_values_1_9_4;
  wire       [7:0]    _zz_products_w_values_1_9_5;
  wire       [7:0]    _zz_products_w_values_1_9_6;
  wire       [7:0]    _zz_products_w_values_1_10;
  wire       [14:0]   _zz_products_w_values_1_10_1;
  wire       [14:0]   _zz_products_w_values_1_10_2;
  wire       [9:0]    _zz_products_w_values_1_10_3;
  wire       [14:0]   _zz_products_w_values_1_10_4;
  wire       [7:0]    _zz_products_w_values_1_10_5;
  wire       [7:0]    _zz_products_w_values_1_10_6;
  wire       [7:0]    _zz_products_w_values_1_11;
  wire       [14:0]   _zz_products_w_values_1_11_1;
  wire       [14:0]   _zz_products_w_values_1_11_2;
  wire       [9:0]    _zz_products_w_values_1_11_3;
  wire       [14:0]   _zz_products_w_values_1_11_4;
  wire       [7:0]    _zz_products_w_values_1_11_5;
  wire       [7:0]    _zz_products_w_values_1_11_6;
  wire       [7:0]    _zz_products_w_values_1_12;
  wire       [14:0]   _zz_products_w_values_1_12_1;
  wire       [14:0]   _zz_products_w_values_1_12_2;
  wire       [9:0]    _zz_products_w_values_1_12_3;
  wire       [14:0]   _zz_products_w_values_1_12_4;
  wire       [7:0]    _zz_products_w_values_1_12_5;
  wire       [7:0]    _zz_products_w_values_1_12_6;
  wire       [7:0]    _zz_products_w_values_1_13;
  wire       [14:0]   _zz_products_w_values_1_13_1;
  wire       [14:0]   _zz_products_w_values_1_13_2;
  wire       [9:0]    _zz_products_w_values_1_13_3;
  wire       [14:0]   _zz_products_w_values_1_13_4;
  wire       [7:0]    _zz_products_w_values_1_13_5;
  wire       [7:0]    _zz_products_w_values_1_13_6;
  wire       [7:0]    _zz_products_w_values_1_14;
  wire       [14:0]   _zz_products_w_values_1_14_1;
  wire       [14:0]   _zz_products_w_values_1_14_2;
  wire       [9:0]    _zz_products_w_values_1_14_3;
  wire       [14:0]   _zz_products_w_values_1_14_4;
  wire       [7:0]    _zz_products_w_values_1_14_5;
  wire       [7:0]    _zz_products_w_values_1_14_6;
  wire       [7:0]    _zz_products_w_values_1_15;
  wire       [14:0]   _zz_products_w_values_1_15_1;
  wire       [14:0]   _zz_products_w_values_1_15_2;
  wire       [9:0]    _zz_products_w_values_1_15_3;
  wire       [14:0]   _zz_products_w_values_1_15_4;
  wire       [7:0]    _zz_products_w_values_1_15_5;
  wire       [7:0]    _zz_products_w_values_1_15_6;
  wire       [7:0]    _zz_products_w_values_2_0;
  wire       [14:0]   _zz_products_w_values_2_0_1;
  wire       [14:0]   _zz_products_w_values_2_0_2;
  wire       [9:0]    _zz_products_w_values_2_0_3;
  wire       [14:0]   _zz_products_w_values_2_0_4;
  wire       [7:0]    _zz_products_w_values_2_0_5;
  wire       [7:0]    _zz_products_w_values_2_0_6;
  wire       [7:0]    _zz_products_w_values_2_1;
  wire       [14:0]   _zz_products_w_values_2_1_1;
  wire       [14:0]   _zz_products_w_values_2_1_2;
  wire       [9:0]    _zz_products_w_values_2_1_3;
  wire       [14:0]   _zz_products_w_values_2_1_4;
  wire       [7:0]    _zz_products_w_values_2_1_5;
  wire       [7:0]    _zz_products_w_values_2_1_6;
  wire       [7:0]    _zz_products_w_values_2_2;
  wire       [14:0]   _zz_products_w_values_2_2_1;
  wire       [14:0]   _zz_products_w_values_2_2_2;
  wire       [9:0]    _zz_products_w_values_2_2_3;
  wire       [14:0]   _zz_products_w_values_2_2_4;
  wire       [7:0]    _zz_products_w_values_2_2_5;
  wire       [7:0]    _zz_products_w_values_2_2_6;
  wire       [7:0]    _zz_products_w_values_2_3;
  wire       [14:0]   _zz_products_w_values_2_3_1;
  wire       [14:0]   _zz_products_w_values_2_3_2;
  wire       [9:0]    _zz_products_w_values_2_3_3;
  wire       [14:0]   _zz_products_w_values_2_3_4;
  wire       [7:0]    _zz_products_w_values_2_3_5;
  wire       [7:0]    _zz_products_w_values_2_3_6;
  wire       [7:0]    _zz_products_w_values_2_4;
  wire       [14:0]   _zz_products_w_values_2_4_1;
  wire       [14:0]   _zz_products_w_values_2_4_2;
  wire       [9:0]    _zz_products_w_values_2_4_3;
  wire       [14:0]   _zz_products_w_values_2_4_4;
  wire       [7:0]    _zz_products_w_values_2_4_5;
  wire       [7:0]    _zz_products_w_values_2_4_6;
  wire       [7:0]    _zz_products_w_values_2_5;
  wire       [14:0]   _zz_products_w_values_2_5_1;
  wire       [14:0]   _zz_products_w_values_2_5_2;
  wire       [9:0]    _zz_products_w_values_2_5_3;
  wire       [14:0]   _zz_products_w_values_2_5_4;
  wire       [7:0]    _zz_products_w_values_2_5_5;
  wire       [7:0]    _zz_products_w_values_2_5_6;
  wire       [7:0]    _zz_products_w_values_2_6;
  wire       [14:0]   _zz_products_w_values_2_6_1;
  wire       [14:0]   _zz_products_w_values_2_6_2;
  wire       [9:0]    _zz_products_w_values_2_6_3;
  wire       [14:0]   _zz_products_w_values_2_6_4;
  wire       [7:0]    _zz_products_w_values_2_6_5;
  wire       [7:0]    _zz_products_w_values_2_6_6;
  wire       [7:0]    _zz_products_w_values_2_7;
  wire       [14:0]   _zz_products_w_values_2_7_1;
  wire       [14:0]   _zz_products_w_values_2_7_2;
  wire       [9:0]    _zz_products_w_values_2_7_3;
  wire       [14:0]   _zz_products_w_values_2_7_4;
  wire       [7:0]    _zz_products_w_values_2_7_5;
  wire       [7:0]    _zz_products_w_values_2_7_6;
  wire       [7:0]    _zz_products_w_values_2_8;
  wire       [14:0]   _zz_products_w_values_2_8_1;
  wire       [14:0]   _zz_products_w_values_2_8_2;
  wire       [9:0]    _zz_products_w_values_2_8_3;
  wire       [14:0]   _zz_products_w_values_2_8_4;
  wire       [7:0]    _zz_products_w_values_2_8_5;
  wire       [7:0]    _zz_products_w_values_2_8_6;
  wire       [7:0]    _zz_products_w_values_2_9;
  wire       [14:0]   _zz_products_w_values_2_9_1;
  wire       [14:0]   _zz_products_w_values_2_9_2;
  wire       [9:0]    _zz_products_w_values_2_9_3;
  wire       [14:0]   _zz_products_w_values_2_9_4;
  wire       [7:0]    _zz_products_w_values_2_9_5;
  wire       [7:0]    _zz_products_w_values_2_9_6;
  wire       [7:0]    _zz_products_w_values_2_10;
  wire       [14:0]   _zz_products_w_values_2_10_1;
  wire       [14:0]   _zz_products_w_values_2_10_2;
  wire       [9:0]    _zz_products_w_values_2_10_3;
  wire       [14:0]   _zz_products_w_values_2_10_4;
  wire       [7:0]    _zz_products_w_values_2_10_5;
  wire       [7:0]    _zz_products_w_values_2_10_6;
  wire       [7:0]    _zz_products_w_values_2_11;
  wire       [14:0]   _zz_products_w_values_2_11_1;
  wire       [14:0]   _zz_products_w_values_2_11_2;
  wire       [9:0]    _zz_products_w_values_2_11_3;
  wire       [14:0]   _zz_products_w_values_2_11_4;
  wire       [7:0]    _zz_products_w_values_2_11_5;
  wire       [7:0]    _zz_products_w_values_2_11_6;
  wire       [7:0]    _zz_products_w_values_2_12;
  wire       [14:0]   _zz_products_w_values_2_12_1;
  wire       [14:0]   _zz_products_w_values_2_12_2;
  wire       [9:0]    _zz_products_w_values_2_12_3;
  wire       [14:0]   _zz_products_w_values_2_12_4;
  wire       [7:0]    _zz_products_w_values_2_12_5;
  wire       [7:0]    _zz_products_w_values_2_12_6;
  wire       [7:0]    _zz_products_w_values_2_13;
  wire       [14:0]   _zz_products_w_values_2_13_1;
  wire       [14:0]   _zz_products_w_values_2_13_2;
  wire       [9:0]    _zz_products_w_values_2_13_3;
  wire       [14:0]   _zz_products_w_values_2_13_4;
  wire       [7:0]    _zz_products_w_values_2_13_5;
  wire       [7:0]    _zz_products_w_values_2_13_6;
  wire       [7:0]    _zz_products_w_values_2_14;
  wire       [14:0]   _zz_products_w_values_2_14_1;
  wire       [14:0]   _zz_products_w_values_2_14_2;
  wire       [9:0]    _zz_products_w_values_2_14_3;
  wire       [14:0]   _zz_products_w_values_2_14_4;
  wire       [7:0]    _zz_products_w_values_2_14_5;
  wire       [7:0]    _zz_products_w_values_2_14_6;
  wire       [7:0]    _zz_products_w_values_2_15;
  wire       [14:0]   _zz_products_w_values_2_15_1;
  wire       [14:0]   _zz_products_w_values_2_15_2;
  wire       [9:0]    _zz_products_w_values_2_15_3;
  wire       [14:0]   _zz_products_w_values_2_15_4;
  wire       [7:0]    _zz_products_w_values_2_15_5;
  wire       [7:0]    _zz_products_w_values_2_15_6;
  wire       [7:0]    _zz_products_w_values_3_0;
  wire       [14:0]   _zz_products_w_values_3_0_1;
  wire       [14:0]   _zz_products_w_values_3_0_2;
  wire       [9:0]    _zz_products_w_values_3_0_3;
  wire       [14:0]   _zz_products_w_values_3_0_4;
  wire       [7:0]    _zz_products_w_values_3_0_5;
  wire       [7:0]    _zz_products_w_values_3_0_6;
  wire       [7:0]    _zz_products_w_values_3_1;
  wire       [14:0]   _zz_products_w_values_3_1_1;
  wire       [14:0]   _zz_products_w_values_3_1_2;
  wire       [9:0]    _zz_products_w_values_3_1_3;
  wire       [14:0]   _zz_products_w_values_3_1_4;
  wire       [7:0]    _zz_products_w_values_3_1_5;
  wire       [7:0]    _zz_products_w_values_3_1_6;
  wire       [7:0]    _zz_products_w_values_3_2;
  wire       [14:0]   _zz_products_w_values_3_2_1;
  wire       [14:0]   _zz_products_w_values_3_2_2;
  wire       [9:0]    _zz_products_w_values_3_2_3;
  wire       [14:0]   _zz_products_w_values_3_2_4;
  wire       [7:0]    _zz_products_w_values_3_2_5;
  wire       [7:0]    _zz_products_w_values_3_2_6;
  wire       [7:0]    _zz_products_w_values_3_3;
  wire       [14:0]   _zz_products_w_values_3_3_1;
  wire       [14:0]   _zz_products_w_values_3_3_2;
  wire       [9:0]    _zz_products_w_values_3_3_3;
  wire       [14:0]   _zz_products_w_values_3_3_4;
  wire       [7:0]    _zz_products_w_values_3_3_5;
  wire       [7:0]    _zz_products_w_values_3_3_6;
  wire       [7:0]    _zz_products_w_values_3_4;
  wire       [14:0]   _zz_products_w_values_3_4_1;
  wire       [14:0]   _zz_products_w_values_3_4_2;
  wire       [9:0]    _zz_products_w_values_3_4_3;
  wire       [14:0]   _zz_products_w_values_3_4_4;
  wire       [7:0]    _zz_products_w_values_3_4_5;
  wire       [7:0]    _zz_products_w_values_3_4_6;
  wire       [7:0]    _zz_products_w_values_3_5;
  wire       [14:0]   _zz_products_w_values_3_5_1;
  wire       [14:0]   _zz_products_w_values_3_5_2;
  wire       [9:0]    _zz_products_w_values_3_5_3;
  wire       [14:0]   _zz_products_w_values_3_5_4;
  wire       [7:0]    _zz_products_w_values_3_5_5;
  wire       [7:0]    _zz_products_w_values_3_5_6;
  wire       [7:0]    _zz_products_w_values_3_6;
  wire       [14:0]   _zz_products_w_values_3_6_1;
  wire       [14:0]   _zz_products_w_values_3_6_2;
  wire       [9:0]    _zz_products_w_values_3_6_3;
  wire       [14:0]   _zz_products_w_values_3_6_4;
  wire       [7:0]    _zz_products_w_values_3_6_5;
  wire       [7:0]    _zz_products_w_values_3_6_6;
  wire       [7:0]    _zz_products_w_values_3_7;
  wire       [14:0]   _zz_products_w_values_3_7_1;
  wire       [14:0]   _zz_products_w_values_3_7_2;
  wire       [9:0]    _zz_products_w_values_3_7_3;
  wire       [14:0]   _zz_products_w_values_3_7_4;
  wire       [7:0]    _zz_products_w_values_3_7_5;
  wire       [7:0]    _zz_products_w_values_3_7_6;
  wire       [7:0]    _zz_products_w_values_3_8;
  wire       [14:0]   _zz_products_w_values_3_8_1;
  wire       [14:0]   _zz_products_w_values_3_8_2;
  wire       [9:0]    _zz_products_w_values_3_8_3;
  wire       [14:0]   _zz_products_w_values_3_8_4;
  wire       [7:0]    _zz_products_w_values_3_8_5;
  wire       [7:0]    _zz_products_w_values_3_8_6;
  wire       [7:0]    _zz_products_w_values_3_9;
  wire       [14:0]   _zz_products_w_values_3_9_1;
  wire       [14:0]   _zz_products_w_values_3_9_2;
  wire       [9:0]    _zz_products_w_values_3_9_3;
  wire       [14:0]   _zz_products_w_values_3_9_4;
  wire       [7:0]    _zz_products_w_values_3_9_5;
  wire       [7:0]    _zz_products_w_values_3_9_6;
  wire       [7:0]    _zz_products_w_values_3_10;
  wire       [14:0]   _zz_products_w_values_3_10_1;
  wire       [14:0]   _zz_products_w_values_3_10_2;
  wire       [9:0]    _zz_products_w_values_3_10_3;
  wire       [14:0]   _zz_products_w_values_3_10_4;
  wire       [7:0]    _zz_products_w_values_3_10_5;
  wire       [7:0]    _zz_products_w_values_3_10_6;
  wire       [7:0]    _zz_products_w_values_3_11;
  wire       [14:0]   _zz_products_w_values_3_11_1;
  wire       [14:0]   _zz_products_w_values_3_11_2;
  wire       [9:0]    _zz_products_w_values_3_11_3;
  wire       [14:0]   _zz_products_w_values_3_11_4;
  wire       [7:0]    _zz_products_w_values_3_11_5;
  wire       [7:0]    _zz_products_w_values_3_11_6;
  wire       [7:0]    _zz_products_w_values_3_12;
  wire       [14:0]   _zz_products_w_values_3_12_1;
  wire       [14:0]   _zz_products_w_values_3_12_2;
  wire       [9:0]    _zz_products_w_values_3_12_3;
  wire       [14:0]   _zz_products_w_values_3_12_4;
  wire       [7:0]    _zz_products_w_values_3_12_5;
  wire       [7:0]    _zz_products_w_values_3_12_6;
  wire       [7:0]    _zz_products_w_values_3_13;
  wire       [14:0]   _zz_products_w_values_3_13_1;
  wire       [14:0]   _zz_products_w_values_3_13_2;
  wire       [9:0]    _zz_products_w_values_3_13_3;
  wire       [14:0]   _zz_products_w_values_3_13_4;
  wire       [7:0]    _zz_products_w_values_3_13_5;
  wire       [7:0]    _zz_products_w_values_3_13_6;
  wire       [7:0]    _zz_products_w_values_3_14;
  wire       [14:0]   _zz_products_w_values_3_14_1;
  wire       [14:0]   _zz_products_w_values_3_14_2;
  wire       [9:0]    _zz_products_w_values_3_14_3;
  wire       [14:0]   _zz_products_w_values_3_14_4;
  wire       [7:0]    _zz_products_w_values_3_14_5;
  wire       [7:0]    _zz_products_w_values_3_14_6;
  wire       [7:0]    _zz_products_w_values_3_15;
  wire       [14:0]   _zz_products_w_values_3_15_1;
  wire       [14:0]   _zz_products_w_values_3_15_2;
  wire       [9:0]    _zz_products_w_values_3_15_3;
  wire       [14:0]   _zz_products_w_values_3_15_4;
  wire       [7:0]    _zz_products_w_values_3_15_5;
  wire       [7:0]    _zz_products_w_values_3_15_6;
  wire       [16:0]   _zz_reduce8_w_values_0_0;
  wire       [16:0]   _zz_reduce8_w_values_0_0_1;
  wire       [16:0]   _zz_reduce8_w_values_0_1;
  wire       [16:0]   _zz_reduce8_w_values_0_1_1;
  wire       [16:0]   _zz_reduce8_w_values_0_2;
  wire       [16:0]   _zz_reduce8_w_values_0_2_1;
  wire       [16:0]   _zz_reduce8_w_values_0_3;
  wire       [16:0]   _zz_reduce8_w_values_0_3_1;
  wire       [16:0]   _zz_reduce8_w_values_0_4;
  wire       [16:0]   _zz_reduce8_w_values_0_4_1;
  wire       [16:0]   _zz_reduce8_w_values_0_5;
  wire       [16:0]   _zz_reduce8_w_values_0_5_1;
  wire       [16:0]   _zz_reduce8_w_values_0_6;
  wire       [16:0]   _zz_reduce8_w_values_0_6_1;
  wire       [16:0]   _zz_reduce8_w_values_0_7;
  wire       [16:0]   _zz_reduce8_w_values_0_7_1;
  wire       [16:0]   _zz_reduce8_w_values_1_0;
  wire       [16:0]   _zz_reduce8_w_values_1_0_1;
  wire       [16:0]   _zz_reduce8_w_values_1_1;
  wire       [16:0]   _zz_reduce8_w_values_1_1_1;
  wire       [16:0]   _zz_reduce8_w_values_1_2;
  wire       [16:0]   _zz_reduce8_w_values_1_2_1;
  wire       [16:0]   _zz_reduce8_w_values_1_3;
  wire       [16:0]   _zz_reduce8_w_values_1_3_1;
  wire       [16:0]   _zz_reduce8_w_values_1_4;
  wire       [16:0]   _zz_reduce8_w_values_1_4_1;
  wire       [16:0]   _zz_reduce8_w_values_1_5;
  wire       [16:0]   _zz_reduce8_w_values_1_5_1;
  wire       [16:0]   _zz_reduce8_w_values_1_6;
  wire       [16:0]   _zz_reduce8_w_values_1_6_1;
  wire       [16:0]   _zz_reduce8_w_values_1_7;
  wire       [16:0]   _zz_reduce8_w_values_1_7_1;
  wire       [16:0]   _zz_reduce8_w_values_2_0;
  wire       [16:0]   _zz_reduce8_w_values_2_0_1;
  wire       [16:0]   _zz_reduce8_w_values_2_1;
  wire       [16:0]   _zz_reduce8_w_values_2_1_1;
  wire       [16:0]   _zz_reduce8_w_values_2_2;
  wire       [16:0]   _zz_reduce8_w_values_2_2_1;
  wire       [16:0]   _zz_reduce8_w_values_2_3;
  wire       [16:0]   _zz_reduce8_w_values_2_3_1;
  wire       [16:0]   _zz_reduce8_w_values_2_4;
  wire       [16:0]   _zz_reduce8_w_values_2_4_1;
  wire       [16:0]   _zz_reduce8_w_values_2_5;
  wire       [16:0]   _zz_reduce8_w_values_2_5_1;
  wire       [16:0]   _zz_reduce8_w_values_2_6;
  wire       [16:0]   _zz_reduce8_w_values_2_6_1;
  wire       [16:0]   _zz_reduce8_w_values_2_7;
  wire       [16:0]   _zz_reduce8_w_values_2_7_1;
  wire       [16:0]   _zz_reduce8_w_values_3_0;
  wire       [16:0]   _zz_reduce8_w_values_3_0_1;
  wire       [16:0]   _zz_reduce8_w_values_3_1;
  wire       [16:0]   _zz_reduce8_w_values_3_1_1;
  wire       [16:0]   _zz_reduce8_w_values_3_2;
  wire       [16:0]   _zz_reduce8_w_values_3_2_1;
  wire       [16:0]   _zz_reduce8_w_values_3_3;
  wire       [16:0]   _zz_reduce8_w_values_3_3_1;
  wire       [16:0]   _zz_reduce8_w_values_3_4;
  wire       [16:0]   _zz_reduce8_w_values_3_4_1;
  wire       [16:0]   _zz_reduce8_w_values_3_5;
  wire       [16:0]   _zz_reduce8_w_values_3_5_1;
  wire       [16:0]   _zz_reduce8_w_values_3_6;
  wire       [16:0]   _zz_reduce8_w_values_3_6_1;
  wire       [16:0]   _zz_reduce8_w_values_3_7;
  wire       [16:0]   _zz_reduce8_w_values_3_7_1;
  wire       [17:0]   _zz_reduce4_w_values_0_0;
  wire       [17:0]   _zz_reduce4_w_values_0_0_1;
  wire       [17:0]   _zz_reduce4_w_values_0_1;
  wire       [17:0]   _zz_reduce4_w_values_0_1_1;
  wire       [17:0]   _zz_reduce4_w_values_0_2;
  wire       [17:0]   _zz_reduce4_w_values_0_2_1;
  wire       [17:0]   _zz_reduce4_w_values_0_3;
  wire       [17:0]   _zz_reduce4_w_values_0_3_1;
  wire       [17:0]   _zz_reduce4_w_values_1_0;
  wire       [17:0]   _zz_reduce4_w_values_1_0_1;
  wire       [17:0]   _zz_reduce4_w_values_1_1;
  wire       [17:0]   _zz_reduce4_w_values_1_1_1;
  wire       [17:0]   _zz_reduce4_w_values_1_2;
  wire       [17:0]   _zz_reduce4_w_values_1_2_1;
  wire       [17:0]   _zz_reduce4_w_values_1_3;
  wire       [17:0]   _zz_reduce4_w_values_1_3_1;
  wire       [17:0]   _zz_reduce4_w_values_2_0;
  wire       [17:0]   _zz_reduce4_w_values_2_0_1;
  wire       [17:0]   _zz_reduce4_w_values_2_1;
  wire       [17:0]   _zz_reduce4_w_values_2_1_1;
  wire       [17:0]   _zz_reduce4_w_values_2_2;
  wire       [17:0]   _zz_reduce4_w_values_2_2_1;
  wire       [17:0]   _zz_reduce4_w_values_2_3;
  wire       [17:0]   _zz_reduce4_w_values_2_3_1;
  wire       [17:0]   _zz_reduce4_w_values_3_0;
  wire       [17:0]   _zz_reduce4_w_values_3_0_1;
  wire       [17:0]   _zz_reduce4_w_values_3_1;
  wire       [17:0]   _zz_reduce4_w_values_3_1_1;
  wire       [17:0]   _zz_reduce4_w_values_3_2;
  wire       [17:0]   _zz_reduce4_w_values_3_2_1;
  wire       [17:0]   _zz_reduce4_w_values_3_3;
  wire       [17:0]   _zz_reduce4_w_values_3_3_1;
  wire       [18:0]   _zz_reduce2_w_values_0_0;
  wire       [18:0]   _zz_reduce2_w_values_0_0_1;
  wire       [18:0]   _zz_reduce2_w_values_0_1;
  wire       [18:0]   _zz_reduce2_w_values_0_1_1;
  wire       [18:0]   _zz_reduce2_w_values_1_0;
  wire       [18:0]   _zz_reduce2_w_values_1_0_1;
  wire       [18:0]   _zz_reduce2_w_values_1_1;
  wire       [18:0]   _zz_reduce2_w_values_1_1_1;
  wire       [18:0]   _zz_reduce2_w_values_2_0;
  wire       [18:0]   _zz_reduce2_w_values_2_0_1;
  wire       [18:0]   _zz_reduce2_w_values_2_1;
  wire       [18:0]   _zz_reduce2_w_values_2_1_1;
  wire       [18:0]   _zz_reduce2_w_values_3_0;
  wire       [18:0]   _zz_reduce2_w_values_3_0_1;
  wire       [18:0]   _zz_reduce2_w_values_3_1;
  wire       [18:0]   _zz_reduce2_w_values_3_1_1;
  wire       [19:0]   _zz_dot_w_values_0_0;
  wire       [19:0]   _zz_dot_w_values_0_0_1;
  wire       [19:0]   _zz_dot_w_values_1_0;
  wire       [19:0]   _zz_dot_w_values_1_0_1;
  wire       [19:0]   _zz_dot_w_values_2_0;
  wire       [19:0]   _zz_dot_w_values_2_0_1;
  wire       [19:0]   _zz_dot_w_values_3_0;
  wire       [19:0]   _zz_dot_w_values_3_0_1;
  wire       [18:0]   _zz_localPixel_w;
  wire       [31:0]   _zz__zz_quantRequest_payload_mac_0;
  reg        [31:0]   _zz__zz_quantRequest_payload_mac_0_1;
  wire       [31:0]   _zz__zz_quantRequest_payload_mac_0_2;
  wire       [31:0]   _zz__zz_quantRequest_payload_mac_1;
  reg        [31:0]   _zz__zz_quantRequest_payload_mac_1_1;
  wire       [31:0]   _zz__zz_quantRequest_payload_mac_1_2;
  wire       [31:0]   _zz__zz_quantRequest_payload_mac_2;
  reg        [31:0]   _zz__zz_quantRequest_payload_mac_2_1;
  wire       [31:0]   _zz__zz_quantRequest_payload_mac_2_2;
  wire       [31:0]   _zz__zz_quantRequest_payload_mac_3;
  reg        [31:0]   _zz__zz_quantRequest_payload_mac_3_1;
  wire       [31:0]   _zz__zz_quantRequest_payload_mac_3_2;
  wire       [6:0]    _zz_paramMem_0_port;
  wire       [127:0]  _zz_paramMem_0_port_1;
  wire       [6:0]    _zz_paramMem_1_port;
  wire       [127:0]  _zz_paramMem_1_port_1;
  wire       [6:0]    _zz_paramMem_2_port;
  wire       [127:0]  _zz_paramMem_2_port_1;
  wire       [6:0]    _zz_paramMem_3_port;
  wire       [127:0]  _zz_paramMem_3_port_1;
  wire       [7:0]    _zz_lastTileOutput_w;
  wire       [7:0]    _zz_lastTileOutput_w_1;
  wire       [18:0]   _zz_lastTileOutput_w_2;
  wire       [18:0]   _zz_lastTileOutput_w_3;
  wire       [18:0]   _zz_lastTileOutput_w_4;
  wire       [18:0]   _zz__zz_tileCount_r;
  wire       [18:0]   _zz__zz_tileCount_r_1;
  wire       [18:0]   _zz_tileBase_r;
  wire       [4:0]    _zz_tileCount_r_2;
  wire       [2:0]    IDLE;
  wire       [2:0]    LOAD;
  wire       [2:0]    READY;
  wire       [2:0]    FILL;
  wire       [2:0]    ISSUE;
  wire       [2:0]    DRAIN;
  reg        [2:0]    state_r;
  reg        [9:0]    run_r_cin;
  reg        [9:0]    run_r_cout;
  reg        [18:0]   run_r_pixels;
  reg        [5:0]    run_r_shift;
  reg                 run_r_raw;
  reg                 run_r_int16;
  reg        [5:0]    igCount_r;
  reg        [7:0]    ogCount_r;
  reg        [12:0]   weightCount_r;
  reg        [7:0]    paramCount_r;
  reg        [12:0]   weightTotal_r;
  reg        [18:0]   tileBase_r;
  reg        [4:0]    tileCount_r;
  reg        [5:0]    fillGroup_r;
  reg        [4:0]    fillPixel_r;
  reg                 waiting_r;
  reg        [6:0]    issueGroup_r;
  reg        [5:0]    issueInput_r;
  reg        [4:0]    issuePixel_r;
  reg                 done_r;
  wire                validConfig_w;
  wire       [5:0]    cfgIg_w;
  wire       [7:0]    cfgOg_w;
  wire                io_cfg_i_fire;
  wire                io_weights_i_fire;
  wire                io_params_i_fire;
  wire                when_PwMac_l181;
  wire                io_start_i_fire;
  wire                io_rd_o_fire;
  wire       [9:0]    fillAddress_w;
  wire                io_rsp_i_fire;
  wire                when_PwMac_l204;
  wire                when_PwMac_l206;
  wire                request_valid;
  reg                 request_ready;
  wire       [18:0]   request_payload_tag_pixel;
  wire       [6:0]    request_payload_tag_group;
  reg        [3:0]    request_payload_tag_mask;
  wire                request_payload_tag_first;
  wire                request_payload_tag_finalInput;
  wire                request_payload_tag_tileLast;
  wire                request_payload_tag_last;
  wire       [5:0]    request_payload_inputGroup;
  wire                response_valid;
  wire                response_ready;
  wire       [18:0]   response_payload_tag_pixel;
  wire       [6:0]    response_payload_tag_group;
  wire       [3:0]    response_payload_tag_mask;
  wire                response_payload_tag_first;
  wire                response_payload_tag_finalInput;
  wire                response_payload_tag_tileLast;
  wire                response_payload_tag_last;
  wire       [5:0]    response_payload_inputGroup;
  reg                 request_rValid;
  reg        [18:0]   request_rData_tag_pixel;
  reg        [6:0]    request_rData_tag_group;
  reg        [3:0]    request_rData_tag_mask;
  reg                 request_rData_tag_first;
  reg                 request_rData_tag_finalInput;
  reg                 request_rData_tag_tileLast;
  reg                 request_rData_tag_last;
  reg        [5:0]    request_rData_inputGroup;
  wire                when_Stream_l477;
  wire       [9:0]    inputAddress_w;
  wire                request_fire;
  wire       [127:0]  inputData_w;
  wire       [12:0]   weightAddress_w;
  wire       [127:0]  weights_w_0;
  wire       [127:0]  weights_w_1;
  wire       [127:0]  weights_w_2;
  wire       [127:0]  weights_w_3;
  wire                when_PwMac_l252;
  wire                when_PwMac_l254;
  wire                when_PwMac_l256;
  wire       [18:0]   products_w_tag_pixel;
  wire       [6:0]    products_w_tag_group;
  wire       [3:0]    products_w_tag_mask;
  wire                products_w_tag_first;
  wire                products_w_tag_finalInput;
  wire                products_w_tag_tileLast;
  wire                products_w_tag_last;
  wire       [15:0]   products_w_values_0_0;
  wire       [15:0]   products_w_values_0_1;
  wire       [15:0]   products_w_values_0_2;
  wire       [15:0]   products_w_values_0_3;
  wire       [15:0]   products_w_values_0_4;
  wire       [15:0]   products_w_values_0_5;
  wire       [15:0]   products_w_values_0_6;
  wire       [15:0]   products_w_values_0_7;
  wire       [15:0]   products_w_values_0_8;
  wire       [15:0]   products_w_values_0_9;
  wire       [15:0]   products_w_values_0_10;
  wire       [15:0]   products_w_values_0_11;
  wire       [15:0]   products_w_values_0_12;
  wire       [15:0]   products_w_values_0_13;
  wire       [15:0]   products_w_values_0_14;
  wire       [15:0]   products_w_values_0_15;
  wire       [15:0]   products_w_values_1_0;
  wire       [15:0]   products_w_values_1_1;
  wire       [15:0]   products_w_values_1_2;
  wire       [15:0]   products_w_values_1_3;
  wire       [15:0]   products_w_values_1_4;
  wire       [15:0]   products_w_values_1_5;
  wire       [15:0]   products_w_values_1_6;
  wire       [15:0]   products_w_values_1_7;
  wire       [15:0]   products_w_values_1_8;
  wire       [15:0]   products_w_values_1_9;
  wire       [15:0]   products_w_values_1_10;
  wire       [15:0]   products_w_values_1_11;
  wire       [15:0]   products_w_values_1_12;
  wire       [15:0]   products_w_values_1_13;
  wire       [15:0]   products_w_values_1_14;
  wire       [15:0]   products_w_values_1_15;
  wire       [15:0]   products_w_values_2_0;
  wire       [15:0]   products_w_values_2_1;
  wire       [15:0]   products_w_values_2_2;
  wire       [15:0]   products_w_values_2_3;
  wire       [15:0]   products_w_values_2_4;
  wire       [15:0]   products_w_values_2_5;
  wire       [15:0]   products_w_values_2_6;
  wire       [15:0]   products_w_values_2_7;
  wire       [15:0]   products_w_values_2_8;
  wire       [15:0]   products_w_values_2_9;
  wire       [15:0]   products_w_values_2_10;
  wire       [15:0]   products_w_values_2_11;
  wire       [15:0]   products_w_values_2_12;
  wire       [15:0]   products_w_values_2_13;
  wire       [15:0]   products_w_values_2_14;
  wire       [15:0]   products_w_values_2_15;
  wire       [15:0]   products_w_values_3_0;
  wire       [15:0]   products_w_values_3_1;
  wire       [15:0]   products_w_values_3_2;
  wire       [15:0]   products_w_values_3_3;
  wire       [15:0]   products_w_values_3_4;
  wire       [15:0]   products_w_values_3_5;
  wire       [15:0]   products_w_values_3_6;
  wire       [15:0]   products_w_values_3_7;
  wire       [15:0]   products_w_values_3_8;
  wire       [15:0]   products_w_values_3_9;
  wire       [15:0]   products_w_values_3_10;
  wire       [15:0]   products_w_values_3_11;
  wire       [15:0]   products_w_values_3_12;
  wire       [15:0]   products_w_values_3_13;
  wire       [15:0]   products_w_values_3_14;
  wire       [15:0]   products_w_values_3_15;
  wire                response_translated_valid;
  reg                 response_translated_ready;
  wire       [18:0]   response_translated_payload_tag_pixel;
  wire       [6:0]    response_translated_payload_tag_group;
  wire       [3:0]    response_translated_payload_tag_mask;
  wire                response_translated_payload_tag_first;
  wire                response_translated_payload_tag_finalInput;
  wire                response_translated_payload_tag_tileLast;
  wire                response_translated_payload_tag_last;
  wire       [15:0]   response_translated_payload_values_0_0;
  wire       [15:0]   response_translated_payload_values_0_1;
  wire       [15:0]   response_translated_payload_values_0_2;
  wire       [15:0]   response_translated_payload_values_0_3;
  wire       [15:0]   response_translated_payload_values_0_4;
  wire       [15:0]   response_translated_payload_values_0_5;
  wire       [15:0]   response_translated_payload_values_0_6;
  wire       [15:0]   response_translated_payload_values_0_7;
  wire       [15:0]   response_translated_payload_values_0_8;
  wire       [15:0]   response_translated_payload_values_0_9;
  wire       [15:0]   response_translated_payload_values_0_10;
  wire       [15:0]   response_translated_payload_values_0_11;
  wire       [15:0]   response_translated_payload_values_0_12;
  wire       [15:0]   response_translated_payload_values_0_13;
  wire       [15:0]   response_translated_payload_values_0_14;
  wire       [15:0]   response_translated_payload_values_0_15;
  wire       [15:0]   response_translated_payload_values_1_0;
  wire       [15:0]   response_translated_payload_values_1_1;
  wire       [15:0]   response_translated_payload_values_1_2;
  wire       [15:0]   response_translated_payload_values_1_3;
  wire       [15:0]   response_translated_payload_values_1_4;
  wire       [15:0]   response_translated_payload_values_1_5;
  wire       [15:0]   response_translated_payload_values_1_6;
  wire       [15:0]   response_translated_payload_values_1_7;
  wire       [15:0]   response_translated_payload_values_1_8;
  wire       [15:0]   response_translated_payload_values_1_9;
  wire       [15:0]   response_translated_payload_values_1_10;
  wire       [15:0]   response_translated_payload_values_1_11;
  wire       [15:0]   response_translated_payload_values_1_12;
  wire       [15:0]   response_translated_payload_values_1_13;
  wire       [15:0]   response_translated_payload_values_1_14;
  wire       [15:0]   response_translated_payload_values_1_15;
  wire       [15:0]   response_translated_payload_values_2_0;
  wire       [15:0]   response_translated_payload_values_2_1;
  wire       [15:0]   response_translated_payload_values_2_2;
  wire       [15:0]   response_translated_payload_values_2_3;
  wire       [15:0]   response_translated_payload_values_2_4;
  wire       [15:0]   response_translated_payload_values_2_5;
  wire       [15:0]   response_translated_payload_values_2_6;
  wire       [15:0]   response_translated_payload_values_2_7;
  wire       [15:0]   response_translated_payload_values_2_8;
  wire       [15:0]   response_translated_payload_values_2_9;
  wire       [15:0]   response_translated_payload_values_2_10;
  wire       [15:0]   response_translated_payload_values_2_11;
  wire       [15:0]   response_translated_payload_values_2_12;
  wire       [15:0]   response_translated_payload_values_2_13;
  wire       [15:0]   response_translated_payload_values_2_14;
  wire       [15:0]   response_translated_payload_values_2_15;
  wire       [15:0]   response_translated_payload_values_3_0;
  wire       [15:0]   response_translated_payload_values_3_1;
  wire       [15:0]   response_translated_payload_values_3_2;
  wire       [15:0]   response_translated_payload_values_3_3;
  wire       [15:0]   response_translated_payload_values_3_4;
  wire       [15:0]   response_translated_payload_values_3_5;
  wire       [15:0]   response_translated_payload_values_3_6;
  wire       [15:0]   response_translated_payload_values_3_7;
  wire       [15:0]   response_translated_payload_values_3_8;
  wire       [15:0]   response_translated_payload_values_3_9;
  wire       [15:0]   response_translated_payload_values_3_10;
  wire       [15:0]   response_translated_payload_values_3_11;
  wire       [15:0]   response_translated_payload_values_3_12;
  wire       [15:0]   response_translated_payload_values_3_13;
  wire       [15:0]   response_translated_payload_values_3_14;
  wire       [15:0]   response_translated_payload_values_3_15;
  wire                products_valid;
  wire                products_ready;
  wire       [18:0]   products_payload_tag_pixel;
  wire       [6:0]    products_payload_tag_group;
  wire       [3:0]    products_payload_tag_mask;
  wire                products_payload_tag_first;
  wire                products_payload_tag_finalInput;
  wire                products_payload_tag_tileLast;
  wire                products_payload_tag_last;
  wire       [15:0]   products_payload_values_0_0;
  wire       [15:0]   products_payload_values_0_1;
  wire       [15:0]   products_payload_values_0_2;
  wire       [15:0]   products_payload_values_0_3;
  wire       [15:0]   products_payload_values_0_4;
  wire       [15:0]   products_payload_values_0_5;
  wire       [15:0]   products_payload_values_0_6;
  wire       [15:0]   products_payload_values_0_7;
  wire       [15:0]   products_payload_values_0_8;
  wire       [15:0]   products_payload_values_0_9;
  wire       [15:0]   products_payload_values_0_10;
  wire       [15:0]   products_payload_values_0_11;
  wire       [15:0]   products_payload_values_0_12;
  wire       [15:0]   products_payload_values_0_13;
  wire       [15:0]   products_payload_values_0_14;
  wire       [15:0]   products_payload_values_0_15;
  wire       [15:0]   products_payload_values_1_0;
  wire       [15:0]   products_payload_values_1_1;
  wire       [15:0]   products_payload_values_1_2;
  wire       [15:0]   products_payload_values_1_3;
  wire       [15:0]   products_payload_values_1_4;
  wire       [15:0]   products_payload_values_1_5;
  wire       [15:0]   products_payload_values_1_6;
  wire       [15:0]   products_payload_values_1_7;
  wire       [15:0]   products_payload_values_1_8;
  wire       [15:0]   products_payload_values_1_9;
  wire       [15:0]   products_payload_values_1_10;
  wire       [15:0]   products_payload_values_1_11;
  wire       [15:0]   products_payload_values_1_12;
  wire       [15:0]   products_payload_values_1_13;
  wire       [15:0]   products_payload_values_1_14;
  wire       [15:0]   products_payload_values_1_15;
  wire       [15:0]   products_payload_values_2_0;
  wire       [15:0]   products_payload_values_2_1;
  wire       [15:0]   products_payload_values_2_2;
  wire       [15:0]   products_payload_values_2_3;
  wire       [15:0]   products_payload_values_2_4;
  wire       [15:0]   products_payload_values_2_5;
  wire       [15:0]   products_payload_values_2_6;
  wire       [15:0]   products_payload_values_2_7;
  wire       [15:0]   products_payload_values_2_8;
  wire       [15:0]   products_payload_values_2_9;
  wire       [15:0]   products_payload_values_2_10;
  wire       [15:0]   products_payload_values_2_11;
  wire       [15:0]   products_payload_values_2_12;
  wire       [15:0]   products_payload_values_2_13;
  wire       [15:0]   products_payload_values_2_14;
  wire       [15:0]   products_payload_values_2_15;
  wire       [15:0]   products_payload_values_3_0;
  wire       [15:0]   products_payload_values_3_1;
  wire       [15:0]   products_payload_values_3_2;
  wire       [15:0]   products_payload_values_3_3;
  wire       [15:0]   products_payload_values_3_4;
  wire       [15:0]   products_payload_values_3_5;
  wire       [15:0]   products_payload_values_3_6;
  wire       [15:0]   products_payload_values_3_7;
  wire       [15:0]   products_payload_values_3_8;
  wire       [15:0]   products_payload_values_3_9;
  wire       [15:0]   products_payload_values_3_10;
  wire       [15:0]   products_payload_values_3_11;
  wire       [15:0]   products_payload_values_3_12;
  wire       [15:0]   products_payload_values_3_13;
  wire       [15:0]   products_payload_values_3_14;
  wire       [15:0]   products_payload_values_3_15;
  reg                 response_translated_rValid;
  reg        [18:0]   response_translated_rData_tag_pixel;
  reg        [6:0]    response_translated_rData_tag_group;
  reg        [3:0]    response_translated_rData_tag_mask;
  reg                 response_translated_rData_tag_first;
  reg                 response_translated_rData_tag_finalInput;
  reg                 response_translated_rData_tag_tileLast;
  reg                 response_translated_rData_tag_last;
  reg        [15:0]   response_translated_rData_values_0_0;
  reg        [15:0]   response_translated_rData_values_0_1;
  reg        [15:0]   response_translated_rData_values_0_2;
  reg        [15:0]   response_translated_rData_values_0_3;
  reg        [15:0]   response_translated_rData_values_0_4;
  reg        [15:0]   response_translated_rData_values_0_5;
  reg        [15:0]   response_translated_rData_values_0_6;
  reg        [15:0]   response_translated_rData_values_0_7;
  reg        [15:0]   response_translated_rData_values_0_8;
  reg        [15:0]   response_translated_rData_values_0_9;
  reg        [15:0]   response_translated_rData_values_0_10;
  reg        [15:0]   response_translated_rData_values_0_11;
  reg        [15:0]   response_translated_rData_values_0_12;
  reg        [15:0]   response_translated_rData_values_0_13;
  reg        [15:0]   response_translated_rData_values_0_14;
  reg        [15:0]   response_translated_rData_values_0_15;
  reg        [15:0]   response_translated_rData_values_1_0;
  reg        [15:0]   response_translated_rData_values_1_1;
  reg        [15:0]   response_translated_rData_values_1_2;
  reg        [15:0]   response_translated_rData_values_1_3;
  reg        [15:0]   response_translated_rData_values_1_4;
  reg        [15:0]   response_translated_rData_values_1_5;
  reg        [15:0]   response_translated_rData_values_1_6;
  reg        [15:0]   response_translated_rData_values_1_7;
  reg        [15:0]   response_translated_rData_values_1_8;
  reg        [15:0]   response_translated_rData_values_1_9;
  reg        [15:0]   response_translated_rData_values_1_10;
  reg        [15:0]   response_translated_rData_values_1_11;
  reg        [15:0]   response_translated_rData_values_1_12;
  reg        [15:0]   response_translated_rData_values_1_13;
  reg        [15:0]   response_translated_rData_values_1_14;
  reg        [15:0]   response_translated_rData_values_1_15;
  reg        [15:0]   response_translated_rData_values_2_0;
  reg        [15:0]   response_translated_rData_values_2_1;
  reg        [15:0]   response_translated_rData_values_2_2;
  reg        [15:0]   response_translated_rData_values_2_3;
  reg        [15:0]   response_translated_rData_values_2_4;
  reg        [15:0]   response_translated_rData_values_2_5;
  reg        [15:0]   response_translated_rData_values_2_6;
  reg        [15:0]   response_translated_rData_values_2_7;
  reg        [15:0]   response_translated_rData_values_2_8;
  reg        [15:0]   response_translated_rData_values_2_9;
  reg        [15:0]   response_translated_rData_values_2_10;
  reg        [15:0]   response_translated_rData_values_2_11;
  reg        [15:0]   response_translated_rData_values_2_12;
  reg        [15:0]   response_translated_rData_values_2_13;
  reg        [15:0]   response_translated_rData_values_2_14;
  reg        [15:0]   response_translated_rData_values_2_15;
  reg        [15:0]   response_translated_rData_values_3_0;
  reg        [15:0]   response_translated_rData_values_3_1;
  reg        [15:0]   response_translated_rData_values_3_2;
  reg        [15:0]   response_translated_rData_values_3_3;
  reg        [15:0]   response_translated_rData_values_3_4;
  reg        [15:0]   response_translated_rData_values_3_5;
  reg        [15:0]   response_translated_rData_values_3_6;
  reg        [15:0]   response_translated_rData_values_3_7;
  reg        [15:0]   response_translated_rData_values_3_8;
  reg        [15:0]   response_translated_rData_values_3_9;
  reg        [15:0]   response_translated_rData_values_3_10;
  reg        [15:0]   response_translated_rData_values_3_11;
  reg        [15:0]   response_translated_rData_values_3_12;
  reg        [15:0]   response_translated_rData_values_3_13;
  reg        [15:0]   response_translated_rData_values_3_14;
  reg        [15:0]   response_translated_rData_values_3_15;
  wire                when_Stream_l477_1;
  wire       [18:0]   reduce8_w_tag_pixel;
  wire       [6:0]    reduce8_w_tag_group;
  wire       [3:0]    reduce8_w_tag_mask;
  wire                reduce8_w_tag_first;
  wire                reduce8_w_tag_finalInput;
  wire                reduce8_w_tag_tileLast;
  wire                reduce8_w_tag_last;
  wire       [16:0]   reduce8_w_values_0_0;
  wire       [16:0]   reduce8_w_values_0_1;
  wire       [16:0]   reduce8_w_values_0_2;
  wire       [16:0]   reduce8_w_values_0_3;
  wire       [16:0]   reduce8_w_values_0_4;
  wire       [16:0]   reduce8_w_values_0_5;
  wire       [16:0]   reduce8_w_values_0_6;
  wire       [16:0]   reduce8_w_values_0_7;
  wire       [16:0]   reduce8_w_values_1_0;
  wire       [16:0]   reduce8_w_values_1_1;
  wire       [16:0]   reduce8_w_values_1_2;
  wire       [16:0]   reduce8_w_values_1_3;
  wire       [16:0]   reduce8_w_values_1_4;
  wire       [16:0]   reduce8_w_values_1_5;
  wire       [16:0]   reduce8_w_values_1_6;
  wire       [16:0]   reduce8_w_values_1_7;
  wire       [16:0]   reduce8_w_values_2_0;
  wire       [16:0]   reduce8_w_values_2_1;
  wire       [16:0]   reduce8_w_values_2_2;
  wire       [16:0]   reduce8_w_values_2_3;
  wire       [16:0]   reduce8_w_values_2_4;
  wire       [16:0]   reduce8_w_values_2_5;
  wire       [16:0]   reduce8_w_values_2_6;
  wire       [16:0]   reduce8_w_values_2_7;
  wire       [16:0]   reduce8_w_values_3_0;
  wire       [16:0]   reduce8_w_values_3_1;
  wire       [16:0]   reduce8_w_values_3_2;
  wire       [16:0]   reduce8_w_values_3_3;
  wire       [16:0]   reduce8_w_values_3_4;
  wire       [16:0]   reduce8_w_values_3_5;
  wire       [16:0]   reduce8_w_values_3_6;
  wire       [16:0]   reduce8_w_values_3_7;
  wire                products_translated_valid;
  reg                 products_translated_ready;
  wire       [18:0]   products_translated_payload_tag_pixel;
  wire       [6:0]    products_translated_payload_tag_group;
  wire       [3:0]    products_translated_payload_tag_mask;
  wire                products_translated_payload_tag_first;
  wire                products_translated_payload_tag_finalInput;
  wire                products_translated_payload_tag_tileLast;
  wire                products_translated_payload_tag_last;
  wire       [16:0]   products_translated_payload_values_0_0;
  wire       [16:0]   products_translated_payload_values_0_1;
  wire       [16:0]   products_translated_payload_values_0_2;
  wire       [16:0]   products_translated_payload_values_0_3;
  wire       [16:0]   products_translated_payload_values_0_4;
  wire       [16:0]   products_translated_payload_values_0_5;
  wire       [16:0]   products_translated_payload_values_0_6;
  wire       [16:0]   products_translated_payload_values_0_7;
  wire       [16:0]   products_translated_payload_values_1_0;
  wire       [16:0]   products_translated_payload_values_1_1;
  wire       [16:0]   products_translated_payload_values_1_2;
  wire       [16:0]   products_translated_payload_values_1_3;
  wire       [16:0]   products_translated_payload_values_1_4;
  wire       [16:0]   products_translated_payload_values_1_5;
  wire       [16:0]   products_translated_payload_values_1_6;
  wire       [16:0]   products_translated_payload_values_1_7;
  wire       [16:0]   products_translated_payload_values_2_0;
  wire       [16:0]   products_translated_payload_values_2_1;
  wire       [16:0]   products_translated_payload_values_2_2;
  wire       [16:0]   products_translated_payload_values_2_3;
  wire       [16:0]   products_translated_payload_values_2_4;
  wire       [16:0]   products_translated_payload_values_2_5;
  wire       [16:0]   products_translated_payload_values_2_6;
  wire       [16:0]   products_translated_payload_values_2_7;
  wire       [16:0]   products_translated_payload_values_3_0;
  wire       [16:0]   products_translated_payload_values_3_1;
  wire       [16:0]   products_translated_payload_values_3_2;
  wire       [16:0]   products_translated_payload_values_3_3;
  wire       [16:0]   products_translated_payload_values_3_4;
  wire       [16:0]   products_translated_payload_values_3_5;
  wire       [16:0]   products_translated_payload_values_3_6;
  wire       [16:0]   products_translated_payload_values_3_7;
  wire                reduce8_valid;
  wire                reduce8_ready;
  wire       [18:0]   reduce8_payload_tag_pixel;
  wire       [6:0]    reduce8_payload_tag_group;
  wire       [3:0]    reduce8_payload_tag_mask;
  wire                reduce8_payload_tag_first;
  wire                reduce8_payload_tag_finalInput;
  wire                reduce8_payload_tag_tileLast;
  wire                reduce8_payload_tag_last;
  wire       [16:0]   reduce8_payload_values_0_0;
  wire       [16:0]   reduce8_payload_values_0_1;
  wire       [16:0]   reduce8_payload_values_0_2;
  wire       [16:0]   reduce8_payload_values_0_3;
  wire       [16:0]   reduce8_payload_values_0_4;
  wire       [16:0]   reduce8_payload_values_0_5;
  wire       [16:0]   reduce8_payload_values_0_6;
  wire       [16:0]   reduce8_payload_values_0_7;
  wire       [16:0]   reduce8_payload_values_1_0;
  wire       [16:0]   reduce8_payload_values_1_1;
  wire       [16:0]   reduce8_payload_values_1_2;
  wire       [16:0]   reduce8_payload_values_1_3;
  wire       [16:0]   reduce8_payload_values_1_4;
  wire       [16:0]   reduce8_payload_values_1_5;
  wire       [16:0]   reduce8_payload_values_1_6;
  wire       [16:0]   reduce8_payload_values_1_7;
  wire       [16:0]   reduce8_payload_values_2_0;
  wire       [16:0]   reduce8_payload_values_2_1;
  wire       [16:0]   reduce8_payload_values_2_2;
  wire       [16:0]   reduce8_payload_values_2_3;
  wire       [16:0]   reduce8_payload_values_2_4;
  wire       [16:0]   reduce8_payload_values_2_5;
  wire       [16:0]   reduce8_payload_values_2_6;
  wire       [16:0]   reduce8_payload_values_2_7;
  wire       [16:0]   reduce8_payload_values_3_0;
  wire       [16:0]   reduce8_payload_values_3_1;
  wire       [16:0]   reduce8_payload_values_3_2;
  wire       [16:0]   reduce8_payload_values_3_3;
  wire       [16:0]   reduce8_payload_values_3_4;
  wire       [16:0]   reduce8_payload_values_3_5;
  wire       [16:0]   reduce8_payload_values_3_6;
  wire       [16:0]   reduce8_payload_values_3_7;
  reg                 products_translated_rValid;
  reg        [18:0]   products_translated_rData_tag_pixel;
  reg        [6:0]    products_translated_rData_tag_group;
  reg        [3:0]    products_translated_rData_tag_mask;
  reg                 products_translated_rData_tag_first;
  reg                 products_translated_rData_tag_finalInput;
  reg                 products_translated_rData_tag_tileLast;
  reg                 products_translated_rData_tag_last;
  reg        [16:0]   products_translated_rData_values_0_0;
  reg        [16:0]   products_translated_rData_values_0_1;
  reg        [16:0]   products_translated_rData_values_0_2;
  reg        [16:0]   products_translated_rData_values_0_3;
  reg        [16:0]   products_translated_rData_values_0_4;
  reg        [16:0]   products_translated_rData_values_0_5;
  reg        [16:0]   products_translated_rData_values_0_6;
  reg        [16:0]   products_translated_rData_values_0_7;
  reg        [16:0]   products_translated_rData_values_1_0;
  reg        [16:0]   products_translated_rData_values_1_1;
  reg        [16:0]   products_translated_rData_values_1_2;
  reg        [16:0]   products_translated_rData_values_1_3;
  reg        [16:0]   products_translated_rData_values_1_4;
  reg        [16:0]   products_translated_rData_values_1_5;
  reg        [16:0]   products_translated_rData_values_1_6;
  reg        [16:0]   products_translated_rData_values_1_7;
  reg        [16:0]   products_translated_rData_values_2_0;
  reg        [16:0]   products_translated_rData_values_2_1;
  reg        [16:0]   products_translated_rData_values_2_2;
  reg        [16:0]   products_translated_rData_values_2_3;
  reg        [16:0]   products_translated_rData_values_2_4;
  reg        [16:0]   products_translated_rData_values_2_5;
  reg        [16:0]   products_translated_rData_values_2_6;
  reg        [16:0]   products_translated_rData_values_2_7;
  reg        [16:0]   products_translated_rData_values_3_0;
  reg        [16:0]   products_translated_rData_values_3_1;
  reg        [16:0]   products_translated_rData_values_3_2;
  reg        [16:0]   products_translated_rData_values_3_3;
  reg        [16:0]   products_translated_rData_values_3_4;
  reg        [16:0]   products_translated_rData_values_3_5;
  reg        [16:0]   products_translated_rData_values_3_6;
  reg        [16:0]   products_translated_rData_values_3_7;
  wire                when_Stream_l477_2;
  wire       [18:0]   reduce4_w_tag_pixel;
  wire       [6:0]    reduce4_w_tag_group;
  wire       [3:0]    reduce4_w_tag_mask;
  wire                reduce4_w_tag_first;
  wire                reduce4_w_tag_finalInput;
  wire                reduce4_w_tag_tileLast;
  wire                reduce4_w_tag_last;
  wire       [17:0]   reduce4_w_values_0_0;
  wire       [17:0]   reduce4_w_values_0_1;
  wire       [17:0]   reduce4_w_values_0_2;
  wire       [17:0]   reduce4_w_values_0_3;
  wire       [17:0]   reduce4_w_values_1_0;
  wire       [17:0]   reduce4_w_values_1_1;
  wire       [17:0]   reduce4_w_values_1_2;
  wire       [17:0]   reduce4_w_values_1_3;
  wire       [17:0]   reduce4_w_values_2_0;
  wire       [17:0]   reduce4_w_values_2_1;
  wire       [17:0]   reduce4_w_values_2_2;
  wire       [17:0]   reduce4_w_values_2_3;
  wire       [17:0]   reduce4_w_values_3_0;
  wire       [17:0]   reduce4_w_values_3_1;
  wire       [17:0]   reduce4_w_values_3_2;
  wire       [17:0]   reduce4_w_values_3_3;
  wire                reduce8_translated_valid;
  reg                 reduce8_translated_ready;
  wire       [18:0]   reduce8_translated_payload_tag_pixel;
  wire       [6:0]    reduce8_translated_payload_tag_group;
  wire       [3:0]    reduce8_translated_payload_tag_mask;
  wire                reduce8_translated_payload_tag_first;
  wire                reduce8_translated_payload_tag_finalInput;
  wire                reduce8_translated_payload_tag_tileLast;
  wire                reduce8_translated_payload_tag_last;
  wire       [17:0]   reduce8_translated_payload_values_0_0;
  wire       [17:0]   reduce8_translated_payload_values_0_1;
  wire       [17:0]   reduce8_translated_payload_values_0_2;
  wire       [17:0]   reduce8_translated_payload_values_0_3;
  wire       [17:0]   reduce8_translated_payload_values_1_0;
  wire       [17:0]   reduce8_translated_payload_values_1_1;
  wire       [17:0]   reduce8_translated_payload_values_1_2;
  wire       [17:0]   reduce8_translated_payload_values_1_3;
  wire       [17:0]   reduce8_translated_payload_values_2_0;
  wire       [17:0]   reduce8_translated_payload_values_2_1;
  wire       [17:0]   reduce8_translated_payload_values_2_2;
  wire       [17:0]   reduce8_translated_payload_values_2_3;
  wire       [17:0]   reduce8_translated_payload_values_3_0;
  wire       [17:0]   reduce8_translated_payload_values_3_1;
  wire       [17:0]   reduce8_translated_payload_values_3_2;
  wire       [17:0]   reduce8_translated_payload_values_3_3;
  wire                reduce4_valid;
  wire                reduce4_ready;
  wire       [18:0]   reduce4_payload_tag_pixel;
  wire       [6:0]    reduce4_payload_tag_group;
  wire       [3:0]    reduce4_payload_tag_mask;
  wire                reduce4_payload_tag_first;
  wire                reduce4_payload_tag_finalInput;
  wire                reduce4_payload_tag_tileLast;
  wire                reduce4_payload_tag_last;
  wire       [17:0]   reduce4_payload_values_0_0;
  wire       [17:0]   reduce4_payload_values_0_1;
  wire       [17:0]   reduce4_payload_values_0_2;
  wire       [17:0]   reduce4_payload_values_0_3;
  wire       [17:0]   reduce4_payload_values_1_0;
  wire       [17:0]   reduce4_payload_values_1_1;
  wire       [17:0]   reduce4_payload_values_1_2;
  wire       [17:0]   reduce4_payload_values_1_3;
  wire       [17:0]   reduce4_payload_values_2_0;
  wire       [17:0]   reduce4_payload_values_2_1;
  wire       [17:0]   reduce4_payload_values_2_2;
  wire       [17:0]   reduce4_payload_values_2_3;
  wire       [17:0]   reduce4_payload_values_3_0;
  wire       [17:0]   reduce4_payload_values_3_1;
  wire       [17:0]   reduce4_payload_values_3_2;
  wire       [17:0]   reduce4_payload_values_3_3;
  reg                 reduce8_translated_rValid;
  reg        [18:0]   reduce8_translated_rData_tag_pixel;
  reg        [6:0]    reduce8_translated_rData_tag_group;
  reg        [3:0]    reduce8_translated_rData_tag_mask;
  reg                 reduce8_translated_rData_tag_first;
  reg                 reduce8_translated_rData_tag_finalInput;
  reg                 reduce8_translated_rData_tag_tileLast;
  reg                 reduce8_translated_rData_tag_last;
  reg        [17:0]   reduce8_translated_rData_values_0_0;
  reg        [17:0]   reduce8_translated_rData_values_0_1;
  reg        [17:0]   reduce8_translated_rData_values_0_2;
  reg        [17:0]   reduce8_translated_rData_values_0_3;
  reg        [17:0]   reduce8_translated_rData_values_1_0;
  reg        [17:0]   reduce8_translated_rData_values_1_1;
  reg        [17:0]   reduce8_translated_rData_values_1_2;
  reg        [17:0]   reduce8_translated_rData_values_1_3;
  reg        [17:0]   reduce8_translated_rData_values_2_0;
  reg        [17:0]   reduce8_translated_rData_values_2_1;
  reg        [17:0]   reduce8_translated_rData_values_2_2;
  reg        [17:0]   reduce8_translated_rData_values_2_3;
  reg        [17:0]   reduce8_translated_rData_values_3_0;
  reg        [17:0]   reduce8_translated_rData_values_3_1;
  reg        [17:0]   reduce8_translated_rData_values_3_2;
  reg        [17:0]   reduce8_translated_rData_values_3_3;
  wire                when_Stream_l477_3;
  wire       [18:0]   reduce2_w_tag_pixel;
  wire       [6:0]    reduce2_w_tag_group;
  wire       [3:0]    reduce2_w_tag_mask;
  wire                reduce2_w_tag_first;
  wire                reduce2_w_tag_finalInput;
  wire                reduce2_w_tag_tileLast;
  wire                reduce2_w_tag_last;
  wire       [18:0]   reduce2_w_values_0_0;
  wire       [18:0]   reduce2_w_values_0_1;
  wire       [18:0]   reduce2_w_values_1_0;
  wire       [18:0]   reduce2_w_values_1_1;
  wire       [18:0]   reduce2_w_values_2_0;
  wire       [18:0]   reduce2_w_values_2_1;
  wire       [18:0]   reduce2_w_values_3_0;
  wire       [18:0]   reduce2_w_values_3_1;
  wire                reduce4_translated_valid;
  reg                 reduce4_translated_ready;
  wire       [18:0]   reduce4_translated_payload_tag_pixel;
  wire       [6:0]    reduce4_translated_payload_tag_group;
  wire       [3:0]    reduce4_translated_payload_tag_mask;
  wire                reduce4_translated_payload_tag_first;
  wire                reduce4_translated_payload_tag_finalInput;
  wire                reduce4_translated_payload_tag_tileLast;
  wire                reduce4_translated_payload_tag_last;
  wire       [18:0]   reduce4_translated_payload_values_0_0;
  wire       [18:0]   reduce4_translated_payload_values_0_1;
  wire       [18:0]   reduce4_translated_payload_values_1_0;
  wire       [18:0]   reduce4_translated_payload_values_1_1;
  wire       [18:0]   reduce4_translated_payload_values_2_0;
  wire       [18:0]   reduce4_translated_payload_values_2_1;
  wire       [18:0]   reduce4_translated_payload_values_3_0;
  wire       [18:0]   reduce4_translated_payload_values_3_1;
  wire                reduce2_valid;
  wire                reduce2_ready;
  wire       [18:0]   reduce2_payload_tag_pixel;
  wire       [6:0]    reduce2_payload_tag_group;
  wire       [3:0]    reduce2_payload_tag_mask;
  wire                reduce2_payload_tag_first;
  wire                reduce2_payload_tag_finalInput;
  wire                reduce2_payload_tag_tileLast;
  wire                reduce2_payload_tag_last;
  wire       [18:0]   reduce2_payload_values_0_0;
  wire       [18:0]   reduce2_payload_values_0_1;
  wire       [18:0]   reduce2_payload_values_1_0;
  wire       [18:0]   reduce2_payload_values_1_1;
  wire       [18:0]   reduce2_payload_values_2_0;
  wire       [18:0]   reduce2_payload_values_2_1;
  wire       [18:0]   reduce2_payload_values_3_0;
  wire       [18:0]   reduce2_payload_values_3_1;
  reg                 reduce4_translated_rValid;
  reg        [18:0]   reduce4_translated_rData_tag_pixel;
  reg        [6:0]    reduce4_translated_rData_tag_group;
  reg        [3:0]    reduce4_translated_rData_tag_mask;
  reg                 reduce4_translated_rData_tag_first;
  reg                 reduce4_translated_rData_tag_finalInput;
  reg                 reduce4_translated_rData_tag_tileLast;
  reg                 reduce4_translated_rData_tag_last;
  reg        [18:0]   reduce4_translated_rData_values_0_0;
  reg        [18:0]   reduce4_translated_rData_values_0_1;
  reg        [18:0]   reduce4_translated_rData_values_1_0;
  reg        [18:0]   reduce4_translated_rData_values_1_1;
  reg        [18:0]   reduce4_translated_rData_values_2_0;
  reg        [18:0]   reduce4_translated_rData_values_2_1;
  reg        [18:0]   reduce4_translated_rData_values_3_0;
  reg        [18:0]   reduce4_translated_rData_values_3_1;
  wire                when_Stream_l477_4;
  wire       [18:0]   dot_w_tag_pixel;
  wire       [6:0]    dot_w_tag_group;
  wire       [3:0]    dot_w_tag_mask;
  wire                dot_w_tag_first;
  wire                dot_w_tag_finalInput;
  wire                dot_w_tag_tileLast;
  wire                dot_w_tag_last;
  wire       [19:0]   dot_w_values_0_0;
  wire       [19:0]   dot_w_values_1_0;
  wire       [19:0]   dot_w_values_2_0;
  wire       [19:0]   dot_w_values_3_0;
  wire                reduce2_translated_valid;
  reg                 reduce2_translated_ready;
  wire       [18:0]   reduce2_translated_payload_tag_pixel;
  wire       [6:0]    reduce2_translated_payload_tag_group;
  wire       [3:0]    reduce2_translated_payload_tag_mask;
  wire                reduce2_translated_payload_tag_first;
  wire                reduce2_translated_payload_tag_finalInput;
  wire                reduce2_translated_payload_tag_tileLast;
  wire                reduce2_translated_payload_tag_last;
  wire       [19:0]   reduce2_translated_payload_values_0_0;
  wire       [19:0]   reduce2_translated_payload_values_1_0;
  wire       [19:0]   reduce2_translated_payload_values_2_0;
  wire       [19:0]   reduce2_translated_payload_values_3_0;
  wire                dot_valid;
  wire                dot_ready;
  wire       [18:0]   dot_payload_tag_pixel;
  wire       [6:0]    dot_payload_tag_group;
  wire       [3:0]    dot_payload_tag_mask;
  wire                dot_payload_tag_first;
  wire                dot_payload_tag_finalInput;
  wire                dot_payload_tag_tileLast;
  wire                dot_payload_tag_last;
  wire       [19:0]   dot_payload_values_0_0;
  wire       [19:0]   dot_payload_values_1_0;
  wire       [19:0]   dot_payload_values_2_0;
  wire       [19:0]   dot_payload_values_3_0;
  reg                 reduce2_translated_rValid;
  reg        [18:0]   reduce2_translated_rData_tag_pixel;
  reg        [6:0]    reduce2_translated_rData_tag_group;
  reg        [3:0]    reduce2_translated_rData_tag_mask;
  reg                 reduce2_translated_rData_tag_first;
  reg                 reduce2_translated_rData_tag_finalInput;
  reg                 reduce2_translated_rData_tag_tileLast;
  reg                 reduce2_translated_rData_tag_last;
  reg        [19:0]   reduce2_translated_rData_values_0_0;
  reg        [19:0]   reduce2_translated_rData_values_1_0;
  reg        [19:0]   reduce2_translated_rData_values_2_0;
  reg        [19:0]   reduce2_translated_rData_values_3_0;
  wire                when_Stream_l477_5;
  reg        [31:0]   acc_r_0_0;
  reg        [31:0]   acc_r_0_1;
  reg        [31:0]   acc_r_0_2;
  reg        [31:0]   acc_r_0_3;
  reg        [31:0]   acc_r_0_4;
  reg        [31:0]   acc_r_0_5;
  reg        [31:0]   acc_r_0_6;
  reg        [31:0]   acc_r_0_7;
  reg        [31:0]   acc_r_0_8;
  reg        [31:0]   acc_r_0_9;
  reg        [31:0]   acc_r_0_10;
  reg        [31:0]   acc_r_0_11;
  reg        [31:0]   acc_r_0_12;
  reg        [31:0]   acc_r_0_13;
  reg        [31:0]   acc_r_0_14;
  reg        [31:0]   acc_r_0_15;
  reg        [31:0]   acc_r_1_0;
  reg        [31:0]   acc_r_1_1;
  reg        [31:0]   acc_r_1_2;
  reg        [31:0]   acc_r_1_3;
  reg        [31:0]   acc_r_1_4;
  reg        [31:0]   acc_r_1_5;
  reg        [31:0]   acc_r_1_6;
  reg        [31:0]   acc_r_1_7;
  reg        [31:0]   acc_r_1_8;
  reg        [31:0]   acc_r_1_9;
  reg        [31:0]   acc_r_1_10;
  reg        [31:0]   acc_r_1_11;
  reg        [31:0]   acc_r_1_12;
  reg        [31:0]   acc_r_1_13;
  reg        [31:0]   acc_r_1_14;
  reg        [31:0]   acc_r_1_15;
  reg        [31:0]   acc_r_2_0;
  reg        [31:0]   acc_r_2_1;
  reg        [31:0]   acc_r_2_2;
  reg        [31:0]   acc_r_2_3;
  reg        [31:0]   acc_r_2_4;
  reg        [31:0]   acc_r_2_5;
  reg        [31:0]   acc_r_2_6;
  reg        [31:0]   acc_r_2_7;
  reg        [31:0]   acc_r_2_8;
  reg        [31:0]   acc_r_2_9;
  reg        [31:0]   acc_r_2_10;
  reg        [31:0]   acc_r_2_11;
  reg        [31:0]   acc_r_2_12;
  reg        [31:0]   acc_r_2_13;
  reg        [31:0]   acc_r_2_14;
  reg        [31:0]   acc_r_2_15;
  reg        [31:0]   acc_r_3_0;
  reg        [31:0]   acc_r_3_1;
  reg        [31:0]   acc_r_3_2;
  reg        [31:0]   acc_r_3_3;
  reg        [31:0]   acc_r_3_4;
  reg        [31:0]   acc_r_3_5;
  reg        [31:0]   acc_r_3_6;
  reg        [31:0]   acc_r_3_7;
  reg        [31:0]   acc_r_3_8;
  reg        [31:0]   acc_r_3_9;
  reg        [31:0]   acc_r_3_10;
  reg        [31:0]   acc_r_3_11;
  reg        [31:0]   acc_r_3_12;
  reg        [31:0]   acc_r_3_13;
  reg        [31:0]   acc_r_3_14;
  reg        [31:0]   acc_r_3_15;
  wire       [3:0]    localPixel_w;
  wire                quantRequest_valid;
  reg                 quantRequest_ready;
  wire       [18:0]   quantRequest_payload_tag_pixel;
  wire       [6:0]    quantRequest_payload_tag_group;
  wire       [3:0]    quantRequest_payload_tag_mask;
  wire                quantRequest_payload_tag_first;
  wire                quantRequest_payload_tag_finalInput;
  wire                quantRequest_payload_tag_tileLast;
  wire                quantRequest_payload_tag_last;
  wire       [31:0]   quantRequest_payload_mac_0;
  wire       [31:0]   quantRequest_payload_mac_1;
  wire       [31:0]   quantRequest_payload_mac_2;
  wire       [31:0]   quantRequest_payload_mac_3;
  wire       [15:0]   _zz_3;
  wire       [31:0]   _zz_quantRequest_payload_mac_0;
  wire                dot_fire;
  wire       [31:0]   _zz_acc_r_0_0;
  wire       [15:0]   _zz_4;
  wire       [31:0]   _zz_quantRequest_payload_mac_1;
  wire       [31:0]   _zz_acc_r_1_0;
  wire       [15:0]   _zz_5;
  wire       [31:0]   _zz_quantRequest_payload_mac_2;
  wire       [31:0]   _zz_acc_r_2_0;
  wire       [15:0]   _zz_6;
  wire       [31:0]   _zz_quantRequest_payload_mac_3;
  wire       [31:0]   _zz_acc_r_3_0;
  wire                quantResponse_valid;
  wire                quantResponse_ready;
  wire       [18:0]   quantResponse_payload_tag_pixel;
  wire       [6:0]    quantResponse_payload_tag_group;
  wire       [3:0]    quantResponse_payload_tag_mask;
  wire                quantResponse_payload_tag_first;
  wire                quantResponse_payload_tag_finalInput;
  wire                quantResponse_payload_tag_tileLast;
  wire                quantResponse_payload_tag_last;
  wire       [31:0]   quantResponse_payload_mac_0;
  wire       [31:0]   quantResponse_payload_mac_1;
  wire       [31:0]   quantResponse_payload_mac_2;
  wire       [31:0]   quantResponse_payload_mac_3;
  reg                 quantRequest_rValid;
  reg        [18:0]   quantRequest_rData_tag_pixel;
  reg        [6:0]    quantRequest_rData_tag_group;
  reg        [3:0]    quantRequest_rData_tag_mask;
  reg                 quantRequest_rData_tag_first;
  reg                 quantRequest_rData_tag_finalInput;
  reg                 quantRequest_rData_tag_tileLast;
  reg                 quantRequest_rData_tag_last;
  reg        [31:0]   quantRequest_rData_mac_0;
  reg        [31:0]   quantRequest_rData_mac_1;
  reg        [31:0]   quantRequest_rData_mac_2;
  reg        [31:0]   quantRequest_rData_mac_3;
  wire                when_Stream_l477_6;
  wire       [6:0]    _zz_params_w_0;
  wire                quantRequest_fire;
  wire       [127:0]  params_w_0;
  wire       [6:0]    _zz_params_w_1;
  wire       [127:0]  params_w_1;
  wire       [6:0]    _zz_params_w_2;
  wire       [127:0]  params_w_2;
  wire       [6:0]    _zz_params_w_3;
  wire       [127:0]  params_w_3;
  wire       [18:0]   quantInput_w_tag_pixel;
  wire       [6:0]    quantInput_w_tag_group;
  wire       [3:0]    quantInput_w_tag_mask;
  wire                quantInput_w_tag_first;
  wire                quantInput_w_tag_finalInput;
  wire                quantInput_w_tag_tileLast;
  wire                quantInput_w_tag_last;
  wire                quantInput_w_raw;
  wire                quantInput_w_int16;
  wire       [5:0]    quantInput_w_shift;
  wire       [31:0]   quantInput_w_mac_0;
  wire       [31:0]   quantInput_w_mac_1;
  wire       [31:0]   quantInput_w_mac_2;
  wire       [31:0]   quantInput_w_mac_3;
  wire       [31:0]   quantInput_w_multiplier_0;
  wire       [31:0]   quantInput_w_multiplier_1;
  wire       [31:0]   quantInput_w_multiplier_2;
  wire       [31:0]   quantInput_w_multiplier_3;
  wire       [63:0]   quantInput_w_bias_0;
  wire       [63:0]   quantInput_w_bias_1;
  wire       [63:0]   quantInput_w_bias_2;
  wire       [63:0]   quantInput_w_bias_3;
  wire       [15:0]   quantInput_w_lower_0;
  wire       [15:0]   quantInput_w_lower_1;
  wire       [15:0]   quantInput_w_lower_2;
  wire       [15:0]   quantInput_w_lower_3;
  wire       [15:0]   quantInput_w_upper_0;
  wire       [15:0]   quantInput_w_upper_1;
  wire       [15:0]   quantInput_w_upper_2;
  wire       [15:0]   quantInput_w_upper_3;
  wire                quantResponse_translated_valid;
  wire                quantResponse_translated_ready;
  wire       [18:0]   quantResponse_translated_payload_tag_pixel;
  wire       [6:0]    quantResponse_translated_payload_tag_group;
  wire       [3:0]    quantResponse_translated_payload_tag_mask;
  wire                quantResponse_translated_payload_tag_first;
  wire                quantResponse_translated_payload_tag_finalInput;
  wire                quantResponse_translated_payload_tag_tileLast;
  wire                quantResponse_translated_payload_tag_last;
  wire                quantResponse_translated_payload_raw;
  wire                quantResponse_translated_payload_int16;
  wire       [5:0]    quantResponse_translated_payload_shift;
  wire       [31:0]   quantResponse_translated_payload_mac_0;
  wire       [31:0]   quantResponse_translated_payload_mac_1;
  wire       [31:0]   quantResponse_translated_payload_mac_2;
  wire       [31:0]   quantResponse_translated_payload_mac_3;
  wire       [31:0]   quantResponse_translated_payload_multiplier_0;
  wire       [31:0]   quantResponse_translated_payload_multiplier_1;
  wire       [31:0]   quantResponse_translated_payload_multiplier_2;
  wire       [31:0]   quantResponse_translated_payload_multiplier_3;
  wire       [63:0]   quantResponse_translated_payload_bias_0;
  wire       [63:0]   quantResponse_translated_payload_bias_1;
  wire       [63:0]   quantResponse_translated_payload_bias_2;
  wire       [63:0]   quantResponse_translated_payload_bias_3;
  wire       [15:0]   quantResponse_translated_payload_lower_0;
  wire       [15:0]   quantResponse_translated_payload_lower_1;
  wire       [15:0]   quantResponse_translated_payload_lower_2;
  wire       [15:0]   quantResponse_translated_payload_lower_3;
  wire       [15:0]   quantResponse_translated_payload_upper_0;
  wire       [15:0]   quantResponse_translated_payload_upper_1;
  wire       [15:0]   quantResponse_translated_payload_upper_2;
  wire       [15:0]   quantResponse_translated_payload_upper_3;
  wire                lastTileOutput_w;
  wire                io_output_o_fire;
  wire                when_PwMac_l339;
  wire       [18:0]   _zz_tileCount_r;
  (* ram_style = "block" *) reg [127:0] inputMem [0:767];
  (* ram_style = "block" *) reg [127:0] paramMem_0 [0:127];
  (* ram_style = "block" *) reg [127:0] paramMem_1 [0:127];
  (* ram_style = "block" *) reg [127:0] paramMem_2 [0:127];
  (* ram_style = "block" *) reg [127:0] paramMem_3 [0:127];

  assign _zz_cfgIg_w = (io_cfg_i_payload_cin + 10'h00f);
  assign _zz_cfgOg_w = (io_cfg_i_payload_cout + 10'h003);
  assign _zz_weightTotal_r = (cfgIg_w * cfgOg_w);
  assign _zz_tileCount_r_1 = run_r_pixels[4:0];
  assign _zz_io_rd_o_payload = (_zz_io_rd_o_payload_1 + _zz_io_rd_o_payload_4);
  assign _zz_io_rd_o_payload_1 = (_zz_io_rd_o_payload_2 + _zz_io_rd_o_payload_3);
  assign _zz_io_rd_o_payload_2 = (fillGroup_r * run_r_pixels);
  assign _zz_io_rd_o_payload_3 = {6'd0, tileBase_r};
  assign _zz_io_rd_o_payload_4 = {20'd0, fillPixel_r};
  assign _zz_fillAddress_w = (_zz_fillAddress_w_1 + _zz_fillAddress_w_2);
  assign _zz_fillAddress_w_1 = (fillGroup_r * 5'h10);
  assign _zz_fillAddress_w_2 = {6'd0, fillPixel_r};
  assign _zz_when_PwMac_l204 = (tileCount_r - 5'h01);
  assign _zz_when_PwMac_l206 = (igCount_r - 6'h01);
  assign _zz_request_payload_tag_pixel = {14'd0, issuePixel_r};
  assign _zz_request_payload_tag_mask = (_zz_request_payload_tag_mask_1 + 13'h0);
  assign _zz_request_payload_tag_mask_1 = (_zz_request_payload_tag_mask_2 * 3'b100);
  assign _zz_request_payload_tag_mask_2 = {3'd0, issueGroup_r};
  assign _zz_request_payload_tag_mask_3 = {3'd0, run_r_cout};
  assign _zz_request_payload_tag_mask_4 = (_zz_request_payload_tag_mask_5 + 13'h0001);
  assign _zz_request_payload_tag_mask_5 = (_zz_request_payload_tag_mask_6 * 3'b100);
  assign _zz_request_payload_tag_mask_6 = {3'd0, issueGroup_r};
  assign _zz_request_payload_tag_mask_7 = {3'd0, run_r_cout};
  assign _zz_request_payload_tag_mask_8 = (_zz_request_payload_tag_mask_9 + 13'h0002);
  assign _zz_request_payload_tag_mask_9 = (_zz_request_payload_tag_mask_10 * 3'b100);
  assign _zz_request_payload_tag_mask_10 = {3'd0, issueGroup_r};
  assign _zz_request_payload_tag_mask_11 = {3'd0, run_r_cout};
  assign _zz_request_payload_tag_mask_12 = (_zz_request_payload_tag_mask_13 + 13'h0003);
  assign _zz_request_payload_tag_mask_13 = (_zz_request_payload_tag_mask_14 * 3'b100);
  assign _zz_request_payload_tag_mask_14 = {3'd0, issueGroup_r};
  assign _zz_request_payload_tag_mask_15 = {3'd0, run_r_cout};
  assign _zz_request_payload_tag_finalInput = (igCount_r - 6'h01);
  assign _zz_request_payload_tag_tileLast = {1'd0, issueGroup_r};
  assign _zz_request_payload_tag_tileLast_1 = (ogCount_r - 8'h01);
  assign _zz_request_payload_tag_tileLast_2 = (tileCount_r - 5'h01);
  assign _zz_request_payload_tag_last = (tileBase_r + _zz_request_payload_tag_last_1);
  assign _zz_request_payload_tag_last_1 = {14'd0, tileCount_r};
  assign _zz_inputAddress_w = (_zz_inputAddress_w_1 + _zz_inputAddress_w_2);
  assign _zz_inputAddress_w_1 = (issueInput_r * 5'h10);
  assign _zz_inputAddress_w_2 = {6'd0, issuePixel_r};
  assign _zz_weightAddress_w = (issueGroup_r * igCount_r);
  assign _zz_weightAddress_w_1 = {7'd0, issueInput_r};
  assign _zz_when_PwMac_l252 = (tileCount_r - 5'h01);
  assign _zz_when_PwMac_l254 = (igCount_r - 6'h01);
  assign _zz_when_PwMac_l256 = {1'd0, issueGroup_r};
  assign _zz_when_PwMac_l256_1 = (ogCount_r - 8'h01);
  assign _zz_products_w_values_0_0 = ((_zz_products_w_values_0_0_1 < _zz_products_w_values_0_0_4) ? _zz_products_w_values_0_0_5 : 8'h0);
  assign _zz_products_w_values_0_0_1 = (_zz_products_w_values_0_0_2 + 15'h0);
  assign _zz_products_w_values_0_0_2 = (_zz_products_w_values_0_0_3 * 5'h10);
  assign _zz_products_w_values_0_0_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_0_0_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_0_0_5 = inputData_w[7 : 0];
  assign _zz_products_w_values_0_0_6 = weights_w_0[7 : 0];
  assign _zz_products_w_values_0_1 = ((_zz_products_w_values_0_1_1 < _zz_products_w_values_0_1_4) ? _zz_products_w_values_0_1_5 : 8'h0);
  assign _zz_products_w_values_0_1_1 = (_zz_products_w_values_0_1_2 + 15'h0001);
  assign _zz_products_w_values_0_1_2 = (_zz_products_w_values_0_1_3 * 5'h10);
  assign _zz_products_w_values_0_1_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_0_1_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_0_1_5 = inputData_w[15 : 8];
  assign _zz_products_w_values_0_1_6 = weights_w_0[15 : 8];
  assign _zz_products_w_values_0_2 = ((_zz_products_w_values_0_2_1 < _zz_products_w_values_0_2_4) ? _zz_products_w_values_0_2_5 : 8'h0);
  assign _zz_products_w_values_0_2_1 = (_zz_products_w_values_0_2_2 + 15'h0002);
  assign _zz_products_w_values_0_2_2 = (_zz_products_w_values_0_2_3 * 5'h10);
  assign _zz_products_w_values_0_2_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_0_2_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_0_2_5 = inputData_w[23 : 16];
  assign _zz_products_w_values_0_2_6 = weights_w_0[23 : 16];
  assign _zz_products_w_values_0_3 = ((_zz_products_w_values_0_3_1 < _zz_products_w_values_0_3_4) ? _zz_products_w_values_0_3_5 : 8'h0);
  assign _zz_products_w_values_0_3_1 = (_zz_products_w_values_0_3_2 + 15'h0003);
  assign _zz_products_w_values_0_3_2 = (_zz_products_w_values_0_3_3 * 5'h10);
  assign _zz_products_w_values_0_3_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_0_3_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_0_3_5 = inputData_w[31 : 24];
  assign _zz_products_w_values_0_3_6 = weights_w_0[31 : 24];
  assign _zz_products_w_values_0_4 = ((_zz_products_w_values_0_4_1 < _zz_products_w_values_0_4_4) ? _zz_products_w_values_0_4_5 : 8'h0);
  assign _zz_products_w_values_0_4_1 = (_zz_products_w_values_0_4_2 + 15'h0004);
  assign _zz_products_w_values_0_4_2 = (_zz_products_w_values_0_4_3 * 5'h10);
  assign _zz_products_w_values_0_4_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_0_4_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_0_4_5 = inputData_w[39 : 32];
  assign _zz_products_w_values_0_4_6 = weights_w_0[39 : 32];
  assign _zz_products_w_values_0_5 = ((_zz_products_w_values_0_5_1 < _zz_products_w_values_0_5_4) ? _zz_products_w_values_0_5_5 : 8'h0);
  assign _zz_products_w_values_0_5_1 = (_zz_products_w_values_0_5_2 + 15'h0005);
  assign _zz_products_w_values_0_5_2 = (_zz_products_w_values_0_5_3 * 5'h10);
  assign _zz_products_w_values_0_5_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_0_5_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_0_5_5 = inputData_w[47 : 40];
  assign _zz_products_w_values_0_5_6 = weights_w_0[47 : 40];
  assign _zz_products_w_values_0_6 = ((_zz_products_w_values_0_6_1 < _zz_products_w_values_0_6_4) ? _zz_products_w_values_0_6_5 : 8'h0);
  assign _zz_products_w_values_0_6_1 = (_zz_products_w_values_0_6_2 + 15'h0006);
  assign _zz_products_w_values_0_6_2 = (_zz_products_w_values_0_6_3 * 5'h10);
  assign _zz_products_w_values_0_6_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_0_6_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_0_6_5 = inputData_w[55 : 48];
  assign _zz_products_w_values_0_6_6 = weights_w_0[55 : 48];
  assign _zz_products_w_values_0_7 = ((_zz_products_w_values_0_7_1 < _zz_products_w_values_0_7_4) ? _zz_products_w_values_0_7_5 : 8'h0);
  assign _zz_products_w_values_0_7_1 = (_zz_products_w_values_0_7_2 + 15'h0007);
  assign _zz_products_w_values_0_7_2 = (_zz_products_w_values_0_7_3 * 5'h10);
  assign _zz_products_w_values_0_7_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_0_7_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_0_7_5 = inputData_w[63 : 56];
  assign _zz_products_w_values_0_7_6 = weights_w_0[63 : 56];
  assign _zz_products_w_values_0_8 = ((_zz_products_w_values_0_8_1 < _zz_products_w_values_0_8_4) ? _zz_products_w_values_0_8_5 : 8'h0);
  assign _zz_products_w_values_0_8_1 = (_zz_products_w_values_0_8_2 + 15'h0008);
  assign _zz_products_w_values_0_8_2 = (_zz_products_w_values_0_8_3 * 5'h10);
  assign _zz_products_w_values_0_8_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_0_8_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_0_8_5 = inputData_w[71 : 64];
  assign _zz_products_w_values_0_8_6 = weights_w_0[71 : 64];
  assign _zz_products_w_values_0_9 = ((_zz_products_w_values_0_9_1 < _zz_products_w_values_0_9_4) ? _zz_products_w_values_0_9_5 : 8'h0);
  assign _zz_products_w_values_0_9_1 = (_zz_products_w_values_0_9_2 + 15'h0009);
  assign _zz_products_w_values_0_9_2 = (_zz_products_w_values_0_9_3 * 5'h10);
  assign _zz_products_w_values_0_9_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_0_9_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_0_9_5 = inputData_w[79 : 72];
  assign _zz_products_w_values_0_9_6 = weights_w_0[79 : 72];
  assign _zz_products_w_values_0_10 = ((_zz_products_w_values_0_10_1 < _zz_products_w_values_0_10_4) ? _zz_products_w_values_0_10_5 : 8'h0);
  assign _zz_products_w_values_0_10_1 = (_zz_products_w_values_0_10_2 + 15'h000a);
  assign _zz_products_w_values_0_10_2 = (_zz_products_w_values_0_10_3 * 5'h10);
  assign _zz_products_w_values_0_10_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_0_10_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_0_10_5 = inputData_w[87 : 80];
  assign _zz_products_w_values_0_10_6 = weights_w_0[87 : 80];
  assign _zz_products_w_values_0_11 = ((_zz_products_w_values_0_11_1 < _zz_products_w_values_0_11_4) ? _zz_products_w_values_0_11_5 : 8'h0);
  assign _zz_products_w_values_0_11_1 = (_zz_products_w_values_0_11_2 + 15'h000b);
  assign _zz_products_w_values_0_11_2 = (_zz_products_w_values_0_11_3 * 5'h10);
  assign _zz_products_w_values_0_11_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_0_11_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_0_11_5 = inputData_w[95 : 88];
  assign _zz_products_w_values_0_11_6 = weights_w_0[95 : 88];
  assign _zz_products_w_values_0_12 = ((_zz_products_w_values_0_12_1 < _zz_products_w_values_0_12_4) ? _zz_products_w_values_0_12_5 : 8'h0);
  assign _zz_products_w_values_0_12_1 = (_zz_products_w_values_0_12_2 + 15'h000c);
  assign _zz_products_w_values_0_12_2 = (_zz_products_w_values_0_12_3 * 5'h10);
  assign _zz_products_w_values_0_12_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_0_12_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_0_12_5 = inputData_w[103 : 96];
  assign _zz_products_w_values_0_12_6 = weights_w_0[103 : 96];
  assign _zz_products_w_values_0_13 = ((_zz_products_w_values_0_13_1 < _zz_products_w_values_0_13_4) ? _zz_products_w_values_0_13_5 : 8'h0);
  assign _zz_products_w_values_0_13_1 = (_zz_products_w_values_0_13_2 + 15'h000d);
  assign _zz_products_w_values_0_13_2 = (_zz_products_w_values_0_13_3 * 5'h10);
  assign _zz_products_w_values_0_13_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_0_13_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_0_13_5 = inputData_w[111 : 104];
  assign _zz_products_w_values_0_13_6 = weights_w_0[111 : 104];
  assign _zz_products_w_values_0_14 = ((_zz_products_w_values_0_14_1 < _zz_products_w_values_0_14_4) ? _zz_products_w_values_0_14_5 : 8'h0);
  assign _zz_products_w_values_0_14_1 = (_zz_products_w_values_0_14_2 + 15'h000e);
  assign _zz_products_w_values_0_14_2 = (_zz_products_w_values_0_14_3 * 5'h10);
  assign _zz_products_w_values_0_14_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_0_14_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_0_14_5 = inputData_w[119 : 112];
  assign _zz_products_w_values_0_14_6 = weights_w_0[119 : 112];
  assign _zz_products_w_values_0_15 = ((_zz_products_w_values_0_15_1 < _zz_products_w_values_0_15_4) ? _zz_products_w_values_0_15_5 : 8'h0);
  assign _zz_products_w_values_0_15_1 = (_zz_products_w_values_0_15_2 + 15'h000f);
  assign _zz_products_w_values_0_15_2 = (_zz_products_w_values_0_15_3 * 5'h10);
  assign _zz_products_w_values_0_15_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_0_15_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_0_15_5 = inputData_w[127 : 120];
  assign _zz_products_w_values_0_15_6 = weights_w_0[127 : 120];
  assign _zz_products_w_values_1_0 = ((_zz_products_w_values_1_0_1 < _zz_products_w_values_1_0_4) ? _zz_products_w_values_1_0_5 : 8'h0);
  assign _zz_products_w_values_1_0_1 = (_zz_products_w_values_1_0_2 + 15'h0);
  assign _zz_products_w_values_1_0_2 = (_zz_products_w_values_1_0_3 * 5'h10);
  assign _zz_products_w_values_1_0_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_1_0_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_1_0_5 = inputData_w[7 : 0];
  assign _zz_products_w_values_1_0_6 = weights_w_1[7 : 0];
  assign _zz_products_w_values_1_1 = ((_zz_products_w_values_1_1_1 < _zz_products_w_values_1_1_4) ? _zz_products_w_values_1_1_5 : 8'h0);
  assign _zz_products_w_values_1_1_1 = (_zz_products_w_values_1_1_2 + 15'h0001);
  assign _zz_products_w_values_1_1_2 = (_zz_products_w_values_1_1_3 * 5'h10);
  assign _zz_products_w_values_1_1_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_1_1_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_1_1_5 = inputData_w[15 : 8];
  assign _zz_products_w_values_1_1_6 = weights_w_1[15 : 8];
  assign _zz_products_w_values_1_2 = ((_zz_products_w_values_1_2_1 < _zz_products_w_values_1_2_4) ? _zz_products_w_values_1_2_5 : 8'h0);
  assign _zz_products_w_values_1_2_1 = (_zz_products_w_values_1_2_2 + 15'h0002);
  assign _zz_products_w_values_1_2_2 = (_zz_products_w_values_1_2_3 * 5'h10);
  assign _zz_products_w_values_1_2_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_1_2_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_1_2_5 = inputData_w[23 : 16];
  assign _zz_products_w_values_1_2_6 = weights_w_1[23 : 16];
  assign _zz_products_w_values_1_3 = ((_zz_products_w_values_1_3_1 < _zz_products_w_values_1_3_4) ? _zz_products_w_values_1_3_5 : 8'h0);
  assign _zz_products_w_values_1_3_1 = (_zz_products_w_values_1_3_2 + 15'h0003);
  assign _zz_products_w_values_1_3_2 = (_zz_products_w_values_1_3_3 * 5'h10);
  assign _zz_products_w_values_1_3_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_1_3_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_1_3_5 = inputData_w[31 : 24];
  assign _zz_products_w_values_1_3_6 = weights_w_1[31 : 24];
  assign _zz_products_w_values_1_4 = ((_zz_products_w_values_1_4_1 < _zz_products_w_values_1_4_4) ? _zz_products_w_values_1_4_5 : 8'h0);
  assign _zz_products_w_values_1_4_1 = (_zz_products_w_values_1_4_2 + 15'h0004);
  assign _zz_products_w_values_1_4_2 = (_zz_products_w_values_1_4_3 * 5'h10);
  assign _zz_products_w_values_1_4_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_1_4_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_1_4_5 = inputData_w[39 : 32];
  assign _zz_products_w_values_1_4_6 = weights_w_1[39 : 32];
  assign _zz_products_w_values_1_5 = ((_zz_products_w_values_1_5_1 < _zz_products_w_values_1_5_4) ? _zz_products_w_values_1_5_5 : 8'h0);
  assign _zz_products_w_values_1_5_1 = (_zz_products_w_values_1_5_2 + 15'h0005);
  assign _zz_products_w_values_1_5_2 = (_zz_products_w_values_1_5_3 * 5'h10);
  assign _zz_products_w_values_1_5_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_1_5_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_1_5_5 = inputData_w[47 : 40];
  assign _zz_products_w_values_1_5_6 = weights_w_1[47 : 40];
  assign _zz_products_w_values_1_6 = ((_zz_products_w_values_1_6_1 < _zz_products_w_values_1_6_4) ? _zz_products_w_values_1_6_5 : 8'h0);
  assign _zz_products_w_values_1_6_1 = (_zz_products_w_values_1_6_2 + 15'h0006);
  assign _zz_products_w_values_1_6_2 = (_zz_products_w_values_1_6_3 * 5'h10);
  assign _zz_products_w_values_1_6_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_1_6_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_1_6_5 = inputData_w[55 : 48];
  assign _zz_products_w_values_1_6_6 = weights_w_1[55 : 48];
  assign _zz_products_w_values_1_7 = ((_zz_products_w_values_1_7_1 < _zz_products_w_values_1_7_4) ? _zz_products_w_values_1_7_5 : 8'h0);
  assign _zz_products_w_values_1_7_1 = (_zz_products_w_values_1_7_2 + 15'h0007);
  assign _zz_products_w_values_1_7_2 = (_zz_products_w_values_1_7_3 * 5'h10);
  assign _zz_products_w_values_1_7_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_1_7_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_1_7_5 = inputData_w[63 : 56];
  assign _zz_products_w_values_1_7_6 = weights_w_1[63 : 56];
  assign _zz_products_w_values_1_8 = ((_zz_products_w_values_1_8_1 < _zz_products_w_values_1_8_4) ? _zz_products_w_values_1_8_5 : 8'h0);
  assign _zz_products_w_values_1_8_1 = (_zz_products_w_values_1_8_2 + 15'h0008);
  assign _zz_products_w_values_1_8_2 = (_zz_products_w_values_1_8_3 * 5'h10);
  assign _zz_products_w_values_1_8_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_1_8_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_1_8_5 = inputData_w[71 : 64];
  assign _zz_products_w_values_1_8_6 = weights_w_1[71 : 64];
  assign _zz_products_w_values_1_9 = ((_zz_products_w_values_1_9_1 < _zz_products_w_values_1_9_4) ? _zz_products_w_values_1_9_5 : 8'h0);
  assign _zz_products_w_values_1_9_1 = (_zz_products_w_values_1_9_2 + 15'h0009);
  assign _zz_products_w_values_1_9_2 = (_zz_products_w_values_1_9_3 * 5'h10);
  assign _zz_products_w_values_1_9_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_1_9_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_1_9_5 = inputData_w[79 : 72];
  assign _zz_products_w_values_1_9_6 = weights_w_1[79 : 72];
  assign _zz_products_w_values_1_10 = ((_zz_products_w_values_1_10_1 < _zz_products_w_values_1_10_4) ? _zz_products_w_values_1_10_5 : 8'h0);
  assign _zz_products_w_values_1_10_1 = (_zz_products_w_values_1_10_2 + 15'h000a);
  assign _zz_products_w_values_1_10_2 = (_zz_products_w_values_1_10_3 * 5'h10);
  assign _zz_products_w_values_1_10_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_1_10_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_1_10_5 = inputData_w[87 : 80];
  assign _zz_products_w_values_1_10_6 = weights_w_1[87 : 80];
  assign _zz_products_w_values_1_11 = ((_zz_products_w_values_1_11_1 < _zz_products_w_values_1_11_4) ? _zz_products_w_values_1_11_5 : 8'h0);
  assign _zz_products_w_values_1_11_1 = (_zz_products_w_values_1_11_2 + 15'h000b);
  assign _zz_products_w_values_1_11_2 = (_zz_products_w_values_1_11_3 * 5'h10);
  assign _zz_products_w_values_1_11_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_1_11_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_1_11_5 = inputData_w[95 : 88];
  assign _zz_products_w_values_1_11_6 = weights_w_1[95 : 88];
  assign _zz_products_w_values_1_12 = ((_zz_products_w_values_1_12_1 < _zz_products_w_values_1_12_4) ? _zz_products_w_values_1_12_5 : 8'h0);
  assign _zz_products_w_values_1_12_1 = (_zz_products_w_values_1_12_2 + 15'h000c);
  assign _zz_products_w_values_1_12_2 = (_zz_products_w_values_1_12_3 * 5'h10);
  assign _zz_products_w_values_1_12_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_1_12_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_1_12_5 = inputData_w[103 : 96];
  assign _zz_products_w_values_1_12_6 = weights_w_1[103 : 96];
  assign _zz_products_w_values_1_13 = ((_zz_products_w_values_1_13_1 < _zz_products_w_values_1_13_4) ? _zz_products_w_values_1_13_5 : 8'h0);
  assign _zz_products_w_values_1_13_1 = (_zz_products_w_values_1_13_2 + 15'h000d);
  assign _zz_products_w_values_1_13_2 = (_zz_products_w_values_1_13_3 * 5'h10);
  assign _zz_products_w_values_1_13_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_1_13_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_1_13_5 = inputData_w[111 : 104];
  assign _zz_products_w_values_1_13_6 = weights_w_1[111 : 104];
  assign _zz_products_w_values_1_14 = ((_zz_products_w_values_1_14_1 < _zz_products_w_values_1_14_4) ? _zz_products_w_values_1_14_5 : 8'h0);
  assign _zz_products_w_values_1_14_1 = (_zz_products_w_values_1_14_2 + 15'h000e);
  assign _zz_products_w_values_1_14_2 = (_zz_products_w_values_1_14_3 * 5'h10);
  assign _zz_products_w_values_1_14_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_1_14_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_1_14_5 = inputData_w[119 : 112];
  assign _zz_products_w_values_1_14_6 = weights_w_1[119 : 112];
  assign _zz_products_w_values_1_15 = ((_zz_products_w_values_1_15_1 < _zz_products_w_values_1_15_4) ? _zz_products_w_values_1_15_5 : 8'h0);
  assign _zz_products_w_values_1_15_1 = (_zz_products_w_values_1_15_2 + 15'h000f);
  assign _zz_products_w_values_1_15_2 = (_zz_products_w_values_1_15_3 * 5'h10);
  assign _zz_products_w_values_1_15_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_1_15_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_1_15_5 = inputData_w[127 : 120];
  assign _zz_products_w_values_1_15_6 = weights_w_1[127 : 120];
  assign _zz_products_w_values_2_0 = ((_zz_products_w_values_2_0_1 < _zz_products_w_values_2_0_4) ? _zz_products_w_values_2_0_5 : 8'h0);
  assign _zz_products_w_values_2_0_1 = (_zz_products_w_values_2_0_2 + 15'h0);
  assign _zz_products_w_values_2_0_2 = (_zz_products_w_values_2_0_3 * 5'h10);
  assign _zz_products_w_values_2_0_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_2_0_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_2_0_5 = inputData_w[7 : 0];
  assign _zz_products_w_values_2_0_6 = weights_w_2[7 : 0];
  assign _zz_products_w_values_2_1 = ((_zz_products_w_values_2_1_1 < _zz_products_w_values_2_1_4) ? _zz_products_w_values_2_1_5 : 8'h0);
  assign _zz_products_w_values_2_1_1 = (_zz_products_w_values_2_1_2 + 15'h0001);
  assign _zz_products_w_values_2_1_2 = (_zz_products_w_values_2_1_3 * 5'h10);
  assign _zz_products_w_values_2_1_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_2_1_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_2_1_5 = inputData_w[15 : 8];
  assign _zz_products_w_values_2_1_6 = weights_w_2[15 : 8];
  assign _zz_products_w_values_2_2 = ((_zz_products_w_values_2_2_1 < _zz_products_w_values_2_2_4) ? _zz_products_w_values_2_2_5 : 8'h0);
  assign _zz_products_w_values_2_2_1 = (_zz_products_w_values_2_2_2 + 15'h0002);
  assign _zz_products_w_values_2_2_2 = (_zz_products_w_values_2_2_3 * 5'h10);
  assign _zz_products_w_values_2_2_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_2_2_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_2_2_5 = inputData_w[23 : 16];
  assign _zz_products_w_values_2_2_6 = weights_w_2[23 : 16];
  assign _zz_products_w_values_2_3 = ((_zz_products_w_values_2_3_1 < _zz_products_w_values_2_3_4) ? _zz_products_w_values_2_3_5 : 8'h0);
  assign _zz_products_w_values_2_3_1 = (_zz_products_w_values_2_3_2 + 15'h0003);
  assign _zz_products_w_values_2_3_2 = (_zz_products_w_values_2_3_3 * 5'h10);
  assign _zz_products_w_values_2_3_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_2_3_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_2_3_5 = inputData_w[31 : 24];
  assign _zz_products_w_values_2_3_6 = weights_w_2[31 : 24];
  assign _zz_products_w_values_2_4 = ((_zz_products_w_values_2_4_1 < _zz_products_w_values_2_4_4) ? _zz_products_w_values_2_4_5 : 8'h0);
  assign _zz_products_w_values_2_4_1 = (_zz_products_w_values_2_4_2 + 15'h0004);
  assign _zz_products_w_values_2_4_2 = (_zz_products_w_values_2_4_3 * 5'h10);
  assign _zz_products_w_values_2_4_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_2_4_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_2_4_5 = inputData_w[39 : 32];
  assign _zz_products_w_values_2_4_6 = weights_w_2[39 : 32];
  assign _zz_products_w_values_2_5 = ((_zz_products_w_values_2_5_1 < _zz_products_w_values_2_5_4) ? _zz_products_w_values_2_5_5 : 8'h0);
  assign _zz_products_w_values_2_5_1 = (_zz_products_w_values_2_5_2 + 15'h0005);
  assign _zz_products_w_values_2_5_2 = (_zz_products_w_values_2_5_3 * 5'h10);
  assign _zz_products_w_values_2_5_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_2_5_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_2_5_5 = inputData_w[47 : 40];
  assign _zz_products_w_values_2_5_6 = weights_w_2[47 : 40];
  assign _zz_products_w_values_2_6 = ((_zz_products_w_values_2_6_1 < _zz_products_w_values_2_6_4) ? _zz_products_w_values_2_6_5 : 8'h0);
  assign _zz_products_w_values_2_6_1 = (_zz_products_w_values_2_6_2 + 15'h0006);
  assign _zz_products_w_values_2_6_2 = (_zz_products_w_values_2_6_3 * 5'h10);
  assign _zz_products_w_values_2_6_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_2_6_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_2_6_5 = inputData_w[55 : 48];
  assign _zz_products_w_values_2_6_6 = weights_w_2[55 : 48];
  assign _zz_products_w_values_2_7 = ((_zz_products_w_values_2_7_1 < _zz_products_w_values_2_7_4) ? _zz_products_w_values_2_7_5 : 8'h0);
  assign _zz_products_w_values_2_7_1 = (_zz_products_w_values_2_7_2 + 15'h0007);
  assign _zz_products_w_values_2_7_2 = (_zz_products_w_values_2_7_3 * 5'h10);
  assign _zz_products_w_values_2_7_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_2_7_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_2_7_5 = inputData_w[63 : 56];
  assign _zz_products_w_values_2_7_6 = weights_w_2[63 : 56];
  assign _zz_products_w_values_2_8 = ((_zz_products_w_values_2_8_1 < _zz_products_w_values_2_8_4) ? _zz_products_w_values_2_8_5 : 8'h0);
  assign _zz_products_w_values_2_8_1 = (_zz_products_w_values_2_8_2 + 15'h0008);
  assign _zz_products_w_values_2_8_2 = (_zz_products_w_values_2_8_3 * 5'h10);
  assign _zz_products_w_values_2_8_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_2_8_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_2_8_5 = inputData_w[71 : 64];
  assign _zz_products_w_values_2_8_6 = weights_w_2[71 : 64];
  assign _zz_products_w_values_2_9 = ((_zz_products_w_values_2_9_1 < _zz_products_w_values_2_9_4) ? _zz_products_w_values_2_9_5 : 8'h0);
  assign _zz_products_w_values_2_9_1 = (_zz_products_w_values_2_9_2 + 15'h0009);
  assign _zz_products_w_values_2_9_2 = (_zz_products_w_values_2_9_3 * 5'h10);
  assign _zz_products_w_values_2_9_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_2_9_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_2_9_5 = inputData_w[79 : 72];
  assign _zz_products_w_values_2_9_6 = weights_w_2[79 : 72];
  assign _zz_products_w_values_2_10 = ((_zz_products_w_values_2_10_1 < _zz_products_w_values_2_10_4) ? _zz_products_w_values_2_10_5 : 8'h0);
  assign _zz_products_w_values_2_10_1 = (_zz_products_w_values_2_10_2 + 15'h000a);
  assign _zz_products_w_values_2_10_2 = (_zz_products_w_values_2_10_3 * 5'h10);
  assign _zz_products_w_values_2_10_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_2_10_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_2_10_5 = inputData_w[87 : 80];
  assign _zz_products_w_values_2_10_6 = weights_w_2[87 : 80];
  assign _zz_products_w_values_2_11 = ((_zz_products_w_values_2_11_1 < _zz_products_w_values_2_11_4) ? _zz_products_w_values_2_11_5 : 8'h0);
  assign _zz_products_w_values_2_11_1 = (_zz_products_w_values_2_11_2 + 15'h000b);
  assign _zz_products_w_values_2_11_2 = (_zz_products_w_values_2_11_3 * 5'h10);
  assign _zz_products_w_values_2_11_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_2_11_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_2_11_5 = inputData_w[95 : 88];
  assign _zz_products_w_values_2_11_6 = weights_w_2[95 : 88];
  assign _zz_products_w_values_2_12 = ((_zz_products_w_values_2_12_1 < _zz_products_w_values_2_12_4) ? _zz_products_w_values_2_12_5 : 8'h0);
  assign _zz_products_w_values_2_12_1 = (_zz_products_w_values_2_12_2 + 15'h000c);
  assign _zz_products_w_values_2_12_2 = (_zz_products_w_values_2_12_3 * 5'h10);
  assign _zz_products_w_values_2_12_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_2_12_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_2_12_5 = inputData_w[103 : 96];
  assign _zz_products_w_values_2_12_6 = weights_w_2[103 : 96];
  assign _zz_products_w_values_2_13 = ((_zz_products_w_values_2_13_1 < _zz_products_w_values_2_13_4) ? _zz_products_w_values_2_13_5 : 8'h0);
  assign _zz_products_w_values_2_13_1 = (_zz_products_w_values_2_13_2 + 15'h000d);
  assign _zz_products_w_values_2_13_2 = (_zz_products_w_values_2_13_3 * 5'h10);
  assign _zz_products_w_values_2_13_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_2_13_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_2_13_5 = inputData_w[111 : 104];
  assign _zz_products_w_values_2_13_6 = weights_w_2[111 : 104];
  assign _zz_products_w_values_2_14 = ((_zz_products_w_values_2_14_1 < _zz_products_w_values_2_14_4) ? _zz_products_w_values_2_14_5 : 8'h0);
  assign _zz_products_w_values_2_14_1 = (_zz_products_w_values_2_14_2 + 15'h000e);
  assign _zz_products_w_values_2_14_2 = (_zz_products_w_values_2_14_3 * 5'h10);
  assign _zz_products_w_values_2_14_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_2_14_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_2_14_5 = inputData_w[119 : 112];
  assign _zz_products_w_values_2_14_6 = weights_w_2[119 : 112];
  assign _zz_products_w_values_2_15 = ((_zz_products_w_values_2_15_1 < _zz_products_w_values_2_15_4) ? _zz_products_w_values_2_15_5 : 8'h0);
  assign _zz_products_w_values_2_15_1 = (_zz_products_w_values_2_15_2 + 15'h000f);
  assign _zz_products_w_values_2_15_2 = (_zz_products_w_values_2_15_3 * 5'h10);
  assign _zz_products_w_values_2_15_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_2_15_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_2_15_5 = inputData_w[127 : 120];
  assign _zz_products_w_values_2_15_6 = weights_w_2[127 : 120];
  assign _zz_products_w_values_3_0 = ((_zz_products_w_values_3_0_1 < _zz_products_w_values_3_0_4) ? _zz_products_w_values_3_0_5 : 8'h0);
  assign _zz_products_w_values_3_0_1 = (_zz_products_w_values_3_0_2 + 15'h0);
  assign _zz_products_w_values_3_0_2 = (_zz_products_w_values_3_0_3 * 5'h10);
  assign _zz_products_w_values_3_0_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_3_0_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_3_0_5 = inputData_w[7 : 0];
  assign _zz_products_w_values_3_0_6 = weights_w_3[7 : 0];
  assign _zz_products_w_values_3_1 = ((_zz_products_w_values_3_1_1 < _zz_products_w_values_3_1_4) ? _zz_products_w_values_3_1_5 : 8'h0);
  assign _zz_products_w_values_3_1_1 = (_zz_products_w_values_3_1_2 + 15'h0001);
  assign _zz_products_w_values_3_1_2 = (_zz_products_w_values_3_1_3 * 5'h10);
  assign _zz_products_w_values_3_1_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_3_1_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_3_1_5 = inputData_w[15 : 8];
  assign _zz_products_w_values_3_1_6 = weights_w_3[15 : 8];
  assign _zz_products_w_values_3_2 = ((_zz_products_w_values_3_2_1 < _zz_products_w_values_3_2_4) ? _zz_products_w_values_3_2_5 : 8'h0);
  assign _zz_products_w_values_3_2_1 = (_zz_products_w_values_3_2_2 + 15'h0002);
  assign _zz_products_w_values_3_2_2 = (_zz_products_w_values_3_2_3 * 5'h10);
  assign _zz_products_w_values_3_2_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_3_2_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_3_2_5 = inputData_w[23 : 16];
  assign _zz_products_w_values_3_2_6 = weights_w_3[23 : 16];
  assign _zz_products_w_values_3_3 = ((_zz_products_w_values_3_3_1 < _zz_products_w_values_3_3_4) ? _zz_products_w_values_3_3_5 : 8'h0);
  assign _zz_products_w_values_3_3_1 = (_zz_products_w_values_3_3_2 + 15'h0003);
  assign _zz_products_w_values_3_3_2 = (_zz_products_w_values_3_3_3 * 5'h10);
  assign _zz_products_w_values_3_3_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_3_3_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_3_3_5 = inputData_w[31 : 24];
  assign _zz_products_w_values_3_3_6 = weights_w_3[31 : 24];
  assign _zz_products_w_values_3_4 = ((_zz_products_w_values_3_4_1 < _zz_products_w_values_3_4_4) ? _zz_products_w_values_3_4_5 : 8'h0);
  assign _zz_products_w_values_3_4_1 = (_zz_products_w_values_3_4_2 + 15'h0004);
  assign _zz_products_w_values_3_4_2 = (_zz_products_w_values_3_4_3 * 5'h10);
  assign _zz_products_w_values_3_4_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_3_4_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_3_4_5 = inputData_w[39 : 32];
  assign _zz_products_w_values_3_4_6 = weights_w_3[39 : 32];
  assign _zz_products_w_values_3_5 = ((_zz_products_w_values_3_5_1 < _zz_products_w_values_3_5_4) ? _zz_products_w_values_3_5_5 : 8'h0);
  assign _zz_products_w_values_3_5_1 = (_zz_products_w_values_3_5_2 + 15'h0005);
  assign _zz_products_w_values_3_5_2 = (_zz_products_w_values_3_5_3 * 5'h10);
  assign _zz_products_w_values_3_5_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_3_5_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_3_5_5 = inputData_w[47 : 40];
  assign _zz_products_w_values_3_5_6 = weights_w_3[47 : 40];
  assign _zz_products_w_values_3_6 = ((_zz_products_w_values_3_6_1 < _zz_products_w_values_3_6_4) ? _zz_products_w_values_3_6_5 : 8'h0);
  assign _zz_products_w_values_3_6_1 = (_zz_products_w_values_3_6_2 + 15'h0006);
  assign _zz_products_w_values_3_6_2 = (_zz_products_w_values_3_6_3 * 5'h10);
  assign _zz_products_w_values_3_6_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_3_6_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_3_6_5 = inputData_w[55 : 48];
  assign _zz_products_w_values_3_6_6 = weights_w_3[55 : 48];
  assign _zz_products_w_values_3_7 = ((_zz_products_w_values_3_7_1 < _zz_products_w_values_3_7_4) ? _zz_products_w_values_3_7_5 : 8'h0);
  assign _zz_products_w_values_3_7_1 = (_zz_products_w_values_3_7_2 + 15'h0007);
  assign _zz_products_w_values_3_7_2 = (_zz_products_w_values_3_7_3 * 5'h10);
  assign _zz_products_w_values_3_7_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_3_7_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_3_7_5 = inputData_w[63 : 56];
  assign _zz_products_w_values_3_7_6 = weights_w_3[63 : 56];
  assign _zz_products_w_values_3_8 = ((_zz_products_w_values_3_8_1 < _zz_products_w_values_3_8_4) ? _zz_products_w_values_3_8_5 : 8'h0);
  assign _zz_products_w_values_3_8_1 = (_zz_products_w_values_3_8_2 + 15'h0008);
  assign _zz_products_w_values_3_8_2 = (_zz_products_w_values_3_8_3 * 5'h10);
  assign _zz_products_w_values_3_8_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_3_8_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_3_8_5 = inputData_w[71 : 64];
  assign _zz_products_w_values_3_8_6 = weights_w_3[71 : 64];
  assign _zz_products_w_values_3_9 = ((_zz_products_w_values_3_9_1 < _zz_products_w_values_3_9_4) ? _zz_products_w_values_3_9_5 : 8'h0);
  assign _zz_products_w_values_3_9_1 = (_zz_products_w_values_3_9_2 + 15'h0009);
  assign _zz_products_w_values_3_9_2 = (_zz_products_w_values_3_9_3 * 5'h10);
  assign _zz_products_w_values_3_9_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_3_9_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_3_9_5 = inputData_w[79 : 72];
  assign _zz_products_w_values_3_9_6 = weights_w_3[79 : 72];
  assign _zz_products_w_values_3_10 = ((_zz_products_w_values_3_10_1 < _zz_products_w_values_3_10_4) ? _zz_products_w_values_3_10_5 : 8'h0);
  assign _zz_products_w_values_3_10_1 = (_zz_products_w_values_3_10_2 + 15'h000a);
  assign _zz_products_w_values_3_10_2 = (_zz_products_w_values_3_10_3 * 5'h10);
  assign _zz_products_w_values_3_10_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_3_10_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_3_10_5 = inputData_w[87 : 80];
  assign _zz_products_w_values_3_10_6 = weights_w_3[87 : 80];
  assign _zz_products_w_values_3_11 = ((_zz_products_w_values_3_11_1 < _zz_products_w_values_3_11_4) ? _zz_products_w_values_3_11_5 : 8'h0);
  assign _zz_products_w_values_3_11_1 = (_zz_products_w_values_3_11_2 + 15'h000b);
  assign _zz_products_w_values_3_11_2 = (_zz_products_w_values_3_11_3 * 5'h10);
  assign _zz_products_w_values_3_11_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_3_11_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_3_11_5 = inputData_w[95 : 88];
  assign _zz_products_w_values_3_11_6 = weights_w_3[95 : 88];
  assign _zz_products_w_values_3_12 = ((_zz_products_w_values_3_12_1 < _zz_products_w_values_3_12_4) ? _zz_products_w_values_3_12_5 : 8'h0);
  assign _zz_products_w_values_3_12_1 = (_zz_products_w_values_3_12_2 + 15'h000c);
  assign _zz_products_w_values_3_12_2 = (_zz_products_w_values_3_12_3 * 5'h10);
  assign _zz_products_w_values_3_12_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_3_12_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_3_12_5 = inputData_w[103 : 96];
  assign _zz_products_w_values_3_12_6 = weights_w_3[103 : 96];
  assign _zz_products_w_values_3_13 = ((_zz_products_w_values_3_13_1 < _zz_products_w_values_3_13_4) ? _zz_products_w_values_3_13_5 : 8'h0);
  assign _zz_products_w_values_3_13_1 = (_zz_products_w_values_3_13_2 + 15'h000d);
  assign _zz_products_w_values_3_13_2 = (_zz_products_w_values_3_13_3 * 5'h10);
  assign _zz_products_w_values_3_13_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_3_13_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_3_13_5 = inputData_w[111 : 104];
  assign _zz_products_w_values_3_13_6 = weights_w_3[111 : 104];
  assign _zz_products_w_values_3_14 = ((_zz_products_w_values_3_14_1 < _zz_products_w_values_3_14_4) ? _zz_products_w_values_3_14_5 : 8'h0);
  assign _zz_products_w_values_3_14_1 = (_zz_products_w_values_3_14_2 + 15'h000e);
  assign _zz_products_w_values_3_14_2 = (_zz_products_w_values_3_14_3 * 5'h10);
  assign _zz_products_w_values_3_14_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_3_14_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_3_14_5 = inputData_w[119 : 112];
  assign _zz_products_w_values_3_14_6 = weights_w_3[119 : 112];
  assign _zz_products_w_values_3_15 = ((_zz_products_w_values_3_15_1 < _zz_products_w_values_3_15_4) ? _zz_products_w_values_3_15_5 : 8'h0);
  assign _zz_products_w_values_3_15_1 = (_zz_products_w_values_3_15_2 + 15'h000f);
  assign _zz_products_w_values_3_15_2 = (_zz_products_w_values_3_15_3 * 5'h10);
  assign _zz_products_w_values_3_15_3 = {4'd0, response_payload_inputGroup};
  assign _zz_products_w_values_3_15_4 = {5'd0, run_r_cin};
  assign _zz_products_w_values_3_15_5 = inputData_w[127 : 120];
  assign _zz_products_w_values_3_15_6 = weights_w_3[127 : 120];
  assign _zz_reduce8_w_values_0_0 = {{1{products_payload_values_0_0[15]}}, products_payload_values_0_0};
  assign _zz_reduce8_w_values_0_0_1 = {{1{products_payload_values_0_1[15]}}, products_payload_values_0_1};
  assign _zz_reduce8_w_values_0_1 = {{1{products_payload_values_0_2[15]}}, products_payload_values_0_2};
  assign _zz_reduce8_w_values_0_1_1 = {{1{products_payload_values_0_3[15]}}, products_payload_values_0_3};
  assign _zz_reduce8_w_values_0_2 = {{1{products_payload_values_0_4[15]}}, products_payload_values_0_4};
  assign _zz_reduce8_w_values_0_2_1 = {{1{products_payload_values_0_5[15]}}, products_payload_values_0_5};
  assign _zz_reduce8_w_values_0_3 = {{1{products_payload_values_0_6[15]}}, products_payload_values_0_6};
  assign _zz_reduce8_w_values_0_3_1 = {{1{products_payload_values_0_7[15]}}, products_payload_values_0_7};
  assign _zz_reduce8_w_values_0_4 = {{1{products_payload_values_0_8[15]}}, products_payload_values_0_8};
  assign _zz_reduce8_w_values_0_4_1 = {{1{products_payload_values_0_9[15]}}, products_payload_values_0_9};
  assign _zz_reduce8_w_values_0_5 = {{1{products_payload_values_0_10[15]}}, products_payload_values_0_10};
  assign _zz_reduce8_w_values_0_5_1 = {{1{products_payload_values_0_11[15]}}, products_payload_values_0_11};
  assign _zz_reduce8_w_values_0_6 = {{1{products_payload_values_0_12[15]}}, products_payload_values_0_12};
  assign _zz_reduce8_w_values_0_6_1 = {{1{products_payload_values_0_13[15]}}, products_payload_values_0_13};
  assign _zz_reduce8_w_values_0_7 = {{1{products_payload_values_0_14[15]}}, products_payload_values_0_14};
  assign _zz_reduce8_w_values_0_7_1 = {{1{products_payload_values_0_15[15]}}, products_payload_values_0_15};
  assign _zz_reduce8_w_values_1_0 = {{1{products_payload_values_1_0[15]}}, products_payload_values_1_0};
  assign _zz_reduce8_w_values_1_0_1 = {{1{products_payload_values_1_1[15]}}, products_payload_values_1_1};
  assign _zz_reduce8_w_values_1_1 = {{1{products_payload_values_1_2[15]}}, products_payload_values_1_2};
  assign _zz_reduce8_w_values_1_1_1 = {{1{products_payload_values_1_3[15]}}, products_payload_values_1_3};
  assign _zz_reduce8_w_values_1_2 = {{1{products_payload_values_1_4[15]}}, products_payload_values_1_4};
  assign _zz_reduce8_w_values_1_2_1 = {{1{products_payload_values_1_5[15]}}, products_payload_values_1_5};
  assign _zz_reduce8_w_values_1_3 = {{1{products_payload_values_1_6[15]}}, products_payload_values_1_6};
  assign _zz_reduce8_w_values_1_3_1 = {{1{products_payload_values_1_7[15]}}, products_payload_values_1_7};
  assign _zz_reduce8_w_values_1_4 = {{1{products_payload_values_1_8[15]}}, products_payload_values_1_8};
  assign _zz_reduce8_w_values_1_4_1 = {{1{products_payload_values_1_9[15]}}, products_payload_values_1_9};
  assign _zz_reduce8_w_values_1_5 = {{1{products_payload_values_1_10[15]}}, products_payload_values_1_10};
  assign _zz_reduce8_w_values_1_5_1 = {{1{products_payload_values_1_11[15]}}, products_payload_values_1_11};
  assign _zz_reduce8_w_values_1_6 = {{1{products_payload_values_1_12[15]}}, products_payload_values_1_12};
  assign _zz_reduce8_w_values_1_6_1 = {{1{products_payload_values_1_13[15]}}, products_payload_values_1_13};
  assign _zz_reduce8_w_values_1_7 = {{1{products_payload_values_1_14[15]}}, products_payload_values_1_14};
  assign _zz_reduce8_w_values_1_7_1 = {{1{products_payload_values_1_15[15]}}, products_payload_values_1_15};
  assign _zz_reduce8_w_values_2_0 = {{1{products_payload_values_2_0[15]}}, products_payload_values_2_0};
  assign _zz_reduce8_w_values_2_0_1 = {{1{products_payload_values_2_1[15]}}, products_payload_values_2_1};
  assign _zz_reduce8_w_values_2_1 = {{1{products_payload_values_2_2[15]}}, products_payload_values_2_2};
  assign _zz_reduce8_w_values_2_1_1 = {{1{products_payload_values_2_3[15]}}, products_payload_values_2_3};
  assign _zz_reduce8_w_values_2_2 = {{1{products_payload_values_2_4[15]}}, products_payload_values_2_4};
  assign _zz_reduce8_w_values_2_2_1 = {{1{products_payload_values_2_5[15]}}, products_payload_values_2_5};
  assign _zz_reduce8_w_values_2_3 = {{1{products_payload_values_2_6[15]}}, products_payload_values_2_6};
  assign _zz_reduce8_w_values_2_3_1 = {{1{products_payload_values_2_7[15]}}, products_payload_values_2_7};
  assign _zz_reduce8_w_values_2_4 = {{1{products_payload_values_2_8[15]}}, products_payload_values_2_8};
  assign _zz_reduce8_w_values_2_4_1 = {{1{products_payload_values_2_9[15]}}, products_payload_values_2_9};
  assign _zz_reduce8_w_values_2_5 = {{1{products_payload_values_2_10[15]}}, products_payload_values_2_10};
  assign _zz_reduce8_w_values_2_5_1 = {{1{products_payload_values_2_11[15]}}, products_payload_values_2_11};
  assign _zz_reduce8_w_values_2_6 = {{1{products_payload_values_2_12[15]}}, products_payload_values_2_12};
  assign _zz_reduce8_w_values_2_6_1 = {{1{products_payload_values_2_13[15]}}, products_payload_values_2_13};
  assign _zz_reduce8_w_values_2_7 = {{1{products_payload_values_2_14[15]}}, products_payload_values_2_14};
  assign _zz_reduce8_w_values_2_7_1 = {{1{products_payload_values_2_15[15]}}, products_payload_values_2_15};
  assign _zz_reduce8_w_values_3_0 = {{1{products_payload_values_3_0[15]}}, products_payload_values_3_0};
  assign _zz_reduce8_w_values_3_0_1 = {{1{products_payload_values_3_1[15]}}, products_payload_values_3_1};
  assign _zz_reduce8_w_values_3_1 = {{1{products_payload_values_3_2[15]}}, products_payload_values_3_2};
  assign _zz_reduce8_w_values_3_1_1 = {{1{products_payload_values_3_3[15]}}, products_payload_values_3_3};
  assign _zz_reduce8_w_values_3_2 = {{1{products_payload_values_3_4[15]}}, products_payload_values_3_4};
  assign _zz_reduce8_w_values_3_2_1 = {{1{products_payload_values_3_5[15]}}, products_payload_values_3_5};
  assign _zz_reduce8_w_values_3_3 = {{1{products_payload_values_3_6[15]}}, products_payload_values_3_6};
  assign _zz_reduce8_w_values_3_3_1 = {{1{products_payload_values_3_7[15]}}, products_payload_values_3_7};
  assign _zz_reduce8_w_values_3_4 = {{1{products_payload_values_3_8[15]}}, products_payload_values_3_8};
  assign _zz_reduce8_w_values_3_4_1 = {{1{products_payload_values_3_9[15]}}, products_payload_values_3_9};
  assign _zz_reduce8_w_values_3_5 = {{1{products_payload_values_3_10[15]}}, products_payload_values_3_10};
  assign _zz_reduce8_w_values_3_5_1 = {{1{products_payload_values_3_11[15]}}, products_payload_values_3_11};
  assign _zz_reduce8_w_values_3_6 = {{1{products_payload_values_3_12[15]}}, products_payload_values_3_12};
  assign _zz_reduce8_w_values_3_6_1 = {{1{products_payload_values_3_13[15]}}, products_payload_values_3_13};
  assign _zz_reduce8_w_values_3_7 = {{1{products_payload_values_3_14[15]}}, products_payload_values_3_14};
  assign _zz_reduce8_w_values_3_7_1 = {{1{products_payload_values_3_15[15]}}, products_payload_values_3_15};
  assign _zz_reduce4_w_values_0_0 = {{1{reduce8_payload_values_0_0[16]}}, reduce8_payload_values_0_0};
  assign _zz_reduce4_w_values_0_0_1 = {{1{reduce8_payload_values_0_1[16]}}, reduce8_payload_values_0_1};
  assign _zz_reduce4_w_values_0_1 = {{1{reduce8_payload_values_0_2[16]}}, reduce8_payload_values_0_2};
  assign _zz_reduce4_w_values_0_1_1 = {{1{reduce8_payload_values_0_3[16]}}, reduce8_payload_values_0_3};
  assign _zz_reduce4_w_values_0_2 = {{1{reduce8_payload_values_0_4[16]}}, reduce8_payload_values_0_4};
  assign _zz_reduce4_w_values_0_2_1 = {{1{reduce8_payload_values_0_5[16]}}, reduce8_payload_values_0_5};
  assign _zz_reduce4_w_values_0_3 = {{1{reduce8_payload_values_0_6[16]}}, reduce8_payload_values_0_6};
  assign _zz_reduce4_w_values_0_3_1 = {{1{reduce8_payload_values_0_7[16]}}, reduce8_payload_values_0_7};
  assign _zz_reduce4_w_values_1_0 = {{1{reduce8_payload_values_1_0[16]}}, reduce8_payload_values_1_0};
  assign _zz_reduce4_w_values_1_0_1 = {{1{reduce8_payload_values_1_1[16]}}, reduce8_payload_values_1_1};
  assign _zz_reduce4_w_values_1_1 = {{1{reduce8_payload_values_1_2[16]}}, reduce8_payload_values_1_2};
  assign _zz_reduce4_w_values_1_1_1 = {{1{reduce8_payload_values_1_3[16]}}, reduce8_payload_values_1_3};
  assign _zz_reduce4_w_values_1_2 = {{1{reduce8_payload_values_1_4[16]}}, reduce8_payload_values_1_4};
  assign _zz_reduce4_w_values_1_2_1 = {{1{reduce8_payload_values_1_5[16]}}, reduce8_payload_values_1_5};
  assign _zz_reduce4_w_values_1_3 = {{1{reduce8_payload_values_1_6[16]}}, reduce8_payload_values_1_6};
  assign _zz_reduce4_w_values_1_3_1 = {{1{reduce8_payload_values_1_7[16]}}, reduce8_payload_values_1_7};
  assign _zz_reduce4_w_values_2_0 = {{1{reduce8_payload_values_2_0[16]}}, reduce8_payload_values_2_0};
  assign _zz_reduce4_w_values_2_0_1 = {{1{reduce8_payload_values_2_1[16]}}, reduce8_payload_values_2_1};
  assign _zz_reduce4_w_values_2_1 = {{1{reduce8_payload_values_2_2[16]}}, reduce8_payload_values_2_2};
  assign _zz_reduce4_w_values_2_1_1 = {{1{reduce8_payload_values_2_3[16]}}, reduce8_payload_values_2_3};
  assign _zz_reduce4_w_values_2_2 = {{1{reduce8_payload_values_2_4[16]}}, reduce8_payload_values_2_4};
  assign _zz_reduce4_w_values_2_2_1 = {{1{reduce8_payload_values_2_5[16]}}, reduce8_payload_values_2_5};
  assign _zz_reduce4_w_values_2_3 = {{1{reduce8_payload_values_2_6[16]}}, reduce8_payload_values_2_6};
  assign _zz_reduce4_w_values_2_3_1 = {{1{reduce8_payload_values_2_7[16]}}, reduce8_payload_values_2_7};
  assign _zz_reduce4_w_values_3_0 = {{1{reduce8_payload_values_3_0[16]}}, reduce8_payload_values_3_0};
  assign _zz_reduce4_w_values_3_0_1 = {{1{reduce8_payload_values_3_1[16]}}, reduce8_payload_values_3_1};
  assign _zz_reduce4_w_values_3_1 = {{1{reduce8_payload_values_3_2[16]}}, reduce8_payload_values_3_2};
  assign _zz_reduce4_w_values_3_1_1 = {{1{reduce8_payload_values_3_3[16]}}, reduce8_payload_values_3_3};
  assign _zz_reduce4_w_values_3_2 = {{1{reduce8_payload_values_3_4[16]}}, reduce8_payload_values_3_4};
  assign _zz_reduce4_w_values_3_2_1 = {{1{reduce8_payload_values_3_5[16]}}, reduce8_payload_values_3_5};
  assign _zz_reduce4_w_values_3_3 = {{1{reduce8_payload_values_3_6[16]}}, reduce8_payload_values_3_6};
  assign _zz_reduce4_w_values_3_3_1 = {{1{reduce8_payload_values_3_7[16]}}, reduce8_payload_values_3_7};
  assign _zz_reduce2_w_values_0_0 = {{1{reduce4_payload_values_0_0[17]}}, reduce4_payload_values_0_0};
  assign _zz_reduce2_w_values_0_0_1 = {{1{reduce4_payload_values_0_1[17]}}, reduce4_payload_values_0_1};
  assign _zz_reduce2_w_values_0_1 = {{1{reduce4_payload_values_0_2[17]}}, reduce4_payload_values_0_2};
  assign _zz_reduce2_w_values_0_1_1 = {{1{reduce4_payload_values_0_3[17]}}, reduce4_payload_values_0_3};
  assign _zz_reduce2_w_values_1_0 = {{1{reduce4_payload_values_1_0[17]}}, reduce4_payload_values_1_0};
  assign _zz_reduce2_w_values_1_0_1 = {{1{reduce4_payload_values_1_1[17]}}, reduce4_payload_values_1_1};
  assign _zz_reduce2_w_values_1_1 = {{1{reduce4_payload_values_1_2[17]}}, reduce4_payload_values_1_2};
  assign _zz_reduce2_w_values_1_1_1 = {{1{reduce4_payload_values_1_3[17]}}, reduce4_payload_values_1_3};
  assign _zz_reduce2_w_values_2_0 = {{1{reduce4_payload_values_2_0[17]}}, reduce4_payload_values_2_0};
  assign _zz_reduce2_w_values_2_0_1 = {{1{reduce4_payload_values_2_1[17]}}, reduce4_payload_values_2_1};
  assign _zz_reduce2_w_values_2_1 = {{1{reduce4_payload_values_2_2[17]}}, reduce4_payload_values_2_2};
  assign _zz_reduce2_w_values_2_1_1 = {{1{reduce4_payload_values_2_3[17]}}, reduce4_payload_values_2_3};
  assign _zz_reduce2_w_values_3_0 = {{1{reduce4_payload_values_3_0[17]}}, reduce4_payload_values_3_0};
  assign _zz_reduce2_w_values_3_0_1 = {{1{reduce4_payload_values_3_1[17]}}, reduce4_payload_values_3_1};
  assign _zz_reduce2_w_values_3_1 = {{1{reduce4_payload_values_3_2[17]}}, reduce4_payload_values_3_2};
  assign _zz_reduce2_w_values_3_1_1 = {{1{reduce4_payload_values_3_3[17]}}, reduce4_payload_values_3_3};
  assign _zz_dot_w_values_0_0 = {{1{reduce2_payload_values_0_0[18]}}, reduce2_payload_values_0_0};
  assign _zz_dot_w_values_0_0_1 = {{1{reduce2_payload_values_0_1[18]}}, reduce2_payload_values_0_1};
  assign _zz_dot_w_values_1_0 = {{1{reduce2_payload_values_1_0[18]}}, reduce2_payload_values_1_0};
  assign _zz_dot_w_values_1_0_1 = {{1{reduce2_payload_values_1_1[18]}}, reduce2_payload_values_1_1};
  assign _zz_dot_w_values_2_0 = {{1{reduce2_payload_values_2_0[18]}}, reduce2_payload_values_2_0};
  assign _zz_dot_w_values_2_0_1 = {{1{reduce2_payload_values_2_1[18]}}, reduce2_payload_values_2_1};
  assign _zz_dot_w_values_3_0 = {{1{reduce2_payload_values_3_0[18]}}, reduce2_payload_values_3_0};
  assign _zz_dot_w_values_3_0_1 = {{1{reduce2_payload_values_3_1[18]}}, reduce2_payload_values_3_1};
  assign _zz_localPixel_w = (dot_payload_tag_pixel - tileBase_r);
  assign _zz__zz_quantRequest_payload_mac_0 = (dot_payload_tag_first ? 32'h0 : _zz__zz_quantRequest_payload_mac_0_1);
  assign _zz__zz_quantRequest_payload_mac_0_2 = {{12{dot_payload_values_0_0[19]}}, dot_payload_values_0_0};
  assign _zz__zz_quantRequest_payload_mac_1 = (dot_payload_tag_first ? 32'h0 : _zz__zz_quantRequest_payload_mac_1_1);
  assign _zz__zz_quantRequest_payload_mac_1_2 = {{12{dot_payload_values_1_0[19]}}, dot_payload_values_1_0};
  assign _zz__zz_quantRequest_payload_mac_2 = (dot_payload_tag_first ? 32'h0 : _zz__zz_quantRequest_payload_mac_2_1);
  assign _zz__zz_quantRequest_payload_mac_2_2 = {{12{dot_payload_values_2_0[19]}}, dot_payload_values_2_0};
  assign _zz__zz_quantRequest_payload_mac_3 = (dot_payload_tag_first ? 32'h0 : _zz__zz_quantRequest_payload_mac_3_1);
  assign _zz__zz_quantRequest_payload_mac_3_2 = {{12{dot_payload_values_3_0[19]}}, dot_payload_values_3_0};
  assign _zz_paramMem_0_port = paramCount_r[6:0];
  assign _zz_paramMem_1_port = paramCount_r[6:0];
  assign _zz_paramMem_2_port = paramCount_r[6:0];
  assign _zz_paramMem_3_port = paramCount_r[6:0];
  assign _zz_lastTileOutput_w = {1'd0, io_output_o_payload_group};
  assign _zz_lastTileOutput_w_1 = (ogCount_r - 8'h01);
  assign _zz_lastTileOutput_w_2 = (_zz_lastTileOutput_w_3 - 19'h00001);
  assign _zz_lastTileOutput_w_3 = (tileBase_r + _zz_lastTileOutput_w_4);
  assign _zz_lastTileOutput_w_4 = {14'd0, tileCount_r};
  assign _zz__zz_tileCount_r = (run_r_pixels - tileBase_r);
  assign _zz__zz_tileCount_r_1 = {14'd0, tileCount_r};
  assign _zz_tileBase_r = {14'd0, tileCount_r};
  assign _zz_tileCount_r_2 = _zz_tileCount_r[4:0];
  assign _zz_paramMem_0_port_1 = io_params_i_payload[127 : 0];
  assign _zz_paramMem_1_port_1 = io_params_i_payload[255 : 128];
  assign _zz_paramMem_2_port_1 = io_params_i_payload[383 : 256];
  assign _zz_paramMem_3_port_1 = io_params_i_payload[511 : 384];
  always @(posedge clk) begin
    if(io_rsp_i_fire) begin
      inputMem[fillAddress_w] <= io_rsp_i_payload;
    end
  end

  always @(posedge clk) begin
    if(request_fire) begin
      inputMem_spinal_port1 <= inputMem[inputAddress_w];
    end
  end

  always @(posedge clk) begin
    if(io_params_i_fire) begin
      paramMem_0[_zz_paramMem_0_port] <= _zz_paramMem_0_port_1;
    end
  end

  always @(posedge clk) begin
    if(quantRequest_fire) begin
      paramMem_0_spinal_port1 <= paramMem_0[_zz_params_w_0];
    end
  end

  always @(posedge clk) begin
    if(io_params_i_fire) begin
      paramMem_1[_zz_paramMem_1_port] <= _zz_paramMem_1_port_1;
    end
  end

  always @(posedge clk) begin
    if(quantRequest_fire) begin
      paramMem_1_spinal_port1 <= paramMem_1[_zz_params_w_1];
    end
  end

  always @(posedge clk) begin
    if(io_params_i_fire) begin
      paramMem_2[_zz_paramMem_2_port] <= _zz_paramMem_2_port_1;
    end
  end

  always @(posedge clk) begin
    if(quantRequest_fire) begin
      paramMem_2_spinal_port1 <= paramMem_2[_zz_params_w_2];
    end
  end

  always @(posedge clk) begin
    if(io_params_i_fire) begin
      paramMem_3[_zz_paramMem_3_port] <= _zz_paramMem_3_port_1;
    end
  end

  always @(posedge clk) begin
    if(quantRequest_fire) begin
      paramMem_3_spinal_port1 <= paramMem_3[_zz_params_w_3];
    end
  end

  pw_weight_uram pwWeightUram (
    .clka  (clk                        ), //i
    .ena   (io_weights_i_fire          ), //i
    .wea   (pwWeightUram_wea           ), //i
    .addra (weightCount_r[12:0]        ), //i
    .dina  (io_weights_i_payload[511:0]), //i
    .clkb  (clk                        ), //i
    .enb   (request_fire               ), //i
    .addrb (weightAddress_w[12:0]      ), //i
    .doutb (pwWeightUram_doutb[511:0]  )  //o
  );
  PwRequant requant (
    .io_input_i_valid                  (quantResponse_translated_valid                     ), //i
    .io_input_i_ready                  (requant_io_input_i_ready                           ), //o
    .io_input_i_payload_tag_pixel      (quantResponse_translated_payload_tag_pixel[18:0]   ), //i
    .io_input_i_payload_tag_group      (quantResponse_translated_payload_tag_group[6:0]    ), //i
    .io_input_i_payload_tag_mask       (quantResponse_translated_payload_tag_mask[3:0]     ), //i
    .io_input_i_payload_tag_first      (quantResponse_translated_payload_tag_first         ), //i
    .io_input_i_payload_tag_finalInput (quantResponse_translated_payload_tag_finalInput    ), //i
    .io_input_i_payload_tag_tileLast   (quantResponse_translated_payload_tag_tileLast      ), //i
    .io_input_i_payload_tag_last       (quantResponse_translated_payload_tag_last          ), //i
    .io_input_i_payload_raw            (quantResponse_translated_payload_raw               ), //i
    .io_input_i_payload_int16          (quantResponse_translated_payload_int16             ), //i
    .io_input_i_payload_shift          (quantResponse_translated_payload_shift[5:0]        ), //i
    .io_input_i_payload_mac_0          (quantResponse_translated_payload_mac_0[31:0]       ), //i
    .io_input_i_payload_mac_1          (quantResponse_translated_payload_mac_1[31:0]       ), //i
    .io_input_i_payload_mac_2          (quantResponse_translated_payload_mac_2[31:0]       ), //i
    .io_input_i_payload_mac_3          (quantResponse_translated_payload_mac_3[31:0]       ), //i
    .io_input_i_payload_multiplier_0   (quantResponse_translated_payload_multiplier_0[31:0]), //i
    .io_input_i_payload_multiplier_1   (quantResponse_translated_payload_multiplier_1[31:0]), //i
    .io_input_i_payload_multiplier_2   (quantResponse_translated_payload_multiplier_2[31:0]), //i
    .io_input_i_payload_multiplier_3   (quantResponse_translated_payload_multiplier_3[31:0]), //i
    .io_input_i_payload_bias_0         (quantResponse_translated_payload_bias_0[63:0]      ), //i
    .io_input_i_payload_bias_1         (quantResponse_translated_payload_bias_1[63:0]      ), //i
    .io_input_i_payload_bias_2         (quantResponse_translated_payload_bias_2[63:0]      ), //i
    .io_input_i_payload_bias_3         (quantResponse_translated_payload_bias_3[63:0]      ), //i
    .io_input_i_payload_lower_0        (quantResponse_translated_payload_lower_0[15:0]     ), //i
    .io_input_i_payload_lower_1        (quantResponse_translated_payload_lower_1[15:0]     ), //i
    .io_input_i_payload_lower_2        (quantResponse_translated_payload_lower_2[15:0]     ), //i
    .io_input_i_payload_lower_3        (quantResponse_translated_payload_lower_3[15:0]     ), //i
    .io_input_i_payload_upper_0        (quantResponse_translated_payload_upper_0[15:0]     ), //i
    .io_input_i_payload_upper_1        (quantResponse_translated_payload_upper_1[15:0]     ), //i
    .io_input_i_payload_upper_2        (quantResponse_translated_payload_upper_2[15:0]     ), //i
    .io_input_i_payload_upper_3        (quantResponse_translated_payload_upper_3[15:0]     ), //i
    .io_output_o_valid                 (requant_io_output_o_valid                          ), //o
    .io_output_o_ready                 (io_output_o_ready                                  ), //i
    .io_output_o_payload_pixel         (requant_io_output_o_payload_pixel[18:0]            ), //o
    .io_output_o_payload_group         (requant_io_output_o_payload_group[6:0]             ), //o
    .io_output_o_payload_mask          (requant_io_output_o_payload_mask[3:0]              ), //o
    .io_output_o_payload_last          (requant_io_output_o_payload_last                   ), //o
    .io_output_o_payload_raw           (requant_io_output_o_payload_raw                    ), //o
    .io_output_o_payload_int16         (requant_io_output_o_payload_int16                  ), //o
    .io_output_o_payload_mac_0         (requant_io_output_o_payload_mac_0[31:0]            ), //o
    .io_output_o_payload_mac_1         (requant_io_output_o_payload_mac_1[31:0]            ), //o
    .io_output_o_payload_mac_2         (requant_io_output_o_payload_mac_2[31:0]            ), //o
    .io_output_o_payload_mac_3         (requant_io_output_o_payload_mac_3[31:0]            ), //o
    .io_output_o_payload_q_0           (requant_io_output_o_payload_q_0[15:0]              ), //o
    .io_output_o_payload_q_1           (requant_io_output_o_payload_q_1[15:0]              ), //o
    .io_output_o_payload_q_2           (requant_io_output_o_payload_q_2[15:0]              ), //o
    .io_output_o_payload_q_3           (requant_io_output_o_payload_q_3[15:0]              ), //o
    .clk                               (clk                                                ), //i
    .resetn                            (resetn                                             )  //i
  );
  always @(*) begin
    case(localPixel_w)
      4'b0000 : begin
        _zz__zz_quantRequest_payload_mac_0_1 = acc_r_0_0;
        _zz__zz_quantRequest_payload_mac_1_1 = acc_r_1_0;
        _zz__zz_quantRequest_payload_mac_2_1 = acc_r_2_0;
        _zz__zz_quantRequest_payload_mac_3_1 = acc_r_3_0;
      end
      4'b0001 : begin
        _zz__zz_quantRequest_payload_mac_0_1 = acc_r_0_1;
        _zz__zz_quantRequest_payload_mac_1_1 = acc_r_1_1;
        _zz__zz_quantRequest_payload_mac_2_1 = acc_r_2_1;
        _zz__zz_quantRequest_payload_mac_3_1 = acc_r_3_1;
      end
      4'b0010 : begin
        _zz__zz_quantRequest_payload_mac_0_1 = acc_r_0_2;
        _zz__zz_quantRequest_payload_mac_1_1 = acc_r_1_2;
        _zz__zz_quantRequest_payload_mac_2_1 = acc_r_2_2;
        _zz__zz_quantRequest_payload_mac_3_1 = acc_r_3_2;
      end
      4'b0011 : begin
        _zz__zz_quantRequest_payload_mac_0_1 = acc_r_0_3;
        _zz__zz_quantRequest_payload_mac_1_1 = acc_r_1_3;
        _zz__zz_quantRequest_payload_mac_2_1 = acc_r_2_3;
        _zz__zz_quantRequest_payload_mac_3_1 = acc_r_3_3;
      end
      4'b0100 : begin
        _zz__zz_quantRequest_payload_mac_0_1 = acc_r_0_4;
        _zz__zz_quantRequest_payload_mac_1_1 = acc_r_1_4;
        _zz__zz_quantRequest_payload_mac_2_1 = acc_r_2_4;
        _zz__zz_quantRequest_payload_mac_3_1 = acc_r_3_4;
      end
      4'b0101 : begin
        _zz__zz_quantRequest_payload_mac_0_1 = acc_r_0_5;
        _zz__zz_quantRequest_payload_mac_1_1 = acc_r_1_5;
        _zz__zz_quantRequest_payload_mac_2_1 = acc_r_2_5;
        _zz__zz_quantRequest_payload_mac_3_1 = acc_r_3_5;
      end
      4'b0110 : begin
        _zz__zz_quantRequest_payload_mac_0_1 = acc_r_0_6;
        _zz__zz_quantRequest_payload_mac_1_1 = acc_r_1_6;
        _zz__zz_quantRequest_payload_mac_2_1 = acc_r_2_6;
        _zz__zz_quantRequest_payload_mac_3_1 = acc_r_3_6;
      end
      4'b0111 : begin
        _zz__zz_quantRequest_payload_mac_0_1 = acc_r_0_7;
        _zz__zz_quantRequest_payload_mac_1_1 = acc_r_1_7;
        _zz__zz_quantRequest_payload_mac_2_1 = acc_r_2_7;
        _zz__zz_quantRequest_payload_mac_3_1 = acc_r_3_7;
      end
      4'b1000 : begin
        _zz__zz_quantRequest_payload_mac_0_1 = acc_r_0_8;
        _zz__zz_quantRequest_payload_mac_1_1 = acc_r_1_8;
        _zz__zz_quantRequest_payload_mac_2_1 = acc_r_2_8;
        _zz__zz_quantRequest_payload_mac_3_1 = acc_r_3_8;
      end
      4'b1001 : begin
        _zz__zz_quantRequest_payload_mac_0_1 = acc_r_0_9;
        _zz__zz_quantRequest_payload_mac_1_1 = acc_r_1_9;
        _zz__zz_quantRequest_payload_mac_2_1 = acc_r_2_9;
        _zz__zz_quantRequest_payload_mac_3_1 = acc_r_3_9;
      end
      4'b1010 : begin
        _zz__zz_quantRequest_payload_mac_0_1 = acc_r_0_10;
        _zz__zz_quantRequest_payload_mac_1_1 = acc_r_1_10;
        _zz__zz_quantRequest_payload_mac_2_1 = acc_r_2_10;
        _zz__zz_quantRequest_payload_mac_3_1 = acc_r_3_10;
      end
      4'b1011 : begin
        _zz__zz_quantRequest_payload_mac_0_1 = acc_r_0_11;
        _zz__zz_quantRequest_payload_mac_1_1 = acc_r_1_11;
        _zz__zz_quantRequest_payload_mac_2_1 = acc_r_2_11;
        _zz__zz_quantRequest_payload_mac_3_1 = acc_r_3_11;
      end
      4'b1100 : begin
        _zz__zz_quantRequest_payload_mac_0_1 = acc_r_0_12;
        _zz__zz_quantRequest_payload_mac_1_1 = acc_r_1_12;
        _zz__zz_quantRequest_payload_mac_2_1 = acc_r_2_12;
        _zz__zz_quantRequest_payload_mac_3_1 = acc_r_3_12;
      end
      4'b1101 : begin
        _zz__zz_quantRequest_payload_mac_0_1 = acc_r_0_13;
        _zz__zz_quantRequest_payload_mac_1_1 = acc_r_1_13;
        _zz__zz_quantRequest_payload_mac_2_1 = acc_r_2_13;
        _zz__zz_quantRequest_payload_mac_3_1 = acc_r_3_13;
      end
      4'b1110 : begin
        _zz__zz_quantRequest_payload_mac_0_1 = acc_r_0_14;
        _zz__zz_quantRequest_payload_mac_1_1 = acc_r_1_14;
        _zz__zz_quantRequest_payload_mac_2_1 = acc_r_2_14;
        _zz__zz_quantRequest_payload_mac_3_1 = acc_r_3_14;
      end
      default : begin
        _zz__zz_quantRequest_payload_mac_0_1 = acc_r_0_15;
        _zz__zz_quantRequest_payload_mac_1_1 = acc_r_1_15;
        _zz__zz_quantRequest_payload_mac_2_1 = acc_r_2_15;
        _zz__zz_quantRequest_payload_mac_3_1 = acc_r_3_15;
      end
    endcase
  end

  assign IDLE = 3'b000;
  assign LOAD = 3'b001;
  assign READY = 3'b010;
  assign FILL = 3'b011;
  assign ISSUE = 3'b100;
  assign DRAIN = 3'b101;
  assign io_done_o = done_r;
  assign io_busy_o = ((state_r != IDLE) && (state_r != READY));
  assign validConfig_w = (((((((io_cfg_i_payload_cin != 10'h0) && (io_cfg_i_payload_cin <= 10'h300)) && (io_cfg_i_payload_cout != 10'h0)) && (io_cfg_i_payload_cout <= 10'h200)) && (io_cfg_i_payload_pixels != 19'h0)) && (io_cfg_i_payload_pixels <= 19'h40000)) && (io_cfg_i_payload_shift <= 6'h3e));
  assign io_cfg_i_ready = (((state_r == IDLE) || (state_r == READY)) && validConfig_w);
  assign cfgIg_w = (_zz_cfgIg_w >>> 3'd4);
  assign cfgOg_w = (_zz_cfgOg_w >>> 2'd2);
  assign io_cfg_i_fire = (io_cfg_i_valid && io_cfg_i_ready);
  assign io_weights_i_ready = ((state_r == LOAD) && (weightCount_r < weightTotal_r));
  assign io_params_i_ready = ((state_r == LOAD) && (paramCount_r < ogCount_r));
  assign io_weights_i_fire = (io_weights_i_valid && io_weights_i_ready);
  assign io_params_i_fire = (io_params_i_valid && io_params_i_ready);
  assign when_PwMac_l181 = (((state_r == LOAD) && (weightCount_r == weightTotal_r)) && (paramCount_r == ogCount_r));
  assign io_start_i_ready = ((state_r == READY) && (! io_cfg_i_valid));
  assign io_start_i_fire = (io_start_i_valid && io_start_i_ready);
  assign io_rd_o_valid = ((state_r == FILL) && (! waiting_r));
  assign io_rd_o_payload = {7'd0, _zz_io_rd_o_payload};
  assign io_rsp_i_ready = ((state_r == FILL) && waiting_r);
  assign io_rd_o_fire = (io_rd_o_valid && io_rd_o_ready);
  assign fillAddress_w = _zz_fillAddress_w[9:0];
  assign io_rsp_i_fire = (io_rsp_i_valid && io_rsp_i_ready);
  assign when_PwMac_l204 = (fillPixel_r == _zz_when_PwMac_l204);
  assign when_PwMac_l206 = (fillGroup_r == _zz_when_PwMac_l206);
  assign request_valid = (state_r == ISSUE);
  assign request_payload_tag_pixel = (tileBase_r + _zz_request_payload_tag_pixel);
  assign request_payload_tag_group = issueGroup_r;
  always @(*) begin
    request_payload_tag_mask[0] = (_zz_request_payload_tag_mask < _zz_request_payload_tag_mask_3);
    request_payload_tag_mask[1] = (_zz_request_payload_tag_mask_4 < _zz_request_payload_tag_mask_7);
    request_payload_tag_mask[2] = (_zz_request_payload_tag_mask_8 < _zz_request_payload_tag_mask_11);
    request_payload_tag_mask[3] = (_zz_request_payload_tag_mask_12 < _zz_request_payload_tag_mask_15);
  end

  assign request_payload_tag_first = (issueInput_r == 6'h0);
  assign request_payload_tag_finalInput = (issueInput_r == _zz_request_payload_tag_finalInput);
  assign request_payload_tag_tileLast = ((_zz_request_payload_tag_tileLast == _zz_request_payload_tag_tileLast_1) && (issuePixel_r == _zz_request_payload_tag_tileLast_2));
  assign request_payload_tag_last = (request_payload_tag_tileLast && (_zz_request_payload_tag_last == run_r_pixels));
  assign request_payload_inputGroup = issueInput_r;
  always @(*) begin
    request_ready = response_ready;
    if(when_Stream_l477) begin
      request_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! response_valid);
  assign response_valid = request_rValid;
  assign response_payload_tag_pixel = request_rData_tag_pixel;
  assign response_payload_tag_group = request_rData_tag_group;
  assign response_payload_tag_mask = request_rData_tag_mask;
  assign response_payload_tag_first = request_rData_tag_first;
  assign response_payload_tag_finalInput = request_rData_tag_finalInput;
  assign response_payload_tag_tileLast = request_rData_tag_tileLast;
  assign response_payload_tag_last = request_rData_tag_last;
  assign response_payload_inputGroup = request_rData_inputGroup;
  assign inputAddress_w = _zz_inputAddress_w[9:0];
  assign request_fire = (request_valid && request_ready);
  assign inputData_w = inputMem_spinal_port1;
  assign weightAddress_w = (_zz_weightAddress_w + _zz_weightAddress_w_1);
  assign pwWeightUram_wea = io_weights_i_fire;
  assign weights_w_0 = pwWeightUram_doutb[127 : 0];
  assign weights_w_1 = pwWeightUram_doutb[255 : 128];
  assign weights_w_2 = pwWeightUram_doutb[383 : 256];
  assign weights_w_3 = pwWeightUram_doutb[511 : 384];
  assign when_PwMac_l252 = (issuePixel_r == _zz_when_PwMac_l252);
  assign when_PwMac_l254 = (issueInput_r == _zz_when_PwMac_l254);
  assign when_PwMac_l256 = (_zz_when_PwMac_l256 == _zz_when_PwMac_l256_1);
  assign products_w_tag_pixel = response_payload_tag_pixel;
  assign products_w_tag_group = response_payload_tag_group;
  assign products_w_tag_mask = response_payload_tag_mask;
  assign products_w_tag_first = response_payload_tag_first;
  assign products_w_tag_finalInput = response_payload_tag_finalInput;
  assign products_w_tag_tileLast = response_payload_tag_tileLast;
  assign products_w_tag_last = response_payload_tag_last;
  assign products_w_values_0_0 = ($signed(_zz_products_w_values_0_0) * $signed(_zz_products_w_values_0_0_6));
  assign products_w_values_0_1 = ($signed(_zz_products_w_values_0_1) * $signed(_zz_products_w_values_0_1_6));
  assign products_w_values_0_2 = ($signed(_zz_products_w_values_0_2) * $signed(_zz_products_w_values_0_2_6));
  assign products_w_values_0_3 = ($signed(_zz_products_w_values_0_3) * $signed(_zz_products_w_values_0_3_6));
  assign products_w_values_0_4 = ($signed(_zz_products_w_values_0_4) * $signed(_zz_products_w_values_0_4_6));
  assign products_w_values_0_5 = ($signed(_zz_products_w_values_0_5) * $signed(_zz_products_w_values_0_5_6));
  assign products_w_values_0_6 = ($signed(_zz_products_w_values_0_6) * $signed(_zz_products_w_values_0_6_6));
  assign products_w_values_0_7 = ($signed(_zz_products_w_values_0_7) * $signed(_zz_products_w_values_0_7_6));
  assign products_w_values_0_8 = ($signed(_zz_products_w_values_0_8) * $signed(_zz_products_w_values_0_8_6));
  assign products_w_values_0_9 = ($signed(_zz_products_w_values_0_9) * $signed(_zz_products_w_values_0_9_6));
  assign products_w_values_0_10 = ($signed(_zz_products_w_values_0_10) * $signed(_zz_products_w_values_0_10_6));
  assign products_w_values_0_11 = ($signed(_zz_products_w_values_0_11) * $signed(_zz_products_w_values_0_11_6));
  assign products_w_values_0_12 = ($signed(_zz_products_w_values_0_12) * $signed(_zz_products_w_values_0_12_6));
  assign products_w_values_0_13 = ($signed(_zz_products_w_values_0_13) * $signed(_zz_products_w_values_0_13_6));
  assign products_w_values_0_14 = ($signed(_zz_products_w_values_0_14) * $signed(_zz_products_w_values_0_14_6));
  assign products_w_values_0_15 = ($signed(_zz_products_w_values_0_15) * $signed(_zz_products_w_values_0_15_6));
  assign products_w_values_1_0 = ($signed(_zz_products_w_values_1_0) * $signed(_zz_products_w_values_1_0_6));
  assign products_w_values_1_1 = ($signed(_zz_products_w_values_1_1) * $signed(_zz_products_w_values_1_1_6));
  assign products_w_values_1_2 = ($signed(_zz_products_w_values_1_2) * $signed(_zz_products_w_values_1_2_6));
  assign products_w_values_1_3 = ($signed(_zz_products_w_values_1_3) * $signed(_zz_products_w_values_1_3_6));
  assign products_w_values_1_4 = ($signed(_zz_products_w_values_1_4) * $signed(_zz_products_w_values_1_4_6));
  assign products_w_values_1_5 = ($signed(_zz_products_w_values_1_5) * $signed(_zz_products_w_values_1_5_6));
  assign products_w_values_1_6 = ($signed(_zz_products_w_values_1_6) * $signed(_zz_products_w_values_1_6_6));
  assign products_w_values_1_7 = ($signed(_zz_products_w_values_1_7) * $signed(_zz_products_w_values_1_7_6));
  assign products_w_values_1_8 = ($signed(_zz_products_w_values_1_8) * $signed(_zz_products_w_values_1_8_6));
  assign products_w_values_1_9 = ($signed(_zz_products_w_values_1_9) * $signed(_zz_products_w_values_1_9_6));
  assign products_w_values_1_10 = ($signed(_zz_products_w_values_1_10) * $signed(_zz_products_w_values_1_10_6));
  assign products_w_values_1_11 = ($signed(_zz_products_w_values_1_11) * $signed(_zz_products_w_values_1_11_6));
  assign products_w_values_1_12 = ($signed(_zz_products_w_values_1_12) * $signed(_zz_products_w_values_1_12_6));
  assign products_w_values_1_13 = ($signed(_zz_products_w_values_1_13) * $signed(_zz_products_w_values_1_13_6));
  assign products_w_values_1_14 = ($signed(_zz_products_w_values_1_14) * $signed(_zz_products_w_values_1_14_6));
  assign products_w_values_1_15 = ($signed(_zz_products_w_values_1_15) * $signed(_zz_products_w_values_1_15_6));
  assign products_w_values_2_0 = ($signed(_zz_products_w_values_2_0) * $signed(_zz_products_w_values_2_0_6));
  assign products_w_values_2_1 = ($signed(_zz_products_w_values_2_1) * $signed(_zz_products_w_values_2_1_6));
  assign products_w_values_2_2 = ($signed(_zz_products_w_values_2_2) * $signed(_zz_products_w_values_2_2_6));
  assign products_w_values_2_3 = ($signed(_zz_products_w_values_2_3) * $signed(_zz_products_w_values_2_3_6));
  assign products_w_values_2_4 = ($signed(_zz_products_w_values_2_4) * $signed(_zz_products_w_values_2_4_6));
  assign products_w_values_2_5 = ($signed(_zz_products_w_values_2_5) * $signed(_zz_products_w_values_2_5_6));
  assign products_w_values_2_6 = ($signed(_zz_products_w_values_2_6) * $signed(_zz_products_w_values_2_6_6));
  assign products_w_values_2_7 = ($signed(_zz_products_w_values_2_7) * $signed(_zz_products_w_values_2_7_6));
  assign products_w_values_2_8 = ($signed(_zz_products_w_values_2_8) * $signed(_zz_products_w_values_2_8_6));
  assign products_w_values_2_9 = ($signed(_zz_products_w_values_2_9) * $signed(_zz_products_w_values_2_9_6));
  assign products_w_values_2_10 = ($signed(_zz_products_w_values_2_10) * $signed(_zz_products_w_values_2_10_6));
  assign products_w_values_2_11 = ($signed(_zz_products_w_values_2_11) * $signed(_zz_products_w_values_2_11_6));
  assign products_w_values_2_12 = ($signed(_zz_products_w_values_2_12) * $signed(_zz_products_w_values_2_12_6));
  assign products_w_values_2_13 = ($signed(_zz_products_w_values_2_13) * $signed(_zz_products_w_values_2_13_6));
  assign products_w_values_2_14 = ($signed(_zz_products_w_values_2_14) * $signed(_zz_products_w_values_2_14_6));
  assign products_w_values_2_15 = ($signed(_zz_products_w_values_2_15) * $signed(_zz_products_w_values_2_15_6));
  assign products_w_values_3_0 = ($signed(_zz_products_w_values_3_0) * $signed(_zz_products_w_values_3_0_6));
  assign products_w_values_3_1 = ($signed(_zz_products_w_values_3_1) * $signed(_zz_products_w_values_3_1_6));
  assign products_w_values_3_2 = ($signed(_zz_products_w_values_3_2) * $signed(_zz_products_w_values_3_2_6));
  assign products_w_values_3_3 = ($signed(_zz_products_w_values_3_3) * $signed(_zz_products_w_values_3_3_6));
  assign products_w_values_3_4 = ($signed(_zz_products_w_values_3_4) * $signed(_zz_products_w_values_3_4_6));
  assign products_w_values_3_5 = ($signed(_zz_products_w_values_3_5) * $signed(_zz_products_w_values_3_5_6));
  assign products_w_values_3_6 = ($signed(_zz_products_w_values_3_6) * $signed(_zz_products_w_values_3_6_6));
  assign products_w_values_3_7 = ($signed(_zz_products_w_values_3_7) * $signed(_zz_products_w_values_3_7_6));
  assign products_w_values_3_8 = ($signed(_zz_products_w_values_3_8) * $signed(_zz_products_w_values_3_8_6));
  assign products_w_values_3_9 = ($signed(_zz_products_w_values_3_9) * $signed(_zz_products_w_values_3_9_6));
  assign products_w_values_3_10 = ($signed(_zz_products_w_values_3_10) * $signed(_zz_products_w_values_3_10_6));
  assign products_w_values_3_11 = ($signed(_zz_products_w_values_3_11) * $signed(_zz_products_w_values_3_11_6));
  assign products_w_values_3_12 = ($signed(_zz_products_w_values_3_12) * $signed(_zz_products_w_values_3_12_6));
  assign products_w_values_3_13 = ($signed(_zz_products_w_values_3_13) * $signed(_zz_products_w_values_3_13_6));
  assign products_w_values_3_14 = ($signed(_zz_products_w_values_3_14) * $signed(_zz_products_w_values_3_14_6));
  assign products_w_values_3_15 = ($signed(_zz_products_w_values_3_15) * $signed(_zz_products_w_values_3_15_6));
  assign response_translated_valid = response_valid;
  assign response_ready = response_translated_ready;
  assign response_translated_payload_tag_pixel = products_w_tag_pixel;
  assign response_translated_payload_tag_group = products_w_tag_group;
  assign response_translated_payload_tag_mask = products_w_tag_mask;
  assign response_translated_payload_tag_first = products_w_tag_first;
  assign response_translated_payload_tag_finalInput = products_w_tag_finalInput;
  assign response_translated_payload_tag_tileLast = products_w_tag_tileLast;
  assign response_translated_payload_tag_last = products_w_tag_last;
  assign response_translated_payload_values_0_0 = products_w_values_0_0;
  assign response_translated_payload_values_0_1 = products_w_values_0_1;
  assign response_translated_payload_values_0_2 = products_w_values_0_2;
  assign response_translated_payload_values_0_3 = products_w_values_0_3;
  assign response_translated_payload_values_0_4 = products_w_values_0_4;
  assign response_translated_payload_values_0_5 = products_w_values_0_5;
  assign response_translated_payload_values_0_6 = products_w_values_0_6;
  assign response_translated_payload_values_0_7 = products_w_values_0_7;
  assign response_translated_payload_values_0_8 = products_w_values_0_8;
  assign response_translated_payload_values_0_9 = products_w_values_0_9;
  assign response_translated_payload_values_0_10 = products_w_values_0_10;
  assign response_translated_payload_values_0_11 = products_w_values_0_11;
  assign response_translated_payload_values_0_12 = products_w_values_0_12;
  assign response_translated_payload_values_0_13 = products_w_values_0_13;
  assign response_translated_payload_values_0_14 = products_w_values_0_14;
  assign response_translated_payload_values_0_15 = products_w_values_0_15;
  assign response_translated_payload_values_1_0 = products_w_values_1_0;
  assign response_translated_payload_values_1_1 = products_w_values_1_1;
  assign response_translated_payload_values_1_2 = products_w_values_1_2;
  assign response_translated_payload_values_1_3 = products_w_values_1_3;
  assign response_translated_payload_values_1_4 = products_w_values_1_4;
  assign response_translated_payload_values_1_5 = products_w_values_1_5;
  assign response_translated_payload_values_1_6 = products_w_values_1_6;
  assign response_translated_payload_values_1_7 = products_w_values_1_7;
  assign response_translated_payload_values_1_8 = products_w_values_1_8;
  assign response_translated_payload_values_1_9 = products_w_values_1_9;
  assign response_translated_payload_values_1_10 = products_w_values_1_10;
  assign response_translated_payload_values_1_11 = products_w_values_1_11;
  assign response_translated_payload_values_1_12 = products_w_values_1_12;
  assign response_translated_payload_values_1_13 = products_w_values_1_13;
  assign response_translated_payload_values_1_14 = products_w_values_1_14;
  assign response_translated_payload_values_1_15 = products_w_values_1_15;
  assign response_translated_payload_values_2_0 = products_w_values_2_0;
  assign response_translated_payload_values_2_1 = products_w_values_2_1;
  assign response_translated_payload_values_2_2 = products_w_values_2_2;
  assign response_translated_payload_values_2_3 = products_w_values_2_3;
  assign response_translated_payload_values_2_4 = products_w_values_2_4;
  assign response_translated_payload_values_2_5 = products_w_values_2_5;
  assign response_translated_payload_values_2_6 = products_w_values_2_6;
  assign response_translated_payload_values_2_7 = products_w_values_2_7;
  assign response_translated_payload_values_2_8 = products_w_values_2_8;
  assign response_translated_payload_values_2_9 = products_w_values_2_9;
  assign response_translated_payload_values_2_10 = products_w_values_2_10;
  assign response_translated_payload_values_2_11 = products_w_values_2_11;
  assign response_translated_payload_values_2_12 = products_w_values_2_12;
  assign response_translated_payload_values_2_13 = products_w_values_2_13;
  assign response_translated_payload_values_2_14 = products_w_values_2_14;
  assign response_translated_payload_values_2_15 = products_w_values_2_15;
  assign response_translated_payload_values_3_0 = products_w_values_3_0;
  assign response_translated_payload_values_3_1 = products_w_values_3_1;
  assign response_translated_payload_values_3_2 = products_w_values_3_2;
  assign response_translated_payload_values_3_3 = products_w_values_3_3;
  assign response_translated_payload_values_3_4 = products_w_values_3_4;
  assign response_translated_payload_values_3_5 = products_w_values_3_5;
  assign response_translated_payload_values_3_6 = products_w_values_3_6;
  assign response_translated_payload_values_3_7 = products_w_values_3_7;
  assign response_translated_payload_values_3_8 = products_w_values_3_8;
  assign response_translated_payload_values_3_9 = products_w_values_3_9;
  assign response_translated_payload_values_3_10 = products_w_values_3_10;
  assign response_translated_payload_values_3_11 = products_w_values_3_11;
  assign response_translated_payload_values_3_12 = products_w_values_3_12;
  assign response_translated_payload_values_3_13 = products_w_values_3_13;
  assign response_translated_payload_values_3_14 = products_w_values_3_14;
  assign response_translated_payload_values_3_15 = products_w_values_3_15;
  always @(*) begin
    response_translated_ready = products_ready;
    if(when_Stream_l477_1) begin
      response_translated_ready = 1'b1;
    end
  end

  assign when_Stream_l477_1 = (! products_valid);
  assign products_valid = response_translated_rValid;
  assign products_payload_tag_pixel = response_translated_rData_tag_pixel;
  assign products_payload_tag_group = response_translated_rData_tag_group;
  assign products_payload_tag_mask = response_translated_rData_tag_mask;
  assign products_payload_tag_first = response_translated_rData_tag_first;
  assign products_payload_tag_finalInput = response_translated_rData_tag_finalInput;
  assign products_payload_tag_tileLast = response_translated_rData_tag_tileLast;
  assign products_payload_tag_last = response_translated_rData_tag_last;
  assign products_payload_values_0_0 = response_translated_rData_values_0_0;
  assign products_payload_values_0_1 = response_translated_rData_values_0_1;
  assign products_payload_values_0_2 = response_translated_rData_values_0_2;
  assign products_payload_values_0_3 = response_translated_rData_values_0_3;
  assign products_payload_values_0_4 = response_translated_rData_values_0_4;
  assign products_payload_values_0_5 = response_translated_rData_values_0_5;
  assign products_payload_values_0_6 = response_translated_rData_values_0_6;
  assign products_payload_values_0_7 = response_translated_rData_values_0_7;
  assign products_payload_values_0_8 = response_translated_rData_values_0_8;
  assign products_payload_values_0_9 = response_translated_rData_values_0_9;
  assign products_payload_values_0_10 = response_translated_rData_values_0_10;
  assign products_payload_values_0_11 = response_translated_rData_values_0_11;
  assign products_payload_values_0_12 = response_translated_rData_values_0_12;
  assign products_payload_values_0_13 = response_translated_rData_values_0_13;
  assign products_payload_values_0_14 = response_translated_rData_values_0_14;
  assign products_payload_values_0_15 = response_translated_rData_values_0_15;
  assign products_payload_values_1_0 = response_translated_rData_values_1_0;
  assign products_payload_values_1_1 = response_translated_rData_values_1_1;
  assign products_payload_values_1_2 = response_translated_rData_values_1_2;
  assign products_payload_values_1_3 = response_translated_rData_values_1_3;
  assign products_payload_values_1_4 = response_translated_rData_values_1_4;
  assign products_payload_values_1_5 = response_translated_rData_values_1_5;
  assign products_payload_values_1_6 = response_translated_rData_values_1_6;
  assign products_payload_values_1_7 = response_translated_rData_values_1_7;
  assign products_payload_values_1_8 = response_translated_rData_values_1_8;
  assign products_payload_values_1_9 = response_translated_rData_values_1_9;
  assign products_payload_values_1_10 = response_translated_rData_values_1_10;
  assign products_payload_values_1_11 = response_translated_rData_values_1_11;
  assign products_payload_values_1_12 = response_translated_rData_values_1_12;
  assign products_payload_values_1_13 = response_translated_rData_values_1_13;
  assign products_payload_values_1_14 = response_translated_rData_values_1_14;
  assign products_payload_values_1_15 = response_translated_rData_values_1_15;
  assign products_payload_values_2_0 = response_translated_rData_values_2_0;
  assign products_payload_values_2_1 = response_translated_rData_values_2_1;
  assign products_payload_values_2_2 = response_translated_rData_values_2_2;
  assign products_payload_values_2_3 = response_translated_rData_values_2_3;
  assign products_payload_values_2_4 = response_translated_rData_values_2_4;
  assign products_payload_values_2_5 = response_translated_rData_values_2_5;
  assign products_payload_values_2_6 = response_translated_rData_values_2_6;
  assign products_payload_values_2_7 = response_translated_rData_values_2_7;
  assign products_payload_values_2_8 = response_translated_rData_values_2_8;
  assign products_payload_values_2_9 = response_translated_rData_values_2_9;
  assign products_payload_values_2_10 = response_translated_rData_values_2_10;
  assign products_payload_values_2_11 = response_translated_rData_values_2_11;
  assign products_payload_values_2_12 = response_translated_rData_values_2_12;
  assign products_payload_values_2_13 = response_translated_rData_values_2_13;
  assign products_payload_values_2_14 = response_translated_rData_values_2_14;
  assign products_payload_values_2_15 = response_translated_rData_values_2_15;
  assign products_payload_values_3_0 = response_translated_rData_values_3_0;
  assign products_payload_values_3_1 = response_translated_rData_values_3_1;
  assign products_payload_values_3_2 = response_translated_rData_values_3_2;
  assign products_payload_values_3_3 = response_translated_rData_values_3_3;
  assign products_payload_values_3_4 = response_translated_rData_values_3_4;
  assign products_payload_values_3_5 = response_translated_rData_values_3_5;
  assign products_payload_values_3_6 = response_translated_rData_values_3_6;
  assign products_payload_values_3_7 = response_translated_rData_values_3_7;
  assign products_payload_values_3_8 = response_translated_rData_values_3_8;
  assign products_payload_values_3_9 = response_translated_rData_values_3_9;
  assign products_payload_values_3_10 = response_translated_rData_values_3_10;
  assign products_payload_values_3_11 = response_translated_rData_values_3_11;
  assign products_payload_values_3_12 = response_translated_rData_values_3_12;
  assign products_payload_values_3_13 = response_translated_rData_values_3_13;
  assign products_payload_values_3_14 = response_translated_rData_values_3_14;
  assign products_payload_values_3_15 = response_translated_rData_values_3_15;
  assign reduce8_w_tag_pixel = products_payload_tag_pixel;
  assign reduce8_w_tag_group = products_payload_tag_group;
  assign reduce8_w_tag_mask = products_payload_tag_mask;
  assign reduce8_w_tag_first = products_payload_tag_first;
  assign reduce8_w_tag_finalInput = products_payload_tag_finalInput;
  assign reduce8_w_tag_tileLast = products_payload_tag_tileLast;
  assign reduce8_w_tag_last = products_payload_tag_last;
  assign reduce8_w_values_0_0 = ($signed(_zz_reduce8_w_values_0_0) + $signed(_zz_reduce8_w_values_0_0_1));
  assign reduce8_w_values_0_1 = ($signed(_zz_reduce8_w_values_0_1) + $signed(_zz_reduce8_w_values_0_1_1));
  assign reduce8_w_values_0_2 = ($signed(_zz_reduce8_w_values_0_2) + $signed(_zz_reduce8_w_values_0_2_1));
  assign reduce8_w_values_0_3 = ($signed(_zz_reduce8_w_values_0_3) + $signed(_zz_reduce8_w_values_0_3_1));
  assign reduce8_w_values_0_4 = ($signed(_zz_reduce8_w_values_0_4) + $signed(_zz_reduce8_w_values_0_4_1));
  assign reduce8_w_values_0_5 = ($signed(_zz_reduce8_w_values_0_5) + $signed(_zz_reduce8_w_values_0_5_1));
  assign reduce8_w_values_0_6 = ($signed(_zz_reduce8_w_values_0_6) + $signed(_zz_reduce8_w_values_0_6_1));
  assign reduce8_w_values_0_7 = ($signed(_zz_reduce8_w_values_0_7) + $signed(_zz_reduce8_w_values_0_7_1));
  assign reduce8_w_values_1_0 = ($signed(_zz_reduce8_w_values_1_0) + $signed(_zz_reduce8_w_values_1_0_1));
  assign reduce8_w_values_1_1 = ($signed(_zz_reduce8_w_values_1_1) + $signed(_zz_reduce8_w_values_1_1_1));
  assign reduce8_w_values_1_2 = ($signed(_zz_reduce8_w_values_1_2) + $signed(_zz_reduce8_w_values_1_2_1));
  assign reduce8_w_values_1_3 = ($signed(_zz_reduce8_w_values_1_3) + $signed(_zz_reduce8_w_values_1_3_1));
  assign reduce8_w_values_1_4 = ($signed(_zz_reduce8_w_values_1_4) + $signed(_zz_reduce8_w_values_1_4_1));
  assign reduce8_w_values_1_5 = ($signed(_zz_reduce8_w_values_1_5) + $signed(_zz_reduce8_w_values_1_5_1));
  assign reduce8_w_values_1_6 = ($signed(_zz_reduce8_w_values_1_6) + $signed(_zz_reduce8_w_values_1_6_1));
  assign reduce8_w_values_1_7 = ($signed(_zz_reduce8_w_values_1_7) + $signed(_zz_reduce8_w_values_1_7_1));
  assign reduce8_w_values_2_0 = ($signed(_zz_reduce8_w_values_2_0) + $signed(_zz_reduce8_w_values_2_0_1));
  assign reduce8_w_values_2_1 = ($signed(_zz_reduce8_w_values_2_1) + $signed(_zz_reduce8_w_values_2_1_1));
  assign reduce8_w_values_2_2 = ($signed(_zz_reduce8_w_values_2_2) + $signed(_zz_reduce8_w_values_2_2_1));
  assign reduce8_w_values_2_3 = ($signed(_zz_reduce8_w_values_2_3) + $signed(_zz_reduce8_w_values_2_3_1));
  assign reduce8_w_values_2_4 = ($signed(_zz_reduce8_w_values_2_4) + $signed(_zz_reduce8_w_values_2_4_1));
  assign reduce8_w_values_2_5 = ($signed(_zz_reduce8_w_values_2_5) + $signed(_zz_reduce8_w_values_2_5_1));
  assign reduce8_w_values_2_6 = ($signed(_zz_reduce8_w_values_2_6) + $signed(_zz_reduce8_w_values_2_6_1));
  assign reduce8_w_values_2_7 = ($signed(_zz_reduce8_w_values_2_7) + $signed(_zz_reduce8_w_values_2_7_1));
  assign reduce8_w_values_3_0 = ($signed(_zz_reduce8_w_values_3_0) + $signed(_zz_reduce8_w_values_3_0_1));
  assign reduce8_w_values_3_1 = ($signed(_zz_reduce8_w_values_3_1) + $signed(_zz_reduce8_w_values_3_1_1));
  assign reduce8_w_values_3_2 = ($signed(_zz_reduce8_w_values_3_2) + $signed(_zz_reduce8_w_values_3_2_1));
  assign reduce8_w_values_3_3 = ($signed(_zz_reduce8_w_values_3_3) + $signed(_zz_reduce8_w_values_3_3_1));
  assign reduce8_w_values_3_4 = ($signed(_zz_reduce8_w_values_3_4) + $signed(_zz_reduce8_w_values_3_4_1));
  assign reduce8_w_values_3_5 = ($signed(_zz_reduce8_w_values_3_5) + $signed(_zz_reduce8_w_values_3_5_1));
  assign reduce8_w_values_3_6 = ($signed(_zz_reduce8_w_values_3_6) + $signed(_zz_reduce8_w_values_3_6_1));
  assign reduce8_w_values_3_7 = ($signed(_zz_reduce8_w_values_3_7) + $signed(_zz_reduce8_w_values_3_7_1));
  assign products_translated_valid = products_valid;
  assign products_ready = products_translated_ready;
  assign products_translated_payload_tag_pixel = reduce8_w_tag_pixel;
  assign products_translated_payload_tag_group = reduce8_w_tag_group;
  assign products_translated_payload_tag_mask = reduce8_w_tag_mask;
  assign products_translated_payload_tag_first = reduce8_w_tag_first;
  assign products_translated_payload_tag_finalInput = reduce8_w_tag_finalInput;
  assign products_translated_payload_tag_tileLast = reduce8_w_tag_tileLast;
  assign products_translated_payload_tag_last = reduce8_w_tag_last;
  assign products_translated_payload_values_0_0 = reduce8_w_values_0_0;
  assign products_translated_payload_values_0_1 = reduce8_w_values_0_1;
  assign products_translated_payload_values_0_2 = reduce8_w_values_0_2;
  assign products_translated_payload_values_0_3 = reduce8_w_values_0_3;
  assign products_translated_payload_values_0_4 = reduce8_w_values_0_4;
  assign products_translated_payload_values_0_5 = reduce8_w_values_0_5;
  assign products_translated_payload_values_0_6 = reduce8_w_values_0_6;
  assign products_translated_payload_values_0_7 = reduce8_w_values_0_7;
  assign products_translated_payload_values_1_0 = reduce8_w_values_1_0;
  assign products_translated_payload_values_1_1 = reduce8_w_values_1_1;
  assign products_translated_payload_values_1_2 = reduce8_w_values_1_2;
  assign products_translated_payload_values_1_3 = reduce8_w_values_1_3;
  assign products_translated_payload_values_1_4 = reduce8_w_values_1_4;
  assign products_translated_payload_values_1_5 = reduce8_w_values_1_5;
  assign products_translated_payload_values_1_6 = reduce8_w_values_1_6;
  assign products_translated_payload_values_1_7 = reduce8_w_values_1_7;
  assign products_translated_payload_values_2_0 = reduce8_w_values_2_0;
  assign products_translated_payload_values_2_1 = reduce8_w_values_2_1;
  assign products_translated_payload_values_2_2 = reduce8_w_values_2_2;
  assign products_translated_payload_values_2_3 = reduce8_w_values_2_3;
  assign products_translated_payload_values_2_4 = reduce8_w_values_2_4;
  assign products_translated_payload_values_2_5 = reduce8_w_values_2_5;
  assign products_translated_payload_values_2_6 = reduce8_w_values_2_6;
  assign products_translated_payload_values_2_7 = reduce8_w_values_2_7;
  assign products_translated_payload_values_3_0 = reduce8_w_values_3_0;
  assign products_translated_payload_values_3_1 = reduce8_w_values_3_1;
  assign products_translated_payload_values_3_2 = reduce8_w_values_3_2;
  assign products_translated_payload_values_3_3 = reduce8_w_values_3_3;
  assign products_translated_payload_values_3_4 = reduce8_w_values_3_4;
  assign products_translated_payload_values_3_5 = reduce8_w_values_3_5;
  assign products_translated_payload_values_3_6 = reduce8_w_values_3_6;
  assign products_translated_payload_values_3_7 = reduce8_w_values_3_7;
  always @(*) begin
    products_translated_ready = reduce8_ready;
    if(when_Stream_l477_2) begin
      products_translated_ready = 1'b1;
    end
  end

  assign when_Stream_l477_2 = (! reduce8_valid);
  assign reduce8_valid = products_translated_rValid;
  assign reduce8_payload_tag_pixel = products_translated_rData_tag_pixel;
  assign reduce8_payload_tag_group = products_translated_rData_tag_group;
  assign reduce8_payload_tag_mask = products_translated_rData_tag_mask;
  assign reduce8_payload_tag_first = products_translated_rData_tag_first;
  assign reduce8_payload_tag_finalInput = products_translated_rData_tag_finalInput;
  assign reduce8_payload_tag_tileLast = products_translated_rData_tag_tileLast;
  assign reduce8_payload_tag_last = products_translated_rData_tag_last;
  assign reduce8_payload_values_0_0 = products_translated_rData_values_0_0;
  assign reduce8_payload_values_0_1 = products_translated_rData_values_0_1;
  assign reduce8_payload_values_0_2 = products_translated_rData_values_0_2;
  assign reduce8_payload_values_0_3 = products_translated_rData_values_0_3;
  assign reduce8_payload_values_0_4 = products_translated_rData_values_0_4;
  assign reduce8_payload_values_0_5 = products_translated_rData_values_0_5;
  assign reduce8_payload_values_0_6 = products_translated_rData_values_0_6;
  assign reduce8_payload_values_0_7 = products_translated_rData_values_0_7;
  assign reduce8_payload_values_1_0 = products_translated_rData_values_1_0;
  assign reduce8_payload_values_1_1 = products_translated_rData_values_1_1;
  assign reduce8_payload_values_1_2 = products_translated_rData_values_1_2;
  assign reduce8_payload_values_1_3 = products_translated_rData_values_1_3;
  assign reduce8_payload_values_1_4 = products_translated_rData_values_1_4;
  assign reduce8_payload_values_1_5 = products_translated_rData_values_1_5;
  assign reduce8_payload_values_1_6 = products_translated_rData_values_1_6;
  assign reduce8_payload_values_1_7 = products_translated_rData_values_1_7;
  assign reduce8_payload_values_2_0 = products_translated_rData_values_2_0;
  assign reduce8_payload_values_2_1 = products_translated_rData_values_2_1;
  assign reduce8_payload_values_2_2 = products_translated_rData_values_2_2;
  assign reduce8_payload_values_2_3 = products_translated_rData_values_2_3;
  assign reduce8_payload_values_2_4 = products_translated_rData_values_2_4;
  assign reduce8_payload_values_2_5 = products_translated_rData_values_2_5;
  assign reduce8_payload_values_2_6 = products_translated_rData_values_2_6;
  assign reduce8_payload_values_2_7 = products_translated_rData_values_2_7;
  assign reduce8_payload_values_3_0 = products_translated_rData_values_3_0;
  assign reduce8_payload_values_3_1 = products_translated_rData_values_3_1;
  assign reduce8_payload_values_3_2 = products_translated_rData_values_3_2;
  assign reduce8_payload_values_3_3 = products_translated_rData_values_3_3;
  assign reduce8_payload_values_3_4 = products_translated_rData_values_3_4;
  assign reduce8_payload_values_3_5 = products_translated_rData_values_3_5;
  assign reduce8_payload_values_3_6 = products_translated_rData_values_3_6;
  assign reduce8_payload_values_3_7 = products_translated_rData_values_3_7;
  assign reduce4_w_tag_pixel = reduce8_payload_tag_pixel;
  assign reduce4_w_tag_group = reduce8_payload_tag_group;
  assign reduce4_w_tag_mask = reduce8_payload_tag_mask;
  assign reduce4_w_tag_first = reduce8_payload_tag_first;
  assign reduce4_w_tag_finalInput = reduce8_payload_tag_finalInput;
  assign reduce4_w_tag_tileLast = reduce8_payload_tag_tileLast;
  assign reduce4_w_tag_last = reduce8_payload_tag_last;
  assign reduce4_w_values_0_0 = ($signed(_zz_reduce4_w_values_0_0) + $signed(_zz_reduce4_w_values_0_0_1));
  assign reduce4_w_values_0_1 = ($signed(_zz_reduce4_w_values_0_1) + $signed(_zz_reduce4_w_values_0_1_1));
  assign reduce4_w_values_0_2 = ($signed(_zz_reduce4_w_values_0_2) + $signed(_zz_reduce4_w_values_0_2_1));
  assign reduce4_w_values_0_3 = ($signed(_zz_reduce4_w_values_0_3) + $signed(_zz_reduce4_w_values_0_3_1));
  assign reduce4_w_values_1_0 = ($signed(_zz_reduce4_w_values_1_0) + $signed(_zz_reduce4_w_values_1_0_1));
  assign reduce4_w_values_1_1 = ($signed(_zz_reduce4_w_values_1_1) + $signed(_zz_reduce4_w_values_1_1_1));
  assign reduce4_w_values_1_2 = ($signed(_zz_reduce4_w_values_1_2) + $signed(_zz_reduce4_w_values_1_2_1));
  assign reduce4_w_values_1_3 = ($signed(_zz_reduce4_w_values_1_3) + $signed(_zz_reduce4_w_values_1_3_1));
  assign reduce4_w_values_2_0 = ($signed(_zz_reduce4_w_values_2_0) + $signed(_zz_reduce4_w_values_2_0_1));
  assign reduce4_w_values_2_1 = ($signed(_zz_reduce4_w_values_2_1) + $signed(_zz_reduce4_w_values_2_1_1));
  assign reduce4_w_values_2_2 = ($signed(_zz_reduce4_w_values_2_2) + $signed(_zz_reduce4_w_values_2_2_1));
  assign reduce4_w_values_2_3 = ($signed(_zz_reduce4_w_values_2_3) + $signed(_zz_reduce4_w_values_2_3_1));
  assign reduce4_w_values_3_0 = ($signed(_zz_reduce4_w_values_3_0) + $signed(_zz_reduce4_w_values_3_0_1));
  assign reduce4_w_values_3_1 = ($signed(_zz_reduce4_w_values_3_1) + $signed(_zz_reduce4_w_values_3_1_1));
  assign reduce4_w_values_3_2 = ($signed(_zz_reduce4_w_values_3_2) + $signed(_zz_reduce4_w_values_3_2_1));
  assign reduce4_w_values_3_3 = ($signed(_zz_reduce4_w_values_3_3) + $signed(_zz_reduce4_w_values_3_3_1));
  assign reduce8_translated_valid = reduce8_valid;
  assign reduce8_ready = reduce8_translated_ready;
  assign reduce8_translated_payload_tag_pixel = reduce4_w_tag_pixel;
  assign reduce8_translated_payload_tag_group = reduce4_w_tag_group;
  assign reduce8_translated_payload_tag_mask = reduce4_w_tag_mask;
  assign reduce8_translated_payload_tag_first = reduce4_w_tag_first;
  assign reduce8_translated_payload_tag_finalInput = reduce4_w_tag_finalInput;
  assign reduce8_translated_payload_tag_tileLast = reduce4_w_tag_tileLast;
  assign reduce8_translated_payload_tag_last = reduce4_w_tag_last;
  assign reduce8_translated_payload_values_0_0 = reduce4_w_values_0_0;
  assign reduce8_translated_payload_values_0_1 = reduce4_w_values_0_1;
  assign reduce8_translated_payload_values_0_2 = reduce4_w_values_0_2;
  assign reduce8_translated_payload_values_0_3 = reduce4_w_values_0_3;
  assign reduce8_translated_payload_values_1_0 = reduce4_w_values_1_0;
  assign reduce8_translated_payload_values_1_1 = reduce4_w_values_1_1;
  assign reduce8_translated_payload_values_1_2 = reduce4_w_values_1_2;
  assign reduce8_translated_payload_values_1_3 = reduce4_w_values_1_3;
  assign reduce8_translated_payload_values_2_0 = reduce4_w_values_2_0;
  assign reduce8_translated_payload_values_2_1 = reduce4_w_values_2_1;
  assign reduce8_translated_payload_values_2_2 = reduce4_w_values_2_2;
  assign reduce8_translated_payload_values_2_3 = reduce4_w_values_2_3;
  assign reduce8_translated_payload_values_3_0 = reduce4_w_values_3_0;
  assign reduce8_translated_payload_values_3_1 = reduce4_w_values_3_1;
  assign reduce8_translated_payload_values_3_2 = reduce4_w_values_3_2;
  assign reduce8_translated_payload_values_3_3 = reduce4_w_values_3_3;
  always @(*) begin
    reduce8_translated_ready = reduce4_ready;
    if(when_Stream_l477_3) begin
      reduce8_translated_ready = 1'b1;
    end
  end

  assign when_Stream_l477_3 = (! reduce4_valid);
  assign reduce4_valid = reduce8_translated_rValid;
  assign reduce4_payload_tag_pixel = reduce8_translated_rData_tag_pixel;
  assign reduce4_payload_tag_group = reduce8_translated_rData_tag_group;
  assign reduce4_payload_tag_mask = reduce8_translated_rData_tag_mask;
  assign reduce4_payload_tag_first = reduce8_translated_rData_tag_first;
  assign reduce4_payload_tag_finalInput = reduce8_translated_rData_tag_finalInput;
  assign reduce4_payload_tag_tileLast = reduce8_translated_rData_tag_tileLast;
  assign reduce4_payload_tag_last = reduce8_translated_rData_tag_last;
  assign reduce4_payload_values_0_0 = reduce8_translated_rData_values_0_0;
  assign reduce4_payload_values_0_1 = reduce8_translated_rData_values_0_1;
  assign reduce4_payload_values_0_2 = reduce8_translated_rData_values_0_2;
  assign reduce4_payload_values_0_3 = reduce8_translated_rData_values_0_3;
  assign reduce4_payload_values_1_0 = reduce8_translated_rData_values_1_0;
  assign reduce4_payload_values_1_1 = reduce8_translated_rData_values_1_1;
  assign reduce4_payload_values_1_2 = reduce8_translated_rData_values_1_2;
  assign reduce4_payload_values_1_3 = reduce8_translated_rData_values_1_3;
  assign reduce4_payload_values_2_0 = reduce8_translated_rData_values_2_0;
  assign reduce4_payload_values_2_1 = reduce8_translated_rData_values_2_1;
  assign reduce4_payload_values_2_2 = reduce8_translated_rData_values_2_2;
  assign reduce4_payload_values_2_3 = reduce8_translated_rData_values_2_3;
  assign reduce4_payload_values_3_0 = reduce8_translated_rData_values_3_0;
  assign reduce4_payload_values_3_1 = reduce8_translated_rData_values_3_1;
  assign reduce4_payload_values_3_2 = reduce8_translated_rData_values_3_2;
  assign reduce4_payload_values_3_3 = reduce8_translated_rData_values_3_3;
  assign reduce2_w_tag_pixel = reduce4_payload_tag_pixel;
  assign reduce2_w_tag_group = reduce4_payload_tag_group;
  assign reduce2_w_tag_mask = reduce4_payload_tag_mask;
  assign reduce2_w_tag_first = reduce4_payload_tag_first;
  assign reduce2_w_tag_finalInput = reduce4_payload_tag_finalInput;
  assign reduce2_w_tag_tileLast = reduce4_payload_tag_tileLast;
  assign reduce2_w_tag_last = reduce4_payload_tag_last;
  assign reduce2_w_values_0_0 = ($signed(_zz_reduce2_w_values_0_0) + $signed(_zz_reduce2_w_values_0_0_1));
  assign reduce2_w_values_0_1 = ($signed(_zz_reduce2_w_values_0_1) + $signed(_zz_reduce2_w_values_0_1_1));
  assign reduce2_w_values_1_0 = ($signed(_zz_reduce2_w_values_1_0) + $signed(_zz_reduce2_w_values_1_0_1));
  assign reduce2_w_values_1_1 = ($signed(_zz_reduce2_w_values_1_1) + $signed(_zz_reduce2_w_values_1_1_1));
  assign reduce2_w_values_2_0 = ($signed(_zz_reduce2_w_values_2_0) + $signed(_zz_reduce2_w_values_2_0_1));
  assign reduce2_w_values_2_1 = ($signed(_zz_reduce2_w_values_2_1) + $signed(_zz_reduce2_w_values_2_1_1));
  assign reduce2_w_values_3_0 = ($signed(_zz_reduce2_w_values_3_0) + $signed(_zz_reduce2_w_values_3_0_1));
  assign reduce2_w_values_3_1 = ($signed(_zz_reduce2_w_values_3_1) + $signed(_zz_reduce2_w_values_3_1_1));
  assign reduce4_translated_valid = reduce4_valid;
  assign reduce4_ready = reduce4_translated_ready;
  assign reduce4_translated_payload_tag_pixel = reduce2_w_tag_pixel;
  assign reduce4_translated_payload_tag_group = reduce2_w_tag_group;
  assign reduce4_translated_payload_tag_mask = reduce2_w_tag_mask;
  assign reduce4_translated_payload_tag_first = reduce2_w_tag_first;
  assign reduce4_translated_payload_tag_finalInput = reduce2_w_tag_finalInput;
  assign reduce4_translated_payload_tag_tileLast = reduce2_w_tag_tileLast;
  assign reduce4_translated_payload_tag_last = reduce2_w_tag_last;
  assign reduce4_translated_payload_values_0_0 = reduce2_w_values_0_0;
  assign reduce4_translated_payload_values_0_1 = reduce2_w_values_0_1;
  assign reduce4_translated_payload_values_1_0 = reduce2_w_values_1_0;
  assign reduce4_translated_payload_values_1_1 = reduce2_w_values_1_1;
  assign reduce4_translated_payload_values_2_0 = reduce2_w_values_2_0;
  assign reduce4_translated_payload_values_2_1 = reduce2_w_values_2_1;
  assign reduce4_translated_payload_values_3_0 = reduce2_w_values_3_0;
  assign reduce4_translated_payload_values_3_1 = reduce2_w_values_3_1;
  always @(*) begin
    reduce4_translated_ready = reduce2_ready;
    if(when_Stream_l477_4) begin
      reduce4_translated_ready = 1'b1;
    end
  end

  assign when_Stream_l477_4 = (! reduce2_valid);
  assign reduce2_valid = reduce4_translated_rValid;
  assign reduce2_payload_tag_pixel = reduce4_translated_rData_tag_pixel;
  assign reduce2_payload_tag_group = reduce4_translated_rData_tag_group;
  assign reduce2_payload_tag_mask = reduce4_translated_rData_tag_mask;
  assign reduce2_payload_tag_first = reduce4_translated_rData_tag_first;
  assign reduce2_payload_tag_finalInput = reduce4_translated_rData_tag_finalInput;
  assign reduce2_payload_tag_tileLast = reduce4_translated_rData_tag_tileLast;
  assign reduce2_payload_tag_last = reduce4_translated_rData_tag_last;
  assign reduce2_payload_values_0_0 = reduce4_translated_rData_values_0_0;
  assign reduce2_payload_values_0_1 = reduce4_translated_rData_values_0_1;
  assign reduce2_payload_values_1_0 = reduce4_translated_rData_values_1_0;
  assign reduce2_payload_values_1_1 = reduce4_translated_rData_values_1_1;
  assign reduce2_payload_values_2_0 = reduce4_translated_rData_values_2_0;
  assign reduce2_payload_values_2_1 = reduce4_translated_rData_values_2_1;
  assign reduce2_payload_values_3_0 = reduce4_translated_rData_values_3_0;
  assign reduce2_payload_values_3_1 = reduce4_translated_rData_values_3_1;
  assign dot_w_tag_pixel = reduce2_payload_tag_pixel;
  assign dot_w_tag_group = reduce2_payload_tag_group;
  assign dot_w_tag_mask = reduce2_payload_tag_mask;
  assign dot_w_tag_first = reduce2_payload_tag_first;
  assign dot_w_tag_finalInput = reduce2_payload_tag_finalInput;
  assign dot_w_tag_tileLast = reduce2_payload_tag_tileLast;
  assign dot_w_tag_last = reduce2_payload_tag_last;
  assign dot_w_values_0_0 = ($signed(_zz_dot_w_values_0_0) + $signed(_zz_dot_w_values_0_0_1));
  assign dot_w_values_1_0 = ($signed(_zz_dot_w_values_1_0) + $signed(_zz_dot_w_values_1_0_1));
  assign dot_w_values_2_0 = ($signed(_zz_dot_w_values_2_0) + $signed(_zz_dot_w_values_2_0_1));
  assign dot_w_values_3_0 = ($signed(_zz_dot_w_values_3_0) + $signed(_zz_dot_w_values_3_0_1));
  assign reduce2_translated_valid = reduce2_valid;
  assign reduce2_ready = reduce2_translated_ready;
  assign reduce2_translated_payload_tag_pixel = dot_w_tag_pixel;
  assign reduce2_translated_payload_tag_group = dot_w_tag_group;
  assign reduce2_translated_payload_tag_mask = dot_w_tag_mask;
  assign reduce2_translated_payload_tag_first = dot_w_tag_first;
  assign reduce2_translated_payload_tag_finalInput = dot_w_tag_finalInput;
  assign reduce2_translated_payload_tag_tileLast = dot_w_tag_tileLast;
  assign reduce2_translated_payload_tag_last = dot_w_tag_last;
  assign reduce2_translated_payload_values_0_0 = dot_w_values_0_0;
  assign reduce2_translated_payload_values_1_0 = dot_w_values_1_0;
  assign reduce2_translated_payload_values_2_0 = dot_w_values_2_0;
  assign reduce2_translated_payload_values_3_0 = dot_w_values_3_0;
  always @(*) begin
    reduce2_translated_ready = dot_ready;
    if(when_Stream_l477_5) begin
      reduce2_translated_ready = 1'b1;
    end
  end

  assign when_Stream_l477_5 = (! dot_valid);
  assign dot_valid = reduce2_translated_rValid;
  assign dot_payload_tag_pixel = reduce2_translated_rData_tag_pixel;
  assign dot_payload_tag_group = reduce2_translated_rData_tag_group;
  assign dot_payload_tag_mask = reduce2_translated_rData_tag_mask;
  assign dot_payload_tag_first = reduce2_translated_rData_tag_first;
  assign dot_payload_tag_finalInput = reduce2_translated_rData_tag_finalInput;
  assign dot_payload_tag_tileLast = reduce2_translated_rData_tag_tileLast;
  assign dot_payload_tag_last = reduce2_translated_rData_tag_last;
  assign dot_payload_values_0_0 = reduce2_translated_rData_values_0_0;
  assign dot_payload_values_1_0 = reduce2_translated_rData_values_1_0;
  assign dot_payload_values_2_0 = reduce2_translated_rData_values_2_0;
  assign dot_payload_values_3_0 = reduce2_translated_rData_values_3_0;
  assign localPixel_w = _zz_localPixel_w[3:0];
  assign quantRequest_valid = (dot_valid && dot_payload_tag_finalInput);
  assign quantRequest_payload_tag_pixel = dot_payload_tag_pixel;
  assign quantRequest_payload_tag_group = dot_payload_tag_group;
  assign quantRequest_payload_tag_mask = dot_payload_tag_mask;
  assign quantRequest_payload_tag_first = dot_payload_tag_first;
  assign quantRequest_payload_tag_finalInput = dot_payload_tag_finalInput;
  assign quantRequest_payload_tag_tileLast = dot_payload_tag_tileLast;
  assign quantRequest_payload_tag_last = dot_payload_tag_last;
  assign dot_ready = ((! dot_payload_tag_finalInput) || quantRequest_ready);
  assign _zz_3 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_quantRequest_payload_mac_0 = ($signed(_zz__zz_quantRequest_payload_mac_0) + $signed(_zz__zz_quantRequest_payload_mac_0_2));
  assign quantRequest_payload_mac_0 = _zz_quantRequest_payload_mac_0;
  assign dot_fire = (dot_valid && dot_ready);
  assign _zz_acc_r_0_0 = _zz_quantRequest_payload_mac_0;
  assign _zz_4 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_quantRequest_payload_mac_1 = ($signed(_zz__zz_quantRequest_payload_mac_1) + $signed(_zz__zz_quantRequest_payload_mac_1_2));
  assign quantRequest_payload_mac_1 = _zz_quantRequest_payload_mac_1;
  assign _zz_acc_r_1_0 = _zz_quantRequest_payload_mac_1;
  assign _zz_5 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_quantRequest_payload_mac_2 = ($signed(_zz__zz_quantRequest_payload_mac_2) + $signed(_zz__zz_quantRequest_payload_mac_2_2));
  assign quantRequest_payload_mac_2 = _zz_quantRequest_payload_mac_2;
  assign _zz_acc_r_2_0 = _zz_quantRequest_payload_mac_2;
  assign _zz_6 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_quantRequest_payload_mac_3 = ($signed(_zz__zz_quantRequest_payload_mac_3) + $signed(_zz__zz_quantRequest_payload_mac_3_2));
  assign quantRequest_payload_mac_3 = _zz_quantRequest_payload_mac_3;
  assign _zz_acc_r_3_0 = _zz_quantRequest_payload_mac_3;
  always @(*) begin
    quantRequest_ready = quantResponse_ready;
    if(when_Stream_l477_6) begin
      quantRequest_ready = 1'b1;
    end
  end

  assign when_Stream_l477_6 = (! quantResponse_valid);
  assign quantResponse_valid = quantRequest_rValid;
  assign quantResponse_payload_tag_pixel = quantRequest_rData_tag_pixel;
  assign quantResponse_payload_tag_group = quantRequest_rData_tag_group;
  assign quantResponse_payload_tag_mask = quantRequest_rData_tag_mask;
  assign quantResponse_payload_tag_first = quantRequest_rData_tag_first;
  assign quantResponse_payload_tag_finalInput = quantRequest_rData_tag_finalInput;
  assign quantResponse_payload_tag_tileLast = quantRequest_rData_tag_tileLast;
  assign quantResponse_payload_tag_last = quantRequest_rData_tag_last;
  assign quantResponse_payload_mac_0 = quantRequest_rData_mac_0;
  assign quantResponse_payload_mac_1 = quantRequest_rData_mac_1;
  assign quantResponse_payload_mac_2 = quantRequest_rData_mac_2;
  assign quantResponse_payload_mac_3 = quantRequest_rData_mac_3;
  assign _zz_params_w_0 = quantRequest_payload_tag_group;
  assign quantRequest_fire = (quantRequest_valid && quantRequest_ready);
  assign params_w_0 = paramMem_0_spinal_port1;
  assign _zz_params_w_1 = quantRequest_payload_tag_group;
  assign params_w_1 = paramMem_1_spinal_port1;
  assign _zz_params_w_2 = quantRequest_payload_tag_group;
  assign params_w_2 = paramMem_2_spinal_port1;
  assign _zz_params_w_3 = quantRequest_payload_tag_group;
  assign params_w_3 = paramMem_3_spinal_port1;
  assign quantInput_w_tag_pixel = quantResponse_payload_tag_pixel;
  assign quantInput_w_tag_group = quantResponse_payload_tag_group;
  assign quantInput_w_tag_mask = quantResponse_payload_tag_mask;
  assign quantInput_w_tag_first = quantResponse_payload_tag_first;
  assign quantInput_w_tag_finalInput = quantResponse_payload_tag_finalInput;
  assign quantInput_w_tag_tileLast = quantResponse_payload_tag_tileLast;
  assign quantInput_w_tag_last = quantResponse_payload_tag_last;
  assign quantInput_w_mac_0 = quantResponse_payload_mac_0;
  assign quantInput_w_mac_1 = quantResponse_payload_mac_1;
  assign quantInput_w_mac_2 = quantResponse_payload_mac_2;
  assign quantInput_w_mac_3 = quantResponse_payload_mac_3;
  assign quantInput_w_raw = run_r_raw;
  assign quantInput_w_int16 = run_r_int16;
  assign quantInput_w_shift = run_r_shift;
  assign quantInput_w_multiplier_0 = params_w_0[31 : 0];
  assign quantInput_w_bias_0 = params_w_0[95 : 32];
  assign quantInput_w_lower_0 = params_w_0[111 : 96];
  assign quantInput_w_upper_0 = params_w_0[127 : 112];
  assign quantInput_w_multiplier_1 = params_w_1[31 : 0];
  assign quantInput_w_bias_1 = params_w_1[95 : 32];
  assign quantInput_w_lower_1 = params_w_1[111 : 96];
  assign quantInput_w_upper_1 = params_w_1[127 : 112];
  assign quantInput_w_multiplier_2 = params_w_2[31 : 0];
  assign quantInput_w_bias_2 = params_w_2[95 : 32];
  assign quantInput_w_lower_2 = params_w_2[111 : 96];
  assign quantInput_w_upper_2 = params_w_2[127 : 112];
  assign quantInput_w_multiplier_3 = params_w_3[31 : 0];
  assign quantInput_w_bias_3 = params_w_3[95 : 32];
  assign quantInput_w_lower_3 = params_w_3[111 : 96];
  assign quantInput_w_upper_3 = params_w_3[127 : 112];
  assign quantResponse_translated_valid = quantResponse_valid;
  assign quantResponse_ready = quantResponse_translated_ready;
  assign quantResponse_translated_payload_tag_pixel = quantInput_w_tag_pixel;
  assign quantResponse_translated_payload_tag_group = quantInput_w_tag_group;
  assign quantResponse_translated_payload_tag_mask = quantInput_w_tag_mask;
  assign quantResponse_translated_payload_tag_first = quantInput_w_tag_first;
  assign quantResponse_translated_payload_tag_finalInput = quantInput_w_tag_finalInput;
  assign quantResponse_translated_payload_tag_tileLast = quantInput_w_tag_tileLast;
  assign quantResponse_translated_payload_tag_last = quantInput_w_tag_last;
  assign quantResponse_translated_payload_raw = quantInput_w_raw;
  assign quantResponse_translated_payload_int16 = quantInput_w_int16;
  assign quantResponse_translated_payload_shift = quantInput_w_shift;
  assign quantResponse_translated_payload_mac_0 = quantInput_w_mac_0;
  assign quantResponse_translated_payload_mac_1 = quantInput_w_mac_1;
  assign quantResponse_translated_payload_mac_2 = quantInput_w_mac_2;
  assign quantResponse_translated_payload_mac_3 = quantInput_w_mac_3;
  assign quantResponse_translated_payload_multiplier_0 = quantInput_w_multiplier_0;
  assign quantResponse_translated_payload_multiplier_1 = quantInput_w_multiplier_1;
  assign quantResponse_translated_payload_multiplier_2 = quantInput_w_multiplier_2;
  assign quantResponse_translated_payload_multiplier_3 = quantInput_w_multiplier_3;
  assign quantResponse_translated_payload_bias_0 = quantInput_w_bias_0;
  assign quantResponse_translated_payload_bias_1 = quantInput_w_bias_1;
  assign quantResponse_translated_payload_bias_2 = quantInput_w_bias_2;
  assign quantResponse_translated_payload_bias_3 = quantInput_w_bias_3;
  assign quantResponse_translated_payload_lower_0 = quantInput_w_lower_0;
  assign quantResponse_translated_payload_lower_1 = quantInput_w_lower_1;
  assign quantResponse_translated_payload_lower_2 = quantInput_w_lower_2;
  assign quantResponse_translated_payload_lower_3 = quantInput_w_lower_3;
  assign quantResponse_translated_payload_upper_0 = quantInput_w_upper_0;
  assign quantResponse_translated_payload_upper_1 = quantInput_w_upper_1;
  assign quantResponse_translated_payload_upper_2 = quantInput_w_upper_2;
  assign quantResponse_translated_payload_upper_3 = quantInput_w_upper_3;
  assign quantResponse_translated_ready = requant_io_input_i_ready;
  assign io_output_o_valid = requant_io_output_o_valid;
  assign io_output_o_payload_pixel = requant_io_output_o_payload_pixel;
  assign io_output_o_payload_group = requant_io_output_o_payload_group;
  assign io_output_o_payload_mask = requant_io_output_o_payload_mask;
  assign io_output_o_payload_last = requant_io_output_o_payload_last;
  assign io_output_o_payload_raw = requant_io_output_o_payload_raw;
  assign io_output_o_payload_int16 = requant_io_output_o_payload_int16;
  assign io_output_o_payload_mac_0 = requant_io_output_o_payload_mac_0;
  assign io_output_o_payload_mac_1 = requant_io_output_o_payload_mac_1;
  assign io_output_o_payload_mac_2 = requant_io_output_o_payload_mac_2;
  assign io_output_o_payload_mac_3 = requant_io_output_o_payload_mac_3;
  assign io_output_o_payload_q_0 = requant_io_output_o_payload_q_0;
  assign io_output_o_payload_q_1 = requant_io_output_o_payload_q_1;
  assign io_output_o_payload_q_2 = requant_io_output_o_payload_q_2;
  assign io_output_o_payload_q_3 = requant_io_output_o_payload_q_3;
  assign lastTileOutput_w = ((_zz_lastTileOutput_w == _zz_lastTileOutput_w_1) && (io_output_o_payload_pixel == _zz_lastTileOutput_w_2));
  assign io_output_o_fire = (io_output_o_valid && io_output_o_ready);
  assign when_PwMac_l339 = (io_output_o_fire && lastTileOutput_w);
  assign _zz_tileCount_r = (_zz__zz_tileCount_r - _zz__zz_tileCount_r_1);
  always @(posedge clk or negedge resetn) begin
    if(!resetn) begin
      state_r <= 3'b000;
      weightCount_r <= 13'h0;
      paramCount_r <= 8'h0;
      tileBase_r <= 19'h0;
      tileCount_r <= 5'h0;
      fillGroup_r <= 6'h0;
      fillPixel_r <= 5'h0;
      waiting_r <= 1'b0;
      issueGroup_r <= 7'h0;
      issueInput_r <= 6'h0;
      issuePixel_r <= 5'h0;
      done_r <= 1'b0;
      request_rValid <= 1'b0;
      response_translated_rValid <= 1'b0;
      products_translated_rValid <= 1'b0;
      reduce8_translated_rValid <= 1'b0;
      reduce4_translated_rValid <= 1'b0;
      reduce2_translated_rValid <= 1'b0;
      quantRequest_rValid <= 1'b0;
    end else begin
      done_r <= 1'b0;
      if(io_cfg_i_fire) begin
        weightCount_r <= 13'h0;
        paramCount_r <= 8'h0;
        state_r <= LOAD;
      end
      if(io_weights_i_fire) begin
        weightCount_r <= (weightCount_r + 13'h0001);
      end
      if(io_params_i_fire) begin
        paramCount_r <= (paramCount_r + 8'h01);
      end
      if(when_PwMac_l181) begin
        state_r <= READY;
      end
      if(io_start_i_fire) begin
        tileBase_r <= 19'h0;
        tileCount_r <= ((19'h00010 < run_r_pixels) ? 5'h10 : _zz_tileCount_r_1);
        fillGroup_r <= 6'h0;
        fillPixel_r <= 5'h0;
        waiting_r <= 1'b0;
        state_r <= FILL;
      end
      if(io_rd_o_fire) begin
        waiting_r <= 1'b1;
      end
      if(io_rsp_i_fire) begin
        waiting_r <= 1'b0;
        if(when_PwMac_l204) begin
          fillPixel_r <= 5'h0;
          if(when_PwMac_l206) begin
            issueGroup_r <= 7'h0;
            issueInput_r <= 6'h0;
            issuePixel_r <= 5'h0;
            state_r <= ISSUE;
          end else begin
            fillGroup_r <= (fillGroup_r + 6'h01);
          end
        end else begin
          fillPixel_r <= (fillPixel_r + 5'h01);
        end
      end
      if(request_ready) begin
        request_rValid <= request_valid;
      end
      if(request_fire) begin
        if(when_PwMac_l252) begin
          issuePixel_r <= 5'h0;
          if(when_PwMac_l254) begin
            issueInput_r <= 6'h0;
            if(when_PwMac_l256) begin
              state_r <= DRAIN;
            end else begin
              issueGroup_r <= (issueGroup_r + 7'h01);
            end
          end else begin
            issueInput_r <= (issueInput_r + 6'h01);
          end
        end else begin
          issuePixel_r <= (issuePixel_r + 5'h01);
        end
      end
      if(response_translated_ready) begin
        response_translated_rValid <= response_translated_valid;
      end
      if(products_translated_ready) begin
        products_translated_rValid <= products_translated_valid;
      end
      if(reduce8_translated_ready) begin
        reduce8_translated_rValid <= reduce8_translated_valid;
      end
      if(reduce4_translated_ready) begin
        reduce4_translated_rValid <= reduce4_translated_valid;
      end
      if(reduce2_translated_ready) begin
        reduce2_translated_rValid <= reduce2_translated_valid;
      end
      if(quantRequest_ready) begin
        quantRequest_rValid <= quantRequest_valid;
      end
      if(when_PwMac_l339) begin
        if(io_output_o_payload_last) begin
          done_r <= 1'b1;
          state_r <= READY;
        end else begin
          tileBase_r <= (tileBase_r + _zz_tileBase_r);
          tileCount_r <= ((19'h00010 < _zz_tileCount_r) ? 5'h10 : _zz_tileCount_r_2);
          fillGroup_r <= 6'h0;
          fillPixel_r <= 5'h0;
          waiting_r <= 1'b0;
          state_r <= FILL;
        end
      end
    end
  end

  always @(posedge clk) begin
    if(io_cfg_i_fire) begin
      run_r_cin <= io_cfg_i_payload_cin;
      run_r_cout <= io_cfg_i_payload_cout;
      run_r_pixels <= io_cfg_i_payload_pixels;
      run_r_shift <= io_cfg_i_payload_shift;
      run_r_raw <= io_cfg_i_payload_raw;
      run_r_int16 <= io_cfg_i_payload_int16;
      igCount_r <= cfgIg_w;
      ogCount_r <= cfgOg_w;
      weightTotal_r <= _zz_weightTotal_r[12:0];
    end
    if(request_ready) begin
      request_rData_tag_pixel <= request_payload_tag_pixel;
      request_rData_tag_group <= request_payload_tag_group;
      request_rData_tag_mask <= request_payload_tag_mask;
      request_rData_tag_first <= request_payload_tag_first;
      request_rData_tag_finalInput <= request_payload_tag_finalInput;
      request_rData_tag_tileLast <= request_payload_tag_tileLast;
      request_rData_tag_last <= request_payload_tag_last;
      request_rData_inputGroup <= request_payload_inputGroup;
    end
    if(response_translated_ready) begin
      response_translated_rData_tag_pixel <= response_translated_payload_tag_pixel;
      response_translated_rData_tag_group <= response_translated_payload_tag_group;
      response_translated_rData_tag_mask <= response_translated_payload_tag_mask;
      response_translated_rData_tag_first <= response_translated_payload_tag_first;
      response_translated_rData_tag_finalInput <= response_translated_payload_tag_finalInput;
      response_translated_rData_tag_tileLast <= response_translated_payload_tag_tileLast;
      response_translated_rData_tag_last <= response_translated_payload_tag_last;
      response_translated_rData_values_0_0 <= response_translated_payload_values_0_0;
      response_translated_rData_values_0_1 <= response_translated_payload_values_0_1;
      response_translated_rData_values_0_2 <= response_translated_payload_values_0_2;
      response_translated_rData_values_0_3 <= response_translated_payload_values_0_3;
      response_translated_rData_values_0_4 <= response_translated_payload_values_0_4;
      response_translated_rData_values_0_5 <= response_translated_payload_values_0_5;
      response_translated_rData_values_0_6 <= response_translated_payload_values_0_6;
      response_translated_rData_values_0_7 <= response_translated_payload_values_0_7;
      response_translated_rData_values_0_8 <= response_translated_payload_values_0_8;
      response_translated_rData_values_0_9 <= response_translated_payload_values_0_9;
      response_translated_rData_values_0_10 <= response_translated_payload_values_0_10;
      response_translated_rData_values_0_11 <= response_translated_payload_values_0_11;
      response_translated_rData_values_0_12 <= response_translated_payload_values_0_12;
      response_translated_rData_values_0_13 <= response_translated_payload_values_0_13;
      response_translated_rData_values_0_14 <= response_translated_payload_values_0_14;
      response_translated_rData_values_0_15 <= response_translated_payload_values_0_15;
      response_translated_rData_values_1_0 <= response_translated_payload_values_1_0;
      response_translated_rData_values_1_1 <= response_translated_payload_values_1_1;
      response_translated_rData_values_1_2 <= response_translated_payload_values_1_2;
      response_translated_rData_values_1_3 <= response_translated_payload_values_1_3;
      response_translated_rData_values_1_4 <= response_translated_payload_values_1_4;
      response_translated_rData_values_1_5 <= response_translated_payload_values_1_5;
      response_translated_rData_values_1_6 <= response_translated_payload_values_1_6;
      response_translated_rData_values_1_7 <= response_translated_payload_values_1_7;
      response_translated_rData_values_1_8 <= response_translated_payload_values_1_8;
      response_translated_rData_values_1_9 <= response_translated_payload_values_1_9;
      response_translated_rData_values_1_10 <= response_translated_payload_values_1_10;
      response_translated_rData_values_1_11 <= response_translated_payload_values_1_11;
      response_translated_rData_values_1_12 <= response_translated_payload_values_1_12;
      response_translated_rData_values_1_13 <= response_translated_payload_values_1_13;
      response_translated_rData_values_1_14 <= response_translated_payload_values_1_14;
      response_translated_rData_values_1_15 <= response_translated_payload_values_1_15;
      response_translated_rData_values_2_0 <= response_translated_payload_values_2_0;
      response_translated_rData_values_2_1 <= response_translated_payload_values_2_1;
      response_translated_rData_values_2_2 <= response_translated_payload_values_2_2;
      response_translated_rData_values_2_3 <= response_translated_payload_values_2_3;
      response_translated_rData_values_2_4 <= response_translated_payload_values_2_4;
      response_translated_rData_values_2_5 <= response_translated_payload_values_2_5;
      response_translated_rData_values_2_6 <= response_translated_payload_values_2_6;
      response_translated_rData_values_2_7 <= response_translated_payload_values_2_7;
      response_translated_rData_values_2_8 <= response_translated_payload_values_2_8;
      response_translated_rData_values_2_9 <= response_translated_payload_values_2_9;
      response_translated_rData_values_2_10 <= response_translated_payload_values_2_10;
      response_translated_rData_values_2_11 <= response_translated_payload_values_2_11;
      response_translated_rData_values_2_12 <= response_translated_payload_values_2_12;
      response_translated_rData_values_2_13 <= response_translated_payload_values_2_13;
      response_translated_rData_values_2_14 <= response_translated_payload_values_2_14;
      response_translated_rData_values_2_15 <= response_translated_payload_values_2_15;
      response_translated_rData_values_3_0 <= response_translated_payload_values_3_0;
      response_translated_rData_values_3_1 <= response_translated_payload_values_3_1;
      response_translated_rData_values_3_2 <= response_translated_payload_values_3_2;
      response_translated_rData_values_3_3 <= response_translated_payload_values_3_3;
      response_translated_rData_values_3_4 <= response_translated_payload_values_3_4;
      response_translated_rData_values_3_5 <= response_translated_payload_values_3_5;
      response_translated_rData_values_3_6 <= response_translated_payload_values_3_6;
      response_translated_rData_values_3_7 <= response_translated_payload_values_3_7;
      response_translated_rData_values_3_8 <= response_translated_payload_values_3_8;
      response_translated_rData_values_3_9 <= response_translated_payload_values_3_9;
      response_translated_rData_values_3_10 <= response_translated_payload_values_3_10;
      response_translated_rData_values_3_11 <= response_translated_payload_values_3_11;
      response_translated_rData_values_3_12 <= response_translated_payload_values_3_12;
      response_translated_rData_values_3_13 <= response_translated_payload_values_3_13;
      response_translated_rData_values_3_14 <= response_translated_payload_values_3_14;
      response_translated_rData_values_3_15 <= response_translated_payload_values_3_15;
    end
    if(products_translated_ready) begin
      products_translated_rData_tag_pixel <= products_translated_payload_tag_pixel;
      products_translated_rData_tag_group <= products_translated_payload_tag_group;
      products_translated_rData_tag_mask <= products_translated_payload_tag_mask;
      products_translated_rData_tag_first <= products_translated_payload_tag_first;
      products_translated_rData_tag_finalInput <= products_translated_payload_tag_finalInput;
      products_translated_rData_tag_tileLast <= products_translated_payload_tag_tileLast;
      products_translated_rData_tag_last <= products_translated_payload_tag_last;
      products_translated_rData_values_0_0 <= products_translated_payload_values_0_0;
      products_translated_rData_values_0_1 <= products_translated_payload_values_0_1;
      products_translated_rData_values_0_2 <= products_translated_payload_values_0_2;
      products_translated_rData_values_0_3 <= products_translated_payload_values_0_3;
      products_translated_rData_values_0_4 <= products_translated_payload_values_0_4;
      products_translated_rData_values_0_5 <= products_translated_payload_values_0_5;
      products_translated_rData_values_0_6 <= products_translated_payload_values_0_6;
      products_translated_rData_values_0_7 <= products_translated_payload_values_0_7;
      products_translated_rData_values_1_0 <= products_translated_payload_values_1_0;
      products_translated_rData_values_1_1 <= products_translated_payload_values_1_1;
      products_translated_rData_values_1_2 <= products_translated_payload_values_1_2;
      products_translated_rData_values_1_3 <= products_translated_payload_values_1_3;
      products_translated_rData_values_1_4 <= products_translated_payload_values_1_4;
      products_translated_rData_values_1_5 <= products_translated_payload_values_1_5;
      products_translated_rData_values_1_6 <= products_translated_payload_values_1_6;
      products_translated_rData_values_1_7 <= products_translated_payload_values_1_7;
      products_translated_rData_values_2_0 <= products_translated_payload_values_2_0;
      products_translated_rData_values_2_1 <= products_translated_payload_values_2_1;
      products_translated_rData_values_2_2 <= products_translated_payload_values_2_2;
      products_translated_rData_values_2_3 <= products_translated_payload_values_2_3;
      products_translated_rData_values_2_4 <= products_translated_payload_values_2_4;
      products_translated_rData_values_2_5 <= products_translated_payload_values_2_5;
      products_translated_rData_values_2_6 <= products_translated_payload_values_2_6;
      products_translated_rData_values_2_7 <= products_translated_payload_values_2_7;
      products_translated_rData_values_3_0 <= products_translated_payload_values_3_0;
      products_translated_rData_values_3_1 <= products_translated_payload_values_3_1;
      products_translated_rData_values_3_2 <= products_translated_payload_values_3_2;
      products_translated_rData_values_3_3 <= products_translated_payload_values_3_3;
      products_translated_rData_values_3_4 <= products_translated_payload_values_3_4;
      products_translated_rData_values_3_5 <= products_translated_payload_values_3_5;
      products_translated_rData_values_3_6 <= products_translated_payload_values_3_6;
      products_translated_rData_values_3_7 <= products_translated_payload_values_3_7;
    end
    if(reduce8_translated_ready) begin
      reduce8_translated_rData_tag_pixel <= reduce8_translated_payload_tag_pixel;
      reduce8_translated_rData_tag_group <= reduce8_translated_payload_tag_group;
      reduce8_translated_rData_tag_mask <= reduce8_translated_payload_tag_mask;
      reduce8_translated_rData_tag_first <= reduce8_translated_payload_tag_first;
      reduce8_translated_rData_tag_finalInput <= reduce8_translated_payload_tag_finalInput;
      reduce8_translated_rData_tag_tileLast <= reduce8_translated_payload_tag_tileLast;
      reduce8_translated_rData_tag_last <= reduce8_translated_payload_tag_last;
      reduce8_translated_rData_values_0_0 <= reduce8_translated_payload_values_0_0;
      reduce8_translated_rData_values_0_1 <= reduce8_translated_payload_values_0_1;
      reduce8_translated_rData_values_0_2 <= reduce8_translated_payload_values_0_2;
      reduce8_translated_rData_values_0_3 <= reduce8_translated_payload_values_0_3;
      reduce8_translated_rData_values_1_0 <= reduce8_translated_payload_values_1_0;
      reduce8_translated_rData_values_1_1 <= reduce8_translated_payload_values_1_1;
      reduce8_translated_rData_values_1_2 <= reduce8_translated_payload_values_1_2;
      reduce8_translated_rData_values_1_3 <= reduce8_translated_payload_values_1_3;
      reduce8_translated_rData_values_2_0 <= reduce8_translated_payload_values_2_0;
      reduce8_translated_rData_values_2_1 <= reduce8_translated_payload_values_2_1;
      reduce8_translated_rData_values_2_2 <= reduce8_translated_payload_values_2_2;
      reduce8_translated_rData_values_2_3 <= reduce8_translated_payload_values_2_3;
      reduce8_translated_rData_values_3_0 <= reduce8_translated_payload_values_3_0;
      reduce8_translated_rData_values_3_1 <= reduce8_translated_payload_values_3_1;
      reduce8_translated_rData_values_3_2 <= reduce8_translated_payload_values_3_2;
      reduce8_translated_rData_values_3_3 <= reduce8_translated_payload_values_3_3;
    end
    if(reduce4_translated_ready) begin
      reduce4_translated_rData_tag_pixel <= reduce4_translated_payload_tag_pixel;
      reduce4_translated_rData_tag_group <= reduce4_translated_payload_tag_group;
      reduce4_translated_rData_tag_mask <= reduce4_translated_payload_tag_mask;
      reduce4_translated_rData_tag_first <= reduce4_translated_payload_tag_first;
      reduce4_translated_rData_tag_finalInput <= reduce4_translated_payload_tag_finalInput;
      reduce4_translated_rData_tag_tileLast <= reduce4_translated_payload_tag_tileLast;
      reduce4_translated_rData_tag_last <= reduce4_translated_payload_tag_last;
      reduce4_translated_rData_values_0_0 <= reduce4_translated_payload_values_0_0;
      reduce4_translated_rData_values_0_1 <= reduce4_translated_payload_values_0_1;
      reduce4_translated_rData_values_1_0 <= reduce4_translated_payload_values_1_0;
      reduce4_translated_rData_values_1_1 <= reduce4_translated_payload_values_1_1;
      reduce4_translated_rData_values_2_0 <= reduce4_translated_payload_values_2_0;
      reduce4_translated_rData_values_2_1 <= reduce4_translated_payload_values_2_1;
      reduce4_translated_rData_values_3_0 <= reduce4_translated_payload_values_3_0;
      reduce4_translated_rData_values_3_1 <= reduce4_translated_payload_values_3_1;
    end
    if(reduce2_translated_ready) begin
      reduce2_translated_rData_tag_pixel <= reduce2_translated_payload_tag_pixel;
      reduce2_translated_rData_tag_group <= reduce2_translated_payload_tag_group;
      reduce2_translated_rData_tag_mask <= reduce2_translated_payload_tag_mask;
      reduce2_translated_rData_tag_first <= reduce2_translated_payload_tag_first;
      reduce2_translated_rData_tag_finalInput <= reduce2_translated_payload_tag_finalInput;
      reduce2_translated_rData_tag_tileLast <= reduce2_translated_payload_tag_tileLast;
      reduce2_translated_rData_tag_last <= reduce2_translated_payload_tag_last;
      reduce2_translated_rData_values_0_0 <= reduce2_translated_payload_values_0_0;
      reduce2_translated_rData_values_1_0 <= reduce2_translated_payload_values_1_0;
      reduce2_translated_rData_values_2_0 <= reduce2_translated_payload_values_2_0;
      reduce2_translated_rData_values_3_0 <= reduce2_translated_payload_values_3_0;
    end
    if(dot_fire) begin
      if(_zz_3[0]) begin
        acc_r_0_0 <= _zz_acc_r_0_0;
      end
      if(_zz_3[1]) begin
        acc_r_0_1 <= _zz_acc_r_0_0;
      end
      if(_zz_3[2]) begin
        acc_r_0_2 <= _zz_acc_r_0_0;
      end
      if(_zz_3[3]) begin
        acc_r_0_3 <= _zz_acc_r_0_0;
      end
      if(_zz_3[4]) begin
        acc_r_0_4 <= _zz_acc_r_0_0;
      end
      if(_zz_3[5]) begin
        acc_r_0_5 <= _zz_acc_r_0_0;
      end
      if(_zz_3[6]) begin
        acc_r_0_6 <= _zz_acc_r_0_0;
      end
      if(_zz_3[7]) begin
        acc_r_0_7 <= _zz_acc_r_0_0;
      end
      if(_zz_3[8]) begin
        acc_r_0_8 <= _zz_acc_r_0_0;
      end
      if(_zz_3[9]) begin
        acc_r_0_9 <= _zz_acc_r_0_0;
      end
      if(_zz_3[10]) begin
        acc_r_0_10 <= _zz_acc_r_0_0;
      end
      if(_zz_3[11]) begin
        acc_r_0_11 <= _zz_acc_r_0_0;
      end
      if(_zz_3[12]) begin
        acc_r_0_12 <= _zz_acc_r_0_0;
      end
      if(_zz_3[13]) begin
        acc_r_0_13 <= _zz_acc_r_0_0;
      end
      if(_zz_3[14]) begin
        acc_r_0_14 <= _zz_acc_r_0_0;
      end
      if(_zz_3[15]) begin
        acc_r_0_15 <= _zz_acc_r_0_0;
      end
    end
    if(dot_fire) begin
      if(_zz_4[0]) begin
        acc_r_1_0 <= _zz_acc_r_1_0;
      end
      if(_zz_4[1]) begin
        acc_r_1_1 <= _zz_acc_r_1_0;
      end
      if(_zz_4[2]) begin
        acc_r_1_2 <= _zz_acc_r_1_0;
      end
      if(_zz_4[3]) begin
        acc_r_1_3 <= _zz_acc_r_1_0;
      end
      if(_zz_4[4]) begin
        acc_r_1_4 <= _zz_acc_r_1_0;
      end
      if(_zz_4[5]) begin
        acc_r_1_5 <= _zz_acc_r_1_0;
      end
      if(_zz_4[6]) begin
        acc_r_1_6 <= _zz_acc_r_1_0;
      end
      if(_zz_4[7]) begin
        acc_r_1_7 <= _zz_acc_r_1_0;
      end
      if(_zz_4[8]) begin
        acc_r_1_8 <= _zz_acc_r_1_0;
      end
      if(_zz_4[9]) begin
        acc_r_1_9 <= _zz_acc_r_1_0;
      end
      if(_zz_4[10]) begin
        acc_r_1_10 <= _zz_acc_r_1_0;
      end
      if(_zz_4[11]) begin
        acc_r_1_11 <= _zz_acc_r_1_0;
      end
      if(_zz_4[12]) begin
        acc_r_1_12 <= _zz_acc_r_1_0;
      end
      if(_zz_4[13]) begin
        acc_r_1_13 <= _zz_acc_r_1_0;
      end
      if(_zz_4[14]) begin
        acc_r_1_14 <= _zz_acc_r_1_0;
      end
      if(_zz_4[15]) begin
        acc_r_1_15 <= _zz_acc_r_1_0;
      end
    end
    if(dot_fire) begin
      if(_zz_5[0]) begin
        acc_r_2_0 <= _zz_acc_r_2_0;
      end
      if(_zz_5[1]) begin
        acc_r_2_1 <= _zz_acc_r_2_0;
      end
      if(_zz_5[2]) begin
        acc_r_2_2 <= _zz_acc_r_2_0;
      end
      if(_zz_5[3]) begin
        acc_r_2_3 <= _zz_acc_r_2_0;
      end
      if(_zz_5[4]) begin
        acc_r_2_4 <= _zz_acc_r_2_0;
      end
      if(_zz_5[5]) begin
        acc_r_2_5 <= _zz_acc_r_2_0;
      end
      if(_zz_5[6]) begin
        acc_r_2_6 <= _zz_acc_r_2_0;
      end
      if(_zz_5[7]) begin
        acc_r_2_7 <= _zz_acc_r_2_0;
      end
      if(_zz_5[8]) begin
        acc_r_2_8 <= _zz_acc_r_2_0;
      end
      if(_zz_5[9]) begin
        acc_r_2_9 <= _zz_acc_r_2_0;
      end
      if(_zz_5[10]) begin
        acc_r_2_10 <= _zz_acc_r_2_0;
      end
      if(_zz_5[11]) begin
        acc_r_2_11 <= _zz_acc_r_2_0;
      end
      if(_zz_5[12]) begin
        acc_r_2_12 <= _zz_acc_r_2_0;
      end
      if(_zz_5[13]) begin
        acc_r_2_13 <= _zz_acc_r_2_0;
      end
      if(_zz_5[14]) begin
        acc_r_2_14 <= _zz_acc_r_2_0;
      end
      if(_zz_5[15]) begin
        acc_r_2_15 <= _zz_acc_r_2_0;
      end
    end
    if(dot_fire) begin
      if(_zz_6[0]) begin
        acc_r_3_0 <= _zz_acc_r_3_0;
      end
      if(_zz_6[1]) begin
        acc_r_3_1 <= _zz_acc_r_3_0;
      end
      if(_zz_6[2]) begin
        acc_r_3_2 <= _zz_acc_r_3_0;
      end
      if(_zz_6[3]) begin
        acc_r_3_3 <= _zz_acc_r_3_0;
      end
      if(_zz_6[4]) begin
        acc_r_3_4 <= _zz_acc_r_3_0;
      end
      if(_zz_6[5]) begin
        acc_r_3_5 <= _zz_acc_r_3_0;
      end
      if(_zz_6[6]) begin
        acc_r_3_6 <= _zz_acc_r_3_0;
      end
      if(_zz_6[7]) begin
        acc_r_3_7 <= _zz_acc_r_3_0;
      end
      if(_zz_6[8]) begin
        acc_r_3_8 <= _zz_acc_r_3_0;
      end
      if(_zz_6[9]) begin
        acc_r_3_9 <= _zz_acc_r_3_0;
      end
      if(_zz_6[10]) begin
        acc_r_3_10 <= _zz_acc_r_3_0;
      end
      if(_zz_6[11]) begin
        acc_r_3_11 <= _zz_acc_r_3_0;
      end
      if(_zz_6[12]) begin
        acc_r_3_12 <= _zz_acc_r_3_0;
      end
      if(_zz_6[13]) begin
        acc_r_3_13 <= _zz_acc_r_3_0;
      end
      if(_zz_6[14]) begin
        acc_r_3_14 <= _zz_acc_r_3_0;
      end
      if(_zz_6[15]) begin
        acc_r_3_15 <= _zz_acc_r_3_0;
      end
    end
    if(quantRequest_ready) begin
      quantRequest_rData_tag_pixel <= quantRequest_payload_tag_pixel;
      quantRequest_rData_tag_group <= quantRequest_payload_tag_group;
      quantRequest_rData_tag_mask <= quantRequest_payload_tag_mask;
      quantRequest_rData_tag_first <= quantRequest_payload_tag_first;
      quantRequest_rData_tag_finalInput <= quantRequest_payload_tag_finalInput;
      quantRequest_rData_tag_tileLast <= quantRequest_payload_tag_tileLast;
      quantRequest_rData_tag_last <= quantRequest_payload_tag_last;
      quantRequest_rData_mac_0 <= quantRequest_payload_mac_0;
      quantRequest_rData_mac_1 <= quantRequest_payload_mac_1;
      quantRequest_rData_mac_2 <= quantRequest_payload_mac_2;
      quantRequest_rData_mac_3 <= quantRequest_payload_mac_3;
    end
  end


endmodule

module PwRequant (
  input  wire          io_input_i_valid,
  output wire          io_input_i_ready,
  input  wire [18:0]   io_input_i_payload_tag_pixel,
  input  wire [6:0]    io_input_i_payload_tag_group,
  input  wire [3:0]    io_input_i_payload_tag_mask,
  input  wire          io_input_i_payload_tag_first,
  input  wire          io_input_i_payload_tag_finalInput,
  input  wire          io_input_i_payload_tag_tileLast,
  input  wire          io_input_i_payload_tag_last,
  input  wire          io_input_i_payload_raw,
  input  wire          io_input_i_payload_int16,
  input  wire [5:0]    io_input_i_payload_shift,
  input  wire [31:0]   io_input_i_payload_mac_0,
  input  wire [31:0]   io_input_i_payload_mac_1,
  input  wire [31:0]   io_input_i_payload_mac_2,
  input  wire [31:0]   io_input_i_payload_mac_3,
  input  wire [31:0]   io_input_i_payload_multiplier_0,
  input  wire [31:0]   io_input_i_payload_multiplier_1,
  input  wire [31:0]   io_input_i_payload_multiplier_2,
  input  wire [31:0]   io_input_i_payload_multiplier_3,
  input  wire [63:0]   io_input_i_payload_bias_0,
  input  wire [63:0]   io_input_i_payload_bias_1,
  input  wire [63:0]   io_input_i_payload_bias_2,
  input  wire [63:0]   io_input_i_payload_bias_3,
  input  wire [15:0]   io_input_i_payload_lower_0,
  input  wire [15:0]   io_input_i_payload_lower_1,
  input  wire [15:0]   io_input_i_payload_lower_2,
  input  wire [15:0]   io_input_i_payload_lower_3,
  input  wire [15:0]   io_input_i_payload_upper_0,
  input  wire [15:0]   io_input_i_payload_upper_1,
  input  wire [15:0]   io_input_i_payload_upper_2,
  input  wire [15:0]   io_input_i_payload_upper_3,
  output wire          io_output_o_valid,
  input  wire          io_output_o_ready,
  output wire [18:0]   io_output_o_payload_pixel,
  output wire [6:0]    io_output_o_payload_group,
  output wire [3:0]    io_output_o_payload_mask,
  output wire          io_output_o_payload_last,
  output wire          io_output_o_payload_raw,
  output wire          io_output_o_payload_int16,
  output wire [31:0]   io_output_o_payload_mac_0,
  output wire [31:0]   io_output_o_payload_mac_1,
  output wire [31:0]   io_output_o_payload_mac_2,
  output wire [31:0]   io_output_o_payload_mac_3,
  output wire [15:0]   io_output_o_payload_q_0,
  output wire [15:0]   io_output_o_payload_q_1,
  output wire [15:0]   io_output_o_payload_q_2,
  output wire [15:0]   io_output_o_payload_q_3,
  input  wire          clk,
  input  wire          resetn
);

  wire       [63:0]   _zz_remainderMask_w;
  wire       [5:0]    _zz_half_w;
  wire       [63:0]   _zz_round_w_value_0_2;
  wire       [63:0]   _zz_round_w_value_0_3;
  wire       [0:0]    _zz_round_w_value_0_4;
  wire       [63:0]   _zz_round_w_value_1_2;
  wire       [63:0]   _zz_round_w_value_1_3;
  wire       [0:0]    _zz_round_w_value_1_4;
  wire       [63:0]   _zz_round_w_value_2_2;
  wire       [63:0]   _zz_round_w_value_2_3;
  wire       [0:0]    _zz_round_w_value_2_4;
  wire       [63:0]   _zz_round_w_value_3_2;
  wire       [63:0]   _zz_round_w_value_3_3;
  wire       [0:0]    _zz_round_w_value_3_4;
  wire       [63:0]   _zz_when_PwMac_l96;
  wire       [63:0]   _zz_when_PwMac_l98;
  wire       [63:0]   _zz_when_PwMac_l96_1;
  wire       [63:0]   _zz_when_PwMac_l98_1;
  wire       [63:0]   _zz_when_PwMac_l96_2;
  wire       [63:0]   _zz_when_PwMac_l98_2;
  wire       [63:0]   _zz_when_PwMac_l96_3;
  wire       [63:0]   _zz_when_PwMac_l98_3;
  wire       [18:0]   product_w_info_tag_pixel;
  wire       [6:0]    product_w_info_tag_group;
  wire       [3:0]    product_w_info_tag_mask;
  wire                product_w_info_tag_first;
  wire                product_w_info_tag_finalInput;
  wire                product_w_info_tag_tileLast;
  wire                product_w_info_tag_last;
  wire                product_w_info_raw;
  wire                product_w_info_int16;
  wire       [5:0]    product_w_info_shift;
  wire       [31:0]   product_w_info_mac_0;
  wire       [31:0]   product_w_info_mac_1;
  wire       [31:0]   product_w_info_mac_2;
  wire       [31:0]   product_w_info_mac_3;
  wire       [31:0]   product_w_info_multiplier_0;
  wire       [31:0]   product_w_info_multiplier_1;
  wire       [31:0]   product_w_info_multiplier_2;
  wire       [31:0]   product_w_info_multiplier_3;
  wire       [63:0]   product_w_info_bias_0;
  wire       [63:0]   product_w_info_bias_1;
  wire       [63:0]   product_w_info_bias_2;
  wire       [63:0]   product_w_info_bias_3;
  wire       [15:0]   product_w_info_lower_0;
  wire       [15:0]   product_w_info_lower_1;
  wire       [15:0]   product_w_info_lower_2;
  wire       [15:0]   product_w_info_lower_3;
  wire       [15:0]   product_w_info_upper_0;
  wire       [15:0]   product_w_info_upper_1;
  wire       [15:0]   product_w_info_upper_2;
  wire       [15:0]   product_w_info_upper_3;
  wire       [63:0]   product_w_value_0;
  wire       [63:0]   product_w_value_1;
  wire       [63:0]   product_w_value_2;
  wire       [63:0]   product_w_value_3;
  wire                io_input_i_translated_valid;
  reg                 io_input_i_translated_ready;
  wire       [18:0]   io_input_i_translated_payload_info_tag_pixel;
  wire       [6:0]    io_input_i_translated_payload_info_tag_group;
  wire       [3:0]    io_input_i_translated_payload_info_tag_mask;
  wire                io_input_i_translated_payload_info_tag_first;
  wire                io_input_i_translated_payload_info_tag_finalInput;
  wire                io_input_i_translated_payload_info_tag_tileLast;
  wire                io_input_i_translated_payload_info_tag_last;
  wire                io_input_i_translated_payload_info_raw;
  wire                io_input_i_translated_payload_info_int16;
  wire       [5:0]    io_input_i_translated_payload_info_shift;
  wire       [31:0]   io_input_i_translated_payload_info_mac_0;
  wire       [31:0]   io_input_i_translated_payload_info_mac_1;
  wire       [31:0]   io_input_i_translated_payload_info_mac_2;
  wire       [31:0]   io_input_i_translated_payload_info_mac_3;
  wire       [31:0]   io_input_i_translated_payload_info_multiplier_0;
  wire       [31:0]   io_input_i_translated_payload_info_multiplier_1;
  wire       [31:0]   io_input_i_translated_payload_info_multiplier_2;
  wire       [31:0]   io_input_i_translated_payload_info_multiplier_3;
  wire       [63:0]   io_input_i_translated_payload_info_bias_0;
  wire       [63:0]   io_input_i_translated_payload_info_bias_1;
  wire       [63:0]   io_input_i_translated_payload_info_bias_2;
  wire       [63:0]   io_input_i_translated_payload_info_bias_3;
  wire       [15:0]   io_input_i_translated_payload_info_lower_0;
  wire       [15:0]   io_input_i_translated_payload_info_lower_1;
  wire       [15:0]   io_input_i_translated_payload_info_lower_2;
  wire       [15:0]   io_input_i_translated_payload_info_lower_3;
  wire       [15:0]   io_input_i_translated_payload_info_upper_0;
  wire       [15:0]   io_input_i_translated_payload_info_upper_1;
  wire       [15:0]   io_input_i_translated_payload_info_upper_2;
  wire       [15:0]   io_input_i_translated_payload_info_upper_3;
  wire       [63:0]   io_input_i_translated_payload_value_0;
  wire       [63:0]   io_input_i_translated_payload_value_1;
  wire       [63:0]   io_input_i_translated_payload_value_2;
  wire       [63:0]   io_input_i_translated_payload_value_3;
  wire                product_valid;
  wire                product_ready;
  wire       [18:0]   product_payload_info_tag_pixel;
  wire       [6:0]    product_payload_info_tag_group;
  wire       [3:0]    product_payload_info_tag_mask;
  wire                product_payload_info_tag_first;
  wire                product_payload_info_tag_finalInput;
  wire                product_payload_info_tag_tileLast;
  wire                product_payload_info_tag_last;
  wire                product_payload_info_raw;
  wire                product_payload_info_int16;
  wire       [5:0]    product_payload_info_shift;
  wire       [31:0]   product_payload_info_mac_0;
  wire       [31:0]   product_payload_info_mac_1;
  wire       [31:0]   product_payload_info_mac_2;
  wire       [31:0]   product_payload_info_mac_3;
  wire       [31:0]   product_payload_info_multiplier_0;
  wire       [31:0]   product_payload_info_multiplier_1;
  wire       [31:0]   product_payload_info_multiplier_2;
  wire       [31:0]   product_payload_info_multiplier_3;
  wire       [63:0]   product_payload_info_bias_0;
  wire       [63:0]   product_payload_info_bias_1;
  wire       [63:0]   product_payload_info_bias_2;
  wire       [63:0]   product_payload_info_bias_3;
  wire       [15:0]   product_payload_info_lower_0;
  wire       [15:0]   product_payload_info_lower_1;
  wire       [15:0]   product_payload_info_lower_2;
  wire       [15:0]   product_payload_info_lower_3;
  wire       [15:0]   product_payload_info_upper_0;
  wire       [15:0]   product_payload_info_upper_1;
  wire       [15:0]   product_payload_info_upper_2;
  wire       [15:0]   product_payload_info_upper_3;
  wire       [63:0]   product_payload_value_0;
  wire       [63:0]   product_payload_value_1;
  wire       [63:0]   product_payload_value_2;
  wire       [63:0]   product_payload_value_3;
  reg                 io_input_i_translated_rValid;
  reg        [18:0]   io_input_i_translated_rData_info_tag_pixel;
  reg        [6:0]    io_input_i_translated_rData_info_tag_group;
  reg        [3:0]    io_input_i_translated_rData_info_tag_mask;
  reg                 io_input_i_translated_rData_info_tag_first;
  reg                 io_input_i_translated_rData_info_tag_finalInput;
  reg                 io_input_i_translated_rData_info_tag_tileLast;
  reg                 io_input_i_translated_rData_info_tag_last;
  reg                 io_input_i_translated_rData_info_raw;
  reg                 io_input_i_translated_rData_info_int16;
  reg        [5:0]    io_input_i_translated_rData_info_shift;
  reg        [31:0]   io_input_i_translated_rData_info_mac_0;
  reg        [31:0]   io_input_i_translated_rData_info_mac_1;
  reg        [31:0]   io_input_i_translated_rData_info_mac_2;
  reg        [31:0]   io_input_i_translated_rData_info_mac_3;
  reg        [31:0]   io_input_i_translated_rData_info_multiplier_0;
  reg        [31:0]   io_input_i_translated_rData_info_multiplier_1;
  reg        [31:0]   io_input_i_translated_rData_info_multiplier_2;
  reg        [31:0]   io_input_i_translated_rData_info_multiplier_3;
  reg        [63:0]   io_input_i_translated_rData_info_bias_0;
  reg        [63:0]   io_input_i_translated_rData_info_bias_1;
  reg        [63:0]   io_input_i_translated_rData_info_bias_2;
  reg        [63:0]   io_input_i_translated_rData_info_bias_3;
  reg        [15:0]   io_input_i_translated_rData_info_lower_0;
  reg        [15:0]   io_input_i_translated_rData_info_lower_1;
  reg        [15:0]   io_input_i_translated_rData_info_lower_2;
  reg        [15:0]   io_input_i_translated_rData_info_lower_3;
  reg        [15:0]   io_input_i_translated_rData_info_upper_0;
  reg        [15:0]   io_input_i_translated_rData_info_upper_1;
  reg        [15:0]   io_input_i_translated_rData_info_upper_2;
  reg        [15:0]   io_input_i_translated_rData_info_upper_3;
  reg        [63:0]   io_input_i_translated_rData_value_0;
  reg        [63:0]   io_input_i_translated_rData_value_1;
  reg        [63:0]   io_input_i_translated_rData_value_2;
  reg        [63:0]   io_input_i_translated_rData_value_3;
  wire                when_Stream_l477;
  wire       [18:0]   sum_w_info_tag_pixel;
  wire       [6:0]    sum_w_info_tag_group;
  wire       [3:0]    sum_w_info_tag_mask;
  wire                sum_w_info_tag_first;
  wire                sum_w_info_tag_finalInput;
  wire                sum_w_info_tag_tileLast;
  wire                sum_w_info_tag_last;
  wire                sum_w_info_raw;
  wire                sum_w_info_int16;
  wire       [5:0]    sum_w_info_shift;
  wire       [31:0]   sum_w_info_mac_0;
  wire       [31:0]   sum_w_info_mac_1;
  wire       [31:0]   sum_w_info_mac_2;
  wire       [31:0]   sum_w_info_mac_3;
  wire       [31:0]   sum_w_info_multiplier_0;
  wire       [31:0]   sum_w_info_multiplier_1;
  wire       [31:0]   sum_w_info_multiplier_2;
  wire       [31:0]   sum_w_info_multiplier_3;
  wire       [63:0]   sum_w_info_bias_0;
  wire       [63:0]   sum_w_info_bias_1;
  wire       [63:0]   sum_w_info_bias_2;
  wire       [63:0]   sum_w_info_bias_3;
  wire       [15:0]   sum_w_info_lower_0;
  wire       [15:0]   sum_w_info_lower_1;
  wire       [15:0]   sum_w_info_lower_2;
  wire       [15:0]   sum_w_info_lower_3;
  wire       [15:0]   sum_w_info_upper_0;
  wire       [15:0]   sum_w_info_upper_1;
  wire       [15:0]   sum_w_info_upper_2;
  wire       [15:0]   sum_w_info_upper_3;
  wire       [63:0]   sum_w_value_0;
  wire       [63:0]   sum_w_value_1;
  wire       [63:0]   sum_w_value_2;
  wire       [63:0]   sum_w_value_3;
  wire                product_translated_valid;
  reg                 product_translated_ready;
  wire       [18:0]   product_translated_payload_info_tag_pixel;
  wire       [6:0]    product_translated_payload_info_tag_group;
  wire       [3:0]    product_translated_payload_info_tag_mask;
  wire                product_translated_payload_info_tag_first;
  wire                product_translated_payload_info_tag_finalInput;
  wire                product_translated_payload_info_tag_tileLast;
  wire                product_translated_payload_info_tag_last;
  wire                product_translated_payload_info_raw;
  wire                product_translated_payload_info_int16;
  wire       [5:0]    product_translated_payload_info_shift;
  wire       [31:0]   product_translated_payload_info_mac_0;
  wire       [31:0]   product_translated_payload_info_mac_1;
  wire       [31:0]   product_translated_payload_info_mac_2;
  wire       [31:0]   product_translated_payload_info_mac_3;
  wire       [31:0]   product_translated_payload_info_multiplier_0;
  wire       [31:0]   product_translated_payload_info_multiplier_1;
  wire       [31:0]   product_translated_payload_info_multiplier_2;
  wire       [31:0]   product_translated_payload_info_multiplier_3;
  wire       [63:0]   product_translated_payload_info_bias_0;
  wire       [63:0]   product_translated_payload_info_bias_1;
  wire       [63:0]   product_translated_payload_info_bias_2;
  wire       [63:0]   product_translated_payload_info_bias_3;
  wire       [15:0]   product_translated_payload_info_lower_0;
  wire       [15:0]   product_translated_payload_info_lower_1;
  wire       [15:0]   product_translated_payload_info_lower_2;
  wire       [15:0]   product_translated_payload_info_lower_3;
  wire       [15:0]   product_translated_payload_info_upper_0;
  wire       [15:0]   product_translated_payload_info_upper_1;
  wire       [15:0]   product_translated_payload_info_upper_2;
  wire       [15:0]   product_translated_payload_info_upper_3;
  wire       [63:0]   product_translated_payload_value_0;
  wire       [63:0]   product_translated_payload_value_1;
  wire       [63:0]   product_translated_payload_value_2;
  wire       [63:0]   product_translated_payload_value_3;
  wire                sum_valid;
  wire                sum_ready;
  wire       [18:0]   sum_payload_info_tag_pixel;
  wire       [6:0]    sum_payload_info_tag_group;
  wire       [3:0]    sum_payload_info_tag_mask;
  wire                sum_payload_info_tag_first;
  wire                sum_payload_info_tag_finalInput;
  wire                sum_payload_info_tag_tileLast;
  wire                sum_payload_info_tag_last;
  wire                sum_payload_info_raw;
  wire                sum_payload_info_int16;
  wire       [5:0]    sum_payload_info_shift;
  wire       [31:0]   sum_payload_info_mac_0;
  wire       [31:0]   sum_payload_info_mac_1;
  wire       [31:0]   sum_payload_info_mac_2;
  wire       [31:0]   sum_payload_info_mac_3;
  wire       [31:0]   sum_payload_info_multiplier_0;
  wire       [31:0]   sum_payload_info_multiplier_1;
  wire       [31:0]   sum_payload_info_multiplier_2;
  wire       [31:0]   sum_payload_info_multiplier_3;
  wire       [63:0]   sum_payload_info_bias_0;
  wire       [63:0]   sum_payload_info_bias_1;
  wire       [63:0]   sum_payload_info_bias_2;
  wire       [63:0]   sum_payload_info_bias_3;
  wire       [15:0]   sum_payload_info_lower_0;
  wire       [15:0]   sum_payload_info_lower_1;
  wire       [15:0]   sum_payload_info_lower_2;
  wire       [15:0]   sum_payload_info_lower_3;
  wire       [15:0]   sum_payload_info_upper_0;
  wire       [15:0]   sum_payload_info_upper_1;
  wire       [15:0]   sum_payload_info_upper_2;
  wire       [15:0]   sum_payload_info_upper_3;
  wire       [63:0]   sum_payload_value_0;
  wire       [63:0]   sum_payload_value_1;
  wire       [63:0]   sum_payload_value_2;
  wire       [63:0]   sum_payload_value_3;
  reg                 product_translated_rValid;
  reg        [18:0]   product_translated_rData_info_tag_pixel;
  reg        [6:0]    product_translated_rData_info_tag_group;
  reg        [3:0]    product_translated_rData_info_tag_mask;
  reg                 product_translated_rData_info_tag_first;
  reg                 product_translated_rData_info_tag_finalInput;
  reg                 product_translated_rData_info_tag_tileLast;
  reg                 product_translated_rData_info_tag_last;
  reg                 product_translated_rData_info_raw;
  reg                 product_translated_rData_info_int16;
  reg        [5:0]    product_translated_rData_info_shift;
  reg        [31:0]   product_translated_rData_info_mac_0;
  reg        [31:0]   product_translated_rData_info_mac_1;
  reg        [31:0]   product_translated_rData_info_mac_2;
  reg        [31:0]   product_translated_rData_info_mac_3;
  reg        [31:0]   product_translated_rData_info_multiplier_0;
  reg        [31:0]   product_translated_rData_info_multiplier_1;
  reg        [31:0]   product_translated_rData_info_multiplier_2;
  reg        [31:0]   product_translated_rData_info_multiplier_3;
  reg        [63:0]   product_translated_rData_info_bias_0;
  reg        [63:0]   product_translated_rData_info_bias_1;
  reg        [63:0]   product_translated_rData_info_bias_2;
  reg        [63:0]   product_translated_rData_info_bias_3;
  reg        [15:0]   product_translated_rData_info_lower_0;
  reg        [15:0]   product_translated_rData_info_lower_1;
  reg        [15:0]   product_translated_rData_info_lower_2;
  reg        [15:0]   product_translated_rData_info_lower_3;
  reg        [15:0]   product_translated_rData_info_upper_0;
  reg        [15:0]   product_translated_rData_info_upper_1;
  reg        [15:0]   product_translated_rData_info_upper_2;
  reg        [15:0]   product_translated_rData_info_upper_3;
  reg        [63:0]   product_translated_rData_value_0;
  reg        [63:0]   product_translated_rData_value_1;
  reg        [63:0]   product_translated_rData_value_2;
  reg        [63:0]   product_translated_rData_value_3;
  wire                when_Stream_l477_1;
  wire       [18:0]   round_w_info_tag_pixel;
  wire       [6:0]    round_w_info_tag_group;
  wire       [3:0]    round_w_info_tag_mask;
  wire                round_w_info_tag_first;
  wire                round_w_info_tag_finalInput;
  wire                round_w_info_tag_tileLast;
  wire                round_w_info_tag_last;
  wire                round_w_info_raw;
  wire                round_w_info_int16;
  wire       [5:0]    round_w_info_shift;
  wire       [31:0]   round_w_info_mac_0;
  wire       [31:0]   round_w_info_mac_1;
  wire       [31:0]   round_w_info_mac_2;
  wire       [31:0]   round_w_info_mac_3;
  wire       [31:0]   round_w_info_multiplier_0;
  wire       [31:0]   round_w_info_multiplier_1;
  wire       [31:0]   round_w_info_multiplier_2;
  wire       [31:0]   round_w_info_multiplier_3;
  wire       [63:0]   round_w_info_bias_0;
  wire       [63:0]   round_w_info_bias_1;
  wire       [63:0]   round_w_info_bias_2;
  wire       [63:0]   round_w_info_bias_3;
  wire       [15:0]   round_w_info_lower_0;
  wire       [15:0]   round_w_info_lower_1;
  wire       [15:0]   round_w_info_lower_2;
  wire       [15:0]   round_w_info_lower_3;
  wire       [15:0]   round_w_info_upper_0;
  wire       [15:0]   round_w_info_upper_1;
  wire       [15:0]   round_w_info_upper_2;
  wire       [15:0]   round_w_info_upper_3;
  wire       [63:0]   round_w_value_0;
  wire       [63:0]   round_w_value_1;
  wire       [63:0]   round_w_value_2;
  wire       [63:0]   round_w_value_3;
  wire       [63:0]   remainderMask_w;
  wire       [63:0]   half_w;
  wire       [63:0]   _zz_round_w_value_0;
  wire       [63:0]   _zz_round_w_value_0_1;
  wire       [63:0]   _zz_round_w_value_1;
  wire       [63:0]   _zz_round_w_value_1_1;
  wire       [63:0]   _zz_round_w_value_2;
  wire       [63:0]   _zz_round_w_value_2_1;
  wire       [63:0]   _zz_round_w_value_3;
  wire       [63:0]   _zz_round_w_value_3_1;
  wire                sum_translated_valid;
  reg                 sum_translated_ready;
  wire       [18:0]   sum_translated_payload_info_tag_pixel;
  wire       [6:0]    sum_translated_payload_info_tag_group;
  wire       [3:0]    sum_translated_payload_info_tag_mask;
  wire                sum_translated_payload_info_tag_first;
  wire                sum_translated_payload_info_tag_finalInput;
  wire                sum_translated_payload_info_tag_tileLast;
  wire                sum_translated_payload_info_tag_last;
  wire                sum_translated_payload_info_raw;
  wire                sum_translated_payload_info_int16;
  wire       [5:0]    sum_translated_payload_info_shift;
  wire       [31:0]   sum_translated_payload_info_mac_0;
  wire       [31:0]   sum_translated_payload_info_mac_1;
  wire       [31:0]   sum_translated_payload_info_mac_2;
  wire       [31:0]   sum_translated_payload_info_mac_3;
  wire       [31:0]   sum_translated_payload_info_multiplier_0;
  wire       [31:0]   sum_translated_payload_info_multiplier_1;
  wire       [31:0]   sum_translated_payload_info_multiplier_2;
  wire       [31:0]   sum_translated_payload_info_multiplier_3;
  wire       [63:0]   sum_translated_payload_info_bias_0;
  wire       [63:0]   sum_translated_payload_info_bias_1;
  wire       [63:0]   sum_translated_payload_info_bias_2;
  wire       [63:0]   sum_translated_payload_info_bias_3;
  wire       [15:0]   sum_translated_payload_info_lower_0;
  wire       [15:0]   sum_translated_payload_info_lower_1;
  wire       [15:0]   sum_translated_payload_info_lower_2;
  wire       [15:0]   sum_translated_payload_info_lower_3;
  wire       [15:0]   sum_translated_payload_info_upper_0;
  wire       [15:0]   sum_translated_payload_info_upper_1;
  wire       [15:0]   sum_translated_payload_info_upper_2;
  wire       [15:0]   sum_translated_payload_info_upper_3;
  wire       [63:0]   sum_translated_payload_value_0;
  wire       [63:0]   sum_translated_payload_value_1;
  wire       [63:0]   sum_translated_payload_value_2;
  wire       [63:0]   sum_translated_payload_value_3;
  wire                rounded_valid;
  wire                rounded_ready;
  wire       [18:0]   rounded_payload_info_tag_pixel;
  wire       [6:0]    rounded_payload_info_tag_group;
  wire       [3:0]    rounded_payload_info_tag_mask;
  wire                rounded_payload_info_tag_first;
  wire                rounded_payload_info_tag_finalInput;
  wire                rounded_payload_info_tag_tileLast;
  wire                rounded_payload_info_tag_last;
  wire                rounded_payload_info_raw;
  wire                rounded_payload_info_int16;
  wire       [5:0]    rounded_payload_info_shift;
  wire       [31:0]   rounded_payload_info_mac_0;
  wire       [31:0]   rounded_payload_info_mac_1;
  wire       [31:0]   rounded_payload_info_mac_2;
  wire       [31:0]   rounded_payload_info_mac_3;
  wire       [31:0]   rounded_payload_info_multiplier_0;
  wire       [31:0]   rounded_payload_info_multiplier_1;
  wire       [31:0]   rounded_payload_info_multiplier_2;
  wire       [31:0]   rounded_payload_info_multiplier_3;
  wire       [63:0]   rounded_payload_info_bias_0;
  wire       [63:0]   rounded_payload_info_bias_1;
  wire       [63:0]   rounded_payload_info_bias_2;
  wire       [63:0]   rounded_payload_info_bias_3;
  wire       [15:0]   rounded_payload_info_lower_0;
  wire       [15:0]   rounded_payload_info_lower_1;
  wire       [15:0]   rounded_payload_info_lower_2;
  wire       [15:0]   rounded_payload_info_lower_3;
  wire       [15:0]   rounded_payload_info_upper_0;
  wire       [15:0]   rounded_payload_info_upper_1;
  wire       [15:0]   rounded_payload_info_upper_2;
  wire       [15:0]   rounded_payload_info_upper_3;
  wire       [63:0]   rounded_payload_value_0;
  wire       [63:0]   rounded_payload_value_1;
  wire       [63:0]   rounded_payload_value_2;
  wire       [63:0]   rounded_payload_value_3;
  reg                 sum_translated_rValid;
  reg        [18:0]   sum_translated_rData_info_tag_pixel;
  reg        [6:0]    sum_translated_rData_info_tag_group;
  reg        [3:0]    sum_translated_rData_info_tag_mask;
  reg                 sum_translated_rData_info_tag_first;
  reg                 sum_translated_rData_info_tag_finalInput;
  reg                 sum_translated_rData_info_tag_tileLast;
  reg                 sum_translated_rData_info_tag_last;
  reg                 sum_translated_rData_info_raw;
  reg                 sum_translated_rData_info_int16;
  reg        [5:0]    sum_translated_rData_info_shift;
  reg        [31:0]   sum_translated_rData_info_mac_0;
  reg        [31:0]   sum_translated_rData_info_mac_1;
  reg        [31:0]   sum_translated_rData_info_mac_2;
  reg        [31:0]   sum_translated_rData_info_mac_3;
  reg        [31:0]   sum_translated_rData_info_multiplier_0;
  reg        [31:0]   sum_translated_rData_info_multiplier_1;
  reg        [31:0]   sum_translated_rData_info_multiplier_2;
  reg        [31:0]   sum_translated_rData_info_multiplier_3;
  reg        [63:0]   sum_translated_rData_info_bias_0;
  reg        [63:0]   sum_translated_rData_info_bias_1;
  reg        [63:0]   sum_translated_rData_info_bias_2;
  reg        [63:0]   sum_translated_rData_info_bias_3;
  reg        [15:0]   sum_translated_rData_info_lower_0;
  reg        [15:0]   sum_translated_rData_info_lower_1;
  reg        [15:0]   sum_translated_rData_info_lower_2;
  reg        [15:0]   sum_translated_rData_info_lower_3;
  reg        [15:0]   sum_translated_rData_info_upper_0;
  reg        [15:0]   sum_translated_rData_info_upper_1;
  reg        [15:0]   sum_translated_rData_info_upper_2;
  reg        [15:0]   sum_translated_rData_info_upper_3;
  reg        [63:0]   sum_translated_rData_value_0;
  reg        [63:0]   sum_translated_rData_value_1;
  reg        [63:0]   sum_translated_rData_value_2;
  reg        [63:0]   sum_translated_rData_value_3;
  wire                when_Stream_l477_2;
  wire       [18:0]   result_w_pixel;
  wire       [6:0]    result_w_group;
  wire       [3:0]    result_w_mask;
  wire                result_w_last;
  wire                result_w_raw;
  wire                result_w_int16;
  wire       [31:0]   result_w_mac_0;
  wire       [31:0]   result_w_mac_1;
  wire       [31:0]   result_w_mac_2;
  wire       [31:0]   result_w_mac_3;
  wire       [15:0]   result_w_q_0;
  wire       [15:0]   result_w_q_1;
  wire       [15:0]   result_w_q_2;
  wire       [15:0]   result_w_q_3;
  reg        [15:0]   _zz_result_w_q_0;
  wire                when_PwMac_l96;
  wire                when_PwMac_l98;
  reg        [15:0]   _zz_result_w_q_1;
  wire                when_PwMac_l96_1;
  wire                when_PwMac_l98_1;
  reg        [15:0]   _zz_result_w_q_2;
  wire                when_PwMac_l96_2;
  wire                when_PwMac_l98_2;
  reg        [15:0]   _zz_result_w_q_3;
  wire                when_PwMac_l96_3;
  wire                when_PwMac_l98_3;
  wire                rounded_translated_valid;
  reg                 rounded_translated_ready;
  wire       [18:0]   rounded_translated_payload_pixel;
  wire       [6:0]    rounded_translated_payload_group;
  wire       [3:0]    rounded_translated_payload_mask;
  wire                rounded_translated_payload_last;
  wire                rounded_translated_payload_raw;
  wire                rounded_translated_payload_int16;
  wire       [31:0]   rounded_translated_payload_mac_0;
  wire       [31:0]   rounded_translated_payload_mac_1;
  wire       [31:0]   rounded_translated_payload_mac_2;
  wire       [31:0]   rounded_translated_payload_mac_3;
  wire       [15:0]   rounded_translated_payload_q_0;
  wire       [15:0]   rounded_translated_payload_q_1;
  wire       [15:0]   rounded_translated_payload_q_2;
  wire       [15:0]   rounded_translated_payload_q_3;
  wire                rounded_translated_m2sPipe_valid;
  wire                rounded_translated_m2sPipe_ready;
  wire       [18:0]   rounded_translated_m2sPipe_payload_pixel;
  wire       [6:0]    rounded_translated_m2sPipe_payload_group;
  wire       [3:0]    rounded_translated_m2sPipe_payload_mask;
  wire                rounded_translated_m2sPipe_payload_last;
  wire                rounded_translated_m2sPipe_payload_raw;
  wire                rounded_translated_m2sPipe_payload_int16;
  wire       [31:0]   rounded_translated_m2sPipe_payload_mac_0;
  wire       [31:0]   rounded_translated_m2sPipe_payload_mac_1;
  wire       [31:0]   rounded_translated_m2sPipe_payload_mac_2;
  wire       [31:0]   rounded_translated_m2sPipe_payload_mac_3;
  wire       [15:0]   rounded_translated_m2sPipe_payload_q_0;
  wire       [15:0]   rounded_translated_m2sPipe_payload_q_1;
  wire       [15:0]   rounded_translated_m2sPipe_payload_q_2;
  wire       [15:0]   rounded_translated_m2sPipe_payload_q_3;
  reg                 rounded_translated_rValid;
  reg        [18:0]   rounded_translated_rData_pixel;
  reg        [6:0]    rounded_translated_rData_group;
  reg        [3:0]    rounded_translated_rData_mask;
  reg                 rounded_translated_rData_last;
  reg                 rounded_translated_rData_raw;
  reg                 rounded_translated_rData_int16;
  reg        [31:0]   rounded_translated_rData_mac_0;
  reg        [31:0]   rounded_translated_rData_mac_1;
  reg        [31:0]   rounded_translated_rData_mac_2;
  reg        [31:0]   rounded_translated_rData_mac_3;
  reg        [15:0]   rounded_translated_rData_q_0;
  reg        [15:0]   rounded_translated_rData_q_1;
  reg        [15:0]   rounded_translated_rData_q_2;
  reg        [15:0]   rounded_translated_rData_q_3;
  wire                when_Stream_l477_3;

  assign _zz_remainderMask_w = (64'h0000000000000001 <<< sum_payload_info_shift);
  assign _zz_half_w = (sum_payload_info_shift - 6'h01);
  assign _zz_round_w_value_0_2 = _zz_round_w_value_0_3;
  assign _zz_round_w_value_0_4 = ((sum_payload_info_shift != 6'h0) && ((half_w < _zz_round_w_value_0_1) || ((_zz_round_w_value_0_1 == half_w) && _zz_round_w_value_0[0])));
  assign _zz_round_w_value_0_3 = {63'd0, _zz_round_w_value_0_4};
  assign _zz_round_w_value_1_2 = _zz_round_w_value_1_3;
  assign _zz_round_w_value_1_4 = ((sum_payload_info_shift != 6'h0) && ((half_w < _zz_round_w_value_1_1) || ((_zz_round_w_value_1_1 == half_w) && _zz_round_w_value_1[0])));
  assign _zz_round_w_value_1_3 = {63'd0, _zz_round_w_value_1_4};
  assign _zz_round_w_value_2_2 = _zz_round_w_value_2_3;
  assign _zz_round_w_value_2_4 = ((sum_payload_info_shift != 6'h0) && ((half_w < _zz_round_w_value_2_1) || ((_zz_round_w_value_2_1 == half_w) && _zz_round_w_value_2[0])));
  assign _zz_round_w_value_2_3 = {63'd0, _zz_round_w_value_2_4};
  assign _zz_round_w_value_3_2 = _zz_round_w_value_3_3;
  assign _zz_round_w_value_3_4 = ((sum_payload_info_shift != 6'h0) && ((half_w < _zz_round_w_value_3_1) || ((_zz_round_w_value_3_1 == half_w) && _zz_round_w_value_3[0])));
  assign _zz_round_w_value_3_3 = {63'd0, _zz_round_w_value_3_4};
  assign _zz_when_PwMac_l96 = {{48{rounded_payload_info_lower_0[15]}}, rounded_payload_info_lower_0};
  assign _zz_when_PwMac_l98 = {{48{rounded_payload_info_upper_0[15]}}, rounded_payload_info_upper_0};
  assign _zz_when_PwMac_l96_1 = {{48{rounded_payload_info_lower_1[15]}}, rounded_payload_info_lower_1};
  assign _zz_when_PwMac_l98_1 = {{48{rounded_payload_info_upper_1[15]}}, rounded_payload_info_upper_1};
  assign _zz_when_PwMac_l96_2 = {{48{rounded_payload_info_lower_2[15]}}, rounded_payload_info_lower_2};
  assign _zz_when_PwMac_l98_2 = {{48{rounded_payload_info_upper_2[15]}}, rounded_payload_info_upper_2};
  assign _zz_when_PwMac_l96_3 = {{48{rounded_payload_info_lower_3[15]}}, rounded_payload_info_lower_3};
  assign _zz_when_PwMac_l98_3 = {{48{rounded_payload_info_upper_3[15]}}, rounded_payload_info_upper_3};
  assign product_w_info_tag_pixel = io_input_i_payload_tag_pixel;
  assign product_w_info_tag_group = io_input_i_payload_tag_group;
  assign product_w_info_tag_mask = io_input_i_payload_tag_mask;
  assign product_w_info_tag_first = io_input_i_payload_tag_first;
  assign product_w_info_tag_finalInput = io_input_i_payload_tag_finalInput;
  assign product_w_info_tag_tileLast = io_input_i_payload_tag_tileLast;
  assign product_w_info_tag_last = io_input_i_payload_tag_last;
  assign product_w_info_raw = io_input_i_payload_raw;
  assign product_w_info_int16 = io_input_i_payload_int16;
  assign product_w_info_shift = io_input_i_payload_shift;
  assign product_w_info_mac_0 = io_input_i_payload_mac_0;
  assign product_w_info_mac_1 = io_input_i_payload_mac_1;
  assign product_w_info_mac_2 = io_input_i_payload_mac_2;
  assign product_w_info_mac_3 = io_input_i_payload_mac_3;
  assign product_w_info_multiplier_0 = io_input_i_payload_multiplier_0;
  assign product_w_info_multiplier_1 = io_input_i_payload_multiplier_1;
  assign product_w_info_multiplier_2 = io_input_i_payload_multiplier_2;
  assign product_w_info_multiplier_3 = io_input_i_payload_multiplier_3;
  assign product_w_info_bias_0 = io_input_i_payload_bias_0;
  assign product_w_info_bias_1 = io_input_i_payload_bias_1;
  assign product_w_info_bias_2 = io_input_i_payload_bias_2;
  assign product_w_info_bias_3 = io_input_i_payload_bias_3;
  assign product_w_info_lower_0 = io_input_i_payload_lower_0;
  assign product_w_info_lower_1 = io_input_i_payload_lower_1;
  assign product_w_info_lower_2 = io_input_i_payload_lower_2;
  assign product_w_info_lower_3 = io_input_i_payload_lower_3;
  assign product_w_info_upper_0 = io_input_i_payload_upper_0;
  assign product_w_info_upper_1 = io_input_i_payload_upper_1;
  assign product_w_info_upper_2 = io_input_i_payload_upper_2;
  assign product_w_info_upper_3 = io_input_i_payload_upper_3;
  assign product_w_value_0 = ($signed(io_input_i_payload_mac_0) * $signed(io_input_i_payload_multiplier_0));
  assign product_w_value_1 = ($signed(io_input_i_payload_mac_1) * $signed(io_input_i_payload_multiplier_1));
  assign product_w_value_2 = ($signed(io_input_i_payload_mac_2) * $signed(io_input_i_payload_multiplier_2));
  assign product_w_value_3 = ($signed(io_input_i_payload_mac_3) * $signed(io_input_i_payload_multiplier_3));
  assign io_input_i_translated_valid = io_input_i_valid;
  assign io_input_i_ready = io_input_i_translated_ready;
  assign io_input_i_translated_payload_info_tag_pixel = product_w_info_tag_pixel;
  assign io_input_i_translated_payload_info_tag_group = product_w_info_tag_group;
  assign io_input_i_translated_payload_info_tag_mask = product_w_info_tag_mask;
  assign io_input_i_translated_payload_info_tag_first = product_w_info_tag_first;
  assign io_input_i_translated_payload_info_tag_finalInput = product_w_info_tag_finalInput;
  assign io_input_i_translated_payload_info_tag_tileLast = product_w_info_tag_tileLast;
  assign io_input_i_translated_payload_info_tag_last = product_w_info_tag_last;
  assign io_input_i_translated_payload_info_raw = product_w_info_raw;
  assign io_input_i_translated_payload_info_int16 = product_w_info_int16;
  assign io_input_i_translated_payload_info_shift = product_w_info_shift;
  assign io_input_i_translated_payload_info_mac_0 = product_w_info_mac_0;
  assign io_input_i_translated_payload_info_mac_1 = product_w_info_mac_1;
  assign io_input_i_translated_payload_info_mac_2 = product_w_info_mac_2;
  assign io_input_i_translated_payload_info_mac_3 = product_w_info_mac_3;
  assign io_input_i_translated_payload_info_multiplier_0 = product_w_info_multiplier_0;
  assign io_input_i_translated_payload_info_multiplier_1 = product_w_info_multiplier_1;
  assign io_input_i_translated_payload_info_multiplier_2 = product_w_info_multiplier_2;
  assign io_input_i_translated_payload_info_multiplier_3 = product_w_info_multiplier_3;
  assign io_input_i_translated_payload_info_bias_0 = product_w_info_bias_0;
  assign io_input_i_translated_payload_info_bias_1 = product_w_info_bias_1;
  assign io_input_i_translated_payload_info_bias_2 = product_w_info_bias_2;
  assign io_input_i_translated_payload_info_bias_3 = product_w_info_bias_3;
  assign io_input_i_translated_payload_info_lower_0 = product_w_info_lower_0;
  assign io_input_i_translated_payload_info_lower_1 = product_w_info_lower_1;
  assign io_input_i_translated_payload_info_lower_2 = product_w_info_lower_2;
  assign io_input_i_translated_payload_info_lower_3 = product_w_info_lower_3;
  assign io_input_i_translated_payload_info_upper_0 = product_w_info_upper_0;
  assign io_input_i_translated_payload_info_upper_1 = product_w_info_upper_1;
  assign io_input_i_translated_payload_info_upper_2 = product_w_info_upper_2;
  assign io_input_i_translated_payload_info_upper_3 = product_w_info_upper_3;
  assign io_input_i_translated_payload_value_0 = product_w_value_0;
  assign io_input_i_translated_payload_value_1 = product_w_value_1;
  assign io_input_i_translated_payload_value_2 = product_w_value_2;
  assign io_input_i_translated_payload_value_3 = product_w_value_3;
  always @(*) begin
    io_input_i_translated_ready = product_ready;
    if(when_Stream_l477) begin
      io_input_i_translated_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! product_valid);
  assign product_valid = io_input_i_translated_rValid;
  assign product_payload_info_tag_pixel = io_input_i_translated_rData_info_tag_pixel;
  assign product_payload_info_tag_group = io_input_i_translated_rData_info_tag_group;
  assign product_payload_info_tag_mask = io_input_i_translated_rData_info_tag_mask;
  assign product_payload_info_tag_first = io_input_i_translated_rData_info_tag_first;
  assign product_payload_info_tag_finalInput = io_input_i_translated_rData_info_tag_finalInput;
  assign product_payload_info_tag_tileLast = io_input_i_translated_rData_info_tag_tileLast;
  assign product_payload_info_tag_last = io_input_i_translated_rData_info_tag_last;
  assign product_payload_info_raw = io_input_i_translated_rData_info_raw;
  assign product_payload_info_int16 = io_input_i_translated_rData_info_int16;
  assign product_payload_info_shift = io_input_i_translated_rData_info_shift;
  assign product_payload_info_mac_0 = io_input_i_translated_rData_info_mac_0;
  assign product_payload_info_mac_1 = io_input_i_translated_rData_info_mac_1;
  assign product_payload_info_mac_2 = io_input_i_translated_rData_info_mac_2;
  assign product_payload_info_mac_3 = io_input_i_translated_rData_info_mac_3;
  assign product_payload_info_multiplier_0 = io_input_i_translated_rData_info_multiplier_0;
  assign product_payload_info_multiplier_1 = io_input_i_translated_rData_info_multiplier_1;
  assign product_payload_info_multiplier_2 = io_input_i_translated_rData_info_multiplier_2;
  assign product_payload_info_multiplier_3 = io_input_i_translated_rData_info_multiplier_3;
  assign product_payload_info_bias_0 = io_input_i_translated_rData_info_bias_0;
  assign product_payload_info_bias_1 = io_input_i_translated_rData_info_bias_1;
  assign product_payload_info_bias_2 = io_input_i_translated_rData_info_bias_2;
  assign product_payload_info_bias_3 = io_input_i_translated_rData_info_bias_3;
  assign product_payload_info_lower_0 = io_input_i_translated_rData_info_lower_0;
  assign product_payload_info_lower_1 = io_input_i_translated_rData_info_lower_1;
  assign product_payload_info_lower_2 = io_input_i_translated_rData_info_lower_2;
  assign product_payload_info_lower_3 = io_input_i_translated_rData_info_lower_3;
  assign product_payload_info_upper_0 = io_input_i_translated_rData_info_upper_0;
  assign product_payload_info_upper_1 = io_input_i_translated_rData_info_upper_1;
  assign product_payload_info_upper_2 = io_input_i_translated_rData_info_upper_2;
  assign product_payload_info_upper_3 = io_input_i_translated_rData_info_upper_3;
  assign product_payload_value_0 = io_input_i_translated_rData_value_0;
  assign product_payload_value_1 = io_input_i_translated_rData_value_1;
  assign product_payload_value_2 = io_input_i_translated_rData_value_2;
  assign product_payload_value_3 = io_input_i_translated_rData_value_3;
  assign sum_w_info_tag_pixel = product_payload_info_tag_pixel;
  assign sum_w_info_tag_group = product_payload_info_tag_group;
  assign sum_w_info_tag_mask = product_payload_info_tag_mask;
  assign sum_w_info_tag_first = product_payload_info_tag_first;
  assign sum_w_info_tag_finalInput = product_payload_info_tag_finalInput;
  assign sum_w_info_tag_tileLast = product_payload_info_tag_tileLast;
  assign sum_w_info_tag_last = product_payload_info_tag_last;
  assign sum_w_info_raw = product_payload_info_raw;
  assign sum_w_info_int16 = product_payload_info_int16;
  assign sum_w_info_shift = product_payload_info_shift;
  assign sum_w_info_mac_0 = product_payload_info_mac_0;
  assign sum_w_info_mac_1 = product_payload_info_mac_1;
  assign sum_w_info_mac_2 = product_payload_info_mac_2;
  assign sum_w_info_mac_3 = product_payload_info_mac_3;
  assign sum_w_info_multiplier_0 = product_payload_info_multiplier_0;
  assign sum_w_info_multiplier_1 = product_payload_info_multiplier_1;
  assign sum_w_info_multiplier_2 = product_payload_info_multiplier_2;
  assign sum_w_info_multiplier_3 = product_payload_info_multiplier_3;
  assign sum_w_info_bias_0 = product_payload_info_bias_0;
  assign sum_w_info_bias_1 = product_payload_info_bias_1;
  assign sum_w_info_bias_2 = product_payload_info_bias_2;
  assign sum_w_info_bias_3 = product_payload_info_bias_3;
  assign sum_w_info_lower_0 = product_payload_info_lower_0;
  assign sum_w_info_lower_1 = product_payload_info_lower_1;
  assign sum_w_info_lower_2 = product_payload_info_lower_2;
  assign sum_w_info_lower_3 = product_payload_info_lower_3;
  assign sum_w_info_upper_0 = product_payload_info_upper_0;
  assign sum_w_info_upper_1 = product_payload_info_upper_1;
  assign sum_w_info_upper_2 = product_payload_info_upper_2;
  assign sum_w_info_upper_3 = product_payload_info_upper_3;
  assign sum_w_value_0 = ($signed(product_payload_value_0) + $signed(product_payload_info_bias_0));
  assign sum_w_value_1 = ($signed(product_payload_value_1) + $signed(product_payload_info_bias_1));
  assign sum_w_value_2 = ($signed(product_payload_value_2) + $signed(product_payload_info_bias_2));
  assign sum_w_value_3 = ($signed(product_payload_value_3) + $signed(product_payload_info_bias_3));
  assign product_translated_valid = product_valid;
  assign product_ready = product_translated_ready;
  assign product_translated_payload_info_tag_pixel = sum_w_info_tag_pixel;
  assign product_translated_payload_info_tag_group = sum_w_info_tag_group;
  assign product_translated_payload_info_tag_mask = sum_w_info_tag_mask;
  assign product_translated_payload_info_tag_first = sum_w_info_tag_first;
  assign product_translated_payload_info_tag_finalInput = sum_w_info_tag_finalInput;
  assign product_translated_payload_info_tag_tileLast = sum_w_info_tag_tileLast;
  assign product_translated_payload_info_tag_last = sum_w_info_tag_last;
  assign product_translated_payload_info_raw = sum_w_info_raw;
  assign product_translated_payload_info_int16 = sum_w_info_int16;
  assign product_translated_payload_info_shift = sum_w_info_shift;
  assign product_translated_payload_info_mac_0 = sum_w_info_mac_0;
  assign product_translated_payload_info_mac_1 = sum_w_info_mac_1;
  assign product_translated_payload_info_mac_2 = sum_w_info_mac_2;
  assign product_translated_payload_info_mac_3 = sum_w_info_mac_3;
  assign product_translated_payload_info_multiplier_0 = sum_w_info_multiplier_0;
  assign product_translated_payload_info_multiplier_1 = sum_w_info_multiplier_1;
  assign product_translated_payload_info_multiplier_2 = sum_w_info_multiplier_2;
  assign product_translated_payload_info_multiplier_3 = sum_w_info_multiplier_3;
  assign product_translated_payload_info_bias_0 = sum_w_info_bias_0;
  assign product_translated_payload_info_bias_1 = sum_w_info_bias_1;
  assign product_translated_payload_info_bias_2 = sum_w_info_bias_2;
  assign product_translated_payload_info_bias_3 = sum_w_info_bias_3;
  assign product_translated_payload_info_lower_0 = sum_w_info_lower_0;
  assign product_translated_payload_info_lower_1 = sum_w_info_lower_1;
  assign product_translated_payload_info_lower_2 = sum_w_info_lower_2;
  assign product_translated_payload_info_lower_3 = sum_w_info_lower_3;
  assign product_translated_payload_info_upper_0 = sum_w_info_upper_0;
  assign product_translated_payload_info_upper_1 = sum_w_info_upper_1;
  assign product_translated_payload_info_upper_2 = sum_w_info_upper_2;
  assign product_translated_payload_info_upper_3 = sum_w_info_upper_3;
  assign product_translated_payload_value_0 = sum_w_value_0;
  assign product_translated_payload_value_1 = sum_w_value_1;
  assign product_translated_payload_value_2 = sum_w_value_2;
  assign product_translated_payload_value_3 = sum_w_value_3;
  always @(*) begin
    product_translated_ready = sum_ready;
    if(when_Stream_l477_1) begin
      product_translated_ready = 1'b1;
    end
  end

  assign when_Stream_l477_1 = (! sum_valid);
  assign sum_valid = product_translated_rValid;
  assign sum_payload_info_tag_pixel = product_translated_rData_info_tag_pixel;
  assign sum_payload_info_tag_group = product_translated_rData_info_tag_group;
  assign sum_payload_info_tag_mask = product_translated_rData_info_tag_mask;
  assign sum_payload_info_tag_first = product_translated_rData_info_tag_first;
  assign sum_payload_info_tag_finalInput = product_translated_rData_info_tag_finalInput;
  assign sum_payload_info_tag_tileLast = product_translated_rData_info_tag_tileLast;
  assign sum_payload_info_tag_last = product_translated_rData_info_tag_last;
  assign sum_payload_info_raw = product_translated_rData_info_raw;
  assign sum_payload_info_int16 = product_translated_rData_info_int16;
  assign sum_payload_info_shift = product_translated_rData_info_shift;
  assign sum_payload_info_mac_0 = product_translated_rData_info_mac_0;
  assign sum_payload_info_mac_1 = product_translated_rData_info_mac_1;
  assign sum_payload_info_mac_2 = product_translated_rData_info_mac_2;
  assign sum_payload_info_mac_3 = product_translated_rData_info_mac_3;
  assign sum_payload_info_multiplier_0 = product_translated_rData_info_multiplier_0;
  assign sum_payload_info_multiplier_1 = product_translated_rData_info_multiplier_1;
  assign sum_payload_info_multiplier_2 = product_translated_rData_info_multiplier_2;
  assign sum_payload_info_multiplier_3 = product_translated_rData_info_multiplier_3;
  assign sum_payload_info_bias_0 = product_translated_rData_info_bias_0;
  assign sum_payload_info_bias_1 = product_translated_rData_info_bias_1;
  assign sum_payload_info_bias_2 = product_translated_rData_info_bias_2;
  assign sum_payload_info_bias_3 = product_translated_rData_info_bias_3;
  assign sum_payload_info_lower_0 = product_translated_rData_info_lower_0;
  assign sum_payload_info_lower_1 = product_translated_rData_info_lower_1;
  assign sum_payload_info_lower_2 = product_translated_rData_info_lower_2;
  assign sum_payload_info_lower_3 = product_translated_rData_info_lower_3;
  assign sum_payload_info_upper_0 = product_translated_rData_info_upper_0;
  assign sum_payload_info_upper_1 = product_translated_rData_info_upper_1;
  assign sum_payload_info_upper_2 = product_translated_rData_info_upper_2;
  assign sum_payload_info_upper_3 = product_translated_rData_info_upper_3;
  assign sum_payload_value_0 = product_translated_rData_value_0;
  assign sum_payload_value_1 = product_translated_rData_value_1;
  assign sum_payload_value_2 = product_translated_rData_value_2;
  assign sum_payload_value_3 = product_translated_rData_value_3;
  assign round_w_info_tag_pixel = sum_payload_info_tag_pixel;
  assign round_w_info_tag_group = sum_payload_info_tag_group;
  assign round_w_info_tag_mask = sum_payload_info_tag_mask;
  assign round_w_info_tag_first = sum_payload_info_tag_first;
  assign round_w_info_tag_finalInput = sum_payload_info_tag_finalInput;
  assign round_w_info_tag_tileLast = sum_payload_info_tag_tileLast;
  assign round_w_info_tag_last = sum_payload_info_tag_last;
  assign round_w_info_raw = sum_payload_info_raw;
  assign round_w_info_int16 = sum_payload_info_int16;
  assign round_w_info_shift = sum_payload_info_shift;
  assign round_w_info_mac_0 = sum_payload_info_mac_0;
  assign round_w_info_mac_1 = sum_payload_info_mac_1;
  assign round_w_info_mac_2 = sum_payload_info_mac_2;
  assign round_w_info_mac_3 = sum_payload_info_mac_3;
  assign round_w_info_multiplier_0 = sum_payload_info_multiplier_0;
  assign round_w_info_multiplier_1 = sum_payload_info_multiplier_1;
  assign round_w_info_multiplier_2 = sum_payload_info_multiplier_2;
  assign round_w_info_multiplier_3 = sum_payload_info_multiplier_3;
  assign round_w_info_bias_0 = sum_payload_info_bias_0;
  assign round_w_info_bias_1 = sum_payload_info_bias_1;
  assign round_w_info_bias_2 = sum_payload_info_bias_2;
  assign round_w_info_bias_3 = sum_payload_info_bias_3;
  assign round_w_info_lower_0 = sum_payload_info_lower_0;
  assign round_w_info_lower_1 = sum_payload_info_lower_1;
  assign round_w_info_lower_2 = sum_payload_info_lower_2;
  assign round_w_info_lower_3 = sum_payload_info_lower_3;
  assign round_w_info_upper_0 = sum_payload_info_upper_0;
  assign round_w_info_upper_1 = sum_payload_info_upper_1;
  assign round_w_info_upper_2 = sum_payload_info_upper_2;
  assign round_w_info_upper_3 = sum_payload_info_upper_3;
  assign remainderMask_w = (_zz_remainderMask_w - 64'h0000000000000001);
  assign half_w = (64'h0000000000000001 <<< _zz_half_w);
  assign _zz_round_w_value_0 = ($signed(sum_payload_value_0) >>> sum_payload_info_shift);
  assign _zz_round_w_value_0_1 = (sum_payload_value_0 & remainderMask_w);
  assign round_w_value_0 = ($signed(_zz_round_w_value_0) + $signed(_zz_round_w_value_0_2));
  assign _zz_round_w_value_1 = ($signed(sum_payload_value_1) >>> sum_payload_info_shift);
  assign _zz_round_w_value_1_1 = (sum_payload_value_1 & remainderMask_w);
  assign round_w_value_1 = ($signed(_zz_round_w_value_1) + $signed(_zz_round_w_value_1_2));
  assign _zz_round_w_value_2 = ($signed(sum_payload_value_2) >>> sum_payload_info_shift);
  assign _zz_round_w_value_2_1 = (sum_payload_value_2 & remainderMask_w);
  assign round_w_value_2 = ($signed(_zz_round_w_value_2) + $signed(_zz_round_w_value_2_2));
  assign _zz_round_w_value_3 = ($signed(sum_payload_value_3) >>> sum_payload_info_shift);
  assign _zz_round_w_value_3_1 = (sum_payload_value_3 & remainderMask_w);
  assign round_w_value_3 = ($signed(_zz_round_w_value_3) + $signed(_zz_round_w_value_3_2));
  assign sum_translated_valid = sum_valid;
  assign sum_ready = sum_translated_ready;
  assign sum_translated_payload_info_tag_pixel = round_w_info_tag_pixel;
  assign sum_translated_payload_info_tag_group = round_w_info_tag_group;
  assign sum_translated_payload_info_tag_mask = round_w_info_tag_mask;
  assign sum_translated_payload_info_tag_first = round_w_info_tag_first;
  assign sum_translated_payload_info_tag_finalInput = round_w_info_tag_finalInput;
  assign sum_translated_payload_info_tag_tileLast = round_w_info_tag_tileLast;
  assign sum_translated_payload_info_tag_last = round_w_info_tag_last;
  assign sum_translated_payload_info_raw = round_w_info_raw;
  assign sum_translated_payload_info_int16 = round_w_info_int16;
  assign sum_translated_payload_info_shift = round_w_info_shift;
  assign sum_translated_payload_info_mac_0 = round_w_info_mac_0;
  assign sum_translated_payload_info_mac_1 = round_w_info_mac_1;
  assign sum_translated_payload_info_mac_2 = round_w_info_mac_2;
  assign sum_translated_payload_info_mac_3 = round_w_info_mac_3;
  assign sum_translated_payload_info_multiplier_0 = round_w_info_multiplier_0;
  assign sum_translated_payload_info_multiplier_1 = round_w_info_multiplier_1;
  assign sum_translated_payload_info_multiplier_2 = round_w_info_multiplier_2;
  assign sum_translated_payload_info_multiplier_3 = round_w_info_multiplier_3;
  assign sum_translated_payload_info_bias_0 = round_w_info_bias_0;
  assign sum_translated_payload_info_bias_1 = round_w_info_bias_1;
  assign sum_translated_payload_info_bias_2 = round_w_info_bias_2;
  assign sum_translated_payload_info_bias_3 = round_w_info_bias_3;
  assign sum_translated_payload_info_lower_0 = round_w_info_lower_0;
  assign sum_translated_payload_info_lower_1 = round_w_info_lower_1;
  assign sum_translated_payload_info_lower_2 = round_w_info_lower_2;
  assign sum_translated_payload_info_lower_3 = round_w_info_lower_3;
  assign sum_translated_payload_info_upper_0 = round_w_info_upper_0;
  assign sum_translated_payload_info_upper_1 = round_w_info_upper_1;
  assign sum_translated_payload_info_upper_2 = round_w_info_upper_2;
  assign sum_translated_payload_info_upper_3 = round_w_info_upper_3;
  assign sum_translated_payload_value_0 = round_w_value_0;
  assign sum_translated_payload_value_1 = round_w_value_1;
  assign sum_translated_payload_value_2 = round_w_value_2;
  assign sum_translated_payload_value_3 = round_w_value_3;
  always @(*) begin
    sum_translated_ready = rounded_ready;
    if(when_Stream_l477_2) begin
      sum_translated_ready = 1'b1;
    end
  end

  assign when_Stream_l477_2 = (! rounded_valid);
  assign rounded_valid = sum_translated_rValid;
  assign rounded_payload_info_tag_pixel = sum_translated_rData_info_tag_pixel;
  assign rounded_payload_info_tag_group = sum_translated_rData_info_tag_group;
  assign rounded_payload_info_tag_mask = sum_translated_rData_info_tag_mask;
  assign rounded_payload_info_tag_first = sum_translated_rData_info_tag_first;
  assign rounded_payload_info_tag_finalInput = sum_translated_rData_info_tag_finalInput;
  assign rounded_payload_info_tag_tileLast = sum_translated_rData_info_tag_tileLast;
  assign rounded_payload_info_tag_last = sum_translated_rData_info_tag_last;
  assign rounded_payload_info_raw = sum_translated_rData_info_raw;
  assign rounded_payload_info_int16 = sum_translated_rData_info_int16;
  assign rounded_payload_info_shift = sum_translated_rData_info_shift;
  assign rounded_payload_info_mac_0 = sum_translated_rData_info_mac_0;
  assign rounded_payload_info_mac_1 = sum_translated_rData_info_mac_1;
  assign rounded_payload_info_mac_2 = sum_translated_rData_info_mac_2;
  assign rounded_payload_info_mac_3 = sum_translated_rData_info_mac_3;
  assign rounded_payload_info_multiplier_0 = sum_translated_rData_info_multiplier_0;
  assign rounded_payload_info_multiplier_1 = sum_translated_rData_info_multiplier_1;
  assign rounded_payload_info_multiplier_2 = sum_translated_rData_info_multiplier_2;
  assign rounded_payload_info_multiplier_3 = sum_translated_rData_info_multiplier_3;
  assign rounded_payload_info_bias_0 = sum_translated_rData_info_bias_0;
  assign rounded_payload_info_bias_1 = sum_translated_rData_info_bias_1;
  assign rounded_payload_info_bias_2 = sum_translated_rData_info_bias_2;
  assign rounded_payload_info_bias_3 = sum_translated_rData_info_bias_3;
  assign rounded_payload_info_lower_0 = sum_translated_rData_info_lower_0;
  assign rounded_payload_info_lower_1 = sum_translated_rData_info_lower_1;
  assign rounded_payload_info_lower_2 = sum_translated_rData_info_lower_2;
  assign rounded_payload_info_lower_3 = sum_translated_rData_info_lower_3;
  assign rounded_payload_info_upper_0 = sum_translated_rData_info_upper_0;
  assign rounded_payload_info_upper_1 = sum_translated_rData_info_upper_1;
  assign rounded_payload_info_upper_2 = sum_translated_rData_info_upper_2;
  assign rounded_payload_info_upper_3 = sum_translated_rData_info_upper_3;
  assign rounded_payload_value_0 = sum_translated_rData_value_0;
  assign rounded_payload_value_1 = sum_translated_rData_value_1;
  assign rounded_payload_value_2 = sum_translated_rData_value_2;
  assign rounded_payload_value_3 = sum_translated_rData_value_3;
  assign result_w_pixel = rounded_payload_info_tag_pixel;
  assign result_w_group = rounded_payload_info_tag_group;
  assign result_w_mask = rounded_payload_info_tag_mask;
  assign result_w_last = rounded_payload_info_tag_last;
  assign result_w_raw = rounded_payload_info_raw;
  assign result_w_int16 = rounded_payload_info_int16;
  assign result_w_mac_0 = (rounded_payload_info_tag_mask[0] ? rounded_payload_info_mac_0 : 32'h0);
  always @(*) begin
    _zz_result_w_q_0 = rounded_payload_value_0[15:0];
    if(when_PwMac_l96) begin
      _zz_result_w_q_0 = rounded_payload_info_lower_0;
    end else begin
      if(when_PwMac_l98) begin
        _zz_result_w_q_0 = rounded_payload_info_upper_0;
      end
    end
  end

  assign when_PwMac_l96 = ($signed(rounded_payload_value_0) < $signed(_zz_when_PwMac_l96));
  assign when_PwMac_l98 = ($signed(_zz_when_PwMac_l98) < $signed(rounded_payload_value_0));
  assign result_w_q_0 = ((rounded_payload_info_raw || (! rounded_payload_info_tag_mask[0])) ? 16'h0 : _zz_result_w_q_0);
  assign result_w_mac_1 = (rounded_payload_info_tag_mask[1] ? rounded_payload_info_mac_1 : 32'h0);
  always @(*) begin
    _zz_result_w_q_1 = rounded_payload_value_1[15:0];
    if(when_PwMac_l96_1) begin
      _zz_result_w_q_1 = rounded_payload_info_lower_1;
    end else begin
      if(when_PwMac_l98_1) begin
        _zz_result_w_q_1 = rounded_payload_info_upper_1;
      end
    end
  end

  assign when_PwMac_l96_1 = ($signed(rounded_payload_value_1) < $signed(_zz_when_PwMac_l96_1));
  assign when_PwMac_l98_1 = ($signed(_zz_when_PwMac_l98_1) < $signed(rounded_payload_value_1));
  assign result_w_q_1 = ((rounded_payload_info_raw || (! rounded_payload_info_tag_mask[1])) ? 16'h0 : _zz_result_w_q_1);
  assign result_w_mac_2 = (rounded_payload_info_tag_mask[2] ? rounded_payload_info_mac_2 : 32'h0);
  always @(*) begin
    _zz_result_w_q_2 = rounded_payload_value_2[15:0];
    if(when_PwMac_l96_2) begin
      _zz_result_w_q_2 = rounded_payload_info_lower_2;
    end else begin
      if(when_PwMac_l98_2) begin
        _zz_result_w_q_2 = rounded_payload_info_upper_2;
      end
    end
  end

  assign when_PwMac_l96_2 = ($signed(rounded_payload_value_2) < $signed(_zz_when_PwMac_l96_2));
  assign when_PwMac_l98_2 = ($signed(_zz_when_PwMac_l98_2) < $signed(rounded_payload_value_2));
  assign result_w_q_2 = ((rounded_payload_info_raw || (! rounded_payload_info_tag_mask[2])) ? 16'h0 : _zz_result_w_q_2);
  assign result_w_mac_3 = (rounded_payload_info_tag_mask[3] ? rounded_payload_info_mac_3 : 32'h0);
  always @(*) begin
    _zz_result_w_q_3 = rounded_payload_value_3[15:0];
    if(when_PwMac_l96_3) begin
      _zz_result_w_q_3 = rounded_payload_info_lower_3;
    end else begin
      if(when_PwMac_l98_3) begin
        _zz_result_w_q_3 = rounded_payload_info_upper_3;
      end
    end
  end

  assign when_PwMac_l96_3 = ($signed(rounded_payload_value_3) < $signed(_zz_when_PwMac_l96_3));
  assign when_PwMac_l98_3 = ($signed(_zz_when_PwMac_l98_3) < $signed(rounded_payload_value_3));
  assign result_w_q_3 = ((rounded_payload_info_raw || (! rounded_payload_info_tag_mask[3])) ? 16'h0 : _zz_result_w_q_3);
  assign rounded_translated_valid = rounded_valid;
  assign rounded_ready = rounded_translated_ready;
  assign rounded_translated_payload_pixel = result_w_pixel;
  assign rounded_translated_payload_group = result_w_group;
  assign rounded_translated_payload_mask = result_w_mask;
  assign rounded_translated_payload_last = result_w_last;
  assign rounded_translated_payload_raw = result_w_raw;
  assign rounded_translated_payload_int16 = result_w_int16;
  assign rounded_translated_payload_mac_0 = result_w_mac_0;
  assign rounded_translated_payload_mac_1 = result_w_mac_1;
  assign rounded_translated_payload_mac_2 = result_w_mac_2;
  assign rounded_translated_payload_mac_3 = result_w_mac_3;
  assign rounded_translated_payload_q_0 = result_w_q_0;
  assign rounded_translated_payload_q_1 = result_w_q_1;
  assign rounded_translated_payload_q_2 = result_w_q_2;
  assign rounded_translated_payload_q_3 = result_w_q_3;
  always @(*) begin
    rounded_translated_ready = rounded_translated_m2sPipe_ready;
    if(when_Stream_l477_3) begin
      rounded_translated_ready = 1'b1;
    end
  end

  assign when_Stream_l477_3 = (! rounded_translated_m2sPipe_valid);
  assign rounded_translated_m2sPipe_valid = rounded_translated_rValid;
  assign rounded_translated_m2sPipe_payload_pixel = rounded_translated_rData_pixel;
  assign rounded_translated_m2sPipe_payload_group = rounded_translated_rData_group;
  assign rounded_translated_m2sPipe_payload_mask = rounded_translated_rData_mask;
  assign rounded_translated_m2sPipe_payload_last = rounded_translated_rData_last;
  assign rounded_translated_m2sPipe_payload_raw = rounded_translated_rData_raw;
  assign rounded_translated_m2sPipe_payload_int16 = rounded_translated_rData_int16;
  assign rounded_translated_m2sPipe_payload_mac_0 = rounded_translated_rData_mac_0;
  assign rounded_translated_m2sPipe_payload_mac_1 = rounded_translated_rData_mac_1;
  assign rounded_translated_m2sPipe_payload_mac_2 = rounded_translated_rData_mac_2;
  assign rounded_translated_m2sPipe_payload_mac_3 = rounded_translated_rData_mac_3;
  assign rounded_translated_m2sPipe_payload_q_0 = rounded_translated_rData_q_0;
  assign rounded_translated_m2sPipe_payload_q_1 = rounded_translated_rData_q_1;
  assign rounded_translated_m2sPipe_payload_q_2 = rounded_translated_rData_q_2;
  assign rounded_translated_m2sPipe_payload_q_3 = rounded_translated_rData_q_3;
  assign io_output_o_valid = rounded_translated_m2sPipe_valid;
  assign rounded_translated_m2sPipe_ready = io_output_o_ready;
  assign io_output_o_payload_pixel = rounded_translated_m2sPipe_payload_pixel;
  assign io_output_o_payload_group = rounded_translated_m2sPipe_payload_group;
  assign io_output_o_payload_mask = rounded_translated_m2sPipe_payload_mask;
  assign io_output_o_payload_last = rounded_translated_m2sPipe_payload_last;
  assign io_output_o_payload_raw = rounded_translated_m2sPipe_payload_raw;
  assign io_output_o_payload_int16 = rounded_translated_m2sPipe_payload_int16;
  assign io_output_o_payload_mac_0 = rounded_translated_m2sPipe_payload_mac_0;
  assign io_output_o_payload_mac_1 = rounded_translated_m2sPipe_payload_mac_1;
  assign io_output_o_payload_mac_2 = rounded_translated_m2sPipe_payload_mac_2;
  assign io_output_o_payload_mac_3 = rounded_translated_m2sPipe_payload_mac_3;
  assign io_output_o_payload_q_0 = rounded_translated_m2sPipe_payload_q_0;
  assign io_output_o_payload_q_1 = rounded_translated_m2sPipe_payload_q_1;
  assign io_output_o_payload_q_2 = rounded_translated_m2sPipe_payload_q_2;
  assign io_output_o_payload_q_3 = rounded_translated_m2sPipe_payload_q_3;
  always @(posedge clk or negedge resetn) begin
    if(!resetn) begin
      io_input_i_translated_rValid <= 1'b0;
      product_translated_rValid <= 1'b0;
      sum_translated_rValid <= 1'b0;
      rounded_translated_rValid <= 1'b0;
    end else begin
      if(io_input_i_translated_ready) begin
        io_input_i_translated_rValid <= io_input_i_translated_valid;
      end
      if(product_translated_ready) begin
        product_translated_rValid <= product_translated_valid;
      end
      if(sum_translated_ready) begin
        sum_translated_rValid <= sum_translated_valid;
      end
      if(rounded_translated_ready) begin
        rounded_translated_rValid <= rounded_translated_valid;
      end
    end
  end

  always @(posedge clk) begin
    if(io_input_i_translated_ready) begin
      io_input_i_translated_rData_info_tag_pixel <= io_input_i_translated_payload_info_tag_pixel;
      io_input_i_translated_rData_info_tag_group <= io_input_i_translated_payload_info_tag_group;
      io_input_i_translated_rData_info_tag_mask <= io_input_i_translated_payload_info_tag_mask;
      io_input_i_translated_rData_info_tag_first <= io_input_i_translated_payload_info_tag_first;
      io_input_i_translated_rData_info_tag_finalInput <= io_input_i_translated_payload_info_tag_finalInput;
      io_input_i_translated_rData_info_tag_tileLast <= io_input_i_translated_payload_info_tag_tileLast;
      io_input_i_translated_rData_info_tag_last <= io_input_i_translated_payload_info_tag_last;
      io_input_i_translated_rData_info_raw <= io_input_i_translated_payload_info_raw;
      io_input_i_translated_rData_info_int16 <= io_input_i_translated_payload_info_int16;
      io_input_i_translated_rData_info_shift <= io_input_i_translated_payload_info_shift;
      io_input_i_translated_rData_info_mac_0 <= io_input_i_translated_payload_info_mac_0;
      io_input_i_translated_rData_info_mac_1 <= io_input_i_translated_payload_info_mac_1;
      io_input_i_translated_rData_info_mac_2 <= io_input_i_translated_payload_info_mac_2;
      io_input_i_translated_rData_info_mac_3 <= io_input_i_translated_payload_info_mac_3;
      io_input_i_translated_rData_info_multiplier_0 <= io_input_i_translated_payload_info_multiplier_0;
      io_input_i_translated_rData_info_multiplier_1 <= io_input_i_translated_payload_info_multiplier_1;
      io_input_i_translated_rData_info_multiplier_2 <= io_input_i_translated_payload_info_multiplier_2;
      io_input_i_translated_rData_info_multiplier_3 <= io_input_i_translated_payload_info_multiplier_3;
      io_input_i_translated_rData_info_bias_0 <= io_input_i_translated_payload_info_bias_0;
      io_input_i_translated_rData_info_bias_1 <= io_input_i_translated_payload_info_bias_1;
      io_input_i_translated_rData_info_bias_2 <= io_input_i_translated_payload_info_bias_2;
      io_input_i_translated_rData_info_bias_3 <= io_input_i_translated_payload_info_bias_3;
      io_input_i_translated_rData_info_lower_0 <= io_input_i_translated_payload_info_lower_0;
      io_input_i_translated_rData_info_lower_1 <= io_input_i_translated_payload_info_lower_1;
      io_input_i_translated_rData_info_lower_2 <= io_input_i_translated_payload_info_lower_2;
      io_input_i_translated_rData_info_lower_3 <= io_input_i_translated_payload_info_lower_3;
      io_input_i_translated_rData_info_upper_0 <= io_input_i_translated_payload_info_upper_0;
      io_input_i_translated_rData_info_upper_1 <= io_input_i_translated_payload_info_upper_1;
      io_input_i_translated_rData_info_upper_2 <= io_input_i_translated_payload_info_upper_2;
      io_input_i_translated_rData_info_upper_3 <= io_input_i_translated_payload_info_upper_3;
      io_input_i_translated_rData_value_0 <= io_input_i_translated_payload_value_0;
      io_input_i_translated_rData_value_1 <= io_input_i_translated_payload_value_1;
      io_input_i_translated_rData_value_2 <= io_input_i_translated_payload_value_2;
      io_input_i_translated_rData_value_3 <= io_input_i_translated_payload_value_3;
    end
    if(product_translated_ready) begin
      product_translated_rData_info_tag_pixel <= product_translated_payload_info_tag_pixel;
      product_translated_rData_info_tag_group <= product_translated_payload_info_tag_group;
      product_translated_rData_info_tag_mask <= product_translated_payload_info_tag_mask;
      product_translated_rData_info_tag_first <= product_translated_payload_info_tag_first;
      product_translated_rData_info_tag_finalInput <= product_translated_payload_info_tag_finalInput;
      product_translated_rData_info_tag_tileLast <= product_translated_payload_info_tag_tileLast;
      product_translated_rData_info_tag_last <= product_translated_payload_info_tag_last;
      product_translated_rData_info_raw <= product_translated_payload_info_raw;
      product_translated_rData_info_int16 <= product_translated_payload_info_int16;
      product_translated_rData_info_shift <= product_translated_payload_info_shift;
      product_translated_rData_info_mac_0 <= product_translated_payload_info_mac_0;
      product_translated_rData_info_mac_1 <= product_translated_payload_info_mac_1;
      product_translated_rData_info_mac_2 <= product_translated_payload_info_mac_2;
      product_translated_rData_info_mac_3 <= product_translated_payload_info_mac_3;
      product_translated_rData_info_multiplier_0 <= product_translated_payload_info_multiplier_0;
      product_translated_rData_info_multiplier_1 <= product_translated_payload_info_multiplier_1;
      product_translated_rData_info_multiplier_2 <= product_translated_payload_info_multiplier_2;
      product_translated_rData_info_multiplier_3 <= product_translated_payload_info_multiplier_3;
      product_translated_rData_info_bias_0 <= product_translated_payload_info_bias_0;
      product_translated_rData_info_bias_1 <= product_translated_payload_info_bias_1;
      product_translated_rData_info_bias_2 <= product_translated_payload_info_bias_2;
      product_translated_rData_info_bias_3 <= product_translated_payload_info_bias_3;
      product_translated_rData_info_lower_0 <= product_translated_payload_info_lower_0;
      product_translated_rData_info_lower_1 <= product_translated_payload_info_lower_1;
      product_translated_rData_info_lower_2 <= product_translated_payload_info_lower_2;
      product_translated_rData_info_lower_3 <= product_translated_payload_info_lower_3;
      product_translated_rData_info_upper_0 <= product_translated_payload_info_upper_0;
      product_translated_rData_info_upper_1 <= product_translated_payload_info_upper_1;
      product_translated_rData_info_upper_2 <= product_translated_payload_info_upper_2;
      product_translated_rData_info_upper_3 <= product_translated_payload_info_upper_3;
      product_translated_rData_value_0 <= product_translated_payload_value_0;
      product_translated_rData_value_1 <= product_translated_payload_value_1;
      product_translated_rData_value_2 <= product_translated_payload_value_2;
      product_translated_rData_value_3 <= product_translated_payload_value_3;
    end
    if(sum_translated_ready) begin
      sum_translated_rData_info_tag_pixel <= sum_translated_payload_info_tag_pixel;
      sum_translated_rData_info_tag_group <= sum_translated_payload_info_tag_group;
      sum_translated_rData_info_tag_mask <= sum_translated_payload_info_tag_mask;
      sum_translated_rData_info_tag_first <= sum_translated_payload_info_tag_first;
      sum_translated_rData_info_tag_finalInput <= sum_translated_payload_info_tag_finalInput;
      sum_translated_rData_info_tag_tileLast <= sum_translated_payload_info_tag_tileLast;
      sum_translated_rData_info_tag_last <= sum_translated_payload_info_tag_last;
      sum_translated_rData_info_raw <= sum_translated_payload_info_raw;
      sum_translated_rData_info_int16 <= sum_translated_payload_info_int16;
      sum_translated_rData_info_shift <= sum_translated_payload_info_shift;
      sum_translated_rData_info_mac_0 <= sum_translated_payload_info_mac_0;
      sum_translated_rData_info_mac_1 <= sum_translated_payload_info_mac_1;
      sum_translated_rData_info_mac_2 <= sum_translated_payload_info_mac_2;
      sum_translated_rData_info_mac_3 <= sum_translated_payload_info_mac_3;
      sum_translated_rData_info_multiplier_0 <= sum_translated_payload_info_multiplier_0;
      sum_translated_rData_info_multiplier_1 <= sum_translated_payload_info_multiplier_1;
      sum_translated_rData_info_multiplier_2 <= sum_translated_payload_info_multiplier_2;
      sum_translated_rData_info_multiplier_3 <= sum_translated_payload_info_multiplier_3;
      sum_translated_rData_info_bias_0 <= sum_translated_payload_info_bias_0;
      sum_translated_rData_info_bias_1 <= sum_translated_payload_info_bias_1;
      sum_translated_rData_info_bias_2 <= sum_translated_payload_info_bias_2;
      sum_translated_rData_info_bias_3 <= sum_translated_payload_info_bias_3;
      sum_translated_rData_info_lower_0 <= sum_translated_payload_info_lower_0;
      sum_translated_rData_info_lower_1 <= sum_translated_payload_info_lower_1;
      sum_translated_rData_info_lower_2 <= sum_translated_payload_info_lower_2;
      sum_translated_rData_info_lower_3 <= sum_translated_payload_info_lower_3;
      sum_translated_rData_info_upper_0 <= sum_translated_payload_info_upper_0;
      sum_translated_rData_info_upper_1 <= sum_translated_payload_info_upper_1;
      sum_translated_rData_info_upper_2 <= sum_translated_payload_info_upper_2;
      sum_translated_rData_info_upper_3 <= sum_translated_payload_info_upper_3;
      sum_translated_rData_value_0 <= sum_translated_payload_value_0;
      sum_translated_rData_value_1 <= sum_translated_payload_value_1;
      sum_translated_rData_value_2 <= sum_translated_payload_value_2;
      sum_translated_rData_value_3 <= sum_translated_payload_value_3;
    end
    if(rounded_translated_ready) begin
      rounded_translated_rData_pixel <= rounded_translated_payload_pixel;
      rounded_translated_rData_group <= rounded_translated_payload_group;
      rounded_translated_rData_mask <= rounded_translated_payload_mask;
      rounded_translated_rData_last <= rounded_translated_payload_last;
      rounded_translated_rData_raw <= rounded_translated_payload_raw;
      rounded_translated_rData_int16 <= rounded_translated_payload_int16;
      rounded_translated_rData_mac_0 <= rounded_translated_payload_mac_0;
      rounded_translated_rData_mac_1 <= rounded_translated_payload_mac_1;
      rounded_translated_rData_mac_2 <= rounded_translated_payload_mac_2;
      rounded_translated_rData_mac_3 <= rounded_translated_payload_mac_3;
      rounded_translated_rData_q_0 <= rounded_translated_payload_q_0;
      rounded_translated_rData_q_1 <= rounded_translated_payload_q_1;
      rounded_translated_rData_q_2 <= rounded_translated_payload_q_2;
      rounded_translated_rData_q_3 <= rounded_translated_payload_q_3;
    end
  end


endmodule
