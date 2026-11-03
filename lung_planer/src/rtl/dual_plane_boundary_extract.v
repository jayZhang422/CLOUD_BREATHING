`timescale 1ns/1ps

// Enumerate clipped polygon edges that lie on each of the four cap planes.
// One physical edge can be emitted twice when it lies on a tetrahedron edge.
module dual_plane_boundary_extract (
    input wire clk, input wire rst_n, input wire start,
    input wire [3:0] polygon_count,
    input wire [447:0] in_x, in_y, in_z,
    input wire [27:0] in_mask,
    input wire segment_ready,
    output reg busy, output reg done, output reg segment_valid,
    output reg [1:0] segment_plane,
    output reg [63:0] ax, ay, az, bx, by, bz,
    output reg [31:0] segment_count,
    output reg [7:0] diagnostics
);
    localparam [1:0] S_IDLE=0, S_SCAN=1, S_SEND=2, S_FINISH=3;
    localparam [7:0] ERR_OVERFLOW=8'h04;
    reg [1:0] state;
    reg [2:0] edge_index;
    reg [1:0] plane_index;
    wire [2:0] next_index = (edge_index + 1 >= polygon_count) ? 3'd0 : edge_index + 1'b1;
    wire on_plane = in_mask[edge_index*4 + plane_index] &&
                    in_mask[next_index*4 + plane_index];
    wire distinct = in_x[edge_index*64 +: 64] != in_x[next_index*64 +: 64] ||
                    in_y[edge_index*64 +: 64] != in_y[next_index*64 +: 64] ||
                    in_z[edge_index*64 +: 64] != in_z[next_index*64 +: 64];

    always @(posedge clk) begin
        if (!rst_n) begin
            state<=S_IDLE; busy<=0; done<=0; segment_valid<=0;
            segment_plane<=0; edge_index<=0; plane_index<=0;
            ax<=0; ay<=0; az<=0; bx<=0; by<=0; bz<=0;
            segment_count<=0; diagnostics<=0;
        end else begin
            done<=0;
            case (state)
                S_IDLE: if (start) begin
                    busy<=1; segment_valid<=0; segment_count<=0; diagnostics<=0;
                    edge_index<=0; plane_index<=0;
                    if (polygon_count > 7) begin diagnostics<=ERR_OVERFLOW; state<=S_FINISH; end
                    else if (polygon_count < 3) state<=S_FINISH;
                    else state<=S_SCAN;
                end
                S_SCAN: begin
                    if (on_plane && distinct) begin
                        segment_plane<=plane_index;
                        ax<=in_x[edge_index*64 +: 64];
                        ay<=in_y[edge_index*64 +: 64];
                        az<=in_z[edge_index*64 +: 64];
                        bx<=in_x[next_index*64 +: 64];
                        by<=in_y[next_index*64 +: 64];
                        bz<=in_z[next_index*64 +: 64];
                        segment_valid<=1;
                        state<=S_SEND;
                    end else if (plane_index == 3) begin
                        plane_index<=0;
                        if (edge_index + 1 >= polygon_count) state<=S_FINISH;
                        else edge_index<=edge_index+1'b1;
                    end else plane_index<=plane_index+1'b1;
                end
                S_SEND: if (segment_ready) begin
                    segment_valid<=0;
                    segment_count<=segment_count+1'b1;
                    if (plane_index == 3) begin
                        plane_index<=0;
                        if (edge_index + 1 >= polygon_count) state<=S_FINISH;
                        else begin edge_index<=edge_index+1'b1; state<=S_SCAN; end
                    end else begin plane_index<=plane_index+1'b1; state<=S_SCAN; end
                end
                S_FINISH: begin busy<=0; done<=1; state<=S_IDLE; end
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
