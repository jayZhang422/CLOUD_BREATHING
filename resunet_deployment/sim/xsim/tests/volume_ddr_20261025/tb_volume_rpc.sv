`timescale 1ns/1ps
// 【文件类型：.sv】实际 op_board＋ROM IP 的 XSim 自校验。
// 验证边界为原解析器的 CRC 合格帧输出及已有 DDR master 用户接口。
// 算法 Golden 来自冻结整数张量；DDR 模型只负责时序和字节存储。
module tb_volume_rpc #(parameter bit FAST=1'b1, parameter bit VOLUME_ONLY=1'b0,
    parameter bit AUTONOMOUS=1'b0, parameter bit AXI_MASTER=1'b0,
    parameter bit RESET_SKEW=1'b0);
    localparam string VECTOR_DIR = "sim/xsim/tests/mkdc/vectors/";
    string case_list = "sim/xsim/tests/p8p16_pending/rpc_cases.txt";
    logic bounds_done = 1'b0, bounds_we = 1'b0, bounds_en = 1'b0;
    logic [12:0] bounds_wr_addr = 13'd0, bounds_rd_addr = 13'd0;
    logic [511:0] bounds_wr_data = 512'd0, bounds_rd_data;
    logic rx_clk = 1'b0, ui_clk = 1'b0, rst_n = 1'b0;
    logic rx_enable = 1'b1;
    always #4 if(rx_enable) rx_clk = !rx_clk;
    // 算子/ROM选择125或250MHz，MIG UI=333.333MHz。
    always #1.5 ui_clk = !ui_clk;
    wire compute_250, compute_125, clock_locked;
    wire compute_clk = FAST ? compute_250 : compute_125;
    op_compute_clk_wiz clocks(.clk_in1(ui_clk),.resetn(rst_n),.locked(clock_locked),
                               .clk_out1(compute_250),.clk_out2(compute_125));
    logic frame_valid = 1'b0, body_en = 1'b0;
    logic [7:0] msg = 8'd0, body_data = 8'd0;
    logic [31:0] run_id = 32'd0, sequence_id = 32'd0;
    logic [15:0] body_len = 16'd0, body_count = 16'd0;
    logic accept, block_rx, claim, tx_start;
    logic tx_req = 1'b0, tx_done = 1'b0;
    logic [7:0] tx_data;
    logic [15:0] tx_len;
    logic image_ready = 1'b0;
    logic [30:0] image_base = 31'h10000000;
    logic [31:0] image_slices = 32'd0;
    logic wr_start, wr_empty, rd_start, rd_full;
    logic wr_ready, rd_ready, wr_re, rd_we, wr_done, rd_done;
    logic [30:0] wr_addr, rd_addr;
    logic [31:0] wr_len, rd_len;
    logic [255:0] wr_data, rd_data;
    logic coeff_req, coeff_ready, coeff_valid, coeff_rsp_ready, coeff_error;
    logic [30:0] coeff_addr;
    logic [255:0] coeff_data;
    logic compute_rst_n;

op_board #(.COMPUTE_HZ(FAST ? 32'd250000000 : 32'd125000000)) dut (
        .rx_clk_i(rx_clk), .ui_clk_i(ui_clk), .rx_rst_n_i(rst_n), .ui_rst_n_i(rst_n),
        .compute_clk_i(compute_clk), .compute_locked_i(clock_locked), .compute_rst_n_o(compute_rst_n),
        .legacy_idle_rx_i(1'b1), .storage_idle_ui_i(1'b1),
        .image_ready_rx_i(image_ready), .image_base_rx_i(image_base), .image_slices_rx_i(image_slices),
        .frame_valid_i(frame_valid), .body_en_i(body_en), .accept_o(accept), .block_rx_o(block_rx),
        .claim_ui_o(claim), .tx_start_o(tx_start), .tx_req_i(tx_req), .tx_done_i(tx_done),
        .msg_i(msg), .id_i(run_id), .sequence_i(sequence_id), .body_len_i(body_len),
        .body_count_i(body_count), .body_data_i(body_data), .tx_data_o(tx_data), .tx_len_o(tx_len),
        .wr_start_o(wr_start), .wr_ready_i(wr_ready), .wr_done_i(wr_done), .wr_error_i(1'b0),
        .wr_fifo_re_i(wr_re), .wr_fifo_empty_o(wr_empty), .wr_fifo_data_o(wr_data),
        .wr_addr_o(wr_addr), .wr_len_o(wr_len),
        .rd_start_o(rd_start), .rd_ready_i(rd_ready), .rd_done_i(rd_done), .rd_error_i(1'b0),
        .rd_fifo_we_i(rd_we), .rd_fifo_full_o(rd_full), .rd_fifo_data_i(rd_data),
        .rd_addr_o(rd_addr), .rd_len_o(rd_len),
        .coeff_req_valid_o(coeff_req), .coeff_req_ready_i(coeff_ready), .coeff_req_addr_o(coeff_addr),
        .coeff_rsp_valid_i(coeff_valid), .coeff_rsp_ready_o(coeff_rsp_ready),
        .coeff_rsp_data_i(coeff_data), .coeff_rsp_error_i(coeff_error)
    );
    op_coeff_rom rom (
        .clk_i(compute_clk), .rst_n_i(compute_rst_n), .req_valid_i(coeff_req), .req_ready_o(coeff_ready),
        .req_addr_i(coeff_addr), .rsp_valid_o(coeff_valid), .rsp_ready_i(coeff_rsp_ready),
        .rsp_data_o(coeff_data), .rsp_error_o(coeff_error)
    );

    // 稀疏字节 DDR；确定性暂停请求、数据和完成响应。
    byte unsigned memory_bytes [int unsigned];
    int cycle = 0, rd_phase = 0, wr_phase = 0, rd_delay = 0, wr_delay = 0;
    int unsigned rd_address_r, wr_address_r, rd_remaining_r, wr_remaining_r;
    int ddr_reads = 0, ddr_writes = 0, rom_reads = 0;
    longint unsigned read_bytes=0, run_read_bytes=0;
    int run_reads=0;
    function automatic byte unsigned get_byte(input int unsigned address);
        if (memory_bytes.exists(address)) return memory_bytes[address];
        return 8'ha5;
    endfunction
    always @(posedge ui_clk) cycle = cycle + 1;
    generate if(!AXI_MASTER) begin : g_user_ddr
    assign wr_ready = claim && wr_phase == 0 && cycle % 7 != 1;
    assign rd_ready = claim && rd_phase == 0 && cycle % 11 != 3;
    assign wr_re = wr_phase == 1 && wr_delay == 0 && !wr_empty && cycle % 5 != 0;
    assign rd_we = rd_phase == 1 && rd_delay == 0 && !rd_full && cycle % 7 != 0;
    assign wr_done = wr_phase == 2 && wr_delay == 0;
    assign rd_done = rd_phase == 2 && rd_delay == 0;
    // XSim 不支持关联数组的自动敏感列表，负沿准备正沿交付的数据。
    always @(negedge ui_clk) begin
        rd_data = 256'd0;
        for (int b = 0; b < 32; b++) rd_data[b*8 +: 8] = get_byte(rd_address_r + b);
    end
    always @(posedge ui_clk) begin
        if (!rst_n) begin rd_phase = 0; wr_phase = 0; rd_delay = 0; wr_delay = 0; end
        else begin
            if ((rd_start || wr_start || rd_we || wr_re) && claim !== 1'b1) begin
                $error("DDR operation without UI ownership cycle=%0d",cycle); $stop;
            end
            if (rd_start && rd_ready) begin
                if ((rd_len < 32'd32 || rd_len > 32'd1024 || rd_len[4:0] !== 5'd0 || {1'b0,rd_addr[11:0]} + rd_len > 32'd4096) || rd_addr[4:0] !== 5'd0 || (rd_addr >= 31'h00100000 && rd_addr < 31'h00400000)) begin
                    $error("invalid DDR read addr=%h len=%d",rd_addr,rd_len); $stop;
                end
                rd_address_r <= rd_addr; rd_remaining_r <= rd_len;
                rd_phase <= 1; rd_delay <= 2; ddr_reads = ddr_reads + 1; read_bytes=read_bytes+rd_len;
            end else if (rd_we) begin
                rd_address_r <= rd_address_r + 32'd32;
                rd_remaining_r <= rd_remaining_r - 32'd32;
                if (rd_remaining_r == 32'd32) begin rd_phase <= 2; rd_delay <= 3; end
            end
            else if (rd_done) rd_phase <= 0;
            else if (rd_delay > 0) rd_delay <= rd_delay - 1;
            if (wr_start && wr_ready) begin
                if ((wr_len < 32'd32 || wr_len > 32'd1024 || wr_len[4:0] !== 5'd0 || {1'b0,wr_addr[11:0]} + wr_len > 32'd4096) || wr_addr[4:0] !== 5'd0 || (wr_addr >= 31'h00100000 && wr_addr < 31'h00400000)) begin
                    $error("invalid DDR write addr=%h len=%d",wr_addr,wr_len); $stop;
                end
                wr_address_r <= wr_addr; wr_remaining_r <= wr_len;
                wr_phase <= 1; wr_delay <= 2;
            end else if (wr_re) begin
                for (int b = 0; b < 32; b++) memory_bytes[wr_address_r+b] = wr_data[b*8 +: 8];
                if ($isunknown(wr_data)) begin $error("unknown write data cycle=%0d",cycle); $stop; end
                wr_address_r <= wr_address_r + 32'd32;
                wr_remaining_r <= wr_remaining_r - 32'd32;
                if (wr_remaining_r == 32'd32) begin
                    wr_phase <= 2; wr_delay <= 64; ddr_writes = ddr_writes + 1;
                end
            end else if (wr_done) wr_phase <= 0;
            else if (wr_delay > 0) wr_delay <= wr_delay - 1;
        end
    end
    end else begin : g_axi_ddr
        logic [31:0] awaddr,araddr,wstrb;
        logic [7:0] awlen,arlen;
        logic [2:0] awsize,arsize;
        logic [1:0] awburst,arburst;
        logic awvalid,awready,wvalid,wready,wlast,bvalid=1'b0,bready;
        logic arvalid,arready,rvalid=1'b0,rready,rlast=1'b0;
        logic [255:0] wdata,rdata=256'd0;
        logic b_pending=1'b0,w_stalled=1'b0,r_stalled=1'b0;
        logic [288:0] held_w;
        logic [256:0] held_r;
        aq_axi_master master(
            .ACLK(ui_clk),.ARESETN(rst_n),.MASTER_RST(1'b0),
            .M_AXI_AWADDR(awaddr),.M_AXI_AWLEN(awlen),.M_AXI_AWSIZE(awsize),.M_AXI_AWBURST(awburst),
            .M_AXI_AWVALID(awvalid),.M_AXI_AWREADY(awready),.M_AXI_WDATA(wdata),.M_AXI_WSTRB(wstrb),
            .M_AXI_WLAST(wlast),.M_AXI_WVALID(wvalid),.M_AXI_WREADY(wready),
            .M_AXI_BID(1'b0),.M_AXI_BUSER(1'b0),.M_AXI_BRESP(2'b00),.M_AXI_BVALID(bvalid),.M_AXI_BREADY(bready),
            .M_AXI_ARADDR(araddr),.M_AXI_ARLEN(arlen),.M_AXI_ARSIZE(arsize),.M_AXI_ARBURST(arburst),
            .M_AXI_ARVALID(arvalid),.M_AXI_ARREADY(arready),.M_AXI_RID(1'b0),.M_AXI_RUSER(1'b0),
            .M_AXI_RDATA(rdata),.M_AXI_RRESP(2'b00),.M_AXI_RLAST(rlast),.M_AXI_RVALID(rvalid),.M_AXI_RREADY(rready),
            .WR_START(wr_start),.WR_ADRS({1'b0,wr_addr}),.WR_LEN(wr_len),.WR_READY(wr_ready),
            .WR_FIFO_RE(wr_re),.WR_FIFO_EMPTY(wr_empty),.WR_FIFO_DATA(wr_data),.WR_DONE(wr_done),.WR_ERR(),
            .RD_START(rd_start),.RD_ADRS({1'b0,rd_addr}),.RD_LEN(rd_len),.RD_READY(rd_ready),
            .RD_FIFO_WE(rd_we),.RD_FIFO_FULL(rd_full),.RD_FIFO_DATA(rd_data),.RD_DONE(rd_done),.RD_ERR()
        );
        assign awready=claim&&wr_phase==0&&!b_pending&&!bvalid&&cycle%7!=1;
        assign wready=wr_phase==1&&cycle%5!=0;
        assign arready=claim&&rd_phase==0&&!rvalid&&cycle%11!=3;
        always @(posedge ui_clk)begin
            if(!rst_n)begin
                wr_phase<=0;rd_phase<=0;wr_delay<=0;rd_delay<=0;
                b_pending<=1'b0;bvalid<=1'b0;rvalid<=1'b0;
                w_stalled<=1'b0;r_stalled<=1'b0;
            end else begin
                if(w_stalled&&(wvalid!==1'b1||{wdata,wstrb,wlast}!==held_w))begin $error("AXI W unstable cycle=%0d",cycle);$stop;end
                if(r_stalled&&(rvalid!==1'b1||{rdata,rlast}!==held_r))begin $error("AXI R unstable cycle=%0d",cycle);$stop;end
                w_stalled<=wvalid&&!wready;held_w<={wdata,wstrb,wlast};
                r_stalled<=rvalid&&!rready;held_r<={rdata,rlast};
                if(awvalid&&awready)begin
                    if(awsize!==3'd5||awburst!==2'b01||awaddr[4:0]!==5'd0||int'(awaddr[11:0])+(int'(awlen)+1)*32>4096)begin $error("AXI AW boundary");$stop;end
                    wr_address_r<=awaddr;wr_remaining_r<=(int'(awlen)+1)*32;wr_phase<=1;
                end
                if(wvalid&&wready)begin
                    if(wlast!==(wr_remaining_r==32)||wstrb!==32'hffffffff)begin $error("AXI W length/mask");$stop;end
                    for(int b=0;b<32;b++)memory_bytes[wr_address_r+b]=wdata[b*8+:8];
                    wr_address_r<=wr_address_r+32;wr_remaining_r<=wr_remaining_r-32;
                    if(wlast)begin wr_phase<=0;b_pending<=1'b1;wr_delay<=64;ddr_writes=ddr_writes+1;end
                end
                if(b_pending)begin
                    if(wr_delay==0)begin bvalid<=1'b1;b_pending<=1'b0;end
                    else wr_delay<=wr_delay-1;
                end
                if(bvalid&&bready)bvalid<=1'b0;
                if(arvalid&&arready)begin
                    if(arsize!==3'd5||arburst!==2'b01||araddr[4:0]!==5'd0||int'(araddr[11:0])+(int'(arlen)+1)*32>4096)begin $error("AXI AR boundary");$stop;end
                    rd_address_r<=araddr;rd_remaining_r<=(int'(arlen)+1)*32;rd_phase<=1;rd_delay<=12;
                    ddr_reads=ddr_reads+1;read_bytes=read_bytes+(int'(arlen)+1)*32;
                end
                if(rd_phase==1&&rd_delay>0)rd_delay<=rd_delay-1;
                if(rvalid&&rready)begin
                    rvalid<=1'b0;rd_address_r<=rd_address_r+32;rd_remaining_r<=rd_remaining_r-32;
                    if(rlast)rd_phase<=0;
                end
                if(rd_phase==1&&(!rvalid||rready)&&!(rvalid&&rlast)&&rd_delay==0&&cycle%4!=0)begin
                    rvalid<=1'b1;rlast<=rd_remaining_r==(rvalid?64:32);
                    for(int b=0;b<32;b++)rdata[b*8+:8]<=get_byte(rd_address_r+(rvalid?32:0)+b);
                end
            end
        end
    end endgenerate

    string case_folder;
    longint unsigned hardware_cycles = 64'd0;
`ifndef CONTINUOUS_BASELINE
    longint unsigned perf_reference[0:15];
    always @(posedge compute_clk) begin
        if (!compute_rst_n || (dut.u_service.u_operator.u_engine.run_valid_i && dut.u_service.u_operator.u_engine.run_ready_o))
            for(int p=0;p<16;p++) perf_reference[p] <= 64'd0;
        else if(dut.u_service.u_operator.u_engine.busy_o && !dut.u_service.u_operator.u_engine.done_o)
            for(int p=0;p<16;p++)
                if(dut.u_service.u_operator.u_engine.perf_event_w[p]) perf_reference[p] <= perf_reference[p]+64'd1;
    end
`endif
    always @(posedge compute_clk) begin
        if (!compute_rst_n || (dut.u_service.u_operator.u_engine.run_valid_i && dut.u_service.u_operator.u_engine.run_ready_o))
            hardware_cycles <= 64'd0;
        else if (dut.u_service.u_operator.u_engine.busy_o && !dut.u_service.u_operator.u_engine.done_o)
            hardware_cycles <= hardware_cycles+64'd1;
    end
    integer csv;
    logic stalled_r = 1'b0;
    logic [255:0] stalled_data_r;
    logic bank_stalled_r = 1'b0;
    logic [127:0] bank_held_r;
    always @(posedge compute_clk) begin
        if (compute_rst_n && bank_stalled_r &&
            (dut.u_service.u_operator.u_engine.bank_out_valid_w !== 1'b1 ||
             dut.u_service.u_operator.u_engine.bank_data_w !== bank_held_r)) begin
            $error("core output changed under backpressure cycle=%0d",cycle); $stop;
        end
        bank_stalled_r <= compute_rst_n && dut.u_service.u_operator.u_engine.bank_out_valid_w && !dut.u_service.u_operator.u_engine.bank_out_ready_w;
        bank_held_r <= dut.u_service.u_operator.u_engine.bank_data_w;
    end
    always @(posedge ui_clk) begin
        $fdisplay(csv,"%0d,%s,%h,%b,%b,%h,%h,%b,%h,%h,%b,%h,%h",cycle,dut.u_service.u_operator.state_r.name(),dut.u_service.u_operator.offset_r,dut.mem_valid_w,dut.mem_ready_w,dut.mem_addr_w,dut.mem_data_w[31:0],dut.u_service.u_operator.req_data_en_o,dut.u_service.u_operator.req_data_addr_o,dut.u_service.u_operator.req_data_i[31:0],wr_re,wr_address_r,wr_data[31:0]);
    end
    // 独立黑匣子只记录控制与计数，失败时可定位首个停止前进的通道。
    integer engine_csv;
`define ENG dut.u_service.u_operator.u_engine
    always @(posedge compute_clk) begin
        if (compute_rst_n)
            $fdisplay(engine_csv,"%0t,%s,%0d,%0d,%b,%b,%b,%b,%b,%b,%b,%b,%0d,%0d,%0d,%0d",
                $time,`ENG.state_r.name(),`ENG.input_count_r,`ENG.output_count_r,
                `ENG.core_done_r,`ENG.pending_r,`ENG.move_valid_w,`ENG.move_ready_w,
                `ENG.bank_out_valid_w,`ENG.bank_out_ready_w,`ENG.move_read_idle_w,`ENG.move_write_idle_w,
                `ENG.u_move_reader.credit_r,`ENG.u_move_reader.left_r,
                `ENG.u_move_writer.queued_r,`ENG.u_move_writer.pending_r);
    end
`undef ENG
    // 显式故障注入：只模拟FSM各Q到组合译码器的50ps偏斜，不代表实测布线延迟。
    // 脉冲完全位于两时钟沿之间；寄存复位必须隔离它，后续仍检查完整Golden。
    generate if(RESET_SKEW)begin : g_reset_skew
        initial begin
            wait(dut.u_service.u_operator.u_engine.op_w==8'd11 &&
                dut.u_service.u_operator.u_engine.state_r==dut.u_service.u_operator.u_engine.CONFIGURE &&
                dut.u_service.u_operator.u_engine.add_loaded_r && dut.u_service.u_operator.u_engine.cfg_accepted_r);
            @(posedge compute_clk);#0.05;
            force dut.u_service.u_operator.u_engine.state_r=dut.u_service.u_operator.u_engine.RESET_CORE;
            #0.05;
            if(dut.u_service.u_operator.u_engine.u_bank.rst_n_i!==1'b1)begin
                $error("FSM skew caused asynchronous core reset");$stop;
            end
            force dut.u_service.u_operator.u_engine.state_r=dut.u_service.u_operator.u_engine.RUN;
            #0.01;release dut.u_service.u_operator.u_engine.state_r;
            $display("[CASE PASS] registered core reset rejects injected 50ps FSM skew");
        end
    end endgenerate
    always @(posedge compute_clk) begin
        if (compute_rst_n && coeff_req && coeff_ready) rom_reads = rom_reads + 1;
        if (compute_rst_n && stalled_r && (coeff_valid !== 1'b1 || coeff_data !== stalled_data_r)) begin
            $error("ROM response changed under backpressure cycle=%0d",cycle); $stop;
        end
        stalled_r <= compute_rst_n && coeff_valid && !coeff_rsp_ready;
        stalled_data_r <= coeff_data;
    end
    initial begin
        engine_csv = $fopen("engine_trace.csv","w");
        $fdisplay(engine_csv,"time,engine,input_count,output_count,core_done,pending,in_valid,in_ready,out_valid,out_ready,read_idle,write_idle,read_credit,read_left,write_queued,write_pending");
        csv = $fopen("sim_trace.csv","w");
        $fdisplay(csv,"cycle,service_state,offset,mem_valid,mem_ready,mem_addr,mem_data,req_en,req_addr,req_data,wr_re,wr_addr,wr_data");
        $dumpfile("waveform.vcd");
        $dumpvars(0,rst_n,coeff_req,coeff_ready,coeff_valid,coeff_rsp_ready,coeff_addr,rd_start,wr_start,wr_len,rd_len);
        repeat (5000000) @(posedge ui_clk);
        $fatal(1,"Simulation Timeout cycle=%0d",cycle);
    end

    byte unsigned request [0:1039], reply [0:1079];
    byte unsigned descriptor_mem [0:63];
    byte unsigned prefix_descriptor [0:63];
    byte unsigned file_mem [0:8388607], golden_mem [0:8388607];
    int reply_length;
    function automatic logic [31:0] crc_byte(input logic [31:0] old_crc,input byte unsigned data);
        logic [31:0] c;
        c = old_crc ^ {24'd0,data};
        for (int b=0;b<8;b++) c = c[0] ? (c>>1)^32'hedb88320 : c>>1;
        return c;
    endfunction
    function automatic int unsigned desc32(input int offset);
        return {descriptor_mem[offset+3],descriptor_mem[offset+2],descriptor_mem[offset+1],descriptor_mem[offset]};
    endfunction
    task automatic put32(input int offset,input int unsigned value);
        for (int b=0;b<4;b++) request[offset+b] = value[b*8 +: 8];
    endtask
    task automatic rpc(input byte unsigned kind,input int unsigned identity,input int length);
        logic [31:0] crc, observed;
        @(negedge rx_clk);
        msg = kind; run_id = identity; sequence_id = sequence_id + 32'd1; body_len = 16'(length);
        for (int b=0;b<length;b++) begin
            body_en = 1'b1; body_count = 16'(b); body_data = request[b];
            @(negedge rx_clk);
        end
        body_en = 1'b0; frame_valid = 1'b1;
        #1;
        if (accept !== 1'b1) begin $error("RPC rejected kind=%h time=%t",kind,$time); $stop; end
        @(negedge rx_clk); frame_valid = 1'b0;
        wait(tx_start === 1'b1);
        // One queued request is legal while the current reply is pending.
        // Do not inject a partial frame here: accept_o advertises mailbox capacity,
        // and the old probe accidentally enqueued the previous command again.
        reply_length = tx_len;
        if (reply_length < 38 || reply_length > 1080) begin $error("reply length %d",reply_length); $stop; end
        for (int b=0;b<reply_length;b++) begin
            if(b%5==2) begin @(negedge rx_clk);tx_req=1'b0;repeat(3)@(negedge rx_clk);end
            @(negedge rx_clk); tx_req = 1'b1;
            @(posedge rx_clk); #1; reply[b] = tx_data;
        end
        @(negedge rx_clk); tx_req = 1'b0; tx_done = 1'b1;
        @(negedge rx_clk); tx_done = 1'b0;
        crc=32'hffffffff;
        for (int b=2;b<reply_length-6;b++) crc=crc_byte(crc,reply[b]);
        crc=~crc;
        observed={reply[reply_length-6],reply[reply_length-5],reply[reply_length-4],reply[reply_length-3]};
        if (reply[0] !== 8'h55 || reply[1] !== 8'haa || reply[3] !== (kind|8'h80) || observed !== crc ||
            reply[reply_length-2] !== 8'haa || reply[reply_length-1] !== 8'h55 ||
            {reply[4],reply[5],reply[6],reply[7]} !== identity ||
            {reply[12],reply[13],reply[14],reply[15]} !== sequence_id) begin
            $error("RPC header/CRC mismatch kind=%h crc=%h expected=%h",kind,observed,crc); $stop;
        end
        repeat (6) @(negedge rx_clk);
    endtask
    task automatic check_status(input byte unsigned expected);
        if (reply[16] !== expected) begin $error("RPC status expected=%d actual=%d state=%d",expected,reply[16],reply[17]); $stop; end
    endtask
    task automatic compare_result(input string name,input string filename,input int unsigned base,input int size,input int unsigned identity);
        int length, limit;
        $readmemh({case_folder,filename},golden_mem,0,size-1);
        for (int b=0;b<size;b++) if (get_byte(base+b) !== golden_mem[b]) begin
            $error("DDR Golden %s/%s byte=%0d expected=%h actual=%h cycle=%0d",name,filename,b,golden_mem[b],get_byte(base+b),cycle); $stop;
        end
        if(name.substr(0,4)=="move_")
            for(int b=size;b<((size+31)&~31);b++)if(get_byte(base+b)!==8'ha5)begin
                $error("partial write guard %s byte=%0d actual=%h",name,b,get_byte(base+b));$stop;
            end
        if(AUTONOMOUS) return; // 整卷未释放前仅允许结果区READ；特征已逐字节检查。
        // DDR始终逐字节全量Golden比对；大于16KiB时RPC另查首尾包。
        limit = size > 16384 ? 1024 : size;
        for (int offset=0;offset<limit;offset+=1024) begin
            length = size-offset < 1024 ? ((size-offset+31)&~31) : 1024;
            put32(0,base+offset); request[4]=8'(length);request[5]=8'(length>>8);request[6]=8'd0;request[7]=8'd0;
            rpc(8'h23,identity,8);check_status(8'd0);
            if (reply_length !== length+38) begin $error("READ size mismatch");$stop;end
            for(int b=0;b<length && offset+b<size;b++) if(reply[32+b] !== golden_mem[offset+b]) begin
                $error("RPC Golden %s byte=%0d expected=%h actual=%h",name,offset+b,golden_mem[offset+b],reply[32+b]);$stop;
            end
        end
        if(size>16384) begin
            put32(0,base+size-1024);request[4]=8'd0;request[5]=8'd4;request[6]=8'd0;request[7]=8'd0;
            rpc(8'h23,identity,8);check_status(8'd0);
            for(int b=0;b<1024;b++) if(reply[32+b] !== golden_mem[size-1024+b]) begin $error("READ final packet %s",name);$stop;end
        end
    endtask

    initial begin : regression
        integer cases_fd, uploads_fd, got;
        string name, filename;
        int result_size, mac_size, input_size, passed, polls;
        int unsigned input_addr, identity;
        passed=0;
        if ($value$plusargs("CASE_LIST=%s",case_list)) $display("[REGRESSION] %s",case_list);
        repeat(8) @(negedge ui_clk);rst_n=1'b1; wait(compute_rst_n); repeat(8) @(negedge rx_clk);
        repeat(12) @(negedge rx_clk);
        if(VOLUME_ONLY)begin
            image_ready=1'b1;image_base=31'h00400000;image_slices=32'd2;
            for(integer b=0;b<96;b=b+1)memory_bytes[32'h08200000+b]=8'd0;
            memory_bytes[32'h08200000]=8'hff;
            for(integer b=0;b<32;b=b+1)memory_bytes[32'h10000000+b]=8'(b);
            for(integer b=0;b<64;b=b+1)request[b]=8'd0;
            put32(0,32'h314c4f56);put32(4,32'd1);put32(8,32'h08200000);put32(12,32'd1);
            put32(16,32'h00400000);put32(20,32'd2);put32(24,32'h10000000);put32(28,32'd1048576);
            rpc(8'h26,32'd200,64);check_status(8'd0);
            rpc(8'h26,32'd200,64);check_status(8'd0);
            do begin rpc(8'h27,32'd200,0);check_status(8'd0);end while(reply[17]===8'd1);
            if(reply[17]!==8'd2||{reply[23],reply[22],reply[21],reply[20]}!==32'd200)begin $error("volume identity/state");$stop;end
            if(reply_length!==134||{reply[35],reply[34],reply[33],reply[32]}!==32'h34474456||
               {reply[59],reply[58],reply[57],reply[56]}==32'd0||
               {reply[43],reply[42],reply[41],reply[40]}!=32'd0||
               {reply[47],reply[46],reply[45],reply[44]}!=32'd0||
               {reply[79],reply[78],reply[77],reply[76]}!=32'd0||
               {reply[75],reply[74],reply[73],reply[72]}!=32'd0||
               {reply[95],reply[94],reply[93],reply[92]}!=32'd0)begin
                $error("volume QUERY VDG4 length=%0d fetch=%0d reads=%0d writes=%0d kind4_hi=%0d kind4_lo=%0d responses=%0d",
                    reply_length,{reply[59],reply[58],reply[57],reply[56]},
                    {reply[43],reply[42],reply[41],reply[40]},{reply[47],reply[46],reply[45],reply[44]},
                    {reply[79],reply[78],reply[77],reply[76]},{reply[75],reply[74],reply[73],reply[72]},
                    {reply[95],reply[94],reply[93],reply[92]});$stop;
            end
            put32(0,32'h10000000);request[4]=8'd32;request[5]=8'd0;request[6]=8'd0;request[7]=8'd0;
            rpc(8'h23,32'd200,8);check_status(8'd0);
            for(integer b=0;b<32;b=b+1)if(reply[32+b]!==8'(b))begin $error("volume wire READ byte=%0d",b);$stop;end
            rpc(8'h29,32'd200,0);check_status(8'd0);
            rpc(8'h28,32'd200,0);check_status(8'd0);rpc(8'h28,32'd200,0);check_status(8'd0);
            rpc(8'h27,32'd200,0);check_status(8'd6);
            $display("[TB PASSED] VOL1 transport CDC START QUERY READ ABORT RELEASE CRC; empty-list control test");$fclose(csv);$finish;
        end
        // 参数区 WRITE 被拒绝，且不能发往 DDR。
        put32(0,32'h00100000);request[4]=8'd32;request[5]=8'd0;request[6]=8'd0;request[7]=8'd0;
        for(int b=8;b<40;b++)request[b]=8'h5a;
        rpc(8'h20,32'd0,40);check_status(8'd3);
        if(ddr_writes!==0)begin $error("ROM write leaked to DDR");$stop;end
        $display("[CASE PASS] read_only_coefficients");
        // 快速覆盖新增图像描述快照：在线RUN因ready/切片数/基址不匹配被拒绝，不能启动DDR。
        for(int b=0;b<64;b++)request[b]=8'd0;
        request[0]=8'd1;request[1]=8'd1;request[2]=8'd3;request[3]=8'd16;
        request[5]=8'd2;request[7]=8'd2;request[8]=8'd1;request[10]=8'd24;
        put32(16,32'h10000000);put32(24,32'h18000000);
        put32(32,32'h00100000);put32(36,32'h00100100);put32(40,32'd2);
        image_ready=1'b0;image_slices=32'd2;put32(48,32'hf0000001);
        rpc(8'h21,32'hf0000001,64);check_status(8'd5);
        image_ready=1'b1;image_slices=32'd3;put32(48,32'hf0000002);
        rpc(8'h21,32'hf0000002,64);check_status(8'd5);
        if(dut.image_ready_r!==1'b1 || dut.image_slices_r!==32'd3 || dut.image_base_r!==31'h10000000)begin
            $error("image metadata snapshot mismatch cycle=%0d",cycle);$stop;
        end
        image_slices=32'd2;put32(16,32'h10040000);put32(48,32'hf0000003);
        rpc(8'h21,32'hf0000003,64);check_status(8'd5);
        if(ddr_reads!==0 || ddr_writes!==0 || rom_reads!==0 || claim!==1'b0)begin
            $error("rejected online descriptor started an engine transaction");$stop;
        end
        image_ready=1'b0;image_slices=32'd0;
        $display("[CASE PASS] image_metadata_snapshot_and_online_rejection");
        // 新增布局/权重描述必须在计算前拒绝，不允许产生DDR事务。
        for (int test_id=0;test_id<6;test_id++) begin
            for (int b=0;b<64;b++) request[b]=8'd0;
            request[0]=8'd8; request[4]=8'd1; request[6]=8'd1; request[8]=8'd1;
            put32(16,32'h03000000); put32(24,32'h06000000);
            put32(32,32'h00100000); put32(36,32'h00100100);
            put32(48,32'hf1000000+32'(test_id));
            case(test_id)
                0: request[8]=8'd0;
                1: request[8]=8'd33;
                2: put32(32,32'h00100010);
                3: put32(32,32'h081fffc0);
                4: begin request[0]=8'd1;request[1]=8'd16;request[2]=8'd16;request[3]=8'd16;end
                5: begin request[0]=8'd1;request[1]=8'd20;request[2]=8'd16;request[3]=8'd17;end
                default: ;
            endcase
            rpc(8'h21,32'hf1000000+32'(test_id),64);check_status(8'd2);
        end
        if(ddr_reads!==0 || ddr_writes!==0 || rom_reads!==0) begin
            $error("invalid DW/P16 descriptor started memory transaction");$stop;
        end
        $display("[CASE PASS] DW_P16_descriptor_rejection cases=6");
        // 每个合法上传长度均跨真实官方宽度转换 RAM；长包后换短包，检查陈旧字节泄漏。
        for (int n=1024;n>=32;n-=32) begin
            put32(0,32'h09000000); request[4]=8'(n); request[5]=8'(n>>8); request[6]=8'd0;request[7]=8'd0;
            for(int b=0;b<n;b++) request[8+b]=8'(b*13+n/32);
            rpc(8'h20,32'd0,n+8);check_status(8'd0);
            for(int b=0;b<n;b++) if(get_byte(32'h09000000+b) !== 8'(b*13+n/32)) begin $error("UPLOAD byte=%0d len=%0d expected=%h actual=%h",b,n,8'(b*13+n/32),get_byte(32'h09000000+b));$fflush(csv);$stop;end
            put32(0,32'h09000000);request[4]=8'(n);request[5]=8'(n>>8);request[6]=8'd1;request[7]=8'd0;
            rpc(8'h23,32'd0,8);check_status(8'd0);
            if(reply_length !== n+38) begin $error("READ frame length n=%0d",n);$stop;end
            for(int b=0;b<n;b++) if(reply[32+b] !== 8'(b*13+n/32)) begin $error("READ byte=%0d len=%0d",b,n);$stop;end
        end
        for(int t=0;t<4;t++) begin
            put32(0,32'h09000000);request[4]=8'(t==0?0:t==1?31:t==2?33:1056);request[5]=8'((t==3?1056:0)>>8);request[6]=8'd1;request[7]=8'd0;
            rpc(8'h23,32'd0,8);check_status(8'd2);
        end
        rpc(8'h22,32'd0,1);check_status(8'd2);
        rpc(8'h24,32'h12345678,0);check_status(8'd6);
        rpc(8'h25,32'h12345678,0);check_status(8'd6);
        $display("[CASE PASS] RPC_RAM all_32_lengths upload_read_backpressure invalid_lengths control_errors");
        cases_fd=$fopen(case_list,"r");
        if(!cases_fd)$fatal(1,"missing cases.txt");
        while(!$feof(cases_fd)) begin
            got=$fscanf(cases_fd,"%s %d %d\n",name,result_size,mac_size);
            if(got==3) begin
                $display("[CASE] %s cycle=%0d",name,cycle);
                case_folder = {VECTOR_DIR,name,"/"};
                if(name.substr(0,5)=="stall_") case_folder={"sim/xsim/tests/volume_stall_20261025/vectors/",name,"/"};
                if(name=="lobe_e1.expand" || name=="tumor_d3.expand" || name=="tumor_head") case_folder="sim/xsim/tests/pw_doublebuffer/vectors/";
                if(name=="lobe_e1.expand" || name=="tumor_d3.expand" || name=="tumor_head") case_folder={case_folder,name,"/"};
                if (name=="upsample" || name=="concat" || name=="fused_dw11" || name=="pw_tail_clear")
                    case_folder={"sim/xsim/tests/rtl_slim_batch2/vectors/",name,"/"};
                if(name.substr(0,4)=="move_") case_folder={"sim/xsim/tests/move_clock/vectors/",name,"/"};
                if(name=="tumor_head") case_folder="sim/xsim/tests/p8p16_pending/vectors/rpc_tumor_head/";
                $readmemh({case_folder,"descriptor.hex"},descriptor_mem);
                identity=desc32(48);
                if (identity==32'd0) begin
                    identity=32'h6e000001+32'(passed);
                    for(int b=0;b<4;b++) descriptor_mem[48+b]=identity[b*8 +: 8];
                end
                image_ready=descriptor_mem[1][0];image_slices=desc32(40);
                uploads_fd=$fopen({case_folder,"uploads.txt"},"r");
                if(!uploads_fd)$fatal(1,"missing uploads %s",name);
                while(!$feof(uploads_fd)) begin
                    got=$fscanf(uploads_fd,"%h %d %s\n",input_addr,input_size,filename);
                    if(got==3) begin
                        if (filename.substr(1,1)==":") $readmemh(filename,file_mem,0,input_size-1);
                        else if(name=="lobe_e1.expand" || name=="tumor_d3.expand" || name=="tumor_head") $readmemh({"sim/xsim/tests/pw_doublebuffer/vectors/",filename},file_mem,0,input_size-1); else $readmemh({VECTOR_DIR,filename},file_mem,0,input_size-1);
                        // 此边界模拟已验证 BIN 上传完成后的 DDR 内容，不替换 DUT 内部信号。
                        for(int b=0;b<input_size;b++)memory_bytes[input_addr+b]=file_mem[b];
                    end
                end
                $fclose(uploads_fd);
                if(name=="lobe_mid_mix")begin
                    $readmemh({VECTOR_DIR,"lobe_mid_dw3/golden.hex"},file_mem,0,8191);
                    for(int b=0;b<8192;b++)memory_bytes[32'h03200000+b]=file_mem[b];
                    $readmemh({VECTOR_DIR,"lobe_mid_dw5/golden.hex"},file_mem,0,8191);
                    for(int b=0;b<8192;b++)memory_bytes[32'h03300000+b]=file_mem[b];
                end
                if(name=="lobe_mid_out")begin
                    $readmemh({VECTOR_DIR,"lobe_mid_skip/golden.hex"},file_mem,0,8191);
                    for(int b=0;b<8192;b++)memory_bytes[32'h03600000+b]=file_mem[b];
                end
                repeat(8) @(negedge ui_clk);
                if(name.substr(0,4)=="move_")
                    for(int b=result_size;b<((result_size+31)&~31);b++)memory_bytes[desc32(24)+b]=8'ha5;
                for(int b=0;b<64;b++)request[b]=descriptor_mem[b];
                run_read_bytes=read_bytes; run_reads=ddr_reads;
                if(AUTONOMOUS) begin
                    // 前置Shuffle把输入写到op11特征区，覆盖跨算子FENCE与缓存相关。
                    for(int b=0;b<288;b++)memory_bytes[32'h08200000+b]=8'd0;
                    memory_bytes[32'h08200000]=8'd1;
                    if(name.substr(0,10)=="stall_lobe_")begin
                        $readmemh({case_folder,"prefix_descriptor.hex"},prefix_descriptor);
                        for(int b=0;b<64;b++)memory_bytes[32'h08200020+b]=prefix_descriptor[b];
                    end else begin
                        for(int b=0;b<64;b++)memory_bytes[32'h08200020+b]=descriptor_mem[b];
                        memory_bytes[32'h08200020]=8'd7;
                        for(int b=0;b<4;b++)begin
                            memory_bytes[32'h08200030+b]=8'((32'h0a000000)>>(b*8));
                            memory_bytes[32'h08200038+b]=8'((32'h0a400000)>>(b*8));
                        end
                        for(int b=0;b<result_size;b+=16)
                            for(int lane=0;lane<8;lane++)begin
                                memory_bytes[32'h0a000000+b+lane]=get_byte(32'h0a400000+b+2*lane);
                                memory_bytes[32'h0a000000+b+lane+8]=get_byte(32'h0a400000+b+2*lane+1);
                            end
                    end
                    memory_bytes[32'h08200060]=8'd1;
                    for(int b=0;b<64;b++)memory_bytes[32'h08200080+b]=descriptor_mem[b];
                    memory_bytes[32'h082000c0]=8'hff;
                    image_ready=1'b1;image_base=31'h00400000;image_slices=32'd1;
                    for(int b=0;b<64;b++)request[b]=8'd0;
                    put32(0,32'h314c4f56);put32(4,32'd1);put32(8,32'h08200000);put32(12,32'd3);
                    put32(16,32'h00400000);put32(20,32'd1);put32(24,32'h10000000);put32(28,32'd524288);
                    rpc(8'h26,identity,64);check_status(8'd0);
                end else begin rpc(8'h21,identity,64);check_status(8'd0);end
                if(FAST && name=="move_up_256") begin : pause_phy_clock
                    longint unsigned cycles_before, accepted_before;
                    wait(dut.u_service.u_operator.u_engine.busy_o);
                    @(negedge rx_clk);rx_enable=1'b0;
                    @(negedge compute_clk);
                    cycles_before=hardware_cycles;accepted_before=perf_reference[3];
                    repeat(1000)@(negedge compute_clk);
                    if(clock_locked!==1'b1 || compute_rst_n!==1'b1 ||
                       hardware_cycles-cycles_before!==64'd1000 || perf_reference[3]<=accepted_before)begin
                        $error("RX pause blocked compute cycles=%0d inputs=%0d",hardware_cycles-cycles_before,perf_reference[3]-accepted_before);$stop;
                    end
                    $display("[CASE PASS] RX_clock_paused compute_cycles=%0d accepted_inputs=%0d",hardware_cycles-cycles_before,perf_reference[3]-accepted_before);
                    rx_enable=1'b1;
                end
                polls=0;
                do begin
                    repeat(1000)@(negedge ui_clk);
                    rpc(AUTONOMOUS ? 8'h27 : 8'h22,identity,0);check_status(8'd0);polls++;
                    if(AUTONOMOUS && (reply_length!==134 || {reply[35],reply[34],reply[33],reply[32]}!==32'h34474456))begin
                        $error("QUERY debug payload length/magic");$stop;
                    end
                    if(reply[17]===8'd3)begin $error("operator failed %s",name);$stop;end
                    if(polls>12000)$fatal(1,"case watchdog %s",name);
                end while(reply[17]!==8'd2);
                if(!AUTONOMOUS && ({reply[27],reply[26],reply[25],reply[24]}!==32'(result_size) ||
                   {reply[31],reply[30],reply[29],reply[28]}!==32'(mac_size)))begin $error("result size %s",name);$stop;end
                if(AUTONOMOUS && {reply[31],reply[30],reply[29],reply[28]}!==32'd3)begin $error("volume command count");$stop;end
                if(AUTONOMOUS && ({reply[51],reply[50],reply[49],reply[48]}==32'd0 ||
                   {reply[55],reply[54],reply[53],reply[52]}==32'd0 ||
                   {reply[59],reply[58],reply[57],reply[56]}==32'd0 ||
                   {reply[63],reply[62],reply[61],reply[60]}==32'd0))begin
                    $error("volume cycle counters missing fetch=%0d operator=%0d gather=%0d classify=%0d",
                        {reply[51],reply[50],reply[49],reply[48]},{reply[55],reply[54],reply[53],reply[52]},
                        {reply[59],reply[58],reply[57],reply[56]},{reply[63],reply[62],reply[61],reply[60]});$stop;
                end
                if ((descriptor_mem[0] == 8'd8 || descriptor_mem[0] == 8'd9 || descriptor_mem[1][4]) && reply[19] !== 8'd5) begin
                    $error("P16 INT32 format not reported %s format=%d",name,reply[19]); $stop;
                end
                compare_result(name,"golden.hex",desc32(24),result_size,identity);
                if(AUTONOMOUS && name.substr(0,10)=="stall_lobe_")
                    compare_result(name,"expanded.hex",desc32(16),result_size,identity);
                if(mac_size>0)compare_result(name,"mac.hex",desc32(28),mac_size,identity);
                rpc(AUTONOMOUS ? 8'h28 : 8'h24,identity,0);check_status(8'd0);
                $display("[TIMING] %s hardware_cycles=%0d read_bursts=%0d read_bytes=%0d",name,hardware_cycles,ddr_reads-run_reads,read_bytes-run_read_bytes);
`ifndef CONTINUOUS_BASELINE
                if(!AUTONOMOUS) begin
                    longint unsigned expected_cycles, observed_cycles;
                    int reads_before;
                    expected_cycles=hardware_cycles;
                    reads_before=ddr_reads;
                    put32(0,32'h1fff0000+((identity & 63)*256));
                    request[4]=8'd0;request[5]=8'd1;request[6]=8'd1;request[7]=8'd0;
                    rpc(8'h23,32'd0,8);check_status(8'd0);
                    if ({reply[35],reply[34],reply[33],reply[32]} !== 32'h4650504f ||
                        {reply[47],reply[46],reply[45],reply[44]} !== 32'(identity) ||
                        {reply[55],reply[54],reply[53],reply[52]} !== (FAST ? 32'd250000000 : 32'd125000000)) begin
                        $error("profiler header/id mismatch %s",name);$stop;
                    end
                    observed_cycles=64'd0;
                    for(int b=0;b<8;b++) observed_cycles[b*8 +: 8]=reply[64+b];
                    if(observed_cycles !== expected_cycles || expected_cycles === 64'd0 || ddr_reads !== reads_before) begin
                        $error("profiler data mismatch %s expected=%0d actual=%0d",name,expected_cycles,observed_cycles);$stop;
                    end
                    for(int p=0;p<16;p++)begin
                        observed_cycles=64'd0;
                        for(int b=0;b<8;b++) observed_cycles[b*8 +: 8]=reply[64+p*8+b];
                        if(observed_cycles !== perf_reference[p])begin
                            $error("pipelined counter mismatch %s index=%0d expected=%0d actual=%0d",name,p,perf_reference[p],observed_cycles);$stop;
                        end
                    end
                    if(descriptor_mem[0]==8'd2 || descriptor_mem[0]==8'd5 || descriptor_mem[0]==8'd10)begin
                        int unsigned expected_inputs;
                        expected_inputs=int'({descriptor_mem[5],descriptor_mem[4]}) *
                                        int'({descriptor_mem[7],descriptor_mem[6]}) *
                                        (int'({descriptor_mem[9],descriptor_mem[8]}) +
                                         (descriptor_mem[0]==8'd5 ? int'({descriptor_mem[15],descriptor_mem[14]}) : 0));
                        if(perf_reference[3]!==64'(expected_inputs) || perf_reference[4]!==64'(result_size/16))begin
                            $error("move transaction count %s expected_in=%0d actual_in=%0d expected_out=%0d actual_out=%0d",name,
                                   expected_inputs,perf_reference[3],result_size/16,perf_reference[4]);$stop;
                        end
                    end
                    $display("[PERF] %s hardware_cycles=%0d load=%0d run=%0d output_blocked=%0d",name,
                        expected_cycles,dut.u_service.u_operator.u_engine.perf_data_o[127:64],
                        dut.u_service.u_operator.u_engine.perf_data_o[191:128],dut.u_service.u_operator.u_engine.perf_data_o[511:448]);
                end
`endif
                passed++;
                $display("[CASE PASS] %s bytes=%0d mac_bytes=%0d cycle=%0d",name,result_size,mac_size,cycle);
            end
        end

        $fclose(cases_fd);$fclose(csv);
        $display("[TB PASSED] 全部数据验证一致 cases=%0d cycles=%0d rom_reads=%0d ddr_reads=%0d ddr_writes=%0d",passed,cycle,rom_reads,ddr_reads,ddr_writes);
        $finish;
    end
endmodule

module tb_volume_board;
    tb_volume_rpc #(.VOLUME_ONLY(1'b1)) test();
endmodule
