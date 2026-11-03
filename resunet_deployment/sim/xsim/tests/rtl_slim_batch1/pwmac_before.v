// Generator : SpinalHDL v1.12.3    git head : 591e64062329e5e2e2b81f4d52422948053edb97
// Component : PwMac_before
// Git hash  : 22833009c62b65d1ff5487a4f76e31eebe4c7fba

`timescale 1ns/1ps

module PwMac_before (
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

  wire                pwWeightBank_ena;
  wire       [0:0]    pwWeightBank_wea;
  wire       [10:0]   pwWeightBank_addra;
  wire                pwWeightBank_1_ena;
  wire       [0:0]    pwWeightBank_1_wea;
  wire       [10:0]   pwWeightBank_1_addra;
  wire                pwWeightBank_2_ena;
  wire       [0:0]    pwWeightBank_2_wea;
  wire       [10:0]   pwWeightBank_2_addra;
  wire                pwWeightBank_3_ena;
  wire       [0:0]    pwWeightBank_3_wea;
  wire       [10:0]   pwWeightBank_3_addra;
  reg        [127:0]  inputMem_spinal_port1;
  reg        [511:0]  paramMemory_spinal_port1;
  wire       [511:0]  pwWeightBank_doutb;
  wire       [511:0]  pwWeightBank_1_doutb;
  wire       [511:0]  pwWeightBank_2_doutb;
  wire       [511:0]  pwWeightBank_3_doutb;
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
  wire       [9:0]    _zz_cfgParamGroups_w;
  wire       [13:0]   _zz_weightTotal_r;
  wire       [7:0]    _zz_io_params_i_ready;
  wire       [9:0]    _zz_io_params_i_ready_1;
  wire       [5:0]    _zz_when_PwMac_l243;
  wire       [7:0]    _zz_when_PwMac_l249;
  wire       [9:0]    _zz_when_PwMac_l249_1;
  wire       [4:0]    _zz_tileCount_r;
  wire       [18:0]   _zz_tileLastPixel_r;
  wire       [18:0]   _zz_tileLastPixel_r_1;
  wire       [10:0]   _zz_fillAddress_w;
  wire       [10:0]   _zz_fillAddress_w_1;
  wire       [10:0]   _zz_fillAddress_w_2;
  wire       [4:0]    _zz_when_PwMac_l283;
  wire       [5:0]    _zz_when_PwMac_l285;
  wire       [31:0]   _zz_fillGroupBase_r;
  wire       [31:0]   _zz_fillReadAddr_r;
  wire       [18:0]   _zz_request_payload_tag_pixel;
  wire       [12:0]   _zz_request_payload_tag_group;
  wire       [9:0]    _zz_request_payload_tag_group_1;
  wire       [14:0]   _zz_request_payload_tag_mask;
  wire       [14:0]   _zz_request_payload_tag_mask_1;
  wire       [9:0]    _zz_request_payload_tag_mask_2;
  wire       [14:0]   _zz_request_payload_tag_mask_3;
  wire       [14:0]   _zz_request_payload_tag_mask_4;
  wire       [14:0]   _zz_request_payload_tag_mask_5;
  wire       [9:0]    _zz_request_payload_tag_mask_6;
  wire       [14:0]   _zz_request_payload_tag_mask_7;
  wire       [14:0]   _zz_request_payload_tag_mask_8;
  wire       [14:0]   _zz_request_payload_tag_mask_9;
  wire       [9:0]    _zz_request_payload_tag_mask_10;
  wire       [14:0]   _zz_request_payload_tag_mask_11;
  wire       [14:0]   _zz_request_payload_tag_mask_12;
  wire       [14:0]   _zz_request_payload_tag_mask_13;
  wire       [9:0]    _zz_request_payload_tag_mask_14;
  wire       [14:0]   _zz_request_payload_tag_mask_15;
  wire       [5:0]    _zz_request_payload_tag_finalInput;
  wire       [4:0]    _zz_request_payload_tag_tileLast;
  wire       [5:0]    _zz_request_payload_tag_tileLast_1;
  wire       [5:0]    _zz_request_payload_tag_last;
  wire       [5:0]    _zz_request_payload_tag_last_1;
  wire       [18:0]   _zz_request_payload_tag_last_2;
  wire       [18:0]   _zz_request_payload_tag_last_3;
  wire       [10:0]   _zz_inputAddress_w;
  wire       [10:0]   _zz_inputAddress_w_1;
  wire       [10:0]   _zz_inputAddress_w_2;
  wire       [10:0]   _zz_weightAddress_w;
  wire       [10:0]   _zz_weightAddress_w_1;
  wire       [11:0]   _zz_addra;
  wire       [11:0]   _zz_addra_1;
  wire       [11:0]   _zz_addra_2;
  wire       [11:0]   _zz_addra_3;
  wire       [11:0]   _zz_addra_4;
  wire       [11:0]   _zz_addra_5;
  wire       [11:0]   _zz_addra_6;
  wire       [11:0]   _zz_addra_7;
  wire       [11:0]   _zz_addra_8;
  wire       [11:0]   _zz_addra_9;
  wire       [11:0]   _zz_addra_10;
  wire       [11:0]   _zz_addra_11;
  wire       [4:0]    _zz_when_PwMac_l345;
  wire       [5:0]    _zz_when_PwMac_l347;
  wire       [14:0]   _zz_operands_w_mask;
  wire       [14:0]   _zz_operands_w_mask_1;
  wire       [9:0]    _zz_operands_w_mask_2;
  wire       [14:0]   _zz_operands_w_mask_3;
  wire       [14:0]   _zz_operands_w_mask_4;
  wire       [14:0]   _zz_operands_w_mask_5;
  wire       [9:0]    _zz_operands_w_mask_6;
  wire       [14:0]   _zz_operands_w_mask_7;
  wire       [14:0]   _zz_operands_w_mask_8;
  wire       [14:0]   _zz_operands_w_mask_9;
  wire       [9:0]    _zz_operands_w_mask_10;
  wire       [14:0]   _zz_operands_w_mask_11;
  wire       [14:0]   _zz_operands_w_mask_12;
  wire       [14:0]   _zz_operands_w_mask_13;
  wire       [9:0]    _zz_operands_w_mask_14;
  wire       [14:0]   _zz_operands_w_mask_15;
  wire       [14:0]   _zz_operands_w_mask_16;
  wire       [14:0]   _zz_operands_w_mask_17;
  wire       [9:0]    _zz_operands_w_mask_18;
  wire       [14:0]   _zz_operands_w_mask_19;
  wire       [14:0]   _zz_operands_w_mask_20;
  wire       [14:0]   _zz_operands_w_mask_21;
  wire       [9:0]    _zz_operands_w_mask_22;
  wire       [14:0]   _zz_operands_w_mask_23;
  wire       [14:0]   _zz_operands_w_mask_24;
  wire       [14:0]   _zz_operands_w_mask_25;
  wire       [9:0]    _zz_operands_w_mask_26;
  wire       [14:0]   _zz_operands_w_mask_27;
  wire       [14:0]   _zz_operands_w_mask_28;
  wire       [14:0]   _zz_operands_w_mask_29;
  wire       [9:0]    _zz_operands_w_mask_30;
  wire       [14:0]   _zz_operands_w_mask_31;
  wire       [14:0]   _zz_operands_w_mask_32;
  wire       [14:0]   _zz_operands_w_mask_33;
  wire       [9:0]    _zz_operands_w_mask_34;
  wire       [14:0]   _zz_operands_w_mask_35;
  wire       [14:0]   _zz_operands_w_mask_36;
  wire       [14:0]   _zz_operands_w_mask_37;
  wire       [9:0]    _zz_operands_w_mask_38;
  wire       [14:0]   _zz_operands_w_mask_39;
  wire       [14:0]   _zz_operands_w_mask_40;
  wire       [14:0]   _zz_operands_w_mask_41;
  wire       [9:0]    _zz_operands_w_mask_42;
  wire       [14:0]   _zz_operands_w_mask_43;
  wire       [14:0]   _zz_operands_w_mask_44;
  wire       [14:0]   _zz_operands_w_mask_45;
  wire       [9:0]    _zz_operands_w_mask_46;
  wire       [14:0]   _zz_operands_w_mask_47;
  wire       [14:0]   _zz_operands_w_mask_48;
  wire       [14:0]   _zz_operands_w_mask_49;
  wire       [9:0]    _zz_operands_w_mask_50;
  wire       [14:0]   _zz_operands_w_mask_51;
  wire       [14:0]   _zz_operands_w_mask_52;
  wire       [14:0]   _zz_operands_w_mask_53;
  wire       [9:0]    _zz_operands_w_mask_54;
  wire       [14:0]   _zz_operands_w_mask_55;
  wire       [14:0]   _zz_operands_w_mask_56;
  wire       [14:0]   _zz_operands_w_mask_57;
  wire       [9:0]    _zz_operands_w_mask_58;
  wire       [14:0]   _zz_operands_w_mask_59;
  wire       [14:0]   _zz_operands_w_mask_60;
  wire       [14:0]   _zz_operands_w_mask_61;
  wire       [9:0]    _zz_operands_w_mask_62;
  wire       [14:0]   _zz_operands_w_mask_63;
  wire       [7:0]    _zz_products_w_values_0_0;
  wire       [7:0]    _zz_products_w_values_0_0_1;
  wire       [7:0]    _zz_products_w_values_0_0_2;
  wire       [7:0]    _zz_products_w_values_0_1;
  wire       [7:0]    _zz_products_w_values_0_1_1;
  wire       [7:0]    _zz_products_w_values_0_1_2;
  wire       [7:0]    _zz_products_w_values_0_2;
  wire       [7:0]    _zz_products_w_values_0_2_1;
  wire       [7:0]    _zz_products_w_values_0_2_2;
  wire       [7:0]    _zz_products_w_values_0_3;
  wire       [7:0]    _zz_products_w_values_0_3_1;
  wire       [7:0]    _zz_products_w_values_0_3_2;
  wire       [7:0]    _zz_products_w_values_0_4;
  wire       [7:0]    _zz_products_w_values_0_4_1;
  wire       [7:0]    _zz_products_w_values_0_4_2;
  wire       [7:0]    _zz_products_w_values_0_5;
  wire       [7:0]    _zz_products_w_values_0_5_1;
  wire       [7:0]    _zz_products_w_values_0_5_2;
  wire       [7:0]    _zz_products_w_values_0_6;
  wire       [7:0]    _zz_products_w_values_0_6_1;
  wire       [7:0]    _zz_products_w_values_0_6_2;
  wire       [7:0]    _zz_products_w_values_0_7;
  wire       [7:0]    _zz_products_w_values_0_7_1;
  wire       [7:0]    _zz_products_w_values_0_7_2;
  wire       [7:0]    _zz_products_w_values_0_8;
  wire       [7:0]    _zz_products_w_values_0_8_1;
  wire       [7:0]    _zz_products_w_values_0_8_2;
  wire       [7:0]    _zz_products_w_values_0_9;
  wire       [7:0]    _zz_products_w_values_0_9_1;
  wire       [7:0]    _zz_products_w_values_0_9_2;
  wire       [7:0]    _zz_products_w_values_0_10;
  wire       [7:0]    _zz_products_w_values_0_10_1;
  wire       [7:0]    _zz_products_w_values_0_10_2;
  wire       [7:0]    _zz_products_w_values_0_11;
  wire       [7:0]    _zz_products_w_values_0_11_1;
  wire       [7:0]    _zz_products_w_values_0_11_2;
  wire       [7:0]    _zz_products_w_values_0_12;
  wire       [7:0]    _zz_products_w_values_0_12_1;
  wire       [7:0]    _zz_products_w_values_0_12_2;
  wire       [7:0]    _zz_products_w_values_0_13;
  wire       [7:0]    _zz_products_w_values_0_13_1;
  wire       [7:0]    _zz_products_w_values_0_13_2;
  wire       [7:0]    _zz_products_w_values_0_14;
  wire       [7:0]    _zz_products_w_values_0_14_1;
  wire       [7:0]    _zz_products_w_values_0_14_2;
  wire       [7:0]    _zz_products_w_values_0_15;
  wire       [7:0]    _zz_products_w_values_0_15_1;
  wire       [7:0]    _zz_products_w_values_0_15_2;
  wire       [7:0]    _zz_products_w_values_1_0;
  wire       [7:0]    _zz_products_w_values_1_0_1;
  wire       [7:0]    _zz_products_w_values_1_0_2;
  wire       [7:0]    _zz_products_w_values_1_1;
  wire       [7:0]    _zz_products_w_values_1_1_1;
  wire       [7:0]    _zz_products_w_values_1_1_2;
  wire       [7:0]    _zz_products_w_values_1_2;
  wire       [7:0]    _zz_products_w_values_1_2_1;
  wire       [7:0]    _zz_products_w_values_1_2_2;
  wire       [7:0]    _zz_products_w_values_1_3;
  wire       [7:0]    _zz_products_w_values_1_3_1;
  wire       [7:0]    _zz_products_w_values_1_3_2;
  wire       [7:0]    _zz_products_w_values_1_4;
  wire       [7:0]    _zz_products_w_values_1_4_1;
  wire       [7:0]    _zz_products_w_values_1_4_2;
  wire       [7:0]    _zz_products_w_values_1_5;
  wire       [7:0]    _zz_products_w_values_1_5_1;
  wire       [7:0]    _zz_products_w_values_1_5_2;
  wire       [7:0]    _zz_products_w_values_1_6;
  wire       [7:0]    _zz_products_w_values_1_6_1;
  wire       [7:0]    _zz_products_w_values_1_6_2;
  wire       [7:0]    _zz_products_w_values_1_7;
  wire       [7:0]    _zz_products_w_values_1_7_1;
  wire       [7:0]    _zz_products_w_values_1_7_2;
  wire       [7:0]    _zz_products_w_values_1_8;
  wire       [7:0]    _zz_products_w_values_1_8_1;
  wire       [7:0]    _zz_products_w_values_1_8_2;
  wire       [7:0]    _zz_products_w_values_1_9;
  wire       [7:0]    _zz_products_w_values_1_9_1;
  wire       [7:0]    _zz_products_w_values_1_9_2;
  wire       [7:0]    _zz_products_w_values_1_10;
  wire       [7:0]    _zz_products_w_values_1_10_1;
  wire       [7:0]    _zz_products_w_values_1_10_2;
  wire       [7:0]    _zz_products_w_values_1_11;
  wire       [7:0]    _zz_products_w_values_1_11_1;
  wire       [7:0]    _zz_products_w_values_1_11_2;
  wire       [7:0]    _zz_products_w_values_1_12;
  wire       [7:0]    _zz_products_w_values_1_12_1;
  wire       [7:0]    _zz_products_w_values_1_12_2;
  wire       [7:0]    _zz_products_w_values_1_13;
  wire       [7:0]    _zz_products_w_values_1_13_1;
  wire       [7:0]    _zz_products_w_values_1_13_2;
  wire       [7:0]    _zz_products_w_values_1_14;
  wire       [7:0]    _zz_products_w_values_1_14_1;
  wire       [7:0]    _zz_products_w_values_1_14_2;
  wire       [7:0]    _zz_products_w_values_1_15;
  wire       [7:0]    _zz_products_w_values_1_15_1;
  wire       [7:0]    _zz_products_w_values_1_15_2;
  wire       [7:0]    _zz_products_w_values_2_0;
  wire       [7:0]    _zz_products_w_values_2_0_1;
  wire       [7:0]    _zz_products_w_values_2_0_2;
  wire       [7:0]    _zz_products_w_values_2_1;
  wire       [7:0]    _zz_products_w_values_2_1_1;
  wire       [7:0]    _zz_products_w_values_2_1_2;
  wire       [7:0]    _zz_products_w_values_2_2;
  wire       [7:0]    _zz_products_w_values_2_2_1;
  wire       [7:0]    _zz_products_w_values_2_2_2;
  wire       [7:0]    _zz_products_w_values_2_3;
  wire       [7:0]    _zz_products_w_values_2_3_1;
  wire       [7:0]    _zz_products_w_values_2_3_2;
  wire       [7:0]    _zz_products_w_values_2_4;
  wire       [7:0]    _zz_products_w_values_2_4_1;
  wire       [7:0]    _zz_products_w_values_2_4_2;
  wire       [7:0]    _zz_products_w_values_2_5;
  wire       [7:0]    _zz_products_w_values_2_5_1;
  wire       [7:0]    _zz_products_w_values_2_5_2;
  wire       [7:0]    _zz_products_w_values_2_6;
  wire       [7:0]    _zz_products_w_values_2_6_1;
  wire       [7:0]    _zz_products_w_values_2_6_2;
  wire       [7:0]    _zz_products_w_values_2_7;
  wire       [7:0]    _zz_products_w_values_2_7_1;
  wire       [7:0]    _zz_products_w_values_2_7_2;
  wire       [7:0]    _zz_products_w_values_2_8;
  wire       [7:0]    _zz_products_w_values_2_8_1;
  wire       [7:0]    _zz_products_w_values_2_8_2;
  wire       [7:0]    _zz_products_w_values_2_9;
  wire       [7:0]    _zz_products_w_values_2_9_1;
  wire       [7:0]    _zz_products_w_values_2_9_2;
  wire       [7:0]    _zz_products_w_values_2_10;
  wire       [7:0]    _zz_products_w_values_2_10_1;
  wire       [7:0]    _zz_products_w_values_2_10_2;
  wire       [7:0]    _zz_products_w_values_2_11;
  wire       [7:0]    _zz_products_w_values_2_11_1;
  wire       [7:0]    _zz_products_w_values_2_11_2;
  wire       [7:0]    _zz_products_w_values_2_12;
  wire       [7:0]    _zz_products_w_values_2_12_1;
  wire       [7:0]    _zz_products_w_values_2_12_2;
  wire       [7:0]    _zz_products_w_values_2_13;
  wire       [7:0]    _zz_products_w_values_2_13_1;
  wire       [7:0]    _zz_products_w_values_2_13_2;
  wire       [7:0]    _zz_products_w_values_2_14;
  wire       [7:0]    _zz_products_w_values_2_14_1;
  wire       [7:0]    _zz_products_w_values_2_14_2;
  wire       [7:0]    _zz_products_w_values_2_15;
  wire       [7:0]    _zz_products_w_values_2_15_1;
  wire       [7:0]    _zz_products_w_values_2_15_2;
  wire       [7:0]    _zz_products_w_values_3_0;
  wire       [7:0]    _zz_products_w_values_3_0_1;
  wire       [7:0]    _zz_products_w_values_3_0_2;
  wire       [7:0]    _zz_products_w_values_3_1;
  wire       [7:0]    _zz_products_w_values_3_1_1;
  wire       [7:0]    _zz_products_w_values_3_1_2;
  wire       [7:0]    _zz_products_w_values_3_2;
  wire       [7:0]    _zz_products_w_values_3_2_1;
  wire       [7:0]    _zz_products_w_values_3_2_2;
  wire       [7:0]    _zz_products_w_values_3_3;
  wire       [7:0]    _zz_products_w_values_3_3_1;
  wire       [7:0]    _zz_products_w_values_3_3_2;
  wire       [7:0]    _zz_products_w_values_3_4;
  wire       [7:0]    _zz_products_w_values_3_4_1;
  wire       [7:0]    _zz_products_w_values_3_4_2;
  wire       [7:0]    _zz_products_w_values_3_5;
  wire       [7:0]    _zz_products_w_values_3_5_1;
  wire       [7:0]    _zz_products_w_values_3_5_2;
  wire       [7:0]    _zz_products_w_values_3_6;
  wire       [7:0]    _zz_products_w_values_3_6_1;
  wire       [7:0]    _zz_products_w_values_3_6_2;
  wire       [7:0]    _zz_products_w_values_3_7;
  wire       [7:0]    _zz_products_w_values_3_7_1;
  wire       [7:0]    _zz_products_w_values_3_7_2;
  wire       [7:0]    _zz_products_w_values_3_8;
  wire       [7:0]    _zz_products_w_values_3_8_1;
  wire       [7:0]    _zz_products_w_values_3_8_2;
  wire       [7:0]    _zz_products_w_values_3_9;
  wire       [7:0]    _zz_products_w_values_3_9_1;
  wire       [7:0]    _zz_products_w_values_3_9_2;
  wire       [7:0]    _zz_products_w_values_3_10;
  wire       [7:0]    _zz_products_w_values_3_10_1;
  wire       [7:0]    _zz_products_w_values_3_10_2;
  wire       [7:0]    _zz_products_w_values_3_11;
  wire       [7:0]    _zz_products_w_values_3_11_1;
  wire       [7:0]    _zz_products_w_values_3_11_2;
  wire       [7:0]    _zz_products_w_values_3_12;
  wire       [7:0]    _zz_products_w_values_3_12_1;
  wire       [7:0]    _zz_products_w_values_3_12_2;
  wire       [7:0]    _zz_products_w_values_3_13;
  wire       [7:0]    _zz_products_w_values_3_13_1;
  wire       [7:0]    _zz_products_w_values_3_13_2;
  wire       [7:0]    _zz_products_w_values_3_14;
  wire       [7:0]    _zz_products_w_values_3_14_1;
  wire       [7:0]    _zz_products_w_values_3_14_2;
  wire       [7:0]    _zz_products_w_values_3_15;
  wire       [7:0]    _zz_products_w_values_3_15_1;
  wire       [7:0]    _zz_products_w_values_3_15_2;
  wire       [7:0]    _zz_products_w_values_4_0;
  wire       [7:0]    _zz_products_w_values_4_0_1;
  wire       [7:0]    _zz_products_w_values_4_0_2;
  wire       [7:0]    _zz_products_w_values_4_1;
  wire       [7:0]    _zz_products_w_values_4_1_1;
  wire       [7:0]    _zz_products_w_values_4_1_2;
  wire       [7:0]    _zz_products_w_values_4_2;
  wire       [7:0]    _zz_products_w_values_4_2_1;
  wire       [7:0]    _zz_products_w_values_4_2_2;
  wire       [7:0]    _zz_products_w_values_4_3;
  wire       [7:0]    _zz_products_w_values_4_3_1;
  wire       [7:0]    _zz_products_w_values_4_3_2;
  wire       [7:0]    _zz_products_w_values_4_4;
  wire       [7:0]    _zz_products_w_values_4_4_1;
  wire       [7:0]    _zz_products_w_values_4_4_2;
  wire       [7:0]    _zz_products_w_values_4_5;
  wire       [7:0]    _zz_products_w_values_4_5_1;
  wire       [7:0]    _zz_products_w_values_4_5_2;
  wire       [7:0]    _zz_products_w_values_4_6;
  wire       [7:0]    _zz_products_w_values_4_6_1;
  wire       [7:0]    _zz_products_w_values_4_6_2;
  wire       [7:0]    _zz_products_w_values_4_7;
  wire       [7:0]    _zz_products_w_values_4_7_1;
  wire       [7:0]    _zz_products_w_values_4_7_2;
  wire       [7:0]    _zz_products_w_values_4_8;
  wire       [7:0]    _zz_products_w_values_4_8_1;
  wire       [7:0]    _zz_products_w_values_4_8_2;
  wire       [7:0]    _zz_products_w_values_4_9;
  wire       [7:0]    _zz_products_w_values_4_9_1;
  wire       [7:0]    _zz_products_w_values_4_9_2;
  wire       [7:0]    _zz_products_w_values_4_10;
  wire       [7:0]    _zz_products_w_values_4_10_1;
  wire       [7:0]    _zz_products_w_values_4_10_2;
  wire       [7:0]    _zz_products_w_values_4_11;
  wire       [7:0]    _zz_products_w_values_4_11_1;
  wire       [7:0]    _zz_products_w_values_4_11_2;
  wire       [7:0]    _zz_products_w_values_4_12;
  wire       [7:0]    _zz_products_w_values_4_12_1;
  wire       [7:0]    _zz_products_w_values_4_12_2;
  wire       [7:0]    _zz_products_w_values_4_13;
  wire       [7:0]    _zz_products_w_values_4_13_1;
  wire       [7:0]    _zz_products_w_values_4_13_2;
  wire       [7:0]    _zz_products_w_values_4_14;
  wire       [7:0]    _zz_products_w_values_4_14_1;
  wire       [7:0]    _zz_products_w_values_4_14_2;
  wire       [7:0]    _zz_products_w_values_4_15;
  wire       [7:0]    _zz_products_w_values_4_15_1;
  wire       [7:0]    _zz_products_w_values_4_15_2;
  wire       [7:0]    _zz_products_w_values_5_0;
  wire       [7:0]    _zz_products_w_values_5_0_1;
  wire       [7:0]    _zz_products_w_values_5_0_2;
  wire       [7:0]    _zz_products_w_values_5_1;
  wire       [7:0]    _zz_products_w_values_5_1_1;
  wire       [7:0]    _zz_products_w_values_5_1_2;
  wire       [7:0]    _zz_products_w_values_5_2;
  wire       [7:0]    _zz_products_w_values_5_2_1;
  wire       [7:0]    _zz_products_w_values_5_2_2;
  wire       [7:0]    _zz_products_w_values_5_3;
  wire       [7:0]    _zz_products_w_values_5_3_1;
  wire       [7:0]    _zz_products_w_values_5_3_2;
  wire       [7:0]    _zz_products_w_values_5_4;
  wire       [7:0]    _zz_products_w_values_5_4_1;
  wire       [7:0]    _zz_products_w_values_5_4_2;
  wire       [7:0]    _zz_products_w_values_5_5;
  wire       [7:0]    _zz_products_w_values_5_5_1;
  wire       [7:0]    _zz_products_w_values_5_5_2;
  wire       [7:0]    _zz_products_w_values_5_6;
  wire       [7:0]    _zz_products_w_values_5_6_1;
  wire       [7:0]    _zz_products_w_values_5_6_2;
  wire       [7:0]    _zz_products_w_values_5_7;
  wire       [7:0]    _zz_products_w_values_5_7_1;
  wire       [7:0]    _zz_products_w_values_5_7_2;
  wire       [7:0]    _zz_products_w_values_5_8;
  wire       [7:0]    _zz_products_w_values_5_8_1;
  wire       [7:0]    _zz_products_w_values_5_8_2;
  wire       [7:0]    _zz_products_w_values_5_9;
  wire       [7:0]    _zz_products_w_values_5_9_1;
  wire       [7:0]    _zz_products_w_values_5_9_2;
  wire       [7:0]    _zz_products_w_values_5_10;
  wire       [7:0]    _zz_products_w_values_5_10_1;
  wire       [7:0]    _zz_products_w_values_5_10_2;
  wire       [7:0]    _zz_products_w_values_5_11;
  wire       [7:0]    _zz_products_w_values_5_11_1;
  wire       [7:0]    _zz_products_w_values_5_11_2;
  wire       [7:0]    _zz_products_w_values_5_12;
  wire       [7:0]    _zz_products_w_values_5_12_1;
  wire       [7:0]    _zz_products_w_values_5_12_2;
  wire       [7:0]    _zz_products_w_values_5_13;
  wire       [7:0]    _zz_products_w_values_5_13_1;
  wire       [7:0]    _zz_products_w_values_5_13_2;
  wire       [7:0]    _zz_products_w_values_5_14;
  wire       [7:0]    _zz_products_w_values_5_14_1;
  wire       [7:0]    _zz_products_w_values_5_14_2;
  wire       [7:0]    _zz_products_w_values_5_15;
  wire       [7:0]    _zz_products_w_values_5_15_1;
  wire       [7:0]    _zz_products_w_values_5_15_2;
  wire       [7:0]    _zz_products_w_values_6_0;
  wire       [7:0]    _zz_products_w_values_6_0_1;
  wire       [7:0]    _zz_products_w_values_6_0_2;
  wire       [7:0]    _zz_products_w_values_6_1;
  wire       [7:0]    _zz_products_w_values_6_1_1;
  wire       [7:0]    _zz_products_w_values_6_1_2;
  wire       [7:0]    _zz_products_w_values_6_2;
  wire       [7:0]    _zz_products_w_values_6_2_1;
  wire       [7:0]    _zz_products_w_values_6_2_2;
  wire       [7:0]    _zz_products_w_values_6_3;
  wire       [7:0]    _zz_products_w_values_6_3_1;
  wire       [7:0]    _zz_products_w_values_6_3_2;
  wire       [7:0]    _zz_products_w_values_6_4;
  wire       [7:0]    _zz_products_w_values_6_4_1;
  wire       [7:0]    _zz_products_w_values_6_4_2;
  wire       [7:0]    _zz_products_w_values_6_5;
  wire       [7:0]    _zz_products_w_values_6_5_1;
  wire       [7:0]    _zz_products_w_values_6_5_2;
  wire       [7:0]    _zz_products_w_values_6_6;
  wire       [7:0]    _zz_products_w_values_6_6_1;
  wire       [7:0]    _zz_products_w_values_6_6_2;
  wire       [7:0]    _zz_products_w_values_6_7;
  wire       [7:0]    _zz_products_w_values_6_7_1;
  wire       [7:0]    _zz_products_w_values_6_7_2;
  wire       [7:0]    _zz_products_w_values_6_8;
  wire       [7:0]    _zz_products_w_values_6_8_1;
  wire       [7:0]    _zz_products_w_values_6_8_2;
  wire       [7:0]    _zz_products_w_values_6_9;
  wire       [7:0]    _zz_products_w_values_6_9_1;
  wire       [7:0]    _zz_products_w_values_6_9_2;
  wire       [7:0]    _zz_products_w_values_6_10;
  wire       [7:0]    _zz_products_w_values_6_10_1;
  wire       [7:0]    _zz_products_w_values_6_10_2;
  wire       [7:0]    _zz_products_w_values_6_11;
  wire       [7:0]    _zz_products_w_values_6_11_1;
  wire       [7:0]    _zz_products_w_values_6_11_2;
  wire       [7:0]    _zz_products_w_values_6_12;
  wire       [7:0]    _zz_products_w_values_6_12_1;
  wire       [7:0]    _zz_products_w_values_6_12_2;
  wire       [7:0]    _zz_products_w_values_6_13;
  wire       [7:0]    _zz_products_w_values_6_13_1;
  wire       [7:0]    _zz_products_w_values_6_13_2;
  wire       [7:0]    _zz_products_w_values_6_14;
  wire       [7:0]    _zz_products_w_values_6_14_1;
  wire       [7:0]    _zz_products_w_values_6_14_2;
  wire       [7:0]    _zz_products_w_values_6_15;
  wire       [7:0]    _zz_products_w_values_6_15_1;
  wire       [7:0]    _zz_products_w_values_6_15_2;
  wire       [7:0]    _zz_products_w_values_7_0;
  wire       [7:0]    _zz_products_w_values_7_0_1;
  wire       [7:0]    _zz_products_w_values_7_0_2;
  wire       [7:0]    _zz_products_w_values_7_1;
  wire       [7:0]    _zz_products_w_values_7_1_1;
  wire       [7:0]    _zz_products_w_values_7_1_2;
  wire       [7:0]    _zz_products_w_values_7_2;
  wire       [7:0]    _zz_products_w_values_7_2_1;
  wire       [7:0]    _zz_products_w_values_7_2_2;
  wire       [7:0]    _zz_products_w_values_7_3;
  wire       [7:0]    _zz_products_w_values_7_3_1;
  wire       [7:0]    _zz_products_w_values_7_3_2;
  wire       [7:0]    _zz_products_w_values_7_4;
  wire       [7:0]    _zz_products_w_values_7_4_1;
  wire       [7:0]    _zz_products_w_values_7_4_2;
  wire       [7:0]    _zz_products_w_values_7_5;
  wire       [7:0]    _zz_products_w_values_7_5_1;
  wire       [7:0]    _zz_products_w_values_7_5_2;
  wire       [7:0]    _zz_products_w_values_7_6;
  wire       [7:0]    _zz_products_w_values_7_6_1;
  wire       [7:0]    _zz_products_w_values_7_6_2;
  wire       [7:0]    _zz_products_w_values_7_7;
  wire       [7:0]    _zz_products_w_values_7_7_1;
  wire       [7:0]    _zz_products_w_values_7_7_2;
  wire       [7:0]    _zz_products_w_values_7_8;
  wire       [7:0]    _zz_products_w_values_7_8_1;
  wire       [7:0]    _zz_products_w_values_7_8_2;
  wire       [7:0]    _zz_products_w_values_7_9;
  wire       [7:0]    _zz_products_w_values_7_9_1;
  wire       [7:0]    _zz_products_w_values_7_9_2;
  wire       [7:0]    _zz_products_w_values_7_10;
  wire       [7:0]    _zz_products_w_values_7_10_1;
  wire       [7:0]    _zz_products_w_values_7_10_2;
  wire       [7:0]    _zz_products_w_values_7_11;
  wire       [7:0]    _zz_products_w_values_7_11_1;
  wire       [7:0]    _zz_products_w_values_7_11_2;
  wire       [7:0]    _zz_products_w_values_7_12;
  wire       [7:0]    _zz_products_w_values_7_12_1;
  wire       [7:0]    _zz_products_w_values_7_12_2;
  wire       [7:0]    _zz_products_w_values_7_13;
  wire       [7:0]    _zz_products_w_values_7_13_1;
  wire       [7:0]    _zz_products_w_values_7_13_2;
  wire       [7:0]    _zz_products_w_values_7_14;
  wire       [7:0]    _zz_products_w_values_7_14_1;
  wire       [7:0]    _zz_products_w_values_7_14_2;
  wire       [7:0]    _zz_products_w_values_7_15;
  wire       [7:0]    _zz_products_w_values_7_15_1;
  wire       [7:0]    _zz_products_w_values_7_15_2;
  wire       [7:0]    _zz_products_w_values_8_0;
  wire       [7:0]    _zz_products_w_values_8_0_1;
  wire       [7:0]    _zz_products_w_values_8_0_2;
  wire       [7:0]    _zz_products_w_values_8_1;
  wire       [7:0]    _zz_products_w_values_8_1_1;
  wire       [7:0]    _zz_products_w_values_8_1_2;
  wire       [7:0]    _zz_products_w_values_8_2;
  wire       [7:0]    _zz_products_w_values_8_2_1;
  wire       [7:0]    _zz_products_w_values_8_2_2;
  wire       [7:0]    _zz_products_w_values_8_3;
  wire       [7:0]    _zz_products_w_values_8_3_1;
  wire       [7:0]    _zz_products_w_values_8_3_2;
  wire       [7:0]    _zz_products_w_values_8_4;
  wire       [7:0]    _zz_products_w_values_8_4_1;
  wire       [7:0]    _zz_products_w_values_8_4_2;
  wire       [7:0]    _zz_products_w_values_8_5;
  wire       [7:0]    _zz_products_w_values_8_5_1;
  wire       [7:0]    _zz_products_w_values_8_5_2;
  wire       [7:0]    _zz_products_w_values_8_6;
  wire       [7:0]    _zz_products_w_values_8_6_1;
  wire       [7:0]    _zz_products_w_values_8_6_2;
  wire       [7:0]    _zz_products_w_values_8_7;
  wire       [7:0]    _zz_products_w_values_8_7_1;
  wire       [7:0]    _zz_products_w_values_8_7_2;
  wire       [7:0]    _zz_products_w_values_8_8;
  wire       [7:0]    _zz_products_w_values_8_8_1;
  wire       [7:0]    _zz_products_w_values_8_8_2;
  wire       [7:0]    _zz_products_w_values_8_9;
  wire       [7:0]    _zz_products_w_values_8_9_1;
  wire       [7:0]    _zz_products_w_values_8_9_2;
  wire       [7:0]    _zz_products_w_values_8_10;
  wire       [7:0]    _zz_products_w_values_8_10_1;
  wire       [7:0]    _zz_products_w_values_8_10_2;
  wire       [7:0]    _zz_products_w_values_8_11;
  wire       [7:0]    _zz_products_w_values_8_11_1;
  wire       [7:0]    _zz_products_w_values_8_11_2;
  wire       [7:0]    _zz_products_w_values_8_12;
  wire       [7:0]    _zz_products_w_values_8_12_1;
  wire       [7:0]    _zz_products_w_values_8_12_2;
  wire       [7:0]    _zz_products_w_values_8_13;
  wire       [7:0]    _zz_products_w_values_8_13_1;
  wire       [7:0]    _zz_products_w_values_8_13_2;
  wire       [7:0]    _zz_products_w_values_8_14;
  wire       [7:0]    _zz_products_w_values_8_14_1;
  wire       [7:0]    _zz_products_w_values_8_14_2;
  wire       [7:0]    _zz_products_w_values_8_15;
  wire       [7:0]    _zz_products_w_values_8_15_1;
  wire       [7:0]    _zz_products_w_values_8_15_2;
  wire       [7:0]    _zz_products_w_values_9_0;
  wire       [7:0]    _zz_products_w_values_9_0_1;
  wire       [7:0]    _zz_products_w_values_9_0_2;
  wire       [7:0]    _zz_products_w_values_9_1;
  wire       [7:0]    _zz_products_w_values_9_1_1;
  wire       [7:0]    _zz_products_w_values_9_1_2;
  wire       [7:0]    _zz_products_w_values_9_2;
  wire       [7:0]    _zz_products_w_values_9_2_1;
  wire       [7:0]    _zz_products_w_values_9_2_2;
  wire       [7:0]    _zz_products_w_values_9_3;
  wire       [7:0]    _zz_products_w_values_9_3_1;
  wire       [7:0]    _zz_products_w_values_9_3_2;
  wire       [7:0]    _zz_products_w_values_9_4;
  wire       [7:0]    _zz_products_w_values_9_4_1;
  wire       [7:0]    _zz_products_w_values_9_4_2;
  wire       [7:0]    _zz_products_w_values_9_5;
  wire       [7:0]    _zz_products_w_values_9_5_1;
  wire       [7:0]    _zz_products_w_values_9_5_2;
  wire       [7:0]    _zz_products_w_values_9_6;
  wire       [7:0]    _zz_products_w_values_9_6_1;
  wire       [7:0]    _zz_products_w_values_9_6_2;
  wire       [7:0]    _zz_products_w_values_9_7;
  wire       [7:0]    _zz_products_w_values_9_7_1;
  wire       [7:0]    _zz_products_w_values_9_7_2;
  wire       [7:0]    _zz_products_w_values_9_8;
  wire       [7:0]    _zz_products_w_values_9_8_1;
  wire       [7:0]    _zz_products_w_values_9_8_2;
  wire       [7:0]    _zz_products_w_values_9_9;
  wire       [7:0]    _zz_products_w_values_9_9_1;
  wire       [7:0]    _zz_products_w_values_9_9_2;
  wire       [7:0]    _zz_products_w_values_9_10;
  wire       [7:0]    _zz_products_w_values_9_10_1;
  wire       [7:0]    _zz_products_w_values_9_10_2;
  wire       [7:0]    _zz_products_w_values_9_11;
  wire       [7:0]    _zz_products_w_values_9_11_1;
  wire       [7:0]    _zz_products_w_values_9_11_2;
  wire       [7:0]    _zz_products_w_values_9_12;
  wire       [7:0]    _zz_products_w_values_9_12_1;
  wire       [7:0]    _zz_products_w_values_9_12_2;
  wire       [7:0]    _zz_products_w_values_9_13;
  wire       [7:0]    _zz_products_w_values_9_13_1;
  wire       [7:0]    _zz_products_w_values_9_13_2;
  wire       [7:0]    _zz_products_w_values_9_14;
  wire       [7:0]    _zz_products_w_values_9_14_1;
  wire       [7:0]    _zz_products_w_values_9_14_2;
  wire       [7:0]    _zz_products_w_values_9_15;
  wire       [7:0]    _zz_products_w_values_9_15_1;
  wire       [7:0]    _zz_products_w_values_9_15_2;
  wire       [7:0]    _zz_products_w_values_10_0;
  wire       [7:0]    _zz_products_w_values_10_0_1;
  wire       [7:0]    _zz_products_w_values_10_0_2;
  wire       [7:0]    _zz_products_w_values_10_1;
  wire       [7:0]    _zz_products_w_values_10_1_1;
  wire       [7:0]    _zz_products_w_values_10_1_2;
  wire       [7:0]    _zz_products_w_values_10_2;
  wire       [7:0]    _zz_products_w_values_10_2_1;
  wire       [7:0]    _zz_products_w_values_10_2_2;
  wire       [7:0]    _zz_products_w_values_10_3;
  wire       [7:0]    _zz_products_w_values_10_3_1;
  wire       [7:0]    _zz_products_w_values_10_3_2;
  wire       [7:0]    _zz_products_w_values_10_4;
  wire       [7:0]    _zz_products_w_values_10_4_1;
  wire       [7:0]    _zz_products_w_values_10_4_2;
  wire       [7:0]    _zz_products_w_values_10_5;
  wire       [7:0]    _zz_products_w_values_10_5_1;
  wire       [7:0]    _zz_products_w_values_10_5_2;
  wire       [7:0]    _zz_products_w_values_10_6;
  wire       [7:0]    _zz_products_w_values_10_6_1;
  wire       [7:0]    _zz_products_w_values_10_6_2;
  wire       [7:0]    _zz_products_w_values_10_7;
  wire       [7:0]    _zz_products_w_values_10_7_1;
  wire       [7:0]    _zz_products_w_values_10_7_2;
  wire       [7:0]    _zz_products_w_values_10_8;
  wire       [7:0]    _zz_products_w_values_10_8_1;
  wire       [7:0]    _zz_products_w_values_10_8_2;
  wire       [7:0]    _zz_products_w_values_10_9;
  wire       [7:0]    _zz_products_w_values_10_9_1;
  wire       [7:0]    _zz_products_w_values_10_9_2;
  wire       [7:0]    _zz_products_w_values_10_10;
  wire       [7:0]    _zz_products_w_values_10_10_1;
  wire       [7:0]    _zz_products_w_values_10_10_2;
  wire       [7:0]    _zz_products_w_values_10_11;
  wire       [7:0]    _zz_products_w_values_10_11_1;
  wire       [7:0]    _zz_products_w_values_10_11_2;
  wire       [7:0]    _zz_products_w_values_10_12;
  wire       [7:0]    _zz_products_w_values_10_12_1;
  wire       [7:0]    _zz_products_w_values_10_12_2;
  wire       [7:0]    _zz_products_w_values_10_13;
  wire       [7:0]    _zz_products_w_values_10_13_1;
  wire       [7:0]    _zz_products_w_values_10_13_2;
  wire       [7:0]    _zz_products_w_values_10_14;
  wire       [7:0]    _zz_products_w_values_10_14_1;
  wire       [7:0]    _zz_products_w_values_10_14_2;
  wire       [7:0]    _zz_products_w_values_10_15;
  wire       [7:0]    _zz_products_w_values_10_15_1;
  wire       [7:0]    _zz_products_w_values_10_15_2;
  wire       [7:0]    _zz_products_w_values_11_0;
  wire       [7:0]    _zz_products_w_values_11_0_1;
  wire       [7:0]    _zz_products_w_values_11_0_2;
  wire       [7:0]    _zz_products_w_values_11_1;
  wire       [7:0]    _zz_products_w_values_11_1_1;
  wire       [7:0]    _zz_products_w_values_11_1_2;
  wire       [7:0]    _zz_products_w_values_11_2;
  wire       [7:0]    _zz_products_w_values_11_2_1;
  wire       [7:0]    _zz_products_w_values_11_2_2;
  wire       [7:0]    _zz_products_w_values_11_3;
  wire       [7:0]    _zz_products_w_values_11_3_1;
  wire       [7:0]    _zz_products_w_values_11_3_2;
  wire       [7:0]    _zz_products_w_values_11_4;
  wire       [7:0]    _zz_products_w_values_11_4_1;
  wire       [7:0]    _zz_products_w_values_11_4_2;
  wire       [7:0]    _zz_products_w_values_11_5;
  wire       [7:0]    _zz_products_w_values_11_5_1;
  wire       [7:0]    _zz_products_w_values_11_5_2;
  wire       [7:0]    _zz_products_w_values_11_6;
  wire       [7:0]    _zz_products_w_values_11_6_1;
  wire       [7:0]    _zz_products_w_values_11_6_2;
  wire       [7:0]    _zz_products_w_values_11_7;
  wire       [7:0]    _zz_products_w_values_11_7_1;
  wire       [7:0]    _zz_products_w_values_11_7_2;
  wire       [7:0]    _zz_products_w_values_11_8;
  wire       [7:0]    _zz_products_w_values_11_8_1;
  wire       [7:0]    _zz_products_w_values_11_8_2;
  wire       [7:0]    _zz_products_w_values_11_9;
  wire       [7:0]    _zz_products_w_values_11_9_1;
  wire       [7:0]    _zz_products_w_values_11_9_2;
  wire       [7:0]    _zz_products_w_values_11_10;
  wire       [7:0]    _zz_products_w_values_11_10_1;
  wire       [7:0]    _zz_products_w_values_11_10_2;
  wire       [7:0]    _zz_products_w_values_11_11;
  wire       [7:0]    _zz_products_w_values_11_11_1;
  wire       [7:0]    _zz_products_w_values_11_11_2;
  wire       [7:0]    _zz_products_w_values_11_12;
  wire       [7:0]    _zz_products_w_values_11_12_1;
  wire       [7:0]    _zz_products_w_values_11_12_2;
  wire       [7:0]    _zz_products_w_values_11_13;
  wire       [7:0]    _zz_products_w_values_11_13_1;
  wire       [7:0]    _zz_products_w_values_11_13_2;
  wire       [7:0]    _zz_products_w_values_11_14;
  wire       [7:0]    _zz_products_w_values_11_14_1;
  wire       [7:0]    _zz_products_w_values_11_14_2;
  wire       [7:0]    _zz_products_w_values_11_15;
  wire       [7:0]    _zz_products_w_values_11_15_1;
  wire       [7:0]    _zz_products_w_values_11_15_2;
  wire       [7:0]    _zz_products_w_values_12_0;
  wire       [7:0]    _zz_products_w_values_12_0_1;
  wire       [7:0]    _zz_products_w_values_12_0_2;
  wire       [7:0]    _zz_products_w_values_12_1;
  wire       [7:0]    _zz_products_w_values_12_1_1;
  wire       [7:0]    _zz_products_w_values_12_1_2;
  wire       [7:0]    _zz_products_w_values_12_2;
  wire       [7:0]    _zz_products_w_values_12_2_1;
  wire       [7:0]    _zz_products_w_values_12_2_2;
  wire       [7:0]    _zz_products_w_values_12_3;
  wire       [7:0]    _zz_products_w_values_12_3_1;
  wire       [7:0]    _zz_products_w_values_12_3_2;
  wire       [7:0]    _zz_products_w_values_12_4;
  wire       [7:0]    _zz_products_w_values_12_4_1;
  wire       [7:0]    _zz_products_w_values_12_4_2;
  wire       [7:0]    _zz_products_w_values_12_5;
  wire       [7:0]    _zz_products_w_values_12_5_1;
  wire       [7:0]    _zz_products_w_values_12_5_2;
  wire       [7:0]    _zz_products_w_values_12_6;
  wire       [7:0]    _zz_products_w_values_12_6_1;
  wire       [7:0]    _zz_products_w_values_12_6_2;
  wire       [7:0]    _zz_products_w_values_12_7;
  wire       [7:0]    _zz_products_w_values_12_7_1;
  wire       [7:0]    _zz_products_w_values_12_7_2;
  wire       [7:0]    _zz_products_w_values_12_8;
  wire       [7:0]    _zz_products_w_values_12_8_1;
  wire       [7:0]    _zz_products_w_values_12_8_2;
  wire       [7:0]    _zz_products_w_values_12_9;
  wire       [7:0]    _zz_products_w_values_12_9_1;
  wire       [7:0]    _zz_products_w_values_12_9_2;
  wire       [7:0]    _zz_products_w_values_12_10;
  wire       [7:0]    _zz_products_w_values_12_10_1;
  wire       [7:0]    _zz_products_w_values_12_10_2;
  wire       [7:0]    _zz_products_w_values_12_11;
  wire       [7:0]    _zz_products_w_values_12_11_1;
  wire       [7:0]    _zz_products_w_values_12_11_2;
  wire       [7:0]    _zz_products_w_values_12_12;
  wire       [7:0]    _zz_products_w_values_12_12_1;
  wire       [7:0]    _zz_products_w_values_12_12_2;
  wire       [7:0]    _zz_products_w_values_12_13;
  wire       [7:0]    _zz_products_w_values_12_13_1;
  wire       [7:0]    _zz_products_w_values_12_13_2;
  wire       [7:0]    _zz_products_w_values_12_14;
  wire       [7:0]    _zz_products_w_values_12_14_1;
  wire       [7:0]    _zz_products_w_values_12_14_2;
  wire       [7:0]    _zz_products_w_values_12_15;
  wire       [7:0]    _zz_products_w_values_12_15_1;
  wire       [7:0]    _zz_products_w_values_12_15_2;
  wire       [7:0]    _zz_products_w_values_13_0;
  wire       [7:0]    _zz_products_w_values_13_0_1;
  wire       [7:0]    _zz_products_w_values_13_0_2;
  wire       [7:0]    _zz_products_w_values_13_1;
  wire       [7:0]    _zz_products_w_values_13_1_1;
  wire       [7:0]    _zz_products_w_values_13_1_2;
  wire       [7:0]    _zz_products_w_values_13_2;
  wire       [7:0]    _zz_products_w_values_13_2_1;
  wire       [7:0]    _zz_products_w_values_13_2_2;
  wire       [7:0]    _zz_products_w_values_13_3;
  wire       [7:0]    _zz_products_w_values_13_3_1;
  wire       [7:0]    _zz_products_w_values_13_3_2;
  wire       [7:0]    _zz_products_w_values_13_4;
  wire       [7:0]    _zz_products_w_values_13_4_1;
  wire       [7:0]    _zz_products_w_values_13_4_2;
  wire       [7:0]    _zz_products_w_values_13_5;
  wire       [7:0]    _zz_products_w_values_13_5_1;
  wire       [7:0]    _zz_products_w_values_13_5_2;
  wire       [7:0]    _zz_products_w_values_13_6;
  wire       [7:0]    _zz_products_w_values_13_6_1;
  wire       [7:0]    _zz_products_w_values_13_6_2;
  wire       [7:0]    _zz_products_w_values_13_7;
  wire       [7:0]    _zz_products_w_values_13_7_1;
  wire       [7:0]    _zz_products_w_values_13_7_2;
  wire       [7:0]    _zz_products_w_values_13_8;
  wire       [7:0]    _zz_products_w_values_13_8_1;
  wire       [7:0]    _zz_products_w_values_13_8_2;
  wire       [7:0]    _zz_products_w_values_13_9;
  wire       [7:0]    _zz_products_w_values_13_9_1;
  wire       [7:0]    _zz_products_w_values_13_9_2;
  wire       [7:0]    _zz_products_w_values_13_10;
  wire       [7:0]    _zz_products_w_values_13_10_1;
  wire       [7:0]    _zz_products_w_values_13_10_2;
  wire       [7:0]    _zz_products_w_values_13_11;
  wire       [7:0]    _zz_products_w_values_13_11_1;
  wire       [7:0]    _zz_products_w_values_13_11_2;
  wire       [7:0]    _zz_products_w_values_13_12;
  wire       [7:0]    _zz_products_w_values_13_12_1;
  wire       [7:0]    _zz_products_w_values_13_12_2;
  wire       [7:0]    _zz_products_w_values_13_13;
  wire       [7:0]    _zz_products_w_values_13_13_1;
  wire       [7:0]    _zz_products_w_values_13_13_2;
  wire       [7:0]    _zz_products_w_values_13_14;
  wire       [7:0]    _zz_products_w_values_13_14_1;
  wire       [7:0]    _zz_products_w_values_13_14_2;
  wire       [7:0]    _zz_products_w_values_13_15;
  wire       [7:0]    _zz_products_w_values_13_15_1;
  wire       [7:0]    _zz_products_w_values_13_15_2;
  wire       [7:0]    _zz_products_w_values_14_0;
  wire       [7:0]    _zz_products_w_values_14_0_1;
  wire       [7:0]    _zz_products_w_values_14_0_2;
  wire       [7:0]    _zz_products_w_values_14_1;
  wire       [7:0]    _zz_products_w_values_14_1_1;
  wire       [7:0]    _zz_products_w_values_14_1_2;
  wire       [7:0]    _zz_products_w_values_14_2;
  wire       [7:0]    _zz_products_w_values_14_2_1;
  wire       [7:0]    _zz_products_w_values_14_2_2;
  wire       [7:0]    _zz_products_w_values_14_3;
  wire       [7:0]    _zz_products_w_values_14_3_1;
  wire       [7:0]    _zz_products_w_values_14_3_2;
  wire       [7:0]    _zz_products_w_values_14_4;
  wire       [7:0]    _zz_products_w_values_14_4_1;
  wire       [7:0]    _zz_products_w_values_14_4_2;
  wire       [7:0]    _zz_products_w_values_14_5;
  wire       [7:0]    _zz_products_w_values_14_5_1;
  wire       [7:0]    _zz_products_w_values_14_5_2;
  wire       [7:0]    _zz_products_w_values_14_6;
  wire       [7:0]    _zz_products_w_values_14_6_1;
  wire       [7:0]    _zz_products_w_values_14_6_2;
  wire       [7:0]    _zz_products_w_values_14_7;
  wire       [7:0]    _zz_products_w_values_14_7_1;
  wire       [7:0]    _zz_products_w_values_14_7_2;
  wire       [7:0]    _zz_products_w_values_14_8;
  wire       [7:0]    _zz_products_w_values_14_8_1;
  wire       [7:0]    _zz_products_w_values_14_8_2;
  wire       [7:0]    _zz_products_w_values_14_9;
  wire       [7:0]    _zz_products_w_values_14_9_1;
  wire       [7:0]    _zz_products_w_values_14_9_2;
  wire       [7:0]    _zz_products_w_values_14_10;
  wire       [7:0]    _zz_products_w_values_14_10_1;
  wire       [7:0]    _zz_products_w_values_14_10_2;
  wire       [7:0]    _zz_products_w_values_14_11;
  wire       [7:0]    _zz_products_w_values_14_11_1;
  wire       [7:0]    _zz_products_w_values_14_11_2;
  wire       [7:0]    _zz_products_w_values_14_12;
  wire       [7:0]    _zz_products_w_values_14_12_1;
  wire       [7:0]    _zz_products_w_values_14_12_2;
  wire       [7:0]    _zz_products_w_values_14_13;
  wire       [7:0]    _zz_products_w_values_14_13_1;
  wire       [7:0]    _zz_products_w_values_14_13_2;
  wire       [7:0]    _zz_products_w_values_14_14;
  wire       [7:0]    _zz_products_w_values_14_14_1;
  wire       [7:0]    _zz_products_w_values_14_14_2;
  wire       [7:0]    _zz_products_w_values_14_15;
  wire       [7:0]    _zz_products_w_values_14_15_1;
  wire       [7:0]    _zz_products_w_values_14_15_2;
  wire       [7:0]    _zz_products_w_values_15_0;
  wire       [7:0]    _zz_products_w_values_15_0_1;
  wire       [7:0]    _zz_products_w_values_15_0_2;
  wire       [7:0]    _zz_products_w_values_15_1;
  wire       [7:0]    _zz_products_w_values_15_1_1;
  wire       [7:0]    _zz_products_w_values_15_1_2;
  wire       [7:0]    _zz_products_w_values_15_2;
  wire       [7:0]    _zz_products_w_values_15_2_1;
  wire       [7:0]    _zz_products_w_values_15_2_2;
  wire       [7:0]    _zz_products_w_values_15_3;
  wire       [7:0]    _zz_products_w_values_15_3_1;
  wire       [7:0]    _zz_products_w_values_15_3_2;
  wire       [7:0]    _zz_products_w_values_15_4;
  wire       [7:0]    _zz_products_w_values_15_4_1;
  wire       [7:0]    _zz_products_w_values_15_4_2;
  wire       [7:0]    _zz_products_w_values_15_5;
  wire       [7:0]    _zz_products_w_values_15_5_1;
  wire       [7:0]    _zz_products_w_values_15_5_2;
  wire       [7:0]    _zz_products_w_values_15_6;
  wire       [7:0]    _zz_products_w_values_15_6_1;
  wire       [7:0]    _zz_products_w_values_15_6_2;
  wire       [7:0]    _zz_products_w_values_15_7;
  wire       [7:0]    _zz_products_w_values_15_7_1;
  wire       [7:0]    _zz_products_w_values_15_7_2;
  wire       [7:0]    _zz_products_w_values_15_8;
  wire       [7:0]    _zz_products_w_values_15_8_1;
  wire       [7:0]    _zz_products_w_values_15_8_2;
  wire       [7:0]    _zz_products_w_values_15_9;
  wire       [7:0]    _zz_products_w_values_15_9_1;
  wire       [7:0]    _zz_products_w_values_15_9_2;
  wire       [7:0]    _zz_products_w_values_15_10;
  wire       [7:0]    _zz_products_w_values_15_10_1;
  wire       [7:0]    _zz_products_w_values_15_10_2;
  wire       [7:0]    _zz_products_w_values_15_11;
  wire       [7:0]    _zz_products_w_values_15_11_1;
  wire       [7:0]    _zz_products_w_values_15_11_2;
  wire       [7:0]    _zz_products_w_values_15_12;
  wire       [7:0]    _zz_products_w_values_15_12_1;
  wire       [7:0]    _zz_products_w_values_15_12_2;
  wire       [7:0]    _zz_products_w_values_15_13;
  wire       [7:0]    _zz_products_w_values_15_13_1;
  wire       [7:0]    _zz_products_w_values_15_13_2;
  wire       [7:0]    _zz_products_w_values_15_14;
  wire       [7:0]    _zz_products_w_values_15_14_1;
  wire       [7:0]    _zz_products_w_values_15_14_2;
  wire       [7:0]    _zz_products_w_values_15_15;
  wire       [7:0]    _zz_products_w_values_15_15_1;
  wire       [7:0]    _zz_products_w_values_15_15_2;
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
  wire       [16:0]   _zz_reduce8_w_values_4_0;
  wire       [16:0]   _zz_reduce8_w_values_4_0_1;
  wire       [16:0]   _zz_reduce8_w_values_4_1;
  wire       [16:0]   _zz_reduce8_w_values_4_1_1;
  wire       [16:0]   _zz_reduce8_w_values_4_2;
  wire       [16:0]   _zz_reduce8_w_values_4_2_1;
  wire       [16:0]   _zz_reduce8_w_values_4_3;
  wire       [16:0]   _zz_reduce8_w_values_4_3_1;
  wire       [16:0]   _zz_reduce8_w_values_4_4;
  wire       [16:0]   _zz_reduce8_w_values_4_4_1;
  wire       [16:0]   _zz_reduce8_w_values_4_5;
  wire       [16:0]   _zz_reduce8_w_values_4_5_1;
  wire       [16:0]   _zz_reduce8_w_values_4_6;
  wire       [16:0]   _zz_reduce8_w_values_4_6_1;
  wire       [16:0]   _zz_reduce8_w_values_4_7;
  wire       [16:0]   _zz_reduce8_w_values_4_7_1;
  wire       [16:0]   _zz_reduce8_w_values_5_0;
  wire       [16:0]   _zz_reduce8_w_values_5_0_1;
  wire       [16:0]   _zz_reduce8_w_values_5_1;
  wire       [16:0]   _zz_reduce8_w_values_5_1_1;
  wire       [16:0]   _zz_reduce8_w_values_5_2;
  wire       [16:0]   _zz_reduce8_w_values_5_2_1;
  wire       [16:0]   _zz_reduce8_w_values_5_3;
  wire       [16:0]   _zz_reduce8_w_values_5_3_1;
  wire       [16:0]   _zz_reduce8_w_values_5_4;
  wire       [16:0]   _zz_reduce8_w_values_5_4_1;
  wire       [16:0]   _zz_reduce8_w_values_5_5;
  wire       [16:0]   _zz_reduce8_w_values_5_5_1;
  wire       [16:0]   _zz_reduce8_w_values_5_6;
  wire       [16:0]   _zz_reduce8_w_values_5_6_1;
  wire       [16:0]   _zz_reduce8_w_values_5_7;
  wire       [16:0]   _zz_reduce8_w_values_5_7_1;
  wire       [16:0]   _zz_reduce8_w_values_6_0;
  wire       [16:0]   _zz_reduce8_w_values_6_0_1;
  wire       [16:0]   _zz_reduce8_w_values_6_1;
  wire       [16:0]   _zz_reduce8_w_values_6_1_1;
  wire       [16:0]   _zz_reduce8_w_values_6_2;
  wire       [16:0]   _zz_reduce8_w_values_6_2_1;
  wire       [16:0]   _zz_reduce8_w_values_6_3;
  wire       [16:0]   _zz_reduce8_w_values_6_3_1;
  wire       [16:0]   _zz_reduce8_w_values_6_4;
  wire       [16:0]   _zz_reduce8_w_values_6_4_1;
  wire       [16:0]   _zz_reduce8_w_values_6_5;
  wire       [16:0]   _zz_reduce8_w_values_6_5_1;
  wire       [16:0]   _zz_reduce8_w_values_6_6;
  wire       [16:0]   _zz_reduce8_w_values_6_6_1;
  wire       [16:0]   _zz_reduce8_w_values_6_7;
  wire       [16:0]   _zz_reduce8_w_values_6_7_1;
  wire       [16:0]   _zz_reduce8_w_values_7_0;
  wire       [16:0]   _zz_reduce8_w_values_7_0_1;
  wire       [16:0]   _zz_reduce8_w_values_7_1;
  wire       [16:0]   _zz_reduce8_w_values_7_1_1;
  wire       [16:0]   _zz_reduce8_w_values_7_2;
  wire       [16:0]   _zz_reduce8_w_values_7_2_1;
  wire       [16:0]   _zz_reduce8_w_values_7_3;
  wire       [16:0]   _zz_reduce8_w_values_7_3_1;
  wire       [16:0]   _zz_reduce8_w_values_7_4;
  wire       [16:0]   _zz_reduce8_w_values_7_4_1;
  wire       [16:0]   _zz_reduce8_w_values_7_5;
  wire       [16:0]   _zz_reduce8_w_values_7_5_1;
  wire       [16:0]   _zz_reduce8_w_values_7_6;
  wire       [16:0]   _zz_reduce8_w_values_7_6_1;
  wire       [16:0]   _zz_reduce8_w_values_7_7;
  wire       [16:0]   _zz_reduce8_w_values_7_7_1;
  wire       [16:0]   _zz_reduce8_w_values_8_0;
  wire       [16:0]   _zz_reduce8_w_values_8_0_1;
  wire       [16:0]   _zz_reduce8_w_values_8_1;
  wire       [16:0]   _zz_reduce8_w_values_8_1_1;
  wire       [16:0]   _zz_reduce8_w_values_8_2;
  wire       [16:0]   _zz_reduce8_w_values_8_2_1;
  wire       [16:0]   _zz_reduce8_w_values_8_3;
  wire       [16:0]   _zz_reduce8_w_values_8_3_1;
  wire       [16:0]   _zz_reduce8_w_values_8_4;
  wire       [16:0]   _zz_reduce8_w_values_8_4_1;
  wire       [16:0]   _zz_reduce8_w_values_8_5;
  wire       [16:0]   _zz_reduce8_w_values_8_5_1;
  wire       [16:0]   _zz_reduce8_w_values_8_6;
  wire       [16:0]   _zz_reduce8_w_values_8_6_1;
  wire       [16:0]   _zz_reduce8_w_values_8_7;
  wire       [16:0]   _zz_reduce8_w_values_8_7_1;
  wire       [16:0]   _zz_reduce8_w_values_9_0;
  wire       [16:0]   _zz_reduce8_w_values_9_0_1;
  wire       [16:0]   _zz_reduce8_w_values_9_1;
  wire       [16:0]   _zz_reduce8_w_values_9_1_1;
  wire       [16:0]   _zz_reduce8_w_values_9_2;
  wire       [16:0]   _zz_reduce8_w_values_9_2_1;
  wire       [16:0]   _zz_reduce8_w_values_9_3;
  wire       [16:0]   _zz_reduce8_w_values_9_3_1;
  wire       [16:0]   _zz_reduce8_w_values_9_4;
  wire       [16:0]   _zz_reduce8_w_values_9_4_1;
  wire       [16:0]   _zz_reduce8_w_values_9_5;
  wire       [16:0]   _zz_reduce8_w_values_9_5_1;
  wire       [16:0]   _zz_reduce8_w_values_9_6;
  wire       [16:0]   _zz_reduce8_w_values_9_6_1;
  wire       [16:0]   _zz_reduce8_w_values_9_7;
  wire       [16:0]   _zz_reduce8_w_values_9_7_1;
  wire       [16:0]   _zz_reduce8_w_values_10_0;
  wire       [16:0]   _zz_reduce8_w_values_10_0_1;
  wire       [16:0]   _zz_reduce8_w_values_10_1;
  wire       [16:0]   _zz_reduce8_w_values_10_1_1;
  wire       [16:0]   _zz_reduce8_w_values_10_2;
  wire       [16:0]   _zz_reduce8_w_values_10_2_1;
  wire       [16:0]   _zz_reduce8_w_values_10_3;
  wire       [16:0]   _zz_reduce8_w_values_10_3_1;
  wire       [16:0]   _zz_reduce8_w_values_10_4;
  wire       [16:0]   _zz_reduce8_w_values_10_4_1;
  wire       [16:0]   _zz_reduce8_w_values_10_5;
  wire       [16:0]   _zz_reduce8_w_values_10_5_1;
  wire       [16:0]   _zz_reduce8_w_values_10_6;
  wire       [16:0]   _zz_reduce8_w_values_10_6_1;
  wire       [16:0]   _zz_reduce8_w_values_10_7;
  wire       [16:0]   _zz_reduce8_w_values_10_7_1;
  wire       [16:0]   _zz_reduce8_w_values_11_0;
  wire       [16:0]   _zz_reduce8_w_values_11_0_1;
  wire       [16:0]   _zz_reduce8_w_values_11_1;
  wire       [16:0]   _zz_reduce8_w_values_11_1_1;
  wire       [16:0]   _zz_reduce8_w_values_11_2;
  wire       [16:0]   _zz_reduce8_w_values_11_2_1;
  wire       [16:0]   _zz_reduce8_w_values_11_3;
  wire       [16:0]   _zz_reduce8_w_values_11_3_1;
  wire       [16:0]   _zz_reduce8_w_values_11_4;
  wire       [16:0]   _zz_reduce8_w_values_11_4_1;
  wire       [16:0]   _zz_reduce8_w_values_11_5;
  wire       [16:0]   _zz_reduce8_w_values_11_5_1;
  wire       [16:0]   _zz_reduce8_w_values_11_6;
  wire       [16:0]   _zz_reduce8_w_values_11_6_1;
  wire       [16:0]   _zz_reduce8_w_values_11_7;
  wire       [16:0]   _zz_reduce8_w_values_11_7_1;
  wire       [16:0]   _zz_reduce8_w_values_12_0;
  wire       [16:0]   _zz_reduce8_w_values_12_0_1;
  wire       [16:0]   _zz_reduce8_w_values_12_1;
  wire       [16:0]   _zz_reduce8_w_values_12_1_1;
  wire       [16:0]   _zz_reduce8_w_values_12_2;
  wire       [16:0]   _zz_reduce8_w_values_12_2_1;
  wire       [16:0]   _zz_reduce8_w_values_12_3;
  wire       [16:0]   _zz_reduce8_w_values_12_3_1;
  wire       [16:0]   _zz_reduce8_w_values_12_4;
  wire       [16:0]   _zz_reduce8_w_values_12_4_1;
  wire       [16:0]   _zz_reduce8_w_values_12_5;
  wire       [16:0]   _zz_reduce8_w_values_12_5_1;
  wire       [16:0]   _zz_reduce8_w_values_12_6;
  wire       [16:0]   _zz_reduce8_w_values_12_6_1;
  wire       [16:0]   _zz_reduce8_w_values_12_7;
  wire       [16:0]   _zz_reduce8_w_values_12_7_1;
  wire       [16:0]   _zz_reduce8_w_values_13_0;
  wire       [16:0]   _zz_reduce8_w_values_13_0_1;
  wire       [16:0]   _zz_reduce8_w_values_13_1;
  wire       [16:0]   _zz_reduce8_w_values_13_1_1;
  wire       [16:0]   _zz_reduce8_w_values_13_2;
  wire       [16:0]   _zz_reduce8_w_values_13_2_1;
  wire       [16:0]   _zz_reduce8_w_values_13_3;
  wire       [16:0]   _zz_reduce8_w_values_13_3_1;
  wire       [16:0]   _zz_reduce8_w_values_13_4;
  wire       [16:0]   _zz_reduce8_w_values_13_4_1;
  wire       [16:0]   _zz_reduce8_w_values_13_5;
  wire       [16:0]   _zz_reduce8_w_values_13_5_1;
  wire       [16:0]   _zz_reduce8_w_values_13_6;
  wire       [16:0]   _zz_reduce8_w_values_13_6_1;
  wire       [16:0]   _zz_reduce8_w_values_13_7;
  wire       [16:0]   _zz_reduce8_w_values_13_7_1;
  wire       [16:0]   _zz_reduce8_w_values_14_0;
  wire       [16:0]   _zz_reduce8_w_values_14_0_1;
  wire       [16:0]   _zz_reduce8_w_values_14_1;
  wire       [16:0]   _zz_reduce8_w_values_14_1_1;
  wire       [16:0]   _zz_reduce8_w_values_14_2;
  wire       [16:0]   _zz_reduce8_w_values_14_2_1;
  wire       [16:0]   _zz_reduce8_w_values_14_3;
  wire       [16:0]   _zz_reduce8_w_values_14_3_1;
  wire       [16:0]   _zz_reduce8_w_values_14_4;
  wire       [16:0]   _zz_reduce8_w_values_14_4_1;
  wire       [16:0]   _zz_reduce8_w_values_14_5;
  wire       [16:0]   _zz_reduce8_w_values_14_5_1;
  wire       [16:0]   _zz_reduce8_w_values_14_6;
  wire       [16:0]   _zz_reduce8_w_values_14_6_1;
  wire       [16:0]   _zz_reduce8_w_values_14_7;
  wire       [16:0]   _zz_reduce8_w_values_14_7_1;
  wire       [16:0]   _zz_reduce8_w_values_15_0;
  wire       [16:0]   _zz_reduce8_w_values_15_0_1;
  wire       [16:0]   _zz_reduce8_w_values_15_1;
  wire       [16:0]   _zz_reduce8_w_values_15_1_1;
  wire       [16:0]   _zz_reduce8_w_values_15_2;
  wire       [16:0]   _zz_reduce8_w_values_15_2_1;
  wire       [16:0]   _zz_reduce8_w_values_15_3;
  wire       [16:0]   _zz_reduce8_w_values_15_3_1;
  wire       [16:0]   _zz_reduce8_w_values_15_4;
  wire       [16:0]   _zz_reduce8_w_values_15_4_1;
  wire       [16:0]   _zz_reduce8_w_values_15_5;
  wire       [16:0]   _zz_reduce8_w_values_15_5_1;
  wire       [16:0]   _zz_reduce8_w_values_15_6;
  wire       [16:0]   _zz_reduce8_w_values_15_6_1;
  wire       [16:0]   _zz_reduce8_w_values_15_7;
  wire       [16:0]   _zz_reduce8_w_values_15_7_1;
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
  wire       [17:0]   _zz_reduce4_w_values_4_0;
  wire       [17:0]   _zz_reduce4_w_values_4_0_1;
  wire       [17:0]   _zz_reduce4_w_values_4_1;
  wire       [17:0]   _zz_reduce4_w_values_4_1_1;
  wire       [17:0]   _zz_reduce4_w_values_4_2;
  wire       [17:0]   _zz_reduce4_w_values_4_2_1;
  wire       [17:0]   _zz_reduce4_w_values_4_3;
  wire       [17:0]   _zz_reduce4_w_values_4_3_1;
  wire       [17:0]   _zz_reduce4_w_values_5_0;
  wire       [17:0]   _zz_reduce4_w_values_5_0_1;
  wire       [17:0]   _zz_reduce4_w_values_5_1;
  wire       [17:0]   _zz_reduce4_w_values_5_1_1;
  wire       [17:0]   _zz_reduce4_w_values_5_2;
  wire       [17:0]   _zz_reduce4_w_values_5_2_1;
  wire       [17:0]   _zz_reduce4_w_values_5_3;
  wire       [17:0]   _zz_reduce4_w_values_5_3_1;
  wire       [17:0]   _zz_reduce4_w_values_6_0;
  wire       [17:0]   _zz_reduce4_w_values_6_0_1;
  wire       [17:0]   _zz_reduce4_w_values_6_1;
  wire       [17:0]   _zz_reduce4_w_values_6_1_1;
  wire       [17:0]   _zz_reduce4_w_values_6_2;
  wire       [17:0]   _zz_reduce4_w_values_6_2_1;
  wire       [17:0]   _zz_reduce4_w_values_6_3;
  wire       [17:0]   _zz_reduce4_w_values_6_3_1;
  wire       [17:0]   _zz_reduce4_w_values_7_0;
  wire       [17:0]   _zz_reduce4_w_values_7_0_1;
  wire       [17:0]   _zz_reduce4_w_values_7_1;
  wire       [17:0]   _zz_reduce4_w_values_7_1_1;
  wire       [17:0]   _zz_reduce4_w_values_7_2;
  wire       [17:0]   _zz_reduce4_w_values_7_2_1;
  wire       [17:0]   _zz_reduce4_w_values_7_3;
  wire       [17:0]   _zz_reduce4_w_values_7_3_1;
  wire       [17:0]   _zz_reduce4_w_values_8_0;
  wire       [17:0]   _zz_reduce4_w_values_8_0_1;
  wire       [17:0]   _zz_reduce4_w_values_8_1;
  wire       [17:0]   _zz_reduce4_w_values_8_1_1;
  wire       [17:0]   _zz_reduce4_w_values_8_2;
  wire       [17:0]   _zz_reduce4_w_values_8_2_1;
  wire       [17:0]   _zz_reduce4_w_values_8_3;
  wire       [17:0]   _zz_reduce4_w_values_8_3_1;
  wire       [17:0]   _zz_reduce4_w_values_9_0;
  wire       [17:0]   _zz_reduce4_w_values_9_0_1;
  wire       [17:0]   _zz_reduce4_w_values_9_1;
  wire       [17:0]   _zz_reduce4_w_values_9_1_1;
  wire       [17:0]   _zz_reduce4_w_values_9_2;
  wire       [17:0]   _zz_reduce4_w_values_9_2_1;
  wire       [17:0]   _zz_reduce4_w_values_9_3;
  wire       [17:0]   _zz_reduce4_w_values_9_3_1;
  wire       [17:0]   _zz_reduce4_w_values_10_0;
  wire       [17:0]   _zz_reduce4_w_values_10_0_1;
  wire       [17:0]   _zz_reduce4_w_values_10_1;
  wire       [17:0]   _zz_reduce4_w_values_10_1_1;
  wire       [17:0]   _zz_reduce4_w_values_10_2;
  wire       [17:0]   _zz_reduce4_w_values_10_2_1;
  wire       [17:0]   _zz_reduce4_w_values_10_3;
  wire       [17:0]   _zz_reduce4_w_values_10_3_1;
  wire       [17:0]   _zz_reduce4_w_values_11_0;
  wire       [17:0]   _zz_reduce4_w_values_11_0_1;
  wire       [17:0]   _zz_reduce4_w_values_11_1;
  wire       [17:0]   _zz_reduce4_w_values_11_1_1;
  wire       [17:0]   _zz_reduce4_w_values_11_2;
  wire       [17:0]   _zz_reduce4_w_values_11_2_1;
  wire       [17:0]   _zz_reduce4_w_values_11_3;
  wire       [17:0]   _zz_reduce4_w_values_11_3_1;
  wire       [17:0]   _zz_reduce4_w_values_12_0;
  wire       [17:0]   _zz_reduce4_w_values_12_0_1;
  wire       [17:0]   _zz_reduce4_w_values_12_1;
  wire       [17:0]   _zz_reduce4_w_values_12_1_1;
  wire       [17:0]   _zz_reduce4_w_values_12_2;
  wire       [17:0]   _zz_reduce4_w_values_12_2_1;
  wire       [17:0]   _zz_reduce4_w_values_12_3;
  wire       [17:0]   _zz_reduce4_w_values_12_3_1;
  wire       [17:0]   _zz_reduce4_w_values_13_0;
  wire       [17:0]   _zz_reduce4_w_values_13_0_1;
  wire       [17:0]   _zz_reduce4_w_values_13_1;
  wire       [17:0]   _zz_reduce4_w_values_13_1_1;
  wire       [17:0]   _zz_reduce4_w_values_13_2;
  wire       [17:0]   _zz_reduce4_w_values_13_2_1;
  wire       [17:0]   _zz_reduce4_w_values_13_3;
  wire       [17:0]   _zz_reduce4_w_values_13_3_1;
  wire       [17:0]   _zz_reduce4_w_values_14_0;
  wire       [17:0]   _zz_reduce4_w_values_14_0_1;
  wire       [17:0]   _zz_reduce4_w_values_14_1;
  wire       [17:0]   _zz_reduce4_w_values_14_1_1;
  wire       [17:0]   _zz_reduce4_w_values_14_2;
  wire       [17:0]   _zz_reduce4_w_values_14_2_1;
  wire       [17:0]   _zz_reduce4_w_values_14_3;
  wire       [17:0]   _zz_reduce4_w_values_14_3_1;
  wire       [17:0]   _zz_reduce4_w_values_15_0;
  wire       [17:0]   _zz_reduce4_w_values_15_0_1;
  wire       [17:0]   _zz_reduce4_w_values_15_1;
  wire       [17:0]   _zz_reduce4_w_values_15_1_1;
  wire       [17:0]   _zz_reduce4_w_values_15_2;
  wire       [17:0]   _zz_reduce4_w_values_15_2_1;
  wire       [17:0]   _zz_reduce4_w_values_15_3;
  wire       [17:0]   _zz_reduce4_w_values_15_3_1;
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
  wire       [18:0]   _zz_reduce2_w_values_4_0;
  wire       [18:0]   _zz_reduce2_w_values_4_0_1;
  wire       [18:0]   _zz_reduce2_w_values_4_1;
  wire       [18:0]   _zz_reduce2_w_values_4_1_1;
  wire       [18:0]   _zz_reduce2_w_values_5_0;
  wire       [18:0]   _zz_reduce2_w_values_5_0_1;
  wire       [18:0]   _zz_reduce2_w_values_5_1;
  wire       [18:0]   _zz_reduce2_w_values_5_1_1;
  wire       [18:0]   _zz_reduce2_w_values_6_0;
  wire       [18:0]   _zz_reduce2_w_values_6_0_1;
  wire       [18:0]   _zz_reduce2_w_values_6_1;
  wire       [18:0]   _zz_reduce2_w_values_6_1_1;
  wire       [18:0]   _zz_reduce2_w_values_7_0;
  wire       [18:0]   _zz_reduce2_w_values_7_0_1;
  wire       [18:0]   _zz_reduce2_w_values_7_1;
  wire       [18:0]   _zz_reduce2_w_values_7_1_1;
  wire       [18:0]   _zz_reduce2_w_values_8_0;
  wire       [18:0]   _zz_reduce2_w_values_8_0_1;
  wire       [18:0]   _zz_reduce2_w_values_8_1;
  wire       [18:0]   _zz_reduce2_w_values_8_1_1;
  wire       [18:0]   _zz_reduce2_w_values_9_0;
  wire       [18:0]   _zz_reduce2_w_values_9_0_1;
  wire       [18:0]   _zz_reduce2_w_values_9_1;
  wire       [18:0]   _zz_reduce2_w_values_9_1_1;
  wire       [18:0]   _zz_reduce2_w_values_10_0;
  wire       [18:0]   _zz_reduce2_w_values_10_0_1;
  wire       [18:0]   _zz_reduce2_w_values_10_1;
  wire       [18:0]   _zz_reduce2_w_values_10_1_1;
  wire       [18:0]   _zz_reduce2_w_values_11_0;
  wire       [18:0]   _zz_reduce2_w_values_11_0_1;
  wire       [18:0]   _zz_reduce2_w_values_11_1;
  wire       [18:0]   _zz_reduce2_w_values_11_1_1;
  wire       [18:0]   _zz_reduce2_w_values_12_0;
  wire       [18:0]   _zz_reduce2_w_values_12_0_1;
  wire       [18:0]   _zz_reduce2_w_values_12_1;
  wire       [18:0]   _zz_reduce2_w_values_12_1_1;
  wire       [18:0]   _zz_reduce2_w_values_13_0;
  wire       [18:0]   _zz_reduce2_w_values_13_0_1;
  wire       [18:0]   _zz_reduce2_w_values_13_1;
  wire       [18:0]   _zz_reduce2_w_values_13_1_1;
  wire       [18:0]   _zz_reduce2_w_values_14_0;
  wire       [18:0]   _zz_reduce2_w_values_14_0_1;
  wire       [18:0]   _zz_reduce2_w_values_14_1;
  wire       [18:0]   _zz_reduce2_w_values_14_1_1;
  wire       [18:0]   _zz_reduce2_w_values_15_0;
  wire       [18:0]   _zz_reduce2_w_values_15_0_1;
  wire       [18:0]   _zz_reduce2_w_values_15_1;
  wire       [18:0]   _zz_reduce2_w_values_15_1_1;
  wire       [19:0]   _zz_dot_w_values_0_0;
  wire       [19:0]   _zz_dot_w_values_0_0_1;
  wire       [19:0]   _zz_dot_w_values_1_0;
  wire       [19:0]   _zz_dot_w_values_1_0_1;
  wire       [19:0]   _zz_dot_w_values_2_0;
  wire       [19:0]   _zz_dot_w_values_2_0_1;
  wire       [19:0]   _zz_dot_w_values_3_0;
  wire       [19:0]   _zz_dot_w_values_3_0_1;
  wire       [19:0]   _zz_dot_w_values_4_0;
  wire       [19:0]   _zz_dot_w_values_4_0_1;
  wire       [19:0]   _zz_dot_w_values_5_0;
  wire       [19:0]   _zz_dot_w_values_5_0_1;
  wire       [19:0]   _zz_dot_w_values_6_0;
  wire       [19:0]   _zz_dot_w_values_6_0_1;
  wire       [19:0]   _zz_dot_w_values_7_0;
  wire       [19:0]   _zz_dot_w_values_7_0_1;
  wire       [19:0]   _zz_dot_w_values_8_0;
  wire       [19:0]   _zz_dot_w_values_8_0_1;
  wire       [19:0]   _zz_dot_w_values_9_0;
  wire       [19:0]   _zz_dot_w_values_9_0_1;
  wire       [19:0]   _zz_dot_w_values_10_0;
  wire       [19:0]   _zz_dot_w_values_10_0_1;
  wire       [19:0]   _zz_dot_w_values_11_0;
  wire       [19:0]   _zz_dot_w_values_11_0_1;
  wire       [19:0]   _zz_dot_w_values_12_0;
  wire       [19:0]   _zz_dot_w_values_12_0_1;
  wire       [19:0]   _zz_dot_w_values_13_0;
  wire       [19:0]   _zz_dot_w_values_13_0_1;
  wire       [19:0]   _zz_dot_w_values_14_0;
  wire       [19:0]   _zz_dot_w_values_14_0_1;
  wire       [19:0]   _zz_dot_w_values_15_0;
  wire       [19:0]   _zz_dot_w_values_15_0_1;
  wire       [31:0]   _zz__zz_acc_r_0_0;
  reg        [31:0]   _zz__zz_acc_r_0_0_1;
  wire       [31:0]   _zz__zz_acc_r_0_0_2;
  wire       [31:0]   _zz__zz_acc_r_1_0;
  reg        [31:0]   _zz__zz_acc_r_1_0_1;
  wire       [31:0]   _zz__zz_acc_r_1_0_2;
  wire       [31:0]   _zz__zz_acc_r_2_0;
  reg        [31:0]   _zz__zz_acc_r_2_0_1;
  wire       [31:0]   _zz__zz_acc_r_2_0_2;
  wire       [31:0]   _zz__zz_acc_r_3_0;
  reg        [31:0]   _zz__zz_acc_r_3_0_1;
  wire       [31:0]   _zz__zz_acc_r_3_0_2;
  wire       [31:0]   _zz__zz_acc_r_4_0;
  reg        [31:0]   _zz__zz_acc_r_4_0_1;
  wire       [31:0]   _zz__zz_acc_r_4_0_2;
  wire       [31:0]   _zz__zz_acc_r_5_0;
  reg        [31:0]   _zz__zz_acc_r_5_0_1;
  wire       [31:0]   _zz__zz_acc_r_5_0_2;
  wire       [31:0]   _zz__zz_acc_r_6_0;
  reg        [31:0]   _zz__zz_acc_r_6_0_1;
  wire       [31:0]   _zz__zz_acc_r_6_0_2;
  wire       [31:0]   _zz__zz_acc_r_7_0;
  reg        [31:0]   _zz__zz_acc_r_7_0_1;
  wire       [31:0]   _zz__zz_acc_r_7_0_2;
  wire       [31:0]   _zz__zz_acc_r_8_0;
  reg        [31:0]   _zz__zz_acc_r_8_0_1;
  wire       [31:0]   _zz__zz_acc_r_8_0_2;
  wire       [31:0]   _zz__zz_acc_r_9_0;
  reg        [31:0]   _zz__zz_acc_r_9_0_1;
  wire       [31:0]   _zz__zz_acc_r_9_0_2;
  wire       [31:0]   _zz__zz_acc_r_10_0;
  reg        [31:0]   _zz__zz_acc_r_10_0_1;
  wire       [31:0]   _zz__zz_acc_r_10_0_2;
  wire       [31:0]   _zz__zz_acc_r_11_0;
  reg        [31:0]   _zz__zz_acc_r_11_0_1;
  wire       [31:0]   _zz__zz_acc_r_11_0_2;
  wire       [31:0]   _zz__zz_acc_r_12_0;
  reg        [31:0]   _zz__zz_acc_r_12_0_1;
  wire       [31:0]   _zz__zz_acc_r_12_0_2;
  wire       [31:0]   _zz__zz_acc_r_13_0;
  reg        [31:0]   _zz__zz_acc_r_13_0_1;
  wire       [31:0]   _zz__zz_acc_r_13_0_2;
  wire       [31:0]   _zz__zz_acc_r_14_0;
  reg        [31:0]   _zz__zz_acc_r_14_0_1;
  wire       [31:0]   _zz__zz_acc_r_14_0_2;
  wire       [31:0]   _zz__zz_acc_r_15_0;
  reg        [31:0]   _zz__zz_acc_r_15_0_1;
  wire       [31:0]   _zz__zz_acc_r_15_0_2;
  wire       [12:0]   _zz__zz_serialGroupCount_r;
  wire       [7:0]    _zz__zz_serialGroupCount_r_1;
  wire       [9:0]    _zz__zz_serialGroupCount_r_2;
  wire       [12:0]   _zz__zz_serialGroupCount_r_3;
  wire       [9:0]    _zz__zz_serialGroupCount_r_4;
  wire       [2:0]    _zz_serialGroupCount_r_1;
  wire       [18:0]   _zz_quantRequest_payload_tag_pixel;
  wire       [12:0]   _zz_quantRequest_payload_tag_group;
  wire       [12:0]   _zz_quantRequest_payload_tag_group_1;
  wire       [9:0]    _zz_quantRequest_payload_tag_group_2;
  wire       [12:0]   _zz_quantRequest_payload_tag_group_3;
  wire       [12:0]   _zz_quantRequest_payload_tag_mask;
  wire       [12:0]   _zz_quantRequest_payload_tag_mask_1;
  wire       [9:0]    _zz_quantRequest_payload_tag_mask_2;
  wire       [12:0]   _zz_quantRequest_payload_tag_mask_3;
  reg        [31:0]   _zz_quantRequest_payload_mac_0_1;
  wire       [3:0]    _zz_quantRequest_payload_mac_0_2;
  reg        [31:0]   _zz_quantRequest_payload_mac_0_3;
  reg        [31:0]   _zz_quantRequest_payload_mac_0_4;
  reg        [31:0]   _zz_quantRequest_payload_mac_0_5;
  reg        [31:0]   _zz_quantRequest_payload_mac_0_6;
  reg        [31:0]   _zz_quantRequest_payload_mac_0_7;
  reg        [31:0]   _zz_quantRequest_payload_mac_0_8;
  reg        [31:0]   _zz_quantRequest_payload_mac_0_9;
  reg        [31:0]   _zz_quantRequest_payload_mac_0_10;
  reg        [31:0]   _zz_quantRequest_payload_mac_0_11;
  reg        [31:0]   _zz_quantRequest_payload_mac_0_12;
  reg        [31:0]   _zz_quantRequest_payload_mac_0_13;
  reg        [31:0]   _zz_quantRequest_payload_mac_0_14;
  reg        [31:0]   _zz_quantRequest_payload_mac_0_15;
  reg        [31:0]   _zz_quantRequest_payload_mac_0_16;
  reg        [31:0]   _zz_quantRequest_payload_mac_0_17;
  reg        [31:0]   _zz_quantRequest_payload_mac_0_18;
  wire       [12:0]   _zz_quantRequest_payload_tag_mask_4;
  wire       [12:0]   _zz_quantRequest_payload_tag_mask_5;
  wire       [9:0]    _zz_quantRequest_payload_tag_mask_6;
  wire       [12:0]   _zz_quantRequest_payload_tag_mask_7;
  reg        [31:0]   _zz_quantRequest_payload_mac_1_1;
  wire       [3:0]    _zz_quantRequest_payload_mac_1_2;
  reg        [31:0]   _zz_quantRequest_payload_mac_1_3;
  reg        [31:0]   _zz_quantRequest_payload_mac_1_4;
  reg        [31:0]   _zz_quantRequest_payload_mac_1_5;
  reg        [31:0]   _zz_quantRequest_payload_mac_1_6;
  reg        [31:0]   _zz_quantRequest_payload_mac_1_7;
  reg        [31:0]   _zz_quantRequest_payload_mac_1_8;
  reg        [31:0]   _zz_quantRequest_payload_mac_1_9;
  reg        [31:0]   _zz_quantRequest_payload_mac_1_10;
  reg        [31:0]   _zz_quantRequest_payload_mac_1_11;
  reg        [31:0]   _zz_quantRequest_payload_mac_1_12;
  reg        [31:0]   _zz_quantRequest_payload_mac_1_13;
  reg        [31:0]   _zz_quantRequest_payload_mac_1_14;
  reg        [31:0]   _zz_quantRequest_payload_mac_1_15;
  reg        [31:0]   _zz_quantRequest_payload_mac_1_16;
  reg        [31:0]   _zz_quantRequest_payload_mac_1_17;
  reg        [31:0]   _zz_quantRequest_payload_mac_1_18;
  wire       [12:0]   _zz_quantRequest_payload_tag_mask_8;
  wire       [12:0]   _zz_quantRequest_payload_tag_mask_9;
  wire       [9:0]    _zz_quantRequest_payload_tag_mask_10;
  wire       [12:0]   _zz_quantRequest_payload_tag_mask_11;
  reg        [31:0]   _zz_quantRequest_payload_mac_2_1;
  wire       [3:0]    _zz_quantRequest_payload_mac_2_2;
  reg        [31:0]   _zz_quantRequest_payload_mac_2_3;
  reg        [31:0]   _zz_quantRequest_payload_mac_2_4;
  reg        [31:0]   _zz_quantRequest_payload_mac_2_5;
  reg        [31:0]   _zz_quantRequest_payload_mac_2_6;
  reg        [31:0]   _zz_quantRequest_payload_mac_2_7;
  reg        [31:0]   _zz_quantRequest_payload_mac_2_8;
  reg        [31:0]   _zz_quantRequest_payload_mac_2_9;
  reg        [31:0]   _zz_quantRequest_payload_mac_2_10;
  reg        [31:0]   _zz_quantRequest_payload_mac_2_11;
  reg        [31:0]   _zz_quantRequest_payload_mac_2_12;
  reg        [31:0]   _zz_quantRequest_payload_mac_2_13;
  reg        [31:0]   _zz_quantRequest_payload_mac_2_14;
  reg        [31:0]   _zz_quantRequest_payload_mac_2_15;
  reg        [31:0]   _zz_quantRequest_payload_mac_2_16;
  reg        [31:0]   _zz_quantRequest_payload_mac_2_17;
  reg        [31:0]   _zz_quantRequest_payload_mac_2_18;
  wire       [12:0]   _zz_quantRequest_payload_tag_mask_12;
  wire       [12:0]   _zz_quantRequest_payload_tag_mask_13;
  wire       [9:0]    _zz_quantRequest_payload_tag_mask_14;
  wire       [12:0]   _zz_quantRequest_payload_tag_mask_15;
  reg        [31:0]   _zz_quantRequest_payload_mac_3_1;
  wire       [3:0]    _zz_quantRequest_payload_mac_3_2;
  reg        [31:0]   _zz_quantRequest_payload_mac_3_3;
  reg        [31:0]   _zz_quantRequest_payload_mac_3_4;
  reg        [31:0]   _zz_quantRequest_payload_mac_3_5;
  reg        [31:0]   _zz_quantRequest_payload_mac_3_6;
  reg        [31:0]   _zz_quantRequest_payload_mac_3_7;
  reg        [31:0]   _zz_quantRequest_payload_mac_3_8;
  reg        [31:0]   _zz_quantRequest_payload_mac_3_9;
  reg        [31:0]   _zz_quantRequest_payload_mac_3_10;
  reg        [31:0]   _zz_quantRequest_payload_mac_3_11;
  reg        [31:0]   _zz_quantRequest_payload_mac_3_12;
  reg        [31:0]   _zz_quantRequest_payload_mac_3_13;
  reg        [31:0]   _zz_quantRequest_payload_mac_3_14;
  reg        [31:0]   _zz_quantRequest_payload_mac_3_15;
  reg        [31:0]   _zz_quantRequest_payload_mac_3_16;
  reg        [31:0]   _zz_quantRequest_payload_mac_3_17;
  reg        [31:0]   _zz_quantRequest_payload_mac_3_18;
  wire       [2:0]    _zz_quantRequest_payload_tag_tileLast;
  wire       [2:0]    _zz_quantRequest_payload_tag_tileLast_1;
  wire       [4:0]    _zz_quantRequest_payload_tag_tileLast_2;
  wire       [5:0]    _zz_quantRequest_payload_tag_last;
  wire       [5:0]    _zz_quantRequest_payload_tag_last_1;
  wire       [18:0]   _zz_quantRequest_payload_tag_last_2;
  wire       [18:0]   _zz_quantRequest_payload_tag_last_3;
  wire       [4:0]    _zz_when_PwMac_l442;
  wire       [2:0]    _zz_when_PwMac_l444;
  wire       [2:0]    _zz_when_PwMac_l444_1;
  wire       [6:0]    _zz_paramMemory_port;
  wire       [6:0]    _zz_when_PwMac_l483;
  wire       [12:0]   _zz_when_PwMac_l483_1;
  wire       [12:0]   _zz_when_PwMac_l483_2;
  wire       [12:0]   _zz_when_PwMac_l483_3;
  wire       [9:0]    _zz_when_PwMac_l483_4;
  wire       [12:0]   _zz_when_PwMac_l483_5;
  wire       [5:0]    _zz_when_PwMac_l484;
  wire       [5:0]    _zz_when_PwMac_l484_1;
  wire       [18:0]   _zz_tileBase_r;
  wire       [18:0]   _zz_remaining_r;
  wire       [3:0]    IDLE;
  wire       [3:0]    LOAD;
  wire       [3:0]    READY;
  wire       [3:0]    FILL;
  wire       [3:0]    ISSUE;
  wire       [3:0]    DRAIN;
  wire       [3:0]    PREPARE;
  wire       [3:0]    TILE_READY;
  wire       [3:0]    SERIALIZE;
  reg        [3:0]    state_r;
  reg        [9:0]    run_r_cin;
  reg        [9:0]    run_r_cout;
  reg        [18:0]   run_r_pixels;
  reg        [5:0]    run_r_shift;
  reg                 run_r_raw;
  reg                 run_r_int16;
  reg        [5:0]    igCount_r;
  reg        [5:0]    ogCount_r;
  reg        [12:0]   weightCount_r;
  reg        [7:0]    paramCount_r;
  reg        [12:0]   weightTotal_r;
  reg        [7:0]    weightGroup_r;
  reg        [5:0]    weightInput_r;
  reg        [7:0]    paramGroup_r;
  reg        [18:0]   tileBase_r;
  reg        [4:0]    tileCount_r;
  reg        [18:0]   remaining_r;
  reg        [18:0]   tileLastPixel_r;
  reg        [31:0]   fillGroupBase_r;
  reg        [31:0]   fillReadAddr_r;
  reg        [5:0]    fillGroup_r;
  reg        [4:0]    fillPixel_r;
  reg                 waiting_r;
  reg        [4:0]    issueGroup_r;
  reg        [5:0]    issueInput_r;
  reg        [4:0]    issuePixel_r;
  reg        [1:0]    serialGroup_r;
  reg        [2:0]    serialGroupCount_r;
  reg        [4:0]    serialPixel_r;
  reg                 serializeIssued_r;
  reg                 done_r;
  wire                validConfig_w;
  wire       [5:0]    cfgIg_w;
  wire       [5:0]    cfgOg_w;
  wire       [7:0]    cfgParamGroups_w;
  wire                io_cfg_i_fire;
  wire                io_weights_i_fire;
  wire                when_PwMac_l243;
  wire                io_params_i_fire;
  wire                when_PwMac_l249;
  wire                io_start_i_fire;
  wire                when_PwMac_l259;
  wire                when_PwMac_l268;
  wire                io_rd_o_fire;
  wire       [9:0]    fillAddress_w;
  wire                io_rsp_i_fire;
  wire                when_PwMac_l283;
  wire                when_PwMac_l285;
  wire                request_valid;
  reg                 request_ready;
  wire       [18:0]   request_payload_tag_pixel;
  wire       [3:0]    request_payload_tag_localPixel;
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
  wire       [3:0]    response_payload_tag_localPixel;
  wire       [6:0]    response_payload_tag_group;
  wire       [3:0]    response_payload_tag_mask;
  wire                response_payload_tag_first;
  wire                response_payload_tag_finalInput;
  wire                response_payload_tag_tileLast;
  wire                response_payload_tag_last;
  wire       [5:0]    response_payload_inputGroup;
  reg                 request_rValid;
  reg        [18:0]   request_rData_tag_pixel;
  reg        [3:0]    request_rData_tag_localPixel;
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
  wire       [10:0]   weightAddress_w;
  wire                _zz_ena;
  wire                _zz_ena_1;
  wire                _zz_ena_2;
  wire                _zz_ena_3;
  wire       [127:0]  weightsByPe_w_0;
  wire       [127:0]  weightsByPe_w_1;
  wire       [127:0]  weightsByPe_w_2;
  wire       [127:0]  weightsByPe_w_3;
  wire       [127:0]  weightsByPe_w_4;
  wire       [127:0]  weightsByPe_w_5;
  wire       [127:0]  weightsByPe_w_6;
  wire       [127:0]  weightsByPe_w_7;
  wire       [127:0]  weightsByPe_w_8;
  wire       [127:0]  weightsByPe_w_9;
  wire       [127:0]  weightsByPe_w_10;
  wire       [127:0]  weightsByPe_w_11;
  wire       [127:0]  weightsByPe_w_12;
  wire       [127:0]  weightsByPe_w_13;
  wire       [127:0]  weightsByPe_w_14;
  wire       [127:0]  weightsByPe_w_15;
  wire                when_PwMac_l345;
  wire                when_PwMac_l347;
  wire       [18:0]   operands_w_tag_pixel;
  wire       [3:0]    operands_w_tag_localPixel;
  wire       [6:0]    operands_w_tag_group;
  wire       [3:0]    operands_w_tag_mask;
  wire                operands_w_tag_first;
  wire                operands_w_tag_finalInput;
  wire                operands_w_tag_tileLast;
  wire                operands_w_tag_last;
  wire       [127:0]  operands_w_input;
  wire       [127:0]  operands_w_weights_0;
  wire       [127:0]  operands_w_weights_1;
  wire       [127:0]  operands_w_weights_2;
  wire       [127:0]  operands_w_weights_3;
  wire       [127:0]  operands_w_weights_4;
  wire       [127:0]  operands_w_weights_5;
  wire       [127:0]  operands_w_weights_6;
  wire       [127:0]  operands_w_weights_7;
  wire       [127:0]  operands_w_weights_8;
  wire       [127:0]  operands_w_weights_9;
  wire       [127:0]  operands_w_weights_10;
  wire       [127:0]  operands_w_weights_11;
  wire       [127:0]  operands_w_weights_12;
  wire       [127:0]  operands_w_weights_13;
  wire       [127:0]  operands_w_weights_14;
  wire       [127:0]  operands_w_weights_15;
  reg        [15:0]   operands_w_mask;
  wire                response_translated_valid;
  reg                 response_translated_ready;
  wire       [18:0]   response_translated_payload_tag_pixel;
  wire       [3:0]    response_translated_payload_tag_localPixel;
  wire       [6:0]    response_translated_payload_tag_group;
  wire       [3:0]    response_translated_payload_tag_mask;
  wire                response_translated_payload_tag_first;
  wire                response_translated_payload_tag_finalInput;
  wire                response_translated_payload_tag_tileLast;
  wire                response_translated_payload_tag_last;
  wire       [127:0]  response_translated_payload_input;
  wire       [127:0]  response_translated_payload_weights_0;
  wire       [127:0]  response_translated_payload_weights_1;
  wire       [127:0]  response_translated_payload_weights_2;
  wire       [127:0]  response_translated_payload_weights_3;
  wire       [127:0]  response_translated_payload_weights_4;
  wire       [127:0]  response_translated_payload_weights_5;
  wire       [127:0]  response_translated_payload_weights_6;
  wire       [127:0]  response_translated_payload_weights_7;
  wire       [127:0]  response_translated_payload_weights_8;
  wire       [127:0]  response_translated_payload_weights_9;
  wire       [127:0]  response_translated_payload_weights_10;
  wire       [127:0]  response_translated_payload_weights_11;
  wire       [127:0]  response_translated_payload_weights_12;
  wire       [127:0]  response_translated_payload_weights_13;
  wire       [127:0]  response_translated_payload_weights_14;
  wire       [127:0]  response_translated_payload_weights_15;
  wire       [15:0]   response_translated_payload_mask;
  wire                operands_valid;
  wire                operands_ready;
  wire       [18:0]   operands_payload_tag_pixel;
  wire       [3:0]    operands_payload_tag_localPixel;
  wire       [6:0]    operands_payload_tag_group;
  wire       [3:0]    operands_payload_tag_mask;
  wire                operands_payload_tag_first;
  wire                operands_payload_tag_finalInput;
  wire                operands_payload_tag_tileLast;
  wire                operands_payload_tag_last;
  wire       [127:0]  operands_payload_input;
  wire       [127:0]  operands_payload_weights_0;
  wire       [127:0]  operands_payload_weights_1;
  wire       [127:0]  operands_payload_weights_2;
  wire       [127:0]  operands_payload_weights_3;
  wire       [127:0]  operands_payload_weights_4;
  wire       [127:0]  operands_payload_weights_5;
  wire       [127:0]  operands_payload_weights_6;
  wire       [127:0]  operands_payload_weights_7;
  wire       [127:0]  operands_payload_weights_8;
  wire       [127:0]  operands_payload_weights_9;
  wire       [127:0]  operands_payload_weights_10;
  wire       [127:0]  operands_payload_weights_11;
  wire       [127:0]  operands_payload_weights_12;
  wire       [127:0]  operands_payload_weights_13;
  wire       [127:0]  operands_payload_weights_14;
  wire       [127:0]  operands_payload_weights_15;
  wire       [15:0]   operands_payload_mask;
  reg                 response_translated_rValid;
  reg        [18:0]   response_translated_rData_tag_pixel;
  reg        [3:0]    response_translated_rData_tag_localPixel;
  reg        [6:0]    response_translated_rData_tag_group;
  reg        [3:0]    response_translated_rData_tag_mask;
  reg                 response_translated_rData_tag_first;
  reg                 response_translated_rData_tag_finalInput;
  reg                 response_translated_rData_tag_tileLast;
  reg                 response_translated_rData_tag_last;
  reg        [127:0]  response_translated_rData_input;
  reg        [127:0]  response_translated_rData_weights_0;
  reg        [127:0]  response_translated_rData_weights_1;
  reg        [127:0]  response_translated_rData_weights_2;
  reg        [127:0]  response_translated_rData_weights_3;
  reg        [127:0]  response_translated_rData_weights_4;
  reg        [127:0]  response_translated_rData_weights_5;
  reg        [127:0]  response_translated_rData_weights_6;
  reg        [127:0]  response_translated_rData_weights_7;
  reg        [127:0]  response_translated_rData_weights_8;
  reg        [127:0]  response_translated_rData_weights_9;
  reg        [127:0]  response_translated_rData_weights_10;
  reg        [127:0]  response_translated_rData_weights_11;
  reg        [127:0]  response_translated_rData_weights_12;
  reg        [127:0]  response_translated_rData_weights_13;
  reg        [127:0]  response_translated_rData_weights_14;
  reg        [127:0]  response_translated_rData_weights_15;
  reg        [15:0]   response_translated_rData_mask;
  wire                when_Stream_l477_1;
  wire       [18:0]   products_w_tag_pixel;
  wire       [3:0]    products_w_tag_localPixel;
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
  wire       [15:0]   products_w_values_4_0;
  wire       [15:0]   products_w_values_4_1;
  wire       [15:0]   products_w_values_4_2;
  wire       [15:0]   products_w_values_4_3;
  wire       [15:0]   products_w_values_4_4;
  wire       [15:0]   products_w_values_4_5;
  wire       [15:0]   products_w_values_4_6;
  wire       [15:0]   products_w_values_4_7;
  wire       [15:0]   products_w_values_4_8;
  wire       [15:0]   products_w_values_4_9;
  wire       [15:0]   products_w_values_4_10;
  wire       [15:0]   products_w_values_4_11;
  wire       [15:0]   products_w_values_4_12;
  wire       [15:0]   products_w_values_4_13;
  wire       [15:0]   products_w_values_4_14;
  wire       [15:0]   products_w_values_4_15;
  wire       [15:0]   products_w_values_5_0;
  wire       [15:0]   products_w_values_5_1;
  wire       [15:0]   products_w_values_5_2;
  wire       [15:0]   products_w_values_5_3;
  wire       [15:0]   products_w_values_5_4;
  wire       [15:0]   products_w_values_5_5;
  wire       [15:0]   products_w_values_5_6;
  wire       [15:0]   products_w_values_5_7;
  wire       [15:0]   products_w_values_5_8;
  wire       [15:0]   products_w_values_5_9;
  wire       [15:0]   products_w_values_5_10;
  wire       [15:0]   products_w_values_5_11;
  wire       [15:0]   products_w_values_5_12;
  wire       [15:0]   products_w_values_5_13;
  wire       [15:0]   products_w_values_5_14;
  wire       [15:0]   products_w_values_5_15;
  wire       [15:0]   products_w_values_6_0;
  wire       [15:0]   products_w_values_6_1;
  wire       [15:0]   products_w_values_6_2;
  wire       [15:0]   products_w_values_6_3;
  wire       [15:0]   products_w_values_6_4;
  wire       [15:0]   products_w_values_6_5;
  wire       [15:0]   products_w_values_6_6;
  wire       [15:0]   products_w_values_6_7;
  wire       [15:0]   products_w_values_6_8;
  wire       [15:0]   products_w_values_6_9;
  wire       [15:0]   products_w_values_6_10;
  wire       [15:0]   products_w_values_6_11;
  wire       [15:0]   products_w_values_6_12;
  wire       [15:0]   products_w_values_6_13;
  wire       [15:0]   products_w_values_6_14;
  wire       [15:0]   products_w_values_6_15;
  wire       [15:0]   products_w_values_7_0;
  wire       [15:0]   products_w_values_7_1;
  wire       [15:0]   products_w_values_7_2;
  wire       [15:0]   products_w_values_7_3;
  wire       [15:0]   products_w_values_7_4;
  wire       [15:0]   products_w_values_7_5;
  wire       [15:0]   products_w_values_7_6;
  wire       [15:0]   products_w_values_7_7;
  wire       [15:0]   products_w_values_7_8;
  wire       [15:0]   products_w_values_7_9;
  wire       [15:0]   products_w_values_7_10;
  wire       [15:0]   products_w_values_7_11;
  wire       [15:0]   products_w_values_7_12;
  wire       [15:0]   products_w_values_7_13;
  wire       [15:0]   products_w_values_7_14;
  wire       [15:0]   products_w_values_7_15;
  wire       [15:0]   products_w_values_8_0;
  wire       [15:0]   products_w_values_8_1;
  wire       [15:0]   products_w_values_8_2;
  wire       [15:0]   products_w_values_8_3;
  wire       [15:0]   products_w_values_8_4;
  wire       [15:0]   products_w_values_8_5;
  wire       [15:0]   products_w_values_8_6;
  wire       [15:0]   products_w_values_8_7;
  wire       [15:0]   products_w_values_8_8;
  wire       [15:0]   products_w_values_8_9;
  wire       [15:0]   products_w_values_8_10;
  wire       [15:0]   products_w_values_8_11;
  wire       [15:0]   products_w_values_8_12;
  wire       [15:0]   products_w_values_8_13;
  wire       [15:0]   products_w_values_8_14;
  wire       [15:0]   products_w_values_8_15;
  wire       [15:0]   products_w_values_9_0;
  wire       [15:0]   products_w_values_9_1;
  wire       [15:0]   products_w_values_9_2;
  wire       [15:0]   products_w_values_9_3;
  wire       [15:0]   products_w_values_9_4;
  wire       [15:0]   products_w_values_9_5;
  wire       [15:0]   products_w_values_9_6;
  wire       [15:0]   products_w_values_9_7;
  wire       [15:0]   products_w_values_9_8;
  wire       [15:0]   products_w_values_9_9;
  wire       [15:0]   products_w_values_9_10;
  wire       [15:0]   products_w_values_9_11;
  wire       [15:0]   products_w_values_9_12;
  wire       [15:0]   products_w_values_9_13;
  wire       [15:0]   products_w_values_9_14;
  wire       [15:0]   products_w_values_9_15;
  wire       [15:0]   products_w_values_10_0;
  wire       [15:0]   products_w_values_10_1;
  wire       [15:0]   products_w_values_10_2;
  wire       [15:0]   products_w_values_10_3;
  wire       [15:0]   products_w_values_10_4;
  wire       [15:0]   products_w_values_10_5;
  wire       [15:0]   products_w_values_10_6;
  wire       [15:0]   products_w_values_10_7;
  wire       [15:0]   products_w_values_10_8;
  wire       [15:0]   products_w_values_10_9;
  wire       [15:0]   products_w_values_10_10;
  wire       [15:0]   products_w_values_10_11;
  wire       [15:0]   products_w_values_10_12;
  wire       [15:0]   products_w_values_10_13;
  wire       [15:0]   products_w_values_10_14;
  wire       [15:0]   products_w_values_10_15;
  wire       [15:0]   products_w_values_11_0;
  wire       [15:0]   products_w_values_11_1;
  wire       [15:0]   products_w_values_11_2;
  wire       [15:0]   products_w_values_11_3;
  wire       [15:0]   products_w_values_11_4;
  wire       [15:0]   products_w_values_11_5;
  wire       [15:0]   products_w_values_11_6;
  wire       [15:0]   products_w_values_11_7;
  wire       [15:0]   products_w_values_11_8;
  wire       [15:0]   products_w_values_11_9;
  wire       [15:0]   products_w_values_11_10;
  wire       [15:0]   products_w_values_11_11;
  wire       [15:0]   products_w_values_11_12;
  wire       [15:0]   products_w_values_11_13;
  wire       [15:0]   products_w_values_11_14;
  wire       [15:0]   products_w_values_11_15;
  wire       [15:0]   products_w_values_12_0;
  wire       [15:0]   products_w_values_12_1;
  wire       [15:0]   products_w_values_12_2;
  wire       [15:0]   products_w_values_12_3;
  wire       [15:0]   products_w_values_12_4;
  wire       [15:0]   products_w_values_12_5;
  wire       [15:0]   products_w_values_12_6;
  wire       [15:0]   products_w_values_12_7;
  wire       [15:0]   products_w_values_12_8;
  wire       [15:0]   products_w_values_12_9;
  wire       [15:0]   products_w_values_12_10;
  wire       [15:0]   products_w_values_12_11;
  wire       [15:0]   products_w_values_12_12;
  wire       [15:0]   products_w_values_12_13;
  wire       [15:0]   products_w_values_12_14;
  wire       [15:0]   products_w_values_12_15;
  wire       [15:0]   products_w_values_13_0;
  wire       [15:0]   products_w_values_13_1;
  wire       [15:0]   products_w_values_13_2;
  wire       [15:0]   products_w_values_13_3;
  wire       [15:0]   products_w_values_13_4;
  wire       [15:0]   products_w_values_13_5;
  wire       [15:0]   products_w_values_13_6;
  wire       [15:0]   products_w_values_13_7;
  wire       [15:0]   products_w_values_13_8;
  wire       [15:0]   products_w_values_13_9;
  wire       [15:0]   products_w_values_13_10;
  wire       [15:0]   products_w_values_13_11;
  wire       [15:0]   products_w_values_13_12;
  wire       [15:0]   products_w_values_13_13;
  wire       [15:0]   products_w_values_13_14;
  wire       [15:0]   products_w_values_13_15;
  wire       [15:0]   products_w_values_14_0;
  wire       [15:0]   products_w_values_14_1;
  wire       [15:0]   products_w_values_14_2;
  wire       [15:0]   products_w_values_14_3;
  wire       [15:0]   products_w_values_14_4;
  wire       [15:0]   products_w_values_14_5;
  wire       [15:0]   products_w_values_14_6;
  wire       [15:0]   products_w_values_14_7;
  wire       [15:0]   products_w_values_14_8;
  wire       [15:0]   products_w_values_14_9;
  wire       [15:0]   products_w_values_14_10;
  wire       [15:0]   products_w_values_14_11;
  wire       [15:0]   products_w_values_14_12;
  wire       [15:0]   products_w_values_14_13;
  wire       [15:0]   products_w_values_14_14;
  wire       [15:0]   products_w_values_14_15;
  wire       [15:0]   products_w_values_15_0;
  wire       [15:0]   products_w_values_15_1;
  wire       [15:0]   products_w_values_15_2;
  wire       [15:0]   products_w_values_15_3;
  wire       [15:0]   products_w_values_15_4;
  wire       [15:0]   products_w_values_15_5;
  wire       [15:0]   products_w_values_15_6;
  wire       [15:0]   products_w_values_15_7;
  wire       [15:0]   products_w_values_15_8;
  wire       [15:0]   products_w_values_15_9;
  wire       [15:0]   products_w_values_15_10;
  wire       [15:0]   products_w_values_15_11;
  wire       [15:0]   products_w_values_15_12;
  wire       [15:0]   products_w_values_15_13;
  wire       [15:0]   products_w_values_15_14;
  wire       [15:0]   products_w_values_15_15;
  wire                operands_translated_valid;
  reg                 operands_translated_ready;
  wire       [18:0]   operands_translated_payload_tag_pixel;
  wire       [3:0]    operands_translated_payload_tag_localPixel;
  wire       [6:0]    operands_translated_payload_tag_group;
  wire       [3:0]    operands_translated_payload_tag_mask;
  wire                operands_translated_payload_tag_first;
  wire                operands_translated_payload_tag_finalInput;
  wire                operands_translated_payload_tag_tileLast;
  wire                operands_translated_payload_tag_last;
  wire       [15:0]   operands_translated_payload_values_0_0;
  wire       [15:0]   operands_translated_payload_values_0_1;
  wire       [15:0]   operands_translated_payload_values_0_2;
  wire       [15:0]   operands_translated_payload_values_0_3;
  wire       [15:0]   operands_translated_payload_values_0_4;
  wire       [15:0]   operands_translated_payload_values_0_5;
  wire       [15:0]   operands_translated_payload_values_0_6;
  wire       [15:0]   operands_translated_payload_values_0_7;
  wire       [15:0]   operands_translated_payload_values_0_8;
  wire       [15:0]   operands_translated_payload_values_0_9;
  wire       [15:0]   operands_translated_payload_values_0_10;
  wire       [15:0]   operands_translated_payload_values_0_11;
  wire       [15:0]   operands_translated_payload_values_0_12;
  wire       [15:0]   operands_translated_payload_values_0_13;
  wire       [15:0]   operands_translated_payload_values_0_14;
  wire       [15:0]   operands_translated_payload_values_0_15;
  wire       [15:0]   operands_translated_payload_values_1_0;
  wire       [15:0]   operands_translated_payload_values_1_1;
  wire       [15:0]   operands_translated_payload_values_1_2;
  wire       [15:0]   operands_translated_payload_values_1_3;
  wire       [15:0]   operands_translated_payload_values_1_4;
  wire       [15:0]   operands_translated_payload_values_1_5;
  wire       [15:0]   operands_translated_payload_values_1_6;
  wire       [15:0]   operands_translated_payload_values_1_7;
  wire       [15:0]   operands_translated_payload_values_1_8;
  wire       [15:0]   operands_translated_payload_values_1_9;
  wire       [15:0]   operands_translated_payload_values_1_10;
  wire       [15:0]   operands_translated_payload_values_1_11;
  wire       [15:0]   operands_translated_payload_values_1_12;
  wire       [15:0]   operands_translated_payload_values_1_13;
  wire       [15:0]   operands_translated_payload_values_1_14;
  wire       [15:0]   operands_translated_payload_values_1_15;
  wire       [15:0]   operands_translated_payload_values_2_0;
  wire       [15:0]   operands_translated_payload_values_2_1;
  wire       [15:0]   operands_translated_payload_values_2_2;
  wire       [15:0]   operands_translated_payload_values_2_3;
  wire       [15:0]   operands_translated_payload_values_2_4;
  wire       [15:0]   operands_translated_payload_values_2_5;
  wire       [15:0]   operands_translated_payload_values_2_6;
  wire       [15:0]   operands_translated_payload_values_2_7;
  wire       [15:0]   operands_translated_payload_values_2_8;
  wire       [15:0]   operands_translated_payload_values_2_9;
  wire       [15:0]   operands_translated_payload_values_2_10;
  wire       [15:0]   operands_translated_payload_values_2_11;
  wire       [15:0]   operands_translated_payload_values_2_12;
  wire       [15:0]   operands_translated_payload_values_2_13;
  wire       [15:0]   operands_translated_payload_values_2_14;
  wire       [15:0]   operands_translated_payload_values_2_15;
  wire       [15:0]   operands_translated_payload_values_3_0;
  wire       [15:0]   operands_translated_payload_values_3_1;
  wire       [15:0]   operands_translated_payload_values_3_2;
  wire       [15:0]   operands_translated_payload_values_3_3;
  wire       [15:0]   operands_translated_payload_values_3_4;
  wire       [15:0]   operands_translated_payload_values_3_5;
  wire       [15:0]   operands_translated_payload_values_3_6;
  wire       [15:0]   operands_translated_payload_values_3_7;
  wire       [15:0]   operands_translated_payload_values_3_8;
  wire       [15:0]   operands_translated_payload_values_3_9;
  wire       [15:0]   operands_translated_payload_values_3_10;
  wire       [15:0]   operands_translated_payload_values_3_11;
  wire       [15:0]   operands_translated_payload_values_3_12;
  wire       [15:0]   operands_translated_payload_values_3_13;
  wire       [15:0]   operands_translated_payload_values_3_14;
  wire       [15:0]   operands_translated_payload_values_3_15;
  wire       [15:0]   operands_translated_payload_values_4_0;
  wire       [15:0]   operands_translated_payload_values_4_1;
  wire       [15:0]   operands_translated_payload_values_4_2;
  wire       [15:0]   operands_translated_payload_values_4_3;
  wire       [15:0]   operands_translated_payload_values_4_4;
  wire       [15:0]   operands_translated_payload_values_4_5;
  wire       [15:0]   operands_translated_payload_values_4_6;
  wire       [15:0]   operands_translated_payload_values_4_7;
  wire       [15:0]   operands_translated_payload_values_4_8;
  wire       [15:0]   operands_translated_payload_values_4_9;
  wire       [15:0]   operands_translated_payload_values_4_10;
  wire       [15:0]   operands_translated_payload_values_4_11;
  wire       [15:0]   operands_translated_payload_values_4_12;
  wire       [15:0]   operands_translated_payload_values_4_13;
  wire       [15:0]   operands_translated_payload_values_4_14;
  wire       [15:0]   operands_translated_payload_values_4_15;
  wire       [15:0]   operands_translated_payload_values_5_0;
  wire       [15:0]   operands_translated_payload_values_5_1;
  wire       [15:0]   operands_translated_payload_values_5_2;
  wire       [15:0]   operands_translated_payload_values_5_3;
  wire       [15:0]   operands_translated_payload_values_5_4;
  wire       [15:0]   operands_translated_payload_values_5_5;
  wire       [15:0]   operands_translated_payload_values_5_6;
  wire       [15:0]   operands_translated_payload_values_5_7;
  wire       [15:0]   operands_translated_payload_values_5_8;
  wire       [15:0]   operands_translated_payload_values_5_9;
  wire       [15:0]   operands_translated_payload_values_5_10;
  wire       [15:0]   operands_translated_payload_values_5_11;
  wire       [15:0]   operands_translated_payload_values_5_12;
  wire       [15:0]   operands_translated_payload_values_5_13;
  wire       [15:0]   operands_translated_payload_values_5_14;
  wire       [15:0]   operands_translated_payload_values_5_15;
  wire       [15:0]   operands_translated_payload_values_6_0;
  wire       [15:0]   operands_translated_payload_values_6_1;
  wire       [15:0]   operands_translated_payload_values_6_2;
  wire       [15:0]   operands_translated_payload_values_6_3;
  wire       [15:0]   operands_translated_payload_values_6_4;
  wire       [15:0]   operands_translated_payload_values_6_5;
  wire       [15:0]   operands_translated_payload_values_6_6;
  wire       [15:0]   operands_translated_payload_values_6_7;
  wire       [15:0]   operands_translated_payload_values_6_8;
  wire       [15:0]   operands_translated_payload_values_6_9;
  wire       [15:0]   operands_translated_payload_values_6_10;
  wire       [15:0]   operands_translated_payload_values_6_11;
  wire       [15:0]   operands_translated_payload_values_6_12;
  wire       [15:0]   operands_translated_payload_values_6_13;
  wire       [15:0]   operands_translated_payload_values_6_14;
  wire       [15:0]   operands_translated_payload_values_6_15;
  wire       [15:0]   operands_translated_payload_values_7_0;
  wire       [15:0]   operands_translated_payload_values_7_1;
  wire       [15:0]   operands_translated_payload_values_7_2;
  wire       [15:0]   operands_translated_payload_values_7_3;
  wire       [15:0]   operands_translated_payload_values_7_4;
  wire       [15:0]   operands_translated_payload_values_7_5;
  wire       [15:0]   operands_translated_payload_values_7_6;
  wire       [15:0]   operands_translated_payload_values_7_7;
  wire       [15:0]   operands_translated_payload_values_7_8;
  wire       [15:0]   operands_translated_payload_values_7_9;
  wire       [15:0]   operands_translated_payload_values_7_10;
  wire       [15:0]   operands_translated_payload_values_7_11;
  wire       [15:0]   operands_translated_payload_values_7_12;
  wire       [15:0]   operands_translated_payload_values_7_13;
  wire       [15:0]   operands_translated_payload_values_7_14;
  wire       [15:0]   operands_translated_payload_values_7_15;
  wire       [15:0]   operands_translated_payload_values_8_0;
  wire       [15:0]   operands_translated_payload_values_8_1;
  wire       [15:0]   operands_translated_payload_values_8_2;
  wire       [15:0]   operands_translated_payload_values_8_3;
  wire       [15:0]   operands_translated_payload_values_8_4;
  wire       [15:0]   operands_translated_payload_values_8_5;
  wire       [15:0]   operands_translated_payload_values_8_6;
  wire       [15:0]   operands_translated_payload_values_8_7;
  wire       [15:0]   operands_translated_payload_values_8_8;
  wire       [15:0]   operands_translated_payload_values_8_9;
  wire       [15:0]   operands_translated_payload_values_8_10;
  wire       [15:0]   operands_translated_payload_values_8_11;
  wire       [15:0]   operands_translated_payload_values_8_12;
  wire       [15:0]   operands_translated_payload_values_8_13;
  wire       [15:0]   operands_translated_payload_values_8_14;
  wire       [15:0]   operands_translated_payload_values_8_15;
  wire       [15:0]   operands_translated_payload_values_9_0;
  wire       [15:0]   operands_translated_payload_values_9_1;
  wire       [15:0]   operands_translated_payload_values_9_2;
  wire       [15:0]   operands_translated_payload_values_9_3;
  wire       [15:0]   operands_translated_payload_values_9_4;
  wire       [15:0]   operands_translated_payload_values_9_5;
  wire       [15:0]   operands_translated_payload_values_9_6;
  wire       [15:0]   operands_translated_payload_values_9_7;
  wire       [15:0]   operands_translated_payload_values_9_8;
  wire       [15:0]   operands_translated_payload_values_9_9;
  wire       [15:0]   operands_translated_payload_values_9_10;
  wire       [15:0]   operands_translated_payload_values_9_11;
  wire       [15:0]   operands_translated_payload_values_9_12;
  wire       [15:0]   operands_translated_payload_values_9_13;
  wire       [15:0]   operands_translated_payload_values_9_14;
  wire       [15:0]   operands_translated_payload_values_9_15;
  wire       [15:0]   operands_translated_payload_values_10_0;
  wire       [15:0]   operands_translated_payload_values_10_1;
  wire       [15:0]   operands_translated_payload_values_10_2;
  wire       [15:0]   operands_translated_payload_values_10_3;
  wire       [15:0]   operands_translated_payload_values_10_4;
  wire       [15:0]   operands_translated_payload_values_10_5;
  wire       [15:0]   operands_translated_payload_values_10_6;
  wire       [15:0]   operands_translated_payload_values_10_7;
  wire       [15:0]   operands_translated_payload_values_10_8;
  wire       [15:0]   operands_translated_payload_values_10_9;
  wire       [15:0]   operands_translated_payload_values_10_10;
  wire       [15:0]   operands_translated_payload_values_10_11;
  wire       [15:0]   operands_translated_payload_values_10_12;
  wire       [15:0]   operands_translated_payload_values_10_13;
  wire       [15:0]   operands_translated_payload_values_10_14;
  wire       [15:0]   operands_translated_payload_values_10_15;
  wire       [15:0]   operands_translated_payload_values_11_0;
  wire       [15:0]   operands_translated_payload_values_11_1;
  wire       [15:0]   operands_translated_payload_values_11_2;
  wire       [15:0]   operands_translated_payload_values_11_3;
  wire       [15:0]   operands_translated_payload_values_11_4;
  wire       [15:0]   operands_translated_payload_values_11_5;
  wire       [15:0]   operands_translated_payload_values_11_6;
  wire       [15:0]   operands_translated_payload_values_11_7;
  wire       [15:0]   operands_translated_payload_values_11_8;
  wire       [15:0]   operands_translated_payload_values_11_9;
  wire       [15:0]   operands_translated_payload_values_11_10;
  wire       [15:0]   operands_translated_payload_values_11_11;
  wire       [15:0]   operands_translated_payload_values_11_12;
  wire       [15:0]   operands_translated_payload_values_11_13;
  wire       [15:0]   operands_translated_payload_values_11_14;
  wire       [15:0]   operands_translated_payload_values_11_15;
  wire       [15:0]   operands_translated_payload_values_12_0;
  wire       [15:0]   operands_translated_payload_values_12_1;
  wire       [15:0]   operands_translated_payload_values_12_2;
  wire       [15:0]   operands_translated_payload_values_12_3;
  wire       [15:0]   operands_translated_payload_values_12_4;
  wire       [15:0]   operands_translated_payload_values_12_5;
  wire       [15:0]   operands_translated_payload_values_12_6;
  wire       [15:0]   operands_translated_payload_values_12_7;
  wire       [15:0]   operands_translated_payload_values_12_8;
  wire       [15:0]   operands_translated_payload_values_12_9;
  wire       [15:0]   operands_translated_payload_values_12_10;
  wire       [15:0]   operands_translated_payload_values_12_11;
  wire       [15:0]   operands_translated_payload_values_12_12;
  wire       [15:0]   operands_translated_payload_values_12_13;
  wire       [15:0]   operands_translated_payload_values_12_14;
  wire       [15:0]   operands_translated_payload_values_12_15;
  wire       [15:0]   operands_translated_payload_values_13_0;
  wire       [15:0]   operands_translated_payload_values_13_1;
  wire       [15:0]   operands_translated_payload_values_13_2;
  wire       [15:0]   operands_translated_payload_values_13_3;
  wire       [15:0]   operands_translated_payload_values_13_4;
  wire       [15:0]   operands_translated_payload_values_13_5;
  wire       [15:0]   operands_translated_payload_values_13_6;
  wire       [15:0]   operands_translated_payload_values_13_7;
  wire       [15:0]   operands_translated_payload_values_13_8;
  wire       [15:0]   operands_translated_payload_values_13_9;
  wire       [15:0]   operands_translated_payload_values_13_10;
  wire       [15:0]   operands_translated_payload_values_13_11;
  wire       [15:0]   operands_translated_payload_values_13_12;
  wire       [15:0]   operands_translated_payload_values_13_13;
  wire       [15:0]   operands_translated_payload_values_13_14;
  wire       [15:0]   operands_translated_payload_values_13_15;
  wire       [15:0]   operands_translated_payload_values_14_0;
  wire       [15:0]   operands_translated_payload_values_14_1;
  wire       [15:0]   operands_translated_payload_values_14_2;
  wire       [15:0]   operands_translated_payload_values_14_3;
  wire       [15:0]   operands_translated_payload_values_14_4;
  wire       [15:0]   operands_translated_payload_values_14_5;
  wire       [15:0]   operands_translated_payload_values_14_6;
  wire       [15:0]   operands_translated_payload_values_14_7;
  wire       [15:0]   operands_translated_payload_values_14_8;
  wire       [15:0]   operands_translated_payload_values_14_9;
  wire       [15:0]   operands_translated_payload_values_14_10;
  wire       [15:0]   operands_translated_payload_values_14_11;
  wire       [15:0]   operands_translated_payload_values_14_12;
  wire       [15:0]   operands_translated_payload_values_14_13;
  wire       [15:0]   operands_translated_payload_values_14_14;
  wire       [15:0]   operands_translated_payload_values_14_15;
  wire       [15:0]   operands_translated_payload_values_15_0;
  wire       [15:0]   operands_translated_payload_values_15_1;
  wire       [15:0]   operands_translated_payload_values_15_2;
  wire       [15:0]   operands_translated_payload_values_15_3;
  wire       [15:0]   operands_translated_payload_values_15_4;
  wire       [15:0]   operands_translated_payload_values_15_5;
  wire       [15:0]   operands_translated_payload_values_15_6;
  wire       [15:0]   operands_translated_payload_values_15_7;
  wire       [15:0]   operands_translated_payload_values_15_8;
  wire       [15:0]   operands_translated_payload_values_15_9;
  wire       [15:0]   operands_translated_payload_values_15_10;
  wire       [15:0]   operands_translated_payload_values_15_11;
  wire       [15:0]   operands_translated_payload_values_15_12;
  wire       [15:0]   operands_translated_payload_values_15_13;
  wire       [15:0]   operands_translated_payload_values_15_14;
  wire       [15:0]   operands_translated_payload_values_15_15;
  wire                products_valid;
  wire                products_ready;
  wire       [18:0]   products_payload_tag_pixel;
  wire       [3:0]    products_payload_tag_localPixel;
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
  wire       [15:0]   products_payload_values_4_0;
  wire       [15:0]   products_payload_values_4_1;
  wire       [15:0]   products_payload_values_4_2;
  wire       [15:0]   products_payload_values_4_3;
  wire       [15:0]   products_payload_values_4_4;
  wire       [15:0]   products_payload_values_4_5;
  wire       [15:0]   products_payload_values_4_6;
  wire       [15:0]   products_payload_values_4_7;
  wire       [15:0]   products_payload_values_4_8;
  wire       [15:0]   products_payload_values_4_9;
  wire       [15:0]   products_payload_values_4_10;
  wire       [15:0]   products_payload_values_4_11;
  wire       [15:0]   products_payload_values_4_12;
  wire       [15:0]   products_payload_values_4_13;
  wire       [15:0]   products_payload_values_4_14;
  wire       [15:0]   products_payload_values_4_15;
  wire       [15:0]   products_payload_values_5_0;
  wire       [15:0]   products_payload_values_5_1;
  wire       [15:0]   products_payload_values_5_2;
  wire       [15:0]   products_payload_values_5_3;
  wire       [15:0]   products_payload_values_5_4;
  wire       [15:0]   products_payload_values_5_5;
  wire       [15:0]   products_payload_values_5_6;
  wire       [15:0]   products_payload_values_5_7;
  wire       [15:0]   products_payload_values_5_8;
  wire       [15:0]   products_payload_values_5_9;
  wire       [15:0]   products_payload_values_5_10;
  wire       [15:0]   products_payload_values_5_11;
  wire       [15:0]   products_payload_values_5_12;
  wire       [15:0]   products_payload_values_5_13;
  wire       [15:0]   products_payload_values_5_14;
  wire       [15:0]   products_payload_values_5_15;
  wire       [15:0]   products_payload_values_6_0;
  wire       [15:0]   products_payload_values_6_1;
  wire       [15:0]   products_payload_values_6_2;
  wire       [15:0]   products_payload_values_6_3;
  wire       [15:0]   products_payload_values_6_4;
  wire       [15:0]   products_payload_values_6_5;
  wire       [15:0]   products_payload_values_6_6;
  wire       [15:0]   products_payload_values_6_7;
  wire       [15:0]   products_payload_values_6_8;
  wire       [15:0]   products_payload_values_6_9;
  wire       [15:0]   products_payload_values_6_10;
  wire       [15:0]   products_payload_values_6_11;
  wire       [15:0]   products_payload_values_6_12;
  wire       [15:0]   products_payload_values_6_13;
  wire       [15:0]   products_payload_values_6_14;
  wire       [15:0]   products_payload_values_6_15;
  wire       [15:0]   products_payload_values_7_0;
  wire       [15:0]   products_payload_values_7_1;
  wire       [15:0]   products_payload_values_7_2;
  wire       [15:0]   products_payload_values_7_3;
  wire       [15:0]   products_payload_values_7_4;
  wire       [15:0]   products_payload_values_7_5;
  wire       [15:0]   products_payload_values_7_6;
  wire       [15:0]   products_payload_values_7_7;
  wire       [15:0]   products_payload_values_7_8;
  wire       [15:0]   products_payload_values_7_9;
  wire       [15:0]   products_payload_values_7_10;
  wire       [15:0]   products_payload_values_7_11;
  wire       [15:0]   products_payload_values_7_12;
  wire       [15:0]   products_payload_values_7_13;
  wire       [15:0]   products_payload_values_7_14;
  wire       [15:0]   products_payload_values_7_15;
  wire       [15:0]   products_payload_values_8_0;
  wire       [15:0]   products_payload_values_8_1;
  wire       [15:0]   products_payload_values_8_2;
  wire       [15:0]   products_payload_values_8_3;
  wire       [15:0]   products_payload_values_8_4;
  wire       [15:0]   products_payload_values_8_5;
  wire       [15:0]   products_payload_values_8_6;
  wire       [15:0]   products_payload_values_8_7;
  wire       [15:0]   products_payload_values_8_8;
  wire       [15:0]   products_payload_values_8_9;
  wire       [15:0]   products_payload_values_8_10;
  wire       [15:0]   products_payload_values_8_11;
  wire       [15:0]   products_payload_values_8_12;
  wire       [15:0]   products_payload_values_8_13;
  wire       [15:0]   products_payload_values_8_14;
  wire       [15:0]   products_payload_values_8_15;
  wire       [15:0]   products_payload_values_9_0;
  wire       [15:0]   products_payload_values_9_1;
  wire       [15:0]   products_payload_values_9_2;
  wire       [15:0]   products_payload_values_9_3;
  wire       [15:0]   products_payload_values_9_4;
  wire       [15:0]   products_payload_values_9_5;
  wire       [15:0]   products_payload_values_9_6;
  wire       [15:0]   products_payload_values_9_7;
  wire       [15:0]   products_payload_values_9_8;
  wire       [15:0]   products_payload_values_9_9;
  wire       [15:0]   products_payload_values_9_10;
  wire       [15:0]   products_payload_values_9_11;
  wire       [15:0]   products_payload_values_9_12;
  wire       [15:0]   products_payload_values_9_13;
  wire       [15:0]   products_payload_values_9_14;
  wire       [15:0]   products_payload_values_9_15;
  wire       [15:0]   products_payload_values_10_0;
  wire       [15:0]   products_payload_values_10_1;
  wire       [15:0]   products_payload_values_10_2;
  wire       [15:0]   products_payload_values_10_3;
  wire       [15:0]   products_payload_values_10_4;
  wire       [15:0]   products_payload_values_10_5;
  wire       [15:0]   products_payload_values_10_6;
  wire       [15:0]   products_payload_values_10_7;
  wire       [15:0]   products_payload_values_10_8;
  wire       [15:0]   products_payload_values_10_9;
  wire       [15:0]   products_payload_values_10_10;
  wire       [15:0]   products_payload_values_10_11;
  wire       [15:0]   products_payload_values_10_12;
  wire       [15:0]   products_payload_values_10_13;
  wire       [15:0]   products_payload_values_10_14;
  wire       [15:0]   products_payload_values_10_15;
  wire       [15:0]   products_payload_values_11_0;
  wire       [15:0]   products_payload_values_11_1;
  wire       [15:0]   products_payload_values_11_2;
  wire       [15:0]   products_payload_values_11_3;
  wire       [15:0]   products_payload_values_11_4;
  wire       [15:0]   products_payload_values_11_5;
  wire       [15:0]   products_payload_values_11_6;
  wire       [15:0]   products_payload_values_11_7;
  wire       [15:0]   products_payload_values_11_8;
  wire       [15:0]   products_payload_values_11_9;
  wire       [15:0]   products_payload_values_11_10;
  wire       [15:0]   products_payload_values_11_11;
  wire       [15:0]   products_payload_values_11_12;
  wire       [15:0]   products_payload_values_11_13;
  wire       [15:0]   products_payload_values_11_14;
  wire       [15:0]   products_payload_values_11_15;
  wire       [15:0]   products_payload_values_12_0;
  wire       [15:0]   products_payload_values_12_1;
  wire       [15:0]   products_payload_values_12_2;
  wire       [15:0]   products_payload_values_12_3;
  wire       [15:0]   products_payload_values_12_4;
  wire       [15:0]   products_payload_values_12_5;
  wire       [15:0]   products_payload_values_12_6;
  wire       [15:0]   products_payload_values_12_7;
  wire       [15:0]   products_payload_values_12_8;
  wire       [15:0]   products_payload_values_12_9;
  wire       [15:0]   products_payload_values_12_10;
  wire       [15:0]   products_payload_values_12_11;
  wire       [15:0]   products_payload_values_12_12;
  wire       [15:0]   products_payload_values_12_13;
  wire       [15:0]   products_payload_values_12_14;
  wire       [15:0]   products_payload_values_12_15;
  wire       [15:0]   products_payload_values_13_0;
  wire       [15:0]   products_payload_values_13_1;
  wire       [15:0]   products_payload_values_13_2;
  wire       [15:0]   products_payload_values_13_3;
  wire       [15:0]   products_payload_values_13_4;
  wire       [15:0]   products_payload_values_13_5;
  wire       [15:0]   products_payload_values_13_6;
  wire       [15:0]   products_payload_values_13_7;
  wire       [15:0]   products_payload_values_13_8;
  wire       [15:0]   products_payload_values_13_9;
  wire       [15:0]   products_payload_values_13_10;
  wire       [15:0]   products_payload_values_13_11;
  wire       [15:0]   products_payload_values_13_12;
  wire       [15:0]   products_payload_values_13_13;
  wire       [15:0]   products_payload_values_13_14;
  wire       [15:0]   products_payload_values_13_15;
  wire       [15:0]   products_payload_values_14_0;
  wire       [15:0]   products_payload_values_14_1;
  wire       [15:0]   products_payload_values_14_2;
  wire       [15:0]   products_payload_values_14_3;
  wire       [15:0]   products_payload_values_14_4;
  wire       [15:0]   products_payload_values_14_5;
  wire       [15:0]   products_payload_values_14_6;
  wire       [15:0]   products_payload_values_14_7;
  wire       [15:0]   products_payload_values_14_8;
  wire       [15:0]   products_payload_values_14_9;
  wire       [15:0]   products_payload_values_14_10;
  wire       [15:0]   products_payload_values_14_11;
  wire       [15:0]   products_payload_values_14_12;
  wire       [15:0]   products_payload_values_14_13;
  wire       [15:0]   products_payload_values_14_14;
  wire       [15:0]   products_payload_values_14_15;
  wire       [15:0]   products_payload_values_15_0;
  wire       [15:0]   products_payload_values_15_1;
  wire       [15:0]   products_payload_values_15_2;
  wire       [15:0]   products_payload_values_15_3;
  wire       [15:0]   products_payload_values_15_4;
  wire       [15:0]   products_payload_values_15_5;
  wire       [15:0]   products_payload_values_15_6;
  wire       [15:0]   products_payload_values_15_7;
  wire       [15:0]   products_payload_values_15_8;
  wire       [15:0]   products_payload_values_15_9;
  wire       [15:0]   products_payload_values_15_10;
  wire       [15:0]   products_payload_values_15_11;
  wire       [15:0]   products_payload_values_15_12;
  wire       [15:0]   products_payload_values_15_13;
  wire       [15:0]   products_payload_values_15_14;
  wire       [15:0]   products_payload_values_15_15;
  reg                 operands_translated_rValid;
  reg        [18:0]   operands_translated_rData_tag_pixel;
  reg        [3:0]    operands_translated_rData_tag_localPixel;
  reg        [6:0]    operands_translated_rData_tag_group;
  reg        [3:0]    operands_translated_rData_tag_mask;
  reg                 operands_translated_rData_tag_first;
  reg                 operands_translated_rData_tag_finalInput;
  reg                 operands_translated_rData_tag_tileLast;
  reg                 operands_translated_rData_tag_last;
  reg        [15:0]   operands_translated_rData_values_0_0;
  reg        [15:0]   operands_translated_rData_values_0_1;
  reg        [15:0]   operands_translated_rData_values_0_2;
  reg        [15:0]   operands_translated_rData_values_0_3;
  reg        [15:0]   operands_translated_rData_values_0_4;
  reg        [15:0]   operands_translated_rData_values_0_5;
  reg        [15:0]   operands_translated_rData_values_0_6;
  reg        [15:0]   operands_translated_rData_values_0_7;
  reg        [15:0]   operands_translated_rData_values_0_8;
  reg        [15:0]   operands_translated_rData_values_0_9;
  reg        [15:0]   operands_translated_rData_values_0_10;
  reg        [15:0]   operands_translated_rData_values_0_11;
  reg        [15:0]   operands_translated_rData_values_0_12;
  reg        [15:0]   operands_translated_rData_values_0_13;
  reg        [15:0]   operands_translated_rData_values_0_14;
  reg        [15:0]   operands_translated_rData_values_0_15;
  reg        [15:0]   operands_translated_rData_values_1_0;
  reg        [15:0]   operands_translated_rData_values_1_1;
  reg        [15:0]   operands_translated_rData_values_1_2;
  reg        [15:0]   operands_translated_rData_values_1_3;
  reg        [15:0]   operands_translated_rData_values_1_4;
  reg        [15:0]   operands_translated_rData_values_1_5;
  reg        [15:0]   operands_translated_rData_values_1_6;
  reg        [15:0]   operands_translated_rData_values_1_7;
  reg        [15:0]   operands_translated_rData_values_1_8;
  reg        [15:0]   operands_translated_rData_values_1_9;
  reg        [15:0]   operands_translated_rData_values_1_10;
  reg        [15:0]   operands_translated_rData_values_1_11;
  reg        [15:0]   operands_translated_rData_values_1_12;
  reg        [15:0]   operands_translated_rData_values_1_13;
  reg        [15:0]   operands_translated_rData_values_1_14;
  reg        [15:0]   operands_translated_rData_values_1_15;
  reg        [15:0]   operands_translated_rData_values_2_0;
  reg        [15:0]   operands_translated_rData_values_2_1;
  reg        [15:0]   operands_translated_rData_values_2_2;
  reg        [15:0]   operands_translated_rData_values_2_3;
  reg        [15:0]   operands_translated_rData_values_2_4;
  reg        [15:0]   operands_translated_rData_values_2_5;
  reg        [15:0]   operands_translated_rData_values_2_6;
  reg        [15:0]   operands_translated_rData_values_2_7;
  reg        [15:0]   operands_translated_rData_values_2_8;
  reg        [15:0]   operands_translated_rData_values_2_9;
  reg        [15:0]   operands_translated_rData_values_2_10;
  reg        [15:0]   operands_translated_rData_values_2_11;
  reg        [15:0]   operands_translated_rData_values_2_12;
  reg        [15:0]   operands_translated_rData_values_2_13;
  reg        [15:0]   operands_translated_rData_values_2_14;
  reg        [15:0]   operands_translated_rData_values_2_15;
  reg        [15:0]   operands_translated_rData_values_3_0;
  reg        [15:0]   operands_translated_rData_values_3_1;
  reg        [15:0]   operands_translated_rData_values_3_2;
  reg        [15:0]   operands_translated_rData_values_3_3;
  reg        [15:0]   operands_translated_rData_values_3_4;
  reg        [15:0]   operands_translated_rData_values_3_5;
  reg        [15:0]   operands_translated_rData_values_3_6;
  reg        [15:0]   operands_translated_rData_values_3_7;
  reg        [15:0]   operands_translated_rData_values_3_8;
  reg        [15:0]   operands_translated_rData_values_3_9;
  reg        [15:0]   operands_translated_rData_values_3_10;
  reg        [15:0]   operands_translated_rData_values_3_11;
  reg        [15:0]   operands_translated_rData_values_3_12;
  reg        [15:0]   operands_translated_rData_values_3_13;
  reg        [15:0]   operands_translated_rData_values_3_14;
  reg        [15:0]   operands_translated_rData_values_3_15;
  reg        [15:0]   operands_translated_rData_values_4_0;
  reg        [15:0]   operands_translated_rData_values_4_1;
  reg        [15:0]   operands_translated_rData_values_4_2;
  reg        [15:0]   operands_translated_rData_values_4_3;
  reg        [15:0]   operands_translated_rData_values_4_4;
  reg        [15:0]   operands_translated_rData_values_4_5;
  reg        [15:0]   operands_translated_rData_values_4_6;
  reg        [15:0]   operands_translated_rData_values_4_7;
  reg        [15:0]   operands_translated_rData_values_4_8;
  reg        [15:0]   operands_translated_rData_values_4_9;
  reg        [15:0]   operands_translated_rData_values_4_10;
  reg        [15:0]   operands_translated_rData_values_4_11;
  reg        [15:0]   operands_translated_rData_values_4_12;
  reg        [15:0]   operands_translated_rData_values_4_13;
  reg        [15:0]   operands_translated_rData_values_4_14;
  reg        [15:0]   operands_translated_rData_values_4_15;
  reg        [15:0]   operands_translated_rData_values_5_0;
  reg        [15:0]   operands_translated_rData_values_5_1;
  reg        [15:0]   operands_translated_rData_values_5_2;
  reg        [15:0]   operands_translated_rData_values_5_3;
  reg        [15:0]   operands_translated_rData_values_5_4;
  reg        [15:0]   operands_translated_rData_values_5_5;
  reg        [15:0]   operands_translated_rData_values_5_6;
  reg        [15:0]   operands_translated_rData_values_5_7;
  reg        [15:0]   operands_translated_rData_values_5_8;
  reg        [15:0]   operands_translated_rData_values_5_9;
  reg        [15:0]   operands_translated_rData_values_5_10;
  reg        [15:0]   operands_translated_rData_values_5_11;
  reg        [15:0]   operands_translated_rData_values_5_12;
  reg        [15:0]   operands_translated_rData_values_5_13;
  reg        [15:0]   operands_translated_rData_values_5_14;
  reg        [15:0]   operands_translated_rData_values_5_15;
  reg        [15:0]   operands_translated_rData_values_6_0;
  reg        [15:0]   operands_translated_rData_values_6_1;
  reg        [15:0]   operands_translated_rData_values_6_2;
  reg        [15:0]   operands_translated_rData_values_6_3;
  reg        [15:0]   operands_translated_rData_values_6_4;
  reg        [15:0]   operands_translated_rData_values_6_5;
  reg        [15:0]   operands_translated_rData_values_6_6;
  reg        [15:0]   operands_translated_rData_values_6_7;
  reg        [15:0]   operands_translated_rData_values_6_8;
  reg        [15:0]   operands_translated_rData_values_6_9;
  reg        [15:0]   operands_translated_rData_values_6_10;
  reg        [15:0]   operands_translated_rData_values_6_11;
  reg        [15:0]   operands_translated_rData_values_6_12;
  reg        [15:0]   operands_translated_rData_values_6_13;
  reg        [15:0]   operands_translated_rData_values_6_14;
  reg        [15:0]   operands_translated_rData_values_6_15;
  reg        [15:0]   operands_translated_rData_values_7_0;
  reg        [15:0]   operands_translated_rData_values_7_1;
  reg        [15:0]   operands_translated_rData_values_7_2;
  reg        [15:0]   operands_translated_rData_values_7_3;
  reg        [15:0]   operands_translated_rData_values_7_4;
  reg        [15:0]   operands_translated_rData_values_7_5;
  reg        [15:0]   operands_translated_rData_values_7_6;
  reg        [15:0]   operands_translated_rData_values_7_7;
  reg        [15:0]   operands_translated_rData_values_7_8;
  reg        [15:0]   operands_translated_rData_values_7_9;
  reg        [15:0]   operands_translated_rData_values_7_10;
  reg        [15:0]   operands_translated_rData_values_7_11;
  reg        [15:0]   operands_translated_rData_values_7_12;
  reg        [15:0]   operands_translated_rData_values_7_13;
  reg        [15:0]   operands_translated_rData_values_7_14;
  reg        [15:0]   operands_translated_rData_values_7_15;
  reg        [15:0]   operands_translated_rData_values_8_0;
  reg        [15:0]   operands_translated_rData_values_8_1;
  reg        [15:0]   operands_translated_rData_values_8_2;
  reg        [15:0]   operands_translated_rData_values_8_3;
  reg        [15:0]   operands_translated_rData_values_8_4;
  reg        [15:0]   operands_translated_rData_values_8_5;
  reg        [15:0]   operands_translated_rData_values_8_6;
  reg        [15:0]   operands_translated_rData_values_8_7;
  reg        [15:0]   operands_translated_rData_values_8_8;
  reg        [15:0]   operands_translated_rData_values_8_9;
  reg        [15:0]   operands_translated_rData_values_8_10;
  reg        [15:0]   operands_translated_rData_values_8_11;
  reg        [15:0]   operands_translated_rData_values_8_12;
  reg        [15:0]   operands_translated_rData_values_8_13;
  reg        [15:0]   operands_translated_rData_values_8_14;
  reg        [15:0]   operands_translated_rData_values_8_15;
  reg        [15:0]   operands_translated_rData_values_9_0;
  reg        [15:0]   operands_translated_rData_values_9_1;
  reg        [15:0]   operands_translated_rData_values_9_2;
  reg        [15:0]   operands_translated_rData_values_9_3;
  reg        [15:0]   operands_translated_rData_values_9_4;
  reg        [15:0]   operands_translated_rData_values_9_5;
  reg        [15:0]   operands_translated_rData_values_9_6;
  reg        [15:0]   operands_translated_rData_values_9_7;
  reg        [15:0]   operands_translated_rData_values_9_8;
  reg        [15:0]   operands_translated_rData_values_9_9;
  reg        [15:0]   operands_translated_rData_values_9_10;
  reg        [15:0]   operands_translated_rData_values_9_11;
  reg        [15:0]   operands_translated_rData_values_9_12;
  reg        [15:0]   operands_translated_rData_values_9_13;
  reg        [15:0]   operands_translated_rData_values_9_14;
  reg        [15:0]   operands_translated_rData_values_9_15;
  reg        [15:0]   operands_translated_rData_values_10_0;
  reg        [15:0]   operands_translated_rData_values_10_1;
  reg        [15:0]   operands_translated_rData_values_10_2;
  reg        [15:0]   operands_translated_rData_values_10_3;
  reg        [15:0]   operands_translated_rData_values_10_4;
  reg        [15:0]   operands_translated_rData_values_10_5;
  reg        [15:0]   operands_translated_rData_values_10_6;
  reg        [15:0]   operands_translated_rData_values_10_7;
  reg        [15:0]   operands_translated_rData_values_10_8;
  reg        [15:0]   operands_translated_rData_values_10_9;
  reg        [15:0]   operands_translated_rData_values_10_10;
  reg        [15:0]   operands_translated_rData_values_10_11;
  reg        [15:0]   operands_translated_rData_values_10_12;
  reg        [15:0]   operands_translated_rData_values_10_13;
  reg        [15:0]   operands_translated_rData_values_10_14;
  reg        [15:0]   operands_translated_rData_values_10_15;
  reg        [15:0]   operands_translated_rData_values_11_0;
  reg        [15:0]   operands_translated_rData_values_11_1;
  reg        [15:0]   operands_translated_rData_values_11_2;
  reg        [15:0]   operands_translated_rData_values_11_3;
  reg        [15:0]   operands_translated_rData_values_11_4;
  reg        [15:0]   operands_translated_rData_values_11_5;
  reg        [15:0]   operands_translated_rData_values_11_6;
  reg        [15:0]   operands_translated_rData_values_11_7;
  reg        [15:0]   operands_translated_rData_values_11_8;
  reg        [15:0]   operands_translated_rData_values_11_9;
  reg        [15:0]   operands_translated_rData_values_11_10;
  reg        [15:0]   operands_translated_rData_values_11_11;
  reg        [15:0]   operands_translated_rData_values_11_12;
  reg        [15:0]   operands_translated_rData_values_11_13;
  reg        [15:0]   operands_translated_rData_values_11_14;
  reg        [15:0]   operands_translated_rData_values_11_15;
  reg        [15:0]   operands_translated_rData_values_12_0;
  reg        [15:0]   operands_translated_rData_values_12_1;
  reg        [15:0]   operands_translated_rData_values_12_2;
  reg        [15:0]   operands_translated_rData_values_12_3;
  reg        [15:0]   operands_translated_rData_values_12_4;
  reg        [15:0]   operands_translated_rData_values_12_5;
  reg        [15:0]   operands_translated_rData_values_12_6;
  reg        [15:0]   operands_translated_rData_values_12_7;
  reg        [15:0]   operands_translated_rData_values_12_8;
  reg        [15:0]   operands_translated_rData_values_12_9;
  reg        [15:0]   operands_translated_rData_values_12_10;
  reg        [15:0]   operands_translated_rData_values_12_11;
  reg        [15:0]   operands_translated_rData_values_12_12;
  reg        [15:0]   operands_translated_rData_values_12_13;
  reg        [15:0]   operands_translated_rData_values_12_14;
  reg        [15:0]   operands_translated_rData_values_12_15;
  reg        [15:0]   operands_translated_rData_values_13_0;
  reg        [15:0]   operands_translated_rData_values_13_1;
  reg        [15:0]   operands_translated_rData_values_13_2;
  reg        [15:0]   operands_translated_rData_values_13_3;
  reg        [15:0]   operands_translated_rData_values_13_4;
  reg        [15:0]   operands_translated_rData_values_13_5;
  reg        [15:0]   operands_translated_rData_values_13_6;
  reg        [15:0]   operands_translated_rData_values_13_7;
  reg        [15:0]   operands_translated_rData_values_13_8;
  reg        [15:0]   operands_translated_rData_values_13_9;
  reg        [15:0]   operands_translated_rData_values_13_10;
  reg        [15:0]   operands_translated_rData_values_13_11;
  reg        [15:0]   operands_translated_rData_values_13_12;
  reg        [15:0]   operands_translated_rData_values_13_13;
  reg        [15:0]   operands_translated_rData_values_13_14;
  reg        [15:0]   operands_translated_rData_values_13_15;
  reg        [15:0]   operands_translated_rData_values_14_0;
  reg        [15:0]   operands_translated_rData_values_14_1;
  reg        [15:0]   operands_translated_rData_values_14_2;
  reg        [15:0]   operands_translated_rData_values_14_3;
  reg        [15:0]   operands_translated_rData_values_14_4;
  reg        [15:0]   operands_translated_rData_values_14_5;
  reg        [15:0]   operands_translated_rData_values_14_6;
  reg        [15:0]   operands_translated_rData_values_14_7;
  reg        [15:0]   operands_translated_rData_values_14_8;
  reg        [15:0]   operands_translated_rData_values_14_9;
  reg        [15:0]   operands_translated_rData_values_14_10;
  reg        [15:0]   operands_translated_rData_values_14_11;
  reg        [15:0]   operands_translated_rData_values_14_12;
  reg        [15:0]   operands_translated_rData_values_14_13;
  reg        [15:0]   operands_translated_rData_values_14_14;
  reg        [15:0]   operands_translated_rData_values_14_15;
  reg        [15:0]   operands_translated_rData_values_15_0;
  reg        [15:0]   operands_translated_rData_values_15_1;
  reg        [15:0]   operands_translated_rData_values_15_2;
  reg        [15:0]   operands_translated_rData_values_15_3;
  reg        [15:0]   operands_translated_rData_values_15_4;
  reg        [15:0]   operands_translated_rData_values_15_5;
  reg        [15:0]   operands_translated_rData_values_15_6;
  reg        [15:0]   operands_translated_rData_values_15_7;
  reg        [15:0]   operands_translated_rData_values_15_8;
  reg        [15:0]   operands_translated_rData_values_15_9;
  reg        [15:0]   operands_translated_rData_values_15_10;
  reg        [15:0]   operands_translated_rData_values_15_11;
  reg        [15:0]   operands_translated_rData_values_15_12;
  reg        [15:0]   operands_translated_rData_values_15_13;
  reg        [15:0]   operands_translated_rData_values_15_14;
  reg        [15:0]   operands_translated_rData_values_15_15;
  wire                when_Stream_l477_2;
  wire       [18:0]   reduce8_w_tag_pixel;
  wire       [3:0]    reduce8_w_tag_localPixel;
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
  wire       [16:0]   reduce8_w_values_4_0;
  wire       [16:0]   reduce8_w_values_4_1;
  wire       [16:0]   reduce8_w_values_4_2;
  wire       [16:0]   reduce8_w_values_4_3;
  wire       [16:0]   reduce8_w_values_4_4;
  wire       [16:0]   reduce8_w_values_4_5;
  wire       [16:0]   reduce8_w_values_4_6;
  wire       [16:0]   reduce8_w_values_4_7;
  wire       [16:0]   reduce8_w_values_5_0;
  wire       [16:0]   reduce8_w_values_5_1;
  wire       [16:0]   reduce8_w_values_5_2;
  wire       [16:0]   reduce8_w_values_5_3;
  wire       [16:0]   reduce8_w_values_5_4;
  wire       [16:0]   reduce8_w_values_5_5;
  wire       [16:0]   reduce8_w_values_5_6;
  wire       [16:0]   reduce8_w_values_5_7;
  wire       [16:0]   reduce8_w_values_6_0;
  wire       [16:0]   reduce8_w_values_6_1;
  wire       [16:0]   reduce8_w_values_6_2;
  wire       [16:0]   reduce8_w_values_6_3;
  wire       [16:0]   reduce8_w_values_6_4;
  wire       [16:0]   reduce8_w_values_6_5;
  wire       [16:0]   reduce8_w_values_6_6;
  wire       [16:0]   reduce8_w_values_6_7;
  wire       [16:0]   reduce8_w_values_7_0;
  wire       [16:0]   reduce8_w_values_7_1;
  wire       [16:0]   reduce8_w_values_7_2;
  wire       [16:0]   reduce8_w_values_7_3;
  wire       [16:0]   reduce8_w_values_7_4;
  wire       [16:0]   reduce8_w_values_7_5;
  wire       [16:0]   reduce8_w_values_7_6;
  wire       [16:0]   reduce8_w_values_7_7;
  wire       [16:0]   reduce8_w_values_8_0;
  wire       [16:0]   reduce8_w_values_8_1;
  wire       [16:0]   reduce8_w_values_8_2;
  wire       [16:0]   reduce8_w_values_8_3;
  wire       [16:0]   reduce8_w_values_8_4;
  wire       [16:0]   reduce8_w_values_8_5;
  wire       [16:0]   reduce8_w_values_8_6;
  wire       [16:0]   reduce8_w_values_8_7;
  wire       [16:0]   reduce8_w_values_9_0;
  wire       [16:0]   reduce8_w_values_9_1;
  wire       [16:0]   reduce8_w_values_9_2;
  wire       [16:0]   reduce8_w_values_9_3;
  wire       [16:0]   reduce8_w_values_9_4;
  wire       [16:0]   reduce8_w_values_9_5;
  wire       [16:0]   reduce8_w_values_9_6;
  wire       [16:0]   reduce8_w_values_9_7;
  wire       [16:0]   reduce8_w_values_10_0;
  wire       [16:0]   reduce8_w_values_10_1;
  wire       [16:0]   reduce8_w_values_10_2;
  wire       [16:0]   reduce8_w_values_10_3;
  wire       [16:0]   reduce8_w_values_10_4;
  wire       [16:0]   reduce8_w_values_10_5;
  wire       [16:0]   reduce8_w_values_10_6;
  wire       [16:0]   reduce8_w_values_10_7;
  wire       [16:0]   reduce8_w_values_11_0;
  wire       [16:0]   reduce8_w_values_11_1;
  wire       [16:0]   reduce8_w_values_11_2;
  wire       [16:0]   reduce8_w_values_11_3;
  wire       [16:0]   reduce8_w_values_11_4;
  wire       [16:0]   reduce8_w_values_11_5;
  wire       [16:0]   reduce8_w_values_11_6;
  wire       [16:0]   reduce8_w_values_11_7;
  wire       [16:0]   reduce8_w_values_12_0;
  wire       [16:0]   reduce8_w_values_12_1;
  wire       [16:0]   reduce8_w_values_12_2;
  wire       [16:0]   reduce8_w_values_12_3;
  wire       [16:0]   reduce8_w_values_12_4;
  wire       [16:0]   reduce8_w_values_12_5;
  wire       [16:0]   reduce8_w_values_12_6;
  wire       [16:0]   reduce8_w_values_12_7;
  wire       [16:0]   reduce8_w_values_13_0;
  wire       [16:0]   reduce8_w_values_13_1;
  wire       [16:0]   reduce8_w_values_13_2;
  wire       [16:0]   reduce8_w_values_13_3;
  wire       [16:0]   reduce8_w_values_13_4;
  wire       [16:0]   reduce8_w_values_13_5;
  wire       [16:0]   reduce8_w_values_13_6;
  wire       [16:0]   reduce8_w_values_13_7;
  wire       [16:0]   reduce8_w_values_14_0;
  wire       [16:0]   reduce8_w_values_14_1;
  wire       [16:0]   reduce8_w_values_14_2;
  wire       [16:0]   reduce8_w_values_14_3;
  wire       [16:0]   reduce8_w_values_14_4;
  wire       [16:0]   reduce8_w_values_14_5;
  wire       [16:0]   reduce8_w_values_14_6;
  wire       [16:0]   reduce8_w_values_14_7;
  wire       [16:0]   reduce8_w_values_15_0;
  wire       [16:0]   reduce8_w_values_15_1;
  wire       [16:0]   reduce8_w_values_15_2;
  wire       [16:0]   reduce8_w_values_15_3;
  wire       [16:0]   reduce8_w_values_15_4;
  wire       [16:0]   reduce8_w_values_15_5;
  wire       [16:0]   reduce8_w_values_15_6;
  wire       [16:0]   reduce8_w_values_15_7;
  wire                products_translated_valid;
  reg                 products_translated_ready;
  wire       [18:0]   products_translated_payload_tag_pixel;
  wire       [3:0]    products_translated_payload_tag_localPixel;
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
  wire       [16:0]   products_translated_payload_values_4_0;
  wire       [16:0]   products_translated_payload_values_4_1;
  wire       [16:0]   products_translated_payload_values_4_2;
  wire       [16:0]   products_translated_payload_values_4_3;
  wire       [16:0]   products_translated_payload_values_4_4;
  wire       [16:0]   products_translated_payload_values_4_5;
  wire       [16:0]   products_translated_payload_values_4_6;
  wire       [16:0]   products_translated_payload_values_4_7;
  wire       [16:0]   products_translated_payload_values_5_0;
  wire       [16:0]   products_translated_payload_values_5_1;
  wire       [16:0]   products_translated_payload_values_5_2;
  wire       [16:0]   products_translated_payload_values_5_3;
  wire       [16:0]   products_translated_payload_values_5_4;
  wire       [16:0]   products_translated_payload_values_5_5;
  wire       [16:0]   products_translated_payload_values_5_6;
  wire       [16:0]   products_translated_payload_values_5_7;
  wire       [16:0]   products_translated_payload_values_6_0;
  wire       [16:0]   products_translated_payload_values_6_1;
  wire       [16:0]   products_translated_payload_values_6_2;
  wire       [16:0]   products_translated_payload_values_6_3;
  wire       [16:0]   products_translated_payload_values_6_4;
  wire       [16:0]   products_translated_payload_values_6_5;
  wire       [16:0]   products_translated_payload_values_6_6;
  wire       [16:0]   products_translated_payload_values_6_7;
  wire       [16:0]   products_translated_payload_values_7_0;
  wire       [16:0]   products_translated_payload_values_7_1;
  wire       [16:0]   products_translated_payload_values_7_2;
  wire       [16:0]   products_translated_payload_values_7_3;
  wire       [16:0]   products_translated_payload_values_7_4;
  wire       [16:0]   products_translated_payload_values_7_5;
  wire       [16:0]   products_translated_payload_values_7_6;
  wire       [16:0]   products_translated_payload_values_7_7;
  wire       [16:0]   products_translated_payload_values_8_0;
  wire       [16:0]   products_translated_payload_values_8_1;
  wire       [16:0]   products_translated_payload_values_8_2;
  wire       [16:0]   products_translated_payload_values_8_3;
  wire       [16:0]   products_translated_payload_values_8_4;
  wire       [16:0]   products_translated_payload_values_8_5;
  wire       [16:0]   products_translated_payload_values_8_6;
  wire       [16:0]   products_translated_payload_values_8_7;
  wire       [16:0]   products_translated_payload_values_9_0;
  wire       [16:0]   products_translated_payload_values_9_1;
  wire       [16:0]   products_translated_payload_values_9_2;
  wire       [16:0]   products_translated_payload_values_9_3;
  wire       [16:0]   products_translated_payload_values_9_4;
  wire       [16:0]   products_translated_payload_values_9_5;
  wire       [16:0]   products_translated_payload_values_9_6;
  wire       [16:0]   products_translated_payload_values_9_7;
  wire       [16:0]   products_translated_payload_values_10_0;
  wire       [16:0]   products_translated_payload_values_10_1;
  wire       [16:0]   products_translated_payload_values_10_2;
  wire       [16:0]   products_translated_payload_values_10_3;
  wire       [16:0]   products_translated_payload_values_10_4;
  wire       [16:0]   products_translated_payload_values_10_5;
  wire       [16:0]   products_translated_payload_values_10_6;
  wire       [16:0]   products_translated_payload_values_10_7;
  wire       [16:0]   products_translated_payload_values_11_0;
  wire       [16:0]   products_translated_payload_values_11_1;
  wire       [16:0]   products_translated_payload_values_11_2;
  wire       [16:0]   products_translated_payload_values_11_3;
  wire       [16:0]   products_translated_payload_values_11_4;
  wire       [16:0]   products_translated_payload_values_11_5;
  wire       [16:0]   products_translated_payload_values_11_6;
  wire       [16:0]   products_translated_payload_values_11_7;
  wire       [16:0]   products_translated_payload_values_12_0;
  wire       [16:0]   products_translated_payload_values_12_1;
  wire       [16:0]   products_translated_payload_values_12_2;
  wire       [16:0]   products_translated_payload_values_12_3;
  wire       [16:0]   products_translated_payload_values_12_4;
  wire       [16:0]   products_translated_payload_values_12_5;
  wire       [16:0]   products_translated_payload_values_12_6;
  wire       [16:0]   products_translated_payload_values_12_7;
  wire       [16:0]   products_translated_payload_values_13_0;
  wire       [16:0]   products_translated_payload_values_13_1;
  wire       [16:0]   products_translated_payload_values_13_2;
  wire       [16:0]   products_translated_payload_values_13_3;
  wire       [16:0]   products_translated_payload_values_13_4;
  wire       [16:0]   products_translated_payload_values_13_5;
  wire       [16:0]   products_translated_payload_values_13_6;
  wire       [16:0]   products_translated_payload_values_13_7;
  wire       [16:0]   products_translated_payload_values_14_0;
  wire       [16:0]   products_translated_payload_values_14_1;
  wire       [16:0]   products_translated_payload_values_14_2;
  wire       [16:0]   products_translated_payload_values_14_3;
  wire       [16:0]   products_translated_payload_values_14_4;
  wire       [16:0]   products_translated_payload_values_14_5;
  wire       [16:0]   products_translated_payload_values_14_6;
  wire       [16:0]   products_translated_payload_values_14_7;
  wire       [16:0]   products_translated_payload_values_15_0;
  wire       [16:0]   products_translated_payload_values_15_1;
  wire       [16:0]   products_translated_payload_values_15_2;
  wire       [16:0]   products_translated_payload_values_15_3;
  wire       [16:0]   products_translated_payload_values_15_4;
  wire       [16:0]   products_translated_payload_values_15_5;
  wire       [16:0]   products_translated_payload_values_15_6;
  wire       [16:0]   products_translated_payload_values_15_7;
  wire                reduce8_valid;
  wire                reduce8_ready;
  wire       [18:0]   reduce8_payload_tag_pixel;
  wire       [3:0]    reduce8_payload_tag_localPixel;
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
  wire       [16:0]   reduce8_payload_values_4_0;
  wire       [16:0]   reduce8_payload_values_4_1;
  wire       [16:0]   reduce8_payload_values_4_2;
  wire       [16:0]   reduce8_payload_values_4_3;
  wire       [16:0]   reduce8_payload_values_4_4;
  wire       [16:0]   reduce8_payload_values_4_5;
  wire       [16:0]   reduce8_payload_values_4_6;
  wire       [16:0]   reduce8_payload_values_4_7;
  wire       [16:0]   reduce8_payload_values_5_0;
  wire       [16:0]   reduce8_payload_values_5_1;
  wire       [16:0]   reduce8_payload_values_5_2;
  wire       [16:0]   reduce8_payload_values_5_3;
  wire       [16:0]   reduce8_payload_values_5_4;
  wire       [16:0]   reduce8_payload_values_5_5;
  wire       [16:0]   reduce8_payload_values_5_6;
  wire       [16:0]   reduce8_payload_values_5_7;
  wire       [16:0]   reduce8_payload_values_6_0;
  wire       [16:0]   reduce8_payload_values_6_1;
  wire       [16:0]   reduce8_payload_values_6_2;
  wire       [16:0]   reduce8_payload_values_6_3;
  wire       [16:0]   reduce8_payload_values_6_4;
  wire       [16:0]   reduce8_payload_values_6_5;
  wire       [16:0]   reduce8_payload_values_6_6;
  wire       [16:0]   reduce8_payload_values_6_7;
  wire       [16:0]   reduce8_payload_values_7_0;
  wire       [16:0]   reduce8_payload_values_7_1;
  wire       [16:0]   reduce8_payload_values_7_2;
  wire       [16:0]   reduce8_payload_values_7_3;
  wire       [16:0]   reduce8_payload_values_7_4;
  wire       [16:0]   reduce8_payload_values_7_5;
  wire       [16:0]   reduce8_payload_values_7_6;
  wire       [16:0]   reduce8_payload_values_7_7;
  wire       [16:0]   reduce8_payload_values_8_0;
  wire       [16:0]   reduce8_payload_values_8_1;
  wire       [16:0]   reduce8_payload_values_8_2;
  wire       [16:0]   reduce8_payload_values_8_3;
  wire       [16:0]   reduce8_payload_values_8_4;
  wire       [16:0]   reduce8_payload_values_8_5;
  wire       [16:0]   reduce8_payload_values_8_6;
  wire       [16:0]   reduce8_payload_values_8_7;
  wire       [16:0]   reduce8_payload_values_9_0;
  wire       [16:0]   reduce8_payload_values_9_1;
  wire       [16:0]   reduce8_payload_values_9_2;
  wire       [16:0]   reduce8_payload_values_9_3;
  wire       [16:0]   reduce8_payload_values_9_4;
  wire       [16:0]   reduce8_payload_values_9_5;
  wire       [16:0]   reduce8_payload_values_9_6;
  wire       [16:0]   reduce8_payload_values_9_7;
  wire       [16:0]   reduce8_payload_values_10_0;
  wire       [16:0]   reduce8_payload_values_10_1;
  wire       [16:0]   reduce8_payload_values_10_2;
  wire       [16:0]   reduce8_payload_values_10_3;
  wire       [16:0]   reduce8_payload_values_10_4;
  wire       [16:0]   reduce8_payload_values_10_5;
  wire       [16:0]   reduce8_payload_values_10_6;
  wire       [16:0]   reduce8_payload_values_10_7;
  wire       [16:0]   reduce8_payload_values_11_0;
  wire       [16:0]   reduce8_payload_values_11_1;
  wire       [16:0]   reduce8_payload_values_11_2;
  wire       [16:0]   reduce8_payload_values_11_3;
  wire       [16:0]   reduce8_payload_values_11_4;
  wire       [16:0]   reduce8_payload_values_11_5;
  wire       [16:0]   reduce8_payload_values_11_6;
  wire       [16:0]   reduce8_payload_values_11_7;
  wire       [16:0]   reduce8_payload_values_12_0;
  wire       [16:0]   reduce8_payload_values_12_1;
  wire       [16:0]   reduce8_payload_values_12_2;
  wire       [16:0]   reduce8_payload_values_12_3;
  wire       [16:0]   reduce8_payload_values_12_4;
  wire       [16:0]   reduce8_payload_values_12_5;
  wire       [16:0]   reduce8_payload_values_12_6;
  wire       [16:0]   reduce8_payload_values_12_7;
  wire       [16:0]   reduce8_payload_values_13_0;
  wire       [16:0]   reduce8_payload_values_13_1;
  wire       [16:0]   reduce8_payload_values_13_2;
  wire       [16:0]   reduce8_payload_values_13_3;
  wire       [16:0]   reduce8_payload_values_13_4;
  wire       [16:0]   reduce8_payload_values_13_5;
  wire       [16:0]   reduce8_payload_values_13_6;
  wire       [16:0]   reduce8_payload_values_13_7;
  wire       [16:0]   reduce8_payload_values_14_0;
  wire       [16:0]   reduce8_payload_values_14_1;
  wire       [16:0]   reduce8_payload_values_14_2;
  wire       [16:0]   reduce8_payload_values_14_3;
  wire       [16:0]   reduce8_payload_values_14_4;
  wire       [16:0]   reduce8_payload_values_14_5;
  wire       [16:0]   reduce8_payload_values_14_6;
  wire       [16:0]   reduce8_payload_values_14_7;
  wire       [16:0]   reduce8_payload_values_15_0;
  wire       [16:0]   reduce8_payload_values_15_1;
  wire       [16:0]   reduce8_payload_values_15_2;
  wire       [16:0]   reduce8_payload_values_15_3;
  wire       [16:0]   reduce8_payload_values_15_4;
  wire       [16:0]   reduce8_payload_values_15_5;
  wire       [16:0]   reduce8_payload_values_15_6;
  wire       [16:0]   reduce8_payload_values_15_7;
  reg                 products_translated_rValid;
  reg        [18:0]   products_translated_rData_tag_pixel;
  reg        [3:0]    products_translated_rData_tag_localPixel;
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
  reg        [16:0]   products_translated_rData_values_4_0;
  reg        [16:0]   products_translated_rData_values_4_1;
  reg        [16:0]   products_translated_rData_values_4_2;
  reg        [16:0]   products_translated_rData_values_4_3;
  reg        [16:0]   products_translated_rData_values_4_4;
  reg        [16:0]   products_translated_rData_values_4_5;
  reg        [16:0]   products_translated_rData_values_4_6;
  reg        [16:0]   products_translated_rData_values_4_7;
  reg        [16:0]   products_translated_rData_values_5_0;
  reg        [16:0]   products_translated_rData_values_5_1;
  reg        [16:0]   products_translated_rData_values_5_2;
  reg        [16:0]   products_translated_rData_values_5_3;
  reg        [16:0]   products_translated_rData_values_5_4;
  reg        [16:0]   products_translated_rData_values_5_5;
  reg        [16:0]   products_translated_rData_values_5_6;
  reg        [16:0]   products_translated_rData_values_5_7;
  reg        [16:0]   products_translated_rData_values_6_0;
  reg        [16:0]   products_translated_rData_values_6_1;
  reg        [16:0]   products_translated_rData_values_6_2;
  reg        [16:0]   products_translated_rData_values_6_3;
  reg        [16:0]   products_translated_rData_values_6_4;
  reg        [16:0]   products_translated_rData_values_6_5;
  reg        [16:0]   products_translated_rData_values_6_6;
  reg        [16:0]   products_translated_rData_values_6_7;
  reg        [16:0]   products_translated_rData_values_7_0;
  reg        [16:0]   products_translated_rData_values_7_1;
  reg        [16:0]   products_translated_rData_values_7_2;
  reg        [16:0]   products_translated_rData_values_7_3;
  reg        [16:0]   products_translated_rData_values_7_4;
  reg        [16:0]   products_translated_rData_values_7_5;
  reg        [16:0]   products_translated_rData_values_7_6;
  reg        [16:0]   products_translated_rData_values_7_7;
  reg        [16:0]   products_translated_rData_values_8_0;
  reg        [16:0]   products_translated_rData_values_8_1;
  reg        [16:0]   products_translated_rData_values_8_2;
  reg        [16:0]   products_translated_rData_values_8_3;
  reg        [16:0]   products_translated_rData_values_8_4;
  reg        [16:0]   products_translated_rData_values_8_5;
  reg        [16:0]   products_translated_rData_values_8_6;
  reg        [16:0]   products_translated_rData_values_8_7;
  reg        [16:0]   products_translated_rData_values_9_0;
  reg        [16:0]   products_translated_rData_values_9_1;
  reg        [16:0]   products_translated_rData_values_9_2;
  reg        [16:0]   products_translated_rData_values_9_3;
  reg        [16:0]   products_translated_rData_values_9_4;
  reg        [16:0]   products_translated_rData_values_9_5;
  reg        [16:0]   products_translated_rData_values_9_6;
  reg        [16:0]   products_translated_rData_values_9_7;
  reg        [16:0]   products_translated_rData_values_10_0;
  reg        [16:0]   products_translated_rData_values_10_1;
  reg        [16:0]   products_translated_rData_values_10_2;
  reg        [16:0]   products_translated_rData_values_10_3;
  reg        [16:0]   products_translated_rData_values_10_4;
  reg        [16:0]   products_translated_rData_values_10_5;
  reg        [16:0]   products_translated_rData_values_10_6;
  reg        [16:0]   products_translated_rData_values_10_7;
  reg        [16:0]   products_translated_rData_values_11_0;
  reg        [16:0]   products_translated_rData_values_11_1;
  reg        [16:0]   products_translated_rData_values_11_2;
  reg        [16:0]   products_translated_rData_values_11_3;
  reg        [16:0]   products_translated_rData_values_11_4;
  reg        [16:0]   products_translated_rData_values_11_5;
  reg        [16:0]   products_translated_rData_values_11_6;
  reg        [16:0]   products_translated_rData_values_11_7;
  reg        [16:0]   products_translated_rData_values_12_0;
  reg        [16:0]   products_translated_rData_values_12_1;
  reg        [16:0]   products_translated_rData_values_12_2;
  reg        [16:0]   products_translated_rData_values_12_3;
  reg        [16:0]   products_translated_rData_values_12_4;
  reg        [16:0]   products_translated_rData_values_12_5;
  reg        [16:0]   products_translated_rData_values_12_6;
  reg        [16:0]   products_translated_rData_values_12_7;
  reg        [16:0]   products_translated_rData_values_13_0;
  reg        [16:0]   products_translated_rData_values_13_1;
  reg        [16:0]   products_translated_rData_values_13_2;
  reg        [16:0]   products_translated_rData_values_13_3;
  reg        [16:0]   products_translated_rData_values_13_4;
  reg        [16:0]   products_translated_rData_values_13_5;
  reg        [16:0]   products_translated_rData_values_13_6;
  reg        [16:0]   products_translated_rData_values_13_7;
  reg        [16:0]   products_translated_rData_values_14_0;
  reg        [16:0]   products_translated_rData_values_14_1;
  reg        [16:0]   products_translated_rData_values_14_2;
  reg        [16:0]   products_translated_rData_values_14_3;
  reg        [16:0]   products_translated_rData_values_14_4;
  reg        [16:0]   products_translated_rData_values_14_5;
  reg        [16:0]   products_translated_rData_values_14_6;
  reg        [16:0]   products_translated_rData_values_14_7;
  reg        [16:0]   products_translated_rData_values_15_0;
  reg        [16:0]   products_translated_rData_values_15_1;
  reg        [16:0]   products_translated_rData_values_15_2;
  reg        [16:0]   products_translated_rData_values_15_3;
  reg        [16:0]   products_translated_rData_values_15_4;
  reg        [16:0]   products_translated_rData_values_15_5;
  reg        [16:0]   products_translated_rData_values_15_6;
  reg        [16:0]   products_translated_rData_values_15_7;
  wire                when_Stream_l477_3;
  wire       [18:0]   reduce4_w_tag_pixel;
  wire       [3:0]    reduce4_w_tag_localPixel;
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
  wire       [17:0]   reduce4_w_values_4_0;
  wire       [17:0]   reduce4_w_values_4_1;
  wire       [17:0]   reduce4_w_values_4_2;
  wire       [17:0]   reduce4_w_values_4_3;
  wire       [17:0]   reduce4_w_values_5_0;
  wire       [17:0]   reduce4_w_values_5_1;
  wire       [17:0]   reduce4_w_values_5_2;
  wire       [17:0]   reduce4_w_values_5_3;
  wire       [17:0]   reduce4_w_values_6_0;
  wire       [17:0]   reduce4_w_values_6_1;
  wire       [17:0]   reduce4_w_values_6_2;
  wire       [17:0]   reduce4_w_values_6_3;
  wire       [17:0]   reduce4_w_values_7_0;
  wire       [17:0]   reduce4_w_values_7_1;
  wire       [17:0]   reduce4_w_values_7_2;
  wire       [17:0]   reduce4_w_values_7_3;
  wire       [17:0]   reduce4_w_values_8_0;
  wire       [17:0]   reduce4_w_values_8_1;
  wire       [17:0]   reduce4_w_values_8_2;
  wire       [17:0]   reduce4_w_values_8_3;
  wire       [17:0]   reduce4_w_values_9_0;
  wire       [17:0]   reduce4_w_values_9_1;
  wire       [17:0]   reduce4_w_values_9_2;
  wire       [17:0]   reduce4_w_values_9_3;
  wire       [17:0]   reduce4_w_values_10_0;
  wire       [17:0]   reduce4_w_values_10_1;
  wire       [17:0]   reduce4_w_values_10_2;
  wire       [17:0]   reduce4_w_values_10_3;
  wire       [17:0]   reduce4_w_values_11_0;
  wire       [17:0]   reduce4_w_values_11_1;
  wire       [17:0]   reduce4_w_values_11_2;
  wire       [17:0]   reduce4_w_values_11_3;
  wire       [17:0]   reduce4_w_values_12_0;
  wire       [17:0]   reduce4_w_values_12_1;
  wire       [17:0]   reduce4_w_values_12_2;
  wire       [17:0]   reduce4_w_values_12_3;
  wire       [17:0]   reduce4_w_values_13_0;
  wire       [17:0]   reduce4_w_values_13_1;
  wire       [17:0]   reduce4_w_values_13_2;
  wire       [17:0]   reduce4_w_values_13_3;
  wire       [17:0]   reduce4_w_values_14_0;
  wire       [17:0]   reduce4_w_values_14_1;
  wire       [17:0]   reduce4_w_values_14_2;
  wire       [17:0]   reduce4_w_values_14_3;
  wire       [17:0]   reduce4_w_values_15_0;
  wire       [17:0]   reduce4_w_values_15_1;
  wire       [17:0]   reduce4_w_values_15_2;
  wire       [17:0]   reduce4_w_values_15_3;
  wire                reduce8_translated_valid;
  reg                 reduce8_translated_ready;
  wire       [18:0]   reduce8_translated_payload_tag_pixel;
  wire       [3:0]    reduce8_translated_payload_tag_localPixel;
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
  wire       [17:0]   reduce8_translated_payload_values_4_0;
  wire       [17:0]   reduce8_translated_payload_values_4_1;
  wire       [17:0]   reduce8_translated_payload_values_4_2;
  wire       [17:0]   reduce8_translated_payload_values_4_3;
  wire       [17:0]   reduce8_translated_payload_values_5_0;
  wire       [17:0]   reduce8_translated_payload_values_5_1;
  wire       [17:0]   reduce8_translated_payload_values_5_2;
  wire       [17:0]   reduce8_translated_payload_values_5_3;
  wire       [17:0]   reduce8_translated_payload_values_6_0;
  wire       [17:0]   reduce8_translated_payload_values_6_1;
  wire       [17:0]   reduce8_translated_payload_values_6_2;
  wire       [17:0]   reduce8_translated_payload_values_6_3;
  wire       [17:0]   reduce8_translated_payload_values_7_0;
  wire       [17:0]   reduce8_translated_payload_values_7_1;
  wire       [17:0]   reduce8_translated_payload_values_7_2;
  wire       [17:0]   reduce8_translated_payload_values_7_3;
  wire       [17:0]   reduce8_translated_payload_values_8_0;
  wire       [17:0]   reduce8_translated_payload_values_8_1;
  wire       [17:0]   reduce8_translated_payload_values_8_2;
  wire       [17:0]   reduce8_translated_payload_values_8_3;
  wire       [17:0]   reduce8_translated_payload_values_9_0;
  wire       [17:0]   reduce8_translated_payload_values_9_1;
  wire       [17:0]   reduce8_translated_payload_values_9_2;
  wire       [17:0]   reduce8_translated_payload_values_9_3;
  wire       [17:0]   reduce8_translated_payload_values_10_0;
  wire       [17:0]   reduce8_translated_payload_values_10_1;
  wire       [17:0]   reduce8_translated_payload_values_10_2;
  wire       [17:0]   reduce8_translated_payload_values_10_3;
  wire       [17:0]   reduce8_translated_payload_values_11_0;
  wire       [17:0]   reduce8_translated_payload_values_11_1;
  wire       [17:0]   reduce8_translated_payload_values_11_2;
  wire       [17:0]   reduce8_translated_payload_values_11_3;
  wire       [17:0]   reduce8_translated_payload_values_12_0;
  wire       [17:0]   reduce8_translated_payload_values_12_1;
  wire       [17:0]   reduce8_translated_payload_values_12_2;
  wire       [17:0]   reduce8_translated_payload_values_12_3;
  wire       [17:0]   reduce8_translated_payload_values_13_0;
  wire       [17:0]   reduce8_translated_payload_values_13_1;
  wire       [17:0]   reduce8_translated_payload_values_13_2;
  wire       [17:0]   reduce8_translated_payload_values_13_3;
  wire       [17:0]   reduce8_translated_payload_values_14_0;
  wire       [17:0]   reduce8_translated_payload_values_14_1;
  wire       [17:0]   reduce8_translated_payload_values_14_2;
  wire       [17:0]   reduce8_translated_payload_values_14_3;
  wire       [17:0]   reduce8_translated_payload_values_15_0;
  wire       [17:0]   reduce8_translated_payload_values_15_1;
  wire       [17:0]   reduce8_translated_payload_values_15_2;
  wire       [17:0]   reduce8_translated_payload_values_15_3;
  wire                reduce4_valid;
  wire                reduce4_ready;
  wire       [18:0]   reduce4_payload_tag_pixel;
  wire       [3:0]    reduce4_payload_tag_localPixel;
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
  wire       [17:0]   reduce4_payload_values_4_0;
  wire       [17:0]   reduce4_payload_values_4_1;
  wire       [17:0]   reduce4_payload_values_4_2;
  wire       [17:0]   reduce4_payload_values_4_3;
  wire       [17:0]   reduce4_payload_values_5_0;
  wire       [17:0]   reduce4_payload_values_5_1;
  wire       [17:0]   reduce4_payload_values_5_2;
  wire       [17:0]   reduce4_payload_values_5_3;
  wire       [17:0]   reduce4_payload_values_6_0;
  wire       [17:0]   reduce4_payload_values_6_1;
  wire       [17:0]   reduce4_payload_values_6_2;
  wire       [17:0]   reduce4_payload_values_6_3;
  wire       [17:0]   reduce4_payload_values_7_0;
  wire       [17:0]   reduce4_payload_values_7_1;
  wire       [17:0]   reduce4_payload_values_7_2;
  wire       [17:0]   reduce4_payload_values_7_3;
  wire       [17:0]   reduce4_payload_values_8_0;
  wire       [17:0]   reduce4_payload_values_8_1;
  wire       [17:0]   reduce4_payload_values_8_2;
  wire       [17:0]   reduce4_payload_values_8_3;
  wire       [17:0]   reduce4_payload_values_9_0;
  wire       [17:0]   reduce4_payload_values_9_1;
  wire       [17:0]   reduce4_payload_values_9_2;
  wire       [17:0]   reduce4_payload_values_9_3;
  wire       [17:0]   reduce4_payload_values_10_0;
  wire       [17:0]   reduce4_payload_values_10_1;
  wire       [17:0]   reduce4_payload_values_10_2;
  wire       [17:0]   reduce4_payload_values_10_3;
  wire       [17:0]   reduce4_payload_values_11_0;
  wire       [17:0]   reduce4_payload_values_11_1;
  wire       [17:0]   reduce4_payload_values_11_2;
  wire       [17:0]   reduce4_payload_values_11_3;
  wire       [17:0]   reduce4_payload_values_12_0;
  wire       [17:0]   reduce4_payload_values_12_1;
  wire       [17:0]   reduce4_payload_values_12_2;
  wire       [17:0]   reduce4_payload_values_12_3;
  wire       [17:0]   reduce4_payload_values_13_0;
  wire       [17:0]   reduce4_payload_values_13_1;
  wire       [17:0]   reduce4_payload_values_13_2;
  wire       [17:0]   reduce4_payload_values_13_3;
  wire       [17:0]   reduce4_payload_values_14_0;
  wire       [17:0]   reduce4_payload_values_14_1;
  wire       [17:0]   reduce4_payload_values_14_2;
  wire       [17:0]   reduce4_payload_values_14_3;
  wire       [17:0]   reduce4_payload_values_15_0;
  wire       [17:0]   reduce4_payload_values_15_1;
  wire       [17:0]   reduce4_payload_values_15_2;
  wire       [17:0]   reduce4_payload_values_15_3;
  reg                 reduce8_translated_rValid;
  reg        [18:0]   reduce8_translated_rData_tag_pixel;
  reg        [3:0]    reduce8_translated_rData_tag_localPixel;
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
  reg        [17:0]   reduce8_translated_rData_values_4_0;
  reg        [17:0]   reduce8_translated_rData_values_4_1;
  reg        [17:0]   reduce8_translated_rData_values_4_2;
  reg        [17:0]   reduce8_translated_rData_values_4_3;
  reg        [17:0]   reduce8_translated_rData_values_5_0;
  reg        [17:0]   reduce8_translated_rData_values_5_1;
  reg        [17:0]   reduce8_translated_rData_values_5_2;
  reg        [17:0]   reduce8_translated_rData_values_5_3;
  reg        [17:0]   reduce8_translated_rData_values_6_0;
  reg        [17:0]   reduce8_translated_rData_values_6_1;
  reg        [17:0]   reduce8_translated_rData_values_6_2;
  reg        [17:0]   reduce8_translated_rData_values_6_3;
  reg        [17:0]   reduce8_translated_rData_values_7_0;
  reg        [17:0]   reduce8_translated_rData_values_7_1;
  reg        [17:0]   reduce8_translated_rData_values_7_2;
  reg        [17:0]   reduce8_translated_rData_values_7_3;
  reg        [17:0]   reduce8_translated_rData_values_8_0;
  reg        [17:0]   reduce8_translated_rData_values_8_1;
  reg        [17:0]   reduce8_translated_rData_values_8_2;
  reg        [17:0]   reduce8_translated_rData_values_8_3;
  reg        [17:0]   reduce8_translated_rData_values_9_0;
  reg        [17:0]   reduce8_translated_rData_values_9_1;
  reg        [17:0]   reduce8_translated_rData_values_9_2;
  reg        [17:0]   reduce8_translated_rData_values_9_3;
  reg        [17:0]   reduce8_translated_rData_values_10_0;
  reg        [17:0]   reduce8_translated_rData_values_10_1;
  reg        [17:0]   reduce8_translated_rData_values_10_2;
  reg        [17:0]   reduce8_translated_rData_values_10_3;
  reg        [17:0]   reduce8_translated_rData_values_11_0;
  reg        [17:0]   reduce8_translated_rData_values_11_1;
  reg        [17:0]   reduce8_translated_rData_values_11_2;
  reg        [17:0]   reduce8_translated_rData_values_11_3;
  reg        [17:0]   reduce8_translated_rData_values_12_0;
  reg        [17:0]   reduce8_translated_rData_values_12_1;
  reg        [17:0]   reduce8_translated_rData_values_12_2;
  reg        [17:0]   reduce8_translated_rData_values_12_3;
  reg        [17:0]   reduce8_translated_rData_values_13_0;
  reg        [17:0]   reduce8_translated_rData_values_13_1;
  reg        [17:0]   reduce8_translated_rData_values_13_2;
  reg        [17:0]   reduce8_translated_rData_values_13_3;
  reg        [17:0]   reduce8_translated_rData_values_14_0;
  reg        [17:0]   reduce8_translated_rData_values_14_1;
  reg        [17:0]   reduce8_translated_rData_values_14_2;
  reg        [17:0]   reduce8_translated_rData_values_14_3;
  reg        [17:0]   reduce8_translated_rData_values_15_0;
  reg        [17:0]   reduce8_translated_rData_values_15_1;
  reg        [17:0]   reduce8_translated_rData_values_15_2;
  reg        [17:0]   reduce8_translated_rData_values_15_3;
  wire                when_Stream_l477_4;
  wire       [18:0]   reduce2_w_tag_pixel;
  wire       [3:0]    reduce2_w_tag_localPixel;
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
  wire       [18:0]   reduce2_w_values_4_0;
  wire       [18:0]   reduce2_w_values_4_1;
  wire       [18:0]   reduce2_w_values_5_0;
  wire       [18:0]   reduce2_w_values_5_1;
  wire       [18:0]   reduce2_w_values_6_0;
  wire       [18:0]   reduce2_w_values_6_1;
  wire       [18:0]   reduce2_w_values_7_0;
  wire       [18:0]   reduce2_w_values_7_1;
  wire       [18:0]   reduce2_w_values_8_0;
  wire       [18:0]   reduce2_w_values_8_1;
  wire       [18:0]   reduce2_w_values_9_0;
  wire       [18:0]   reduce2_w_values_9_1;
  wire       [18:0]   reduce2_w_values_10_0;
  wire       [18:0]   reduce2_w_values_10_1;
  wire       [18:0]   reduce2_w_values_11_0;
  wire       [18:0]   reduce2_w_values_11_1;
  wire       [18:0]   reduce2_w_values_12_0;
  wire       [18:0]   reduce2_w_values_12_1;
  wire       [18:0]   reduce2_w_values_13_0;
  wire       [18:0]   reduce2_w_values_13_1;
  wire       [18:0]   reduce2_w_values_14_0;
  wire       [18:0]   reduce2_w_values_14_1;
  wire       [18:0]   reduce2_w_values_15_0;
  wire       [18:0]   reduce2_w_values_15_1;
  wire                reduce4_translated_valid;
  reg                 reduce4_translated_ready;
  wire       [18:0]   reduce4_translated_payload_tag_pixel;
  wire       [3:0]    reduce4_translated_payload_tag_localPixel;
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
  wire       [18:0]   reduce4_translated_payload_values_4_0;
  wire       [18:0]   reduce4_translated_payload_values_4_1;
  wire       [18:0]   reduce4_translated_payload_values_5_0;
  wire       [18:0]   reduce4_translated_payload_values_5_1;
  wire       [18:0]   reduce4_translated_payload_values_6_0;
  wire       [18:0]   reduce4_translated_payload_values_6_1;
  wire       [18:0]   reduce4_translated_payload_values_7_0;
  wire       [18:0]   reduce4_translated_payload_values_7_1;
  wire       [18:0]   reduce4_translated_payload_values_8_0;
  wire       [18:0]   reduce4_translated_payload_values_8_1;
  wire       [18:0]   reduce4_translated_payload_values_9_0;
  wire       [18:0]   reduce4_translated_payload_values_9_1;
  wire       [18:0]   reduce4_translated_payload_values_10_0;
  wire       [18:0]   reduce4_translated_payload_values_10_1;
  wire       [18:0]   reduce4_translated_payload_values_11_0;
  wire       [18:0]   reduce4_translated_payload_values_11_1;
  wire       [18:0]   reduce4_translated_payload_values_12_0;
  wire       [18:0]   reduce4_translated_payload_values_12_1;
  wire       [18:0]   reduce4_translated_payload_values_13_0;
  wire       [18:0]   reduce4_translated_payload_values_13_1;
  wire       [18:0]   reduce4_translated_payload_values_14_0;
  wire       [18:0]   reduce4_translated_payload_values_14_1;
  wire       [18:0]   reduce4_translated_payload_values_15_0;
  wire       [18:0]   reduce4_translated_payload_values_15_1;
  wire                reduce2_valid;
  wire                reduce2_ready;
  wire       [18:0]   reduce2_payload_tag_pixel;
  wire       [3:0]    reduce2_payload_tag_localPixel;
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
  wire       [18:0]   reduce2_payload_values_4_0;
  wire       [18:0]   reduce2_payload_values_4_1;
  wire       [18:0]   reduce2_payload_values_5_0;
  wire       [18:0]   reduce2_payload_values_5_1;
  wire       [18:0]   reduce2_payload_values_6_0;
  wire       [18:0]   reduce2_payload_values_6_1;
  wire       [18:0]   reduce2_payload_values_7_0;
  wire       [18:0]   reduce2_payload_values_7_1;
  wire       [18:0]   reduce2_payload_values_8_0;
  wire       [18:0]   reduce2_payload_values_8_1;
  wire       [18:0]   reduce2_payload_values_9_0;
  wire       [18:0]   reduce2_payload_values_9_1;
  wire       [18:0]   reduce2_payload_values_10_0;
  wire       [18:0]   reduce2_payload_values_10_1;
  wire       [18:0]   reduce2_payload_values_11_0;
  wire       [18:0]   reduce2_payload_values_11_1;
  wire       [18:0]   reduce2_payload_values_12_0;
  wire       [18:0]   reduce2_payload_values_12_1;
  wire       [18:0]   reduce2_payload_values_13_0;
  wire       [18:0]   reduce2_payload_values_13_1;
  wire       [18:0]   reduce2_payload_values_14_0;
  wire       [18:0]   reduce2_payload_values_14_1;
  wire       [18:0]   reduce2_payload_values_15_0;
  wire       [18:0]   reduce2_payload_values_15_1;
  reg                 reduce4_translated_rValid;
  reg        [18:0]   reduce4_translated_rData_tag_pixel;
  reg        [3:0]    reduce4_translated_rData_tag_localPixel;
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
  reg        [18:0]   reduce4_translated_rData_values_4_0;
  reg        [18:0]   reduce4_translated_rData_values_4_1;
  reg        [18:0]   reduce4_translated_rData_values_5_0;
  reg        [18:0]   reduce4_translated_rData_values_5_1;
  reg        [18:0]   reduce4_translated_rData_values_6_0;
  reg        [18:0]   reduce4_translated_rData_values_6_1;
  reg        [18:0]   reduce4_translated_rData_values_7_0;
  reg        [18:0]   reduce4_translated_rData_values_7_1;
  reg        [18:0]   reduce4_translated_rData_values_8_0;
  reg        [18:0]   reduce4_translated_rData_values_8_1;
  reg        [18:0]   reduce4_translated_rData_values_9_0;
  reg        [18:0]   reduce4_translated_rData_values_9_1;
  reg        [18:0]   reduce4_translated_rData_values_10_0;
  reg        [18:0]   reduce4_translated_rData_values_10_1;
  reg        [18:0]   reduce4_translated_rData_values_11_0;
  reg        [18:0]   reduce4_translated_rData_values_11_1;
  reg        [18:0]   reduce4_translated_rData_values_12_0;
  reg        [18:0]   reduce4_translated_rData_values_12_1;
  reg        [18:0]   reduce4_translated_rData_values_13_0;
  reg        [18:0]   reduce4_translated_rData_values_13_1;
  reg        [18:0]   reduce4_translated_rData_values_14_0;
  reg        [18:0]   reduce4_translated_rData_values_14_1;
  reg        [18:0]   reduce4_translated_rData_values_15_0;
  reg        [18:0]   reduce4_translated_rData_values_15_1;
  wire                when_Stream_l477_5;
  wire       [18:0]   dot_w_tag_pixel;
  wire       [3:0]    dot_w_tag_localPixel;
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
  wire       [19:0]   dot_w_values_4_0;
  wire       [19:0]   dot_w_values_5_0;
  wire       [19:0]   dot_w_values_6_0;
  wire       [19:0]   dot_w_values_7_0;
  wire       [19:0]   dot_w_values_8_0;
  wire       [19:0]   dot_w_values_9_0;
  wire       [19:0]   dot_w_values_10_0;
  wire       [19:0]   dot_w_values_11_0;
  wire       [19:0]   dot_w_values_12_0;
  wire       [19:0]   dot_w_values_13_0;
  wire       [19:0]   dot_w_values_14_0;
  wire       [19:0]   dot_w_values_15_0;
  wire                reduce2_translated_valid;
  reg                 reduce2_translated_ready;
  wire       [18:0]   reduce2_translated_payload_tag_pixel;
  wire       [3:0]    reduce2_translated_payload_tag_localPixel;
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
  wire       [19:0]   reduce2_translated_payload_values_4_0;
  wire       [19:0]   reduce2_translated_payload_values_5_0;
  wire       [19:0]   reduce2_translated_payload_values_6_0;
  wire       [19:0]   reduce2_translated_payload_values_7_0;
  wire       [19:0]   reduce2_translated_payload_values_8_0;
  wire       [19:0]   reduce2_translated_payload_values_9_0;
  wire       [19:0]   reduce2_translated_payload_values_10_0;
  wire       [19:0]   reduce2_translated_payload_values_11_0;
  wire       [19:0]   reduce2_translated_payload_values_12_0;
  wire       [19:0]   reduce2_translated_payload_values_13_0;
  wire       [19:0]   reduce2_translated_payload_values_14_0;
  wire       [19:0]   reduce2_translated_payload_values_15_0;
  wire                dot_valid;
  wire                dot_ready;
  wire       [18:0]   dot_payload_tag_pixel;
  wire       [3:0]    dot_payload_tag_localPixel;
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
  wire       [19:0]   dot_payload_values_4_0;
  wire       [19:0]   dot_payload_values_5_0;
  wire       [19:0]   dot_payload_values_6_0;
  wire       [19:0]   dot_payload_values_7_0;
  wire       [19:0]   dot_payload_values_8_0;
  wire       [19:0]   dot_payload_values_9_0;
  wire       [19:0]   dot_payload_values_10_0;
  wire       [19:0]   dot_payload_values_11_0;
  wire       [19:0]   dot_payload_values_12_0;
  wire       [19:0]   dot_payload_values_13_0;
  wire       [19:0]   dot_payload_values_14_0;
  wire       [19:0]   dot_payload_values_15_0;
  reg                 reduce2_translated_rValid;
  reg        [18:0]   reduce2_translated_rData_tag_pixel;
  reg        [3:0]    reduce2_translated_rData_tag_localPixel;
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
  reg        [19:0]   reduce2_translated_rData_values_4_0;
  reg        [19:0]   reduce2_translated_rData_values_5_0;
  reg        [19:0]   reduce2_translated_rData_values_6_0;
  reg        [19:0]   reduce2_translated_rData_values_7_0;
  reg        [19:0]   reduce2_translated_rData_values_8_0;
  reg        [19:0]   reduce2_translated_rData_values_9_0;
  reg        [19:0]   reduce2_translated_rData_values_10_0;
  reg        [19:0]   reduce2_translated_rData_values_11_0;
  reg        [19:0]   reduce2_translated_rData_values_12_0;
  reg        [19:0]   reduce2_translated_rData_values_13_0;
  reg        [19:0]   reduce2_translated_rData_values_14_0;
  reg        [19:0]   reduce2_translated_rData_values_15_0;
  wire                when_Stream_l477_6;
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
  reg        [31:0]   acc_r_4_0;
  reg        [31:0]   acc_r_4_1;
  reg        [31:0]   acc_r_4_2;
  reg        [31:0]   acc_r_4_3;
  reg        [31:0]   acc_r_4_4;
  reg        [31:0]   acc_r_4_5;
  reg        [31:0]   acc_r_4_6;
  reg        [31:0]   acc_r_4_7;
  reg        [31:0]   acc_r_4_8;
  reg        [31:0]   acc_r_4_9;
  reg        [31:0]   acc_r_4_10;
  reg        [31:0]   acc_r_4_11;
  reg        [31:0]   acc_r_4_12;
  reg        [31:0]   acc_r_4_13;
  reg        [31:0]   acc_r_4_14;
  reg        [31:0]   acc_r_4_15;
  reg        [31:0]   acc_r_5_0;
  reg        [31:0]   acc_r_5_1;
  reg        [31:0]   acc_r_5_2;
  reg        [31:0]   acc_r_5_3;
  reg        [31:0]   acc_r_5_4;
  reg        [31:0]   acc_r_5_5;
  reg        [31:0]   acc_r_5_6;
  reg        [31:0]   acc_r_5_7;
  reg        [31:0]   acc_r_5_8;
  reg        [31:0]   acc_r_5_9;
  reg        [31:0]   acc_r_5_10;
  reg        [31:0]   acc_r_5_11;
  reg        [31:0]   acc_r_5_12;
  reg        [31:0]   acc_r_5_13;
  reg        [31:0]   acc_r_5_14;
  reg        [31:0]   acc_r_5_15;
  reg        [31:0]   acc_r_6_0;
  reg        [31:0]   acc_r_6_1;
  reg        [31:0]   acc_r_6_2;
  reg        [31:0]   acc_r_6_3;
  reg        [31:0]   acc_r_6_4;
  reg        [31:0]   acc_r_6_5;
  reg        [31:0]   acc_r_6_6;
  reg        [31:0]   acc_r_6_7;
  reg        [31:0]   acc_r_6_8;
  reg        [31:0]   acc_r_6_9;
  reg        [31:0]   acc_r_6_10;
  reg        [31:0]   acc_r_6_11;
  reg        [31:0]   acc_r_6_12;
  reg        [31:0]   acc_r_6_13;
  reg        [31:0]   acc_r_6_14;
  reg        [31:0]   acc_r_6_15;
  reg        [31:0]   acc_r_7_0;
  reg        [31:0]   acc_r_7_1;
  reg        [31:0]   acc_r_7_2;
  reg        [31:0]   acc_r_7_3;
  reg        [31:0]   acc_r_7_4;
  reg        [31:0]   acc_r_7_5;
  reg        [31:0]   acc_r_7_6;
  reg        [31:0]   acc_r_7_7;
  reg        [31:0]   acc_r_7_8;
  reg        [31:0]   acc_r_7_9;
  reg        [31:0]   acc_r_7_10;
  reg        [31:0]   acc_r_7_11;
  reg        [31:0]   acc_r_7_12;
  reg        [31:0]   acc_r_7_13;
  reg        [31:0]   acc_r_7_14;
  reg        [31:0]   acc_r_7_15;
  reg        [31:0]   acc_r_8_0;
  reg        [31:0]   acc_r_8_1;
  reg        [31:0]   acc_r_8_2;
  reg        [31:0]   acc_r_8_3;
  reg        [31:0]   acc_r_8_4;
  reg        [31:0]   acc_r_8_5;
  reg        [31:0]   acc_r_8_6;
  reg        [31:0]   acc_r_8_7;
  reg        [31:0]   acc_r_8_8;
  reg        [31:0]   acc_r_8_9;
  reg        [31:0]   acc_r_8_10;
  reg        [31:0]   acc_r_8_11;
  reg        [31:0]   acc_r_8_12;
  reg        [31:0]   acc_r_8_13;
  reg        [31:0]   acc_r_8_14;
  reg        [31:0]   acc_r_8_15;
  reg        [31:0]   acc_r_9_0;
  reg        [31:0]   acc_r_9_1;
  reg        [31:0]   acc_r_9_2;
  reg        [31:0]   acc_r_9_3;
  reg        [31:0]   acc_r_9_4;
  reg        [31:0]   acc_r_9_5;
  reg        [31:0]   acc_r_9_6;
  reg        [31:0]   acc_r_9_7;
  reg        [31:0]   acc_r_9_8;
  reg        [31:0]   acc_r_9_9;
  reg        [31:0]   acc_r_9_10;
  reg        [31:0]   acc_r_9_11;
  reg        [31:0]   acc_r_9_12;
  reg        [31:0]   acc_r_9_13;
  reg        [31:0]   acc_r_9_14;
  reg        [31:0]   acc_r_9_15;
  reg        [31:0]   acc_r_10_0;
  reg        [31:0]   acc_r_10_1;
  reg        [31:0]   acc_r_10_2;
  reg        [31:0]   acc_r_10_3;
  reg        [31:0]   acc_r_10_4;
  reg        [31:0]   acc_r_10_5;
  reg        [31:0]   acc_r_10_6;
  reg        [31:0]   acc_r_10_7;
  reg        [31:0]   acc_r_10_8;
  reg        [31:0]   acc_r_10_9;
  reg        [31:0]   acc_r_10_10;
  reg        [31:0]   acc_r_10_11;
  reg        [31:0]   acc_r_10_12;
  reg        [31:0]   acc_r_10_13;
  reg        [31:0]   acc_r_10_14;
  reg        [31:0]   acc_r_10_15;
  reg        [31:0]   acc_r_11_0;
  reg        [31:0]   acc_r_11_1;
  reg        [31:0]   acc_r_11_2;
  reg        [31:0]   acc_r_11_3;
  reg        [31:0]   acc_r_11_4;
  reg        [31:0]   acc_r_11_5;
  reg        [31:0]   acc_r_11_6;
  reg        [31:0]   acc_r_11_7;
  reg        [31:0]   acc_r_11_8;
  reg        [31:0]   acc_r_11_9;
  reg        [31:0]   acc_r_11_10;
  reg        [31:0]   acc_r_11_11;
  reg        [31:0]   acc_r_11_12;
  reg        [31:0]   acc_r_11_13;
  reg        [31:0]   acc_r_11_14;
  reg        [31:0]   acc_r_11_15;
  reg        [31:0]   acc_r_12_0;
  reg        [31:0]   acc_r_12_1;
  reg        [31:0]   acc_r_12_2;
  reg        [31:0]   acc_r_12_3;
  reg        [31:0]   acc_r_12_4;
  reg        [31:0]   acc_r_12_5;
  reg        [31:0]   acc_r_12_6;
  reg        [31:0]   acc_r_12_7;
  reg        [31:0]   acc_r_12_8;
  reg        [31:0]   acc_r_12_9;
  reg        [31:0]   acc_r_12_10;
  reg        [31:0]   acc_r_12_11;
  reg        [31:0]   acc_r_12_12;
  reg        [31:0]   acc_r_12_13;
  reg        [31:0]   acc_r_12_14;
  reg        [31:0]   acc_r_12_15;
  reg        [31:0]   acc_r_13_0;
  reg        [31:0]   acc_r_13_1;
  reg        [31:0]   acc_r_13_2;
  reg        [31:0]   acc_r_13_3;
  reg        [31:0]   acc_r_13_4;
  reg        [31:0]   acc_r_13_5;
  reg        [31:0]   acc_r_13_6;
  reg        [31:0]   acc_r_13_7;
  reg        [31:0]   acc_r_13_8;
  reg        [31:0]   acc_r_13_9;
  reg        [31:0]   acc_r_13_10;
  reg        [31:0]   acc_r_13_11;
  reg        [31:0]   acc_r_13_12;
  reg        [31:0]   acc_r_13_13;
  reg        [31:0]   acc_r_13_14;
  reg        [31:0]   acc_r_13_15;
  reg        [31:0]   acc_r_14_0;
  reg        [31:0]   acc_r_14_1;
  reg        [31:0]   acc_r_14_2;
  reg        [31:0]   acc_r_14_3;
  reg        [31:0]   acc_r_14_4;
  reg        [31:0]   acc_r_14_5;
  reg        [31:0]   acc_r_14_6;
  reg        [31:0]   acc_r_14_7;
  reg        [31:0]   acc_r_14_8;
  reg        [31:0]   acc_r_14_9;
  reg        [31:0]   acc_r_14_10;
  reg        [31:0]   acc_r_14_11;
  reg        [31:0]   acc_r_14_12;
  reg        [31:0]   acc_r_14_13;
  reg        [31:0]   acc_r_14_14;
  reg        [31:0]   acc_r_14_15;
  reg        [31:0]   acc_r_15_0;
  reg        [31:0]   acc_r_15_1;
  reg        [31:0]   acc_r_15_2;
  reg        [31:0]   acc_r_15_3;
  reg        [31:0]   acc_r_15_4;
  reg        [31:0]   acc_r_15_5;
  reg        [31:0]   acc_r_15_6;
  reg        [31:0]   acc_r_15_7;
  reg        [31:0]   acc_r_15_8;
  reg        [31:0]   acc_r_15_9;
  reg        [31:0]   acc_r_15_10;
  reg        [31:0]   acc_r_15_11;
  reg        [31:0]   acc_r_15_12;
  reg        [31:0]   acc_r_15_13;
  reg        [31:0]   acc_r_15_14;
  reg        [31:0]   acc_r_15_15;
  reg        [31:0]   tileMac_r_0_0;
  reg        [31:0]   tileMac_r_0_1;
  reg        [31:0]   tileMac_r_0_2;
  reg        [31:0]   tileMac_r_0_3;
  reg        [31:0]   tileMac_r_0_4;
  reg        [31:0]   tileMac_r_0_5;
  reg        [31:0]   tileMac_r_0_6;
  reg        [31:0]   tileMac_r_0_7;
  reg        [31:0]   tileMac_r_0_8;
  reg        [31:0]   tileMac_r_0_9;
  reg        [31:0]   tileMac_r_0_10;
  reg        [31:0]   tileMac_r_0_11;
  reg        [31:0]   tileMac_r_0_12;
  reg        [31:0]   tileMac_r_0_13;
  reg        [31:0]   tileMac_r_0_14;
  reg        [31:0]   tileMac_r_0_15;
  reg        [31:0]   tileMac_r_1_0;
  reg        [31:0]   tileMac_r_1_1;
  reg        [31:0]   tileMac_r_1_2;
  reg        [31:0]   tileMac_r_1_3;
  reg        [31:0]   tileMac_r_1_4;
  reg        [31:0]   tileMac_r_1_5;
  reg        [31:0]   tileMac_r_1_6;
  reg        [31:0]   tileMac_r_1_7;
  reg        [31:0]   tileMac_r_1_8;
  reg        [31:0]   tileMac_r_1_9;
  reg        [31:0]   tileMac_r_1_10;
  reg        [31:0]   tileMac_r_1_11;
  reg        [31:0]   tileMac_r_1_12;
  reg        [31:0]   tileMac_r_1_13;
  reg        [31:0]   tileMac_r_1_14;
  reg        [31:0]   tileMac_r_1_15;
  reg        [31:0]   tileMac_r_2_0;
  reg        [31:0]   tileMac_r_2_1;
  reg        [31:0]   tileMac_r_2_2;
  reg        [31:0]   tileMac_r_2_3;
  reg        [31:0]   tileMac_r_2_4;
  reg        [31:0]   tileMac_r_2_5;
  reg        [31:0]   tileMac_r_2_6;
  reg        [31:0]   tileMac_r_2_7;
  reg        [31:0]   tileMac_r_2_8;
  reg        [31:0]   tileMac_r_2_9;
  reg        [31:0]   tileMac_r_2_10;
  reg        [31:0]   tileMac_r_2_11;
  reg        [31:0]   tileMac_r_2_12;
  reg        [31:0]   tileMac_r_2_13;
  reg        [31:0]   tileMac_r_2_14;
  reg        [31:0]   tileMac_r_2_15;
  reg        [31:0]   tileMac_r_3_0;
  reg        [31:0]   tileMac_r_3_1;
  reg        [31:0]   tileMac_r_3_2;
  reg        [31:0]   tileMac_r_3_3;
  reg        [31:0]   tileMac_r_3_4;
  reg        [31:0]   tileMac_r_3_5;
  reg        [31:0]   tileMac_r_3_6;
  reg        [31:0]   tileMac_r_3_7;
  reg        [31:0]   tileMac_r_3_8;
  reg        [31:0]   tileMac_r_3_9;
  reg        [31:0]   tileMac_r_3_10;
  reg        [31:0]   tileMac_r_3_11;
  reg        [31:0]   tileMac_r_3_12;
  reg        [31:0]   tileMac_r_3_13;
  reg        [31:0]   tileMac_r_3_14;
  reg        [31:0]   tileMac_r_3_15;
  reg        [31:0]   tileMac_r_4_0;
  reg        [31:0]   tileMac_r_4_1;
  reg        [31:0]   tileMac_r_4_2;
  reg        [31:0]   tileMac_r_4_3;
  reg        [31:0]   tileMac_r_4_4;
  reg        [31:0]   tileMac_r_4_5;
  reg        [31:0]   tileMac_r_4_6;
  reg        [31:0]   tileMac_r_4_7;
  reg        [31:0]   tileMac_r_4_8;
  reg        [31:0]   tileMac_r_4_9;
  reg        [31:0]   tileMac_r_4_10;
  reg        [31:0]   tileMac_r_4_11;
  reg        [31:0]   tileMac_r_4_12;
  reg        [31:0]   tileMac_r_4_13;
  reg        [31:0]   tileMac_r_4_14;
  reg        [31:0]   tileMac_r_4_15;
  reg        [31:0]   tileMac_r_5_0;
  reg        [31:0]   tileMac_r_5_1;
  reg        [31:0]   tileMac_r_5_2;
  reg        [31:0]   tileMac_r_5_3;
  reg        [31:0]   tileMac_r_5_4;
  reg        [31:0]   tileMac_r_5_5;
  reg        [31:0]   tileMac_r_5_6;
  reg        [31:0]   tileMac_r_5_7;
  reg        [31:0]   tileMac_r_5_8;
  reg        [31:0]   tileMac_r_5_9;
  reg        [31:0]   tileMac_r_5_10;
  reg        [31:0]   tileMac_r_5_11;
  reg        [31:0]   tileMac_r_5_12;
  reg        [31:0]   tileMac_r_5_13;
  reg        [31:0]   tileMac_r_5_14;
  reg        [31:0]   tileMac_r_5_15;
  reg        [31:0]   tileMac_r_6_0;
  reg        [31:0]   tileMac_r_6_1;
  reg        [31:0]   tileMac_r_6_2;
  reg        [31:0]   tileMac_r_6_3;
  reg        [31:0]   tileMac_r_6_4;
  reg        [31:0]   tileMac_r_6_5;
  reg        [31:0]   tileMac_r_6_6;
  reg        [31:0]   tileMac_r_6_7;
  reg        [31:0]   tileMac_r_6_8;
  reg        [31:0]   tileMac_r_6_9;
  reg        [31:0]   tileMac_r_6_10;
  reg        [31:0]   tileMac_r_6_11;
  reg        [31:0]   tileMac_r_6_12;
  reg        [31:0]   tileMac_r_6_13;
  reg        [31:0]   tileMac_r_6_14;
  reg        [31:0]   tileMac_r_6_15;
  reg        [31:0]   tileMac_r_7_0;
  reg        [31:0]   tileMac_r_7_1;
  reg        [31:0]   tileMac_r_7_2;
  reg        [31:0]   tileMac_r_7_3;
  reg        [31:0]   tileMac_r_7_4;
  reg        [31:0]   tileMac_r_7_5;
  reg        [31:0]   tileMac_r_7_6;
  reg        [31:0]   tileMac_r_7_7;
  reg        [31:0]   tileMac_r_7_8;
  reg        [31:0]   tileMac_r_7_9;
  reg        [31:0]   tileMac_r_7_10;
  reg        [31:0]   tileMac_r_7_11;
  reg        [31:0]   tileMac_r_7_12;
  reg        [31:0]   tileMac_r_7_13;
  reg        [31:0]   tileMac_r_7_14;
  reg        [31:0]   tileMac_r_7_15;
  reg        [31:0]   tileMac_r_8_0;
  reg        [31:0]   tileMac_r_8_1;
  reg        [31:0]   tileMac_r_8_2;
  reg        [31:0]   tileMac_r_8_3;
  reg        [31:0]   tileMac_r_8_4;
  reg        [31:0]   tileMac_r_8_5;
  reg        [31:0]   tileMac_r_8_6;
  reg        [31:0]   tileMac_r_8_7;
  reg        [31:0]   tileMac_r_8_8;
  reg        [31:0]   tileMac_r_8_9;
  reg        [31:0]   tileMac_r_8_10;
  reg        [31:0]   tileMac_r_8_11;
  reg        [31:0]   tileMac_r_8_12;
  reg        [31:0]   tileMac_r_8_13;
  reg        [31:0]   tileMac_r_8_14;
  reg        [31:0]   tileMac_r_8_15;
  reg        [31:0]   tileMac_r_9_0;
  reg        [31:0]   tileMac_r_9_1;
  reg        [31:0]   tileMac_r_9_2;
  reg        [31:0]   tileMac_r_9_3;
  reg        [31:0]   tileMac_r_9_4;
  reg        [31:0]   tileMac_r_9_5;
  reg        [31:0]   tileMac_r_9_6;
  reg        [31:0]   tileMac_r_9_7;
  reg        [31:0]   tileMac_r_9_8;
  reg        [31:0]   tileMac_r_9_9;
  reg        [31:0]   tileMac_r_9_10;
  reg        [31:0]   tileMac_r_9_11;
  reg        [31:0]   tileMac_r_9_12;
  reg        [31:0]   tileMac_r_9_13;
  reg        [31:0]   tileMac_r_9_14;
  reg        [31:0]   tileMac_r_9_15;
  reg        [31:0]   tileMac_r_10_0;
  reg        [31:0]   tileMac_r_10_1;
  reg        [31:0]   tileMac_r_10_2;
  reg        [31:0]   tileMac_r_10_3;
  reg        [31:0]   tileMac_r_10_4;
  reg        [31:0]   tileMac_r_10_5;
  reg        [31:0]   tileMac_r_10_6;
  reg        [31:0]   tileMac_r_10_7;
  reg        [31:0]   tileMac_r_10_8;
  reg        [31:0]   tileMac_r_10_9;
  reg        [31:0]   tileMac_r_10_10;
  reg        [31:0]   tileMac_r_10_11;
  reg        [31:0]   tileMac_r_10_12;
  reg        [31:0]   tileMac_r_10_13;
  reg        [31:0]   tileMac_r_10_14;
  reg        [31:0]   tileMac_r_10_15;
  reg        [31:0]   tileMac_r_11_0;
  reg        [31:0]   tileMac_r_11_1;
  reg        [31:0]   tileMac_r_11_2;
  reg        [31:0]   tileMac_r_11_3;
  reg        [31:0]   tileMac_r_11_4;
  reg        [31:0]   tileMac_r_11_5;
  reg        [31:0]   tileMac_r_11_6;
  reg        [31:0]   tileMac_r_11_7;
  reg        [31:0]   tileMac_r_11_8;
  reg        [31:0]   tileMac_r_11_9;
  reg        [31:0]   tileMac_r_11_10;
  reg        [31:0]   tileMac_r_11_11;
  reg        [31:0]   tileMac_r_11_12;
  reg        [31:0]   tileMac_r_11_13;
  reg        [31:0]   tileMac_r_11_14;
  reg        [31:0]   tileMac_r_11_15;
  reg        [31:0]   tileMac_r_12_0;
  reg        [31:0]   tileMac_r_12_1;
  reg        [31:0]   tileMac_r_12_2;
  reg        [31:0]   tileMac_r_12_3;
  reg        [31:0]   tileMac_r_12_4;
  reg        [31:0]   tileMac_r_12_5;
  reg        [31:0]   tileMac_r_12_6;
  reg        [31:0]   tileMac_r_12_7;
  reg        [31:0]   tileMac_r_12_8;
  reg        [31:0]   tileMac_r_12_9;
  reg        [31:0]   tileMac_r_12_10;
  reg        [31:0]   tileMac_r_12_11;
  reg        [31:0]   tileMac_r_12_12;
  reg        [31:0]   tileMac_r_12_13;
  reg        [31:0]   tileMac_r_12_14;
  reg        [31:0]   tileMac_r_12_15;
  reg        [31:0]   tileMac_r_13_0;
  reg        [31:0]   tileMac_r_13_1;
  reg        [31:0]   tileMac_r_13_2;
  reg        [31:0]   tileMac_r_13_3;
  reg        [31:0]   tileMac_r_13_4;
  reg        [31:0]   tileMac_r_13_5;
  reg        [31:0]   tileMac_r_13_6;
  reg        [31:0]   tileMac_r_13_7;
  reg        [31:0]   tileMac_r_13_8;
  reg        [31:0]   tileMac_r_13_9;
  reg        [31:0]   tileMac_r_13_10;
  reg        [31:0]   tileMac_r_13_11;
  reg        [31:0]   tileMac_r_13_12;
  reg        [31:0]   tileMac_r_13_13;
  reg        [31:0]   tileMac_r_13_14;
  reg        [31:0]   tileMac_r_13_15;
  reg        [31:0]   tileMac_r_14_0;
  reg        [31:0]   tileMac_r_14_1;
  reg        [31:0]   tileMac_r_14_2;
  reg        [31:0]   tileMac_r_14_3;
  reg        [31:0]   tileMac_r_14_4;
  reg        [31:0]   tileMac_r_14_5;
  reg        [31:0]   tileMac_r_14_6;
  reg        [31:0]   tileMac_r_14_7;
  reg        [31:0]   tileMac_r_14_8;
  reg        [31:0]   tileMac_r_14_9;
  reg        [31:0]   tileMac_r_14_10;
  reg        [31:0]   tileMac_r_14_11;
  reg        [31:0]   tileMac_r_14_12;
  reg        [31:0]   tileMac_r_14_13;
  reg        [31:0]   tileMac_r_14_14;
  reg        [31:0]   tileMac_r_14_15;
  reg        [31:0]   tileMac_r_15_0;
  reg        [31:0]   tileMac_r_15_1;
  reg        [31:0]   tileMac_r_15_2;
  reg        [31:0]   tileMac_r_15_3;
  reg        [31:0]   tileMac_r_15_4;
  reg        [31:0]   tileMac_r_15_5;
  reg        [31:0]   tileMac_r_15_6;
  reg        [31:0]   tileMac_r_15_7;
  reg        [31:0]   tileMac_r_15_8;
  reg        [31:0]   tileMac_r_15_9;
  reg        [31:0]   tileMac_r_15_10;
  reg        [31:0]   tileMac_r_15_11;
  reg        [31:0]   tileMac_r_15_12;
  reg        [31:0]   tileMac_r_15_13;
  reg        [31:0]   tileMac_r_15_14;
  reg        [31:0]   tileMac_r_15_15;
  wire       [3:0]    localPixel_w;
  wire                quantRequest_valid;
  reg                 quantRequest_ready;
  wire       [18:0]   quantRequest_payload_tag_pixel;
  wire       [3:0]    quantRequest_payload_tag_localPixel;
  wire       [6:0]    quantRequest_payload_tag_group;
  reg        [3:0]    quantRequest_payload_tag_mask;
  wire                quantRequest_payload_tag_first;
  wire                quantRequest_payload_tag_finalInput;
  wire                quantRequest_payload_tag_tileLast;
  wire                quantRequest_payload_tag_last;
  wire       [31:0]   quantRequest_payload_mac_0;
  wire       [31:0]   quantRequest_payload_mac_1;
  wire       [31:0]   quantRequest_payload_mac_2;
  wire       [31:0]   quantRequest_payload_mac_3;
  wire       [15:0]   _zz_3;
  wire       [31:0]   _zz_acc_r_0_0;
  wire                dot_fire;
  wire       [31:0]   _zz_acc_r_0_0_1;
  wire       [15:0]   _zz_4;
  wire       [31:0]   _zz_tileMac_r_0_0;
  wire       [15:0]   _zz_5;
  wire       [31:0]   _zz_acc_r_1_0;
  wire       [31:0]   _zz_acc_r_1_0_1;
  wire       [15:0]   _zz_6;
  wire       [31:0]   _zz_tileMac_r_1_0;
  wire       [15:0]   _zz_7;
  wire       [31:0]   _zz_acc_r_2_0;
  wire       [31:0]   _zz_acc_r_2_0_1;
  wire       [15:0]   _zz_8;
  wire       [31:0]   _zz_tileMac_r_2_0;
  wire       [15:0]   _zz_9;
  wire       [31:0]   _zz_acc_r_3_0;
  wire       [31:0]   _zz_acc_r_3_0_1;
  wire       [15:0]   _zz_10;
  wire       [31:0]   _zz_tileMac_r_3_0;
  wire       [15:0]   _zz_11;
  wire       [31:0]   _zz_acc_r_4_0;
  wire       [31:0]   _zz_acc_r_4_0_1;
  wire       [15:0]   _zz_12;
  wire       [31:0]   _zz_tileMac_r_4_0;
  wire       [15:0]   _zz_13;
  wire       [31:0]   _zz_acc_r_5_0;
  wire       [31:0]   _zz_acc_r_5_0_1;
  wire       [15:0]   _zz_14;
  wire       [31:0]   _zz_tileMac_r_5_0;
  wire       [15:0]   _zz_15;
  wire       [31:0]   _zz_acc_r_6_0;
  wire       [31:0]   _zz_acc_r_6_0_1;
  wire       [15:0]   _zz_16;
  wire       [31:0]   _zz_tileMac_r_6_0;
  wire       [15:0]   _zz_17;
  wire       [31:0]   _zz_acc_r_7_0;
  wire       [31:0]   _zz_acc_r_7_0_1;
  wire       [15:0]   _zz_18;
  wire       [31:0]   _zz_tileMac_r_7_0;
  wire       [15:0]   _zz_19;
  wire       [31:0]   _zz_acc_r_8_0;
  wire       [31:0]   _zz_acc_r_8_0_1;
  wire       [15:0]   _zz_20;
  wire       [31:0]   _zz_tileMac_r_8_0;
  wire       [15:0]   _zz_21;
  wire       [31:0]   _zz_acc_r_9_0;
  wire       [31:0]   _zz_acc_r_9_0_1;
  wire       [15:0]   _zz_22;
  wire       [31:0]   _zz_tileMac_r_9_0;
  wire       [15:0]   _zz_23;
  wire       [31:0]   _zz_acc_r_10_0;
  wire       [31:0]   _zz_acc_r_10_0_1;
  wire       [15:0]   _zz_24;
  wire       [31:0]   _zz_tileMac_r_10_0;
  wire       [15:0]   _zz_25;
  wire       [31:0]   _zz_acc_r_11_0;
  wire       [31:0]   _zz_acc_r_11_0_1;
  wire       [15:0]   _zz_26;
  wire       [31:0]   _zz_tileMac_r_11_0;
  wire       [15:0]   _zz_27;
  wire       [31:0]   _zz_acc_r_12_0;
  wire       [31:0]   _zz_acc_r_12_0_1;
  wire       [15:0]   _zz_28;
  wire       [31:0]   _zz_tileMac_r_12_0;
  wire       [15:0]   _zz_29;
  wire       [31:0]   _zz_acc_r_13_0;
  wire       [31:0]   _zz_acc_r_13_0_1;
  wire       [15:0]   _zz_30;
  wire       [31:0]   _zz_tileMac_r_13_0;
  wire       [15:0]   _zz_31;
  wire       [31:0]   _zz_acc_r_14_0;
  wire       [31:0]   _zz_acc_r_14_0_1;
  wire       [15:0]   _zz_32;
  wire       [31:0]   _zz_tileMac_r_14_0;
  wire       [15:0]   _zz_33;
  wire       [31:0]   _zz_acc_r_15_0;
  wire       [31:0]   _zz_acc_r_15_0_1;
  wire       [15:0]   _zz_34;
  wire       [31:0]   _zz_tileMac_r_15_0;
  wire                when_PwMac_l419;
  wire       [12:0]   _zz_serialGroupCount_r;
  wire       [3:0]    _zz_quantRequest_payload_mac_0;
  wire       [3:0]    _zz_quantRequest_payload_mac_1;
  wire       [3:0]    _zz_quantRequest_payload_mac_2;
  wire       [3:0]    _zz_quantRequest_payload_mac_3;
  wire                quantRequest_fire;
  wire                when_PwMac_l442;
  wire                when_PwMac_l444;
  wire       [6:0]    _zz_paramData_w;
  wire       [511:0]  paramData_w;
  wire                quantResponse_valid;
  wire                quantResponse_ready;
  wire       [18:0]   quantResponse_payload_tag_pixel;
  wire       [3:0]    quantResponse_payload_tag_localPixel;
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
  reg        [3:0]    quantRequest_rData_tag_localPixel;
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
  wire                when_Stream_l477_7;
  wire       [18:0]   quantInput_w_tag_pixel;
  wire       [3:0]    quantInput_w_tag_localPixel;
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
  wire       [3:0]    quantResponse_translated_payload_tag_localPixel;
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
  wire                io_output_o_fire;
  wire                when_PwMac_l478;
  wire                when_PwMac_l483;
  wire                when_PwMac_l484;
  (* ram_style = "block" *) reg [127:0] inputMem [0:767];
  (* ram_style = "block" *) reg [511:0] paramMemory [0:127];

  assign _zz_cfgIg_w = (io_cfg_i_payload_cin + 10'h00f);
  assign _zz_cfgOg_w = (io_cfg_i_payload_cout + 10'h00f);
  assign _zz_cfgParamGroups_w = (io_cfg_i_payload_cout + 10'h003);
  assign _zz_weightTotal_r = (cfgIg_w * cfgParamGroups_w);
  assign _zz_io_params_i_ready = (_zz_io_params_i_ready_1 >>> 2'd2);
  assign _zz_io_params_i_ready_1 = (run_r_cout + 10'h003);
  assign _zz_when_PwMac_l243 = (igCount_r - 6'h01);
  assign _zz_when_PwMac_l249 = (_zz_when_PwMac_l249_1 >>> 2'd2);
  assign _zz_when_PwMac_l249_1 = (run_r_cout + 10'h003);
  assign _zz_tileCount_r = remaining_r[4:0];
  assign _zz_tileLastPixel_r = (tileBase_r + _zz_tileLastPixel_r_1);
  assign _zz_tileLastPixel_r_1 = {14'd0, tileCount_r};
  assign _zz_fillAddress_w = (_zz_fillAddress_w_1 + _zz_fillAddress_w_2);
  assign _zz_fillAddress_w_1 = (fillGroup_r * 5'h10);
  assign _zz_fillAddress_w_2 = {6'd0, fillPixel_r};
  assign _zz_when_PwMac_l283 = (tileCount_r - 5'h01);
  assign _zz_when_PwMac_l285 = (igCount_r - 6'h01);
  assign _zz_fillGroupBase_r = {13'd0, run_r_pixels};
  assign _zz_fillReadAddr_r = {13'd0, run_r_pixels};
  assign _zz_request_payload_tag_pixel = {14'd0, issuePixel_r};
  assign _zz_request_payload_tag_group = (_zz_request_payload_tag_group_1 * 3'b100);
  assign _zz_request_payload_tag_group_1 = {5'd0, issueGroup_r};
  assign _zz_request_payload_tag_mask = (_zz_request_payload_tag_mask_1 + 15'h0);
  assign _zz_request_payload_tag_mask_1 = (_zz_request_payload_tag_mask_2 * 5'h10);
  assign _zz_request_payload_tag_mask_2 = {5'd0, issueGroup_r};
  assign _zz_request_payload_tag_mask_3 = {5'd0, run_r_cout};
  assign _zz_request_payload_tag_mask_4 = (_zz_request_payload_tag_mask_5 + 15'h0001);
  assign _zz_request_payload_tag_mask_5 = (_zz_request_payload_tag_mask_6 * 5'h10);
  assign _zz_request_payload_tag_mask_6 = {5'd0, issueGroup_r};
  assign _zz_request_payload_tag_mask_7 = {5'd0, run_r_cout};
  assign _zz_request_payload_tag_mask_8 = (_zz_request_payload_tag_mask_9 + 15'h0002);
  assign _zz_request_payload_tag_mask_9 = (_zz_request_payload_tag_mask_10 * 5'h10);
  assign _zz_request_payload_tag_mask_10 = {5'd0, issueGroup_r};
  assign _zz_request_payload_tag_mask_11 = {5'd0, run_r_cout};
  assign _zz_request_payload_tag_mask_12 = (_zz_request_payload_tag_mask_13 + 15'h0003);
  assign _zz_request_payload_tag_mask_13 = (_zz_request_payload_tag_mask_14 * 5'h10);
  assign _zz_request_payload_tag_mask_14 = {5'd0, issueGroup_r};
  assign _zz_request_payload_tag_mask_15 = {5'd0, run_r_cout};
  assign _zz_request_payload_tag_finalInput = (igCount_r - 6'h01);
  assign _zz_request_payload_tag_tileLast = (tileCount_r - 5'h01);
  assign _zz_request_payload_tag_tileLast_1 = (igCount_r - 6'h01);
  assign _zz_request_payload_tag_last = {1'd0, issueGroup_r};
  assign _zz_request_payload_tag_last_1 = (ogCount_r - 6'h01);
  assign _zz_request_payload_tag_last_2 = (tileBase_r + _zz_request_payload_tag_last_3);
  assign _zz_request_payload_tag_last_3 = {14'd0, tileCount_r};
  assign _zz_inputAddress_w = (_zz_inputAddress_w_1 + _zz_inputAddress_w_2);
  assign _zz_inputAddress_w_1 = (issueInput_r * 5'h10);
  assign _zz_inputAddress_w_2 = {6'd0, issuePixel_r};
  assign _zz_weightAddress_w = (issueGroup_r * igCount_r);
  assign _zz_weightAddress_w_1 = {5'd0, issueInput_r};
  assign _zz_addra = (_zz_addra_1 + _zz_addra_2);
  assign _zz_addra_1 = (weightGroup_r[7 : 2] * igCount_r);
  assign _zz_addra_2 = {6'd0, weightInput_r};
  assign _zz_addra_3 = (_zz_addra_4 + _zz_addra_5);
  assign _zz_addra_4 = (weightGroup_r[7 : 2] * igCount_r);
  assign _zz_addra_5 = {6'd0, weightInput_r};
  assign _zz_addra_6 = (_zz_addra_7 + _zz_addra_8);
  assign _zz_addra_7 = (weightGroup_r[7 : 2] * igCount_r);
  assign _zz_addra_8 = {6'd0, weightInput_r};
  assign _zz_addra_9 = (_zz_addra_10 + _zz_addra_11);
  assign _zz_addra_10 = (weightGroup_r[7 : 2] * igCount_r);
  assign _zz_addra_11 = {6'd0, weightInput_r};
  assign _zz_when_PwMac_l345 = (tileCount_r - 5'h01);
  assign _zz_when_PwMac_l347 = (igCount_r - 6'h01);
  assign _zz_operands_w_mask = (_zz_operands_w_mask_1 + 15'h0);
  assign _zz_operands_w_mask_1 = (_zz_operands_w_mask_2 * 5'h10);
  assign _zz_operands_w_mask_2 = {4'd0, response_payload_inputGroup};
  assign _zz_operands_w_mask_3 = {5'd0, run_r_cin};
  assign _zz_operands_w_mask_4 = (_zz_operands_w_mask_5 + 15'h0001);
  assign _zz_operands_w_mask_5 = (_zz_operands_w_mask_6 * 5'h10);
  assign _zz_operands_w_mask_6 = {4'd0, response_payload_inputGroup};
  assign _zz_operands_w_mask_7 = {5'd0, run_r_cin};
  assign _zz_operands_w_mask_8 = (_zz_operands_w_mask_9 + 15'h0002);
  assign _zz_operands_w_mask_9 = (_zz_operands_w_mask_10 * 5'h10);
  assign _zz_operands_w_mask_10 = {4'd0, response_payload_inputGroup};
  assign _zz_operands_w_mask_11 = {5'd0, run_r_cin};
  assign _zz_operands_w_mask_12 = (_zz_operands_w_mask_13 + 15'h0003);
  assign _zz_operands_w_mask_13 = (_zz_operands_w_mask_14 * 5'h10);
  assign _zz_operands_w_mask_14 = {4'd0, response_payload_inputGroup};
  assign _zz_operands_w_mask_15 = {5'd0, run_r_cin};
  assign _zz_operands_w_mask_16 = (_zz_operands_w_mask_17 + 15'h0004);
  assign _zz_operands_w_mask_17 = (_zz_operands_w_mask_18 * 5'h10);
  assign _zz_operands_w_mask_18 = {4'd0, response_payload_inputGroup};
  assign _zz_operands_w_mask_19 = {5'd0, run_r_cin};
  assign _zz_operands_w_mask_20 = (_zz_operands_w_mask_21 + 15'h0005);
  assign _zz_operands_w_mask_21 = (_zz_operands_w_mask_22 * 5'h10);
  assign _zz_operands_w_mask_22 = {4'd0, response_payload_inputGroup};
  assign _zz_operands_w_mask_23 = {5'd0, run_r_cin};
  assign _zz_operands_w_mask_24 = (_zz_operands_w_mask_25 + 15'h0006);
  assign _zz_operands_w_mask_25 = (_zz_operands_w_mask_26 * 5'h10);
  assign _zz_operands_w_mask_26 = {4'd0, response_payload_inputGroup};
  assign _zz_operands_w_mask_27 = {5'd0, run_r_cin};
  assign _zz_operands_w_mask_28 = (_zz_operands_w_mask_29 + 15'h0007);
  assign _zz_operands_w_mask_29 = (_zz_operands_w_mask_30 * 5'h10);
  assign _zz_operands_w_mask_30 = {4'd0, response_payload_inputGroup};
  assign _zz_operands_w_mask_31 = {5'd0, run_r_cin};
  assign _zz_operands_w_mask_32 = (_zz_operands_w_mask_33 + 15'h0008);
  assign _zz_operands_w_mask_33 = (_zz_operands_w_mask_34 * 5'h10);
  assign _zz_operands_w_mask_34 = {4'd0, response_payload_inputGroup};
  assign _zz_operands_w_mask_35 = {5'd0, run_r_cin};
  assign _zz_operands_w_mask_36 = (_zz_operands_w_mask_37 + 15'h0009);
  assign _zz_operands_w_mask_37 = (_zz_operands_w_mask_38 * 5'h10);
  assign _zz_operands_w_mask_38 = {4'd0, response_payload_inputGroup};
  assign _zz_operands_w_mask_39 = {5'd0, run_r_cin};
  assign _zz_operands_w_mask_40 = (_zz_operands_w_mask_41 + 15'h000a);
  assign _zz_operands_w_mask_41 = (_zz_operands_w_mask_42 * 5'h10);
  assign _zz_operands_w_mask_42 = {4'd0, response_payload_inputGroup};
  assign _zz_operands_w_mask_43 = {5'd0, run_r_cin};
  assign _zz_operands_w_mask_44 = (_zz_operands_w_mask_45 + 15'h000b);
  assign _zz_operands_w_mask_45 = (_zz_operands_w_mask_46 * 5'h10);
  assign _zz_operands_w_mask_46 = {4'd0, response_payload_inputGroup};
  assign _zz_operands_w_mask_47 = {5'd0, run_r_cin};
  assign _zz_operands_w_mask_48 = (_zz_operands_w_mask_49 + 15'h000c);
  assign _zz_operands_w_mask_49 = (_zz_operands_w_mask_50 * 5'h10);
  assign _zz_operands_w_mask_50 = {4'd0, response_payload_inputGroup};
  assign _zz_operands_w_mask_51 = {5'd0, run_r_cin};
  assign _zz_operands_w_mask_52 = (_zz_operands_w_mask_53 + 15'h000d);
  assign _zz_operands_w_mask_53 = (_zz_operands_w_mask_54 * 5'h10);
  assign _zz_operands_w_mask_54 = {4'd0, response_payload_inputGroup};
  assign _zz_operands_w_mask_55 = {5'd0, run_r_cin};
  assign _zz_operands_w_mask_56 = (_zz_operands_w_mask_57 + 15'h000e);
  assign _zz_operands_w_mask_57 = (_zz_operands_w_mask_58 * 5'h10);
  assign _zz_operands_w_mask_58 = {4'd0, response_payload_inputGroup};
  assign _zz_operands_w_mask_59 = {5'd0, run_r_cin};
  assign _zz_operands_w_mask_60 = (_zz_operands_w_mask_61 + 15'h000f);
  assign _zz_operands_w_mask_61 = (_zz_operands_w_mask_62 * 5'h10);
  assign _zz_operands_w_mask_62 = {4'd0, response_payload_inputGroup};
  assign _zz_operands_w_mask_63 = {5'd0, run_r_cin};
  assign _zz_products_w_values_0_0 = (operands_payload_mask[0] ? _zz_products_w_values_0_0_1 : 8'h0);
  assign _zz_products_w_values_0_0_1 = operands_payload_input[7 : 0];
  assign _zz_products_w_values_0_0_2 = operands_payload_weights_0[7 : 0];
  assign _zz_products_w_values_0_1 = (operands_payload_mask[1] ? _zz_products_w_values_0_1_1 : 8'h0);
  assign _zz_products_w_values_0_1_1 = operands_payload_input[15 : 8];
  assign _zz_products_w_values_0_1_2 = operands_payload_weights_0[15 : 8];
  assign _zz_products_w_values_0_2 = (operands_payload_mask[2] ? _zz_products_w_values_0_2_1 : 8'h0);
  assign _zz_products_w_values_0_2_1 = operands_payload_input[23 : 16];
  assign _zz_products_w_values_0_2_2 = operands_payload_weights_0[23 : 16];
  assign _zz_products_w_values_0_3 = (operands_payload_mask[3] ? _zz_products_w_values_0_3_1 : 8'h0);
  assign _zz_products_w_values_0_3_1 = operands_payload_input[31 : 24];
  assign _zz_products_w_values_0_3_2 = operands_payload_weights_0[31 : 24];
  assign _zz_products_w_values_0_4 = (operands_payload_mask[4] ? _zz_products_w_values_0_4_1 : 8'h0);
  assign _zz_products_w_values_0_4_1 = operands_payload_input[39 : 32];
  assign _zz_products_w_values_0_4_2 = operands_payload_weights_0[39 : 32];
  assign _zz_products_w_values_0_5 = (operands_payload_mask[5] ? _zz_products_w_values_0_5_1 : 8'h0);
  assign _zz_products_w_values_0_5_1 = operands_payload_input[47 : 40];
  assign _zz_products_w_values_0_5_2 = operands_payload_weights_0[47 : 40];
  assign _zz_products_w_values_0_6 = (operands_payload_mask[6] ? _zz_products_w_values_0_6_1 : 8'h0);
  assign _zz_products_w_values_0_6_1 = operands_payload_input[55 : 48];
  assign _zz_products_w_values_0_6_2 = operands_payload_weights_0[55 : 48];
  assign _zz_products_w_values_0_7 = (operands_payload_mask[7] ? _zz_products_w_values_0_7_1 : 8'h0);
  assign _zz_products_w_values_0_7_1 = operands_payload_input[63 : 56];
  assign _zz_products_w_values_0_7_2 = operands_payload_weights_0[63 : 56];
  assign _zz_products_w_values_0_8 = (operands_payload_mask[8] ? _zz_products_w_values_0_8_1 : 8'h0);
  assign _zz_products_w_values_0_8_1 = operands_payload_input[71 : 64];
  assign _zz_products_w_values_0_8_2 = operands_payload_weights_0[71 : 64];
  assign _zz_products_w_values_0_9 = (operands_payload_mask[9] ? _zz_products_w_values_0_9_1 : 8'h0);
  assign _zz_products_w_values_0_9_1 = operands_payload_input[79 : 72];
  assign _zz_products_w_values_0_9_2 = operands_payload_weights_0[79 : 72];
  assign _zz_products_w_values_0_10 = (operands_payload_mask[10] ? _zz_products_w_values_0_10_1 : 8'h0);
  assign _zz_products_w_values_0_10_1 = operands_payload_input[87 : 80];
  assign _zz_products_w_values_0_10_2 = operands_payload_weights_0[87 : 80];
  assign _zz_products_w_values_0_11 = (operands_payload_mask[11] ? _zz_products_w_values_0_11_1 : 8'h0);
  assign _zz_products_w_values_0_11_1 = operands_payload_input[95 : 88];
  assign _zz_products_w_values_0_11_2 = operands_payload_weights_0[95 : 88];
  assign _zz_products_w_values_0_12 = (operands_payload_mask[12] ? _zz_products_w_values_0_12_1 : 8'h0);
  assign _zz_products_w_values_0_12_1 = operands_payload_input[103 : 96];
  assign _zz_products_w_values_0_12_2 = operands_payload_weights_0[103 : 96];
  assign _zz_products_w_values_0_13 = (operands_payload_mask[13] ? _zz_products_w_values_0_13_1 : 8'h0);
  assign _zz_products_w_values_0_13_1 = operands_payload_input[111 : 104];
  assign _zz_products_w_values_0_13_2 = operands_payload_weights_0[111 : 104];
  assign _zz_products_w_values_0_14 = (operands_payload_mask[14] ? _zz_products_w_values_0_14_1 : 8'h0);
  assign _zz_products_w_values_0_14_1 = operands_payload_input[119 : 112];
  assign _zz_products_w_values_0_14_2 = operands_payload_weights_0[119 : 112];
  assign _zz_products_w_values_0_15 = (operands_payload_mask[15] ? _zz_products_w_values_0_15_1 : 8'h0);
  assign _zz_products_w_values_0_15_1 = operands_payload_input[127 : 120];
  assign _zz_products_w_values_0_15_2 = operands_payload_weights_0[127 : 120];
  assign _zz_products_w_values_1_0 = (operands_payload_mask[0] ? _zz_products_w_values_1_0_1 : 8'h0);
  assign _zz_products_w_values_1_0_1 = operands_payload_input[7 : 0];
  assign _zz_products_w_values_1_0_2 = operands_payload_weights_1[7 : 0];
  assign _zz_products_w_values_1_1 = (operands_payload_mask[1] ? _zz_products_w_values_1_1_1 : 8'h0);
  assign _zz_products_w_values_1_1_1 = operands_payload_input[15 : 8];
  assign _zz_products_w_values_1_1_2 = operands_payload_weights_1[15 : 8];
  assign _zz_products_w_values_1_2 = (operands_payload_mask[2] ? _zz_products_w_values_1_2_1 : 8'h0);
  assign _zz_products_w_values_1_2_1 = operands_payload_input[23 : 16];
  assign _zz_products_w_values_1_2_2 = operands_payload_weights_1[23 : 16];
  assign _zz_products_w_values_1_3 = (operands_payload_mask[3] ? _zz_products_w_values_1_3_1 : 8'h0);
  assign _zz_products_w_values_1_3_1 = operands_payload_input[31 : 24];
  assign _zz_products_w_values_1_3_2 = operands_payload_weights_1[31 : 24];
  assign _zz_products_w_values_1_4 = (operands_payload_mask[4] ? _zz_products_w_values_1_4_1 : 8'h0);
  assign _zz_products_w_values_1_4_1 = operands_payload_input[39 : 32];
  assign _zz_products_w_values_1_4_2 = operands_payload_weights_1[39 : 32];
  assign _zz_products_w_values_1_5 = (operands_payload_mask[5] ? _zz_products_w_values_1_5_1 : 8'h0);
  assign _zz_products_w_values_1_5_1 = operands_payload_input[47 : 40];
  assign _zz_products_w_values_1_5_2 = operands_payload_weights_1[47 : 40];
  assign _zz_products_w_values_1_6 = (operands_payload_mask[6] ? _zz_products_w_values_1_6_1 : 8'h0);
  assign _zz_products_w_values_1_6_1 = operands_payload_input[55 : 48];
  assign _zz_products_w_values_1_6_2 = operands_payload_weights_1[55 : 48];
  assign _zz_products_w_values_1_7 = (operands_payload_mask[7] ? _zz_products_w_values_1_7_1 : 8'h0);
  assign _zz_products_w_values_1_7_1 = operands_payload_input[63 : 56];
  assign _zz_products_w_values_1_7_2 = operands_payload_weights_1[63 : 56];
  assign _zz_products_w_values_1_8 = (operands_payload_mask[8] ? _zz_products_w_values_1_8_1 : 8'h0);
  assign _zz_products_w_values_1_8_1 = operands_payload_input[71 : 64];
  assign _zz_products_w_values_1_8_2 = operands_payload_weights_1[71 : 64];
  assign _zz_products_w_values_1_9 = (operands_payload_mask[9] ? _zz_products_w_values_1_9_1 : 8'h0);
  assign _zz_products_w_values_1_9_1 = operands_payload_input[79 : 72];
  assign _zz_products_w_values_1_9_2 = operands_payload_weights_1[79 : 72];
  assign _zz_products_w_values_1_10 = (operands_payload_mask[10] ? _zz_products_w_values_1_10_1 : 8'h0);
  assign _zz_products_w_values_1_10_1 = operands_payload_input[87 : 80];
  assign _zz_products_w_values_1_10_2 = operands_payload_weights_1[87 : 80];
  assign _zz_products_w_values_1_11 = (operands_payload_mask[11] ? _zz_products_w_values_1_11_1 : 8'h0);
  assign _zz_products_w_values_1_11_1 = operands_payload_input[95 : 88];
  assign _zz_products_w_values_1_11_2 = operands_payload_weights_1[95 : 88];
  assign _zz_products_w_values_1_12 = (operands_payload_mask[12] ? _zz_products_w_values_1_12_1 : 8'h0);
  assign _zz_products_w_values_1_12_1 = operands_payload_input[103 : 96];
  assign _zz_products_w_values_1_12_2 = operands_payload_weights_1[103 : 96];
  assign _zz_products_w_values_1_13 = (operands_payload_mask[13] ? _zz_products_w_values_1_13_1 : 8'h0);
  assign _zz_products_w_values_1_13_1 = operands_payload_input[111 : 104];
  assign _zz_products_w_values_1_13_2 = operands_payload_weights_1[111 : 104];
  assign _zz_products_w_values_1_14 = (operands_payload_mask[14] ? _zz_products_w_values_1_14_1 : 8'h0);
  assign _zz_products_w_values_1_14_1 = operands_payload_input[119 : 112];
  assign _zz_products_w_values_1_14_2 = operands_payload_weights_1[119 : 112];
  assign _zz_products_w_values_1_15 = (operands_payload_mask[15] ? _zz_products_w_values_1_15_1 : 8'h0);
  assign _zz_products_w_values_1_15_1 = operands_payload_input[127 : 120];
  assign _zz_products_w_values_1_15_2 = operands_payload_weights_1[127 : 120];
  assign _zz_products_w_values_2_0 = (operands_payload_mask[0] ? _zz_products_w_values_2_0_1 : 8'h0);
  assign _zz_products_w_values_2_0_1 = operands_payload_input[7 : 0];
  assign _zz_products_w_values_2_0_2 = operands_payload_weights_2[7 : 0];
  assign _zz_products_w_values_2_1 = (operands_payload_mask[1] ? _zz_products_w_values_2_1_1 : 8'h0);
  assign _zz_products_w_values_2_1_1 = operands_payload_input[15 : 8];
  assign _zz_products_w_values_2_1_2 = operands_payload_weights_2[15 : 8];
  assign _zz_products_w_values_2_2 = (operands_payload_mask[2] ? _zz_products_w_values_2_2_1 : 8'h0);
  assign _zz_products_w_values_2_2_1 = operands_payload_input[23 : 16];
  assign _zz_products_w_values_2_2_2 = operands_payload_weights_2[23 : 16];
  assign _zz_products_w_values_2_3 = (operands_payload_mask[3] ? _zz_products_w_values_2_3_1 : 8'h0);
  assign _zz_products_w_values_2_3_1 = operands_payload_input[31 : 24];
  assign _zz_products_w_values_2_3_2 = operands_payload_weights_2[31 : 24];
  assign _zz_products_w_values_2_4 = (operands_payload_mask[4] ? _zz_products_w_values_2_4_1 : 8'h0);
  assign _zz_products_w_values_2_4_1 = operands_payload_input[39 : 32];
  assign _zz_products_w_values_2_4_2 = operands_payload_weights_2[39 : 32];
  assign _zz_products_w_values_2_5 = (operands_payload_mask[5] ? _zz_products_w_values_2_5_1 : 8'h0);
  assign _zz_products_w_values_2_5_1 = operands_payload_input[47 : 40];
  assign _zz_products_w_values_2_5_2 = operands_payload_weights_2[47 : 40];
  assign _zz_products_w_values_2_6 = (operands_payload_mask[6] ? _zz_products_w_values_2_6_1 : 8'h0);
  assign _zz_products_w_values_2_6_1 = operands_payload_input[55 : 48];
  assign _zz_products_w_values_2_6_2 = operands_payload_weights_2[55 : 48];
  assign _zz_products_w_values_2_7 = (operands_payload_mask[7] ? _zz_products_w_values_2_7_1 : 8'h0);
  assign _zz_products_w_values_2_7_1 = operands_payload_input[63 : 56];
  assign _zz_products_w_values_2_7_2 = operands_payload_weights_2[63 : 56];
  assign _zz_products_w_values_2_8 = (operands_payload_mask[8] ? _zz_products_w_values_2_8_1 : 8'h0);
  assign _zz_products_w_values_2_8_1 = operands_payload_input[71 : 64];
  assign _zz_products_w_values_2_8_2 = operands_payload_weights_2[71 : 64];
  assign _zz_products_w_values_2_9 = (operands_payload_mask[9] ? _zz_products_w_values_2_9_1 : 8'h0);
  assign _zz_products_w_values_2_9_1 = operands_payload_input[79 : 72];
  assign _zz_products_w_values_2_9_2 = operands_payload_weights_2[79 : 72];
  assign _zz_products_w_values_2_10 = (operands_payload_mask[10] ? _zz_products_w_values_2_10_1 : 8'h0);
  assign _zz_products_w_values_2_10_1 = operands_payload_input[87 : 80];
  assign _zz_products_w_values_2_10_2 = operands_payload_weights_2[87 : 80];
  assign _zz_products_w_values_2_11 = (operands_payload_mask[11] ? _zz_products_w_values_2_11_1 : 8'h0);
  assign _zz_products_w_values_2_11_1 = operands_payload_input[95 : 88];
  assign _zz_products_w_values_2_11_2 = operands_payload_weights_2[95 : 88];
  assign _zz_products_w_values_2_12 = (operands_payload_mask[12] ? _zz_products_w_values_2_12_1 : 8'h0);
  assign _zz_products_w_values_2_12_1 = operands_payload_input[103 : 96];
  assign _zz_products_w_values_2_12_2 = operands_payload_weights_2[103 : 96];
  assign _zz_products_w_values_2_13 = (operands_payload_mask[13] ? _zz_products_w_values_2_13_1 : 8'h0);
  assign _zz_products_w_values_2_13_1 = operands_payload_input[111 : 104];
  assign _zz_products_w_values_2_13_2 = operands_payload_weights_2[111 : 104];
  assign _zz_products_w_values_2_14 = (operands_payload_mask[14] ? _zz_products_w_values_2_14_1 : 8'h0);
  assign _zz_products_w_values_2_14_1 = operands_payload_input[119 : 112];
  assign _zz_products_w_values_2_14_2 = operands_payload_weights_2[119 : 112];
  assign _zz_products_w_values_2_15 = (operands_payload_mask[15] ? _zz_products_w_values_2_15_1 : 8'h0);
  assign _zz_products_w_values_2_15_1 = operands_payload_input[127 : 120];
  assign _zz_products_w_values_2_15_2 = operands_payload_weights_2[127 : 120];
  assign _zz_products_w_values_3_0 = (operands_payload_mask[0] ? _zz_products_w_values_3_0_1 : 8'h0);
  assign _zz_products_w_values_3_0_1 = operands_payload_input[7 : 0];
  assign _zz_products_w_values_3_0_2 = operands_payload_weights_3[7 : 0];
  assign _zz_products_w_values_3_1 = (operands_payload_mask[1] ? _zz_products_w_values_3_1_1 : 8'h0);
  assign _zz_products_w_values_3_1_1 = operands_payload_input[15 : 8];
  assign _zz_products_w_values_3_1_2 = operands_payload_weights_3[15 : 8];
  assign _zz_products_w_values_3_2 = (operands_payload_mask[2] ? _zz_products_w_values_3_2_1 : 8'h0);
  assign _zz_products_w_values_3_2_1 = operands_payload_input[23 : 16];
  assign _zz_products_w_values_3_2_2 = operands_payload_weights_3[23 : 16];
  assign _zz_products_w_values_3_3 = (operands_payload_mask[3] ? _zz_products_w_values_3_3_1 : 8'h0);
  assign _zz_products_w_values_3_3_1 = operands_payload_input[31 : 24];
  assign _zz_products_w_values_3_3_2 = operands_payload_weights_3[31 : 24];
  assign _zz_products_w_values_3_4 = (operands_payload_mask[4] ? _zz_products_w_values_3_4_1 : 8'h0);
  assign _zz_products_w_values_3_4_1 = operands_payload_input[39 : 32];
  assign _zz_products_w_values_3_4_2 = operands_payload_weights_3[39 : 32];
  assign _zz_products_w_values_3_5 = (operands_payload_mask[5] ? _zz_products_w_values_3_5_1 : 8'h0);
  assign _zz_products_w_values_3_5_1 = operands_payload_input[47 : 40];
  assign _zz_products_w_values_3_5_2 = operands_payload_weights_3[47 : 40];
  assign _zz_products_w_values_3_6 = (operands_payload_mask[6] ? _zz_products_w_values_3_6_1 : 8'h0);
  assign _zz_products_w_values_3_6_1 = operands_payload_input[55 : 48];
  assign _zz_products_w_values_3_6_2 = operands_payload_weights_3[55 : 48];
  assign _zz_products_w_values_3_7 = (operands_payload_mask[7] ? _zz_products_w_values_3_7_1 : 8'h0);
  assign _zz_products_w_values_3_7_1 = operands_payload_input[63 : 56];
  assign _zz_products_w_values_3_7_2 = operands_payload_weights_3[63 : 56];
  assign _zz_products_w_values_3_8 = (operands_payload_mask[8] ? _zz_products_w_values_3_8_1 : 8'h0);
  assign _zz_products_w_values_3_8_1 = operands_payload_input[71 : 64];
  assign _zz_products_w_values_3_8_2 = operands_payload_weights_3[71 : 64];
  assign _zz_products_w_values_3_9 = (operands_payload_mask[9] ? _zz_products_w_values_3_9_1 : 8'h0);
  assign _zz_products_w_values_3_9_1 = operands_payload_input[79 : 72];
  assign _zz_products_w_values_3_9_2 = operands_payload_weights_3[79 : 72];
  assign _zz_products_w_values_3_10 = (operands_payload_mask[10] ? _zz_products_w_values_3_10_1 : 8'h0);
  assign _zz_products_w_values_3_10_1 = operands_payload_input[87 : 80];
  assign _zz_products_w_values_3_10_2 = operands_payload_weights_3[87 : 80];
  assign _zz_products_w_values_3_11 = (operands_payload_mask[11] ? _zz_products_w_values_3_11_1 : 8'h0);
  assign _zz_products_w_values_3_11_1 = operands_payload_input[95 : 88];
  assign _zz_products_w_values_3_11_2 = operands_payload_weights_3[95 : 88];
  assign _zz_products_w_values_3_12 = (operands_payload_mask[12] ? _zz_products_w_values_3_12_1 : 8'h0);
  assign _zz_products_w_values_3_12_1 = operands_payload_input[103 : 96];
  assign _zz_products_w_values_3_12_2 = operands_payload_weights_3[103 : 96];
  assign _zz_products_w_values_3_13 = (operands_payload_mask[13] ? _zz_products_w_values_3_13_1 : 8'h0);
  assign _zz_products_w_values_3_13_1 = operands_payload_input[111 : 104];
  assign _zz_products_w_values_3_13_2 = operands_payload_weights_3[111 : 104];
  assign _zz_products_w_values_3_14 = (operands_payload_mask[14] ? _zz_products_w_values_3_14_1 : 8'h0);
  assign _zz_products_w_values_3_14_1 = operands_payload_input[119 : 112];
  assign _zz_products_w_values_3_14_2 = operands_payload_weights_3[119 : 112];
  assign _zz_products_w_values_3_15 = (operands_payload_mask[15] ? _zz_products_w_values_3_15_1 : 8'h0);
  assign _zz_products_w_values_3_15_1 = operands_payload_input[127 : 120];
  assign _zz_products_w_values_3_15_2 = operands_payload_weights_3[127 : 120];
  assign _zz_products_w_values_4_0 = (operands_payload_mask[0] ? _zz_products_w_values_4_0_1 : 8'h0);
  assign _zz_products_w_values_4_0_1 = operands_payload_input[7 : 0];
  assign _zz_products_w_values_4_0_2 = operands_payload_weights_4[7 : 0];
  assign _zz_products_w_values_4_1 = (operands_payload_mask[1] ? _zz_products_w_values_4_1_1 : 8'h0);
  assign _zz_products_w_values_4_1_1 = operands_payload_input[15 : 8];
  assign _zz_products_w_values_4_1_2 = operands_payload_weights_4[15 : 8];
  assign _zz_products_w_values_4_2 = (operands_payload_mask[2] ? _zz_products_w_values_4_2_1 : 8'h0);
  assign _zz_products_w_values_4_2_1 = operands_payload_input[23 : 16];
  assign _zz_products_w_values_4_2_2 = operands_payload_weights_4[23 : 16];
  assign _zz_products_w_values_4_3 = (operands_payload_mask[3] ? _zz_products_w_values_4_3_1 : 8'h0);
  assign _zz_products_w_values_4_3_1 = operands_payload_input[31 : 24];
  assign _zz_products_w_values_4_3_2 = operands_payload_weights_4[31 : 24];
  assign _zz_products_w_values_4_4 = (operands_payload_mask[4] ? _zz_products_w_values_4_4_1 : 8'h0);
  assign _zz_products_w_values_4_4_1 = operands_payload_input[39 : 32];
  assign _zz_products_w_values_4_4_2 = operands_payload_weights_4[39 : 32];
  assign _zz_products_w_values_4_5 = (operands_payload_mask[5] ? _zz_products_w_values_4_5_1 : 8'h0);
  assign _zz_products_w_values_4_5_1 = operands_payload_input[47 : 40];
  assign _zz_products_w_values_4_5_2 = operands_payload_weights_4[47 : 40];
  assign _zz_products_w_values_4_6 = (operands_payload_mask[6] ? _zz_products_w_values_4_6_1 : 8'h0);
  assign _zz_products_w_values_4_6_1 = operands_payload_input[55 : 48];
  assign _zz_products_w_values_4_6_2 = operands_payload_weights_4[55 : 48];
  assign _zz_products_w_values_4_7 = (operands_payload_mask[7] ? _zz_products_w_values_4_7_1 : 8'h0);
  assign _zz_products_w_values_4_7_1 = operands_payload_input[63 : 56];
  assign _zz_products_w_values_4_7_2 = operands_payload_weights_4[63 : 56];
  assign _zz_products_w_values_4_8 = (operands_payload_mask[8] ? _zz_products_w_values_4_8_1 : 8'h0);
  assign _zz_products_w_values_4_8_1 = operands_payload_input[71 : 64];
  assign _zz_products_w_values_4_8_2 = operands_payload_weights_4[71 : 64];
  assign _zz_products_w_values_4_9 = (operands_payload_mask[9] ? _zz_products_w_values_4_9_1 : 8'h0);
  assign _zz_products_w_values_4_9_1 = operands_payload_input[79 : 72];
  assign _zz_products_w_values_4_9_2 = operands_payload_weights_4[79 : 72];
  assign _zz_products_w_values_4_10 = (operands_payload_mask[10] ? _zz_products_w_values_4_10_1 : 8'h0);
  assign _zz_products_w_values_4_10_1 = operands_payload_input[87 : 80];
  assign _zz_products_w_values_4_10_2 = operands_payload_weights_4[87 : 80];
  assign _zz_products_w_values_4_11 = (operands_payload_mask[11] ? _zz_products_w_values_4_11_1 : 8'h0);
  assign _zz_products_w_values_4_11_1 = operands_payload_input[95 : 88];
  assign _zz_products_w_values_4_11_2 = operands_payload_weights_4[95 : 88];
  assign _zz_products_w_values_4_12 = (operands_payload_mask[12] ? _zz_products_w_values_4_12_1 : 8'h0);
  assign _zz_products_w_values_4_12_1 = operands_payload_input[103 : 96];
  assign _zz_products_w_values_4_12_2 = operands_payload_weights_4[103 : 96];
  assign _zz_products_w_values_4_13 = (operands_payload_mask[13] ? _zz_products_w_values_4_13_1 : 8'h0);
  assign _zz_products_w_values_4_13_1 = operands_payload_input[111 : 104];
  assign _zz_products_w_values_4_13_2 = operands_payload_weights_4[111 : 104];
  assign _zz_products_w_values_4_14 = (operands_payload_mask[14] ? _zz_products_w_values_4_14_1 : 8'h0);
  assign _zz_products_w_values_4_14_1 = operands_payload_input[119 : 112];
  assign _zz_products_w_values_4_14_2 = operands_payload_weights_4[119 : 112];
  assign _zz_products_w_values_4_15 = (operands_payload_mask[15] ? _zz_products_w_values_4_15_1 : 8'h0);
  assign _zz_products_w_values_4_15_1 = operands_payload_input[127 : 120];
  assign _zz_products_w_values_4_15_2 = operands_payload_weights_4[127 : 120];
  assign _zz_products_w_values_5_0 = (operands_payload_mask[0] ? _zz_products_w_values_5_0_1 : 8'h0);
  assign _zz_products_w_values_5_0_1 = operands_payload_input[7 : 0];
  assign _zz_products_w_values_5_0_2 = operands_payload_weights_5[7 : 0];
  assign _zz_products_w_values_5_1 = (operands_payload_mask[1] ? _zz_products_w_values_5_1_1 : 8'h0);
  assign _zz_products_w_values_5_1_1 = operands_payload_input[15 : 8];
  assign _zz_products_w_values_5_1_2 = operands_payload_weights_5[15 : 8];
  assign _zz_products_w_values_5_2 = (operands_payload_mask[2] ? _zz_products_w_values_5_2_1 : 8'h0);
  assign _zz_products_w_values_5_2_1 = operands_payload_input[23 : 16];
  assign _zz_products_w_values_5_2_2 = operands_payload_weights_5[23 : 16];
  assign _zz_products_w_values_5_3 = (operands_payload_mask[3] ? _zz_products_w_values_5_3_1 : 8'h0);
  assign _zz_products_w_values_5_3_1 = operands_payload_input[31 : 24];
  assign _zz_products_w_values_5_3_2 = operands_payload_weights_5[31 : 24];
  assign _zz_products_w_values_5_4 = (operands_payload_mask[4] ? _zz_products_w_values_5_4_1 : 8'h0);
  assign _zz_products_w_values_5_4_1 = operands_payload_input[39 : 32];
  assign _zz_products_w_values_5_4_2 = operands_payload_weights_5[39 : 32];
  assign _zz_products_w_values_5_5 = (operands_payload_mask[5] ? _zz_products_w_values_5_5_1 : 8'h0);
  assign _zz_products_w_values_5_5_1 = operands_payload_input[47 : 40];
  assign _zz_products_w_values_5_5_2 = operands_payload_weights_5[47 : 40];
  assign _zz_products_w_values_5_6 = (operands_payload_mask[6] ? _zz_products_w_values_5_6_1 : 8'h0);
  assign _zz_products_w_values_5_6_1 = operands_payload_input[55 : 48];
  assign _zz_products_w_values_5_6_2 = operands_payload_weights_5[55 : 48];
  assign _zz_products_w_values_5_7 = (operands_payload_mask[7] ? _zz_products_w_values_5_7_1 : 8'h0);
  assign _zz_products_w_values_5_7_1 = operands_payload_input[63 : 56];
  assign _zz_products_w_values_5_7_2 = operands_payload_weights_5[63 : 56];
  assign _zz_products_w_values_5_8 = (operands_payload_mask[8] ? _zz_products_w_values_5_8_1 : 8'h0);
  assign _zz_products_w_values_5_8_1 = operands_payload_input[71 : 64];
  assign _zz_products_w_values_5_8_2 = operands_payload_weights_5[71 : 64];
  assign _zz_products_w_values_5_9 = (operands_payload_mask[9] ? _zz_products_w_values_5_9_1 : 8'h0);
  assign _zz_products_w_values_5_9_1 = operands_payload_input[79 : 72];
  assign _zz_products_w_values_5_9_2 = operands_payload_weights_5[79 : 72];
  assign _zz_products_w_values_5_10 = (operands_payload_mask[10] ? _zz_products_w_values_5_10_1 : 8'h0);
  assign _zz_products_w_values_5_10_1 = operands_payload_input[87 : 80];
  assign _zz_products_w_values_5_10_2 = operands_payload_weights_5[87 : 80];
  assign _zz_products_w_values_5_11 = (operands_payload_mask[11] ? _zz_products_w_values_5_11_1 : 8'h0);
  assign _zz_products_w_values_5_11_1 = operands_payload_input[95 : 88];
  assign _zz_products_w_values_5_11_2 = operands_payload_weights_5[95 : 88];
  assign _zz_products_w_values_5_12 = (operands_payload_mask[12] ? _zz_products_w_values_5_12_1 : 8'h0);
  assign _zz_products_w_values_5_12_1 = operands_payload_input[103 : 96];
  assign _zz_products_w_values_5_12_2 = operands_payload_weights_5[103 : 96];
  assign _zz_products_w_values_5_13 = (operands_payload_mask[13] ? _zz_products_w_values_5_13_1 : 8'h0);
  assign _zz_products_w_values_5_13_1 = operands_payload_input[111 : 104];
  assign _zz_products_w_values_5_13_2 = operands_payload_weights_5[111 : 104];
  assign _zz_products_w_values_5_14 = (operands_payload_mask[14] ? _zz_products_w_values_5_14_1 : 8'h0);
  assign _zz_products_w_values_5_14_1 = operands_payload_input[119 : 112];
  assign _zz_products_w_values_5_14_2 = operands_payload_weights_5[119 : 112];
  assign _zz_products_w_values_5_15 = (operands_payload_mask[15] ? _zz_products_w_values_5_15_1 : 8'h0);
  assign _zz_products_w_values_5_15_1 = operands_payload_input[127 : 120];
  assign _zz_products_w_values_5_15_2 = operands_payload_weights_5[127 : 120];
  assign _zz_products_w_values_6_0 = (operands_payload_mask[0] ? _zz_products_w_values_6_0_1 : 8'h0);
  assign _zz_products_w_values_6_0_1 = operands_payload_input[7 : 0];
  assign _zz_products_w_values_6_0_2 = operands_payload_weights_6[7 : 0];
  assign _zz_products_w_values_6_1 = (operands_payload_mask[1] ? _zz_products_w_values_6_1_1 : 8'h0);
  assign _zz_products_w_values_6_1_1 = operands_payload_input[15 : 8];
  assign _zz_products_w_values_6_1_2 = operands_payload_weights_6[15 : 8];
  assign _zz_products_w_values_6_2 = (operands_payload_mask[2] ? _zz_products_w_values_6_2_1 : 8'h0);
  assign _zz_products_w_values_6_2_1 = operands_payload_input[23 : 16];
  assign _zz_products_w_values_6_2_2 = operands_payload_weights_6[23 : 16];
  assign _zz_products_w_values_6_3 = (operands_payload_mask[3] ? _zz_products_w_values_6_3_1 : 8'h0);
  assign _zz_products_w_values_6_3_1 = operands_payload_input[31 : 24];
  assign _zz_products_w_values_6_3_2 = operands_payload_weights_6[31 : 24];
  assign _zz_products_w_values_6_4 = (operands_payload_mask[4] ? _zz_products_w_values_6_4_1 : 8'h0);
  assign _zz_products_w_values_6_4_1 = operands_payload_input[39 : 32];
  assign _zz_products_w_values_6_4_2 = operands_payload_weights_6[39 : 32];
  assign _zz_products_w_values_6_5 = (operands_payload_mask[5] ? _zz_products_w_values_6_5_1 : 8'h0);
  assign _zz_products_w_values_6_5_1 = operands_payload_input[47 : 40];
  assign _zz_products_w_values_6_5_2 = operands_payload_weights_6[47 : 40];
  assign _zz_products_w_values_6_6 = (operands_payload_mask[6] ? _zz_products_w_values_6_6_1 : 8'h0);
  assign _zz_products_w_values_6_6_1 = operands_payload_input[55 : 48];
  assign _zz_products_w_values_6_6_2 = operands_payload_weights_6[55 : 48];
  assign _zz_products_w_values_6_7 = (operands_payload_mask[7] ? _zz_products_w_values_6_7_1 : 8'h0);
  assign _zz_products_w_values_6_7_1 = operands_payload_input[63 : 56];
  assign _zz_products_w_values_6_7_2 = operands_payload_weights_6[63 : 56];
  assign _zz_products_w_values_6_8 = (operands_payload_mask[8] ? _zz_products_w_values_6_8_1 : 8'h0);
  assign _zz_products_w_values_6_8_1 = operands_payload_input[71 : 64];
  assign _zz_products_w_values_6_8_2 = operands_payload_weights_6[71 : 64];
  assign _zz_products_w_values_6_9 = (operands_payload_mask[9] ? _zz_products_w_values_6_9_1 : 8'h0);
  assign _zz_products_w_values_6_9_1 = operands_payload_input[79 : 72];
  assign _zz_products_w_values_6_9_2 = operands_payload_weights_6[79 : 72];
  assign _zz_products_w_values_6_10 = (operands_payload_mask[10] ? _zz_products_w_values_6_10_1 : 8'h0);
  assign _zz_products_w_values_6_10_1 = operands_payload_input[87 : 80];
  assign _zz_products_w_values_6_10_2 = operands_payload_weights_6[87 : 80];
  assign _zz_products_w_values_6_11 = (operands_payload_mask[11] ? _zz_products_w_values_6_11_1 : 8'h0);
  assign _zz_products_w_values_6_11_1 = operands_payload_input[95 : 88];
  assign _zz_products_w_values_6_11_2 = operands_payload_weights_6[95 : 88];
  assign _zz_products_w_values_6_12 = (operands_payload_mask[12] ? _zz_products_w_values_6_12_1 : 8'h0);
  assign _zz_products_w_values_6_12_1 = operands_payload_input[103 : 96];
  assign _zz_products_w_values_6_12_2 = operands_payload_weights_6[103 : 96];
  assign _zz_products_w_values_6_13 = (operands_payload_mask[13] ? _zz_products_w_values_6_13_1 : 8'h0);
  assign _zz_products_w_values_6_13_1 = operands_payload_input[111 : 104];
  assign _zz_products_w_values_6_13_2 = operands_payload_weights_6[111 : 104];
  assign _zz_products_w_values_6_14 = (operands_payload_mask[14] ? _zz_products_w_values_6_14_1 : 8'h0);
  assign _zz_products_w_values_6_14_1 = operands_payload_input[119 : 112];
  assign _zz_products_w_values_6_14_2 = operands_payload_weights_6[119 : 112];
  assign _zz_products_w_values_6_15 = (operands_payload_mask[15] ? _zz_products_w_values_6_15_1 : 8'h0);
  assign _zz_products_w_values_6_15_1 = operands_payload_input[127 : 120];
  assign _zz_products_w_values_6_15_2 = operands_payload_weights_6[127 : 120];
  assign _zz_products_w_values_7_0 = (operands_payload_mask[0] ? _zz_products_w_values_7_0_1 : 8'h0);
  assign _zz_products_w_values_7_0_1 = operands_payload_input[7 : 0];
  assign _zz_products_w_values_7_0_2 = operands_payload_weights_7[7 : 0];
  assign _zz_products_w_values_7_1 = (operands_payload_mask[1] ? _zz_products_w_values_7_1_1 : 8'h0);
  assign _zz_products_w_values_7_1_1 = operands_payload_input[15 : 8];
  assign _zz_products_w_values_7_1_2 = operands_payload_weights_7[15 : 8];
  assign _zz_products_w_values_7_2 = (operands_payload_mask[2] ? _zz_products_w_values_7_2_1 : 8'h0);
  assign _zz_products_w_values_7_2_1 = operands_payload_input[23 : 16];
  assign _zz_products_w_values_7_2_2 = operands_payload_weights_7[23 : 16];
  assign _zz_products_w_values_7_3 = (operands_payload_mask[3] ? _zz_products_w_values_7_3_1 : 8'h0);
  assign _zz_products_w_values_7_3_1 = operands_payload_input[31 : 24];
  assign _zz_products_w_values_7_3_2 = operands_payload_weights_7[31 : 24];
  assign _zz_products_w_values_7_4 = (operands_payload_mask[4] ? _zz_products_w_values_7_4_1 : 8'h0);
  assign _zz_products_w_values_7_4_1 = operands_payload_input[39 : 32];
  assign _zz_products_w_values_7_4_2 = operands_payload_weights_7[39 : 32];
  assign _zz_products_w_values_7_5 = (operands_payload_mask[5] ? _zz_products_w_values_7_5_1 : 8'h0);
  assign _zz_products_w_values_7_5_1 = operands_payload_input[47 : 40];
  assign _zz_products_w_values_7_5_2 = operands_payload_weights_7[47 : 40];
  assign _zz_products_w_values_7_6 = (operands_payload_mask[6] ? _zz_products_w_values_7_6_1 : 8'h0);
  assign _zz_products_w_values_7_6_1 = operands_payload_input[55 : 48];
  assign _zz_products_w_values_7_6_2 = operands_payload_weights_7[55 : 48];
  assign _zz_products_w_values_7_7 = (operands_payload_mask[7] ? _zz_products_w_values_7_7_1 : 8'h0);
  assign _zz_products_w_values_7_7_1 = operands_payload_input[63 : 56];
  assign _zz_products_w_values_7_7_2 = operands_payload_weights_7[63 : 56];
  assign _zz_products_w_values_7_8 = (operands_payload_mask[8] ? _zz_products_w_values_7_8_1 : 8'h0);
  assign _zz_products_w_values_7_8_1 = operands_payload_input[71 : 64];
  assign _zz_products_w_values_7_8_2 = operands_payload_weights_7[71 : 64];
  assign _zz_products_w_values_7_9 = (operands_payload_mask[9] ? _zz_products_w_values_7_9_1 : 8'h0);
  assign _zz_products_w_values_7_9_1 = operands_payload_input[79 : 72];
  assign _zz_products_w_values_7_9_2 = operands_payload_weights_7[79 : 72];
  assign _zz_products_w_values_7_10 = (operands_payload_mask[10] ? _zz_products_w_values_7_10_1 : 8'h0);
  assign _zz_products_w_values_7_10_1 = operands_payload_input[87 : 80];
  assign _zz_products_w_values_7_10_2 = operands_payload_weights_7[87 : 80];
  assign _zz_products_w_values_7_11 = (operands_payload_mask[11] ? _zz_products_w_values_7_11_1 : 8'h0);
  assign _zz_products_w_values_7_11_1 = operands_payload_input[95 : 88];
  assign _zz_products_w_values_7_11_2 = operands_payload_weights_7[95 : 88];
  assign _zz_products_w_values_7_12 = (operands_payload_mask[12] ? _zz_products_w_values_7_12_1 : 8'h0);
  assign _zz_products_w_values_7_12_1 = operands_payload_input[103 : 96];
  assign _zz_products_w_values_7_12_2 = operands_payload_weights_7[103 : 96];
  assign _zz_products_w_values_7_13 = (operands_payload_mask[13] ? _zz_products_w_values_7_13_1 : 8'h0);
  assign _zz_products_w_values_7_13_1 = operands_payload_input[111 : 104];
  assign _zz_products_w_values_7_13_2 = operands_payload_weights_7[111 : 104];
  assign _zz_products_w_values_7_14 = (operands_payload_mask[14] ? _zz_products_w_values_7_14_1 : 8'h0);
  assign _zz_products_w_values_7_14_1 = operands_payload_input[119 : 112];
  assign _zz_products_w_values_7_14_2 = operands_payload_weights_7[119 : 112];
  assign _zz_products_w_values_7_15 = (operands_payload_mask[15] ? _zz_products_w_values_7_15_1 : 8'h0);
  assign _zz_products_w_values_7_15_1 = operands_payload_input[127 : 120];
  assign _zz_products_w_values_7_15_2 = operands_payload_weights_7[127 : 120];
  assign _zz_products_w_values_8_0 = (operands_payload_mask[0] ? _zz_products_w_values_8_0_1 : 8'h0);
  assign _zz_products_w_values_8_0_1 = operands_payload_input[7 : 0];
  assign _zz_products_w_values_8_0_2 = operands_payload_weights_8[7 : 0];
  assign _zz_products_w_values_8_1 = (operands_payload_mask[1] ? _zz_products_w_values_8_1_1 : 8'h0);
  assign _zz_products_w_values_8_1_1 = operands_payload_input[15 : 8];
  assign _zz_products_w_values_8_1_2 = operands_payload_weights_8[15 : 8];
  assign _zz_products_w_values_8_2 = (operands_payload_mask[2] ? _zz_products_w_values_8_2_1 : 8'h0);
  assign _zz_products_w_values_8_2_1 = operands_payload_input[23 : 16];
  assign _zz_products_w_values_8_2_2 = operands_payload_weights_8[23 : 16];
  assign _zz_products_w_values_8_3 = (operands_payload_mask[3] ? _zz_products_w_values_8_3_1 : 8'h0);
  assign _zz_products_w_values_8_3_1 = operands_payload_input[31 : 24];
  assign _zz_products_w_values_8_3_2 = operands_payload_weights_8[31 : 24];
  assign _zz_products_w_values_8_4 = (operands_payload_mask[4] ? _zz_products_w_values_8_4_1 : 8'h0);
  assign _zz_products_w_values_8_4_1 = operands_payload_input[39 : 32];
  assign _zz_products_w_values_8_4_2 = operands_payload_weights_8[39 : 32];
  assign _zz_products_w_values_8_5 = (operands_payload_mask[5] ? _zz_products_w_values_8_5_1 : 8'h0);
  assign _zz_products_w_values_8_5_1 = operands_payload_input[47 : 40];
  assign _zz_products_w_values_8_5_2 = operands_payload_weights_8[47 : 40];
  assign _zz_products_w_values_8_6 = (operands_payload_mask[6] ? _zz_products_w_values_8_6_1 : 8'h0);
  assign _zz_products_w_values_8_6_1 = operands_payload_input[55 : 48];
  assign _zz_products_w_values_8_6_2 = operands_payload_weights_8[55 : 48];
  assign _zz_products_w_values_8_7 = (operands_payload_mask[7] ? _zz_products_w_values_8_7_1 : 8'h0);
  assign _zz_products_w_values_8_7_1 = operands_payload_input[63 : 56];
  assign _zz_products_w_values_8_7_2 = operands_payload_weights_8[63 : 56];
  assign _zz_products_w_values_8_8 = (operands_payload_mask[8] ? _zz_products_w_values_8_8_1 : 8'h0);
  assign _zz_products_w_values_8_8_1 = operands_payload_input[71 : 64];
  assign _zz_products_w_values_8_8_2 = operands_payload_weights_8[71 : 64];
  assign _zz_products_w_values_8_9 = (operands_payload_mask[9] ? _zz_products_w_values_8_9_1 : 8'h0);
  assign _zz_products_w_values_8_9_1 = operands_payload_input[79 : 72];
  assign _zz_products_w_values_8_9_2 = operands_payload_weights_8[79 : 72];
  assign _zz_products_w_values_8_10 = (operands_payload_mask[10] ? _zz_products_w_values_8_10_1 : 8'h0);
  assign _zz_products_w_values_8_10_1 = operands_payload_input[87 : 80];
  assign _zz_products_w_values_8_10_2 = operands_payload_weights_8[87 : 80];
  assign _zz_products_w_values_8_11 = (operands_payload_mask[11] ? _zz_products_w_values_8_11_1 : 8'h0);
  assign _zz_products_w_values_8_11_1 = operands_payload_input[95 : 88];
  assign _zz_products_w_values_8_11_2 = operands_payload_weights_8[95 : 88];
  assign _zz_products_w_values_8_12 = (operands_payload_mask[12] ? _zz_products_w_values_8_12_1 : 8'h0);
  assign _zz_products_w_values_8_12_1 = operands_payload_input[103 : 96];
  assign _zz_products_w_values_8_12_2 = operands_payload_weights_8[103 : 96];
  assign _zz_products_w_values_8_13 = (operands_payload_mask[13] ? _zz_products_w_values_8_13_1 : 8'h0);
  assign _zz_products_w_values_8_13_1 = operands_payload_input[111 : 104];
  assign _zz_products_w_values_8_13_2 = operands_payload_weights_8[111 : 104];
  assign _zz_products_w_values_8_14 = (operands_payload_mask[14] ? _zz_products_w_values_8_14_1 : 8'h0);
  assign _zz_products_w_values_8_14_1 = operands_payload_input[119 : 112];
  assign _zz_products_w_values_8_14_2 = operands_payload_weights_8[119 : 112];
  assign _zz_products_w_values_8_15 = (operands_payload_mask[15] ? _zz_products_w_values_8_15_1 : 8'h0);
  assign _zz_products_w_values_8_15_1 = operands_payload_input[127 : 120];
  assign _zz_products_w_values_8_15_2 = operands_payload_weights_8[127 : 120];
  assign _zz_products_w_values_9_0 = (operands_payload_mask[0] ? _zz_products_w_values_9_0_1 : 8'h0);
  assign _zz_products_w_values_9_0_1 = operands_payload_input[7 : 0];
  assign _zz_products_w_values_9_0_2 = operands_payload_weights_9[7 : 0];
  assign _zz_products_w_values_9_1 = (operands_payload_mask[1] ? _zz_products_w_values_9_1_1 : 8'h0);
  assign _zz_products_w_values_9_1_1 = operands_payload_input[15 : 8];
  assign _zz_products_w_values_9_1_2 = operands_payload_weights_9[15 : 8];
  assign _zz_products_w_values_9_2 = (operands_payload_mask[2] ? _zz_products_w_values_9_2_1 : 8'h0);
  assign _zz_products_w_values_9_2_1 = operands_payload_input[23 : 16];
  assign _zz_products_w_values_9_2_2 = operands_payload_weights_9[23 : 16];
  assign _zz_products_w_values_9_3 = (operands_payload_mask[3] ? _zz_products_w_values_9_3_1 : 8'h0);
  assign _zz_products_w_values_9_3_1 = operands_payload_input[31 : 24];
  assign _zz_products_w_values_9_3_2 = operands_payload_weights_9[31 : 24];
  assign _zz_products_w_values_9_4 = (operands_payload_mask[4] ? _zz_products_w_values_9_4_1 : 8'h0);
  assign _zz_products_w_values_9_4_1 = operands_payload_input[39 : 32];
  assign _zz_products_w_values_9_4_2 = operands_payload_weights_9[39 : 32];
  assign _zz_products_w_values_9_5 = (operands_payload_mask[5] ? _zz_products_w_values_9_5_1 : 8'h0);
  assign _zz_products_w_values_9_5_1 = operands_payload_input[47 : 40];
  assign _zz_products_w_values_9_5_2 = operands_payload_weights_9[47 : 40];
  assign _zz_products_w_values_9_6 = (operands_payload_mask[6] ? _zz_products_w_values_9_6_1 : 8'h0);
  assign _zz_products_w_values_9_6_1 = operands_payload_input[55 : 48];
  assign _zz_products_w_values_9_6_2 = operands_payload_weights_9[55 : 48];
  assign _zz_products_w_values_9_7 = (operands_payload_mask[7] ? _zz_products_w_values_9_7_1 : 8'h0);
  assign _zz_products_w_values_9_7_1 = operands_payload_input[63 : 56];
  assign _zz_products_w_values_9_7_2 = operands_payload_weights_9[63 : 56];
  assign _zz_products_w_values_9_8 = (operands_payload_mask[8] ? _zz_products_w_values_9_8_1 : 8'h0);
  assign _zz_products_w_values_9_8_1 = operands_payload_input[71 : 64];
  assign _zz_products_w_values_9_8_2 = operands_payload_weights_9[71 : 64];
  assign _zz_products_w_values_9_9 = (operands_payload_mask[9] ? _zz_products_w_values_9_9_1 : 8'h0);
  assign _zz_products_w_values_9_9_1 = operands_payload_input[79 : 72];
  assign _zz_products_w_values_9_9_2 = operands_payload_weights_9[79 : 72];
  assign _zz_products_w_values_9_10 = (operands_payload_mask[10] ? _zz_products_w_values_9_10_1 : 8'h0);
  assign _zz_products_w_values_9_10_1 = operands_payload_input[87 : 80];
  assign _zz_products_w_values_9_10_2 = operands_payload_weights_9[87 : 80];
  assign _zz_products_w_values_9_11 = (operands_payload_mask[11] ? _zz_products_w_values_9_11_1 : 8'h0);
  assign _zz_products_w_values_9_11_1 = operands_payload_input[95 : 88];
  assign _zz_products_w_values_9_11_2 = operands_payload_weights_9[95 : 88];
  assign _zz_products_w_values_9_12 = (operands_payload_mask[12] ? _zz_products_w_values_9_12_1 : 8'h0);
  assign _zz_products_w_values_9_12_1 = operands_payload_input[103 : 96];
  assign _zz_products_w_values_9_12_2 = operands_payload_weights_9[103 : 96];
  assign _zz_products_w_values_9_13 = (operands_payload_mask[13] ? _zz_products_w_values_9_13_1 : 8'h0);
  assign _zz_products_w_values_9_13_1 = operands_payload_input[111 : 104];
  assign _zz_products_w_values_9_13_2 = operands_payload_weights_9[111 : 104];
  assign _zz_products_w_values_9_14 = (operands_payload_mask[14] ? _zz_products_w_values_9_14_1 : 8'h0);
  assign _zz_products_w_values_9_14_1 = operands_payload_input[119 : 112];
  assign _zz_products_w_values_9_14_2 = operands_payload_weights_9[119 : 112];
  assign _zz_products_w_values_9_15 = (operands_payload_mask[15] ? _zz_products_w_values_9_15_1 : 8'h0);
  assign _zz_products_w_values_9_15_1 = operands_payload_input[127 : 120];
  assign _zz_products_w_values_9_15_2 = operands_payload_weights_9[127 : 120];
  assign _zz_products_w_values_10_0 = (operands_payload_mask[0] ? _zz_products_w_values_10_0_1 : 8'h0);
  assign _zz_products_w_values_10_0_1 = operands_payload_input[7 : 0];
  assign _zz_products_w_values_10_0_2 = operands_payload_weights_10[7 : 0];
  assign _zz_products_w_values_10_1 = (operands_payload_mask[1] ? _zz_products_w_values_10_1_1 : 8'h0);
  assign _zz_products_w_values_10_1_1 = operands_payload_input[15 : 8];
  assign _zz_products_w_values_10_1_2 = operands_payload_weights_10[15 : 8];
  assign _zz_products_w_values_10_2 = (operands_payload_mask[2] ? _zz_products_w_values_10_2_1 : 8'h0);
  assign _zz_products_w_values_10_2_1 = operands_payload_input[23 : 16];
  assign _zz_products_w_values_10_2_2 = operands_payload_weights_10[23 : 16];
  assign _zz_products_w_values_10_3 = (operands_payload_mask[3] ? _zz_products_w_values_10_3_1 : 8'h0);
  assign _zz_products_w_values_10_3_1 = operands_payload_input[31 : 24];
  assign _zz_products_w_values_10_3_2 = operands_payload_weights_10[31 : 24];
  assign _zz_products_w_values_10_4 = (operands_payload_mask[4] ? _zz_products_w_values_10_4_1 : 8'h0);
  assign _zz_products_w_values_10_4_1 = operands_payload_input[39 : 32];
  assign _zz_products_w_values_10_4_2 = operands_payload_weights_10[39 : 32];
  assign _zz_products_w_values_10_5 = (operands_payload_mask[5] ? _zz_products_w_values_10_5_1 : 8'h0);
  assign _zz_products_w_values_10_5_1 = operands_payload_input[47 : 40];
  assign _zz_products_w_values_10_5_2 = operands_payload_weights_10[47 : 40];
  assign _zz_products_w_values_10_6 = (operands_payload_mask[6] ? _zz_products_w_values_10_6_1 : 8'h0);
  assign _zz_products_w_values_10_6_1 = operands_payload_input[55 : 48];
  assign _zz_products_w_values_10_6_2 = operands_payload_weights_10[55 : 48];
  assign _zz_products_w_values_10_7 = (operands_payload_mask[7] ? _zz_products_w_values_10_7_1 : 8'h0);
  assign _zz_products_w_values_10_7_1 = operands_payload_input[63 : 56];
  assign _zz_products_w_values_10_7_2 = operands_payload_weights_10[63 : 56];
  assign _zz_products_w_values_10_8 = (operands_payload_mask[8] ? _zz_products_w_values_10_8_1 : 8'h0);
  assign _zz_products_w_values_10_8_1 = operands_payload_input[71 : 64];
  assign _zz_products_w_values_10_8_2 = operands_payload_weights_10[71 : 64];
  assign _zz_products_w_values_10_9 = (operands_payload_mask[9] ? _zz_products_w_values_10_9_1 : 8'h0);
  assign _zz_products_w_values_10_9_1 = operands_payload_input[79 : 72];
  assign _zz_products_w_values_10_9_2 = operands_payload_weights_10[79 : 72];
  assign _zz_products_w_values_10_10 = (operands_payload_mask[10] ? _zz_products_w_values_10_10_1 : 8'h0);
  assign _zz_products_w_values_10_10_1 = operands_payload_input[87 : 80];
  assign _zz_products_w_values_10_10_2 = operands_payload_weights_10[87 : 80];
  assign _zz_products_w_values_10_11 = (operands_payload_mask[11] ? _zz_products_w_values_10_11_1 : 8'h0);
  assign _zz_products_w_values_10_11_1 = operands_payload_input[95 : 88];
  assign _zz_products_w_values_10_11_2 = operands_payload_weights_10[95 : 88];
  assign _zz_products_w_values_10_12 = (operands_payload_mask[12] ? _zz_products_w_values_10_12_1 : 8'h0);
  assign _zz_products_w_values_10_12_1 = operands_payload_input[103 : 96];
  assign _zz_products_w_values_10_12_2 = operands_payload_weights_10[103 : 96];
  assign _zz_products_w_values_10_13 = (operands_payload_mask[13] ? _zz_products_w_values_10_13_1 : 8'h0);
  assign _zz_products_w_values_10_13_1 = operands_payload_input[111 : 104];
  assign _zz_products_w_values_10_13_2 = operands_payload_weights_10[111 : 104];
  assign _zz_products_w_values_10_14 = (operands_payload_mask[14] ? _zz_products_w_values_10_14_1 : 8'h0);
  assign _zz_products_w_values_10_14_1 = operands_payload_input[119 : 112];
  assign _zz_products_w_values_10_14_2 = operands_payload_weights_10[119 : 112];
  assign _zz_products_w_values_10_15 = (operands_payload_mask[15] ? _zz_products_w_values_10_15_1 : 8'h0);
  assign _zz_products_w_values_10_15_1 = operands_payload_input[127 : 120];
  assign _zz_products_w_values_10_15_2 = operands_payload_weights_10[127 : 120];
  assign _zz_products_w_values_11_0 = (operands_payload_mask[0] ? _zz_products_w_values_11_0_1 : 8'h0);
  assign _zz_products_w_values_11_0_1 = operands_payload_input[7 : 0];
  assign _zz_products_w_values_11_0_2 = operands_payload_weights_11[7 : 0];
  assign _zz_products_w_values_11_1 = (operands_payload_mask[1] ? _zz_products_w_values_11_1_1 : 8'h0);
  assign _zz_products_w_values_11_1_1 = operands_payload_input[15 : 8];
  assign _zz_products_w_values_11_1_2 = operands_payload_weights_11[15 : 8];
  assign _zz_products_w_values_11_2 = (operands_payload_mask[2] ? _zz_products_w_values_11_2_1 : 8'h0);
  assign _zz_products_w_values_11_2_1 = operands_payload_input[23 : 16];
  assign _zz_products_w_values_11_2_2 = operands_payload_weights_11[23 : 16];
  assign _zz_products_w_values_11_3 = (operands_payload_mask[3] ? _zz_products_w_values_11_3_1 : 8'h0);
  assign _zz_products_w_values_11_3_1 = operands_payload_input[31 : 24];
  assign _zz_products_w_values_11_3_2 = operands_payload_weights_11[31 : 24];
  assign _zz_products_w_values_11_4 = (operands_payload_mask[4] ? _zz_products_w_values_11_4_1 : 8'h0);
  assign _zz_products_w_values_11_4_1 = operands_payload_input[39 : 32];
  assign _zz_products_w_values_11_4_2 = operands_payload_weights_11[39 : 32];
  assign _zz_products_w_values_11_5 = (operands_payload_mask[5] ? _zz_products_w_values_11_5_1 : 8'h0);
  assign _zz_products_w_values_11_5_1 = operands_payload_input[47 : 40];
  assign _zz_products_w_values_11_5_2 = operands_payload_weights_11[47 : 40];
  assign _zz_products_w_values_11_6 = (operands_payload_mask[6] ? _zz_products_w_values_11_6_1 : 8'h0);
  assign _zz_products_w_values_11_6_1 = operands_payload_input[55 : 48];
  assign _zz_products_w_values_11_6_2 = operands_payload_weights_11[55 : 48];
  assign _zz_products_w_values_11_7 = (operands_payload_mask[7] ? _zz_products_w_values_11_7_1 : 8'h0);
  assign _zz_products_w_values_11_7_1 = operands_payload_input[63 : 56];
  assign _zz_products_w_values_11_7_2 = operands_payload_weights_11[63 : 56];
  assign _zz_products_w_values_11_8 = (operands_payload_mask[8] ? _zz_products_w_values_11_8_1 : 8'h0);
  assign _zz_products_w_values_11_8_1 = operands_payload_input[71 : 64];
  assign _zz_products_w_values_11_8_2 = operands_payload_weights_11[71 : 64];
  assign _zz_products_w_values_11_9 = (operands_payload_mask[9] ? _zz_products_w_values_11_9_1 : 8'h0);
  assign _zz_products_w_values_11_9_1 = operands_payload_input[79 : 72];
  assign _zz_products_w_values_11_9_2 = operands_payload_weights_11[79 : 72];
  assign _zz_products_w_values_11_10 = (operands_payload_mask[10] ? _zz_products_w_values_11_10_1 : 8'h0);
  assign _zz_products_w_values_11_10_1 = operands_payload_input[87 : 80];
  assign _zz_products_w_values_11_10_2 = operands_payload_weights_11[87 : 80];
  assign _zz_products_w_values_11_11 = (operands_payload_mask[11] ? _zz_products_w_values_11_11_1 : 8'h0);
  assign _zz_products_w_values_11_11_1 = operands_payload_input[95 : 88];
  assign _zz_products_w_values_11_11_2 = operands_payload_weights_11[95 : 88];
  assign _zz_products_w_values_11_12 = (operands_payload_mask[12] ? _zz_products_w_values_11_12_1 : 8'h0);
  assign _zz_products_w_values_11_12_1 = operands_payload_input[103 : 96];
  assign _zz_products_w_values_11_12_2 = operands_payload_weights_11[103 : 96];
  assign _zz_products_w_values_11_13 = (operands_payload_mask[13] ? _zz_products_w_values_11_13_1 : 8'h0);
  assign _zz_products_w_values_11_13_1 = operands_payload_input[111 : 104];
  assign _zz_products_w_values_11_13_2 = operands_payload_weights_11[111 : 104];
  assign _zz_products_w_values_11_14 = (operands_payload_mask[14] ? _zz_products_w_values_11_14_1 : 8'h0);
  assign _zz_products_w_values_11_14_1 = operands_payload_input[119 : 112];
  assign _zz_products_w_values_11_14_2 = operands_payload_weights_11[119 : 112];
  assign _zz_products_w_values_11_15 = (operands_payload_mask[15] ? _zz_products_w_values_11_15_1 : 8'h0);
  assign _zz_products_w_values_11_15_1 = operands_payload_input[127 : 120];
  assign _zz_products_w_values_11_15_2 = operands_payload_weights_11[127 : 120];
  assign _zz_products_w_values_12_0 = (operands_payload_mask[0] ? _zz_products_w_values_12_0_1 : 8'h0);
  assign _zz_products_w_values_12_0_1 = operands_payload_input[7 : 0];
  assign _zz_products_w_values_12_0_2 = operands_payload_weights_12[7 : 0];
  assign _zz_products_w_values_12_1 = (operands_payload_mask[1] ? _zz_products_w_values_12_1_1 : 8'h0);
  assign _zz_products_w_values_12_1_1 = operands_payload_input[15 : 8];
  assign _zz_products_w_values_12_1_2 = operands_payload_weights_12[15 : 8];
  assign _zz_products_w_values_12_2 = (operands_payload_mask[2] ? _zz_products_w_values_12_2_1 : 8'h0);
  assign _zz_products_w_values_12_2_1 = operands_payload_input[23 : 16];
  assign _zz_products_w_values_12_2_2 = operands_payload_weights_12[23 : 16];
  assign _zz_products_w_values_12_3 = (operands_payload_mask[3] ? _zz_products_w_values_12_3_1 : 8'h0);
  assign _zz_products_w_values_12_3_1 = operands_payload_input[31 : 24];
  assign _zz_products_w_values_12_3_2 = operands_payload_weights_12[31 : 24];
  assign _zz_products_w_values_12_4 = (operands_payload_mask[4] ? _zz_products_w_values_12_4_1 : 8'h0);
  assign _zz_products_w_values_12_4_1 = operands_payload_input[39 : 32];
  assign _zz_products_w_values_12_4_2 = operands_payload_weights_12[39 : 32];
  assign _zz_products_w_values_12_5 = (operands_payload_mask[5] ? _zz_products_w_values_12_5_1 : 8'h0);
  assign _zz_products_w_values_12_5_1 = operands_payload_input[47 : 40];
  assign _zz_products_w_values_12_5_2 = operands_payload_weights_12[47 : 40];
  assign _zz_products_w_values_12_6 = (operands_payload_mask[6] ? _zz_products_w_values_12_6_1 : 8'h0);
  assign _zz_products_w_values_12_6_1 = operands_payload_input[55 : 48];
  assign _zz_products_w_values_12_6_2 = operands_payload_weights_12[55 : 48];
  assign _zz_products_w_values_12_7 = (operands_payload_mask[7] ? _zz_products_w_values_12_7_1 : 8'h0);
  assign _zz_products_w_values_12_7_1 = operands_payload_input[63 : 56];
  assign _zz_products_w_values_12_7_2 = operands_payload_weights_12[63 : 56];
  assign _zz_products_w_values_12_8 = (operands_payload_mask[8] ? _zz_products_w_values_12_8_1 : 8'h0);
  assign _zz_products_w_values_12_8_1 = operands_payload_input[71 : 64];
  assign _zz_products_w_values_12_8_2 = operands_payload_weights_12[71 : 64];
  assign _zz_products_w_values_12_9 = (operands_payload_mask[9] ? _zz_products_w_values_12_9_1 : 8'h0);
  assign _zz_products_w_values_12_9_1 = operands_payload_input[79 : 72];
  assign _zz_products_w_values_12_9_2 = operands_payload_weights_12[79 : 72];
  assign _zz_products_w_values_12_10 = (operands_payload_mask[10] ? _zz_products_w_values_12_10_1 : 8'h0);
  assign _zz_products_w_values_12_10_1 = operands_payload_input[87 : 80];
  assign _zz_products_w_values_12_10_2 = operands_payload_weights_12[87 : 80];
  assign _zz_products_w_values_12_11 = (operands_payload_mask[11] ? _zz_products_w_values_12_11_1 : 8'h0);
  assign _zz_products_w_values_12_11_1 = operands_payload_input[95 : 88];
  assign _zz_products_w_values_12_11_2 = operands_payload_weights_12[95 : 88];
  assign _zz_products_w_values_12_12 = (operands_payload_mask[12] ? _zz_products_w_values_12_12_1 : 8'h0);
  assign _zz_products_w_values_12_12_1 = operands_payload_input[103 : 96];
  assign _zz_products_w_values_12_12_2 = operands_payload_weights_12[103 : 96];
  assign _zz_products_w_values_12_13 = (operands_payload_mask[13] ? _zz_products_w_values_12_13_1 : 8'h0);
  assign _zz_products_w_values_12_13_1 = operands_payload_input[111 : 104];
  assign _zz_products_w_values_12_13_2 = operands_payload_weights_12[111 : 104];
  assign _zz_products_w_values_12_14 = (operands_payload_mask[14] ? _zz_products_w_values_12_14_1 : 8'h0);
  assign _zz_products_w_values_12_14_1 = operands_payload_input[119 : 112];
  assign _zz_products_w_values_12_14_2 = operands_payload_weights_12[119 : 112];
  assign _zz_products_w_values_12_15 = (operands_payload_mask[15] ? _zz_products_w_values_12_15_1 : 8'h0);
  assign _zz_products_w_values_12_15_1 = operands_payload_input[127 : 120];
  assign _zz_products_w_values_12_15_2 = operands_payload_weights_12[127 : 120];
  assign _zz_products_w_values_13_0 = (operands_payload_mask[0] ? _zz_products_w_values_13_0_1 : 8'h0);
  assign _zz_products_w_values_13_0_1 = operands_payload_input[7 : 0];
  assign _zz_products_w_values_13_0_2 = operands_payload_weights_13[7 : 0];
  assign _zz_products_w_values_13_1 = (operands_payload_mask[1] ? _zz_products_w_values_13_1_1 : 8'h0);
  assign _zz_products_w_values_13_1_1 = operands_payload_input[15 : 8];
  assign _zz_products_w_values_13_1_2 = operands_payload_weights_13[15 : 8];
  assign _zz_products_w_values_13_2 = (operands_payload_mask[2] ? _zz_products_w_values_13_2_1 : 8'h0);
  assign _zz_products_w_values_13_2_1 = operands_payload_input[23 : 16];
  assign _zz_products_w_values_13_2_2 = operands_payload_weights_13[23 : 16];
  assign _zz_products_w_values_13_3 = (operands_payload_mask[3] ? _zz_products_w_values_13_3_1 : 8'h0);
  assign _zz_products_w_values_13_3_1 = operands_payload_input[31 : 24];
  assign _zz_products_w_values_13_3_2 = operands_payload_weights_13[31 : 24];
  assign _zz_products_w_values_13_4 = (operands_payload_mask[4] ? _zz_products_w_values_13_4_1 : 8'h0);
  assign _zz_products_w_values_13_4_1 = operands_payload_input[39 : 32];
  assign _zz_products_w_values_13_4_2 = operands_payload_weights_13[39 : 32];
  assign _zz_products_w_values_13_5 = (operands_payload_mask[5] ? _zz_products_w_values_13_5_1 : 8'h0);
  assign _zz_products_w_values_13_5_1 = operands_payload_input[47 : 40];
  assign _zz_products_w_values_13_5_2 = operands_payload_weights_13[47 : 40];
  assign _zz_products_w_values_13_6 = (operands_payload_mask[6] ? _zz_products_w_values_13_6_1 : 8'h0);
  assign _zz_products_w_values_13_6_1 = operands_payload_input[55 : 48];
  assign _zz_products_w_values_13_6_2 = operands_payload_weights_13[55 : 48];
  assign _zz_products_w_values_13_7 = (operands_payload_mask[7] ? _zz_products_w_values_13_7_1 : 8'h0);
  assign _zz_products_w_values_13_7_1 = operands_payload_input[63 : 56];
  assign _zz_products_w_values_13_7_2 = operands_payload_weights_13[63 : 56];
  assign _zz_products_w_values_13_8 = (operands_payload_mask[8] ? _zz_products_w_values_13_8_1 : 8'h0);
  assign _zz_products_w_values_13_8_1 = operands_payload_input[71 : 64];
  assign _zz_products_w_values_13_8_2 = operands_payload_weights_13[71 : 64];
  assign _zz_products_w_values_13_9 = (operands_payload_mask[9] ? _zz_products_w_values_13_9_1 : 8'h0);
  assign _zz_products_w_values_13_9_1 = operands_payload_input[79 : 72];
  assign _zz_products_w_values_13_9_2 = operands_payload_weights_13[79 : 72];
  assign _zz_products_w_values_13_10 = (operands_payload_mask[10] ? _zz_products_w_values_13_10_1 : 8'h0);
  assign _zz_products_w_values_13_10_1 = operands_payload_input[87 : 80];
  assign _zz_products_w_values_13_10_2 = operands_payload_weights_13[87 : 80];
  assign _zz_products_w_values_13_11 = (operands_payload_mask[11] ? _zz_products_w_values_13_11_1 : 8'h0);
  assign _zz_products_w_values_13_11_1 = operands_payload_input[95 : 88];
  assign _zz_products_w_values_13_11_2 = operands_payload_weights_13[95 : 88];
  assign _zz_products_w_values_13_12 = (operands_payload_mask[12] ? _zz_products_w_values_13_12_1 : 8'h0);
  assign _zz_products_w_values_13_12_1 = operands_payload_input[103 : 96];
  assign _zz_products_w_values_13_12_2 = operands_payload_weights_13[103 : 96];
  assign _zz_products_w_values_13_13 = (operands_payload_mask[13] ? _zz_products_w_values_13_13_1 : 8'h0);
  assign _zz_products_w_values_13_13_1 = operands_payload_input[111 : 104];
  assign _zz_products_w_values_13_13_2 = operands_payload_weights_13[111 : 104];
  assign _zz_products_w_values_13_14 = (operands_payload_mask[14] ? _zz_products_w_values_13_14_1 : 8'h0);
  assign _zz_products_w_values_13_14_1 = operands_payload_input[119 : 112];
  assign _zz_products_w_values_13_14_2 = operands_payload_weights_13[119 : 112];
  assign _zz_products_w_values_13_15 = (operands_payload_mask[15] ? _zz_products_w_values_13_15_1 : 8'h0);
  assign _zz_products_w_values_13_15_1 = operands_payload_input[127 : 120];
  assign _zz_products_w_values_13_15_2 = operands_payload_weights_13[127 : 120];
  assign _zz_products_w_values_14_0 = (operands_payload_mask[0] ? _zz_products_w_values_14_0_1 : 8'h0);
  assign _zz_products_w_values_14_0_1 = operands_payload_input[7 : 0];
  assign _zz_products_w_values_14_0_2 = operands_payload_weights_14[7 : 0];
  assign _zz_products_w_values_14_1 = (operands_payload_mask[1] ? _zz_products_w_values_14_1_1 : 8'h0);
  assign _zz_products_w_values_14_1_1 = operands_payload_input[15 : 8];
  assign _zz_products_w_values_14_1_2 = operands_payload_weights_14[15 : 8];
  assign _zz_products_w_values_14_2 = (operands_payload_mask[2] ? _zz_products_w_values_14_2_1 : 8'h0);
  assign _zz_products_w_values_14_2_1 = operands_payload_input[23 : 16];
  assign _zz_products_w_values_14_2_2 = operands_payload_weights_14[23 : 16];
  assign _zz_products_w_values_14_3 = (operands_payload_mask[3] ? _zz_products_w_values_14_3_1 : 8'h0);
  assign _zz_products_w_values_14_3_1 = operands_payload_input[31 : 24];
  assign _zz_products_w_values_14_3_2 = operands_payload_weights_14[31 : 24];
  assign _zz_products_w_values_14_4 = (operands_payload_mask[4] ? _zz_products_w_values_14_4_1 : 8'h0);
  assign _zz_products_w_values_14_4_1 = operands_payload_input[39 : 32];
  assign _zz_products_w_values_14_4_2 = operands_payload_weights_14[39 : 32];
  assign _zz_products_w_values_14_5 = (operands_payload_mask[5] ? _zz_products_w_values_14_5_1 : 8'h0);
  assign _zz_products_w_values_14_5_1 = operands_payload_input[47 : 40];
  assign _zz_products_w_values_14_5_2 = operands_payload_weights_14[47 : 40];
  assign _zz_products_w_values_14_6 = (operands_payload_mask[6] ? _zz_products_w_values_14_6_1 : 8'h0);
  assign _zz_products_w_values_14_6_1 = operands_payload_input[55 : 48];
  assign _zz_products_w_values_14_6_2 = operands_payload_weights_14[55 : 48];
  assign _zz_products_w_values_14_7 = (operands_payload_mask[7] ? _zz_products_w_values_14_7_1 : 8'h0);
  assign _zz_products_w_values_14_7_1 = operands_payload_input[63 : 56];
  assign _zz_products_w_values_14_7_2 = operands_payload_weights_14[63 : 56];
  assign _zz_products_w_values_14_8 = (operands_payload_mask[8] ? _zz_products_w_values_14_8_1 : 8'h0);
  assign _zz_products_w_values_14_8_1 = operands_payload_input[71 : 64];
  assign _zz_products_w_values_14_8_2 = operands_payload_weights_14[71 : 64];
  assign _zz_products_w_values_14_9 = (operands_payload_mask[9] ? _zz_products_w_values_14_9_1 : 8'h0);
  assign _zz_products_w_values_14_9_1 = operands_payload_input[79 : 72];
  assign _zz_products_w_values_14_9_2 = operands_payload_weights_14[79 : 72];
  assign _zz_products_w_values_14_10 = (operands_payload_mask[10] ? _zz_products_w_values_14_10_1 : 8'h0);
  assign _zz_products_w_values_14_10_1 = operands_payload_input[87 : 80];
  assign _zz_products_w_values_14_10_2 = operands_payload_weights_14[87 : 80];
  assign _zz_products_w_values_14_11 = (operands_payload_mask[11] ? _zz_products_w_values_14_11_1 : 8'h0);
  assign _zz_products_w_values_14_11_1 = operands_payload_input[95 : 88];
  assign _zz_products_w_values_14_11_2 = operands_payload_weights_14[95 : 88];
  assign _zz_products_w_values_14_12 = (operands_payload_mask[12] ? _zz_products_w_values_14_12_1 : 8'h0);
  assign _zz_products_w_values_14_12_1 = operands_payload_input[103 : 96];
  assign _zz_products_w_values_14_12_2 = operands_payload_weights_14[103 : 96];
  assign _zz_products_w_values_14_13 = (operands_payload_mask[13] ? _zz_products_w_values_14_13_1 : 8'h0);
  assign _zz_products_w_values_14_13_1 = operands_payload_input[111 : 104];
  assign _zz_products_w_values_14_13_2 = operands_payload_weights_14[111 : 104];
  assign _zz_products_w_values_14_14 = (operands_payload_mask[14] ? _zz_products_w_values_14_14_1 : 8'h0);
  assign _zz_products_w_values_14_14_1 = operands_payload_input[119 : 112];
  assign _zz_products_w_values_14_14_2 = operands_payload_weights_14[119 : 112];
  assign _zz_products_w_values_14_15 = (operands_payload_mask[15] ? _zz_products_w_values_14_15_1 : 8'h0);
  assign _zz_products_w_values_14_15_1 = operands_payload_input[127 : 120];
  assign _zz_products_w_values_14_15_2 = operands_payload_weights_14[127 : 120];
  assign _zz_products_w_values_15_0 = (operands_payload_mask[0] ? _zz_products_w_values_15_0_1 : 8'h0);
  assign _zz_products_w_values_15_0_1 = operands_payload_input[7 : 0];
  assign _zz_products_w_values_15_0_2 = operands_payload_weights_15[7 : 0];
  assign _zz_products_w_values_15_1 = (operands_payload_mask[1] ? _zz_products_w_values_15_1_1 : 8'h0);
  assign _zz_products_w_values_15_1_1 = operands_payload_input[15 : 8];
  assign _zz_products_w_values_15_1_2 = operands_payload_weights_15[15 : 8];
  assign _zz_products_w_values_15_2 = (operands_payload_mask[2] ? _zz_products_w_values_15_2_1 : 8'h0);
  assign _zz_products_w_values_15_2_1 = operands_payload_input[23 : 16];
  assign _zz_products_w_values_15_2_2 = operands_payload_weights_15[23 : 16];
  assign _zz_products_w_values_15_3 = (operands_payload_mask[3] ? _zz_products_w_values_15_3_1 : 8'h0);
  assign _zz_products_w_values_15_3_1 = operands_payload_input[31 : 24];
  assign _zz_products_w_values_15_3_2 = operands_payload_weights_15[31 : 24];
  assign _zz_products_w_values_15_4 = (operands_payload_mask[4] ? _zz_products_w_values_15_4_1 : 8'h0);
  assign _zz_products_w_values_15_4_1 = operands_payload_input[39 : 32];
  assign _zz_products_w_values_15_4_2 = operands_payload_weights_15[39 : 32];
  assign _zz_products_w_values_15_5 = (operands_payload_mask[5] ? _zz_products_w_values_15_5_1 : 8'h0);
  assign _zz_products_w_values_15_5_1 = operands_payload_input[47 : 40];
  assign _zz_products_w_values_15_5_2 = operands_payload_weights_15[47 : 40];
  assign _zz_products_w_values_15_6 = (operands_payload_mask[6] ? _zz_products_w_values_15_6_1 : 8'h0);
  assign _zz_products_w_values_15_6_1 = operands_payload_input[55 : 48];
  assign _zz_products_w_values_15_6_2 = operands_payload_weights_15[55 : 48];
  assign _zz_products_w_values_15_7 = (operands_payload_mask[7] ? _zz_products_w_values_15_7_1 : 8'h0);
  assign _zz_products_w_values_15_7_1 = operands_payload_input[63 : 56];
  assign _zz_products_w_values_15_7_2 = operands_payload_weights_15[63 : 56];
  assign _zz_products_w_values_15_8 = (operands_payload_mask[8] ? _zz_products_w_values_15_8_1 : 8'h0);
  assign _zz_products_w_values_15_8_1 = operands_payload_input[71 : 64];
  assign _zz_products_w_values_15_8_2 = operands_payload_weights_15[71 : 64];
  assign _zz_products_w_values_15_9 = (operands_payload_mask[9] ? _zz_products_w_values_15_9_1 : 8'h0);
  assign _zz_products_w_values_15_9_1 = operands_payload_input[79 : 72];
  assign _zz_products_w_values_15_9_2 = operands_payload_weights_15[79 : 72];
  assign _zz_products_w_values_15_10 = (operands_payload_mask[10] ? _zz_products_w_values_15_10_1 : 8'h0);
  assign _zz_products_w_values_15_10_1 = operands_payload_input[87 : 80];
  assign _zz_products_w_values_15_10_2 = operands_payload_weights_15[87 : 80];
  assign _zz_products_w_values_15_11 = (operands_payload_mask[11] ? _zz_products_w_values_15_11_1 : 8'h0);
  assign _zz_products_w_values_15_11_1 = operands_payload_input[95 : 88];
  assign _zz_products_w_values_15_11_2 = operands_payload_weights_15[95 : 88];
  assign _zz_products_w_values_15_12 = (operands_payload_mask[12] ? _zz_products_w_values_15_12_1 : 8'h0);
  assign _zz_products_w_values_15_12_1 = operands_payload_input[103 : 96];
  assign _zz_products_w_values_15_12_2 = operands_payload_weights_15[103 : 96];
  assign _zz_products_w_values_15_13 = (operands_payload_mask[13] ? _zz_products_w_values_15_13_1 : 8'h0);
  assign _zz_products_w_values_15_13_1 = operands_payload_input[111 : 104];
  assign _zz_products_w_values_15_13_2 = operands_payload_weights_15[111 : 104];
  assign _zz_products_w_values_15_14 = (operands_payload_mask[14] ? _zz_products_w_values_15_14_1 : 8'h0);
  assign _zz_products_w_values_15_14_1 = operands_payload_input[119 : 112];
  assign _zz_products_w_values_15_14_2 = operands_payload_weights_15[119 : 112];
  assign _zz_products_w_values_15_15 = (operands_payload_mask[15] ? _zz_products_w_values_15_15_1 : 8'h0);
  assign _zz_products_w_values_15_15_1 = operands_payload_input[127 : 120];
  assign _zz_products_w_values_15_15_2 = operands_payload_weights_15[127 : 120];
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
  assign _zz_reduce8_w_values_4_0 = {{1{products_payload_values_4_0[15]}}, products_payload_values_4_0};
  assign _zz_reduce8_w_values_4_0_1 = {{1{products_payload_values_4_1[15]}}, products_payload_values_4_1};
  assign _zz_reduce8_w_values_4_1 = {{1{products_payload_values_4_2[15]}}, products_payload_values_4_2};
  assign _zz_reduce8_w_values_4_1_1 = {{1{products_payload_values_4_3[15]}}, products_payload_values_4_3};
  assign _zz_reduce8_w_values_4_2 = {{1{products_payload_values_4_4[15]}}, products_payload_values_4_4};
  assign _zz_reduce8_w_values_4_2_1 = {{1{products_payload_values_4_5[15]}}, products_payload_values_4_5};
  assign _zz_reduce8_w_values_4_3 = {{1{products_payload_values_4_6[15]}}, products_payload_values_4_6};
  assign _zz_reduce8_w_values_4_3_1 = {{1{products_payload_values_4_7[15]}}, products_payload_values_4_7};
  assign _zz_reduce8_w_values_4_4 = {{1{products_payload_values_4_8[15]}}, products_payload_values_4_8};
  assign _zz_reduce8_w_values_4_4_1 = {{1{products_payload_values_4_9[15]}}, products_payload_values_4_9};
  assign _zz_reduce8_w_values_4_5 = {{1{products_payload_values_4_10[15]}}, products_payload_values_4_10};
  assign _zz_reduce8_w_values_4_5_1 = {{1{products_payload_values_4_11[15]}}, products_payload_values_4_11};
  assign _zz_reduce8_w_values_4_6 = {{1{products_payload_values_4_12[15]}}, products_payload_values_4_12};
  assign _zz_reduce8_w_values_4_6_1 = {{1{products_payload_values_4_13[15]}}, products_payload_values_4_13};
  assign _zz_reduce8_w_values_4_7 = {{1{products_payload_values_4_14[15]}}, products_payload_values_4_14};
  assign _zz_reduce8_w_values_4_7_1 = {{1{products_payload_values_4_15[15]}}, products_payload_values_4_15};
  assign _zz_reduce8_w_values_5_0 = {{1{products_payload_values_5_0[15]}}, products_payload_values_5_0};
  assign _zz_reduce8_w_values_5_0_1 = {{1{products_payload_values_5_1[15]}}, products_payload_values_5_1};
  assign _zz_reduce8_w_values_5_1 = {{1{products_payload_values_5_2[15]}}, products_payload_values_5_2};
  assign _zz_reduce8_w_values_5_1_1 = {{1{products_payload_values_5_3[15]}}, products_payload_values_5_3};
  assign _zz_reduce8_w_values_5_2 = {{1{products_payload_values_5_4[15]}}, products_payload_values_5_4};
  assign _zz_reduce8_w_values_5_2_1 = {{1{products_payload_values_5_5[15]}}, products_payload_values_5_5};
  assign _zz_reduce8_w_values_5_3 = {{1{products_payload_values_5_6[15]}}, products_payload_values_5_6};
  assign _zz_reduce8_w_values_5_3_1 = {{1{products_payload_values_5_7[15]}}, products_payload_values_5_7};
  assign _zz_reduce8_w_values_5_4 = {{1{products_payload_values_5_8[15]}}, products_payload_values_5_8};
  assign _zz_reduce8_w_values_5_4_1 = {{1{products_payload_values_5_9[15]}}, products_payload_values_5_9};
  assign _zz_reduce8_w_values_5_5 = {{1{products_payload_values_5_10[15]}}, products_payload_values_5_10};
  assign _zz_reduce8_w_values_5_5_1 = {{1{products_payload_values_5_11[15]}}, products_payload_values_5_11};
  assign _zz_reduce8_w_values_5_6 = {{1{products_payload_values_5_12[15]}}, products_payload_values_5_12};
  assign _zz_reduce8_w_values_5_6_1 = {{1{products_payload_values_5_13[15]}}, products_payload_values_5_13};
  assign _zz_reduce8_w_values_5_7 = {{1{products_payload_values_5_14[15]}}, products_payload_values_5_14};
  assign _zz_reduce8_w_values_5_7_1 = {{1{products_payload_values_5_15[15]}}, products_payload_values_5_15};
  assign _zz_reduce8_w_values_6_0 = {{1{products_payload_values_6_0[15]}}, products_payload_values_6_0};
  assign _zz_reduce8_w_values_6_0_1 = {{1{products_payload_values_6_1[15]}}, products_payload_values_6_1};
  assign _zz_reduce8_w_values_6_1 = {{1{products_payload_values_6_2[15]}}, products_payload_values_6_2};
  assign _zz_reduce8_w_values_6_1_1 = {{1{products_payload_values_6_3[15]}}, products_payload_values_6_3};
  assign _zz_reduce8_w_values_6_2 = {{1{products_payload_values_6_4[15]}}, products_payload_values_6_4};
  assign _zz_reduce8_w_values_6_2_1 = {{1{products_payload_values_6_5[15]}}, products_payload_values_6_5};
  assign _zz_reduce8_w_values_6_3 = {{1{products_payload_values_6_6[15]}}, products_payload_values_6_6};
  assign _zz_reduce8_w_values_6_3_1 = {{1{products_payload_values_6_7[15]}}, products_payload_values_6_7};
  assign _zz_reduce8_w_values_6_4 = {{1{products_payload_values_6_8[15]}}, products_payload_values_6_8};
  assign _zz_reduce8_w_values_6_4_1 = {{1{products_payload_values_6_9[15]}}, products_payload_values_6_9};
  assign _zz_reduce8_w_values_6_5 = {{1{products_payload_values_6_10[15]}}, products_payload_values_6_10};
  assign _zz_reduce8_w_values_6_5_1 = {{1{products_payload_values_6_11[15]}}, products_payload_values_6_11};
  assign _zz_reduce8_w_values_6_6 = {{1{products_payload_values_6_12[15]}}, products_payload_values_6_12};
  assign _zz_reduce8_w_values_6_6_1 = {{1{products_payload_values_6_13[15]}}, products_payload_values_6_13};
  assign _zz_reduce8_w_values_6_7 = {{1{products_payload_values_6_14[15]}}, products_payload_values_6_14};
  assign _zz_reduce8_w_values_6_7_1 = {{1{products_payload_values_6_15[15]}}, products_payload_values_6_15};
  assign _zz_reduce8_w_values_7_0 = {{1{products_payload_values_7_0[15]}}, products_payload_values_7_0};
  assign _zz_reduce8_w_values_7_0_1 = {{1{products_payload_values_7_1[15]}}, products_payload_values_7_1};
  assign _zz_reduce8_w_values_7_1 = {{1{products_payload_values_7_2[15]}}, products_payload_values_7_2};
  assign _zz_reduce8_w_values_7_1_1 = {{1{products_payload_values_7_3[15]}}, products_payload_values_7_3};
  assign _zz_reduce8_w_values_7_2 = {{1{products_payload_values_7_4[15]}}, products_payload_values_7_4};
  assign _zz_reduce8_w_values_7_2_1 = {{1{products_payload_values_7_5[15]}}, products_payload_values_7_5};
  assign _zz_reduce8_w_values_7_3 = {{1{products_payload_values_7_6[15]}}, products_payload_values_7_6};
  assign _zz_reduce8_w_values_7_3_1 = {{1{products_payload_values_7_7[15]}}, products_payload_values_7_7};
  assign _zz_reduce8_w_values_7_4 = {{1{products_payload_values_7_8[15]}}, products_payload_values_7_8};
  assign _zz_reduce8_w_values_7_4_1 = {{1{products_payload_values_7_9[15]}}, products_payload_values_7_9};
  assign _zz_reduce8_w_values_7_5 = {{1{products_payload_values_7_10[15]}}, products_payload_values_7_10};
  assign _zz_reduce8_w_values_7_5_1 = {{1{products_payload_values_7_11[15]}}, products_payload_values_7_11};
  assign _zz_reduce8_w_values_7_6 = {{1{products_payload_values_7_12[15]}}, products_payload_values_7_12};
  assign _zz_reduce8_w_values_7_6_1 = {{1{products_payload_values_7_13[15]}}, products_payload_values_7_13};
  assign _zz_reduce8_w_values_7_7 = {{1{products_payload_values_7_14[15]}}, products_payload_values_7_14};
  assign _zz_reduce8_w_values_7_7_1 = {{1{products_payload_values_7_15[15]}}, products_payload_values_7_15};
  assign _zz_reduce8_w_values_8_0 = {{1{products_payload_values_8_0[15]}}, products_payload_values_8_0};
  assign _zz_reduce8_w_values_8_0_1 = {{1{products_payload_values_8_1[15]}}, products_payload_values_8_1};
  assign _zz_reduce8_w_values_8_1 = {{1{products_payload_values_8_2[15]}}, products_payload_values_8_2};
  assign _zz_reduce8_w_values_8_1_1 = {{1{products_payload_values_8_3[15]}}, products_payload_values_8_3};
  assign _zz_reduce8_w_values_8_2 = {{1{products_payload_values_8_4[15]}}, products_payload_values_8_4};
  assign _zz_reduce8_w_values_8_2_1 = {{1{products_payload_values_8_5[15]}}, products_payload_values_8_5};
  assign _zz_reduce8_w_values_8_3 = {{1{products_payload_values_8_6[15]}}, products_payload_values_8_6};
  assign _zz_reduce8_w_values_8_3_1 = {{1{products_payload_values_8_7[15]}}, products_payload_values_8_7};
  assign _zz_reduce8_w_values_8_4 = {{1{products_payload_values_8_8[15]}}, products_payload_values_8_8};
  assign _zz_reduce8_w_values_8_4_1 = {{1{products_payload_values_8_9[15]}}, products_payload_values_8_9};
  assign _zz_reduce8_w_values_8_5 = {{1{products_payload_values_8_10[15]}}, products_payload_values_8_10};
  assign _zz_reduce8_w_values_8_5_1 = {{1{products_payload_values_8_11[15]}}, products_payload_values_8_11};
  assign _zz_reduce8_w_values_8_6 = {{1{products_payload_values_8_12[15]}}, products_payload_values_8_12};
  assign _zz_reduce8_w_values_8_6_1 = {{1{products_payload_values_8_13[15]}}, products_payload_values_8_13};
  assign _zz_reduce8_w_values_8_7 = {{1{products_payload_values_8_14[15]}}, products_payload_values_8_14};
  assign _zz_reduce8_w_values_8_7_1 = {{1{products_payload_values_8_15[15]}}, products_payload_values_8_15};
  assign _zz_reduce8_w_values_9_0 = {{1{products_payload_values_9_0[15]}}, products_payload_values_9_0};
  assign _zz_reduce8_w_values_9_0_1 = {{1{products_payload_values_9_1[15]}}, products_payload_values_9_1};
  assign _zz_reduce8_w_values_9_1 = {{1{products_payload_values_9_2[15]}}, products_payload_values_9_2};
  assign _zz_reduce8_w_values_9_1_1 = {{1{products_payload_values_9_3[15]}}, products_payload_values_9_3};
  assign _zz_reduce8_w_values_9_2 = {{1{products_payload_values_9_4[15]}}, products_payload_values_9_4};
  assign _zz_reduce8_w_values_9_2_1 = {{1{products_payload_values_9_5[15]}}, products_payload_values_9_5};
  assign _zz_reduce8_w_values_9_3 = {{1{products_payload_values_9_6[15]}}, products_payload_values_9_6};
  assign _zz_reduce8_w_values_9_3_1 = {{1{products_payload_values_9_7[15]}}, products_payload_values_9_7};
  assign _zz_reduce8_w_values_9_4 = {{1{products_payload_values_9_8[15]}}, products_payload_values_9_8};
  assign _zz_reduce8_w_values_9_4_1 = {{1{products_payload_values_9_9[15]}}, products_payload_values_9_9};
  assign _zz_reduce8_w_values_9_5 = {{1{products_payload_values_9_10[15]}}, products_payload_values_9_10};
  assign _zz_reduce8_w_values_9_5_1 = {{1{products_payload_values_9_11[15]}}, products_payload_values_9_11};
  assign _zz_reduce8_w_values_9_6 = {{1{products_payload_values_9_12[15]}}, products_payload_values_9_12};
  assign _zz_reduce8_w_values_9_6_1 = {{1{products_payload_values_9_13[15]}}, products_payload_values_9_13};
  assign _zz_reduce8_w_values_9_7 = {{1{products_payload_values_9_14[15]}}, products_payload_values_9_14};
  assign _zz_reduce8_w_values_9_7_1 = {{1{products_payload_values_9_15[15]}}, products_payload_values_9_15};
  assign _zz_reduce8_w_values_10_0 = {{1{products_payload_values_10_0[15]}}, products_payload_values_10_0};
  assign _zz_reduce8_w_values_10_0_1 = {{1{products_payload_values_10_1[15]}}, products_payload_values_10_1};
  assign _zz_reduce8_w_values_10_1 = {{1{products_payload_values_10_2[15]}}, products_payload_values_10_2};
  assign _zz_reduce8_w_values_10_1_1 = {{1{products_payload_values_10_3[15]}}, products_payload_values_10_3};
  assign _zz_reduce8_w_values_10_2 = {{1{products_payload_values_10_4[15]}}, products_payload_values_10_4};
  assign _zz_reduce8_w_values_10_2_1 = {{1{products_payload_values_10_5[15]}}, products_payload_values_10_5};
  assign _zz_reduce8_w_values_10_3 = {{1{products_payload_values_10_6[15]}}, products_payload_values_10_6};
  assign _zz_reduce8_w_values_10_3_1 = {{1{products_payload_values_10_7[15]}}, products_payload_values_10_7};
  assign _zz_reduce8_w_values_10_4 = {{1{products_payload_values_10_8[15]}}, products_payload_values_10_8};
  assign _zz_reduce8_w_values_10_4_1 = {{1{products_payload_values_10_9[15]}}, products_payload_values_10_9};
  assign _zz_reduce8_w_values_10_5 = {{1{products_payload_values_10_10[15]}}, products_payload_values_10_10};
  assign _zz_reduce8_w_values_10_5_1 = {{1{products_payload_values_10_11[15]}}, products_payload_values_10_11};
  assign _zz_reduce8_w_values_10_6 = {{1{products_payload_values_10_12[15]}}, products_payload_values_10_12};
  assign _zz_reduce8_w_values_10_6_1 = {{1{products_payload_values_10_13[15]}}, products_payload_values_10_13};
  assign _zz_reduce8_w_values_10_7 = {{1{products_payload_values_10_14[15]}}, products_payload_values_10_14};
  assign _zz_reduce8_w_values_10_7_1 = {{1{products_payload_values_10_15[15]}}, products_payload_values_10_15};
  assign _zz_reduce8_w_values_11_0 = {{1{products_payload_values_11_0[15]}}, products_payload_values_11_0};
  assign _zz_reduce8_w_values_11_0_1 = {{1{products_payload_values_11_1[15]}}, products_payload_values_11_1};
  assign _zz_reduce8_w_values_11_1 = {{1{products_payload_values_11_2[15]}}, products_payload_values_11_2};
  assign _zz_reduce8_w_values_11_1_1 = {{1{products_payload_values_11_3[15]}}, products_payload_values_11_3};
  assign _zz_reduce8_w_values_11_2 = {{1{products_payload_values_11_4[15]}}, products_payload_values_11_4};
  assign _zz_reduce8_w_values_11_2_1 = {{1{products_payload_values_11_5[15]}}, products_payload_values_11_5};
  assign _zz_reduce8_w_values_11_3 = {{1{products_payload_values_11_6[15]}}, products_payload_values_11_6};
  assign _zz_reduce8_w_values_11_3_1 = {{1{products_payload_values_11_7[15]}}, products_payload_values_11_7};
  assign _zz_reduce8_w_values_11_4 = {{1{products_payload_values_11_8[15]}}, products_payload_values_11_8};
  assign _zz_reduce8_w_values_11_4_1 = {{1{products_payload_values_11_9[15]}}, products_payload_values_11_9};
  assign _zz_reduce8_w_values_11_5 = {{1{products_payload_values_11_10[15]}}, products_payload_values_11_10};
  assign _zz_reduce8_w_values_11_5_1 = {{1{products_payload_values_11_11[15]}}, products_payload_values_11_11};
  assign _zz_reduce8_w_values_11_6 = {{1{products_payload_values_11_12[15]}}, products_payload_values_11_12};
  assign _zz_reduce8_w_values_11_6_1 = {{1{products_payload_values_11_13[15]}}, products_payload_values_11_13};
  assign _zz_reduce8_w_values_11_7 = {{1{products_payload_values_11_14[15]}}, products_payload_values_11_14};
  assign _zz_reduce8_w_values_11_7_1 = {{1{products_payload_values_11_15[15]}}, products_payload_values_11_15};
  assign _zz_reduce8_w_values_12_0 = {{1{products_payload_values_12_0[15]}}, products_payload_values_12_0};
  assign _zz_reduce8_w_values_12_0_1 = {{1{products_payload_values_12_1[15]}}, products_payload_values_12_1};
  assign _zz_reduce8_w_values_12_1 = {{1{products_payload_values_12_2[15]}}, products_payload_values_12_2};
  assign _zz_reduce8_w_values_12_1_1 = {{1{products_payload_values_12_3[15]}}, products_payload_values_12_3};
  assign _zz_reduce8_w_values_12_2 = {{1{products_payload_values_12_4[15]}}, products_payload_values_12_4};
  assign _zz_reduce8_w_values_12_2_1 = {{1{products_payload_values_12_5[15]}}, products_payload_values_12_5};
  assign _zz_reduce8_w_values_12_3 = {{1{products_payload_values_12_6[15]}}, products_payload_values_12_6};
  assign _zz_reduce8_w_values_12_3_1 = {{1{products_payload_values_12_7[15]}}, products_payload_values_12_7};
  assign _zz_reduce8_w_values_12_4 = {{1{products_payload_values_12_8[15]}}, products_payload_values_12_8};
  assign _zz_reduce8_w_values_12_4_1 = {{1{products_payload_values_12_9[15]}}, products_payload_values_12_9};
  assign _zz_reduce8_w_values_12_5 = {{1{products_payload_values_12_10[15]}}, products_payload_values_12_10};
  assign _zz_reduce8_w_values_12_5_1 = {{1{products_payload_values_12_11[15]}}, products_payload_values_12_11};
  assign _zz_reduce8_w_values_12_6 = {{1{products_payload_values_12_12[15]}}, products_payload_values_12_12};
  assign _zz_reduce8_w_values_12_6_1 = {{1{products_payload_values_12_13[15]}}, products_payload_values_12_13};
  assign _zz_reduce8_w_values_12_7 = {{1{products_payload_values_12_14[15]}}, products_payload_values_12_14};
  assign _zz_reduce8_w_values_12_7_1 = {{1{products_payload_values_12_15[15]}}, products_payload_values_12_15};
  assign _zz_reduce8_w_values_13_0 = {{1{products_payload_values_13_0[15]}}, products_payload_values_13_0};
  assign _zz_reduce8_w_values_13_0_1 = {{1{products_payload_values_13_1[15]}}, products_payload_values_13_1};
  assign _zz_reduce8_w_values_13_1 = {{1{products_payload_values_13_2[15]}}, products_payload_values_13_2};
  assign _zz_reduce8_w_values_13_1_1 = {{1{products_payload_values_13_3[15]}}, products_payload_values_13_3};
  assign _zz_reduce8_w_values_13_2 = {{1{products_payload_values_13_4[15]}}, products_payload_values_13_4};
  assign _zz_reduce8_w_values_13_2_1 = {{1{products_payload_values_13_5[15]}}, products_payload_values_13_5};
  assign _zz_reduce8_w_values_13_3 = {{1{products_payload_values_13_6[15]}}, products_payload_values_13_6};
  assign _zz_reduce8_w_values_13_3_1 = {{1{products_payload_values_13_7[15]}}, products_payload_values_13_7};
  assign _zz_reduce8_w_values_13_4 = {{1{products_payload_values_13_8[15]}}, products_payload_values_13_8};
  assign _zz_reduce8_w_values_13_4_1 = {{1{products_payload_values_13_9[15]}}, products_payload_values_13_9};
  assign _zz_reduce8_w_values_13_5 = {{1{products_payload_values_13_10[15]}}, products_payload_values_13_10};
  assign _zz_reduce8_w_values_13_5_1 = {{1{products_payload_values_13_11[15]}}, products_payload_values_13_11};
  assign _zz_reduce8_w_values_13_6 = {{1{products_payload_values_13_12[15]}}, products_payload_values_13_12};
  assign _zz_reduce8_w_values_13_6_1 = {{1{products_payload_values_13_13[15]}}, products_payload_values_13_13};
  assign _zz_reduce8_w_values_13_7 = {{1{products_payload_values_13_14[15]}}, products_payload_values_13_14};
  assign _zz_reduce8_w_values_13_7_1 = {{1{products_payload_values_13_15[15]}}, products_payload_values_13_15};
  assign _zz_reduce8_w_values_14_0 = {{1{products_payload_values_14_0[15]}}, products_payload_values_14_0};
  assign _zz_reduce8_w_values_14_0_1 = {{1{products_payload_values_14_1[15]}}, products_payload_values_14_1};
  assign _zz_reduce8_w_values_14_1 = {{1{products_payload_values_14_2[15]}}, products_payload_values_14_2};
  assign _zz_reduce8_w_values_14_1_1 = {{1{products_payload_values_14_3[15]}}, products_payload_values_14_3};
  assign _zz_reduce8_w_values_14_2 = {{1{products_payload_values_14_4[15]}}, products_payload_values_14_4};
  assign _zz_reduce8_w_values_14_2_1 = {{1{products_payload_values_14_5[15]}}, products_payload_values_14_5};
  assign _zz_reduce8_w_values_14_3 = {{1{products_payload_values_14_6[15]}}, products_payload_values_14_6};
  assign _zz_reduce8_w_values_14_3_1 = {{1{products_payload_values_14_7[15]}}, products_payload_values_14_7};
  assign _zz_reduce8_w_values_14_4 = {{1{products_payload_values_14_8[15]}}, products_payload_values_14_8};
  assign _zz_reduce8_w_values_14_4_1 = {{1{products_payload_values_14_9[15]}}, products_payload_values_14_9};
  assign _zz_reduce8_w_values_14_5 = {{1{products_payload_values_14_10[15]}}, products_payload_values_14_10};
  assign _zz_reduce8_w_values_14_5_1 = {{1{products_payload_values_14_11[15]}}, products_payload_values_14_11};
  assign _zz_reduce8_w_values_14_6 = {{1{products_payload_values_14_12[15]}}, products_payload_values_14_12};
  assign _zz_reduce8_w_values_14_6_1 = {{1{products_payload_values_14_13[15]}}, products_payload_values_14_13};
  assign _zz_reduce8_w_values_14_7 = {{1{products_payload_values_14_14[15]}}, products_payload_values_14_14};
  assign _zz_reduce8_w_values_14_7_1 = {{1{products_payload_values_14_15[15]}}, products_payload_values_14_15};
  assign _zz_reduce8_w_values_15_0 = {{1{products_payload_values_15_0[15]}}, products_payload_values_15_0};
  assign _zz_reduce8_w_values_15_0_1 = {{1{products_payload_values_15_1[15]}}, products_payload_values_15_1};
  assign _zz_reduce8_w_values_15_1 = {{1{products_payload_values_15_2[15]}}, products_payload_values_15_2};
  assign _zz_reduce8_w_values_15_1_1 = {{1{products_payload_values_15_3[15]}}, products_payload_values_15_3};
  assign _zz_reduce8_w_values_15_2 = {{1{products_payload_values_15_4[15]}}, products_payload_values_15_4};
  assign _zz_reduce8_w_values_15_2_1 = {{1{products_payload_values_15_5[15]}}, products_payload_values_15_5};
  assign _zz_reduce8_w_values_15_3 = {{1{products_payload_values_15_6[15]}}, products_payload_values_15_6};
  assign _zz_reduce8_w_values_15_3_1 = {{1{products_payload_values_15_7[15]}}, products_payload_values_15_7};
  assign _zz_reduce8_w_values_15_4 = {{1{products_payload_values_15_8[15]}}, products_payload_values_15_8};
  assign _zz_reduce8_w_values_15_4_1 = {{1{products_payload_values_15_9[15]}}, products_payload_values_15_9};
  assign _zz_reduce8_w_values_15_5 = {{1{products_payload_values_15_10[15]}}, products_payload_values_15_10};
  assign _zz_reduce8_w_values_15_5_1 = {{1{products_payload_values_15_11[15]}}, products_payload_values_15_11};
  assign _zz_reduce8_w_values_15_6 = {{1{products_payload_values_15_12[15]}}, products_payload_values_15_12};
  assign _zz_reduce8_w_values_15_6_1 = {{1{products_payload_values_15_13[15]}}, products_payload_values_15_13};
  assign _zz_reduce8_w_values_15_7 = {{1{products_payload_values_15_14[15]}}, products_payload_values_15_14};
  assign _zz_reduce8_w_values_15_7_1 = {{1{products_payload_values_15_15[15]}}, products_payload_values_15_15};
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
  assign _zz_reduce4_w_values_4_0 = {{1{reduce8_payload_values_4_0[16]}}, reduce8_payload_values_4_0};
  assign _zz_reduce4_w_values_4_0_1 = {{1{reduce8_payload_values_4_1[16]}}, reduce8_payload_values_4_1};
  assign _zz_reduce4_w_values_4_1 = {{1{reduce8_payload_values_4_2[16]}}, reduce8_payload_values_4_2};
  assign _zz_reduce4_w_values_4_1_1 = {{1{reduce8_payload_values_4_3[16]}}, reduce8_payload_values_4_3};
  assign _zz_reduce4_w_values_4_2 = {{1{reduce8_payload_values_4_4[16]}}, reduce8_payload_values_4_4};
  assign _zz_reduce4_w_values_4_2_1 = {{1{reduce8_payload_values_4_5[16]}}, reduce8_payload_values_4_5};
  assign _zz_reduce4_w_values_4_3 = {{1{reduce8_payload_values_4_6[16]}}, reduce8_payload_values_4_6};
  assign _zz_reduce4_w_values_4_3_1 = {{1{reduce8_payload_values_4_7[16]}}, reduce8_payload_values_4_7};
  assign _zz_reduce4_w_values_5_0 = {{1{reduce8_payload_values_5_0[16]}}, reduce8_payload_values_5_0};
  assign _zz_reduce4_w_values_5_0_1 = {{1{reduce8_payload_values_5_1[16]}}, reduce8_payload_values_5_1};
  assign _zz_reduce4_w_values_5_1 = {{1{reduce8_payload_values_5_2[16]}}, reduce8_payload_values_5_2};
  assign _zz_reduce4_w_values_5_1_1 = {{1{reduce8_payload_values_5_3[16]}}, reduce8_payload_values_5_3};
  assign _zz_reduce4_w_values_5_2 = {{1{reduce8_payload_values_5_4[16]}}, reduce8_payload_values_5_4};
  assign _zz_reduce4_w_values_5_2_1 = {{1{reduce8_payload_values_5_5[16]}}, reduce8_payload_values_5_5};
  assign _zz_reduce4_w_values_5_3 = {{1{reduce8_payload_values_5_6[16]}}, reduce8_payload_values_5_6};
  assign _zz_reduce4_w_values_5_3_1 = {{1{reduce8_payload_values_5_7[16]}}, reduce8_payload_values_5_7};
  assign _zz_reduce4_w_values_6_0 = {{1{reduce8_payload_values_6_0[16]}}, reduce8_payload_values_6_0};
  assign _zz_reduce4_w_values_6_0_1 = {{1{reduce8_payload_values_6_1[16]}}, reduce8_payload_values_6_1};
  assign _zz_reduce4_w_values_6_1 = {{1{reduce8_payload_values_6_2[16]}}, reduce8_payload_values_6_2};
  assign _zz_reduce4_w_values_6_1_1 = {{1{reduce8_payload_values_6_3[16]}}, reduce8_payload_values_6_3};
  assign _zz_reduce4_w_values_6_2 = {{1{reduce8_payload_values_6_4[16]}}, reduce8_payload_values_6_4};
  assign _zz_reduce4_w_values_6_2_1 = {{1{reduce8_payload_values_6_5[16]}}, reduce8_payload_values_6_5};
  assign _zz_reduce4_w_values_6_3 = {{1{reduce8_payload_values_6_6[16]}}, reduce8_payload_values_6_6};
  assign _zz_reduce4_w_values_6_3_1 = {{1{reduce8_payload_values_6_7[16]}}, reduce8_payload_values_6_7};
  assign _zz_reduce4_w_values_7_0 = {{1{reduce8_payload_values_7_0[16]}}, reduce8_payload_values_7_0};
  assign _zz_reduce4_w_values_7_0_1 = {{1{reduce8_payload_values_7_1[16]}}, reduce8_payload_values_7_1};
  assign _zz_reduce4_w_values_7_1 = {{1{reduce8_payload_values_7_2[16]}}, reduce8_payload_values_7_2};
  assign _zz_reduce4_w_values_7_1_1 = {{1{reduce8_payload_values_7_3[16]}}, reduce8_payload_values_7_3};
  assign _zz_reduce4_w_values_7_2 = {{1{reduce8_payload_values_7_4[16]}}, reduce8_payload_values_7_4};
  assign _zz_reduce4_w_values_7_2_1 = {{1{reduce8_payload_values_7_5[16]}}, reduce8_payload_values_7_5};
  assign _zz_reduce4_w_values_7_3 = {{1{reduce8_payload_values_7_6[16]}}, reduce8_payload_values_7_6};
  assign _zz_reduce4_w_values_7_3_1 = {{1{reduce8_payload_values_7_7[16]}}, reduce8_payload_values_7_7};
  assign _zz_reduce4_w_values_8_0 = {{1{reduce8_payload_values_8_0[16]}}, reduce8_payload_values_8_0};
  assign _zz_reduce4_w_values_8_0_1 = {{1{reduce8_payload_values_8_1[16]}}, reduce8_payload_values_8_1};
  assign _zz_reduce4_w_values_8_1 = {{1{reduce8_payload_values_8_2[16]}}, reduce8_payload_values_8_2};
  assign _zz_reduce4_w_values_8_1_1 = {{1{reduce8_payload_values_8_3[16]}}, reduce8_payload_values_8_3};
  assign _zz_reduce4_w_values_8_2 = {{1{reduce8_payload_values_8_4[16]}}, reduce8_payload_values_8_4};
  assign _zz_reduce4_w_values_8_2_1 = {{1{reduce8_payload_values_8_5[16]}}, reduce8_payload_values_8_5};
  assign _zz_reduce4_w_values_8_3 = {{1{reduce8_payload_values_8_6[16]}}, reduce8_payload_values_8_6};
  assign _zz_reduce4_w_values_8_3_1 = {{1{reduce8_payload_values_8_7[16]}}, reduce8_payload_values_8_7};
  assign _zz_reduce4_w_values_9_0 = {{1{reduce8_payload_values_9_0[16]}}, reduce8_payload_values_9_0};
  assign _zz_reduce4_w_values_9_0_1 = {{1{reduce8_payload_values_9_1[16]}}, reduce8_payload_values_9_1};
  assign _zz_reduce4_w_values_9_1 = {{1{reduce8_payload_values_9_2[16]}}, reduce8_payload_values_9_2};
  assign _zz_reduce4_w_values_9_1_1 = {{1{reduce8_payload_values_9_3[16]}}, reduce8_payload_values_9_3};
  assign _zz_reduce4_w_values_9_2 = {{1{reduce8_payload_values_9_4[16]}}, reduce8_payload_values_9_4};
  assign _zz_reduce4_w_values_9_2_1 = {{1{reduce8_payload_values_9_5[16]}}, reduce8_payload_values_9_5};
  assign _zz_reduce4_w_values_9_3 = {{1{reduce8_payload_values_9_6[16]}}, reduce8_payload_values_9_6};
  assign _zz_reduce4_w_values_9_3_1 = {{1{reduce8_payload_values_9_7[16]}}, reduce8_payload_values_9_7};
  assign _zz_reduce4_w_values_10_0 = {{1{reduce8_payload_values_10_0[16]}}, reduce8_payload_values_10_0};
  assign _zz_reduce4_w_values_10_0_1 = {{1{reduce8_payload_values_10_1[16]}}, reduce8_payload_values_10_1};
  assign _zz_reduce4_w_values_10_1 = {{1{reduce8_payload_values_10_2[16]}}, reduce8_payload_values_10_2};
  assign _zz_reduce4_w_values_10_1_1 = {{1{reduce8_payload_values_10_3[16]}}, reduce8_payload_values_10_3};
  assign _zz_reduce4_w_values_10_2 = {{1{reduce8_payload_values_10_4[16]}}, reduce8_payload_values_10_4};
  assign _zz_reduce4_w_values_10_2_1 = {{1{reduce8_payload_values_10_5[16]}}, reduce8_payload_values_10_5};
  assign _zz_reduce4_w_values_10_3 = {{1{reduce8_payload_values_10_6[16]}}, reduce8_payload_values_10_6};
  assign _zz_reduce4_w_values_10_3_1 = {{1{reduce8_payload_values_10_7[16]}}, reduce8_payload_values_10_7};
  assign _zz_reduce4_w_values_11_0 = {{1{reduce8_payload_values_11_0[16]}}, reduce8_payload_values_11_0};
  assign _zz_reduce4_w_values_11_0_1 = {{1{reduce8_payload_values_11_1[16]}}, reduce8_payload_values_11_1};
  assign _zz_reduce4_w_values_11_1 = {{1{reduce8_payload_values_11_2[16]}}, reduce8_payload_values_11_2};
  assign _zz_reduce4_w_values_11_1_1 = {{1{reduce8_payload_values_11_3[16]}}, reduce8_payload_values_11_3};
  assign _zz_reduce4_w_values_11_2 = {{1{reduce8_payload_values_11_4[16]}}, reduce8_payload_values_11_4};
  assign _zz_reduce4_w_values_11_2_1 = {{1{reduce8_payload_values_11_5[16]}}, reduce8_payload_values_11_5};
  assign _zz_reduce4_w_values_11_3 = {{1{reduce8_payload_values_11_6[16]}}, reduce8_payload_values_11_6};
  assign _zz_reduce4_w_values_11_3_1 = {{1{reduce8_payload_values_11_7[16]}}, reduce8_payload_values_11_7};
  assign _zz_reduce4_w_values_12_0 = {{1{reduce8_payload_values_12_0[16]}}, reduce8_payload_values_12_0};
  assign _zz_reduce4_w_values_12_0_1 = {{1{reduce8_payload_values_12_1[16]}}, reduce8_payload_values_12_1};
  assign _zz_reduce4_w_values_12_1 = {{1{reduce8_payload_values_12_2[16]}}, reduce8_payload_values_12_2};
  assign _zz_reduce4_w_values_12_1_1 = {{1{reduce8_payload_values_12_3[16]}}, reduce8_payload_values_12_3};
  assign _zz_reduce4_w_values_12_2 = {{1{reduce8_payload_values_12_4[16]}}, reduce8_payload_values_12_4};
  assign _zz_reduce4_w_values_12_2_1 = {{1{reduce8_payload_values_12_5[16]}}, reduce8_payload_values_12_5};
  assign _zz_reduce4_w_values_12_3 = {{1{reduce8_payload_values_12_6[16]}}, reduce8_payload_values_12_6};
  assign _zz_reduce4_w_values_12_3_1 = {{1{reduce8_payload_values_12_7[16]}}, reduce8_payload_values_12_7};
  assign _zz_reduce4_w_values_13_0 = {{1{reduce8_payload_values_13_0[16]}}, reduce8_payload_values_13_0};
  assign _zz_reduce4_w_values_13_0_1 = {{1{reduce8_payload_values_13_1[16]}}, reduce8_payload_values_13_1};
  assign _zz_reduce4_w_values_13_1 = {{1{reduce8_payload_values_13_2[16]}}, reduce8_payload_values_13_2};
  assign _zz_reduce4_w_values_13_1_1 = {{1{reduce8_payload_values_13_3[16]}}, reduce8_payload_values_13_3};
  assign _zz_reduce4_w_values_13_2 = {{1{reduce8_payload_values_13_4[16]}}, reduce8_payload_values_13_4};
  assign _zz_reduce4_w_values_13_2_1 = {{1{reduce8_payload_values_13_5[16]}}, reduce8_payload_values_13_5};
  assign _zz_reduce4_w_values_13_3 = {{1{reduce8_payload_values_13_6[16]}}, reduce8_payload_values_13_6};
  assign _zz_reduce4_w_values_13_3_1 = {{1{reduce8_payload_values_13_7[16]}}, reduce8_payload_values_13_7};
  assign _zz_reduce4_w_values_14_0 = {{1{reduce8_payload_values_14_0[16]}}, reduce8_payload_values_14_0};
  assign _zz_reduce4_w_values_14_0_1 = {{1{reduce8_payload_values_14_1[16]}}, reduce8_payload_values_14_1};
  assign _zz_reduce4_w_values_14_1 = {{1{reduce8_payload_values_14_2[16]}}, reduce8_payload_values_14_2};
  assign _zz_reduce4_w_values_14_1_1 = {{1{reduce8_payload_values_14_3[16]}}, reduce8_payload_values_14_3};
  assign _zz_reduce4_w_values_14_2 = {{1{reduce8_payload_values_14_4[16]}}, reduce8_payload_values_14_4};
  assign _zz_reduce4_w_values_14_2_1 = {{1{reduce8_payload_values_14_5[16]}}, reduce8_payload_values_14_5};
  assign _zz_reduce4_w_values_14_3 = {{1{reduce8_payload_values_14_6[16]}}, reduce8_payload_values_14_6};
  assign _zz_reduce4_w_values_14_3_1 = {{1{reduce8_payload_values_14_7[16]}}, reduce8_payload_values_14_7};
  assign _zz_reduce4_w_values_15_0 = {{1{reduce8_payload_values_15_0[16]}}, reduce8_payload_values_15_0};
  assign _zz_reduce4_w_values_15_0_1 = {{1{reduce8_payload_values_15_1[16]}}, reduce8_payload_values_15_1};
  assign _zz_reduce4_w_values_15_1 = {{1{reduce8_payload_values_15_2[16]}}, reduce8_payload_values_15_2};
  assign _zz_reduce4_w_values_15_1_1 = {{1{reduce8_payload_values_15_3[16]}}, reduce8_payload_values_15_3};
  assign _zz_reduce4_w_values_15_2 = {{1{reduce8_payload_values_15_4[16]}}, reduce8_payload_values_15_4};
  assign _zz_reduce4_w_values_15_2_1 = {{1{reduce8_payload_values_15_5[16]}}, reduce8_payload_values_15_5};
  assign _zz_reduce4_w_values_15_3 = {{1{reduce8_payload_values_15_6[16]}}, reduce8_payload_values_15_6};
  assign _zz_reduce4_w_values_15_3_1 = {{1{reduce8_payload_values_15_7[16]}}, reduce8_payload_values_15_7};
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
  assign _zz_reduce2_w_values_4_0 = {{1{reduce4_payload_values_4_0[17]}}, reduce4_payload_values_4_0};
  assign _zz_reduce2_w_values_4_0_1 = {{1{reduce4_payload_values_4_1[17]}}, reduce4_payload_values_4_1};
  assign _zz_reduce2_w_values_4_1 = {{1{reduce4_payload_values_4_2[17]}}, reduce4_payload_values_4_2};
  assign _zz_reduce2_w_values_4_1_1 = {{1{reduce4_payload_values_4_3[17]}}, reduce4_payload_values_4_3};
  assign _zz_reduce2_w_values_5_0 = {{1{reduce4_payload_values_5_0[17]}}, reduce4_payload_values_5_0};
  assign _zz_reduce2_w_values_5_0_1 = {{1{reduce4_payload_values_5_1[17]}}, reduce4_payload_values_5_1};
  assign _zz_reduce2_w_values_5_1 = {{1{reduce4_payload_values_5_2[17]}}, reduce4_payload_values_5_2};
  assign _zz_reduce2_w_values_5_1_1 = {{1{reduce4_payload_values_5_3[17]}}, reduce4_payload_values_5_3};
  assign _zz_reduce2_w_values_6_0 = {{1{reduce4_payload_values_6_0[17]}}, reduce4_payload_values_6_0};
  assign _zz_reduce2_w_values_6_0_1 = {{1{reduce4_payload_values_6_1[17]}}, reduce4_payload_values_6_1};
  assign _zz_reduce2_w_values_6_1 = {{1{reduce4_payload_values_6_2[17]}}, reduce4_payload_values_6_2};
  assign _zz_reduce2_w_values_6_1_1 = {{1{reduce4_payload_values_6_3[17]}}, reduce4_payload_values_6_3};
  assign _zz_reduce2_w_values_7_0 = {{1{reduce4_payload_values_7_0[17]}}, reduce4_payload_values_7_0};
  assign _zz_reduce2_w_values_7_0_1 = {{1{reduce4_payload_values_7_1[17]}}, reduce4_payload_values_7_1};
  assign _zz_reduce2_w_values_7_1 = {{1{reduce4_payload_values_7_2[17]}}, reduce4_payload_values_7_2};
  assign _zz_reduce2_w_values_7_1_1 = {{1{reduce4_payload_values_7_3[17]}}, reduce4_payload_values_7_3};
  assign _zz_reduce2_w_values_8_0 = {{1{reduce4_payload_values_8_0[17]}}, reduce4_payload_values_8_0};
  assign _zz_reduce2_w_values_8_0_1 = {{1{reduce4_payload_values_8_1[17]}}, reduce4_payload_values_8_1};
  assign _zz_reduce2_w_values_8_1 = {{1{reduce4_payload_values_8_2[17]}}, reduce4_payload_values_8_2};
  assign _zz_reduce2_w_values_8_1_1 = {{1{reduce4_payload_values_8_3[17]}}, reduce4_payload_values_8_3};
  assign _zz_reduce2_w_values_9_0 = {{1{reduce4_payload_values_9_0[17]}}, reduce4_payload_values_9_0};
  assign _zz_reduce2_w_values_9_0_1 = {{1{reduce4_payload_values_9_1[17]}}, reduce4_payload_values_9_1};
  assign _zz_reduce2_w_values_9_1 = {{1{reduce4_payload_values_9_2[17]}}, reduce4_payload_values_9_2};
  assign _zz_reduce2_w_values_9_1_1 = {{1{reduce4_payload_values_9_3[17]}}, reduce4_payload_values_9_3};
  assign _zz_reduce2_w_values_10_0 = {{1{reduce4_payload_values_10_0[17]}}, reduce4_payload_values_10_0};
  assign _zz_reduce2_w_values_10_0_1 = {{1{reduce4_payload_values_10_1[17]}}, reduce4_payload_values_10_1};
  assign _zz_reduce2_w_values_10_1 = {{1{reduce4_payload_values_10_2[17]}}, reduce4_payload_values_10_2};
  assign _zz_reduce2_w_values_10_1_1 = {{1{reduce4_payload_values_10_3[17]}}, reduce4_payload_values_10_3};
  assign _zz_reduce2_w_values_11_0 = {{1{reduce4_payload_values_11_0[17]}}, reduce4_payload_values_11_0};
  assign _zz_reduce2_w_values_11_0_1 = {{1{reduce4_payload_values_11_1[17]}}, reduce4_payload_values_11_1};
  assign _zz_reduce2_w_values_11_1 = {{1{reduce4_payload_values_11_2[17]}}, reduce4_payload_values_11_2};
  assign _zz_reduce2_w_values_11_1_1 = {{1{reduce4_payload_values_11_3[17]}}, reduce4_payload_values_11_3};
  assign _zz_reduce2_w_values_12_0 = {{1{reduce4_payload_values_12_0[17]}}, reduce4_payload_values_12_0};
  assign _zz_reduce2_w_values_12_0_1 = {{1{reduce4_payload_values_12_1[17]}}, reduce4_payload_values_12_1};
  assign _zz_reduce2_w_values_12_1 = {{1{reduce4_payload_values_12_2[17]}}, reduce4_payload_values_12_2};
  assign _zz_reduce2_w_values_12_1_1 = {{1{reduce4_payload_values_12_3[17]}}, reduce4_payload_values_12_3};
  assign _zz_reduce2_w_values_13_0 = {{1{reduce4_payload_values_13_0[17]}}, reduce4_payload_values_13_0};
  assign _zz_reduce2_w_values_13_0_1 = {{1{reduce4_payload_values_13_1[17]}}, reduce4_payload_values_13_1};
  assign _zz_reduce2_w_values_13_1 = {{1{reduce4_payload_values_13_2[17]}}, reduce4_payload_values_13_2};
  assign _zz_reduce2_w_values_13_1_1 = {{1{reduce4_payload_values_13_3[17]}}, reduce4_payload_values_13_3};
  assign _zz_reduce2_w_values_14_0 = {{1{reduce4_payload_values_14_0[17]}}, reduce4_payload_values_14_0};
  assign _zz_reduce2_w_values_14_0_1 = {{1{reduce4_payload_values_14_1[17]}}, reduce4_payload_values_14_1};
  assign _zz_reduce2_w_values_14_1 = {{1{reduce4_payload_values_14_2[17]}}, reduce4_payload_values_14_2};
  assign _zz_reduce2_w_values_14_1_1 = {{1{reduce4_payload_values_14_3[17]}}, reduce4_payload_values_14_3};
  assign _zz_reduce2_w_values_15_0 = {{1{reduce4_payload_values_15_0[17]}}, reduce4_payload_values_15_0};
  assign _zz_reduce2_w_values_15_0_1 = {{1{reduce4_payload_values_15_1[17]}}, reduce4_payload_values_15_1};
  assign _zz_reduce2_w_values_15_1 = {{1{reduce4_payload_values_15_2[17]}}, reduce4_payload_values_15_2};
  assign _zz_reduce2_w_values_15_1_1 = {{1{reduce4_payload_values_15_3[17]}}, reduce4_payload_values_15_3};
  assign _zz_dot_w_values_0_0 = {{1{reduce2_payload_values_0_0[18]}}, reduce2_payload_values_0_0};
  assign _zz_dot_w_values_0_0_1 = {{1{reduce2_payload_values_0_1[18]}}, reduce2_payload_values_0_1};
  assign _zz_dot_w_values_1_0 = {{1{reduce2_payload_values_1_0[18]}}, reduce2_payload_values_1_0};
  assign _zz_dot_w_values_1_0_1 = {{1{reduce2_payload_values_1_1[18]}}, reduce2_payload_values_1_1};
  assign _zz_dot_w_values_2_0 = {{1{reduce2_payload_values_2_0[18]}}, reduce2_payload_values_2_0};
  assign _zz_dot_w_values_2_0_1 = {{1{reduce2_payload_values_2_1[18]}}, reduce2_payload_values_2_1};
  assign _zz_dot_w_values_3_0 = {{1{reduce2_payload_values_3_0[18]}}, reduce2_payload_values_3_0};
  assign _zz_dot_w_values_3_0_1 = {{1{reduce2_payload_values_3_1[18]}}, reduce2_payload_values_3_1};
  assign _zz_dot_w_values_4_0 = {{1{reduce2_payload_values_4_0[18]}}, reduce2_payload_values_4_0};
  assign _zz_dot_w_values_4_0_1 = {{1{reduce2_payload_values_4_1[18]}}, reduce2_payload_values_4_1};
  assign _zz_dot_w_values_5_0 = {{1{reduce2_payload_values_5_0[18]}}, reduce2_payload_values_5_0};
  assign _zz_dot_w_values_5_0_1 = {{1{reduce2_payload_values_5_1[18]}}, reduce2_payload_values_5_1};
  assign _zz_dot_w_values_6_0 = {{1{reduce2_payload_values_6_0[18]}}, reduce2_payload_values_6_0};
  assign _zz_dot_w_values_6_0_1 = {{1{reduce2_payload_values_6_1[18]}}, reduce2_payload_values_6_1};
  assign _zz_dot_w_values_7_0 = {{1{reduce2_payload_values_7_0[18]}}, reduce2_payload_values_7_0};
  assign _zz_dot_w_values_7_0_1 = {{1{reduce2_payload_values_7_1[18]}}, reduce2_payload_values_7_1};
  assign _zz_dot_w_values_8_0 = {{1{reduce2_payload_values_8_0[18]}}, reduce2_payload_values_8_0};
  assign _zz_dot_w_values_8_0_1 = {{1{reduce2_payload_values_8_1[18]}}, reduce2_payload_values_8_1};
  assign _zz_dot_w_values_9_0 = {{1{reduce2_payload_values_9_0[18]}}, reduce2_payload_values_9_0};
  assign _zz_dot_w_values_9_0_1 = {{1{reduce2_payload_values_9_1[18]}}, reduce2_payload_values_9_1};
  assign _zz_dot_w_values_10_0 = {{1{reduce2_payload_values_10_0[18]}}, reduce2_payload_values_10_0};
  assign _zz_dot_w_values_10_0_1 = {{1{reduce2_payload_values_10_1[18]}}, reduce2_payload_values_10_1};
  assign _zz_dot_w_values_11_0 = {{1{reduce2_payload_values_11_0[18]}}, reduce2_payload_values_11_0};
  assign _zz_dot_w_values_11_0_1 = {{1{reduce2_payload_values_11_1[18]}}, reduce2_payload_values_11_1};
  assign _zz_dot_w_values_12_0 = {{1{reduce2_payload_values_12_0[18]}}, reduce2_payload_values_12_0};
  assign _zz_dot_w_values_12_0_1 = {{1{reduce2_payload_values_12_1[18]}}, reduce2_payload_values_12_1};
  assign _zz_dot_w_values_13_0 = {{1{reduce2_payload_values_13_0[18]}}, reduce2_payload_values_13_0};
  assign _zz_dot_w_values_13_0_1 = {{1{reduce2_payload_values_13_1[18]}}, reduce2_payload_values_13_1};
  assign _zz_dot_w_values_14_0 = {{1{reduce2_payload_values_14_0[18]}}, reduce2_payload_values_14_0};
  assign _zz_dot_w_values_14_0_1 = {{1{reduce2_payload_values_14_1[18]}}, reduce2_payload_values_14_1};
  assign _zz_dot_w_values_15_0 = {{1{reduce2_payload_values_15_0[18]}}, reduce2_payload_values_15_0};
  assign _zz_dot_w_values_15_0_1 = {{1{reduce2_payload_values_15_1[18]}}, reduce2_payload_values_15_1};
  assign _zz__zz_acc_r_0_0 = (dot_payload_tag_first ? 32'h0 : _zz__zz_acc_r_0_0_1);
  assign _zz__zz_acc_r_0_0_2 = {{12{dot_payload_values_0_0[19]}}, dot_payload_values_0_0};
  assign _zz__zz_acc_r_1_0 = (dot_payload_tag_first ? 32'h0 : _zz__zz_acc_r_1_0_1);
  assign _zz__zz_acc_r_1_0_2 = {{12{dot_payload_values_1_0[19]}}, dot_payload_values_1_0};
  assign _zz__zz_acc_r_2_0 = (dot_payload_tag_first ? 32'h0 : _zz__zz_acc_r_2_0_1);
  assign _zz__zz_acc_r_2_0_2 = {{12{dot_payload_values_2_0[19]}}, dot_payload_values_2_0};
  assign _zz__zz_acc_r_3_0 = (dot_payload_tag_first ? 32'h0 : _zz__zz_acc_r_3_0_1);
  assign _zz__zz_acc_r_3_0_2 = {{12{dot_payload_values_3_0[19]}}, dot_payload_values_3_0};
  assign _zz__zz_acc_r_4_0 = (dot_payload_tag_first ? 32'h0 : _zz__zz_acc_r_4_0_1);
  assign _zz__zz_acc_r_4_0_2 = {{12{dot_payload_values_4_0[19]}}, dot_payload_values_4_0};
  assign _zz__zz_acc_r_5_0 = (dot_payload_tag_first ? 32'h0 : _zz__zz_acc_r_5_0_1);
  assign _zz__zz_acc_r_5_0_2 = {{12{dot_payload_values_5_0[19]}}, dot_payload_values_5_0};
  assign _zz__zz_acc_r_6_0 = (dot_payload_tag_first ? 32'h0 : _zz__zz_acc_r_6_0_1);
  assign _zz__zz_acc_r_6_0_2 = {{12{dot_payload_values_6_0[19]}}, dot_payload_values_6_0};
  assign _zz__zz_acc_r_7_0 = (dot_payload_tag_first ? 32'h0 : _zz__zz_acc_r_7_0_1);
  assign _zz__zz_acc_r_7_0_2 = {{12{dot_payload_values_7_0[19]}}, dot_payload_values_7_0};
  assign _zz__zz_acc_r_8_0 = (dot_payload_tag_first ? 32'h0 : _zz__zz_acc_r_8_0_1);
  assign _zz__zz_acc_r_8_0_2 = {{12{dot_payload_values_8_0[19]}}, dot_payload_values_8_0};
  assign _zz__zz_acc_r_9_0 = (dot_payload_tag_first ? 32'h0 : _zz__zz_acc_r_9_0_1);
  assign _zz__zz_acc_r_9_0_2 = {{12{dot_payload_values_9_0[19]}}, dot_payload_values_9_0};
  assign _zz__zz_acc_r_10_0 = (dot_payload_tag_first ? 32'h0 : _zz__zz_acc_r_10_0_1);
  assign _zz__zz_acc_r_10_0_2 = {{12{dot_payload_values_10_0[19]}}, dot_payload_values_10_0};
  assign _zz__zz_acc_r_11_0 = (dot_payload_tag_first ? 32'h0 : _zz__zz_acc_r_11_0_1);
  assign _zz__zz_acc_r_11_0_2 = {{12{dot_payload_values_11_0[19]}}, dot_payload_values_11_0};
  assign _zz__zz_acc_r_12_0 = (dot_payload_tag_first ? 32'h0 : _zz__zz_acc_r_12_0_1);
  assign _zz__zz_acc_r_12_0_2 = {{12{dot_payload_values_12_0[19]}}, dot_payload_values_12_0};
  assign _zz__zz_acc_r_13_0 = (dot_payload_tag_first ? 32'h0 : _zz__zz_acc_r_13_0_1);
  assign _zz__zz_acc_r_13_0_2 = {{12{dot_payload_values_13_0[19]}}, dot_payload_values_13_0};
  assign _zz__zz_acc_r_14_0 = (dot_payload_tag_first ? 32'h0 : _zz__zz_acc_r_14_0_1);
  assign _zz__zz_acc_r_14_0_2 = {{12{dot_payload_values_14_0[19]}}, dot_payload_values_14_0};
  assign _zz__zz_acc_r_15_0 = (dot_payload_tag_first ? 32'h0 : _zz__zz_acc_r_15_0_1);
  assign _zz__zz_acc_r_15_0_2 = {{12{dot_payload_values_15_0[19]}}, dot_payload_values_15_0};
  assign _zz__zz_serialGroupCount_r_1 = (_zz__zz_serialGroupCount_r_2 >>> 2'd2);
  assign _zz__zz_serialGroupCount_r = {5'd0, _zz__zz_serialGroupCount_r_1};
  assign _zz__zz_serialGroupCount_r_2 = (run_r_cout + 10'h003);
  assign _zz__zz_serialGroupCount_r_3 = (_zz__zz_serialGroupCount_r_4 * 3'b100);
  assign _zz__zz_serialGroupCount_r_4 = {5'd0, issueGroup_r};
  assign _zz_serialGroupCount_r_1 = _zz_serialGroupCount_r[2:0];
  assign _zz_quantRequest_payload_tag_pixel = {14'd0, serialPixel_r};
  assign _zz_quantRequest_payload_tag_group = (_zz_quantRequest_payload_tag_group_1 + _zz_quantRequest_payload_tag_group_3);
  assign _zz_quantRequest_payload_tag_group_1 = (_zz_quantRequest_payload_tag_group_2 * 3'b100);
  assign _zz_quantRequest_payload_tag_group_2 = {5'd0, issueGroup_r};
  assign _zz_quantRequest_payload_tag_group_3 = {11'd0, serialGroup_r};
  assign _zz_quantRequest_payload_tag_mask = (_zz_quantRequest_payload_tag_mask_1 + 13'h0);
  assign _zz_quantRequest_payload_tag_mask_1 = (_zz_quantRequest_payload_tag_mask_2 * 3'b100);
  assign _zz_quantRequest_payload_tag_mask_2 = {3'd0, quantRequest_payload_tag_group};
  assign _zz_quantRequest_payload_tag_mask_3 = {3'd0, run_r_cout};
  assign _zz_quantRequest_payload_mac_0_2 = serialPixel_r[3:0];
  assign _zz_quantRequest_payload_tag_mask_4 = (_zz_quantRequest_payload_tag_mask_5 + 13'h0001);
  assign _zz_quantRequest_payload_tag_mask_5 = (_zz_quantRequest_payload_tag_mask_6 * 3'b100);
  assign _zz_quantRequest_payload_tag_mask_6 = {3'd0, quantRequest_payload_tag_group};
  assign _zz_quantRequest_payload_tag_mask_7 = {3'd0, run_r_cout};
  assign _zz_quantRequest_payload_mac_1_2 = serialPixel_r[3:0];
  assign _zz_quantRequest_payload_tag_mask_8 = (_zz_quantRequest_payload_tag_mask_9 + 13'h0002);
  assign _zz_quantRequest_payload_tag_mask_9 = (_zz_quantRequest_payload_tag_mask_10 * 3'b100);
  assign _zz_quantRequest_payload_tag_mask_10 = {3'd0, quantRequest_payload_tag_group};
  assign _zz_quantRequest_payload_tag_mask_11 = {3'd0, run_r_cout};
  assign _zz_quantRequest_payload_mac_2_2 = serialPixel_r[3:0];
  assign _zz_quantRequest_payload_tag_mask_12 = (_zz_quantRequest_payload_tag_mask_13 + 13'h0003);
  assign _zz_quantRequest_payload_tag_mask_13 = (_zz_quantRequest_payload_tag_mask_14 * 3'b100);
  assign _zz_quantRequest_payload_tag_mask_14 = {3'd0, quantRequest_payload_tag_group};
  assign _zz_quantRequest_payload_tag_mask_15 = {3'd0, run_r_cout};
  assign _zz_quantRequest_payload_mac_3_2 = serialPixel_r[3:0];
  assign _zz_quantRequest_payload_tag_tileLast = {1'd0, serialGroup_r};
  assign _zz_quantRequest_payload_tag_tileLast_1 = (serialGroupCount_r - 3'b001);
  assign _zz_quantRequest_payload_tag_tileLast_2 = (tileCount_r - 5'h01);
  assign _zz_quantRequest_payload_tag_last = {1'd0, issueGroup_r};
  assign _zz_quantRequest_payload_tag_last_1 = (ogCount_r - 6'h01);
  assign _zz_quantRequest_payload_tag_last_2 = (tileBase_r + _zz_quantRequest_payload_tag_last_3);
  assign _zz_quantRequest_payload_tag_last_3 = {14'd0, tileCount_r};
  assign _zz_when_PwMac_l442 = (tileCount_r - 5'h01);
  assign _zz_when_PwMac_l444 = {1'd0, serialGroup_r};
  assign _zz_when_PwMac_l444_1 = (serialGroupCount_r - 3'b001);
  assign _zz_paramMemory_port = paramGroup_r[6:0];
  assign _zz_when_PwMac_l483_1 = (_zz_when_PwMac_l483_2 - 13'h0001);
  assign _zz_when_PwMac_l483 = _zz_when_PwMac_l483_1[6:0];
  assign _zz_when_PwMac_l483_2 = (_zz_when_PwMac_l483_3 + _zz_when_PwMac_l483_5);
  assign _zz_when_PwMac_l483_3 = (_zz_when_PwMac_l483_4 * 3'b100);
  assign _zz_when_PwMac_l483_4 = {5'd0, issueGroup_r};
  assign _zz_when_PwMac_l483_5 = {10'd0, serialGroupCount_r};
  assign _zz_when_PwMac_l484 = {1'd0, issueGroup_r};
  assign _zz_when_PwMac_l484_1 = (ogCount_r - 6'h01);
  assign _zz_tileBase_r = {14'd0, tileCount_r};
  assign _zz_remaining_r = {14'd0, tileCount_r};
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
      paramMemory[_zz_paramMemory_port] <= io_params_i_payload;
    end
  end

  always @(posedge clk) begin
    if(quantRequest_fire) begin
      paramMemory_spinal_port1 <= paramMemory[_zz_paramData_w];
    end
  end

  pw_weight_bank pwWeightBank (
    .clka  (clk                        ), //i
    .ena   (pwWeightBank_ena           ), //i
    .wea   (pwWeightBank_wea           ), //i
    .addra (pwWeightBank_addra[10:0]   ), //i
    .dina  (io_weights_i_payload[511:0]), //i
    .clkb  (clk                        ), //i
    .enb   (request_fire               ), //i
    .addrb (weightAddress_w[10:0]      ), //i
    .doutb (pwWeightBank_doutb[511:0]  )  //o
  );
  pw_weight_bank pwWeightBank_1 (
    .clka  (clk                        ), //i
    .ena   (pwWeightBank_1_ena         ), //i
    .wea   (pwWeightBank_1_wea         ), //i
    .addra (pwWeightBank_1_addra[10:0] ), //i
    .dina  (io_weights_i_payload[511:0]), //i
    .clkb  (clk                        ), //i
    .enb   (request_fire               ), //i
    .addrb (weightAddress_w[10:0]      ), //i
    .doutb (pwWeightBank_1_doutb[511:0])  //o
  );
  pw_weight_bank pwWeightBank_2 (
    .clka  (clk                        ), //i
    .ena   (pwWeightBank_2_ena         ), //i
    .wea   (pwWeightBank_2_wea         ), //i
    .addra (pwWeightBank_2_addra[10:0] ), //i
    .dina  (io_weights_i_payload[511:0]), //i
    .clkb  (clk                        ), //i
    .enb   (request_fire               ), //i
    .addrb (weightAddress_w[10:0]      ), //i
    .doutb (pwWeightBank_2_doutb[511:0])  //o
  );
  pw_weight_bank pwWeightBank_3 (
    .clka  (clk                        ), //i
    .ena   (pwWeightBank_3_ena         ), //i
    .wea   (pwWeightBank_3_wea         ), //i
    .addra (pwWeightBank_3_addra[10:0] ), //i
    .dina  (io_weights_i_payload[511:0]), //i
    .clkb  (clk                        ), //i
    .enb   (request_fire               ), //i
    .addrb (weightAddress_w[10:0]      ), //i
    .doutb (pwWeightBank_3_doutb[511:0])  //o
  );
  PwRequant_before requant (
    .io_input_i_valid                  (quantResponse_translated_valid                      ), //i
    .io_input_i_ready                  (requant_io_input_i_ready                            ), //o
    .io_input_i_payload_tag_pixel      (quantResponse_translated_payload_tag_pixel[18:0]    ), //i
    .io_input_i_payload_tag_localPixel (quantResponse_translated_payload_tag_localPixel[3:0]), //i
    .io_input_i_payload_tag_group      (quantResponse_translated_payload_tag_group[6:0]     ), //i
    .io_input_i_payload_tag_mask       (quantResponse_translated_payload_tag_mask[3:0]      ), //i
    .io_input_i_payload_tag_first      (quantResponse_translated_payload_tag_first          ), //i
    .io_input_i_payload_tag_finalInput (quantResponse_translated_payload_tag_finalInput     ), //i
    .io_input_i_payload_tag_tileLast   (quantResponse_translated_payload_tag_tileLast       ), //i
    .io_input_i_payload_tag_last       (quantResponse_translated_payload_tag_last           ), //i
    .io_input_i_payload_raw            (quantResponse_translated_payload_raw                ), //i
    .io_input_i_payload_int16          (quantResponse_translated_payload_int16              ), //i
    .io_input_i_payload_shift          (quantResponse_translated_payload_shift[5:0]         ), //i
    .io_input_i_payload_mac_0          (quantResponse_translated_payload_mac_0[31:0]        ), //i
    .io_input_i_payload_mac_1          (quantResponse_translated_payload_mac_1[31:0]        ), //i
    .io_input_i_payload_mac_2          (quantResponse_translated_payload_mac_2[31:0]        ), //i
    .io_input_i_payload_mac_3          (quantResponse_translated_payload_mac_3[31:0]        ), //i
    .io_input_i_payload_multiplier_0   (quantResponse_translated_payload_multiplier_0[31:0] ), //i
    .io_input_i_payload_multiplier_1   (quantResponse_translated_payload_multiplier_1[31:0] ), //i
    .io_input_i_payload_multiplier_2   (quantResponse_translated_payload_multiplier_2[31:0] ), //i
    .io_input_i_payload_multiplier_3   (quantResponse_translated_payload_multiplier_3[31:0] ), //i
    .io_input_i_payload_bias_0         (quantResponse_translated_payload_bias_0[63:0]       ), //i
    .io_input_i_payload_bias_1         (quantResponse_translated_payload_bias_1[63:0]       ), //i
    .io_input_i_payload_bias_2         (quantResponse_translated_payload_bias_2[63:0]       ), //i
    .io_input_i_payload_bias_3         (quantResponse_translated_payload_bias_3[63:0]       ), //i
    .io_input_i_payload_lower_0        (quantResponse_translated_payload_lower_0[15:0]      ), //i
    .io_input_i_payload_lower_1        (quantResponse_translated_payload_lower_1[15:0]      ), //i
    .io_input_i_payload_lower_2        (quantResponse_translated_payload_lower_2[15:0]      ), //i
    .io_input_i_payload_lower_3        (quantResponse_translated_payload_lower_3[15:0]      ), //i
    .io_input_i_payload_upper_0        (quantResponse_translated_payload_upper_0[15:0]      ), //i
    .io_input_i_payload_upper_1        (quantResponse_translated_payload_upper_1[15:0]      ), //i
    .io_input_i_payload_upper_2        (quantResponse_translated_payload_upper_2[15:0]      ), //i
    .io_input_i_payload_upper_3        (quantResponse_translated_payload_upper_3[15:0]      ), //i
    .io_output_o_valid                 (requant_io_output_o_valid                           ), //o
    .io_output_o_ready                 (io_output_o_ready                                   ), //i
    .io_output_o_payload_pixel         (requant_io_output_o_payload_pixel[18:0]             ), //o
    .io_output_o_payload_group         (requant_io_output_o_payload_group[6:0]              ), //o
    .io_output_o_payload_mask          (requant_io_output_o_payload_mask[3:0]               ), //o
    .io_output_o_payload_last          (requant_io_output_o_payload_last                    ), //o
    .io_output_o_payload_raw           (requant_io_output_o_payload_raw                     ), //o
    .io_output_o_payload_int16         (requant_io_output_o_payload_int16                   ), //o
    .io_output_o_payload_mac_0         (requant_io_output_o_payload_mac_0[31:0]             ), //o
    .io_output_o_payload_mac_1         (requant_io_output_o_payload_mac_1[31:0]             ), //o
    .io_output_o_payload_mac_2         (requant_io_output_o_payload_mac_2[31:0]             ), //o
    .io_output_o_payload_mac_3         (requant_io_output_o_payload_mac_3[31:0]             ), //o
    .io_output_o_payload_q_0           (requant_io_output_o_payload_q_0[15:0]               ), //o
    .io_output_o_payload_q_1           (requant_io_output_o_payload_q_1[15:0]               ), //o
    .io_output_o_payload_q_2           (requant_io_output_o_payload_q_2[15:0]               ), //o
    .io_output_o_payload_q_3           (requant_io_output_o_payload_q_3[15:0]               ), //o
    .clk                               (clk                                                 ), //i
    .resetn                            (resetn                                              )  //i
  );
  always @(*) begin
    case(localPixel_w)
      4'b0000 : begin
        _zz__zz_acc_r_0_0_1 = acc_r_0_0;
        _zz__zz_acc_r_1_0_1 = acc_r_1_0;
        _zz__zz_acc_r_2_0_1 = acc_r_2_0;
        _zz__zz_acc_r_3_0_1 = acc_r_3_0;
        _zz__zz_acc_r_4_0_1 = acc_r_4_0;
        _zz__zz_acc_r_5_0_1 = acc_r_5_0;
        _zz__zz_acc_r_6_0_1 = acc_r_6_0;
        _zz__zz_acc_r_7_0_1 = acc_r_7_0;
        _zz__zz_acc_r_8_0_1 = acc_r_8_0;
        _zz__zz_acc_r_9_0_1 = acc_r_9_0;
        _zz__zz_acc_r_10_0_1 = acc_r_10_0;
        _zz__zz_acc_r_11_0_1 = acc_r_11_0;
        _zz__zz_acc_r_12_0_1 = acc_r_12_0;
        _zz__zz_acc_r_13_0_1 = acc_r_13_0;
        _zz__zz_acc_r_14_0_1 = acc_r_14_0;
        _zz__zz_acc_r_15_0_1 = acc_r_15_0;
      end
      4'b0001 : begin
        _zz__zz_acc_r_0_0_1 = acc_r_0_1;
        _zz__zz_acc_r_1_0_1 = acc_r_1_1;
        _zz__zz_acc_r_2_0_1 = acc_r_2_1;
        _zz__zz_acc_r_3_0_1 = acc_r_3_1;
        _zz__zz_acc_r_4_0_1 = acc_r_4_1;
        _zz__zz_acc_r_5_0_1 = acc_r_5_1;
        _zz__zz_acc_r_6_0_1 = acc_r_6_1;
        _zz__zz_acc_r_7_0_1 = acc_r_7_1;
        _zz__zz_acc_r_8_0_1 = acc_r_8_1;
        _zz__zz_acc_r_9_0_1 = acc_r_9_1;
        _zz__zz_acc_r_10_0_1 = acc_r_10_1;
        _zz__zz_acc_r_11_0_1 = acc_r_11_1;
        _zz__zz_acc_r_12_0_1 = acc_r_12_1;
        _zz__zz_acc_r_13_0_1 = acc_r_13_1;
        _zz__zz_acc_r_14_0_1 = acc_r_14_1;
        _zz__zz_acc_r_15_0_1 = acc_r_15_1;
      end
      4'b0010 : begin
        _zz__zz_acc_r_0_0_1 = acc_r_0_2;
        _zz__zz_acc_r_1_0_1 = acc_r_1_2;
        _zz__zz_acc_r_2_0_1 = acc_r_2_2;
        _zz__zz_acc_r_3_0_1 = acc_r_3_2;
        _zz__zz_acc_r_4_0_1 = acc_r_4_2;
        _zz__zz_acc_r_5_0_1 = acc_r_5_2;
        _zz__zz_acc_r_6_0_1 = acc_r_6_2;
        _zz__zz_acc_r_7_0_1 = acc_r_7_2;
        _zz__zz_acc_r_8_0_1 = acc_r_8_2;
        _zz__zz_acc_r_9_0_1 = acc_r_9_2;
        _zz__zz_acc_r_10_0_1 = acc_r_10_2;
        _zz__zz_acc_r_11_0_1 = acc_r_11_2;
        _zz__zz_acc_r_12_0_1 = acc_r_12_2;
        _zz__zz_acc_r_13_0_1 = acc_r_13_2;
        _zz__zz_acc_r_14_0_1 = acc_r_14_2;
        _zz__zz_acc_r_15_0_1 = acc_r_15_2;
      end
      4'b0011 : begin
        _zz__zz_acc_r_0_0_1 = acc_r_0_3;
        _zz__zz_acc_r_1_0_1 = acc_r_1_3;
        _zz__zz_acc_r_2_0_1 = acc_r_2_3;
        _zz__zz_acc_r_3_0_1 = acc_r_3_3;
        _zz__zz_acc_r_4_0_1 = acc_r_4_3;
        _zz__zz_acc_r_5_0_1 = acc_r_5_3;
        _zz__zz_acc_r_6_0_1 = acc_r_6_3;
        _zz__zz_acc_r_7_0_1 = acc_r_7_3;
        _zz__zz_acc_r_8_0_1 = acc_r_8_3;
        _zz__zz_acc_r_9_0_1 = acc_r_9_3;
        _zz__zz_acc_r_10_0_1 = acc_r_10_3;
        _zz__zz_acc_r_11_0_1 = acc_r_11_3;
        _zz__zz_acc_r_12_0_1 = acc_r_12_3;
        _zz__zz_acc_r_13_0_1 = acc_r_13_3;
        _zz__zz_acc_r_14_0_1 = acc_r_14_3;
        _zz__zz_acc_r_15_0_1 = acc_r_15_3;
      end
      4'b0100 : begin
        _zz__zz_acc_r_0_0_1 = acc_r_0_4;
        _zz__zz_acc_r_1_0_1 = acc_r_1_4;
        _zz__zz_acc_r_2_0_1 = acc_r_2_4;
        _zz__zz_acc_r_3_0_1 = acc_r_3_4;
        _zz__zz_acc_r_4_0_1 = acc_r_4_4;
        _zz__zz_acc_r_5_0_1 = acc_r_5_4;
        _zz__zz_acc_r_6_0_1 = acc_r_6_4;
        _zz__zz_acc_r_7_0_1 = acc_r_7_4;
        _zz__zz_acc_r_8_0_1 = acc_r_8_4;
        _zz__zz_acc_r_9_0_1 = acc_r_9_4;
        _zz__zz_acc_r_10_0_1 = acc_r_10_4;
        _zz__zz_acc_r_11_0_1 = acc_r_11_4;
        _zz__zz_acc_r_12_0_1 = acc_r_12_4;
        _zz__zz_acc_r_13_0_1 = acc_r_13_4;
        _zz__zz_acc_r_14_0_1 = acc_r_14_4;
        _zz__zz_acc_r_15_0_1 = acc_r_15_4;
      end
      4'b0101 : begin
        _zz__zz_acc_r_0_0_1 = acc_r_0_5;
        _zz__zz_acc_r_1_0_1 = acc_r_1_5;
        _zz__zz_acc_r_2_0_1 = acc_r_2_5;
        _zz__zz_acc_r_3_0_1 = acc_r_3_5;
        _zz__zz_acc_r_4_0_1 = acc_r_4_5;
        _zz__zz_acc_r_5_0_1 = acc_r_5_5;
        _zz__zz_acc_r_6_0_1 = acc_r_6_5;
        _zz__zz_acc_r_7_0_1 = acc_r_7_5;
        _zz__zz_acc_r_8_0_1 = acc_r_8_5;
        _zz__zz_acc_r_9_0_1 = acc_r_9_5;
        _zz__zz_acc_r_10_0_1 = acc_r_10_5;
        _zz__zz_acc_r_11_0_1 = acc_r_11_5;
        _zz__zz_acc_r_12_0_1 = acc_r_12_5;
        _zz__zz_acc_r_13_0_1 = acc_r_13_5;
        _zz__zz_acc_r_14_0_1 = acc_r_14_5;
        _zz__zz_acc_r_15_0_1 = acc_r_15_5;
      end
      4'b0110 : begin
        _zz__zz_acc_r_0_0_1 = acc_r_0_6;
        _zz__zz_acc_r_1_0_1 = acc_r_1_6;
        _zz__zz_acc_r_2_0_1 = acc_r_2_6;
        _zz__zz_acc_r_3_0_1 = acc_r_3_6;
        _zz__zz_acc_r_4_0_1 = acc_r_4_6;
        _zz__zz_acc_r_5_0_1 = acc_r_5_6;
        _zz__zz_acc_r_6_0_1 = acc_r_6_6;
        _zz__zz_acc_r_7_0_1 = acc_r_7_6;
        _zz__zz_acc_r_8_0_1 = acc_r_8_6;
        _zz__zz_acc_r_9_0_1 = acc_r_9_6;
        _zz__zz_acc_r_10_0_1 = acc_r_10_6;
        _zz__zz_acc_r_11_0_1 = acc_r_11_6;
        _zz__zz_acc_r_12_0_1 = acc_r_12_6;
        _zz__zz_acc_r_13_0_1 = acc_r_13_6;
        _zz__zz_acc_r_14_0_1 = acc_r_14_6;
        _zz__zz_acc_r_15_0_1 = acc_r_15_6;
      end
      4'b0111 : begin
        _zz__zz_acc_r_0_0_1 = acc_r_0_7;
        _zz__zz_acc_r_1_0_1 = acc_r_1_7;
        _zz__zz_acc_r_2_0_1 = acc_r_2_7;
        _zz__zz_acc_r_3_0_1 = acc_r_3_7;
        _zz__zz_acc_r_4_0_1 = acc_r_4_7;
        _zz__zz_acc_r_5_0_1 = acc_r_5_7;
        _zz__zz_acc_r_6_0_1 = acc_r_6_7;
        _zz__zz_acc_r_7_0_1 = acc_r_7_7;
        _zz__zz_acc_r_8_0_1 = acc_r_8_7;
        _zz__zz_acc_r_9_0_1 = acc_r_9_7;
        _zz__zz_acc_r_10_0_1 = acc_r_10_7;
        _zz__zz_acc_r_11_0_1 = acc_r_11_7;
        _zz__zz_acc_r_12_0_1 = acc_r_12_7;
        _zz__zz_acc_r_13_0_1 = acc_r_13_7;
        _zz__zz_acc_r_14_0_1 = acc_r_14_7;
        _zz__zz_acc_r_15_0_1 = acc_r_15_7;
      end
      4'b1000 : begin
        _zz__zz_acc_r_0_0_1 = acc_r_0_8;
        _zz__zz_acc_r_1_0_1 = acc_r_1_8;
        _zz__zz_acc_r_2_0_1 = acc_r_2_8;
        _zz__zz_acc_r_3_0_1 = acc_r_3_8;
        _zz__zz_acc_r_4_0_1 = acc_r_4_8;
        _zz__zz_acc_r_5_0_1 = acc_r_5_8;
        _zz__zz_acc_r_6_0_1 = acc_r_6_8;
        _zz__zz_acc_r_7_0_1 = acc_r_7_8;
        _zz__zz_acc_r_8_0_1 = acc_r_8_8;
        _zz__zz_acc_r_9_0_1 = acc_r_9_8;
        _zz__zz_acc_r_10_0_1 = acc_r_10_8;
        _zz__zz_acc_r_11_0_1 = acc_r_11_8;
        _zz__zz_acc_r_12_0_1 = acc_r_12_8;
        _zz__zz_acc_r_13_0_1 = acc_r_13_8;
        _zz__zz_acc_r_14_0_1 = acc_r_14_8;
        _zz__zz_acc_r_15_0_1 = acc_r_15_8;
      end
      4'b1001 : begin
        _zz__zz_acc_r_0_0_1 = acc_r_0_9;
        _zz__zz_acc_r_1_0_1 = acc_r_1_9;
        _zz__zz_acc_r_2_0_1 = acc_r_2_9;
        _zz__zz_acc_r_3_0_1 = acc_r_3_9;
        _zz__zz_acc_r_4_0_1 = acc_r_4_9;
        _zz__zz_acc_r_5_0_1 = acc_r_5_9;
        _zz__zz_acc_r_6_0_1 = acc_r_6_9;
        _zz__zz_acc_r_7_0_1 = acc_r_7_9;
        _zz__zz_acc_r_8_0_1 = acc_r_8_9;
        _zz__zz_acc_r_9_0_1 = acc_r_9_9;
        _zz__zz_acc_r_10_0_1 = acc_r_10_9;
        _zz__zz_acc_r_11_0_1 = acc_r_11_9;
        _zz__zz_acc_r_12_0_1 = acc_r_12_9;
        _zz__zz_acc_r_13_0_1 = acc_r_13_9;
        _zz__zz_acc_r_14_0_1 = acc_r_14_9;
        _zz__zz_acc_r_15_0_1 = acc_r_15_9;
      end
      4'b1010 : begin
        _zz__zz_acc_r_0_0_1 = acc_r_0_10;
        _zz__zz_acc_r_1_0_1 = acc_r_1_10;
        _zz__zz_acc_r_2_0_1 = acc_r_2_10;
        _zz__zz_acc_r_3_0_1 = acc_r_3_10;
        _zz__zz_acc_r_4_0_1 = acc_r_4_10;
        _zz__zz_acc_r_5_0_1 = acc_r_5_10;
        _zz__zz_acc_r_6_0_1 = acc_r_6_10;
        _zz__zz_acc_r_7_0_1 = acc_r_7_10;
        _zz__zz_acc_r_8_0_1 = acc_r_8_10;
        _zz__zz_acc_r_9_0_1 = acc_r_9_10;
        _zz__zz_acc_r_10_0_1 = acc_r_10_10;
        _zz__zz_acc_r_11_0_1 = acc_r_11_10;
        _zz__zz_acc_r_12_0_1 = acc_r_12_10;
        _zz__zz_acc_r_13_0_1 = acc_r_13_10;
        _zz__zz_acc_r_14_0_1 = acc_r_14_10;
        _zz__zz_acc_r_15_0_1 = acc_r_15_10;
      end
      4'b1011 : begin
        _zz__zz_acc_r_0_0_1 = acc_r_0_11;
        _zz__zz_acc_r_1_0_1 = acc_r_1_11;
        _zz__zz_acc_r_2_0_1 = acc_r_2_11;
        _zz__zz_acc_r_3_0_1 = acc_r_3_11;
        _zz__zz_acc_r_4_0_1 = acc_r_4_11;
        _zz__zz_acc_r_5_0_1 = acc_r_5_11;
        _zz__zz_acc_r_6_0_1 = acc_r_6_11;
        _zz__zz_acc_r_7_0_1 = acc_r_7_11;
        _zz__zz_acc_r_8_0_1 = acc_r_8_11;
        _zz__zz_acc_r_9_0_1 = acc_r_9_11;
        _zz__zz_acc_r_10_0_1 = acc_r_10_11;
        _zz__zz_acc_r_11_0_1 = acc_r_11_11;
        _zz__zz_acc_r_12_0_1 = acc_r_12_11;
        _zz__zz_acc_r_13_0_1 = acc_r_13_11;
        _zz__zz_acc_r_14_0_1 = acc_r_14_11;
        _zz__zz_acc_r_15_0_1 = acc_r_15_11;
      end
      4'b1100 : begin
        _zz__zz_acc_r_0_0_1 = acc_r_0_12;
        _zz__zz_acc_r_1_0_1 = acc_r_1_12;
        _zz__zz_acc_r_2_0_1 = acc_r_2_12;
        _zz__zz_acc_r_3_0_1 = acc_r_3_12;
        _zz__zz_acc_r_4_0_1 = acc_r_4_12;
        _zz__zz_acc_r_5_0_1 = acc_r_5_12;
        _zz__zz_acc_r_6_0_1 = acc_r_6_12;
        _zz__zz_acc_r_7_0_1 = acc_r_7_12;
        _zz__zz_acc_r_8_0_1 = acc_r_8_12;
        _zz__zz_acc_r_9_0_1 = acc_r_9_12;
        _zz__zz_acc_r_10_0_1 = acc_r_10_12;
        _zz__zz_acc_r_11_0_1 = acc_r_11_12;
        _zz__zz_acc_r_12_0_1 = acc_r_12_12;
        _zz__zz_acc_r_13_0_1 = acc_r_13_12;
        _zz__zz_acc_r_14_0_1 = acc_r_14_12;
        _zz__zz_acc_r_15_0_1 = acc_r_15_12;
      end
      4'b1101 : begin
        _zz__zz_acc_r_0_0_1 = acc_r_0_13;
        _zz__zz_acc_r_1_0_1 = acc_r_1_13;
        _zz__zz_acc_r_2_0_1 = acc_r_2_13;
        _zz__zz_acc_r_3_0_1 = acc_r_3_13;
        _zz__zz_acc_r_4_0_1 = acc_r_4_13;
        _zz__zz_acc_r_5_0_1 = acc_r_5_13;
        _zz__zz_acc_r_6_0_1 = acc_r_6_13;
        _zz__zz_acc_r_7_0_1 = acc_r_7_13;
        _zz__zz_acc_r_8_0_1 = acc_r_8_13;
        _zz__zz_acc_r_9_0_1 = acc_r_9_13;
        _zz__zz_acc_r_10_0_1 = acc_r_10_13;
        _zz__zz_acc_r_11_0_1 = acc_r_11_13;
        _zz__zz_acc_r_12_0_1 = acc_r_12_13;
        _zz__zz_acc_r_13_0_1 = acc_r_13_13;
        _zz__zz_acc_r_14_0_1 = acc_r_14_13;
        _zz__zz_acc_r_15_0_1 = acc_r_15_13;
      end
      4'b1110 : begin
        _zz__zz_acc_r_0_0_1 = acc_r_0_14;
        _zz__zz_acc_r_1_0_1 = acc_r_1_14;
        _zz__zz_acc_r_2_0_1 = acc_r_2_14;
        _zz__zz_acc_r_3_0_1 = acc_r_3_14;
        _zz__zz_acc_r_4_0_1 = acc_r_4_14;
        _zz__zz_acc_r_5_0_1 = acc_r_5_14;
        _zz__zz_acc_r_6_0_1 = acc_r_6_14;
        _zz__zz_acc_r_7_0_1 = acc_r_7_14;
        _zz__zz_acc_r_8_0_1 = acc_r_8_14;
        _zz__zz_acc_r_9_0_1 = acc_r_9_14;
        _zz__zz_acc_r_10_0_1 = acc_r_10_14;
        _zz__zz_acc_r_11_0_1 = acc_r_11_14;
        _zz__zz_acc_r_12_0_1 = acc_r_12_14;
        _zz__zz_acc_r_13_0_1 = acc_r_13_14;
        _zz__zz_acc_r_14_0_1 = acc_r_14_14;
        _zz__zz_acc_r_15_0_1 = acc_r_15_14;
      end
      default : begin
        _zz__zz_acc_r_0_0_1 = acc_r_0_15;
        _zz__zz_acc_r_1_0_1 = acc_r_1_15;
        _zz__zz_acc_r_2_0_1 = acc_r_2_15;
        _zz__zz_acc_r_3_0_1 = acc_r_3_15;
        _zz__zz_acc_r_4_0_1 = acc_r_4_15;
        _zz__zz_acc_r_5_0_1 = acc_r_5_15;
        _zz__zz_acc_r_6_0_1 = acc_r_6_15;
        _zz__zz_acc_r_7_0_1 = acc_r_7_15;
        _zz__zz_acc_r_8_0_1 = acc_r_8_15;
        _zz__zz_acc_r_9_0_1 = acc_r_9_15;
        _zz__zz_acc_r_10_0_1 = acc_r_10_15;
        _zz__zz_acc_r_11_0_1 = acc_r_11_15;
        _zz__zz_acc_r_12_0_1 = acc_r_12_15;
        _zz__zz_acc_r_13_0_1 = acc_r_13_15;
        _zz__zz_acc_r_14_0_1 = acc_r_14_15;
        _zz__zz_acc_r_15_0_1 = acc_r_15_15;
      end
    endcase
  end

  always @(*) begin
    case(_zz_quantRequest_payload_mac_0_2)
      4'b0000 : _zz_quantRequest_payload_mac_0_1 = _zz_quantRequest_payload_mac_0_3;
      4'b0001 : _zz_quantRequest_payload_mac_0_1 = _zz_quantRequest_payload_mac_0_4;
      4'b0010 : _zz_quantRequest_payload_mac_0_1 = _zz_quantRequest_payload_mac_0_5;
      4'b0011 : _zz_quantRequest_payload_mac_0_1 = _zz_quantRequest_payload_mac_0_6;
      4'b0100 : _zz_quantRequest_payload_mac_0_1 = _zz_quantRequest_payload_mac_0_7;
      4'b0101 : _zz_quantRequest_payload_mac_0_1 = _zz_quantRequest_payload_mac_0_8;
      4'b0110 : _zz_quantRequest_payload_mac_0_1 = _zz_quantRequest_payload_mac_0_9;
      4'b0111 : _zz_quantRequest_payload_mac_0_1 = _zz_quantRequest_payload_mac_0_10;
      4'b1000 : _zz_quantRequest_payload_mac_0_1 = _zz_quantRequest_payload_mac_0_11;
      4'b1001 : _zz_quantRequest_payload_mac_0_1 = _zz_quantRequest_payload_mac_0_12;
      4'b1010 : _zz_quantRequest_payload_mac_0_1 = _zz_quantRequest_payload_mac_0_13;
      4'b1011 : _zz_quantRequest_payload_mac_0_1 = _zz_quantRequest_payload_mac_0_14;
      4'b1100 : _zz_quantRequest_payload_mac_0_1 = _zz_quantRequest_payload_mac_0_15;
      4'b1101 : _zz_quantRequest_payload_mac_0_1 = _zz_quantRequest_payload_mac_0_16;
      4'b1110 : _zz_quantRequest_payload_mac_0_1 = _zz_quantRequest_payload_mac_0_17;
      default : _zz_quantRequest_payload_mac_0_1 = _zz_quantRequest_payload_mac_0_18;
    endcase
  end

  always @(*) begin
    case(_zz_quantRequest_payload_mac_0)
      4'b0000 : begin
        _zz_quantRequest_payload_mac_0_3 = tileMac_r_0_0;
        _zz_quantRequest_payload_mac_0_4 = tileMac_r_0_1;
        _zz_quantRequest_payload_mac_0_5 = tileMac_r_0_2;
        _zz_quantRequest_payload_mac_0_6 = tileMac_r_0_3;
        _zz_quantRequest_payload_mac_0_7 = tileMac_r_0_4;
        _zz_quantRequest_payload_mac_0_8 = tileMac_r_0_5;
        _zz_quantRequest_payload_mac_0_9 = tileMac_r_0_6;
        _zz_quantRequest_payload_mac_0_10 = tileMac_r_0_7;
        _zz_quantRequest_payload_mac_0_11 = tileMac_r_0_8;
        _zz_quantRequest_payload_mac_0_12 = tileMac_r_0_9;
        _zz_quantRequest_payload_mac_0_13 = tileMac_r_0_10;
        _zz_quantRequest_payload_mac_0_14 = tileMac_r_0_11;
        _zz_quantRequest_payload_mac_0_15 = tileMac_r_0_12;
        _zz_quantRequest_payload_mac_0_16 = tileMac_r_0_13;
        _zz_quantRequest_payload_mac_0_17 = tileMac_r_0_14;
        _zz_quantRequest_payload_mac_0_18 = tileMac_r_0_15;
      end
      4'b0001 : begin
        _zz_quantRequest_payload_mac_0_3 = tileMac_r_1_0;
        _zz_quantRequest_payload_mac_0_4 = tileMac_r_1_1;
        _zz_quantRequest_payload_mac_0_5 = tileMac_r_1_2;
        _zz_quantRequest_payload_mac_0_6 = tileMac_r_1_3;
        _zz_quantRequest_payload_mac_0_7 = tileMac_r_1_4;
        _zz_quantRequest_payload_mac_0_8 = tileMac_r_1_5;
        _zz_quantRequest_payload_mac_0_9 = tileMac_r_1_6;
        _zz_quantRequest_payload_mac_0_10 = tileMac_r_1_7;
        _zz_quantRequest_payload_mac_0_11 = tileMac_r_1_8;
        _zz_quantRequest_payload_mac_0_12 = tileMac_r_1_9;
        _zz_quantRequest_payload_mac_0_13 = tileMac_r_1_10;
        _zz_quantRequest_payload_mac_0_14 = tileMac_r_1_11;
        _zz_quantRequest_payload_mac_0_15 = tileMac_r_1_12;
        _zz_quantRequest_payload_mac_0_16 = tileMac_r_1_13;
        _zz_quantRequest_payload_mac_0_17 = tileMac_r_1_14;
        _zz_quantRequest_payload_mac_0_18 = tileMac_r_1_15;
      end
      4'b0010 : begin
        _zz_quantRequest_payload_mac_0_3 = tileMac_r_2_0;
        _zz_quantRequest_payload_mac_0_4 = tileMac_r_2_1;
        _zz_quantRequest_payload_mac_0_5 = tileMac_r_2_2;
        _zz_quantRequest_payload_mac_0_6 = tileMac_r_2_3;
        _zz_quantRequest_payload_mac_0_7 = tileMac_r_2_4;
        _zz_quantRequest_payload_mac_0_8 = tileMac_r_2_5;
        _zz_quantRequest_payload_mac_0_9 = tileMac_r_2_6;
        _zz_quantRequest_payload_mac_0_10 = tileMac_r_2_7;
        _zz_quantRequest_payload_mac_0_11 = tileMac_r_2_8;
        _zz_quantRequest_payload_mac_0_12 = tileMac_r_2_9;
        _zz_quantRequest_payload_mac_0_13 = tileMac_r_2_10;
        _zz_quantRequest_payload_mac_0_14 = tileMac_r_2_11;
        _zz_quantRequest_payload_mac_0_15 = tileMac_r_2_12;
        _zz_quantRequest_payload_mac_0_16 = tileMac_r_2_13;
        _zz_quantRequest_payload_mac_0_17 = tileMac_r_2_14;
        _zz_quantRequest_payload_mac_0_18 = tileMac_r_2_15;
      end
      4'b0011 : begin
        _zz_quantRequest_payload_mac_0_3 = tileMac_r_3_0;
        _zz_quantRequest_payload_mac_0_4 = tileMac_r_3_1;
        _zz_quantRequest_payload_mac_0_5 = tileMac_r_3_2;
        _zz_quantRequest_payload_mac_0_6 = tileMac_r_3_3;
        _zz_quantRequest_payload_mac_0_7 = tileMac_r_3_4;
        _zz_quantRequest_payload_mac_0_8 = tileMac_r_3_5;
        _zz_quantRequest_payload_mac_0_9 = tileMac_r_3_6;
        _zz_quantRequest_payload_mac_0_10 = tileMac_r_3_7;
        _zz_quantRequest_payload_mac_0_11 = tileMac_r_3_8;
        _zz_quantRequest_payload_mac_0_12 = tileMac_r_3_9;
        _zz_quantRequest_payload_mac_0_13 = tileMac_r_3_10;
        _zz_quantRequest_payload_mac_0_14 = tileMac_r_3_11;
        _zz_quantRequest_payload_mac_0_15 = tileMac_r_3_12;
        _zz_quantRequest_payload_mac_0_16 = tileMac_r_3_13;
        _zz_quantRequest_payload_mac_0_17 = tileMac_r_3_14;
        _zz_quantRequest_payload_mac_0_18 = tileMac_r_3_15;
      end
      4'b0100 : begin
        _zz_quantRequest_payload_mac_0_3 = tileMac_r_4_0;
        _zz_quantRequest_payload_mac_0_4 = tileMac_r_4_1;
        _zz_quantRequest_payload_mac_0_5 = tileMac_r_4_2;
        _zz_quantRequest_payload_mac_0_6 = tileMac_r_4_3;
        _zz_quantRequest_payload_mac_0_7 = tileMac_r_4_4;
        _zz_quantRequest_payload_mac_0_8 = tileMac_r_4_5;
        _zz_quantRequest_payload_mac_0_9 = tileMac_r_4_6;
        _zz_quantRequest_payload_mac_0_10 = tileMac_r_4_7;
        _zz_quantRequest_payload_mac_0_11 = tileMac_r_4_8;
        _zz_quantRequest_payload_mac_0_12 = tileMac_r_4_9;
        _zz_quantRequest_payload_mac_0_13 = tileMac_r_4_10;
        _zz_quantRequest_payload_mac_0_14 = tileMac_r_4_11;
        _zz_quantRequest_payload_mac_0_15 = tileMac_r_4_12;
        _zz_quantRequest_payload_mac_0_16 = tileMac_r_4_13;
        _zz_quantRequest_payload_mac_0_17 = tileMac_r_4_14;
        _zz_quantRequest_payload_mac_0_18 = tileMac_r_4_15;
      end
      4'b0101 : begin
        _zz_quantRequest_payload_mac_0_3 = tileMac_r_5_0;
        _zz_quantRequest_payload_mac_0_4 = tileMac_r_5_1;
        _zz_quantRequest_payload_mac_0_5 = tileMac_r_5_2;
        _zz_quantRequest_payload_mac_0_6 = tileMac_r_5_3;
        _zz_quantRequest_payload_mac_0_7 = tileMac_r_5_4;
        _zz_quantRequest_payload_mac_0_8 = tileMac_r_5_5;
        _zz_quantRequest_payload_mac_0_9 = tileMac_r_5_6;
        _zz_quantRequest_payload_mac_0_10 = tileMac_r_5_7;
        _zz_quantRequest_payload_mac_0_11 = tileMac_r_5_8;
        _zz_quantRequest_payload_mac_0_12 = tileMac_r_5_9;
        _zz_quantRequest_payload_mac_0_13 = tileMac_r_5_10;
        _zz_quantRequest_payload_mac_0_14 = tileMac_r_5_11;
        _zz_quantRequest_payload_mac_0_15 = tileMac_r_5_12;
        _zz_quantRequest_payload_mac_0_16 = tileMac_r_5_13;
        _zz_quantRequest_payload_mac_0_17 = tileMac_r_5_14;
        _zz_quantRequest_payload_mac_0_18 = tileMac_r_5_15;
      end
      4'b0110 : begin
        _zz_quantRequest_payload_mac_0_3 = tileMac_r_6_0;
        _zz_quantRequest_payload_mac_0_4 = tileMac_r_6_1;
        _zz_quantRequest_payload_mac_0_5 = tileMac_r_6_2;
        _zz_quantRequest_payload_mac_0_6 = tileMac_r_6_3;
        _zz_quantRequest_payload_mac_0_7 = tileMac_r_6_4;
        _zz_quantRequest_payload_mac_0_8 = tileMac_r_6_5;
        _zz_quantRequest_payload_mac_0_9 = tileMac_r_6_6;
        _zz_quantRequest_payload_mac_0_10 = tileMac_r_6_7;
        _zz_quantRequest_payload_mac_0_11 = tileMac_r_6_8;
        _zz_quantRequest_payload_mac_0_12 = tileMac_r_6_9;
        _zz_quantRequest_payload_mac_0_13 = tileMac_r_6_10;
        _zz_quantRequest_payload_mac_0_14 = tileMac_r_6_11;
        _zz_quantRequest_payload_mac_0_15 = tileMac_r_6_12;
        _zz_quantRequest_payload_mac_0_16 = tileMac_r_6_13;
        _zz_quantRequest_payload_mac_0_17 = tileMac_r_6_14;
        _zz_quantRequest_payload_mac_0_18 = tileMac_r_6_15;
      end
      4'b0111 : begin
        _zz_quantRequest_payload_mac_0_3 = tileMac_r_7_0;
        _zz_quantRequest_payload_mac_0_4 = tileMac_r_7_1;
        _zz_quantRequest_payload_mac_0_5 = tileMac_r_7_2;
        _zz_quantRequest_payload_mac_0_6 = tileMac_r_7_3;
        _zz_quantRequest_payload_mac_0_7 = tileMac_r_7_4;
        _zz_quantRequest_payload_mac_0_8 = tileMac_r_7_5;
        _zz_quantRequest_payload_mac_0_9 = tileMac_r_7_6;
        _zz_quantRequest_payload_mac_0_10 = tileMac_r_7_7;
        _zz_quantRequest_payload_mac_0_11 = tileMac_r_7_8;
        _zz_quantRequest_payload_mac_0_12 = tileMac_r_7_9;
        _zz_quantRequest_payload_mac_0_13 = tileMac_r_7_10;
        _zz_quantRequest_payload_mac_0_14 = tileMac_r_7_11;
        _zz_quantRequest_payload_mac_0_15 = tileMac_r_7_12;
        _zz_quantRequest_payload_mac_0_16 = tileMac_r_7_13;
        _zz_quantRequest_payload_mac_0_17 = tileMac_r_7_14;
        _zz_quantRequest_payload_mac_0_18 = tileMac_r_7_15;
      end
      4'b1000 : begin
        _zz_quantRequest_payload_mac_0_3 = tileMac_r_8_0;
        _zz_quantRequest_payload_mac_0_4 = tileMac_r_8_1;
        _zz_quantRequest_payload_mac_0_5 = tileMac_r_8_2;
        _zz_quantRequest_payload_mac_0_6 = tileMac_r_8_3;
        _zz_quantRequest_payload_mac_0_7 = tileMac_r_8_4;
        _zz_quantRequest_payload_mac_0_8 = tileMac_r_8_5;
        _zz_quantRequest_payload_mac_0_9 = tileMac_r_8_6;
        _zz_quantRequest_payload_mac_0_10 = tileMac_r_8_7;
        _zz_quantRequest_payload_mac_0_11 = tileMac_r_8_8;
        _zz_quantRequest_payload_mac_0_12 = tileMac_r_8_9;
        _zz_quantRequest_payload_mac_0_13 = tileMac_r_8_10;
        _zz_quantRequest_payload_mac_0_14 = tileMac_r_8_11;
        _zz_quantRequest_payload_mac_0_15 = tileMac_r_8_12;
        _zz_quantRequest_payload_mac_0_16 = tileMac_r_8_13;
        _zz_quantRequest_payload_mac_0_17 = tileMac_r_8_14;
        _zz_quantRequest_payload_mac_0_18 = tileMac_r_8_15;
      end
      4'b1001 : begin
        _zz_quantRequest_payload_mac_0_3 = tileMac_r_9_0;
        _zz_quantRequest_payload_mac_0_4 = tileMac_r_9_1;
        _zz_quantRequest_payload_mac_0_5 = tileMac_r_9_2;
        _zz_quantRequest_payload_mac_0_6 = tileMac_r_9_3;
        _zz_quantRequest_payload_mac_0_7 = tileMac_r_9_4;
        _zz_quantRequest_payload_mac_0_8 = tileMac_r_9_5;
        _zz_quantRequest_payload_mac_0_9 = tileMac_r_9_6;
        _zz_quantRequest_payload_mac_0_10 = tileMac_r_9_7;
        _zz_quantRequest_payload_mac_0_11 = tileMac_r_9_8;
        _zz_quantRequest_payload_mac_0_12 = tileMac_r_9_9;
        _zz_quantRequest_payload_mac_0_13 = tileMac_r_9_10;
        _zz_quantRequest_payload_mac_0_14 = tileMac_r_9_11;
        _zz_quantRequest_payload_mac_0_15 = tileMac_r_9_12;
        _zz_quantRequest_payload_mac_0_16 = tileMac_r_9_13;
        _zz_quantRequest_payload_mac_0_17 = tileMac_r_9_14;
        _zz_quantRequest_payload_mac_0_18 = tileMac_r_9_15;
      end
      4'b1010 : begin
        _zz_quantRequest_payload_mac_0_3 = tileMac_r_10_0;
        _zz_quantRequest_payload_mac_0_4 = tileMac_r_10_1;
        _zz_quantRequest_payload_mac_0_5 = tileMac_r_10_2;
        _zz_quantRequest_payload_mac_0_6 = tileMac_r_10_3;
        _zz_quantRequest_payload_mac_0_7 = tileMac_r_10_4;
        _zz_quantRequest_payload_mac_0_8 = tileMac_r_10_5;
        _zz_quantRequest_payload_mac_0_9 = tileMac_r_10_6;
        _zz_quantRequest_payload_mac_0_10 = tileMac_r_10_7;
        _zz_quantRequest_payload_mac_0_11 = tileMac_r_10_8;
        _zz_quantRequest_payload_mac_0_12 = tileMac_r_10_9;
        _zz_quantRequest_payload_mac_0_13 = tileMac_r_10_10;
        _zz_quantRequest_payload_mac_0_14 = tileMac_r_10_11;
        _zz_quantRequest_payload_mac_0_15 = tileMac_r_10_12;
        _zz_quantRequest_payload_mac_0_16 = tileMac_r_10_13;
        _zz_quantRequest_payload_mac_0_17 = tileMac_r_10_14;
        _zz_quantRequest_payload_mac_0_18 = tileMac_r_10_15;
      end
      4'b1011 : begin
        _zz_quantRequest_payload_mac_0_3 = tileMac_r_11_0;
        _zz_quantRequest_payload_mac_0_4 = tileMac_r_11_1;
        _zz_quantRequest_payload_mac_0_5 = tileMac_r_11_2;
        _zz_quantRequest_payload_mac_0_6 = tileMac_r_11_3;
        _zz_quantRequest_payload_mac_0_7 = tileMac_r_11_4;
        _zz_quantRequest_payload_mac_0_8 = tileMac_r_11_5;
        _zz_quantRequest_payload_mac_0_9 = tileMac_r_11_6;
        _zz_quantRequest_payload_mac_0_10 = tileMac_r_11_7;
        _zz_quantRequest_payload_mac_0_11 = tileMac_r_11_8;
        _zz_quantRequest_payload_mac_0_12 = tileMac_r_11_9;
        _zz_quantRequest_payload_mac_0_13 = tileMac_r_11_10;
        _zz_quantRequest_payload_mac_0_14 = tileMac_r_11_11;
        _zz_quantRequest_payload_mac_0_15 = tileMac_r_11_12;
        _zz_quantRequest_payload_mac_0_16 = tileMac_r_11_13;
        _zz_quantRequest_payload_mac_0_17 = tileMac_r_11_14;
        _zz_quantRequest_payload_mac_0_18 = tileMac_r_11_15;
      end
      4'b1100 : begin
        _zz_quantRequest_payload_mac_0_3 = tileMac_r_12_0;
        _zz_quantRequest_payload_mac_0_4 = tileMac_r_12_1;
        _zz_quantRequest_payload_mac_0_5 = tileMac_r_12_2;
        _zz_quantRequest_payload_mac_0_6 = tileMac_r_12_3;
        _zz_quantRequest_payload_mac_0_7 = tileMac_r_12_4;
        _zz_quantRequest_payload_mac_0_8 = tileMac_r_12_5;
        _zz_quantRequest_payload_mac_0_9 = tileMac_r_12_6;
        _zz_quantRequest_payload_mac_0_10 = tileMac_r_12_7;
        _zz_quantRequest_payload_mac_0_11 = tileMac_r_12_8;
        _zz_quantRequest_payload_mac_0_12 = tileMac_r_12_9;
        _zz_quantRequest_payload_mac_0_13 = tileMac_r_12_10;
        _zz_quantRequest_payload_mac_0_14 = tileMac_r_12_11;
        _zz_quantRequest_payload_mac_0_15 = tileMac_r_12_12;
        _zz_quantRequest_payload_mac_0_16 = tileMac_r_12_13;
        _zz_quantRequest_payload_mac_0_17 = tileMac_r_12_14;
        _zz_quantRequest_payload_mac_0_18 = tileMac_r_12_15;
      end
      4'b1101 : begin
        _zz_quantRequest_payload_mac_0_3 = tileMac_r_13_0;
        _zz_quantRequest_payload_mac_0_4 = tileMac_r_13_1;
        _zz_quantRequest_payload_mac_0_5 = tileMac_r_13_2;
        _zz_quantRequest_payload_mac_0_6 = tileMac_r_13_3;
        _zz_quantRequest_payload_mac_0_7 = tileMac_r_13_4;
        _zz_quantRequest_payload_mac_0_8 = tileMac_r_13_5;
        _zz_quantRequest_payload_mac_0_9 = tileMac_r_13_6;
        _zz_quantRequest_payload_mac_0_10 = tileMac_r_13_7;
        _zz_quantRequest_payload_mac_0_11 = tileMac_r_13_8;
        _zz_quantRequest_payload_mac_0_12 = tileMac_r_13_9;
        _zz_quantRequest_payload_mac_0_13 = tileMac_r_13_10;
        _zz_quantRequest_payload_mac_0_14 = tileMac_r_13_11;
        _zz_quantRequest_payload_mac_0_15 = tileMac_r_13_12;
        _zz_quantRequest_payload_mac_0_16 = tileMac_r_13_13;
        _zz_quantRequest_payload_mac_0_17 = tileMac_r_13_14;
        _zz_quantRequest_payload_mac_0_18 = tileMac_r_13_15;
      end
      4'b1110 : begin
        _zz_quantRequest_payload_mac_0_3 = tileMac_r_14_0;
        _zz_quantRequest_payload_mac_0_4 = tileMac_r_14_1;
        _zz_quantRequest_payload_mac_0_5 = tileMac_r_14_2;
        _zz_quantRequest_payload_mac_0_6 = tileMac_r_14_3;
        _zz_quantRequest_payload_mac_0_7 = tileMac_r_14_4;
        _zz_quantRequest_payload_mac_0_8 = tileMac_r_14_5;
        _zz_quantRequest_payload_mac_0_9 = tileMac_r_14_6;
        _zz_quantRequest_payload_mac_0_10 = tileMac_r_14_7;
        _zz_quantRequest_payload_mac_0_11 = tileMac_r_14_8;
        _zz_quantRequest_payload_mac_0_12 = tileMac_r_14_9;
        _zz_quantRequest_payload_mac_0_13 = tileMac_r_14_10;
        _zz_quantRequest_payload_mac_0_14 = tileMac_r_14_11;
        _zz_quantRequest_payload_mac_0_15 = tileMac_r_14_12;
        _zz_quantRequest_payload_mac_0_16 = tileMac_r_14_13;
        _zz_quantRequest_payload_mac_0_17 = tileMac_r_14_14;
        _zz_quantRequest_payload_mac_0_18 = tileMac_r_14_15;
      end
      default : begin
        _zz_quantRequest_payload_mac_0_3 = tileMac_r_15_0;
        _zz_quantRequest_payload_mac_0_4 = tileMac_r_15_1;
        _zz_quantRequest_payload_mac_0_5 = tileMac_r_15_2;
        _zz_quantRequest_payload_mac_0_6 = tileMac_r_15_3;
        _zz_quantRequest_payload_mac_0_7 = tileMac_r_15_4;
        _zz_quantRequest_payload_mac_0_8 = tileMac_r_15_5;
        _zz_quantRequest_payload_mac_0_9 = tileMac_r_15_6;
        _zz_quantRequest_payload_mac_0_10 = tileMac_r_15_7;
        _zz_quantRequest_payload_mac_0_11 = tileMac_r_15_8;
        _zz_quantRequest_payload_mac_0_12 = tileMac_r_15_9;
        _zz_quantRequest_payload_mac_0_13 = tileMac_r_15_10;
        _zz_quantRequest_payload_mac_0_14 = tileMac_r_15_11;
        _zz_quantRequest_payload_mac_0_15 = tileMac_r_15_12;
        _zz_quantRequest_payload_mac_0_16 = tileMac_r_15_13;
        _zz_quantRequest_payload_mac_0_17 = tileMac_r_15_14;
        _zz_quantRequest_payload_mac_0_18 = tileMac_r_15_15;
      end
    endcase
  end

  always @(*) begin
    case(_zz_quantRequest_payload_mac_1_2)
      4'b0000 : _zz_quantRequest_payload_mac_1_1 = _zz_quantRequest_payload_mac_1_3;
      4'b0001 : _zz_quantRequest_payload_mac_1_1 = _zz_quantRequest_payload_mac_1_4;
      4'b0010 : _zz_quantRequest_payload_mac_1_1 = _zz_quantRequest_payload_mac_1_5;
      4'b0011 : _zz_quantRequest_payload_mac_1_1 = _zz_quantRequest_payload_mac_1_6;
      4'b0100 : _zz_quantRequest_payload_mac_1_1 = _zz_quantRequest_payload_mac_1_7;
      4'b0101 : _zz_quantRequest_payload_mac_1_1 = _zz_quantRequest_payload_mac_1_8;
      4'b0110 : _zz_quantRequest_payload_mac_1_1 = _zz_quantRequest_payload_mac_1_9;
      4'b0111 : _zz_quantRequest_payload_mac_1_1 = _zz_quantRequest_payload_mac_1_10;
      4'b1000 : _zz_quantRequest_payload_mac_1_1 = _zz_quantRequest_payload_mac_1_11;
      4'b1001 : _zz_quantRequest_payload_mac_1_1 = _zz_quantRequest_payload_mac_1_12;
      4'b1010 : _zz_quantRequest_payload_mac_1_1 = _zz_quantRequest_payload_mac_1_13;
      4'b1011 : _zz_quantRequest_payload_mac_1_1 = _zz_quantRequest_payload_mac_1_14;
      4'b1100 : _zz_quantRequest_payload_mac_1_1 = _zz_quantRequest_payload_mac_1_15;
      4'b1101 : _zz_quantRequest_payload_mac_1_1 = _zz_quantRequest_payload_mac_1_16;
      4'b1110 : _zz_quantRequest_payload_mac_1_1 = _zz_quantRequest_payload_mac_1_17;
      default : _zz_quantRequest_payload_mac_1_1 = _zz_quantRequest_payload_mac_1_18;
    endcase
  end

  always @(*) begin
    case(_zz_quantRequest_payload_mac_1)
      4'b0000 : begin
        _zz_quantRequest_payload_mac_1_3 = tileMac_r_0_0;
        _zz_quantRequest_payload_mac_1_4 = tileMac_r_0_1;
        _zz_quantRequest_payload_mac_1_5 = tileMac_r_0_2;
        _zz_quantRequest_payload_mac_1_6 = tileMac_r_0_3;
        _zz_quantRequest_payload_mac_1_7 = tileMac_r_0_4;
        _zz_quantRequest_payload_mac_1_8 = tileMac_r_0_5;
        _zz_quantRequest_payload_mac_1_9 = tileMac_r_0_6;
        _zz_quantRequest_payload_mac_1_10 = tileMac_r_0_7;
        _zz_quantRequest_payload_mac_1_11 = tileMac_r_0_8;
        _zz_quantRequest_payload_mac_1_12 = tileMac_r_0_9;
        _zz_quantRequest_payload_mac_1_13 = tileMac_r_0_10;
        _zz_quantRequest_payload_mac_1_14 = tileMac_r_0_11;
        _zz_quantRequest_payload_mac_1_15 = tileMac_r_0_12;
        _zz_quantRequest_payload_mac_1_16 = tileMac_r_0_13;
        _zz_quantRequest_payload_mac_1_17 = tileMac_r_0_14;
        _zz_quantRequest_payload_mac_1_18 = tileMac_r_0_15;
      end
      4'b0001 : begin
        _zz_quantRequest_payload_mac_1_3 = tileMac_r_1_0;
        _zz_quantRequest_payload_mac_1_4 = tileMac_r_1_1;
        _zz_quantRequest_payload_mac_1_5 = tileMac_r_1_2;
        _zz_quantRequest_payload_mac_1_6 = tileMac_r_1_3;
        _zz_quantRequest_payload_mac_1_7 = tileMac_r_1_4;
        _zz_quantRequest_payload_mac_1_8 = tileMac_r_1_5;
        _zz_quantRequest_payload_mac_1_9 = tileMac_r_1_6;
        _zz_quantRequest_payload_mac_1_10 = tileMac_r_1_7;
        _zz_quantRequest_payload_mac_1_11 = tileMac_r_1_8;
        _zz_quantRequest_payload_mac_1_12 = tileMac_r_1_9;
        _zz_quantRequest_payload_mac_1_13 = tileMac_r_1_10;
        _zz_quantRequest_payload_mac_1_14 = tileMac_r_1_11;
        _zz_quantRequest_payload_mac_1_15 = tileMac_r_1_12;
        _zz_quantRequest_payload_mac_1_16 = tileMac_r_1_13;
        _zz_quantRequest_payload_mac_1_17 = tileMac_r_1_14;
        _zz_quantRequest_payload_mac_1_18 = tileMac_r_1_15;
      end
      4'b0010 : begin
        _zz_quantRequest_payload_mac_1_3 = tileMac_r_2_0;
        _zz_quantRequest_payload_mac_1_4 = tileMac_r_2_1;
        _zz_quantRequest_payload_mac_1_5 = tileMac_r_2_2;
        _zz_quantRequest_payload_mac_1_6 = tileMac_r_2_3;
        _zz_quantRequest_payload_mac_1_7 = tileMac_r_2_4;
        _zz_quantRequest_payload_mac_1_8 = tileMac_r_2_5;
        _zz_quantRequest_payload_mac_1_9 = tileMac_r_2_6;
        _zz_quantRequest_payload_mac_1_10 = tileMac_r_2_7;
        _zz_quantRequest_payload_mac_1_11 = tileMac_r_2_8;
        _zz_quantRequest_payload_mac_1_12 = tileMac_r_2_9;
        _zz_quantRequest_payload_mac_1_13 = tileMac_r_2_10;
        _zz_quantRequest_payload_mac_1_14 = tileMac_r_2_11;
        _zz_quantRequest_payload_mac_1_15 = tileMac_r_2_12;
        _zz_quantRequest_payload_mac_1_16 = tileMac_r_2_13;
        _zz_quantRequest_payload_mac_1_17 = tileMac_r_2_14;
        _zz_quantRequest_payload_mac_1_18 = tileMac_r_2_15;
      end
      4'b0011 : begin
        _zz_quantRequest_payload_mac_1_3 = tileMac_r_3_0;
        _zz_quantRequest_payload_mac_1_4 = tileMac_r_3_1;
        _zz_quantRequest_payload_mac_1_5 = tileMac_r_3_2;
        _zz_quantRequest_payload_mac_1_6 = tileMac_r_3_3;
        _zz_quantRequest_payload_mac_1_7 = tileMac_r_3_4;
        _zz_quantRequest_payload_mac_1_8 = tileMac_r_3_5;
        _zz_quantRequest_payload_mac_1_9 = tileMac_r_3_6;
        _zz_quantRequest_payload_mac_1_10 = tileMac_r_3_7;
        _zz_quantRequest_payload_mac_1_11 = tileMac_r_3_8;
        _zz_quantRequest_payload_mac_1_12 = tileMac_r_3_9;
        _zz_quantRequest_payload_mac_1_13 = tileMac_r_3_10;
        _zz_quantRequest_payload_mac_1_14 = tileMac_r_3_11;
        _zz_quantRequest_payload_mac_1_15 = tileMac_r_3_12;
        _zz_quantRequest_payload_mac_1_16 = tileMac_r_3_13;
        _zz_quantRequest_payload_mac_1_17 = tileMac_r_3_14;
        _zz_quantRequest_payload_mac_1_18 = tileMac_r_3_15;
      end
      4'b0100 : begin
        _zz_quantRequest_payload_mac_1_3 = tileMac_r_4_0;
        _zz_quantRequest_payload_mac_1_4 = tileMac_r_4_1;
        _zz_quantRequest_payload_mac_1_5 = tileMac_r_4_2;
        _zz_quantRequest_payload_mac_1_6 = tileMac_r_4_3;
        _zz_quantRequest_payload_mac_1_7 = tileMac_r_4_4;
        _zz_quantRequest_payload_mac_1_8 = tileMac_r_4_5;
        _zz_quantRequest_payload_mac_1_9 = tileMac_r_4_6;
        _zz_quantRequest_payload_mac_1_10 = tileMac_r_4_7;
        _zz_quantRequest_payload_mac_1_11 = tileMac_r_4_8;
        _zz_quantRequest_payload_mac_1_12 = tileMac_r_4_9;
        _zz_quantRequest_payload_mac_1_13 = tileMac_r_4_10;
        _zz_quantRequest_payload_mac_1_14 = tileMac_r_4_11;
        _zz_quantRequest_payload_mac_1_15 = tileMac_r_4_12;
        _zz_quantRequest_payload_mac_1_16 = tileMac_r_4_13;
        _zz_quantRequest_payload_mac_1_17 = tileMac_r_4_14;
        _zz_quantRequest_payload_mac_1_18 = tileMac_r_4_15;
      end
      4'b0101 : begin
        _zz_quantRequest_payload_mac_1_3 = tileMac_r_5_0;
        _zz_quantRequest_payload_mac_1_4 = tileMac_r_5_1;
        _zz_quantRequest_payload_mac_1_5 = tileMac_r_5_2;
        _zz_quantRequest_payload_mac_1_6 = tileMac_r_5_3;
        _zz_quantRequest_payload_mac_1_7 = tileMac_r_5_4;
        _zz_quantRequest_payload_mac_1_8 = tileMac_r_5_5;
        _zz_quantRequest_payload_mac_1_9 = tileMac_r_5_6;
        _zz_quantRequest_payload_mac_1_10 = tileMac_r_5_7;
        _zz_quantRequest_payload_mac_1_11 = tileMac_r_5_8;
        _zz_quantRequest_payload_mac_1_12 = tileMac_r_5_9;
        _zz_quantRequest_payload_mac_1_13 = tileMac_r_5_10;
        _zz_quantRequest_payload_mac_1_14 = tileMac_r_5_11;
        _zz_quantRequest_payload_mac_1_15 = tileMac_r_5_12;
        _zz_quantRequest_payload_mac_1_16 = tileMac_r_5_13;
        _zz_quantRequest_payload_mac_1_17 = tileMac_r_5_14;
        _zz_quantRequest_payload_mac_1_18 = tileMac_r_5_15;
      end
      4'b0110 : begin
        _zz_quantRequest_payload_mac_1_3 = tileMac_r_6_0;
        _zz_quantRequest_payload_mac_1_4 = tileMac_r_6_1;
        _zz_quantRequest_payload_mac_1_5 = tileMac_r_6_2;
        _zz_quantRequest_payload_mac_1_6 = tileMac_r_6_3;
        _zz_quantRequest_payload_mac_1_7 = tileMac_r_6_4;
        _zz_quantRequest_payload_mac_1_8 = tileMac_r_6_5;
        _zz_quantRequest_payload_mac_1_9 = tileMac_r_6_6;
        _zz_quantRequest_payload_mac_1_10 = tileMac_r_6_7;
        _zz_quantRequest_payload_mac_1_11 = tileMac_r_6_8;
        _zz_quantRequest_payload_mac_1_12 = tileMac_r_6_9;
        _zz_quantRequest_payload_mac_1_13 = tileMac_r_6_10;
        _zz_quantRequest_payload_mac_1_14 = tileMac_r_6_11;
        _zz_quantRequest_payload_mac_1_15 = tileMac_r_6_12;
        _zz_quantRequest_payload_mac_1_16 = tileMac_r_6_13;
        _zz_quantRequest_payload_mac_1_17 = tileMac_r_6_14;
        _zz_quantRequest_payload_mac_1_18 = tileMac_r_6_15;
      end
      4'b0111 : begin
        _zz_quantRequest_payload_mac_1_3 = tileMac_r_7_0;
        _zz_quantRequest_payload_mac_1_4 = tileMac_r_7_1;
        _zz_quantRequest_payload_mac_1_5 = tileMac_r_7_2;
        _zz_quantRequest_payload_mac_1_6 = tileMac_r_7_3;
        _zz_quantRequest_payload_mac_1_7 = tileMac_r_7_4;
        _zz_quantRequest_payload_mac_1_8 = tileMac_r_7_5;
        _zz_quantRequest_payload_mac_1_9 = tileMac_r_7_6;
        _zz_quantRequest_payload_mac_1_10 = tileMac_r_7_7;
        _zz_quantRequest_payload_mac_1_11 = tileMac_r_7_8;
        _zz_quantRequest_payload_mac_1_12 = tileMac_r_7_9;
        _zz_quantRequest_payload_mac_1_13 = tileMac_r_7_10;
        _zz_quantRequest_payload_mac_1_14 = tileMac_r_7_11;
        _zz_quantRequest_payload_mac_1_15 = tileMac_r_7_12;
        _zz_quantRequest_payload_mac_1_16 = tileMac_r_7_13;
        _zz_quantRequest_payload_mac_1_17 = tileMac_r_7_14;
        _zz_quantRequest_payload_mac_1_18 = tileMac_r_7_15;
      end
      4'b1000 : begin
        _zz_quantRequest_payload_mac_1_3 = tileMac_r_8_0;
        _zz_quantRequest_payload_mac_1_4 = tileMac_r_8_1;
        _zz_quantRequest_payload_mac_1_5 = tileMac_r_8_2;
        _zz_quantRequest_payload_mac_1_6 = tileMac_r_8_3;
        _zz_quantRequest_payload_mac_1_7 = tileMac_r_8_4;
        _zz_quantRequest_payload_mac_1_8 = tileMac_r_8_5;
        _zz_quantRequest_payload_mac_1_9 = tileMac_r_8_6;
        _zz_quantRequest_payload_mac_1_10 = tileMac_r_8_7;
        _zz_quantRequest_payload_mac_1_11 = tileMac_r_8_8;
        _zz_quantRequest_payload_mac_1_12 = tileMac_r_8_9;
        _zz_quantRequest_payload_mac_1_13 = tileMac_r_8_10;
        _zz_quantRequest_payload_mac_1_14 = tileMac_r_8_11;
        _zz_quantRequest_payload_mac_1_15 = tileMac_r_8_12;
        _zz_quantRequest_payload_mac_1_16 = tileMac_r_8_13;
        _zz_quantRequest_payload_mac_1_17 = tileMac_r_8_14;
        _zz_quantRequest_payload_mac_1_18 = tileMac_r_8_15;
      end
      4'b1001 : begin
        _zz_quantRequest_payload_mac_1_3 = tileMac_r_9_0;
        _zz_quantRequest_payload_mac_1_4 = tileMac_r_9_1;
        _zz_quantRequest_payload_mac_1_5 = tileMac_r_9_2;
        _zz_quantRequest_payload_mac_1_6 = tileMac_r_9_3;
        _zz_quantRequest_payload_mac_1_7 = tileMac_r_9_4;
        _zz_quantRequest_payload_mac_1_8 = tileMac_r_9_5;
        _zz_quantRequest_payload_mac_1_9 = tileMac_r_9_6;
        _zz_quantRequest_payload_mac_1_10 = tileMac_r_9_7;
        _zz_quantRequest_payload_mac_1_11 = tileMac_r_9_8;
        _zz_quantRequest_payload_mac_1_12 = tileMac_r_9_9;
        _zz_quantRequest_payload_mac_1_13 = tileMac_r_9_10;
        _zz_quantRequest_payload_mac_1_14 = tileMac_r_9_11;
        _zz_quantRequest_payload_mac_1_15 = tileMac_r_9_12;
        _zz_quantRequest_payload_mac_1_16 = tileMac_r_9_13;
        _zz_quantRequest_payload_mac_1_17 = tileMac_r_9_14;
        _zz_quantRequest_payload_mac_1_18 = tileMac_r_9_15;
      end
      4'b1010 : begin
        _zz_quantRequest_payload_mac_1_3 = tileMac_r_10_0;
        _zz_quantRequest_payload_mac_1_4 = tileMac_r_10_1;
        _zz_quantRequest_payload_mac_1_5 = tileMac_r_10_2;
        _zz_quantRequest_payload_mac_1_6 = tileMac_r_10_3;
        _zz_quantRequest_payload_mac_1_7 = tileMac_r_10_4;
        _zz_quantRequest_payload_mac_1_8 = tileMac_r_10_5;
        _zz_quantRequest_payload_mac_1_9 = tileMac_r_10_6;
        _zz_quantRequest_payload_mac_1_10 = tileMac_r_10_7;
        _zz_quantRequest_payload_mac_1_11 = tileMac_r_10_8;
        _zz_quantRequest_payload_mac_1_12 = tileMac_r_10_9;
        _zz_quantRequest_payload_mac_1_13 = tileMac_r_10_10;
        _zz_quantRequest_payload_mac_1_14 = tileMac_r_10_11;
        _zz_quantRequest_payload_mac_1_15 = tileMac_r_10_12;
        _zz_quantRequest_payload_mac_1_16 = tileMac_r_10_13;
        _zz_quantRequest_payload_mac_1_17 = tileMac_r_10_14;
        _zz_quantRequest_payload_mac_1_18 = tileMac_r_10_15;
      end
      4'b1011 : begin
        _zz_quantRequest_payload_mac_1_3 = tileMac_r_11_0;
        _zz_quantRequest_payload_mac_1_4 = tileMac_r_11_1;
        _zz_quantRequest_payload_mac_1_5 = tileMac_r_11_2;
        _zz_quantRequest_payload_mac_1_6 = tileMac_r_11_3;
        _zz_quantRequest_payload_mac_1_7 = tileMac_r_11_4;
        _zz_quantRequest_payload_mac_1_8 = tileMac_r_11_5;
        _zz_quantRequest_payload_mac_1_9 = tileMac_r_11_6;
        _zz_quantRequest_payload_mac_1_10 = tileMac_r_11_7;
        _zz_quantRequest_payload_mac_1_11 = tileMac_r_11_8;
        _zz_quantRequest_payload_mac_1_12 = tileMac_r_11_9;
        _zz_quantRequest_payload_mac_1_13 = tileMac_r_11_10;
        _zz_quantRequest_payload_mac_1_14 = tileMac_r_11_11;
        _zz_quantRequest_payload_mac_1_15 = tileMac_r_11_12;
        _zz_quantRequest_payload_mac_1_16 = tileMac_r_11_13;
        _zz_quantRequest_payload_mac_1_17 = tileMac_r_11_14;
        _zz_quantRequest_payload_mac_1_18 = tileMac_r_11_15;
      end
      4'b1100 : begin
        _zz_quantRequest_payload_mac_1_3 = tileMac_r_12_0;
        _zz_quantRequest_payload_mac_1_4 = tileMac_r_12_1;
        _zz_quantRequest_payload_mac_1_5 = tileMac_r_12_2;
        _zz_quantRequest_payload_mac_1_6 = tileMac_r_12_3;
        _zz_quantRequest_payload_mac_1_7 = tileMac_r_12_4;
        _zz_quantRequest_payload_mac_1_8 = tileMac_r_12_5;
        _zz_quantRequest_payload_mac_1_9 = tileMac_r_12_6;
        _zz_quantRequest_payload_mac_1_10 = tileMac_r_12_7;
        _zz_quantRequest_payload_mac_1_11 = tileMac_r_12_8;
        _zz_quantRequest_payload_mac_1_12 = tileMac_r_12_9;
        _zz_quantRequest_payload_mac_1_13 = tileMac_r_12_10;
        _zz_quantRequest_payload_mac_1_14 = tileMac_r_12_11;
        _zz_quantRequest_payload_mac_1_15 = tileMac_r_12_12;
        _zz_quantRequest_payload_mac_1_16 = tileMac_r_12_13;
        _zz_quantRequest_payload_mac_1_17 = tileMac_r_12_14;
        _zz_quantRequest_payload_mac_1_18 = tileMac_r_12_15;
      end
      4'b1101 : begin
        _zz_quantRequest_payload_mac_1_3 = tileMac_r_13_0;
        _zz_quantRequest_payload_mac_1_4 = tileMac_r_13_1;
        _zz_quantRequest_payload_mac_1_5 = tileMac_r_13_2;
        _zz_quantRequest_payload_mac_1_6 = tileMac_r_13_3;
        _zz_quantRequest_payload_mac_1_7 = tileMac_r_13_4;
        _zz_quantRequest_payload_mac_1_8 = tileMac_r_13_5;
        _zz_quantRequest_payload_mac_1_9 = tileMac_r_13_6;
        _zz_quantRequest_payload_mac_1_10 = tileMac_r_13_7;
        _zz_quantRequest_payload_mac_1_11 = tileMac_r_13_8;
        _zz_quantRequest_payload_mac_1_12 = tileMac_r_13_9;
        _zz_quantRequest_payload_mac_1_13 = tileMac_r_13_10;
        _zz_quantRequest_payload_mac_1_14 = tileMac_r_13_11;
        _zz_quantRequest_payload_mac_1_15 = tileMac_r_13_12;
        _zz_quantRequest_payload_mac_1_16 = tileMac_r_13_13;
        _zz_quantRequest_payload_mac_1_17 = tileMac_r_13_14;
        _zz_quantRequest_payload_mac_1_18 = tileMac_r_13_15;
      end
      4'b1110 : begin
        _zz_quantRequest_payload_mac_1_3 = tileMac_r_14_0;
        _zz_quantRequest_payload_mac_1_4 = tileMac_r_14_1;
        _zz_quantRequest_payload_mac_1_5 = tileMac_r_14_2;
        _zz_quantRequest_payload_mac_1_6 = tileMac_r_14_3;
        _zz_quantRequest_payload_mac_1_7 = tileMac_r_14_4;
        _zz_quantRequest_payload_mac_1_8 = tileMac_r_14_5;
        _zz_quantRequest_payload_mac_1_9 = tileMac_r_14_6;
        _zz_quantRequest_payload_mac_1_10 = tileMac_r_14_7;
        _zz_quantRequest_payload_mac_1_11 = tileMac_r_14_8;
        _zz_quantRequest_payload_mac_1_12 = tileMac_r_14_9;
        _zz_quantRequest_payload_mac_1_13 = tileMac_r_14_10;
        _zz_quantRequest_payload_mac_1_14 = tileMac_r_14_11;
        _zz_quantRequest_payload_mac_1_15 = tileMac_r_14_12;
        _zz_quantRequest_payload_mac_1_16 = tileMac_r_14_13;
        _zz_quantRequest_payload_mac_1_17 = tileMac_r_14_14;
        _zz_quantRequest_payload_mac_1_18 = tileMac_r_14_15;
      end
      default : begin
        _zz_quantRequest_payload_mac_1_3 = tileMac_r_15_0;
        _zz_quantRequest_payload_mac_1_4 = tileMac_r_15_1;
        _zz_quantRequest_payload_mac_1_5 = tileMac_r_15_2;
        _zz_quantRequest_payload_mac_1_6 = tileMac_r_15_3;
        _zz_quantRequest_payload_mac_1_7 = tileMac_r_15_4;
        _zz_quantRequest_payload_mac_1_8 = tileMac_r_15_5;
        _zz_quantRequest_payload_mac_1_9 = tileMac_r_15_6;
        _zz_quantRequest_payload_mac_1_10 = tileMac_r_15_7;
        _zz_quantRequest_payload_mac_1_11 = tileMac_r_15_8;
        _zz_quantRequest_payload_mac_1_12 = tileMac_r_15_9;
        _zz_quantRequest_payload_mac_1_13 = tileMac_r_15_10;
        _zz_quantRequest_payload_mac_1_14 = tileMac_r_15_11;
        _zz_quantRequest_payload_mac_1_15 = tileMac_r_15_12;
        _zz_quantRequest_payload_mac_1_16 = tileMac_r_15_13;
        _zz_quantRequest_payload_mac_1_17 = tileMac_r_15_14;
        _zz_quantRequest_payload_mac_1_18 = tileMac_r_15_15;
      end
    endcase
  end

  always @(*) begin
    case(_zz_quantRequest_payload_mac_2_2)
      4'b0000 : _zz_quantRequest_payload_mac_2_1 = _zz_quantRequest_payload_mac_2_3;
      4'b0001 : _zz_quantRequest_payload_mac_2_1 = _zz_quantRequest_payload_mac_2_4;
      4'b0010 : _zz_quantRequest_payload_mac_2_1 = _zz_quantRequest_payload_mac_2_5;
      4'b0011 : _zz_quantRequest_payload_mac_2_1 = _zz_quantRequest_payload_mac_2_6;
      4'b0100 : _zz_quantRequest_payload_mac_2_1 = _zz_quantRequest_payload_mac_2_7;
      4'b0101 : _zz_quantRequest_payload_mac_2_1 = _zz_quantRequest_payload_mac_2_8;
      4'b0110 : _zz_quantRequest_payload_mac_2_1 = _zz_quantRequest_payload_mac_2_9;
      4'b0111 : _zz_quantRequest_payload_mac_2_1 = _zz_quantRequest_payload_mac_2_10;
      4'b1000 : _zz_quantRequest_payload_mac_2_1 = _zz_quantRequest_payload_mac_2_11;
      4'b1001 : _zz_quantRequest_payload_mac_2_1 = _zz_quantRequest_payload_mac_2_12;
      4'b1010 : _zz_quantRequest_payload_mac_2_1 = _zz_quantRequest_payload_mac_2_13;
      4'b1011 : _zz_quantRequest_payload_mac_2_1 = _zz_quantRequest_payload_mac_2_14;
      4'b1100 : _zz_quantRequest_payload_mac_2_1 = _zz_quantRequest_payload_mac_2_15;
      4'b1101 : _zz_quantRequest_payload_mac_2_1 = _zz_quantRequest_payload_mac_2_16;
      4'b1110 : _zz_quantRequest_payload_mac_2_1 = _zz_quantRequest_payload_mac_2_17;
      default : _zz_quantRequest_payload_mac_2_1 = _zz_quantRequest_payload_mac_2_18;
    endcase
  end

  always @(*) begin
    case(_zz_quantRequest_payload_mac_2)
      4'b0000 : begin
        _zz_quantRequest_payload_mac_2_3 = tileMac_r_0_0;
        _zz_quantRequest_payload_mac_2_4 = tileMac_r_0_1;
        _zz_quantRequest_payload_mac_2_5 = tileMac_r_0_2;
        _zz_quantRequest_payload_mac_2_6 = tileMac_r_0_3;
        _zz_quantRequest_payload_mac_2_7 = tileMac_r_0_4;
        _zz_quantRequest_payload_mac_2_8 = tileMac_r_0_5;
        _zz_quantRequest_payload_mac_2_9 = tileMac_r_0_6;
        _zz_quantRequest_payload_mac_2_10 = tileMac_r_0_7;
        _zz_quantRequest_payload_mac_2_11 = tileMac_r_0_8;
        _zz_quantRequest_payload_mac_2_12 = tileMac_r_0_9;
        _zz_quantRequest_payload_mac_2_13 = tileMac_r_0_10;
        _zz_quantRequest_payload_mac_2_14 = tileMac_r_0_11;
        _zz_quantRequest_payload_mac_2_15 = tileMac_r_0_12;
        _zz_quantRequest_payload_mac_2_16 = tileMac_r_0_13;
        _zz_quantRequest_payload_mac_2_17 = tileMac_r_0_14;
        _zz_quantRequest_payload_mac_2_18 = tileMac_r_0_15;
      end
      4'b0001 : begin
        _zz_quantRequest_payload_mac_2_3 = tileMac_r_1_0;
        _zz_quantRequest_payload_mac_2_4 = tileMac_r_1_1;
        _zz_quantRequest_payload_mac_2_5 = tileMac_r_1_2;
        _zz_quantRequest_payload_mac_2_6 = tileMac_r_1_3;
        _zz_quantRequest_payload_mac_2_7 = tileMac_r_1_4;
        _zz_quantRequest_payload_mac_2_8 = tileMac_r_1_5;
        _zz_quantRequest_payload_mac_2_9 = tileMac_r_1_6;
        _zz_quantRequest_payload_mac_2_10 = tileMac_r_1_7;
        _zz_quantRequest_payload_mac_2_11 = tileMac_r_1_8;
        _zz_quantRequest_payload_mac_2_12 = tileMac_r_1_9;
        _zz_quantRequest_payload_mac_2_13 = tileMac_r_1_10;
        _zz_quantRequest_payload_mac_2_14 = tileMac_r_1_11;
        _zz_quantRequest_payload_mac_2_15 = tileMac_r_1_12;
        _zz_quantRequest_payload_mac_2_16 = tileMac_r_1_13;
        _zz_quantRequest_payload_mac_2_17 = tileMac_r_1_14;
        _zz_quantRequest_payload_mac_2_18 = tileMac_r_1_15;
      end
      4'b0010 : begin
        _zz_quantRequest_payload_mac_2_3 = tileMac_r_2_0;
        _zz_quantRequest_payload_mac_2_4 = tileMac_r_2_1;
        _zz_quantRequest_payload_mac_2_5 = tileMac_r_2_2;
        _zz_quantRequest_payload_mac_2_6 = tileMac_r_2_3;
        _zz_quantRequest_payload_mac_2_7 = tileMac_r_2_4;
        _zz_quantRequest_payload_mac_2_8 = tileMac_r_2_5;
        _zz_quantRequest_payload_mac_2_9 = tileMac_r_2_6;
        _zz_quantRequest_payload_mac_2_10 = tileMac_r_2_7;
        _zz_quantRequest_payload_mac_2_11 = tileMac_r_2_8;
        _zz_quantRequest_payload_mac_2_12 = tileMac_r_2_9;
        _zz_quantRequest_payload_mac_2_13 = tileMac_r_2_10;
        _zz_quantRequest_payload_mac_2_14 = tileMac_r_2_11;
        _zz_quantRequest_payload_mac_2_15 = tileMac_r_2_12;
        _zz_quantRequest_payload_mac_2_16 = tileMac_r_2_13;
        _zz_quantRequest_payload_mac_2_17 = tileMac_r_2_14;
        _zz_quantRequest_payload_mac_2_18 = tileMac_r_2_15;
      end
      4'b0011 : begin
        _zz_quantRequest_payload_mac_2_3 = tileMac_r_3_0;
        _zz_quantRequest_payload_mac_2_4 = tileMac_r_3_1;
        _zz_quantRequest_payload_mac_2_5 = tileMac_r_3_2;
        _zz_quantRequest_payload_mac_2_6 = tileMac_r_3_3;
        _zz_quantRequest_payload_mac_2_7 = tileMac_r_3_4;
        _zz_quantRequest_payload_mac_2_8 = tileMac_r_3_5;
        _zz_quantRequest_payload_mac_2_9 = tileMac_r_3_6;
        _zz_quantRequest_payload_mac_2_10 = tileMac_r_3_7;
        _zz_quantRequest_payload_mac_2_11 = tileMac_r_3_8;
        _zz_quantRequest_payload_mac_2_12 = tileMac_r_3_9;
        _zz_quantRequest_payload_mac_2_13 = tileMac_r_3_10;
        _zz_quantRequest_payload_mac_2_14 = tileMac_r_3_11;
        _zz_quantRequest_payload_mac_2_15 = tileMac_r_3_12;
        _zz_quantRequest_payload_mac_2_16 = tileMac_r_3_13;
        _zz_quantRequest_payload_mac_2_17 = tileMac_r_3_14;
        _zz_quantRequest_payload_mac_2_18 = tileMac_r_3_15;
      end
      4'b0100 : begin
        _zz_quantRequest_payload_mac_2_3 = tileMac_r_4_0;
        _zz_quantRequest_payload_mac_2_4 = tileMac_r_4_1;
        _zz_quantRequest_payload_mac_2_5 = tileMac_r_4_2;
        _zz_quantRequest_payload_mac_2_6 = tileMac_r_4_3;
        _zz_quantRequest_payload_mac_2_7 = tileMac_r_4_4;
        _zz_quantRequest_payload_mac_2_8 = tileMac_r_4_5;
        _zz_quantRequest_payload_mac_2_9 = tileMac_r_4_6;
        _zz_quantRequest_payload_mac_2_10 = tileMac_r_4_7;
        _zz_quantRequest_payload_mac_2_11 = tileMac_r_4_8;
        _zz_quantRequest_payload_mac_2_12 = tileMac_r_4_9;
        _zz_quantRequest_payload_mac_2_13 = tileMac_r_4_10;
        _zz_quantRequest_payload_mac_2_14 = tileMac_r_4_11;
        _zz_quantRequest_payload_mac_2_15 = tileMac_r_4_12;
        _zz_quantRequest_payload_mac_2_16 = tileMac_r_4_13;
        _zz_quantRequest_payload_mac_2_17 = tileMac_r_4_14;
        _zz_quantRequest_payload_mac_2_18 = tileMac_r_4_15;
      end
      4'b0101 : begin
        _zz_quantRequest_payload_mac_2_3 = tileMac_r_5_0;
        _zz_quantRequest_payload_mac_2_4 = tileMac_r_5_1;
        _zz_quantRequest_payload_mac_2_5 = tileMac_r_5_2;
        _zz_quantRequest_payload_mac_2_6 = tileMac_r_5_3;
        _zz_quantRequest_payload_mac_2_7 = tileMac_r_5_4;
        _zz_quantRequest_payload_mac_2_8 = tileMac_r_5_5;
        _zz_quantRequest_payload_mac_2_9 = tileMac_r_5_6;
        _zz_quantRequest_payload_mac_2_10 = tileMac_r_5_7;
        _zz_quantRequest_payload_mac_2_11 = tileMac_r_5_8;
        _zz_quantRequest_payload_mac_2_12 = tileMac_r_5_9;
        _zz_quantRequest_payload_mac_2_13 = tileMac_r_5_10;
        _zz_quantRequest_payload_mac_2_14 = tileMac_r_5_11;
        _zz_quantRequest_payload_mac_2_15 = tileMac_r_5_12;
        _zz_quantRequest_payload_mac_2_16 = tileMac_r_5_13;
        _zz_quantRequest_payload_mac_2_17 = tileMac_r_5_14;
        _zz_quantRequest_payload_mac_2_18 = tileMac_r_5_15;
      end
      4'b0110 : begin
        _zz_quantRequest_payload_mac_2_3 = tileMac_r_6_0;
        _zz_quantRequest_payload_mac_2_4 = tileMac_r_6_1;
        _zz_quantRequest_payload_mac_2_5 = tileMac_r_6_2;
        _zz_quantRequest_payload_mac_2_6 = tileMac_r_6_3;
        _zz_quantRequest_payload_mac_2_7 = tileMac_r_6_4;
        _zz_quantRequest_payload_mac_2_8 = tileMac_r_6_5;
        _zz_quantRequest_payload_mac_2_9 = tileMac_r_6_6;
        _zz_quantRequest_payload_mac_2_10 = tileMac_r_6_7;
        _zz_quantRequest_payload_mac_2_11 = tileMac_r_6_8;
        _zz_quantRequest_payload_mac_2_12 = tileMac_r_6_9;
        _zz_quantRequest_payload_mac_2_13 = tileMac_r_6_10;
        _zz_quantRequest_payload_mac_2_14 = tileMac_r_6_11;
        _zz_quantRequest_payload_mac_2_15 = tileMac_r_6_12;
        _zz_quantRequest_payload_mac_2_16 = tileMac_r_6_13;
        _zz_quantRequest_payload_mac_2_17 = tileMac_r_6_14;
        _zz_quantRequest_payload_mac_2_18 = tileMac_r_6_15;
      end
      4'b0111 : begin
        _zz_quantRequest_payload_mac_2_3 = tileMac_r_7_0;
        _zz_quantRequest_payload_mac_2_4 = tileMac_r_7_1;
        _zz_quantRequest_payload_mac_2_5 = tileMac_r_7_2;
        _zz_quantRequest_payload_mac_2_6 = tileMac_r_7_3;
        _zz_quantRequest_payload_mac_2_7 = tileMac_r_7_4;
        _zz_quantRequest_payload_mac_2_8 = tileMac_r_7_5;
        _zz_quantRequest_payload_mac_2_9 = tileMac_r_7_6;
        _zz_quantRequest_payload_mac_2_10 = tileMac_r_7_7;
        _zz_quantRequest_payload_mac_2_11 = tileMac_r_7_8;
        _zz_quantRequest_payload_mac_2_12 = tileMac_r_7_9;
        _zz_quantRequest_payload_mac_2_13 = tileMac_r_7_10;
        _zz_quantRequest_payload_mac_2_14 = tileMac_r_7_11;
        _zz_quantRequest_payload_mac_2_15 = tileMac_r_7_12;
        _zz_quantRequest_payload_mac_2_16 = tileMac_r_7_13;
        _zz_quantRequest_payload_mac_2_17 = tileMac_r_7_14;
        _zz_quantRequest_payload_mac_2_18 = tileMac_r_7_15;
      end
      4'b1000 : begin
        _zz_quantRequest_payload_mac_2_3 = tileMac_r_8_0;
        _zz_quantRequest_payload_mac_2_4 = tileMac_r_8_1;
        _zz_quantRequest_payload_mac_2_5 = tileMac_r_8_2;
        _zz_quantRequest_payload_mac_2_6 = tileMac_r_8_3;
        _zz_quantRequest_payload_mac_2_7 = tileMac_r_8_4;
        _zz_quantRequest_payload_mac_2_8 = tileMac_r_8_5;
        _zz_quantRequest_payload_mac_2_9 = tileMac_r_8_6;
        _zz_quantRequest_payload_mac_2_10 = tileMac_r_8_7;
        _zz_quantRequest_payload_mac_2_11 = tileMac_r_8_8;
        _zz_quantRequest_payload_mac_2_12 = tileMac_r_8_9;
        _zz_quantRequest_payload_mac_2_13 = tileMac_r_8_10;
        _zz_quantRequest_payload_mac_2_14 = tileMac_r_8_11;
        _zz_quantRequest_payload_mac_2_15 = tileMac_r_8_12;
        _zz_quantRequest_payload_mac_2_16 = tileMac_r_8_13;
        _zz_quantRequest_payload_mac_2_17 = tileMac_r_8_14;
        _zz_quantRequest_payload_mac_2_18 = tileMac_r_8_15;
      end
      4'b1001 : begin
        _zz_quantRequest_payload_mac_2_3 = tileMac_r_9_0;
        _zz_quantRequest_payload_mac_2_4 = tileMac_r_9_1;
        _zz_quantRequest_payload_mac_2_5 = tileMac_r_9_2;
        _zz_quantRequest_payload_mac_2_6 = tileMac_r_9_3;
        _zz_quantRequest_payload_mac_2_7 = tileMac_r_9_4;
        _zz_quantRequest_payload_mac_2_8 = tileMac_r_9_5;
        _zz_quantRequest_payload_mac_2_9 = tileMac_r_9_6;
        _zz_quantRequest_payload_mac_2_10 = tileMac_r_9_7;
        _zz_quantRequest_payload_mac_2_11 = tileMac_r_9_8;
        _zz_quantRequest_payload_mac_2_12 = tileMac_r_9_9;
        _zz_quantRequest_payload_mac_2_13 = tileMac_r_9_10;
        _zz_quantRequest_payload_mac_2_14 = tileMac_r_9_11;
        _zz_quantRequest_payload_mac_2_15 = tileMac_r_9_12;
        _zz_quantRequest_payload_mac_2_16 = tileMac_r_9_13;
        _zz_quantRequest_payload_mac_2_17 = tileMac_r_9_14;
        _zz_quantRequest_payload_mac_2_18 = tileMac_r_9_15;
      end
      4'b1010 : begin
        _zz_quantRequest_payload_mac_2_3 = tileMac_r_10_0;
        _zz_quantRequest_payload_mac_2_4 = tileMac_r_10_1;
        _zz_quantRequest_payload_mac_2_5 = tileMac_r_10_2;
        _zz_quantRequest_payload_mac_2_6 = tileMac_r_10_3;
        _zz_quantRequest_payload_mac_2_7 = tileMac_r_10_4;
        _zz_quantRequest_payload_mac_2_8 = tileMac_r_10_5;
        _zz_quantRequest_payload_mac_2_9 = tileMac_r_10_6;
        _zz_quantRequest_payload_mac_2_10 = tileMac_r_10_7;
        _zz_quantRequest_payload_mac_2_11 = tileMac_r_10_8;
        _zz_quantRequest_payload_mac_2_12 = tileMac_r_10_9;
        _zz_quantRequest_payload_mac_2_13 = tileMac_r_10_10;
        _zz_quantRequest_payload_mac_2_14 = tileMac_r_10_11;
        _zz_quantRequest_payload_mac_2_15 = tileMac_r_10_12;
        _zz_quantRequest_payload_mac_2_16 = tileMac_r_10_13;
        _zz_quantRequest_payload_mac_2_17 = tileMac_r_10_14;
        _zz_quantRequest_payload_mac_2_18 = tileMac_r_10_15;
      end
      4'b1011 : begin
        _zz_quantRequest_payload_mac_2_3 = tileMac_r_11_0;
        _zz_quantRequest_payload_mac_2_4 = tileMac_r_11_1;
        _zz_quantRequest_payload_mac_2_5 = tileMac_r_11_2;
        _zz_quantRequest_payload_mac_2_6 = tileMac_r_11_3;
        _zz_quantRequest_payload_mac_2_7 = tileMac_r_11_4;
        _zz_quantRequest_payload_mac_2_8 = tileMac_r_11_5;
        _zz_quantRequest_payload_mac_2_9 = tileMac_r_11_6;
        _zz_quantRequest_payload_mac_2_10 = tileMac_r_11_7;
        _zz_quantRequest_payload_mac_2_11 = tileMac_r_11_8;
        _zz_quantRequest_payload_mac_2_12 = tileMac_r_11_9;
        _zz_quantRequest_payload_mac_2_13 = tileMac_r_11_10;
        _zz_quantRequest_payload_mac_2_14 = tileMac_r_11_11;
        _zz_quantRequest_payload_mac_2_15 = tileMac_r_11_12;
        _zz_quantRequest_payload_mac_2_16 = tileMac_r_11_13;
        _zz_quantRequest_payload_mac_2_17 = tileMac_r_11_14;
        _zz_quantRequest_payload_mac_2_18 = tileMac_r_11_15;
      end
      4'b1100 : begin
        _zz_quantRequest_payload_mac_2_3 = tileMac_r_12_0;
        _zz_quantRequest_payload_mac_2_4 = tileMac_r_12_1;
        _zz_quantRequest_payload_mac_2_5 = tileMac_r_12_2;
        _zz_quantRequest_payload_mac_2_6 = tileMac_r_12_3;
        _zz_quantRequest_payload_mac_2_7 = tileMac_r_12_4;
        _zz_quantRequest_payload_mac_2_8 = tileMac_r_12_5;
        _zz_quantRequest_payload_mac_2_9 = tileMac_r_12_6;
        _zz_quantRequest_payload_mac_2_10 = tileMac_r_12_7;
        _zz_quantRequest_payload_mac_2_11 = tileMac_r_12_8;
        _zz_quantRequest_payload_mac_2_12 = tileMac_r_12_9;
        _zz_quantRequest_payload_mac_2_13 = tileMac_r_12_10;
        _zz_quantRequest_payload_mac_2_14 = tileMac_r_12_11;
        _zz_quantRequest_payload_mac_2_15 = tileMac_r_12_12;
        _zz_quantRequest_payload_mac_2_16 = tileMac_r_12_13;
        _zz_quantRequest_payload_mac_2_17 = tileMac_r_12_14;
        _zz_quantRequest_payload_mac_2_18 = tileMac_r_12_15;
      end
      4'b1101 : begin
        _zz_quantRequest_payload_mac_2_3 = tileMac_r_13_0;
        _zz_quantRequest_payload_mac_2_4 = tileMac_r_13_1;
        _zz_quantRequest_payload_mac_2_5 = tileMac_r_13_2;
        _zz_quantRequest_payload_mac_2_6 = tileMac_r_13_3;
        _zz_quantRequest_payload_mac_2_7 = tileMac_r_13_4;
        _zz_quantRequest_payload_mac_2_8 = tileMac_r_13_5;
        _zz_quantRequest_payload_mac_2_9 = tileMac_r_13_6;
        _zz_quantRequest_payload_mac_2_10 = tileMac_r_13_7;
        _zz_quantRequest_payload_mac_2_11 = tileMac_r_13_8;
        _zz_quantRequest_payload_mac_2_12 = tileMac_r_13_9;
        _zz_quantRequest_payload_mac_2_13 = tileMac_r_13_10;
        _zz_quantRequest_payload_mac_2_14 = tileMac_r_13_11;
        _zz_quantRequest_payload_mac_2_15 = tileMac_r_13_12;
        _zz_quantRequest_payload_mac_2_16 = tileMac_r_13_13;
        _zz_quantRequest_payload_mac_2_17 = tileMac_r_13_14;
        _zz_quantRequest_payload_mac_2_18 = tileMac_r_13_15;
      end
      4'b1110 : begin
        _zz_quantRequest_payload_mac_2_3 = tileMac_r_14_0;
        _zz_quantRequest_payload_mac_2_4 = tileMac_r_14_1;
        _zz_quantRequest_payload_mac_2_5 = tileMac_r_14_2;
        _zz_quantRequest_payload_mac_2_6 = tileMac_r_14_3;
        _zz_quantRequest_payload_mac_2_7 = tileMac_r_14_4;
        _zz_quantRequest_payload_mac_2_8 = tileMac_r_14_5;
        _zz_quantRequest_payload_mac_2_9 = tileMac_r_14_6;
        _zz_quantRequest_payload_mac_2_10 = tileMac_r_14_7;
        _zz_quantRequest_payload_mac_2_11 = tileMac_r_14_8;
        _zz_quantRequest_payload_mac_2_12 = tileMac_r_14_9;
        _zz_quantRequest_payload_mac_2_13 = tileMac_r_14_10;
        _zz_quantRequest_payload_mac_2_14 = tileMac_r_14_11;
        _zz_quantRequest_payload_mac_2_15 = tileMac_r_14_12;
        _zz_quantRequest_payload_mac_2_16 = tileMac_r_14_13;
        _zz_quantRequest_payload_mac_2_17 = tileMac_r_14_14;
        _zz_quantRequest_payload_mac_2_18 = tileMac_r_14_15;
      end
      default : begin
        _zz_quantRequest_payload_mac_2_3 = tileMac_r_15_0;
        _zz_quantRequest_payload_mac_2_4 = tileMac_r_15_1;
        _zz_quantRequest_payload_mac_2_5 = tileMac_r_15_2;
        _zz_quantRequest_payload_mac_2_6 = tileMac_r_15_3;
        _zz_quantRequest_payload_mac_2_7 = tileMac_r_15_4;
        _zz_quantRequest_payload_mac_2_8 = tileMac_r_15_5;
        _zz_quantRequest_payload_mac_2_9 = tileMac_r_15_6;
        _zz_quantRequest_payload_mac_2_10 = tileMac_r_15_7;
        _zz_quantRequest_payload_mac_2_11 = tileMac_r_15_8;
        _zz_quantRequest_payload_mac_2_12 = tileMac_r_15_9;
        _zz_quantRequest_payload_mac_2_13 = tileMac_r_15_10;
        _zz_quantRequest_payload_mac_2_14 = tileMac_r_15_11;
        _zz_quantRequest_payload_mac_2_15 = tileMac_r_15_12;
        _zz_quantRequest_payload_mac_2_16 = tileMac_r_15_13;
        _zz_quantRequest_payload_mac_2_17 = tileMac_r_15_14;
        _zz_quantRequest_payload_mac_2_18 = tileMac_r_15_15;
      end
    endcase
  end

  always @(*) begin
    case(_zz_quantRequest_payload_mac_3_2)
      4'b0000 : _zz_quantRequest_payload_mac_3_1 = _zz_quantRequest_payload_mac_3_3;
      4'b0001 : _zz_quantRequest_payload_mac_3_1 = _zz_quantRequest_payload_mac_3_4;
      4'b0010 : _zz_quantRequest_payload_mac_3_1 = _zz_quantRequest_payload_mac_3_5;
      4'b0011 : _zz_quantRequest_payload_mac_3_1 = _zz_quantRequest_payload_mac_3_6;
      4'b0100 : _zz_quantRequest_payload_mac_3_1 = _zz_quantRequest_payload_mac_3_7;
      4'b0101 : _zz_quantRequest_payload_mac_3_1 = _zz_quantRequest_payload_mac_3_8;
      4'b0110 : _zz_quantRequest_payload_mac_3_1 = _zz_quantRequest_payload_mac_3_9;
      4'b0111 : _zz_quantRequest_payload_mac_3_1 = _zz_quantRequest_payload_mac_3_10;
      4'b1000 : _zz_quantRequest_payload_mac_3_1 = _zz_quantRequest_payload_mac_3_11;
      4'b1001 : _zz_quantRequest_payload_mac_3_1 = _zz_quantRequest_payload_mac_3_12;
      4'b1010 : _zz_quantRequest_payload_mac_3_1 = _zz_quantRequest_payload_mac_3_13;
      4'b1011 : _zz_quantRequest_payload_mac_3_1 = _zz_quantRequest_payload_mac_3_14;
      4'b1100 : _zz_quantRequest_payload_mac_3_1 = _zz_quantRequest_payload_mac_3_15;
      4'b1101 : _zz_quantRequest_payload_mac_3_1 = _zz_quantRequest_payload_mac_3_16;
      4'b1110 : _zz_quantRequest_payload_mac_3_1 = _zz_quantRequest_payload_mac_3_17;
      default : _zz_quantRequest_payload_mac_3_1 = _zz_quantRequest_payload_mac_3_18;
    endcase
  end

  always @(*) begin
    case(_zz_quantRequest_payload_mac_3)
      4'b0000 : begin
        _zz_quantRequest_payload_mac_3_3 = tileMac_r_0_0;
        _zz_quantRequest_payload_mac_3_4 = tileMac_r_0_1;
        _zz_quantRequest_payload_mac_3_5 = tileMac_r_0_2;
        _zz_quantRequest_payload_mac_3_6 = tileMac_r_0_3;
        _zz_quantRequest_payload_mac_3_7 = tileMac_r_0_4;
        _zz_quantRequest_payload_mac_3_8 = tileMac_r_0_5;
        _zz_quantRequest_payload_mac_3_9 = tileMac_r_0_6;
        _zz_quantRequest_payload_mac_3_10 = tileMac_r_0_7;
        _zz_quantRequest_payload_mac_3_11 = tileMac_r_0_8;
        _zz_quantRequest_payload_mac_3_12 = tileMac_r_0_9;
        _zz_quantRequest_payload_mac_3_13 = tileMac_r_0_10;
        _zz_quantRequest_payload_mac_3_14 = tileMac_r_0_11;
        _zz_quantRequest_payload_mac_3_15 = tileMac_r_0_12;
        _zz_quantRequest_payload_mac_3_16 = tileMac_r_0_13;
        _zz_quantRequest_payload_mac_3_17 = tileMac_r_0_14;
        _zz_quantRequest_payload_mac_3_18 = tileMac_r_0_15;
      end
      4'b0001 : begin
        _zz_quantRequest_payload_mac_3_3 = tileMac_r_1_0;
        _zz_quantRequest_payload_mac_3_4 = tileMac_r_1_1;
        _zz_quantRequest_payload_mac_3_5 = tileMac_r_1_2;
        _zz_quantRequest_payload_mac_3_6 = tileMac_r_1_3;
        _zz_quantRequest_payload_mac_3_7 = tileMac_r_1_4;
        _zz_quantRequest_payload_mac_3_8 = tileMac_r_1_5;
        _zz_quantRequest_payload_mac_3_9 = tileMac_r_1_6;
        _zz_quantRequest_payload_mac_3_10 = tileMac_r_1_7;
        _zz_quantRequest_payload_mac_3_11 = tileMac_r_1_8;
        _zz_quantRequest_payload_mac_3_12 = tileMac_r_1_9;
        _zz_quantRequest_payload_mac_3_13 = tileMac_r_1_10;
        _zz_quantRequest_payload_mac_3_14 = tileMac_r_1_11;
        _zz_quantRequest_payload_mac_3_15 = tileMac_r_1_12;
        _zz_quantRequest_payload_mac_3_16 = tileMac_r_1_13;
        _zz_quantRequest_payload_mac_3_17 = tileMac_r_1_14;
        _zz_quantRequest_payload_mac_3_18 = tileMac_r_1_15;
      end
      4'b0010 : begin
        _zz_quantRequest_payload_mac_3_3 = tileMac_r_2_0;
        _zz_quantRequest_payload_mac_3_4 = tileMac_r_2_1;
        _zz_quantRequest_payload_mac_3_5 = tileMac_r_2_2;
        _zz_quantRequest_payload_mac_3_6 = tileMac_r_2_3;
        _zz_quantRequest_payload_mac_3_7 = tileMac_r_2_4;
        _zz_quantRequest_payload_mac_3_8 = tileMac_r_2_5;
        _zz_quantRequest_payload_mac_3_9 = tileMac_r_2_6;
        _zz_quantRequest_payload_mac_3_10 = tileMac_r_2_7;
        _zz_quantRequest_payload_mac_3_11 = tileMac_r_2_8;
        _zz_quantRequest_payload_mac_3_12 = tileMac_r_2_9;
        _zz_quantRequest_payload_mac_3_13 = tileMac_r_2_10;
        _zz_quantRequest_payload_mac_3_14 = tileMac_r_2_11;
        _zz_quantRequest_payload_mac_3_15 = tileMac_r_2_12;
        _zz_quantRequest_payload_mac_3_16 = tileMac_r_2_13;
        _zz_quantRequest_payload_mac_3_17 = tileMac_r_2_14;
        _zz_quantRequest_payload_mac_3_18 = tileMac_r_2_15;
      end
      4'b0011 : begin
        _zz_quantRequest_payload_mac_3_3 = tileMac_r_3_0;
        _zz_quantRequest_payload_mac_3_4 = tileMac_r_3_1;
        _zz_quantRequest_payload_mac_3_5 = tileMac_r_3_2;
        _zz_quantRequest_payload_mac_3_6 = tileMac_r_3_3;
        _zz_quantRequest_payload_mac_3_7 = tileMac_r_3_4;
        _zz_quantRequest_payload_mac_3_8 = tileMac_r_3_5;
        _zz_quantRequest_payload_mac_3_9 = tileMac_r_3_6;
        _zz_quantRequest_payload_mac_3_10 = tileMac_r_3_7;
        _zz_quantRequest_payload_mac_3_11 = tileMac_r_3_8;
        _zz_quantRequest_payload_mac_3_12 = tileMac_r_3_9;
        _zz_quantRequest_payload_mac_3_13 = tileMac_r_3_10;
        _zz_quantRequest_payload_mac_3_14 = tileMac_r_3_11;
        _zz_quantRequest_payload_mac_3_15 = tileMac_r_3_12;
        _zz_quantRequest_payload_mac_3_16 = tileMac_r_3_13;
        _zz_quantRequest_payload_mac_3_17 = tileMac_r_3_14;
        _zz_quantRequest_payload_mac_3_18 = tileMac_r_3_15;
      end
      4'b0100 : begin
        _zz_quantRequest_payload_mac_3_3 = tileMac_r_4_0;
        _zz_quantRequest_payload_mac_3_4 = tileMac_r_4_1;
        _zz_quantRequest_payload_mac_3_5 = tileMac_r_4_2;
        _zz_quantRequest_payload_mac_3_6 = tileMac_r_4_3;
        _zz_quantRequest_payload_mac_3_7 = tileMac_r_4_4;
        _zz_quantRequest_payload_mac_3_8 = tileMac_r_4_5;
        _zz_quantRequest_payload_mac_3_9 = tileMac_r_4_6;
        _zz_quantRequest_payload_mac_3_10 = tileMac_r_4_7;
        _zz_quantRequest_payload_mac_3_11 = tileMac_r_4_8;
        _zz_quantRequest_payload_mac_3_12 = tileMac_r_4_9;
        _zz_quantRequest_payload_mac_3_13 = tileMac_r_4_10;
        _zz_quantRequest_payload_mac_3_14 = tileMac_r_4_11;
        _zz_quantRequest_payload_mac_3_15 = tileMac_r_4_12;
        _zz_quantRequest_payload_mac_3_16 = tileMac_r_4_13;
        _zz_quantRequest_payload_mac_3_17 = tileMac_r_4_14;
        _zz_quantRequest_payload_mac_3_18 = tileMac_r_4_15;
      end
      4'b0101 : begin
        _zz_quantRequest_payload_mac_3_3 = tileMac_r_5_0;
        _zz_quantRequest_payload_mac_3_4 = tileMac_r_5_1;
        _zz_quantRequest_payload_mac_3_5 = tileMac_r_5_2;
        _zz_quantRequest_payload_mac_3_6 = tileMac_r_5_3;
        _zz_quantRequest_payload_mac_3_7 = tileMac_r_5_4;
        _zz_quantRequest_payload_mac_3_8 = tileMac_r_5_5;
        _zz_quantRequest_payload_mac_3_9 = tileMac_r_5_6;
        _zz_quantRequest_payload_mac_3_10 = tileMac_r_5_7;
        _zz_quantRequest_payload_mac_3_11 = tileMac_r_5_8;
        _zz_quantRequest_payload_mac_3_12 = tileMac_r_5_9;
        _zz_quantRequest_payload_mac_3_13 = tileMac_r_5_10;
        _zz_quantRequest_payload_mac_3_14 = tileMac_r_5_11;
        _zz_quantRequest_payload_mac_3_15 = tileMac_r_5_12;
        _zz_quantRequest_payload_mac_3_16 = tileMac_r_5_13;
        _zz_quantRequest_payload_mac_3_17 = tileMac_r_5_14;
        _zz_quantRequest_payload_mac_3_18 = tileMac_r_5_15;
      end
      4'b0110 : begin
        _zz_quantRequest_payload_mac_3_3 = tileMac_r_6_0;
        _zz_quantRequest_payload_mac_3_4 = tileMac_r_6_1;
        _zz_quantRequest_payload_mac_3_5 = tileMac_r_6_2;
        _zz_quantRequest_payload_mac_3_6 = tileMac_r_6_3;
        _zz_quantRequest_payload_mac_3_7 = tileMac_r_6_4;
        _zz_quantRequest_payload_mac_3_8 = tileMac_r_6_5;
        _zz_quantRequest_payload_mac_3_9 = tileMac_r_6_6;
        _zz_quantRequest_payload_mac_3_10 = tileMac_r_6_7;
        _zz_quantRequest_payload_mac_3_11 = tileMac_r_6_8;
        _zz_quantRequest_payload_mac_3_12 = tileMac_r_6_9;
        _zz_quantRequest_payload_mac_3_13 = tileMac_r_6_10;
        _zz_quantRequest_payload_mac_3_14 = tileMac_r_6_11;
        _zz_quantRequest_payload_mac_3_15 = tileMac_r_6_12;
        _zz_quantRequest_payload_mac_3_16 = tileMac_r_6_13;
        _zz_quantRequest_payload_mac_3_17 = tileMac_r_6_14;
        _zz_quantRequest_payload_mac_3_18 = tileMac_r_6_15;
      end
      4'b0111 : begin
        _zz_quantRequest_payload_mac_3_3 = tileMac_r_7_0;
        _zz_quantRequest_payload_mac_3_4 = tileMac_r_7_1;
        _zz_quantRequest_payload_mac_3_5 = tileMac_r_7_2;
        _zz_quantRequest_payload_mac_3_6 = tileMac_r_7_3;
        _zz_quantRequest_payload_mac_3_7 = tileMac_r_7_4;
        _zz_quantRequest_payload_mac_3_8 = tileMac_r_7_5;
        _zz_quantRequest_payload_mac_3_9 = tileMac_r_7_6;
        _zz_quantRequest_payload_mac_3_10 = tileMac_r_7_7;
        _zz_quantRequest_payload_mac_3_11 = tileMac_r_7_8;
        _zz_quantRequest_payload_mac_3_12 = tileMac_r_7_9;
        _zz_quantRequest_payload_mac_3_13 = tileMac_r_7_10;
        _zz_quantRequest_payload_mac_3_14 = tileMac_r_7_11;
        _zz_quantRequest_payload_mac_3_15 = tileMac_r_7_12;
        _zz_quantRequest_payload_mac_3_16 = tileMac_r_7_13;
        _zz_quantRequest_payload_mac_3_17 = tileMac_r_7_14;
        _zz_quantRequest_payload_mac_3_18 = tileMac_r_7_15;
      end
      4'b1000 : begin
        _zz_quantRequest_payload_mac_3_3 = tileMac_r_8_0;
        _zz_quantRequest_payload_mac_3_4 = tileMac_r_8_1;
        _zz_quantRequest_payload_mac_3_5 = tileMac_r_8_2;
        _zz_quantRequest_payload_mac_3_6 = tileMac_r_8_3;
        _zz_quantRequest_payload_mac_3_7 = tileMac_r_8_4;
        _zz_quantRequest_payload_mac_3_8 = tileMac_r_8_5;
        _zz_quantRequest_payload_mac_3_9 = tileMac_r_8_6;
        _zz_quantRequest_payload_mac_3_10 = tileMac_r_8_7;
        _zz_quantRequest_payload_mac_3_11 = tileMac_r_8_8;
        _zz_quantRequest_payload_mac_3_12 = tileMac_r_8_9;
        _zz_quantRequest_payload_mac_3_13 = tileMac_r_8_10;
        _zz_quantRequest_payload_mac_3_14 = tileMac_r_8_11;
        _zz_quantRequest_payload_mac_3_15 = tileMac_r_8_12;
        _zz_quantRequest_payload_mac_3_16 = tileMac_r_8_13;
        _zz_quantRequest_payload_mac_3_17 = tileMac_r_8_14;
        _zz_quantRequest_payload_mac_3_18 = tileMac_r_8_15;
      end
      4'b1001 : begin
        _zz_quantRequest_payload_mac_3_3 = tileMac_r_9_0;
        _zz_quantRequest_payload_mac_3_4 = tileMac_r_9_1;
        _zz_quantRequest_payload_mac_3_5 = tileMac_r_9_2;
        _zz_quantRequest_payload_mac_3_6 = tileMac_r_9_3;
        _zz_quantRequest_payload_mac_3_7 = tileMac_r_9_4;
        _zz_quantRequest_payload_mac_3_8 = tileMac_r_9_5;
        _zz_quantRequest_payload_mac_3_9 = tileMac_r_9_6;
        _zz_quantRequest_payload_mac_3_10 = tileMac_r_9_7;
        _zz_quantRequest_payload_mac_3_11 = tileMac_r_9_8;
        _zz_quantRequest_payload_mac_3_12 = tileMac_r_9_9;
        _zz_quantRequest_payload_mac_3_13 = tileMac_r_9_10;
        _zz_quantRequest_payload_mac_3_14 = tileMac_r_9_11;
        _zz_quantRequest_payload_mac_3_15 = tileMac_r_9_12;
        _zz_quantRequest_payload_mac_3_16 = tileMac_r_9_13;
        _zz_quantRequest_payload_mac_3_17 = tileMac_r_9_14;
        _zz_quantRequest_payload_mac_3_18 = tileMac_r_9_15;
      end
      4'b1010 : begin
        _zz_quantRequest_payload_mac_3_3 = tileMac_r_10_0;
        _zz_quantRequest_payload_mac_3_4 = tileMac_r_10_1;
        _zz_quantRequest_payload_mac_3_5 = tileMac_r_10_2;
        _zz_quantRequest_payload_mac_3_6 = tileMac_r_10_3;
        _zz_quantRequest_payload_mac_3_7 = tileMac_r_10_4;
        _zz_quantRequest_payload_mac_3_8 = tileMac_r_10_5;
        _zz_quantRequest_payload_mac_3_9 = tileMac_r_10_6;
        _zz_quantRequest_payload_mac_3_10 = tileMac_r_10_7;
        _zz_quantRequest_payload_mac_3_11 = tileMac_r_10_8;
        _zz_quantRequest_payload_mac_3_12 = tileMac_r_10_9;
        _zz_quantRequest_payload_mac_3_13 = tileMac_r_10_10;
        _zz_quantRequest_payload_mac_3_14 = tileMac_r_10_11;
        _zz_quantRequest_payload_mac_3_15 = tileMac_r_10_12;
        _zz_quantRequest_payload_mac_3_16 = tileMac_r_10_13;
        _zz_quantRequest_payload_mac_3_17 = tileMac_r_10_14;
        _zz_quantRequest_payload_mac_3_18 = tileMac_r_10_15;
      end
      4'b1011 : begin
        _zz_quantRequest_payload_mac_3_3 = tileMac_r_11_0;
        _zz_quantRequest_payload_mac_3_4 = tileMac_r_11_1;
        _zz_quantRequest_payload_mac_3_5 = tileMac_r_11_2;
        _zz_quantRequest_payload_mac_3_6 = tileMac_r_11_3;
        _zz_quantRequest_payload_mac_3_7 = tileMac_r_11_4;
        _zz_quantRequest_payload_mac_3_8 = tileMac_r_11_5;
        _zz_quantRequest_payload_mac_3_9 = tileMac_r_11_6;
        _zz_quantRequest_payload_mac_3_10 = tileMac_r_11_7;
        _zz_quantRequest_payload_mac_3_11 = tileMac_r_11_8;
        _zz_quantRequest_payload_mac_3_12 = tileMac_r_11_9;
        _zz_quantRequest_payload_mac_3_13 = tileMac_r_11_10;
        _zz_quantRequest_payload_mac_3_14 = tileMac_r_11_11;
        _zz_quantRequest_payload_mac_3_15 = tileMac_r_11_12;
        _zz_quantRequest_payload_mac_3_16 = tileMac_r_11_13;
        _zz_quantRequest_payload_mac_3_17 = tileMac_r_11_14;
        _zz_quantRequest_payload_mac_3_18 = tileMac_r_11_15;
      end
      4'b1100 : begin
        _zz_quantRequest_payload_mac_3_3 = tileMac_r_12_0;
        _zz_quantRequest_payload_mac_3_4 = tileMac_r_12_1;
        _zz_quantRequest_payload_mac_3_5 = tileMac_r_12_2;
        _zz_quantRequest_payload_mac_3_6 = tileMac_r_12_3;
        _zz_quantRequest_payload_mac_3_7 = tileMac_r_12_4;
        _zz_quantRequest_payload_mac_3_8 = tileMac_r_12_5;
        _zz_quantRequest_payload_mac_3_9 = tileMac_r_12_6;
        _zz_quantRequest_payload_mac_3_10 = tileMac_r_12_7;
        _zz_quantRequest_payload_mac_3_11 = tileMac_r_12_8;
        _zz_quantRequest_payload_mac_3_12 = tileMac_r_12_9;
        _zz_quantRequest_payload_mac_3_13 = tileMac_r_12_10;
        _zz_quantRequest_payload_mac_3_14 = tileMac_r_12_11;
        _zz_quantRequest_payload_mac_3_15 = tileMac_r_12_12;
        _zz_quantRequest_payload_mac_3_16 = tileMac_r_12_13;
        _zz_quantRequest_payload_mac_3_17 = tileMac_r_12_14;
        _zz_quantRequest_payload_mac_3_18 = tileMac_r_12_15;
      end
      4'b1101 : begin
        _zz_quantRequest_payload_mac_3_3 = tileMac_r_13_0;
        _zz_quantRequest_payload_mac_3_4 = tileMac_r_13_1;
        _zz_quantRequest_payload_mac_3_5 = tileMac_r_13_2;
        _zz_quantRequest_payload_mac_3_6 = tileMac_r_13_3;
        _zz_quantRequest_payload_mac_3_7 = tileMac_r_13_4;
        _zz_quantRequest_payload_mac_3_8 = tileMac_r_13_5;
        _zz_quantRequest_payload_mac_3_9 = tileMac_r_13_6;
        _zz_quantRequest_payload_mac_3_10 = tileMac_r_13_7;
        _zz_quantRequest_payload_mac_3_11 = tileMac_r_13_8;
        _zz_quantRequest_payload_mac_3_12 = tileMac_r_13_9;
        _zz_quantRequest_payload_mac_3_13 = tileMac_r_13_10;
        _zz_quantRequest_payload_mac_3_14 = tileMac_r_13_11;
        _zz_quantRequest_payload_mac_3_15 = tileMac_r_13_12;
        _zz_quantRequest_payload_mac_3_16 = tileMac_r_13_13;
        _zz_quantRequest_payload_mac_3_17 = tileMac_r_13_14;
        _zz_quantRequest_payload_mac_3_18 = tileMac_r_13_15;
      end
      4'b1110 : begin
        _zz_quantRequest_payload_mac_3_3 = tileMac_r_14_0;
        _zz_quantRequest_payload_mac_3_4 = tileMac_r_14_1;
        _zz_quantRequest_payload_mac_3_5 = tileMac_r_14_2;
        _zz_quantRequest_payload_mac_3_6 = tileMac_r_14_3;
        _zz_quantRequest_payload_mac_3_7 = tileMac_r_14_4;
        _zz_quantRequest_payload_mac_3_8 = tileMac_r_14_5;
        _zz_quantRequest_payload_mac_3_9 = tileMac_r_14_6;
        _zz_quantRequest_payload_mac_3_10 = tileMac_r_14_7;
        _zz_quantRequest_payload_mac_3_11 = tileMac_r_14_8;
        _zz_quantRequest_payload_mac_3_12 = tileMac_r_14_9;
        _zz_quantRequest_payload_mac_3_13 = tileMac_r_14_10;
        _zz_quantRequest_payload_mac_3_14 = tileMac_r_14_11;
        _zz_quantRequest_payload_mac_3_15 = tileMac_r_14_12;
        _zz_quantRequest_payload_mac_3_16 = tileMac_r_14_13;
        _zz_quantRequest_payload_mac_3_17 = tileMac_r_14_14;
        _zz_quantRequest_payload_mac_3_18 = tileMac_r_14_15;
      end
      default : begin
        _zz_quantRequest_payload_mac_3_3 = tileMac_r_15_0;
        _zz_quantRequest_payload_mac_3_4 = tileMac_r_15_1;
        _zz_quantRequest_payload_mac_3_5 = tileMac_r_15_2;
        _zz_quantRequest_payload_mac_3_6 = tileMac_r_15_3;
        _zz_quantRequest_payload_mac_3_7 = tileMac_r_15_4;
        _zz_quantRequest_payload_mac_3_8 = tileMac_r_15_5;
        _zz_quantRequest_payload_mac_3_9 = tileMac_r_15_6;
        _zz_quantRequest_payload_mac_3_10 = tileMac_r_15_7;
        _zz_quantRequest_payload_mac_3_11 = tileMac_r_15_8;
        _zz_quantRequest_payload_mac_3_12 = tileMac_r_15_9;
        _zz_quantRequest_payload_mac_3_13 = tileMac_r_15_10;
        _zz_quantRequest_payload_mac_3_14 = tileMac_r_15_11;
        _zz_quantRequest_payload_mac_3_15 = tileMac_r_15_12;
        _zz_quantRequest_payload_mac_3_16 = tileMac_r_15_13;
        _zz_quantRequest_payload_mac_3_17 = tileMac_r_15_14;
        _zz_quantRequest_payload_mac_3_18 = tileMac_r_15_15;
      end
    endcase
  end

  assign IDLE = 4'b0000;
  assign LOAD = 4'b0001;
  assign READY = 4'b0010;
  assign FILL = 4'b0011;
  assign ISSUE = 4'b0100;
  assign DRAIN = 4'b0101;
  assign PREPARE = 4'b0110;
  assign TILE_READY = 4'b0111;
  assign SERIALIZE = 4'b1000;
  assign io_done_o = done_r;
  assign io_busy_o = ((state_r != IDLE) && (state_r != READY));
  assign validConfig_w = (((((((io_cfg_i_payload_cin != 10'h0) && (io_cfg_i_payload_cin <= 10'h300)) && (io_cfg_i_payload_cout != 10'h0)) && (io_cfg_i_payload_cout <= 10'h200)) && (io_cfg_i_payload_pixels != 19'h0)) && (io_cfg_i_payload_pixels <= 19'h40000)) && (io_cfg_i_payload_shift <= 6'h3e));
  assign io_cfg_i_ready = (((state_r == IDLE) || (state_r == READY)) && validConfig_w);
  assign cfgIg_w = (_zz_cfgIg_w >>> 3'd4);
  assign cfgOg_w = (_zz_cfgOg_w >>> 3'd4);
  assign cfgParamGroups_w = (_zz_cfgParamGroups_w >>> 2'd2);
  assign io_cfg_i_fire = (io_cfg_i_valid && io_cfg_i_ready);
  assign io_weights_i_ready = ((state_r == LOAD) && (weightCount_r < weightTotal_r));
  assign io_params_i_ready = ((state_r == LOAD) && (paramCount_r < _zz_io_params_i_ready));
  assign io_weights_i_fire = (io_weights_i_valid && io_weights_i_ready);
  assign when_PwMac_l243 = (weightInput_r == _zz_when_PwMac_l243);
  assign io_params_i_fire = (io_params_i_valid && io_params_i_ready);
  assign when_PwMac_l249 = (((state_r == LOAD) && (weightCount_r == weightTotal_r)) && (paramCount_r == _zz_when_PwMac_l249));
  assign io_start_i_ready = ((state_r == READY) && (! io_cfg_i_valid));
  assign io_start_i_fire = (io_start_i_valid && io_start_i_ready);
  assign when_PwMac_l259 = (state_r == PREPARE);
  assign when_PwMac_l268 = (state_r == TILE_READY);
  assign io_rd_o_valid = ((state_r == FILL) && (! waiting_r));
  assign io_rd_o_payload = fillReadAddr_r;
  assign io_rsp_i_ready = ((state_r == FILL) && waiting_r);
  assign io_rd_o_fire = (io_rd_o_valid && io_rd_o_ready);
  assign fillAddress_w = _zz_fillAddress_w[9:0];
  assign io_rsp_i_fire = (io_rsp_i_valid && io_rsp_i_ready);
  assign when_PwMac_l283 = (fillPixel_r == _zz_when_PwMac_l283);
  assign when_PwMac_l285 = (fillGroup_r == _zz_when_PwMac_l285);
  assign request_valid = (state_r == ISSUE);
  assign request_payload_tag_pixel = (tileBase_r + _zz_request_payload_tag_pixel);
  assign request_payload_tag_localPixel = issuePixel_r[3:0];
  assign request_payload_tag_group = _zz_request_payload_tag_group[6:0];
  always @(*) begin
    request_payload_tag_mask[0] = (_zz_request_payload_tag_mask < _zz_request_payload_tag_mask_3);
    request_payload_tag_mask[1] = (_zz_request_payload_tag_mask_4 < _zz_request_payload_tag_mask_7);
    request_payload_tag_mask[2] = (_zz_request_payload_tag_mask_8 < _zz_request_payload_tag_mask_11);
    request_payload_tag_mask[3] = (_zz_request_payload_tag_mask_12 < _zz_request_payload_tag_mask_15);
  end

  assign request_payload_tag_first = (issueInput_r == 6'h0);
  assign request_payload_tag_finalInput = (issueInput_r == _zz_request_payload_tag_finalInput);
  assign request_payload_tag_tileLast = ((issuePixel_r == _zz_request_payload_tag_tileLast) && (issueInput_r == _zz_request_payload_tag_tileLast_1));
  assign request_payload_tag_last = ((request_payload_tag_tileLast && (_zz_request_payload_tag_last == _zz_request_payload_tag_last_1)) && (_zz_request_payload_tag_last_2 == run_r_pixels));
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
  assign response_payload_tag_localPixel = request_rData_tag_localPixel;
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
  assign _zz_ena = (weightGroup_r[1 : 0] == 2'b00);
  assign pwWeightBank_ena = (io_weights_i_fire && _zz_ena);
  assign pwWeightBank_wea = (io_weights_i_fire && _zz_ena);
  assign pwWeightBank_addra = _zz_addra[10:0];
  assign _zz_ena_1 = (weightGroup_r[1 : 0] == 2'b01);
  assign pwWeightBank_1_ena = (io_weights_i_fire && _zz_ena_1);
  assign pwWeightBank_1_wea = (io_weights_i_fire && _zz_ena_1);
  assign pwWeightBank_1_addra = _zz_addra_3[10:0];
  assign _zz_ena_2 = (weightGroup_r[1 : 0] == 2'b10);
  assign pwWeightBank_2_ena = (io_weights_i_fire && _zz_ena_2);
  assign pwWeightBank_2_wea = (io_weights_i_fire && _zz_ena_2);
  assign pwWeightBank_2_addra = _zz_addra_6[10:0];
  assign _zz_ena_3 = (weightGroup_r[1 : 0] == 2'b11);
  assign pwWeightBank_3_ena = (io_weights_i_fire && _zz_ena_3);
  assign pwWeightBank_3_wea = (io_weights_i_fire && _zz_ena_3);
  assign pwWeightBank_3_addra = _zz_addra_9[10:0];
  assign weightsByPe_w_0 = pwWeightBank_doutb[127 : 0];
  assign weightsByPe_w_1 = pwWeightBank_doutb[255 : 128];
  assign weightsByPe_w_2 = pwWeightBank_doutb[383 : 256];
  assign weightsByPe_w_3 = pwWeightBank_doutb[511 : 384];
  assign weightsByPe_w_4 = pwWeightBank_1_doutb[127 : 0];
  assign weightsByPe_w_5 = pwWeightBank_1_doutb[255 : 128];
  assign weightsByPe_w_6 = pwWeightBank_1_doutb[383 : 256];
  assign weightsByPe_w_7 = pwWeightBank_1_doutb[511 : 384];
  assign weightsByPe_w_8 = pwWeightBank_2_doutb[127 : 0];
  assign weightsByPe_w_9 = pwWeightBank_2_doutb[255 : 128];
  assign weightsByPe_w_10 = pwWeightBank_2_doutb[383 : 256];
  assign weightsByPe_w_11 = pwWeightBank_2_doutb[511 : 384];
  assign weightsByPe_w_12 = pwWeightBank_3_doutb[127 : 0];
  assign weightsByPe_w_13 = pwWeightBank_3_doutb[255 : 128];
  assign weightsByPe_w_14 = pwWeightBank_3_doutb[383 : 256];
  assign weightsByPe_w_15 = pwWeightBank_3_doutb[511 : 384];
  assign when_PwMac_l345 = (issuePixel_r == _zz_when_PwMac_l345);
  assign when_PwMac_l347 = (issueInput_r == _zz_when_PwMac_l347);
  assign operands_w_tag_pixel = response_payload_tag_pixel;
  assign operands_w_tag_localPixel = response_payload_tag_localPixel;
  assign operands_w_tag_group = response_payload_tag_group;
  assign operands_w_tag_mask = response_payload_tag_mask;
  assign operands_w_tag_first = response_payload_tag_first;
  assign operands_w_tag_finalInput = response_payload_tag_finalInput;
  assign operands_w_tag_tileLast = response_payload_tag_tileLast;
  assign operands_w_tag_last = response_payload_tag_last;
  assign operands_w_input = inputData_w;
  assign operands_w_weights_0 = weightsByPe_w_0;
  assign operands_w_weights_1 = weightsByPe_w_1;
  assign operands_w_weights_2 = weightsByPe_w_2;
  assign operands_w_weights_3 = weightsByPe_w_3;
  assign operands_w_weights_4 = weightsByPe_w_4;
  assign operands_w_weights_5 = weightsByPe_w_5;
  assign operands_w_weights_6 = weightsByPe_w_6;
  assign operands_w_weights_7 = weightsByPe_w_7;
  assign operands_w_weights_8 = weightsByPe_w_8;
  assign operands_w_weights_9 = weightsByPe_w_9;
  assign operands_w_weights_10 = weightsByPe_w_10;
  assign operands_w_weights_11 = weightsByPe_w_11;
  assign operands_w_weights_12 = weightsByPe_w_12;
  assign operands_w_weights_13 = weightsByPe_w_13;
  assign operands_w_weights_14 = weightsByPe_w_14;
  assign operands_w_weights_15 = weightsByPe_w_15;
  always @(*) begin
    operands_w_mask[0] = (_zz_operands_w_mask < _zz_operands_w_mask_3);
    operands_w_mask[1] = (_zz_operands_w_mask_4 < _zz_operands_w_mask_7);
    operands_w_mask[2] = (_zz_operands_w_mask_8 < _zz_operands_w_mask_11);
    operands_w_mask[3] = (_zz_operands_w_mask_12 < _zz_operands_w_mask_15);
    operands_w_mask[4] = (_zz_operands_w_mask_16 < _zz_operands_w_mask_19);
    operands_w_mask[5] = (_zz_operands_w_mask_20 < _zz_operands_w_mask_23);
    operands_w_mask[6] = (_zz_operands_w_mask_24 < _zz_operands_w_mask_27);
    operands_w_mask[7] = (_zz_operands_w_mask_28 < _zz_operands_w_mask_31);
    operands_w_mask[8] = (_zz_operands_w_mask_32 < _zz_operands_w_mask_35);
    operands_w_mask[9] = (_zz_operands_w_mask_36 < _zz_operands_w_mask_39);
    operands_w_mask[10] = (_zz_operands_w_mask_40 < _zz_operands_w_mask_43);
    operands_w_mask[11] = (_zz_operands_w_mask_44 < _zz_operands_w_mask_47);
    operands_w_mask[12] = (_zz_operands_w_mask_48 < _zz_operands_w_mask_51);
    operands_w_mask[13] = (_zz_operands_w_mask_52 < _zz_operands_w_mask_55);
    operands_w_mask[14] = (_zz_operands_w_mask_56 < _zz_operands_w_mask_59);
    operands_w_mask[15] = (_zz_operands_w_mask_60 < _zz_operands_w_mask_63);
  end

  assign response_translated_valid = response_valid;
  assign response_ready = response_translated_ready;
  assign response_translated_payload_tag_pixel = operands_w_tag_pixel;
  assign response_translated_payload_tag_localPixel = operands_w_tag_localPixel;
  assign response_translated_payload_tag_group = operands_w_tag_group;
  assign response_translated_payload_tag_mask = operands_w_tag_mask;
  assign response_translated_payload_tag_first = operands_w_tag_first;
  assign response_translated_payload_tag_finalInput = operands_w_tag_finalInput;
  assign response_translated_payload_tag_tileLast = operands_w_tag_tileLast;
  assign response_translated_payload_tag_last = operands_w_tag_last;
  assign response_translated_payload_input = operands_w_input;
  assign response_translated_payload_weights_0 = operands_w_weights_0;
  assign response_translated_payload_weights_1 = operands_w_weights_1;
  assign response_translated_payload_weights_2 = operands_w_weights_2;
  assign response_translated_payload_weights_3 = operands_w_weights_3;
  assign response_translated_payload_weights_4 = operands_w_weights_4;
  assign response_translated_payload_weights_5 = operands_w_weights_5;
  assign response_translated_payload_weights_6 = operands_w_weights_6;
  assign response_translated_payload_weights_7 = operands_w_weights_7;
  assign response_translated_payload_weights_8 = operands_w_weights_8;
  assign response_translated_payload_weights_9 = operands_w_weights_9;
  assign response_translated_payload_weights_10 = operands_w_weights_10;
  assign response_translated_payload_weights_11 = operands_w_weights_11;
  assign response_translated_payload_weights_12 = operands_w_weights_12;
  assign response_translated_payload_weights_13 = operands_w_weights_13;
  assign response_translated_payload_weights_14 = operands_w_weights_14;
  assign response_translated_payload_weights_15 = operands_w_weights_15;
  assign response_translated_payload_mask = operands_w_mask;
  always @(*) begin
    response_translated_ready = operands_ready;
    if(when_Stream_l477_1) begin
      response_translated_ready = 1'b1;
    end
  end

  assign when_Stream_l477_1 = (! operands_valid);
  assign operands_valid = response_translated_rValid;
  assign operands_payload_tag_pixel = response_translated_rData_tag_pixel;
  assign operands_payload_tag_localPixel = response_translated_rData_tag_localPixel;
  assign operands_payload_tag_group = response_translated_rData_tag_group;
  assign operands_payload_tag_mask = response_translated_rData_tag_mask;
  assign operands_payload_tag_first = response_translated_rData_tag_first;
  assign operands_payload_tag_finalInput = response_translated_rData_tag_finalInput;
  assign operands_payload_tag_tileLast = response_translated_rData_tag_tileLast;
  assign operands_payload_tag_last = response_translated_rData_tag_last;
  assign operands_payload_input = response_translated_rData_input;
  assign operands_payload_weights_0 = response_translated_rData_weights_0;
  assign operands_payload_weights_1 = response_translated_rData_weights_1;
  assign operands_payload_weights_2 = response_translated_rData_weights_2;
  assign operands_payload_weights_3 = response_translated_rData_weights_3;
  assign operands_payload_weights_4 = response_translated_rData_weights_4;
  assign operands_payload_weights_5 = response_translated_rData_weights_5;
  assign operands_payload_weights_6 = response_translated_rData_weights_6;
  assign operands_payload_weights_7 = response_translated_rData_weights_7;
  assign operands_payload_weights_8 = response_translated_rData_weights_8;
  assign operands_payload_weights_9 = response_translated_rData_weights_9;
  assign operands_payload_weights_10 = response_translated_rData_weights_10;
  assign operands_payload_weights_11 = response_translated_rData_weights_11;
  assign operands_payload_weights_12 = response_translated_rData_weights_12;
  assign operands_payload_weights_13 = response_translated_rData_weights_13;
  assign operands_payload_weights_14 = response_translated_rData_weights_14;
  assign operands_payload_weights_15 = response_translated_rData_weights_15;
  assign operands_payload_mask = response_translated_rData_mask;
  assign products_w_tag_pixel = operands_payload_tag_pixel;
  assign products_w_tag_localPixel = operands_payload_tag_localPixel;
  assign products_w_tag_group = operands_payload_tag_group;
  assign products_w_tag_mask = operands_payload_tag_mask;
  assign products_w_tag_first = operands_payload_tag_first;
  assign products_w_tag_finalInput = operands_payload_tag_finalInput;
  assign products_w_tag_tileLast = operands_payload_tag_tileLast;
  assign products_w_tag_last = operands_payload_tag_last;
  assign products_w_values_0_0 = ($signed(_zz_products_w_values_0_0) * $signed(_zz_products_w_values_0_0_2));
  assign products_w_values_0_1 = ($signed(_zz_products_w_values_0_1) * $signed(_zz_products_w_values_0_1_2));
  assign products_w_values_0_2 = ($signed(_zz_products_w_values_0_2) * $signed(_zz_products_w_values_0_2_2));
  assign products_w_values_0_3 = ($signed(_zz_products_w_values_0_3) * $signed(_zz_products_w_values_0_3_2));
  assign products_w_values_0_4 = ($signed(_zz_products_w_values_0_4) * $signed(_zz_products_w_values_0_4_2));
  assign products_w_values_0_5 = ($signed(_zz_products_w_values_0_5) * $signed(_zz_products_w_values_0_5_2));
  assign products_w_values_0_6 = ($signed(_zz_products_w_values_0_6) * $signed(_zz_products_w_values_0_6_2));
  assign products_w_values_0_7 = ($signed(_zz_products_w_values_0_7) * $signed(_zz_products_w_values_0_7_2));
  assign products_w_values_0_8 = ($signed(_zz_products_w_values_0_8) * $signed(_zz_products_w_values_0_8_2));
  assign products_w_values_0_9 = ($signed(_zz_products_w_values_0_9) * $signed(_zz_products_w_values_0_9_2));
  assign products_w_values_0_10 = ($signed(_zz_products_w_values_0_10) * $signed(_zz_products_w_values_0_10_2));
  assign products_w_values_0_11 = ($signed(_zz_products_w_values_0_11) * $signed(_zz_products_w_values_0_11_2));
  assign products_w_values_0_12 = ($signed(_zz_products_w_values_0_12) * $signed(_zz_products_w_values_0_12_2));
  assign products_w_values_0_13 = ($signed(_zz_products_w_values_0_13) * $signed(_zz_products_w_values_0_13_2));
  assign products_w_values_0_14 = ($signed(_zz_products_w_values_0_14) * $signed(_zz_products_w_values_0_14_2));
  assign products_w_values_0_15 = ($signed(_zz_products_w_values_0_15) * $signed(_zz_products_w_values_0_15_2));
  assign products_w_values_1_0 = ($signed(_zz_products_w_values_1_0) * $signed(_zz_products_w_values_1_0_2));
  assign products_w_values_1_1 = ($signed(_zz_products_w_values_1_1) * $signed(_zz_products_w_values_1_1_2));
  assign products_w_values_1_2 = ($signed(_zz_products_w_values_1_2) * $signed(_zz_products_w_values_1_2_2));
  assign products_w_values_1_3 = ($signed(_zz_products_w_values_1_3) * $signed(_zz_products_w_values_1_3_2));
  assign products_w_values_1_4 = ($signed(_zz_products_w_values_1_4) * $signed(_zz_products_w_values_1_4_2));
  assign products_w_values_1_5 = ($signed(_zz_products_w_values_1_5) * $signed(_zz_products_w_values_1_5_2));
  assign products_w_values_1_6 = ($signed(_zz_products_w_values_1_6) * $signed(_zz_products_w_values_1_6_2));
  assign products_w_values_1_7 = ($signed(_zz_products_w_values_1_7) * $signed(_zz_products_w_values_1_7_2));
  assign products_w_values_1_8 = ($signed(_zz_products_w_values_1_8) * $signed(_zz_products_w_values_1_8_2));
  assign products_w_values_1_9 = ($signed(_zz_products_w_values_1_9) * $signed(_zz_products_w_values_1_9_2));
  assign products_w_values_1_10 = ($signed(_zz_products_w_values_1_10) * $signed(_zz_products_w_values_1_10_2));
  assign products_w_values_1_11 = ($signed(_zz_products_w_values_1_11) * $signed(_zz_products_w_values_1_11_2));
  assign products_w_values_1_12 = ($signed(_zz_products_w_values_1_12) * $signed(_zz_products_w_values_1_12_2));
  assign products_w_values_1_13 = ($signed(_zz_products_w_values_1_13) * $signed(_zz_products_w_values_1_13_2));
  assign products_w_values_1_14 = ($signed(_zz_products_w_values_1_14) * $signed(_zz_products_w_values_1_14_2));
  assign products_w_values_1_15 = ($signed(_zz_products_w_values_1_15) * $signed(_zz_products_w_values_1_15_2));
  assign products_w_values_2_0 = ($signed(_zz_products_w_values_2_0) * $signed(_zz_products_w_values_2_0_2));
  assign products_w_values_2_1 = ($signed(_zz_products_w_values_2_1) * $signed(_zz_products_w_values_2_1_2));
  assign products_w_values_2_2 = ($signed(_zz_products_w_values_2_2) * $signed(_zz_products_w_values_2_2_2));
  assign products_w_values_2_3 = ($signed(_zz_products_w_values_2_3) * $signed(_zz_products_w_values_2_3_2));
  assign products_w_values_2_4 = ($signed(_zz_products_w_values_2_4) * $signed(_zz_products_w_values_2_4_2));
  assign products_w_values_2_5 = ($signed(_zz_products_w_values_2_5) * $signed(_zz_products_w_values_2_5_2));
  assign products_w_values_2_6 = ($signed(_zz_products_w_values_2_6) * $signed(_zz_products_w_values_2_6_2));
  assign products_w_values_2_7 = ($signed(_zz_products_w_values_2_7) * $signed(_zz_products_w_values_2_7_2));
  assign products_w_values_2_8 = ($signed(_zz_products_w_values_2_8) * $signed(_zz_products_w_values_2_8_2));
  assign products_w_values_2_9 = ($signed(_zz_products_w_values_2_9) * $signed(_zz_products_w_values_2_9_2));
  assign products_w_values_2_10 = ($signed(_zz_products_w_values_2_10) * $signed(_zz_products_w_values_2_10_2));
  assign products_w_values_2_11 = ($signed(_zz_products_w_values_2_11) * $signed(_zz_products_w_values_2_11_2));
  assign products_w_values_2_12 = ($signed(_zz_products_w_values_2_12) * $signed(_zz_products_w_values_2_12_2));
  assign products_w_values_2_13 = ($signed(_zz_products_w_values_2_13) * $signed(_zz_products_w_values_2_13_2));
  assign products_w_values_2_14 = ($signed(_zz_products_w_values_2_14) * $signed(_zz_products_w_values_2_14_2));
  assign products_w_values_2_15 = ($signed(_zz_products_w_values_2_15) * $signed(_zz_products_w_values_2_15_2));
  assign products_w_values_3_0 = ($signed(_zz_products_w_values_3_0) * $signed(_zz_products_w_values_3_0_2));
  assign products_w_values_3_1 = ($signed(_zz_products_w_values_3_1) * $signed(_zz_products_w_values_3_1_2));
  assign products_w_values_3_2 = ($signed(_zz_products_w_values_3_2) * $signed(_zz_products_w_values_3_2_2));
  assign products_w_values_3_3 = ($signed(_zz_products_w_values_3_3) * $signed(_zz_products_w_values_3_3_2));
  assign products_w_values_3_4 = ($signed(_zz_products_w_values_3_4) * $signed(_zz_products_w_values_3_4_2));
  assign products_w_values_3_5 = ($signed(_zz_products_w_values_3_5) * $signed(_zz_products_w_values_3_5_2));
  assign products_w_values_3_6 = ($signed(_zz_products_w_values_3_6) * $signed(_zz_products_w_values_3_6_2));
  assign products_w_values_3_7 = ($signed(_zz_products_w_values_3_7) * $signed(_zz_products_w_values_3_7_2));
  assign products_w_values_3_8 = ($signed(_zz_products_w_values_3_8) * $signed(_zz_products_w_values_3_8_2));
  assign products_w_values_3_9 = ($signed(_zz_products_w_values_3_9) * $signed(_zz_products_w_values_3_9_2));
  assign products_w_values_3_10 = ($signed(_zz_products_w_values_3_10) * $signed(_zz_products_w_values_3_10_2));
  assign products_w_values_3_11 = ($signed(_zz_products_w_values_3_11) * $signed(_zz_products_w_values_3_11_2));
  assign products_w_values_3_12 = ($signed(_zz_products_w_values_3_12) * $signed(_zz_products_w_values_3_12_2));
  assign products_w_values_3_13 = ($signed(_zz_products_w_values_3_13) * $signed(_zz_products_w_values_3_13_2));
  assign products_w_values_3_14 = ($signed(_zz_products_w_values_3_14) * $signed(_zz_products_w_values_3_14_2));
  assign products_w_values_3_15 = ($signed(_zz_products_w_values_3_15) * $signed(_zz_products_w_values_3_15_2));
  assign products_w_values_4_0 = ($signed(_zz_products_w_values_4_0) * $signed(_zz_products_w_values_4_0_2));
  assign products_w_values_4_1 = ($signed(_zz_products_w_values_4_1) * $signed(_zz_products_w_values_4_1_2));
  assign products_w_values_4_2 = ($signed(_zz_products_w_values_4_2) * $signed(_zz_products_w_values_4_2_2));
  assign products_w_values_4_3 = ($signed(_zz_products_w_values_4_3) * $signed(_zz_products_w_values_4_3_2));
  assign products_w_values_4_4 = ($signed(_zz_products_w_values_4_4) * $signed(_zz_products_w_values_4_4_2));
  assign products_w_values_4_5 = ($signed(_zz_products_w_values_4_5) * $signed(_zz_products_w_values_4_5_2));
  assign products_w_values_4_6 = ($signed(_zz_products_w_values_4_6) * $signed(_zz_products_w_values_4_6_2));
  assign products_w_values_4_7 = ($signed(_zz_products_w_values_4_7) * $signed(_zz_products_w_values_4_7_2));
  assign products_w_values_4_8 = ($signed(_zz_products_w_values_4_8) * $signed(_zz_products_w_values_4_8_2));
  assign products_w_values_4_9 = ($signed(_zz_products_w_values_4_9) * $signed(_zz_products_w_values_4_9_2));
  assign products_w_values_4_10 = ($signed(_zz_products_w_values_4_10) * $signed(_zz_products_w_values_4_10_2));
  assign products_w_values_4_11 = ($signed(_zz_products_w_values_4_11) * $signed(_zz_products_w_values_4_11_2));
  assign products_w_values_4_12 = ($signed(_zz_products_w_values_4_12) * $signed(_zz_products_w_values_4_12_2));
  assign products_w_values_4_13 = ($signed(_zz_products_w_values_4_13) * $signed(_zz_products_w_values_4_13_2));
  assign products_w_values_4_14 = ($signed(_zz_products_w_values_4_14) * $signed(_zz_products_w_values_4_14_2));
  assign products_w_values_4_15 = ($signed(_zz_products_w_values_4_15) * $signed(_zz_products_w_values_4_15_2));
  assign products_w_values_5_0 = ($signed(_zz_products_w_values_5_0) * $signed(_zz_products_w_values_5_0_2));
  assign products_w_values_5_1 = ($signed(_zz_products_w_values_5_1) * $signed(_zz_products_w_values_5_1_2));
  assign products_w_values_5_2 = ($signed(_zz_products_w_values_5_2) * $signed(_zz_products_w_values_5_2_2));
  assign products_w_values_5_3 = ($signed(_zz_products_w_values_5_3) * $signed(_zz_products_w_values_5_3_2));
  assign products_w_values_5_4 = ($signed(_zz_products_w_values_5_4) * $signed(_zz_products_w_values_5_4_2));
  assign products_w_values_5_5 = ($signed(_zz_products_w_values_5_5) * $signed(_zz_products_w_values_5_5_2));
  assign products_w_values_5_6 = ($signed(_zz_products_w_values_5_6) * $signed(_zz_products_w_values_5_6_2));
  assign products_w_values_5_7 = ($signed(_zz_products_w_values_5_7) * $signed(_zz_products_w_values_5_7_2));
  assign products_w_values_5_8 = ($signed(_zz_products_w_values_5_8) * $signed(_zz_products_w_values_5_8_2));
  assign products_w_values_5_9 = ($signed(_zz_products_w_values_5_9) * $signed(_zz_products_w_values_5_9_2));
  assign products_w_values_5_10 = ($signed(_zz_products_w_values_5_10) * $signed(_zz_products_w_values_5_10_2));
  assign products_w_values_5_11 = ($signed(_zz_products_w_values_5_11) * $signed(_zz_products_w_values_5_11_2));
  assign products_w_values_5_12 = ($signed(_zz_products_w_values_5_12) * $signed(_zz_products_w_values_5_12_2));
  assign products_w_values_5_13 = ($signed(_zz_products_w_values_5_13) * $signed(_zz_products_w_values_5_13_2));
  assign products_w_values_5_14 = ($signed(_zz_products_w_values_5_14) * $signed(_zz_products_w_values_5_14_2));
  assign products_w_values_5_15 = ($signed(_zz_products_w_values_5_15) * $signed(_zz_products_w_values_5_15_2));
  assign products_w_values_6_0 = ($signed(_zz_products_w_values_6_0) * $signed(_zz_products_w_values_6_0_2));
  assign products_w_values_6_1 = ($signed(_zz_products_w_values_6_1) * $signed(_zz_products_w_values_6_1_2));
  assign products_w_values_6_2 = ($signed(_zz_products_w_values_6_2) * $signed(_zz_products_w_values_6_2_2));
  assign products_w_values_6_3 = ($signed(_zz_products_w_values_6_3) * $signed(_zz_products_w_values_6_3_2));
  assign products_w_values_6_4 = ($signed(_zz_products_w_values_6_4) * $signed(_zz_products_w_values_6_4_2));
  assign products_w_values_6_5 = ($signed(_zz_products_w_values_6_5) * $signed(_zz_products_w_values_6_5_2));
  assign products_w_values_6_6 = ($signed(_zz_products_w_values_6_6) * $signed(_zz_products_w_values_6_6_2));
  assign products_w_values_6_7 = ($signed(_zz_products_w_values_6_7) * $signed(_zz_products_w_values_6_7_2));
  assign products_w_values_6_8 = ($signed(_zz_products_w_values_6_8) * $signed(_zz_products_w_values_6_8_2));
  assign products_w_values_6_9 = ($signed(_zz_products_w_values_6_9) * $signed(_zz_products_w_values_6_9_2));
  assign products_w_values_6_10 = ($signed(_zz_products_w_values_6_10) * $signed(_zz_products_w_values_6_10_2));
  assign products_w_values_6_11 = ($signed(_zz_products_w_values_6_11) * $signed(_zz_products_w_values_6_11_2));
  assign products_w_values_6_12 = ($signed(_zz_products_w_values_6_12) * $signed(_zz_products_w_values_6_12_2));
  assign products_w_values_6_13 = ($signed(_zz_products_w_values_6_13) * $signed(_zz_products_w_values_6_13_2));
  assign products_w_values_6_14 = ($signed(_zz_products_w_values_6_14) * $signed(_zz_products_w_values_6_14_2));
  assign products_w_values_6_15 = ($signed(_zz_products_w_values_6_15) * $signed(_zz_products_w_values_6_15_2));
  assign products_w_values_7_0 = ($signed(_zz_products_w_values_7_0) * $signed(_zz_products_w_values_7_0_2));
  assign products_w_values_7_1 = ($signed(_zz_products_w_values_7_1) * $signed(_zz_products_w_values_7_1_2));
  assign products_w_values_7_2 = ($signed(_zz_products_w_values_7_2) * $signed(_zz_products_w_values_7_2_2));
  assign products_w_values_7_3 = ($signed(_zz_products_w_values_7_3) * $signed(_zz_products_w_values_7_3_2));
  assign products_w_values_7_4 = ($signed(_zz_products_w_values_7_4) * $signed(_zz_products_w_values_7_4_2));
  assign products_w_values_7_5 = ($signed(_zz_products_w_values_7_5) * $signed(_zz_products_w_values_7_5_2));
  assign products_w_values_7_6 = ($signed(_zz_products_w_values_7_6) * $signed(_zz_products_w_values_7_6_2));
  assign products_w_values_7_7 = ($signed(_zz_products_w_values_7_7) * $signed(_zz_products_w_values_7_7_2));
  assign products_w_values_7_8 = ($signed(_zz_products_w_values_7_8) * $signed(_zz_products_w_values_7_8_2));
  assign products_w_values_7_9 = ($signed(_zz_products_w_values_7_9) * $signed(_zz_products_w_values_7_9_2));
  assign products_w_values_7_10 = ($signed(_zz_products_w_values_7_10) * $signed(_zz_products_w_values_7_10_2));
  assign products_w_values_7_11 = ($signed(_zz_products_w_values_7_11) * $signed(_zz_products_w_values_7_11_2));
  assign products_w_values_7_12 = ($signed(_zz_products_w_values_7_12) * $signed(_zz_products_w_values_7_12_2));
  assign products_w_values_7_13 = ($signed(_zz_products_w_values_7_13) * $signed(_zz_products_w_values_7_13_2));
  assign products_w_values_7_14 = ($signed(_zz_products_w_values_7_14) * $signed(_zz_products_w_values_7_14_2));
  assign products_w_values_7_15 = ($signed(_zz_products_w_values_7_15) * $signed(_zz_products_w_values_7_15_2));
  assign products_w_values_8_0 = ($signed(_zz_products_w_values_8_0) * $signed(_zz_products_w_values_8_0_2));
  assign products_w_values_8_1 = ($signed(_zz_products_w_values_8_1) * $signed(_zz_products_w_values_8_1_2));
  assign products_w_values_8_2 = ($signed(_zz_products_w_values_8_2) * $signed(_zz_products_w_values_8_2_2));
  assign products_w_values_8_3 = ($signed(_zz_products_w_values_8_3) * $signed(_zz_products_w_values_8_3_2));
  assign products_w_values_8_4 = ($signed(_zz_products_w_values_8_4) * $signed(_zz_products_w_values_8_4_2));
  assign products_w_values_8_5 = ($signed(_zz_products_w_values_8_5) * $signed(_zz_products_w_values_8_5_2));
  assign products_w_values_8_6 = ($signed(_zz_products_w_values_8_6) * $signed(_zz_products_w_values_8_6_2));
  assign products_w_values_8_7 = ($signed(_zz_products_w_values_8_7) * $signed(_zz_products_w_values_8_7_2));
  assign products_w_values_8_8 = ($signed(_zz_products_w_values_8_8) * $signed(_zz_products_w_values_8_8_2));
  assign products_w_values_8_9 = ($signed(_zz_products_w_values_8_9) * $signed(_zz_products_w_values_8_9_2));
  assign products_w_values_8_10 = ($signed(_zz_products_w_values_8_10) * $signed(_zz_products_w_values_8_10_2));
  assign products_w_values_8_11 = ($signed(_zz_products_w_values_8_11) * $signed(_zz_products_w_values_8_11_2));
  assign products_w_values_8_12 = ($signed(_zz_products_w_values_8_12) * $signed(_zz_products_w_values_8_12_2));
  assign products_w_values_8_13 = ($signed(_zz_products_w_values_8_13) * $signed(_zz_products_w_values_8_13_2));
  assign products_w_values_8_14 = ($signed(_zz_products_w_values_8_14) * $signed(_zz_products_w_values_8_14_2));
  assign products_w_values_8_15 = ($signed(_zz_products_w_values_8_15) * $signed(_zz_products_w_values_8_15_2));
  assign products_w_values_9_0 = ($signed(_zz_products_w_values_9_0) * $signed(_zz_products_w_values_9_0_2));
  assign products_w_values_9_1 = ($signed(_zz_products_w_values_9_1) * $signed(_zz_products_w_values_9_1_2));
  assign products_w_values_9_2 = ($signed(_zz_products_w_values_9_2) * $signed(_zz_products_w_values_9_2_2));
  assign products_w_values_9_3 = ($signed(_zz_products_w_values_9_3) * $signed(_zz_products_w_values_9_3_2));
  assign products_w_values_9_4 = ($signed(_zz_products_w_values_9_4) * $signed(_zz_products_w_values_9_4_2));
  assign products_w_values_9_5 = ($signed(_zz_products_w_values_9_5) * $signed(_zz_products_w_values_9_5_2));
  assign products_w_values_9_6 = ($signed(_zz_products_w_values_9_6) * $signed(_zz_products_w_values_9_6_2));
  assign products_w_values_9_7 = ($signed(_zz_products_w_values_9_7) * $signed(_zz_products_w_values_9_7_2));
  assign products_w_values_9_8 = ($signed(_zz_products_w_values_9_8) * $signed(_zz_products_w_values_9_8_2));
  assign products_w_values_9_9 = ($signed(_zz_products_w_values_9_9) * $signed(_zz_products_w_values_9_9_2));
  assign products_w_values_9_10 = ($signed(_zz_products_w_values_9_10) * $signed(_zz_products_w_values_9_10_2));
  assign products_w_values_9_11 = ($signed(_zz_products_w_values_9_11) * $signed(_zz_products_w_values_9_11_2));
  assign products_w_values_9_12 = ($signed(_zz_products_w_values_9_12) * $signed(_zz_products_w_values_9_12_2));
  assign products_w_values_9_13 = ($signed(_zz_products_w_values_9_13) * $signed(_zz_products_w_values_9_13_2));
  assign products_w_values_9_14 = ($signed(_zz_products_w_values_9_14) * $signed(_zz_products_w_values_9_14_2));
  assign products_w_values_9_15 = ($signed(_zz_products_w_values_9_15) * $signed(_zz_products_w_values_9_15_2));
  assign products_w_values_10_0 = ($signed(_zz_products_w_values_10_0) * $signed(_zz_products_w_values_10_0_2));
  assign products_w_values_10_1 = ($signed(_zz_products_w_values_10_1) * $signed(_zz_products_w_values_10_1_2));
  assign products_w_values_10_2 = ($signed(_zz_products_w_values_10_2) * $signed(_zz_products_w_values_10_2_2));
  assign products_w_values_10_3 = ($signed(_zz_products_w_values_10_3) * $signed(_zz_products_w_values_10_3_2));
  assign products_w_values_10_4 = ($signed(_zz_products_w_values_10_4) * $signed(_zz_products_w_values_10_4_2));
  assign products_w_values_10_5 = ($signed(_zz_products_w_values_10_5) * $signed(_zz_products_w_values_10_5_2));
  assign products_w_values_10_6 = ($signed(_zz_products_w_values_10_6) * $signed(_zz_products_w_values_10_6_2));
  assign products_w_values_10_7 = ($signed(_zz_products_w_values_10_7) * $signed(_zz_products_w_values_10_7_2));
  assign products_w_values_10_8 = ($signed(_zz_products_w_values_10_8) * $signed(_zz_products_w_values_10_8_2));
  assign products_w_values_10_9 = ($signed(_zz_products_w_values_10_9) * $signed(_zz_products_w_values_10_9_2));
  assign products_w_values_10_10 = ($signed(_zz_products_w_values_10_10) * $signed(_zz_products_w_values_10_10_2));
  assign products_w_values_10_11 = ($signed(_zz_products_w_values_10_11) * $signed(_zz_products_w_values_10_11_2));
  assign products_w_values_10_12 = ($signed(_zz_products_w_values_10_12) * $signed(_zz_products_w_values_10_12_2));
  assign products_w_values_10_13 = ($signed(_zz_products_w_values_10_13) * $signed(_zz_products_w_values_10_13_2));
  assign products_w_values_10_14 = ($signed(_zz_products_w_values_10_14) * $signed(_zz_products_w_values_10_14_2));
  assign products_w_values_10_15 = ($signed(_zz_products_w_values_10_15) * $signed(_zz_products_w_values_10_15_2));
  assign products_w_values_11_0 = ($signed(_zz_products_w_values_11_0) * $signed(_zz_products_w_values_11_0_2));
  assign products_w_values_11_1 = ($signed(_zz_products_w_values_11_1) * $signed(_zz_products_w_values_11_1_2));
  assign products_w_values_11_2 = ($signed(_zz_products_w_values_11_2) * $signed(_zz_products_w_values_11_2_2));
  assign products_w_values_11_3 = ($signed(_zz_products_w_values_11_3) * $signed(_zz_products_w_values_11_3_2));
  assign products_w_values_11_4 = ($signed(_zz_products_w_values_11_4) * $signed(_zz_products_w_values_11_4_2));
  assign products_w_values_11_5 = ($signed(_zz_products_w_values_11_5) * $signed(_zz_products_w_values_11_5_2));
  assign products_w_values_11_6 = ($signed(_zz_products_w_values_11_6) * $signed(_zz_products_w_values_11_6_2));
  assign products_w_values_11_7 = ($signed(_zz_products_w_values_11_7) * $signed(_zz_products_w_values_11_7_2));
  assign products_w_values_11_8 = ($signed(_zz_products_w_values_11_8) * $signed(_zz_products_w_values_11_8_2));
  assign products_w_values_11_9 = ($signed(_zz_products_w_values_11_9) * $signed(_zz_products_w_values_11_9_2));
  assign products_w_values_11_10 = ($signed(_zz_products_w_values_11_10) * $signed(_zz_products_w_values_11_10_2));
  assign products_w_values_11_11 = ($signed(_zz_products_w_values_11_11) * $signed(_zz_products_w_values_11_11_2));
  assign products_w_values_11_12 = ($signed(_zz_products_w_values_11_12) * $signed(_zz_products_w_values_11_12_2));
  assign products_w_values_11_13 = ($signed(_zz_products_w_values_11_13) * $signed(_zz_products_w_values_11_13_2));
  assign products_w_values_11_14 = ($signed(_zz_products_w_values_11_14) * $signed(_zz_products_w_values_11_14_2));
  assign products_w_values_11_15 = ($signed(_zz_products_w_values_11_15) * $signed(_zz_products_w_values_11_15_2));
  assign products_w_values_12_0 = ($signed(_zz_products_w_values_12_0) * $signed(_zz_products_w_values_12_0_2));
  assign products_w_values_12_1 = ($signed(_zz_products_w_values_12_1) * $signed(_zz_products_w_values_12_1_2));
  assign products_w_values_12_2 = ($signed(_zz_products_w_values_12_2) * $signed(_zz_products_w_values_12_2_2));
  assign products_w_values_12_3 = ($signed(_zz_products_w_values_12_3) * $signed(_zz_products_w_values_12_3_2));
  assign products_w_values_12_4 = ($signed(_zz_products_w_values_12_4) * $signed(_zz_products_w_values_12_4_2));
  assign products_w_values_12_5 = ($signed(_zz_products_w_values_12_5) * $signed(_zz_products_w_values_12_5_2));
  assign products_w_values_12_6 = ($signed(_zz_products_w_values_12_6) * $signed(_zz_products_w_values_12_6_2));
  assign products_w_values_12_7 = ($signed(_zz_products_w_values_12_7) * $signed(_zz_products_w_values_12_7_2));
  assign products_w_values_12_8 = ($signed(_zz_products_w_values_12_8) * $signed(_zz_products_w_values_12_8_2));
  assign products_w_values_12_9 = ($signed(_zz_products_w_values_12_9) * $signed(_zz_products_w_values_12_9_2));
  assign products_w_values_12_10 = ($signed(_zz_products_w_values_12_10) * $signed(_zz_products_w_values_12_10_2));
  assign products_w_values_12_11 = ($signed(_zz_products_w_values_12_11) * $signed(_zz_products_w_values_12_11_2));
  assign products_w_values_12_12 = ($signed(_zz_products_w_values_12_12) * $signed(_zz_products_w_values_12_12_2));
  assign products_w_values_12_13 = ($signed(_zz_products_w_values_12_13) * $signed(_zz_products_w_values_12_13_2));
  assign products_w_values_12_14 = ($signed(_zz_products_w_values_12_14) * $signed(_zz_products_w_values_12_14_2));
  assign products_w_values_12_15 = ($signed(_zz_products_w_values_12_15) * $signed(_zz_products_w_values_12_15_2));
  assign products_w_values_13_0 = ($signed(_zz_products_w_values_13_0) * $signed(_zz_products_w_values_13_0_2));
  assign products_w_values_13_1 = ($signed(_zz_products_w_values_13_1) * $signed(_zz_products_w_values_13_1_2));
  assign products_w_values_13_2 = ($signed(_zz_products_w_values_13_2) * $signed(_zz_products_w_values_13_2_2));
  assign products_w_values_13_3 = ($signed(_zz_products_w_values_13_3) * $signed(_zz_products_w_values_13_3_2));
  assign products_w_values_13_4 = ($signed(_zz_products_w_values_13_4) * $signed(_zz_products_w_values_13_4_2));
  assign products_w_values_13_5 = ($signed(_zz_products_w_values_13_5) * $signed(_zz_products_w_values_13_5_2));
  assign products_w_values_13_6 = ($signed(_zz_products_w_values_13_6) * $signed(_zz_products_w_values_13_6_2));
  assign products_w_values_13_7 = ($signed(_zz_products_w_values_13_7) * $signed(_zz_products_w_values_13_7_2));
  assign products_w_values_13_8 = ($signed(_zz_products_w_values_13_8) * $signed(_zz_products_w_values_13_8_2));
  assign products_w_values_13_9 = ($signed(_zz_products_w_values_13_9) * $signed(_zz_products_w_values_13_9_2));
  assign products_w_values_13_10 = ($signed(_zz_products_w_values_13_10) * $signed(_zz_products_w_values_13_10_2));
  assign products_w_values_13_11 = ($signed(_zz_products_w_values_13_11) * $signed(_zz_products_w_values_13_11_2));
  assign products_w_values_13_12 = ($signed(_zz_products_w_values_13_12) * $signed(_zz_products_w_values_13_12_2));
  assign products_w_values_13_13 = ($signed(_zz_products_w_values_13_13) * $signed(_zz_products_w_values_13_13_2));
  assign products_w_values_13_14 = ($signed(_zz_products_w_values_13_14) * $signed(_zz_products_w_values_13_14_2));
  assign products_w_values_13_15 = ($signed(_zz_products_w_values_13_15) * $signed(_zz_products_w_values_13_15_2));
  assign products_w_values_14_0 = ($signed(_zz_products_w_values_14_0) * $signed(_zz_products_w_values_14_0_2));
  assign products_w_values_14_1 = ($signed(_zz_products_w_values_14_1) * $signed(_zz_products_w_values_14_1_2));
  assign products_w_values_14_2 = ($signed(_zz_products_w_values_14_2) * $signed(_zz_products_w_values_14_2_2));
  assign products_w_values_14_3 = ($signed(_zz_products_w_values_14_3) * $signed(_zz_products_w_values_14_3_2));
  assign products_w_values_14_4 = ($signed(_zz_products_w_values_14_4) * $signed(_zz_products_w_values_14_4_2));
  assign products_w_values_14_5 = ($signed(_zz_products_w_values_14_5) * $signed(_zz_products_w_values_14_5_2));
  assign products_w_values_14_6 = ($signed(_zz_products_w_values_14_6) * $signed(_zz_products_w_values_14_6_2));
  assign products_w_values_14_7 = ($signed(_zz_products_w_values_14_7) * $signed(_zz_products_w_values_14_7_2));
  assign products_w_values_14_8 = ($signed(_zz_products_w_values_14_8) * $signed(_zz_products_w_values_14_8_2));
  assign products_w_values_14_9 = ($signed(_zz_products_w_values_14_9) * $signed(_zz_products_w_values_14_9_2));
  assign products_w_values_14_10 = ($signed(_zz_products_w_values_14_10) * $signed(_zz_products_w_values_14_10_2));
  assign products_w_values_14_11 = ($signed(_zz_products_w_values_14_11) * $signed(_zz_products_w_values_14_11_2));
  assign products_w_values_14_12 = ($signed(_zz_products_w_values_14_12) * $signed(_zz_products_w_values_14_12_2));
  assign products_w_values_14_13 = ($signed(_zz_products_w_values_14_13) * $signed(_zz_products_w_values_14_13_2));
  assign products_w_values_14_14 = ($signed(_zz_products_w_values_14_14) * $signed(_zz_products_w_values_14_14_2));
  assign products_w_values_14_15 = ($signed(_zz_products_w_values_14_15) * $signed(_zz_products_w_values_14_15_2));
  assign products_w_values_15_0 = ($signed(_zz_products_w_values_15_0) * $signed(_zz_products_w_values_15_0_2));
  assign products_w_values_15_1 = ($signed(_zz_products_w_values_15_1) * $signed(_zz_products_w_values_15_1_2));
  assign products_w_values_15_2 = ($signed(_zz_products_w_values_15_2) * $signed(_zz_products_w_values_15_2_2));
  assign products_w_values_15_3 = ($signed(_zz_products_w_values_15_3) * $signed(_zz_products_w_values_15_3_2));
  assign products_w_values_15_4 = ($signed(_zz_products_w_values_15_4) * $signed(_zz_products_w_values_15_4_2));
  assign products_w_values_15_5 = ($signed(_zz_products_w_values_15_5) * $signed(_zz_products_w_values_15_5_2));
  assign products_w_values_15_6 = ($signed(_zz_products_w_values_15_6) * $signed(_zz_products_w_values_15_6_2));
  assign products_w_values_15_7 = ($signed(_zz_products_w_values_15_7) * $signed(_zz_products_w_values_15_7_2));
  assign products_w_values_15_8 = ($signed(_zz_products_w_values_15_8) * $signed(_zz_products_w_values_15_8_2));
  assign products_w_values_15_9 = ($signed(_zz_products_w_values_15_9) * $signed(_zz_products_w_values_15_9_2));
  assign products_w_values_15_10 = ($signed(_zz_products_w_values_15_10) * $signed(_zz_products_w_values_15_10_2));
  assign products_w_values_15_11 = ($signed(_zz_products_w_values_15_11) * $signed(_zz_products_w_values_15_11_2));
  assign products_w_values_15_12 = ($signed(_zz_products_w_values_15_12) * $signed(_zz_products_w_values_15_12_2));
  assign products_w_values_15_13 = ($signed(_zz_products_w_values_15_13) * $signed(_zz_products_w_values_15_13_2));
  assign products_w_values_15_14 = ($signed(_zz_products_w_values_15_14) * $signed(_zz_products_w_values_15_14_2));
  assign products_w_values_15_15 = ($signed(_zz_products_w_values_15_15) * $signed(_zz_products_w_values_15_15_2));
  assign operands_translated_valid = operands_valid;
  assign operands_ready = operands_translated_ready;
  assign operands_translated_payload_tag_pixel = products_w_tag_pixel;
  assign operands_translated_payload_tag_localPixel = products_w_tag_localPixel;
  assign operands_translated_payload_tag_group = products_w_tag_group;
  assign operands_translated_payload_tag_mask = products_w_tag_mask;
  assign operands_translated_payload_tag_first = products_w_tag_first;
  assign operands_translated_payload_tag_finalInput = products_w_tag_finalInput;
  assign operands_translated_payload_tag_tileLast = products_w_tag_tileLast;
  assign operands_translated_payload_tag_last = products_w_tag_last;
  assign operands_translated_payload_values_0_0 = products_w_values_0_0;
  assign operands_translated_payload_values_0_1 = products_w_values_0_1;
  assign operands_translated_payload_values_0_2 = products_w_values_0_2;
  assign operands_translated_payload_values_0_3 = products_w_values_0_3;
  assign operands_translated_payload_values_0_4 = products_w_values_0_4;
  assign operands_translated_payload_values_0_5 = products_w_values_0_5;
  assign operands_translated_payload_values_0_6 = products_w_values_0_6;
  assign operands_translated_payload_values_0_7 = products_w_values_0_7;
  assign operands_translated_payload_values_0_8 = products_w_values_0_8;
  assign operands_translated_payload_values_0_9 = products_w_values_0_9;
  assign operands_translated_payload_values_0_10 = products_w_values_0_10;
  assign operands_translated_payload_values_0_11 = products_w_values_0_11;
  assign operands_translated_payload_values_0_12 = products_w_values_0_12;
  assign operands_translated_payload_values_0_13 = products_w_values_0_13;
  assign operands_translated_payload_values_0_14 = products_w_values_0_14;
  assign operands_translated_payload_values_0_15 = products_w_values_0_15;
  assign operands_translated_payload_values_1_0 = products_w_values_1_0;
  assign operands_translated_payload_values_1_1 = products_w_values_1_1;
  assign operands_translated_payload_values_1_2 = products_w_values_1_2;
  assign operands_translated_payload_values_1_3 = products_w_values_1_3;
  assign operands_translated_payload_values_1_4 = products_w_values_1_4;
  assign operands_translated_payload_values_1_5 = products_w_values_1_5;
  assign operands_translated_payload_values_1_6 = products_w_values_1_6;
  assign operands_translated_payload_values_1_7 = products_w_values_1_7;
  assign operands_translated_payload_values_1_8 = products_w_values_1_8;
  assign operands_translated_payload_values_1_9 = products_w_values_1_9;
  assign operands_translated_payload_values_1_10 = products_w_values_1_10;
  assign operands_translated_payload_values_1_11 = products_w_values_1_11;
  assign operands_translated_payload_values_1_12 = products_w_values_1_12;
  assign operands_translated_payload_values_1_13 = products_w_values_1_13;
  assign operands_translated_payload_values_1_14 = products_w_values_1_14;
  assign operands_translated_payload_values_1_15 = products_w_values_1_15;
  assign operands_translated_payload_values_2_0 = products_w_values_2_0;
  assign operands_translated_payload_values_2_1 = products_w_values_2_1;
  assign operands_translated_payload_values_2_2 = products_w_values_2_2;
  assign operands_translated_payload_values_2_3 = products_w_values_2_3;
  assign operands_translated_payload_values_2_4 = products_w_values_2_4;
  assign operands_translated_payload_values_2_5 = products_w_values_2_5;
  assign operands_translated_payload_values_2_6 = products_w_values_2_6;
  assign operands_translated_payload_values_2_7 = products_w_values_2_7;
  assign operands_translated_payload_values_2_8 = products_w_values_2_8;
  assign operands_translated_payload_values_2_9 = products_w_values_2_9;
  assign operands_translated_payload_values_2_10 = products_w_values_2_10;
  assign operands_translated_payload_values_2_11 = products_w_values_2_11;
  assign operands_translated_payload_values_2_12 = products_w_values_2_12;
  assign operands_translated_payload_values_2_13 = products_w_values_2_13;
  assign operands_translated_payload_values_2_14 = products_w_values_2_14;
  assign operands_translated_payload_values_2_15 = products_w_values_2_15;
  assign operands_translated_payload_values_3_0 = products_w_values_3_0;
  assign operands_translated_payload_values_3_1 = products_w_values_3_1;
  assign operands_translated_payload_values_3_2 = products_w_values_3_2;
  assign operands_translated_payload_values_3_3 = products_w_values_3_3;
  assign operands_translated_payload_values_3_4 = products_w_values_3_4;
  assign operands_translated_payload_values_3_5 = products_w_values_3_5;
  assign operands_translated_payload_values_3_6 = products_w_values_3_6;
  assign operands_translated_payload_values_3_7 = products_w_values_3_7;
  assign operands_translated_payload_values_3_8 = products_w_values_3_8;
  assign operands_translated_payload_values_3_9 = products_w_values_3_9;
  assign operands_translated_payload_values_3_10 = products_w_values_3_10;
  assign operands_translated_payload_values_3_11 = products_w_values_3_11;
  assign operands_translated_payload_values_3_12 = products_w_values_3_12;
  assign operands_translated_payload_values_3_13 = products_w_values_3_13;
  assign operands_translated_payload_values_3_14 = products_w_values_3_14;
  assign operands_translated_payload_values_3_15 = products_w_values_3_15;
  assign operands_translated_payload_values_4_0 = products_w_values_4_0;
  assign operands_translated_payload_values_4_1 = products_w_values_4_1;
  assign operands_translated_payload_values_4_2 = products_w_values_4_2;
  assign operands_translated_payload_values_4_3 = products_w_values_4_3;
  assign operands_translated_payload_values_4_4 = products_w_values_4_4;
  assign operands_translated_payload_values_4_5 = products_w_values_4_5;
  assign operands_translated_payload_values_4_6 = products_w_values_4_6;
  assign operands_translated_payload_values_4_7 = products_w_values_4_7;
  assign operands_translated_payload_values_4_8 = products_w_values_4_8;
  assign operands_translated_payload_values_4_9 = products_w_values_4_9;
  assign operands_translated_payload_values_4_10 = products_w_values_4_10;
  assign operands_translated_payload_values_4_11 = products_w_values_4_11;
  assign operands_translated_payload_values_4_12 = products_w_values_4_12;
  assign operands_translated_payload_values_4_13 = products_w_values_4_13;
  assign operands_translated_payload_values_4_14 = products_w_values_4_14;
  assign operands_translated_payload_values_4_15 = products_w_values_4_15;
  assign operands_translated_payload_values_5_0 = products_w_values_5_0;
  assign operands_translated_payload_values_5_1 = products_w_values_5_1;
  assign operands_translated_payload_values_5_2 = products_w_values_5_2;
  assign operands_translated_payload_values_5_3 = products_w_values_5_3;
  assign operands_translated_payload_values_5_4 = products_w_values_5_4;
  assign operands_translated_payload_values_5_5 = products_w_values_5_5;
  assign operands_translated_payload_values_5_6 = products_w_values_5_6;
  assign operands_translated_payload_values_5_7 = products_w_values_5_7;
  assign operands_translated_payload_values_5_8 = products_w_values_5_8;
  assign operands_translated_payload_values_5_9 = products_w_values_5_9;
  assign operands_translated_payload_values_5_10 = products_w_values_5_10;
  assign operands_translated_payload_values_5_11 = products_w_values_5_11;
  assign operands_translated_payload_values_5_12 = products_w_values_5_12;
  assign operands_translated_payload_values_5_13 = products_w_values_5_13;
  assign operands_translated_payload_values_5_14 = products_w_values_5_14;
  assign operands_translated_payload_values_5_15 = products_w_values_5_15;
  assign operands_translated_payload_values_6_0 = products_w_values_6_0;
  assign operands_translated_payload_values_6_1 = products_w_values_6_1;
  assign operands_translated_payload_values_6_2 = products_w_values_6_2;
  assign operands_translated_payload_values_6_3 = products_w_values_6_3;
  assign operands_translated_payload_values_6_4 = products_w_values_6_4;
  assign operands_translated_payload_values_6_5 = products_w_values_6_5;
  assign operands_translated_payload_values_6_6 = products_w_values_6_6;
  assign operands_translated_payload_values_6_7 = products_w_values_6_7;
  assign operands_translated_payload_values_6_8 = products_w_values_6_8;
  assign operands_translated_payload_values_6_9 = products_w_values_6_9;
  assign operands_translated_payload_values_6_10 = products_w_values_6_10;
  assign operands_translated_payload_values_6_11 = products_w_values_6_11;
  assign operands_translated_payload_values_6_12 = products_w_values_6_12;
  assign operands_translated_payload_values_6_13 = products_w_values_6_13;
  assign operands_translated_payload_values_6_14 = products_w_values_6_14;
  assign operands_translated_payload_values_6_15 = products_w_values_6_15;
  assign operands_translated_payload_values_7_0 = products_w_values_7_0;
  assign operands_translated_payload_values_7_1 = products_w_values_7_1;
  assign operands_translated_payload_values_7_2 = products_w_values_7_2;
  assign operands_translated_payload_values_7_3 = products_w_values_7_3;
  assign operands_translated_payload_values_7_4 = products_w_values_7_4;
  assign operands_translated_payload_values_7_5 = products_w_values_7_5;
  assign operands_translated_payload_values_7_6 = products_w_values_7_6;
  assign operands_translated_payload_values_7_7 = products_w_values_7_7;
  assign operands_translated_payload_values_7_8 = products_w_values_7_8;
  assign operands_translated_payload_values_7_9 = products_w_values_7_9;
  assign operands_translated_payload_values_7_10 = products_w_values_7_10;
  assign operands_translated_payload_values_7_11 = products_w_values_7_11;
  assign operands_translated_payload_values_7_12 = products_w_values_7_12;
  assign operands_translated_payload_values_7_13 = products_w_values_7_13;
  assign operands_translated_payload_values_7_14 = products_w_values_7_14;
  assign operands_translated_payload_values_7_15 = products_w_values_7_15;
  assign operands_translated_payload_values_8_0 = products_w_values_8_0;
  assign operands_translated_payload_values_8_1 = products_w_values_8_1;
  assign operands_translated_payload_values_8_2 = products_w_values_8_2;
  assign operands_translated_payload_values_8_3 = products_w_values_8_3;
  assign operands_translated_payload_values_8_4 = products_w_values_8_4;
  assign operands_translated_payload_values_8_5 = products_w_values_8_5;
  assign operands_translated_payload_values_8_6 = products_w_values_8_6;
  assign operands_translated_payload_values_8_7 = products_w_values_8_7;
  assign operands_translated_payload_values_8_8 = products_w_values_8_8;
  assign operands_translated_payload_values_8_9 = products_w_values_8_9;
  assign operands_translated_payload_values_8_10 = products_w_values_8_10;
  assign operands_translated_payload_values_8_11 = products_w_values_8_11;
  assign operands_translated_payload_values_8_12 = products_w_values_8_12;
  assign operands_translated_payload_values_8_13 = products_w_values_8_13;
  assign operands_translated_payload_values_8_14 = products_w_values_8_14;
  assign operands_translated_payload_values_8_15 = products_w_values_8_15;
  assign operands_translated_payload_values_9_0 = products_w_values_9_0;
  assign operands_translated_payload_values_9_1 = products_w_values_9_1;
  assign operands_translated_payload_values_9_2 = products_w_values_9_2;
  assign operands_translated_payload_values_9_3 = products_w_values_9_3;
  assign operands_translated_payload_values_9_4 = products_w_values_9_4;
  assign operands_translated_payload_values_9_5 = products_w_values_9_5;
  assign operands_translated_payload_values_9_6 = products_w_values_9_6;
  assign operands_translated_payload_values_9_7 = products_w_values_9_7;
  assign operands_translated_payload_values_9_8 = products_w_values_9_8;
  assign operands_translated_payload_values_9_9 = products_w_values_9_9;
  assign operands_translated_payload_values_9_10 = products_w_values_9_10;
  assign operands_translated_payload_values_9_11 = products_w_values_9_11;
  assign operands_translated_payload_values_9_12 = products_w_values_9_12;
  assign operands_translated_payload_values_9_13 = products_w_values_9_13;
  assign operands_translated_payload_values_9_14 = products_w_values_9_14;
  assign operands_translated_payload_values_9_15 = products_w_values_9_15;
  assign operands_translated_payload_values_10_0 = products_w_values_10_0;
  assign operands_translated_payload_values_10_1 = products_w_values_10_1;
  assign operands_translated_payload_values_10_2 = products_w_values_10_2;
  assign operands_translated_payload_values_10_3 = products_w_values_10_3;
  assign operands_translated_payload_values_10_4 = products_w_values_10_4;
  assign operands_translated_payload_values_10_5 = products_w_values_10_5;
  assign operands_translated_payload_values_10_6 = products_w_values_10_6;
  assign operands_translated_payload_values_10_7 = products_w_values_10_7;
  assign operands_translated_payload_values_10_8 = products_w_values_10_8;
  assign operands_translated_payload_values_10_9 = products_w_values_10_9;
  assign operands_translated_payload_values_10_10 = products_w_values_10_10;
  assign operands_translated_payload_values_10_11 = products_w_values_10_11;
  assign operands_translated_payload_values_10_12 = products_w_values_10_12;
  assign operands_translated_payload_values_10_13 = products_w_values_10_13;
  assign operands_translated_payload_values_10_14 = products_w_values_10_14;
  assign operands_translated_payload_values_10_15 = products_w_values_10_15;
  assign operands_translated_payload_values_11_0 = products_w_values_11_0;
  assign operands_translated_payload_values_11_1 = products_w_values_11_1;
  assign operands_translated_payload_values_11_2 = products_w_values_11_2;
  assign operands_translated_payload_values_11_3 = products_w_values_11_3;
  assign operands_translated_payload_values_11_4 = products_w_values_11_4;
  assign operands_translated_payload_values_11_5 = products_w_values_11_5;
  assign operands_translated_payload_values_11_6 = products_w_values_11_6;
  assign operands_translated_payload_values_11_7 = products_w_values_11_7;
  assign operands_translated_payload_values_11_8 = products_w_values_11_8;
  assign operands_translated_payload_values_11_9 = products_w_values_11_9;
  assign operands_translated_payload_values_11_10 = products_w_values_11_10;
  assign operands_translated_payload_values_11_11 = products_w_values_11_11;
  assign operands_translated_payload_values_11_12 = products_w_values_11_12;
  assign operands_translated_payload_values_11_13 = products_w_values_11_13;
  assign operands_translated_payload_values_11_14 = products_w_values_11_14;
  assign operands_translated_payload_values_11_15 = products_w_values_11_15;
  assign operands_translated_payload_values_12_0 = products_w_values_12_0;
  assign operands_translated_payload_values_12_1 = products_w_values_12_1;
  assign operands_translated_payload_values_12_2 = products_w_values_12_2;
  assign operands_translated_payload_values_12_3 = products_w_values_12_3;
  assign operands_translated_payload_values_12_4 = products_w_values_12_4;
  assign operands_translated_payload_values_12_5 = products_w_values_12_5;
  assign operands_translated_payload_values_12_6 = products_w_values_12_6;
  assign operands_translated_payload_values_12_7 = products_w_values_12_7;
  assign operands_translated_payload_values_12_8 = products_w_values_12_8;
  assign operands_translated_payload_values_12_9 = products_w_values_12_9;
  assign operands_translated_payload_values_12_10 = products_w_values_12_10;
  assign operands_translated_payload_values_12_11 = products_w_values_12_11;
  assign operands_translated_payload_values_12_12 = products_w_values_12_12;
  assign operands_translated_payload_values_12_13 = products_w_values_12_13;
  assign operands_translated_payload_values_12_14 = products_w_values_12_14;
  assign operands_translated_payload_values_12_15 = products_w_values_12_15;
  assign operands_translated_payload_values_13_0 = products_w_values_13_0;
  assign operands_translated_payload_values_13_1 = products_w_values_13_1;
  assign operands_translated_payload_values_13_2 = products_w_values_13_2;
  assign operands_translated_payload_values_13_3 = products_w_values_13_3;
  assign operands_translated_payload_values_13_4 = products_w_values_13_4;
  assign operands_translated_payload_values_13_5 = products_w_values_13_5;
  assign operands_translated_payload_values_13_6 = products_w_values_13_6;
  assign operands_translated_payload_values_13_7 = products_w_values_13_7;
  assign operands_translated_payload_values_13_8 = products_w_values_13_8;
  assign operands_translated_payload_values_13_9 = products_w_values_13_9;
  assign operands_translated_payload_values_13_10 = products_w_values_13_10;
  assign operands_translated_payload_values_13_11 = products_w_values_13_11;
  assign operands_translated_payload_values_13_12 = products_w_values_13_12;
  assign operands_translated_payload_values_13_13 = products_w_values_13_13;
  assign operands_translated_payload_values_13_14 = products_w_values_13_14;
  assign operands_translated_payload_values_13_15 = products_w_values_13_15;
  assign operands_translated_payload_values_14_0 = products_w_values_14_0;
  assign operands_translated_payload_values_14_1 = products_w_values_14_1;
  assign operands_translated_payload_values_14_2 = products_w_values_14_2;
  assign operands_translated_payload_values_14_3 = products_w_values_14_3;
  assign operands_translated_payload_values_14_4 = products_w_values_14_4;
  assign operands_translated_payload_values_14_5 = products_w_values_14_5;
  assign operands_translated_payload_values_14_6 = products_w_values_14_6;
  assign operands_translated_payload_values_14_7 = products_w_values_14_7;
  assign operands_translated_payload_values_14_8 = products_w_values_14_8;
  assign operands_translated_payload_values_14_9 = products_w_values_14_9;
  assign operands_translated_payload_values_14_10 = products_w_values_14_10;
  assign operands_translated_payload_values_14_11 = products_w_values_14_11;
  assign operands_translated_payload_values_14_12 = products_w_values_14_12;
  assign operands_translated_payload_values_14_13 = products_w_values_14_13;
  assign operands_translated_payload_values_14_14 = products_w_values_14_14;
  assign operands_translated_payload_values_14_15 = products_w_values_14_15;
  assign operands_translated_payload_values_15_0 = products_w_values_15_0;
  assign operands_translated_payload_values_15_1 = products_w_values_15_1;
  assign operands_translated_payload_values_15_2 = products_w_values_15_2;
  assign operands_translated_payload_values_15_3 = products_w_values_15_3;
  assign operands_translated_payload_values_15_4 = products_w_values_15_4;
  assign operands_translated_payload_values_15_5 = products_w_values_15_5;
  assign operands_translated_payload_values_15_6 = products_w_values_15_6;
  assign operands_translated_payload_values_15_7 = products_w_values_15_7;
  assign operands_translated_payload_values_15_8 = products_w_values_15_8;
  assign operands_translated_payload_values_15_9 = products_w_values_15_9;
  assign operands_translated_payload_values_15_10 = products_w_values_15_10;
  assign operands_translated_payload_values_15_11 = products_w_values_15_11;
  assign operands_translated_payload_values_15_12 = products_w_values_15_12;
  assign operands_translated_payload_values_15_13 = products_w_values_15_13;
  assign operands_translated_payload_values_15_14 = products_w_values_15_14;
  assign operands_translated_payload_values_15_15 = products_w_values_15_15;
  always @(*) begin
    operands_translated_ready = products_ready;
    if(when_Stream_l477_2) begin
      operands_translated_ready = 1'b1;
    end
  end

  assign when_Stream_l477_2 = (! products_valid);
  assign products_valid = operands_translated_rValid;
  assign products_payload_tag_pixel = operands_translated_rData_tag_pixel;
  assign products_payload_tag_localPixel = operands_translated_rData_tag_localPixel;
  assign products_payload_tag_group = operands_translated_rData_tag_group;
  assign products_payload_tag_mask = operands_translated_rData_tag_mask;
  assign products_payload_tag_first = operands_translated_rData_tag_first;
  assign products_payload_tag_finalInput = operands_translated_rData_tag_finalInput;
  assign products_payload_tag_tileLast = operands_translated_rData_tag_tileLast;
  assign products_payload_tag_last = operands_translated_rData_tag_last;
  assign products_payload_values_0_0 = operands_translated_rData_values_0_0;
  assign products_payload_values_0_1 = operands_translated_rData_values_0_1;
  assign products_payload_values_0_2 = operands_translated_rData_values_0_2;
  assign products_payload_values_0_3 = operands_translated_rData_values_0_3;
  assign products_payload_values_0_4 = operands_translated_rData_values_0_4;
  assign products_payload_values_0_5 = operands_translated_rData_values_0_5;
  assign products_payload_values_0_6 = operands_translated_rData_values_0_6;
  assign products_payload_values_0_7 = operands_translated_rData_values_0_7;
  assign products_payload_values_0_8 = operands_translated_rData_values_0_8;
  assign products_payload_values_0_9 = operands_translated_rData_values_0_9;
  assign products_payload_values_0_10 = operands_translated_rData_values_0_10;
  assign products_payload_values_0_11 = operands_translated_rData_values_0_11;
  assign products_payload_values_0_12 = operands_translated_rData_values_0_12;
  assign products_payload_values_0_13 = operands_translated_rData_values_0_13;
  assign products_payload_values_0_14 = operands_translated_rData_values_0_14;
  assign products_payload_values_0_15 = operands_translated_rData_values_0_15;
  assign products_payload_values_1_0 = operands_translated_rData_values_1_0;
  assign products_payload_values_1_1 = operands_translated_rData_values_1_1;
  assign products_payload_values_1_2 = operands_translated_rData_values_1_2;
  assign products_payload_values_1_3 = operands_translated_rData_values_1_3;
  assign products_payload_values_1_4 = operands_translated_rData_values_1_4;
  assign products_payload_values_1_5 = operands_translated_rData_values_1_5;
  assign products_payload_values_1_6 = operands_translated_rData_values_1_6;
  assign products_payload_values_1_7 = operands_translated_rData_values_1_7;
  assign products_payload_values_1_8 = operands_translated_rData_values_1_8;
  assign products_payload_values_1_9 = operands_translated_rData_values_1_9;
  assign products_payload_values_1_10 = operands_translated_rData_values_1_10;
  assign products_payload_values_1_11 = operands_translated_rData_values_1_11;
  assign products_payload_values_1_12 = operands_translated_rData_values_1_12;
  assign products_payload_values_1_13 = operands_translated_rData_values_1_13;
  assign products_payload_values_1_14 = operands_translated_rData_values_1_14;
  assign products_payload_values_1_15 = operands_translated_rData_values_1_15;
  assign products_payload_values_2_0 = operands_translated_rData_values_2_0;
  assign products_payload_values_2_1 = operands_translated_rData_values_2_1;
  assign products_payload_values_2_2 = operands_translated_rData_values_2_2;
  assign products_payload_values_2_3 = operands_translated_rData_values_2_3;
  assign products_payload_values_2_4 = operands_translated_rData_values_2_4;
  assign products_payload_values_2_5 = operands_translated_rData_values_2_5;
  assign products_payload_values_2_6 = operands_translated_rData_values_2_6;
  assign products_payload_values_2_7 = operands_translated_rData_values_2_7;
  assign products_payload_values_2_8 = operands_translated_rData_values_2_8;
  assign products_payload_values_2_9 = operands_translated_rData_values_2_9;
  assign products_payload_values_2_10 = operands_translated_rData_values_2_10;
  assign products_payload_values_2_11 = operands_translated_rData_values_2_11;
  assign products_payload_values_2_12 = operands_translated_rData_values_2_12;
  assign products_payload_values_2_13 = operands_translated_rData_values_2_13;
  assign products_payload_values_2_14 = operands_translated_rData_values_2_14;
  assign products_payload_values_2_15 = operands_translated_rData_values_2_15;
  assign products_payload_values_3_0 = operands_translated_rData_values_3_0;
  assign products_payload_values_3_1 = operands_translated_rData_values_3_1;
  assign products_payload_values_3_2 = operands_translated_rData_values_3_2;
  assign products_payload_values_3_3 = operands_translated_rData_values_3_3;
  assign products_payload_values_3_4 = operands_translated_rData_values_3_4;
  assign products_payload_values_3_5 = operands_translated_rData_values_3_5;
  assign products_payload_values_3_6 = operands_translated_rData_values_3_6;
  assign products_payload_values_3_7 = operands_translated_rData_values_3_7;
  assign products_payload_values_3_8 = operands_translated_rData_values_3_8;
  assign products_payload_values_3_9 = operands_translated_rData_values_3_9;
  assign products_payload_values_3_10 = operands_translated_rData_values_3_10;
  assign products_payload_values_3_11 = operands_translated_rData_values_3_11;
  assign products_payload_values_3_12 = operands_translated_rData_values_3_12;
  assign products_payload_values_3_13 = operands_translated_rData_values_3_13;
  assign products_payload_values_3_14 = operands_translated_rData_values_3_14;
  assign products_payload_values_3_15 = operands_translated_rData_values_3_15;
  assign products_payload_values_4_0 = operands_translated_rData_values_4_0;
  assign products_payload_values_4_1 = operands_translated_rData_values_4_1;
  assign products_payload_values_4_2 = operands_translated_rData_values_4_2;
  assign products_payload_values_4_3 = operands_translated_rData_values_4_3;
  assign products_payload_values_4_4 = operands_translated_rData_values_4_4;
  assign products_payload_values_4_5 = operands_translated_rData_values_4_5;
  assign products_payload_values_4_6 = operands_translated_rData_values_4_6;
  assign products_payload_values_4_7 = operands_translated_rData_values_4_7;
  assign products_payload_values_4_8 = operands_translated_rData_values_4_8;
  assign products_payload_values_4_9 = operands_translated_rData_values_4_9;
  assign products_payload_values_4_10 = operands_translated_rData_values_4_10;
  assign products_payload_values_4_11 = operands_translated_rData_values_4_11;
  assign products_payload_values_4_12 = operands_translated_rData_values_4_12;
  assign products_payload_values_4_13 = operands_translated_rData_values_4_13;
  assign products_payload_values_4_14 = operands_translated_rData_values_4_14;
  assign products_payload_values_4_15 = operands_translated_rData_values_4_15;
  assign products_payload_values_5_0 = operands_translated_rData_values_5_0;
  assign products_payload_values_5_1 = operands_translated_rData_values_5_1;
  assign products_payload_values_5_2 = operands_translated_rData_values_5_2;
  assign products_payload_values_5_3 = operands_translated_rData_values_5_3;
  assign products_payload_values_5_4 = operands_translated_rData_values_5_4;
  assign products_payload_values_5_5 = operands_translated_rData_values_5_5;
  assign products_payload_values_5_6 = operands_translated_rData_values_5_6;
  assign products_payload_values_5_7 = operands_translated_rData_values_5_7;
  assign products_payload_values_5_8 = operands_translated_rData_values_5_8;
  assign products_payload_values_5_9 = operands_translated_rData_values_5_9;
  assign products_payload_values_5_10 = operands_translated_rData_values_5_10;
  assign products_payload_values_5_11 = operands_translated_rData_values_5_11;
  assign products_payload_values_5_12 = operands_translated_rData_values_5_12;
  assign products_payload_values_5_13 = operands_translated_rData_values_5_13;
  assign products_payload_values_5_14 = operands_translated_rData_values_5_14;
  assign products_payload_values_5_15 = operands_translated_rData_values_5_15;
  assign products_payload_values_6_0 = operands_translated_rData_values_6_0;
  assign products_payload_values_6_1 = operands_translated_rData_values_6_1;
  assign products_payload_values_6_2 = operands_translated_rData_values_6_2;
  assign products_payload_values_6_3 = operands_translated_rData_values_6_3;
  assign products_payload_values_6_4 = operands_translated_rData_values_6_4;
  assign products_payload_values_6_5 = operands_translated_rData_values_6_5;
  assign products_payload_values_6_6 = operands_translated_rData_values_6_6;
  assign products_payload_values_6_7 = operands_translated_rData_values_6_7;
  assign products_payload_values_6_8 = operands_translated_rData_values_6_8;
  assign products_payload_values_6_9 = operands_translated_rData_values_6_9;
  assign products_payload_values_6_10 = operands_translated_rData_values_6_10;
  assign products_payload_values_6_11 = operands_translated_rData_values_6_11;
  assign products_payload_values_6_12 = operands_translated_rData_values_6_12;
  assign products_payload_values_6_13 = operands_translated_rData_values_6_13;
  assign products_payload_values_6_14 = operands_translated_rData_values_6_14;
  assign products_payload_values_6_15 = operands_translated_rData_values_6_15;
  assign products_payload_values_7_0 = operands_translated_rData_values_7_0;
  assign products_payload_values_7_1 = operands_translated_rData_values_7_1;
  assign products_payload_values_7_2 = operands_translated_rData_values_7_2;
  assign products_payload_values_7_3 = operands_translated_rData_values_7_3;
  assign products_payload_values_7_4 = operands_translated_rData_values_7_4;
  assign products_payload_values_7_5 = operands_translated_rData_values_7_5;
  assign products_payload_values_7_6 = operands_translated_rData_values_7_6;
  assign products_payload_values_7_7 = operands_translated_rData_values_7_7;
  assign products_payload_values_7_8 = operands_translated_rData_values_7_8;
  assign products_payload_values_7_9 = operands_translated_rData_values_7_9;
  assign products_payload_values_7_10 = operands_translated_rData_values_7_10;
  assign products_payload_values_7_11 = operands_translated_rData_values_7_11;
  assign products_payload_values_7_12 = operands_translated_rData_values_7_12;
  assign products_payload_values_7_13 = operands_translated_rData_values_7_13;
  assign products_payload_values_7_14 = operands_translated_rData_values_7_14;
  assign products_payload_values_7_15 = operands_translated_rData_values_7_15;
  assign products_payload_values_8_0 = operands_translated_rData_values_8_0;
  assign products_payload_values_8_1 = operands_translated_rData_values_8_1;
  assign products_payload_values_8_2 = operands_translated_rData_values_8_2;
  assign products_payload_values_8_3 = operands_translated_rData_values_8_3;
  assign products_payload_values_8_4 = operands_translated_rData_values_8_4;
  assign products_payload_values_8_5 = operands_translated_rData_values_8_5;
  assign products_payload_values_8_6 = operands_translated_rData_values_8_6;
  assign products_payload_values_8_7 = operands_translated_rData_values_8_7;
  assign products_payload_values_8_8 = operands_translated_rData_values_8_8;
  assign products_payload_values_8_9 = operands_translated_rData_values_8_9;
  assign products_payload_values_8_10 = operands_translated_rData_values_8_10;
  assign products_payload_values_8_11 = operands_translated_rData_values_8_11;
  assign products_payload_values_8_12 = operands_translated_rData_values_8_12;
  assign products_payload_values_8_13 = operands_translated_rData_values_8_13;
  assign products_payload_values_8_14 = operands_translated_rData_values_8_14;
  assign products_payload_values_8_15 = operands_translated_rData_values_8_15;
  assign products_payload_values_9_0 = operands_translated_rData_values_9_0;
  assign products_payload_values_9_1 = operands_translated_rData_values_9_1;
  assign products_payload_values_9_2 = operands_translated_rData_values_9_2;
  assign products_payload_values_9_3 = operands_translated_rData_values_9_3;
  assign products_payload_values_9_4 = operands_translated_rData_values_9_4;
  assign products_payload_values_9_5 = operands_translated_rData_values_9_5;
  assign products_payload_values_9_6 = operands_translated_rData_values_9_6;
  assign products_payload_values_9_7 = operands_translated_rData_values_9_7;
  assign products_payload_values_9_8 = operands_translated_rData_values_9_8;
  assign products_payload_values_9_9 = operands_translated_rData_values_9_9;
  assign products_payload_values_9_10 = operands_translated_rData_values_9_10;
  assign products_payload_values_9_11 = operands_translated_rData_values_9_11;
  assign products_payload_values_9_12 = operands_translated_rData_values_9_12;
  assign products_payload_values_9_13 = operands_translated_rData_values_9_13;
  assign products_payload_values_9_14 = operands_translated_rData_values_9_14;
  assign products_payload_values_9_15 = operands_translated_rData_values_9_15;
  assign products_payload_values_10_0 = operands_translated_rData_values_10_0;
  assign products_payload_values_10_1 = operands_translated_rData_values_10_1;
  assign products_payload_values_10_2 = operands_translated_rData_values_10_2;
  assign products_payload_values_10_3 = operands_translated_rData_values_10_3;
  assign products_payload_values_10_4 = operands_translated_rData_values_10_4;
  assign products_payload_values_10_5 = operands_translated_rData_values_10_5;
  assign products_payload_values_10_6 = operands_translated_rData_values_10_6;
  assign products_payload_values_10_7 = operands_translated_rData_values_10_7;
  assign products_payload_values_10_8 = operands_translated_rData_values_10_8;
  assign products_payload_values_10_9 = operands_translated_rData_values_10_9;
  assign products_payload_values_10_10 = operands_translated_rData_values_10_10;
  assign products_payload_values_10_11 = operands_translated_rData_values_10_11;
  assign products_payload_values_10_12 = operands_translated_rData_values_10_12;
  assign products_payload_values_10_13 = operands_translated_rData_values_10_13;
  assign products_payload_values_10_14 = operands_translated_rData_values_10_14;
  assign products_payload_values_10_15 = operands_translated_rData_values_10_15;
  assign products_payload_values_11_0 = operands_translated_rData_values_11_0;
  assign products_payload_values_11_1 = operands_translated_rData_values_11_1;
  assign products_payload_values_11_2 = operands_translated_rData_values_11_2;
  assign products_payload_values_11_3 = operands_translated_rData_values_11_3;
  assign products_payload_values_11_4 = operands_translated_rData_values_11_4;
  assign products_payload_values_11_5 = operands_translated_rData_values_11_5;
  assign products_payload_values_11_6 = operands_translated_rData_values_11_6;
  assign products_payload_values_11_7 = operands_translated_rData_values_11_7;
  assign products_payload_values_11_8 = operands_translated_rData_values_11_8;
  assign products_payload_values_11_9 = operands_translated_rData_values_11_9;
  assign products_payload_values_11_10 = operands_translated_rData_values_11_10;
  assign products_payload_values_11_11 = operands_translated_rData_values_11_11;
  assign products_payload_values_11_12 = operands_translated_rData_values_11_12;
  assign products_payload_values_11_13 = operands_translated_rData_values_11_13;
  assign products_payload_values_11_14 = operands_translated_rData_values_11_14;
  assign products_payload_values_11_15 = operands_translated_rData_values_11_15;
  assign products_payload_values_12_0 = operands_translated_rData_values_12_0;
  assign products_payload_values_12_1 = operands_translated_rData_values_12_1;
  assign products_payload_values_12_2 = operands_translated_rData_values_12_2;
  assign products_payload_values_12_3 = operands_translated_rData_values_12_3;
  assign products_payload_values_12_4 = operands_translated_rData_values_12_4;
  assign products_payload_values_12_5 = operands_translated_rData_values_12_5;
  assign products_payload_values_12_6 = operands_translated_rData_values_12_6;
  assign products_payload_values_12_7 = operands_translated_rData_values_12_7;
  assign products_payload_values_12_8 = operands_translated_rData_values_12_8;
  assign products_payload_values_12_9 = operands_translated_rData_values_12_9;
  assign products_payload_values_12_10 = operands_translated_rData_values_12_10;
  assign products_payload_values_12_11 = operands_translated_rData_values_12_11;
  assign products_payload_values_12_12 = operands_translated_rData_values_12_12;
  assign products_payload_values_12_13 = operands_translated_rData_values_12_13;
  assign products_payload_values_12_14 = operands_translated_rData_values_12_14;
  assign products_payload_values_12_15 = operands_translated_rData_values_12_15;
  assign products_payload_values_13_0 = operands_translated_rData_values_13_0;
  assign products_payload_values_13_1 = operands_translated_rData_values_13_1;
  assign products_payload_values_13_2 = operands_translated_rData_values_13_2;
  assign products_payload_values_13_3 = operands_translated_rData_values_13_3;
  assign products_payload_values_13_4 = operands_translated_rData_values_13_4;
  assign products_payload_values_13_5 = operands_translated_rData_values_13_5;
  assign products_payload_values_13_6 = operands_translated_rData_values_13_6;
  assign products_payload_values_13_7 = operands_translated_rData_values_13_7;
  assign products_payload_values_13_8 = operands_translated_rData_values_13_8;
  assign products_payload_values_13_9 = operands_translated_rData_values_13_9;
  assign products_payload_values_13_10 = operands_translated_rData_values_13_10;
  assign products_payload_values_13_11 = operands_translated_rData_values_13_11;
  assign products_payload_values_13_12 = operands_translated_rData_values_13_12;
  assign products_payload_values_13_13 = operands_translated_rData_values_13_13;
  assign products_payload_values_13_14 = operands_translated_rData_values_13_14;
  assign products_payload_values_13_15 = operands_translated_rData_values_13_15;
  assign products_payload_values_14_0 = operands_translated_rData_values_14_0;
  assign products_payload_values_14_1 = operands_translated_rData_values_14_1;
  assign products_payload_values_14_2 = operands_translated_rData_values_14_2;
  assign products_payload_values_14_3 = operands_translated_rData_values_14_3;
  assign products_payload_values_14_4 = operands_translated_rData_values_14_4;
  assign products_payload_values_14_5 = operands_translated_rData_values_14_5;
  assign products_payload_values_14_6 = operands_translated_rData_values_14_6;
  assign products_payload_values_14_7 = operands_translated_rData_values_14_7;
  assign products_payload_values_14_8 = operands_translated_rData_values_14_8;
  assign products_payload_values_14_9 = operands_translated_rData_values_14_9;
  assign products_payload_values_14_10 = operands_translated_rData_values_14_10;
  assign products_payload_values_14_11 = operands_translated_rData_values_14_11;
  assign products_payload_values_14_12 = operands_translated_rData_values_14_12;
  assign products_payload_values_14_13 = operands_translated_rData_values_14_13;
  assign products_payload_values_14_14 = operands_translated_rData_values_14_14;
  assign products_payload_values_14_15 = operands_translated_rData_values_14_15;
  assign products_payload_values_15_0 = operands_translated_rData_values_15_0;
  assign products_payload_values_15_1 = operands_translated_rData_values_15_1;
  assign products_payload_values_15_2 = operands_translated_rData_values_15_2;
  assign products_payload_values_15_3 = operands_translated_rData_values_15_3;
  assign products_payload_values_15_4 = operands_translated_rData_values_15_4;
  assign products_payload_values_15_5 = operands_translated_rData_values_15_5;
  assign products_payload_values_15_6 = operands_translated_rData_values_15_6;
  assign products_payload_values_15_7 = operands_translated_rData_values_15_7;
  assign products_payload_values_15_8 = operands_translated_rData_values_15_8;
  assign products_payload_values_15_9 = operands_translated_rData_values_15_9;
  assign products_payload_values_15_10 = operands_translated_rData_values_15_10;
  assign products_payload_values_15_11 = operands_translated_rData_values_15_11;
  assign products_payload_values_15_12 = operands_translated_rData_values_15_12;
  assign products_payload_values_15_13 = operands_translated_rData_values_15_13;
  assign products_payload_values_15_14 = operands_translated_rData_values_15_14;
  assign products_payload_values_15_15 = operands_translated_rData_values_15_15;
  assign reduce8_w_tag_pixel = products_payload_tag_pixel;
  assign reduce8_w_tag_localPixel = products_payload_tag_localPixel;
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
  assign reduce8_w_values_4_0 = ($signed(_zz_reduce8_w_values_4_0) + $signed(_zz_reduce8_w_values_4_0_1));
  assign reduce8_w_values_4_1 = ($signed(_zz_reduce8_w_values_4_1) + $signed(_zz_reduce8_w_values_4_1_1));
  assign reduce8_w_values_4_2 = ($signed(_zz_reduce8_w_values_4_2) + $signed(_zz_reduce8_w_values_4_2_1));
  assign reduce8_w_values_4_3 = ($signed(_zz_reduce8_w_values_4_3) + $signed(_zz_reduce8_w_values_4_3_1));
  assign reduce8_w_values_4_4 = ($signed(_zz_reduce8_w_values_4_4) + $signed(_zz_reduce8_w_values_4_4_1));
  assign reduce8_w_values_4_5 = ($signed(_zz_reduce8_w_values_4_5) + $signed(_zz_reduce8_w_values_4_5_1));
  assign reduce8_w_values_4_6 = ($signed(_zz_reduce8_w_values_4_6) + $signed(_zz_reduce8_w_values_4_6_1));
  assign reduce8_w_values_4_7 = ($signed(_zz_reduce8_w_values_4_7) + $signed(_zz_reduce8_w_values_4_7_1));
  assign reduce8_w_values_5_0 = ($signed(_zz_reduce8_w_values_5_0) + $signed(_zz_reduce8_w_values_5_0_1));
  assign reduce8_w_values_5_1 = ($signed(_zz_reduce8_w_values_5_1) + $signed(_zz_reduce8_w_values_5_1_1));
  assign reduce8_w_values_5_2 = ($signed(_zz_reduce8_w_values_5_2) + $signed(_zz_reduce8_w_values_5_2_1));
  assign reduce8_w_values_5_3 = ($signed(_zz_reduce8_w_values_5_3) + $signed(_zz_reduce8_w_values_5_3_1));
  assign reduce8_w_values_5_4 = ($signed(_zz_reduce8_w_values_5_4) + $signed(_zz_reduce8_w_values_5_4_1));
  assign reduce8_w_values_5_5 = ($signed(_zz_reduce8_w_values_5_5) + $signed(_zz_reduce8_w_values_5_5_1));
  assign reduce8_w_values_5_6 = ($signed(_zz_reduce8_w_values_5_6) + $signed(_zz_reduce8_w_values_5_6_1));
  assign reduce8_w_values_5_7 = ($signed(_zz_reduce8_w_values_5_7) + $signed(_zz_reduce8_w_values_5_7_1));
  assign reduce8_w_values_6_0 = ($signed(_zz_reduce8_w_values_6_0) + $signed(_zz_reduce8_w_values_6_0_1));
  assign reduce8_w_values_6_1 = ($signed(_zz_reduce8_w_values_6_1) + $signed(_zz_reduce8_w_values_6_1_1));
  assign reduce8_w_values_6_2 = ($signed(_zz_reduce8_w_values_6_2) + $signed(_zz_reduce8_w_values_6_2_1));
  assign reduce8_w_values_6_3 = ($signed(_zz_reduce8_w_values_6_3) + $signed(_zz_reduce8_w_values_6_3_1));
  assign reduce8_w_values_6_4 = ($signed(_zz_reduce8_w_values_6_4) + $signed(_zz_reduce8_w_values_6_4_1));
  assign reduce8_w_values_6_5 = ($signed(_zz_reduce8_w_values_6_5) + $signed(_zz_reduce8_w_values_6_5_1));
  assign reduce8_w_values_6_6 = ($signed(_zz_reduce8_w_values_6_6) + $signed(_zz_reduce8_w_values_6_6_1));
  assign reduce8_w_values_6_7 = ($signed(_zz_reduce8_w_values_6_7) + $signed(_zz_reduce8_w_values_6_7_1));
  assign reduce8_w_values_7_0 = ($signed(_zz_reduce8_w_values_7_0) + $signed(_zz_reduce8_w_values_7_0_1));
  assign reduce8_w_values_7_1 = ($signed(_zz_reduce8_w_values_7_1) + $signed(_zz_reduce8_w_values_7_1_1));
  assign reduce8_w_values_7_2 = ($signed(_zz_reduce8_w_values_7_2) + $signed(_zz_reduce8_w_values_7_2_1));
  assign reduce8_w_values_7_3 = ($signed(_zz_reduce8_w_values_7_3) + $signed(_zz_reduce8_w_values_7_3_1));
  assign reduce8_w_values_7_4 = ($signed(_zz_reduce8_w_values_7_4) + $signed(_zz_reduce8_w_values_7_4_1));
  assign reduce8_w_values_7_5 = ($signed(_zz_reduce8_w_values_7_5) + $signed(_zz_reduce8_w_values_7_5_1));
  assign reduce8_w_values_7_6 = ($signed(_zz_reduce8_w_values_7_6) + $signed(_zz_reduce8_w_values_7_6_1));
  assign reduce8_w_values_7_7 = ($signed(_zz_reduce8_w_values_7_7) + $signed(_zz_reduce8_w_values_7_7_1));
  assign reduce8_w_values_8_0 = ($signed(_zz_reduce8_w_values_8_0) + $signed(_zz_reduce8_w_values_8_0_1));
  assign reduce8_w_values_8_1 = ($signed(_zz_reduce8_w_values_8_1) + $signed(_zz_reduce8_w_values_8_1_1));
  assign reduce8_w_values_8_2 = ($signed(_zz_reduce8_w_values_8_2) + $signed(_zz_reduce8_w_values_8_2_1));
  assign reduce8_w_values_8_3 = ($signed(_zz_reduce8_w_values_8_3) + $signed(_zz_reduce8_w_values_8_3_1));
  assign reduce8_w_values_8_4 = ($signed(_zz_reduce8_w_values_8_4) + $signed(_zz_reduce8_w_values_8_4_1));
  assign reduce8_w_values_8_5 = ($signed(_zz_reduce8_w_values_8_5) + $signed(_zz_reduce8_w_values_8_5_1));
  assign reduce8_w_values_8_6 = ($signed(_zz_reduce8_w_values_8_6) + $signed(_zz_reduce8_w_values_8_6_1));
  assign reduce8_w_values_8_7 = ($signed(_zz_reduce8_w_values_8_7) + $signed(_zz_reduce8_w_values_8_7_1));
  assign reduce8_w_values_9_0 = ($signed(_zz_reduce8_w_values_9_0) + $signed(_zz_reduce8_w_values_9_0_1));
  assign reduce8_w_values_9_1 = ($signed(_zz_reduce8_w_values_9_1) + $signed(_zz_reduce8_w_values_9_1_1));
  assign reduce8_w_values_9_2 = ($signed(_zz_reduce8_w_values_9_2) + $signed(_zz_reduce8_w_values_9_2_1));
  assign reduce8_w_values_9_3 = ($signed(_zz_reduce8_w_values_9_3) + $signed(_zz_reduce8_w_values_9_3_1));
  assign reduce8_w_values_9_4 = ($signed(_zz_reduce8_w_values_9_4) + $signed(_zz_reduce8_w_values_9_4_1));
  assign reduce8_w_values_9_5 = ($signed(_zz_reduce8_w_values_9_5) + $signed(_zz_reduce8_w_values_9_5_1));
  assign reduce8_w_values_9_6 = ($signed(_zz_reduce8_w_values_9_6) + $signed(_zz_reduce8_w_values_9_6_1));
  assign reduce8_w_values_9_7 = ($signed(_zz_reduce8_w_values_9_7) + $signed(_zz_reduce8_w_values_9_7_1));
  assign reduce8_w_values_10_0 = ($signed(_zz_reduce8_w_values_10_0) + $signed(_zz_reduce8_w_values_10_0_1));
  assign reduce8_w_values_10_1 = ($signed(_zz_reduce8_w_values_10_1) + $signed(_zz_reduce8_w_values_10_1_1));
  assign reduce8_w_values_10_2 = ($signed(_zz_reduce8_w_values_10_2) + $signed(_zz_reduce8_w_values_10_2_1));
  assign reduce8_w_values_10_3 = ($signed(_zz_reduce8_w_values_10_3) + $signed(_zz_reduce8_w_values_10_3_1));
  assign reduce8_w_values_10_4 = ($signed(_zz_reduce8_w_values_10_4) + $signed(_zz_reduce8_w_values_10_4_1));
  assign reduce8_w_values_10_5 = ($signed(_zz_reduce8_w_values_10_5) + $signed(_zz_reduce8_w_values_10_5_1));
  assign reduce8_w_values_10_6 = ($signed(_zz_reduce8_w_values_10_6) + $signed(_zz_reduce8_w_values_10_6_1));
  assign reduce8_w_values_10_7 = ($signed(_zz_reduce8_w_values_10_7) + $signed(_zz_reduce8_w_values_10_7_1));
  assign reduce8_w_values_11_0 = ($signed(_zz_reduce8_w_values_11_0) + $signed(_zz_reduce8_w_values_11_0_1));
  assign reduce8_w_values_11_1 = ($signed(_zz_reduce8_w_values_11_1) + $signed(_zz_reduce8_w_values_11_1_1));
  assign reduce8_w_values_11_2 = ($signed(_zz_reduce8_w_values_11_2) + $signed(_zz_reduce8_w_values_11_2_1));
  assign reduce8_w_values_11_3 = ($signed(_zz_reduce8_w_values_11_3) + $signed(_zz_reduce8_w_values_11_3_1));
  assign reduce8_w_values_11_4 = ($signed(_zz_reduce8_w_values_11_4) + $signed(_zz_reduce8_w_values_11_4_1));
  assign reduce8_w_values_11_5 = ($signed(_zz_reduce8_w_values_11_5) + $signed(_zz_reduce8_w_values_11_5_1));
  assign reduce8_w_values_11_6 = ($signed(_zz_reduce8_w_values_11_6) + $signed(_zz_reduce8_w_values_11_6_1));
  assign reduce8_w_values_11_7 = ($signed(_zz_reduce8_w_values_11_7) + $signed(_zz_reduce8_w_values_11_7_1));
  assign reduce8_w_values_12_0 = ($signed(_zz_reduce8_w_values_12_0) + $signed(_zz_reduce8_w_values_12_0_1));
  assign reduce8_w_values_12_1 = ($signed(_zz_reduce8_w_values_12_1) + $signed(_zz_reduce8_w_values_12_1_1));
  assign reduce8_w_values_12_2 = ($signed(_zz_reduce8_w_values_12_2) + $signed(_zz_reduce8_w_values_12_2_1));
  assign reduce8_w_values_12_3 = ($signed(_zz_reduce8_w_values_12_3) + $signed(_zz_reduce8_w_values_12_3_1));
  assign reduce8_w_values_12_4 = ($signed(_zz_reduce8_w_values_12_4) + $signed(_zz_reduce8_w_values_12_4_1));
  assign reduce8_w_values_12_5 = ($signed(_zz_reduce8_w_values_12_5) + $signed(_zz_reduce8_w_values_12_5_1));
  assign reduce8_w_values_12_6 = ($signed(_zz_reduce8_w_values_12_6) + $signed(_zz_reduce8_w_values_12_6_1));
  assign reduce8_w_values_12_7 = ($signed(_zz_reduce8_w_values_12_7) + $signed(_zz_reduce8_w_values_12_7_1));
  assign reduce8_w_values_13_0 = ($signed(_zz_reduce8_w_values_13_0) + $signed(_zz_reduce8_w_values_13_0_1));
  assign reduce8_w_values_13_1 = ($signed(_zz_reduce8_w_values_13_1) + $signed(_zz_reduce8_w_values_13_1_1));
  assign reduce8_w_values_13_2 = ($signed(_zz_reduce8_w_values_13_2) + $signed(_zz_reduce8_w_values_13_2_1));
  assign reduce8_w_values_13_3 = ($signed(_zz_reduce8_w_values_13_3) + $signed(_zz_reduce8_w_values_13_3_1));
  assign reduce8_w_values_13_4 = ($signed(_zz_reduce8_w_values_13_4) + $signed(_zz_reduce8_w_values_13_4_1));
  assign reduce8_w_values_13_5 = ($signed(_zz_reduce8_w_values_13_5) + $signed(_zz_reduce8_w_values_13_5_1));
  assign reduce8_w_values_13_6 = ($signed(_zz_reduce8_w_values_13_6) + $signed(_zz_reduce8_w_values_13_6_1));
  assign reduce8_w_values_13_7 = ($signed(_zz_reduce8_w_values_13_7) + $signed(_zz_reduce8_w_values_13_7_1));
  assign reduce8_w_values_14_0 = ($signed(_zz_reduce8_w_values_14_0) + $signed(_zz_reduce8_w_values_14_0_1));
  assign reduce8_w_values_14_1 = ($signed(_zz_reduce8_w_values_14_1) + $signed(_zz_reduce8_w_values_14_1_1));
  assign reduce8_w_values_14_2 = ($signed(_zz_reduce8_w_values_14_2) + $signed(_zz_reduce8_w_values_14_2_1));
  assign reduce8_w_values_14_3 = ($signed(_zz_reduce8_w_values_14_3) + $signed(_zz_reduce8_w_values_14_3_1));
  assign reduce8_w_values_14_4 = ($signed(_zz_reduce8_w_values_14_4) + $signed(_zz_reduce8_w_values_14_4_1));
  assign reduce8_w_values_14_5 = ($signed(_zz_reduce8_w_values_14_5) + $signed(_zz_reduce8_w_values_14_5_1));
  assign reduce8_w_values_14_6 = ($signed(_zz_reduce8_w_values_14_6) + $signed(_zz_reduce8_w_values_14_6_1));
  assign reduce8_w_values_14_7 = ($signed(_zz_reduce8_w_values_14_7) + $signed(_zz_reduce8_w_values_14_7_1));
  assign reduce8_w_values_15_0 = ($signed(_zz_reduce8_w_values_15_0) + $signed(_zz_reduce8_w_values_15_0_1));
  assign reduce8_w_values_15_1 = ($signed(_zz_reduce8_w_values_15_1) + $signed(_zz_reduce8_w_values_15_1_1));
  assign reduce8_w_values_15_2 = ($signed(_zz_reduce8_w_values_15_2) + $signed(_zz_reduce8_w_values_15_2_1));
  assign reduce8_w_values_15_3 = ($signed(_zz_reduce8_w_values_15_3) + $signed(_zz_reduce8_w_values_15_3_1));
  assign reduce8_w_values_15_4 = ($signed(_zz_reduce8_w_values_15_4) + $signed(_zz_reduce8_w_values_15_4_1));
  assign reduce8_w_values_15_5 = ($signed(_zz_reduce8_w_values_15_5) + $signed(_zz_reduce8_w_values_15_5_1));
  assign reduce8_w_values_15_6 = ($signed(_zz_reduce8_w_values_15_6) + $signed(_zz_reduce8_w_values_15_6_1));
  assign reduce8_w_values_15_7 = ($signed(_zz_reduce8_w_values_15_7) + $signed(_zz_reduce8_w_values_15_7_1));
  assign products_translated_valid = products_valid;
  assign products_ready = products_translated_ready;
  assign products_translated_payload_tag_pixel = reduce8_w_tag_pixel;
  assign products_translated_payload_tag_localPixel = reduce8_w_tag_localPixel;
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
  assign products_translated_payload_values_4_0 = reduce8_w_values_4_0;
  assign products_translated_payload_values_4_1 = reduce8_w_values_4_1;
  assign products_translated_payload_values_4_2 = reduce8_w_values_4_2;
  assign products_translated_payload_values_4_3 = reduce8_w_values_4_3;
  assign products_translated_payload_values_4_4 = reduce8_w_values_4_4;
  assign products_translated_payload_values_4_5 = reduce8_w_values_4_5;
  assign products_translated_payload_values_4_6 = reduce8_w_values_4_6;
  assign products_translated_payload_values_4_7 = reduce8_w_values_4_7;
  assign products_translated_payload_values_5_0 = reduce8_w_values_5_0;
  assign products_translated_payload_values_5_1 = reduce8_w_values_5_1;
  assign products_translated_payload_values_5_2 = reduce8_w_values_5_2;
  assign products_translated_payload_values_5_3 = reduce8_w_values_5_3;
  assign products_translated_payload_values_5_4 = reduce8_w_values_5_4;
  assign products_translated_payload_values_5_5 = reduce8_w_values_5_5;
  assign products_translated_payload_values_5_6 = reduce8_w_values_5_6;
  assign products_translated_payload_values_5_7 = reduce8_w_values_5_7;
  assign products_translated_payload_values_6_0 = reduce8_w_values_6_0;
  assign products_translated_payload_values_6_1 = reduce8_w_values_6_1;
  assign products_translated_payload_values_6_2 = reduce8_w_values_6_2;
  assign products_translated_payload_values_6_3 = reduce8_w_values_6_3;
  assign products_translated_payload_values_6_4 = reduce8_w_values_6_4;
  assign products_translated_payload_values_6_5 = reduce8_w_values_6_5;
  assign products_translated_payload_values_6_6 = reduce8_w_values_6_6;
  assign products_translated_payload_values_6_7 = reduce8_w_values_6_7;
  assign products_translated_payload_values_7_0 = reduce8_w_values_7_0;
  assign products_translated_payload_values_7_1 = reduce8_w_values_7_1;
  assign products_translated_payload_values_7_2 = reduce8_w_values_7_2;
  assign products_translated_payload_values_7_3 = reduce8_w_values_7_3;
  assign products_translated_payload_values_7_4 = reduce8_w_values_7_4;
  assign products_translated_payload_values_7_5 = reduce8_w_values_7_5;
  assign products_translated_payload_values_7_6 = reduce8_w_values_7_6;
  assign products_translated_payload_values_7_7 = reduce8_w_values_7_7;
  assign products_translated_payload_values_8_0 = reduce8_w_values_8_0;
  assign products_translated_payload_values_8_1 = reduce8_w_values_8_1;
  assign products_translated_payload_values_8_2 = reduce8_w_values_8_2;
  assign products_translated_payload_values_8_3 = reduce8_w_values_8_3;
  assign products_translated_payload_values_8_4 = reduce8_w_values_8_4;
  assign products_translated_payload_values_8_5 = reduce8_w_values_8_5;
  assign products_translated_payload_values_8_6 = reduce8_w_values_8_6;
  assign products_translated_payload_values_8_7 = reduce8_w_values_8_7;
  assign products_translated_payload_values_9_0 = reduce8_w_values_9_0;
  assign products_translated_payload_values_9_1 = reduce8_w_values_9_1;
  assign products_translated_payload_values_9_2 = reduce8_w_values_9_2;
  assign products_translated_payload_values_9_3 = reduce8_w_values_9_3;
  assign products_translated_payload_values_9_4 = reduce8_w_values_9_4;
  assign products_translated_payload_values_9_5 = reduce8_w_values_9_5;
  assign products_translated_payload_values_9_6 = reduce8_w_values_9_6;
  assign products_translated_payload_values_9_7 = reduce8_w_values_9_7;
  assign products_translated_payload_values_10_0 = reduce8_w_values_10_0;
  assign products_translated_payload_values_10_1 = reduce8_w_values_10_1;
  assign products_translated_payload_values_10_2 = reduce8_w_values_10_2;
  assign products_translated_payload_values_10_3 = reduce8_w_values_10_3;
  assign products_translated_payload_values_10_4 = reduce8_w_values_10_4;
  assign products_translated_payload_values_10_5 = reduce8_w_values_10_5;
  assign products_translated_payload_values_10_6 = reduce8_w_values_10_6;
  assign products_translated_payload_values_10_7 = reduce8_w_values_10_7;
  assign products_translated_payload_values_11_0 = reduce8_w_values_11_0;
  assign products_translated_payload_values_11_1 = reduce8_w_values_11_1;
  assign products_translated_payload_values_11_2 = reduce8_w_values_11_2;
  assign products_translated_payload_values_11_3 = reduce8_w_values_11_3;
  assign products_translated_payload_values_11_4 = reduce8_w_values_11_4;
  assign products_translated_payload_values_11_5 = reduce8_w_values_11_5;
  assign products_translated_payload_values_11_6 = reduce8_w_values_11_6;
  assign products_translated_payload_values_11_7 = reduce8_w_values_11_7;
  assign products_translated_payload_values_12_0 = reduce8_w_values_12_0;
  assign products_translated_payload_values_12_1 = reduce8_w_values_12_1;
  assign products_translated_payload_values_12_2 = reduce8_w_values_12_2;
  assign products_translated_payload_values_12_3 = reduce8_w_values_12_3;
  assign products_translated_payload_values_12_4 = reduce8_w_values_12_4;
  assign products_translated_payload_values_12_5 = reduce8_w_values_12_5;
  assign products_translated_payload_values_12_6 = reduce8_w_values_12_6;
  assign products_translated_payload_values_12_7 = reduce8_w_values_12_7;
  assign products_translated_payload_values_13_0 = reduce8_w_values_13_0;
  assign products_translated_payload_values_13_1 = reduce8_w_values_13_1;
  assign products_translated_payload_values_13_2 = reduce8_w_values_13_2;
  assign products_translated_payload_values_13_3 = reduce8_w_values_13_3;
  assign products_translated_payload_values_13_4 = reduce8_w_values_13_4;
  assign products_translated_payload_values_13_5 = reduce8_w_values_13_5;
  assign products_translated_payload_values_13_6 = reduce8_w_values_13_6;
  assign products_translated_payload_values_13_7 = reduce8_w_values_13_7;
  assign products_translated_payload_values_14_0 = reduce8_w_values_14_0;
  assign products_translated_payload_values_14_1 = reduce8_w_values_14_1;
  assign products_translated_payload_values_14_2 = reduce8_w_values_14_2;
  assign products_translated_payload_values_14_3 = reduce8_w_values_14_3;
  assign products_translated_payload_values_14_4 = reduce8_w_values_14_4;
  assign products_translated_payload_values_14_5 = reduce8_w_values_14_5;
  assign products_translated_payload_values_14_6 = reduce8_w_values_14_6;
  assign products_translated_payload_values_14_7 = reduce8_w_values_14_7;
  assign products_translated_payload_values_15_0 = reduce8_w_values_15_0;
  assign products_translated_payload_values_15_1 = reduce8_w_values_15_1;
  assign products_translated_payload_values_15_2 = reduce8_w_values_15_2;
  assign products_translated_payload_values_15_3 = reduce8_w_values_15_3;
  assign products_translated_payload_values_15_4 = reduce8_w_values_15_4;
  assign products_translated_payload_values_15_5 = reduce8_w_values_15_5;
  assign products_translated_payload_values_15_6 = reduce8_w_values_15_6;
  assign products_translated_payload_values_15_7 = reduce8_w_values_15_7;
  always @(*) begin
    products_translated_ready = reduce8_ready;
    if(when_Stream_l477_3) begin
      products_translated_ready = 1'b1;
    end
  end

  assign when_Stream_l477_3 = (! reduce8_valid);
  assign reduce8_valid = products_translated_rValid;
  assign reduce8_payload_tag_pixel = products_translated_rData_tag_pixel;
  assign reduce8_payload_tag_localPixel = products_translated_rData_tag_localPixel;
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
  assign reduce8_payload_values_4_0 = products_translated_rData_values_4_0;
  assign reduce8_payload_values_4_1 = products_translated_rData_values_4_1;
  assign reduce8_payload_values_4_2 = products_translated_rData_values_4_2;
  assign reduce8_payload_values_4_3 = products_translated_rData_values_4_3;
  assign reduce8_payload_values_4_4 = products_translated_rData_values_4_4;
  assign reduce8_payload_values_4_5 = products_translated_rData_values_4_5;
  assign reduce8_payload_values_4_6 = products_translated_rData_values_4_6;
  assign reduce8_payload_values_4_7 = products_translated_rData_values_4_7;
  assign reduce8_payload_values_5_0 = products_translated_rData_values_5_0;
  assign reduce8_payload_values_5_1 = products_translated_rData_values_5_1;
  assign reduce8_payload_values_5_2 = products_translated_rData_values_5_2;
  assign reduce8_payload_values_5_3 = products_translated_rData_values_5_3;
  assign reduce8_payload_values_5_4 = products_translated_rData_values_5_4;
  assign reduce8_payload_values_5_5 = products_translated_rData_values_5_5;
  assign reduce8_payload_values_5_6 = products_translated_rData_values_5_6;
  assign reduce8_payload_values_5_7 = products_translated_rData_values_5_7;
  assign reduce8_payload_values_6_0 = products_translated_rData_values_6_0;
  assign reduce8_payload_values_6_1 = products_translated_rData_values_6_1;
  assign reduce8_payload_values_6_2 = products_translated_rData_values_6_2;
  assign reduce8_payload_values_6_3 = products_translated_rData_values_6_3;
  assign reduce8_payload_values_6_4 = products_translated_rData_values_6_4;
  assign reduce8_payload_values_6_5 = products_translated_rData_values_6_5;
  assign reduce8_payload_values_6_6 = products_translated_rData_values_6_6;
  assign reduce8_payload_values_6_7 = products_translated_rData_values_6_7;
  assign reduce8_payload_values_7_0 = products_translated_rData_values_7_0;
  assign reduce8_payload_values_7_1 = products_translated_rData_values_7_1;
  assign reduce8_payload_values_7_2 = products_translated_rData_values_7_2;
  assign reduce8_payload_values_7_3 = products_translated_rData_values_7_3;
  assign reduce8_payload_values_7_4 = products_translated_rData_values_7_4;
  assign reduce8_payload_values_7_5 = products_translated_rData_values_7_5;
  assign reduce8_payload_values_7_6 = products_translated_rData_values_7_6;
  assign reduce8_payload_values_7_7 = products_translated_rData_values_7_7;
  assign reduce8_payload_values_8_0 = products_translated_rData_values_8_0;
  assign reduce8_payload_values_8_1 = products_translated_rData_values_8_1;
  assign reduce8_payload_values_8_2 = products_translated_rData_values_8_2;
  assign reduce8_payload_values_8_3 = products_translated_rData_values_8_3;
  assign reduce8_payload_values_8_4 = products_translated_rData_values_8_4;
  assign reduce8_payload_values_8_5 = products_translated_rData_values_8_5;
  assign reduce8_payload_values_8_6 = products_translated_rData_values_8_6;
  assign reduce8_payload_values_8_7 = products_translated_rData_values_8_7;
  assign reduce8_payload_values_9_0 = products_translated_rData_values_9_0;
  assign reduce8_payload_values_9_1 = products_translated_rData_values_9_1;
  assign reduce8_payload_values_9_2 = products_translated_rData_values_9_2;
  assign reduce8_payload_values_9_3 = products_translated_rData_values_9_3;
  assign reduce8_payload_values_9_4 = products_translated_rData_values_9_4;
  assign reduce8_payload_values_9_5 = products_translated_rData_values_9_5;
  assign reduce8_payload_values_9_6 = products_translated_rData_values_9_6;
  assign reduce8_payload_values_9_7 = products_translated_rData_values_9_7;
  assign reduce8_payload_values_10_0 = products_translated_rData_values_10_0;
  assign reduce8_payload_values_10_1 = products_translated_rData_values_10_1;
  assign reduce8_payload_values_10_2 = products_translated_rData_values_10_2;
  assign reduce8_payload_values_10_3 = products_translated_rData_values_10_3;
  assign reduce8_payload_values_10_4 = products_translated_rData_values_10_4;
  assign reduce8_payload_values_10_5 = products_translated_rData_values_10_5;
  assign reduce8_payload_values_10_6 = products_translated_rData_values_10_6;
  assign reduce8_payload_values_10_7 = products_translated_rData_values_10_7;
  assign reduce8_payload_values_11_0 = products_translated_rData_values_11_0;
  assign reduce8_payload_values_11_1 = products_translated_rData_values_11_1;
  assign reduce8_payload_values_11_2 = products_translated_rData_values_11_2;
  assign reduce8_payload_values_11_3 = products_translated_rData_values_11_3;
  assign reduce8_payload_values_11_4 = products_translated_rData_values_11_4;
  assign reduce8_payload_values_11_5 = products_translated_rData_values_11_5;
  assign reduce8_payload_values_11_6 = products_translated_rData_values_11_6;
  assign reduce8_payload_values_11_7 = products_translated_rData_values_11_7;
  assign reduce8_payload_values_12_0 = products_translated_rData_values_12_0;
  assign reduce8_payload_values_12_1 = products_translated_rData_values_12_1;
  assign reduce8_payload_values_12_2 = products_translated_rData_values_12_2;
  assign reduce8_payload_values_12_3 = products_translated_rData_values_12_3;
  assign reduce8_payload_values_12_4 = products_translated_rData_values_12_4;
  assign reduce8_payload_values_12_5 = products_translated_rData_values_12_5;
  assign reduce8_payload_values_12_6 = products_translated_rData_values_12_6;
  assign reduce8_payload_values_12_7 = products_translated_rData_values_12_7;
  assign reduce8_payload_values_13_0 = products_translated_rData_values_13_0;
  assign reduce8_payload_values_13_1 = products_translated_rData_values_13_1;
  assign reduce8_payload_values_13_2 = products_translated_rData_values_13_2;
  assign reduce8_payload_values_13_3 = products_translated_rData_values_13_3;
  assign reduce8_payload_values_13_4 = products_translated_rData_values_13_4;
  assign reduce8_payload_values_13_5 = products_translated_rData_values_13_5;
  assign reduce8_payload_values_13_6 = products_translated_rData_values_13_6;
  assign reduce8_payload_values_13_7 = products_translated_rData_values_13_7;
  assign reduce8_payload_values_14_0 = products_translated_rData_values_14_0;
  assign reduce8_payload_values_14_1 = products_translated_rData_values_14_1;
  assign reduce8_payload_values_14_2 = products_translated_rData_values_14_2;
  assign reduce8_payload_values_14_3 = products_translated_rData_values_14_3;
  assign reduce8_payload_values_14_4 = products_translated_rData_values_14_4;
  assign reduce8_payload_values_14_5 = products_translated_rData_values_14_5;
  assign reduce8_payload_values_14_6 = products_translated_rData_values_14_6;
  assign reduce8_payload_values_14_7 = products_translated_rData_values_14_7;
  assign reduce8_payload_values_15_0 = products_translated_rData_values_15_0;
  assign reduce8_payload_values_15_1 = products_translated_rData_values_15_1;
  assign reduce8_payload_values_15_2 = products_translated_rData_values_15_2;
  assign reduce8_payload_values_15_3 = products_translated_rData_values_15_3;
  assign reduce8_payload_values_15_4 = products_translated_rData_values_15_4;
  assign reduce8_payload_values_15_5 = products_translated_rData_values_15_5;
  assign reduce8_payload_values_15_6 = products_translated_rData_values_15_6;
  assign reduce8_payload_values_15_7 = products_translated_rData_values_15_7;
  assign reduce4_w_tag_pixel = reduce8_payload_tag_pixel;
  assign reduce4_w_tag_localPixel = reduce8_payload_tag_localPixel;
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
  assign reduce4_w_values_4_0 = ($signed(_zz_reduce4_w_values_4_0) + $signed(_zz_reduce4_w_values_4_0_1));
  assign reduce4_w_values_4_1 = ($signed(_zz_reduce4_w_values_4_1) + $signed(_zz_reduce4_w_values_4_1_1));
  assign reduce4_w_values_4_2 = ($signed(_zz_reduce4_w_values_4_2) + $signed(_zz_reduce4_w_values_4_2_1));
  assign reduce4_w_values_4_3 = ($signed(_zz_reduce4_w_values_4_3) + $signed(_zz_reduce4_w_values_4_3_1));
  assign reduce4_w_values_5_0 = ($signed(_zz_reduce4_w_values_5_0) + $signed(_zz_reduce4_w_values_5_0_1));
  assign reduce4_w_values_5_1 = ($signed(_zz_reduce4_w_values_5_1) + $signed(_zz_reduce4_w_values_5_1_1));
  assign reduce4_w_values_5_2 = ($signed(_zz_reduce4_w_values_5_2) + $signed(_zz_reduce4_w_values_5_2_1));
  assign reduce4_w_values_5_3 = ($signed(_zz_reduce4_w_values_5_3) + $signed(_zz_reduce4_w_values_5_3_1));
  assign reduce4_w_values_6_0 = ($signed(_zz_reduce4_w_values_6_0) + $signed(_zz_reduce4_w_values_6_0_1));
  assign reduce4_w_values_6_1 = ($signed(_zz_reduce4_w_values_6_1) + $signed(_zz_reduce4_w_values_6_1_1));
  assign reduce4_w_values_6_2 = ($signed(_zz_reduce4_w_values_6_2) + $signed(_zz_reduce4_w_values_6_2_1));
  assign reduce4_w_values_6_3 = ($signed(_zz_reduce4_w_values_6_3) + $signed(_zz_reduce4_w_values_6_3_1));
  assign reduce4_w_values_7_0 = ($signed(_zz_reduce4_w_values_7_0) + $signed(_zz_reduce4_w_values_7_0_1));
  assign reduce4_w_values_7_1 = ($signed(_zz_reduce4_w_values_7_1) + $signed(_zz_reduce4_w_values_7_1_1));
  assign reduce4_w_values_7_2 = ($signed(_zz_reduce4_w_values_7_2) + $signed(_zz_reduce4_w_values_7_2_1));
  assign reduce4_w_values_7_3 = ($signed(_zz_reduce4_w_values_7_3) + $signed(_zz_reduce4_w_values_7_3_1));
  assign reduce4_w_values_8_0 = ($signed(_zz_reduce4_w_values_8_0) + $signed(_zz_reduce4_w_values_8_0_1));
  assign reduce4_w_values_8_1 = ($signed(_zz_reduce4_w_values_8_1) + $signed(_zz_reduce4_w_values_8_1_1));
  assign reduce4_w_values_8_2 = ($signed(_zz_reduce4_w_values_8_2) + $signed(_zz_reduce4_w_values_8_2_1));
  assign reduce4_w_values_8_3 = ($signed(_zz_reduce4_w_values_8_3) + $signed(_zz_reduce4_w_values_8_3_1));
  assign reduce4_w_values_9_0 = ($signed(_zz_reduce4_w_values_9_0) + $signed(_zz_reduce4_w_values_9_0_1));
  assign reduce4_w_values_9_1 = ($signed(_zz_reduce4_w_values_9_1) + $signed(_zz_reduce4_w_values_9_1_1));
  assign reduce4_w_values_9_2 = ($signed(_zz_reduce4_w_values_9_2) + $signed(_zz_reduce4_w_values_9_2_1));
  assign reduce4_w_values_9_3 = ($signed(_zz_reduce4_w_values_9_3) + $signed(_zz_reduce4_w_values_9_3_1));
  assign reduce4_w_values_10_0 = ($signed(_zz_reduce4_w_values_10_0) + $signed(_zz_reduce4_w_values_10_0_1));
  assign reduce4_w_values_10_1 = ($signed(_zz_reduce4_w_values_10_1) + $signed(_zz_reduce4_w_values_10_1_1));
  assign reduce4_w_values_10_2 = ($signed(_zz_reduce4_w_values_10_2) + $signed(_zz_reduce4_w_values_10_2_1));
  assign reduce4_w_values_10_3 = ($signed(_zz_reduce4_w_values_10_3) + $signed(_zz_reduce4_w_values_10_3_1));
  assign reduce4_w_values_11_0 = ($signed(_zz_reduce4_w_values_11_0) + $signed(_zz_reduce4_w_values_11_0_1));
  assign reduce4_w_values_11_1 = ($signed(_zz_reduce4_w_values_11_1) + $signed(_zz_reduce4_w_values_11_1_1));
  assign reduce4_w_values_11_2 = ($signed(_zz_reduce4_w_values_11_2) + $signed(_zz_reduce4_w_values_11_2_1));
  assign reduce4_w_values_11_3 = ($signed(_zz_reduce4_w_values_11_3) + $signed(_zz_reduce4_w_values_11_3_1));
  assign reduce4_w_values_12_0 = ($signed(_zz_reduce4_w_values_12_0) + $signed(_zz_reduce4_w_values_12_0_1));
  assign reduce4_w_values_12_1 = ($signed(_zz_reduce4_w_values_12_1) + $signed(_zz_reduce4_w_values_12_1_1));
  assign reduce4_w_values_12_2 = ($signed(_zz_reduce4_w_values_12_2) + $signed(_zz_reduce4_w_values_12_2_1));
  assign reduce4_w_values_12_3 = ($signed(_zz_reduce4_w_values_12_3) + $signed(_zz_reduce4_w_values_12_3_1));
  assign reduce4_w_values_13_0 = ($signed(_zz_reduce4_w_values_13_0) + $signed(_zz_reduce4_w_values_13_0_1));
  assign reduce4_w_values_13_1 = ($signed(_zz_reduce4_w_values_13_1) + $signed(_zz_reduce4_w_values_13_1_1));
  assign reduce4_w_values_13_2 = ($signed(_zz_reduce4_w_values_13_2) + $signed(_zz_reduce4_w_values_13_2_1));
  assign reduce4_w_values_13_3 = ($signed(_zz_reduce4_w_values_13_3) + $signed(_zz_reduce4_w_values_13_3_1));
  assign reduce4_w_values_14_0 = ($signed(_zz_reduce4_w_values_14_0) + $signed(_zz_reduce4_w_values_14_0_1));
  assign reduce4_w_values_14_1 = ($signed(_zz_reduce4_w_values_14_1) + $signed(_zz_reduce4_w_values_14_1_1));
  assign reduce4_w_values_14_2 = ($signed(_zz_reduce4_w_values_14_2) + $signed(_zz_reduce4_w_values_14_2_1));
  assign reduce4_w_values_14_3 = ($signed(_zz_reduce4_w_values_14_3) + $signed(_zz_reduce4_w_values_14_3_1));
  assign reduce4_w_values_15_0 = ($signed(_zz_reduce4_w_values_15_0) + $signed(_zz_reduce4_w_values_15_0_1));
  assign reduce4_w_values_15_1 = ($signed(_zz_reduce4_w_values_15_1) + $signed(_zz_reduce4_w_values_15_1_1));
  assign reduce4_w_values_15_2 = ($signed(_zz_reduce4_w_values_15_2) + $signed(_zz_reduce4_w_values_15_2_1));
  assign reduce4_w_values_15_3 = ($signed(_zz_reduce4_w_values_15_3) + $signed(_zz_reduce4_w_values_15_3_1));
  assign reduce8_translated_valid = reduce8_valid;
  assign reduce8_ready = reduce8_translated_ready;
  assign reduce8_translated_payload_tag_pixel = reduce4_w_tag_pixel;
  assign reduce8_translated_payload_tag_localPixel = reduce4_w_tag_localPixel;
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
  assign reduce8_translated_payload_values_4_0 = reduce4_w_values_4_0;
  assign reduce8_translated_payload_values_4_1 = reduce4_w_values_4_1;
  assign reduce8_translated_payload_values_4_2 = reduce4_w_values_4_2;
  assign reduce8_translated_payload_values_4_3 = reduce4_w_values_4_3;
  assign reduce8_translated_payload_values_5_0 = reduce4_w_values_5_0;
  assign reduce8_translated_payload_values_5_1 = reduce4_w_values_5_1;
  assign reduce8_translated_payload_values_5_2 = reduce4_w_values_5_2;
  assign reduce8_translated_payload_values_5_3 = reduce4_w_values_5_3;
  assign reduce8_translated_payload_values_6_0 = reduce4_w_values_6_0;
  assign reduce8_translated_payload_values_6_1 = reduce4_w_values_6_1;
  assign reduce8_translated_payload_values_6_2 = reduce4_w_values_6_2;
  assign reduce8_translated_payload_values_6_3 = reduce4_w_values_6_3;
  assign reduce8_translated_payload_values_7_0 = reduce4_w_values_7_0;
  assign reduce8_translated_payload_values_7_1 = reduce4_w_values_7_1;
  assign reduce8_translated_payload_values_7_2 = reduce4_w_values_7_2;
  assign reduce8_translated_payload_values_7_3 = reduce4_w_values_7_3;
  assign reduce8_translated_payload_values_8_0 = reduce4_w_values_8_0;
  assign reduce8_translated_payload_values_8_1 = reduce4_w_values_8_1;
  assign reduce8_translated_payload_values_8_2 = reduce4_w_values_8_2;
  assign reduce8_translated_payload_values_8_3 = reduce4_w_values_8_3;
  assign reduce8_translated_payload_values_9_0 = reduce4_w_values_9_0;
  assign reduce8_translated_payload_values_9_1 = reduce4_w_values_9_1;
  assign reduce8_translated_payload_values_9_2 = reduce4_w_values_9_2;
  assign reduce8_translated_payload_values_9_3 = reduce4_w_values_9_3;
  assign reduce8_translated_payload_values_10_0 = reduce4_w_values_10_0;
  assign reduce8_translated_payload_values_10_1 = reduce4_w_values_10_1;
  assign reduce8_translated_payload_values_10_2 = reduce4_w_values_10_2;
  assign reduce8_translated_payload_values_10_3 = reduce4_w_values_10_3;
  assign reduce8_translated_payload_values_11_0 = reduce4_w_values_11_0;
  assign reduce8_translated_payload_values_11_1 = reduce4_w_values_11_1;
  assign reduce8_translated_payload_values_11_2 = reduce4_w_values_11_2;
  assign reduce8_translated_payload_values_11_3 = reduce4_w_values_11_3;
  assign reduce8_translated_payload_values_12_0 = reduce4_w_values_12_0;
  assign reduce8_translated_payload_values_12_1 = reduce4_w_values_12_1;
  assign reduce8_translated_payload_values_12_2 = reduce4_w_values_12_2;
  assign reduce8_translated_payload_values_12_3 = reduce4_w_values_12_3;
  assign reduce8_translated_payload_values_13_0 = reduce4_w_values_13_0;
  assign reduce8_translated_payload_values_13_1 = reduce4_w_values_13_1;
  assign reduce8_translated_payload_values_13_2 = reduce4_w_values_13_2;
  assign reduce8_translated_payload_values_13_3 = reduce4_w_values_13_3;
  assign reduce8_translated_payload_values_14_0 = reduce4_w_values_14_0;
  assign reduce8_translated_payload_values_14_1 = reduce4_w_values_14_1;
  assign reduce8_translated_payload_values_14_2 = reduce4_w_values_14_2;
  assign reduce8_translated_payload_values_14_3 = reduce4_w_values_14_3;
  assign reduce8_translated_payload_values_15_0 = reduce4_w_values_15_0;
  assign reduce8_translated_payload_values_15_1 = reduce4_w_values_15_1;
  assign reduce8_translated_payload_values_15_2 = reduce4_w_values_15_2;
  assign reduce8_translated_payload_values_15_3 = reduce4_w_values_15_3;
  always @(*) begin
    reduce8_translated_ready = reduce4_ready;
    if(when_Stream_l477_4) begin
      reduce8_translated_ready = 1'b1;
    end
  end

  assign when_Stream_l477_4 = (! reduce4_valid);
  assign reduce4_valid = reduce8_translated_rValid;
  assign reduce4_payload_tag_pixel = reduce8_translated_rData_tag_pixel;
  assign reduce4_payload_tag_localPixel = reduce8_translated_rData_tag_localPixel;
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
  assign reduce4_payload_values_4_0 = reduce8_translated_rData_values_4_0;
  assign reduce4_payload_values_4_1 = reduce8_translated_rData_values_4_1;
  assign reduce4_payload_values_4_2 = reduce8_translated_rData_values_4_2;
  assign reduce4_payload_values_4_3 = reduce8_translated_rData_values_4_3;
  assign reduce4_payload_values_5_0 = reduce8_translated_rData_values_5_0;
  assign reduce4_payload_values_5_1 = reduce8_translated_rData_values_5_1;
  assign reduce4_payload_values_5_2 = reduce8_translated_rData_values_5_2;
  assign reduce4_payload_values_5_3 = reduce8_translated_rData_values_5_3;
  assign reduce4_payload_values_6_0 = reduce8_translated_rData_values_6_0;
  assign reduce4_payload_values_6_1 = reduce8_translated_rData_values_6_1;
  assign reduce4_payload_values_6_2 = reduce8_translated_rData_values_6_2;
  assign reduce4_payload_values_6_3 = reduce8_translated_rData_values_6_3;
  assign reduce4_payload_values_7_0 = reduce8_translated_rData_values_7_0;
  assign reduce4_payload_values_7_1 = reduce8_translated_rData_values_7_1;
  assign reduce4_payload_values_7_2 = reduce8_translated_rData_values_7_2;
  assign reduce4_payload_values_7_3 = reduce8_translated_rData_values_7_3;
  assign reduce4_payload_values_8_0 = reduce8_translated_rData_values_8_0;
  assign reduce4_payload_values_8_1 = reduce8_translated_rData_values_8_1;
  assign reduce4_payload_values_8_2 = reduce8_translated_rData_values_8_2;
  assign reduce4_payload_values_8_3 = reduce8_translated_rData_values_8_3;
  assign reduce4_payload_values_9_0 = reduce8_translated_rData_values_9_0;
  assign reduce4_payload_values_9_1 = reduce8_translated_rData_values_9_1;
  assign reduce4_payload_values_9_2 = reduce8_translated_rData_values_9_2;
  assign reduce4_payload_values_9_3 = reduce8_translated_rData_values_9_3;
  assign reduce4_payload_values_10_0 = reduce8_translated_rData_values_10_0;
  assign reduce4_payload_values_10_1 = reduce8_translated_rData_values_10_1;
  assign reduce4_payload_values_10_2 = reduce8_translated_rData_values_10_2;
  assign reduce4_payload_values_10_3 = reduce8_translated_rData_values_10_3;
  assign reduce4_payload_values_11_0 = reduce8_translated_rData_values_11_0;
  assign reduce4_payload_values_11_1 = reduce8_translated_rData_values_11_1;
  assign reduce4_payload_values_11_2 = reduce8_translated_rData_values_11_2;
  assign reduce4_payload_values_11_3 = reduce8_translated_rData_values_11_3;
  assign reduce4_payload_values_12_0 = reduce8_translated_rData_values_12_0;
  assign reduce4_payload_values_12_1 = reduce8_translated_rData_values_12_1;
  assign reduce4_payload_values_12_2 = reduce8_translated_rData_values_12_2;
  assign reduce4_payload_values_12_3 = reduce8_translated_rData_values_12_3;
  assign reduce4_payload_values_13_0 = reduce8_translated_rData_values_13_0;
  assign reduce4_payload_values_13_1 = reduce8_translated_rData_values_13_1;
  assign reduce4_payload_values_13_2 = reduce8_translated_rData_values_13_2;
  assign reduce4_payload_values_13_3 = reduce8_translated_rData_values_13_3;
  assign reduce4_payload_values_14_0 = reduce8_translated_rData_values_14_0;
  assign reduce4_payload_values_14_1 = reduce8_translated_rData_values_14_1;
  assign reduce4_payload_values_14_2 = reduce8_translated_rData_values_14_2;
  assign reduce4_payload_values_14_3 = reduce8_translated_rData_values_14_3;
  assign reduce4_payload_values_15_0 = reduce8_translated_rData_values_15_0;
  assign reduce4_payload_values_15_1 = reduce8_translated_rData_values_15_1;
  assign reduce4_payload_values_15_2 = reduce8_translated_rData_values_15_2;
  assign reduce4_payload_values_15_3 = reduce8_translated_rData_values_15_3;
  assign reduce2_w_tag_pixel = reduce4_payload_tag_pixel;
  assign reduce2_w_tag_localPixel = reduce4_payload_tag_localPixel;
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
  assign reduce2_w_values_4_0 = ($signed(_zz_reduce2_w_values_4_0) + $signed(_zz_reduce2_w_values_4_0_1));
  assign reduce2_w_values_4_1 = ($signed(_zz_reduce2_w_values_4_1) + $signed(_zz_reduce2_w_values_4_1_1));
  assign reduce2_w_values_5_0 = ($signed(_zz_reduce2_w_values_5_0) + $signed(_zz_reduce2_w_values_5_0_1));
  assign reduce2_w_values_5_1 = ($signed(_zz_reduce2_w_values_5_1) + $signed(_zz_reduce2_w_values_5_1_1));
  assign reduce2_w_values_6_0 = ($signed(_zz_reduce2_w_values_6_0) + $signed(_zz_reduce2_w_values_6_0_1));
  assign reduce2_w_values_6_1 = ($signed(_zz_reduce2_w_values_6_1) + $signed(_zz_reduce2_w_values_6_1_1));
  assign reduce2_w_values_7_0 = ($signed(_zz_reduce2_w_values_7_0) + $signed(_zz_reduce2_w_values_7_0_1));
  assign reduce2_w_values_7_1 = ($signed(_zz_reduce2_w_values_7_1) + $signed(_zz_reduce2_w_values_7_1_1));
  assign reduce2_w_values_8_0 = ($signed(_zz_reduce2_w_values_8_0) + $signed(_zz_reduce2_w_values_8_0_1));
  assign reduce2_w_values_8_1 = ($signed(_zz_reduce2_w_values_8_1) + $signed(_zz_reduce2_w_values_8_1_1));
  assign reduce2_w_values_9_0 = ($signed(_zz_reduce2_w_values_9_0) + $signed(_zz_reduce2_w_values_9_0_1));
  assign reduce2_w_values_9_1 = ($signed(_zz_reduce2_w_values_9_1) + $signed(_zz_reduce2_w_values_9_1_1));
  assign reduce2_w_values_10_0 = ($signed(_zz_reduce2_w_values_10_0) + $signed(_zz_reduce2_w_values_10_0_1));
  assign reduce2_w_values_10_1 = ($signed(_zz_reduce2_w_values_10_1) + $signed(_zz_reduce2_w_values_10_1_1));
  assign reduce2_w_values_11_0 = ($signed(_zz_reduce2_w_values_11_0) + $signed(_zz_reduce2_w_values_11_0_1));
  assign reduce2_w_values_11_1 = ($signed(_zz_reduce2_w_values_11_1) + $signed(_zz_reduce2_w_values_11_1_1));
  assign reduce2_w_values_12_0 = ($signed(_zz_reduce2_w_values_12_0) + $signed(_zz_reduce2_w_values_12_0_1));
  assign reduce2_w_values_12_1 = ($signed(_zz_reduce2_w_values_12_1) + $signed(_zz_reduce2_w_values_12_1_1));
  assign reduce2_w_values_13_0 = ($signed(_zz_reduce2_w_values_13_0) + $signed(_zz_reduce2_w_values_13_0_1));
  assign reduce2_w_values_13_1 = ($signed(_zz_reduce2_w_values_13_1) + $signed(_zz_reduce2_w_values_13_1_1));
  assign reduce2_w_values_14_0 = ($signed(_zz_reduce2_w_values_14_0) + $signed(_zz_reduce2_w_values_14_0_1));
  assign reduce2_w_values_14_1 = ($signed(_zz_reduce2_w_values_14_1) + $signed(_zz_reduce2_w_values_14_1_1));
  assign reduce2_w_values_15_0 = ($signed(_zz_reduce2_w_values_15_0) + $signed(_zz_reduce2_w_values_15_0_1));
  assign reduce2_w_values_15_1 = ($signed(_zz_reduce2_w_values_15_1) + $signed(_zz_reduce2_w_values_15_1_1));
  assign reduce4_translated_valid = reduce4_valid;
  assign reduce4_ready = reduce4_translated_ready;
  assign reduce4_translated_payload_tag_pixel = reduce2_w_tag_pixel;
  assign reduce4_translated_payload_tag_localPixel = reduce2_w_tag_localPixel;
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
  assign reduce4_translated_payload_values_4_0 = reduce2_w_values_4_0;
  assign reduce4_translated_payload_values_4_1 = reduce2_w_values_4_1;
  assign reduce4_translated_payload_values_5_0 = reduce2_w_values_5_0;
  assign reduce4_translated_payload_values_5_1 = reduce2_w_values_5_1;
  assign reduce4_translated_payload_values_6_0 = reduce2_w_values_6_0;
  assign reduce4_translated_payload_values_6_1 = reduce2_w_values_6_1;
  assign reduce4_translated_payload_values_7_0 = reduce2_w_values_7_0;
  assign reduce4_translated_payload_values_7_1 = reduce2_w_values_7_1;
  assign reduce4_translated_payload_values_8_0 = reduce2_w_values_8_0;
  assign reduce4_translated_payload_values_8_1 = reduce2_w_values_8_1;
  assign reduce4_translated_payload_values_9_0 = reduce2_w_values_9_0;
  assign reduce4_translated_payload_values_9_1 = reduce2_w_values_9_1;
  assign reduce4_translated_payload_values_10_0 = reduce2_w_values_10_0;
  assign reduce4_translated_payload_values_10_1 = reduce2_w_values_10_1;
  assign reduce4_translated_payload_values_11_0 = reduce2_w_values_11_0;
  assign reduce4_translated_payload_values_11_1 = reduce2_w_values_11_1;
  assign reduce4_translated_payload_values_12_0 = reduce2_w_values_12_0;
  assign reduce4_translated_payload_values_12_1 = reduce2_w_values_12_1;
  assign reduce4_translated_payload_values_13_0 = reduce2_w_values_13_0;
  assign reduce4_translated_payload_values_13_1 = reduce2_w_values_13_1;
  assign reduce4_translated_payload_values_14_0 = reduce2_w_values_14_0;
  assign reduce4_translated_payload_values_14_1 = reduce2_w_values_14_1;
  assign reduce4_translated_payload_values_15_0 = reduce2_w_values_15_0;
  assign reduce4_translated_payload_values_15_1 = reduce2_w_values_15_1;
  always @(*) begin
    reduce4_translated_ready = reduce2_ready;
    if(when_Stream_l477_5) begin
      reduce4_translated_ready = 1'b1;
    end
  end

  assign when_Stream_l477_5 = (! reduce2_valid);
  assign reduce2_valid = reduce4_translated_rValid;
  assign reduce2_payload_tag_pixel = reduce4_translated_rData_tag_pixel;
  assign reduce2_payload_tag_localPixel = reduce4_translated_rData_tag_localPixel;
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
  assign reduce2_payload_values_4_0 = reduce4_translated_rData_values_4_0;
  assign reduce2_payload_values_4_1 = reduce4_translated_rData_values_4_1;
  assign reduce2_payload_values_5_0 = reduce4_translated_rData_values_5_0;
  assign reduce2_payload_values_5_1 = reduce4_translated_rData_values_5_1;
  assign reduce2_payload_values_6_0 = reduce4_translated_rData_values_6_0;
  assign reduce2_payload_values_6_1 = reduce4_translated_rData_values_6_1;
  assign reduce2_payload_values_7_0 = reduce4_translated_rData_values_7_0;
  assign reduce2_payload_values_7_1 = reduce4_translated_rData_values_7_1;
  assign reduce2_payload_values_8_0 = reduce4_translated_rData_values_8_0;
  assign reduce2_payload_values_8_1 = reduce4_translated_rData_values_8_1;
  assign reduce2_payload_values_9_0 = reduce4_translated_rData_values_9_0;
  assign reduce2_payload_values_9_1 = reduce4_translated_rData_values_9_1;
  assign reduce2_payload_values_10_0 = reduce4_translated_rData_values_10_0;
  assign reduce2_payload_values_10_1 = reduce4_translated_rData_values_10_1;
  assign reduce2_payload_values_11_0 = reduce4_translated_rData_values_11_0;
  assign reduce2_payload_values_11_1 = reduce4_translated_rData_values_11_1;
  assign reduce2_payload_values_12_0 = reduce4_translated_rData_values_12_0;
  assign reduce2_payload_values_12_1 = reduce4_translated_rData_values_12_1;
  assign reduce2_payload_values_13_0 = reduce4_translated_rData_values_13_0;
  assign reduce2_payload_values_13_1 = reduce4_translated_rData_values_13_1;
  assign reduce2_payload_values_14_0 = reduce4_translated_rData_values_14_0;
  assign reduce2_payload_values_14_1 = reduce4_translated_rData_values_14_1;
  assign reduce2_payload_values_15_0 = reduce4_translated_rData_values_15_0;
  assign reduce2_payload_values_15_1 = reduce4_translated_rData_values_15_1;
  assign dot_w_tag_pixel = reduce2_payload_tag_pixel;
  assign dot_w_tag_localPixel = reduce2_payload_tag_localPixel;
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
  assign dot_w_values_4_0 = ($signed(_zz_dot_w_values_4_0) + $signed(_zz_dot_w_values_4_0_1));
  assign dot_w_values_5_0 = ($signed(_zz_dot_w_values_5_0) + $signed(_zz_dot_w_values_5_0_1));
  assign dot_w_values_6_0 = ($signed(_zz_dot_w_values_6_0) + $signed(_zz_dot_w_values_6_0_1));
  assign dot_w_values_7_0 = ($signed(_zz_dot_w_values_7_0) + $signed(_zz_dot_w_values_7_0_1));
  assign dot_w_values_8_0 = ($signed(_zz_dot_w_values_8_0) + $signed(_zz_dot_w_values_8_0_1));
  assign dot_w_values_9_0 = ($signed(_zz_dot_w_values_9_0) + $signed(_zz_dot_w_values_9_0_1));
  assign dot_w_values_10_0 = ($signed(_zz_dot_w_values_10_0) + $signed(_zz_dot_w_values_10_0_1));
  assign dot_w_values_11_0 = ($signed(_zz_dot_w_values_11_0) + $signed(_zz_dot_w_values_11_0_1));
  assign dot_w_values_12_0 = ($signed(_zz_dot_w_values_12_0) + $signed(_zz_dot_w_values_12_0_1));
  assign dot_w_values_13_0 = ($signed(_zz_dot_w_values_13_0) + $signed(_zz_dot_w_values_13_0_1));
  assign dot_w_values_14_0 = ($signed(_zz_dot_w_values_14_0) + $signed(_zz_dot_w_values_14_0_1));
  assign dot_w_values_15_0 = ($signed(_zz_dot_w_values_15_0) + $signed(_zz_dot_w_values_15_0_1));
  assign reduce2_translated_valid = reduce2_valid;
  assign reduce2_ready = reduce2_translated_ready;
  assign reduce2_translated_payload_tag_pixel = dot_w_tag_pixel;
  assign reduce2_translated_payload_tag_localPixel = dot_w_tag_localPixel;
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
  assign reduce2_translated_payload_values_4_0 = dot_w_values_4_0;
  assign reduce2_translated_payload_values_5_0 = dot_w_values_5_0;
  assign reduce2_translated_payload_values_6_0 = dot_w_values_6_0;
  assign reduce2_translated_payload_values_7_0 = dot_w_values_7_0;
  assign reduce2_translated_payload_values_8_0 = dot_w_values_8_0;
  assign reduce2_translated_payload_values_9_0 = dot_w_values_9_0;
  assign reduce2_translated_payload_values_10_0 = dot_w_values_10_0;
  assign reduce2_translated_payload_values_11_0 = dot_w_values_11_0;
  assign reduce2_translated_payload_values_12_0 = dot_w_values_12_0;
  assign reduce2_translated_payload_values_13_0 = dot_w_values_13_0;
  assign reduce2_translated_payload_values_14_0 = dot_w_values_14_0;
  assign reduce2_translated_payload_values_15_0 = dot_w_values_15_0;
  always @(*) begin
    reduce2_translated_ready = dot_ready;
    if(when_Stream_l477_6) begin
      reduce2_translated_ready = 1'b1;
    end
  end

  assign when_Stream_l477_6 = (! dot_valid);
  assign dot_valid = reduce2_translated_rValid;
  assign dot_payload_tag_pixel = reduce2_translated_rData_tag_pixel;
  assign dot_payload_tag_localPixel = reduce2_translated_rData_tag_localPixel;
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
  assign dot_payload_values_4_0 = reduce2_translated_rData_values_4_0;
  assign dot_payload_values_5_0 = reduce2_translated_rData_values_5_0;
  assign dot_payload_values_6_0 = reduce2_translated_rData_values_6_0;
  assign dot_payload_values_7_0 = reduce2_translated_rData_values_7_0;
  assign dot_payload_values_8_0 = reduce2_translated_rData_values_8_0;
  assign dot_payload_values_9_0 = reduce2_translated_rData_values_9_0;
  assign dot_payload_values_10_0 = reduce2_translated_rData_values_10_0;
  assign dot_payload_values_11_0 = reduce2_translated_rData_values_11_0;
  assign dot_payload_values_12_0 = reduce2_translated_rData_values_12_0;
  assign dot_payload_values_13_0 = reduce2_translated_rData_values_13_0;
  assign dot_payload_values_14_0 = reduce2_translated_rData_values_14_0;
  assign dot_payload_values_15_0 = reduce2_translated_rData_values_15_0;
  assign localPixel_w = dot_payload_tag_localPixel;
  assign dot_ready = 1'b1;
  assign _zz_3 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_acc_r_0_0 = ($signed(_zz__zz_acc_r_0_0) + $signed(_zz__zz_acc_r_0_0_2));
  assign dot_fire = (dot_valid && dot_ready);
  assign _zz_acc_r_0_0_1 = _zz_acc_r_0_0;
  assign _zz_4 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_tileMac_r_0_0 = _zz_acc_r_0_0;
  assign _zz_5 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_acc_r_1_0 = ($signed(_zz__zz_acc_r_1_0) + $signed(_zz__zz_acc_r_1_0_2));
  assign _zz_acc_r_1_0_1 = _zz_acc_r_1_0;
  assign _zz_6 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_tileMac_r_1_0 = _zz_acc_r_1_0;
  assign _zz_7 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_acc_r_2_0 = ($signed(_zz__zz_acc_r_2_0) + $signed(_zz__zz_acc_r_2_0_2));
  assign _zz_acc_r_2_0_1 = _zz_acc_r_2_0;
  assign _zz_8 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_tileMac_r_2_0 = _zz_acc_r_2_0;
  assign _zz_9 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_acc_r_3_0 = ($signed(_zz__zz_acc_r_3_0) + $signed(_zz__zz_acc_r_3_0_2));
  assign _zz_acc_r_3_0_1 = _zz_acc_r_3_0;
  assign _zz_10 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_tileMac_r_3_0 = _zz_acc_r_3_0;
  assign _zz_11 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_acc_r_4_0 = ($signed(_zz__zz_acc_r_4_0) + $signed(_zz__zz_acc_r_4_0_2));
  assign _zz_acc_r_4_0_1 = _zz_acc_r_4_0;
  assign _zz_12 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_tileMac_r_4_0 = _zz_acc_r_4_0;
  assign _zz_13 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_acc_r_5_0 = ($signed(_zz__zz_acc_r_5_0) + $signed(_zz__zz_acc_r_5_0_2));
  assign _zz_acc_r_5_0_1 = _zz_acc_r_5_0;
  assign _zz_14 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_tileMac_r_5_0 = _zz_acc_r_5_0;
  assign _zz_15 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_acc_r_6_0 = ($signed(_zz__zz_acc_r_6_0) + $signed(_zz__zz_acc_r_6_0_2));
  assign _zz_acc_r_6_0_1 = _zz_acc_r_6_0;
  assign _zz_16 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_tileMac_r_6_0 = _zz_acc_r_6_0;
  assign _zz_17 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_acc_r_7_0 = ($signed(_zz__zz_acc_r_7_0) + $signed(_zz__zz_acc_r_7_0_2));
  assign _zz_acc_r_7_0_1 = _zz_acc_r_7_0;
  assign _zz_18 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_tileMac_r_7_0 = _zz_acc_r_7_0;
  assign _zz_19 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_acc_r_8_0 = ($signed(_zz__zz_acc_r_8_0) + $signed(_zz__zz_acc_r_8_0_2));
  assign _zz_acc_r_8_0_1 = _zz_acc_r_8_0;
  assign _zz_20 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_tileMac_r_8_0 = _zz_acc_r_8_0;
  assign _zz_21 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_acc_r_9_0 = ($signed(_zz__zz_acc_r_9_0) + $signed(_zz__zz_acc_r_9_0_2));
  assign _zz_acc_r_9_0_1 = _zz_acc_r_9_0;
  assign _zz_22 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_tileMac_r_9_0 = _zz_acc_r_9_0;
  assign _zz_23 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_acc_r_10_0 = ($signed(_zz__zz_acc_r_10_0) + $signed(_zz__zz_acc_r_10_0_2));
  assign _zz_acc_r_10_0_1 = _zz_acc_r_10_0;
  assign _zz_24 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_tileMac_r_10_0 = _zz_acc_r_10_0;
  assign _zz_25 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_acc_r_11_0 = ($signed(_zz__zz_acc_r_11_0) + $signed(_zz__zz_acc_r_11_0_2));
  assign _zz_acc_r_11_0_1 = _zz_acc_r_11_0;
  assign _zz_26 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_tileMac_r_11_0 = _zz_acc_r_11_0;
  assign _zz_27 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_acc_r_12_0 = ($signed(_zz__zz_acc_r_12_0) + $signed(_zz__zz_acc_r_12_0_2));
  assign _zz_acc_r_12_0_1 = _zz_acc_r_12_0;
  assign _zz_28 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_tileMac_r_12_0 = _zz_acc_r_12_0;
  assign _zz_29 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_acc_r_13_0 = ($signed(_zz__zz_acc_r_13_0) + $signed(_zz__zz_acc_r_13_0_2));
  assign _zz_acc_r_13_0_1 = _zz_acc_r_13_0;
  assign _zz_30 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_tileMac_r_13_0 = _zz_acc_r_13_0;
  assign _zz_31 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_acc_r_14_0 = ($signed(_zz__zz_acc_r_14_0) + $signed(_zz__zz_acc_r_14_0_2));
  assign _zz_acc_r_14_0_1 = _zz_acc_r_14_0;
  assign _zz_32 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_tileMac_r_14_0 = _zz_acc_r_14_0;
  assign _zz_33 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_acc_r_15_0 = ($signed(_zz__zz_acc_r_15_0) + $signed(_zz__zz_acc_r_15_0_2));
  assign _zz_acc_r_15_0_1 = _zz_acc_r_15_0;
  assign _zz_34 = ({15'd0,1'b1} <<< localPixel_w);
  assign _zz_tileMac_r_15_0 = _zz_acc_r_15_0;
  assign when_PwMac_l419 = (dot_fire && dot_payload_tag_tileLast);
  assign _zz_serialGroupCount_r = (_zz__zz_serialGroupCount_r - _zz__zz_serialGroupCount_r_3);
  assign quantRequest_valid = ((state_r == SERIALIZE) && (! serializeIssued_r));
  assign quantRequest_payload_tag_pixel = (tileBase_r + _zz_quantRequest_payload_tag_pixel);
  assign quantRequest_payload_tag_localPixel = serialPixel_r[3:0];
  assign quantRequest_payload_tag_group = _zz_quantRequest_payload_tag_group[6:0];
  always @(*) begin
    quantRequest_payload_tag_mask[0] = (_zz_quantRequest_payload_tag_mask < _zz_quantRequest_payload_tag_mask_3);
    quantRequest_payload_tag_mask[1] = (_zz_quantRequest_payload_tag_mask_4 < _zz_quantRequest_payload_tag_mask_7);
    quantRequest_payload_tag_mask[2] = (_zz_quantRequest_payload_tag_mask_8 < _zz_quantRequest_payload_tag_mask_11);
    quantRequest_payload_tag_mask[3] = (_zz_quantRequest_payload_tag_mask_12 < _zz_quantRequest_payload_tag_mask_15);
  end

  assign _zz_quantRequest_payload_mac_0 = {serialGroup_r,2'b00};
  assign quantRequest_payload_mac_0 = _zz_quantRequest_payload_mac_0_1;
  assign _zz_quantRequest_payload_mac_1 = {serialGroup_r,2'b01};
  assign quantRequest_payload_mac_1 = _zz_quantRequest_payload_mac_1_1;
  assign _zz_quantRequest_payload_mac_2 = {serialGroup_r,2'b10};
  assign quantRequest_payload_mac_2 = _zz_quantRequest_payload_mac_2_1;
  assign _zz_quantRequest_payload_mac_3 = {serialGroup_r,2'b11};
  assign quantRequest_payload_mac_3 = _zz_quantRequest_payload_mac_3_1;
  assign quantRequest_payload_tag_first = 1'b0;
  assign quantRequest_payload_tag_finalInput = 1'b1;
  assign quantRequest_payload_tag_tileLast = ((_zz_quantRequest_payload_tag_tileLast == _zz_quantRequest_payload_tag_tileLast_1) && (serialPixel_r == _zz_quantRequest_payload_tag_tileLast_2));
  assign quantRequest_payload_tag_last = ((quantRequest_payload_tag_tileLast && (_zz_quantRequest_payload_tag_last == _zz_quantRequest_payload_tag_last_1)) && (_zz_quantRequest_payload_tag_last_2 == run_r_pixels));
  assign quantRequest_fire = (quantRequest_valid && quantRequest_ready);
  assign when_PwMac_l442 = (serialPixel_r == _zz_when_PwMac_l442);
  assign when_PwMac_l444 = (_zz_when_PwMac_l444 == _zz_when_PwMac_l444_1);
  assign _zz_paramData_w = quantRequest_payload_tag_group;
  assign paramData_w = paramMemory_spinal_port1;
  always @(*) begin
    quantRequest_ready = quantResponse_ready;
    if(when_Stream_l477_7) begin
      quantRequest_ready = 1'b1;
    end
  end

  assign when_Stream_l477_7 = (! quantResponse_valid);
  assign quantResponse_valid = quantRequest_rValid;
  assign quantResponse_payload_tag_pixel = quantRequest_rData_tag_pixel;
  assign quantResponse_payload_tag_localPixel = quantRequest_rData_tag_localPixel;
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
  assign quantInput_w_tag_pixel = quantResponse_payload_tag_pixel;
  assign quantInput_w_tag_localPixel = quantResponse_payload_tag_localPixel;
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
  assign quantInput_w_multiplier_0 = paramData_w[31 : 0];
  assign quantInput_w_bias_0 = paramData_w[95 : 32];
  assign quantInput_w_lower_0 = paramData_w[111 : 96];
  assign quantInput_w_upper_0 = paramData_w[127 : 112];
  assign quantInput_w_multiplier_1 = paramData_w[159 : 128];
  assign quantInput_w_bias_1 = paramData_w[223 : 160];
  assign quantInput_w_lower_1 = paramData_w[239 : 224];
  assign quantInput_w_upper_1 = paramData_w[255 : 240];
  assign quantInput_w_multiplier_2 = paramData_w[287 : 256];
  assign quantInput_w_bias_2 = paramData_w[351 : 288];
  assign quantInput_w_lower_2 = paramData_w[367 : 352];
  assign quantInput_w_upper_2 = paramData_w[383 : 368];
  assign quantInput_w_multiplier_3 = paramData_w[415 : 384];
  assign quantInput_w_bias_3 = paramData_w[479 : 416];
  assign quantInput_w_lower_3 = paramData_w[495 : 480];
  assign quantInput_w_upper_3 = paramData_w[511 : 496];
  assign quantResponse_translated_valid = quantResponse_valid;
  assign quantResponse_ready = quantResponse_translated_ready;
  assign quantResponse_translated_payload_tag_pixel = quantInput_w_tag_pixel;
  assign quantResponse_translated_payload_tag_localPixel = quantInput_w_tag_localPixel;
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
  assign io_output_o_fire = (io_output_o_valid && io_output_o_ready);
  assign when_PwMac_l478 = (io_output_o_fire && io_output_o_payload_last);
  assign when_PwMac_l483 = (((io_output_o_fire && (io_output_o_payload_group == _zz_when_PwMac_l483)) && (io_output_o_payload_pixel == tileLastPixel_r)) && (! io_output_o_payload_last));
  assign when_PwMac_l484 = (_zz_when_PwMac_l484 == _zz_when_PwMac_l484_1);
  always @(posedge clk or negedge resetn) begin
    if(!resetn) begin
      state_r <= 4'b0000;
      weightCount_r <= 13'h0;
      paramCount_r <= 8'h0;
      weightGroup_r <= 8'h0;
      weightInput_r <= 6'h0;
      paramGroup_r <= 8'h0;
      tileBase_r <= 19'h0;
      tileCount_r <= 5'h0;
      fillGroup_r <= 6'h0;
      fillPixel_r <= 5'h0;
      waiting_r <= 1'b0;
      issueGroup_r <= 5'h0;
      issueInput_r <= 6'h0;
      issuePixel_r <= 5'h0;
      serialGroup_r <= 2'b00;
      serialGroupCount_r <= 3'b000;
      serialPixel_r <= 5'h0;
      serializeIssued_r <= 1'b0;
      done_r <= 1'b0;
      request_rValid <= 1'b0;
      response_translated_rValid <= 1'b0;
      operands_translated_rValid <= 1'b0;
      products_translated_rValid <= 1'b0;
      reduce8_translated_rValid <= 1'b0;
      reduce4_translated_rValid <= 1'b0;
      reduce2_translated_rValid <= 1'b0;
      quantRequest_rValid <= 1'b0;
    end else begin
      done_r <= 1'b0;
      if(io_cfg_i_fire) begin
        weightCount_r <= 13'h0;
        weightGroup_r <= 8'h0;
        weightInput_r <= 6'h0;
        paramCount_r <= 8'h0;
        paramGroup_r <= 8'h0;
        state_r <= LOAD;
      end
      if(io_weights_i_fire) begin
        weightCount_r <= (weightCount_r + 13'h0001);
        if(when_PwMac_l243) begin
          weightInput_r <= 6'h0;
          weightGroup_r <= (weightGroup_r + 8'h01);
        end else begin
          weightInput_r <= (weightInput_r + 6'h01);
        end
      end
      if(io_params_i_fire) begin
        paramCount_r <= (paramCount_r + 8'h01);
        paramGroup_r <= (paramGroup_r + 8'h01);
      end
      if(when_PwMac_l249) begin
        state_r <= READY;
      end
      if(io_start_i_fire) begin
        tileBase_r <= 19'h0;
        state_r <= PREPARE;
      end
      if(when_PwMac_l259) begin
        tileCount_r <= ((19'h00010 < remaining_r) ? 5'h10 : _zz_tileCount_r);
        fillGroup_r <= 6'h0;
        fillPixel_r <= 5'h0;
        waiting_r <= 1'b0;
        state_r <= TILE_READY;
      end
      if(when_PwMac_l268) begin
        state_r <= FILL;
      end
      if(io_rd_o_fire) begin
        waiting_r <= 1'b1;
      end
      if(io_rsp_i_fire) begin
        waiting_r <= 1'b0;
        if(when_PwMac_l283) begin
          fillPixel_r <= 5'h0;
          if(when_PwMac_l285) begin
            issueGroup_r <= 5'h0;
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
        if(when_PwMac_l345) begin
          issuePixel_r <= 5'h0;
          if(when_PwMac_l347) begin
            issueInput_r <= 6'h0;
            state_r <= DRAIN;
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
      if(operands_translated_ready) begin
        operands_translated_rValid <= operands_translated_valid;
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
      if(when_PwMac_l419) begin
        serialGroup_r <= 2'b00;
        serialPixel_r <= 5'h0;
        serializeIssued_r <= 1'b0;
        serialGroupCount_r <= ((13'h0004 < _zz_serialGroupCount_r) ? 3'b100 : _zz_serialGroupCount_r_1);
        state_r <= SERIALIZE;
      end
      if(quantRequest_fire) begin
        if(when_PwMac_l442) begin
          serialPixel_r <= 5'h0;
          if(when_PwMac_l444) begin
            serializeIssued_r <= 1'b1;
          end else begin
            serialGroup_r <= (serialGroup_r + 2'b01);
          end
        end else begin
          serialPixel_r <= (serialPixel_r + 5'h01);
        end
      end
      if(quantRequest_ready) begin
        quantRequest_rValid <= quantRequest_valid;
      end
      if(when_PwMac_l478) begin
        done_r <= 1'b1;
        state_r <= READY;
      end
      if(when_PwMac_l483) begin
        if(when_PwMac_l484) begin
          tileBase_r <= (tileBase_r + _zz_tileBase_r);
          serializeIssued_r <= 1'b0;
          state_r <= PREPARE;
        end else begin
          issueGroup_r <= (issueGroup_r + 5'h01);
          issueInput_r <= 6'h0;
          issuePixel_r <= 5'h0;
          serializeIssued_r <= 1'b0;
          state_r <= ISSUE;
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
    if(io_start_i_fire) begin
      remaining_r <= run_r_pixels;
    end
    if(when_PwMac_l259) begin
      fillGroupBase_r <= {13'd0, tileBase_r};
      fillReadAddr_r <= {13'd0, tileBase_r};
    end
    if(when_PwMac_l268) begin
      tileLastPixel_r <= (_zz_tileLastPixel_r - 19'h00001);
    end
    if(io_rsp_i_fire) begin
      if(when_PwMac_l283) begin
        if(!when_PwMac_l285) begin
          fillGroupBase_r <= (fillGroupBase_r + _zz_fillGroupBase_r);
          fillReadAddr_r <= (fillGroupBase_r + _zz_fillReadAddr_r);
        end
      end else begin
        fillReadAddr_r <= (fillReadAddr_r + 32'h00000001);
      end
    end
    if(request_ready) begin
      request_rData_tag_pixel <= request_payload_tag_pixel;
      request_rData_tag_localPixel <= request_payload_tag_localPixel;
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
      response_translated_rData_tag_localPixel <= response_translated_payload_tag_localPixel;
      response_translated_rData_tag_group <= response_translated_payload_tag_group;
      response_translated_rData_tag_mask <= response_translated_payload_tag_mask;
      response_translated_rData_tag_first <= response_translated_payload_tag_first;
      response_translated_rData_tag_finalInput <= response_translated_payload_tag_finalInput;
      response_translated_rData_tag_tileLast <= response_translated_payload_tag_tileLast;
      response_translated_rData_tag_last <= response_translated_payload_tag_last;
      response_translated_rData_input <= response_translated_payload_input;
      response_translated_rData_weights_0 <= response_translated_payload_weights_0;
      response_translated_rData_weights_1 <= response_translated_payload_weights_1;
      response_translated_rData_weights_2 <= response_translated_payload_weights_2;
      response_translated_rData_weights_3 <= response_translated_payload_weights_3;
      response_translated_rData_weights_4 <= response_translated_payload_weights_4;
      response_translated_rData_weights_5 <= response_translated_payload_weights_5;
      response_translated_rData_weights_6 <= response_translated_payload_weights_6;
      response_translated_rData_weights_7 <= response_translated_payload_weights_7;
      response_translated_rData_weights_8 <= response_translated_payload_weights_8;
      response_translated_rData_weights_9 <= response_translated_payload_weights_9;
      response_translated_rData_weights_10 <= response_translated_payload_weights_10;
      response_translated_rData_weights_11 <= response_translated_payload_weights_11;
      response_translated_rData_weights_12 <= response_translated_payload_weights_12;
      response_translated_rData_weights_13 <= response_translated_payload_weights_13;
      response_translated_rData_weights_14 <= response_translated_payload_weights_14;
      response_translated_rData_weights_15 <= response_translated_payload_weights_15;
      response_translated_rData_mask <= response_translated_payload_mask;
    end
    if(operands_translated_ready) begin
      operands_translated_rData_tag_pixel <= operands_translated_payload_tag_pixel;
      operands_translated_rData_tag_localPixel <= operands_translated_payload_tag_localPixel;
      operands_translated_rData_tag_group <= operands_translated_payload_tag_group;
      operands_translated_rData_tag_mask <= operands_translated_payload_tag_mask;
      operands_translated_rData_tag_first <= operands_translated_payload_tag_first;
      operands_translated_rData_tag_finalInput <= operands_translated_payload_tag_finalInput;
      operands_translated_rData_tag_tileLast <= operands_translated_payload_tag_tileLast;
      operands_translated_rData_tag_last <= operands_translated_payload_tag_last;
      operands_translated_rData_values_0_0 <= operands_translated_payload_values_0_0;
      operands_translated_rData_values_0_1 <= operands_translated_payload_values_0_1;
      operands_translated_rData_values_0_2 <= operands_translated_payload_values_0_2;
      operands_translated_rData_values_0_3 <= operands_translated_payload_values_0_3;
      operands_translated_rData_values_0_4 <= operands_translated_payload_values_0_4;
      operands_translated_rData_values_0_5 <= operands_translated_payload_values_0_5;
      operands_translated_rData_values_0_6 <= operands_translated_payload_values_0_6;
      operands_translated_rData_values_0_7 <= operands_translated_payload_values_0_7;
      operands_translated_rData_values_0_8 <= operands_translated_payload_values_0_8;
      operands_translated_rData_values_0_9 <= operands_translated_payload_values_0_9;
      operands_translated_rData_values_0_10 <= operands_translated_payload_values_0_10;
      operands_translated_rData_values_0_11 <= operands_translated_payload_values_0_11;
      operands_translated_rData_values_0_12 <= operands_translated_payload_values_0_12;
      operands_translated_rData_values_0_13 <= operands_translated_payload_values_0_13;
      operands_translated_rData_values_0_14 <= operands_translated_payload_values_0_14;
      operands_translated_rData_values_0_15 <= operands_translated_payload_values_0_15;
      operands_translated_rData_values_1_0 <= operands_translated_payload_values_1_0;
      operands_translated_rData_values_1_1 <= operands_translated_payload_values_1_1;
      operands_translated_rData_values_1_2 <= operands_translated_payload_values_1_2;
      operands_translated_rData_values_1_3 <= operands_translated_payload_values_1_3;
      operands_translated_rData_values_1_4 <= operands_translated_payload_values_1_4;
      operands_translated_rData_values_1_5 <= operands_translated_payload_values_1_5;
      operands_translated_rData_values_1_6 <= operands_translated_payload_values_1_6;
      operands_translated_rData_values_1_7 <= operands_translated_payload_values_1_7;
      operands_translated_rData_values_1_8 <= operands_translated_payload_values_1_8;
      operands_translated_rData_values_1_9 <= operands_translated_payload_values_1_9;
      operands_translated_rData_values_1_10 <= operands_translated_payload_values_1_10;
      operands_translated_rData_values_1_11 <= operands_translated_payload_values_1_11;
      operands_translated_rData_values_1_12 <= operands_translated_payload_values_1_12;
      operands_translated_rData_values_1_13 <= operands_translated_payload_values_1_13;
      operands_translated_rData_values_1_14 <= operands_translated_payload_values_1_14;
      operands_translated_rData_values_1_15 <= operands_translated_payload_values_1_15;
      operands_translated_rData_values_2_0 <= operands_translated_payload_values_2_0;
      operands_translated_rData_values_2_1 <= operands_translated_payload_values_2_1;
      operands_translated_rData_values_2_2 <= operands_translated_payload_values_2_2;
      operands_translated_rData_values_2_3 <= operands_translated_payload_values_2_3;
      operands_translated_rData_values_2_4 <= operands_translated_payload_values_2_4;
      operands_translated_rData_values_2_5 <= operands_translated_payload_values_2_5;
      operands_translated_rData_values_2_6 <= operands_translated_payload_values_2_6;
      operands_translated_rData_values_2_7 <= operands_translated_payload_values_2_7;
      operands_translated_rData_values_2_8 <= operands_translated_payload_values_2_8;
      operands_translated_rData_values_2_9 <= operands_translated_payload_values_2_9;
      operands_translated_rData_values_2_10 <= operands_translated_payload_values_2_10;
      operands_translated_rData_values_2_11 <= operands_translated_payload_values_2_11;
      operands_translated_rData_values_2_12 <= operands_translated_payload_values_2_12;
      operands_translated_rData_values_2_13 <= operands_translated_payload_values_2_13;
      operands_translated_rData_values_2_14 <= operands_translated_payload_values_2_14;
      operands_translated_rData_values_2_15 <= operands_translated_payload_values_2_15;
      operands_translated_rData_values_3_0 <= operands_translated_payload_values_3_0;
      operands_translated_rData_values_3_1 <= operands_translated_payload_values_3_1;
      operands_translated_rData_values_3_2 <= operands_translated_payload_values_3_2;
      operands_translated_rData_values_3_3 <= operands_translated_payload_values_3_3;
      operands_translated_rData_values_3_4 <= operands_translated_payload_values_3_4;
      operands_translated_rData_values_3_5 <= operands_translated_payload_values_3_5;
      operands_translated_rData_values_3_6 <= operands_translated_payload_values_3_6;
      operands_translated_rData_values_3_7 <= operands_translated_payload_values_3_7;
      operands_translated_rData_values_3_8 <= operands_translated_payload_values_3_8;
      operands_translated_rData_values_3_9 <= operands_translated_payload_values_3_9;
      operands_translated_rData_values_3_10 <= operands_translated_payload_values_3_10;
      operands_translated_rData_values_3_11 <= operands_translated_payload_values_3_11;
      operands_translated_rData_values_3_12 <= operands_translated_payload_values_3_12;
      operands_translated_rData_values_3_13 <= operands_translated_payload_values_3_13;
      operands_translated_rData_values_3_14 <= operands_translated_payload_values_3_14;
      operands_translated_rData_values_3_15 <= operands_translated_payload_values_3_15;
      operands_translated_rData_values_4_0 <= operands_translated_payload_values_4_0;
      operands_translated_rData_values_4_1 <= operands_translated_payload_values_4_1;
      operands_translated_rData_values_4_2 <= operands_translated_payload_values_4_2;
      operands_translated_rData_values_4_3 <= operands_translated_payload_values_4_3;
      operands_translated_rData_values_4_4 <= operands_translated_payload_values_4_4;
      operands_translated_rData_values_4_5 <= operands_translated_payload_values_4_5;
      operands_translated_rData_values_4_6 <= operands_translated_payload_values_4_6;
      operands_translated_rData_values_4_7 <= operands_translated_payload_values_4_7;
      operands_translated_rData_values_4_8 <= operands_translated_payload_values_4_8;
      operands_translated_rData_values_4_9 <= operands_translated_payload_values_4_9;
      operands_translated_rData_values_4_10 <= operands_translated_payload_values_4_10;
      operands_translated_rData_values_4_11 <= operands_translated_payload_values_4_11;
      operands_translated_rData_values_4_12 <= operands_translated_payload_values_4_12;
      operands_translated_rData_values_4_13 <= operands_translated_payload_values_4_13;
      operands_translated_rData_values_4_14 <= operands_translated_payload_values_4_14;
      operands_translated_rData_values_4_15 <= operands_translated_payload_values_4_15;
      operands_translated_rData_values_5_0 <= operands_translated_payload_values_5_0;
      operands_translated_rData_values_5_1 <= operands_translated_payload_values_5_1;
      operands_translated_rData_values_5_2 <= operands_translated_payload_values_5_2;
      operands_translated_rData_values_5_3 <= operands_translated_payload_values_5_3;
      operands_translated_rData_values_5_4 <= operands_translated_payload_values_5_4;
      operands_translated_rData_values_5_5 <= operands_translated_payload_values_5_5;
      operands_translated_rData_values_5_6 <= operands_translated_payload_values_5_6;
      operands_translated_rData_values_5_7 <= operands_translated_payload_values_5_7;
      operands_translated_rData_values_5_8 <= operands_translated_payload_values_5_8;
      operands_translated_rData_values_5_9 <= operands_translated_payload_values_5_9;
      operands_translated_rData_values_5_10 <= operands_translated_payload_values_5_10;
      operands_translated_rData_values_5_11 <= operands_translated_payload_values_5_11;
      operands_translated_rData_values_5_12 <= operands_translated_payload_values_5_12;
      operands_translated_rData_values_5_13 <= operands_translated_payload_values_5_13;
      operands_translated_rData_values_5_14 <= operands_translated_payload_values_5_14;
      operands_translated_rData_values_5_15 <= operands_translated_payload_values_5_15;
      operands_translated_rData_values_6_0 <= operands_translated_payload_values_6_0;
      operands_translated_rData_values_6_1 <= operands_translated_payload_values_6_1;
      operands_translated_rData_values_6_2 <= operands_translated_payload_values_6_2;
      operands_translated_rData_values_6_3 <= operands_translated_payload_values_6_3;
      operands_translated_rData_values_6_4 <= operands_translated_payload_values_6_4;
      operands_translated_rData_values_6_5 <= operands_translated_payload_values_6_5;
      operands_translated_rData_values_6_6 <= operands_translated_payload_values_6_6;
      operands_translated_rData_values_6_7 <= operands_translated_payload_values_6_7;
      operands_translated_rData_values_6_8 <= operands_translated_payload_values_6_8;
      operands_translated_rData_values_6_9 <= operands_translated_payload_values_6_9;
      operands_translated_rData_values_6_10 <= operands_translated_payload_values_6_10;
      operands_translated_rData_values_6_11 <= operands_translated_payload_values_6_11;
      operands_translated_rData_values_6_12 <= operands_translated_payload_values_6_12;
      operands_translated_rData_values_6_13 <= operands_translated_payload_values_6_13;
      operands_translated_rData_values_6_14 <= operands_translated_payload_values_6_14;
      operands_translated_rData_values_6_15 <= operands_translated_payload_values_6_15;
      operands_translated_rData_values_7_0 <= operands_translated_payload_values_7_0;
      operands_translated_rData_values_7_1 <= operands_translated_payload_values_7_1;
      operands_translated_rData_values_7_2 <= operands_translated_payload_values_7_2;
      operands_translated_rData_values_7_3 <= operands_translated_payload_values_7_3;
      operands_translated_rData_values_7_4 <= operands_translated_payload_values_7_4;
      operands_translated_rData_values_7_5 <= operands_translated_payload_values_7_5;
      operands_translated_rData_values_7_6 <= operands_translated_payload_values_7_6;
      operands_translated_rData_values_7_7 <= operands_translated_payload_values_7_7;
      operands_translated_rData_values_7_8 <= operands_translated_payload_values_7_8;
      operands_translated_rData_values_7_9 <= operands_translated_payload_values_7_9;
      operands_translated_rData_values_7_10 <= operands_translated_payload_values_7_10;
      operands_translated_rData_values_7_11 <= operands_translated_payload_values_7_11;
      operands_translated_rData_values_7_12 <= operands_translated_payload_values_7_12;
      operands_translated_rData_values_7_13 <= operands_translated_payload_values_7_13;
      operands_translated_rData_values_7_14 <= operands_translated_payload_values_7_14;
      operands_translated_rData_values_7_15 <= operands_translated_payload_values_7_15;
      operands_translated_rData_values_8_0 <= operands_translated_payload_values_8_0;
      operands_translated_rData_values_8_1 <= operands_translated_payload_values_8_1;
      operands_translated_rData_values_8_2 <= operands_translated_payload_values_8_2;
      operands_translated_rData_values_8_3 <= operands_translated_payload_values_8_3;
      operands_translated_rData_values_8_4 <= operands_translated_payload_values_8_4;
      operands_translated_rData_values_8_5 <= operands_translated_payload_values_8_5;
      operands_translated_rData_values_8_6 <= operands_translated_payload_values_8_6;
      operands_translated_rData_values_8_7 <= operands_translated_payload_values_8_7;
      operands_translated_rData_values_8_8 <= operands_translated_payload_values_8_8;
      operands_translated_rData_values_8_9 <= operands_translated_payload_values_8_9;
      operands_translated_rData_values_8_10 <= operands_translated_payload_values_8_10;
      operands_translated_rData_values_8_11 <= operands_translated_payload_values_8_11;
      operands_translated_rData_values_8_12 <= operands_translated_payload_values_8_12;
      operands_translated_rData_values_8_13 <= operands_translated_payload_values_8_13;
      operands_translated_rData_values_8_14 <= operands_translated_payload_values_8_14;
      operands_translated_rData_values_8_15 <= operands_translated_payload_values_8_15;
      operands_translated_rData_values_9_0 <= operands_translated_payload_values_9_0;
      operands_translated_rData_values_9_1 <= operands_translated_payload_values_9_1;
      operands_translated_rData_values_9_2 <= operands_translated_payload_values_9_2;
      operands_translated_rData_values_9_3 <= operands_translated_payload_values_9_3;
      operands_translated_rData_values_9_4 <= operands_translated_payload_values_9_4;
      operands_translated_rData_values_9_5 <= operands_translated_payload_values_9_5;
      operands_translated_rData_values_9_6 <= operands_translated_payload_values_9_6;
      operands_translated_rData_values_9_7 <= operands_translated_payload_values_9_7;
      operands_translated_rData_values_9_8 <= operands_translated_payload_values_9_8;
      operands_translated_rData_values_9_9 <= operands_translated_payload_values_9_9;
      operands_translated_rData_values_9_10 <= operands_translated_payload_values_9_10;
      operands_translated_rData_values_9_11 <= operands_translated_payload_values_9_11;
      operands_translated_rData_values_9_12 <= operands_translated_payload_values_9_12;
      operands_translated_rData_values_9_13 <= operands_translated_payload_values_9_13;
      operands_translated_rData_values_9_14 <= operands_translated_payload_values_9_14;
      operands_translated_rData_values_9_15 <= operands_translated_payload_values_9_15;
      operands_translated_rData_values_10_0 <= operands_translated_payload_values_10_0;
      operands_translated_rData_values_10_1 <= operands_translated_payload_values_10_1;
      operands_translated_rData_values_10_2 <= operands_translated_payload_values_10_2;
      operands_translated_rData_values_10_3 <= operands_translated_payload_values_10_3;
      operands_translated_rData_values_10_4 <= operands_translated_payload_values_10_4;
      operands_translated_rData_values_10_5 <= operands_translated_payload_values_10_5;
      operands_translated_rData_values_10_6 <= operands_translated_payload_values_10_6;
      operands_translated_rData_values_10_7 <= operands_translated_payload_values_10_7;
      operands_translated_rData_values_10_8 <= operands_translated_payload_values_10_8;
      operands_translated_rData_values_10_9 <= operands_translated_payload_values_10_9;
      operands_translated_rData_values_10_10 <= operands_translated_payload_values_10_10;
      operands_translated_rData_values_10_11 <= operands_translated_payload_values_10_11;
      operands_translated_rData_values_10_12 <= operands_translated_payload_values_10_12;
      operands_translated_rData_values_10_13 <= operands_translated_payload_values_10_13;
      operands_translated_rData_values_10_14 <= operands_translated_payload_values_10_14;
      operands_translated_rData_values_10_15 <= operands_translated_payload_values_10_15;
      operands_translated_rData_values_11_0 <= operands_translated_payload_values_11_0;
      operands_translated_rData_values_11_1 <= operands_translated_payload_values_11_1;
      operands_translated_rData_values_11_2 <= operands_translated_payload_values_11_2;
      operands_translated_rData_values_11_3 <= operands_translated_payload_values_11_3;
      operands_translated_rData_values_11_4 <= operands_translated_payload_values_11_4;
      operands_translated_rData_values_11_5 <= operands_translated_payload_values_11_5;
      operands_translated_rData_values_11_6 <= operands_translated_payload_values_11_6;
      operands_translated_rData_values_11_7 <= operands_translated_payload_values_11_7;
      operands_translated_rData_values_11_8 <= operands_translated_payload_values_11_8;
      operands_translated_rData_values_11_9 <= operands_translated_payload_values_11_9;
      operands_translated_rData_values_11_10 <= operands_translated_payload_values_11_10;
      operands_translated_rData_values_11_11 <= operands_translated_payload_values_11_11;
      operands_translated_rData_values_11_12 <= operands_translated_payload_values_11_12;
      operands_translated_rData_values_11_13 <= operands_translated_payload_values_11_13;
      operands_translated_rData_values_11_14 <= operands_translated_payload_values_11_14;
      operands_translated_rData_values_11_15 <= operands_translated_payload_values_11_15;
      operands_translated_rData_values_12_0 <= operands_translated_payload_values_12_0;
      operands_translated_rData_values_12_1 <= operands_translated_payload_values_12_1;
      operands_translated_rData_values_12_2 <= operands_translated_payload_values_12_2;
      operands_translated_rData_values_12_3 <= operands_translated_payload_values_12_3;
      operands_translated_rData_values_12_4 <= operands_translated_payload_values_12_4;
      operands_translated_rData_values_12_5 <= operands_translated_payload_values_12_5;
      operands_translated_rData_values_12_6 <= operands_translated_payload_values_12_6;
      operands_translated_rData_values_12_7 <= operands_translated_payload_values_12_7;
      operands_translated_rData_values_12_8 <= operands_translated_payload_values_12_8;
      operands_translated_rData_values_12_9 <= operands_translated_payload_values_12_9;
      operands_translated_rData_values_12_10 <= operands_translated_payload_values_12_10;
      operands_translated_rData_values_12_11 <= operands_translated_payload_values_12_11;
      operands_translated_rData_values_12_12 <= operands_translated_payload_values_12_12;
      operands_translated_rData_values_12_13 <= operands_translated_payload_values_12_13;
      operands_translated_rData_values_12_14 <= operands_translated_payload_values_12_14;
      operands_translated_rData_values_12_15 <= operands_translated_payload_values_12_15;
      operands_translated_rData_values_13_0 <= operands_translated_payload_values_13_0;
      operands_translated_rData_values_13_1 <= operands_translated_payload_values_13_1;
      operands_translated_rData_values_13_2 <= operands_translated_payload_values_13_2;
      operands_translated_rData_values_13_3 <= operands_translated_payload_values_13_3;
      operands_translated_rData_values_13_4 <= operands_translated_payload_values_13_4;
      operands_translated_rData_values_13_5 <= operands_translated_payload_values_13_5;
      operands_translated_rData_values_13_6 <= operands_translated_payload_values_13_6;
      operands_translated_rData_values_13_7 <= operands_translated_payload_values_13_7;
      operands_translated_rData_values_13_8 <= operands_translated_payload_values_13_8;
      operands_translated_rData_values_13_9 <= operands_translated_payload_values_13_9;
      operands_translated_rData_values_13_10 <= operands_translated_payload_values_13_10;
      operands_translated_rData_values_13_11 <= operands_translated_payload_values_13_11;
      operands_translated_rData_values_13_12 <= operands_translated_payload_values_13_12;
      operands_translated_rData_values_13_13 <= operands_translated_payload_values_13_13;
      operands_translated_rData_values_13_14 <= operands_translated_payload_values_13_14;
      operands_translated_rData_values_13_15 <= operands_translated_payload_values_13_15;
      operands_translated_rData_values_14_0 <= operands_translated_payload_values_14_0;
      operands_translated_rData_values_14_1 <= operands_translated_payload_values_14_1;
      operands_translated_rData_values_14_2 <= operands_translated_payload_values_14_2;
      operands_translated_rData_values_14_3 <= operands_translated_payload_values_14_3;
      operands_translated_rData_values_14_4 <= operands_translated_payload_values_14_4;
      operands_translated_rData_values_14_5 <= operands_translated_payload_values_14_5;
      operands_translated_rData_values_14_6 <= operands_translated_payload_values_14_6;
      operands_translated_rData_values_14_7 <= operands_translated_payload_values_14_7;
      operands_translated_rData_values_14_8 <= operands_translated_payload_values_14_8;
      operands_translated_rData_values_14_9 <= operands_translated_payload_values_14_9;
      operands_translated_rData_values_14_10 <= operands_translated_payload_values_14_10;
      operands_translated_rData_values_14_11 <= operands_translated_payload_values_14_11;
      operands_translated_rData_values_14_12 <= operands_translated_payload_values_14_12;
      operands_translated_rData_values_14_13 <= operands_translated_payload_values_14_13;
      operands_translated_rData_values_14_14 <= operands_translated_payload_values_14_14;
      operands_translated_rData_values_14_15 <= operands_translated_payload_values_14_15;
      operands_translated_rData_values_15_0 <= operands_translated_payload_values_15_0;
      operands_translated_rData_values_15_1 <= operands_translated_payload_values_15_1;
      operands_translated_rData_values_15_2 <= operands_translated_payload_values_15_2;
      operands_translated_rData_values_15_3 <= operands_translated_payload_values_15_3;
      operands_translated_rData_values_15_4 <= operands_translated_payload_values_15_4;
      operands_translated_rData_values_15_5 <= operands_translated_payload_values_15_5;
      operands_translated_rData_values_15_6 <= operands_translated_payload_values_15_6;
      operands_translated_rData_values_15_7 <= operands_translated_payload_values_15_7;
      operands_translated_rData_values_15_8 <= operands_translated_payload_values_15_8;
      operands_translated_rData_values_15_9 <= operands_translated_payload_values_15_9;
      operands_translated_rData_values_15_10 <= operands_translated_payload_values_15_10;
      operands_translated_rData_values_15_11 <= operands_translated_payload_values_15_11;
      operands_translated_rData_values_15_12 <= operands_translated_payload_values_15_12;
      operands_translated_rData_values_15_13 <= operands_translated_payload_values_15_13;
      operands_translated_rData_values_15_14 <= operands_translated_payload_values_15_14;
      operands_translated_rData_values_15_15 <= operands_translated_payload_values_15_15;
    end
    if(products_translated_ready) begin
      products_translated_rData_tag_pixel <= products_translated_payload_tag_pixel;
      products_translated_rData_tag_localPixel <= products_translated_payload_tag_localPixel;
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
      products_translated_rData_values_4_0 <= products_translated_payload_values_4_0;
      products_translated_rData_values_4_1 <= products_translated_payload_values_4_1;
      products_translated_rData_values_4_2 <= products_translated_payload_values_4_2;
      products_translated_rData_values_4_3 <= products_translated_payload_values_4_3;
      products_translated_rData_values_4_4 <= products_translated_payload_values_4_4;
      products_translated_rData_values_4_5 <= products_translated_payload_values_4_5;
      products_translated_rData_values_4_6 <= products_translated_payload_values_4_6;
      products_translated_rData_values_4_7 <= products_translated_payload_values_4_7;
      products_translated_rData_values_5_0 <= products_translated_payload_values_5_0;
      products_translated_rData_values_5_1 <= products_translated_payload_values_5_1;
      products_translated_rData_values_5_2 <= products_translated_payload_values_5_2;
      products_translated_rData_values_5_3 <= products_translated_payload_values_5_3;
      products_translated_rData_values_5_4 <= products_translated_payload_values_5_4;
      products_translated_rData_values_5_5 <= products_translated_payload_values_5_5;
      products_translated_rData_values_5_6 <= products_translated_payload_values_5_6;
      products_translated_rData_values_5_7 <= products_translated_payload_values_5_7;
      products_translated_rData_values_6_0 <= products_translated_payload_values_6_0;
      products_translated_rData_values_6_1 <= products_translated_payload_values_6_1;
      products_translated_rData_values_6_2 <= products_translated_payload_values_6_2;
      products_translated_rData_values_6_3 <= products_translated_payload_values_6_3;
      products_translated_rData_values_6_4 <= products_translated_payload_values_6_4;
      products_translated_rData_values_6_5 <= products_translated_payload_values_6_5;
      products_translated_rData_values_6_6 <= products_translated_payload_values_6_6;
      products_translated_rData_values_6_7 <= products_translated_payload_values_6_7;
      products_translated_rData_values_7_0 <= products_translated_payload_values_7_0;
      products_translated_rData_values_7_1 <= products_translated_payload_values_7_1;
      products_translated_rData_values_7_2 <= products_translated_payload_values_7_2;
      products_translated_rData_values_7_3 <= products_translated_payload_values_7_3;
      products_translated_rData_values_7_4 <= products_translated_payload_values_7_4;
      products_translated_rData_values_7_5 <= products_translated_payload_values_7_5;
      products_translated_rData_values_7_6 <= products_translated_payload_values_7_6;
      products_translated_rData_values_7_7 <= products_translated_payload_values_7_7;
      products_translated_rData_values_8_0 <= products_translated_payload_values_8_0;
      products_translated_rData_values_8_1 <= products_translated_payload_values_8_1;
      products_translated_rData_values_8_2 <= products_translated_payload_values_8_2;
      products_translated_rData_values_8_3 <= products_translated_payload_values_8_3;
      products_translated_rData_values_8_4 <= products_translated_payload_values_8_4;
      products_translated_rData_values_8_5 <= products_translated_payload_values_8_5;
      products_translated_rData_values_8_6 <= products_translated_payload_values_8_6;
      products_translated_rData_values_8_7 <= products_translated_payload_values_8_7;
      products_translated_rData_values_9_0 <= products_translated_payload_values_9_0;
      products_translated_rData_values_9_1 <= products_translated_payload_values_9_1;
      products_translated_rData_values_9_2 <= products_translated_payload_values_9_2;
      products_translated_rData_values_9_3 <= products_translated_payload_values_9_3;
      products_translated_rData_values_9_4 <= products_translated_payload_values_9_4;
      products_translated_rData_values_9_5 <= products_translated_payload_values_9_5;
      products_translated_rData_values_9_6 <= products_translated_payload_values_9_6;
      products_translated_rData_values_9_7 <= products_translated_payload_values_9_7;
      products_translated_rData_values_10_0 <= products_translated_payload_values_10_0;
      products_translated_rData_values_10_1 <= products_translated_payload_values_10_1;
      products_translated_rData_values_10_2 <= products_translated_payload_values_10_2;
      products_translated_rData_values_10_3 <= products_translated_payload_values_10_3;
      products_translated_rData_values_10_4 <= products_translated_payload_values_10_4;
      products_translated_rData_values_10_5 <= products_translated_payload_values_10_5;
      products_translated_rData_values_10_6 <= products_translated_payload_values_10_6;
      products_translated_rData_values_10_7 <= products_translated_payload_values_10_7;
      products_translated_rData_values_11_0 <= products_translated_payload_values_11_0;
      products_translated_rData_values_11_1 <= products_translated_payload_values_11_1;
      products_translated_rData_values_11_2 <= products_translated_payload_values_11_2;
      products_translated_rData_values_11_3 <= products_translated_payload_values_11_3;
      products_translated_rData_values_11_4 <= products_translated_payload_values_11_4;
      products_translated_rData_values_11_5 <= products_translated_payload_values_11_5;
      products_translated_rData_values_11_6 <= products_translated_payload_values_11_6;
      products_translated_rData_values_11_7 <= products_translated_payload_values_11_7;
      products_translated_rData_values_12_0 <= products_translated_payload_values_12_0;
      products_translated_rData_values_12_1 <= products_translated_payload_values_12_1;
      products_translated_rData_values_12_2 <= products_translated_payload_values_12_2;
      products_translated_rData_values_12_3 <= products_translated_payload_values_12_3;
      products_translated_rData_values_12_4 <= products_translated_payload_values_12_4;
      products_translated_rData_values_12_5 <= products_translated_payload_values_12_5;
      products_translated_rData_values_12_6 <= products_translated_payload_values_12_6;
      products_translated_rData_values_12_7 <= products_translated_payload_values_12_7;
      products_translated_rData_values_13_0 <= products_translated_payload_values_13_0;
      products_translated_rData_values_13_1 <= products_translated_payload_values_13_1;
      products_translated_rData_values_13_2 <= products_translated_payload_values_13_2;
      products_translated_rData_values_13_3 <= products_translated_payload_values_13_3;
      products_translated_rData_values_13_4 <= products_translated_payload_values_13_4;
      products_translated_rData_values_13_5 <= products_translated_payload_values_13_5;
      products_translated_rData_values_13_6 <= products_translated_payload_values_13_6;
      products_translated_rData_values_13_7 <= products_translated_payload_values_13_7;
      products_translated_rData_values_14_0 <= products_translated_payload_values_14_0;
      products_translated_rData_values_14_1 <= products_translated_payload_values_14_1;
      products_translated_rData_values_14_2 <= products_translated_payload_values_14_2;
      products_translated_rData_values_14_3 <= products_translated_payload_values_14_3;
      products_translated_rData_values_14_4 <= products_translated_payload_values_14_4;
      products_translated_rData_values_14_5 <= products_translated_payload_values_14_5;
      products_translated_rData_values_14_6 <= products_translated_payload_values_14_6;
      products_translated_rData_values_14_7 <= products_translated_payload_values_14_7;
      products_translated_rData_values_15_0 <= products_translated_payload_values_15_0;
      products_translated_rData_values_15_1 <= products_translated_payload_values_15_1;
      products_translated_rData_values_15_2 <= products_translated_payload_values_15_2;
      products_translated_rData_values_15_3 <= products_translated_payload_values_15_3;
      products_translated_rData_values_15_4 <= products_translated_payload_values_15_4;
      products_translated_rData_values_15_5 <= products_translated_payload_values_15_5;
      products_translated_rData_values_15_6 <= products_translated_payload_values_15_6;
      products_translated_rData_values_15_7 <= products_translated_payload_values_15_7;
    end
    if(reduce8_translated_ready) begin
      reduce8_translated_rData_tag_pixel <= reduce8_translated_payload_tag_pixel;
      reduce8_translated_rData_tag_localPixel <= reduce8_translated_payload_tag_localPixel;
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
      reduce8_translated_rData_values_4_0 <= reduce8_translated_payload_values_4_0;
      reduce8_translated_rData_values_4_1 <= reduce8_translated_payload_values_4_1;
      reduce8_translated_rData_values_4_2 <= reduce8_translated_payload_values_4_2;
      reduce8_translated_rData_values_4_3 <= reduce8_translated_payload_values_4_3;
      reduce8_translated_rData_values_5_0 <= reduce8_translated_payload_values_5_0;
      reduce8_translated_rData_values_5_1 <= reduce8_translated_payload_values_5_1;
      reduce8_translated_rData_values_5_2 <= reduce8_translated_payload_values_5_2;
      reduce8_translated_rData_values_5_3 <= reduce8_translated_payload_values_5_3;
      reduce8_translated_rData_values_6_0 <= reduce8_translated_payload_values_6_0;
      reduce8_translated_rData_values_6_1 <= reduce8_translated_payload_values_6_1;
      reduce8_translated_rData_values_6_2 <= reduce8_translated_payload_values_6_2;
      reduce8_translated_rData_values_6_3 <= reduce8_translated_payload_values_6_3;
      reduce8_translated_rData_values_7_0 <= reduce8_translated_payload_values_7_0;
      reduce8_translated_rData_values_7_1 <= reduce8_translated_payload_values_7_1;
      reduce8_translated_rData_values_7_2 <= reduce8_translated_payload_values_7_2;
      reduce8_translated_rData_values_7_3 <= reduce8_translated_payload_values_7_3;
      reduce8_translated_rData_values_8_0 <= reduce8_translated_payload_values_8_0;
      reduce8_translated_rData_values_8_1 <= reduce8_translated_payload_values_8_1;
      reduce8_translated_rData_values_8_2 <= reduce8_translated_payload_values_8_2;
      reduce8_translated_rData_values_8_3 <= reduce8_translated_payload_values_8_3;
      reduce8_translated_rData_values_9_0 <= reduce8_translated_payload_values_9_0;
      reduce8_translated_rData_values_9_1 <= reduce8_translated_payload_values_9_1;
      reduce8_translated_rData_values_9_2 <= reduce8_translated_payload_values_9_2;
      reduce8_translated_rData_values_9_3 <= reduce8_translated_payload_values_9_3;
      reduce8_translated_rData_values_10_0 <= reduce8_translated_payload_values_10_0;
      reduce8_translated_rData_values_10_1 <= reduce8_translated_payload_values_10_1;
      reduce8_translated_rData_values_10_2 <= reduce8_translated_payload_values_10_2;
      reduce8_translated_rData_values_10_3 <= reduce8_translated_payload_values_10_3;
      reduce8_translated_rData_values_11_0 <= reduce8_translated_payload_values_11_0;
      reduce8_translated_rData_values_11_1 <= reduce8_translated_payload_values_11_1;
      reduce8_translated_rData_values_11_2 <= reduce8_translated_payload_values_11_2;
      reduce8_translated_rData_values_11_3 <= reduce8_translated_payload_values_11_3;
      reduce8_translated_rData_values_12_0 <= reduce8_translated_payload_values_12_0;
      reduce8_translated_rData_values_12_1 <= reduce8_translated_payload_values_12_1;
      reduce8_translated_rData_values_12_2 <= reduce8_translated_payload_values_12_2;
      reduce8_translated_rData_values_12_3 <= reduce8_translated_payload_values_12_3;
      reduce8_translated_rData_values_13_0 <= reduce8_translated_payload_values_13_0;
      reduce8_translated_rData_values_13_1 <= reduce8_translated_payload_values_13_1;
      reduce8_translated_rData_values_13_2 <= reduce8_translated_payload_values_13_2;
      reduce8_translated_rData_values_13_3 <= reduce8_translated_payload_values_13_3;
      reduce8_translated_rData_values_14_0 <= reduce8_translated_payload_values_14_0;
      reduce8_translated_rData_values_14_1 <= reduce8_translated_payload_values_14_1;
      reduce8_translated_rData_values_14_2 <= reduce8_translated_payload_values_14_2;
      reduce8_translated_rData_values_14_3 <= reduce8_translated_payload_values_14_3;
      reduce8_translated_rData_values_15_0 <= reduce8_translated_payload_values_15_0;
      reduce8_translated_rData_values_15_1 <= reduce8_translated_payload_values_15_1;
      reduce8_translated_rData_values_15_2 <= reduce8_translated_payload_values_15_2;
      reduce8_translated_rData_values_15_3 <= reduce8_translated_payload_values_15_3;
    end
    if(reduce4_translated_ready) begin
      reduce4_translated_rData_tag_pixel <= reduce4_translated_payload_tag_pixel;
      reduce4_translated_rData_tag_localPixel <= reduce4_translated_payload_tag_localPixel;
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
      reduce4_translated_rData_values_4_0 <= reduce4_translated_payload_values_4_0;
      reduce4_translated_rData_values_4_1 <= reduce4_translated_payload_values_4_1;
      reduce4_translated_rData_values_5_0 <= reduce4_translated_payload_values_5_0;
      reduce4_translated_rData_values_5_1 <= reduce4_translated_payload_values_5_1;
      reduce4_translated_rData_values_6_0 <= reduce4_translated_payload_values_6_0;
      reduce4_translated_rData_values_6_1 <= reduce4_translated_payload_values_6_1;
      reduce4_translated_rData_values_7_0 <= reduce4_translated_payload_values_7_0;
      reduce4_translated_rData_values_7_1 <= reduce4_translated_payload_values_7_1;
      reduce4_translated_rData_values_8_0 <= reduce4_translated_payload_values_8_0;
      reduce4_translated_rData_values_8_1 <= reduce4_translated_payload_values_8_1;
      reduce4_translated_rData_values_9_0 <= reduce4_translated_payload_values_9_0;
      reduce4_translated_rData_values_9_1 <= reduce4_translated_payload_values_9_1;
      reduce4_translated_rData_values_10_0 <= reduce4_translated_payload_values_10_0;
      reduce4_translated_rData_values_10_1 <= reduce4_translated_payload_values_10_1;
      reduce4_translated_rData_values_11_0 <= reduce4_translated_payload_values_11_0;
      reduce4_translated_rData_values_11_1 <= reduce4_translated_payload_values_11_1;
      reduce4_translated_rData_values_12_0 <= reduce4_translated_payload_values_12_0;
      reduce4_translated_rData_values_12_1 <= reduce4_translated_payload_values_12_1;
      reduce4_translated_rData_values_13_0 <= reduce4_translated_payload_values_13_0;
      reduce4_translated_rData_values_13_1 <= reduce4_translated_payload_values_13_1;
      reduce4_translated_rData_values_14_0 <= reduce4_translated_payload_values_14_0;
      reduce4_translated_rData_values_14_1 <= reduce4_translated_payload_values_14_1;
      reduce4_translated_rData_values_15_0 <= reduce4_translated_payload_values_15_0;
      reduce4_translated_rData_values_15_1 <= reduce4_translated_payload_values_15_1;
    end
    if(reduce2_translated_ready) begin
      reduce2_translated_rData_tag_pixel <= reduce2_translated_payload_tag_pixel;
      reduce2_translated_rData_tag_localPixel <= reduce2_translated_payload_tag_localPixel;
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
      reduce2_translated_rData_values_4_0 <= reduce2_translated_payload_values_4_0;
      reduce2_translated_rData_values_5_0 <= reduce2_translated_payload_values_5_0;
      reduce2_translated_rData_values_6_0 <= reduce2_translated_payload_values_6_0;
      reduce2_translated_rData_values_7_0 <= reduce2_translated_payload_values_7_0;
      reduce2_translated_rData_values_8_0 <= reduce2_translated_payload_values_8_0;
      reduce2_translated_rData_values_9_0 <= reduce2_translated_payload_values_9_0;
      reduce2_translated_rData_values_10_0 <= reduce2_translated_payload_values_10_0;
      reduce2_translated_rData_values_11_0 <= reduce2_translated_payload_values_11_0;
      reduce2_translated_rData_values_12_0 <= reduce2_translated_payload_values_12_0;
      reduce2_translated_rData_values_13_0 <= reduce2_translated_payload_values_13_0;
      reduce2_translated_rData_values_14_0 <= reduce2_translated_payload_values_14_0;
      reduce2_translated_rData_values_15_0 <= reduce2_translated_payload_values_15_0;
    end
    if(dot_fire) begin
      if(_zz_3[0]) begin
        acc_r_0_0 <= _zz_acc_r_0_0_1;
      end
      if(_zz_3[1]) begin
        acc_r_0_1 <= _zz_acc_r_0_0_1;
      end
      if(_zz_3[2]) begin
        acc_r_0_2 <= _zz_acc_r_0_0_1;
      end
      if(_zz_3[3]) begin
        acc_r_0_3 <= _zz_acc_r_0_0_1;
      end
      if(_zz_3[4]) begin
        acc_r_0_4 <= _zz_acc_r_0_0_1;
      end
      if(_zz_3[5]) begin
        acc_r_0_5 <= _zz_acc_r_0_0_1;
      end
      if(_zz_3[6]) begin
        acc_r_0_6 <= _zz_acc_r_0_0_1;
      end
      if(_zz_3[7]) begin
        acc_r_0_7 <= _zz_acc_r_0_0_1;
      end
      if(_zz_3[8]) begin
        acc_r_0_8 <= _zz_acc_r_0_0_1;
      end
      if(_zz_3[9]) begin
        acc_r_0_9 <= _zz_acc_r_0_0_1;
      end
      if(_zz_3[10]) begin
        acc_r_0_10 <= _zz_acc_r_0_0_1;
      end
      if(_zz_3[11]) begin
        acc_r_0_11 <= _zz_acc_r_0_0_1;
      end
      if(_zz_3[12]) begin
        acc_r_0_12 <= _zz_acc_r_0_0_1;
      end
      if(_zz_3[13]) begin
        acc_r_0_13 <= _zz_acc_r_0_0_1;
      end
      if(_zz_3[14]) begin
        acc_r_0_14 <= _zz_acc_r_0_0_1;
      end
      if(_zz_3[15]) begin
        acc_r_0_15 <= _zz_acc_r_0_0_1;
      end
      if(dot_payload_tag_finalInput) begin
        if(_zz_4[0]) begin
          tileMac_r_0_0 <= _zz_tileMac_r_0_0;
        end
        if(_zz_4[1]) begin
          tileMac_r_0_1 <= _zz_tileMac_r_0_0;
        end
        if(_zz_4[2]) begin
          tileMac_r_0_2 <= _zz_tileMac_r_0_0;
        end
        if(_zz_4[3]) begin
          tileMac_r_0_3 <= _zz_tileMac_r_0_0;
        end
        if(_zz_4[4]) begin
          tileMac_r_0_4 <= _zz_tileMac_r_0_0;
        end
        if(_zz_4[5]) begin
          tileMac_r_0_5 <= _zz_tileMac_r_0_0;
        end
        if(_zz_4[6]) begin
          tileMac_r_0_6 <= _zz_tileMac_r_0_0;
        end
        if(_zz_4[7]) begin
          tileMac_r_0_7 <= _zz_tileMac_r_0_0;
        end
        if(_zz_4[8]) begin
          tileMac_r_0_8 <= _zz_tileMac_r_0_0;
        end
        if(_zz_4[9]) begin
          tileMac_r_0_9 <= _zz_tileMac_r_0_0;
        end
        if(_zz_4[10]) begin
          tileMac_r_0_10 <= _zz_tileMac_r_0_0;
        end
        if(_zz_4[11]) begin
          tileMac_r_0_11 <= _zz_tileMac_r_0_0;
        end
        if(_zz_4[12]) begin
          tileMac_r_0_12 <= _zz_tileMac_r_0_0;
        end
        if(_zz_4[13]) begin
          tileMac_r_0_13 <= _zz_tileMac_r_0_0;
        end
        if(_zz_4[14]) begin
          tileMac_r_0_14 <= _zz_tileMac_r_0_0;
        end
        if(_zz_4[15]) begin
          tileMac_r_0_15 <= _zz_tileMac_r_0_0;
        end
      end
    end
    if(dot_fire) begin
      if(_zz_5[0]) begin
        acc_r_1_0 <= _zz_acc_r_1_0_1;
      end
      if(_zz_5[1]) begin
        acc_r_1_1 <= _zz_acc_r_1_0_1;
      end
      if(_zz_5[2]) begin
        acc_r_1_2 <= _zz_acc_r_1_0_1;
      end
      if(_zz_5[3]) begin
        acc_r_1_3 <= _zz_acc_r_1_0_1;
      end
      if(_zz_5[4]) begin
        acc_r_1_4 <= _zz_acc_r_1_0_1;
      end
      if(_zz_5[5]) begin
        acc_r_1_5 <= _zz_acc_r_1_0_1;
      end
      if(_zz_5[6]) begin
        acc_r_1_6 <= _zz_acc_r_1_0_1;
      end
      if(_zz_5[7]) begin
        acc_r_1_7 <= _zz_acc_r_1_0_1;
      end
      if(_zz_5[8]) begin
        acc_r_1_8 <= _zz_acc_r_1_0_1;
      end
      if(_zz_5[9]) begin
        acc_r_1_9 <= _zz_acc_r_1_0_1;
      end
      if(_zz_5[10]) begin
        acc_r_1_10 <= _zz_acc_r_1_0_1;
      end
      if(_zz_5[11]) begin
        acc_r_1_11 <= _zz_acc_r_1_0_1;
      end
      if(_zz_5[12]) begin
        acc_r_1_12 <= _zz_acc_r_1_0_1;
      end
      if(_zz_5[13]) begin
        acc_r_1_13 <= _zz_acc_r_1_0_1;
      end
      if(_zz_5[14]) begin
        acc_r_1_14 <= _zz_acc_r_1_0_1;
      end
      if(_zz_5[15]) begin
        acc_r_1_15 <= _zz_acc_r_1_0_1;
      end
      if(dot_payload_tag_finalInput) begin
        if(_zz_6[0]) begin
          tileMac_r_1_0 <= _zz_tileMac_r_1_0;
        end
        if(_zz_6[1]) begin
          tileMac_r_1_1 <= _zz_tileMac_r_1_0;
        end
        if(_zz_6[2]) begin
          tileMac_r_1_2 <= _zz_tileMac_r_1_0;
        end
        if(_zz_6[3]) begin
          tileMac_r_1_3 <= _zz_tileMac_r_1_0;
        end
        if(_zz_6[4]) begin
          tileMac_r_1_4 <= _zz_tileMac_r_1_0;
        end
        if(_zz_6[5]) begin
          tileMac_r_1_5 <= _zz_tileMac_r_1_0;
        end
        if(_zz_6[6]) begin
          tileMac_r_1_6 <= _zz_tileMac_r_1_0;
        end
        if(_zz_6[7]) begin
          tileMac_r_1_7 <= _zz_tileMac_r_1_0;
        end
        if(_zz_6[8]) begin
          tileMac_r_1_8 <= _zz_tileMac_r_1_0;
        end
        if(_zz_6[9]) begin
          tileMac_r_1_9 <= _zz_tileMac_r_1_0;
        end
        if(_zz_6[10]) begin
          tileMac_r_1_10 <= _zz_tileMac_r_1_0;
        end
        if(_zz_6[11]) begin
          tileMac_r_1_11 <= _zz_tileMac_r_1_0;
        end
        if(_zz_6[12]) begin
          tileMac_r_1_12 <= _zz_tileMac_r_1_0;
        end
        if(_zz_6[13]) begin
          tileMac_r_1_13 <= _zz_tileMac_r_1_0;
        end
        if(_zz_6[14]) begin
          tileMac_r_1_14 <= _zz_tileMac_r_1_0;
        end
        if(_zz_6[15]) begin
          tileMac_r_1_15 <= _zz_tileMac_r_1_0;
        end
      end
    end
    if(dot_fire) begin
      if(_zz_7[0]) begin
        acc_r_2_0 <= _zz_acc_r_2_0_1;
      end
      if(_zz_7[1]) begin
        acc_r_2_1 <= _zz_acc_r_2_0_1;
      end
      if(_zz_7[2]) begin
        acc_r_2_2 <= _zz_acc_r_2_0_1;
      end
      if(_zz_7[3]) begin
        acc_r_2_3 <= _zz_acc_r_2_0_1;
      end
      if(_zz_7[4]) begin
        acc_r_2_4 <= _zz_acc_r_2_0_1;
      end
      if(_zz_7[5]) begin
        acc_r_2_5 <= _zz_acc_r_2_0_1;
      end
      if(_zz_7[6]) begin
        acc_r_2_6 <= _zz_acc_r_2_0_1;
      end
      if(_zz_7[7]) begin
        acc_r_2_7 <= _zz_acc_r_2_0_1;
      end
      if(_zz_7[8]) begin
        acc_r_2_8 <= _zz_acc_r_2_0_1;
      end
      if(_zz_7[9]) begin
        acc_r_2_9 <= _zz_acc_r_2_0_1;
      end
      if(_zz_7[10]) begin
        acc_r_2_10 <= _zz_acc_r_2_0_1;
      end
      if(_zz_7[11]) begin
        acc_r_2_11 <= _zz_acc_r_2_0_1;
      end
      if(_zz_7[12]) begin
        acc_r_2_12 <= _zz_acc_r_2_0_1;
      end
      if(_zz_7[13]) begin
        acc_r_2_13 <= _zz_acc_r_2_0_1;
      end
      if(_zz_7[14]) begin
        acc_r_2_14 <= _zz_acc_r_2_0_1;
      end
      if(_zz_7[15]) begin
        acc_r_2_15 <= _zz_acc_r_2_0_1;
      end
      if(dot_payload_tag_finalInput) begin
        if(_zz_8[0]) begin
          tileMac_r_2_0 <= _zz_tileMac_r_2_0;
        end
        if(_zz_8[1]) begin
          tileMac_r_2_1 <= _zz_tileMac_r_2_0;
        end
        if(_zz_8[2]) begin
          tileMac_r_2_2 <= _zz_tileMac_r_2_0;
        end
        if(_zz_8[3]) begin
          tileMac_r_2_3 <= _zz_tileMac_r_2_0;
        end
        if(_zz_8[4]) begin
          tileMac_r_2_4 <= _zz_tileMac_r_2_0;
        end
        if(_zz_8[5]) begin
          tileMac_r_2_5 <= _zz_tileMac_r_2_0;
        end
        if(_zz_8[6]) begin
          tileMac_r_2_6 <= _zz_tileMac_r_2_0;
        end
        if(_zz_8[7]) begin
          tileMac_r_2_7 <= _zz_tileMac_r_2_0;
        end
        if(_zz_8[8]) begin
          tileMac_r_2_8 <= _zz_tileMac_r_2_0;
        end
        if(_zz_8[9]) begin
          tileMac_r_2_9 <= _zz_tileMac_r_2_0;
        end
        if(_zz_8[10]) begin
          tileMac_r_2_10 <= _zz_tileMac_r_2_0;
        end
        if(_zz_8[11]) begin
          tileMac_r_2_11 <= _zz_tileMac_r_2_0;
        end
        if(_zz_8[12]) begin
          tileMac_r_2_12 <= _zz_tileMac_r_2_0;
        end
        if(_zz_8[13]) begin
          tileMac_r_2_13 <= _zz_tileMac_r_2_0;
        end
        if(_zz_8[14]) begin
          tileMac_r_2_14 <= _zz_tileMac_r_2_0;
        end
        if(_zz_8[15]) begin
          tileMac_r_2_15 <= _zz_tileMac_r_2_0;
        end
      end
    end
    if(dot_fire) begin
      if(_zz_9[0]) begin
        acc_r_3_0 <= _zz_acc_r_3_0_1;
      end
      if(_zz_9[1]) begin
        acc_r_3_1 <= _zz_acc_r_3_0_1;
      end
      if(_zz_9[2]) begin
        acc_r_3_2 <= _zz_acc_r_3_0_1;
      end
      if(_zz_9[3]) begin
        acc_r_3_3 <= _zz_acc_r_3_0_1;
      end
      if(_zz_9[4]) begin
        acc_r_3_4 <= _zz_acc_r_3_0_1;
      end
      if(_zz_9[5]) begin
        acc_r_3_5 <= _zz_acc_r_3_0_1;
      end
      if(_zz_9[6]) begin
        acc_r_3_6 <= _zz_acc_r_3_0_1;
      end
      if(_zz_9[7]) begin
        acc_r_3_7 <= _zz_acc_r_3_0_1;
      end
      if(_zz_9[8]) begin
        acc_r_3_8 <= _zz_acc_r_3_0_1;
      end
      if(_zz_9[9]) begin
        acc_r_3_9 <= _zz_acc_r_3_0_1;
      end
      if(_zz_9[10]) begin
        acc_r_3_10 <= _zz_acc_r_3_0_1;
      end
      if(_zz_9[11]) begin
        acc_r_3_11 <= _zz_acc_r_3_0_1;
      end
      if(_zz_9[12]) begin
        acc_r_3_12 <= _zz_acc_r_3_0_1;
      end
      if(_zz_9[13]) begin
        acc_r_3_13 <= _zz_acc_r_3_0_1;
      end
      if(_zz_9[14]) begin
        acc_r_3_14 <= _zz_acc_r_3_0_1;
      end
      if(_zz_9[15]) begin
        acc_r_3_15 <= _zz_acc_r_3_0_1;
      end
      if(dot_payload_tag_finalInput) begin
        if(_zz_10[0]) begin
          tileMac_r_3_0 <= _zz_tileMac_r_3_0;
        end
        if(_zz_10[1]) begin
          tileMac_r_3_1 <= _zz_tileMac_r_3_0;
        end
        if(_zz_10[2]) begin
          tileMac_r_3_2 <= _zz_tileMac_r_3_0;
        end
        if(_zz_10[3]) begin
          tileMac_r_3_3 <= _zz_tileMac_r_3_0;
        end
        if(_zz_10[4]) begin
          tileMac_r_3_4 <= _zz_tileMac_r_3_0;
        end
        if(_zz_10[5]) begin
          tileMac_r_3_5 <= _zz_tileMac_r_3_0;
        end
        if(_zz_10[6]) begin
          tileMac_r_3_6 <= _zz_tileMac_r_3_0;
        end
        if(_zz_10[7]) begin
          tileMac_r_3_7 <= _zz_tileMac_r_3_0;
        end
        if(_zz_10[8]) begin
          tileMac_r_3_8 <= _zz_tileMac_r_3_0;
        end
        if(_zz_10[9]) begin
          tileMac_r_3_9 <= _zz_tileMac_r_3_0;
        end
        if(_zz_10[10]) begin
          tileMac_r_3_10 <= _zz_tileMac_r_3_0;
        end
        if(_zz_10[11]) begin
          tileMac_r_3_11 <= _zz_tileMac_r_3_0;
        end
        if(_zz_10[12]) begin
          tileMac_r_3_12 <= _zz_tileMac_r_3_0;
        end
        if(_zz_10[13]) begin
          tileMac_r_3_13 <= _zz_tileMac_r_3_0;
        end
        if(_zz_10[14]) begin
          tileMac_r_3_14 <= _zz_tileMac_r_3_0;
        end
        if(_zz_10[15]) begin
          tileMac_r_3_15 <= _zz_tileMac_r_3_0;
        end
      end
    end
    if(dot_fire) begin
      if(_zz_11[0]) begin
        acc_r_4_0 <= _zz_acc_r_4_0_1;
      end
      if(_zz_11[1]) begin
        acc_r_4_1 <= _zz_acc_r_4_0_1;
      end
      if(_zz_11[2]) begin
        acc_r_4_2 <= _zz_acc_r_4_0_1;
      end
      if(_zz_11[3]) begin
        acc_r_4_3 <= _zz_acc_r_4_0_1;
      end
      if(_zz_11[4]) begin
        acc_r_4_4 <= _zz_acc_r_4_0_1;
      end
      if(_zz_11[5]) begin
        acc_r_4_5 <= _zz_acc_r_4_0_1;
      end
      if(_zz_11[6]) begin
        acc_r_4_6 <= _zz_acc_r_4_0_1;
      end
      if(_zz_11[7]) begin
        acc_r_4_7 <= _zz_acc_r_4_0_1;
      end
      if(_zz_11[8]) begin
        acc_r_4_8 <= _zz_acc_r_4_0_1;
      end
      if(_zz_11[9]) begin
        acc_r_4_9 <= _zz_acc_r_4_0_1;
      end
      if(_zz_11[10]) begin
        acc_r_4_10 <= _zz_acc_r_4_0_1;
      end
      if(_zz_11[11]) begin
        acc_r_4_11 <= _zz_acc_r_4_0_1;
      end
      if(_zz_11[12]) begin
        acc_r_4_12 <= _zz_acc_r_4_0_1;
      end
      if(_zz_11[13]) begin
        acc_r_4_13 <= _zz_acc_r_4_0_1;
      end
      if(_zz_11[14]) begin
        acc_r_4_14 <= _zz_acc_r_4_0_1;
      end
      if(_zz_11[15]) begin
        acc_r_4_15 <= _zz_acc_r_4_0_1;
      end
      if(dot_payload_tag_finalInput) begin
        if(_zz_12[0]) begin
          tileMac_r_4_0 <= _zz_tileMac_r_4_0;
        end
        if(_zz_12[1]) begin
          tileMac_r_4_1 <= _zz_tileMac_r_4_0;
        end
        if(_zz_12[2]) begin
          tileMac_r_4_2 <= _zz_tileMac_r_4_0;
        end
        if(_zz_12[3]) begin
          tileMac_r_4_3 <= _zz_tileMac_r_4_0;
        end
        if(_zz_12[4]) begin
          tileMac_r_4_4 <= _zz_tileMac_r_4_0;
        end
        if(_zz_12[5]) begin
          tileMac_r_4_5 <= _zz_tileMac_r_4_0;
        end
        if(_zz_12[6]) begin
          tileMac_r_4_6 <= _zz_tileMac_r_4_0;
        end
        if(_zz_12[7]) begin
          tileMac_r_4_7 <= _zz_tileMac_r_4_0;
        end
        if(_zz_12[8]) begin
          tileMac_r_4_8 <= _zz_tileMac_r_4_0;
        end
        if(_zz_12[9]) begin
          tileMac_r_4_9 <= _zz_tileMac_r_4_0;
        end
        if(_zz_12[10]) begin
          tileMac_r_4_10 <= _zz_tileMac_r_4_0;
        end
        if(_zz_12[11]) begin
          tileMac_r_4_11 <= _zz_tileMac_r_4_0;
        end
        if(_zz_12[12]) begin
          tileMac_r_4_12 <= _zz_tileMac_r_4_0;
        end
        if(_zz_12[13]) begin
          tileMac_r_4_13 <= _zz_tileMac_r_4_0;
        end
        if(_zz_12[14]) begin
          tileMac_r_4_14 <= _zz_tileMac_r_4_0;
        end
        if(_zz_12[15]) begin
          tileMac_r_4_15 <= _zz_tileMac_r_4_0;
        end
      end
    end
    if(dot_fire) begin
      if(_zz_13[0]) begin
        acc_r_5_0 <= _zz_acc_r_5_0_1;
      end
      if(_zz_13[1]) begin
        acc_r_5_1 <= _zz_acc_r_5_0_1;
      end
      if(_zz_13[2]) begin
        acc_r_5_2 <= _zz_acc_r_5_0_1;
      end
      if(_zz_13[3]) begin
        acc_r_5_3 <= _zz_acc_r_5_0_1;
      end
      if(_zz_13[4]) begin
        acc_r_5_4 <= _zz_acc_r_5_0_1;
      end
      if(_zz_13[5]) begin
        acc_r_5_5 <= _zz_acc_r_5_0_1;
      end
      if(_zz_13[6]) begin
        acc_r_5_6 <= _zz_acc_r_5_0_1;
      end
      if(_zz_13[7]) begin
        acc_r_5_7 <= _zz_acc_r_5_0_1;
      end
      if(_zz_13[8]) begin
        acc_r_5_8 <= _zz_acc_r_5_0_1;
      end
      if(_zz_13[9]) begin
        acc_r_5_9 <= _zz_acc_r_5_0_1;
      end
      if(_zz_13[10]) begin
        acc_r_5_10 <= _zz_acc_r_5_0_1;
      end
      if(_zz_13[11]) begin
        acc_r_5_11 <= _zz_acc_r_5_0_1;
      end
      if(_zz_13[12]) begin
        acc_r_5_12 <= _zz_acc_r_5_0_1;
      end
      if(_zz_13[13]) begin
        acc_r_5_13 <= _zz_acc_r_5_0_1;
      end
      if(_zz_13[14]) begin
        acc_r_5_14 <= _zz_acc_r_5_0_1;
      end
      if(_zz_13[15]) begin
        acc_r_5_15 <= _zz_acc_r_5_0_1;
      end
      if(dot_payload_tag_finalInput) begin
        if(_zz_14[0]) begin
          tileMac_r_5_0 <= _zz_tileMac_r_5_0;
        end
        if(_zz_14[1]) begin
          tileMac_r_5_1 <= _zz_tileMac_r_5_0;
        end
        if(_zz_14[2]) begin
          tileMac_r_5_2 <= _zz_tileMac_r_5_0;
        end
        if(_zz_14[3]) begin
          tileMac_r_5_3 <= _zz_tileMac_r_5_0;
        end
        if(_zz_14[4]) begin
          tileMac_r_5_4 <= _zz_tileMac_r_5_0;
        end
        if(_zz_14[5]) begin
          tileMac_r_5_5 <= _zz_tileMac_r_5_0;
        end
        if(_zz_14[6]) begin
          tileMac_r_5_6 <= _zz_tileMac_r_5_0;
        end
        if(_zz_14[7]) begin
          tileMac_r_5_7 <= _zz_tileMac_r_5_0;
        end
        if(_zz_14[8]) begin
          tileMac_r_5_8 <= _zz_tileMac_r_5_0;
        end
        if(_zz_14[9]) begin
          tileMac_r_5_9 <= _zz_tileMac_r_5_0;
        end
        if(_zz_14[10]) begin
          tileMac_r_5_10 <= _zz_tileMac_r_5_0;
        end
        if(_zz_14[11]) begin
          tileMac_r_5_11 <= _zz_tileMac_r_5_0;
        end
        if(_zz_14[12]) begin
          tileMac_r_5_12 <= _zz_tileMac_r_5_0;
        end
        if(_zz_14[13]) begin
          tileMac_r_5_13 <= _zz_tileMac_r_5_0;
        end
        if(_zz_14[14]) begin
          tileMac_r_5_14 <= _zz_tileMac_r_5_0;
        end
        if(_zz_14[15]) begin
          tileMac_r_5_15 <= _zz_tileMac_r_5_0;
        end
      end
    end
    if(dot_fire) begin
      if(_zz_15[0]) begin
        acc_r_6_0 <= _zz_acc_r_6_0_1;
      end
      if(_zz_15[1]) begin
        acc_r_6_1 <= _zz_acc_r_6_0_1;
      end
      if(_zz_15[2]) begin
        acc_r_6_2 <= _zz_acc_r_6_0_1;
      end
      if(_zz_15[3]) begin
        acc_r_6_3 <= _zz_acc_r_6_0_1;
      end
      if(_zz_15[4]) begin
        acc_r_6_4 <= _zz_acc_r_6_0_1;
      end
      if(_zz_15[5]) begin
        acc_r_6_5 <= _zz_acc_r_6_0_1;
      end
      if(_zz_15[6]) begin
        acc_r_6_6 <= _zz_acc_r_6_0_1;
      end
      if(_zz_15[7]) begin
        acc_r_6_7 <= _zz_acc_r_6_0_1;
      end
      if(_zz_15[8]) begin
        acc_r_6_8 <= _zz_acc_r_6_0_1;
      end
      if(_zz_15[9]) begin
        acc_r_6_9 <= _zz_acc_r_6_0_1;
      end
      if(_zz_15[10]) begin
        acc_r_6_10 <= _zz_acc_r_6_0_1;
      end
      if(_zz_15[11]) begin
        acc_r_6_11 <= _zz_acc_r_6_0_1;
      end
      if(_zz_15[12]) begin
        acc_r_6_12 <= _zz_acc_r_6_0_1;
      end
      if(_zz_15[13]) begin
        acc_r_6_13 <= _zz_acc_r_6_0_1;
      end
      if(_zz_15[14]) begin
        acc_r_6_14 <= _zz_acc_r_6_0_1;
      end
      if(_zz_15[15]) begin
        acc_r_6_15 <= _zz_acc_r_6_0_1;
      end
      if(dot_payload_tag_finalInput) begin
        if(_zz_16[0]) begin
          tileMac_r_6_0 <= _zz_tileMac_r_6_0;
        end
        if(_zz_16[1]) begin
          tileMac_r_6_1 <= _zz_tileMac_r_6_0;
        end
        if(_zz_16[2]) begin
          tileMac_r_6_2 <= _zz_tileMac_r_6_0;
        end
        if(_zz_16[3]) begin
          tileMac_r_6_3 <= _zz_tileMac_r_6_0;
        end
        if(_zz_16[4]) begin
          tileMac_r_6_4 <= _zz_tileMac_r_6_0;
        end
        if(_zz_16[5]) begin
          tileMac_r_6_5 <= _zz_tileMac_r_6_0;
        end
        if(_zz_16[6]) begin
          tileMac_r_6_6 <= _zz_tileMac_r_6_0;
        end
        if(_zz_16[7]) begin
          tileMac_r_6_7 <= _zz_tileMac_r_6_0;
        end
        if(_zz_16[8]) begin
          tileMac_r_6_8 <= _zz_tileMac_r_6_0;
        end
        if(_zz_16[9]) begin
          tileMac_r_6_9 <= _zz_tileMac_r_6_0;
        end
        if(_zz_16[10]) begin
          tileMac_r_6_10 <= _zz_tileMac_r_6_0;
        end
        if(_zz_16[11]) begin
          tileMac_r_6_11 <= _zz_tileMac_r_6_0;
        end
        if(_zz_16[12]) begin
          tileMac_r_6_12 <= _zz_tileMac_r_6_0;
        end
        if(_zz_16[13]) begin
          tileMac_r_6_13 <= _zz_tileMac_r_6_0;
        end
        if(_zz_16[14]) begin
          tileMac_r_6_14 <= _zz_tileMac_r_6_0;
        end
        if(_zz_16[15]) begin
          tileMac_r_6_15 <= _zz_tileMac_r_6_0;
        end
      end
    end
    if(dot_fire) begin
      if(_zz_17[0]) begin
        acc_r_7_0 <= _zz_acc_r_7_0_1;
      end
      if(_zz_17[1]) begin
        acc_r_7_1 <= _zz_acc_r_7_0_1;
      end
      if(_zz_17[2]) begin
        acc_r_7_2 <= _zz_acc_r_7_0_1;
      end
      if(_zz_17[3]) begin
        acc_r_7_3 <= _zz_acc_r_7_0_1;
      end
      if(_zz_17[4]) begin
        acc_r_7_4 <= _zz_acc_r_7_0_1;
      end
      if(_zz_17[5]) begin
        acc_r_7_5 <= _zz_acc_r_7_0_1;
      end
      if(_zz_17[6]) begin
        acc_r_7_6 <= _zz_acc_r_7_0_1;
      end
      if(_zz_17[7]) begin
        acc_r_7_7 <= _zz_acc_r_7_0_1;
      end
      if(_zz_17[8]) begin
        acc_r_7_8 <= _zz_acc_r_7_0_1;
      end
      if(_zz_17[9]) begin
        acc_r_7_9 <= _zz_acc_r_7_0_1;
      end
      if(_zz_17[10]) begin
        acc_r_7_10 <= _zz_acc_r_7_0_1;
      end
      if(_zz_17[11]) begin
        acc_r_7_11 <= _zz_acc_r_7_0_1;
      end
      if(_zz_17[12]) begin
        acc_r_7_12 <= _zz_acc_r_7_0_1;
      end
      if(_zz_17[13]) begin
        acc_r_7_13 <= _zz_acc_r_7_0_1;
      end
      if(_zz_17[14]) begin
        acc_r_7_14 <= _zz_acc_r_7_0_1;
      end
      if(_zz_17[15]) begin
        acc_r_7_15 <= _zz_acc_r_7_0_1;
      end
      if(dot_payload_tag_finalInput) begin
        if(_zz_18[0]) begin
          tileMac_r_7_0 <= _zz_tileMac_r_7_0;
        end
        if(_zz_18[1]) begin
          tileMac_r_7_1 <= _zz_tileMac_r_7_0;
        end
        if(_zz_18[2]) begin
          tileMac_r_7_2 <= _zz_tileMac_r_7_0;
        end
        if(_zz_18[3]) begin
          tileMac_r_7_3 <= _zz_tileMac_r_7_0;
        end
        if(_zz_18[4]) begin
          tileMac_r_7_4 <= _zz_tileMac_r_7_0;
        end
        if(_zz_18[5]) begin
          tileMac_r_7_5 <= _zz_tileMac_r_7_0;
        end
        if(_zz_18[6]) begin
          tileMac_r_7_6 <= _zz_tileMac_r_7_0;
        end
        if(_zz_18[7]) begin
          tileMac_r_7_7 <= _zz_tileMac_r_7_0;
        end
        if(_zz_18[8]) begin
          tileMac_r_7_8 <= _zz_tileMac_r_7_0;
        end
        if(_zz_18[9]) begin
          tileMac_r_7_9 <= _zz_tileMac_r_7_0;
        end
        if(_zz_18[10]) begin
          tileMac_r_7_10 <= _zz_tileMac_r_7_0;
        end
        if(_zz_18[11]) begin
          tileMac_r_7_11 <= _zz_tileMac_r_7_0;
        end
        if(_zz_18[12]) begin
          tileMac_r_7_12 <= _zz_tileMac_r_7_0;
        end
        if(_zz_18[13]) begin
          tileMac_r_7_13 <= _zz_tileMac_r_7_0;
        end
        if(_zz_18[14]) begin
          tileMac_r_7_14 <= _zz_tileMac_r_7_0;
        end
        if(_zz_18[15]) begin
          tileMac_r_7_15 <= _zz_tileMac_r_7_0;
        end
      end
    end
    if(dot_fire) begin
      if(_zz_19[0]) begin
        acc_r_8_0 <= _zz_acc_r_8_0_1;
      end
      if(_zz_19[1]) begin
        acc_r_8_1 <= _zz_acc_r_8_0_1;
      end
      if(_zz_19[2]) begin
        acc_r_8_2 <= _zz_acc_r_8_0_1;
      end
      if(_zz_19[3]) begin
        acc_r_8_3 <= _zz_acc_r_8_0_1;
      end
      if(_zz_19[4]) begin
        acc_r_8_4 <= _zz_acc_r_8_0_1;
      end
      if(_zz_19[5]) begin
        acc_r_8_5 <= _zz_acc_r_8_0_1;
      end
      if(_zz_19[6]) begin
        acc_r_8_6 <= _zz_acc_r_8_0_1;
      end
      if(_zz_19[7]) begin
        acc_r_8_7 <= _zz_acc_r_8_0_1;
      end
      if(_zz_19[8]) begin
        acc_r_8_8 <= _zz_acc_r_8_0_1;
      end
      if(_zz_19[9]) begin
        acc_r_8_9 <= _zz_acc_r_8_0_1;
      end
      if(_zz_19[10]) begin
        acc_r_8_10 <= _zz_acc_r_8_0_1;
      end
      if(_zz_19[11]) begin
        acc_r_8_11 <= _zz_acc_r_8_0_1;
      end
      if(_zz_19[12]) begin
        acc_r_8_12 <= _zz_acc_r_8_0_1;
      end
      if(_zz_19[13]) begin
        acc_r_8_13 <= _zz_acc_r_8_0_1;
      end
      if(_zz_19[14]) begin
        acc_r_8_14 <= _zz_acc_r_8_0_1;
      end
      if(_zz_19[15]) begin
        acc_r_8_15 <= _zz_acc_r_8_0_1;
      end
      if(dot_payload_tag_finalInput) begin
        if(_zz_20[0]) begin
          tileMac_r_8_0 <= _zz_tileMac_r_8_0;
        end
        if(_zz_20[1]) begin
          tileMac_r_8_1 <= _zz_tileMac_r_8_0;
        end
        if(_zz_20[2]) begin
          tileMac_r_8_2 <= _zz_tileMac_r_8_0;
        end
        if(_zz_20[3]) begin
          tileMac_r_8_3 <= _zz_tileMac_r_8_0;
        end
        if(_zz_20[4]) begin
          tileMac_r_8_4 <= _zz_tileMac_r_8_0;
        end
        if(_zz_20[5]) begin
          tileMac_r_8_5 <= _zz_tileMac_r_8_0;
        end
        if(_zz_20[6]) begin
          tileMac_r_8_6 <= _zz_tileMac_r_8_0;
        end
        if(_zz_20[7]) begin
          tileMac_r_8_7 <= _zz_tileMac_r_8_0;
        end
        if(_zz_20[8]) begin
          tileMac_r_8_8 <= _zz_tileMac_r_8_0;
        end
        if(_zz_20[9]) begin
          tileMac_r_8_9 <= _zz_tileMac_r_8_0;
        end
        if(_zz_20[10]) begin
          tileMac_r_8_10 <= _zz_tileMac_r_8_0;
        end
        if(_zz_20[11]) begin
          tileMac_r_8_11 <= _zz_tileMac_r_8_0;
        end
        if(_zz_20[12]) begin
          tileMac_r_8_12 <= _zz_tileMac_r_8_0;
        end
        if(_zz_20[13]) begin
          tileMac_r_8_13 <= _zz_tileMac_r_8_0;
        end
        if(_zz_20[14]) begin
          tileMac_r_8_14 <= _zz_tileMac_r_8_0;
        end
        if(_zz_20[15]) begin
          tileMac_r_8_15 <= _zz_tileMac_r_8_0;
        end
      end
    end
    if(dot_fire) begin
      if(_zz_21[0]) begin
        acc_r_9_0 <= _zz_acc_r_9_0_1;
      end
      if(_zz_21[1]) begin
        acc_r_9_1 <= _zz_acc_r_9_0_1;
      end
      if(_zz_21[2]) begin
        acc_r_9_2 <= _zz_acc_r_9_0_1;
      end
      if(_zz_21[3]) begin
        acc_r_9_3 <= _zz_acc_r_9_0_1;
      end
      if(_zz_21[4]) begin
        acc_r_9_4 <= _zz_acc_r_9_0_1;
      end
      if(_zz_21[5]) begin
        acc_r_9_5 <= _zz_acc_r_9_0_1;
      end
      if(_zz_21[6]) begin
        acc_r_9_6 <= _zz_acc_r_9_0_1;
      end
      if(_zz_21[7]) begin
        acc_r_9_7 <= _zz_acc_r_9_0_1;
      end
      if(_zz_21[8]) begin
        acc_r_9_8 <= _zz_acc_r_9_0_1;
      end
      if(_zz_21[9]) begin
        acc_r_9_9 <= _zz_acc_r_9_0_1;
      end
      if(_zz_21[10]) begin
        acc_r_9_10 <= _zz_acc_r_9_0_1;
      end
      if(_zz_21[11]) begin
        acc_r_9_11 <= _zz_acc_r_9_0_1;
      end
      if(_zz_21[12]) begin
        acc_r_9_12 <= _zz_acc_r_9_0_1;
      end
      if(_zz_21[13]) begin
        acc_r_9_13 <= _zz_acc_r_9_0_1;
      end
      if(_zz_21[14]) begin
        acc_r_9_14 <= _zz_acc_r_9_0_1;
      end
      if(_zz_21[15]) begin
        acc_r_9_15 <= _zz_acc_r_9_0_1;
      end
      if(dot_payload_tag_finalInput) begin
        if(_zz_22[0]) begin
          tileMac_r_9_0 <= _zz_tileMac_r_9_0;
        end
        if(_zz_22[1]) begin
          tileMac_r_9_1 <= _zz_tileMac_r_9_0;
        end
        if(_zz_22[2]) begin
          tileMac_r_9_2 <= _zz_tileMac_r_9_0;
        end
        if(_zz_22[3]) begin
          tileMac_r_9_3 <= _zz_tileMac_r_9_0;
        end
        if(_zz_22[4]) begin
          tileMac_r_9_4 <= _zz_tileMac_r_9_0;
        end
        if(_zz_22[5]) begin
          tileMac_r_9_5 <= _zz_tileMac_r_9_0;
        end
        if(_zz_22[6]) begin
          tileMac_r_9_6 <= _zz_tileMac_r_9_0;
        end
        if(_zz_22[7]) begin
          tileMac_r_9_7 <= _zz_tileMac_r_9_0;
        end
        if(_zz_22[8]) begin
          tileMac_r_9_8 <= _zz_tileMac_r_9_0;
        end
        if(_zz_22[9]) begin
          tileMac_r_9_9 <= _zz_tileMac_r_9_0;
        end
        if(_zz_22[10]) begin
          tileMac_r_9_10 <= _zz_tileMac_r_9_0;
        end
        if(_zz_22[11]) begin
          tileMac_r_9_11 <= _zz_tileMac_r_9_0;
        end
        if(_zz_22[12]) begin
          tileMac_r_9_12 <= _zz_tileMac_r_9_0;
        end
        if(_zz_22[13]) begin
          tileMac_r_9_13 <= _zz_tileMac_r_9_0;
        end
        if(_zz_22[14]) begin
          tileMac_r_9_14 <= _zz_tileMac_r_9_0;
        end
        if(_zz_22[15]) begin
          tileMac_r_9_15 <= _zz_tileMac_r_9_0;
        end
      end
    end
    if(dot_fire) begin
      if(_zz_23[0]) begin
        acc_r_10_0 <= _zz_acc_r_10_0_1;
      end
      if(_zz_23[1]) begin
        acc_r_10_1 <= _zz_acc_r_10_0_1;
      end
      if(_zz_23[2]) begin
        acc_r_10_2 <= _zz_acc_r_10_0_1;
      end
      if(_zz_23[3]) begin
        acc_r_10_3 <= _zz_acc_r_10_0_1;
      end
      if(_zz_23[4]) begin
        acc_r_10_4 <= _zz_acc_r_10_0_1;
      end
      if(_zz_23[5]) begin
        acc_r_10_5 <= _zz_acc_r_10_0_1;
      end
      if(_zz_23[6]) begin
        acc_r_10_6 <= _zz_acc_r_10_0_1;
      end
      if(_zz_23[7]) begin
        acc_r_10_7 <= _zz_acc_r_10_0_1;
      end
      if(_zz_23[8]) begin
        acc_r_10_8 <= _zz_acc_r_10_0_1;
      end
      if(_zz_23[9]) begin
        acc_r_10_9 <= _zz_acc_r_10_0_1;
      end
      if(_zz_23[10]) begin
        acc_r_10_10 <= _zz_acc_r_10_0_1;
      end
      if(_zz_23[11]) begin
        acc_r_10_11 <= _zz_acc_r_10_0_1;
      end
      if(_zz_23[12]) begin
        acc_r_10_12 <= _zz_acc_r_10_0_1;
      end
      if(_zz_23[13]) begin
        acc_r_10_13 <= _zz_acc_r_10_0_1;
      end
      if(_zz_23[14]) begin
        acc_r_10_14 <= _zz_acc_r_10_0_1;
      end
      if(_zz_23[15]) begin
        acc_r_10_15 <= _zz_acc_r_10_0_1;
      end
      if(dot_payload_tag_finalInput) begin
        if(_zz_24[0]) begin
          tileMac_r_10_0 <= _zz_tileMac_r_10_0;
        end
        if(_zz_24[1]) begin
          tileMac_r_10_1 <= _zz_tileMac_r_10_0;
        end
        if(_zz_24[2]) begin
          tileMac_r_10_2 <= _zz_tileMac_r_10_0;
        end
        if(_zz_24[3]) begin
          tileMac_r_10_3 <= _zz_tileMac_r_10_0;
        end
        if(_zz_24[4]) begin
          tileMac_r_10_4 <= _zz_tileMac_r_10_0;
        end
        if(_zz_24[5]) begin
          tileMac_r_10_5 <= _zz_tileMac_r_10_0;
        end
        if(_zz_24[6]) begin
          tileMac_r_10_6 <= _zz_tileMac_r_10_0;
        end
        if(_zz_24[7]) begin
          tileMac_r_10_7 <= _zz_tileMac_r_10_0;
        end
        if(_zz_24[8]) begin
          tileMac_r_10_8 <= _zz_tileMac_r_10_0;
        end
        if(_zz_24[9]) begin
          tileMac_r_10_9 <= _zz_tileMac_r_10_0;
        end
        if(_zz_24[10]) begin
          tileMac_r_10_10 <= _zz_tileMac_r_10_0;
        end
        if(_zz_24[11]) begin
          tileMac_r_10_11 <= _zz_tileMac_r_10_0;
        end
        if(_zz_24[12]) begin
          tileMac_r_10_12 <= _zz_tileMac_r_10_0;
        end
        if(_zz_24[13]) begin
          tileMac_r_10_13 <= _zz_tileMac_r_10_0;
        end
        if(_zz_24[14]) begin
          tileMac_r_10_14 <= _zz_tileMac_r_10_0;
        end
        if(_zz_24[15]) begin
          tileMac_r_10_15 <= _zz_tileMac_r_10_0;
        end
      end
    end
    if(dot_fire) begin
      if(_zz_25[0]) begin
        acc_r_11_0 <= _zz_acc_r_11_0_1;
      end
      if(_zz_25[1]) begin
        acc_r_11_1 <= _zz_acc_r_11_0_1;
      end
      if(_zz_25[2]) begin
        acc_r_11_2 <= _zz_acc_r_11_0_1;
      end
      if(_zz_25[3]) begin
        acc_r_11_3 <= _zz_acc_r_11_0_1;
      end
      if(_zz_25[4]) begin
        acc_r_11_4 <= _zz_acc_r_11_0_1;
      end
      if(_zz_25[5]) begin
        acc_r_11_5 <= _zz_acc_r_11_0_1;
      end
      if(_zz_25[6]) begin
        acc_r_11_6 <= _zz_acc_r_11_0_1;
      end
      if(_zz_25[7]) begin
        acc_r_11_7 <= _zz_acc_r_11_0_1;
      end
      if(_zz_25[8]) begin
        acc_r_11_8 <= _zz_acc_r_11_0_1;
      end
      if(_zz_25[9]) begin
        acc_r_11_9 <= _zz_acc_r_11_0_1;
      end
      if(_zz_25[10]) begin
        acc_r_11_10 <= _zz_acc_r_11_0_1;
      end
      if(_zz_25[11]) begin
        acc_r_11_11 <= _zz_acc_r_11_0_1;
      end
      if(_zz_25[12]) begin
        acc_r_11_12 <= _zz_acc_r_11_0_1;
      end
      if(_zz_25[13]) begin
        acc_r_11_13 <= _zz_acc_r_11_0_1;
      end
      if(_zz_25[14]) begin
        acc_r_11_14 <= _zz_acc_r_11_0_1;
      end
      if(_zz_25[15]) begin
        acc_r_11_15 <= _zz_acc_r_11_0_1;
      end
      if(dot_payload_tag_finalInput) begin
        if(_zz_26[0]) begin
          tileMac_r_11_0 <= _zz_tileMac_r_11_0;
        end
        if(_zz_26[1]) begin
          tileMac_r_11_1 <= _zz_tileMac_r_11_0;
        end
        if(_zz_26[2]) begin
          tileMac_r_11_2 <= _zz_tileMac_r_11_0;
        end
        if(_zz_26[3]) begin
          tileMac_r_11_3 <= _zz_tileMac_r_11_0;
        end
        if(_zz_26[4]) begin
          tileMac_r_11_4 <= _zz_tileMac_r_11_0;
        end
        if(_zz_26[5]) begin
          tileMac_r_11_5 <= _zz_tileMac_r_11_0;
        end
        if(_zz_26[6]) begin
          tileMac_r_11_6 <= _zz_tileMac_r_11_0;
        end
        if(_zz_26[7]) begin
          tileMac_r_11_7 <= _zz_tileMac_r_11_0;
        end
        if(_zz_26[8]) begin
          tileMac_r_11_8 <= _zz_tileMac_r_11_0;
        end
        if(_zz_26[9]) begin
          tileMac_r_11_9 <= _zz_tileMac_r_11_0;
        end
        if(_zz_26[10]) begin
          tileMac_r_11_10 <= _zz_tileMac_r_11_0;
        end
        if(_zz_26[11]) begin
          tileMac_r_11_11 <= _zz_tileMac_r_11_0;
        end
        if(_zz_26[12]) begin
          tileMac_r_11_12 <= _zz_tileMac_r_11_0;
        end
        if(_zz_26[13]) begin
          tileMac_r_11_13 <= _zz_tileMac_r_11_0;
        end
        if(_zz_26[14]) begin
          tileMac_r_11_14 <= _zz_tileMac_r_11_0;
        end
        if(_zz_26[15]) begin
          tileMac_r_11_15 <= _zz_tileMac_r_11_0;
        end
      end
    end
    if(dot_fire) begin
      if(_zz_27[0]) begin
        acc_r_12_0 <= _zz_acc_r_12_0_1;
      end
      if(_zz_27[1]) begin
        acc_r_12_1 <= _zz_acc_r_12_0_1;
      end
      if(_zz_27[2]) begin
        acc_r_12_2 <= _zz_acc_r_12_0_1;
      end
      if(_zz_27[3]) begin
        acc_r_12_3 <= _zz_acc_r_12_0_1;
      end
      if(_zz_27[4]) begin
        acc_r_12_4 <= _zz_acc_r_12_0_1;
      end
      if(_zz_27[5]) begin
        acc_r_12_5 <= _zz_acc_r_12_0_1;
      end
      if(_zz_27[6]) begin
        acc_r_12_6 <= _zz_acc_r_12_0_1;
      end
      if(_zz_27[7]) begin
        acc_r_12_7 <= _zz_acc_r_12_0_1;
      end
      if(_zz_27[8]) begin
        acc_r_12_8 <= _zz_acc_r_12_0_1;
      end
      if(_zz_27[9]) begin
        acc_r_12_9 <= _zz_acc_r_12_0_1;
      end
      if(_zz_27[10]) begin
        acc_r_12_10 <= _zz_acc_r_12_0_1;
      end
      if(_zz_27[11]) begin
        acc_r_12_11 <= _zz_acc_r_12_0_1;
      end
      if(_zz_27[12]) begin
        acc_r_12_12 <= _zz_acc_r_12_0_1;
      end
      if(_zz_27[13]) begin
        acc_r_12_13 <= _zz_acc_r_12_0_1;
      end
      if(_zz_27[14]) begin
        acc_r_12_14 <= _zz_acc_r_12_0_1;
      end
      if(_zz_27[15]) begin
        acc_r_12_15 <= _zz_acc_r_12_0_1;
      end
      if(dot_payload_tag_finalInput) begin
        if(_zz_28[0]) begin
          tileMac_r_12_0 <= _zz_tileMac_r_12_0;
        end
        if(_zz_28[1]) begin
          tileMac_r_12_1 <= _zz_tileMac_r_12_0;
        end
        if(_zz_28[2]) begin
          tileMac_r_12_2 <= _zz_tileMac_r_12_0;
        end
        if(_zz_28[3]) begin
          tileMac_r_12_3 <= _zz_tileMac_r_12_0;
        end
        if(_zz_28[4]) begin
          tileMac_r_12_4 <= _zz_tileMac_r_12_0;
        end
        if(_zz_28[5]) begin
          tileMac_r_12_5 <= _zz_tileMac_r_12_0;
        end
        if(_zz_28[6]) begin
          tileMac_r_12_6 <= _zz_tileMac_r_12_0;
        end
        if(_zz_28[7]) begin
          tileMac_r_12_7 <= _zz_tileMac_r_12_0;
        end
        if(_zz_28[8]) begin
          tileMac_r_12_8 <= _zz_tileMac_r_12_0;
        end
        if(_zz_28[9]) begin
          tileMac_r_12_9 <= _zz_tileMac_r_12_0;
        end
        if(_zz_28[10]) begin
          tileMac_r_12_10 <= _zz_tileMac_r_12_0;
        end
        if(_zz_28[11]) begin
          tileMac_r_12_11 <= _zz_tileMac_r_12_0;
        end
        if(_zz_28[12]) begin
          tileMac_r_12_12 <= _zz_tileMac_r_12_0;
        end
        if(_zz_28[13]) begin
          tileMac_r_12_13 <= _zz_tileMac_r_12_0;
        end
        if(_zz_28[14]) begin
          tileMac_r_12_14 <= _zz_tileMac_r_12_0;
        end
        if(_zz_28[15]) begin
          tileMac_r_12_15 <= _zz_tileMac_r_12_0;
        end
      end
    end
    if(dot_fire) begin
      if(_zz_29[0]) begin
        acc_r_13_0 <= _zz_acc_r_13_0_1;
      end
      if(_zz_29[1]) begin
        acc_r_13_1 <= _zz_acc_r_13_0_1;
      end
      if(_zz_29[2]) begin
        acc_r_13_2 <= _zz_acc_r_13_0_1;
      end
      if(_zz_29[3]) begin
        acc_r_13_3 <= _zz_acc_r_13_0_1;
      end
      if(_zz_29[4]) begin
        acc_r_13_4 <= _zz_acc_r_13_0_1;
      end
      if(_zz_29[5]) begin
        acc_r_13_5 <= _zz_acc_r_13_0_1;
      end
      if(_zz_29[6]) begin
        acc_r_13_6 <= _zz_acc_r_13_0_1;
      end
      if(_zz_29[7]) begin
        acc_r_13_7 <= _zz_acc_r_13_0_1;
      end
      if(_zz_29[8]) begin
        acc_r_13_8 <= _zz_acc_r_13_0_1;
      end
      if(_zz_29[9]) begin
        acc_r_13_9 <= _zz_acc_r_13_0_1;
      end
      if(_zz_29[10]) begin
        acc_r_13_10 <= _zz_acc_r_13_0_1;
      end
      if(_zz_29[11]) begin
        acc_r_13_11 <= _zz_acc_r_13_0_1;
      end
      if(_zz_29[12]) begin
        acc_r_13_12 <= _zz_acc_r_13_0_1;
      end
      if(_zz_29[13]) begin
        acc_r_13_13 <= _zz_acc_r_13_0_1;
      end
      if(_zz_29[14]) begin
        acc_r_13_14 <= _zz_acc_r_13_0_1;
      end
      if(_zz_29[15]) begin
        acc_r_13_15 <= _zz_acc_r_13_0_1;
      end
      if(dot_payload_tag_finalInput) begin
        if(_zz_30[0]) begin
          tileMac_r_13_0 <= _zz_tileMac_r_13_0;
        end
        if(_zz_30[1]) begin
          tileMac_r_13_1 <= _zz_tileMac_r_13_0;
        end
        if(_zz_30[2]) begin
          tileMac_r_13_2 <= _zz_tileMac_r_13_0;
        end
        if(_zz_30[3]) begin
          tileMac_r_13_3 <= _zz_tileMac_r_13_0;
        end
        if(_zz_30[4]) begin
          tileMac_r_13_4 <= _zz_tileMac_r_13_0;
        end
        if(_zz_30[5]) begin
          tileMac_r_13_5 <= _zz_tileMac_r_13_0;
        end
        if(_zz_30[6]) begin
          tileMac_r_13_6 <= _zz_tileMac_r_13_0;
        end
        if(_zz_30[7]) begin
          tileMac_r_13_7 <= _zz_tileMac_r_13_0;
        end
        if(_zz_30[8]) begin
          tileMac_r_13_8 <= _zz_tileMac_r_13_0;
        end
        if(_zz_30[9]) begin
          tileMac_r_13_9 <= _zz_tileMac_r_13_0;
        end
        if(_zz_30[10]) begin
          tileMac_r_13_10 <= _zz_tileMac_r_13_0;
        end
        if(_zz_30[11]) begin
          tileMac_r_13_11 <= _zz_tileMac_r_13_0;
        end
        if(_zz_30[12]) begin
          tileMac_r_13_12 <= _zz_tileMac_r_13_0;
        end
        if(_zz_30[13]) begin
          tileMac_r_13_13 <= _zz_tileMac_r_13_0;
        end
        if(_zz_30[14]) begin
          tileMac_r_13_14 <= _zz_tileMac_r_13_0;
        end
        if(_zz_30[15]) begin
          tileMac_r_13_15 <= _zz_tileMac_r_13_0;
        end
      end
    end
    if(dot_fire) begin
      if(_zz_31[0]) begin
        acc_r_14_0 <= _zz_acc_r_14_0_1;
      end
      if(_zz_31[1]) begin
        acc_r_14_1 <= _zz_acc_r_14_0_1;
      end
      if(_zz_31[2]) begin
        acc_r_14_2 <= _zz_acc_r_14_0_1;
      end
      if(_zz_31[3]) begin
        acc_r_14_3 <= _zz_acc_r_14_0_1;
      end
      if(_zz_31[4]) begin
        acc_r_14_4 <= _zz_acc_r_14_0_1;
      end
      if(_zz_31[5]) begin
        acc_r_14_5 <= _zz_acc_r_14_0_1;
      end
      if(_zz_31[6]) begin
        acc_r_14_6 <= _zz_acc_r_14_0_1;
      end
      if(_zz_31[7]) begin
        acc_r_14_7 <= _zz_acc_r_14_0_1;
      end
      if(_zz_31[8]) begin
        acc_r_14_8 <= _zz_acc_r_14_0_1;
      end
      if(_zz_31[9]) begin
        acc_r_14_9 <= _zz_acc_r_14_0_1;
      end
      if(_zz_31[10]) begin
        acc_r_14_10 <= _zz_acc_r_14_0_1;
      end
      if(_zz_31[11]) begin
        acc_r_14_11 <= _zz_acc_r_14_0_1;
      end
      if(_zz_31[12]) begin
        acc_r_14_12 <= _zz_acc_r_14_0_1;
      end
      if(_zz_31[13]) begin
        acc_r_14_13 <= _zz_acc_r_14_0_1;
      end
      if(_zz_31[14]) begin
        acc_r_14_14 <= _zz_acc_r_14_0_1;
      end
      if(_zz_31[15]) begin
        acc_r_14_15 <= _zz_acc_r_14_0_1;
      end
      if(dot_payload_tag_finalInput) begin
        if(_zz_32[0]) begin
          tileMac_r_14_0 <= _zz_tileMac_r_14_0;
        end
        if(_zz_32[1]) begin
          tileMac_r_14_1 <= _zz_tileMac_r_14_0;
        end
        if(_zz_32[2]) begin
          tileMac_r_14_2 <= _zz_tileMac_r_14_0;
        end
        if(_zz_32[3]) begin
          tileMac_r_14_3 <= _zz_tileMac_r_14_0;
        end
        if(_zz_32[4]) begin
          tileMac_r_14_4 <= _zz_tileMac_r_14_0;
        end
        if(_zz_32[5]) begin
          tileMac_r_14_5 <= _zz_tileMac_r_14_0;
        end
        if(_zz_32[6]) begin
          tileMac_r_14_6 <= _zz_tileMac_r_14_0;
        end
        if(_zz_32[7]) begin
          tileMac_r_14_7 <= _zz_tileMac_r_14_0;
        end
        if(_zz_32[8]) begin
          tileMac_r_14_8 <= _zz_tileMac_r_14_0;
        end
        if(_zz_32[9]) begin
          tileMac_r_14_9 <= _zz_tileMac_r_14_0;
        end
        if(_zz_32[10]) begin
          tileMac_r_14_10 <= _zz_tileMac_r_14_0;
        end
        if(_zz_32[11]) begin
          tileMac_r_14_11 <= _zz_tileMac_r_14_0;
        end
        if(_zz_32[12]) begin
          tileMac_r_14_12 <= _zz_tileMac_r_14_0;
        end
        if(_zz_32[13]) begin
          tileMac_r_14_13 <= _zz_tileMac_r_14_0;
        end
        if(_zz_32[14]) begin
          tileMac_r_14_14 <= _zz_tileMac_r_14_0;
        end
        if(_zz_32[15]) begin
          tileMac_r_14_15 <= _zz_tileMac_r_14_0;
        end
      end
    end
    if(dot_fire) begin
      if(_zz_33[0]) begin
        acc_r_15_0 <= _zz_acc_r_15_0_1;
      end
      if(_zz_33[1]) begin
        acc_r_15_1 <= _zz_acc_r_15_0_1;
      end
      if(_zz_33[2]) begin
        acc_r_15_2 <= _zz_acc_r_15_0_1;
      end
      if(_zz_33[3]) begin
        acc_r_15_3 <= _zz_acc_r_15_0_1;
      end
      if(_zz_33[4]) begin
        acc_r_15_4 <= _zz_acc_r_15_0_1;
      end
      if(_zz_33[5]) begin
        acc_r_15_5 <= _zz_acc_r_15_0_1;
      end
      if(_zz_33[6]) begin
        acc_r_15_6 <= _zz_acc_r_15_0_1;
      end
      if(_zz_33[7]) begin
        acc_r_15_7 <= _zz_acc_r_15_0_1;
      end
      if(_zz_33[8]) begin
        acc_r_15_8 <= _zz_acc_r_15_0_1;
      end
      if(_zz_33[9]) begin
        acc_r_15_9 <= _zz_acc_r_15_0_1;
      end
      if(_zz_33[10]) begin
        acc_r_15_10 <= _zz_acc_r_15_0_1;
      end
      if(_zz_33[11]) begin
        acc_r_15_11 <= _zz_acc_r_15_0_1;
      end
      if(_zz_33[12]) begin
        acc_r_15_12 <= _zz_acc_r_15_0_1;
      end
      if(_zz_33[13]) begin
        acc_r_15_13 <= _zz_acc_r_15_0_1;
      end
      if(_zz_33[14]) begin
        acc_r_15_14 <= _zz_acc_r_15_0_1;
      end
      if(_zz_33[15]) begin
        acc_r_15_15 <= _zz_acc_r_15_0_1;
      end
      if(dot_payload_tag_finalInput) begin
        if(_zz_34[0]) begin
          tileMac_r_15_0 <= _zz_tileMac_r_15_0;
        end
        if(_zz_34[1]) begin
          tileMac_r_15_1 <= _zz_tileMac_r_15_0;
        end
        if(_zz_34[2]) begin
          tileMac_r_15_2 <= _zz_tileMac_r_15_0;
        end
        if(_zz_34[3]) begin
          tileMac_r_15_3 <= _zz_tileMac_r_15_0;
        end
        if(_zz_34[4]) begin
          tileMac_r_15_4 <= _zz_tileMac_r_15_0;
        end
        if(_zz_34[5]) begin
          tileMac_r_15_5 <= _zz_tileMac_r_15_0;
        end
        if(_zz_34[6]) begin
          tileMac_r_15_6 <= _zz_tileMac_r_15_0;
        end
        if(_zz_34[7]) begin
          tileMac_r_15_7 <= _zz_tileMac_r_15_0;
        end
        if(_zz_34[8]) begin
          tileMac_r_15_8 <= _zz_tileMac_r_15_0;
        end
        if(_zz_34[9]) begin
          tileMac_r_15_9 <= _zz_tileMac_r_15_0;
        end
        if(_zz_34[10]) begin
          tileMac_r_15_10 <= _zz_tileMac_r_15_0;
        end
        if(_zz_34[11]) begin
          tileMac_r_15_11 <= _zz_tileMac_r_15_0;
        end
        if(_zz_34[12]) begin
          tileMac_r_15_12 <= _zz_tileMac_r_15_0;
        end
        if(_zz_34[13]) begin
          tileMac_r_15_13 <= _zz_tileMac_r_15_0;
        end
        if(_zz_34[14]) begin
          tileMac_r_15_14 <= _zz_tileMac_r_15_0;
        end
        if(_zz_34[15]) begin
          tileMac_r_15_15 <= _zz_tileMac_r_15_0;
        end
      end
    end
    if(quantRequest_ready) begin
      quantRequest_rData_tag_pixel <= quantRequest_payload_tag_pixel;
      quantRequest_rData_tag_localPixel <= quantRequest_payload_tag_localPixel;
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
    if(when_PwMac_l483) begin
      if(when_PwMac_l484) begin
        remaining_r <= (remaining_r - _zz_remaining_r);
      end
    end
  end


endmodule

module PwRequant_before (
  input  wire          io_input_i_valid,
  output wire          io_input_i_ready,
  input  wire [18:0]   io_input_i_payload_tag_pixel,
  input  wire [3:0]    io_input_i_payload_tag_localPixel,
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
  wire       [5:0]    _zz_divide_w_half;
  wire       [63:0]   _zz_round_w_value_0;
  wire       [63:0]   _zz_round_w_value_0_1;
  wire       [0:0]    _zz_round_w_value_0_2;
  wire       [63:0]   _zz_round_w_value_1;
  wire       [63:0]   _zz_round_w_value_1_1;
  wire       [0:0]    _zz_round_w_value_1_2;
  wire       [63:0]   _zz_round_w_value_2;
  wire       [63:0]   _zz_round_w_value_2_1;
  wire       [0:0]    _zz_round_w_value_2_2;
  wire       [63:0]   _zz_round_w_value_3;
  wire       [63:0]   _zz_round_w_value_3_1;
  wire       [0:0]    _zz_round_w_value_3_2;
  wire       [63:0]   _zz_when_PwMac_l123;
  wire       [63:0]   _zz_when_PwMac_l125;
  wire       [63:0]   _zz_when_PwMac_l123_1;
  wire       [63:0]   _zz_when_PwMac_l125_1;
  wire       [63:0]   _zz_when_PwMac_l123_2;
  wire       [63:0]   _zz_when_PwMac_l125_2;
  wire       [63:0]   _zz_when_PwMac_l123_3;
  wire       [63:0]   _zz_when_PwMac_l125_3;
  wire       [18:0]   product_w_info_tag_pixel;
  wire       [3:0]    product_w_info_tag_localPixel;
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
  wire       [3:0]    io_input_i_translated_payload_info_tag_localPixel;
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
  wire       [3:0]    product_payload_info_tag_localPixel;
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
  reg        [3:0]    io_input_i_translated_rData_info_tag_localPixel;
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
  wire       [3:0]    sum_w_info_tag_localPixel;
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
  wire       [3:0]    product_translated_payload_info_tag_localPixel;
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
  wire       [3:0]    sum_payload_info_tag_localPixel;
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
  reg        [3:0]    product_translated_rData_info_tag_localPixel;
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
  wire       [18:0]   divide_w_info_tag_pixel;
  wire       [3:0]    divide_w_info_tag_localPixel;
  wire       [6:0]    divide_w_info_tag_group;
  wire       [3:0]    divide_w_info_tag_mask;
  wire                divide_w_info_tag_first;
  wire                divide_w_info_tag_finalInput;
  wire                divide_w_info_tag_tileLast;
  wire                divide_w_info_tag_last;
  wire                divide_w_info_raw;
  wire                divide_w_info_int16;
  wire       [5:0]    divide_w_info_shift;
  wire       [31:0]   divide_w_info_mac_0;
  wire       [31:0]   divide_w_info_mac_1;
  wire       [31:0]   divide_w_info_mac_2;
  wire       [31:0]   divide_w_info_mac_3;
  wire       [31:0]   divide_w_info_multiplier_0;
  wire       [31:0]   divide_w_info_multiplier_1;
  wire       [31:0]   divide_w_info_multiplier_2;
  wire       [31:0]   divide_w_info_multiplier_3;
  wire       [63:0]   divide_w_info_bias_0;
  wire       [63:0]   divide_w_info_bias_1;
  wire       [63:0]   divide_w_info_bias_2;
  wire       [63:0]   divide_w_info_bias_3;
  wire       [15:0]   divide_w_info_lower_0;
  wire       [15:0]   divide_w_info_lower_1;
  wire       [15:0]   divide_w_info_lower_2;
  wire       [15:0]   divide_w_info_lower_3;
  wire       [15:0]   divide_w_info_upper_0;
  wire       [15:0]   divide_w_info_upper_1;
  wire       [15:0]   divide_w_info_upper_2;
  wire       [15:0]   divide_w_info_upper_3;
  wire       [63:0]   divide_w_whole_0;
  wire       [63:0]   divide_w_whole_1;
  wire       [63:0]   divide_w_whole_2;
  wire       [63:0]   divide_w_whole_3;
  wire       [63:0]   divide_w_remainder_0;
  wire       [63:0]   divide_w_remainder_1;
  wire       [63:0]   divide_w_remainder_2;
  wire       [63:0]   divide_w_remainder_3;
  wire       [63:0]   divide_w_half;
  wire       [63:0]   remainderMask_w;
  wire                sum_translated_valid;
  reg                 sum_translated_ready;
  wire       [18:0]   sum_translated_payload_info_tag_pixel;
  wire       [3:0]    sum_translated_payload_info_tag_localPixel;
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
  wire       [63:0]   sum_translated_payload_whole_0;
  wire       [63:0]   sum_translated_payload_whole_1;
  wire       [63:0]   sum_translated_payload_whole_2;
  wire       [63:0]   sum_translated_payload_whole_3;
  wire       [63:0]   sum_translated_payload_remainder_0;
  wire       [63:0]   sum_translated_payload_remainder_1;
  wire       [63:0]   sum_translated_payload_remainder_2;
  wire       [63:0]   sum_translated_payload_remainder_3;
  wire       [63:0]   sum_translated_payload_half;
  wire                divide_valid;
  wire                divide_ready;
  wire       [18:0]   divide_payload_info_tag_pixel;
  wire       [3:0]    divide_payload_info_tag_localPixel;
  wire       [6:0]    divide_payload_info_tag_group;
  wire       [3:0]    divide_payload_info_tag_mask;
  wire                divide_payload_info_tag_first;
  wire                divide_payload_info_tag_finalInput;
  wire                divide_payload_info_tag_tileLast;
  wire                divide_payload_info_tag_last;
  wire                divide_payload_info_raw;
  wire                divide_payload_info_int16;
  wire       [5:0]    divide_payload_info_shift;
  wire       [31:0]   divide_payload_info_mac_0;
  wire       [31:0]   divide_payload_info_mac_1;
  wire       [31:0]   divide_payload_info_mac_2;
  wire       [31:0]   divide_payload_info_mac_3;
  wire       [31:0]   divide_payload_info_multiplier_0;
  wire       [31:0]   divide_payload_info_multiplier_1;
  wire       [31:0]   divide_payload_info_multiplier_2;
  wire       [31:0]   divide_payload_info_multiplier_3;
  wire       [63:0]   divide_payload_info_bias_0;
  wire       [63:0]   divide_payload_info_bias_1;
  wire       [63:0]   divide_payload_info_bias_2;
  wire       [63:0]   divide_payload_info_bias_3;
  wire       [15:0]   divide_payload_info_lower_0;
  wire       [15:0]   divide_payload_info_lower_1;
  wire       [15:0]   divide_payload_info_lower_2;
  wire       [15:0]   divide_payload_info_lower_3;
  wire       [15:0]   divide_payload_info_upper_0;
  wire       [15:0]   divide_payload_info_upper_1;
  wire       [15:0]   divide_payload_info_upper_2;
  wire       [15:0]   divide_payload_info_upper_3;
  wire       [63:0]   divide_payload_whole_0;
  wire       [63:0]   divide_payload_whole_1;
  wire       [63:0]   divide_payload_whole_2;
  wire       [63:0]   divide_payload_whole_3;
  wire       [63:0]   divide_payload_remainder_0;
  wire       [63:0]   divide_payload_remainder_1;
  wire       [63:0]   divide_payload_remainder_2;
  wire       [63:0]   divide_payload_remainder_3;
  wire       [63:0]   divide_payload_half;
  reg                 sum_translated_rValid;
  reg        [18:0]   sum_translated_rData_info_tag_pixel;
  reg        [3:0]    sum_translated_rData_info_tag_localPixel;
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
  reg        [63:0]   sum_translated_rData_whole_0;
  reg        [63:0]   sum_translated_rData_whole_1;
  reg        [63:0]   sum_translated_rData_whole_2;
  reg        [63:0]   sum_translated_rData_whole_3;
  reg        [63:0]   sum_translated_rData_remainder_0;
  reg        [63:0]   sum_translated_rData_remainder_1;
  reg        [63:0]   sum_translated_rData_remainder_2;
  reg        [63:0]   sum_translated_rData_remainder_3;
  reg        [63:0]   sum_translated_rData_half;
  wire                when_Stream_l477_2;
  wire       [18:0]   decision_w_info_tag_pixel;
  wire       [3:0]    decision_w_info_tag_localPixel;
  wire       [6:0]    decision_w_info_tag_group;
  wire       [3:0]    decision_w_info_tag_mask;
  wire                decision_w_info_tag_first;
  wire                decision_w_info_tag_finalInput;
  wire                decision_w_info_tag_tileLast;
  wire                decision_w_info_tag_last;
  wire                decision_w_info_raw;
  wire                decision_w_info_int16;
  wire       [5:0]    decision_w_info_shift;
  wire       [31:0]   decision_w_info_mac_0;
  wire       [31:0]   decision_w_info_mac_1;
  wire       [31:0]   decision_w_info_mac_2;
  wire       [31:0]   decision_w_info_mac_3;
  wire       [31:0]   decision_w_info_multiplier_0;
  wire       [31:0]   decision_w_info_multiplier_1;
  wire       [31:0]   decision_w_info_multiplier_2;
  wire       [31:0]   decision_w_info_multiplier_3;
  wire       [63:0]   decision_w_info_bias_0;
  wire       [63:0]   decision_w_info_bias_1;
  wire       [63:0]   decision_w_info_bias_2;
  wire       [63:0]   decision_w_info_bias_3;
  wire       [15:0]   decision_w_info_lower_0;
  wire       [15:0]   decision_w_info_lower_1;
  wire       [15:0]   decision_w_info_lower_2;
  wire       [15:0]   decision_w_info_lower_3;
  wire       [15:0]   decision_w_info_upper_0;
  wire       [15:0]   decision_w_info_upper_1;
  wire       [15:0]   decision_w_info_upper_2;
  wire       [15:0]   decision_w_info_upper_3;
  wire       [63:0]   decision_w_whole_0;
  wire       [63:0]   decision_w_whole_1;
  wire       [63:0]   decision_w_whole_2;
  wire       [63:0]   decision_w_whole_3;
  reg        [3:0]    decision_w_increment;
  wire                divide_translated_valid;
  reg                 divide_translated_ready;
  wire       [18:0]   divide_translated_payload_info_tag_pixel;
  wire       [3:0]    divide_translated_payload_info_tag_localPixel;
  wire       [6:0]    divide_translated_payload_info_tag_group;
  wire       [3:0]    divide_translated_payload_info_tag_mask;
  wire                divide_translated_payload_info_tag_first;
  wire                divide_translated_payload_info_tag_finalInput;
  wire                divide_translated_payload_info_tag_tileLast;
  wire                divide_translated_payload_info_tag_last;
  wire                divide_translated_payload_info_raw;
  wire                divide_translated_payload_info_int16;
  wire       [5:0]    divide_translated_payload_info_shift;
  wire       [31:0]   divide_translated_payload_info_mac_0;
  wire       [31:0]   divide_translated_payload_info_mac_1;
  wire       [31:0]   divide_translated_payload_info_mac_2;
  wire       [31:0]   divide_translated_payload_info_mac_3;
  wire       [31:0]   divide_translated_payload_info_multiplier_0;
  wire       [31:0]   divide_translated_payload_info_multiplier_1;
  wire       [31:0]   divide_translated_payload_info_multiplier_2;
  wire       [31:0]   divide_translated_payload_info_multiplier_3;
  wire       [63:0]   divide_translated_payload_info_bias_0;
  wire       [63:0]   divide_translated_payload_info_bias_1;
  wire       [63:0]   divide_translated_payload_info_bias_2;
  wire       [63:0]   divide_translated_payload_info_bias_3;
  wire       [15:0]   divide_translated_payload_info_lower_0;
  wire       [15:0]   divide_translated_payload_info_lower_1;
  wire       [15:0]   divide_translated_payload_info_lower_2;
  wire       [15:0]   divide_translated_payload_info_lower_3;
  wire       [15:0]   divide_translated_payload_info_upper_0;
  wire       [15:0]   divide_translated_payload_info_upper_1;
  wire       [15:0]   divide_translated_payload_info_upper_2;
  wire       [15:0]   divide_translated_payload_info_upper_3;
  wire       [63:0]   divide_translated_payload_whole_0;
  wire       [63:0]   divide_translated_payload_whole_1;
  wire       [63:0]   divide_translated_payload_whole_2;
  wire       [63:0]   divide_translated_payload_whole_3;
  wire       [3:0]    divide_translated_payload_increment;
  wire                decision_valid;
  wire                decision_ready;
  wire       [18:0]   decision_payload_info_tag_pixel;
  wire       [3:0]    decision_payload_info_tag_localPixel;
  wire       [6:0]    decision_payload_info_tag_group;
  wire       [3:0]    decision_payload_info_tag_mask;
  wire                decision_payload_info_tag_first;
  wire                decision_payload_info_tag_finalInput;
  wire                decision_payload_info_tag_tileLast;
  wire                decision_payload_info_tag_last;
  wire                decision_payload_info_raw;
  wire                decision_payload_info_int16;
  wire       [5:0]    decision_payload_info_shift;
  wire       [31:0]   decision_payload_info_mac_0;
  wire       [31:0]   decision_payload_info_mac_1;
  wire       [31:0]   decision_payload_info_mac_2;
  wire       [31:0]   decision_payload_info_mac_3;
  wire       [31:0]   decision_payload_info_multiplier_0;
  wire       [31:0]   decision_payload_info_multiplier_1;
  wire       [31:0]   decision_payload_info_multiplier_2;
  wire       [31:0]   decision_payload_info_multiplier_3;
  wire       [63:0]   decision_payload_info_bias_0;
  wire       [63:0]   decision_payload_info_bias_1;
  wire       [63:0]   decision_payload_info_bias_2;
  wire       [63:0]   decision_payload_info_bias_3;
  wire       [15:0]   decision_payload_info_lower_0;
  wire       [15:0]   decision_payload_info_lower_1;
  wire       [15:0]   decision_payload_info_lower_2;
  wire       [15:0]   decision_payload_info_lower_3;
  wire       [15:0]   decision_payload_info_upper_0;
  wire       [15:0]   decision_payload_info_upper_1;
  wire       [15:0]   decision_payload_info_upper_2;
  wire       [15:0]   decision_payload_info_upper_3;
  wire       [63:0]   decision_payload_whole_0;
  wire       [63:0]   decision_payload_whole_1;
  wire       [63:0]   decision_payload_whole_2;
  wire       [63:0]   decision_payload_whole_3;
  wire       [3:0]    decision_payload_increment;
  reg                 divide_translated_rValid;
  reg        [18:0]   divide_translated_rData_info_tag_pixel;
  reg        [3:0]    divide_translated_rData_info_tag_localPixel;
  reg        [6:0]    divide_translated_rData_info_tag_group;
  reg        [3:0]    divide_translated_rData_info_tag_mask;
  reg                 divide_translated_rData_info_tag_first;
  reg                 divide_translated_rData_info_tag_finalInput;
  reg                 divide_translated_rData_info_tag_tileLast;
  reg                 divide_translated_rData_info_tag_last;
  reg                 divide_translated_rData_info_raw;
  reg                 divide_translated_rData_info_int16;
  reg        [5:0]    divide_translated_rData_info_shift;
  reg        [31:0]   divide_translated_rData_info_mac_0;
  reg        [31:0]   divide_translated_rData_info_mac_1;
  reg        [31:0]   divide_translated_rData_info_mac_2;
  reg        [31:0]   divide_translated_rData_info_mac_3;
  reg        [31:0]   divide_translated_rData_info_multiplier_0;
  reg        [31:0]   divide_translated_rData_info_multiplier_1;
  reg        [31:0]   divide_translated_rData_info_multiplier_2;
  reg        [31:0]   divide_translated_rData_info_multiplier_3;
  reg        [63:0]   divide_translated_rData_info_bias_0;
  reg        [63:0]   divide_translated_rData_info_bias_1;
  reg        [63:0]   divide_translated_rData_info_bias_2;
  reg        [63:0]   divide_translated_rData_info_bias_3;
  reg        [15:0]   divide_translated_rData_info_lower_0;
  reg        [15:0]   divide_translated_rData_info_lower_1;
  reg        [15:0]   divide_translated_rData_info_lower_2;
  reg        [15:0]   divide_translated_rData_info_lower_3;
  reg        [15:0]   divide_translated_rData_info_upper_0;
  reg        [15:0]   divide_translated_rData_info_upper_1;
  reg        [15:0]   divide_translated_rData_info_upper_2;
  reg        [15:0]   divide_translated_rData_info_upper_3;
  reg        [63:0]   divide_translated_rData_whole_0;
  reg        [63:0]   divide_translated_rData_whole_1;
  reg        [63:0]   divide_translated_rData_whole_2;
  reg        [63:0]   divide_translated_rData_whole_3;
  reg        [3:0]    divide_translated_rData_increment;
  wire                when_Stream_l477_3;
  wire       [18:0]   round_w_info_tag_pixel;
  wire       [3:0]    round_w_info_tag_localPixel;
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
  wire                decision_translated_valid;
  reg                 decision_translated_ready;
  wire       [18:0]   decision_translated_payload_info_tag_pixel;
  wire       [3:0]    decision_translated_payload_info_tag_localPixel;
  wire       [6:0]    decision_translated_payload_info_tag_group;
  wire       [3:0]    decision_translated_payload_info_tag_mask;
  wire                decision_translated_payload_info_tag_first;
  wire                decision_translated_payload_info_tag_finalInput;
  wire                decision_translated_payload_info_tag_tileLast;
  wire                decision_translated_payload_info_tag_last;
  wire                decision_translated_payload_info_raw;
  wire                decision_translated_payload_info_int16;
  wire       [5:0]    decision_translated_payload_info_shift;
  wire       [31:0]   decision_translated_payload_info_mac_0;
  wire       [31:0]   decision_translated_payload_info_mac_1;
  wire       [31:0]   decision_translated_payload_info_mac_2;
  wire       [31:0]   decision_translated_payload_info_mac_3;
  wire       [31:0]   decision_translated_payload_info_multiplier_0;
  wire       [31:0]   decision_translated_payload_info_multiplier_1;
  wire       [31:0]   decision_translated_payload_info_multiplier_2;
  wire       [31:0]   decision_translated_payload_info_multiplier_3;
  wire       [63:0]   decision_translated_payload_info_bias_0;
  wire       [63:0]   decision_translated_payload_info_bias_1;
  wire       [63:0]   decision_translated_payload_info_bias_2;
  wire       [63:0]   decision_translated_payload_info_bias_3;
  wire       [15:0]   decision_translated_payload_info_lower_0;
  wire       [15:0]   decision_translated_payload_info_lower_1;
  wire       [15:0]   decision_translated_payload_info_lower_2;
  wire       [15:0]   decision_translated_payload_info_lower_3;
  wire       [15:0]   decision_translated_payload_info_upper_0;
  wire       [15:0]   decision_translated_payload_info_upper_1;
  wire       [15:0]   decision_translated_payload_info_upper_2;
  wire       [15:0]   decision_translated_payload_info_upper_3;
  wire       [63:0]   decision_translated_payload_value_0;
  wire       [63:0]   decision_translated_payload_value_1;
  wire       [63:0]   decision_translated_payload_value_2;
  wire       [63:0]   decision_translated_payload_value_3;
  wire                rounded_valid;
  wire                rounded_ready;
  wire       [18:0]   rounded_payload_info_tag_pixel;
  wire       [3:0]    rounded_payload_info_tag_localPixel;
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
  reg                 decision_translated_rValid;
  reg        [18:0]   decision_translated_rData_info_tag_pixel;
  reg        [3:0]    decision_translated_rData_info_tag_localPixel;
  reg        [6:0]    decision_translated_rData_info_tag_group;
  reg        [3:0]    decision_translated_rData_info_tag_mask;
  reg                 decision_translated_rData_info_tag_first;
  reg                 decision_translated_rData_info_tag_finalInput;
  reg                 decision_translated_rData_info_tag_tileLast;
  reg                 decision_translated_rData_info_tag_last;
  reg                 decision_translated_rData_info_raw;
  reg                 decision_translated_rData_info_int16;
  reg        [5:0]    decision_translated_rData_info_shift;
  reg        [31:0]   decision_translated_rData_info_mac_0;
  reg        [31:0]   decision_translated_rData_info_mac_1;
  reg        [31:0]   decision_translated_rData_info_mac_2;
  reg        [31:0]   decision_translated_rData_info_mac_3;
  reg        [31:0]   decision_translated_rData_info_multiplier_0;
  reg        [31:0]   decision_translated_rData_info_multiplier_1;
  reg        [31:0]   decision_translated_rData_info_multiplier_2;
  reg        [31:0]   decision_translated_rData_info_multiplier_3;
  reg        [63:0]   decision_translated_rData_info_bias_0;
  reg        [63:0]   decision_translated_rData_info_bias_1;
  reg        [63:0]   decision_translated_rData_info_bias_2;
  reg        [63:0]   decision_translated_rData_info_bias_3;
  reg        [15:0]   decision_translated_rData_info_lower_0;
  reg        [15:0]   decision_translated_rData_info_lower_1;
  reg        [15:0]   decision_translated_rData_info_lower_2;
  reg        [15:0]   decision_translated_rData_info_lower_3;
  reg        [15:0]   decision_translated_rData_info_upper_0;
  reg        [15:0]   decision_translated_rData_info_upper_1;
  reg        [15:0]   decision_translated_rData_info_upper_2;
  reg        [15:0]   decision_translated_rData_info_upper_3;
  reg        [63:0]   decision_translated_rData_value_0;
  reg        [63:0]   decision_translated_rData_value_1;
  reg        [63:0]   decision_translated_rData_value_2;
  reg        [63:0]   decision_translated_rData_value_3;
  wire                when_Stream_l477_4;
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
  wire                when_PwMac_l123;
  wire                when_PwMac_l125;
  reg        [15:0]   _zz_result_w_q_1;
  wire                when_PwMac_l123_1;
  wire                when_PwMac_l125_1;
  reg        [15:0]   _zz_result_w_q_2;
  wire                when_PwMac_l123_2;
  wire                when_PwMac_l125_2;
  reg        [15:0]   _zz_result_w_q_3;
  wire                when_PwMac_l123_3;
  wire                when_PwMac_l125_3;
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
  wire                when_Stream_l477_5;

  assign _zz_remainderMask_w = (64'h0000000000000001 <<< sum_payload_info_shift);
  assign _zz_divide_w_half = (sum_payload_info_shift - 6'h01);
  assign _zz_round_w_value_0 = _zz_round_w_value_0_1;
  assign _zz_round_w_value_0_2 = decision_payload_increment[0];
  assign _zz_round_w_value_0_1 = {63'd0, _zz_round_w_value_0_2};
  assign _zz_round_w_value_1 = _zz_round_w_value_1_1;
  assign _zz_round_w_value_1_2 = decision_payload_increment[1];
  assign _zz_round_w_value_1_1 = {63'd0, _zz_round_w_value_1_2};
  assign _zz_round_w_value_2 = _zz_round_w_value_2_1;
  assign _zz_round_w_value_2_2 = decision_payload_increment[2];
  assign _zz_round_w_value_2_1 = {63'd0, _zz_round_w_value_2_2};
  assign _zz_round_w_value_3 = _zz_round_w_value_3_1;
  assign _zz_round_w_value_3_2 = decision_payload_increment[3];
  assign _zz_round_w_value_3_1 = {63'd0, _zz_round_w_value_3_2};
  assign _zz_when_PwMac_l123 = {{48{rounded_payload_info_lower_0[15]}}, rounded_payload_info_lower_0};
  assign _zz_when_PwMac_l125 = {{48{rounded_payload_info_upper_0[15]}}, rounded_payload_info_upper_0};
  assign _zz_when_PwMac_l123_1 = {{48{rounded_payload_info_lower_1[15]}}, rounded_payload_info_lower_1};
  assign _zz_when_PwMac_l125_1 = {{48{rounded_payload_info_upper_1[15]}}, rounded_payload_info_upper_1};
  assign _zz_when_PwMac_l123_2 = {{48{rounded_payload_info_lower_2[15]}}, rounded_payload_info_lower_2};
  assign _zz_when_PwMac_l125_2 = {{48{rounded_payload_info_upper_2[15]}}, rounded_payload_info_upper_2};
  assign _zz_when_PwMac_l123_3 = {{48{rounded_payload_info_lower_3[15]}}, rounded_payload_info_lower_3};
  assign _zz_when_PwMac_l125_3 = {{48{rounded_payload_info_upper_3[15]}}, rounded_payload_info_upper_3};
  assign product_w_info_tag_pixel = io_input_i_payload_tag_pixel;
  assign product_w_info_tag_localPixel = io_input_i_payload_tag_localPixel;
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
  assign io_input_i_translated_payload_info_tag_localPixel = product_w_info_tag_localPixel;
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
  assign product_payload_info_tag_localPixel = io_input_i_translated_rData_info_tag_localPixel;
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
  assign sum_w_info_tag_localPixel = product_payload_info_tag_localPixel;
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
  assign product_translated_payload_info_tag_localPixel = sum_w_info_tag_localPixel;
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
  assign sum_payload_info_tag_localPixel = product_translated_rData_info_tag_localPixel;
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
  assign divide_w_info_tag_pixel = sum_payload_info_tag_pixel;
  assign divide_w_info_tag_localPixel = sum_payload_info_tag_localPixel;
  assign divide_w_info_tag_group = sum_payload_info_tag_group;
  assign divide_w_info_tag_mask = sum_payload_info_tag_mask;
  assign divide_w_info_tag_first = sum_payload_info_tag_first;
  assign divide_w_info_tag_finalInput = sum_payload_info_tag_finalInput;
  assign divide_w_info_tag_tileLast = sum_payload_info_tag_tileLast;
  assign divide_w_info_tag_last = sum_payload_info_tag_last;
  assign divide_w_info_raw = sum_payload_info_raw;
  assign divide_w_info_int16 = sum_payload_info_int16;
  assign divide_w_info_shift = sum_payload_info_shift;
  assign divide_w_info_mac_0 = sum_payload_info_mac_0;
  assign divide_w_info_mac_1 = sum_payload_info_mac_1;
  assign divide_w_info_mac_2 = sum_payload_info_mac_2;
  assign divide_w_info_mac_3 = sum_payload_info_mac_3;
  assign divide_w_info_multiplier_0 = sum_payload_info_multiplier_0;
  assign divide_w_info_multiplier_1 = sum_payload_info_multiplier_1;
  assign divide_w_info_multiplier_2 = sum_payload_info_multiplier_2;
  assign divide_w_info_multiplier_3 = sum_payload_info_multiplier_3;
  assign divide_w_info_bias_0 = sum_payload_info_bias_0;
  assign divide_w_info_bias_1 = sum_payload_info_bias_1;
  assign divide_w_info_bias_2 = sum_payload_info_bias_2;
  assign divide_w_info_bias_3 = sum_payload_info_bias_3;
  assign divide_w_info_lower_0 = sum_payload_info_lower_0;
  assign divide_w_info_lower_1 = sum_payload_info_lower_1;
  assign divide_w_info_lower_2 = sum_payload_info_lower_2;
  assign divide_w_info_lower_3 = sum_payload_info_lower_3;
  assign divide_w_info_upper_0 = sum_payload_info_upper_0;
  assign divide_w_info_upper_1 = sum_payload_info_upper_1;
  assign divide_w_info_upper_2 = sum_payload_info_upper_2;
  assign divide_w_info_upper_3 = sum_payload_info_upper_3;
  assign remainderMask_w = (_zz_remainderMask_w - 64'h0000000000000001);
  assign divide_w_half = (64'h0000000000000001 <<< _zz_divide_w_half);
  assign divide_w_whole_0 = ($signed(sum_payload_value_0) >>> sum_payload_info_shift);
  assign divide_w_remainder_0 = (sum_payload_value_0 & remainderMask_w);
  assign divide_w_whole_1 = ($signed(sum_payload_value_1) >>> sum_payload_info_shift);
  assign divide_w_remainder_1 = (sum_payload_value_1 & remainderMask_w);
  assign divide_w_whole_2 = ($signed(sum_payload_value_2) >>> sum_payload_info_shift);
  assign divide_w_remainder_2 = (sum_payload_value_2 & remainderMask_w);
  assign divide_w_whole_3 = ($signed(sum_payload_value_3) >>> sum_payload_info_shift);
  assign divide_w_remainder_3 = (sum_payload_value_3 & remainderMask_w);
  assign sum_translated_valid = sum_valid;
  assign sum_ready = sum_translated_ready;
  assign sum_translated_payload_info_tag_pixel = divide_w_info_tag_pixel;
  assign sum_translated_payload_info_tag_localPixel = divide_w_info_tag_localPixel;
  assign sum_translated_payload_info_tag_group = divide_w_info_tag_group;
  assign sum_translated_payload_info_tag_mask = divide_w_info_tag_mask;
  assign sum_translated_payload_info_tag_first = divide_w_info_tag_first;
  assign sum_translated_payload_info_tag_finalInput = divide_w_info_tag_finalInput;
  assign sum_translated_payload_info_tag_tileLast = divide_w_info_tag_tileLast;
  assign sum_translated_payload_info_tag_last = divide_w_info_tag_last;
  assign sum_translated_payload_info_raw = divide_w_info_raw;
  assign sum_translated_payload_info_int16 = divide_w_info_int16;
  assign sum_translated_payload_info_shift = divide_w_info_shift;
  assign sum_translated_payload_info_mac_0 = divide_w_info_mac_0;
  assign sum_translated_payload_info_mac_1 = divide_w_info_mac_1;
  assign sum_translated_payload_info_mac_2 = divide_w_info_mac_2;
  assign sum_translated_payload_info_mac_3 = divide_w_info_mac_3;
  assign sum_translated_payload_info_multiplier_0 = divide_w_info_multiplier_0;
  assign sum_translated_payload_info_multiplier_1 = divide_w_info_multiplier_1;
  assign sum_translated_payload_info_multiplier_2 = divide_w_info_multiplier_2;
  assign sum_translated_payload_info_multiplier_3 = divide_w_info_multiplier_3;
  assign sum_translated_payload_info_bias_0 = divide_w_info_bias_0;
  assign sum_translated_payload_info_bias_1 = divide_w_info_bias_1;
  assign sum_translated_payload_info_bias_2 = divide_w_info_bias_2;
  assign sum_translated_payload_info_bias_3 = divide_w_info_bias_3;
  assign sum_translated_payload_info_lower_0 = divide_w_info_lower_0;
  assign sum_translated_payload_info_lower_1 = divide_w_info_lower_1;
  assign sum_translated_payload_info_lower_2 = divide_w_info_lower_2;
  assign sum_translated_payload_info_lower_3 = divide_w_info_lower_3;
  assign sum_translated_payload_info_upper_0 = divide_w_info_upper_0;
  assign sum_translated_payload_info_upper_1 = divide_w_info_upper_1;
  assign sum_translated_payload_info_upper_2 = divide_w_info_upper_2;
  assign sum_translated_payload_info_upper_3 = divide_w_info_upper_3;
  assign sum_translated_payload_whole_0 = divide_w_whole_0;
  assign sum_translated_payload_whole_1 = divide_w_whole_1;
  assign sum_translated_payload_whole_2 = divide_w_whole_2;
  assign sum_translated_payload_whole_3 = divide_w_whole_3;
  assign sum_translated_payload_remainder_0 = divide_w_remainder_0;
  assign sum_translated_payload_remainder_1 = divide_w_remainder_1;
  assign sum_translated_payload_remainder_2 = divide_w_remainder_2;
  assign sum_translated_payload_remainder_3 = divide_w_remainder_3;
  assign sum_translated_payload_half = divide_w_half;
  always @(*) begin
    sum_translated_ready = divide_ready;
    if(when_Stream_l477_2) begin
      sum_translated_ready = 1'b1;
    end
  end

  assign when_Stream_l477_2 = (! divide_valid);
  assign divide_valid = sum_translated_rValid;
  assign divide_payload_info_tag_pixel = sum_translated_rData_info_tag_pixel;
  assign divide_payload_info_tag_localPixel = sum_translated_rData_info_tag_localPixel;
  assign divide_payload_info_tag_group = sum_translated_rData_info_tag_group;
  assign divide_payload_info_tag_mask = sum_translated_rData_info_tag_mask;
  assign divide_payload_info_tag_first = sum_translated_rData_info_tag_first;
  assign divide_payload_info_tag_finalInput = sum_translated_rData_info_tag_finalInput;
  assign divide_payload_info_tag_tileLast = sum_translated_rData_info_tag_tileLast;
  assign divide_payload_info_tag_last = sum_translated_rData_info_tag_last;
  assign divide_payload_info_raw = sum_translated_rData_info_raw;
  assign divide_payload_info_int16 = sum_translated_rData_info_int16;
  assign divide_payload_info_shift = sum_translated_rData_info_shift;
  assign divide_payload_info_mac_0 = sum_translated_rData_info_mac_0;
  assign divide_payload_info_mac_1 = sum_translated_rData_info_mac_1;
  assign divide_payload_info_mac_2 = sum_translated_rData_info_mac_2;
  assign divide_payload_info_mac_3 = sum_translated_rData_info_mac_3;
  assign divide_payload_info_multiplier_0 = sum_translated_rData_info_multiplier_0;
  assign divide_payload_info_multiplier_1 = sum_translated_rData_info_multiplier_1;
  assign divide_payload_info_multiplier_2 = sum_translated_rData_info_multiplier_2;
  assign divide_payload_info_multiplier_3 = sum_translated_rData_info_multiplier_3;
  assign divide_payload_info_bias_0 = sum_translated_rData_info_bias_0;
  assign divide_payload_info_bias_1 = sum_translated_rData_info_bias_1;
  assign divide_payload_info_bias_2 = sum_translated_rData_info_bias_2;
  assign divide_payload_info_bias_3 = sum_translated_rData_info_bias_3;
  assign divide_payload_info_lower_0 = sum_translated_rData_info_lower_0;
  assign divide_payload_info_lower_1 = sum_translated_rData_info_lower_1;
  assign divide_payload_info_lower_2 = sum_translated_rData_info_lower_2;
  assign divide_payload_info_lower_3 = sum_translated_rData_info_lower_3;
  assign divide_payload_info_upper_0 = sum_translated_rData_info_upper_0;
  assign divide_payload_info_upper_1 = sum_translated_rData_info_upper_1;
  assign divide_payload_info_upper_2 = sum_translated_rData_info_upper_2;
  assign divide_payload_info_upper_3 = sum_translated_rData_info_upper_3;
  assign divide_payload_whole_0 = sum_translated_rData_whole_0;
  assign divide_payload_whole_1 = sum_translated_rData_whole_1;
  assign divide_payload_whole_2 = sum_translated_rData_whole_2;
  assign divide_payload_whole_3 = sum_translated_rData_whole_3;
  assign divide_payload_remainder_0 = sum_translated_rData_remainder_0;
  assign divide_payload_remainder_1 = sum_translated_rData_remainder_1;
  assign divide_payload_remainder_2 = sum_translated_rData_remainder_2;
  assign divide_payload_remainder_3 = sum_translated_rData_remainder_3;
  assign divide_payload_half = sum_translated_rData_half;
  assign decision_w_info_tag_pixel = divide_payload_info_tag_pixel;
  assign decision_w_info_tag_localPixel = divide_payload_info_tag_localPixel;
  assign decision_w_info_tag_group = divide_payload_info_tag_group;
  assign decision_w_info_tag_mask = divide_payload_info_tag_mask;
  assign decision_w_info_tag_first = divide_payload_info_tag_first;
  assign decision_w_info_tag_finalInput = divide_payload_info_tag_finalInput;
  assign decision_w_info_tag_tileLast = divide_payload_info_tag_tileLast;
  assign decision_w_info_tag_last = divide_payload_info_tag_last;
  assign decision_w_info_raw = divide_payload_info_raw;
  assign decision_w_info_int16 = divide_payload_info_int16;
  assign decision_w_info_shift = divide_payload_info_shift;
  assign decision_w_info_mac_0 = divide_payload_info_mac_0;
  assign decision_w_info_mac_1 = divide_payload_info_mac_1;
  assign decision_w_info_mac_2 = divide_payload_info_mac_2;
  assign decision_w_info_mac_3 = divide_payload_info_mac_3;
  assign decision_w_info_multiplier_0 = divide_payload_info_multiplier_0;
  assign decision_w_info_multiplier_1 = divide_payload_info_multiplier_1;
  assign decision_w_info_multiplier_2 = divide_payload_info_multiplier_2;
  assign decision_w_info_multiplier_3 = divide_payload_info_multiplier_3;
  assign decision_w_info_bias_0 = divide_payload_info_bias_0;
  assign decision_w_info_bias_1 = divide_payload_info_bias_1;
  assign decision_w_info_bias_2 = divide_payload_info_bias_2;
  assign decision_w_info_bias_3 = divide_payload_info_bias_3;
  assign decision_w_info_lower_0 = divide_payload_info_lower_0;
  assign decision_w_info_lower_1 = divide_payload_info_lower_1;
  assign decision_w_info_lower_2 = divide_payload_info_lower_2;
  assign decision_w_info_lower_3 = divide_payload_info_lower_3;
  assign decision_w_info_upper_0 = divide_payload_info_upper_0;
  assign decision_w_info_upper_1 = divide_payload_info_upper_1;
  assign decision_w_info_upper_2 = divide_payload_info_upper_2;
  assign decision_w_info_upper_3 = divide_payload_info_upper_3;
  assign decision_w_whole_0 = divide_payload_whole_0;
  assign decision_w_whole_1 = divide_payload_whole_1;
  assign decision_w_whole_2 = divide_payload_whole_2;
  assign decision_w_whole_3 = divide_payload_whole_3;
  always @(*) begin
    decision_w_increment[0] = ((divide_payload_info_shift != 6'h0) && ((divide_payload_half < divide_payload_remainder_0) || ((divide_payload_remainder_0 == divide_payload_half) && divide_payload_whole_0[0])));
    decision_w_increment[1] = ((divide_payload_info_shift != 6'h0) && ((divide_payload_half < divide_payload_remainder_1) || ((divide_payload_remainder_1 == divide_payload_half) && divide_payload_whole_1[0])));
    decision_w_increment[2] = ((divide_payload_info_shift != 6'h0) && ((divide_payload_half < divide_payload_remainder_2) || ((divide_payload_remainder_2 == divide_payload_half) && divide_payload_whole_2[0])));
    decision_w_increment[3] = ((divide_payload_info_shift != 6'h0) && ((divide_payload_half < divide_payload_remainder_3) || ((divide_payload_remainder_3 == divide_payload_half) && divide_payload_whole_3[0])));
  end

  assign divide_translated_valid = divide_valid;
  assign divide_ready = divide_translated_ready;
  assign divide_translated_payload_info_tag_pixel = decision_w_info_tag_pixel;
  assign divide_translated_payload_info_tag_localPixel = decision_w_info_tag_localPixel;
  assign divide_translated_payload_info_tag_group = decision_w_info_tag_group;
  assign divide_translated_payload_info_tag_mask = decision_w_info_tag_mask;
  assign divide_translated_payload_info_tag_first = decision_w_info_tag_first;
  assign divide_translated_payload_info_tag_finalInput = decision_w_info_tag_finalInput;
  assign divide_translated_payload_info_tag_tileLast = decision_w_info_tag_tileLast;
  assign divide_translated_payload_info_tag_last = decision_w_info_tag_last;
  assign divide_translated_payload_info_raw = decision_w_info_raw;
  assign divide_translated_payload_info_int16 = decision_w_info_int16;
  assign divide_translated_payload_info_shift = decision_w_info_shift;
  assign divide_translated_payload_info_mac_0 = decision_w_info_mac_0;
  assign divide_translated_payload_info_mac_1 = decision_w_info_mac_1;
  assign divide_translated_payload_info_mac_2 = decision_w_info_mac_2;
  assign divide_translated_payload_info_mac_3 = decision_w_info_mac_3;
  assign divide_translated_payload_info_multiplier_0 = decision_w_info_multiplier_0;
  assign divide_translated_payload_info_multiplier_1 = decision_w_info_multiplier_1;
  assign divide_translated_payload_info_multiplier_2 = decision_w_info_multiplier_2;
  assign divide_translated_payload_info_multiplier_3 = decision_w_info_multiplier_3;
  assign divide_translated_payload_info_bias_0 = decision_w_info_bias_0;
  assign divide_translated_payload_info_bias_1 = decision_w_info_bias_1;
  assign divide_translated_payload_info_bias_2 = decision_w_info_bias_2;
  assign divide_translated_payload_info_bias_3 = decision_w_info_bias_3;
  assign divide_translated_payload_info_lower_0 = decision_w_info_lower_0;
  assign divide_translated_payload_info_lower_1 = decision_w_info_lower_1;
  assign divide_translated_payload_info_lower_2 = decision_w_info_lower_2;
  assign divide_translated_payload_info_lower_3 = decision_w_info_lower_3;
  assign divide_translated_payload_info_upper_0 = decision_w_info_upper_0;
  assign divide_translated_payload_info_upper_1 = decision_w_info_upper_1;
  assign divide_translated_payload_info_upper_2 = decision_w_info_upper_2;
  assign divide_translated_payload_info_upper_3 = decision_w_info_upper_3;
  assign divide_translated_payload_whole_0 = decision_w_whole_0;
  assign divide_translated_payload_whole_1 = decision_w_whole_1;
  assign divide_translated_payload_whole_2 = decision_w_whole_2;
  assign divide_translated_payload_whole_3 = decision_w_whole_3;
  assign divide_translated_payload_increment = decision_w_increment;
  always @(*) begin
    divide_translated_ready = decision_ready;
    if(when_Stream_l477_3) begin
      divide_translated_ready = 1'b1;
    end
  end

  assign when_Stream_l477_3 = (! decision_valid);
  assign decision_valid = divide_translated_rValid;
  assign decision_payload_info_tag_pixel = divide_translated_rData_info_tag_pixel;
  assign decision_payload_info_tag_localPixel = divide_translated_rData_info_tag_localPixel;
  assign decision_payload_info_tag_group = divide_translated_rData_info_tag_group;
  assign decision_payload_info_tag_mask = divide_translated_rData_info_tag_mask;
  assign decision_payload_info_tag_first = divide_translated_rData_info_tag_first;
  assign decision_payload_info_tag_finalInput = divide_translated_rData_info_tag_finalInput;
  assign decision_payload_info_tag_tileLast = divide_translated_rData_info_tag_tileLast;
  assign decision_payload_info_tag_last = divide_translated_rData_info_tag_last;
  assign decision_payload_info_raw = divide_translated_rData_info_raw;
  assign decision_payload_info_int16 = divide_translated_rData_info_int16;
  assign decision_payload_info_shift = divide_translated_rData_info_shift;
  assign decision_payload_info_mac_0 = divide_translated_rData_info_mac_0;
  assign decision_payload_info_mac_1 = divide_translated_rData_info_mac_1;
  assign decision_payload_info_mac_2 = divide_translated_rData_info_mac_2;
  assign decision_payload_info_mac_3 = divide_translated_rData_info_mac_3;
  assign decision_payload_info_multiplier_0 = divide_translated_rData_info_multiplier_0;
  assign decision_payload_info_multiplier_1 = divide_translated_rData_info_multiplier_1;
  assign decision_payload_info_multiplier_2 = divide_translated_rData_info_multiplier_2;
  assign decision_payload_info_multiplier_3 = divide_translated_rData_info_multiplier_3;
  assign decision_payload_info_bias_0 = divide_translated_rData_info_bias_0;
  assign decision_payload_info_bias_1 = divide_translated_rData_info_bias_1;
  assign decision_payload_info_bias_2 = divide_translated_rData_info_bias_2;
  assign decision_payload_info_bias_3 = divide_translated_rData_info_bias_3;
  assign decision_payload_info_lower_0 = divide_translated_rData_info_lower_0;
  assign decision_payload_info_lower_1 = divide_translated_rData_info_lower_1;
  assign decision_payload_info_lower_2 = divide_translated_rData_info_lower_2;
  assign decision_payload_info_lower_3 = divide_translated_rData_info_lower_3;
  assign decision_payload_info_upper_0 = divide_translated_rData_info_upper_0;
  assign decision_payload_info_upper_1 = divide_translated_rData_info_upper_1;
  assign decision_payload_info_upper_2 = divide_translated_rData_info_upper_2;
  assign decision_payload_info_upper_3 = divide_translated_rData_info_upper_3;
  assign decision_payload_whole_0 = divide_translated_rData_whole_0;
  assign decision_payload_whole_1 = divide_translated_rData_whole_1;
  assign decision_payload_whole_2 = divide_translated_rData_whole_2;
  assign decision_payload_whole_3 = divide_translated_rData_whole_3;
  assign decision_payload_increment = divide_translated_rData_increment;
  assign round_w_info_tag_pixel = decision_payload_info_tag_pixel;
  assign round_w_info_tag_localPixel = decision_payload_info_tag_localPixel;
  assign round_w_info_tag_group = decision_payload_info_tag_group;
  assign round_w_info_tag_mask = decision_payload_info_tag_mask;
  assign round_w_info_tag_first = decision_payload_info_tag_first;
  assign round_w_info_tag_finalInput = decision_payload_info_tag_finalInput;
  assign round_w_info_tag_tileLast = decision_payload_info_tag_tileLast;
  assign round_w_info_tag_last = decision_payload_info_tag_last;
  assign round_w_info_raw = decision_payload_info_raw;
  assign round_w_info_int16 = decision_payload_info_int16;
  assign round_w_info_shift = decision_payload_info_shift;
  assign round_w_info_mac_0 = decision_payload_info_mac_0;
  assign round_w_info_mac_1 = decision_payload_info_mac_1;
  assign round_w_info_mac_2 = decision_payload_info_mac_2;
  assign round_w_info_mac_3 = decision_payload_info_mac_3;
  assign round_w_info_multiplier_0 = decision_payload_info_multiplier_0;
  assign round_w_info_multiplier_1 = decision_payload_info_multiplier_1;
  assign round_w_info_multiplier_2 = decision_payload_info_multiplier_2;
  assign round_w_info_multiplier_3 = decision_payload_info_multiplier_3;
  assign round_w_info_bias_0 = decision_payload_info_bias_0;
  assign round_w_info_bias_1 = decision_payload_info_bias_1;
  assign round_w_info_bias_2 = decision_payload_info_bias_2;
  assign round_w_info_bias_3 = decision_payload_info_bias_3;
  assign round_w_info_lower_0 = decision_payload_info_lower_0;
  assign round_w_info_lower_1 = decision_payload_info_lower_1;
  assign round_w_info_lower_2 = decision_payload_info_lower_2;
  assign round_w_info_lower_3 = decision_payload_info_lower_3;
  assign round_w_info_upper_0 = decision_payload_info_upper_0;
  assign round_w_info_upper_1 = decision_payload_info_upper_1;
  assign round_w_info_upper_2 = decision_payload_info_upper_2;
  assign round_w_info_upper_3 = decision_payload_info_upper_3;
  assign round_w_value_0 = ($signed(decision_payload_whole_0) + $signed(_zz_round_w_value_0));
  assign round_w_value_1 = ($signed(decision_payload_whole_1) + $signed(_zz_round_w_value_1));
  assign round_w_value_2 = ($signed(decision_payload_whole_2) + $signed(_zz_round_w_value_2));
  assign round_w_value_3 = ($signed(decision_payload_whole_3) + $signed(_zz_round_w_value_3));
  assign decision_translated_valid = decision_valid;
  assign decision_ready = decision_translated_ready;
  assign decision_translated_payload_info_tag_pixel = round_w_info_tag_pixel;
  assign decision_translated_payload_info_tag_localPixel = round_w_info_tag_localPixel;
  assign decision_translated_payload_info_tag_group = round_w_info_tag_group;
  assign decision_translated_payload_info_tag_mask = round_w_info_tag_mask;
  assign decision_translated_payload_info_tag_first = round_w_info_tag_first;
  assign decision_translated_payload_info_tag_finalInput = round_w_info_tag_finalInput;
  assign decision_translated_payload_info_tag_tileLast = round_w_info_tag_tileLast;
  assign decision_translated_payload_info_tag_last = round_w_info_tag_last;
  assign decision_translated_payload_info_raw = round_w_info_raw;
  assign decision_translated_payload_info_int16 = round_w_info_int16;
  assign decision_translated_payload_info_shift = round_w_info_shift;
  assign decision_translated_payload_info_mac_0 = round_w_info_mac_0;
  assign decision_translated_payload_info_mac_1 = round_w_info_mac_1;
  assign decision_translated_payload_info_mac_2 = round_w_info_mac_2;
  assign decision_translated_payload_info_mac_3 = round_w_info_mac_3;
  assign decision_translated_payload_info_multiplier_0 = round_w_info_multiplier_0;
  assign decision_translated_payload_info_multiplier_1 = round_w_info_multiplier_1;
  assign decision_translated_payload_info_multiplier_2 = round_w_info_multiplier_2;
  assign decision_translated_payload_info_multiplier_3 = round_w_info_multiplier_3;
  assign decision_translated_payload_info_bias_0 = round_w_info_bias_0;
  assign decision_translated_payload_info_bias_1 = round_w_info_bias_1;
  assign decision_translated_payload_info_bias_2 = round_w_info_bias_2;
  assign decision_translated_payload_info_bias_3 = round_w_info_bias_3;
  assign decision_translated_payload_info_lower_0 = round_w_info_lower_0;
  assign decision_translated_payload_info_lower_1 = round_w_info_lower_1;
  assign decision_translated_payload_info_lower_2 = round_w_info_lower_2;
  assign decision_translated_payload_info_lower_3 = round_w_info_lower_3;
  assign decision_translated_payload_info_upper_0 = round_w_info_upper_0;
  assign decision_translated_payload_info_upper_1 = round_w_info_upper_1;
  assign decision_translated_payload_info_upper_2 = round_w_info_upper_2;
  assign decision_translated_payload_info_upper_3 = round_w_info_upper_3;
  assign decision_translated_payload_value_0 = round_w_value_0;
  assign decision_translated_payload_value_1 = round_w_value_1;
  assign decision_translated_payload_value_2 = round_w_value_2;
  assign decision_translated_payload_value_3 = round_w_value_3;
  always @(*) begin
    decision_translated_ready = rounded_ready;
    if(when_Stream_l477_4) begin
      decision_translated_ready = 1'b1;
    end
  end

  assign when_Stream_l477_4 = (! rounded_valid);
  assign rounded_valid = decision_translated_rValid;
  assign rounded_payload_info_tag_pixel = decision_translated_rData_info_tag_pixel;
  assign rounded_payload_info_tag_localPixel = decision_translated_rData_info_tag_localPixel;
  assign rounded_payload_info_tag_group = decision_translated_rData_info_tag_group;
  assign rounded_payload_info_tag_mask = decision_translated_rData_info_tag_mask;
  assign rounded_payload_info_tag_first = decision_translated_rData_info_tag_first;
  assign rounded_payload_info_tag_finalInput = decision_translated_rData_info_tag_finalInput;
  assign rounded_payload_info_tag_tileLast = decision_translated_rData_info_tag_tileLast;
  assign rounded_payload_info_tag_last = decision_translated_rData_info_tag_last;
  assign rounded_payload_info_raw = decision_translated_rData_info_raw;
  assign rounded_payload_info_int16 = decision_translated_rData_info_int16;
  assign rounded_payload_info_shift = decision_translated_rData_info_shift;
  assign rounded_payload_info_mac_0 = decision_translated_rData_info_mac_0;
  assign rounded_payload_info_mac_1 = decision_translated_rData_info_mac_1;
  assign rounded_payload_info_mac_2 = decision_translated_rData_info_mac_2;
  assign rounded_payload_info_mac_3 = decision_translated_rData_info_mac_3;
  assign rounded_payload_info_multiplier_0 = decision_translated_rData_info_multiplier_0;
  assign rounded_payload_info_multiplier_1 = decision_translated_rData_info_multiplier_1;
  assign rounded_payload_info_multiplier_2 = decision_translated_rData_info_multiplier_2;
  assign rounded_payload_info_multiplier_3 = decision_translated_rData_info_multiplier_3;
  assign rounded_payload_info_bias_0 = decision_translated_rData_info_bias_0;
  assign rounded_payload_info_bias_1 = decision_translated_rData_info_bias_1;
  assign rounded_payload_info_bias_2 = decision_translated_rData_info_bias_2;
  assign rounded_payload_info_bias_3 = decision_translated_rData_info_bias_3;
  assign rounded_payload_info_lower_0 = decision_translated_rData_info_lower_0;
  assign rounded_payload_info_lower_1 = decision_translated_rData_info_lower_1;
  assign rounded_payload_info_lower_2 = decision_translated_rData_info_lower_2;
  assign rounded_payload_info_lower_3 = decision_translated_rData_info_lower_3;
  assign rounded_payload_info_upper_0 = decision_translated_rData_info_upper_0;
  assign rounded_payload_info_upper_1 = decision_translated_rData_info_upper_1;
  assign rounded_payload_info_upper_2 = decision_translated_rData_info_upper_2;
  assign rounded_payload_info_upper_3 = decision_translated_rData_info_upper_3;
  assign rounded_payload_value_0 = decision_translated_rData_value_0;
  assign rounded_payload_value_1 = decision_translated_rData_value_1;
  assign rounded_payload_value_2 = decision_translated_rData_value_2;
  assign rounded_payload_value_3 = decision_translated_rData_value_3;
  assign result_w_pixel = rounded_payload_info_tag_pixel;
  assign result_w_group = rounded_payload_info_tag_group;
  assign result_w_mask = rounded_payload_info_tag_mask;
  assign result_w_last = rounded_payload_info_tag_last;
  assign result_w_raw = rounded_payload_info_raw;
  assign result_w_int16 = rounded_payload_info_int16;
  assign result_w_mac_0 = (rounded_payload_info_tag_mask[0] ? rounded_payload_info_mac_0 : 32'h0);
  always @(*) begin
    _zz_result_w_q_0 = rounded_payload_value_0[15:0];
    if(when_PwMac_l123) begin
      _zz_result_w_q_0 = rounded_payload_info_lower_0;
    end else begin
      if(when_PwMac_l125) begin
        _zz_result_w_q_0 = rounded_payload_info_upper_0;
      end
    end
  end

  assign when_PwMac_l123 = ($signed(rounded_payload_value_0) < $signed(_zz_when_PwMac_l123));
  assign when_PwMac_l125 = ($signed(_zz_when_PwMac_l125) < $signed(rounded_payload_value_0));
  assign result_w_q_0 = ((rounded_payload_info_raw || (! rounded_payload_info_tag_mask[0])) ? 16'h0 : _zz_result_w_q_0);
  assign result_w_mac_1 = (rounded_payload_info_tag_mask[1] ? rounded_payload_info_mac_1 : 32'h0);
  always @(*) begin
    _zz_result_w_q_1 = rounded_payload_value_1[15:0];
    if(when_PwMac_l123_1) begin
      _zz_result_w_q_1 = rounded_payload_info_lower_1;
    end else begin
      if(when_PwMac_l125_1) begin
        _zz_result_w_q_1 = rounded_payload_info_upper_1;
      end
    end
  end

  assign when_PwMac_l123_1 = ($signed(rounded_payload_value_1) < $signed(_zz_when_PwMac_l123_1));
  assign when_PwMac_l125_1 = ($signed(_zz_when_PwMac_l125_1) < $signed(rounded_payload_value_1));
  assign result_w_q_1 = ((rounded_payload_info_raw || (! rounded_payload_info_tag_mask[1])) ? 16'h0 : _zz_result_w_q_1);
  assign result_w_mac_2 = (rounded_payload_info_tag_mask[2] ? rounded_payload_info_mac_2 : 32'h0);
  always @(*) begin
    _zz_result_w_q_2 = rounded_payload_value_2[15:0];
    if(when_PwMac_l123_2) begin
      _zz_result_w_q_2 = rounded_payload_info_lower_2;
    end else begin
      if(when_PwMac_l125_2) begin
        _zz_result_w_q_2 = rounded_payload_info_upper_2;
      end
    end
  end

  assign when_PwMac_l123_2 = ($signed(rounded_payload_value_2) < $signed(_zz_when_PwMac_l123_2));
  assign when_PwMac_l125_2 = ($signed(_zz_when_PwMac_l125_2) < $signed(rounded_payload_value_2));
  assign result_w_q_2 = ((rounded_payload_info_raw || (! rounded_payload_info_tag_mask[2])) ? 16'h0 : _zz_result_w_q_2);
  assign result_w_mac_3 = (rounded_payload_info_tag_mask[3] ? rounded_payload_info_mac_3 : 32'h0);
  always @(*) begin
    _zz_result_w_q_3 = rounded_payload_value_3[15:0];
    if(when_PwMac_l123_3) begin
      _zz_result_w_q_3 = rounded_payload_info_lower_3;
    end else begin
      if(when_PwMac_l125_3) begin
        _zz_result_w_q_3 = rounded_payload_info_upper_3;
      end
    end
  end

  assign when_PwMac_l123_3 = ($signed(rounded_payload_value_3) < $signed(_zz_when_PwMac_l123_3));
  assign when_PwMac_l125_3 = ($signed(_zz_when_PwMac_l125_3) < $signed(rounded_payload_value_3));
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
    if(when_Stream_l477_5) begin
      rounded_translated_ready = 1'b1;
    end
  end

  assign when_Stream_l477_5 = (! rounded_translated_m2sPipe_valid);
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
      divide_translated_rValid <= 1'b0;
      decision_translated_rValid <= 1'b0;
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
      if(divide_translated_ready) begin
        divide_translated_rValid <= divide_translated_valid;
      end
      if(decision_translated_ready) begin
        decision_translated_rValid <= decision_translated_valid;
      end
      if(rounded_translated_ready) begin
        rounded_translated_rValid <= rounded_translated_valid;
      end
    end
  end

  always @(posedge clk) begin
    if(io_input_i_translated_ready) begin
      io_input_i_translated_rData_info_tag_pixel <= io_input_i_translated_payload_info_tag_pixel;
      io_input_i_translated_rData_info_tag_localPixel <= io_input_i_translated_payload_info_tag_localPixel;
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
      product_translated_rData_info_tag_localPixel <= product_translated_payload_info_tag_localPixel;
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
      sum_translated_rData_info_tag_localPixel <= sum_translated_payload_info_tag_localPixel;
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
      sum_translated_rData_whole_0 <= sum_translated_payload_whole_0;
      sum_translated_rData_whole_1 <= sum_translated_payload_whole_1;
      sum_translated_rData_whole_2 <= sum_translated_payload_whole_2;
      sum_translated_rData_whole_3 <= sum_translated_payload_whole_3;
      sum_translated_rData_remainder_0 <= sum_translated_payload_remainder_0;
      sum_translated_rData_remainder_1 <= sum_translated_payload_remainder_1;
      sum_translated_rData_remainder_2 <= sum_translated_payload_remainder_2;
      sum_translated_rData_remainder_3 <= sum_translated_payload_remainder_3;
      sum_translated_rData_half <= sum_translated_payload_half;
    end
    if(divide_translated_ready) begin
      divide_translated_rData_info_tag_pixel <= divide_translated_payload_info_tag_pixel;
      divide_translated_rData_info_tag_localPixel <= divide_translated_payload_info_tag_localPixel;
      divide_translated_rData_info_tag_group <= divide_translated_payload_info_tag_group;
      divide_translated_rData_info_tag_mask <= divide_translated_payload_info_tag_mask;
      divide_translated_rData_info_tag_first <= divide_translated_payload_info_tag_first;
      divide_translated_rData_info_tag_finalInput <= divide_translated_payload_info_tag_finalInput;
      divide_translated_rData_info_tag_tileLast <= divide_translated_payload_info_tag_tileLast;
      divide_translated_rData_info_tag_last <= divide_translated_payload_info_tag_last;
      divide_translated_rData_info_raw <= divide_translated_payload_info_raw;
      divide_translated_rData_info_int16 <= divide_translated_payload_info_int16;
      divide_translated_rData_info_shift <= divide_translated_payload_info_shift;
      divide_translated_rData_info_mac_0 <= divide_translated_payload_info_mac_0;
      divide_translated_rData_info_mac_1 <= divide_translated_payload_info_mac_1;
      divide_translated_rData_info_mac_2 <= divide_translated_payload_info_mac_2;
      divide_translated_rData_info_mac_3 <= divide_translated_payload_info_mac_3;
      divide_translated_rData_info_multiplier_0 <= divide_translated_payload_info_multiplier_0;
      divide_translated_rData_info_multiplier_1 <= divide_translated_payload_info_multiplier_1;
      divide_translated_rData_info_multiplier_2 <= divide_translated_payload_info_multiplier_2;
      divide_translated_rData_info_multiplier_3 <= divide_translated_payload_info_multiplier_3;
      divide_translated_rData_info_bias_0 <= divide_translated_payload_info_bias_0;
      divide_translated_rData_info_bias_1 <= divide_translated_payload_info_bias_1;
      divide_translated_rData_info_bias_2 <= divide_translated_payload_info_bias_2;
      divide_translated_rData_info_bias_3 <= divide_translated_payload_info_bias_3;
      divide_translated_rData_info_lower_0 <= divide_translated_payload_info_lower_0;
      divide_translated_rData_info_lower_1 <= divide_translated_payload_info_lower_1;
      divide_translated_rData_info_lower_2 <= divide_translated_payload_info_lower_2;
      divide_translated_rData_info_lower_3 <= divide_translated_payload_info_lower_3;
      divide_translated_rData_info_upper_0 <= divide_translated_payload_info_upper_0;
      divide_translated_rData_info_upper_1 <= divide_translated_payload_info_upper_1;
      divide_translated_rData_info_upper_2 <= divide_translated_payload_info_upper_2;
      divide_translated_rData_info_upper_3 <= divide_translated_payload_info_upper_3;
      divide_translated_rData_whole_0 <= divide_translated_payload_whole_0;
      divide_translated_rData_whole_1 <= divide_translated_payload_whole_1;
      divide_translated_rData_whole_2 <= divide_translated_payload_whole_2;
      divide_translated_rData_whole_3 <= divide_translated_payload_whole_3;
      divide_translated_rData_increment <= divide_translated_payload_increment;
    end
    if(decision_translated_ready) begin
      decision_translated_rData_info_tag_pixel <= decision_translated_payload_info_tag_pixel;
      decision_translated_rData_info_tag_localPixel <= decision_translated_payload_info_tag_localPixel;
      decision_translated_rData_info_tag_group <= decision_translated_payload_info_tag_group;
      decision_translated_rData_info_tag_mask <= decision_translated_payload_info_tag_mask;
      decision_translated_rData_info_tag_first <= decision_translated_payload_info_tag_first;
      decision_translated_rData_info_tag_finalInput <= decision_translated_payload_info_tag_finalInput;
      decision_translated_rData_info_tag_tileLast <= decision_translated_payload_info_tag_tileLast;
      decision_translated_rData_info_tag_last <= decision_translated_payload_info_tag_last;
      decision_translated_rData_info_raw <= decision_translated_payload_info_raw;
      decision_translated_rData_info_int16 <= decision_translated_payload_info_int16;
      decision_translated_rData_info_shift <= decision_translated_payload_info_shift;
      decision_translated_rData_info_mac_0 <= decision_translated_payload_info_mac_0;
      decision_translated_rData_info_mac_1 <= decision_translated_payload_info_mac_1;
      decision_translated_rData_info_mac_2 <= decision_translated_payload_info_mac_2;
      decision_translated_rData_info_mac_3 <= decision_translated_payload_info_mac_3;
      decision_translated_rData_info_multiplier_0 <= decision_translated_payload_info_multiplier_0;
      decision_translated_rData_info_multiplier_1 <= decision_translated_payload_info_multiplier_1;
      decision_translated_rData_info_multiplier_2 <= decision_translated_payload_info_multiplier_2;
      decision_translated_rData_info_multiplier_3 <= decision_translated_payload_info_multiplier_3;
      decision_translated_rData_info_bias_0 <= decision_translated_payload_info_bias_0;
      decision_translated_rData_info_bias_1 <= decision_translated_payload_info_bias_1;
      decision_translated_rData_info_bias_2 <= decision_translated_payload_info_bias_2;
      decision_translated_rData_info_bias_3 <= decision_translated_payload_info_bias_3;
      decision_translated_rData_info_lower_0 <= decision_translated_payload_info_lower_0;
      decision_translated_rData_info_lower_1 <= decision_translated_payload_info_lower_1;
      decision_translated_rData_info_lower_2 <= decision_translated_payload_info_lower_2;
      decision_translated_rData_info_lower_3 <= decision_translated_payload_info_lower_3;
      decision_translated_rData_info_upper_0 <= decision_translated_payload_info_upper_0;
      decision_translated_rData_info_upper_1 <= decision_translated_payload_info_upper_1;
      decision_translated_rData_info_upper_2 <= decision_translated_payload_info_upper_2;
      decision_translated_rData_info_upper_3 <= decision_translated_payload_info_upper_3;
      decision_translated_rData_value_0 <= decision_translated_payload_value_0;
      decision_translated_rData_value_1 <= decision_translated_payload_value_1;
      decision_translated_rData_value_2 <= decision_translated_payload_value_2;
      decision_translated_rData_value_3 <= decision_translated_payload_value_3;
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
