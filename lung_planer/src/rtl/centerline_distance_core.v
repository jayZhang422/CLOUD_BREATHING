`timescale 1ns/1ps
// Exact nearest in-array background query at selected voxel coordinates.
// Integer positive axis weights define squared physical distance up to a
// common scale. Cube shells stop only at a proved lower bound. No deletion,
// resampling or approximate/truncated radius is performed.
module centerline_distance_core (
    input wire clk, rst_n, start, abort_job,
    input wire [31:0] nx, ny, nz, query_count, weight_x, weight_y, weight_z,
    input wire [15:0] max_radius,
    input wire [31:0] timeout_cycles,
    input wire [63:0] mask_base,
    input wire [127:0] s_data,
    input wire [15:0] s_keep,
    input wire s_last, s_valid,
    output wire s_ready,
    output wire [127:0] m_data,
    output wire [15:0] m_keep,
    output wire m_last, m_valid,
    input wire m_ready,
    output wire mem_valid,
    output wire [63:0] mem_address,
    input wire mem_ready,
    input wire [127:0] mem_data,
    input wire mem_data_valid, mem_error,
    output wire mem_data_ready,
    output reg busy, done,
    output reg [31:0] errors, processed, cycles, reads, candidates
);
    localparam IDLE=0, QUERY=1, SCAN=2, WEIGH=3, SUM=4, CHECK=5,
               REQUEST=6, RESPONSE=7, CONSUME=8, ADVANCE=9, BOUND=10, OUTPUT=11;
    localparam ERR_CONFIG=1, ERR_COORD=2, ERR_STREAM=4, ERR_BUS=8,
               ERR_RADIUS=16, ERR_TIMEOUT=32, ERR_ABORT=64;
    reg [3:0] state;
    reg [15:0] qx, qy, qz, radius;
    reg [31:0] tag;
    reg signed [15:0] dx, dy, dz, best_dx, best_dy, best_dz;
    reg [31:0] sx, sy, sz, linear_index, row_index;
    reg [63:0] wx, wy, wz, distance_squared, best_squared;
    reg [63:0] request_address, cache_address;
    reg [127:0] cache_data;
    reg cache_valid, cancel_pending;
    reg [31:0] cancel_error;
    wire signed [31:0] cx = $signed({1'b0,qx}) + $signed(dx);
    wire signed [31:0] cy = $signed({1'b0,qy}) + $signed(dy);
    wire signed [31:0] cz = $signed({1'b0,qz}) + $signed(dz);
    wire in_bounds = cx>=0 && cy>=0 && cz>=0 && cx<$signed(nx) && cy<$signed(ny) && cz<$signed(nz);
    wire on_shell = dx==$signed(radius) || dx==-$signed(radius) ||
                    dy==$signed(radius) || dy==-$signed(radius) ||
                    dz==$signed(radius) || dz==-$signed(radius);
    wire [31:0] min_xy = weight_x < weight_y ? weight_x : weight_y;
    wire [31:0] min_weight = min_xy < weight_z ? min_xy : weight_z;
    wire [31:0] next_radius = {16'b0,radius} + 32'd1;
    wire [31:0] bound_square = next_radius * next_radius;
    wire [63:0] lower_bound = {32'b0,bound_square} * min_weight;
    wire fully_scanned = qx<=radius && qy<=radius && qz<=radius &&
                         ({16'b0,qx}+radius >= nx-1) &&
                         ({16'b0,qy}+radius >= ny-1) &&
                         ({16'b0,qz}+radius >= nz-1);
    wire [63:0] byte_address = mask_base + {32'b0,linear_index};
    wire [7:0] voxel = cache_data[linear_index[3:0]*8 +: 8];
    assign s_ready = state==QUERY && !cancel_pending;
    assign m_valid = state==OUTPUT;
    assign m_data = {32'b0,tag,16'b0,best_dz,best_dy,best_dx};
    assign m_keep = 16'hffff;
    assign m_last = processed+1==query_count;
    assign mem_valid = state==REQUEST;
    assign mem_address = request_address;
    assign mem_data_ready = state==RESPONSE;

    always @(posedge clk) begin
        if (!rst_n) begin
            state<=IDLE; busy<=0; done<=0; errors<=0; processed<=0;
            cycles<=0; reads<=0; candidates<=0; cancel_pending<=0; cancel_error<=0;
            qx<=0; qy<=0; qz<=0; radius<=0; tag<=0;
            dx<=0; dy<=0; dz<=0; best_dx<=0; best_dy<=0; best_dz<=0;
            sx<=0; sy<=0; sz<=0; wx<=0; wy<=0; wz<=0;
            distance_squared<=0; best_squared<=64'hffffffffffffffff;
            linear_index<=0; row_index<=0; request_address<=0;
            cache_valid<=0; cache_address<=0; cache_data<=0;
        end else begin
            done<=0;
            if (busy) begin
                cycles<=cycles+1;
                if (abort_job || (timeout_cycles!=0 && cycles>=timeout_cycles)) begin
                    cancel_pending<=1;
                    cancel_error<=abort_job ? ERR_ABORT : ERR_TIMEOUT;
                end
            end
            // Never withdraw an issued AXI request or abandon an outstanding
            // read. Host recovery must reset the fabric before freeing DDR if
            // a failed interconnect never supplies a response.
            if (cancel_pending && state!=REQUEST && state!=RESPONSE && !(state==OUTPUT && !m_ready)) begin
                errors<=errors|cancel_error; busy<=0; done<=1; state<=IDLE;
                cancel_pending<=0;
            end else case (state)
                IDLE: if (start) begin
                    errors<=0; processed<=0; cycles<=0; reads<=0; candidates<=0;
                    cache_valid<=0; cancel_pending<=0;
                    if (nx==0 || ny==0 || nz==0 || nx>1024 || ny>1024 || nz>1024 ||
                        query_count==0 || weight_x==0 || weight_y==0 || weight_z==0 ||
                        max_radius==0 || max_radius>1023 || mask_base[3:0]!=0) begin
                        errors<=ERR_CONFIG; done<=1; busy<=0;
                    end else begin busy<=1; state<=QUERY; end
                end
                QUERY: if (s_valid && s_ready) begin
                    if (s_keep!=16'hffff || s_last!=(processed+1==query_count) ||
                        s_data[63:48]!=0 || s_data[127:96]!=0) begin
                        errors<=ERR_STREAM; busy<=0; done<=1; state<=IDLE;
                    end else if (s_data[15:0]>=nx || s_data[31:16]>=ny || s_data[47:32]>=nz) begin
                        errors<=ERR_COORD; busy<=0; done<=1; state<=IDLE;
                    end else begin
                        qx<=s_data[15:0]; qy<=s_data[31:16]; qz<=s_data[47:32]; tag<=s_data[95:64];
                        radius<=0; dx<=0; dy<=0; dz<=0;
                        best_squared<=64'hffffffffffffffff; best_dx<=0; best_dy<=0; best_dz<=0;
                        state<=SCAN;
                    end
                end
                SCAN: begin
                    if (!on_shell || !in_bounds) state<=ADVANCE;
                    else begin
                        sx<=$signed(dx)*$signed(dx); sy<=$signed(dy)*$signed(dy); sz<=$signed(dz)*$signed(dz);
                        row_index<=cx*ny+cy;
                        state<=WEIGH;
                    end
                end
                WEIGH: begin
                    wx<={32'b0,sx}*weight_x; wy<={32'b0,sy}*weight_y; wz<={32'b0,sz}*weight_z;
                    linear_index<=row_index*nz+cz;
                    state<=SUM;
                end
                SUM: begin distance_squared<=wx+wy+wz; state<=CHECK; end
                CHECK: begin
                    candidates<=candidates+1;
                    if (distance_squared>=best_squared) state<=ADVANCE;
                    else if (cache_valid && cache_address=={byte_address[63:4],4'b0}) state<=CONSUME;
                    else begin request_address<={byte_address[63:4],4'b0}; state<=REQUEST; end
                end
                REQUEST: if (mem_ready) begin reads<=reads+1; state<=RESPONSE; end
                RESPONSE: if (mem_data_valid) begin
                    if (mem_error) begin errors<=ERR_BUS; busy<=0; done<=1; state<=IDLE; end
                    else begin
                        cache_address<=request_address; cache_data<=mem_data; cache_valid<=1;
                        state<=CONSUME;
                    end
                end
                CONSUME: begin
                    if (voxel==0) begin
                        best_squared<=distance_squared; best_dx<=dx; best_dy<=dy; best_dz<=dz;
                    end
                    state<=ADVANCE;
                end
                ADVANCE: begin
                    if (dz<$signed(radius)) dz<=dz+1;
                    else begin
                        dz<=-$signed(radius);
                        if (dy<$signed(radius)) dy<=dy+1;
                        else begin dy<=-$signed(radius); dx<=dx+1; end
                    end
                    if (dx==$signed(radius) && dy==$signed(radius) && dz==$signed(radius)) state<=BOUND;
                    else state<=SCAN;
                end
                BOUND: begin
                    if (best_squared!=64'hffffffffffffffff && (best_squared<=lower_bound || fully_scanned)) state<=OUTPUT;
                    else if (radius>=max_radius) begin errors<=ERR_RADIUS; busy<=0; done<=1; state<=IDLE; end
                    else begin
                        radius<=radius+1; dx<=-$signed(radius)-16'sd1;
                        dy<=-$signed(radius)-16'sd1; dz<=-$signed(radius)-16'sd1; state<=SCAN;
                    end
                end
                OUTPUT: if (m_valid && m_ready) begin
                    processed<=processed+1;
                    if (processed+1==query_count) begin busy<=0; done<=1; state<=IDLE; end
                    else state<=QUERY;
                end
                default: begin errors<=ERR_CONFIG; busy<=0; done<=1; state<=IDLE; end
            endcase
        end
    end
endmodule
