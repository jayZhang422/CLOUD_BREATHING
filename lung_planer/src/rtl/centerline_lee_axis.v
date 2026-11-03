`timescale 1ns/1ps
// Four independent classifications per 128-bit DMA beat. Candidate collection
// barriers and ordered deletion/rechecks remain in the exact PS coordinator.
module centerline_lee_axis (
    input wire clk, rst_n, start, abort_job,
    input wire [31:0] query_count, timeout_cycles,
    input wire [127:0] s_data,
    input wire [15:0] s_keep,
    input wire s_last, s_valid,
    output wire s_ready,
    output wire [127:0] m_data,
    output wire [15:0] m_keep,
    output wire m_last, m_valid,
    input wire m_ready,
    output reg busy, done,
    output reg [31:0] errors, processed, cycles, input_beats, output_beats, accepted
);
    localparam IDLE=0, INPUT=1, DISPATCH=2, COLLECT=3, EMIT=4;
    reg [2:0] state;
    reg [127:0] words;
    reg [3:0] seen, flags;
    reg [2:0] valid_words;
    wire [3:0] lane_ready, lane_valid, lane_result;
    wire timed_out = busy && cycles >= timeout_cycles;
    wire lane_reset_n = rst_n && !start && !abort_job && !timed_out;
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1) begin: classifiers
        centerline_lee_candidate candidate (
            .clk(clk), .rst_n(lane_reset_n),
            .s_neighborhood(words[lane*32+:27]),
            .s_valid(state==DISPATCH && (&lane_ready)), .s_ready(lane_ready[lane]),
            .m_candidate(lane_result[lane]), .m_valid(lane_valid[lane]),
            .m_ready(state==COLLECT && !seen[lane])
        );
    end endgenerate
    assign s_ready=state==INPUT && busy;
    assign m_valid=state==EMIT && busy;
    assign m_keep=16'hffff;
    assign m_last=processed+valid_words==query_count;
    assign m_data={31'd0,flags[3],31'd0,flags[2],31'd0,flags[1],31'd0,flags[0]};
    integer i,j;
    reg bad_high_bits;
    always @* begin
        bad_high_bits=0;
        for(j=0;j<4;j=j+1)
            if(processed+j<query_count && |s_data[j*32+27+:5]) bad_high_bits=1;
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=IDLE;words<=0;seen<=0;flags<=0;valid_words<=0;
            busy<=0;done<=0;errors<=0;processed<=0;cycles<=0;
            input_beats<=0;output_beats<=0;accepted<=0;
        end else begin
            done<=0;
            if(busy) cycles<=cycles+1;
            if(start && !busy) begin
                errors<=0;processed<=0;cycles<=0;input_beats<=0;output_beats<=0;accepted<=0;
                seen<=0;flags<=0;
                if(query_count==0 || query_count>1048576 || timeout_cycles==0) begin
                    errors<=1;busy<=0;done<=1;state<=IDLE;
                end else begin busy<=1;state<=INPUT;end
            end else if(busy && (abort_job || timed_out)) begin
                errors<=abort_job?32'd16:32'd32;busy<=0;done<=1;state<=IDLE;
            end else case(state)
                INPUT: if(s_valid && s_ready) begin
                    input_beats<=input_beats+1;
                    if(s_keep!=16'hffff || s_last!=(processed+4>=query_count) || bad_high_bits) begin
                        errors<=(s_keep!=16'hffff)?32'd2:((s_last!=(processed+4>=query_count))?32'd4:32'd8);
                        busy<=0;done<=1;state<=IDLE;
                    end else begin
                        words<=s_data;seen<=0;flags<=0;
                        valid_words<=(query_count-processed>=4)?3'd4:query_count-processed;
                        state<=DISPATCH;
                    end
                end
                DISPATCH: if(&lane_ready) state<=COLLECT;
                COLLECT: begin
                    for(i=0;i<4;i=i+1) if(lane_valid[i] && !seen[i]) begin
                        seen[i]<=1;flags[i]<=(i<valid_words) && lane_result[i];
                    end
                    if(&(seen|lane_valid)) state<=EMIT;
                end
                EMIT: if(m_ready) begin
                    processed<=processed+valid_words;output_beats<=output_beats+1;
                    accepted<=accepted+{31'd0,flags[0]}+{31'd0,flags[1]}+{31'd0,flags[2]}+{31'd0,flags[3]};
                    if(processed+valid_words==query_count) begin busy<=0;done<=1;state<=IDLE;end
                    else state<=INPUT;
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
