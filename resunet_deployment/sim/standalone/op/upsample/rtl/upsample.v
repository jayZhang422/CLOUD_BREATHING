// Generator : SpinalHDL v1.12.3    git head : 591e64062329e5e2e2b81f4d52422948053edb97
// Component : Upsample
// Git hash  : f7925ac5f903a229f1d44b20394ae1d42bcbe7bb

`timescale 1ns/1ps

module Upsample (
  input  wire          io_cfg_i_valid,
  output wire          io_cfg_i_ready,
  input  wire [8:0]    io_cfg_i_payload_width,
  input  wire [8:0]    io_cfg_i_payload_height,
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
  output wire [9:0]    io_output_o_payload_fragment_row,
  output wire [9:0]    io_output_o_payload_fragment_col,
  output wire          io_output_o_payload_fragment_group_last,
  input  wire          clk,
  input  wire          resetn
);
  localparam State_IDLE = 2'd0;
  localparam State_FILL = 2'd1;
  localparam State_EMIT = 2'd2;
  localparam State_DRAIN = 2'd3;

  reg        [127:0]  lineMem_spinal_port1;
  wire       [7:0]    _zz_lineMem_port;
  reg        [1:0]    state_r;
  reg        [1:0]    state_nxt;
  reg        [8:0]    endX_r;
  reg        [8:0]    endY_r;
  reg        [5:0]    endGroup_r;
  reg        [8:0]    x_r;
  reg        [8:0]    y_r;
  reg        [5:0]    group_r;
  reg        [9:0]    col_r;
  reg                 repeatRow_r;
  reg        [7:0]    address_r;
  reg                 done_r;
  wire                io_input_i_fire;
  wire       [9:0]    endCol_w;
  wire                rowEnd_w;
  wire                request_valid;
  reg                 request_ready;
  wire                request_payload_last;
  wire       [5:0]    request_payload_fragment_group;
  wire       [9:0]    request_payload_fragment_row;
  wire       [9:0]    request_payload_fragment_col;
  wire                request_payload_fragment_group_last;
  wire                request_fire;
  wire       [127:0]  ramData_w;
  wire                response_valid;
  wire                response_ready;
  wire                response_payload_last;
  wire       [5:0]    response_payload_fragment_group;
  wire       [9:0]    response_payload_fragment_row;
  wire       [9:0]    response_payload_fragment_col;
  wire                response_payload_fragment_group_last;
  reg                 request_rValid;
  reg                 request_rData_last;
  reg        [5:0]    request_rData_fragment_group;
  reg        [9:0]    request_rData_fragment_row;
  reg        [9:0]    request_rData_fragment_col;
  reg                 request_rData_fragment_group_last;
  wire                when_Stream_l477;
  wire                result_valid;
  wire                result_ready;
  wire                result_payload_last;
  wire       [127:0]  result_payload_fragment_data;
  wire       [5:0]    result_payload_fragment_group;
  wire       [9:0]    result_payload_fragment_row;
  wire       [9:0]    result_payload_fragment_col;
  wire                result_payload_fragment_group_last;
  wire                result_s2mPipe_valid;
  reg                 result_s2mPipe_ready;
  wire                result_s2mPipe_payload_last;
  wire       [127:0]  result_s2mPipe_payload_fragment_data;
  wire       [5:0]    result_s2mPipe_payload_fragment_group;
  wire       [9:0]    result_s2mPipe_payload_fragment_row;
  wire       [9:0]    result_s2mPipe_payload_fragment_col;
  wire                result_s2mPipe_payload_fragment_group_last;
  reg                 result_rValidN;
  reg                 result_rData_last;
  reg        [127:0]  result_rData_fragment_data;
  reg        [5:0]    result_rData_fragment_group;
  reg        [9:0]    result_rData_fragment_row;
  reg        [9:0]    result_rData_fragment_col;
  reg                 result_rData_fragment_group_last;
  wire                result_s2mPipe_m2sPipe_valid;
  wire                result_s2mPipe_m2sPipe_ready;
  wire                result_s2mPipe_m2sPipe_payload_last;
  wire       [127:0]  result_s2mPipe_m2sPipe_payload_fragment_data;
  wire       [5:0]    result_s2mPipe_m2sPipe_payload_fragment_group;
  wire       [9:0]    result_s2mPipe_m2sPipe_payload_fragment_row;
  wire       [9:0]    result_s2mPipe_m2sPipe_payload_fragment_col;
  wire                result_s2mPipe_m2sPipe_payload_fragment_group_last;
  reg                 result_s2mPipe_rValid;
  reg                 result_s2mPipe_rData_last;
  reg        [127:0]  result_s2mPipe_rData_fragment_data;
  reg        [5:0]    result_s2mPipe_rData_fragment_group;
  reg        [9:0]    result_s2mPipe_rData_fragment_row;
  reg        [9:0]    result_s2mPipe_rData_fragment_col;
  reg                 result_s2mPipe_rData_fragment_group_last;
  wire                when_Stream_l477_1;
  wire                io_output_o_fire;
  wire                drained_w;
  wire                io_cfg_i_fire;
  wire                when_Upsample_l93;
  wire                when_Upsample_l94;
  wire                when_Upsample_l111;
  wire                when_Upsample_l115;
  wire                when_Upsample_l124;
  `ifndef SYNTHESIS
  reg [39:0] state_r_string;
  reg [39:0] state_nxt_string;
  `endif

  (* ram_style = "block" *) reg [127:0] lineMem [0:255];

  assign _zz_lineMem_port = x_r[7:0];
  always @(posedge clk) begin
    if(io_input_i_fire) begin
      lineMem[_zz_lineMem_port] <= io_input_i_payload;
    end
  end

  always @(posedge clk) begin
    if(request_fire) begin
      lineMem_spinal_port1 <= lineMem[address_r];
    end
  end

  `ifndef SYNTHESIS
  always @(*) begin
    case(state_r)
      State_IDLE : state_r_string = "IDLE ";
      State_FILL : state_r_string = "FILL ";
      State_EMIT : state_r_string = "EMIT ";
      State_DRAIN : state_r_string = "DRAIN";
      default : state_r_string = "?????";
    endcase
  end
  always @(*) begin
    case(state_nxt)
      State_IDLE : state_nxt_string = "IDLE ";
      State_FILL : state_nxt_string = "FILL ";
      State_EMIT : state_nxt_string = "EMIT ";
      State_DRAIN : state_nxt_string = "DRAIN";
      default : state_nxt_string = "?????";
    endcase
  end
  `endif

  assign io_done_o = done_r;
  assign io_busy_o = (state_r != State_IDLE);
  assign io_cfg_i_ready = (((((((state_r == State_IDLE) && (io_cfg_i_payload_width != 9'h0)) && (io_cfg_i_payload_width <= 9'h100)) && (io_cfg_i_payload_height != 9'h0)) && (io_cfg_i_payload_height <= 9'h100)) && (io_cfg_i_payload_groups != 6'h0)) && (io_cfg_i_payload_groups <= 6'h20));
  assign io_input_i_ready = (state_r == State_FILL);
  assign io_input_i_fire = (io_input_i_valid && io_input_i_ready);
  assign endCol_w = {endX_r,1'b1};
  assign rowEnd_w = (col_r == endCol_w);
  assign request_valid = (state_r == State_EMIT);
  assign request_payload_fragment_group = group_r;
  assign request_payload_fragment_row = {y_r,repeatRow_r};
  assign request_payload_fragment_col = col_r;
  assign request_payload_fragment_group_last = ((rowEnd_w && repeatRow_r) && (y_r == endY_r));
  assign request_payload_last = (request_payload_fragment_group_last && (group_r == endGroup_r));
  assign request_fire = (request_valid && request_ready);
  assign ramData_w = lineMem_spinal_port1;
  always @(*) begin
    request_ready = response_ready;
    if(when_Stream_l477) begin
      request_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! response_valid);
  assign response_valid = request_rValid;
  assign response_payload_last = request_rData_last;
  assign response_payload_fragment_group = request_rData_fragment_group;
  assign response_payload_fragment_row = request_rData_fragment_row;
  assign response_payload_fragment_col = request_rData_fragment_col;
  assign response_payload_fragment_group_last = request_rData_fragment_group_last;
  assign result_valid = response_valid;
  assign response_ready = result_ready;
  assign result_payload_fragment_data = ramData_w;
  assign result_payload_fragment_group = response_payload_fragment_group;
  assign result_payload_fragment_row = response_payload_fragment_row;
  assign result_payload_fragment_col = response_payload_fragment_col;
  assign result_payload_fragment_group_last = response_payload_fragment_group_last;
  assign result_payload_last = response_payload_last;
  assign result_ready = result_rValidN;
  assign result_s2mPipe_valid = (result_valid || (! result_rValidN));
  assign result_s2mPipe_payload_last = (result_rValidN ? result_payload_last : result_rData_last);
  assign result_s2mPipe_payload_fragment_data = (result_rValidN ? result_payload_fragment_data : result_rData_fragment_data);
  assign result_s2mPipe_payload_fragment_group = (result_rValidN ? result_payload_fragment_group : result_rData_fragment_group);
  assign result_s2mPipe_payload_fragment_row = (result_rValidN ? result_payload_fragment_row : result_rData_fragment_row);
  assign result_s2mPipe_payload_fragment_col = (result_rValidN ? result_payload_fragment_col : result_rData_fragment_col);
  assign result_s2mPipe_payload_fragment_group_last = (result_rValidN ? result_payload_fragment_group_last : result_rData_fragment_group_last);
  always @(*) begin
    result_s2mPipe_ready = result_s2mPipe_m2sPipe_ready;
    if(when_Stream_l477_1) begin
      result_s2mPipe_ready = 1'b1;
    end
  end

  assign when_Stream_l477_1 = (! result_s2mPipe_m2sPipe_valid);
  assign result_s2mPipe_m2sPipe_valid = result_s2mPipe_rValid;
  assign result_s2mPipe_m2sPipe_payload_last = result_s2mPipe_rData_last;
  assign result_s2mPipe_m2sPipe_payload_fragment_data = result_s2mPipe_rData_fragment_data;
  assign result_s2mPipe_m2sPipe_payload_fragment_group = result_s2mPipe_rData_fragment_group;
  assign result_s2mPipe_m2sPipe_payload_fragment_row = result_s2mPipe_rData_fragment_row;
  assign result_s2mPipe_m2sPipe_payload_fragment_col = result_s2mPipe_rData_fragment_col;
  assign result_s2mPipe_m2sPipe_payload_fragment_group_last = result_s2mPipe_rData_fragment_group_last;
  assign io_output_o_valid = result_s2mPipe_m2sPipe_valid;
  assign result_s2mPipe_m2sPipe_ready = io_output_o_ready;
  assign io_output_o_payload_last = result_s2mPipe_m2sPipe_payload_last;
  assign io_output_o_payload_fragment_data = result_s2mPipe_m2sPipe_payload_fragment_data;
  assign io_output_o_payload_fragment_group = result_s2mPipe_m2sPipe_payload_fragment_group;
  assign io_output_o_payload_fragment_row = result_s2mPipe_m2sPipe_payload_fragment_row;
  assign io_output_o_payload_fragment_col = result_s2mPipe_m2sPipe_payload_fragment_col;
  assign io_output_o_payload_fragment_group_last = result_s2mPipe_m2sPipe_payload_fragment_group_last;
  assign io_output_o_fire = (io_output_o_valid && io_output_o_ready);
  assign drained_w = ((io_output_o_fire && (io_output_o_payload_fragment_col == endCol_w)) && io_output_o_payload_fragment_row[0]);
  always @(*) begin
    state_nxt = state_r;
    case(state_r)
      State_IDLE : begin
        if(io_cfg_i_fire) begin
          state_nxt = State_FILL;
        end
      end
      State_FILL : begin
        if(when_Upsample_l93) begin
          state_nxt = State_EMIT;
        end
      end
      State_EMIT : begin
        if(when_Upsample_l94) begin
          state_nxt = State_DRAIN;
        end
      end
      default : begin
        if(drained_w) begin
          state_nxt = State_FILL;
          if(io_output_o_payload_last) begin
            state_nxt = State_IDLE;
          end
        end
      end
    endcase
  end

  assign io_cfg_i_fire = (io_cfg_i_valid && io_cfg_i_ready);
  assign when_Upsample_l93 = (io_input_i_fire && (x_r == endX_r));
  assign when_Upsample_l94 = ((request_fire && rowEnd_w) && repeatRow_r);
  assign when_Upsample_l111 = (x_r == endX_r);
  assign when_Upsample_l115 = col_r[0];
  assign when_Upsample_l124 = (y_r == endY_r);
  always @(posedge clk or negedge resetn) begin
    if(!resetn) begin
      state_r <= State_IDLE;
      endX_r <= 9'h0;
      endY_r <= 9'h0;
      endGroup_r <= 6'h0;
      x_r <= 9'h0;
      y_r <= 9'h0;
      group_r <= 6'h0;
      col_r <= 10'h0;
      repeatRow_r <= 1'b0;
      address_r <= 8'h0;
      done_r <= 1'b0;
      request_rValid <= 1'b0;
      result_rValidN <= 1'b1;
      result_s2mPipe_rValid <= 1'b0;
    end else begin
      done_r <= 1'b0;
      if(request_ready) begin
        request_rValid <= request_valid;
      end
      if(result_valid) begin
        result_rValidN <= 1'b0;
      end
      if(result_s2mPipe_ready) begin
        result_rValidN <= 1'b1;
      end
      if(result_s2mPipe_ready) begin
        result_s2mPipe_rValid <= result_s2mPipe_valid;
      end
      state_r <= state_nxt;
      if(io_cfg_i_fire) begin
        endX_r <= (io_cfg_i_payload_width - 9'h001);
        endY_r <= (io_cfg_i_payload_height - 9'h001);
        endGroup_r <= (io_cfg_i_payload_groups - 6'h01);
        x_r <= 9'h0;
        y_r <= 9'h0;
        group_r <= 6'h0;
        col_r <= 10'h0;
        repeatRow_r <= 1'b0;
        address_r <= 8'h0;
      end
      if(io_input_i_fire) begin
        x_r <= (x_r + 9'h001);
        if(when_Upsample_l111) begin
          x_r <= 9'h0;
        end
      end
      if(request_fire) begin
        col_r <= (col_r + 10'h001);
        if(when_Upsample_l115) begin
          address_r <= (address_r + 8'h01);
        end
        if(rowEnd_w) begin
          col_r <= 10'h0;
          address_r <= 8'h0;
          repeatRow_r <= (! repeatRow_r);
        end
      end
      if(drained_w) begin
        y_r <= (y_r + 9'h001);
        if(when_Upsample_l124) begin
          y_r <= 9'h0;
          group_r <= (group_r + 6'h01);
        end
        if(io_output_o_payload_last) begin
          done_r <= 1'b1;
        end
      end
    end
  end

  always @(posedge clk) begin
    if(request_ready) begin
      request_rData_last <= request_payload_last;
      request_rData_fragment_group <= request_payload_fragment_group;
      request_rData_fragment_row <= request_payload_fragment_row;
      request_rData_fragment_col <= request_payload_fragment_col;
      request_rData_fragment_group_last <= request_payload_fragment_group_last;
    end
    if(result_ready) begin
      result_rData_last <= result_payload_last;
      result_rData_fragment_data <= result_payload_fragment_data;
      result_rData_fragment_group <= result_payload_fragment_group;
      result_rData_fragment_row <= result_payload_fragment_row;
      result_rData_fragment_col <= result_payload_fragment_col;
      result_rData_fragment_group_last <= result_payload_fragment_group_last;
    end
    if(result_s2mPipe_ready) begin
      result_s2mPipe_rData_last <= result_s2mPipe_payload_last;
      result_s2mPipe_rData_fragment_data <= result_s2mPipe_payload_fragment_data;
      result_s2mPipe_rData_fragment_group <= result_s2mPipe_payload_fragment_group;
      result_s2mPipe_rData_fragment_row <= result_s2mPipe_payload_fragment_row;
      result_s2mPipe_rData_fragment_col <= result_s2mPipe_payload_fragment_col;
      result_s2mPipe_rData_fragment_group_last <= result_s2mPipe_payload_fragment_group_last;
    end
  end


endmodule
