`timescale 1ns/1ps
// DDR/BVH ray accelerator.
//
// Mesh records and BVH nodes are 48-byte signed Q16.16 records in DDR.  The
// scalar implementation deliberately favors a small, auditable control path:
// one node/triangle read at a time, a bounded traversal stack and a bounded
// crossing store.  operation_mode bit 1 selects the fixed-size complete
// crossing frame; bit 0 keeps the DDR mesh mode enabled.
module lung_ray_mesh_axi #(
parameter integer MAX_TRIANGLES = 8192,
parameter integer CORE_COUNT = 1,
parameter integer FAST_DIVIDE = 0,
parameter integer MAX_HITS = 128,
parameter integer STACK_DEPTH = 128
) (
(* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF s_axi:s_mesh:s_ray:m_axis:M_AXI, ASSOCIATED_RESET aresetn, FREQ_HZ 99999001, PHASE 0.0" *)
(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *) input wire aclk,
(* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW" *)
(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *) input wire aresetn,
input wire [11:0] s_axi_awaddr, input wire [2:0] s_axi_awprot,
input wire s_axi_awvalid, output wire s_axi_awready,
input wire [31:0] s_axi_wdata, input wire [3:0] s_axi_wstrb,
input wire s_axi_wvalid, output wire s_axi_wready,
output reg [1:0] s_axi_bresp, output reg s_axi_bvalid,
input wire s_axi_bready,
input wire [11:0] s_axi_araddr, input wire [2:0] s_axi_arprot,
input wire s_axi_arvalid, output wire s_axi_arready,
output reg [31:0] s_axi_rdata, output reg [1:0] s_axi_rresp,
output reg s_axi_rvalid, input wire s_axi_rready,
// Kept for BD migration compatibility; DDR mode does not consume S_MESH.
input wire [127:0] s_mesh_tdata, input wire [15:0] s_mesh_tkeep,
input wire s_mesh_tlast, input wire s_mesh_tvalid, output wire s_mesh_tready,
input wire [127:0] s_ray_tdata, input wire [15:0] s_ray_tkeep,
input wire s_ray_tlast, input wire s_ray_tvalid, output wire s_ray_tready,
output wire [127:0] m_axis_tdata, output wire [15:0] m_axis_tkeep,
output wire m_axis_tlast, output wire m_axis_tvalid,
input wire m_axis_tready, output wire irq,
// AXI4 read master, 128-bit data and 64-bit byte address.
// X_INTERFACE attributes let module-reference infer one AXI master in
// Vivado IP Integrator instead of exposing twenty unrelated pins.
(* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXI, DATA_WIDTH 128, PROTOCOL AXI4, ADDR_WIDTH 64, READ_WRITE_MODE READ_ONLY, FREQ_HZ 99999001, MAX_BURST_LENGTH 1, NUM_READ_OUTSTANDING 1" *)
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARADDR" *) output wire [63:0] m_axi_araddr,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLEN" *) output wire [7:0] m_axi_arlen,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARSIZE" *) output wire [2:0] m_axi_arsize,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARBURST" *) output wire [1:0] m_axi_arburst,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARPROT" *) output wire [2:0] m_axi_arprot,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARCACHE" *) output wire [3:0] m_axi_arcache,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARVALID" *) output wire m_axi_arvalid,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARREADY" *) input wire m_axi_arready,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RDATA" *) input wire [127:0] m_axi_rdata,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RRESP" *) input wire [1:0] m_axi_rresp,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RLAST" *) input wire m_axi_rlast,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RVALID" *) input wire m_axi_rvalid,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RREADY" *) output wire m_axi_rready
);
localparam [7:0] ERR_TLAST=8'h01, ERR_KEEP=8'h02, ERR_TIMEOUT=8'h04,
ERR_RRESP=8'h08, ERR_ARITH=8'h10, ERR_HIT_OVERFLOW=8'h20,
ERR_STACK_OVERFLOW=8'h40, ERR_ABORT=8'h80;
localparam [31:0] MAGIC=32'h4c524d32, ABI_VERSION=32'h00070000;
localparam [5:0] ST_IDLE=0, ST_RAY0=1, ST_RAY1=2,
ST_NODE_AR=3, ST_NODE_R=4, ST_NODE_DECIDE=5,
ST_TRI_AR=6, ST_TRI_R=7, ST_CORE=8, ST_CORE_WAIT=9,
// States 11..14 were the pre-union sort/dedup path. No reachable state
// enters them; the union core owns sorting, deduplication and boundaries.
ST_TRAV_DONE=10,
ST_OUTPUT_SUMMARY=15, ST_OUTPUT_COMPLETE=16, ST_AABB_START=17, ST_AABB_WAIT=18,
ST_VOLUME_START=19, ST_VOLUME_WAIT=20, ST_VOLUME_ACCUM=21,
ST_MEAN_START=22, ST_MEAN_WAIT=23, ST_DISTANCE_DONE=24, ST_OUTPUT_DISTANCE=25,
ST_UNION_WAIT=26, ST_UNION_COPY=27;
reg [5:0] state;
reg [31:0] cfg_triangle_count, cfg_ray_count, cfg_timeout_cycles, cfg_job_id;
reg [63:0] cfg_mesh_base_addr, cfg_bvh_base_addr;
reg [31:0] cfg_bvh_node_count, cfg_max_hits;
reg [5:0] cfg_solid_count;
reg ddr_loaded, ddr_mode, complete_mode, irq_enable, done_sticky;
reg start_run_cmd, start_load_cmd, abort_cmd, aw_pending, w_pending;
reg [11:0] aw_addr;
reg [31:0] w_data;
reg [3:0] w_strb;
reg job_done_pulse;
reg [31:0] mesh_loaded_count, ray_processed, ray_hit_count, ray_cycles, overflow_rays;
reg [7:0] error_flags, ray_errors;
reg [31:0] advisory_flags, parallel_count;
reg hit_overflow_seen;
reg [31:0] ray_id_reg, ray_ox, ray_oy, ray_oz, ray_dx, ray_dy, ray_dz;
reg [31:0] tri_index, tri_end, ray_hits, node_index;
reg [31:0] stack_mem [0:STACK_DEPTH-1];
reg [31:0] stack_top;
reg [2:0] node_beat, triangle_beat;
reg [31:0] node_words [0:11];
reg [127:0] tri_word0, tri_word1, tri_word2;
reg signed [31:0] hit_values [0:MAX_HITS-1];
reg [31:0] raw_count, unique_count;
reg [31:0] output_index;
reg inside_flag;
reg [31:0] interval_count;
reg signed [31:0] out_near, out_far;
reg cancel_pending;
reg volume_mode, distance_mode;
reg [95:0] point_min_q32, batch_min_q32;
reg [31:0] distance_valid_points;
reg point_distance_valid;
wire distance_ready, distance_done, distance_error;
wire [95:0] triangle_distance_q32;
wire point_box_ready, point_box_done;
wire [95:0] point_box_distance_q32;
reg [31:0] ray_length_q16, ray_fraction_q30, volume_valid_rays, volume_mean_q30;
reg ray_volume_valid;
reg [63:0] volume_sum_q30;
wire [31:0] volume_crossing_index, volume_fraction;
wire volume_done, volume_error, mean_done, mean_ready;
wire [63:0] mean_quotient;
wire core_s_ready, core_m_valid, core_hit;
wire signed [31:0] core_t_q16, core_u_q16, core_v_q16;
wire [7:0] core_error;
wire core_accept=(state==ST_CORE)&&(distance_mode?distance_ready:core_s_ready);
wire core_result_accept=(state==ST_CORE_WAIT)&&(distance_mode?distance_done:core_m_valid);
wire [31:0] effective_max_hits=(cfg_max_hits==0||cfg_max_hits>MAX_HITS)?MAX_HITS:cfg_max_hits;
wire union_hit_ready, union_busy, union_done, union_error, union_origin_inside;
wire [31:0] union_raw_count, union_event_count, union_boundary_count;
wire signed [31:0] union_read_t;
reg [6:0] union_copy_index;
wire union_hit_valid=core_result_accept && !distance_mode && core_hit &&
    (union_raw_count<effective_max_hits);
lung_ray_union_core #(.MAX_HITS(MAX_HITS),.MAX_SOLIDS(32)) union_core (
    .clk(aclk),.rst_n(aresetn && state!=ST_IDLE),
    .clear(state==ST_RAY1 && s_ray_tvalid && s_ray_tready),
    .hit_valid(union_hit_valid),.hit_t_q16(core_t_q16),
    .hit_solid_id(tri_word2[36:32]),.hit_ready(union_hit_ready),
    .start(state==ST_TRAV_DONE && !distance_mode),.solid_count(cfg_solid_count),
    .busy(union_busy),.done(union_done),.error(union_error),
    .raw_count(union_raw_count),.event_count(union_event_count),
    .boundary_count(union_boundary_count),.origin_inside(union_origin_inside),
    .read_index(union_copy_index),.read_t_q16(union_read_t));
lung_ray_volume_core volume_core (
.clk(aclk),.rst_n(aresetn && state!=ST_IDLE),.start(state==ST_VOLUME_START && ray_errors==0),
.length_q16(ray_length_q16),.crossing_count(unique_count),.origin_inside(inside_flag),
.crossing_index(volume_crossing_index),
.crossing_q16(hit_values[volume_crossing_index[$clog2(MAX_HITS)-1:0]]),
.done(volume_done),.error(volume_error),.fraction_q30(volume_fraction));
lung_unsigned_divider mean_divider (
.clk(aclk),.rst_n(aresetn && state!=ST_IDLE),.start(state==ST_MEAN_START && volume_valid_rays!=0),
.numerator(volume_sum_q30),.denominator(volume_valid_rays),
.ready(mean_ready),.done(mean_done),.quotient(mean_quotient));
wire signed [31:0] tri_v0_x=tri_word0[31:0], tri_v0_y=tri_word0[63:32], tri_v0_z=tri_word0[95:64];
wire signed [31:0] tri_v1_x=tri_word0[127:96], tri_v1_y=tri_word1[31:0], tri_v1_z=tri_word1[63:32];
wire signed [31:0] tri_v2_x=tri_word1[95:64], tri_v2_y=tri_word1[127:96], tri_v2_z=tri_word2[31:0];
lung_point_triangle_distance_core distance_core (
.clk(aclk),.rst_n(aresetn && state!=ST_IDLE),.start(distance_mode && state==ST_CORE),
.px(ray_ox),.py(ray_oy),.pz(ray_oz),
.ax(tri_v0_x),.ay(tri_v0_y),.az(tri_v0_z),
.bx(tri_v1_x),.by(tri_v1_y),.bz(tri_v1_z),
.cx(tri_v2_x),.cy(tri_v2_y),.cz(tri_v2_z),
.ready(distance_ready),.done(distance_done),.error(distance_error),.distance_q32(triangle_distance_q32));
lung_point_aabb_distance_core point_box (
.clk(aclk),.rst_n(aresetn && state!=ST_IDLE),.start(distance_mode && state==ST_AABB_START),
.px(ray_ox),.py(ray_oy),.pz(ray_oz),
.mnx(node_words[0]),.mny(node_words[1]),.mnz(node_words[2]),
.mxx(node_words[3]),.mxy(node_words[4]),.mxz(node_words[5]),
.ready(point_box_ready),.done(point_box_done),.distance_q32(point_box_distance_q32));
wire job_active=(state!=ST_IDLE);
wire timeout_hit=(cfg_timeout_cycles!=0)&&(ray_cycles>=cfg_timeout_cycles-1);
wire output_transfer=m_axis_tvalid&&m_axis_tready;
lung_ray_triangle_stage3_core #(.FAST_DIVIDE(FAST_DIVIDE), .SAFE_REJECT(1)) core (
.clk(aclk), .rst_n(aresetn && state!=ST_IDLE),
.s_valid(state==ST_CORE && !distance_mode), .s_ready(core_s_ready), .s_ray_id(ray_id_reg), .s_triangle_id(tri_index),
.s_origin_x(ray_ox), .s_origin_y(ray_oy), .s_origin_z(ray_oz),
.s_direction_x(ray_dx), .s_direction_y(ray_dy), .s_direction_z(ray_dz),
.s_v0_x(tri_v0_x), .s_v0_y(tri_v0_y), .s_v0_z(tri_v0_z),
.s_v1_x(tri_v1_x), .s_v1_y(tri_v1_y), .s_v1_z(tri_v1_z),
.s_v2_x(tri_v2_x), .s_v2_y(tri_v2_y), .s_v2_z(tri_v2_z),
.m_valid(core_m_valid), .m_ready(state==ST_CORE_WAIT), .m_ray_id(), .m_triangle_id(),
.m_hit(core_hit), .m_t_q16(core_t_q16), .m_u_q16(core_u_q16), .m_v_q16(core_v_q16), .m_error(core_error));
function automatic [31:0] merge_bytes(input [31:0] old_value,input [31:0] new_value,input [3:0] strobe);
    integer b;
    begin
        merge_bytes=old_value;
        for(b=0;b<4;b=b+1) if(strobe[b]) merge_bytes[b*8 +: 8]=new_value[b*8 +: 8];
    end
endfunction
wire aabb_ready, aabb_valid, node_candidate;
lung_ray_aabb_core aabb (
.clk(aclk), .rst_n(aresetn && state!=ST_IDLE),
.s_valid(state==ST_AABB_START && !distance_mode), .s_ready(aabb_ready),
.ox(ray_ox), .oy(ray_oy), .oz(ray_oz), .dx(ray_dx), .dy(ray_dy), .dz(ray_dz),
.mnx(node_words[0]), .mny(node_words[1]), .mnz(node_words[2]),
.mxx(node_words[3]), .mxy(node_words[4]), .mxz(node_words[5]),
.m_valid(aabb_valid), .m_hit(node_candidate));
wire selected_node_candidate=distance_mode?(point_box_distance_q32<point_min_q32):node_candidate;
wire node_is_leaf=(node_words[10]==1);
wire node_bad=(node_words[10]>1) || ($signed(node_words[0])>$signed(node_words[3])) ||
($signed(node_words[1])>$signed(node_words[4])) || ($signed(node_words[2])>$signed(node_words[5])) ||
((node_words[10]==1) && (node_words[8]>=cfg_triangle_count || node_words[9]==0 ||
{1'b0,node_words[8]}+{1'b0,node_words[9]}>{1'b0,cfg_triangle_count})) ||
((node_words[10]==0) && (node_words[6]<=node_index || node_words[7]<=node_index ||
node_words[6]>=cfg_bvh_node_count || node_words[7]>=cfg_bvh_node_count));
// Compact fixed frame: 4 header beats followed by MAX_HITS/4 t beats.
// MAX_HITS must be a multiple of four. TLAST marks the entire DMA batch.
reg [127:0] complete_data;
integer lane;
always @* begin
    complete_data=0;
    case(output_index)
        0:complete_data={unique_count,ray_hits,{16'd0,advisory_flags[7:0],ray_errors},ray_id_reg};
        1:complete_data={interval_count,{31'd0,inside_flag},out_far,out_near};
        2:complete_data={volume_mode?ray_length_q16:32'd0,parallel_count,32'd1,ray_fraction_q30};
        // tolerance=1 Q16 LSB
        3:complete_data={cfg_solid_count,union_boundary_count,union_event_count,{31'd0,ray_volume_valid}};
        default:for(lane=0;lane<4;lane=lane+1)
        if((output_index-4)*4+lane<unique_count)
        complete_data[lane*32+:32]=hit_values[(output_index-4)*4+lane];
    endcase
end
assign s_mesh_tready=1'b0;
assign s_ray_tready=(state==ST_RAY0)||(state==ST_RAY1);
assign m_axis_tvalid=(state==ST_OUTPUT_SUMMARY)||(state==ST_OUTPUT_COMPLETE)||(state==ST_OUTPUT_DISTANCE);
assign m_axis_tkeep=16'hffff;
assign m_axis_tlast=(ray_processed+1>=cfg_ray_count) &&
((state==ST_OUTPUT_DISTANCE && output_index==1) || (state==ST_OUTPUT_SUMMARY) || (state==ST_OUTPUT_COMPLETE && output_index==3+MAX_HITS/4));
wire [127:0] distance_data=(output_index==0)?
{point_min_q32[63:0],{24'd0,ray_errors},ray_id_reg}:
{32'd32,32'd0,{31'd0,point_distance_valid},point_min_q32[95:64]};
assign m_axis_tdata=(state==ST_OUTPUT_DISTANCE)?distance_data:
(state==ST_OUTPUT_SUMMARY)?{out_far,out_near,ray_hits,ray_id_reg}:complete_data;
assign irq=irq_enable&&done_sticky;
assign m_axi_araddr=(state==ST_NODE_AR||state==ST_NODE_R) ?
(cfg_bvh_base_addr+({32'd0,node_index}*64'd48)+{57'd0,node_beat,4'd0}) :
(cfg_mesh_base_addr+({32'd0,tri_index}*64'd48)+{57'd0,triangle_beat,4'd0});
assign m_axi_arlen=0;
assign m_axi_arsize=3'd4;
assign m_axi_arburst=2'b01;
assign m_axi_arprot=0;
assign m_axi_arcache=4'b0011;
assign m_axi_arvalid=(state==ST_NODE_AR)||(state==ST_TRI_AR);
assign m_axi_rready=(state==ST_NODE_R)||(state==ST_TRI_R);
assign s_axi_awready=!aw_pending&&!s_axi_bvalid;
assign s_axi_wready=!w_pending&&!s_axi_bvalid;
assign s_axi_arready=!s_axi_rvalid;
always @(posedge aclk) begin
    if(!aresetn) begin
        cfg_triangle_count<=0;
        cfg_ray_count<=0;
        cfg_timeout_cycles<=0;
        cfg_job_id<=0;
        cfg_mesh_base_addr<=0;
        cfg_bvh_base_addr<=0;
        cfg_bvh_node_count<=0;
        cfg_max_hits<=MAX_HITS;
        cfg_solid_count<=1;
        ddr_loaded<=0;
        ddr_mode<=1;
        complete_mode<=0;
        volume_mode<=0;
        distance_mode<=0;
        irq_enable<=0;
        done_sticky<=0;
        start_run_cmd<=0;
        start_load_cmd<=0;
        abort_cmd<=0;
        aw_pending<=0;
        w_pending<=0;
        aw_addr<=0;
        w_data<=0;
        w_strb<=0;
        s_axi_bvalid<=0;
        s_axi_bresp<=0;
        s_axi_rvalid<=0;
        s_axi_rresp<=0;
        s_axi_rdata<=0;
    end
    else begin
        start_run_cmd<=0;
        start_load_cmd<=0;
        abort_cmd<=0;
        if(job_done_pulse) done_sticky<=1;
        if(s_axi_bvalid&&s_axi_bready)s_axi_bvalid<=0;
        if(s_axi_rvalid&&s_axi_rready)s_axi_rvalid<=0;
        if(s_axi_awvalid&&s_axi_awready)begin
            aw_pending<=1;
            aw_addr<=s_axi_awaddr;
        end
        if(s_axi_wvalid&&s_axi_wready)begin
            w_pending<=1;
            w_data<=s_axi_wdata;
            w_strb<=s_axi_wstrb;
        end
        if(aw_pending&&w_pending&&!s_axi_bvalid) begin
            aw_pending<=0;
            w_pending<=0;
            s_axi_bvalid<=1;
            s_axi_bresp<=0;
            if(aw_addr[1:0]!=0)s_axi_bresp<=2'b10;
            else if(aw_addr==12'h000)begin
                if(w_strb[1])irq_enable<=w_data[8];
                if(w_strb[0]&&w_data[0])begin
                    if(job_active||cfg_ray_count==0||cfg_triangle_count==0||!ddr_loaded||!ddr_mode)s_axi_bresp<=2'b10;
                    else start_run_cmd<=1;
                    done_sticky<=0;
                end
                if(w_strb[0]&&w_data[1]&&job_active)abort_cmd<=1;
                if(w_strb[0]&&w_data[2])begin
                    if(job_active||cfg_triangle_count==0||cfg_mesh_base_addr[3:0]!=0||cfg_bvh_base_addr==0||cfg_bvh_base_addr[3:0]!=0||cfg_bvh_node_count==0)s_axi_bresp<=2'b10;
                    else begin
                        start_load_cmd<=1;
                        ddr_loaded<=1;
                        done_sticky<=0;
                    end
                end
            end
            else if(aw_addr==12'h004)begin
                if(job_active)s_axi_bresp<=2'b10;
                else begin
                    cfg_triangle_count<=merge_bytes(cfg_triangle_count,w_data,w_strb);
                    if(merge_bytes(cfg_triangle_count,w_data,w_strb)!=cfg_triangle_count)ddr_loaded<=0;
                end
            end
            else if(aw_addr==12'h008)begin
                if(job_active)s_axi_bresp<=2'b10;
                else cfg_ray_count<=merge_bytes(cfg_ray_count,w_data,w_strb);
            end
            else if(aw_addr==12'h00c)begin
                if(job_active)s_axi_bresp<=2'b10;
                else cfg_job_id<=merge_bytes(cfg_job_id,w_data,w_strb);
            end
            else if(aw_addr==12'h030)begin
                if(job_active)s_axi_bresp<=2'b10;
                else cfg_timeout_cycles<=merge_bytes(cfg_timeout_cycles,w_data,w_strb);
            end
            else if(aw_addr==12'h034)begin
                if(job_active)s_axi_bresp<=2'b10;
                else begin
                    cfg_mesh_base_addr[31:0]<=merge_bytes(cfg_mesh_base_addr[31:0],w_data,w_strb);
                    ddr_loaded<=0;
                end
            end
            else if(aw_addr==12'h038)begin
                if(job_active)s_axi_bresp<=2'b10;
                else begin
                    cfg_mesh_base_addr[63:32]<=merge_bytes(cfg_mesh_base_addr[63:32],w_data,w_strb);
                    ddr_loaded<=0;
                end
            end
            else if(aw_addr==12'h03c)begin
                if(job_active)s_axi_bresp<=2'b10;
                else if(w_strb[0]&&((w_data[2]&&!w_data[1])||(w_data[3]&&w_data[2:1]!=0)))s_axi_bresp<=2'b10;
                else if(w_strb[0])begin
                    ddr_mode<=w_data[0];
                    complete_mode<=w_data[1];
                    volume_mode<=w_data[2];
                    distance_mode<=w_data[3];
                end
            end
            else if(aw_addr==12'h040)begin
                if(job_active)s_axi_bresp<=2'b10;
                else begin
                    cfg_bvh_base_addr[31:0]<=merge_bytes(cfg_bvh_base_addr[31:0],w_data,w_strb);
                    ddr_loaded<=0;
                end
            end
            else if(aw_addr==12'h044)begin
                if(job_active)s_axi_bresp<=2'b10;
                else begin
                    cfg_bvh_base_addr[63:32]<=merge_bytes(cfg_bvh_base_addr[63:32],w_data,w_strb);
                    ddr_loaded<=0;
                end
            end
            else if(aw_addr==12'h048)begin
                if(job_active)s_axi_bresp<=2'b10;
                else begin
                    cfg_bvh_node_count<=merge_bytes(cfg_bvh_node_count,w_data,w_strb);
                    ddr_loaded<=0;
                end
            end
            else if(aw_addr==12'h058)begin
                if(job_active||w_data>MAX_HITS)s_axi_bresp<=2'b10;
                else cfg_max_hits<=merge_bytes(cfg_max_hits,w_data,w_strb);
            end
            else if(aw_addr==12'h098)begin
                if(job_active||w_data==0||w_data>32)s_axi_bresp<=2'b10;
                else cfg_solid_count<=merge_bytes({26'd0,cfg_solid_count},w_data,w_strb);
            end
            else if(aw_addr==12'h01c)begin
                if(w_strb[0]&&w_data[0])done_sticky<=0;
            end
            else s_axi_bresp<=2'b10;
        end
        if(s_axi_arvalid&&s_axi_arready)begin
            s_axi_rvalid<=1;
            s_axi_rresp<=0;
            s_axi_rdata<=0;
            if(s_axi_araddr[1:0]!=0)s_axi_rresp<=2'b10;
            else case(s_axi_araddr)
                12'h000:s_axi_rdata<={23'b0,irq_enable,2'b0,(error_flags!=0),done_sticky,job_active,1'b0};
                12'h004:s_axi_rdata<=cfg_triangle_count;
                12'h008:s_axi_rdata<=cfg_ray_count;
                12'h00c:s_axi_rdata<=cfg_job_id;
                12'h010:s_axi_rdata<=ray_processed;
                12'h014:s_axi_rdata<=ray_hit_count;
                12'h018:s_axi_rdata<={24'b0,error_flags};
                12'h01c:s_axi_rdata<={31'b0,done_sticky};
                12'h020:s_axi_rdata<=ray_cycles;
                12'h024:s_axi_rdata<=mesh_loaded_count;
                12'h028:s_axi_rdata<=MAGIC;
                12'h02c:s_axi_rdata<=ABI_VERSION;
                12'h030:s_axi_rdata<=cfg_timeout_cycles;
                12'h034:s_axi_rdata<=cfg_mesh_base_addr[31:0];
                12'h038:s_axi_rdata<=cfg_mesh_base_addr[63:32];
                12'h03c:s_axi_rdata<={19'b0,distance_mode,volume_mode,error_flags,complete_mode,ddr_loaded,ddr_mode};
                12'h040:s_axi_rdata<=cfg_bvh_base_addr[31:0];
                12'h044:s_axi_rdata<=cfg_bvh_base_addr[63:32];
                12'h048:s_axi_rdata<=cfg_bvh_node_count;
                12'h04c:s_axi_rdata<=32'd48;
                12'h050:s_axi_rdata<=32'h0000007f;
                12'h054:s_axi_rdata<=32'd1;
                12'h058:s_axi_rdata<=cfg_max_hits;
                12'h05c:s_axi_rdata<=overflow_rays;
                12'h060:s_axi_rdata<=MAX_HITS;
                12'h064:s_axi_rdata<=(4+MAX_HITS/4)*16;
                12'h068:s_axi_rdata<=STACK_DEPTH;
                12'h06c:s_axi_rdata<=volume_sum_q30[31:0];
                12'h070:s_axi_rdata<=volume_sum_q30[63:32];
                12'h074:s_axi_rdata<=volume_valid_rays;
                12'h078:s_axi_rdata<=volume_mean_q30;
                12'h07c:s_axi_rdata<=32'd30;
                12'h080:s_axi_rdata<=batch_min_q32[31:0];
                12'h084:s_axi_rdata<=batch_min_q32[63:32];
                12'h088:s_axi_rdata<=batch_min_q32[95:64];
                12'h08c:s_axi_rdata<=distance_valid_points;
                12'h090:s_axi_rdata<=32'd32;
                12'h094:s_axi_rdata<=32'd32;
                12'h098:s_axi_rdata<={26'd0,cfg_solid_count};
                12'h09c:s_axi_rdata<=union_event_count;
                12'h0a0:s_axi_rdata<=32'd32;
                12'h0a4:s_axi_rdata<=union_boundary_count;
                default:s_axi_rresp<=2'b10;
            endcase
        end
    end
end
integer k;
always @(posedge aclk) begin
    if(!aresetn)begin
        state<=ST_IDLE;
        mesh_loaded_count<=0;
        ray_processed<=0;
        ray_hit_count<=0;
        ray_cycles<=0;
        overflow_rays<=0;
        error_flags<=0;
        ray_errors<=0;
        advisory_flags<=0;
        parallel_count<=0;
        hit_overflow_seen<=0;
        interval_count<=0;
        ray_id_reg<=0;
        ray_ox<=0;
        ray_oy<=0;
        ray_oz<=0;
        ray_dx<=0;
        ray_dy<=0;
        ray_dz<=0;
        tri_index<=0;
        tri_end<=0;
        ray_hits<=0;
        node_index<=0;
        stack_top<=0;
        node_beat<=0;
        triangle_beat<=0;
        raw_count<=0;
        unique_count<=0;
        output_index<=0;
        inside_flag<=0;
        out_near<=0;
        out_far<=0;
        cancel_pending<=0;
        ray_length_q16<=0;
        point_min_q32<={96{1'b1}};
        point_distance_valid<=0;
        ray_fraction_q30<=0;
        ray_volume_valid<=0;
        volume_sum_q30<=0;
            batch_min_q32<={96{1'b1}};
            distance_valid_points<=0;
        volume_valid_rays<=0;
        volume_mean_q30<=0;
        job_done_pulse<=0;
        tri_word0<=0;
        tri_word1<=0;
        tri_word2<=0;
        union_copy_index<=0;
        for(k=0;k<12;k=k+1)node_words[k]<=0;
    end
    else begin
        job_done_pulse<=0;
        if(start_load_cmd&&state==ST_IDLE)begin
            mesh_loaded_count<=cfg_triangle_count;
            error_flags<=0;
        end
        else if(start_run_cmd&&state==ST_IDLE)begin
            state<=ST_RAY0;
            ray_processed<=0;
            ray_hit_count<=0;
            ray_cycles<=0;
            overflow_rays<=0;
            error_flags<=0;
            cancel_pending<=0;
            volume_sum_q30<=0;
            batch_min_q32<={96{1'b1}};
            distance_valid_points<=0;
            volume_valid_rays<=0;
            volume_mean_q30<=0;
        end
        else if(state!=ST_IDLE)begin
            if(ray_cycles!=32'hffffffff)ray_cycles<=ray_cycles+1;
            if((abort_cmd||timeout_hit)&&!cancel_pending)begin
                error_flags<=error_flags|(abort_cmd?ERR_ABORT:ERR_TIMEOUT);
                if(state==ST_NODE_AR||state==ST_NODE_R||state==ST_TRI_AR||state==ST_TRI_R)begin
                    cancel_pending<=1;
                    if(state==ST_NODE_AR&&m_axi_arready)state<=ST_NODE_R;
                    if(state==ST_TRI_AR&&m_axi_arready)state<=ST_TRI_R;
                    if((state==ST_NODE_R||state==ST_TRI_R)&&m_axi_rvalid)begin
                        state<=ST_IDLE;
                        job_done_pulse<=1;
                    end
                end
                else begin
                    state<=ST_IDLE;
                    job_done_pulse<=1;
                end
            end
            else case(state)
                ST_RAY0:if(s_ray_tvalid&&s_ray_tready)begin
                    ray_errors<={(s_ray_tkeep!=16'hffff)?7'd1:7'd0,s_ray_tlast};
                    error_flags<=error_flags|((s_ray_tkeep!=16'hffff)?ERR_KEEP:0)|(s_ray_tlast?ERR_TLAST:0);
                    advisory_flags<=0;
                    parallel_count<=0;
                    hit_overflow_seen<=0;
                    ray_id_reg<=s_ray_tdata[31:0];
                    ray_ox<=s_ray_tdata[63:32];
                    ray_oy<=s_ray_tdata[95:64];
                    ray_oz<=s_ray_tdata[127:96];
                    state<=ST_RAY1;
                end
                ST_RAY1:if(s_ray_tvalid&&s_ray_tready)begin
                    error_flags<=error_flags|((s_ray_tkeep!=16'hffff)?ERR_KEEP:0)|((s_ray_tlast!=(ray_processed+1==cfg_ray_count))?ERR_TLAST:0);
                    ray_errors<=ray_errors|((s_ray_tkeep!=16'hffff)?ERR_KEEP:0)|((s_ray_tlast!=(ray_processed+1==cfg_ray_count))?ERR_TLAST:0);
                    ray_dx<=s_ray_tdata[31:0];
                    ray_dy<=s_ray_tdata[63:32];
                    ray_dz<=s_ray_tdata[95:64];
                    ray_length_q16<=s_ray_tdata[127:96];
                    point_min_q32<={96{1'b1}};
                    point_distance_valid<=0;
                    ray_fraction_q30<=0;
                    ray_volume_valid<=0;
                    ray_hits<=0;
                    raw_count<=0;
                    unique_count<=0;
                    union_copy_index<=0;
                    interval_count<=0;
                    stack_top<=0;
                    node_index<=0;
                    state<=ST_NODE_AR;
                    node_beat<=0;
                end
                ST_NODE_AR:if(m_axi_arready)state<=ST_NODE_R;
                ST_NODE_R:if(m_axi_rvalid&&m_axi_rready)begin
                    if(cancel_pending)begin
                        state<=ST_IDLE;
                        job_done_pulse<=1;
                    end
                    else begin
                        if(m_axi_rresp!=0)begin
                            error_flags<=error_flags|ERR_RRESP;
                            ray_errors<=ray_errors|ERR_RRESP;
                        end
                        if(!m_axi_rlast)begin
                            error_flags<=error_flags|ERR_TLAST;
                            ray_errors<=ray_errors|ERR_TLAST;
                        end
                        node_words[node_beat*4+0]<=m_axi_rdata[31:0];
                        node_words[node_beat*4+1]<=m_axi_rdata[63:32];
                        node_words[node_beat*4+2]<=m_axi_rdata[95:64];
                        node_words[node_beat*4+3]<=m_axi_rdata[127:96];
                        if(node_beat==2)state<=ST_AABB_START;
                        else begin
                            node_beat<=node_beat+1;
                            state<=ST_NODE_AR;
                        end
                    end
                end
                ST_AABB_START:if(distance_mode?point_box_ready:aabb_ready)state<=ST_AABB_WAIT;
                ST_AABB_WAIT:if(distance_mode?point_box_done:aabb_valid)state<=ST_NODE_DECIDE;
                ST_NODE_DECIDE:begin
                    stack_top<=stack_top;
                    // explicit for readability in waveforms
                    if(node_bad)begin
                        error_flags<=error_flags|ERR_STACK_OVERFLOW;
                        ray_errors<=ray_errors|ERR_STACK_OVERFLOW;
                        stack_top<=0;
                        state<=ST_TRAV_DONE;
                    end
                    else if(!selected_node_candidate)begin
                        if(stack_top==0)state<=ST_TRAV_DONE;
                        else begin
                            node_index<=stack_mem[stack_top-1];
                            stack_top<=stack_top-1;
                            node_beat<=0;
                            state<=ST_NODE_AR;
                        end
                    end
                    else if(node_is_leaf)begin
                        tri_index<=node_words[8];
                        tri_end<=node_words[8]+node_words[9];
                        if(node_words[9]==0)begin
                            if(stack_top==0)state<=ST_TRAV_DONE;
                            else begin
                                node_index<=stack_mem[stack_top-1];
                                stack_top<=stack_top-1;
                                node_beat<=0;
                                state<=ST_NODE_AR;
                            end
                        end
                        else begin
                            triangle_beat<=0;
                            state<=ST_TRI_AR;
                        end
                    end
                    else if(stack_top>=STACK_DEPTH)begin
                        error_flags<=error_flags|ERR_STACK_OVERFLOW;
                        ray_errors<=ray_errors|ERR_STACK_OVERFLOW;
                        stack_top<=0;
                        state<=ST_TRAV_DONE;
                    end
                    else begin
                        stack_mem[stack_top[$clog2(STACK_DEPTH)-1:0]]<=node_words[7];
                        node_index<=node_words[6];
                        stack_top<=stack_top+1;
                        node_beat<=0;
                        state<=ST_NODE_AR;
                    end
                end
                ST_TRI_AR:if(m_axi_arready)state<=ST_TRI_R;
                ST_TRI_R:if(m_axi_rvalid&&m_axi_rready)begin
                    if(cancel_pending)begin
                        state<=ST_IDLE;
                        job_done_pulse<=1;
                    end
                    else begin
                        if(m_axi_rresp!=0)begin
                            error_flags<=error_flags|ERR_RRESP;
                            ray_errors<=ray_errors|ERR_RRESP;
                        end
                        if(!m_axi_rlast)begin
                            error_flags<=error_flags|ERR_TLAST;
                            ray_errors<=ray_errors|ERR_TLAST;
                        end
                        case(triangle_beat)0:tri_word0<=m_axi_rdata;
                            1:tri_word1<=m_axi_rdata;
                            2:tri_word2<=m_axi_rdata;
                        endcase
                        if(triangle_beat==2)state<=ST_CORE;
                        else begin
                            triangle_beat<=triangle_beat+1;
                            state<=ST_TRI_AR;
                        end
                    end
                end
                ST_CORE:if(core_accept)state<=ST_CORE_WAIT;
                ST_CORE_WAIT:if(core_result_accept)begin
                    if(distance_mode?distance_error:core_error[1])begin
                        error_flags<=error_flags|ERR_ARITH;
                        ray_errors<=ray_errors|ERR_ARITH;
                    end
                    if(!distance_mode && core_error[0])begin
                        advisory_flags[0]<=1;
                        parallel_count<=parallel_count+1;
                    end
                    if(distance_mode && !distance_error)begin
                        if(triangle_distance_q32<point_min_q32)point_min_q32<=triangle_distance_q32;
                    end
                    if(!distance_mode && core_hit)begin
                        ray_hits<=ray_hits+1;
                        if(union_hit_ready && union_raw_count<effective_max_hits)begin
                            raw_count<=union_raw_count+1;
                        end
                        else begin
                            error_flags<=error_flags|ERR_HIT_OVERFLOW;
                            ray_errors<=ray_errors|ERR_HIT_OVERFLOW;
                            if(!hit_overflow_seen)overflow_rays<=overflow_rays+1;
                            hit_overflow_seen<=1;
                        end
                    end
                    if(tri_index+1<tri_end)begin
                        tri_index<=tri_index+1;
                        triangle_beat<=0;
                        state<=ST_TRI_AR;
                    end
                    else begin
                        if(stack_top==0)state<=ST_TRAV_DONE;
                        else begin
                            node_index<=stack_mem[stack_top-1];
                            stack_top<=stack_top-1;
                            node_beat<=0;
                            state<=ST_NODE_AR;
                        end
                    end
                end
                ST_TRAV_DONE:begin
                    ray_hit_count<=ray_hit_count+ray_hits;
                    if(distance_mode)state<=ST_DISTANCE_DONE;
                    else state<=ST_UNION_WAIT;
                end
                ST_UNION_WAIT:if(union_done)begin
                    raw_count<=union_raw_count;
                    unique_count<=union_boundary_count;
                    union_copy_index<=0;
                    if(union_error || ray_errors!=0)begin
                        ray_errors<=ray_errors|ERR_ARITH;
                        error_flags<=error_flags|ERR_ARITH;
                    end
                    if(union_boundary_count==0)begin
                        inside_flag<=union_origin_inside;
                        interval_count<=0;
                        out_near<=32'sh7fffffff;
                        out_far<=0;
                        output_index<=0;
                        state<=volume_mode?ST_VOLUME_START:(complete_mode?ST_OUTPUT_COMPLETE:ST_OUTPUT_SUMMARY);
                    end else state<=ST_UNION_COPY;
                end
                ST_UNION_COPY:begin
                    hit_values[union_copy_index]<=union_read_t;
                    if(union_copy_index+1>=union_boundary_count)begin
                        inside_flag<=union_origin_inside;
                        interval_count<=(union_boundary_count+union_origin_inside)>>1;
                        out_near<=union_origin_inside?0:
                                  ((union_copy_index==0)?union_read_t:hit_values[0]);
                        out_far<=union_read_t;
                        output_index<=0;
                        state<=volume_mode?ST_VOLUME_START:(complete_mode?ST_OUTPUT_COMPLETE:ST_OUTPUT_SUMMARY);
                    end else union_copy_index<=union_copy_index+1;
                end
                ST_VOLUME_START:begin
                    if(ray_errors!=0)state<=ST_VOLUME_ACCUM;
                    else state<=ST_VOLUME_WAIT;
                end
                ST_VOLUME_WAIT:if(volume_done)begin
                    if(volume_error)begin
                        ray_errors<=ray_errors|ERR_ARITH;
                        error_flags<=error_flags|ERR_ARITH;
                    end else begin
                        ray_fraction_q30<=volume_fraction;
                        ray_volume_valid<=1;
                    end
                    state<=ST_VOLUME_ACCUM;
                end
                ST_VOLUME_ACCUM:begin
                    if(ray_volume_valid)begin
                        volume_sum_q30<=volume_sum_q30+{32'd0,ray_fraction_q30};
                        volume_valid_rays<=volume_valid_rays+1;
                    end
                    if(ray_processed+1>=cfg_ray_count)state<=ST_MEAN_START;
                    else state<=ST_OUTPUT_COMPLETE;
                end
                ST_MEAN_START:begin
                    if(volume_valid_rays==0)begin volume_mean_q30<=0;state<=ST_OUTPUT_COMPLETE;end
                    else if(mean_ready)state<=ST_MEAN_WAIT;
                end
                ST_MEAN_WAIT:if(mean_done)begin volume_mean_q30<=mean_quotient[31:0];state<=ST_OUTPUT_COMPLETE;end
                ST_DISTANCE_DONE:begin
                    point_distance_valid<=(ray_errors==0 && point_min_q32!={96{1'b1}});
                    if(ray_errors==0 && point_min_q32!={96{1'b1}})begin
                        distance_valid_points<=distance_valid_points+1;
                        if(point_min_q32<batch_min_q32)batch_min_q32<=point_min_q32;
                    end
                    output_index<=0;state<=ST_OUTPUT_DISTANCE;
                end
                ST_OUTPUT_DISTANCE:if(output_transfer)begin
                    if(output_index==1)begin
                        ray_processed<=ray_processed+1;
                        if(ray_processed+1>=cfg_ray_count)begin state<=ST_IDLE;job_done_pulse<=1;end
                        else state<=ST_RAY0;
                    end else output_index<=output_index+1;
                end
                ST_OUTPUT_SUMMARY:if(output_transfer)begin
                    ray_processed<=ray_processed+1;
                    if(ray_processed+1>=cfg_ray_count)begin
                        state<=ST_IDLE;
                        job_done_pulse<=1;
                    end
                    else begin
                        state<=ST_RAY0;
                    end
                end
                ST_OUTPUT_COMPLETE:if(output_transfer)begin
                    if(output_index>=3+MAX_HITS/4)begin
                        ray_processed<=ray_processed+1;
                        if(ray_processed+1>=cfg_ray_count)begin
                            state<=ST_IDLE;
                            job_done_pulse<=1;
                        end
                        else begin
                            state<=ST_RAY0;
                        end
                    end
                    else output_index<=output_index+1;
                end
                default:state<=ST_IDLE;
            endcase
        end
    end
end
endmodule
