`timescale 1ns/1ps
// 【文件类型：.sv】独立只读参数源：64-bit Xilinx ROM → 256-bit 握手响应。
// 每个 32B 请求顺序读取四个 64-bit 字；适配 IP 的同步读和输出寄存器。
module op_coeff_rom_wstream_before (
    input  logic         clk_i,           // 计算域时钟
    input  logic         rst_n_i,         // 异步低有效控制复位
    input  logic         req_valid_i,     // 读取请求有效
    output logic         req_ready_o,     // 请求接收许可
    input  logic [30:0]  req_addr_i,      // 参数空间字节地址，32B 对齐
    output logic         rsp_valid_o,     // 返回有效，反压期间保持
    input  logic         rsp_ready_i,     // 返回接收许可
    output logic [255:0] rsp_data_o,      // 首字节在低位
    output logic         rsp_error_o     // 地址越界或未对齐
);
    localparam logic [30:0] COEFF_BASE  = 31'h00100000;
    // 片上 ROM 只保留 airway/lobe/vessel；tumor 参数由 DDR 参数区提供。
    localparam logic [30:0] COEFF_LIMIT = 31'h00159600; // 45760 个 64-bit 字
    typedef enum logic [2:0] {IDLE, ISSUE, WAIT_ROM, CAPTURE, PACK, RESPONSE} state_t;
    state_t state_r, state_nxt;
    logic [15:0] word_addr_r;
    logic [1:0] part_r;
    logic error_r;
    logic address_ok_w;
    (* max_fanout = 16 *) logic rom_enable_r;
    logic [30:0] offset_w;
    logic [63:0] rom_data_w, rom_data_r;
    logic [255:0] data_r;

    assign offset_w = req_addr_i - COEFF_BASE;
    assign address_ok_w = req_addr_i >= COEFF_BASE &&
        req_addr_i <= COEFF_LIMIT - 31'd32 && req_addr_i[4:0] == 5'd0;
    assign req_ready_o = state_r == IDLE;
    assign rsp_valid_o = state_r == RESPONSE;
    assign rsp_data_o = data_r;
    assign rsp_error_o = error_r;
    // 输出寄存器同样受 ena 控制，ISSUE 后再使能一拍以推进第二级。
    quantized_params_rom u_rom (
        .clka(clk_i), .ena(rom_enable_r), .addra(word_addr_r), .douta(rom_data_w)
    );

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin state_r <= IDLE; rom_enable_r <= 1'b0; end
        else begin
            state_r <= state_nxt;
            rom_enable_r <= state_nxt == ISSUE || state_nxt == WAIT_ROM;
        end
    end
    always_comb begin
        state_nxt = state_r;
        case (state_r)
            IDLE: if (req_valid_i) state_nxt = address_ok_w ? ISSUE : RESPONSE;
            ISSUE: state_nxt = WAIT_ROM;
            WAIT_ROM: state_nxt = CAPTURE;
            CAPTURE: state_nxt = PACK;
            PACK: state_nxt = part_r == 2'd3 ? RESPONSE : ISSUE;
            RESPONSE: if (rsp_ready_i) state_nxt = IDLE;
            default: state_nxt = IDLE;
        endcase
    end
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            word_addr_r <= 16'd0;
            part_r <= 2'd0;
            error_r <= 1'b0;
        end else begin
            if (state_r == IDLE && req_valid_i) begin
                word_addr_r <= offset_w[18:3];
                part_r <= 2'd0;
                error_r <= !address_ok_w;
            end
            if (state_r == PACK) begin
                word_addr_r <= word_addr_r + 16'd1;
                part_r <= part_r + 2'd1;
            end
        end
    end
    // 数据寄存器不复位；有效控制保证复位后的旧数据不会被交付。
    always_ff @(posedge clk_i) begin
        if (state_r == IDLE && req_valid_i) data_r <= 256'd0;
        // IP外先捕获64位输出，下一拍分发到四个响应槽位，降低ROM输出布线扇出。
        if (state_r == CAPTURE) rom_data_r <= rom_data_w;
        if (state_r == PACK) data_r[part_r*64 +: 64] <= rom_data_r;
    end
endmodule
