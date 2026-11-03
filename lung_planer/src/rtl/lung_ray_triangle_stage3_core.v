`timescale 1ns/1ps
// Scalar Moller-Trumbore ray/triangle kernel.
//
// Inputs are signed Q16.16 millimetres (origin and vertices) and signed
// Q16.16 direction components.  Cross products are Q32.32 and dot products
// are Q48.48.  The division result is shifted back to Q16.16 before the
// barycentric and forward-ray tests. FAST_DIVIDE evaluates u, v and t with
// three synthesized signed fixed-point dividers in parallel; the reference
// mode retains three independent iterative dividers for comparison.
module lung_ray_triangle_stage3_core #(
    // Use the synthesized signed divider for the KV260 fast path.  Set to
    // zero to retain the restoring-divider reference implementation.
    parameter integer FAST_DIVIDE = 1,
    parameter integer SAFE_REJECT = 0
) (
    input wire clk,
    input wire rst_n,
    input wire s_valid,
    output wire s_ready,
    input wire [31:0] s_ray_id,
    input wire [31:0] s_triangle_id,
    input wire signed [31:0] s_origin_x,
    input wire signed [31:0] s_origin_y,
    input wire signed [31:0] s_origin_z,
    input wire signed [31:0] s_direction_x,
    input wire signed [31:0] s_direction_y,
    input wire signed [31:0] s_direction_z,
    input wire signed [31:0] s_v0_x,
    input wire signed [31:0] s_v0_y,
    input wire signed [31:0] s_v0_z,
    input wire signed [31:0] s_v1_x,
    input wire signed [31:0] s_v1_y,
    input wire signed [31:0] s_v1_z,
    input wire signed [31:0] s_v2_x,
    input wire signed [31:0] s_v2_y,
    input wire signed [31:0] s_v2_z,
    output reg m_valid,
    input wire m_ready,
    output reg [31:0] m_ray_id,
    output reg [31:0] m_triangle_id,
    output reg m_hit,
    output reg signed [31:0] m_t_q16,
    output reg signed [31:0] m_u_q16,
    output reg signed [31:0] m_v_q16,
    output reg [7:0] m_error
);
    // 1e-9 in Q48.48.  Keep this identical to ray_reference.py and the ABI
    // document; a larger value rejects valid shallow intersections.
    localparam signed [101:0] DET_EPS_Q48 = 102'sd281475;
    localparam signed [117:0] MAX_Q16_W = 118'sd2147483647;
    localparam signed [117:0] MIN_Q16_W = -118'sd2147483648;
    localparam signed [117:0] BARY_TOL_W = 118'sd1;
    localparam signed [117:0] ONE_PLUS_TOL_W = 118'sd65537;

    function automatic signed [66:0] mul32;
        input signed [32:0] a;
        input signed [32:0] b;
        reg signed [66:0] aa;
        reg signed [66:0] bb;
        begin
            aa = a;
            bb = b;
            mul32 = aa * bb;
        end
    endfunction

    function automatic signed [101:0] mul32x64;
        input signed [32:0] a;
        input signed [66:0] b;
        reg signed [101:0] aa;
        reg signed [101:0] bb;
        begin
            aa = {{69{a[32]}}, a};
            bb = {{35{b[66]}}, b};
            mul32x64 = aa * bb;
        end
    endfunction

    function automatic signed [101:0] add3_96;
        input signed [101:0] a;
        input signed [101:0] b;
        input signed [101:0] c;
        begin
            add3_96 = a + b + c;
        end
    endfunction

    function automatic signed [117:0] extend96;
        input signed [101:0] value;
        begin
            extend96 = {{16{value[101]}}, value};
        end
    endfunction

    // Geometry arithmetic is split across registered stages.  This keeps the
    // 32x32 cross products and 32x64 dot products out of one long input path.
    localparam [3:0] ST_IDLE = 4'd0;
    localparam [3:0] ST_PREP = 4'd1;
    localparam [3:0] ST_CROSS = 4'd2;
    localparam [3:0] ST_DOT = 4'd3;
    localparam [3:0] ST_DIV_START = 4'd4;
    localparam [3:0] ST_DIV_RUN = 4'd5;
    localparam [3:0] ST_DIV_FINISH = 4'd6;
    localparam [3:0] ST_FINAL = 4'd7;
    localparam [3:0] ST_CROSS_PRODUCT = 4'd8;
    localparam [3:0] ST_DOT_PRODUCT = 4'd9;
    localparam [3:0] ST_DOT_SUM = 4'd10;
    localparam [3:0] ST_DET_CHECK = 4'd11;

    reg [3:0] state;
    wire accept = s_valid && s_ready;
    assign s_ready = (state == ST_IDLE) && (!m_valid || m_ready);

    reg signed [31:0] in_origin_x, in_origin_y, in_origin_z;
    reg signed [31:0] in_direction_x, in_direction_y, in_direction_z;
    reg signed [31:0] in_v0_x, in_v0_y, in_v0_z;
    reg signed [31:0] in_v1_x, in_v1_y, in_v1_z;
    reg signed [31:0] in_v2_x, in_v2_y, in_v2_z;
    reg signed [32:0] e1x, e1y, e1z, e2x, e2y, e2z;
    reg signed [32:0] sx, sy, sz;
    reg signed [66:0] hx, hy, hz, qx, qy, qz;
    reg signed [101:0] det_value, u_numerator, v_numerator, t_numerator;
    reg signed [117:0] u_ratio, v_ratio, t_ratio;
    reg signed [31:0] calc_t, calc_u, calc_v;
    reg calc_hit;
    reg [7:0] calc_error;
    reg signed [101:0] det_low, det_high;
    reg signed [101:0] saved_det, saved_u_num, saved_v_num, saved_t_num;
    reg [31:0] saved_ray_id, saved_triangle_id;
    reg [7:0] div_count;
    reg [117:0] div_num_shift_u, div_num_shift_v, div_num_shift_t;
    reg [117:0] div_quotient_u, div_quotient_v, div_quotient_t;
    reg [102:0] div_remainder_u, div_remainder_v, div_remainder_t;
    reg [101:0] divisor_mag_u, divisor_mag_v, divisor_mag_t;
    reg div_negative_u, div_negative_v, div_negative_t;

    function automatic [117:0] abs_num_shift;
        input signed [101:0] value;
        reg signed [117:0] extended;
        begin
            extended = {{16{value[101]}}, value};
            if (value[101]) extended = -extended;
            abs_num_shift = extended <<< 16;
        end
    endfunction

    function automatic [101:0] abs_det_value;
        input signed [101:0] value;
        reg signed [101:0] magnitude;
        begin
            magnitude = value;
            if (value[101]) magnitude = -magnitude;
            abs_det_value = magnitude;
        end
    endfunction

    // Convert the Q48.48 numerator/determinant pair to a Q16.16 ratio.
    // The widened shift has the same truncation point as the restoring path.
    function automatic signed [117:0] fixed_div_q16;
        input signed [101:0] numerator;
        input signed [101:0] denominator;
        reg signed [117:0] n_ext;
        reg signed [117:0] d_ext;
        begin
            n_ext = {{16{numerator[101]}}, numerator};
            d_ext = {{16{denominator[101]}}, denominator};
            if (d_ext == 0)
                fixed_div_q16 = 0;
            else
                fixed_div_q16 = (n_ext <<< 16) / d_ext;
        end
    endfunction

    wire [102:0] remainder_shift_u = {div_remainder_u[101:0], div_num_shift_u[117]};
    wire [102:0] remainder_shift_v = {div_remainder_v[101:0], div_num_shift_v[117]};
    wire [102:0] remainder_shift_t = {div_remainder_t[101:0], div_num_shift_t[117]};
    wire quotient_bit_u = remainder_shift_u >= {1'b0, divisor_mag_u};
    wire quotient_bit_v = remainder_shift_v >= {1'b0, divisor_mag_v};
    wire quotient_bit_t = remainder_shift_t >= {1'b0, divisor_mag_t};
    wire det_bad = saved_det <= DET_EPS_Q48 && saved_det >= -DET_EPS_Q48;

    // Full-width registered arithmetic. Free-running datapath registers avoid
    // reset/enable control sets and let synthesis absorb them into DSP stages.
    // The FSM waits for each dependency before consuming it; stale data after
    // reset is never observable. No truncation point or arithmetic width changes.
    reg signed [66:0] cross_a [0:5], cross_b [0:5];
    reg signed [101:0] dot_x [0:3], dot_y [0:3], dot_z [0:3];
    reg signed [101:0] dot_xy [0:3];
    integer dot_lane;
    always @(posedge clk) begin
        cross_a[0] <= mul32(in_direction_y, e2z);
        cross_b[0] <= mul32(in_direction_z, e2y);
        cross_a[1] <= mul32(in_direction_z, e2x);
        cross_b[1] <= mul32(in_direction_x, e2z);
        cross_a[2] <= mul32(in_direction_x, e2y);
        cross_b[2] <= mul32(in_direction_y, e2x);
        cross_a[3] <= mul32(sy, e1z); cross_b[3] <= mul32(sz, e1y);
        cross_a[4] <= mul32(sz, e1x); cross_b[4] <= mul32(sx, e1z);
        cross_a[5] <= mul32(sx, e1y); cross_b[5] <= mul32(sy, e1x);
        dot_x[0] <= mul32x64(e1x, hx);
        dot_y[0] <= mul32x64(e1y, hy);
        dot_z[0] <= mul32x64(e1z, hz);
        dot_x[1] <= mul32x64(sx, hx);
        dot_y[1] <= mul32x64(sy, hy);
        dot_z[1] <= mul32x64(sz, hz);
        dot_x[2] <= mul32x64(in_direction_x, qx);
        dot_y[2] <= mul32x64(in_direction_y, qy);
        dot_z[2] <= mul32x64(in_direction_z, qz);
        dot_x[3] <= mul32x64(e2x, qx);
        dot_y[3] <= mul32x64(e2y, qy);
        dot_z[3] <= mul32x64(e2z, qz);
        for (dot_lane=0; dot_lane<4; dot_lane=dot_lane+1)
            dot_xy[dot_lane] <= dot_x[dot_lane] + dot_y[dot_lane];
    end

    // Final fixed-point range and barycentric checks.  The arithmetic inputs
    // are registered by the geometry pipeline above.
    always @* begin
        calc_t = 0;
        calc_u = 0;
        calc_v = 0;
        calc_hit = 1'b0;
        calc_error = det_bad ? 8'h01 : 8'h00;
        if (det_bad) begin
            calc_error = 8'h01; // determinant too small / parallel
        end else begin
            if (u_ratio > MAX_Q16_W) begin
                calc_u = 32'sh7fffffff;
                calc_error = calc_error | 8'h02;
            end else if (u_ratio < MIN_Q16_W) begin
                calc_u = 32'sh80000000;
                calc_error = calc_error | 8'h02;
            end else begin
                calc_u = u_ratio[31:0];
            end
            if (v_ratio > MAX_Q16_W) begin
                calc_v = 32'sh7fffffff;
                calc_error = calc_error | 8'h02;
            end else if (v_ratio < MIN_Q16_W) begin
                calc_v = 32'sh80000000;
                calc_error = calc_error | 8'h02;
            end else begin
                calc_v = v_ratio[31:0];
            end
            if (t_ratio > MAX_Q16_W) begin
                calc_t = 32'sh7fffffff;
                calc_error = calc_error | 8'h02;
            end else if (t_ratio < MIN_Q16_W) begin
                calc_t = 32'sh80000000;
                calc_error = calc_error | 8'h02;
            end else begin
                calc_t = t_ratio[31:0];
            end
            if (SAFE_REJECT != 0 &&
                (u_ratio < -BARY_TOL_W || u_ratio > ONE_PLUS_TOL_W ||
                 v_ratio < -BARY_TOL_W || v_ratio > ONE_PLUS_TOL_W ||
                 (u_ratio + v_ratio) > ONE_PLUS_TOL_W || t_ratio < 0))
                calc_error = 0;
            if (calc_error == 0 &&
                u_ratio >= -BARY_TOL_W && u_ratio <= ONE_PLUS_TOL_W &&
                v_ratio >= -BARY_TOL_W && v_ratio <= ONE_PLUS_TOL_W &&
                (u_ratio + v_ratio) <= ONE_PLUS_TOL_W && t_ratio >= 0)
                calc_hit = 1'b1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            in_origin_x <= 0; in_origin_y <= 0; in_origin_z <= 0;
            in_direction_x <= 0; in_direction_y <= 0; in_direction_z <= 0;
            in_v0_x <= 0; in_v0_y <= 0; in_v0_z <= 0;
            in_v1_x <= 0; in_v1_y <= 0; in_v1_z <= 0;
            in_v2_x <= 0; in_v2_y <= 0; in_v2_z <= 0;
            e1x <= 0; e1y <= 0; e1z <= 0;
            e2x <= 0; e2y <= 0; e2z <= 0;
            sx <= 0; sy <= 0; sz <= 0;
            hx <= 0; hy <= 0; hz <= 0;
            qx <= 0; qy <= 0; qz <= 0;
            saved_det <= 0;
            saved_u_num <= 0;
            saved_v_num <= 0;
            saved_t_num <= 0;
            saved_ray_id <= 0;
            saved_triangle_id <= 0;
            div_count <= 0;
            div_num_shift_u <= 0; div_num_shift_v <= 0; div_num_shift_t <= 0;
            div_quotient_u <= 0; div_quotient_v <= 0; div_quotient_t <= 0;
            div_remainder_u <= 0; div_remainder_v <= 0; div_remainder_t <= 0;
            divisor_mag_u <= 0; divisor_mag_v <= 0; divisor_mag_t <= 0;
            div_negative_u <= 0; div_negative_v <= 0; div_negative_t <= 0;
            u_ratio <= 0;
            v_ratio <= 0;
            t_ratio <= 0;
            m_valid <= 1'b0;
            m_ray_id <= 0;
            m_triangle_id <= 0;
            m_hit <= 1'b0;
            m_t_q16 <= 0;
            m_u_q16 <= 0;
            m_v_q16 <= 0;
            m_error <= 0;
        end else begin
            if (m_valid && m_ready)
                m_valid <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (accept) begin
                        in_origin_x <= s_origin_x;
                        in_origin_y <= s_origin_y;
                        in_origin_z <= s_origin_z;
                        in_direction_x <= s_direction_x;
                        in_direction_y <= s_direction_y;
                        in_direction_z <= s_direction_z;
                        in_v0_x <= s_v0_x; in_v0_y <= s_v0_y; in_v0_z <= s_v0_z;
                        in_v1_x <= s_v1_x; in_v1_y <= s_v1_y; in_v1_z <= s_v1_z;
                        in_v2_x <= s_v2_x; in_v2_y <= s_v2_y; in_v2_z <= s_v2_z;
                        saved_ray_id <= s_ray_id;
                        saved_triangle_id <= s_triangle_id;
                        u_ratio <= 0;
                        v_ratio <= 0;
                        t_ratio <= 0;
                        state <= ST_PREP;
                    end
                end
                ST_PREP: begin
                    e1x <= in_v1_x - in_v0_x;
                    e1y <= in_v1_y - in_v0_y;
                    e1z <= in_v1_z - in_v0_z;
                    e2x <= in_v2_x - in_v0_x;
                    e2y <= in_v2_y - in_v0_y;
                    e2z <= in_v2_z - in_v0_z;
                    sx <= in_origin_x - in_v0_x;
                    sy <= in_origin_y - in_v0_y;
                    sz <= in_origin_z - in_v0_z;
                    state <= ST_CROSS_PRODUCT;
                end
                ST_CROSS_PRODUCT: state <= ST_CROSS;
                ST_CROSS: begin
                    hx <= cross_a[0] - cross_b[0];
                    hy <= cross_a[1] - cross_b[1];
                    hz <= cross_a[2] - cross_b[2];
                    qx <= cross_a[3] - cross_b[3];
                    qy <= cross_a[4] - cross_b[4];
                    qz <= cross_a[5] - cross_b[5];
                    state <= ST_DOT_PRODUCT;
                end
                ST_DOT_PRODUCT: state <= ST_DOT_SUM;
                ST_DOT_SUM: state <= ST_DOT;
                ST_DOT: begin
                    saved_det <= dot_xy[0] + dot_z[0];
                    saved_u_num <= dot_xy[1] + dot_z[1];
                    saved_v_num <= dot_xy[2] + dot_z[2];
                    saved_t_num <= dot_xy[3] + dot_z[3];
                    state <= ST_DET_CHECK;
                end
                ST_DET_CHECK: begin
                    if (det_bad) state <= ST_FINAL;
                    else state <= ST_DIV_START;
                end
                ST_DIV_START: begin
                    if (FAST_DIVIDE != 0) begin
                        // The three independent ratios are synthesized in
                        // parallel. ST_FINAL remains a registered,
                        // backpressure-safe AXI-stream output stage.
                        u_ratio <= fixed_div_q16(saved_u_num, saved_det);
                        v_ratio <= fixed_div_q16(saved_v_num, saved_det);
                        t_ratio <= fixed_div_q16(saved_t_num, saved_det);
                        state <= ST_FINAL;
                    end else begin
                        divisor_mag_u <= abs_det_value(saved_det);
                        divisor_mag_v <= abs_det_value(saved_det);
                        divisor_mag_t <= abs_det_value(saved_det);
                        div_remainder_u <= 0;
                        div_remainder_v <= 0;
                        div_remainder_t <= 0;
                        div_quotient_u <= 0;
                        div_quotient_v <= 0;
                        div_quotient_t <= 0;
                        div_count <= 0;
                        div_num_shift_u <= abs_num_shift(saved_u_num);
                        div_num_shift_v <= abs_num_shift(saved_v_num);
                        div_num_shift_t <= abs_num_shift(saved_t_num);
                        div_negative_u <= saved_u_num[101] ^ saved_det[101];
                        div_negative_v <= saved_v_num[101] ^ saved_det[101];
                        div_negative_t <= saved_t_num[101] ^ saved_det[101];
                        state <= ST_DIV_RUN;
                    end
                end
                ST_DIV_RUN: begin
                    div_num_shift_u <= {div_num_shift_u[116:0], 1'b0};
                    div_num_shift_v <= {div_num_shift_v[116:0], 1'b0};
                    div_num_shift_t <= {div_num_shift_t[116:0], 1'b0};
                    if (quotient_bit_u)
                        div_remainder_u <= remainder_shift_u - {1'b0, divisor_mag_u};
                    else
                        div_remainder_u <= remainder_shift_u;
                    if (quotient_bit_v)
                        div_remainder_v <= remainder_shift_v - {1'b0, divisor_mag_v};
                    else
                        div_remainder_v <= remainder_shift_v;
                    if (quotient_bit_t)
                        div_remainder_t <= remainder_shift_t - {1'b0, divisor_mag_t};
                    else
                        div_remainder_t <= remainder_shift_t;
                    div_quotient_u[117-div_count] <= quotient_bit_u;
                    div_quotient_v[117-div_count] <= quotient_bit_v;
                    div_quotient_t[117-div_count] <= quotient_bit_t;
                    if (div_count == 8'd117) begin
                        state <= ST_DIV_FINISH;
                    end else begin
                        div_count <= div_count + 1'b1;
                    end
                end
                ST_DIV_FINISH: begin
                    if (div_negative_u) u_ratio <= -$signed(div_quotient_u);
                    else u_ratio <= $signed(div_quotient_u);
                    if (div_negative_v) v_ratio <= -$signed(div_quotient_v);
                    else v_ratio <= $signed(div_quotient_v);
                    if (div_negative_t) t_ratio <= -$signed(div_quotient_t);
                    else t_ratio <= $signed(div_quotient_t);
                    state <= ST_FINAL;
                end
                ST_FINAL: begin
                    m_valid <= 1'b1;
                    m_ray_id <= saved_ray_id;
                    m_triangle_id <= saved_triangle_id;
                    m_hit <= calc_hit;
                    m_t_q16 <= calc_t;
                    m_u_q16 <= calc_u;
                    m_v_q16 <= calc_v;
                    m_error <= calc_error;
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
