`timescale 1ns/1ps
// 【文件类型：.sv】单在途 32B DDR 事务；掩码写先读后合并，B 响应后才返回。
// ponytail: 正确性优先，窄写采用 RMW；需要吞吐时改为小块合并写缓存。
module op_ddr_port_baseline (
    input logic clk_i, // 时钟域输入
    input logic rst_n_i, // 异步低有效控制复位
    input logic req_valid_i, // 握手有效，阻塞期间保持载荷
    output logic req_ready_o, // 握手接收许可
    input logic req_write_i, // 任务配置或协议控制字段
    output logic rsp_valid_o, // 握手有效，阻塞期间保持载荷
    input logic rsp_ready_i, // 握手接收许可
    output logic rsp_error_o, // 本次操作错误状态
    output logic active_o, // 任务配置或协议控制字段
    output logic wr_start_o, // 任务配置或协议控制字段
    input logic wr_ready_i, // 握手接收许可
    input logic wr_done_i, // 完成通知，须遵守排空条件
    input logic wr_error_i, // 本次操作错误状态
    input logic wr_fifo_re_i, // 任务配置或协议控制字段
    output logic wr_fifo_empty_o, // 任务配置或协议控制字段
    output logic rd_start_o, // 任务配置或协议控制字段
    input logic rd_ready_i, // 握手接收许可
    input logic rd_done_i, // 完成通知，须遵守排空条件
    input logic rd_error_i, // 本次操作错误状态
    input logic rd_fifo_we_i, // 任务配置或协议控制字段
    output logic rd_fifo_full_o, // 任务配置或协议控制字段
    input logic [30:0] req_addr_i, // 地址字段，单位按模块接口约定
    input logic [255:0] req_data_i, // 数据载荷，低位承载首字节或首 lane
    input logic [31:0] req_mask_i, // 任务配置或协议控制字段
    output logic [255:0] rsp_data_o, // 数据载荷，低位承载首字节或首 lane
    output logic [30:0] wr_addr_o, // 地址字段，单位按模块接口约定
    output logic [31:0] wr_len_o, // 有效字节数或接口长度
    output logic [255:0] wr_fifo_data_o, // 数据载荷，低位承载首字节或首 lane
    output logic [30:0] rd_addr_o, // 地址字段，单位按模块接口约定
    output logic [31:0] rd_len_o, // 有效字节数或接口长度
    input logic [255:0] rd_fifo_data_i // 数据载荷，低位承载首字节或首 lane
);
    typedef enum logic [3:0] {IDLE, RD_START, RD_DATA, RD_WAIT,
        MERGE, WR_START, WR_DATA, WR_WAIT, RESPONSE} state_t;
    state_t state_r, state_nxt;
    logic write_r, error_r, read_done_r;
    logic [30:0] addr_r;
    logic [31:0] mask_r;
    logic [255:0] data_r, old_r, merged_r;
    always_ff @(posedge clk_i or negedge rst_n_i)
        if (!rst_n_i) state_r <= IDLE; else state_r <= state_nxt;
    always_comb begin
        state_nxt = state_r;
        case (state_r)
            IDLE: if (req_valid_i && wr_ready_i && rd_ready_i)
                state_nxt = req_write_i && (&req_mask_i) ? WR_START : RD_START;
            RD_START: if (rd_ready_i) state_nxt = RD_DATA;
            RD_DATA: if (rd_fifo_we_i) state_nxt = (rd_done_i || read_done_r) ? MERGE : RD_WAIT;
            RD_WAIT: if (rd_done_i || read_done_r) state_nxt = MERGE;
            MERGE: state_nxt = write_r && !error_r ? WR_START : RESPONSE;
            WR_START: if (wr_ready_i) state_nxt = WR_DATA;
            WR_DATA: if (wr_fifo_re_i) state_nxt = wr_done_i ? RESPONSE : WR_WAIT;
            WR_WAIT: if (wr_done_i) state_nxt = RESPONSE;
            RESPONSE: if (rsp_ready_i) state_nxt = IDLE;
            default: state_nxt = IDLE;
        endcase
        req_ready_o = state_r == IDLE && wr_ready_i && rd_ready_i;
        rsp_valid_o = state_r == RESPONSE;
        rsp_data_o = old_r;
        rsp_error_o = error_r;
        active_o = state_r != IDLE;
        wr_start_o = state_r == WR_START && wr_ready_i;
        wr_addr_o = addr_r; wr_len_o = 32'd32;
        wr_fifo_empty_o = state_r != WR_DATA;
        wr_fifo_data_o = merged_r;
        rd_start_o = state_r == RD_START && rd_ready_i;
        rd_addr_o = addr_r; rd_len_o = 32'd32;
        rd_fifo_full_o = state_r != RD_DATA;
    end
    always_ff @(posedge clk_i) begin
        if (state_r == IDLE && req_valid_i && req_ready_o) begin
            data_r <= req_data_i;
            merged_r <= req_data_i;
        end
        if (state_r == RD_DATA && rd_fifo_we_i) old_r <= rd_fifo_data_i;
        if (state_r == MERGE)
            for (int b = 0; b < 32; b++)
                merged_r[b*8 +: 8] <= mask_r[b] ? data_r[b*8 +: 8] : old_r[b*8 +: 8];
    end
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            addr_r <= 31'd0; mask_r <= 32'd0; write_r <= 1'b0;
            error_r <= 1'b0; read_done_r <= 1'b0;
        end else begin
            if (state_r == IDLE && req_valid_i && req_ready_o) begin
                addr_r <= {req_addr_i[30:5],5'd0}; mask_r <= req_mask_i;
                write_r <= req_write_i; error_r <= 1'b0; read_done_r <= 1'b0;
            end
            case (state_r)
                RD_DATA, RD_WAIT: begin
                    error_r <= error_r || rd_error_i;
                    if (rd_done_i) read_done_r <= 1'b1;
                end
                WR_DATA, WR_WAIT: error_r <= error_r || wr_error_i;
                default: ;
            endcase
        end
    end
endmodule
