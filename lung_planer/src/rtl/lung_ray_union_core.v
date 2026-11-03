`timescale 1ns/1ps
module lung_ray_union_core #(
    parameter integer MAX_HITS = 128,
    parameter integer MAX_SOLIDS = 32
) (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire hit_valid,
    input wire signed [31:0] hit_t_q16,
    input wire [4:0] hit_solid_id,
    output wire hit_ready,
    input wire start,
    input wire [5:0] solid_count,
    output reg busy,
    output reg done,
    output reg error,
    output reg [31:0] raw_count,
    output reg [31:0] event_count,
    output reg [31:0] boundary_count,
    output reg origin_inside,
    input wire [6:0] read_index,
    output reg signed [31:0] read_t_q16
);

// Two ping-pong true-dual-port BRAM stores replace the multi-write register
// arrays. Stable bottom-up merge sorting takes O(N log N) record transfers.
// The second pass sorts only t, retaining the per-solid order for equal t.
localparam integer AW = (MAX_HITS<2) ? 1 : $clog2(MAX_HITS);
localparam [3:0] COLLECT=0, SORT_SETUP=1, RUN_SETUP=2, MERGE_READ=3,
    MERGE_EMIT=4, SORT_FINISH=5, DEDUP_READ=6, DEDUP_EMIT=7,
    GROUP_READ=8, GROUP_EMIT=9, GROUP_APPLY=10, FINISH=11;
reg [3:0] state;
(* ram_style="block" *) reg [36:0] store_a[0:MAX_HITS-1];
(* ram_style="block" *) reg [36:0] store_b[0:MAX_HITS-1];
reg [36:0] a_q0,a_q1,b_q0,b_q1;
reg source_b, sort_by_t;
reg [7:0] count, width, base, left_i, right_i, left_end, right_end, dest_i;
reg [7:0] scan_i, compact_count;
reg [36:0] previous;
reg [MAX_SOLIDS-1:0] parity, inside_solid, group_toggle;
reg signed [31:0] group_t;
reg group_valid;
(* ram_style="distributed" *) reg signed [31:0] boundary_t[0:MAX_HITS-1];
wire [36:0] q0=source_b?b_q0:a_q0;
wire [36:0] q1=source_b?b_q1:a_q1;
wire left_first = (right_i>=right_end) || ((left_i<left_end) &&
    ((!sort_by_t && q0[36:32]<q1[36:32]) ||
     ((sort_by_t || q0[36:32]==q1[36:32]) && $signed(q0[31:0])<=$signed(q1[31:0]))));
wire [36:0] selected=left_first?q0:q1;
wire keep_event=(scan_i==0 || q0[36:32]!=previous[36:32] ||
    ($signed(q0[31:0])-$signed(previous[31:0])>1));
wire accept_hit=state==COLLECT && hit_valid && raw_count<MAX_HITS &&
    hit_solid_id<solid_count && solid_count!=0;
wire merge_write=state==MERGE_EMIT;
wire dedup_write=state==DEDUP_EMIT && keep_event;
wire work_write=merge_write || dedup_write;
wire [AW-1:0] read0=(state==MERGE_READ || state==MERGE_EMIT)?left_i[AW-1:0]:scan_i[AW-1:0];
wire [AW-1:0] read1=right_i[AW-1:0];
wire [AW-1:0] write_addr=merge_write?dest_i[AW-1:0]:compact_count[AW-1:0];
wire [36:0] write_data=merge_write?selected:q0;
wire a_write=(!source_b && accept_hit) || (source_b && work_write);
wire b_write=source_b && accept_hit || (!source_b && work_write);
wire [AW-1:0] a_addr0=a_write?(accept_hit?raw_count[AW-1:0]:write_addr):read0;
wire [AW-1:0] b_addr0=b_write?(accept_hit?raw_count[AW-1:0]:write_addr):read0;
wire [36:0] port_data=accept_hit?{hit_solid_id,hit_t_q16}:write_data;
// Each memory has one read/write port and one independent read port.
// No reset on RAM contents or output registers, allowing native RAM inference.
always @(posedge clk) begin
    if(a_write && rst_n && !clear) store_a[a_addr0]<=port_data;
    a_q0<=store_a[a_addr0];
end
always @(posedge clk) a_q1<=store_a[read1];
always @(posedge clk) begin
    if(b_write && rst_n && !clear) store_b[b_addr0]<=port_data;
    b_q0<=store_b[b_addr0];
end
always @(posedge clk) b_q1<=store_b[read1];
assign hit_ready=(state==COLLECT);
always @* read_t_q16=(read_index<boundary_count)?boundary_t[read_index]:0;
wire [MAX_SOLIDS-1:0] next_inside=inside_solid^group_toggle;
wire [8:0] run_middle={1'b0,base}+{1'b0,width};
wire [8:0] run_end={1'b0,base}+({1'b0,width}<<1);
always @(posedge clk) begin
    if(!rst_n || clear) begin
        state<=COLLECT; busy<=0; done<=0; error<=0;
        raw_count<=0; event_count<=0; boundary_count<=0; origin_inside<=0;
        source_b<=0; sort_by_t<=0; count<=0; width<=1; base<=0;
        left_i<=0; right_i<=0; left_end<=0; right_end<=0; dest_i<=0;
        scan_i<=0; compact_count<=0; previous<=0;
        parity<=0; inside_solid<=0; group_toggle<=0; group_t<=0; group_valid<=0;
    end else begin
        done<=0;
        case(state)
            COLLECT: begin
                if(hit_valid) begin
                    if(!accept_hit) error<=1;
                    else raw_count<=raw_count+1'b1;
                end
                if(start) begin
                    if(solid_count==0 || solid_count>MAX_SOLIDS) error<=1;
                    busy<=1; count<=raw_count[7:0]; sort_by_t<=0;
                    state<=SORT_SETUP;
                end
            end
            SORT_SETUP: begin
                width<=1; base<=0;
                if(count<2) state<=SORT_FINISH;
                else state<=RUN_SETUP;
            end
            RUN_SETUP: begin
                if(base>=count) begin
                    source_b<=~source_b;
                    base<=0;
                    if(({1'b0,width}<<1)>=count) state<=SORT_FINISH;
                    else width<=width<<1;
                end else begin
                    left_i<=base; dest_i<=base;
                    right_i<=(run_middle>=count)?count:run_middle[7:0];
                    left_end<=(run_middle>=count)?count:run_middle[7:0];
                    right_end<=(run_end>=count)?count:run_end[7:0];
                    state<=MERGE_READ;
                end
            end
            MERGE_READ: state<=MERGE_EMIT;
            MERGE_EMIT: begin
                if(left_first) left_i<=left_i+1'b1;
                else right_i<=right_i+1'b1;
                dest_i<=dest_i+1'b1;
                if(dest_i+1'b1>=right_end) begin base<=right_end;state<=RUN_SETUP;end
                else state<=MERGE_READ;
            end
            SORT_FINISH: begin
                scan_i<=0;
                if(!sort_by_t) begin compact_count<=0;parity<=0;state<=DEDUP_READ;end
                else begin group_valid<=0;group_toggle<=0;boundary_count<=0;state<=GROUP_READ;end
            end
            DEDUP_READ: begin
                if(scan_i>=count) begin
                    event_count<=compact_count;
                    inside_solid<=parity; origin_inside<=(parity!=0);
                    count<=compact_count;source_b<=~source_b;sort_by_t<=1;
                    state<=SORT_SETUP;
                end else state<=DEDUP_EMIT;
            end
            DEDUP_EMIT: begin
                previous<=q0; scan_i<=scan_i+1'b1;
                if(keep_event) begin
                    compact_count<=compact_count+1'b1;
                    parity[q0[36:32]]<=~parity[q0[36:32]];
                end
                state<=DEDUP_READ;
            end
            GROUP_READ: begin
                if(scan_i>=count) begin
                    if(group_valid) state<=GROUP_APPLY;
                    else state<=FINISH;
                end else state<=GROUP_EMIT;
            end
            GROUP_EMIT: begin
                if(!group_valid) begin
                    group_t<=q0[31:0]; group_toggle<=({{(MAX_SOLIDS-1){1'b0}},1'b1}<<q0[36:32]);
                    group_valid<=1;scan_i<=scan_i+1'b1;state<=GROUP_READ;
                end else if($signed(q0[31:0])-$signed(group_t)<=1) begin
                    group_toggle[q0[36:32]]<=~group_toggle[q0[36:32]];
                    scan_i<=scan_i+1'b1;state<=GROUP_READ;
                end else state<=GROUP_APPLY;
            end
            GROUP_APPLY: begin
                inside_solid<=next_inside;
                if((inside_solid==0)!=(next_inside==0)) begin
                    if(boundary_count>=MAX_HITS) error<=1;
                    else begin boundary_t[boundary_count[AW-1:0]]<=group_t;boundary_count<=boundary_count+1'b1;end
                end
                group_valid<=0;group_toggle<=0;state<=GROUP_READ;
            end
            FINISH: begin busy<=0;done<=1;state<=COLLECT;end
            default: begin error<=1;busy<=0;state<=COLLECT;end
        endcase
    end
end
endmodule
