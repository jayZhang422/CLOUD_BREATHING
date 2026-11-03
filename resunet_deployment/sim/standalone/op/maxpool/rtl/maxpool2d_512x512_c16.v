// Generator : SpinalHDL v1.12.3    git head : 591e64062329e5e2e2b81f4d52422948053edb97
// Component : MaxPool2d_512x512_c16
// Git hash  : 61491ca5e30687cffa35f30468de14ff9f05eb4c

`timescale 1ns/1ps

module MaxPool2d_512x512_c16 (
  input  wire          io_cfg_i_valid,
  output wire          io_cfg_i_ready,
  input  wire [9:0]    io_cfg_i_payload_width,
  input  wire [9:0]    io_cfg_i_payload_height,
  input  wire [5:0]    io_cfg_i_payload_groups,
  output wire          io_busy_o,
  output wire          io_done_o,
  input  wire          io_input_i_valid,
  output wire          io_input_i_ready,
  input  wire [127:0]  io_input_i_payload,
  output wire          io_output_o_valid,
  input  wire          io_output_o_ready,
  output wire          io_output_o_payload_last,
  output wire [127:0]  io_output_o_payload_fragment_data,
  output wire [5:0]    io_output_o_payload_fragment_group,
  output wire          io_output_o_payload_fragment_group_last,
  input  wire          clk,
  input  wire          resetn
);

  reg        [127:0]  topPairMem_spinal_port1;
  wire       [5:0]    _zz_lastGroup_w;
  wire       [127:0]  _zz_topPairMem_port;
  wire                _zz_topPairMem_port_1;
  wire       [9:0]    _zz_when_MaxPool2d_l105;
  wire       [9:0]    _zz_when_MaxPool2d_l107;
  reg        [9:0]    width_r;
  reg        [9:0]    height_r;
  reg        [5:0]    groups_r;
  reg        [9:0]    x_r;
  reg        [9:0]    y_r;
  reg        [5:0]    group_r;
  reg                 active_r;
  reg                 busy_r;
  reg                 outputDone_r;
  reg                 done_r;
  reg        [7:0]    leftPixel_r_0;
  reg        [7:0]    leftPixel_r_1;
  reg        [7:0]    leftPixel_r_2;
  reg        [7:0]    leftPixel_r_3;
  reg        [7:0]    leftPixel_r_4;
  reg        [7:0]    leftPixel_r_5;
  reg        [7:0]    leftPixel_r_6;
  reg        [7:0]    leftPixel_r_7;
  reg        [7:0]    leftPixel_r_8;
  reg        [7:0]    leftPixel_r_9;
  reg        [7:0]    leftPixel_r_10;
  reg        [7:0]    leftPixel_r_11;
  reg        [7:0]    leftPixel_r_12;
  reg        [7:0]    leftPixel_r_13;
  reg        [7:0]    leftPixel_r_14;
  reg        [7:0]    leftPixel_r_15;
  wire       [7:0]    pairMax_w_0;
  wire       [7:0]    pairMax_w_1;
  wire       [7:0]    pairMax_w_2;
  wire       [7:0]    pairMax_w_3;
  wire       [7:0]    pairMax_w_4;
  wire       [7:0]    pairMax_w_5;
  wire       [7:0]    pairMax_w_6;
  wire       [7:0]    pairMax_w_7;
  wire       [7:0]    pairMax_w_8;
  wire       [7:0]    pairMax_w_9;
  wire       [7:0]    pairMax_w_10;
  wire       [7:0]    pairMax_w_11;
  wire       [7:0]    pairMax_w_12;
  wire       [7:0]    pairMax_w_13;
  wire       [7:0]    pairMax_w_14;
  wire       [7:0]    pairMax_w_15;
  wire       [7:0]    _zz_leftPixel_r_0;
  wire                io_input_i_fire;
  wire                when_MaxPool2d_l59;
  wire       [7:0]    _zz_leftPixel_r_1;
  wire                when_MaxPool2d_l59_1;
  wire       [7:0]    _zz_leftPixel_r_2;
  wire                when_MaxPool2d_l59_2;
  wire       [7:0]    _zz_leftPixel_r_3;
  wire                when_MaxPool2d_l59_3;
  wire       [7:0]    _zz_leftPixel_r_4;
  wire                when_MaxPool2d_l59_4;
  wire       [7:0]    _zz_leftPixel_r_5;
  wire                when_MaxPool2d_l59_5;
  wire       [7:0]    _zz_leftPixel_r_6;
  wire                when_MaxPool2d_l59_6;
  wire       [7:0]    _zz_leftPixel_r_7;
  wire                when_MaxPool2d_l59_7;
  wire       [7:0]    _zz_leftPixel_r_8;
  wire                when_MaxPool2d_l59_8;
  wire       [7:0]    _zz_leftPixel_r_9;
  wire                when_MaxPool2d_l59_9;
  wire       [7:0]    _zz_leftPixel_r_10;
  wire                when_MaxPool2d_l59_10;
  wire       [7:0]    _zz_leftPixel_r_11;
  wire                when_MaxPool2d_l59_11;
  wire       [7:0]    _zz_leftPixel_r_12;
  wire                when_MaxPool2d_l59_12;
  wire       [7:0]    _zz_leftPixel_r_13;
  wire                when_MaxPool2d_l59_13;
  wire       [7:0]    _zz_leftPixel_r_14;
  wire                when_MaxPool2d_l59_14;
  wire       [7:0]    _zz_leftPixel_r_15;
  wire                when_MaxPool2d_l59_15;
  wire       [9:0]    outputEndX_w;
  wire       [9:0]    outputEndY_w;
  wire                lastGroup_w;
  wire                request_valid;
  reg                 request_ready;
  wire       [7:0]    request_payload_pair_0;
  wire       [7:0]    request_payload_pair_1;
  wire       [7:0]    request_payload_pair_2;
  wire       [7:0]    request_payload_pair_3;
  wire       [7:0]    request_payload_pair_4;
  wire       [7:0]    request_payload_pair_5;
  wire       [7:0]    request_payload_pair_6;
  wire       [7:0]    request_payload_pair_7;
  wire       [7:0]    request_payload_pair_8;
  wire       [7:0]    request_payload_pair_9;
  wire       [7:0]    request_payload_pair_10;
  wire       [7:0]    request_payload_pair_11;
  wire       [7:0]    request_payload_pair_12;
  wire       [7:0]    request_payload_pair_13;
  wire       [7:0]    request_payload_pair_14;
  wire       [7:0]    request_payload_pair_15;
  wire                request_payload_emit;
  wire       [5:0]    request_payload_group;
  wire                request_payload_group_last;
  wire                request_payload_last;
  wire       [7:0]    pairIndex_w;
  wire                request_fire;
  wire                _zz_topPair_w;
  wire       [127:0]  topPair_w;
  wire                response_valid;
  wire                response_ready;
  wire       [7:0]    response_payload_pair_0;
  wire       [7:0]    response_payload_pair_1;
  wire       [7:0]    response_payload_pair_2;
  wire       [7:0]    response_payload_pair_3;
  wire       [7:0]    response_payload_pair_4;
  wire       [7:0]    response_payload_pair_5;
  wire       [7:0]    response_payload_pair_6;
  wire       [7:0]    response_payload_pair_7;
  wire       [7:0]    response_payload_pair_8;
  wire       [7:0]    response_payload_pair_9;
  wire       [7:0]    response_payload_pair_10;
  wire       [7:0]    response_payload_pair_11;
  wire       [7:0]    response_payload_pair_12;
  wire       [7:0]    response_payload_pair_13;
  wire       [7:0]    response_payload_pair_14;
  wire       [7:0]    response_payload_pair_15;
  wire                response_payload_emit;
  wire       [5:0]    response_payload_group;
  wire                response_payload_group_last;
  wire                response_payload_last;
  reg                 request_rValid;
  reg        [7:0]    request_rData_pair_0;
  reg        [7:0]    request_rData_pair_1;
  reg        [7:0]    request_rData_pair_2;
  reg        [7:0]    request_rData_pair_3;
  reg        [7:0]    request_rData_pair_4;
  reg        [7:0]    request_rData_pair_5;
  reg        [7:0]    request_rData_pair_6;
  reg        [7:0]    request_rData_pair_7;
  reg        [7:0]    request_rData_pair_8;
  reg        [7:0]    request_rData_pair_9;
  reg        [7:0]    request_rData_pair_10;
  reg        [7:0]    request_rData_pair_11;
  reg        [7:0]    request_rData_pair_12;
  reg        [7:0]    request_rData_pair_13;
  reg        [7:0]    request_rData_pair_14;
  reg        [7:0]    request_rData_pair_15;
  reg                 request_rData_emit;
  reg        [5:0]    request_rData_group;
  reg                 request_rData_group_last;
  reg                 request_rData_last;
  wire                when_Stream_l477;
  wire                pooled_valid;
  reg                 pooled_ready;
  wire                pooled_payload_last;
  wire       [127:0]  pooled_payload_fragment_data;
  wire       [5:0]    pooled_payload_fragment_group;
  wire                pooled_payload_fragment_group_last;
  wire       [7:0]    pooledMax_w_0;
  wire       [7:0]    pooledMax_w_1;
  wire       [7:0]    pooledMax_w_2;
  wire       [7:0]    pooledMax_w_3;
  wire       [7:0]    pooledMax_w_4;
  wire       [7:0]    pooledMax_w_5;
  wire       [7:0]    pooledMax_w_6;
  wire       [7:0]    pooledMax_w_7;
  wire       [7:0]    pooledMax_w_8;
  wire       [7:0]    pooledMax_w_9;
  wire       [7:0]    pooledMax_w_10;
  wire       [7:0]    pooledMax_w_11;
  wire       [7:0]    pooledMax_w_12;
  wire       [7:0]    pooledMax_w_13;
  wire       [7:0]    pooledMax_w_14;
  wire       [7:0]    pooledMax_w_15;
  wire       [7:0]    _zz_pooledMax_w_0;
  wire       [7:0]    _zz_pooledMax_w_1;
  wire       [7:0]    _zz_pooledMax_w_2;
  wire       [7:0]    _zz_pooledMax_w_3;
  wire       [7:0]    _zz_pooledMax_w_4;
  wire       [7:0]    _zz_pooledMax_w_5;
  wire       [7:0]    _zz_pooledMax_w_6;
  wire       [7:0]    _zz_pooledMax_w_7;
  wire       [7:0]    _zz_pooledMax_w_8;
  wire       [7:0]    _zz_pooledMax_w_9;
  wire       [7:0]    _zz_pooledMax_w_10;
  wire       [7:0]    _zz_pooledMax_w_11;
  wire       [7:0]    _zz_pooledMax_w_12;
  wire       [7:0]    _zz_pooledMax_w_13;
  wire       [7:0]    _zz_pooledMax_w_14;
  wire       [7:0]    _zz_pooledMax_w_15;
  wire                pooled_m2sPipe_valid;
  wire                pooled_m2sPipe_ready;
  wire                pooled_m2sPipe_payload_last;
  wire       [127:0]  pooled_m2sPipe_payload_fragment_data;
  wire       [5:0]    pooled_m2sPipe_payload_fragment_group;
  wire                pooled_m2sPipe_payload_fragment_group_last;
  reg                 pooled_rValid;
  reg                 pooled_rData_last;
  reg        [127:0]  pooled_rData_fragment_data;
  reg        [5:0]    pooled_rData_fragment_group;
  reg                 pooled_rData_fragment_group_last;
  wire                when_Stream_l477_1;
  wire                when_MaxPool2d_l105;
  wire                when_MaxPool2d_l107;
  wire                io_output_o_fire;
  wire                when_MaxPool2d_l115;
  wire                when_MaxPool2d_l117;
  wire                io_cfg_i_fire;
  (* ram_style = "block" *) reg [127:0] topPairMem [0:255];

  assign _zz_lastGroup_w = (groups_r - 6'h01);
  assign _zz_when_MaxPool2d_l105 = (width_r - 10'h001);
  assign _zz_when_MaxPool2d_l107 = (height_r - 10'h001);
  assign _zz_topPairMem_port = {pairMax_w_15,{pairMax_w_14,{pairMax_w_13,{pairMax_w_12,{pairMax_w_11,{pairMax_w_10,{pairMax_w_9,{pairMax_w_8,{pairMax_w_7,{pairMax_w_6,{pairMax_w_5,{pairMax_w_4,{pairMax_w_3,{pairMax_w_2,{pairMax_w_1,pairMax_w_0}}}}}}}}}}}}}}};
  assign _zz_topPairMem_port_1 = ((request_fire && x_r[0]) && (! y_r[0]));
  always @(posedge clk) begin
    if(_zz_topPairMem_port_1) begin
      topPairMem[pairIndex_w] <= _zz_topPairMem_port;
    end
  end

  always @(posedge clk) begin
    if(_zz_topPair_w) begin
      topPairMem_spinal_port1 <= topPairMem[pairIndex_w];
    end
  end

  assign io_cfg_i_ready = (((((((! busy_r) && (10'h002 <= io_cfg_i_payload_width)) && (io_cfg_i_payload_width <= 10'h200)) && (10'h002 <= io_cfg_i_payload_height)) && (io_cfg_i_payload_height <= 10'h200)) && (io_cfg_i_payload_groups != 6'h0)) && (io_cfg_i_payload_groups <= 6'h20));
  assign io_busy_o = busy_r;
  assign io_done_o = done_r;
  assign _zz_leftPixel_r_0 = io_input_i_payload[7 : 0];
  assign pairMax_w_0 = (($signed(_zz_leftPixel_r_0) < $signed(leftPixel_r_0)) ? leftPixel_r_0 : _zz_leftPixel_r_0);
  assign io_input_i_fire = (io_input_i_valid && io_input_i_ready);
  assign when_MaxPool2d_l59 = (io_input_i_fire && (! x_r[0]));
  assign _zz_leftPixel_r_1 = io_input_i_payload[15 : 8];
  assign pairMax_w_1 = (($signed(_zz_leftPixel_r_1) < $signed(leftPixel_r_1)) ? leftPixel_r_1 : _zz_leftPixel_r_1);
  assign when_MaxPool2d_l59_1 = (io_input_i_fire && (! x_r[0]));
  assign _zz_leftPixel_r_2 = io_input_i_payload[23 : 16];
  assign pairMax_w_2 = (($signed(_zz_leftPixel_r_2) < $signed(leftPixel_r_2)) ? leftPixel_r_2 : _zz_leftPixel_r_2);
  assign when_MaxPool2d_l59_2 = (io_input_i_fire && (! x_r[0]));
  assign _zz_leftPixel_r_3 = io_input_i_payload[31 : 24];
  assign pairMax_w_3 = (($signed(_zz_leftPixel_r_3) < $signed(leftPixel_r_3)) ? leftPixel_r_3 : _zz_leftPixel_r_3);
  assign when_MaxPool2d_l59_3 = (io_input_i_fire && (! x_r[0]));
  assign _zz_leftPixel_r_4 = io_input_i_payload[39 : 32];
  assign pairMax_w_4 = (($signed(_zz_leftPixel_r_4) < $signed(leftPixel_r_4)) ? leftPixel_r_4 : _zz_leftPixel_r_4);
  assign when_MaxPool2d_l59_4 = (io_input_i_fire && (! x_r[0]));
  assign _zz_leftPixel_r_5 = io_input_i_payload[47 : 40];
  assign pairMax_w_5 = (($signed(_zz_leftPixel_r_5) < $signed(leftPixel_r_5)) ? leftPixel_r_5 : _zz_leftPixel_r_5);
  assign when_MaxPool2d_l59_5 = (io_input_i_fire && (! x_r[0]));
  assign _zz_leftPixel_r_6 = io_input_i_payload[55 : 48];
  assign pairMax_w_6 = (($signed(_zz_leftPixel_r_6) < $signed(leftPixel_r_6)) ? leftPixel_r_6 : _zz_leftPixel_r_6);
  assign when_MaxPool2d_l59_6 = (io_input_i_fire && (! x_r[0]));
  assign _zz_leftPixel_r_7 = io_input_i_payload[63 : 56];
  assign pairMax_w_7 = (($signed(_zz_leftPixel_r_7) < $signed(leftPixel_r_7)) ? leftPixel_r_7 : _zz_leftPixel_r_7);
  assign when_MaxPool2d_l59_7 = (io_input_i_fire && (! x_r[0]));
  assign _zz_leftPixel_r_8 = io_input_i_payload[71 : 64];
  assign pairMax_w_8 = (($signed(_zz_leftPixel_r_8) < $signed(leftPixel_r_8)) ? leftPixel_r_8 : _zz_leftPixel_r_8);
  assign when_MaxPool2d_l59_8 = (io_input_i_fire && (! x_r[0]));
  assign _zz_leftPixel_r_9 = io_input_i_payload[79 : 72];
  assign pairMax_w_9 = (($signed(_zz_leftPixel_r_9) < $signed(leftPixel_r_9)) ? leftPixel_r_9 : _zz_leftPixel_r_9);
  assign when_MaxPool2d_l59_9 = (io_input_i_fire && (! x_r[0]));
  assign _zz_leftPixel_r_10 = io_input_i_payload[87 : 80];
  assign pairMax_w_10 = (($signed(_zz_leftPixel_r_10) < $signed(leftPixel_r_10)) ? leftPixel_r_10 : _zz_leftPixel_r_10);
  assign when_MaxPool2d_l59_10 = (io_input_i_fire && (! x_r[0]));
  assign _zz_leftPixel_r_11 = io_input_i_payload[95 : 88];
  assign pairMax_w_11 = (($signed(_zz_leftPixel_r_11) < $signed(leftPixel_r_11)) ? leftPixel_r_11 : _zz_leftPixel_r_11);
  assign when_MaxPool2d_l59_11 = (io_input_i_fire && (! x_r[0]));
  assign _zz_leftPixel_r_12 = io_input_i_payload[103 : 96];
  assign pairMax_w_12 = (($signed(_zz_leftPixel_r_12) < $signed(leftPixel_r_12)) ? leftPixel_r_12 : _zz_leftPixel_r_12);
  assign when_MaxPool2d_l59_12 = (io_input_i_fire && (! x_r[0]));
  assign _zz_leftPixel_r_13 = io_input_i_payload[111 : 104];
  assign pairMax_w_13 = (($signed(_zz_leftPixel_r_13) < $signed(leftPixel_r_13)) ? leftPixel_r_13 : _zz_leftPixel_r_13);
  assign when_MaxPool2d_l59_13 = (io_input_i_fire && (! x_r[0]));
  assign _zz_leftPixel_r_14 = io_input_i_payload[119 : 112];
  assign pairMax_w_14 = (($signed(_zz_leftPixel_r_14) < $signed(leftPixel_r_14)) ? leftPixel_r_14 : _zz_leftPixel_r_14);
  assign when_MaxPool2d_l59_14 = (io_input_i_fire && (! x_r[0]));
  assign _zz_leftPixel_r_15 = io_input_i_payload[127 : 120];
  assign pairMax_w_15 = (($signed(_zz_leftPixel_r_15) < $signed(leftPixel_r_15)) ? leftPixel_r_15 : _zz_leftPixel_r_15);
  assign when_MaxPool2d_l59_15 = (io_input_i_fire && (! x_r[0]));
  assign outputEndX_w = (width_r - (width_r[0] ? 10'h002 : 10'h001));
  assign outputEndY_w = (height_r - (height_r[0] ? 10'h002 : 10'h001));
  assign lastGroup_w = (group_r == _zz_lastGroup_w);
  assign request_valid = (active_r && io_input_i_valid);
  assign request_payload_pair_0 = pairMax_w_0;
  assign request_payload_pair_1 = pairMax_w_1;
  assign request_payload_pair_2 = pairMax_w_2;
  assign request_payload_pair_3 = pairMax_w_3;
  assign request_payload_pair_4 = pairMax_w_4;
  assign request_payload_pair_5 = pairMax_w_5;
  assign request_payload_pair_6 = pairMax_w_6;
  assign request_payload_pair_7 = pairMax_w_7;
  assign request_payload_pair_8 = pairMax_w_8;
  assign request_payload_pair_9 = pairMax_w_9;
  assign request_payload_pair_10 = pairMax_w_10;
  assign request_payload_pair_11 = pairMax_w_11;
  assign request_payload_pair_12 = pairMax_w_12;
  assign request_payload_pair_13 = pairMax_w_13;
  assign request_payload_pair_14 = pairMax_w_14;
  assign request_payload_pair_15 = pairMax_w_15;
  assign request_payload_emit = (x_r[0] && y_r[0]);
  assign request_payload_group = group_r;
  assign request_payload_group_last = ((x_r == outputEndX_w) && (y_r == outputEndY_w));
  assign request_payload_last = (request_payload_group_last && lastGroup_w);
  assign io_input_i_ready = (active_r && request_ready);
  assign pairIndex_w = x_r[8 : 1];
  assign request_fire = (request_valid && request_ready);
  assign _zz_topPair_w = (request_fire && request_payload_emit);
  assign topPair_w = topPairMem_spinal_port1;
  always @(*) begin
    request_ready = response_ready;
    if(when_Stream_l477) begin
      request_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! response_valid);
  assign response_valid = request_rValid;
  assign response_payload_pair_0 = request_rData_pair_0;
  assign response_payload_pair_1 = request_rData_pair_1;
  assign response_payload_pair_2 = request_rData_pair_2;
  assign response_payload_pair_3 = request_rData_pair_3;
  assign response_payload_pair_4 = request_rData_pair_4;
  assign response_payload_pair_5 = request_rData_pair_5;
  assign response_payload_pair_6 = request_rData_pair_6;
  assign response_payload_pair_7 = request_rData_pair_7;
  assign response_payload_pair_8 = request_rData_pair_8;
  assign response_payload_pair_9 = request_rData_pair_9;
  assign response_payload_pair_10 = request_rData_pair_10;
  assign response_payload_pair_11 = request_rData_pair_11;
  assign response_payload_pair_12 = request_rData_pair_12;
  assign response_payload_pair_13 = request_rData_pair_13;
  assign response_payload_pair_14 = request_rData_pair_14;
  assign response_payload_pair_15 = request_rData_pair_15;
  assign response_payload_emit = request_rData_emit;
  assign response_payload_group = request_rData_group;
  assign response_payload_group_last = request_rData_group_last;
  assign response_payload_last = request_rData_last;
  assign _zz_pooledMax_w_0 = topPair_w[7 : 0];
  assign pooledMax_w_0 = (($signed(response_payload_pair_0) < $signed(_zz_pooledMax_w_0)) ? _zz_pooledMax_w_0 : response_payload_pair_0);
  assign _zz_pooledMax_w_1 = topPair_w[15 : 8];
  assign pooledMax_w_1 = (($signed(response_payload_pair_1) < $signed(_zz_pooledMax_w_1)) ? _zz_pooledMax_w_1 : response_payload_pair_1);
  assign _zz_pooledMax_w_2 = topPair_w[23 : 16];
  assign pooledMax_w_2 = (($signed(response_payload_pair_2) < $signed(_zz_pooledMax_w_2)) ? _zz_pooledMax_w_2 : response_payload_pair_2);
  assign _zz_pooledMax_w_3 = topPair_w[31 : 24];
  assign pooledMax_w_3 = (($signed(response_payload_pair_3) < $signed(_zz_pooledMax_w_3)) ? _zz_pooledMax_w_3 : response_payload_pair_3);
  assign _zz_pooledMax_w_4 = topPair_w[39 : 32];
  assign pooledMax_w_4 = (($signed(response_payload_pair_4) < $signed(_zz_pooledMax_w_4)) ? _zz_pooledMax_w_4 : response_payload_pair_4);
  assign _zz_pooledMax_w_5 = topPair_w[47 : 40];
  assign pooledMax_w_5 = (($signed(response_payload_pair_5) < $signed(_zz_pooledMax_w_5)) ? _zz_pooledMax_w_5 : response_payload_pair_5);
  assign _zz_pooledMax_w_6 = topPair_w[55 : 48];
  assign pooledMax_w_6 = (($signed(response_payload_pair_6) < $signed(_zz_pooledMax_w_6)) ? _zz_pooledMax_w_6 : response_payload_pair_6);
  assign _zz_pooledMax_w_7 = topPair_w[63 : 56];
  assign pooledMax_w_7 = (($signed(response_payload_pair_7) < $signed(_zz_pooledMax_w_7)) ? _zz_pooledMax_w_7 : response_payload_pair_7);
  assign _zz_pooledMax_w_8 = topPair_w[71 : 64];
  assign pooledMax_w_8 = (($signed(response_payload_pair_8) < $signed(_zz_pooledMax_w_8)) ? _zz_pooledMax_w_8 : response_payload_pair_8);
  assign _zz_pooledMax_w_9 = topPair_w[79 : 72];
  assign pooledMax_w_9 = (($signed(response_payload_pair_9) < $signed(_zz_pooledMax_w_9)) ? _zz_pooledMax_w_9 : response_payload_pair_9);
  assign _zz_pooledMax_w_10 = topPair_w[87 : 80];
  assign pooledMax_w_10 = (($signed(response_payload_pair_10) < $signed(_zz_pooledMax_w_10)) ? _zz_pooledMax_w_10 : response_payload_pair_10);
  assign _zz_pooledMax_w_11 = topPair_w[95 : 88];
  assign pooledMax_w_11 = (($signed(response_payload_pair_11) < $signed(_zz_pooledMax_w_11)) ? _zz_pooledMax_w_11 : response_payload_pair_11);
  assign _zz_pooledMax_w_12 = topPair_w[103 : 96];
  assign pooledMax_w_12 = (($signed(response_payload_pair_12) < $signed(_zz_pooledMax_w_12)) ? _zz_pooledMax_w_12 : response_payload_pair_12);
  assign _zz_pooledMax_w_13 = topPair_w[111 : 104];
  assign pooledMax_w_13 = (($signed(response_payload_pair_13) < $signed(_zz_pooledMax_w_13)) ? _zz_pooledMax_w_13 : response_payload_pair_13);
  assign _zz_pooledMax_w_14 = topPair_w[119 : 112];
  assign pooledMax_w_14 = (($signed(response_payload_pair_14) < $signed(_zz_pooledMax_w_14)) ? _zz_pooledMax_w_14 : response_payload_pair_14);
  assign _zz_pooledMax_w_15 = topPair_w[127 : 120];
  assign pooledMax_w_15 = (($signed(response_payload_pair_15) < $signed(_zz_pooledMax_w_15)) ? _zz_pooledMax_w_15 : response_payload_pair_15);
  assign pooled_valid = (response_valid && response_payload_emit);
  assign pooled_payload_fragment_data = {pooledMax_w_15,{pooledMax_w_14,{pooledMax_w_13,{pooledMax_w_12,{pooledMax_w_11,{pooledMax_w_10,{pooledMax_w_9,{pooledMax_w_8,{pooledMax_w_7,{pooledMax_w_6,{pooledMax_w_5,{pooledMax_w_4,{pooledMax_w_3,{pooledMax_w_2,{pooledMax_w_1,pooledMax_w_0}}}}}}}}}}}}}}};
  assign pooled_payload_fragment_group = response_payload_group;
  assign pooled_payload_fragment_group_last = response_payload_group_last;
  assign pooled_payload_last = response_payload_last;
  assign response_ready = ((! response_payload_emit) || pooled_ready);
  always @(*) begin
    pooled_ready = pooled_m2sPipe_ready;
    if(when_Stream_l477_1) begin
      pooled_ready = 1'b1;
    end
  end

  assign when_Stream_l477_1 = (! pooled_m2sPipe_valid);
  assign pooled_m2sPipe_valid = pooled_rValid;
  assign pooled_m2sPipe_payload_last = pooled_rData_last;
  assign pooled_m2sPipe_payload_fragment_data = pooled_rData_fragment_data;
  assign pooled_m2sPipe_payload_fragment_group = pooled_rData_fragment_group;
  assign pooled_m2sPipe_payload_fragment_group_last = pooled_rData_fragment_group_last;
  assign io_output_o_valid = pooled_m2sPipe_valid;
  assign pooled_m2sPipe_ready = io_output_o_ready;
  assign io_output_o_payload_last = pooled_m2sPipe_payload_last;
  assign io_output_o_payload_fragment_data = pooled_m2sPipe_payload_fragment_data;
  assign io_output_o_payload_fragment_group = pooled_m2sPipe_payload_fragment_group;
  assign io_output_o_payload_fragment_group_last = pooled_m2sPipe_payload_fragment_group_last;
  assign when_MaxPool2d_l105 = (x_r == _zz_when_MaxPool2d_l105);
  assign when_MaxPool2d_l107 = (y_r == _zz_when_MaxPool2d_l107);
  assign io_output_o_fire = (io_output_o_valid && io_output_o_ready);
  assign when_MaxPool2d_l115 = (io_output_o_fire && io_output_o_payload_last);
  assign when_MaxPool2d_l117 = ((busy_r && (! active_r)) && outputDone_r);
  assign io_cfg_i_fire = (io_cfg_i_valid && io_cfg_i_ready);
  always @(posedge clk or negedge resetn) begin
    if(!resetn) begin
      width_r <= 10'h0;
      height_r <= 10'h0;
      groups_r <= 6'h0;
      x_r <= 10'h0;
      y_r <= 10'h0;
      group_r <= 6'h0;
      active_r <= 1'b0;
      busy_r <= 1'b0;
      outputDone_r <= 1'b0;
      done_r <= 1'b0;
      request_rValid <= 1'b0;
      pooled_rValid <= 1'b0;
    end else begin
      done_r <= 1'b0;
      if(request_ready) begin
        request_rValid <= request_valid;
      end
      if(pooled_ready) begin
        pooled_rValid <= pooled_valid;
      end
      if(request_fire) begin
        if(when_MaxPool2d_l105) begin
          x_r <= 10'h0;
          if(when_MaxPool2d_l107) begin
            y_r <= 10'h0;
            if(lastGroup_w) begin
              active_r <= 1'b0;
            end else begin
              group_r <= (group_r + 6'h01);
            end
          end else begin
            y_r <= (y_r + 10'h001);
          end
        end else begin
          x_r <= (x_r + 10'h001);
        end
      end
      if(when_MaxPool2d_l115) begin
        outputDone_r <= 1'b1;
      end
      if(when_MaxPool2d_l117) begin
        busy_r <= 1'b0;
        done_r <= 1'b1;
      end
      if(io_cfg_i_fire) begin
        width_r <= io_cfg_i_payload_width;
        height_r <= io_cfg_i_payload_height;
        groups_r <= io_cfg_i_payload_groups;
        x_r <= 10'h0;
        y_r <= 10'h0;
        group_r <= 6'h0;
        active_r <= 1'b1;
        busy_r <= 1'b1;
        outputDone_r <= 1'b0;
      end
    end
  end

  always @(posedge clk) begin
    if(when_MaxPool2d_l59) begin
      leftPixel_r_0 <= _zz_leftPixel_r_0;
    end
    if(when_MaxPool2d_l59_1) begin
      leftPixel_r_1 <= _zz_leftPixel_r_1;
    end
    if(when_MaxPool2d_l59_2) begin
      leftPixel_r_2 <= _zz_leftPixel_r_2;
    end
    if(when_MaxPool2d_l59_3) begin
      leftPixel_r_3 <= _zz_leftPixel_r_3;
    end
    if(when_MaxPool2d_l59_4) begin
      leftPixel_r_4 <= _zz_leftPixel_r_4;
    end
    if(when_MaxPool2d_l59_5) begin
      leftPixel_r_5 <= _zz_leftPixel_r_5;
    end
    if(when_MaxPool2d_l59_6) begin
      leftPixel_r_6 <= _zz_leftPixel_r_6;
    end
    if(when_MaxPool2d_l59_7) begin
      leftPixel_r_7 <= _zz_leftPixel_r_7;
    end
    if(when_MaxPool2d_l59_8) begin
      leftPixel_r_8 <= _zz_leftPixel_r_8;
    end
    if(when_MaxPool2d_l59_9) begin
      leftPixel_r_9 <= _zz_leftPixel_r_9;
    end
    if(when_MaxPool2d_l59_10) begin
      leftPixel_r_10 <= _zz_leftPixel_r_10;
    end
    if(when_MaxPool2d_l59_11) begin
      leftPixel_r_11 <= _zz_leftPixel_r_11;
    end
    if(when_MaxPool2d_l59_12) begin
      leftPixel_r_12 <= _zz_leftPixel_r_12;
    end
    if(when_MaxPool2d_l59_13) begin
      leftPixel_r_13 <= _zz_leftPixel_r_13;
    end
    if(when_MaxPool2d_l59_14) begin
      leftPixel_r_14 <= _zz_leftPixel_r_14;
    end
    if(when_MaxPool2d_l59_15) begin
      leftPixel_r_15 <= _zz_leftPixel_r_15;
    end
    if(request_ready) begin
      request_rData_pair_0 <= request_payload_pair_0;
      request_rData_pair_1 <= request_payload_pair_1;
      request_rData_pair_2 <= request_payload_pair_2;
      request_rData_pair_3 <= request_payload_pair_3;
      request_rData_pair_4 <= request_payload_pair_4;
      request_rData_pair_5 <= request_payload_pair_5;
      request_rData_pair_6 <= request_payload_pair_6;
      request_rData_pair_7 <= request_payload_pair_7;
      request_rData_pair_8 <= request_payload_pair_8;
      request_rData_pair_9 <= request_payload_pair_9;
      request_rData_pair_10 <= request_payload_pair_10;
      request_rData_pair_11 <= request_payload_pair_11;
      request_rData_pair_12 <= request_payload_pair_12;
      request_rData_pair_13 <= request_payload_pair_13;
      request_rData_pair_14 <= request_payload_pair_14;
      request_rData_pair_15 <= request_payload_pair_15;
      request_rData_emit <= request_payload_emit;
      request_rData_group <= request_payload_group;
      request_rData_group_last <= request_payload_group_last;
      request_rData_last <= request_payload_last;
    end
    if(pooled_ready) begin
      pooled_rData_last <= pooled_payload_last;
      pooled_rData_fragment_data <= pooled_payload_fragment_data;
      pooled_rData_fragment_group <= pooled_payload_fragment_group;
      pooled_rData_fragment_group_last <= pooled_payload_fragment_group_last;
    end
  end


endmodule
