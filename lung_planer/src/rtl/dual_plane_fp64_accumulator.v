`timescale 1ns/1ps

// Candidate-scoped FP64 pair accumulator. clear is accepted while idle;
// each start adds one signed-volume term and one area term.
module dual_plane_fp64_accumulator #(parameter EXTERNAL_ALU=0) (
    output wire ext_start, output wire [1:0] ext_op,
    output wire [63:0] ext_a, ext_b,
    input wire ext_ready, ext_done, input wire [63:0] ext_result,
    input wire clk, input wire rst_n, input wire clear, input wire start,
    input wire [63:0] volume_term, input wire [63:0] area_term,
    output reg busy, output reg done,
    output reg [63:0] volume_sum, output reg [63:0] area_sum
);
    localparam [1:0] S_IDLE=0,S_VOL=1,S_AREA=2;
    reg [1:0] state;
    reg [63:0] vterm,aterm;
    wire alu_ready,alu_done; wire [63:0] alu_result;
    reg alu_start;
    wire [63:0] alu_a=(state==S_VOL)?volume_sum:area_sum;
    wire [63:0] alu_b=(state==S_VOL)?vterm:aterm;
    assign ext_start=alu_start;
    assign ext_op=2'd0;
    assign ext_a=alu_a;
    assign ext_b=alu_b;
    generate if(EXTERNAL_ALU) begin : external_alu
        assign alu_ready=ext_ready;
        assign alu_done=ext_done;
        assign alu_result=ext_result;
    end else begin : local_alu
        dual_plane_fp64_alu #(.ENABLE_MULTIPLY(0),.ENABLE_DIVIDE(0),.ENABLE_SQRT(0))
            alu(.clk(clk),.rst_n(rst_n),.start(alu_start),.op(2'd0),
            .a(alu_a),.b(alu_b),.ready(alu_ready),.done(alu_done),.result(alu_result));
    end endgenerate
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=S_IDLE;busy<=0;done<=0;alu_start<=0;vterm<=0;aterm<=0;
            volume_sum<=0;area_sum<=0;
        end else begin
            done<=0;alu_start<=0;
            if(state==S_IDLE) begin
                if(clear) begin volume_sum<=0;area_sum<=0; end
                if(start) begin vterm<=volume_term;aterm<=area_term;busy<=1;state<=S_VOL;end
            end else if(state==S_VOL) begin
                if(alu_ready && !alu_start) alu_start<=1;
                if(alu_done) begin volume_sum<=alu_result;state<=S_AREA;end
            end else if(state==S_AREA) begin
                if(alu_ready && !alu_start) alu_start<=1;
                if(alu_done) begin area_sum<=alu_result;busy<=0;done<=1;state<=S_IDLE;end
            end
        end
    end
endmodule
