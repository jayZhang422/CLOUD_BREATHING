`timescale 1ns/1ps

// One source triangle through four-plane clipping and source-face reduction.
// Candidate descriptors and clipper both use outward n*x - offset <= 0.
module dual_plane_mesh_geometry #(parameter EXTERNAL_ALU=0) (
    output wire ext_start,output wire [1:0] ext_op,output wire [63:0] ext_a,ext_b,
    input wire ext_ready,ext_done,input wire [63:0] ext_result,
    input wire clk, input wire rst_n, input wire start,
    input wire [63:0] v0x,v0y,v0z,v1x,v1y,v1z,v2x,v2y,v2z,
    input wire [63:0] plane_nx0,plane_ny0,plane_nz0,plane_o0,
    input wire [63:0] plane_nx1,plane_ny1,plane_nz1,plane_o1,
    input wire [63:0] plane_nx2,plane_ny2,plane_nz2,plane_o2,
    input wire [63:0] plane_nx3,plane_ny3,plane_nz3,plane_o3,
    input wire [63:0] origin_x,origin_y,origin_z,
    output reg busy, output reg done, output reg valid,
    output reg [63:0] volume, output reg [63:0] source_area,
    output reg [31:0] source_triangles, output reg [31:0] boundary_segments,
    output reg [31:0] cut_triangles, output reg [31:0] cap_loops,
    output reg [7:0] diagnostics,
    input wire segment_ready, output wire segment_valid,
    output wire [1:0] segment_plane,
    output wire [63:0] segment_ax,segment_ay,segment_az,
    output wire [63:0] segment_bx,segment_by,segment_bz
);
    localparam [2:0] S_IDLE=0,S_CLIP=1,S_REDUCE=2,S_BOUNDARY=3,S_FINISH=4;
    reg [2:0] state;
    reg clip_start,reduce_start,boundary_start;
    wire clip_busy,clip_done,clip_valid;
    wire [3:0] polygon_count;
    wire [447:0] clip_x,clip_y,clip_z; wire [27:0] clip_mask;
    wire [7:0] clip_diag;
    wire reduce_busy,reduce_done,reduce_valid;
    wire [63:0] reduce_volume,reduce_area;
    wire [31:0] reduce_triangles;
    wire clip_req,reduce_req,shared_ready,shared_done;
    wire [1:0] clip_op,reduce_op;
    wire [63:0] clip_a,clip_b,reduce_a,reduce_b,shared_result;
    // Only one stage is live, and all issued results drain before clip_done.
    // Sharing removes redundant FP64 IP; it does not serialize parallel work.
    wire select_reduce=state==S_REDUCE;
    assign ext_start=select_reduce?reduce_req:clip_req;
    assign ext_op=select_reduce?reduce_op:clip_op;
    assign ext_a=select_reduce?reduce_a:clip_a;assign ext_b=select_reduce?reduce_b:clip_b;
    generate if(EXTERNAL_ALU) begin
        assign shared_ready=ext_ready;assign shared_done=ext_done;assign shared_result=ext_result;
    end else begin
        dual_plane_fp64_alu #(.PIPELINED(1)) shared_alu(.clk(clk),.rst_n(rst_n),
            .start(ext_start),.op(ext_op),.a(ext_a),.b(ext_b),
            .ready(shared_ready),.done(shared_done),.result(shared_result));
    end endgenerate
    dual_plane_triangle_clip #(.EXTERNAL_ALU(1)) clip(
        .ext_start(clip_req),.ext_op(clip_op),.ext_a(clip_a),.ext_b(clip_b),
        .ext_ready(shared_ready&&!select_reduce),.ext_done(shared_done&&!select_reduce),.ext_result(shared_result),.clk(clk),.rst_n(rst_n),.start(clip_start),
        .in_v0x(v0x),.in_v0y(v0y),.in_v0z(v0z),.in_v1x(v1x),.in_v1y(v1y),.in_v1z(v1z),.in_v2x(v2x),.in_v2y(v2y),.in_v2z(v2z),
        .plane_nx0(plane_nx0),.plane_ny0(plane_ny0),.plane_nz0(plane_nz0),.plane_o0(plane_o0),
        .plane_nx1(plane_nx3),.plane_ny1(plane_ny3),.plane_nz1(plane_nz3),.plane_o1(plane_o3),
        .plane_nx2(plane_nx1),.plane_ny2(plane_ny1),.plane_nz2(plane_nz1),.plane_o2(plane_o1),
        .plane_nx3(plane_nx2),.plane_ny3(plane_ny2),.plane_nz3(plane_nz2),.plane_o3(plane_o2),
        .busy(clip_busy),.done(clip_done),.valid(clip_valid),.polygon_count(polygon_count),
        .out_x(clip_x),.out_y(clip_y),.out_z(clip_z),.out_mask(clip_mask),.diagnostics(clip_diag));
    dual_plane_polygon_reduce #(.EXTERNAL_ALU(1)) reduce(
        .ext_start(reduce_req),.ext_op(reduce_op),.ext_a(reduce_a),.ext_b(reduce_b),
        .ext_ready(shared_ready&&select_reduce),.ext_done(shared_done&&select_reduce),.ext_result(shared_result),.clk(clk),.rst_n(rst_n),.start(reduce_start),
        .polygon_count(polygon_count),.in_x(clip_x),.in_y(clip_y),.in_z(clip_z),
        .origin_x(origin_x),.origin_y(origin_y),.origin_z(origin_z),
        .busy(reduce_busy),.done(reduce_done),.valid(reduce_valid),.signed_volume(reduce_volume),
        .area(reduce_area),.triangle_count(reduce_triangles));
    wire boundary_done;
    wire [31:0] boundary_count;
    wire [7:0] boundary_diag;
    dual_plane_boundary_extract boundary(.clk(clk),.rst_n(rst_n),.start(boundary_start),
        .polygon_count(polygon_count),.in_x(clip_x),.in_y(clip_y),.in_z(clip_z),
        .in_mask(clip_mask),.segment_ready(segment_ready),
        .busy(),.done(boundary_done),.segment_valid(segment_valid),
        .segment_plane(segment_plane),.ax(segment_ax),.ay(segment_ay),.az(segment_az),
        .bx(segment_bx),.by(segment_by),.bz(segment_bz),
        .segment_count(boundary_count),.diagnostics(boundary_diag));
    always @(posedge clk) begin
        if(!rst_n) begin state<=S_IDLE;busy<=0;done<=0;valid<=0;clip_start<=0;reduce_start<=0;boundary_start<=0;
            volume<=0;source_area<=0;source_triangles<=0;boundary_segments<=0;cut_triangles<=0;cap_loops<=0;diagnostics<=0; end
        else begin
            done<=0;clip_start<=0;reduce_start<=0;boundary_start<=0;
            case(state)
                S_IDLE: if(start) begin
                    busy<=1;valid<=0;diagnostics<=0;clip_start<=1;state<=S_CLIP;
                    volume<=0;source_area<=0;source_triangles<=0;
                    boundary_segments<=0;cut_triangles<=0;cap_loops<=0;
                end
                S_CLIP: if(clip_done) begin
                    diagnostics<=clip_diag;
                    if(clip_valid) begin reduce_start<=1; state<=S_REDUCE; end
                    else begin valid<=0; state<=S_FINISH; end
                end
                S_REDUCE: if(reduce_done) begin
                    volume<=reduce_volume;
                    source_area<=reduce_area; source_triangles<=reduce_triangles;
                    boundary_start<=1; cut_triangles<=0; cap_loops<=0;
                    diagnostics<=clip_diag;
                    valid<=reduce_valid; state<=S_BOUNDARY;
                end
                S_BOUNDARY: if(boundary_done) begin
                    boundary_segments<=boundary_count;
                    diagnostics<=diagnostics | boundary_diag;
                    state<=S_FINISH;
                end
                S_FINISH: begin busy<=0;done<=1;state<=S_IDLE;end
                default:state<=S_IDLE;
            endcase
        end
    end
endmodule
