`timescale 1ns/1ps

// IEEE-754 triangle-fan reducer for one clipped convex polygon.  This stage
// reports source-face contributions.  For a two-plane wedge, an origin on
// the common ridge makes the flux through both cut faces identically zero.
module dual_plane_polygon_reduce #(parameter EXTERNAL_ALU=0) (
    input wire clk, input wire rst_n, input wire start,
    input wire [3:0] polygon_count,
    input wire [447:0] in_x, in_y, in_z,
    input wire [63:0] origin_x, origin_y, origin_z,
    output reg busy, output reg done, output reg valid,
    output reg [63:0] signed_volume, output reg [63:0] area,
    output wire ext_start,output wire [1:0] ext_op,output wire [63:0] ext_a,ext_b,
    input wire ext_ready,ext_done,input wire [63:0] ext_result,
    output reg [31:0] triangle_count
);
    // Homogeneous operation epochs preserve every FP64 expression and the
    // original fan accumulation order. No operation type changes in flight.
    localparam IDLE=0,LOAD=1,RUN=2,NEXT=3,FINISH=4;
    reg [2:0] state;
    reg [3:0] phase, sent, received, count, fan;
    reg [63:0] ax,ay,az,bx,by,bz,cx,cy,cz;
    reg [63:0] accum_volume,accum_area;
    // Each result is written before reading; data RAM needs no reset.
    reg [63:0] r[0:32];
    reg [3:0] length;
    reg [1:0] op;
    reg [63:0] a,b;
    wire ready,result_valid;wire [63:0] result;
    wire request=state==RUN && sent<length;
    function [63:0] neg(input [63:0] x);begin neg={~x[63],x[62:0]};end endfunction
    function [5:0] slot(input [3:0] epoch,input [3:0] index);
    begin slot=0;case(epoch)
        0:case(index) 0:slot=30;1:slot=31;2:slot=32;3:slot=0;4:slot=1;5:slot=2;6:slot=3;7:slot=4;8:slot=5; endcase
        1:case(index) 0:slot=6;1:slot=7;2:slot=9;3:slot=10;4:slot=12;5:slot=13; endcase
        2:case(index) 0:slot=8;1:slot=11;2:slot=14; endcase
        3:case(index) 0:slot=15;1:slot=16;2:slot=17;3:slot=21;4:slot=22;5:slot=23; endcase
        4:case(index) 0:slot=18;1:slot=24; endcase
        5:case(index) 0:slot=19;1:slot=25; endcase
        6:case(index) 0:slot=20; endcase
        7:case(index) 0:slot=26; endcase
        8:case(index) 0:slot=27; endcase
        9:case(index) 0:slot=28;1:slot=29; endcase
    endcase end endfunction
    wire [5:0] issue_slot=slot(phase,sent), result_slot=slot(phase,received);
    always @* begin
        length=1;op=0;
        case(phase)
        0:begin length=9;op=0;end
        1:begin length=6;op=1;end
        2:begin length=3;op=0;end
        3:begin length=6;op=1;end
        4:begin length=2;op=0;end
        5:begin length=2;op=0;end
        6:begin length=1;op=2;end
        7:begin length=1;op=3;end
        8:begin length=1;op=1;end
        9:begin length=2;op=0;end
        endcase
        a=0;b=0;case(issue_slot)
        0:begin a=bx;b=neg(ax);end
        1:begin a=by;b=neg(ay);end
        2:begin a=bz;b=neg(az);end
        3:begin a=cx;b=neg(ax);end
        4:begin a=cy;b=neg(ay);end
        5:begin a=cz;b=neg(az);end
        6:begin a=r[1];b=r[5];end
        7:begin a=r[2];b=r[4];end
        8:begin a=r[6];b=neg(r[7]);end
        9:begin a=r[2];b=r[3];end
        10:begin a=r[0];b=r[5];end
        11:begin a=r[9];b=neg(r[10]);end
        12:begin a=r[0];b=r[4];end
        13:begin a=r[1];b=r[3];end
        14:begin a=r[12];b=neg(r[13]);end
        15:begin a=r[30];b=r[8];end
        16:begin a=r[31];b=r[11];end
        17:begin a=r[32];b=r[14];end
        18:begin a=r[15];b=r[16];end
        19:begin a=r[18];b=r[17];end
        20:begin a=r[19];b=64'h4018000000000000;end
        21:begin a=r[8];b=r[8];end
        22:begin a=r[11];b=r[11];end
        23:begin a=r[14];b=r[14];end
        24:begin a=r[21];b=r[22];end
        25:begin a=r[24];b=r[23];end
        26:begin a=r[25];b=64'd0;end
        27:begin a=r[26];b=64'h3fe0000000000000;end
        28:begin a=accum_volume;b=r[20];end
        29:begin a=accum_area;b=r[27];end
        30:begin a=ax;b=neg(origin_x);end
        31:begin a=ay;b=neg(origin_y);end
        32:begin a=az;b=neg(origin_z);end
        endcase
    end
    assign ext_start=request;assign ext_op=op;assign ext_a=a;assign ext_b=b;
    generate if(EXTERNAL_ALU) begin
        assign ready=ext_ready;assign result_valid=ext_done;assign result=ext_result;
    end else begin
        dual_plane_fp64_alu #(.PIPELINED(1)) alu(.clk(clk),.rst_n(rst_n),
            .start(request),.op(op),.a(a),.b(b),.ready(ready),.done(result_valid),.result(result));
    end endgenerate
    always @(posedge clk) begin
        if(!rst_n) begin state<=IDLE;busy<=0;done<=0;valid<=0;phase<=0;sent<=0;received<=0;
            count<=0;fan<=0;triangle_count<=0;signed_volume<=0;area<=0;end
        else begin
            done<=0;
            case(state)
            IDLE:if(start) begin busy<=1;valid<=0;count<=polygon_count>7?7:polygon_count;fan<=1;
                accum_volume<=0;accum_area<=0;triangle_count<=0;
                state<=polygon_count>=3?LOAD:FINISH;end
            LOAD:begin
                ax<=in_x[63:0];ay<=in_y[63:0];az<=in_z[63:0];
                bx<=in_x[fan*64+:64];by<=in_y[fan*64+:64];bz<=in_z[fan*64+:64];
                cx<=in_x[(fan+1)*64+:64];cy<=in_y[(fan+1)*64+:64];cz<=in_z[(fan+1)*64+:64];
                phase<=0;sent<=0;received<=0;state<=RUN;end
            RUN:begin
                if(request&&ready) sent<=sent+1'b1;
                if(result_valid) begin
                    r[result_slot]<=result;
                    if(result_slot==28) accum_volume<=result;
                    if(result_slot==29) accum_area<=result;
                    received<=received+1'b1;
                    if(received+1==length) begin
                        sent<=0;received<=0;phase<=phase+1'b1;
                        if(phase==9) state<=NEXT;
                    end
                end
            end
            NEXT:begin triangle_count<=triangle_count+1;
                if(fan+2>=count) state<=FINISH;else begin fan<=fan+1'b1;state<=LOAD;end end
            FINISH:begin signed_volume<=accum_volume;area<=accum_area;
                valid<=count>=3;busy<=0;done<=1;state<=IDLE;end
            default:state<=IDLE;
            endcase
        end
    end
endmodule
