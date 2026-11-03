`timescale 1ns / 1ps
// 【仿真文件：.sv】真实parser/core/bridge/AXI master + 带反压的AXI DDR内存模型。
// 不替代MIG物理校准仿真；覆盖整包CRC门控、乱序/重复/补发、CDC、B响应确认及读回CRC。
module tb_ethernet_ddr;
    logic rx_clk = 1'b0, ui_clk = 1'b0, rst_n = 1'b0;
    always #4 rx_clk = !rx_clk;
    always #1.5 ui_clk = !ui_clk;
    logic udp_en = 1'b0, udp_done = 1'b0;
    logic [7:0] udp_data = 8'd0;
    logic [15:0] udp_bytes = 16'd0;
    logic frame_valid, frame_error, body_en;
    logic [7:0] msg_type, body_data;
    logic [31:0] transfer_id, seq;
    logic [15:0] body_len, body_cnt;
    logic ready, capture_ok, packet_submit, packet_done, packet_error;
    logic verify_start, verify_done, verify_error, storage_error;
    logic [30:0] packet_addr, image_addr;
    logic [31:0] image_bytes, verify_crc, packet_count, bad_crc_count;
    logic tx_start, tx_req = 1'b0, tx_done = 1'b0;
    logic [7:0] tx_data;
    logic [15:0] tx_len;
    protocol_parser u_parser (
        .clk_i(rx_clk), .rst_n_i(rst_n), .udp_rx_en_i(udp_en), .udp_rx_data_i(udp_data),
        .udp_rx_done_i(udp_done), .udp_rx_bytes_i(udp_bytes), .frame_valid_o(frame_valid),
        .frame_error_o(frame_error), .msg_type_o(msg_type), .transfer_id_o(transfer_id),
        .sequence_o(seq), .body_len_o(body_len), .body_en_o(body_en),
        .body_data_o(body_data), .body_cnt_o(body_cnt)
    );
    eth_protocol_core #(.DDR_ENABLE(1'b1)) u_core (
        .clk_i(rx_clk), .rst_n_i(rst_n), .frame_valid_i(frame_valid), .frame_error_i(frame_error),
        .msg_type_i(msg_type), .transfer_id_i(transfer_id), .sequence_i(seq), .body_len_i(body_len),
        .body_en_i(body_en), .body_data_i(body_data), .body_cnt_i(body_cnt),
        .udp_tx_req_i(tx_req), .udp_tx_done_i(tx_done), .udp_tx_start_o(tx_start),
        .udp_tx_data_o(tx_data), .udp_tx_len_o(tx_len), .response_accept_o(),
        .ddr_ready_i(ready), .ddr_capture_ok_i(capture_ok),
        .ddr_packet_done_i(packet_done), .ddr_packet_error_i(packet_error),
        .ddr_verify_done_i(verify_done), .ddr_verify_error_i(verify_error), .ddr_verify_crc_i(verify_crc),
        .ddr_packet_submit_o(packet_submit), .ddr_packet_addr_o(packet_addr),
        .ddr_verify_start_o(verify_start), .ddr_image_addr_o(image_addr),
        .ddr_image_bytes_o(image_bytes), .ddr_error_o(storage_error),
        .rx_msg_type_o(), .rx_frame_valid_o(), .rx_frame_error_o(), .tx_msg_type_o(),
        .tx_frame_done_o(), .rx_pkt_cnt_o(packet_count), .rx_bad_crc_cnt_o(bad_crc_count), .rx_batch_cnt_o()
    );
    logic wr_start, wr_ready, wr_done, wr_error, wr_re, wr_empty;
    logic rd_start, rd_ready, rd_done, rd_error, rd_we, rd_full;
    logic [30:0] wr_addr, rd_addr;
    logic [31:0] wr_len, rd_len;
    logic [255:0] wr_data, rd_data;
    ethernet_ddr_bridge u_bridge (
        .block_rx_i(1'b0), .grant_ui_i(1'b1), .idle_ui_o(),
        .rx_clk_i(rx_clk), .ui_clk_i(ui_clk), .rx_rst_n_i(rst_n), .ui_rst_n_i(rst_n),
        .body_en_i(body_en && msg_type == 8'h01), .body_cnt_i(body_cnt), .body_data_i(body_data),
        .packet_submit_i(packet_submit), .packet_addr_i(packet_addr), .verify_start_i(verify_start),
        .image_addr_i(image_addr), .image_bytes_i(image_bytes), .ready_o(ready), .capture_ok_o(capture_ok),
        .packet_done_o(packet_done), .packet_error_o(packet_error), .verify_done_o(verify_done),
        .verify_error_o(verify_error), .verify_crc_o(verify_crc),
        .wr_start_o(wr_start), .wr_addr_o(wr_addr), .wr_len_o(wr_len), .wr_ready_i(wr_ready),
        .wr_done_i(wr_done), .wr_error_i(wr_error), .wr_fifo_re_i(wr_re),
        .wr_fifo_empty_o(wr_empty), .wr_fifo_data_o(wr_data),
        .rd_start_o(rd_start), .rd_addr_o(rd_addr), .rd_len_o(rd_len), .rd_ready_i(rd_ready),
        .rd_done_i(rd_done), .rd_error_i(rd_error), .rd_fifo_we_i(rd_we),
        .rd_fifo_data_i(rd_data), .rd_fifo_full_o(rd_full)
    );
    logic awvalid, awready, wvalid, wready, wlast, bvalid = 1'b0, bready;
    logic arvalid, arready, rvalid = 1'b0, rready, rlast = 1'b0;
    logic [30:0] awaddr, araddr;
    logic [7:0] awlen, arlen;
    logic [31:0] wstrb;
    logic [255:0] wdata, rdata = 256'd0;
    logic [1:0] bresp = 2'd0, rresp = 2'd0;
    aq_axi_master #(.AXI_ADDR_WIDTH(31), .AXI_DATA_WIDTH(256), .MAX_OUT_WR(8), .MAX_OUT_RD(8)) u_master (
        .ACLK(ui_clk), .ARESETN(rst_n), .MASTER_RST(1'b0),
        .M_AXI_AWID(), .M_AXI_AWADDR(awaddr), .M_AXI_AWLEN(awlen), .M_AXI_AWSIZE(),
        .M_AXI_AWBURST(), .M_AXI_AWLOCK(), .M_AXI_AWCACHE(), .M_AXI_AWPROT(), .M_AXI_AWQOS(),
        .M_AXI_AWUSER(), .M_AXI_AWVALID(awvalid), .M_AXI_AWREADY(awready),
        .M_AXI_WDATA(wdata), .M_AXI_WSTRB(wstrb), .M_AXI_WLAST(wlast), .M_AXI_WUSER(),
        .M_AXI_WVALID(wvalid), .M_AXI_WREADY(wready), .M_AXI_BID(1'b0), .M_AXI_BRESP(bresp),
        .M_AXI_BUSER(1'b0), .M_AXI_BVALID(bvalid), .M_AXI_BREADY(bready),
        .M_AXI_ARID(), .M_AXI_ARADDR(araddr), .M_AXI_ARLEN(arlen), .M_AXI_ARSIZE(),
        .M_AXI_ARBURST(), .M_AXI_ARLOCK(), .M_AXI_ARCACHE(), .M_AXI_ARPROT(), .M_AXI_ARQOS(),
        .M_AXI_ARUSER(), .M_AXI_ARVALID(arvalid), .M_AXI_ARREADY(arready),
        .M_AXI_RID(1'b0), .M_AXI_RDATA(rdata), .M_AXI_RRESP(rresp), .M_AXI_RLAST(rlast),
        .M_AXI_RUSER(1'b0), .M_AXI_RVALID(rvalid), .M_AXI_RREADY(rready),
        .WR_START(wr_start), .WR_ADRS(wr_addr), .WR_LEN(wr_len), .WR_READY(wr_ready),
        .WR_DONE(wr_done), .WR_ERR(wr_error), .WR_FIFO_RE(wr_re),
        .WR_FIFO_EMPTY(wr_empty), .WR_FIFO_DATA(wr_data),
        .RD_START(rd_start), .RD_ADRS(rd_addr), .RD_LEN(rd_len), .RD_READY(rd_ready),
        .RD_DONE(rd_done), .RD_ERR(rd_error), .RD_FIFO_WE(rd_we),
        .RD_FIFO_FULL(rd_full), .RD_FIFO_DATA(rd_data), .DEBUG()
    );

    // AXI内存模型按字节地址存储，AW/W/R分别加入反压，B响应延迟。
    localparam logic [30:0] BASE = 31'h1000_0000;
    logic [255:0] memory [0:8191];
    int ui_cycle = 0, write_index = 0, write_left = 0, read_index = 0, read_left = 0;
    int b_delay = 0, writes_completed = 0, response_delay = 9;
    bit inject_write_error = 1'b0, inject_read_error = 1'b0;
    assign awready = rst_n && write_left == 0 && !bvalid && b_delay == 0 && ui_cycle % 5 != 0;
    assign wready = rst_n && write_left != 0 && ui_cycle % 7 != 0;
    assign arready = rst_n && read_left == 0 && !rvalid && ui_cycle % 5 != 1;
    always @(posedge ui_clk) begin
        ui_cycle <= ui_cycle + 1;
        if (rst_n) begin
            if (awvalid && awready) begin
                if (awaddr < BASE || awaddr >= BASE + 31'd262144 ||
                    {1'b0,awaddr[11:0]} + (({5'd0,awlen} + 13'd1) << 5) > 13'd4096)
                    $fatal(1, "AW address/range/4KB boundary");
                write_index <= (awaddr - BASE) >> 5;
                write_left <= int'(awlen) + 1;
            end
            if (wvalid && wready) begin
                if (wstrb !== 32'hFFFF_FFFF || wlast !== (write_left == 1))
                    $fatal(1, "WSTRB/WLAST mismatch");
                memory[write_index] <= wdata;
                write_index <= write_index + 1;
                write_left <= write_left - 1;
                if (wlast) b_delay <= response_delay;
            end
            if (b_delay != 0) begin
                b_delay <= b_delay - 1;
                if (b_delay == 1) begin
                    bvalid <= 1'b1;
                    bresp <= inject_write_error ? 2'b10 : 2'b00;
                end
            end
            if (bvalid && bready) begin
                bvalid <= 1'b0;
                writes_completed <= writes_completed + 1;
            end
            if (arvalid && arready) begin
                read_index <= (araddr - BASE) >> 5;
                read_left <= int'(arlen) + 1;
            end
            if (rvalid && rready) rvalid <= 1'b0;
            if (!rvalid && read_left != 0 && ui_cycle % 3 != 0) begin
                rvalid <= 1'b1;
                rdata <= memory[read_index];
                rlast <= read_left == 1;
                rresp <= inject_read_error ? 2'b10 : 2'b00;
                read_index <= read_index + 1;
                read_left <= read_left - 1;
            end
        end
    end
    logic stalled_w = 1'b0, stalled_aw = 1'b0, stalled_ar = 1'b0;
    logic [255:0] held_w;
    logic held_last;
    logic [38:0] held_aw, held_ar;
    integer csv, rx_csv, rx_cycle = 0;
    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_ethernet_ddr);
        csv = $fopen("sim_trace.csv", "w");
        rx_csv = $fopen("sim_rx_trace.csv", "w");
        if (!csv || !rx_csv) $fatal(1, "cannot open trace CSV");
        $fdisplay(csv, "cycle,awvalid,awready,awaddr,awlen,wvalid,wready,wdata,wlast,bvalid,bready,bresp,arvalid,arready,araddr,arlen,rvalid,rready,rdata,rlast,rresp,bridge_state");
        $fdisplay(rx_csv, "cycle,frame_valid,frame_error,body_en,body_cnt,packet_submit,packet_done,packet_error,packet_count,verify_start,verify_done,verify_error,verify_crc");
    end
    always @(posedge rx_clk) begin
        rx_cycle <= rx_cycle + 1;
        $fdisplay(rx_csv, "%0d,%b,%b,%b,%0d,%b,%b,%b,%0d,%b,%b,%b,%08h", rx_cycle,
            frame_valid,frame_error,body_en,body_cnt,packet_submit,packet_done,packet_error,
            packet_count,verify_start,verify_done,verify_error,verify_crc);
    end
    always @(posedge ui_clk) begin
        $fdisplay(csv, "%0d,%b,%b,%08h,%0d,%b,%b,%064h,%b,%b,%b,%b,%b,%b,%08h,%0d,%b,%b,%064h,%b,%b,%0d",
            ui_cycle,awvalid,awready,awaddr,awlen,wvalid,wready,wdata,wlast,bvalid,bready,bresp,
            arvalid,arready,araddr,arlen,rvalid,rready,rdata,rlast,rresp,u_bridge.state_r);
        if (rst_n) begin
            if (stalled_w && (!wvalid || wdata !== held_w || wlast !== held_last))
                $fatal(1,"cycle %0d: W payload changed under backpressure",ui_cycle);
            if (stalled_aw && (!awvalid || {awaddr,awlen} !== held_aw))
                $fatal(1,"cycle %0d: AW changed under backpressure",ui_cycle);
            if (stalled_ar && (!arvalid || {araddr,arlen} !== held_ar))
                $fatal(1,"cycle %0d: AR changed under backpressure",ui_cycle);
            stalled_w <= wvalid && !wready;
            stalled_aw <= awvalid && !awready;
            stalled_ar <= arvalid && !arready;
            held_w <= wdata;
            held_last <= wlast;
            held_aw <= {awaddr,awlen};
            held_ar <= {araddr,arlen};
        end
    end

    byte unsigned body [0:1031], request [0:1053], reply [0:319];
    int sequence_number = 0, reply_length;
    logic [31:0] test_id = 32'h1234_5678;
    function automatic logic [31:0] crc_byte(input logic [31:0] crc, input logic [7:0] data);
        logic [31:0] x;
        x = crc ^ {24'd0,data};
        for (int bit_idx = 0; bit_idx < 8; bit_idx++)
            x = x[0] ? ((x >> 1) ^ 32'hEDB8_8320) : (x >> 1);
        return x;
    endfunction
    function automatic byte unsigned pixel(input int packet, input int offset);
        return 8'((packet * 37 + offset * 13 + offset / 256) & 255);
    endfunction
    task automatic clear_body;
        for (int i = 0; i < 1032; i++) body[i] = 8'd0;
    endtask
    task automatic put16(input int pos, input logic [15:0] value);
        body[pos] = value[15:8]; body[pos+1] = value[7:0];
    endtask
    task automatic put32(input int pos, input logic [31:0] value);
        for (int i = 0; i < 4; i++) body[pos+i] = value[31-i*8 -: 8];
    endtask
    task automatic put64(input int pos, input logic [63:0] value);
        for (int i = 0; i < 8; i++) body[pos+i] = value[63-i*8 -: 8];
    endtask
    task automatic send_frame(input byte unsigned kind, input int length, input bit corrupt = 1'b0);
        logic [31:0] crc;
        request[0]=8'h55; request[1]=8'hAA; request[2]=8'h01; request[3]=kind;
        for (int i=0;i<4;i++) request[4+i]=test_id[31-i*8 -: 8];
        request[8]=8'd0; request[9]=8'd16;
        request[10]=8'(length >> 8); request[11]=8'(length);
        for (int i=0;i<4;i++) request[12+i]=8'(sequence_number >> (24-i*8));
        sequence_number++;
        for (int i=0;i<length;i++) request[16+i]=body[i];
        crc=32'hFFFF_FFFF;
        for (int i=2;i<16+length;i++) crc=crc_byte(crc,request[i]);
        crc=~crc;
        if(corrupt) crc=crc ^ 32'd1;
        for(int i=0;i<4;i++) request[16+length+i]=crc[31-i*8 -: 8];
        request[20+length]=8'hAA; request[21+length]=8'h55;
        for(int i=0;i<22+length;i++) begin
            @(negedge rx_clk); udp_en=1'b1; udp_data=request[i];
        end
        @(negedge rx_clk); udp_en=1'b0; udp_done=1'b1; udp_bytes=16'(22+length);
        @(negedge rx_clk); udp_done=1'b0;
        repeat(8) @(negedge rx_clk);
    endtask
    task automatic get_reply(input byte unsigned kind, input int status_offset, input byte unsigned status);
        logic [31:0] crc, received_crc;
        wait(tx_start);
        reply_length=int'(tx_len);
        for(int i=0;i<reply_length;i++) begin
            @(negedge rx_clk); tx_req=1'b1;
            @(posedge rx_clk); #0.1; reply[i]=tx_data;
        end
        @(negedge rx_clk); tx_req=1'b0; tx_done=1'b1;
        @(negedge rx_clk); tx_done=1'b0;
        if(reply[3] !== kind || reply[16+status_offset] !== status)
            $fatal(1,"reply type/status: got %02h/%02h wanted %02h/%02h",reply[3],reply[16+status_offset],kind,status);
        crc=32'hFFFF_FFFF;
        for(int i=2;i<reply_length-6;i++) crc=crc_byte(crc,reply[i]);
        received_crc={reply[reply_length-6],reply[reply_length-5],reply[reply_length-4],reply[reply_length-3]};
        if(received_crc !== ~crc) $fatal(1,"reply frame CRC mismatch");
        repeat(4) @(negedge rx_clk);
    endtask
    logic [31:0] whole_crc;
    task automatic begin_image;
        clear_body(); put32(0,32'd1); put16(4,16'd512); put16(6,16'd512);
        body[8]=8'd1;body[9]=8'd1;body[10]=8'd1;body[11]=8'd1;
        put32(12,32'd1024);put32(16,32'd256);put32(20,32'd262144);
        put64(24,64'd262144);put64(32,{33'd0,BASE});put32(40,32'd1);put32(44,32'd256);
        put32(48,whole_crc);put16(68,16'd33);put16(70,16'd16);put16(72,16'd96);
        send_frame(8'h03,76); get_reply(8'h81,1,8'h00);
    endtask
    task automatic send_packet(input int index, input bit corrupt = 1'b0);
        clear_body();put16(2,16'(index));put16(4,16'd1024);
        for(int i=0;i<1024;i++) body[8+i]=pixel(index,i);
        send_frame(8'h01,1032,corrupt);
        wait(ready);repeat(3) @(negedge rx_clk);
    endtask
    task automatic end_batch(input byte unsigned status);
        clear_body();put16(4,16'd1);put32(8,32'd256);put32(12,whole_crc);
        send_frame(8'h05,16);get_reply(8'h83,2,status);
    endtask
    task automatic end_image(input byte unsigned status);
        clear_body();put32(0,32'd256);put64(4,64'd262144);put32(12,whole_crc);
        send_frame(8'h04,20);get_reply(8'h84,0,status);
    endtask
    initial begin : stimulus
        int saved_writes;
        whole_crc=32'hFFFF_FFFF;
        for(int p=0;p<256;p++)
            for(int i=0;i<1024;i++) whole_crc=crc_byte(whole_crc,pixel(p,i));
        whole_crc=~whole_crc;
        #80; @(negedge rx_clk);rst_n=1'b1;wait(ready);
        begin_image();
        send_packet(0,1'b1);
        if(packet_count !== 32'd0 || writes_completed != 0) $fatal(1,"bad frame reached DDR");
        // 反向发送，漏第7号；先写入最后包，验证地址而非到达次序。
        for(int p=255;p>=0;p--) if(p!=7) send_packet(p);
        saved_writes=writes_completed;
        send_packet(0);
        if(writes_completed!=saved_writes || packet_count!==32'd255) $fatal(1,"duplicate counted/written");
        end_batch(8'h01);
        if(reply[32]!==8'h01) $fatal(1,"missing bitmap bit7 incorrect");
        end_batch(8'h01);
        send_packet(7);
        end_batch(8'h00);end_batch(8'h00);
        if(packet_count!==32'd256 || writes_completed!=256) $fatal(1,"packet commit count mismatch");
        for(int p=0;p<256;p++)
            for(int i=0;i<1024;i++)
                if(memory[p*32+i/32][(i%32)*8 +: 8] !== pixel(p,i))
                    $fatal(1,"DDR byte mismatch packet=%0d byte=%0d",p,i);
        end_image(8'h00);
        if({reply[36],reply[37],reply[38],reply[39]} !== whole_crc)
            $fatal(1,"DDR whole-image CRC mismatch");
        end_image(8'h00); // 重复结束应缓存结果。
        // 新传输：DDR内容损坏必须返回CRC_ERROR，而非伪造OK。
        test_id++;begin_image();
        for(int p=0;p<256;p++) send_packet(p);
        end_batch(8'h00);
        @(negedge ui_clk);memory[0][0]=!memory[0][0];
        end_image(8'h02);
        // 延迟B响应期间不应提前计数，忙时下一包不能覆盖在途缓存。
        test_id++;begin_image();response_delay=4000;
        clear_body();put16(4,16'd1024);
        for(int i=0;i<1024;i++) body[8+i]=pixel(0,i);
        send_frame(8'h01,1032);
        if(packet_count!==32'd0) $fatal(1,"count advanced before B response");
        put16(2,16'd1);
        for(int i=0;i<1024;i++) body[8+i]=pixel(1,i);
        send_frame(8'h01,1032);
        wait(ready);repeat(3) @(negedge rx_clk);
        if(packet_count!==32'd1) $fatal(1,"busy packet was counted");
        response_delay=9;send_packet(1);
        if(packet_count!==32'd2) $fatal(1,"busy packet retransmission failed");
        // AXI写响应出错不得记入位图。
        test_id++;begin_image();inject_write_error=1'b1;send_packet(0);
        if(packet_count!==32'd0 || !storage_error) $fatal(1,"BRESP error incorrectly committed");
        inject_write_error=1'b0;
        $display("[TB PASSED] ETHERNET_DDR: storage, reorder, retry, duplicate, CRC and BRESP checks");
        $fclose(csv);$fclose(rx_csv);$finish;
    end
    initial begin #30_000_000; $fatal(1,"ETHERNET_DDR timeout"); end
endmodule
