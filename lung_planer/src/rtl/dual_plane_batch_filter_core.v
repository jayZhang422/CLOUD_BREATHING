`timescale 1ns/1ps
// Batched Q16.16 half-space filter. The input stream contains the shared
// point cloud followed by two 128-bit plane records per candidate.
module dual_plane_batch_filter_core #(
    parameter integer MAX_POINTS = 4096
) (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire abort_job,
    input wire [31:0] cfg_point_count,
    input wire [31:0] cfg_candidate_count,
    input wire cfg_reuse_points,
    input wire signed [31:0] cfg_margin,
    input wire [31:0] cfg_timeout_cycles,
    input wire [31:0] cfg_job_id,
    input wire [127:0] s_data,
    input wire [15:0] s_keep,
    input wire s_last,
    input wire s_valid,
    output wire s_ready,
    output reg [127:0] m_data,
    output reg [15:0] m_keep,
    output reg m_last,
    output reg m_valid,
    input wire m_ready,
    output wire busy,
    output reg done_pulse,
    output reg [31:0] processed_count,
    output reg [31:0] accepted_count,
    output reg signed [31:0] min_margin_q16,
    output reg [7:0] error_flags,
    output reg [31:0] cycle_count,
    output reg result_valid
);
    localparam [3:0] IDLE=0, LOAD_POINTS=1, DESC0=2, DESC1=3,
                     READ_POINT=4, MULTIPLY=5, SUM_PRODUCTS=6,
                     CLASSIFY=7, PROCESS=8, FINALIZE=9, EMIT=10;
    localparam [7:0] ERR_KEEP=8'h04, ERR_FLAGS=8'h08,
                     ERR_TIMEOUT=8'h10, ERR_ABORT=8'h20,
                     ERR_COUNT=8'h40;
    reg [3:0] state;
    reg [95:0] points [0:MAX_POINTS-1];
    reg [95:0] point_reg;
    reg signed [31:0] plane [0:7];
    reg signed [63:0] p0x_reg, p0y_reg, p0z_reg;
    reg signed [63:0] p1x_reg, p1y_reg, p1z_reg;
    reg signed [65:0] d0_reg, d1_reg;
    reg signed [31:0] point_min_q16_reg;
    reg point_accepted_reg;
    reg [31:0] target_points, target_candidates, candidate_index;
    reg [31:0] point_index, input_points, timeout_limit, idle_count;
    reg signed [31:0] margin;
    reg signed [31:0] min_seen;
    reg [31:0] candidate_accepted;
    reg [31:0] job_id;
    reg points_loaded;
    wire input_state = state == LOAD_POINTS || state == DESC0 || state == DESC1;
    wire transfer = s_valid && s_ready;
    wire timed_out = timeout_limit != 0 && idle_count >= timeout_limit-1;
    assign busy = state != IDLE || m_valid || result_valid;
    assign s_ready = input_state && !abort_job && !timed_out;

    wire signed [31:0] px = point_reg[31:0];
    wire signed [31:0] py = point_reg[63:32];
    wire signed [31:0] pz = point_reg[95:64];
    wire signed [63:0] p0x = px * plane[0];
    wire signed [63:0] p0y = py * plane[1];
    wire signed [63:0] p0z = pz * plane[2];
    wire signed [63:0] p1x = px * plane[4];
    wire signed [63:0] p1y = py * plane[5];
    wire signed [63:0] p1z = pz * plane[6];
    wire signed [65:0] d0_calc = {{2{p0x_reg[63]}},p0x_reg}+{{2{p0y_reg[63]}},p0y_reg}+
        {{2{p0z_reg[63]}},p0z_reg}+({{34{plane[3][31]}},plane[3]} <<< 16);
    wire signed [65:0] d1_calc = {{2{p1x_reg[63]}},p1x_reg}+{{2{p1y_reg[63]}},p1y_reg}+
        {{2{p1z_reg[63]}},p1z_reg}+({{34{plane[7][31]}},plane[7]} <<< 16);
    wire signed [65:0] point_min = d0_reg < d1_reg ? d0_reg : d1_reg;
    wire signed [65:0] margin_ext = {{34{margin[31]}},margin} <<< 16;
    wire signed [65:0] point_q16_wide = point_min >>> 16;
    wire signed [31:0] point_min_q16_calc = point_q16_wide > 66'sd2147483647 ? 32'sh7fffffff :
        point_q16_wide < -66'sd2147483648 ? 32'sh80000000 : point_q16_wide[31:0];
    wire signed [31:0] min_next = $signed(point_min_q16_reg) < $signed(min_seen) ?
        point_min_q16_reg : min_seen;
    wire [31:0] accepted_next = candidate_accepted + point_accepted_reg;

    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            state<=IDLE; target_points<=0; target_candidates<=0; candidate_index<=0;
            point_index<=0; input_points<=0; timeout_limit<=0; idle_count<=0;
            margin<=0; min_seen<=32'sh7fffffff; candidate_accepted<=0; job_id<=0;
            processed_count<=0; accepted_count<=0; min_margin_q16<=0;
            error_flags<=0; cycle_count<=0; m_data<=0; m_keep<=0;
            m_last<=0; m_valid<=0; done_pulse<=0; result_valid<=0;
            point_reg<=0; points_loaded<=0;
            p0x_reg<=0; p0y_reg<=0; p0z_reg<=0;
            p1x_reg<=0; p1y_reg<=0; p1z_reg<=0;
            d0_reg<=0; d1_reg<=0; point_min_q16_reg<=0;
            point_accepted_reg<=0;
            for (i=0;i<8;i=i+1) plane[i]<=0;
        end else begin
            done_pulse<=0; result_valid<=0;
            if (state != IDLE) cycle_count<=cycle_count+1;
            if (abort_job && state!=IDLE) begin
                error_flags<=error_flags|ERR_ABORT; state<=IDLE;
                m_valid<=0; done_pulse<=1; result_valid<=1;
            end else if (start && state==IDLE) begin
                target_points<=cfg_point_count;
                target_candidates<=cfg_candidate_count;
                timeout_limit<=cfg_timeout_cycles; margin<=cfg_margin;
                job_id<=cfg_job_id; candidate_index<=0; point_index<=0;
                input_points<=0; idle_count<=0; candidate_accepted<=0;
                min_seen<=32'sh7fffffff; processed_count<=0; accepted_count<=0;
                min_margin_q16<=0; cycle_count<=0; error_flags<=0;
                if (cfg_point_count==0 || cfg_point_count>MAX_POINTS ||
                    cfg_candidate_count==0 || cfg_candidate_count>4096 || cfg_margin<0) begin
                    error_flags<=ERR_COUNT; state<=IDLE; done_pulse<=1; result_valid<=1;
                end else if (cfg_reuse_points && points_loaded) begin
                    input_points<=cfg_point_count; state<=DESC0;
                end else begin
                    points_loaded<=0; state<=LOAD_POINTS;
                end
            end else if (input_state) begin
                if (transfer) begin
                    idle_count<=0;
                    if (s_keep!=16'hffff) error_flags<=error_flags|ERR_KEEP;
                    if (state==LOAD_POINTS) begin
                        if (s_data[127:96]!=0) error_flags<=error_flags|ERR_FLAGS;
                        points[input_points]<={s_data[95:64],s_data[63:32],s_data[31:0]};
                        input_points<=input_points+1;
                        if (input_points+1==target_points) begin
                            points_loaded<=1; state<=DESC0;
                        end
                    end else if (state==DESC0) begin
                        for (i=0;i<4;i=i+1) plane[i]<=s_data[i*32 +: 32];
                        state<=DESC1;
                    end else begin
                        for (i=0;i<4;i=i+1) plane[i+4]<=s_data[i*32 +: 32];
                        point_index<=0; candidate_accepted<=0; min_seen<=32'sh7fffffff;
                        state<=READ_POINT;
                    end
                end else begin
                    idle_count<=idle_count+1;
                    if (timed_out) begin error_flags<=error_flags|ERR_TIMEOUT; state<=IDLE; done_pulse<=1; result_valid<=1; end
                end
                if (abort_job) begin error_flags<=error_flags|ERR_ABORT; state<=IDLE; done_pulse<=1; result_valid<=1; end
            end else if (state==READ_POINT) begin
                point_reg<=points[point_index];
                state<=MULTIPLY;
            end else if (state==MULTIPLY) begin
                p0x_reg<=p0x; p0y_reg<=p0y; p0z_reg<=p0z;
                p1x_reg<=p1x; p1y_reg<=p1y; p1z_reg<=p1z;
                state<=SUM_PRODUCTS;
            end else if (state==SUM_PRODUCTS) begin
                d0_reg<=d0_calc; d1_reg<=d1_calc;
                state<=CLASSIFY;
            end else if (state==CLASSIFY) begin
                point_min_q16_reg<=point_min_q16_calc;
                point_accepted_reg<=(d0_reg>=margin_ext && d1_reg>=margin_ext);
                state<=PROCESS;
            end else if (state==PROCESS) begin
                candidate_accepted<=accepted_next;
                min_seen<=min_next;
                point_index<=point_index+1;
                if (point_index+1==target_points) begin
                    processed_count<=processed_count+target_points;
                    accepted_count<=accepted_count+accepted_next;
                    state<=FINALIZE;
                end else begin
                    state<=READ_POINT;
                end
            end else if (state==FINALIZE) begin
                if (candidate_index==0 || $signed(min_seen)<$signed(min_margin_q16))
                    min_margin_q16<=min_seen;
                m_data<={candidate_accepted,target_points,min_seen,{24'd0,error_flags}};
                m_keep<=16'hffff; m_last<=(candidate_index+1==target_candidates);
                m_valid<=1; state<=EMIT;
            end else if (state==EMIT && m_valid && m_ready) begin
                m_valid<=0;
                if (candidate_index+1==target_candidates) begin
                    state<=IDLE; done_pulse<=1; result_valid<=1;
                end else begin
                    candidate_index<=candidate_index+1; state<=DESC0;
                end
            end
        end
    end
endmodule
