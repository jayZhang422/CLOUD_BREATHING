`timescale 1ns/1ps
// Conservative AABB classification and translated source-volume aggregate.
// Plane order is original descriptor order; 0 and 3 are nonbinding caps.
module dual_plane_bvh_classify #(parameter EXTERNAL_ALU=0) (
    input wire clk,rst_n,start,
    input wire [191:0] lower,upper,
    input wire [1023:0] planes,
    input wire [191:0] center,origin,flux,
    input wire [63:0] node_volume,
    output reg done,busy,outside,inside,cap_binding,
    output reg [63:0] volume,
    output wire ext_start, output wire [1:0] ext_op, output wire [63:0] ext_a,ext_b,
    input wire ext_ready,ext_done,input wire [63:0] ext_result,
    output reg numeric_error
);
    localparam IDLE=0,RUN=1,DECIDE=2,FINISH=3;
    localparam [62:0] EPS=63'h3e7ad7f29abcaf48;
    reg [1:0] state,sa,ra;
    reg [3:0] phase,sent,received,length;
    reg safe_arithmetic,bounded_inputs;
    integer bounded_index;
    // Magnitudes below 2^257 bound every classification product/sum and
    // translated-volume intermediate far below FP64 overflow. Otherwise
    // execute the original operations, including their numeric diagnostics.
    always @* begin
        bounded_inputs=1'b1;
        for(bounded_index=0;bounded_index<16;bounded_index=bounded_index+1)
            bounded_inputs=bounded_inputs && planes[bounded_index*64+60+:3]<3'd5;
        for(bounded_index=0;bounded_index<3;bounded_index=bounded_index+1) begin
            bounded_inputs=bounded_inputs && lower[bounded_index*64+60+:3]<3'd5;
            bounded_inputs=bounded_inputs && upper[bounded_index*64+60+:3]<3'd5;
            bounded_inputs=bounded_inputs && center[bounded_index*64+60+:3]<3'd5;
            bounded_inputs=bounded_inputs && origin[bounded_index*64+60+:3]<3'd5;
            bounded_inputs=bounded_inputs && flux[bounded_index*64+60+:3]<3'd5;
        end
        bounded_inputs=bounded_inputs && node_volume[62:60]<3'd5;
    end
    // Six contexts for bounded inputs; eight for unsafe inputs, retaining
    // all former intermediate numeric diagnostics even when not classified.
    (* ram_style="distributed" *) reg [63:0] px[0:7],py[0:7],pz[0:7],acc[0:7];
    function [63:0] neg(input [63:0] x);begin neg={~x[63],x[62:0]};end endfunction
    function [2:0] sample(input [3:0] i,input safe);
        begin sample=safe ? (i==0?3'd1:i==5?3'd7:i[2:0]+1'b1) : i[2:0];end
    endfunction
    wire [2:0] source_sample=sample(sent,safe_arithmetic),target_sample=sample(received,safe_arithmetic);
    wire [1:0] source_plane=source_sample[2:1],target_plane=target_sample[2:1];
    wire select_max=source_sample[0];
    wire [63:0] normal=planes[source_plane*256+sa*64+:64];
    wire [63:0] offset=planes[source_plane*256+192+:64];
    reg [1:0] op;reg [63:0] a,b;
    wire ready,result_valid;wire [63:0] result;
    wire request=state==RUN && sent<length;
    assign ext_start=request;assign ext_op=op;assign ext_a=a;assign ext_b=b;
    generate if(EXTERNAL_ALU) begin
        assign ready=ext_ready;assign result_valid=ext_done;assign result=ext_result;
    end else begin
        dual_plane_fp64_alu #(.PIPELINED(1),.ENABLE_DIVIDE(0),.ENABLE_SQRT(0)) alu(
            .clk(clk),.rst_n(rst_n),.start(request),.op(op),.a(a),.b(b),
            .ready(ready),.done(result_valid),.result(result));
    end endgenerate
    always @* begin
        length=phase<4?(safe_arithmetic?6:8):phase<6?3:1;
        op=(phase==0||phase==5)?1:0;a=0;b=0;
        case(phase)
        0:begin a=normal;b=(normal[63]^select_max)?upper[sa*64+:64]:lower[sa*64+:64];end
        1:begin a=px[sent];b=py[sent];end
        2:begin a=acc[sent];b=pz[sent];end
        3:begin a=acc[sent];b=neg(offset);end
        4:begin a=origin[sent*64+:64];b=neg(center[sent*64+:64]);end
        5:begin a=acc[sent];b=flux[sent*64+:64];end
        6:begin a=acc[0];b=acc[1];end
        7:begin a=acc[0];b=acc[2];end
        8:begin a=node_volume;b=neg(acc[0]);end
        endcase
    end
    always @(posedge clk) begin
        if(!rst_n) begin state<=IDLE;phase<=0;sent<=0;received<=0;sa<=0;ra<=0;
            done<=0;busy<=0;outside<=0;inside<=0;cap_binding<=0;volume<=0;
            numeric_error<=0;safe_arithmetic<=0;end
        else begin
            done<=0;
            case(state)
            IDLE:if(start) begin busy<=1;outside<=0;inside<=1;cap_binding<=0;numeric_error<=0;
                safe_arithmetic<=bounded_inputs;phase<=0;sent<=0;received<=0;sa<=0;ra<=0;state<=RUN;end
            RUN:begin
                if(request&&ready) begin
                    if(phase==0&&sa<2) sa<=sa+1'b1;
                    else begin sa<=0;sent<=sent+1'b1;end
                end
                if(result_valid) begin
                    if(result[62:52]==11'h7ff) numeric_error<=1;
                    if(phase==0) case(ra) 0:px[received]<=result;1:py[received]<=result;2:pz[received]<=result;endcase
                    else acc[received]<=result;
                    if(phase==3) begin
                        if(!target_sample[0]&&(target_plane==1||target_plane==2)&&!result[63]&&result[62:0]>EPS) outside<=1;
                        if(target_sample[0]&&(!result[63]||result[62:0]<=EPS)) begin
                            inside<=0;if(target_plane==0||target_plane==3) cap_binding<=1;end
                    end
                    if(phase==8) volume<=result;
                    if(phase==0&&ra<2) ra<=ra+1'b1;
                    else begin
                        ra<=0;received<=received+1'b1;
                        if(received+1==length) begin
                            sent<=0;received<=0;phase<=phase+1'b1;
                            if(phase==3) state<=DECIDE;
                            if(phase==8) state<=FINISH;
                        end
                    end
                end
            end
            DECIDE:if(safe_arithmetic&&(outside||!inside)) begin volume<=0;state<=FINISH;end else state<=RUN;
            FINISH:begin busy<=0;done<=1;state<=IDLE;end
            default:state<=IDLE;
            endcase
        end
    end
endmodule
