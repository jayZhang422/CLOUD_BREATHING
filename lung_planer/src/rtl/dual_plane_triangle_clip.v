`timescale 1ns/1ps

// IEEE-754 double Sutherland-Hodgman clipper for one source triangle.
// Independent distances and xyz intersection coordinates issue in epochs;
// every intermediate and expression order remains IEEE-754 FP64.
module dual_plane_triangle_clip #(parameter EXTERNAL_ALU=0) (
    input wire clk, input wire rst_n, input wire start,
    input wire [63:0] in_v0x, in_v0y, in_v0z, in_v1x, in_v1y, in_v1z, in_v2x, in_v2y, in_v2z,
    input wire [63:0] plane_nx0, plane_ny0, plane_nz0, plane_o0,
    input wire [63:0] plane_nx1, plane_ny1, plane_nz1, plane_o1,
    input wire [63:0] plane_nx2, plane_ny2, plane_nz2, plane_o2,
    input wire [63:0] plane_nx3, plane_ny3, plane_nz3, plane_o3,
    output reg busy, output reg done, output reg valid,
    output reg [3:0] polygon_count,
    // Packed outputs keep the module Verilog-2001 compatible. Vertex i is
    // carried in bits [i*64 +: 64], mask i in [i*4 +: 4].
    output reg [447:0] out_x, out_y, out_z,
    output reg [27:0] out_mask,
    output wire ext_start, output wire [1:0] ext_op,
    output wire [63:0] ext_a,ext_b,
    input wire ext_ready,ext_done,input wire [63:0] ext_result,
    output reg [7:0] diagnostics
);
    localparam [3:0] ST_IDLE=0, ST_D_PREP=1, ST_ISSUE=2, ST_WAIT=3,
                     ST_EDGE=4, ST_INTERSECT=5, ST_EMIT_INTERSECTION=6,
                     ST_EMIT_CURRENT=7, ST_NEXT_EDGE=8, ST_NEXT_PLANE=9,
                     ST_FINISH=10, ST_D_BATCH=11, ST_I_BATCH=12;
    localparam [1:0] OP_ADD=0, OP_MUL=1, OP_DIV=2, OP_SQRT=3;
    localparam [3:0] DEST_D_MUL=1, DEST_D_ADD=2, DEST_D_OFFSET=3,
                     DEST_DENOM=4, DEST_T=5, DEST_DELTA=6, DEST_PRODUCT=7,
                     DEST_POINT=8;
    reg [3:0] state;
    reg [1:0] alu_op; reg [63:0] alu_a, alu_b; reg alu_start;
    wire alu_ready, alu_done; wire [63:0] alu_result;
    reg [3:0] alu_dest;
    wire batch_request,batch_done;wire [1:0] batch_op;
    wire [63:0] batch_a,batch_b;wire [447:0] batch_dist;
    reg batch_start;
    wire batch_active=state==ST_D_BATCH;
    wire intersection_active=state==ST_I_BATCH;
    reg [1:0] intersection_phase,intersection_sent,intersection_received;
    reg [63:0] intersection_temp[0:2];
    reg [63:0] intersection_a,intersection_b;
    wire intersection_request=intersection_active && intersection_sent<3;
    assign ext_start=intersection_active?intersection_request:batch_active?batch_request:alu_start;
    assign ext_op=intersection_active?(intersection_phase==1?OP_MUL:OP_ADD):batch_active?batch_op:alu_op;
    assign ext_a=intersection_active?intersection_a:batch_active?batch_a:alu_a;
    assign ext_b=intersection_active?intersection_b:batch_active?batch_b:alu_b;
    generate if(EXTERNAL_ALU) begin : shared_alu
        assign alu_ready=ext_ready;assign alu_done=ext_done;assign alu_result=ext_result;
    end else begin : local_alu
        dual_plane_fp64_alu #(.ENABLE_SQRT(0),.PIPELINED(1)) alu(
            .clk(clk),.rst_n(rst_n),.start(ext_start),.op(ext_op),.a(ext_a),.b(ext_b),
            .ready(alu_ready),.done(alu_done),.result(alu_result));
    end endgenerate
    reg [63:0] poly_x [0:6], poly_y [0:6], poly_z [0:6];
    reg [3:0] poly_mask [0:6];
    reg [63:0] next_x [0:6], next_y [0:6], next_z [0:6];
    reg [3:0] next_mask [0:6];
    reg [63:0] dist [0:6], dist_acc, temp_result, t_reg, delta_reg, product_reg;
    reg [63:0] pnx [0:3], pny [0:3], pnz [0:3], poff [0:3];
    reg [3:0] plane_index, vertex_index, axis_index, prev_index, curr_index, emit_count;
    reg [1:0] coord_index;
    reg [63:0] inter_x, inter_y, inter_z;
    wire [191:0] previous_xyz={poly_z[prev_index],poly_y[prev_index],poly_x[prev_index]};
    wire [191:0] current_xyz={poly_z[curr_index],poly_y[curr_index],poly_x[curr_index]};
    always @* begin
        intersection_a=0;intersection_b=0;
        case(intersection_phase)
        0:begin intersection_a=current_xyz[intersection_sent*64+:64];
                intersection_b=neg_fp(previous_xyz[intersection_sent*64+:64]);end
        1:begin intersection_a=t_reg;intersection_b=intersection_temp[intersection_sent];end
        2:begin intersection_a=previous_xyz[intersection_sent*64+:64];
                intersection_b=intersection_temp[intersection_sent];end
        endcase
    end
    reg prev_inside, curr_inside, crossing;
    reg mask_pass;
    reg new_intersection;
    localparam [62:0] CLIP_EPS = 63'h3ddb7cdfd9d7bdbb;
    localparam [62:0] PLANE_EPS = 63'h3e8ad7f29abcaf48;
    localparam [7:0] ERR_BINDING_CAP = 8'h20;
    wire closing_duplicate = emit_count > 1 &&
        next_x[0] == next_x[emit_count-1] &&
        next_y[0] == next_y[emit_count-1] &&
        next_z[0] == next_z[emit_count-1];
    wire [3:0] clean_emit_count = closing_duplicate ? emit_count-1'b1 : emit_count;
    wire [447:0] packed_x,packed_y,packed_z;
    genvar g;
    generate for(g=0;g<7;g=g+1) begin : batch_inputs
        assign packed_x[g*64+:64]=poly_x[g];
        assign packed_y[g*64+:64]=poly_y[g];
        assign packed_z[g*64+:64]=poly_z[g];
    end endgenerate
    dual_plane_distance_batch distance_batch(.clk(clk),.rst_n(rst_n),.start(batch_start),
        .count(polygon_count),.x(packed_x),.y(packed_y),.z(packed_z),
        .nx(pnx[plane_index]),.ny(pny[plane_index]),.nz(pnz[plane_index]),.offset(poff[plane_index]),
        .request(batch_request),.ready(alu_ready),.valid(alu_done&&batch_active),.value(alu_result),
        .alu_op(batch_op),.a(batch_a),.b(batch_b),.busy(),.done(batch_done),.distances(batch_dist));
    reg binding_error;integer bi;
    always @* begin
        binding_error=0;
        for(bi=0;bi<7;bi=bi+1)
            if(bi<polygon_count && !is_inside(batch_dist[bi*64+:64])) binding_error=1;
    end
    integer i;
    function automatic is_inside(input [63:0] d);
        begin is_inside = (d[63] == 1'b1) || (d[62:0] <= CLIP_EPS); end
    endfunction
    function automatic [63:0] neg_fp(input [63:0] d);
        begin neg_fp = {~d[63], d[62:0]}; end
    endfunction
    function automatic [63:0] vx(input integer idx);
        begin case(idx) 0:vx=poly_x[prev_index]; 1:vx=poly_y[prev_index]; default:vx=poly_z[prev_index]; endcase end
    endfunction
    function automatic [63:0] vy(input integer idx);
        begin case(idx) 0:vy=poly_x[curr_index]; 1:vy=poly_y[curr_index]; default:vy=poly_z[curr_index]; endcase end
    endfunction
    function automatic [63:0] plane_nx(input integer idx);
        begin plane_nx=pnx[idx]; end
    endfunction
    function automatic [63:0] plane_ny(input integer idx);
        begin plane_ny=pny[idx]; end
    endfunction
    function automatic [63:0] plane_nz(input integer idx);
        begin plane_nz=pnz[idx]; end
    endfunction
    function automatic [63:0] current_coord(input integer which, input integer idx);
        begin
            if(which==0) case(idx) 0:current_coord=poly_x[prev_index]; 1:current_coord=poly_y[prev_index]; default:current_coord=poly_z[prev_index]; endcase
            else case(idx) 0:current_coord=poly_x[curr_index]; 1:current_coord=poly_y[curr_index]; default:current_coord=poly_z[curr_index]; endcase
        end
    endfunction
    always @(posedge clk) begin
        if(!rst_n) begin
            intersection_phase<=0;intersection_sent<=0;intersection_received<=0;
            batch_start<=0;state<=ST_IDLE; busy<=0; done<=0; valid<=0; polygon_count<=0; diagnostics<=0;
            out_x<=0; out_y<=0; out_z<=0; out_mask<=0;
            alu_start<=0; alu_op<=0; alu_a<=0; alu_b<=0; alu_dest<=0; plane_index<=0;
            vertex_index<=0; axis_index<=0; prev_index<=0; curr_index<=0; emit_count<=0; coord_index<=0;
            inter_x<=0; inter_y<=0; inter_z<=0; prev_inside<=0; curr_inside<=0; crossing<=0;
            mask_pass<=0;new_intersection<=0;
            for(i=0;i<7;i=i+1) begin poly_x[i]<=0;poly_y[i]<=0;poly_z[i]<=0;poly_mask[i]<=0;next_x[i]<=0;next_y[i]<=0;next_z[i]<=0;next_mask[i]<=0;dist[i]<=0; end
            for(i=0;i<4;i=i+1) begin pnx[i]<=0;pny[i]<=0;pnz[i]<=0;poff[i]<=0; end
        end else begin
            done<=0; alu_start<=0;batch_start<=0;
            if(state==ST_IDLE) begin
                if(start) begin
                    busy<=1; valid<=0; diagnostics<=0; plane_index<=0; vertex_index<=0; axis_index<=0;
                    mask_pass<=0;new_intersection<=0;
                    poly_x[0]<=in_v0x;poly_y[0]<=in_v0y;poly_z[0]<=in_v0z;poly_mask[0]<=0;
                    poly_x[1]<=in_v1x;poly_y[1]<=in_v1y;poly_z[1]<=in_v1z;poly_mask[1]<=0;
                    poly_x[2]<=in_v2x;poly_y[2]<=in_v2y;poly_z[2]<=in_v2z;poly_mask[2]<=0;
                    polygon_count<=3;
                    pnx[0]<=plane_nx0;pny[0]<=plane_ny0;pnz[0]<=plane_nz0;poff[0]<=plane_o0;
                    pnx[1]<=plane_nx1;pny[1]<=plane_ny1;pnz[1]<=plane_nz1;poff[1]<=plane_o1;
                    pnx[2]<=plane_nx2;pny[2]<=plane_ny2;pnz[2]<=plane_nz2;poff[2]<=plane_o2;
                    pnx[3]<=plane_nx3;pny[3]<=plane_ny3;pnz[3]<=plane_nz3;poff[3]<=plane_o3;
                    state<=ST_D_PREP;
                end
            end else if(state==ST_D_PREP) begin
                if(vertex_index >= polygon_count) begin
                    if(mask_pass) begin
                        if(plane_index==3) state<=ST_FINISH;
                        else begin plane_index<=plane_index+1'b1;vertex_index<=0;axis_index<=0;end
                    end else begin prev_index <= polygon_count-1; curr_index<=0; emit_count<=0; state<=ST_EDGE;end
                end else begin
                    batch_start<=1;state<=ST_D_BATCH;
                end
            end else if(state==ST_D_BATCH) begin
                if(batch_done) begin
                    for(i=0;i<7;i=i+1) if(i<polygon_count) begin
                        dist[i]<=batch_dist[i*64+:64];
                        if((batch_dist[i*64+:64]&64'h7fffffffffffffff)<=PLANE_EPS)
                            poly_mask[i]<=poly_mask[i]|(4'b0001<<plane_index);
                    end
                    if(!mask_pass&&plane_index<2&&binding_error)
                        diagnostics<=diagnostics|ERR_BINDING_CAP;
                    vertex_index<=polygon_count;state<=ST_D_PREP;
                end
            end else if(state==ST_ISSUE) begin
                if(alu_ready) begin alu_start<=1; state<=ST_WAIT; end
            end else if(state==ST_WAIT) begin
                if(alu_done) begin
                    case(alu_dest)
                        DEST_D_MUL: begin
                            if(axis_index==0) begin dist_acc<=alu_result; axis_index<=1; state<=ST_D_PREP; end
                            else begin temp_result<=alu_result; alu_op<=OP_ADD; alu_a<=dist_acc; alu_b<=alu_result; alu_dest<=DEST_D_ADD; state<=ST_ISSUE; end
                        end
                        DEST_D_ADD: begin
                            dist_acc<=alu_result;
                            if(axis_index<2) begin axis_index<=axis_index+1; state<=ST_D_PREP; end
                            else begin alu_op<=OP_ADD; alu_a<=alu_result; alu_b<=neg_fp(poff[plane_index]); alu_dest<=DEST_D_OFFSET; state<=ST_ISSUE; end
                        end
                        DEST_D_OFFSET: begin
                            dist[vertex_index]<=alu_result;
                            if(!mask_pass && plane_index<2 && !is_inside(alu_result))
                                diagnostics<=diagnostics | ERR_BINDING_CAP;
                            if(alu_result[62:0] <= PLANE_EPS)
                                poly_mask[vertex_index] <= poly_mask[vertex_index] | (4'b0001 << plane_index);
                            vertex_index<=vertex_index+1; axis_index<=0; state<=ST_D_PREP;
                        end
                        DEST_DENOM: begin temp_result<=alu_result; alu_op<=OP_DIV; alu_a<=dist[prev_index]; alu_b<=alu_result; alu_dest<=DEST_T; state<=ST_ISSUE; end
                        DEST_T: begin t_reg<=alu_result;intersection_phase<=0;intersection_sent<=0;intersection_received<=0;state<=ST_I_BATCH; end
                        DEST_DELTA: begin delta_reg<=alu_result; alu_op<=OP_MUL; alu_a<=t_reg; alu_b<=alu_result; alu_dest<=DEST_PRODUCT; state<=ST_ISSUE; end
                        DEST_PRODUCT: begin product_reg<=alu_result; alu_op<=OP_ADD; alu_a<=current_coord(0,coord_index); alu_b<=alu_result; alu_dest<=DEST_POINT; state<=ST_ISSUE; end
                        DEST_POINT: begin
                            if(coord_index==0) inter_x<=alu_result; else if(coord_index==1) inter_y<=alu_result; else inter_z<=alu_result;
                            if(coord_index<2) begin coord_index<=coord_index+1; state<=ST_INTERSECT; end else state<=ST_EMIT_INTERSECTION;
                        end
                        default: state<=ST_EDGE;
                    endcase
                end
            end else if(state==ST_EDGE) begin
                prev_inside<=is_inside(dist[prev_index]); curr_inside<=is_inside(dist[curr_index]);
                crossing<=is_inside(dist[prev_index]) != is_inside(dist[curr_index]);
                if(is_inside(dist[prev_index]) != is_inside(dist[curr_index])) begin
                    new_intersection<=1;
                    alu_op<=OP_ADD; alu_a<=dist[prev_index]; alu_b<=neg_fp(dist[curr_index]); alu_dest<=DEST_DENOM; state<=ST_ISSUE;
                end else if(is_inside(dist[curr_index])) state<=ST_EMIT_CURRENT;
                else state<=ST_NEXT_EDGE;
            end else if(state==ST_INTERSECT) begin
                alu_op<=OP_ADD; alu_a<=current_coord(1,coord_index); alu_b<=neg_fp(current_coord(0,coord_index)); alu_dest<=DEST_DELTA; state<=ST_ISSUE;
            end else if(state==ST_I_BATCH) begin
                if(intersection_request&&alu_ready) intersection_sent<=intersection_sent+1'b1;
                if(alu_done) begin
                    intersection_temp[intersection_received]<=alu_result;
                    if(intersection_phase==2) case(intersection_received)
                        0:inter_x<=alu_result;1:inter_y<=alu_result;2:inter_z<=alu_result;
                    endcase
                    intersection_received<=intersection_received+1'b1;
                    if(intersection_received==2) begin
                        intersection_sent<=0;intersection_received<=0;intersection_phase<=intersection_phase+1'b1;
                        if(intersection_phase==2) state<=ST_EMIT_INTERSECTION;
                    end
                end
            end else if(state==ST_EMIT_INTERSECTION) begin
                if(emit_count<7 && (emit_count==0 ||
                   next_x[emit_count-1]!=inter_x || next_y[emit_count-1]!=inter_y || next_z[emit_count-1]!=inter_z)) begin
                    next_x[emit_count]<=inter_x;next_y[emit_count]<=inter_y;next_z[emit_count]<=inter_z;
                    next_mask[emit_count]<=(poly_mask[prev_index] & poly_mask[curr_index]) |
                                           (4'b0001<<plane_index);emit_count<=emit_count+1;
                end
                if(curr_inside) state<=ST_EMIT_CURRENT; else state<=ST_NEXT_EDGE;
            end else if(state==ST_EMIT_CURRENT) begin
                if(emit_count<7 && (emit_count==0 ||
                   next_x[emit_count-1]!=poly_x[curr_index] || next_y[emit_count-1]!=poly_y[curr_index] || next_z[emit_count-1]!=poly_z[curr_index])) begin
                    next_x[emit_count]<=poly_x[curr_index];next_y[emit_count]<=poly_y[curr_index];next_z[emit_count]<=poly_z[curr_index];
                    next_mask[emit_count]<=poly_mask[curr_index];emit_count<=emit_count+1;
                end
                state<=ST_NEXT_EDGE;
            end else if(state==ST_NEXT_EDGE) begin
                if(curr_index+1 >= polygon_count) state<=ST_NEXT_PLANE;
                else begin prev_index<=curr_index;curr_index<=curr_index+1;state<=ST_EDGE; end
            end else if(state==ST_NEXT_PLANE) begin
                for(i=0;i<7;i=i+1) begin poly_x[i]<=next_x[i];poly_y[i]<=next_y[i];poly_z[i]<=next_z[i];poly_mask[i]<=next_mask[i]; end
                polygon_count<=clean_emit_count;
                if(clean_emit_count<3) begin valid<=0; state<=ST_FINISH; end
                else if(plane_index==3 && new_intersection) begin
                    // Reclassify final vertices against every plane. A later
                    // clipping intersection can land on an earlier plane at
                    // an endpoint even when its edge had no common mask.
                    valid<=1;mask_pass<=1;plane_index<=0;vertex_index<=0;axis_index<=0;state<=ST_D_PREP;
                end
                else if(plane_index==3) begin valid<=1;state<=ST_FINISH;end
                else begin plane_index<=plane_index+1;vertex_index<=0;axis_index<=0;state<=ST_D_PREP; end
            end else if(state==ST_FINISH) begin
                // The final plane has already committed next_* into poly_* in
                // ST_NEXT_PLANE. Pack the stable result for the AXI wrapper.
                for(i=0;i<7;i=i+1) begin
                    out_x[i*64 +: 64] <= poly_x[i];
                    out_y[i*64 +: 64] <= poly_y[i];
                    out_z[i*64 +: 64] <= poly_z[i];
                    out_mask[i*4 +: 4] <= poly_mask[i];
                end
                busy<=0; done<=1; state<=ST_IDLE;
            end
        end
    end
endmodule

module dual_plane_distance_batch(
    input clk,rst_n,start, input [3:0] count,
    input [447:0] x,y,z,
    input [63:0] nx,ny,nz,offset,
    // Verification throttles; tied high in any production integration.
    output request, input ready, valid, input [63:0] value,
    output [1:0] alu_op, output reg [63:0] a,b,
    output reg busy,done, output [447:0] distances
);
    reg [1:0] phase,sa,ra;
    reg [3:0] sv,rv;
    // No reset or enable fanout on data: each live entry is written before use.
    // A tiny 7-entry memory is intentionally inferred as distributed RAM;
    // larger triangle context queues should use BRAM, not resettable FFs.
    (* ram_style="distributed" *) reg [63:0] px[0:6],py[0:6],pz[0:6],acc[0:6];
    assign request=busy&&(sv<count);
    assign alu_op=phase==0?2'd1:2'd0;
    genvar g;
    generate for(g=0;g<7;g=g+1) begin assign distances[g*64+:64]=acc[g]; end endgenerate
    always @* begin
        a=0;b=0;
        case(phase)
        0: case(sa)
            0:begin a=nx;b=x[sv*64+:64];end
            1:begin a=ny;b=y[sv*64+:64];end
            2:begin a=nz;b=z[sv*64+:64];end
        endcase
        1:begin a=px[sv];b=py[sv];end
        2:begin a=acc[sv];b=pz[sv];end
        3:begin a=acc[sv];b={~offset[63],offset[62:0]};end
        endcase
    end
    always @(posedge clk) begin
        if(!rst_n) begin busy<=0;done<=0;phase<=0;sv<=0;rv<=0;sa<=0;ra<=0;end
        else begin
            done<=0;
            if(!busy&&start) begin busy<=1;phase<=0;sv<=0;rv<=0;sa<=0;ra<=0;end
            else if(busy) begin
                if(request&&ready) begin
                    if(phase==0&&sa<2) sa<=sa+1'b1;
                    else begin sa<=0;sv<=sv+1'b1;end
                end
                if(valid) begin
                    if(phase==0) case(ra) 0:px[rv]<=value;1:py[rv]<=value;2:pz[rv]<=value;endcase
                    else acc[rv]<=value;
                    if(phase==0&&ra<2) ra<=ra+1'b1;
                    else begin
                        ra<=0;rv<=rv+1'b1;
                        if(rv+1==count) begin
                            if(phase==3) begin busy<=0;done<=1;end
                            else begin phase<=phase+1'b1;sv<=0;rv<=0;sa<=0;ra<=0;end
                        end
                    end
                end
            end
        end
    end
endmodule
