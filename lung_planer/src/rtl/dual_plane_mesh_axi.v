`timescale 1ns/1ps
`include "dual_plane_mesh_abi.vh"

// Pure RTL DDR-resident dual-plane mesh engine.
//
// ABI 0x00050000: stackless BVH traversal, FP64 source-face clipping and
// ridge-origin volume/cap-area integrals. Results carry job/candidate/ABI
// identity. PS admission still requires an independently verified parity gate.
module dual_plane_mesh_axi #(
    parameter integer MAX_TRIANGLES = 1048576,
    parameter integer MAX_CANDIDATES = 1024,
    // DDR/MMIO is the production completion protocol. Legacy stream output
    // is optional and must never stall a system without an AXIS consumer.
    parameter integer ENABLE_STATUS_STREAM = 0
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK",
       X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axi:m_axi:M_AXIS, ASSOCIATED_RESET aresetn, FREQ_HZ 99999001" *) input wire aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *) input wire aresetn,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME s_axi, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 12" *) input wire [11:0] s_axi_awaddr,
    input wire [2:0] s_axi_awprot, input wire s_axi_awvalid, output wire s_axi_awready,
    input wire [31:0] s_axi_wdata, input wire [3:0] s_axi_wstrb, input wire s_axi_wvalid,
    output wire s_axi_wready, output reg [1:0] s_axi_bresp, output reg s_axi_bvalid,
    input wire s_axi_bready, input wire [11:0] s_axi_araddr, input wire [2:0] s_axi_arprot,
    input wire s_axi_arvalid, output wire s_axi_arready, output reg [31:0] s_axi_rdata,
    output reg [1:0] s_axi_rresp, output reg s_axi_rvalid, input wire s_axi_rready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *) output wire [127:0] m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TKEEP" *) output wire [15:0] m_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *) output wire m_axis_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *) output wire m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *) input wire m_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq INTERRUPT",
       X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *) output wire irq,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME m_axi, DATA_WIDTH 128, PROTOCOL AXI4, ADDR_WIDTH 64, READ_WRITE_MODE READ_WRITE, FREQ_HZ 99999001, MAX_BURST_LENGTH 4, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1" *)
    output wire [63:0] m_axi_araddr, output wire [7:0] m_axi_arlen, output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst, output wire [2:0] m_axi_arprot, output wire [3:0] m_axi_arcache,
    output wire m_axi_arvalid, input wire m_axi_arready, input wire [127:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp, input wire m_axi_rlast, input wire m_axi_rvalid, output wire m_axi_rready,
    output wire [63:0] m_axi_awaddr, output wire [7:0] m_axi_awlen, output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst, output wire [2:0] m_axi_awprot, output wire [3:0] m_axi_awcache,
    output wire m_axi_awvalid, input wire m_axi_awready, output wire [127:0] m_axi_wdata,
    output wire [15:0] m_axi_wstrb, output wire m_axi_wlast, output wire m_axi_wvalid,
    input wire m_axi_wready, input wire [1:0] m_axi_bresp, input wire m_axi_bvalid, output wire m_axi_bready
);
    localparam [4:0] ST_IDLE=0, ST_READ_CAND_AR=1, ST_READ_CAND=2,
                     ST_READ_MESH_AR=3, ST_READ_MESH=4, ST_GEOM_START=5,
                     ST_GEOM_WAIT=6, ST_ACCUM_START=7, ST_ACCUM_WAIT=8,
                     ST_WRITE_AW=9, ST_WRITE_W=10, ST_WRITE_B=11, ST_OUTPUT=12, ST_DONE=13,
                     ST_SEG_AW=14, ST_SEG_W=15, ST_SEG_B=16, ST_SEG_ACK=17,
                     ST_SEG_AREA_START=18, ST_SEG_AREA_WAIT=19,
                     ST_SEG_ACCUM_START=20, ST_SEG_ACCUM_WAIT=21,
                     ST_CUT_FINAL_START=22, ST_CUT_FINAL_WAIT=23,
                     ST_BVH_AR=24, ST_BVH_READ=25, ST_BVH_START=26,
                     ST_BVH_WAIT=27, ST_BVH_NEXT=28;
    localparam [31:0] ABI = `DPM_ABI_VERSION;
    localparam [31:0] ERR_OPEN = `DPM_ERR_OPEN_LOOP;
    reg [4:0] state;
    reg [31:0] tri_count, cand_count, seg_capacity, result_count, job_id;
    reg [63:0] mesh_base, cand_base, seg_base, result_base;
    reg [31:0] cand_index, tri_index, cycle_count;
    reg [31:0] prof_cycles [0:6];
    reg [31:0] prof_ar_count, prof_ar_latency;
    reg prof_ar_outstanding, prof_busy_q;
    reg [2:0] prof_class;
    integer prof_i;
    reg [7:0] errors;
    reg done_sticky, irq_enable;
    reg stop_requested;
    reg [31:0] timeout_cycles;
    reg aw_pending, w_pending;
    reg [11:0] aw_addr; reg [31:0] w_data; reg [3:0] w_strb;
    reg [63:0] read_addr, write_addr;
    reg [127:0] cand_words [0:9];
    reg [127:0] mesh_words [0:4];
    reg [3:0] cand_beat;
    reg [3:0] mesh_beat;
    reg mesh_burst;
    reg [3:0] mesh_offset;
    reg [63:0] plane_nx [0:3], plane_ny [0:3], plane_nz [0:3], plane_off [0:3];
    reg [63:0] origin_x,origin_y,origin_z;
    reg [63:0] bvh_base,center_x,center_y,center_z;
    reg [31:0] bvh_count,node_index,leaf_end;
    reg [2:0] node_beat;
    reg [127:0] node_words[0:7];
    reg aggregate_node;
    wire [31:0] node_escape=node_words[3][31:0];
    wire [31:0] node_first=node_words[3][63:32];
    wire [31:0] node_triangles=node_words[3][95:64];
    wire node_leaf=node_words[3][96];
    wire node_done,node_inside,node_outside,node_binding,node_numeric;
    wire [63:0] node_volume;
    wire [1023:0] all_planes={plane_off[3],plane_nz[3],plane_ny[3],plane_nx[3],
        plane_off[2],plane_nz[2],plane_ny[2],plane_nx[2],
        plane_off[1],plane_nz[1],plane_ny[1],plane_nx[1],
        plane_off[0],plane_nz[0],plane_ny[0],plane_nx[0]};
    // BVH classification and triangle geometry are mutually exclusive at
    // this scheduler. Each owner drains its FP64 epoch before reporting done.
    wire bvh_req,geom_req,segment_req,accum_req,cut_accum_req;
    wire shared_ready,shared_done;
    wire [1:0] bvh_op,geom_op,segment_op,accum_op,cut_accum_op;
    wire [63:0] bvh_a,bvh_b,geom_a,geom_b,segment_a,segment_b;
    wire [63:0] accum_a,accum_b,cut_accum_a,cut_accum_b,shared_result;
    wire [63:0] cut_area_one,cut_area_two;
    reg cut_add_start;
    reg serial_alu_busy;
    reg [2:0] serial_alu_owner;
    wire serial_alu_ready=shared_ready&&!serial_alu_busy;
    wire serial_segment_done=shared_done&&serial_alu_busy&&(serial_alu_owner==3'd1);
    wire serial_accum_done=shared_done&&serial_alu_busy&&(serial_alu_owner==3'd2);
    wire serial_cut_accum_done=shared_done&&serial_alu_busy&&(serial_alu_owner==3'd3);
    wire serial_cut_add_done=shared_done&&serial_alu_busy&&(serial_alu_owner==3'd4);
    wire select_bvh=state==ST_BVH_START || state==ST_BVH_WAIT;
    wire select_geom=state==ST_GEOM_WAIT;
    wire select_segment=state==ST_SEG_AREA_WAIT;
    wire select_accum=state==ST_ACCUM_WAIT;
    wire select_cut_accum=state==ST_SEG_ACCUM_WAIT;
    wire select_cut_add=state==ST_CUT_FINAL_START || state==ST_CUT_FINAL_WAIT;
    wire shared_start=select_bvh?bvh_req:
        select_geom?geom_req:
        select_segment?segment_req:
        select_accum?accum_req:
        select_cut_accum?cut_accum_req:
        select_cut_add?cut_add_start:1'b0;
    wire [1:0] shared_op=select_bvh?bvh_op:
        select_geom?geom_op:
        select_segment?segment_op:
        select_accum?accum_op:
        select_cut_accum?cut_accum_op:2'd0;
    wire [63:0] shared_a=select_bvh?bvh_a:
        select_geom?geom_a:
        select_segment?segment_a:
        select_accum?accum_a:
        select_cut_accum?cut_accum_a:cut_area_one;
    wire [63:0] shared_b=select_bvh?bvh_b:
        select_geom?geom_b:
        select_segment?segment_b:
        select_accum?accum_b:
        select_cut_accum?cut_accum_b:cut_area_two;
    dual_plane_fp64_alu #(.PIPELINED(1)) shared_geometry_alu(.clk(aclk),.rst_n(aresetn),
        .start(shared_start),.op(shared_op),.a(shared_a),.b(shared_b),
        .ready(shared_ready),.done(shared_done),.result(shared_result));
    dual_plane_bvh_classify #(.EXTERNAL_ALU(1)) bvh_classify(
        .ext_start(bvh_req),.ext_op(bvh_op),.ext_a(bvh_a),.ext_b(bvh_b),
        .ext_ready(shared_ready&&select_bvh),.ext_done(shared_done&&select_bvh),.ext_result(shared_result),.clk(aclk),.rst_n(aresetn),.start(state==ST_BVH_START),
        .lower({node_words[1][63:0],node_words[0]}),
        .upper({node_words[2],node_words[1][127:64]}),.planes(all_planes),
        .center({center_z,center_y,center_x}),.origin({origin_z,origin_y,origin_x}),
        .flux({node_words[6][63:0],node_words[5]}),.node_volume(node_words[4][63:0]),
        .done(node_done),.busy(),.outside(node_outside),.inside(node_inside),
        .cap_binding(node_binding),.volume(node_volume),.numeric_error(node_numeric));
    reg [127:0] out_word;
    reg [1:0] write_beat;
    reg [31:0] segment_index;
    reg out_valid, out_last;
    reg write_started;
    reg [31:0] candidate_flags;
    reg [63:0] result_volume, result_source_area, result_cut_area;
    reg [31:0] result_source_triangles, result_cut_triangles, result_boundary_segments, result_cap_loops;
    wire geom_busy, geom_done, geom_valid;
    wire [63:0] geom_volume, geom_source_area;
    wire [31:0] geom_source_triangles, geom_boundary_segments, geom_cut_triangles, geom_cap_loops;
    wire [7:0] geom_diagnostics;
    wire geom_segment_valid;
    wire [1:0] geom_segment_plane;
    wire [63:0] geom_segment_ax,geom_segment_ay,geom_segment_az;
    wire [63:0] geom_segment_bx,geom_segment_by,geom_segment_bz;
    wire accum_busy,accum_done;
    wire [63:0] accum_volume,accum_area;
    wire cut_accum_busy,cut_accum_done;
    wire segment_integral_busy,segment_integral_done;
    wire [63:0] segment_signed_area;
    wire cut_add_ready,cut_add_done;
    wire [63:0] cut_add_result;
    wire accum_start=state==ST_ACCUM_START;
    wire accum_clear=state==ST_READ_CAND_AR && cand_beat==0;
    dual_plane_fp64_accumulator #(.EXTERNAL_ALU(1)) accumulator(
        .ext_start(accum_req),.ext_op(accum_op),.ext_a(accum_a),.ext_b(accum_b),
        .ext_ready(serial_alu_ready&&select_accum),.ext_done(serial_accum_done),.ext_result(shared_result),
        .clk(aclk),.rst_n(aresetn),.clear(accum_clear),
        .start(accum_start),.volume_term(aggregate_node ? node_volume : geom_volume),
        .area_term(aggregate_node ? node_words[4][127:64] : geom_source_area),
        .busy(accum_busy),.done(accum_done),.volume_sum(accum_volume),.area_sum(accum_area));
    dual_plane_segment_integral #(.EXTERNAL_ALU(1)) segment_integral(
        .ext_start(segment_req),.ext_op(segment_op),.ext_a(segment_a),.ext_b(segment_b),
        .ext_ready(serial_alu_ready&&select_segment),.ext_done(serial_segment_done),.ext_result(shared_result),
        .clk(aclk),.rst_n(aresetn),
        .start(state==ST_SEG_AREA_START),
        .ax(geom_segment_ax),.ay(geom_segment_ay),.az(geom_segment_az),
        .bx(geom_segment_bx),.by(geom_segment_by),.bz(geom_segment_bz),
        .origin_x(origin_x),.origin_y(origin_y),.origin_z(origin_z),
        .normal_x(geom_segment_plane==2 ? plane_nx[1] : plane_nx[2]),
        .normal_y(geom_segment_plane==2 ? plane_ny[1] : plane_ny[2]),
        .normal_z(geom_segment_plane==2 ? plane_nz[1] : plane_nz[2]),
        .busy(segment_integral_busy),.done(segment_integral_done),
        .signed_area(segment_signed_area));
    dual_plane_fp64_accumulator #(.EXTERNAL_ALU(1)) cut_accumulator(
        .ext_start(cut_accum_req),.ext_op(cut_accum_op),.ext_a(cut_accum_a),.ext_b(cut_accum_b),
        .ext_ready(serial_alu_ready&&select_cut_accum),.ext_done(serial_cut_accum_done),.ext_result(shared_result),
        .clk(aclk),.rst_n(aresetn),
        .clear(accum_clear),.start(state==ST_SEG_ACCUM_START),
        .volume_term(geom_segment_plane==2 ? segment_signed_area : 64'd0),
        .area_term(geom_segment_plane==3 ? segment_signed_area : 64'd0),
        .busy(cut_accum_busy),.done(cut_accum_done),
        .volume_sum(cut_area_one),.area_sum(cut_area_two));
    assign cut_add_ready=serial_alu_ready&&select_cut_add;
    assign cut_add_done=serial_cut_add_done;
    assign cut_add_result=shared_result;
    integer ri,mi,pi;
    wire geom_start = state==ST_GEOM_START;
    wire [63:0] mesh_current_address = mesh_base + tri_index*64'd72;
    wire [63:0] mesh_base_aligned = mesh_current_address & ~64'hf;
    wire [3:0] mesh_byte_offset = mesh_current_address[3:0];
    wire [639:0] mesh_packed = {mesh_words[4],mesh_words[3],mesh_words[2],mesh_words[1],mesh_words[0]};
    wire [575:0] mesh_triangle = mesh_packed >> (mesh_offset * 8);
    function automatic [63:0] candidate_word(input integer index);
        integer beat_index; integer half_index;
        begin beat_index=index/2; half_index=index%2;
            candidate_word=cand_words[beat_index][half_index*64 +:64]; end
    endfunction
    wire segment_overflow = segment_index >= seg_capacity;
    wire geom_segment_ready = (state==ST_SEG_ACK) ||
        (state==ST_GEOM_WAIT && geom_segment_valid && segment_overflow);
    dual_plane_mesh_geometry #(.EXTERNAL_ALU(1)) geometry(
        .ext_start(geom_req),.ext_op(geom_op),.ext_a(geom_a),.ext_b(geom_b),
        .ext_ready(shared_ready&&select_geom),.ext_done(shared_done&&select_geom),.ext_result(shared_result),.clk(aclk),.rst_n(aresetn),.start(geom_start),
        .v0x(mesh_triangle[63:0]),.v0y(mesh_triangle[127:64]),.v0z(mesh_triangle[191:128]),
        .v1x(mesh_triangle[255:192]),.v1y(mesh_triangle[319:256]),.v1z(mesh_triangle[383:320]),
        .v2x(mesh_triangle[447:384]),.v2y(mesh_triangle[511:448]),.v2z(mesh_triangle[575:512]),
        .plane_nx0(plane_nx[0]),.plane_ny0(plane_ny[0]),.plane_nz0(plane_nz[0]),.plane_o0(plane_off[0]),
        .plane_nx1(plane_nx[1]),.plane_ny1(plane_ny[1]),.plane_nz1(plane_nz[1]),.plane_o1(plane_off[1]),
        .plane_nx2(plane_nx[2]),.plane_ny2(plane_ny[2]),.plane_nz2(plane_nz[2]),.plane_o2(plane_off[2]),
        .plane_nx3(plane_nx[3]),.plane_ny3(plane_ny[3]),.plane_nz3(plane_nz[3]),.plane_o3(plane_off[3]),
        .origin_x(origin_x),.origin_y(origin_y),.origin_z(origin_z),
        .busy(geom_busy),.done(geom_done),.valid(geom_valid),.volume(geom_volume),.source_area(geom_source_area),
        .source_triangles(geom_source_triangles),.boundary_segments(geom_boundary_segments),
        .cut_triangles(geom_cut_triangles),.cap_loops(geom_cap_loops),.diagnostics(geom_diagnostics),
        .segment_ready(geom_segment_ready),.segment_valid(geom_segment_valid),
        .segment_plane(geom_segment_plane),
        .segment_ax(geom_segment_ax),.segment_ay(geom_segment_ay),.segment_az(geom_segment_az),
        .segment_bx(geom_segment_bx),.segment_by(geom_segment_by),.segment_bz(geom_segment_bz));
    reg [31:0] candidate_mesh_count;
    wire busy = state != ST_IDLE && state != ST_DONE;
    wire abort_cmd = (s_axi_awvalid && s_axi_wvalid && s_axi_awaddr==`DPM_CONTROL && s_axi_wdata[1]);

    function automatic [31:0] merge_bytes(input [31:0] old_value, input [31:0] new_value, input [3:0] strobe);
        integer b; begin merge_bytes=old_value; for(b=0;b<4;b=b+1) if(strobe[b]) merge_bytes[b*8+:8]=new_value[b*8+:8]; end
    endfunction

    assign s_axi_awready = !aw_pending && !s_axi_bvalid;
    assign s_axi_wready = !w_pending && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;
    assign irq = irq_enable && done_sticky;

    assign m_axi_araddr = read_addr;
    wire mesh_burst_ok = (mesh_beat==0) && (read_addr[11:0] <= 12'hfb0); // 5*16B stays inside 4KB
    assign m_axi_arlen = (state==ST_BVH_AR) ? 8'd7 :
                         (state==ST_READ_MESH_AR && mesh_burst_ok) ? 8'd4 : 8'd0;
    assign m_axi_arsize = 3'd4; assign m_axi_arburst = 2'b01;
    assign m_axi_arprot = 0; assign m_axi_arcache = 4'b0011;
    assign m_axi_arvalid = (state==ST_READ_CAND_AR)||(state==ST_READ_MESH_AR)||(state==ST_BVH_AR);
    assign m_axi_rready = (state==ST_READ_CAND)||(state==ST_READ_MESH)||(state==ST_BVH_READ);
    assign m_axi_awaddr = write_addr; assign m_axi_awlen=8'd3; assign m_axi_awsize=3'd4;
    assign m_axi_awburst=2'b01; assign m_axi_awprot=0; assign m_axi_awcache=4'b0011;
    assign m_axi_awvalid = state==ST_WRITE_AW || state==ST_SEG_AW;
    // One result is 64 bytes, emitted as a four-beat 128-bit AXI burst.
    assign m_axi_wdata = (state==ST_SEG_W) ?
                         ((write_beat==0) ? {geom_segment_ax,62'd0,geom_segment_plane} :
                          (write_beat==1) ? {geom_segment_az,geom_segment_ay} :
                          (write_beat==2) ? {geom_segment_by,geom_segment_bx} :
                                            {64'd0,geom_segment_bz}) :
                         (write_beat==0) ? {result_source_area,result_volume} :
                         (write_beat==1) ? {32'd0,result_source_triangles,result_cut_area} :
                         (write_beat==2) ? {candidate_flags,result_cap_loops,result_boundary_segments,result_cut_triangles} :
                                          {32'd0,ABI,cand_index,job_id};
    assign m_axi_wstrb=16'hffff; assign m_axi_wlast=(write_beat==3);
    assign m_axi_wvalid = state==ST_WRITE_W || state==ST_SEG_W;
    assign m_axi_bready = state==ST_WRITE_B || state==ST_SEG_B;
    assign m_axis_tdata = {32'd0, candidate_mesh_count, candidate_flags, cand_index};
    assign m_axis_tkeep = 16'hffff; assign m_axis_tlast=out_last; assign m_axis_tvalid=out_valid;

    always @(posedge aclk) begin
        if(!aresetn) begin
            state<=ST_IDLE; tri_count<=0; cand_count<=0; seg_capacity<=0; result_count<=0; job_id<=0;
            mesh_base<=0; cand_base<=0; seg_base<=0; result_base<=0; cand_index<=0; tri_index<=0;
            cycle_count<=0; errors<=0; done_sticky<=0; irq_enable<=0; timeout_cycles<=0;
            stop_requested<=0;
            aw_pending<=0; w_pending<=0; s_axi_bvalid<=0; s_axi_bresp<=0; s_axi_rvalid<=0;
            s_axi_rresp<=0; s_axi_rdata<=0; cand_beat<=0; mesh_beat<=0; mesh_burst<=0; read_addr<=0; write_addr<=0;
            out_word<=0; out_valid<=0; out_last<=0; write_started<=0; write_beat<=0; candidate_flags<=0;
            candidate_mesh_count<=0; segment_index<=0;cut_add_start<=0;
            serial_alu_busy<=0;serial_alu_owner<=0;
            result_volume<=0; result_source_area<=0; result_cut_area<=0;
            result_source_triangles<=0; result_cut_triangles<=0; result_boundary_segments<=0; result_cap_loops<=0;
            mesh_offset<=0;
            origin_x<=0;origin_y<=0;origin_z<=0;
            bvh_base<=0;bvh_count<=0;center_x<=0;center_y<=0;center_z<=0;
            node_index<=0;leaf_end<=0;node_beat<=0;aggregate_node<=0;
            for(ri=0;ri<8;ri=ri+1) node_words[ri]<=0;
            for(ri=0;ri<10;ri=ri+1) cand_words[ri]<=0;
            for(mi=0;mi<5;mi=mi+1) mesh_words[mi]<=0;
            for(pi=0;pi<4;pi=pi+1) begin plane_nx[pi]<=0;plane_ny[pi]<=0;plane_nz[pi]<=0;plane_off[pi]<=0;end
        end else begin
            cut_add_start<=0;
            if(serial_alu_busy&&shared_done) serial_alu_busy<=0;
            if(!serial_alu_busy&&shared_start&&shared_ready&&
               (select_segment||select_accum||select_cut_accum||select_cut_add)) begin
                serial_alu_busy<=1;
                serial_alu_owner<=select_segment?3'd1:
                    select_accum?3'd2:select_cut_accum?3'd3:3'd4;
            end
            // Stop only at a candidate boundary after all AXI responses have
            // drained. Never abandon an accepted AR/AW or free its DDR early.
            if(busy) begin
                // Saturate telemetry instead of wrapping after ~43 seconds.
                if(cycle_count!=32'hffffffff) cycle_count<=cycle_count+1;
                if(timeout_cycles!=0 && cycle_count>=timeout_cycles-1) begin errors<=errors|`DPM_ERR_TIMEOUT; stop_requested<=1; end
            end
            if(s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;
            if(s_axi_rvalid && s_axi_rready) s_axi_rvalid<=0;
            if(s_axi_awvalid && s_axi_awready) begin aw_pending<=1; aw_addr<=s_axi_awaddr; end
            if(s_axi_wvalid && s_axi_wready) begin w_pending<=1; w_data<=s_axi_wdata; w_strb<=s_axi_wstrb; end
            if(aw_pending && w_pending && !s_axi_bvalid) begin
                aw_pending<=0; w_pending<=0; s_axi_bvalid<=1; s_axi_bresp<=0;
                if(aw_addr[1:0]!=0) s_axi_bresp<=2'b10;
                else if(aw_addr==`DPM_CONTROL) begin
                    if(w_strb[0] && w_data[1] && busy) begin errors<=errors|`DPM_ERR_ABORT; stop_requested<=1; end
                    if(w_strb[0] && w_data[0] && (state==ST_IDLE || state==ST_DONE)) begin
                        if(tri_count==0 || tri_count>MAX_TRIANGLES || cand_count==0 || cand_count>MAX_CANDIDATES ||
                           result_count<cand_count || mesh_base[3:0]!=0 || cand_base[3:0]!=0 ||
                           result_base[5:0]!=0 || seg_base[5:0]!=0 || bvh_base[6:0]!=0 ||
                           bvh_count>2*MAX_TRIANGLES) begin errors<=`DPM_ERR_DESCRIPTOR; state<=ST_DONE; done_sticky<=1; end
                        else begin stop_requested<=0;cand_index<=0; tri_index<=0; candidate_mesh_count<=0; candidate_flags<=0; errors<=0; done_sticky<=0; cycle_count<=0; cand_beat<=0; read_addr<=cand_base; state<=ST_READ_CAND_AR; end
                    end
                    if(w_strb[1]) irq_enable<=w_data[8];
                end else if(!busy) case(aw_addr)
                    `DPM_TRIANGLE_COUNT: tri_count<=merge_bytes(tri_count,w_data,w_strb);
                    `DPM_CANDIDATE_COUNT: cand_count<=merge_bytes(cand_count,w_data,w_strb);
                    `DPM_JOB_ID: job_id<=merge_bytes(job_id,w_data,w_strb);
                    `DPM_MESH_LO: mesh_base[31:0]<=merge_bytes(mesh_base[31:0],w_data,w_strb);
                    `DPM_MESH_HI: mesh_base[63:32]<=merge_bytes(mesh_base[63:32],w_data,w_strb);
                    `DPM_CANDIDATES_LO: cand_base[31:0]<=merge_bytes(cand_base[31:0],w_data,w_strb);
                    `DPM_CANDIDATES_HI: cand_base[63:32]<=merge_bytes(cand_base[63:32],w_data,w_strb);
                    `DPM_SEGMENTS_LO: seg_base[31:0]<=merge_bytes(seg_base[31:0],w_data,w_strb);
                    `DPM_SEGMENTS_HI: seg_base[63:32]<=merge_bytes(seg_base[63:32],w_data,w_strb);
                    `DPM_RESULTS_LO: result_base[31:0]<=merge_bytes(result_base[31:0],w_data,w_strb);
                    `DPM_RESULTS_HI: result_base[63:32]<=merge_bytes(result_base[63:32],w_data,w_strb);
                    `DPM_SEGMENT_CAPACITY: seg_capacity<=merge_bytes(seg_capacity,w_data,w_strb);
                    `DPM_RESULT_COUNT: result_count<=merge_bytes(result_count,w_data,w_strb);
                    `DPM_CYCLES: timeout_cycles<=merge_bytes(timeout_cycles,w_data,w_strb);
                    `DPM_BVH_LO:bvh_base[31:0]<=merge_bytes(bvh_base[31:0],w_data,w_strb);
                    `DPM_BVH_HI:bvh_base[63:32]<=merge_bytes(bvh_base[63:32],w_data,w_strb);
                    `DPM_BVH_COUNT:bvh_count<=merge_bytes(bvh_count,w_data,w_strb);
                    `DPM_CENTER_X_LO:center_x[31:0]<=merge_bytes(center_x[31:0],w_data,w_strb);
                    `DPM_CENTER_X_HI:center_x[63:32]<=merge_bytes(center_x[63:32],w_data,w_strb);
                    `DPM_CENTER_Y_LO:center_y[31:0]<=merge_bytes(center_y[31:0],w_data,w_strb);
                    `DPM_CENTER_Y_HI:center_y[63:32]<=merge_bytes(center_y[63:32],w_data,w_strb);
                    `DPM_CENTER_Z_LO:center_z[31:0]<=merge_bytes(center_z[31:0],w_data,w_strb);
                    `DPM_CENTER_Z_HI:center_z[63:32]<=merge_bytes(center_z[63:32],w_data,w_strb);
                    default: s_axi_bresp<=2'b10;
                endcase else s_axi_bresp<=2'b10;
            end
            if(s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid<=1; s_axi_rresp<=0; s_axi_rdata<=0;
                case(s_axi_araddr)
                    `DPM_CONTROL: s_axi_rdata<={23'd0,irq_enable,3'd0,(errors!=0),done_sticky,busy,1'b0};
                    `DPM_TRIANGLE_COUNT: s_axi_rdata<=tri_count;
                    `DPM_CANDIDATE_COUNT: s_axi_rdata<=cand_count;
                    `DPM_JOB_ID: s_axi_rdata<=job_id;
                    `DPM_VERSION: s_axi_rdata<=ABI;
                    `DPM_ERRORS: s_axi_rdata<={24'd0,errors};
                    `DPM_SEGMENT_CAPACITY: s_axi_rdata<=seg_capacity;
                    `DPM_RESULT_COUNT: s_axi_rdata<=result_count;
                    `DPM_CYCLES: s_axi_rdata<=cycle_count;
                    `DPM_PROF_CAND_READ: s_axi_rdata<=prof_cycles[0];
                    `DPM_PROF_BVH_READ: s_axi_rdata<=prof_cycles[1];
                    `DPM_PROF_BVH_CLASSIFY: s_axi_rdata<=prof_cycles[2];
                    `DPM_PROF_MESH_READ: s_axi_rdata<=prof_cycles[3];
                    `DPM_PROF_CLIP_SEGMENT: s_axi_rdata<=prof_cycles[4];
                    `DPM_PROF_REDUCE: s_axi_rdata<=prof_cycles[5];
                    `DPM_PROF_OTHER: s_axi_rdata<=prof_cycles[6];
                    `DPM_PROF_AR_COUNT: s_axi_rdata<=prof_ar_count;
                    `DPM_PROF_AR_LATENCY: s_axi_rdata<=prof_ar_latency;
                    default: begin s_axi_rresp<=2'b10; s_axi_rdata<=0; end
                endcase
            end
            case(state)
                ST_READ_CAND_AR: if(m_axi_arready) begin
                    state<=ST_READ_CAND;
                end
                ST_READ_CAND: if(m_axi_rvalid) begin
                    cand_words[cand_beat]<=m_axi_rdata;
                    if(m_axi_rresp!=0) errors<=errors|`DPM_ERR_OPEN_LOOP;
                    if(cand_beat==9) begin
                        for(pi=0;pi<3;pi=pi+1) begin
                            plane_nx[pi]<=candidate_word(pi*4+0);
                            plane_ny[pi]<=candidate_word(pi*4+1);
                            plane_nz[pi]<=candidate_word(pi*4+2);
                            plane_off[pi]<=candidate_word(pi*4+3);
                        end
                        plane_nx[3]<=cand_words[6][63:0]; plane_ny[3]<=cand_words[6][127:64];
                        plane_nz[3]<=cand_words[7][63:0]; plane_off[3]<=cand_words[7][127:64];
                        origin_x<=cand_words[8][63:0]; origin_y<=cand_words[8][127:64];
                        origin_z<=m_axi_rdata[63:0];
                        tri_index<=0; candidate_mesh_count<=0; mesh_beat<=0; segment_index<=0;
                        result_volume<=0;result_source_area<=0;result_source_triangles<=0;
                        result_cut_area<=0;result_cut_triangles<=0;result_boundary_segments<=0;result_cap_loops<=0;
                        // A new candidate always starts at triangle zero,
                        // regardless of the last candidate's tri_index.
                        read_addr<=mesh_base & ~64'hf; mesh_offset<=mesh_base[3:0];
                        aggregate_node<=0;node_index<=0;node_beat<=0;
                        if(bvh_count!=0) begin read_addr<=bvh_base;state<=ST_BVH_AR;end
                        else state<=ST_READ_MESH_AR;
                    end else begin cand_beat<=cand_beat+1; read_addr<=read_addr+16; state<=ST_READ_CAND_AR; end
                end
                ST_READ_MESH_AR: if(m_axi_arready) begin
                    if(mesh_beat==0) begin
                        for(mi=0;mi<5;mi=mi+1) mesh_words[mi]<=0;
                    end
                    mesh_burst<=mesh_burst_ok;
                    state<=ST_READ_MESH;
                end
                ST_READ_MESH: if(m_axi_rvalid) begin
                    mesh_words[mesh_beat]<=m_axi_rdata;
                    candidate_mesh_count<=candidate_mesh_count+1;
                    // RLAST must mark exactly the last beat of the burst (every beat for single reads).
                    if(m_axi_rresp!=0 || (m_axi_rlast !== (mesh_burst ? (mesh_beat==4) : 1'b1)))
                        errors<=errors|`DPM_ERR_OPEN_LOOP;
                    if(mesh_beat==4) begin
                        mesh_beat<=0; mesh_burst<=0;
                        state<=ST_GEOM_START;
                    end else begin
                        mesh_beat<=mesh_beat+1; read_addr<=read_addr+16;
                        state<=mesh_burst ? ST_READ_MESH : ST_READ_MESH_AR;
                    end
                end
                ST_GEOM_START: state<=ST_GEOM_WAIT;
                ST_GEOM_WAIT: begin
                    if(geom_segment_valid) begin
                        if(segment_overflow) candidate_flags<=candidate_flags | `DPM_ERR_SEGMENT_OVF;
                        else begin
                            write_addr<=seg_base + segment_index*64'd64;
                            write_beat<=0;
                            state<=ST_SEG_AW;
                        end
                    end else if(geom_done) begin
                        candidate_flags<=candidate_flags | geom_diagnostics;
                        state<=ST_ACCUM_START;
                    end
                end
                ST_SEG_AW: if(m_axi_awready) state<=ST_SEG_W;
                ST_SEG_W: if(m_axi_wready) begin
                    if(write_beat==3) state<=ST_SEG_B;
                    else write_beat<=write_beat+1'b1;
                end
                ST_SEG_B: if(m_axi_bvalid) begin
                    if(m_axi_bresp!=0) candidate_flags<=candidate_flags | ERR_OPEN;
                    if(geom_segment_plane[1]) state<=ST_SEG_AREA_START;
                    else state<=ST_SEG_ACK;
                end
                ST_SEG_AREA_START: state<=ST_SEG_AREA_WAIT;
                ST_SEG_AREA_WAIT: if(segment_integral_done) state<=ST_SEG_ACCUM_START;
                ST_SEG_ACCUM_START: state<=ST_SEG_ACCUM_WAIT;
                ST_SEG_ACCUM_WAIT: if(cut_accum_done) state<=ST_SEG_ACK;
                ST_SEG_ACK: begin segment_index<=segment_index+1'b1; state<=ST_GEOM_WAIT; end
                ST_ACCUM_START: state<=ST_ACCUM_WAIT;
                ST_ACCUM_WAIT: if(accum_done) begin
                    result_source_triangles<=result_source_triangles+
                        (aggregate_node ? node_triangles : geom_source_triangles);
                    if(!aggregate_node) begin
                        result_boundary_segments<=result_boundary_segments+geom_boundary_segments;
                        result_cut_triangles<=result_cut_triangles+geom_cut_triangles;
                    end
                    if(bvh_count!=0 && (aggregate_node || tri_index+1>=leaf_end)) begin
                        node_index<=node_escape;aggregate_node<=0;state<=ST_BVH_NEXT;
                    end else if(tri_index+1>=tri_count) begin
                        result_volume<={1'b0,accum_volume[62:0]};
                        result_source_area<=accum_area;
                        state<=ST_CUT_FINAL_START;
                    end else begin
                        tri_index<=tri_index+1; mesh_beat<=0;
                        read_addr<=((mesh_base + (tri_index+1)*64'd72) & ~64'hf);
                        mesh_offset<=(mesh_base + (tri_index+1)*64'd72) & 64'hf;
                        state<=ST_READ_MESH_AR;
                    end
                end
                ST_BVH_AR:if(m_axi_arready) state<=ST_BVH_READ;
                ST_BVH_READ:if(m_axi_rvalid) begin
                    node_words[node_beat]<=m_axi_rdata;
                    if(m_axi_rresp!=0 || (m_axi_rlast !== (node_beat==7))) errors<=errors|`DPM_ERR_DESCRIPTOR;
                    if(node_beat==7) state<=ST_BVH_START;
                    else begin node_beat<=node_beat+1'b1;read_addr<=read_addr+16;end
                end
                ST_BVH_START:state<=ST_BVH_WAIT;
                ST_BVH_WAIT:if(node_done) begin
                    if(node_numeric || node_escape<=node_index || node_escape>bvh_count ||
                       node_triangles==0 || node_first>=tri_count || node_triangles>tri_count-node_first) begin
                        candidate_flags<=candidate_flags|`DPM_ERR_DESCRIPTOR;
                        node_index<=bvh_count;state<=ST_BVH_NEXT;
                    end else if(node_index==0 && node_binding) begin
                        candidate_flags<=candidate_flags|`DPM_ERR_BINDING_CAP;
                        node_index<=bvh_count;state<=ST_BVH_NEXT;
                    end else if(node_outside) begin node_index<=node_escape;state<=ST_BVH_NEXT;end
                    else if(node_inside) begin aggregate_node<=1;state<=ST_ACCUM_START;end
                    else if(node_leaf) begin
                        aggregate_node<=0;tri_index<=node_first;leaf_end<=node_first+node_triangles;
                        mesh_beat<=0;read_addr<=(mesh_base+node_first*64'd72)&~64'hf;
                        mesh_offset<=(mesh_base+node_first*64'd72)&64'hf;state<=ST_READ_MESH_AR;
                    end else begin node_index<=node_index+1'b1;state<=ST_BVH_NEXT;end
                end
                ST_BVH_NEXT:begin
                    if(node_index>=bvh_count) begin
                        result_volume<={1'b0,accum_volume[62:0]};result_source_area<=accum_area;
                        state<=ST_CUT_FINAL_START;
                    end else begin node_beat<=0;read_addr<=bvh_base+node_index*64'd128;state<=ST_BVH_AR;end
                end
                ST_CUT_FINAL_START: if(cut_add_ready) begin cut_add_start<=1;state<=ST_CUT_FINAL_WAIT;end
                ST_CUT_FINAL_WAIT: if(cut_add_done) begin
                    result_cut_area<=cut_add_result;
                    if(result_volume[62:52]==11'h7ff || result_source_area[62:52]==11'h7ff ||
                       cut_add_result[62:52]==11'h7ff ||
                       (cut_area_one[63] && cut_area_one[62:0]>63'h3e7ad7f29abcaf48) ||
                       (cut_area_two[63] && cut_area_two[62:0]>63'h3e7ad7f29abcaf48))
                        candidate_flags<=candidate_flags|`DPM_ERR_NUMERIC;
                    write_addr<=result_base + cand_index*64;write_beat<=0;state<=ST_WRITE_AW;
                end
                ST_WRITE_AW: if(m_axi_awready) state<=ST_WRITE_W;
                ST_WRITE_W: if(m_axi_wready) begin if(write_beat==3) state<=ST_WRITE_B; else write_beat<=write_beat+1; end
                ST_WRITE_B: if(m_axi_bvalid) begin if(m_axi_bresp!=0) errors<=errors|`DPM_ERR_OPEN_LOOP; out_valid<=1; out_last<=cand_index+1>=cand_count; state<=ST_OUTPUT; end
                ST_OUTPUT: if(!ENABLE_STATUS_STREAM || m_axis_tready || stop_requested) begin out_valid<=0; if(cand_index+1>=cand_count || stop_requested) begin done_sticky<=1; state<=ST_DONE; end else begin cand_index<=cand_index+1; cand_beat<=0; candidate_flags<=0; read_addr<=cand_base+(cand_index+1)*160; state<=ST_READ_CAND_AR; end end
                ST_DONE: if(!busy && s_axi_awvalid && s_axi_wvalid && s_axi_awaddr==`DPM_CONTROL && s_axi_wdata[0]) begin end
                default: begin end
            endcase
        end
    end
    // Read-only performance profile. It observes state and AXI handshakes only
    // and never feeds the datapath. Classes match sim/tb_dual_plane_mesh_vectors.sv.
    always @* begin
        case(state)
            ST_READ_CAND_AR, ST_READ_CAND: prof_class=3'd0;
            ST_BVH_AR, ST_BVH_READ: prof_class=3'd1;
            ST_BVH_START, ST_BVH_WAIT, ST_BVH_NEXT: prof_class=3'd2;
            ST_READ_MESH_AR, ST_READ_MESH: prof_class=3'd3;
            ST_GEOM_START, ST_GEOM_WAIT, ST_SEG_AW, ST_SEG_W, ST_SEG_B, ST_SEG_ACK,
            ST_SEG_AREA_START, ST_SEG_AREA_WAIT,
            ST_SEG_ACCUM_START, ST_SEG_ACCUM_WAIT: prof_class=3'd4;
            ST_ACCUM_START, ST_ACCUM_WAIT,
            ST_CUT_FINAL_START, ST_CUT_FINAL_WAIT: prof_class=3'd5;
            default: prof_class=3'd6;
        endcase
    end
    always @(posedge aclk) begin
        if(!aresetn) begin
            for(prof_i=0;prof_i<7;prof_i=prof_i+1) prof_cycles[prof_i]<=0;
            prof_ar_count<=0; prof_ar_latency<=0; prof_ar_outstanding<=0; prof_busy_q<=0;
        end else begin
            prof_busy_q<=busy;
            if(busy && !prof_busy_q) begin
                for(prof_i=0;prof_i<7;prof_i=prof_i+1) prof_cycles[prof_i]<=(prof_i==prof_class)?32'd1:32'd0;
                prof_ar_count<=0; prof_ar_latency<=0; prof_ar_outstanding<=0;
            end else if(busy) begin
                if(prof_cycles[prof_class]!=32'hffffffff) prof_cycles[prof_class]<=prof_cycles[prof_class]+1;
                if(m_axi_arvalid && m_axi_arready) begin
                    prof_ar_outstanding<=1;
                    if(prof_ar_count!=32'hffffffff) prof_ar_count<=prof_ar_count+1;
                end
                if(prof_ar_outstanding) begin
                    if(m_axi_rvalid && m_axi_rready) prof_ar_outstanding<=0;
                    if(prof_ar_latency!=32'hffffffff) prof_ar_latency<=prof_ar_latency+1;
                end
            end
        end
    end

endmodule
