`timescale 1ns / 1ps
// 【文件类型：.sv】整包缓存 + 稳定总线/toggle握手CDC；复用现有AXI master。
// 单包1024字节，忙时拒收下一包，由协议缺包位图触发重传。
// 请求至应答期间RAM和命令保持稳定；写完B响应才应答，整图按DDR地址读回算CRC。
module ethernet_ddr_bridge (
    input  logic         block_rx_i,          // 算子阶段禁止新图像包缓存
    input  logic         grant_ui_i,          // DDR 阶段所有权
    output logic         idle_ui_o,           // 无在途及等待提交的旧事务
    input  logic         rx_clk_i,             // 以太网时钟
    input  logic         ui_clk_i,             // MIG用户时钟
    input  logic         rx_rst_n_i,           // 接收域复位
    input  logic         ui_rst_n_i,           // UI域复位，与接收域共同断言
    input  logic         body_en_i,            // IMAGE_DATA原始body字节
    input  logic [15:0]  body_cnt_i,           // 包内偏移，像素从8开始
    input  logic [7:0]   body_data_i,          // 像素字节
    input  logic         packet_submit_i,      // CRC通过的新包提交
    input  logic [30:0]  packet_addr_i,        // DDR字节地址
    input  logic         verify_start_i,       // 整图DDR读回校验
    input  logic [30:0]  image_addr_i,         // 整图起始字节地址
    input  logic [31:0]  image_bytes_i,        // 整图长度，32字节对齐
    output logic         ready_o,              // 可以接收新操作
    output logic         capture_ok_o,         // 本包缓存有效且可提交
    output logic         packet_done_o,        // DDR写响应返回
    output logic         packet_error_o,       // 此次写失败
    output logic         verify_done_o,        // DDR读回和CRC计算结束
    output logic         verify_error_o,       // DDR读响应错误
    output logic [31:0]  verify_crc_o,         // ISO-HDLC，与zlib一致
    output logic         wr_start_o,           // 以下接口均为UI时钟域
    output logic [30:0]  wr_addr_o,
    output logic [31:0]  wr_len_o,
    input  logic         wr_ready_i,
    input  logic         wr_done_i,
    input  logic         wr_error_i,
    input  logic         wr_fifo_re_i,
    output logic         wr_fifo_empty_o,
    output logic [255:0] wr_fifo_data_o,
    output logic         rd_start_o,
    output logic [30:0]  rd_addr_o,
    output logic [31:0]  rd_len_o,
    input  logic         rd_ready_i,
    input  logic         rd_done_i,
    input  logic         rd_error_i,
    input  logic         rd_fifo_we_i,
    input  logic [255:0] rd_fifo_data_i,
    output logic         rd_fifo_full_o
);
    (* ram_style = "block" *) logic [255:0] packet_mem_r [0:31];
    logic [255:0] pack_r;
    logic capture_r, busy_r, request_r, ack_seen_r;
    logic cmd_verify_r;
    logic [30:0] cmd_addr_r;
    logic [31:0] cmd_bytes_r;
    logic ack_r, result_error_r;
    logic [31:0] result_crc_r;
    (* ASYNC_REG = "TRUE" *) logic ack_sync1_r, ack_sync2_r;
    (* ASYNC_REG = "TRUE" *) logic alive_sync1_r, alive_sync2_r;
    (* ASYNC_REG = "TRUE" *) logic request_sync1_r, request_sync2_r;
    logic [15:0] pixel_offset_w;
    assign pixel_offset_w = body_cnt_i - 16'd8;
    assign ready_o = alive_sync2_r && !busy_r && !block_rx_i;
    assign capture_ok_o = capture_r && ready_o;

    // 以太网不可反压，包首决定整包是否缓存；忙时整包丢弃，不能覆盖在途RAM。
    always_ff @(posedge rx_clk_i or negedge rx_rst_n_i) begin
        if (!rx_rst_n_i) capture_r <= 1'b0;
        else if (body_en_i && body_cnt_i == 16'd0) capture_r <= ready_o;
        else if (packet_submit_i || verify_start_i) capture_r <= 1'b0;
    end
    always_ff @(posedge rx_clk_i) begin
        if (body_en_i && capture_r && !busy_r &&
            body_cnt_i >= 16'd8 && body_cnt_i < 16'd1032) begin
            pack_r[pixel_offset_w[4:0]*8 +: 8] <= body_data_i;
            if (pixel_offset_w[4:0] == 5'd31)
                packet_mem_r[pixel_offset_w[9:5]] <= {body_data_i, pack_r[247:0]};
        end
    end

    always_ff @(posedge rx_clk_i or negedge rx_rst_n_i) begin
        if (!rx_rst_n_i) begin
            ack_sync1_r <= 1'b0;
            ack_sync2_r <= 1'b0;
            alive_sync1_r <= 1'b0;
            alive_sync2_r <= 1'b0;
            request_r <= 1'b0;
            ack_seen_r <= 1'b0;
            busy_r <= 1'b0;
            cmd_verify_r <= 1'b0;
            cmd_addr_r <= 31'd0;
            cmd_bytes_r <= 32'd0;
            packet_done_o <= 1'b0;
            packet_error_o <= 1'b0;
            verify_done_o <= 1'b0;
            verify_error_o <= 1'b0;
            verify_crc_o <= 32'd0;
        end else begin
            ack_sync1_r <= ack_r;
            ack_sync2_r <= ack_sync1_r;
            alive_sync1_r <= ui_rst_n_i;
            alive_sync2_r <= alive_sync1_r;
            packet_done_o <= 1'b0;
            verify_done_o <= 1'b0;
            if (ready_o && (packet_submit_i || verify_start_i)) begin
                busy_r <= 1'b1;
                request_r <= !request_r;
                cmd_verify_r <= verify_start_i;
                cmd_addr_r <= verify_start_i ? image_addr_i : packet_addr_i;
                cmd_bytes_r <= verify_start_i ? image_bytes_i : 32'd1024;
            end
            if (busy_r && ack_sync2_r != ack_seen_r) begin
                ack_seen_r <= ack_sync2_r;
                busy_r <= 1'b0;
                packet_done_o <= !cmd_verify_r;
                packet_error_o <= result_error_r;
                verify_done_o <= cmd_verify_r;
                verify_error_o <= result_error_r;
                verify_crc_o <= result_crc_r;
            end
        end
    end

    typedef enum logic [3:0] {
        ST_IDLE = 4'd0, ST_PREP = 4'd1, ST_WR_START = 4'd2,
        ST_WR_RUN = 4'd3, ST_RAM_WAIT = 4'd4, ST_WR_WAIT = 4'd5,
        ST_RD_START = 4'd6, ST_RD_RUN = 4'd7, ST_CRC_BYTE = 4'd8,
        ST_RD_WAIT = 4'd9, ST_DONE = 4'd10,
        ST_LOAD = 4'd11, ST_DISPATCH = 4'd12
    } state_t;
    state_t state_r, state_nxt;
    logic request_seen_r, operation_error_r, read_done_r, operation_verify_r;
    assign idle_ui_o = state_r == ST_IDLE && request_sync2_r == request_seen_r;
    logic [30:0] operation_addr_r;
    logic [31:0] operation_bytes_r, bytes_left_r;
    logic [4:0] read_ptr_r, crc_byte_r;
    logic [255:0] ram_data_r, read_beat_r;
    logic [31:0] crc_w;

    always_ff @(posedge ui_clk_i or negedge ui_rst_n_i) begin
        if (!ui_rst_n_i) begin
            request_sync1_r <= 1'b0;
            request_sync2_r <= 1'b0;
            state_r <= ST_IDLE;
        end else begin
            request_sync1_r <= request_r;
            request_sync2_r <= request_sync1_r;
            state_r <= state_nxt;
        end
    end
    always_comb begin
        state_nxt = state_r;
        case (state_r)
            ST_IDLE: if (grant_ui_i && request_sync2_r != request_seen_r && wr_ready_i && rd_ready_i)
                         state_nxt = ST_LOAD;
            ST_LOAD: state_nxt = ST_DISPATCH;
            ST_DISPATCH: state_nxt = operation_verify_r ? ST_RD_START : ST_PREP;
            ST_PREP: state_nxt = ST_WR_START;
            ST_WR_START: state_nxt = ST_WR_RUN;
            ST_WR_RUN: if (wr_fifo_re_i)
                           state_nxt = (read_ptr_r == 5'd31) ? ST_WR_WAIT : ST_RAM_WAIT;
            ST_RAM_WAIT: state_nxt = ST_WR_RUN;
            ST_WR_WAIT: if (wr_done_i) state_nxt = ST_DONE;
            ST_RD_START: state_nxt = ST_RD_RUN;
            ST_RD_RUN: if (rd_fifo_we_i) state_nxt = ST_CRC_BYTE;
            ST_CRC_BYTE: if (crc_byte_r == 5'd31)
                            state_nxt = (bytes_left_r != 32'd0) ? ST_RD_RUN :
                                        (read_done_r ? ST_DONE : ST_RD_WAIT);
            ST_RD_WAIT: if (read_done_r || rd_done_i) state_nxt = ST_DONE;
            ST_DONE: state_nxt = ST_IDLE;
            default: state_nxt = ST_IDLE;
        endcase
    end

    // BRAM端口B同步读；每次消费后空一拍预取，反压期间输出保持稳定。
    always_ff @(posedge ui_clk_i) ram_data_r <= packet_mem_r[read_ptr_r];
    always_ff @(posedge ui_clk_i) begin
        if (state_r == ST_RD_RUN && rd_fifo_we_i) read_beat_r <= rd_fifo_data_i;
        else if (state_r == ST_CRC_BYTE) read_beat_r <= {8'd0,read_beat_r[255:8]};
    end
    crc32_iso_hdlc u_image_crc (
        .clk_i(ui_clk_i), .rst_n_i(ui_rst_n_i),
        .crc_init_i(state_r == ST_RD_START),
        .crc_en_i(state_r == ST_CRC_BYTE),
        .data_i(read_beat_r[7:0]), .crc_o(crc_w)
    );
    always_ff @(posedge ui_clk_i or negedge ui_rst_n_i) begin
        if (!ui_rst_n_i) begin
            request_seen_r <= 1'b0;
            ack_r <= 1'b0;
            operation_addr_r <= 31'd0;
            operation_bytes_r <= 32'd0;
            bytes_left_r <= 32'd0;
            read_ptr_r <= 5'd0;
            crc_byte_r <= 5'd0;
            operation_error_r <= 1'b0;
            operation_verify_r <= 1'b0;
            read_done_r <= 1'b0;
            result_error_r <= 1'b0;
            result_crc_r <= 32'd0;
        end else begin
            case (state_r)
                // 独立装载拍：宽寄存器使能只译码当前状态，不依赖整段次态逻辑。
                ST_LOAD: begin
                    request_seen_r <= request_sync2_r;
                    operation_verify_r <= cmd_verify_r;
                    operation_addr_r <= cmd_addr_r;
                    operation_bytes_r <= cmd_bytes_r;
                    bytes_left_r <= cmd_bytes_r;
                    read_ptr_r <= 5'd0;
                    crc_byte_r <= 5'd0;
                    operation_error_r <= 1'b0;
                    read_done_r <= 1'b0;
                end
                ST_WR_RUN: if (wr_fifo_re_i && read_ptr_r != 5'd31)
                               read_ptr_r <= read_ptr_r + 5'd1;
                ST_RD_RUN: if (rd_fifo_we_i) begin
                    bytes_left_r <= bytes_left_r - 32'd32;
                    crc_byte_r <= 5'd0;
                end
                ST_CRC_BYTE: crc_byte_r <= crc_byte_r + 5'd1;
                ST_DONE: begin
                    result_error_r <= operation_error_r;
                    result_crc_r <= crc_w;
                    ack_r <= request_seen_r;
                end
                default: ;
            endcase
            case (state_r)
                ST_WR_RUN, ST_RAM_WAIT, ST_WR_WAIT:
                    operation_error_r <= operation_error_r || wr_error_i;
                ST_RD_RUN, ST_CRC_BYTE, ST_RD_WAIT: begin
                    operation_error_r <= operation_error_r || rd_error_i;
                    if (rd_done_i) read_done_r <= 1'b1;
                end
                default: ;
            endcase
        end
    end
    always_comb begin
        wr_start_o = (state_r == ST_WR_START);
        wr_addr_o = operation_addr_r;
        wr_len_o = operation_bytes_r;
        wr_fifo_empty_o = (state_r != ST_WR_RUN);
        wr_fifo_data_o = ram_data_r;
        rd_start_o = (state_r == ST_RD_START);
        rd_addr_o = operation_addr_r;
        rd_len_o = operation_bytes_r;
        rd_fifo_full_o = (state_r != ST_RD_RUN);
    end
endmodule
