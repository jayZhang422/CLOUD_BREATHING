`timescale 1ns/1ps
// Integrate sorted unique forward crossings over [0,L]. Q2.30 fraction.
// The caller supplies parity from the FULL crossing list before clipping.
// Zero crossings are skipped, matching the PS reference's open endpoint rule.
module lung_ray_volume_core (
    input wire clk, input wire rst_n, input wire start,
    input wire [31:0] length_q16, input wire [31:0] crossing_count,
    input wire origin_inside,
    output reg [31:0] crossing_index, input wire signed [31:0] crossing_q16,
    output reg done, output reg error, output reg [31:0] fraction_q30
);
localparam IDLE=0, GET=1, DIV_START=2, DIV_WAIT=3, SQUARE=4,
           CUBE=5, ACCUMULATE=6, FINISH=7;
reg [3:0] state;
reg inside_segment;
reg [31:0] length_reg, count_reg, endpoint, ratio, square_q30, cube_q30;
reg signed [63:0] integral;
wire signed [63:0] final_value=integral+(inside_segment?64'sd1073741824:64'sd0);
wire [63:0] square_product={32'd0,ratio}*ratio;
wire [63:0] cube_product={32'd0,square_q30}*ratio;
wire div_done, div_ready;
wire [63:0] quotient;
lung_unsigned_divider divide (
    .clk(clk),.rst_n(rst_n),.start(state==DIV_START),
    .numerator({2'd0,endpoint,30'd0}),.denominator(length_reg),
    .ready(div_ready),.done(div_done),.quotient(quotient));
always @(posedge clk) begin
    if(!rst_n) begin
        state<=IDLE;done<=0;error<=0;fraction_q30<=0;crossing_index<=0;
        inside_segment<=0;length_reg<=0;count_reg<=0;endpoint<=0;ratio<=0;
        square_q30<=0;cube_q30<=0;integral<=0;
    end else begin
        done<=0;
        case(state)
            IDLE:if(start) begin
                error<=0;fraction_q30<=0;crossing_index<=0;integral<=0;
                length_reg<=length_q16;count_reg<=crossing_count;inside_segment<=origin_inside;
                if(length_q16==0||length_q16[31]) begin error<=1;state<=FINISH;end
                else state<=GET;
            end
            GET:if(crossing_index>=count_reg||crossing_q16>= $signed(length_reg))state<=FINISH;
                else if(crossing_q16<=0)crossing_index<=crossing_index+1;
                else begin endpoint<=crossing_q16;state<=DIV_START;end
            DIV_START:if(div_ready)state<=DIV_WAIT;
            DIV_WAIT:if(div_done)begin ratio<=quotient[31:0];state<=SQUARE;end
            SQUARE:begin square_q30<=square_product[61:30];state<=CUBE;end
            CUBE:begin cube_q30<=cube_product[61:30];state<=ACCUMULATE;end
            ACCUMULATE:begin
                integral<=inside_segment?integral+$signed({32'd0,cube_q30}):integral-$signed({32'd0,cube_q30});
                inside_segment<=!inside_segment;crossing_index<=crossing_index+1;state<=GET;
            end
            FINISH:begin
                if(error||final_value<0||final_value>64'sd1073741824)begin fraction_q30<=0;error<=1;end
                else fraction_q30<=final_value[31:0];
                done<=1;state<=IDLE;
            end
            default:state<=IDLE;
        endcase
    end
end
endmodule
