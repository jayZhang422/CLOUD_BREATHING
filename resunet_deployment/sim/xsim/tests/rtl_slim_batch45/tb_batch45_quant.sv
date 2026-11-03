`timescale 1ns/1ps
module batch45_pw_quant(output logic finished_o);
logic io_input_i_valid;
logic io_input_i_ready;
logic [18:0] io_input_i_payload_tag_pixel;
logic [3:0] io_input_i_payload_tag_localPixel;
logic [6:0] io_input_i_payload_tag_group;
logic [3:0] io_input_i_payload_tag_mask;
logic io_input_i_payload_tag_first;
logic io_input_i_payload_tag_finalInput;
logic io_input_i_payload_tag_tileLast;
logic io_input_i_payload_tag_last;
logic io_input_i_payload_raw;
logic io_input_i_payload_int16;
logic [5:0] io_input_i_payload_shift;
logic [31:0] io_input_i_payload_mac_0;
logic [31:0] io_input_i_payload_mac_1;
logic [31:0] io_input_i_payload_mac_2;
logic [31:0] io_input_i_payload_mac_3;
logic [31:0] io_input_i_payload_multiplier_0;
logic [31:0] io_input_i_payload_multiplier_1;
logic [31:0] io_input_i_payload_multiplier_2;
logic [31:0] io_input_i_payload_multiplier_3;
logic [63:0] io_input_i_payload_bias_0;
logic [63:0] io_input_i_payload_bias_1;
logic [63:0] io_input_i_payload_bias_2;
logic [63:0] io_input_i_payload_bias_3;
logic [15:0] io_input_i_payload_lower_0;
logic [15:0] io_input_i_payload_lower_1;
logic [15:0] io_input_i_payload_lower_2;
logic [15:0] io_input_i_payload_lower_3;
logic [15:0] io_input_i_payload_upper_0;
logic [15:0] io_input_i_payload_upper_1;
logic [15:0] io_input_i_payload_upper_2;
logic [15:0] io_input_i_payload_upper_3;
logic io_output_o_valid;
logic io_output_o_ready;
logic [18:0] io_output_o_payload_pixel;
logic [6:0] io_output_o_payload_group;
logic [3:0] io_output_o_payload_mask;
logic io_output_o_payload_last;
logic io_output_o_payload_raw;
logic io_output_o_payload_int16;
logic [31:0] io_output_o_payload_mac_0;
logic [31:0] io_output_o_payload_mac_1;
logic [31:0] io_output_o_payload_mac_2;
logic [31:0] io_output_o_payload_mac_3;
logic [15:0] io_output_o_payload_q_0;
logic [15:0] io_output_o_payload_q_1;
logic [15:0] io_output_o_payload_q_2;
logic [15:0] io_output_o_payload_q_3;
logic clk;
logic resetn;
PwSharedRequant dut (
.io_input_i_valid(io_input_i_valid),
.io_input_i_ready(io_input_i_ready),
.io_input_i_payload_tag_pixel(io_input_i_payload_tag_pixel),
.io_input_i_payload_tag_localPixel(io_input_i_payload_tag_localPixel),
.io_input_i_payload_tag_group(io_input_i_payload_tag_group),
.io_input_i_payload_tag_mask(io_input_i_payload_tag_mask),
.io_input_i_payload_tag_first(io_input_i_payload_tag_first),
.io_input_i_payload_tag_finalInput(io_input_i_payload_tag_finalInput),
.io_input_i_payload_tag_tileLast(io_input_i_payload_tag_tileLast),
.io_input_i_payload_tag_last(io_input_i_payload_tag_last),
.io_input_i_payload_raw(io_input_i_payload_raw),
.io_input_i_payload_int16(io_input_i_payload_int16),
.io_input_i_payload_shift(io_input_i_payload_shift),
.io_input_i_payload_mac_0(io_input_i_payload_mac_0),
.io_input_i_payload_mac_1(io_input_i_payload_mac_1),
.io_input_i_payload_mac_2(io_input_i_payload_mac_2),
.io_input_i_payload_mac_3(io_input_i_payload_mac_3),
.io_input_i_payload_multiplier_0(io_input_i_payload_multiplier_0),
.io_input_i_payload_multiplier_1(io_input_i_payload_multiplier_1),
.io_input_i_payload_multiplier_2(io_input_i_payload_multiplier_2),
.io_input_i_payload_multiplier_3(io_input_i_payload_multiplier_3),
.io_input_i_payload_bias_0(io_input_i_payload_bias_0),
.io_input_i_payload_bias_1(io_input_i_payload_bias_1),
.io_input_i_payload_bias_2(io_input_i_payload_bias_2),
.io_input_i_payload_bias_3(io_input_i_payload_bias_3),
.io_input_i_payload_lower_0(io_input_i_payload_lower_0),
.io_input_i_payload_lower_1(io_input_i_payload_lower_1),
.io_input_i_payload_lower_2(io_input_i_payload_lower_2),
.io_input_i_payload_lower_3(io_input_i_payload_lower_3),
.io_input_i_payload_upper_0(io_input_i_payload_upper_0),
.io_input_i_payload_upper_1(io_input_i_payload_upper_1),
.io_input_i_payload_upper_2(io_input_i_payload_upper_2),
.io_input_i_payload_upper_3(io_input_i_payload_upper_3),
.io_output_o_valid(io_output_o_valid),
.io_output_o_ready(io_output_o_ready),
.io_output_o_payload_pixel(io_output_o_payload_pixel),
.io_output_o_payload_group(io_output_o_payload_group),
.io_output_o_payload_mask(io_output_o_payload_mask),
.io_output_o_payload_last(io_output_o_payload_last),
.io_output_o_payload_raw(io_output_o_payload_raw),
.io_output_o_payload_int16(io_output_o_payload_int16),
.io_output_o_payload_mac_0(io_output_o_payload_mac_0),
.io_output_o_payload_mac_1(io_output_o_payload_mac_1),
.io_output_o_payload_mac_2(io_output_o_payload_mac_2),
.io_output_o_payload_mac_3(io_output_o_payload_mac_3),
.io_output_o_payload_q_0(io_output_o_payload_q_0),
.io_output_o_payload_q_1(io_output_o_payload_q_1),
.io_output_o_payload_q_2(io_output_o_payload_q_2),
.io_output_o_payload_q_3(io_output_o_payload_q_3),
.clk(clk),
.resetn(resetn)
);

logic [685:0] stimulus[0:8191];
logic [224:0] golden[0:8191];
wire [224:0] actual={io_output_o_payload_pixel,io_output_o_payload_group,io_output_o_payload_mask,io_output_o_payload_last,io_output_o_payload_raw,io_output_o_payload_int16,io_output_o_payload_mac_0,io_output_o_payload_mac_1,io_output_o_payload_mac_2,io_output_o_payload_mac_3,io_output_o_payload_q_0,io_output_o_payload_q_1,io_output_o_payload_q_2,io_output_o_payload_q_3};
logic [224:0] held;
logic stalled=1'b0;
integer sent=0, got=0, cycle=0, csv;
always #4 clk=~clk;
always @(negedge clk) begin
  io_output_o_ready=resetn && cycle%13>=4;
end
always @(posedge clk) begin
  cycle=cycle+1;
  if(resetn) begin
    if(stalled && (!io_output_o_valid || actual !== held)) begin $error("PW quant payload changed cycle=%0d",cycle);$fflush(csv);$stop;end
    stalled=io_output_o_valid && !io_output_o_ready;held=actual;
    if(io_input_i_valid && io_input_i_ready)sent=sent+1;
    if(io_output_o_valid && io_output_o_ready)begin
      if(got>=8192 || actual !== golden[got])begin $error("PW quant Golden index=%0d actual=%h expected=%h",got,actual,golden[got]);$fflush(csv);$stop;end
      got=got+1;
    end
  end
  if(!finished_o)$fdisplay(csv,"%0d,%b,%b,%b,%b,%h,%0d",cycle,io_input_i_valid,io_input_i_ready,io_output_o_valid,io_output_o_ready,actual,got);
end
initial begin
  clk=0;resetn=0;finished_o=0;io_input_i_valid=0;io_output_o_ready=0;
  csv=$fopen("sim_trace_pw_quant.csv","w");
  $fdisplay(csv,"cycle,in_valid,in_ready,out_valid,out_ready,payload,got");
  $readmemh("sim/xsim/tests/rtl_slim_batch45/pw_quant_stimulus.hex",stimulus);
  $readmemh("sim/xsim/tests/rtl_slim_batch45/pw_quant_golden.hex",golden);
  repeat(6)@(negedge clk);resetn=1;
  for(int n=0;n<8192;n++)begin
    @(negedge clk);io_input_i_valid=1;{io_input_i_payload_tag_pixel,io_input_i_payload_tag_localPixel,io_input_i_payload_tag_group,io_input_i_payload_tag_mask,io_input_i_payload_tag_first,io_input_i_payload_tag_finalInput,io_input_i_payload_tag_tileLast,io_input_i_payload_tag_last,io_input_i_payload_raw,io_input_i_payload_int16,io_input_i_payload_shift,io_input_i_payload_mac_0,io_input_i_payload_mac_1,io_input_i_payload_mac_2,io_input_i_payload_mac_3,io_input_i_payload_multiplier_0,io_input_i_payload_multiplier_1,io_input_i_payload_multiplier_2,io_input_i_payload_multiplier_3,io_input_i_payload_bias_0,io_input_i_payload_bias_1,io_input_i_payload_bias_2,io_input_i_payload_bias_3,io_input_i_payload_lower_0,io_input_i_payload_lower_1,io_input_i_payload_lower_2,io_input_i_payload_lower_3,io_input_i_payload_upper_0,io_input_i_payload_upper_1,io_input_i_payload_upper_2,io_input_i_payload_upper_3}=stimulus[n];
    do @(posedge clk);while(io_input_i_ready !== 1'b1);
    @(negedge clk);io_input_i_valid=0;
  end
  wait(got==8192);@(negedge clk);finished_o=1;$fclose(csv);
  $display("[CASE PASS] PW quant 8192 vectors shift0..63 negative ties INT64 wrap saturation mask raw");
end
endmodule
module batch45_add_quant(output logic finished_o);
logic io_cfg_i_valid;
logic io_cfg_i_ready;
logic [18:0] io_cfg_i_payload_words;
logic [5:0] io_cfg_i_payload_group;
logic io_cfg_i_payload_last_group;
logic [21:0] io_cfg_i_payload_multiplier_a_0;
logic [21:0] io_cfg_i_payload_multiplier_a_1;
logic [21:0] io_cfg_i_payload_multiplier_a_2;
logic [21:0] io_cfg_i_payload_multiplier_a_3;
logic [21:0] io_cfg_i_payload_multiplier_a_4;
logic [21:0] io_cfg_i_payload_multiplier_a_5;
logic [21:0] io_cfg_i_payload_multiplier_a_6;
logic [21:0] io_cfg_i_payload_multiplier_a_7;
logic [21:0] io_cfg_i_payload_multiplier_a_8;
logic [21:0] io_cfg_i_payload_multiplier_a_9;
logic [21:0] io_cfg_i_payload_multiplier_a_10;
logic [21:0] io_cfg_i_payload_multiplier_a_11;
logic [21:0] io_cfg_i_payload_multiplier_a_12;
logic [21:0] io_cfg_i_payload_multiplier_a_13;
logic [21:0] io_cfg_i_payload_multiplier_a_14;
logic [21:0] io_cfg_i_payload_multiplier_a_15;
logic [21:0] io_cfg_i_payload_multiplier_b_0;
logic [21:0] io_cfg_i_payload_multiplier_b_1;
logic [21:0] io_cfg_i_payload_multiplier_b_2;
logic [21:0] io_cfg_i_payload_multiplier_b_3;
logic [21:0] io_cfg_i_payload_multiplier_b_4;
logic [21:0] io_cfg_i_payload_multiplier_b_5;
logic [21:0] io_cfg_i_payload_multiplier_b_6;
logic [21:0] io_cfg_i_payload_multiplier_b_7;
logic [21:0] io_cfg_i_payload_multiplier_b_8;
logic [21:0] io_cfg_i_payload_multiplier_b_9;
logic [21:0] io_cfg_i_payload_multiplier_b_10;
logic [21:0] io_cfg_i_payload_multiplier_b_11;
logic [21:0] io_cfg_i_payload_multiplier_b_12;
logic [21:0] io_cfg_i_payload_multiplier_b_13;
logic [21:0] io_cfg_i_payload_multiplier_b_14;
logic [21:0] io_cfg_i_payload_multiplier_b_15;
logic [63:0] io_cfg_i_payload_bias_fixed_0;
logic [63:0] io_cfg_i_payload_bias_fixed_1;
logic [63:0] io_cfg_i_payload_bias_fixed_2;
logic [63:0] io_cfg_i_payload_bias_fixed_3;
logic [63:0] io_cfg_i_payload_bias_fixed_4;
logic [63:0] io_cfg_i_payload_bias_fixed_5;
logic [63:0] io_cfg_i_payload_bias_fixed_6;
logic [63:0] io_cfg_i_payload_bias_fixed_7;
logic [63:0] io_cfg_i_payload_bias_fixed_8;
logic [63:0] io_cfg_i_payload_bias_fixed_9;
logic [63:0] io_cfg_i_payload_bias_fixed_10;
logic [63:0] io_cfg_i_payload_bias_fixed_11;
logic [63:0] io_cfg_i_payload_bias_fixed_12;
logic [63:0] io_cfg_i_payload_bias_fixed_13;
logic [63:0] io_cfg_i_payload_bias_fixed_14;
logic [63:0] io_cfg_i_payload_bias_fixed_15;
logic [5:0] io_cfg_i_payload_shift;
logic [7:0] io_cfg_i_payload_clamp_min;
logic [7:0] io_cfg_i_payload_clamp_max;
logic io_busy_o;
logic io_done_o;
logic io_a_i_valid;
logic io_a_i_ready;
logic [511:0] io_a_i_payload;
logic io_b_i_valid;
logic io_b_i_ready;
logic [511:0] io_b_i_payload;
logic io_output_o_valid;
logic io_output_o_ready;
logic io_output_o_payload_last;
logic [127:0] io_output_o_payload_fragment_data;
logic [5:0] io_output_o_payload_fragment_group;
logic io_output_o_payload_fragment_group_last;
logic clk;
logic resetn;
ElementAdd_p16 dut (
.io_cfg_i_valid(io_cfg_i_valid),
.io_cfg_i_ready(io_cfg_i_ready),
.io_cfg_i_payload_words(io_cfg_i_payload_words),
.io_cfg_i_payload_group(io_cfg_i_payload_group),
.io_cfg_i_payload_last_group(io_cfg_i_payload_last_group),
.io_cfg_i_payload_multiplier_a_0(io_cfg_i_payload_multiplier_a_0),
.io_cfg_i_payload_multiplier_a_1(io_cfg_i_payload_multiplier_a_1),
.io_cfg_i_payload_multiplier_a_2(io_cfg_i_payload_multiplier_a_2),
.io_cfg_i_payload_multiplier_a_3(io_cfg_i_payload_multiplier_a_3),
.io_cfg_i_payload_multiplier_a_4(io_cfg_i_payload_multiplier_a_4),
.io_cfg_i_payload_multiplier_a_5(io_cfg_i_payload_multiplier_a_5),
.io_cfg_i_payload_multiplier_a_6(io_cfg_i_payload_multiplier_a_6),
.io_cfg_i_payload_multiplier_a_7(io_cfg_i_payload_multiplier_a_7),
.io_cfg_i_payload_multiplier_a_8(io_cfg_i_payload_multiplier_a_8),
.io_cfg_i_payload_multiplier_a_9(io_cfg_i_payload_multiplier_a_9),
.io_cfg_i_payload_multiplier_a_10(io_cfg_i_payload_multiplier_a_10),
.io_cfg_i_payload_multiplier_a_11(io_cfg_i_payload_multiplier_a_11),
.io_cfg_i_payload_multiplier_a_12(io_cfg_i_payload_multiplier_a_12),
.io_cfg_i_payload_multiplier_a_13(io_cfg_i_payload_multiplier_a_13),
.io_cfg_i_payload_multiplier_a_14(io_cfg_i_payload_multiplier_a_14),
.io_cfg_i_payload_multiplier_a_15(io_cfg_i_payload_multiplier_a_15),
.io_cfg_i_payload_multiplier_b_0(io_cfg_i_payload_multiplier_b_0),
.io_cfg_i_payload_multiplier_b_1(io_cfg_i_payload_multiplier_b_1),
.io_cfg_i_payload_multiplier_b_2(io_cfg_i_payload_multiplier_b_2),
.io_cfg_i_payload_multiplier_b_3(io_cfg_i_payload_multiplier_b_3),
.io_cfg_i_payload_multiplier_b_4(io_cfg_i_payload_multiplier_b_4),
.io_cfg_i_payload_multiplier_b_5(io_cfg_i_payload_multiplier_b_5),
.io_cfg_i_payload_multiplier_b_6(io_cfg_i_payload_multiplier_b_6),
.io_cfg_i_payload_multiplier_b_7(io_cfg_i_payload_multiplier_b_7),
.io_cfg_i_payload_multiplier_b_8(io_cfg_i_payload_multiplier_b_8),
.io_cfg_i_payload_multiplier_b_9(io_cfg_i_payload_multiplier_b_9),
.io_cfg_i_payload_multiplier_b_10(io_cfg_i_payload_multiplier_b_10),
.io_cfg_i_payload_multiplier_b_11(io_cfg_i_payload_multiplier_b_11),
.io_cfg_i_payload_multiplier_b_12(io_cfg_i_payload_multiplier_b_12),
.io_cfg_i_payload_multiplier_b_13(io_cfg_i_payload_multiplier_b_13),
.io_cfg_i_payload_multiplier_b_14(io_cfg_i_payload_multiplier_b_14),
.io_cfg_i_payload_multiplier_b_15(io_cfg_i_payload_multiplier_b_15),
.io_cfg_i_payload_bias_fixed_0(io_cfg_i_payload_bias_fixed_0),
.io_cfg_i_payload_bias_fixed_1(io_cfg_i_payload_bias_fixed_1),
.io_cfg_i_payload_bias_fixed_2(io_cfg_i_payload_bias_fixed_2),
.io_cfg_i_payload_bias_fixed_3(io_cfg_i_payload_bias_fixed_3),
.io_cfg_i_payload_bias_fixed_4(io_cfg_i_payload_bias_fixed_4),
.io_cfg_i_payload_bias_fixed_5(io_cfg_i_payload_bias_fixed_5),
.io_cfg_i_payload_bias_fixed_6(io_cfg_i_payload_bias_fixed_6),
.io_cfg_i_payload_bias_fixed_7(io_cfg_i_payload_bias_fixed_7),
.io_cfg_i_payload_bias_fixed_8(io_cfg_i_payload_bias_fixed_8),
.io_cfg_i_payload_bias_fixed_9(io_cfg_i_payload_bias_fixed_9),
.io_cfg_i_payload_bias_fixed_10(io_cfg_i_payload_bias_fixed_10),
.io_cfg_i_payload_bias_fixed_11(io_cfg_i_payload_bias_fixed_11),
.io_cfg_i_payload_bias_fixed_12(io_cfg_i_payload_bias_fixed_12),
.io_cfg_i_payload_bias_fixed_13(io_cfg_i_payload_bias_fixed_13),
.io_cfg_i_payload_bias_fixed_14(io_cfg_i_payload_bias_fixed_14),
.io_cfg_i_payload_bias_fixed_15(io_cfg_i_payload_bias_fixed_15),
.io_cfg_i_payload_shift(io_cfg_i_payload_shift),
.io_cfg_i_payload_clamp_min(io_cfg_i_payload_clamp_min),
.io_cfg_i_payload_clamp_max(io_cfg_i_payload_clamp_max),
.io_busy_o(io_busy_o),
.io_done_o(io_done_o),
.io_a_i_valid(io_a_i_valid),
.io_a_i_ready(io_a_i_ready),
.io_a_i_payload(io_a_i_payload),
.io_b_i_valid(io_b_i_valid),
.io_b_i_ready(io_b_i_ready),
.io_b_i_payload(io_b_i_payload),
.io_output_o_valid(io_output_o_valid),
.io_output_o_ready(io_output_o_ready),
.io_output_o_payload_last(io_output_o_payload_last),
.io_output_o_payload_fragment_data(io_output_o_payload_fragment_data),
.io_output_o_payload_fragment_group(io_output_o_payload_fragment_group),
.io_output_o_payload_fragment_group_last(io_output_o_payload_fragment_group_last),
.clk(clk),
.resetn(resetn)
);

logic [1775:0] configs[0:191];
logic [511:0] stimulus_a[0:3263],stimulus_b[0:3263];
logic [135:0] golden[0:3263];
wire [135:0] actual={io_output_o_payload_last,io_output_o_payload_fragment_data,io_output_o_payload_fragment_group,io_output_o_payload_fragment_group_last};
logic [135:0] held;
logic stalled=0;
integer got=0,cycle=0,csv;
always #4 clk=~clk;
always @(negedge clk)io_output_o_ready=resetn && cycle%11>=3;
always @(posedge clk)begin
  cycle=cycle+1;
  if(resetn)begin
    if(stalled && (!io_output_o_valid || actual !== held))begin $error("Add quant stalled payload changed cycle=%0d",cycle);$fflush(csv);$stop;end
    stalled=io_output_o_valid && !io_output_o_ready;held=actual;
    if(io_output_o_valid && io_output_o_ready)begin
      if(got>=3264 || actual !== golden[got])begin $error("Add quant Golden index=%0d actual=%h expected=%h",got,actual,golden[got]);$fflush(csv);$stop;end
      got=got+1;
    end
  end
  if(!finished_o)$fdisplay(csv,"%0d,%b,%b,%b,%b,%b,%b,%h,%0d",cycle,io_a_i_valid,io_a_i_ready,io_b_i_valid,io_b_i_ready,io_output_o_valid,io_output_o_ready,actual,got);
end
initial begin
  clk=0;resetn=0;finished_o=0;io_cfg_i_valid=0;io_a_i_valid=0;io_b_i_valid=0;io_output_o_ready=0;
  csv=$fopen("sim_trace_add_quant.csv","w");$fdisplay(csv,"cycle,a_valid,a_ready,b_valid,b_ready,out_valid,out_ready,payload,got");
  $readmemh("sim/xsim/tests/rtl_slim_batch45/add_cfg.hex",configs);$readmemh("sim/xsim/tests/rtl_slim_batch45/add_a.hex",stimulus_a);$readmemh("sim/xsim/tests/rtl_slim_batch45/add_b.hex",stimulus_b);$readmemh("sim/xsim/tests/rtl_slim_batch45/add_golden.hex",golden);
  repeat(6)@(negedge clk);resetn=1;
  for(int g=0;g<192;g++)begin
    @(negedge clk);{io_cfg_i_payload_words,io_cfg_i_payload_group,io_cfg_i_payload_last_group,io_cfg_i_payload_multiplier_a_0,io_cfg_i_payload_multiplier_a_1,io_cfg_i_payload_multiplier_a_2,io_cfg_i_payload_multiplier_a_3,io_cfg_i_payload_multiplier_a_4,io_cfg_i_payload_multiplier_a_5,io_cfg_i_payload_multiplier_a_6,io_cfg_i_payload_multiplier_a_7,io_cfg_i_payload_multiplier_a_8,io_cfg_i_payload_multiplier_a_9,io_cfg_i_payload_multiplier_a_10,io_cfg_i_payload_multiplier_a_11,io_cfg_i_payload_multiplier_a_12,io_cfg_i_payload_multiplier_a_13,io_cfg_i_payload_multiplier_a_14,io_cfg_i_payload_multiplier_a_15,io_cfg_i_payload_multiplier_b_0,io_cfg_i_payload_multiplier_b_1,io_cfg_i_payload_multiplier_b_2,io_cfg_i_payload_multiplier_b_3,io_cfg_i_payload_multiplier_b_4,io_cfg_i_payload_multiplier_b_5,io_cfg_i_payload_multiplier_b_6,io_cfg_i_payload_multiplier_b_7,io_cfg_i_payload_multiplier_b_8,io_cfg_i_payload_multiplier_b_9,io_cfg_i_payload_multiplier_b_10,io_cfg_i_payload_multiplier_b_11,io_cfg_i_payload_multiplier_b_12,io_cfg_i_payload_multiplier_b_13,io_cfg_i_payload_multiplier_b_14,io_cfg_i_payload_multiplier_b_15,io_cfg_i_payload_bias_fixed_0,io_cfg_i_payload_bias_fixed_1,io_cfg_i_payload_bias_fixed_2,io_cfg_i_payload_bias_fixed_3,io_cfg_i_payload_bias_fixed_4,io_cfg_i_payload_bias_fixed_5,io_cfg_i_payload_bias_fixed_6,io_cfg_i_payload_bias_fixed_7,io_cfg_i_payload_bias_fixed_8,io_cfg_i_payload_bias_fixed_9,io_cfg_i_payload_bias_fixed_10,io_cfg_i_payload_bias_fixed_11,io_cfg_i_payload_bias_fixed_12,io_cfg_i_payload_bias_fixed_13,io_cfg_i_payload_bias_fixed_14,io_cfg_i_payload_bias_fixed_15,io_cfg_i_payload_shift,io_cfg_i_payload_clamp_min,io_cfg_i_payload_clamp_max}=configs[g];io_cfg_i_valid=1;
    do @(posedge clk);while(io_cfg_i_ready !== 1'b1);
    @(negedge clk);io_cfg_i_valid=0;
    for(int w=0;w<17;w++)begin
      @(negedge clk);io_a_i_payload=stimulus_a[g*17+w];io_b_i_payload=stimulus_b[g*17+w];io_a_i_valid=1;
      repeat(w%3)@(negedge clk);io_b_i_valid=1;
      do @(posedge clk);while(!(io_a_i_ready === 1'b1 && io_b_i_ready === 1'b1));
      @(negedge clk);io_a_i_valid=0;io_b_i_valid=0;
    end
    wait(got==(g+1)*17);
  end
  @(negedge clk);finished_o=1;$fclose(csv);
  $display("[CASE PASS] Add quant 192 configs 3264 outputs shift0..63 ties signed extremes join backpressure");
end
endmodule
module tb_batch45_quant;
wire pw_done,add_done;
batch45_pw_quant pw(pw_done);
batch45_add_quant addq(add_done);
initial begin
  $dumpfile("waveform.vcd");$dumpvars(0,pw.clk,pw.resetn,pw_done,add_done);
  wait(pw_done && add_done);$display("[TB PASSED] quantization all offline Golden vectors matched");$finish;
end
initial begin #2000000;$fatal(1,"Quantization timeout");end
endmodule
