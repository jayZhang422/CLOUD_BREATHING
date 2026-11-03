`timescale 1ns/1ps

// Signed outward cap area contributed by one oriented source boundary edge.
// The supplied origin lies on both physical cut planes, so common-ridge edges
// contribute zero and no cap polygon graph is needed for area or volume.
module dual_plane_segment_integral #(parameter EXTERNAL_ALU=0) (
    output wire ext_start, output wire [1:0] ext_op,
    output wire [63:0] ext_a, ext_b,
    input wire ext_ready, ext_done, input wire [63:0] ext_result,
    input wire clk, input wire rst_n, input wire start,
    input wire [63:0] ax,ay,az,bx,by,bz,
    input wire [63:0] origin_x,origin_y,origin_z,
    input wire [63:0] normal_x,normal_y,normal_z,
    output reg busy, output reg done,
    output reg [63:0] signed_area
);
    localparam [1:0] S_IDLE=0,S_ISSUE=1,S_WAIT=2,S_FINISH=3;
    localparam [63:0] FP_NEG_HALF=64'hbfe0000000000000;
    reg [1:0] state;
    reg [4:0] op_index;
    reg alu_start;
    reg [63:0] ra_x,ra_y,ra_z,rb_x,rb_y,rb_z;
    reg [63:0] mul1,mul2,cross_x,cross_y,cross_z;
    reg [63:0] dot_x,dot_y,dot_z,partial,dot;
    reg [63:0] alu_a,alu_b;
    reg [1:0] alu_op;
    wire alu_ready,alu_done;
    wire [63:0] alu_result;

    function automatic [63:0] neg_fp(input [63:0] value);
        begin neg_fp={~value[63],value[62:0]}; end
    endfunction

    assign ext_start=alu_start;
    assign ext_op=alu_op;
    assign ext_a=alu_a;
    assign ext_b=alu_b;
    generate if(EXTERNAL_ALU) begin : external_alu
        assign alu_ready=ext_ready;
        assign alu_done=ext_done;
        assign alu_result=ext_result;
    end else begin : local_alu
        dual_plane_fp64_alu #(.ENABLE_DIVIDE(0),.ENABLE_SQRT(0))
            alu(.clk(clk),.rst_n(rst_n),.start(alu_start),
            .op(alu_op),.a(alu_a),.b(alu_b),.ready(alu_ready),
            .done(alu_done),.result(alu_result));
    end endgenerate

    always @* begin
        alu_op=2'd0; alu_a=0; alu_b=0;
        case(op_index)
            0: begin alu_a=ax;alu_b=neg_fp(origin_x);end
            1: begin alu_a=ay;alu_b=neg_fp(origin_y);end
            2: begin alu_a=az;alu_b=neg_fp(origin_z);end
            3: begin alu_a=bx;alu_b=neg_fp(origin_x);end
            4: begin alu_a=by;alu_b=neg_fp(origin_y);end
            5: begin alu_a=bz;alu_b=neg_fp(origin_z);end
            6: begin alu_op=2'd1;alu_a=ra_y;alu_b=rb_z;end
            7: begin alu_op=2'd1;alu_a=ra_z;alu_b=rb_y;end
            8: begin alu_a=mul1;alu_b=neg_fp(mul2);end
            9: begin alu_op=2'd1;alu_a=ra_z;alu_b=rb_x;end
            10:begin alu_op=2'd1;alu_a=ra_x;alu_b=rb_z;end
            11:begin alu_a=mul1;alu_b=neg_fp(mul2);end
            12:begin alu_op=2'd1;alu_a=ra_x;alu_b=rb_y;end
            13:begin alu_op=2'd1;alu_a=ra_y;alu_b=rb_x;end
            14:begin alu_a=mul1;alu_b=neg_fp(mul2);end
            15:begin alu_op=2'd1;alu_a=normal_x;alu_b=cross_x;end
            16:begin alu_op=2'd1;alu_a=normal_y;alu_b=cross_y;end
            17:begin alu_op=2'd1;alu_a=normal_z;alu_b=cross_z;end
            18:begin alu_a=dot_x;alu_b=dot_y;end
            19:begin alu_a=partial;alu_b=dot_z;end
            20:begin alu_op=2'd1;alu_a=dot;alu_b=FP_NEG_HALF;end
            default:begin end
        endcase
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            state<=S_IDLE;op_index<=0;alu_start<=0;busy<=0;done<=0;signed_area<=0;
            ra_x<=0;ra_y<=0;ra_z<=0;rb_x<=0;rb_y<=0;rb_z<=0;
            mul1<=0;mul2<=0;cross_x<=0;cross_y<=0;cross_z<=0;
            dot_x<=0;dot_y<=0;dot_z<=0;partial<=0;dot<=0;
        end else begin
            done<=0;alu_start<=0;
            case(state)
                S_IDLE: if(start) begin busy<=1;op_index<=0;state<=S_ISSUE;end
                S_ISSUE: if(alu_ready) begin alu_start<=1;state<=S_WAIT;end
                S_WAIT: if(alu_done) begin
                    case(op_index)
                        0:ra_x<=alu_result;1:ra_y<=alu_result;2:ra_z<=alu_result;
                        3:rb_x<=alu_result;4:rb_y<=alu_result;5:rb_z<=alu_result;
                        6:mul1<=alu_result;7:mul2<=alu_result;8:cross_x<=alu_result;
                        9:mul1<=alu_result;10:mul2<=alu_result;11:cross_y<=alu_result;
                        12:mul1<=alu_result;13:mul2<=alu_result;14:cross_z<=alu_result;
                        15:dot_x<=alu_result;16:dot_y<=alu_result;17:dot_z<=alu_result;
                        18:partial<=alu_result;19:dot<=alu_result;
                        20:signed_area<=alu_result;
                        default:begin end
                    endcase
                    if(op_index==20) state<=S_FINISH;
                    else begin op_index<=op_index+1'b1;state<=S_ISSUE;end
                end
                S_FINISH: begin busy<=0;done<=1;state<=S_IDLE;end
                default:state<=S_IDLE;
            endcase
        end
    end
endmodule
