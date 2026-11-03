`timescale 1ns/1ps
// Unsigned restoring division. Fixed 64-cycle latency, no combinational divide.
module lung_unsigned_divider (
    input wire clk, input wire rst_n, input wire start,
    input wire [63:0] numerator, input wire [31:0] denominator,
    output wire ready, output reg done, output reg [63:0] quotient
);
reg busy;
reg [6:0] remaining;
reg [63:0] bits;
reg [31:0] divisor;
reg [32:0] remainder;
wire [32:0] shifted={remainder[31:0],bits[63]};
wire subtract=shifted>={1'b0,divisor};
assign ready=!busy;
always @(posedge clk) begin
    if(!rst_n) begin
        busy<=0;done<=0;quotient<=0;remaining<=0;bits<=0;divisor<=0;remainder<=0;
    end else begin
        done<=0;
        if(start&&!busy) begin
            busy<=1;remaining<=64;bits<=numerator;divisor<=denominator;remainder<=0;
        end else if(busy) begin
            remainder<=subtract?shifted-{1'b0,divisor}:shifted;
            bits<={bits[62:0],subtract};
            remaining<=remaining-1;
            if(remaining==1) begin
                quotient<={bits[62:0],subtract};busy<=0;done<=1;
            end
        end
    end
end
endmodule
