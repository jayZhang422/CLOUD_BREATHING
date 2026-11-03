`timescale 1ns/1ps

// One-at-a-time IEEE-754 double operation service.  The arithmetic is kept
// in generated Vivado Floating Point IP; this wrapper only provides the
// deterministic request/done contract used by the clipping state machine.
module dual_plane_fp64_alu #(
    parameter integer ENABLE_MULTIPLY=1,
    parameter integer ENABLE_DIVIDE=1,
    parameter integer ENABLE_SQRT=1,
    parameter integer PIPELINED=0
) (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [1:0] op,       // 0 add, 1 multiply, 2 divide, 3 sqrt
    input wire [63:0] a,
    input wire [63:0] b,
    output wire ready,
    output reg done,
    output reg [63:0] result
);
    generate if(PIPELINED) begin : streaming
        wire result_valid; wire [63:0] stream_result;
        dual_plane_fp64_epoch_alu #(.ENABLE_SQRT(ENABLE_SQRT),.ENABLE_DIVIDE(ENABLE_DIVIDE)) stream(
            .clk(clk),.rst_n(rst_n),.req_valid(start),.op(op),.a(a),.b(b),.req_ready(ready),
            .result_valid(result_valid),.result_ready(1'b1),.result(stream_result));
        always @* begin done=result_valid;result=stream_result;end
    end else begin : serial
`ifdef DPM_SIM_FAST
    reg busy;
    real lhs,rhs,value;
    assign ready = !busy;
    always @(posedge clk) begin
        if(!rst_n) begin busy<=0;done<=0;result<=0;end
        else begin
            done<=0;
            if(!busy && start) begin
                lhs=$bitstoreal(a);rhs=$bitstoreal(b);
                case(op)
                    0:value=lhs+rhs;
                    1:value=lhs*rhs;
                    2:value=lhs/rhs;
                    default:value=$sqrt(lhs);
                endcase
                result<=$realtobits(value);busy<=1;
            end else if(busy) begin busy<=0;done<=1;end
        end
    end
`else
    reg busy;
    reg [1:0] op_reg;
    reg [63:0] a_reg, b_reg;
    wire add_a_ready, add_b_ready, add_operation_ready, add_valid; wire [63:0] add_result;
    wire mul_a_ready, mul_b_ready, mul_valid; wire [63:0] mul_result;
    wire div_a_ready, div_b_ready, div_valid; wire [63:0] div_result;
    wire sqrt_a_ready, sqrt_valid; wire [63:0] sqrt_result;
    reg a_sent, b_sent, operation_sent;
    wire issue_add = busy && op_reg==2'd0;
    wire issue_mul = busy && op_reg==2'd1;
    wire issue_div = busy && op_reg==2'd2;
    wire issue_sqrt = busy && op_reg==2'd3;
    assign ready = !busy;
    dpm_fp_add add_ip (.aclk(clk), .aresetn(rst_n), .s_axis_a_tvalid(issue_add && !a_sent), .s_axis_a_tready(add_a_ready),
        .s_axis_a_tdata(a_reg), .s_axis_b_tvalid(issue_add && !b_sent), .s_axis_b_tready(add_b_ready),
        .s_axis_operation_tvalid(issue_add && !operation_sent), .s_axis_operation_tready(add_operation_ready),
        .s_axis_operation_tdata(8'd0),
        .s_axis_b_tdata(b_reg), .m_axis_result_tvalid(add_valid), .m_axis_result_tready(1'b1),
        .m_axis_result_tdata(add_result));
    if(ENABLE_MULTIPLY) begin : gen_mul
    dpm_fp_mul mul_ip (.aclk(clk), .aresetn(rst_n), .s_axis_a_tvalid(issue_mul && !a_sent), .s_axis_a_tready(mul_a_ready),
        .s_axis_a_tdata(a_reg), .s_axis_b_tvalid(issue_mul && !b_sent), .s_axis_b_tready(mul_b_ready),
        .s_axis_b_tdata(b_reg), .m_axis_result_tvalid(mul_valid), .m_axis_result_tready(1'b1),
        .m_axis_result_tdata(mul_result));
    end else begin : no_mul
        assign mul_a_ready=0; assign mul_b_ready=0; assign mul_valid=0; assign mul_result=0;
    end
    if(ENABLE_DIVIDE) begin : gen_div
    dpm_fp_divide div_ip (.aclk(clk), .aresetn(rst_n), .s_axis_a_tvalid(issue_div && !a_sent), .s_axis_a_tready(div_a_ready),
        .s_axis_a_tdata(a_reg), .s_axis_b_tvalid(issue_div && !b_sent), .s_axis_b_tready(div_b_ready),
        .s_axis_b_tdata(b_reg), .m_axis_result_tvalid(div_valid), .m_axis_result_tready(1'b1),
        .m_axis_result_tdata(div_result));
    end else begin : no_div
        assign div_a_ready=0; assign div_b_ready=0; assign div_valid=0; assign div_result=0;
    end
    if(ENABLE_SQRT) begin : gen_sqrt
    dpm_fp_sqrt sqrt_ip (.aclk(clk), .aresetn(rst_n), .s_axis_a_tvalid(issue_sqrt && !a_sent), .s_axis_a_tready(sqrt_a_ready),
        .s_axis_a_tdata(a_reg), .m_axis_result_tvalid(sqrt_valid), .m_axis_result_tready(1'b1),
        .m_axis_result_tdata(sqrt_result));
    end else begin : no_sqrt
        assign sqrt_a_ready=0; assign sqrt_valid=0; assign sqrt_result=0;
    end
    always @(posedge clk) begin
        if(!rst_n) begin busy<=1'b0; op_reg<=0; a_reg<=0; b_reg<=0; done<=1'b0; result<=0; a_sent<=0; b_sent<=0; operation_sent<=0; end
        else begin
            done<=1'b0;
            if(!busy && start) begin
                busy<=1'b1; op_reg<=op; a_reg<=a; b_reg<=b;
                a_sent<=0; b_sent<=0; operation_sent<=0;
            end else if(busy) begin
                if((op_reg==0 && add_valid) || (op_reg==1 && mul_valid) ||
                   (op_reg==2 && div_valid) || (op_reg==3 && sqrt_valid)) begin
                    busy<=1'b0; done<=1'b1;
                    case(op_reg)
                        2'd0: result<=add_result;
                        2'd1: result<=mul_result;
                        2'd2: result<=div_result;
                        default: result<=sqrt_result;
                    endcase
                end else begin
                    case(op_reg)
                        2'd0: begin
                            if(!a_sent && add_a_ready) a_sent<=1;
                            if(!b_sent && add_b_ready) b_sent<=1;
                            if(!operation_sent && add_operation_ready) operation_sent<=1;
                        end
                        2'd1: begin
                            if(!a_sent && mul_a_ready) a_sent<=1;
                            if(!b_sent && mul_b_ready) b_sent<=1;
                        end
                        2'd2: begin
                            if(!a_sent && div_a_ready) a_sent<=1;
                            if(!b_sent && div_b_ready) b_sent<=1;
                        end
                        default: if(!a_sent && sqrt_a_ready) a_sent<=1;
                    endcase
                end
            end
        end
    end
`endif
    end endgenerate
endmodule

module dual_plane_fp64_epoch_alu #(parameter ENABLE_DIVIDE=1, ENABLE_SQRT=1)(
    input clk, rst_n, req_valid, input [1:0] op,
    input [63:0] a,b, output req_ready,
    output result_valid, input result_ready, output [63:0] result
);
`ifdef DPM_SIM_FAST
    reg dv;reg [63:0] dr;real lhs,rhs,val;
    assign req_ready=!dv||result_ready;
    assign result_valid=dv;assign result=dr;
    always @(posedge clk) begin
        if(!rst_n) begin dv<=0;dr<=0;end
        else if(req_ready) begin
            dv<=req_valid;
            if(req_valid) begin
                lhs=$bitstoreal(a);rhs=$bitstoreal(b);
                case(op) 0:val=lhs+rhs;1:val=lhs*rhs;2:val=lhs/rhs;3:val=$sqrt(lhs);endcase
                dr<=$realtobits(val);
            end
        end
    end
`else
    wire multiply=op==1;
    reg a_sent,b_sent,op_sent;
    wire d_ar,d_br,s_ar,dv,sv;wire [63:0] dr,sr;
    wire ar,br,opr,m_ar,m_br,a_ar,a_br,a_opr;
    wire mv,av; wire [63:0] mr,adr;
    assign ar=op==0?a_ar:op==1?m_ar:op==2?d_ar:s_ar;
    assign br=op==0?a_br:op==1?m_br:op==2?d_br:1'b1;
    assign opr=op==0?a_opr:1'b1;
    assign req_ready=(a_sent||ar)&&(b_sent||br)&&(op_sent||opr);
    assign result_valid=mv||av||dv||sv;
    assign result=mv?mr:av?adr:dv?dr:sr;
    dpm_fp_mul mul(.aclk(clk),.aresetn(rst_n),
        .s_axis_a_tvalid(req_valid&&multiply&&!a_sent),.s_axis_a_tready(m_ar),.s_axis_a_tdata(a),
        .s_axis_b_tvalid(req_valid&&multiply&&!b_sent),.s_axis_b_tready(m_br),.s_axis_b_tdata(b),
        .m_axis_result_tvalid(mv),.m_axis_result_tready(result_ready),.m_axis_result_tdata(mr));
    dpm_fp_add add(.aclk(clk),.aresetn(rst_n),
        .s_axis_a_tvalid(req_valid&&(op==0)&&!a_sent),.s_axis_a_tready(a_ar),.s_axis_a_tdata(a),
        .s_axis_b_tvalid(req_valid&&(op==0)&&!b_sent),.s_axis_b_tready(a_br),.s_axis_b_tdata(b),
        .s_axis_operation_tvalid(req_valid&&(op==0)&&!op_sent),.s_axis_operation_tready(a_opr),.s_axis_operation_tdata(8'd0),
        .m_axis_result_tvalid(av),.m_axis_result_tready(result_ready),.m_axis_result_tdata(adr));
    generate if(ENABLE_DIVIDE) begin : divide_enabled
    dpm_fp_divide divide(.aclk(clk),.aresetn(rst_n),
        .s_axis_a_tvalid(req_valid&&(op==2)&&!a_sent),.s_axis_a_tready(d_ar),.s_axis_a_tdata(a),
        .s_axis_b_tvalid(req_valid&&(op==2)&&!b_sent),.s_axis_b_tready(d_br),.s_axis_b_tdata(b),
        .m_axis_result_tvalid(dv),.m_axis_result_tready(result_ready),.m_axis_result_tdata(dr));
    end else begin assign d_ar=0;assign d_br=0;assign dv=0;assign dr=0;end
    if(ENABLE_SQRT) begin : sqrt_enabled
    dpm_fp_sqrt sqrt(.aclk(clk),.aresetn(rst_n),
        .s_axis_a_tvalid(req_valid&&(op==3)&&!a_sent),.s_axis_a_tready(s_ar),.s_axis_a_tdata(a),
        .m_axis_result_tvalid(sv),.m_axis_result_tready(result_ready),.m_axis_result_tdata(sr));
    end else begin assign s_ar=0;assign sv=0;assign sr=0;end endgenerate
    always @(posedge clk) begin
        if(!rst_n) begin a_sent<=0;b_sent<=0;op_sent<=0;end
        else if(req_valid) begin
            if(req_ready) begin a_sent<=0;b_sent<=0;op_sent<=0;end
            else begin
                if(ar) a_sent<=1;
                if(br) b_sent<=1;
                if(opr) op_sent<=1;
            end
        end
    end
`endif
endmodule

