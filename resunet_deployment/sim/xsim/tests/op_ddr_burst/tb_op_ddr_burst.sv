`timescale 1ns/1ps
`include "counts.svh"
// 【文件类型：.sv】实际CDC+DDR端口+AXI Master，与原32B通路逐字节差分。
// 黄金字节由Python导出；这里只模拟AXI握手、存储、反压、错误及完成屏障。
module ddr_burst_path #(parameter bit OPTIMIZED = 1'b1) (
    input logic compute_clk,
    input logic ui_clk,
    input logic reset_n,
    output logic finished = 1'b0,
    output integer elapsed_cycles = 0,
    output integer read_bursts = 0,
    output integer write_bursts = 0,
    output integer read_bytes = 0,
    output integer write_bytes = 0,
    output integer overlap_cycles = 0,
    output integer prefetch_starts = 0
);
    localparam string VECTOR_DIR = "sim/xsim/tests/op_ddr_burst/";
    logic local_reset_n = 1'b1;
    wire rst_n = reset_n && local_reset_n;
    logic req_valid = 1'b0, req_ready, req_write = 1'b0;
    logic [30:0] req_addr = 31'd0;
    logic [255:0] req_data = 256'd0;
    logic [31:0] req_mask = 32'd0;
    logic rsp_valid, rsp_ready = 1'b0, rsp_error;
    logic [255:0] rsp_data;
    logic ui_req, ui_ready, ui_write, ui_rsp, ui_rsp_ready, ui_error, cdc_active, port_active;
    logic [30:0] ui_addr;
    logic [255:0] ui_data, ui_rsp_data;
    logic [31:0] ui_mask;
    logic cache_clear = 1'b0;
    logic wr_start, wr_ready, wr_done, wr_error, wr_re, wr_empty;
    logic rd_start, rd_ready, rd_done, rd_error, rd_we, rd_full;
    logic [30:0] wr_addr, rd_addr;
    logic [31:0] wr_len, rd_len;
    logic [255:0] wr_data, rd_data;
    logic [31:0] awaddr, araddr;
    logic [7:0] awlen, arlen;
    logic [2:0] awsize, arsize;
    logic [1:0] awburst, arburst;
    logic awvalid, awready, wvalid, wready, wlast, bvalid = 1'b0, bready;
    logic arvalid, arready, rvalid = 1'b0, rready, rlast = 1'b0;
    logic [255:0] wdata, rdata = 256'd0;
    logic [31:0] wstrb;
    logic [1:0] bresp = 2'b00, rresp = 2'b00;
    logic [7:0] memory[0:262143], expected_memory[0:262143];
    logic [329:0] stimulus[0:`DDR_TRANSACTIONS-1];
    logic [255:0] golden[0:`DDR_TRANSACTIONS-1];
    integer cycle = 0, current_test = -1, current_phase = 0;
    integer write_left = 0, read_left = 0, b_delay = 0, r_delay = 0;
    integer write_address = 0, read_address = 0;
    logic write_active = 1'b0, read_active = 1'b0, b_pending = 1'b0;
    logic inject_b_error = 1'b0, inject_r_error = 1'b0, read_fault = 1'b0;
    logic w_stalled = 1'b0, rsp_stalled = 1'b0;
    logic [288:0] held_w;
    logic [256:0] held_rsp;
    integer csv;

    op_mem_cdc cdc (
        .compute_clk_i(compute_clk), .compute_rst_n_i(rst_n), .ui_clk_i(ui_clk), .ui_rst_n_i(rst_n),
        .req_valid_i(req_valid), .req_ready_o(req_ready), .req_write_i(req_write), .req_addr_i(req_addr),
        .req_data_i(req_data), .req_mask_i(req_mask), .rsp_valid_o(rsp_valid), .rsp_ready_i(rsp_ready),
        .rsp_data_o(rsp_data), .rsp_error_o(rsp_error), .active_ui_o(cdc_active),
        .ui_req_valid_o(ui_req), .ui_req_ready_i(ui_ready), .ui_req_write_o(ui_write), .ui_req_addr_o(ui_addr),
        .ui_req_data_o(ui_data), .ui_req_mask_o(ui_mask), .ui_rsp_valid_i(ui_rsp), .ui_rsp_ready_o(ui_rsp_ready),
        .ui_rsp_data_i(ui_rsp_data), .ui_rsp_error_i(ui_error)
    );
    generate if (OPTIMIZED) begin : g_new
        op_ddr_port port (
            .clk_i(ui_clk), .rst_n_i(rst_n), .cache_clear_i(cache_clear),
            .req_valid_i(ui_req), .req_ready_o(ui_ready), .req_write_i(ui_write), .req_addr_i(ui_addr),
            .req_data_i(ui_data), .req_mask_i(ui_mask), .rsp_valid_o(ui_rsp), .rsp_ready_i(ui_rsp_ready),
            .rsp_data_o(ui_rsp_data), .rsp_error_o(ui_error), .active_o(port_active),
            .wr_start_o(wr_start), .wr_addr_o(wr_addr), .wr_len_o(wr_len), .wr_ready_i(wr_ready),
            .wr_done_i(wr_done), .wr_error_i(wr_error), .wr_fifo_re_i(wr_re),
            .wr_fifo_empty_o(wr_empty), .wr_fifo_data_o(wr_data),
            .rd_start_o(rd_start), .rd_addr_o(rd_addr), .rd_len_o(rd_len), .rd_ready_i(rd_ready),
            .rd_done_i(rd_done), .rd_error_i(rd_error), .rd_fifo_we_i(rd_we),
            .rd_fifo_data_i(rd_data), .rd_fifo_full_o(rd_full)
        );
        always @(posedge ui_clk)
            if (rst_n && port.prefetch_start_w) prefetch_starts <= prefetch_starts + 1;
    end else begin : g_old
        op_ddr_port_baseline port (
            .clk_i(ui_clk), .rst_n_i(rst_n),
            .req_valid_i(ui_req), .req_ready_o(ui_ready), .req_write_i(ui_write), .req_addr_i(ui_addr),
            .req_data_i(ui_data), .req_mask_i(ui_mask), .rsp_valid_o(ui_rsp), .rsp_ready_i(ui_rsp_ready),
            .rsp_data_o(ui_rsp_data), .rsp_error_o(ui_error), .active_o(port_active),
            .wr_start_o(wr_start), .wr_addr_o(wr_addr), .wr_len_o(wr_len), .wr_ready_i(wr_ready),
            .wr_done_i(wr_done), .wr_error_i(wr_error), .wr_fifo_re_i(wr_re),
            .wr_fifo_empty_o(wr_empty), .wr_fifo_data_o(wr_data),
            .rd_start_o(rd_start), .rd_addr_o(rd_addr), .rd_len_o(rd_len), .rd_ready_i(rd_ready),
            .rd_done_i(rd_done), .rd_error_i(rd_error), .rd_fifo_we_i(rd_we),
            .rd_fifo_data_i(rd_data), .rd_fifo_full_o(rd_full)
        );
    end endgenerate
    aq_axi_master master (
        .ACLK(ui_clk), .ARESETN(rst_n), .MASTER_RST(1'b0),
        .M_AXI_AWADDR(awaddr), .M_AXI_AWLEN(awlen), .M_AXI_AWSIZE(awsize), .M_AXI_AWBURST(awburst),
        .M_AXI_AWVALID(awvalid), .M_AXI_AWREADY(awready), .M_AXI_WDATA(wdata), .M_AXI_WSTRB(wstrb),
        .M_AXI_WLAST(wlast), .M_AXI_WVALID(wvalid), .M_AXI_WREADY(wready),
        .M_AXI_BID(1'b0), .M_AXI_BUSER(1'b0), .M_AXI_BRESP(bresp), .M_AXI_BVALID(bvalid), .M_AXI_BREADY(bready),
        .M_AXI_ARADDR(araddr), .M_AXI_ARLEN(arlen), .M_AXI_ARSIZE(arsize), .M_AXI_ARBURST(arburst),
        .M_AXI_ARVALID(arvalid), .M_AXI_ARREADY(arready), .M_AXI_RID(1'b0), .M_AXI_RUSER(1'b0),
        .M_AXI_RDATA(rdata), .M_AXI_RRESP(rresp), .M_AXI_RLAST(rlast), .M_AXI_RVALID(rvalid), .M_AXI_RREADY(rready),
        .WR_START(wr_start), .WR_ADRS({1'b0,wr_addr}), .WR_LEN(wr_len), .WR_READY(wr_ready),
        .WR_FIFO_RE(wr_re), .WR_FIFO_EMPTY(wr_empty), .WR_FIFO_DATA(wr_data), .WR_DONE(wr_done), .WR_ERR(wr_error),
        .RD_START(rd_start), .RD_ADRS({1'b0,rd_addr}), .RD_LEN(rd_len), .RD_READY(rd_ready),
        .RD_FIFO_WE(rd_we), .RD_FIFO_FULL(rd_full), .RD_FIFO_DATA(rd_data), .RD_DONE(rd_done), .RD_ERR(rd_error)
    );

    function automatic logic [255:0] load_word(input integer address);
        logic [255:0] word_data;
        for (int b=0; b<32; b++) word_data[b*8 +: 8] = memory[address+b];
        return word_data;
    endfunction
    assign awready = !write_active && !b_pending && !bvalid && cycle % 7 != 0;
    assign wready = write_active && cycle % 5 != 0;
    assign arready = !read_active && !rvalid && cycle % 11 != 0;
    always @(posedge ui_clk) begin
        cycle <= cycle + 1;
        if (!rst_n) begin
            write_active <= 1'b0; read_active <= 1'b0; b_pending <= 1'b0;
            bvalid <= 1'b0; rvalid <= 1'b0; w_stalled <= 1'b0;
        end else begin
            if (w_stalled && (wvalid !== 1'b1 || {wdata,wstrb,wlast} !== held_w)) begin
                $error("AXI W changed under backpressure optimized=%b cycle=%0d",OPTIMIZED,cycle); $stop;
            end
            w_stalled <= wvalid && !wready; held_w <= {wdata,wstrb,wlast};
            if (awvalid && awready) begin
                if (awsize !== 3'd5 || awburst !== 2'b01 || awaddr[4:0] !== 5'd0 ||
                    int'(awaddr[11:0]) + (int'(awlen)+1)*32 > 4096) begin
                    $error("invalid AXI AW addr=%h len=%0d",awaddr,awlen); $stop;
                end
                write_address <= awaddr; write_left <= int'(awlen)+1; write_active <= 1'b1;
                write_bursts <= write_bursts + 1; write_bytes <= write_bytes + (int'(awlen)+1)*32;
            end
            if (wvalid && wready) begin
                if (wlast !== (write_left == 1) || wstrb !== 32'hffffffff) begin
                    $error("AXI write beat mismatch optimized=%b cycle=%0d left=%0d last=%b",OPTIMIZED,cycle,write_left,wlast); $stop;
                end
                for (int b=0; b<32; b++) memory[write_address+b] <= wdata[b*8 +: 8];
                write_address <= write_address+32; write_left <= write_left-1;
                if (write_left == 1) begin
                    write_active <= 1'b0; b_pending <= 1'b1; b_delay <= 64;
                    bresp <= inject_b_error ? 2'b10 : 2'b00; inject_b_error <= 1'b0;
                end
            end
            if (b_pending) begin
                if (b_delay == 0) begin bvalid <= 1'b1; b_pending <= 1'b0; end
                else b_delay <= b_delay-1;
            end
            if (bvalid && bready) bvalid <= 1'b0;
            if (arvalid && arready) begin
                if (arsize !== 3'd5 || arburst !== 2'b01 || araddr[4:0] !== 5'd0 ||
                    int'(araddr[11:0]) + (int'(arlen)+1)*32 > 4096) begin
                    $error("invalid AXI AR addr=%h len=%0d",araddr,arlen); $stop;
                end
                read_address <= araddr; read_left <= int'(arlen)+1; read_active <= 1'b1; r_delay <= 12;
                read_fault <= inject_r_error; inject_r_error <= 1'b0;
                read_bursts <= read_bursts+1; read_bytes <= read_bytes+(int'(arlen)+1)*32;
            end
            if (read_active && r_delay > 0) r_delay <= r_delay-1;
            if (rvalid && rready) begin
                rvalid <= 1'b0; read_address <= read_address+32; read_left <= read_left-1;
                if (rlast) read_active <= 1'b0;
            end
            if (read_active && (!rvalid || rready) && !(rvalid && rlast) && r_delay == 0 && cycle % 4 != 0) begin
                rvalid <= 1'b1;
                rdata <= load_word(read_address + (rvalid ? 32 : 0));
                rlast <= read_left == (rvalid ? 2 : 1);
                rresp <= read_fault ? 2'b10 : 2'b00;
            end
            if (read_active && (write_active || b_pending || bvalid)) overlap_cycles <= overlap_cycles+1;
        end
        if (!finished) $fdisplay(csv,"%0d,%0d,%0d,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b",cycle,current_phase,current_test,
            ui_req,ui_ready,ui_write,ui_rsp,ui_rsp_ready,awvalid,awready,wvalid,wready,arvalid,arready,bvalid,rvalid);
    end
    always @(posedge compute_clk) begin
        if (!rst_n) rsp_stalled <= 1'b0;
        else begin
            if (rsp_stalled && (rsp_valid !== 1'b1 || {rsp_error,rsp_data} !== held_rsp)) begin
                $error("response changed under backpressure optimized=%b cycle=%0d",OPTIMIZED,cycle); $stop;
            end
            rsp_stalled <= rsp_valid && !rsp_ready; held_rsp <= {rsp_error,rsp_data};
        end
    end

    task automatic request(input bit is_write, input logic [30:0] address,
        input logic [31:0] mask, input logic [255:0] data,
        input integer expected_error, input logic [255:0] expected_data);
        @(negedge compute_clk); req_valid = 1'b1; req_write = is_write;
        req_addr = address; req_mask = mask; req_data = data;
        do @(posedge compute_clk); while (req_ready !== 1'b1);
        @(negedge compute_clk); req_valid = 1'b0;
        wait (rsp_valid === 1'b1);
        repeat ((current_test & 3)+1) @(negedge compute_clk);
        rsp_ready = 1'b1;
        @(posedge compute_clk);
        if ((expected_error < 2 && rsp_error !== 1'(expected_error)) || (!is_write && expected_error == 0 && rsp_data !== expected_data)) begin
            $fflush(csv);
            $error("transport mismatch opt=%b phase=%0d test=%0d addr=%h error=%b expected_error=%0d expected=%h actual=%h cycle=%0d",
                OPTIMIZED,current_phase,current_test,address,rsp_error,expected_error,expected_data,rsp_data,cycle); $stop;
        end
        if (is_write && mask == 32'd0 && (write_active || b_pending || bvalid || wr_ready !== 1'b1)) begin
            $error("fence completed before B response opt=%b cycle=%0d",OPTIMIZED,cycle); $stop;
        end
        @(negedge compute_clk); rsp_ready = 1'b0;
    endtask

    initial begin : replay
        integer started, sequence_cycle_start, sequence_ar_start;
        logic [255:0] before_reset;
        logic [30:0] sequence_address;
        csv = $fopen(OPTIMIZED ? "sim_trace.csv" : "sim_trace_baseline.csv","w");
        $fdisplay(csv,"cycle,phase,test,req,ready,write,rsp,rsp_ready,awvalid,awready,wvalid,wready,arvalid,arready,bvalid,rvalid");
        $readmemh({VECTOR_DIR,"memory_init.hex"},memory);
        $readmemh({VECTOR_DIR,"memory_golden.hex"},expected_memory);
        $readmemh({VECTOR_DIR,"stimulus.hex"},stimulus);
        $readmemh({VECTOR_DIR,"golden.hex"},golden);
        wait(rst_n === 1'b1); repeat (8) @(negedge compute_clk);
        started = cycle;
        for (int index=0; index<`DDR_TRANSACTIONS; index++) begin
            current_test = index; current_phase = stimulus[index][329:322];
            case (stimulus[index][321:319])
                3'd0: request(1'b0,stimulus[index][318:288],32'd0,256'd0,0,golden[index]);
                3'd1: request(1'b1,stimulus[index][318:288],stimulus[index][287:256],stimulus[index][255:0],0,256'd0);
                3'd2: request(1'b1,31'd0,32'd0,256'd0,0,256'd0);
                3'd3: begin
                    @(negedge ui_clk); cache_clear = 1'b1;
                    repeat (8) @(negedge ui_clk);
                    for (int b=0; b<32; b++) memory[stimulus[index][318:288]+b] = stimulus[index][b*8 +: 8];
                    @(negedge ui_clk); cache_clear = 1'b0;
                end
                default: begin $error("invalid stimulus"); $stop; end
            endcase
        end
        // 连续读取四条1KiB行，bit1提示允许后台预取下一行；尾行不触发额外预取。
        current_phase = 7; sequence_cycle_start = cycle; sequence_ar_start = read_bursts;
        for (int row=0; row<4; row++) begin
            for (int word=0; word<32; word++) begin
                current_test = 3000 + row*32 + word;
                sequence_address = 31'h24000 + 31'(row*1024 + word*32);
                request(1'b0,sequence_address,row < 3 ? 32'd6 : 32'd0,256'd0,0,load_word(sequence_address));
            end
        end
        request(1'b1,31'd0,32'd0,256'd0,0,256'd0);
        $display("[PREFETCH] optimized=%b rows=4 bursts=%0d starts=%0d cycles=%0d",
            OPTIMIZED,read_bursts-sequence_ar_start,prefetch_starts,cycle-sequence_cycle_start);
        if (OPTIMIZED && (read_bursts-sequence_ar_start != 4 || prefetch_starts != 3)) begin
            $error("sequential prefetch mismatch; expected 4 line reads and 3 prefetch starts, got %0d and %0d",
                read_bursts-sequence_ar_start,prefetch_starts); $stop;
        end
        elapsed_cycles = cycle-started;
        for (int address=0; address<262144; address++) begin
            if (memory[address] !== expected_memory[address]) begin
                $error("physical DDR/guard mismatch optimized=%b addr=%h expected=%h actual=%h",OPTIMIZED,address,expected_memory[address],memory[address]); $stop;
            end
        end
        $display("[PERF] optimized=%b transactions=%0d cycles=%0d AR=%0d AW=%0d read_bytes=%0d write_bytes=%0d overlap_cycles=%0d",
            OPTIMIZED,`DDR_TRANSACTIONS,elapsed_cycles,read_bursts,write_bursts,read_bytes,write_bytes,overlap_cycles);
        if (OPTIMIZED) begin
            if (overlap_cycles == 0) begin $error("read/write overlap was never exercised"); $stop; end
            current_phase = 6;
            inject_b_error = 1'b1;
            for (int i=0; i<32; i++) request(1'b1,31'h30000+31'(i*32),32'hffffffff,{8{32'(i)}},2,256'd0);
            request(1'b1,31'd0,32'd0,256'd0,1,256'd0);
            request(1'b1,31'd0,32'd0,256'd0,0,256'd0);
            inject_r_error = 1'b1;
            request(1'b0,31'h34000,32'd0,256'd0,1,256'd0);
            request(1'b1,31'd0,32'd0,256'd0,1,256'd0);
            request(1'b1,31'd0,32'd0,256'd0,0,256'd0);
            request(1'b0,31'h34000,32'd0,256'd0,0,load_word('h34000));
            request(1'b1,31'd0,32'd0,256'd0,0,256'd0);
            before_reset = load_word('h35000);
            request(1'b1,31'h35000,32'h0000000f,256'h12345678,0,256'd0);
            @(negedge compute_clk); local_reset_n = 1'b0;
            repeat (8) @(negedge compute_clk); local_reset_n = 1'b1;
            repeat (8) @(negedge compute_clk);
            request(1'b0,31'h35000,32'd0,256'd0,0,before_reset);
            request(1'b1,31'd0,32'd0,256'd0,0,256'd0);
            $display("[CASE PASS] deferred BRESP/RRESP errors, fence clear, reset cancellation");
            current_phase = 8;
            request(1'b0,31'h26000,32'd0,256'd0,0,load_word('h26000));
            inject_r_error = 1'b1;
            request(1'b0,31'h26020,32'd6,256'd0,0,load_word('h26020));
            wait(optimized.g_new.port.prefetch_active_r === 1'b1);
            wait(optimized.g_new.port.prefetch_active_r === 1'b0 && optimized.g_new.port.read_r == 2'd0);
            request(1'b0,31'h26400,32'd0,256'd0,1,load_word('h26400));
            request(1'b1,31'd0,32'd0,256'd0,1,256'd0);
            request(1'b1,31'd0,32'd0,256'd0,0,256'd0);
            $display("[CASE PASS] prefetched RRESP error reaches request and fence");
        end
        $fclose(csv); finished = 1'b1;
    end
endmodule

module tb_op_ddr_burst;
    logic compute_clk = 1'b0, ui_clk = 1'b0, rst_n = 1'b0;
    always #4 compute_clk = ~compute_clk;
    initial begin #0.37; forever #1.5 ui_clk = ~ui_clk; end
    wire old_done, new_done;
    wire integer old_cycles, new_cycles, old_ar, new_ar, old_aw, new_aw, old_rb, new_rb, old_wb, new_wb;
    ddr_burst_path #(.OPTIMIZED(1'b0)) baseline (
        .compute_clk(compute_clk), .ui_clk(ui_clk), .reset_n(rst_n), .finished(old_done),
        .elapsed_cycles(old_cycles), .read_bursts(old_ar), .write_bursts(old_aw), .read_bytes(old_rb), .write_bytes(old_wb)
    );
    ddr_burst_path #(.OPTIMIZED(1'b1)) optimized (
        .compute_clk(compute_clk), .ui_clk(ui_clk), .reset_n(rst_n), .finished(new_done),
        .elapsed_cycles(new_cycles), .read_bursts(new_ar), .write_bursts(new_aw), .read_bytes(new_rb), .write_bytes(new_wb)
    );
    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(0,compute_clk,ui_clk,rst_n,optimized.ui_req,optimized.ui_ready,optimized.ui_write,
            optimized.ui_rsp,optimized.awvalid,optimized.awready,optimized.wvalid,optimized.wready,
            optimized.arvalid,optimized.arready,optimized.bvalid,optimized.rvalid);
        repeat (12) @(negedge compute_clk); rst_n = 1'b1;
        wait (old_done && new_done);
        if (new_cycles >= old_cycles || new_aw >= old_aw || new_ar >= old_ar) begin
            $error("throughput acceptance failed old_cycles=%0d new_cycles=%0d old_aw=%0d new_aw=%0d old_ar=%0d new_ar=%0d",
                old_cycles,new_cycles,old_aw,new_aw,old_ar,new_ar); $stop;
        end
        $display("[TB PASSED] 全部数据验证一致 transactions=%0d speedup=%.3f old_cycles=%0d new_cycles=%0d",
            `DDR_TRANSACTIONS,real'(old_cycles)/real'(new_cycles),old_cycles,new_cycles);
        $finish;
    end
    initial begin repeat (10000000) @(posedge ui_clk); $fatal(1,"Simulation Timeout"); end
endmodule
