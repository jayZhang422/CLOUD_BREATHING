// 文件类型：.sv（仅仿真）。C++ 驱动握手；此处进行四态全等比对与现场停止。
module tb_concat (
    input logic clk_i, rst_n_i,
    input logic cfg_valid_i,
    output logic cfg_ready_o, busy_o, done_o,
    output logic rd_valid_o,
    input logic rd_ready_i, rsp_valid_i,
    output logic rsp_ready_o, valid_o,
    input logic ready_i,
    output logic last_o,
    input logic [31:0] cfg_base1_i, cfg_base2_i, cfg_words1_i, cfg_words2_i,
    output logic rd_source_o,
    output logic [31:0] rd_addr_o,
    input logic [127:0] rsp_data_i,
    output logic [127:0] data_o,
    input logic check_i, finish_i, expected_valid_i,
    input logic expected_source_i, expected_last_i,
    input logic [31:0] expected_addr_i,
    input logic [127:0] golden_i
);
    concat dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .cfg_valid_i(cfg_valid_i), .cfg_ready_o(cfg_ready_o),
        .busy_o(busy_o), .done_o(done_o),
        .rd_valid_o(rd_valid_o), .rd_ready_i(rd_ready_i),
        .rsp_valid_i(rsp_valid_i), .rsp_ready_o(rsp_ready_o),
        .valid_o(valid_o), .ready_i(ready_i), .last_o(last_o),
        .cfg_base1_i(cfg_base1_i), .cfg_base2_i(cfg_base2_i),
        .cfg_words1_i(cfg_words1_i), .cfg_words2_i(cfg_words2_i),
        .rd_source_o(rd_source_o), .rd_addr_o(rd_addr_o),
        .rsp_data_i(rsp_data_i), .data_o(data_o)
    );
    logic held_out_r, held_req_r;
    logic [127:0] held_data_r;
    logic held_last_r, held_source_r;
    logic [31:0] held_addr_r;
    integer cycle_r = 0;

    always @(posedge clk_i) begin
        cycle_r <= cycle_r + 1;
        if (cycle_r > 20000000) $fatal(1, "Simulation Timeout!");
        if (finish_i) $finish;
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            held_out_r <= 1'b0;
            held_req_r <= 1'b0;
        end else if (!check_i) begin
            held_out_r <= 1'b0;
            held_req_r <= 1'b0;
        end else begin
            if (held_out_r && ((valid_o !== 1'b1) || (data_o !== held_data_r) ||
                              (last_o !== held_last_r))) begin
                $error("cycle=%0d 输出反压时 valid/data/last 改变", cycle_r);
                $stop;
            end
            if (held_req_r && ((rd_valid_o !== 1'b1) || (rd_addr_o !== held_addr_r) ||
                              (rd_source_o !== held_source_r))) begin
                $error("cycle=%0d 请求反压时 source/address 改变", cycle_r);
                $stop;
            end
            if (rd_valid_o && rd_ready_i &&
                ((expected_valid_i !== 1'b1) || (rd_addr_o !== expected_addr_i) ||
                 (rd_source_o !== expected_source_i))) begin
                $error("cycle=%0d 读请求 exp=%0d:%0h got=%0d:%0h", cycle_r,
                       expected_source_i, expected_addr_i, rd_source_o, rd_addr_o);
                $stop;
            end
            if (valid_o && ready_i &&
                ((expected_valid_i !== 1'b1) || (data_o !== golden_i) ||
                 (last_o !== expected_last_i))) begin
                $error("cycle=%0d Golden exp=%032h got=%032h exp_last=%b got_last=%b",
                       cycle_r, golden_i, data_o, expected_last_i, last_o);
                $stop;
            end
            held_out_r    <= valid_o && !ready_i;
            held_req_r    <= rd_valid_o && !rd_ready_i;
            held_data_r   <= data_o;
            held_last_r   <= last_o;
            held_addr_r   <= rd_addr_o;
            held_source_r <= rd_source_o;
        end
    end
endmodule
