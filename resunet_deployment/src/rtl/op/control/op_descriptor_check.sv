`timescale 1ns/1ps
// 【文件类型：.sv】原 op_engine 描述检查的分拍实现，不添加算子或修改协议。
// 捕获→字段→面积→面积打拍→字节体积→末地址→范围/重叠→结果；64bit 边界保持。
module op_descriptor_check #(
    parameter bit ENABLE_WIDE_DEBUG = 1'b0
) (
    input  logic         clk_i,          // UI 时钟
    input  logic         rst_n_i,        // 异步低有效控制复位
    input  logic         req_valid_i,    // 保持到 done_o，撤回后可提交下一描述
    output logic         done_o,         // 检查完成
    output logic         ok_o,           // 原合法性判定
    input  logic [511:0] descriptor_i,   // 原64字节描述
    output logic [31:0]  result_bytes_o, // 量化/窗口结果字节数
    output logic [31:0]  mac_bytes_o,    // 调试MAC结果字节数
    output logic [31:0]  pixels_o,       // 锁存面积
    output logic [31:0]  inputs_o,       // 面积×组数
    output logic [31:0]  weight_words_o, // 64B权重字数
    output logic [31:0]  param_words_o,  // 64B参数字数
    output logic [31:0]  words_b_o       // Concat第二输入字数
);
    typedef enum logic [3:0] {IDLE, FIELDS, AREA, AREA_PIPE, BYTES,
        ENDS, RANGES, RESULT, DONE} state_t;
    state_t state_r, state_nxt;
    logic [511:0] descriptor_r;
    logic [15:0] cin_w, cout_w, cin_b_w, ig_r, ibg_r, og4_r, og8_r, og16_r;
    logic [31:0] area_r, pool_area_r, area_r2;
    logic [31:0] inputs_r, words_b_r;
    logic [63:0] plain_words_r, pool_words_r, b_words_r, pw_a_words_r, pw_b_words_r, pw_q4_words_r, pw_q8_words_r, pw_q16_words_r, weights_words_r, weight_b_words_r;
    logic [63:0] a_bytes_r, b_bytes_r, q_bytes_r, m_bytes_r, weights_bytes_r, weight2_bytes_r, params_bytes_r;
    logic [63:0] a_w, b_w, q_w, m_w, weights_w, params_w;
    logic [63:0] a_end_r, b_end_r, q_end_r, m_end_r, weights_end_r, weight2_end_r, params_end_r;
    logic fields_ok_w, fields_ok_r, ranges_ok_r, overlap_r;

    function automatic logic coeff_range_ok(
        input logic [63:0] base,
        input logic [63:0] bytes
    );
        logic [63:0] finish;
        begin
            finish = base + bytes;
            coeff_range_ok = bytes == 64'd0 ||
                ((base >= 64'h00100000) && (finish <= 64'h00159600)) ||
                ((base >= 64'h08000000) && (finish <= 64'h08200000));
        end
    endfunction

    assign cin_w = descriptor_r[431:416] == 16'd0 ? {8'd0,descriptor_r[23:16]} : descriptor_r[431:416];
    assign cout_w = descriptor_r[447:432] == 16'd0 ? {8'd0,descriptor_r[31:24]} : descriptor_r[447:432];
    assign cin_b_w = descriptor_r[463:448];
    assign a_w = {32'd0,descriptor_r[159:128]};
    assign b_w = {32'd0,descriptor_r[191:160]};
    assign q_w = {32'd0,descriptor_r[223:192]};
    assign m_w = {32'd0,descriptor_r[255:224]};
    assign weights_w = {32'd0,descriptor_r[287:256]};
    assign params_w = {32'd0,descriptor_r[319:288]};
    assign done_o = state_r == DONE;
    assign result_bytes_o = q_bytes_r[31:0];
    assign mac_bytes_o = m_bytes_r[31:0];
    assign pixels_o = area_r2;
    assign inputs_o = inputs_r;
    assign words_b_o = words_b_r;
    assign weight_words_o = (descriptor_r[7:0] == 8'd8 || descriptor_r[7:0] == 8'd9) ?
        weights_bytes_r[35:4] : (descriptor_r[7:0] == 8'd11 ?
        ({48'd0,descriptor_r[79:64]} * 64'd34) : (descriptor_r[7:0] == 8'd12 ?
        (weights_bytes_r[37:6] + weight2_bytes_r[37:6]) : weights_bytes_r[37:6]));
    assign param_words_o = {16'd0,og4_r};

    always_comb begin
        fields_ok_w = descriptor_r[7:0] >= 8'd1 && descriptor_r[7:0] <= 8'd13 &&
            descriptor_r[47:32] >= 16'd1 && descriptor_r[47:32] <= 16'd512 &&
            descriptor_r[63:48] >= 16'd1 && descriptor_r[63:48] <= 16'd512 &&
            descriptor_r[79:64] >= 16'd1 && descriptor_r[79:64] <= 16'd32 &&
            a_w[3:0] == 4'd0 && q_w[4:0] == 5'd0 && descriptor_r[15:13] == 3'd0;
        case (descriptor_r[7:0])
            8'd1: begin
                fields_ok_w = fields_ok_w && cin_w >= 16'd1 && cin_w <= 16'd768 &&
                    cout_w >= 16'd1 && cout_w <= 16'd512 && descriptor_r[87:80] <= 8'd62 &&
                    !(descriptor_r[10] && descriptor_r[11]) && weights_w[5:0] == 6'd0 && params_w[5:0] == 6'd0 &&
                    (!descriptor_r[12] || (descriptor_r[10] && cout_w[3:0] == 4'd0));
                if (descriptor_r[8])
                    fields_ok_w = fields_ok_w && cin_w == 16'd3 && (cout_w == 16'd16 || cout_w == 16'd64) &&
                        descriptor_r[47:32] == 16'd512 && descriptor_r[63:48] == 16'd512 && a_w[17:0] == 18'd0 &&
                        descriptor_r[351:320] >= 32'd1 && descriptor_r[351:320] <= 32'd1024 &&
                        descriptor_r[383:352] < descriptor_r[351:320];
            end
            8'd2: fields_ok_w = fields_ok_w && descriptor_r[47:32] >= 16'd2 && descriptor_r[63:48] >= 16'd2;
            8'd5: fields_ok_w = fields_ok_w && descriptor_r[127:112] >= 16'd1 &&
                descriptor_r[127:112] <= 16'd32 && b_w[3:0] == 4'd0;
            8'd6: fields_ok_w = fields_ok_w && a_w[5:0] == 6'd0 && b_w[5:0] == 6'd0 &&
                params_w[5:0] == 6'd0 && descriptor_r[87:80] <= 8'd63 &&
                $signed(descriptor_r[95:88]) <= $signed(descriptor_r[103:96]);
            8'd7: fields_ok_w = fields_ok_w && descriptor_r[79:64] == 16'd1;
            8'd3, 8'd4: fields_ok_w = fields_ok_w && ENABLE_WIDE_DEBUG;
            8'd8, 8'd9: fields_ok_w = fields_ok_w && ENABLE_WIDE_DEBUG && weights_w[5:0] == 6'd0;
            // 融合 DW3+DW5+mix：base_a=输入，q=INT8输出，weights=DW3，mac=DW5，params=mix。
            8'd11: fields_ok_w = fields_ok_w && weights_w[5:0] == 6'd0 &&
                m_w[5:0] == 6'd0 && params_w[5:0] == 6'd0 &&
                descriptor_r[87:80] <= 8'd63;
            // 融合两个raw PW与residual Add；byte56-57保存skip Cin。
            8'd12: fields_ok_w = fields_ok_w && cin_w >= 16'd1 && cin_w <= 16'd768 &&
                cout_w >= 16'd16 && cout_w <= 16'd512 && cout_w[3:0] == 4'd0 &&
                cin_b_w >= 16'd1 && cin_b_w <= 16'd768 &&
                descriptor_r[79:64] == ((cout_w + 16'd15) >> 4) &&
                weights_w[5:0] == 6'd0 && m_w[5:0] == 6'd0 && params_w[5:0] == 6'd0 &&
                descriptor_r[87:80] <= 8'd63;
            // 最近邻2倍：描述尺寸为输入，输出宽高最大512；禁止截断257..512。
            8'd13: fields_ok_w = fields_ok_w && descriptor_r[47:32] <= 16'd256 &&
                descriptor_r[63:48] <= 16'd256 && descriptor_r[127:112] >= 16'd1 &&
                descriptor_r[127:112] <= 16'd32 && b_w[3:0] == 4'd0;
            8'd10: fields_ok_w = fields_ok_w && descriptor_r[47:32] <= 16'd256 &&
                descriptor_r[63:48] <= 16'd256;
            default: ;
        endcase
        if (descriptor_r[7:0] != 8'd1) fields_ok_w = fields_ok_w && descriptor_r[15:8] == 8'd0;
        state_nxt = state_r;
        case (state_r)
            IDLE: if (req_valid_i) state_nxt = FIELDS;
            FIELDS: state_nxt = AREA;
            AREA: state_nxt = AREA_PIPE;
            AREA_PIPE: state_nxt = BYTES;
            BYTES: state_nxt = ENDS;
            ENDS: state_nxt = RANGES;
            RANGES: state_nxt = RESULT;
            RESULT: state_nxt = DONE;
            DONE: if (!req_valid_i) state_nxt = IDLE;
            default: state_nxt = IDLE;
        endcase
    end
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin state_r <= IDLE; ok_o <= 1'b0; end
        else begin
            state_r <= state_nxt;
            if (state_r == RESULT) ok_o <= fields_ok_r && ranges_ok_r && !overlap_r;
        end
    end
    // 数据流水无异步复位；有效性由控制状态保证，允许DSP吸收流水寄存器。
    always_ff @(posedge clk_i) begin
        if (state_r == IDLE && req_valid_i) descriptor_r <= descriptor_i;
        if (state_r == FIELDS) begin
            fields_ok_r <= fields_ok_w;
            ig_r <= 16'(({1'b0,cin_w} + 17'd15)>>4);
            ibg_r <= 16'(({1'b0,cin_b_w} + 17'd15)>>4);
            og4_r <= 16'(({1'b0,cout_w} + 17'd3)>>2);
            og8_r <= 16'(({1'b0,cout_w} + 17'd7)>>3);
            og16_r <= 16'(({1'b0,cout_w} + 17'd15)>>4);
        end
        if (state_r == AREA) begin
            area_r <= {16'd0,descriptor_r[47:32]} * {16'd0,descriptor_r[63:48]};
            pool_area_r <= {16'd0,(descriptor_r[47:32]>>1)} * {16'd0,(descriptor_r[63:48]>>1)};
        end
        if (state_r == AREA_PIPE) begin
            area_r2 <= area_r;
            plain_words_r <= {32'd0,area_r} * {48'd0,descriptor_r[79:64]};
            pool_words_r <= {32'd0,pool_area_r} * {48'd0,descriptor_r[79:64]};
            b_words_r <= {32'd0,area_r} * {48'd0,descriptor_r[127:112]};
            pw_a_words_r <= {32'd0,area_r} * {48'd0,ig_r};
            pw_b_words_r <= {32'd0,area_r} * {48'd0,ibg_r};
            pw_q4_words_r <= {32'd0,area_r} * {48'd0,og4_r};
            pw_q8_words_r <= {32'd0,area_r} * {48'd0,og8_r};
            pw_q16_words_r <= {32'd0,area_r} * {48'd0,og16_r};
            weights_words_r <= {48'd0,og4_r} * {48'd0,ig_r};
            weight_b_words_r <= {48'd0,og4_r} * {48'd0,ibg_r};
        end
        if (state_r == BYTES) begin
            inputs_r <= plain_words_r[31:0];
            words_b_r <= b_words_r[31:0];
            a_bytes_r <= plain_words_r << 4;
            b_bytes_r <= 64'd0; m_bytes_r <= 64'd0;
            q_bytes_r <= plain_words_r << 4;
            weights_bytes_r <= 64'd0; weight2_bytes_r <= 64'd0; params_bytes_r <= 64'd0;
            case (descriptor_r[7:0])
                8'd1: begin
                    a_bytes_r <= pw_a_words_r << 4;
                    q_bytes_r <= pw_q16_words_r << 4;
                    if (descriptor_r[10]) q_bytes_r <= pw_q4_words_r << 4;
                    else if (descriptor_r[11])
                        q_bytes_r <= descriptor_r[9] ? (pw_q4_words_r << 3) : (pw_q8_words_r << 4);
                    if (descriptor_r[9] && !descriptor_r[10]) m_bytes_r <= pw_q4_words_r << 4;
                    weights_bytes_r <= weights_words_r << 6;
                    params_bytes_r <= {48'd0,og4_r} << 6;
                    if (descriptor_r[8]) a_bytes_r <= {32'd0,descriptor_r[351:320]} << 18;
                end
                8'd2: q_bytes_r <= pool_words_r << 4;
                8'd13: begin
                    // 描述尺寸为小图；skip和最终Concat均为2W×2H。
                    words_b_r <= b_words_r[29:0] << 2;
                    b_bytes_r <= b_words_r << 6;
                    q_bytes_r <= (plain_words_r + b_words_r) << 6;
                end
                8'd10: q_bytes_r <= plain_words_r << 6; // 每个P16输入复制为4个P16输出
                8'd3: q_bytes_r <= (plain_words_r << 7) + (plain_words_r << 4);
                8'd4: q_bytes_r <= (plain_words_r << 8) + (plain_words_r << 7) + (plain_words_r << 4);
                8'd5: begin
                    b_bytes_r <= b_words_r << 4;
                    q_bytes_r <= (plain_words_r + b_words_r) << 4;
                end
                8'd6: begin
                    a_bytes_r <= plain_words_r << 6;
                    b_bytes_r <= plain_words_r << 6;
                    params_bytes_r <= {48'd0,descriptor_r[79:64]} << 8;
                end
                8'd8, 8'd9: begin
                    q_bytes_r <= plain_words_r << 6;
                    weights_bytes_r <= descriptor_r[7:0] == 8'd8 ?
                        ({48'd0,descriptor_r[79:64]} * 64'd144) :
                        ({48'd0,descriptor_r[79:64]} * 64'd400);
                end
                8'd11: begin
                    // 两个 DW 权重区分别由 weights/base_m 指向；Add 参数按组各256B。
                    q_bytes_r <= plain_words_r << 4;
                    weights_bytes_r <= {48'd0,descriptor_r[79:64]} * 64'd144;
                    weight2_bytes_r <= {48'd0,descriptor_r[79:64]} * 64'd400;
                    params_bytes_r <= {48'd0,descriptor_r[79:64]} << 8;
                end
                8'd12: begin
                    // 两支P16输入各读一次；双PW权重均按64B PE4/SIMD16字装载。
                    a_bytes_r <= pw_a_words_r << 4;
                    b_bytes_r <= pw_b_words_r << 4;
                    q_bytes_r <= plain_words_r << 4;
                    weights_bytes_r <= weights_words_r << 6;
                    weight2_bytes_r <= weight_b_words_r << 6;
                    params_bytes_r <= {48'd0,descriptor_r[79:64]} << 8;
                end
                default: ;
            endcase
        end
        if (state_r == ENDS) begin
            a_end_r <= a_w + a_bytes_r; b_end_r <= b_w + b_bytes_r;
            q_end_r <= q_w + q_bytes_r; m_end_r <= m_w + m_bytes_r;
            weights_end_r <= weights_w + weights_bytes_r;
            weight2_end_r <= m_w + weight2_bytes_r;
            params_end_r <= params_w + params_bytes_r;
        end
        if (state_r == RANGES) begin
            ranges_ok_r <= a_bytes_r != 64'd0 && a_end_r <= 64'h20000000 &&
                q_bytes_r != 64'd0 && q_end_r <= 64'h20000000 &&
                (b_bytes_r == 64'd0 || b_end_r <= 64'h20000000) &&
                    coeff_range_ok(weights_w, weights_bytes_r) &&
                    coeff_range_ok(params_w, params_bytes_r) &&
                    ((descriptor_r[7:0] != 8'd11 && descriptor_r[7:0] != 8'd12) ||
                        coeff_range_ok(m_w, weight2_bytes_r)) &&
                (weight2_bytes_r == 64'd0 || !(weights_w < weight2_end_r && m_w < weights_end_r)) &&
                (m_bytes_r == 64'd0 || (m_w[4:0] == 5'd0 && m_end_r <= 64'h20000000));
            overlap_r <= (q_w < a_end_r && a_w < q_end_r) ||
                (b_bytes_r != 64'd0 && q_w < b_end_r && b_w < q_end_r) ||
                (weights_bytes_r != 64'd0 && q_w < weights_end_r && weights_w < q_end_r) ||
                (params_bytes_r != 64'd0 && q_w < params_end_r && params_w < q_end_r) ||
                (weight2_bytes_r != 64'd0 && q_w < weight2_end_r && m_w < q_end_r) ||
                (m_bytes_r != 64'd0 && ((m_w < a_end_r && a_w < m_end_r) ||
                    (b_bytes_r != 64'd0 && m_w < b_end_r && b_w < m_end_r) ||
                    (m_w < q_end_r && q_w < m_end_r) ||
                    (weights_bytes_r != 64'd0 && m_w < weights_end_r && weights_w < m_end_r) ||
                    (params_bytes_r != 64'd0 && m_w < params_end_r && params_w < m_end_r)));
        end
    end
endmodule
