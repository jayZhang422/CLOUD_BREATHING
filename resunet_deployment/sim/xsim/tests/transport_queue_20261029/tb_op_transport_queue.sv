`timescale 1ns/1ps
// 【文件类型：.sv】op_transport 四槽请求环形队列的定向自校验（仅测传输层，不含 op_board）。
// 覆盖：CRC 失败帧不入队、满队列阻塞与 accept 拒绝、被拒帧不污染活动槽载荷、
//       队列严格按到达顺序交付（ID/序号/长度/头部/载荷）、槽位回绕复用、
//       接收与释放同拍（count=1 / count=2 / 队满）、回复帧与请求一一对应。
// 服务端、MAC 均为 TB 内的行为模型；DUT 内的 BRAM 使用工程内真实 IP 仿真模型。
// 自校验：任何不一致立即 $error + $stop；全部通过打印 [TB PASSED]；含看门狗。
module tb_op_transport_queue;
    localparam int NB = 4;

    // 125MHz RX 时钟与 250MHz 计算时钟，相位错开以覆盖异步关系。
    logic rx_clk = 1'b0, ui_clk = 1'b0;
    logic rx_rst_n = 1'b0, ui_rst_n = 1'b0;
    always #4 rx_clk = !rx_clk;
    initial begin #1.3; forever #2 ui_clk = !ui_clk; end

    // DUT 接口
    logic frame_valid = 1'b0, body_en = 1'b0;
    logic accept, block_rx, tx_start;
    logic tx_req = 1'b0, tx_done = 1'b0;
    logic [7:0] msg = 8'd0, body_data = 8'd0, tx_data;
    logic [31:0] id = 32'd0, seq_id = 32'd0;
    logic [15:0] body_len = 16'd0, body_count = 16'd0, tx_len;
    logic req_valid, req_ready = 1'b0, resp_valid = 1'b0;
    logic [7:0] req_msg;
    logic [31:0] req_id, req_sequence;
    logic [15:0] req_len;
    logic [511:0] req_body;
    logic [4:0] req_data_addr = 5'd0;
    logic req_data_en = 1'b0;
    logic [255:0] req_data;
    logic [15:0] resp_len = 16'd16;
    logic [127:0] resp_body = 128'd0;
    logic resp_data_we = 1'b0;
    logic [4:0] resp_data_addr = 5'd0;
    logic [255:0] resp_data = 256'd0;

    op_transport dut (
        .rx_clk_i(rx_clk), .ui_clk_i(ui_clk), .rx_rst_n_i(rx_rst_n), .ui_rst_n_i(ui_rst_n),
        .legacy_idle_i(1'b1), .block_ui_i(1'b0),
        .frame_valid_i(frame_valid), .body_en_i(body_en), .accept_o(accept), .block_rx_o(block_rx),
        .tx_start_o(tx_start), .tx_req_i(tx_req), .tx_done_i(tx_done),
        .req_valid_o(req_valid), .req_ready_i(req_ready), .resp_valid_i(resp_valid),
        .msg_i(msg), .id_i(id), .sequence_i(seq_id), .body_len_i(body_len),
        .body_count_i(body_count), .body_data_i(body_data),
        .tx_data_o(tx_data), .tx_len_o(tx_len),
        .req_msg_o(req_msg), .req_id_o(req_id), .req_sequence_o(req_sequence), .req_len_o(req_len),
        .req_body_o(req_body), .req_data_addr_i(req_data_addr), .req_data_en_i(req_data_en), .req_data_o(req_data),
        .resp_len_i(resp_len), .resp_body_i(resp_body), .resp_data_we_i(resp_data_we),
        .resp_data_addr_i(resp_data_addr), .resp_data_i(resp_data)
    );

    int cycle = 0;
    int accepted_q[$];       // 已被 DUT 接受、尚未被服务端取走的帧编号（到达顺序）
    int credit = 0;          // 服务端允许回复的次数
    int obs_count = 0;       // 服务端已取走的请求数
    int accepted_total = 0;
    int csv;

    // 帧内容完全由编号 n 决定：n==3 为 40 字节短写；n==7 为 0x22 零长度请求；其余为满 1032 字节写。
    function automatic int f_len(input int n);
        return n == 3 ? 40 : n == 7 ? 0 : 1032;
    endfunction
    function automatic logic [7:0] f_msg(input int n);
        return n == 7 ? 8'h22 : 8'h20;
    endfunction
    function automatic logic [31:0] f_id(input int n);
        return 32'h1000_0000 + 32'(n);
    endfunction
    function automatic logic [31:0] f_seq(input int n);
        return 32'h2000_0000 + 32'(n) * 32'd16 + 32'd5;
    endfunction
    function automatic logic [7:0] f_byte(input int n, input int b);
        return 8'(n * 37 + b * 3 + 11);
    endfunction
    function automatic logic [31:0] crc_byte(input logic [31:0] c, input logic [7:0] d);
        logic [31:0] x;
        x = c ^ {24'd0, d};
        for (int i = 0; i < 8; i++) x = x[0] ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
        return x;
    endfunction

    task automatic fail(input string text);
        $error("%s time=%0t cycle=%0d", text, $time, cycle);
        $stop;
    endtask

    // 逐周期黑匣子；故障时按 cycle 定位。
    initial begin
        csv = $fopen("sim_trace.csv", "w");
        $fdisplay(csv, "cycle,frame_valid,accept,block_rx,tx_start,tx_done,count,wr_ptr,active,req_valid,req_id,accepted_q,credit");
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_op_transport_queue);
    end
    always @(posedge rx_clk) begin
        cycle <= cycle + 1;
        if (csv != 0)
            $fdisplay(csv, "%0d,%b,%b,%b,%b,%b,%0d,%0d,%0d,%b,%h,%0d,%0d", cycle, frame_valid, accept, block_rx,
                      tx_start, tx_done, dut.count_r, dut.wr_ptr_r, dut.active_bank_r, req_valid, req_id,
                      accepted_q.size(), credit);
    end
    initial begin
        repeat (400000) @(posedge rx_clk);
        $fatal(1, "Simulation Timeout!");
    end

    // ---------------- 服务端行为模型（计算时钟域） ----------------
    task automatic read_word(input int k, output logic [255:0] word);
        @(posedge ui_clk); #1;
        req_data_addr = 5'(k); req_data_en = 1'b1;
        @(posedge ui_clk); #1;
        req_data_en = 1'b0;
        word = req_data;       // 同步读无输出寄存器：使能后的下一个沿后数据有效
    endtask
    task automatic check_payload(input int n);
        logic [255:0] word;
        logic [255:0] expected;
        if (f_msg(n) == 8'h20 && f_len(n) >= 40) begin
            read_word(0, word);
            for (int i = 0; i < 32; i++) expected[i*8 +: 8] = f_byte(n, 8 + i);
            if (word !== expected)
                fail($sformatf("payload word0 mismatch frame=%0d got=%h exp=%h", n, word, expected));
        end
        if (f_len(n) == 1032) begin
            read_word(31, word);
            for (int i = 0; i < 32; i++) expected[i*8 +: 8] = f_byte(n, 8 + 31*32 + i);
            if (word !== expected)
                fail($sformatf("payload word31 mismatch frame=%0d got=%h exp=%h", n, word, expected));
        end
    endtask
    task automatic check_request(input int n);
        int limit;
        if (req_msg !== f_msg(n) || req_id !== f_id(n) || req_sequence !== f_seq(n) || req_len !== 16'(f_len(n)))
            fail($sformatf("descriptor mismatch frame=%0d msg=%h id=%h seq=%h len=%0d", n, req_msg, req_id, req_sequence, req_len));
        limit = f_len(n) < 64 ? f_len(n) : 64;
        for (int b = 0; b < limit; b++)
            if (req_body[b*8 +: 8] !== f_byte(n, b))
                fail($sformatf("request header byte %0d mismatch frame=%0d got=%h exp=%h", b, n, req_body[b*8 +: 8], f_byte(n, b)));
        check_payload(n);
    endtask
    initial begin
        int n;
        wait (ui_rst_n === 1'b1);
        forever begin
            @(posedge ui_clk); #1;
            if (req_valid === 1'b1) begin
                if (accepted_q.size() == 0) fail("request launched but no accepted frame is pending");
                n = accepted_q.pop_front();
                check_request(n);
                obs_count++;
                @(posedge ui_clk); #1; req_ready = 1'b1;       // 取走请求，等价 service 在 R_IDLE 接收
                @(posedge ui_clk); #1; req_ready = 1'b0;
                while (credit == 0) @(posedge ui_clk);
                #1;
                credit--;
                check_payload(n);                               // 回复前再查：被拒绝的帧不得污染活动槽载荷
                resp_len = 16'd16;
                resp_body = {64'd0, f_seq(n), f_id(n)};
                resp_valid = 1'b1;
                @(posedge ui_clk); #1; resp_valid = 1'b0;
            end
        end
    end

    // ---------------- RX 侧帧驱动 ----------------
    task automatic stream_body(input int n);
        @(negedge rx_clk);
        msg = f_msg(n); id = f_id(n); seq_id = f_seq(n); body_len = 16'(f_len(n));
        for (int b = 0; b < f_len(n); b++) begin
            body_en = 1'b1; body_count = 16'(b); body_data = f_byte(n, b);
            @(negedge rx_clk);
        end
        body_en = 1'b0;
    endtask
    task automatic present_frame(output bit acc);
        frame_valid = 1'b1; #1;
        acc = (accept === 1'b1);
        @(negedge rx_clk); frame_valid = 1'b0;
    endtask
    task automatic send_frame(input int n, input bit expect_accept);
        bit acc;
        stream_body(n);
        present_frame(acc);
        if (acc !== expect_accept) fail($sformatf("frame %0d accept=%b expected=%b", n, acc, expect_accept));
        if (acc) begin accepted_q.push_back(n); accepted_total++; end
        repeat (2) @(negedge rx_clk);
    endtask
    task automatic expect_state(input int expected_count, input bit expected_block, input string where_text);
        if (int'(dut.count_r) != expected_count)
            fail($sformatf("%s: count=%0d expected=%0d", where_text, dut.count_r, expected_count));
        if (block_rx !== expected_block)
            fail($sformatf("%s: block_rx=%b expected=%b", where_text, block_rx, expected_block));
    endtask

    // ---------------- TX MAC 行为模型 ----------------
    logic [7:0] rb [0:63];
    task automatic mac_read_reply(input int n);
        logic [31:0] crc, observed;
        int len;
        credit++;
        wait (tx_start === 1'b1);
        len = tx_len;
        if (len != 38) fail($sformatf("reply length %0d expected 38 frame=%0d", len, n));
        for (int b = 0; b < len; b++) begin
            if (b % 7 == 3) begin @(negedge rx_clk); tx_req = 1'b0; repeat (2) @(negedge rx_clk); end
            @(negedge rx_clk); tx_req = 1'b1;
            @(posedge rx_clk); #1; rb[b] = tx_data;
        end
        @(negedge rx_clk); tx_req = 1'b0;
        crc = 32'hffffffff;
        for (int b = 2; b < len - 6; b++) crc = crc_byte(crc, rb[b]);
        crc = ~crc;
        observed = {rb[len-6], rb[len-5], rb[len-4], rb[len-3]};
        if (rb[0] !== 8'h55 || rb[1] !== 8'haa || rb[2] !== 8'h01 || rb[3] !== (f_msg(n) | 8'h80))
            fail($sformatf("reply header mismatch frame=%0d bytes=%h %h %h %h", n, rb[0], rb[1], rb[2], rb[3]));
        if ({rb[4], rb[5], rb[6], rb[7]} !== f_id(n) || {rb[12], rb[13], rb[14], rb[15]} !== f_seq(n))
            fail($sformatf("reply id/seq mismatch frame=%0d id=%h seq=%h", n,
                           {rb[4], rb[5], rb[6], rb[7]}, {rb[12], rb[13], rb[14], rb[15]}));
        if ({rb[19], rb[18], rb[17], rb[16]} !== f_id(n) || {rb[23], rb[22], rb[21], rb[20]} !== f_seq(n))
            fail($sformatf("reply body mismatch frame=%0d body_id=%h body_seq=%h", n,
                           {rb[19], rb[18], rb[17], rb[16]}, {rb[23], rb[22], rb[21], rb[20]}));
        if (observed !== crc || rb[len-2] !== 8'haa || rb[len-1] !== 8'h55)
            fail($sformatf("reply CRC/tail mismatch frame=%0d crc=%h expected=%h", n, observed, crc));
    endtask
    task automatic mac_done();
        @(negedge rx_clk); tx_done = 1'b1;
        @(negedge rx_clk); tx_done = 1'b0;
        repeat (2) @(negedge rx_clk);
    endtask
    // 在同一个 RX 时钟沿同时给出 tx_done 与帧有效（帧体已提前流入）。
    task automatic collide(input int n, input bit expect_accept);
        bit acc;
        @(negedge rx_clk);
        tx_done = 1'b1; frame_valid = 1'b1; #1;
        acc = (accept === 1'b1);
        @(negedge rx_clk);
        tx_done = 1'b0; frame_valid = 1'b0;
        if (acc !== expect_accept) fail($sformatf("collide frame %0d accept=%b expected=%b", n, acc, expect_accept));
        if (acc) begin accepted_q.push_back(n); accepted_total++; end
        repeat (2) @(negedge rx_clk);
    endtask

    // ---------------- 测试流程 ----------------
    initial begin
        bit acc;
        repeat (10) @(negedge rx_clk);
        rx_rst_n = 1'b1; ui_rst_n = 1'b1;
        repeat (10) @(negedge rx_clk);
        expect_state(0, 1'b0, "after reset");

        // 1. CRC 失败帧：帧体流入但不给 frame_valid；随后的合法帧必须不受影响。
        stream_body(9);
        repeat (2) @(negedge rx_clk);
        expect_state(0, 1'b0, "aborted frame");

        // 2. 连续发送 4 帧填满 4 槽；首帧立即成为活动请求，其余排队。
        send_frame(0, 1'b1);
        send_frame(1, 1'b1);
        send_frame(2, 1'b1);
        send_frame(3, 1'b1);
        repeat (6) @(negedge rx_clk);
        expect_state(NB, 1'b1, "queue full");
        if (obs_count != 1) fail($sformatf("service saw %0d requests while queued, expected 1", obs_count));

        // 3. 队满：第 5 帧必须被拒绝，且帧体不得改写活动槽载荷（服务端回复前复查）。
        send_frame(4, 1'b0);
        expect_state(NB, 1'b1, "after rejected frame");

        // 4. 回复活动请求；释放同拍到达的帧在队满时仍被拒绝（accept 要求 full_r=0）。
        mac_read_reply(0);
        stream_body(5);
        collide(5, 1'b0);
        expect_state(NB - 1, 1'b0, "pop with full queue");

        // 5. 释放一个槽后帧 5 被接受，写指针回绕到已释放的槽位，再次队满。
        send_frame(5, 1'b1);
        repeat (4) @(negedge rx_clk);
        expect_state(NB, 1'b1, "refilled after wrap");

        // 6. 依次回复，队列必须按 1,2,3,5 的顺序交付。
        mac_read_reply(1); mac_done();
        mac_read_reply(2); mac_done();
        mac_read_reply(3); mac_done();
        repeat (4) @(negedge rx_clk);
        expect_state(1, 1'b0, "only frame 5 active");

        // 7. 接收与释放同拍（count=1）：新帧直接成为活动请求。
        stream_body(6);
        mac_read_reply(5);
        collide(6, 1'b1);
        expect_state(1, 1'b0, "collide with count=1");

        // 8. 接收与释放同拍（count=2）：队首装载、新帧入队，计数保持。
        send_frame(7, 1'b1);
        expect_state(2, 1'b0, "frame 7 queued");
        stream_body(8);
        mac_read_reply(6);
        collide(8, 1'b1);
        expect_state(2, 1'b0, "collide with count=2");

        // 9. 排空：先交付 7，再交付 8，最后队列回到空闲。
        mac_read_reply(7); mac_done();
        mac_read_reply(8); mac_done();
        repeat (30) @(negedge rx_clk);
        expect_state(0, 1'b0, "drained");
        if (tx_start !== 1'b0) fail("tx_start asserted after drain");
        if (accepted_q.size() != 0) fail("accepted frame never launched");
        if (obs_count != accepted_total) fail($sformatf("service saw %0d requests, accepted %0d", obs_count, accepted_total));
        if (obs_count != 8) fail($sformatf("expected 8 requests, saw %0d", obs_count));

        $fclose(csv);
        $display("[TB PASSED] 全部数据验证一致");
        $finish;
    end
endmodule
