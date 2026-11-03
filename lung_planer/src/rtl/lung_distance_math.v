`timescale 1ns/1ps
// Shared exact integer arithmetic for point-to-triangle distance. No division
// operator or floating point. Signed product (140 x 70) and unsigned quotient
// (210 / 140) cover every signed Q16.16 input, including 33-bit differences.
module lung_distance_math (
    input wire clk, rst_n, start, divide,
    input wire signed [139:0] a,
    input wire signed [69:0] b,
    input wire [209:0] numerator,
    input wire [139:0] denominator,
    output wire ready, output reg done,
    output reg signed [209:0] result
);
reg busy, division, negative;
reg [7:0] remaining;
reg [209:0] multiplicand, accumulator, bits;
reg [209:0] multiplicand_three;
reg [69:0] multiplier;
reg [139:0] divisor;
reg [140:0] remainder;
reg [1:0] normalize;
reg [7:0] numerator_width, divisor_width;
// A balanced leading-bit encoder. Register the widths before the variable
// alignment shifts so the encoder and barrel shifter are in different cycles.
function [7:0] bit_width;
 input [255:0] value;
 reg [255:0] v;
 reg [7:0] width;
 begin
  v=value;width=0;
  if(|v[255:128])begin v=v>>128;width=width+128;end
  if(|v[127:64])begin v=v>>64;width=width+64;end
  if(|v[63:32])begin v=v>>32;width=width+32;end
  if(|v[31:16])begin v=v>>16;width=width+16;end
  if(|v[15:8])begin v=v>>8;width=width+8;end
  if(|v[7:4])begin v=v>>4;width=width+4;end
  if(|v[3:2])begin v=v>>2;width=width+2;end
  if(v[1])begin v=v>>1;width=width+1;end
  bit_width=(value==0)?0:width+1;
 end
endfunction
wire [7:0] quotient_width=numerator_width-divisor_width+8'd1;
wire [140:0] shifted={remainder[139:0],bits[209]};
wire subtract=shifted>={1'b0,divisor};
wire [139:0] magnitude_a=a[139]?-a:a;
wire [209:0] initial_multiplicand={70'd0,magnitude_a};
wire [209:0] addend=multiplier[1:0]==0?210'd0:
 multiplier[1:0]==1?multiplicand:
 multiplier[1:0]==2?(multiplicand<<1):multiplicand_three;
wire [209:0] sum=accumulator+addend;
assign ready=!busy;
always @(posedge clk) begin
    if(!rst_n) begin
        busy<=0;done<=0;result<=0;remaining<=0;division<=0;negative<=0;
        multiplicand<=0;multiplicand_three<=0;multiplier<=0;accumulator<=0;bits<=0;divisor<=0;remainder<=0;
        normalize<=0;numerator_width<=0;divisor_width<=0;
    end else begin
        done<=0;
        if(start&&!busy) begin
            busy<=1;division<=divide;remaining<=divide?210:35;
            normalize<=divide?1:0;
            negative<=a[139]^b[69];
            multiplicand<=initial_multiplicand;
            multiplicand_three<=initial_multiplicand+(initial_multiplicand<<1);
            multiplier<=b[69]?-b:b;accumulator<=0;
            bits<=numerator;divisor<=denominator;remainder<=0;
        end else if(busy) begin
            if(division) begin
                if(normalize==1)begin
                    numerator_width<=bit_width({46'd0,bits});
                    divisor_width<=bit_width({116'd0,divisor});
                    normalize<=2;
                end else if(normalize==2)begin
                    normalize<=0;
                    // Keep the legacy divide-by-zero result (all quotient bits
                    // set). Normal distance callers reject a zero denominator.
                    if(divisor==0)begin result<={210{1'b1}};busy<=0;done<=1;end
                    else if(numerator_width<divisor_width)begin result<=0;busy<=0;done<=1;end
                    else begin
                        // The skipped prefix is strictly below the divisor.
                        // Only quotient_width restoring steps are necessary.
                        remainder<=bits>>quotient_width;
                        bits<=bits<<(8'd210-quotient_width);
                        remaining<=quotient_width;
                    end
                end else begin
                    remaining<=remaining-1;
                    remainder<=subtract?shifted-{1'b0,divisor}:shifted;
                    bits<={bits[208:0],subtract};
                    if(remaining==1) begin result<={bits[208:0],subtract};busy<=0;done<=1;end
                end
            end else begin
                remaining<=remaining-1;
                accumulator<=sum;multiplicand<=multiplicand<<2;
                multiplicand_three<=multiplicand_three<<2;multiplier<=multiplier>>2;
                if(remaining==1 || multiplier[69:2]==0) begin result<=negative?-$signed(sum):$signed(sum);busy<=0;done<=1;end
            end
        end
    end
end
endmodule
