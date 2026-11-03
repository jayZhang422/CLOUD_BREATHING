// Generator : SpinalHDL v1.12.3    git head : 591e64062329e5e2e2b81f4d52422948053edb97
// Component : LineBuffer_3x3
// Git hash  : 24bf059a106bbb8e1d3ec8355a1bd93d1949700f

`timescale 1ns/1ps

module LineBuffer_3x3 (
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
  output wire [127:0]  io_output_o_payload_fragment_window_0_0,
  output wire [127:0]  io_output_o_payload_fragment_window_0_1,
  output wire [127:0]  io_output_o_payload_fragment_window_0_2,
  output wire [127:0]  io_output_o_payload_fragment_window_1_0,
  output wire [127:0]  io_output_o_payload_fragment_window_1_1,
  output wire [127:0]  io_output_o_payload_fragment_window_1_2,
  output wire [127:0]  io_output_o_payload_fragment_window_2_0,
  output wire [127:0]  io_output_o_payload_fragment_window_2_1,
  output wire [127:0]  io_output_o_payload_fragment_window_2_2,
  output wire [5:0]    io_output_o_payload_fragment_group,
  output wire          io_output_o_payload_fragment_group_last,
  input  wire          clk,
  input  wire          resetn
);

  reg        [127:0]  lineMem_0_spinal_port1;
  reg        [127:0]  lineMem_1_spinal_port1;
  wire       [9:0]    _zz_realColumn_w;
  wire       [9:0]    _zz_realPixel_w;
  wire       [9:0]    _zz_groupLast_w;
  wire       [9:0]    _zz_groupLast_w_1;
  wire       [5:0]    _zz_lastGroup_w;
  wire       [8:0]    _zz_request_payload_address;
  wire                _zz_lineMem_0_port;
  wire                _zz_lineMem_1_port;
  wire       [9:0]    _zz_when_LineBuffer_l101;
  wire       [9:0]    _zz_when_LineBuffer_l104;
  reg        [127:0]  _zz__zz_horizontal_r_0_1;
  wire       [0:0]    _zz__zz_horizontal_r_0_1_1;
  reg        [127:0]  _zz__zz_horizontal_r_1_1;
  wire       [0:0]    _zz__zz_horizontal_r_1_1_1;
  reg        [9:0]    width_r;
  reg        [9:0]    height_r;
  reg        [5:0]    groups_r;
  reg                 busy_r;
  reg                 active_r;
  reg                 done_r;
  reg        [9:0]    x_r;
  reg        [9:0]    y_r;
  reg        [0:0]    bank_r;
  reg        [5:0]    group_r;
  wire       [9:0]    paddedWidth_w;
  wire       [9:0]    paddedHeight_w;
  wire                realColumn_w;
  wire                realPixel_w;
  wire                groupLast_w;
  wire                lastGroup_w;
  wire                _zz_io_input_i_ready;
  wire                io_input_i_haltWhen_valid;
  wire                io_input_i_haltWhen_ready;
  wire       [127:0]  io_input_i_haltWhen_payload;
  wire                input_valid;
  wire                input_ready;
  wire       [127:0]  input_payload;
  reg                 io_input_i_haltWhen_rValidN;
  reg        [127:0]  io_input_i_haltWhen_rData;
  wire                request_valid;
  reg                 request_ready;
  wire       [127:0]  request_payload_pixel;
  wire       [8:0]    request_payload_address;
  wire       [0:0]    request_payload_bank;
  wire                request_payload_emit;
  wire                request_payload_real_column;
  wire       [5:0]    request_payload_group;
  wire                request_payload_group_last;
  wire                request_payload_last;
  wire                memoryRequest_valid;
  reg                 memoryRequest_ready;
  wire       [127:0]  memoryRequest_payload_pixel;
  wire       [8:0]    memoryRequest_payload_address;
  wire       [0:0]    memoryRequest_payload_bank;
  wire                memoryRequest_payload_emit;
  wire                memoryRequest_payload_real_column;
  wire       [5:0]    memoryRequest_payload_group;
  wire                memoryRequest_payload_group_last;
  wire                memoryRequest_payload_last;
  reg                 request_rValid;
  reg        [127:0]  request_rData_pixel;
  reg        [8:0]    request_rData_address;
  reg        [0:0]    request_rData_bank;
  reg                 request_rData_emit;
  reg                 request_rData_real_column;
  reg        [5:0]    request_rData_group;
  reg                 request_rData_group_last;
  reg                 request_rData_last;
  wire                when_Stream_l477;
  wire                response_valid;
  wire                response_ready;
  wire       [127:0]  response_payload_pixel;
  wire       [8:0]    response_payload_address;
  wire       [0:0]    response_payload_bank;
  wire                response_payload_emit;
  wire                response_payload_real_column;
  wire       [5:0]    response_payload_group;
  wire                response_payload_group_last;
  wire                response_payload_last;
  reg                 memoryRequest_rValid;
  reg        [127:0]  memoryRequest_rData_pixel;
  reg        [8:0]    memoryRequest_rData_address;
  reg        [0:0]    memoryRequest_rData_bank;
  reg                 memoryRequest_rData_emit;
  reg                 memoryRequest_rData_real_column;
  reg        [5:0]    memoryRequest_rData_group;
  reg                 memoryRequest_rData_group_last;
  reg                 memoryRequest_rData_last;
  wire                when_Stream_l477_1;
  wire                memoryRequest_fire;
  wire                _zz_history_w_0;
  wire       [127:0]  history_w_0;
  wire                _zz_history_w_1;
  wire       [127:0]  history_w_1;
  wire                request_fire;
  wire                when_LineBuffer_l101;
  wire                when_LineBuffer_l104;
  reg        [127:0]  horizontal_r_0_0;
  reg        [127:0]  horizontal_r_0_1;
  reg        [127:0]  horizontal_r_1_0;
  reg        [127:0]  horizontal_r_1_1;
  reg        [127:0]  horizontal_r_2_0;
  reg        [127:0]  horizontal_r_2_1;
  wire                window_valid;
  wire                window_ready;
  wire                window_payload_last;
  wire       [127:0]  window_payload_fragment_window_0_0;
  wire       [127:0]  window_payload_fragment_window_0_1;
  wire       [127:0]  window_payload_fragment_window_0_2;
  wire       [127:0]  window_payload_fragment_window_1_0;
  wire       [127:0]  window_payload_fragment_window_1_1;
  wire       [127:0]  window_payload_fragment_window_1_2;
  wire       [127:0]  window_payload_fragment_window_2_0;
  wire       [127:0]  window_payload_fragment_window_2_1;
  wire       [127:0]  window_payload_fragment_window_2_2;
  wire       [5:0]    window_payload_fragment_group;
  wire                window_payload_fragment_group_last;
  (* max_fanout = 64 *) wire                horizontalStep_w;
  wire       [127:0]  _zz_horizontal_r_0_1;
  wire       [127:0]  _zz_horizontal_r_1_1;
  wire       [127:0]  _zz_horizontal_r_2_1;
  wire                window_halfPipe_valid;
  wire                window_halfPipe_ready;
  wire                window_halfPipe_payload_last;
  wire       [127:0]  window_halfPipe_payload_fragment_window_0_0;
  wire       [127:0]  window_halfPipe_payload_fragment_window_0_1;
  wire       [127:0]  window_halfPipe_payload_fragment_window_0_2;
  wire       [127:0]  window_halfPipe_payload_fragment_window_1_0;
  wire       [127:0]  window_halfPipe_payload_fragment_window_1_1;
  wire       [127:0]  window_halfPipe_payload_fragment_window_1_2;
  wire       [127:0]  window_halfPipe_payload_fragment_window_2_0;
  wire       [127:0]  window_halfPipe_payload_fragment_window_2_1;
  wire       [127:0]  window_halfPipe_payload_fragment_window_2_2;
  wire       [5:0]    window_halfPipe_payload_fragment_group;
  wire                window_halfPipe_payload_fragment_group_last;
  reg                 window_rValid;
  wire                window_halfPipe_fire;
  reg                 window_rData_last;
  reg        [127:0]  window_rData_fragment_window_0_0;
  reg        [127:0]  window_rData_fragment_window_0_1;
  reg        [127:0]  window_rData_fragment_window_0_2;
  reg        [127:0]  window_rData_fragment_window_1_0;
  reg        [127:0]  window_rData_fragment_window_1_1;
  reg        [127:0]  window_rData_fragment_window_1_2;
  reg        [127:0]  window_rData_fragment_window_2_0;
  reg        [127:0]  window_rData_fragment_window_2_1;
  reg        [127:0]  window_rData_fragment_window_2_2;
  reg        [5:0]    window_rData_fragment_group;
  reg                 window_rData_fragment_group_last;
  wire                io_output_o_fire;
  wire                when_LineBuffer_l151;
  wire                io_cfg_i_fire;
  (* ram_style = "block" *) reg [127:0] lineMem_0 [0:511];
  (* ram_style = "block" *) reg [127:0] lineMem_1 [0:511];

  assign _zz_realColumn_w = (width_r + 10'h001);
  assign _zz_realPixel_w = (height_r + 10'h001);
  assign _zz_groupLast_w = (paddedWidth_w - 10'h001);
  assign _zz_groupLast_w_1 = (paddedHeight_w - 10'h001);
  assign _zz_lastGroup_w = (groups_r - 6'h01);
  assign _zz_request_payload_address = x_r[8:0];
  assign _zz_when_LineBuffer_l101 = (paddedWidth_w - 10'h001);
  assign _zz_when_LineBuffer_l104 = (paddedHeight_w - 10'h001);
  assign _zz__zz_horizontal_r_0_1_1 = (response_payload_bank + 1'b0);
  assign _zz__zz_horizontal_r_1_1_1 = (response_payload_bank + 1'b1);
  assign _zz_lineMem_0_port = ((memoryRequest_fire && memoryRequest_payload_real_column) && (memoryRequest_payload_bank == 1'b0));
  assign _zz_lineMem_1_port = ((memoryRequest_fire && memoryRequest_payload_real_column) && (memoryRequest_payload_bank == 1'b1));
  always @(posedge clk) begin
    if(_zz_history_w_0) begin
      lineMem_0_spinal_port1 <= lineMem_0[memoryRequest_payload_address];
    end
    if(_zz_lineMem_0_port) begin
      lineMem_0[memoryRequest_payload_address] <= memoryRequest_payload_pixel;
    end
  end

  always @(posedge clk) begin
    if(_zz_history_w_1) begin
      lineMem_1_spinal_port1 <= lineMem_1[memoryRequest_payload_address];
    end
    if(_zz_lineMem_1_port) begin
      lineMem_1[memoryRequest_payload_address] <= memoryRequest_payload_pixel;
    end
  end

  always @(*) begin
    case(_zz__zz_horizontal_r_0_1_1)
      1'b0 : _zz__zz_horizontal_r_0_1 = history_w_0;
      default : _zz__zz_horizontal_r_0_1 = history_w_1;
    endcase
  end

  always @(*) begin
    case(_zz__zz_horizontal_r_1_1_1)
      1'b0 : _zz__zz_horizontal_r_1_1 = history_w_0;
      default : _zz__zz_horizontal_r_1_1 = history_w_1;
    endcase
  end

  assign paddedWidth_w = (width_r + 10'h002);
  assign paddedHeight_w = (height_r + 10'h002);
  assign realColumn_w = ((10'h001 <= x_r) && (x_r < _zz_realColumn_w));
  assign realPixel_w = ((realColumn_w && (10'h001 <= y_r)) && (y_r < _zz_realPixel_w));
  assign groupLast_w = ((x_r == _zz_groupLast_w) && (y_r == _zz_groupLast_w_1));
  assign lastGroup_w = (group_r == _zz_lastGroup_w);
  assign io_cfg_i_ready = (((((((! busy_r) && (io_cfg_i_payload_width != 10'h0)) && (io_cfg_i_payload_width <= 10'h200)) && (io_cfg_i_payload_height != 10'h0)) && (io_cfg_i_payload_height <= 10'h200)) && (io_cfg_i_payload_groups != 6'h0)) && (io_cfg_i_payload_groups <= 6'h20));
  assign io_busy_o = busy_r;
  assign io_done_o = done_r;
  assign _zz_io_input_i_ready = (! (! active_r));
  assign io_input_i_haltWhen_valid = (io_input_i_valid && _zz_io_input_i_ready);
  assign io_input_i_ready = (io_input_i_haltWhen_ready && _zz_io_input_i_ready);
  assign io_input_i_haltWhen_payload = io_input_i_payload;
  assign io_input_i_haltWhen_ready = io_input_i_haltWhen_rValidN;
  assign input_valid = (io_input_i_haltWhen_valid || (! io_input_i_haltWhen_rValidN));
  assign input_payload = (io_input_i_haltWhen_rValidN ? io_input_i_haltWhen_payload : io_input_i_haltWhen_rData);
  assign request_valid = (active_r && ((! realPixel_w) || input_valid));
  assign request_payload_pixel = (realPixel_w ? input_payload : 128'h0);
  assign request_payload_address = (_zz_request_payload_address - 9'h001);
  assign request_payload_bank = bank_r;
  assign request_payload_emit = ((10'h002 <= x_r) && (10'h002 <= y_r));
  assign request_payload_real_column = realColumn_w;
  assign request_payload_group = group_r;
  assign request_payload_group_last = groupLast_w;
  assign request_payload_last = (groupLast_w && lastGroup_w);
  assign input_ready = ((active_r && realPixel_w) && request_ready);
  always @(*) begin
    request_ready = memoryRequest_ready;
    if(when_Stream_l477) begin
      request_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! memoryRequest_valid);
  assign memoryRequest_valid = request_rValid;
  assign memoryRequest_payload_pixel = request_rData_pixel;
  assign memoryRequest_payload_address = request_rData_address;
  assign memoryRequest_payload_bank = request_rData_bank;
  assign memoryRequest_payload_emit = request_rData_emit;
  assign memoryRequest_payload_real_column = request_rData_real_column;
  assign memoryRequest_payload_group = request_rData_group;
  assign memoryRequest_payload_group_last = request_rData_group_last;
  assign memoryRequest_payload_last = request_rData_last;
  always @(*) begin
    memoryRequest_ready = response_ready;
    if(when_Stream_l477_1) begin
      memoryRequest_ready = 1'b1;
    end
  end

  assign when_Stream_l477_1 = (! response_valid);
  assign response_valid = memoryRequest_rValid;
  assign response_payload_pixel = memoryRequest_rData_pixel;
  assign response_payload_address = memoryRequest_rData_address;
  assign response_payload_bank = memoryRequest_rData_bank;
  assign response_payload_emit = memoryRequest_rData_emit;
  assign response_payload_real_column = memoryRequest_rData_real_column;
  assign response_payload_group = memoryRequest_rData_group;
  assign response_payload_group_last = memoryRequest_rData_group_last;
  assign response_payload_last = memoryRequest_rData_last;
  assign memoryRequest_fire = (memoryRequest_valid && memoryRequest_ready);
  assign _zz_history_w_0 = (memoryRequest_fire && memoryRequest_payload_real_column);
  assign history_w_0 = lineMem_0_spinal_port1;
  assign _zz_history_w_1 = (memoryRequest_fire && memoryRequest_payload_real_column);
  assign history_w_1 = lineMem_1_spinal_port1;
  assign request_fire = (request_valid && request_ready);
  assign when_LineBuffer_l101 = (x_r == _zz_when_LineBuffer_l101);
  assign when_LineBuffer_l104 = (y_r == _zz_when_LineBuffer_l104);
  assign window_valid = (response_valid && response_payload_emit);
  assign window_payload_fragment_group = response_payload_group;
  assign window_payload_fragment_group_last = response_payload_group_last;
  assign window_payload_last = response_payload_last;
  assign response_ready = ((! response_payload_emit) || window_ready);
  assign horizontalStep_w = (response_valid && response_ready);
  assign _zz_horizontal_r_0_1 = (response_payload_real_column ? _zz__zz_horizontal_r_0_1 : 128'h0);
  assign window_payload_fragment_window_0_0 = horizontal_r_0_0;
  assign window_payload_fragment_window_0_1 = horizontal_r_0_1;
  assign window_payload_fragment_window_0_2 = _zz_horizontal_r_0_1;
  assign _zz_horizontal_r_1_1 = (response_payload_real_column ? _zz__zz_horizontal_r_1_1 : 128'h0);
  assign window_payload_fragment_window_1_0 = horizontal_r_1_0;
  assign window_payload_fragment_window_1_1 = horizontal_r_1_1;
  assign window_payload_fragment_window_1_2 = _zz_horizontal_r_1_1;
  assign _zz_horizontal_r_2_1 = response_payload_pixel;
  assign window_payload_fragment_window_2_0 = horizontal_r_2_0;
  assign window_payload_fragment_window_2_1 = horizontal_r_2_1;
  assign window_payload_fragment_window_2_2 = _zz_horizontal_r_2_1;
  assign window_halfPipe_fire = (window_halfPipe_valid && window_halfPipe_ready);
  assign window_ready = (! window_rValid);
  assign window_halfPipe_valid = window_rValid;
  assign window_halfPipe_payload_last = window_rData_last;
  assign window_halfPipe_payload_fragment_window_0_0 = window_rData_fragment_window_0_0;
  assign window_halfPipe_payload_fragment_window_0_1 = window_rData_fragment_window_0_1;
  assign window_halfPipe_payload_fragment_window_0_2 = window_rData_fragment_window_0_2;
  assign window_halfPipe_payload_fragment_window_1_0 = window_rData_fragment_window_1_0;
  assign window_halfPipe_payload_fragment_window_1_1 = window_rData_fragment_window_1_1;
  assign window_halfPipe_payload_fragment_window_1_2 = window_rData_fragment_window_1_2;
  assign window_halfPipe_payload_fragment_window_2_0 = window_rData_fragment_window_2_0;
  assign window_halfPipe_payload_fragment_window_2_1 = window_rData_fragment_window_2_1;
  assign window_halfPipe_payload_fragment_window_2_2 = window_rData_fragment_window_2_2;
  assign window_halfPipe_payload_fragment_group = window_rData_fragment_group;
  assign window_halfPipe_payload_fragment_group_last = window_rData_fragment_group_last;
  assign io_output_o_valid = window_halfPipe_valid;
  assign window_halfPipe_ready = io_output_o_ready;
  assign io_output_o_payload_last = window_halfPipe_payload_last;
  assign io_output_o_payload_fragment_window_0_0 = window_halfPipe_payload_fragment_window_0_0;
  assign io_output_o_payload_fragment_window_0_1 = window_halfPipe_payload_fragment_window_0_1;
  assign io_output_o_payload_fragment_window_0_2 = window_halfPipe_payload_fragment_window_0_2;
  assign io_output_o_payload_fragment_window_1_0 = window_halfPipe_payload_fragment_window_1_0;
  assign io_output_o_payload_fragment_window_1_1 = window_halfPipe_payload_fragment_window_1_1;
  assign io_output_o_payload_fragment_window_1_2 = window_halfPipe_payload_fragment_window_1_2;
  assign io_output_o_payload_fragment_window_2_0 = window_halfPipe_payload_fragment_window_2_0;
  assign io_output_o_payload_fragment_window_2_1 = window_halfPipe_payload_fragment_window_2_1;
  assign io_output_o_payload_fragment_window_2_2 = window_halfPipe_payload_fragment_window_2_2;
  assign io_output_o_payload_fragment_group = window_halfPipe_payload_fragment_group;
  assign io_output_o_payload_fragment_group_last = window_halfPipe_payload_fragment_group_last;
  assign io_output_o_fire = (io_output_o_valid && io_output_o_ready);
  assign when_LineBuffer_l151 = (io_output_o_fire && io_output_o_payload_last);
  assign io_cfg_i_fire = (io_cfg_i_valid && io_cfg_i_ready);
  always @(posedge clk or negedge resetn) begin
    if(!resetn) begin
      width_r <= 10'h0;
      height_r <= 10'h0;
      groups_r <= 6'h0;
      busy_r <= 1'b0;
      active_r <= 1'b0;
      done_r <= 1'b0;
      x_r <= 10'h0;
      y_r <= 10'h0;
      bank_r <= 1'b0;
      group_r <= 6'h0;
      io_input_i_haltWhen_rValidN <= 1'b1;
      request_rValid <= 1'b0;
      memoryRequest_rValid <= 1'b0;
      window_rValid <= 1'b0;
    end else begin
      done_r <= 1'b0;
      if(io_input_i_haltWhen_valid) begin
        io_input_i_haltWhen_rValidN <= 1'b0;
      end
      if(input_ready) begin
        io_input_i_haltWhen_rValidN <= 1'b1;
      end
      if(request_ready) begin
        request_rValid <= request_valid;
      end
      if(memoryRequest_ready) begin
        memoryRequest_rValid <= memoryRequest_valid;
      end
      if(request_fire) begin
        if(when_LineBuffer_l101) begin
          x_r <= 10'h0;
          bank_r <= (bank_r + 1'b1);
          if(when_LineBuffer_l104) begin
            y_r <= 10'h0;
            bank_r <= 1'b0;
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
      if(window_valid) begin
        window_rValid <= 1'b1;
      end
      if(window_halfPipe_fire) begin
        window_rValid <= 1'b0;
      end
      if(when_LineBuffer_l151) begin
        busy_r <= 1'b0;
        done_r <= 1'b1;
      end
      if(io_cfg_i_fire) begin
        width_r <= io_cfg_i_payload_width;
        height_r <= io_cfg_i_payload_height;
        groups_r <= io_cfg_i_payload_groups;
        x_r <= 10'h0;
        y_r <= 10'h0;
        bank_r <= 1'b0;
        group_r <= 6'h0;
        busy_r <= 1'b1;
        active_r <= 1'b1;
      end
    end
  end

  always @(posedge clk) begin
    if(io_input_i_haltWhen_ready) begin
      io_input_i_haltWhen_rData <= io_input_i_haltWhen_payload;
    end
    if(request_ready) begin
      request_rData_pixel <= request_payload_pixel;
      request_rData_address <= request_payload_address;
      request_rData_bank <= request_payload_bank;
      request_rData_emit <= request_payload_emit;
      request_rData_real_column <= request_payload_real_column;
      request_rData_group <= request_payload_group;
      request_rData_group_last <= request_payload_group_last;
      request_rData_last <= request_payload_last;
    end
    if(memoryRequest_ready) begin
      memoryRequest_rData_pixel <= memoryRequest_payload_pixel;
      memoryRequest_rData_address <= memoryRequest_payload_address;
      memoryRequest_rData_bank <= memoryRequest_payload_bank;
      memoryRequest_rData_emit <= memoryRequest_payload_emit;
      memoryRequest_rData_real_column <= memoryRequest_payload_real_column;
      memoryRequest_rData_group <= memoryRequest_payload_group;
      memoryRequest_rData_group_last <= memoryRequest_payload_group_last;
      memoryRequest_rData_last <= memoryRequest_payload_last;
    end
    if(horizontalStep_w) begin
      horizontal_r_0_0 <= horizontal_r_0_1;
    end
    if(horizontalStep_w) begin
      horizontal_r_0_1 <= _zz_horizontal_r_0_1;
    end
    if(horizontalStep_w) begin
      horizontal_r_1_0 <= horizontal_r_1_1;
    end
    if(horizontalStep_w) begin
      horizontal_r_1_1 <= _zz_horizontal_r_1_1;
    end
    if(horizontalStep_w) begin
      horizontal_r_2_0 <= horizontal_r_2_1;
    end
    if(horizontalStep_w) begin
      horizontal_r_2_1 <= _zz_horizontal_r_2_1;
    end
    if(window_ready) begin
      window_rData_last <= window_payload_last;
      window_rData_fragment_window_0_0 <= window_payload_fragment_window_0_0;
      window_rData_fragment_window_0_1 <= window_payload_fragment_window_0_1;
      window_rData_fragment_window_0_2 <= window_payload_fragment_window_0_2;
      window_rData_fragment_window_1_0 <= window_payload_fragment_window_1_0;
      window_rData_fragment_window_1_1 <= window_payload_fragment_window_1_1;
      window_rData_fragment_window_1_2 <= window_payload_fragment_window_1_2;
      window_rData_fragment_window_2_0 <= window_payload_fragment_window_2_0;
      window_rData_fragment_window_2_1 <= window_payload_fragment_window_2_1;
      window_rData_fragment_window_2_2 <= window_payload_fragment_window_2_2;
      window_rData_fragment_group <= window_payload_fragment_group;
      window_rData_fragment_group_last <= window_payload_fragment_group_last;
    end
  end


endmodule
