`timescale 1ns/1ps
// Classify one frozen Lee boundary neighborhood. This block never deletes a
// voxel. The PS coordinator must recheck accepted points in reference C order.
module centerline_lee_candidate (
    input wire clk, rst_n,
    input wire [26:0] s_neighborhood,
    input wire s_valid,
    output wire s_ready,
    output reg m_candidate,
    output wire m_valid,
    input wire m_ready
);
    `include "centerline_lee_tables.vh"
    localparam IDLE=0, PRECHECK=1, CONNECT=2, OUTPUT=3;
    reg [1:0] state;
    reg [26:0] neighbors, reached;
    reg [3:0] steps;
    reg center_present;
    reg [5:0] foreground_count;
    reg signed [7:0] euler_sum;
    wire [26:0] input_neighbors = s_neighborhood & ~(27'd1<<13);
    wire [26:0] seed = input_neighbors & (~input_neighbors + 27'd1);
    function [5:0] popcount(input [26:0] n);
        integer i;
        begin
            popcount=0;
            for(i=0;i<27;i=i+1) popcount=popcount+n[i];
        end
    endfunction
    function signed [7:0] euler(input [6:0] address);
        reg signed [3:0] value;
        begin
            value=LEE_EULER_LUT[address*4 +: 4];
            euler={{4{value[3]}},value};
        end
    endfunction
    wire signed [7:0] term0=euler({s_neighborhood[2],s_neighborhood[1],s_neighborhood[11],s_neighborhood[10],s_neighborhood[5],s_neighborhood[4],s_neighborhood[14]});
    wire signed [7:0] term1=euler({s_neighborhood[0],s_neighborhood[9],s_neighborhood[3],s_neighborhood[12],s_neighborhood[1],s_neighborhood[10],s_neighborhood[4]});
    wire signed [7:0] term2=euler({s_neighborhood[8],s_neighborhood[7],s_neighborhood[17],s_neighborhood[16],s_neighborhood[5],s_neighborhood[4],s_neighborhood[14]});
    wire signed [7:0] term3=euler({s_neighborhood[6],s_neighborhood[15],s_neighborhood[7],s_neighborhood[16],s_neighborhood[3],s_neighborhood[12],s_neighborhood[4]});
    wire signed [7:0] term4=euler({s_neighborhood[20],s_neighborhood[23],s_neighborhood[19],s_neighborhood[22],s_neighborhood[11],s_neighborhood[14],s_neighborhood[10]});
    wire signed [7:0] term5=euler({s_neighborhood[18],s_neighborhood[21],s_neighborhood[9],s_neighborhood[12],s_neighborhood[19],s_neighborhood[22],s_neighborhood[10]});
    wire signed [7:0] term6=euler({s_neighborhood[26],s_neighborhood[23],s_neighborhood[17],s_neighborhood[14],s_neighborhood[25],s_neighborhood[22],s_neighborhood[16]});
    wire signed [7:0] term7=euler({s_neighborhood[24],s_neighborhood[25],s_neighborhood[15],s_neighborhood[16],s_neighborhood[21],s_neighborhood[22],s_neighborhood[12]});
    // Each occupied 2x2x2 octant is a clique under 26-connectivity.
    // Closure across the eight cliques requires at most eight expansions.
    wire [26:0] next_reached = reached |
        ((|(reached&LEE_OCTANT_0)) ? neighbors&LEE_OCTANT_0 : 27'd0) |
        ((|(reached&LEE_OCTANT_1)) ? neighbors&LEE_OCTANT_1 : 27'd0) |
        ((|(reached&LEE_OCTANT_2)) ? neighbors&LEE_OCTANT_2 : 27'd0) |
        ((|(reached&LEE_OCTANT_3)) ? neighbors&LEE_OCTANT_3 : 27'd0) |
        ((|(reached&LEE_OCTANT_4)) ? neighbors&LEE_OCTANT_4 : 27'd0) |
        ((|(reached&LEE_OCTANT_5)) ? neighbors&LEE_OCTANT_5 : 27'd0) |
        ((|(reached&LEE_OCTANT_6)) ? neighbors&LEE_OCTANT_6 : 27'd0) |
        ((|(reached&LEE_OCTANT_7)) ? neighbors&LEE_OCTANT_7 : 27'd0);
    assign s_ready=state==IDLE;
    assign m_valid=state==OUTPUT;
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=IDLE; neighbors<=0; reached<=0; steps<=0;
            foreground_count<=0; center_present<=0; euler_sum<=0; m_candidate<=0;
        end else case(state)
            IDLE: if(s_valid&&s_ready) begin
                neighbors<=input_neighbors; reached<=seed; steps<=0;
                foreground_count<=popcount(s_neighborhood);
                center_present<=s_neighborhood[13];
                euler_sum<=((term0+term1)+(term2+term3))+((term4+term5)+(term6+term7));
                state<=PRECHECK;
            end
            PRECHECK: begin
                if(!center_present||foreground_count==2||euler_sum!=0) begin
                    m_candidate<=0; state<=OUTPUT;
                end else state<=CONNECT;
            end
            CONNECT: begin
                reached<=next_reached; steps<=steps+1;
                if(next_reached==neighbors||next_reached==reached||steps==7) begin
                    m_candidate<=next_reached==neighbors; state<=OUTPUT;
                end
            end
            OUTPUT: if(m_ready) state<=IDLE;
            default: state<=IDLE;
        endcase
    end
endmodule
