`timescale 1ns/1ps
// 【文件类型：.sv】实际 op_board＋ROM IP 的 XSim 自校验。
// 验证边界为原解析器的 CRC 合格帧输出及已有 DDR master 用户接口。
// 算法 Golden 来自冻结整数张量；DDR 模型只负责时序和字节存储。
module tb_fullnet;
    localparam string VECTOR_DIR = "sim/xsim/tests/fullnet/vectors/";
    string case_list = "cases_quick.txt";
    logic bounds_done = 1'b0, bounds_we = 1'b0, bounds_en = 1'b0;
    logic [12:0] bounds_wr_addr = 13'd0, bounds_rd_addr = 13'd0;
    logic [511:0] bounds_wr_data = 512'd0, bounds_rd_data;
    logic rx_clk = 1'b0, ui_clk = 1'b0, rst_n = 1'b0;
    always #4 rx_clk = !rx_clk;
    // 算子/ROM=125MHz，实际MIG UI=333.333MHz，保留异步相位关系。
    always #1.5 ui_clk = !ui_clk;
    // 独立检查同一官方 IP 的全部地址、一拍读及停读保持；不替换 DUT 缓存。
    pw_weight_uram u_bounds (
        .clka(ui_clk), .ena(bounds_we), .wea(bounds_we),
        .addra(bounds_wr_addr), .dina(bounds_wr_data),
        .clkb(ui_clk), .enb(bounds_en), .addrb(bounds_rd_addr), .doutb(bounds_rd_data)
    );
    initial begin : uram_bounds
        logic [511:0] held;
        wait(rst_n === 1'b1);
        for (int a=0; a<6144; a++) begin
            @(negedge ui_clk);
            bounds_we = 1'b1; bounds_wr_addr = 13'(a);
            bounds_wr_data = {16{32'(a) ^ 32'hc05a963c}};
        end
        @(negedge ui_clk); bounds_we = 1'b0;
        for (int a=0; a<6144; a++) begin
            @(negedge ui_clk); bounds_en = 1'b1; bounds_rd_addr = 13'(a);
            @(posedge ui_clk); #1;
            if (bounds_rd_data !== {16{32'(a) ^ 32'hc05a963c}}) begin
                $error("URAM one-cycle read mismatch address=%0d time=%t",a,$time); $stop;
            end
            if (a==4095 || a==4096 || a==6143) begin
                held = bounds_rd_data;
                @(negedge ui_clk); bounds_en = 1'b0; bounds_rd_addr = 13'd0;
                @(posedge ui_clk); #1;
                if (bounds_rd_data !== held) begin
                    $error("URAM disabled read changed address=%0d time=%t",a,$time); $stop;
                end
            end
        end
        @(negedge ui_clk); bounds_en = 1'b0; bounds_done = 1'b1;
        $display("[CASE PASS] uram_all_6144_addresses latency=1 hold=4095/4096/6143");
    end
    logic frame_valid = 1'b0, body_en = 1'b0;
    logic [7:0] msg = 8'd0, body_data = 8'd0;
    logic [31:0] run_id = 32'd0, sequence_id = 32'd0;
    logic [15:0] body_len = 16'd0, body_count = 16'd0;
    logic accept, block_rx, claim, tx_start;
    logic tx_req = 1'b0, tx_done = 1'b0;
    logic [7:0] tx_data;
    logic [15:0] tx_len;
    logic image_ready = 1'b0;
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

    op_board dut (
        .rx_clk_i(rx_clk), .ui_clk_i(ui_clk), .rx_rst_n_i(rst_n), .ui_rst_n_i(rst_n),
        .compute_rst_n_o(compute_rst_n),
        .legacy_idle_rx_i(1'b1), .storage_idle_ui_i(1'b1),
        .image_ready_rx_i(image_ready), .image_base_rx_i(31'h10000000), .image_slices_rx_i(image_slices),
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
        .clk_i(rx_clk), .rst_n_i(compute_rst_n), .req_valid_i(coeff_req), .req_ready_o(coeff_ready),
        .req_addr_i(coeff_addr), .rsp_valid_o(coeff_valid), .rsp_ready_i(coeff_rsp_ready),
        .rsp_data_o(coeff_data), .rsp_error_o(coeff_error)
    );

    // 稀疏字节 DDR；确定性暂停请求、数据和完成响应。
    byte unsigned memory_bytes [int unsigned];
    logic [31:0] random_r = 32'h20261016;
    int seed = 32'h20261016;
    initial begin
        if ($value$plusargs("SEED=%d",seed)) random_r = 32'(seed);
        $display("[SEED] %0d",seed);
    end
    always @(negedge ui_clk) random_r <= {random_r[30:0], random_r[31]^random_r[21]^random_r[1]^random_r[0]};
    int cycle = 0, rd_phase = 0, wr_phase = 0, rd_delay = 0, wr_delay = 0;
    int unsigned rd_address_r, wr_address_r;
    int ddr_reads = 0, ddr_writes = 0, rom_reads = 0;
    function automatic byte unsigned get_byte(input int unsigned address);
        if (memory_bytes.exists(address)) return memory_bytes[address];
        return 8'ha5;
    endfunction
    assign wr_ready = claim && wr_phase == 0 && random_r[0];
    assign rd_ready = claim && rd_phase == 0 && random_r[1];
    assign wr_re = wr_phase == 1 && wr_delay == 0 && !wr_empty && random_r[2];
    assign rd_we = rd_phase == 1 && rd_delay == 0 && !rd_full && random_r[3];
    assign wr_done = wr_phase == 2 && wr_delay == 0;
    assign rd_done = rd_phase == 2 && rd_delay == 0;
    // XSim 不支持关联数组的自动敏感列表，负沿准备正沿交付的数据。
    always @(negedge ui_clk) begin
        // 只在返回窗口准备外部DDR数据；闲拍无需遍历稀疏存储。
        if(rd_phase == 1 && rd_delay == 0 && !rd_full)
            for (int b = 0; b < 32; b++) rd_data[b*8 +: 8] = get_byte(rd_address_r + b);
    end
    always @(posedge ui_clk) begin
        cycle = cycle + 1;
        if (!rst_n) begin rd_phase = 0; wr_phase = 0; rd_delay = 0; wr_delay = 0; end
        else begin
            if ((rd_start || wr_start || rd_we || wr_re) && claim !== 1'b1) begin
                $error("DDR operation without UI ownership cycle=%0d",cycle); $stop;
            end
            if (rd_start && rd_ready) begin
                if (rd_len !== 32'd32 || rd_addr[4:0] !== 5'd0 || (rd_addr >= 31'h00100000 && rd_addr < 31'h00400000)) begin
                    $error("invalid DDR read addr=%h len=%d",rd_addr,rd_len); $stop;
                end
                rd_address_r <= rd_addr;
                rd_phase <= 1; rd_delay <= 2; ddr_reads = ddr_reads + 1;
            end else if (rd_we) begin rd_phase <= 2; rd_delay <= 3; end
            else if (rd_done) rd_phase <= 0;
            else if (rd_delay > 0) rd_delay <= rd_delay - 1;
            if (wr_start && wr_ready) begin
                if (wr_len !== 32'd32 || wr_addr[4:0] !== 5'd0 || (wr_addr >= 31'h00100000 && wr_addr < 31'h00400000)) begin
                    $error("invalid DDR write addr=%h len=%d",wr_addr,wr_len); $stop;
                end
                wr_address_r <= wr_addr;
                wr_phase <= 1; wr_delay <= 2;
            end else if (wr_re) begin
                for (int b = 0; b < 32; b++) memory_bytes[wr_address_r+b] = wr_data[b*8 +: 8];
                wr_phase <= 2; wr_delay <= 4; ddr_writes = ddr_writes + 1;
            end else if (wr_done) wr_phase <= 0;
            else if (wr_delay > 0) wr_delay <= wr_delay - 1;
        end
    end

    integer csv;
    logic stalled_r = 1'b0;
    logic [255:0] stalled_data_r;
    logic bank_stalled_r = 1'b0;
    logic [3199:0] bank_held_r;
    logic bank_last_held_r;
    always @(posedge rx_clk) begin
        if (compute_rst_n && bank_stalled_r &&
            (dut.u_service.u_engine.bank_out_valid_w !== 1'b1 ||
             dut.u_service.u_engine.bank_data_w !== bank_held_r ||
             dut.u_service.u_engine.bank_last_w !== bank_last_held_r)) begin
            $error("core output changed under backpressure cycle=%0d",cycle); $stop;
        end
        bank_stalled_r <= compute_rst_n && dut.u_service.u_engine.bank_out_valid_w && !dut.u_service.u_engine.bank_out_ready_w;
        bank_held_r <= dut.u_service.u_engine.bank_data_w;
        bank_last_held_r <= dut.u_service.u_engine.bank_last_w;
    end
    always @(posedge rx_clk) begin
        $fdisplay(csv,"%0d,%b,%b,%b,%b,%b,%b,%b,%b,%0d,%0d,%b,%b,%h",cycle,coeff_req,coeff_ready,coeff_valid,coeff_rsp_ready,rd_start,rd_we,wr_start,wr_re,dut.u_service.u_engine.op_w,dut.u_service.u_engine.state_r,dut.u_service.u_engine.bank_out_valid_w,dut.u_service.u_engine.bank_out_ready_w,dut.u_service.u_engine.bank_data_w[127:0]);
    end
    always @(posedge rx_clk) begin
        if (compute_rst_n && coeff_req && coeff_ready) rom_reads = rom_reads + 1;
        if (compute_rst_n && stalled_r && (coeff_valid !== 1'b1 || coeff_data !== stalled_data_r)) begin
            $error("ROM response changed under backpressure cycle=%0d",cycle); $stop;
        end
        stalled_r <= compute_rst_n && coeff_valid && !coeff_rsp_ready;
        stalled_data_r <= coeff_data;
    end
    initial begin
        csv = $fopen("sim_trace.csv","w");
        $fdisplay(csv,"cycle,coeff_req,coeff_ready,coeff_valid,coeff_rsp_ready,rd_start,rd_we,wr_start,wr_re,op,state,out_valid,out_ready,out_data");
        $dumpfile("waveform.vcd");
        $dumpvars(0,rst_n,coeff_req,coeff_ready,coeff_valid,coeff_rsp_ready,coeff_addr,rd_start,wr_start,bounds_we,bounds_en,bounds_wr_addr,bounds_rd_addr,bounds_rd_data);
        repeat (200000000) @(posedge ui_clk);
        $fatal(1,"Simulation Timeout cycle=%0d",cycle);
    end

    byte unsigned request [0:1039], reply [0:1079];
    byte unsigned descriptor_mem [0:63];
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
        reply_length = tx_len;
        if (reply_length < 38 || reply_length > 1080) begin $error("reply length %d",reply_length); $stop; end
        for (int b=0;b<reply_length;b++) begin
            @(negedge rx_clk); tx_req = 1'b0;
            if (random_r[4]) repeat(2) @(negedge rx_clk);
            tx_req = 1'b1;
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
        $readmemh({VECTOR_DIR,name,"/",filename},golden_mem,0,size-1);
        for (int b=0;b<size;b++) if (get_byte(base+b) !== golden_mem[b]) begin
            $error("DDR Golden %s/%s byte=%0d expected=%h actual=%h cycle=%0d",name,filename,b,golden_mem[b],get_byte(base+b),cycle); $stop;
        end
        // 最大尺寸用例已全量比对 DDR；再抽查首尾包的真实 RPC 返回，避免四百万字节串行帧拖慢回归。
        limit = size > 1048576 ? 1024 : size;
        for (int offset=0;offset<limit;offset+=1024) begin
            length = size-offset < 1024 ? ((size-offset+31)&~31) : 1024;
            put32(0,base+offset); request[4]=8'(length);request[5]=8'(length>>8);request[6]=8'd0;request[7]=8'd0;
            rpc(8'h23,identity,8);check_status(8'd0);
            if (reply_length !== length+38) begin $error("READ size mismatch");$stop;end
            for(int b=0;b<length && offset+b<size;b++) if(reply[32+b] !== golden_mem[offset+b]) begin
                $error("RPC Golden %s byte=%0d expected=%h actual=%h",name,offset+b,golden_mem[offset+b],reply[32+b]);$stop;
            end
        end
        if(size>1048576) begin
            put32(0,base+size-1024);request[4]=8'd0;request[5]=8'd4;request[6]=8'd0;request[7]=8'd0;
            rpc(8'h23,identity,8);check_status(8'd0);
            for(int b=0;b<1024;b++) if(reply[32+b] !== golden_mem[size-1024+b]) begin $error("READ final packet %s",name);$stop;end
        end
    endtask

    // 输出标签逐握手计数，等待期间包括last在内全部保持；不在TB重写上采样算法。
    wire up_valid = dut.u_service.u_engine.u_bank.u_upsample.io_output_o_valid;
    wire up_ready = dut.u_service.u_engine.u_bank.u_upsample.io_output_o_ready;
    wire [27:0] up_tag = {
        dut.u_service.u_engine.u_bank.u_upsample.io_output_o_payload_last,
        dut.u_service.u_engine.u_bank.u_upsample.io_output_o_payload_fragment_group_last,
        dut.u_service.u_engine.u_bank.u_upsample.io_output_o_payload_fragment_group,
        dut.u_service.u_engine.u_bank.u_upsample.io_output_o_payload_fragment_row,
        dut.u_service.u_engine.u_bank.u_upsample.io_output_o_payload_fragment_col};
    logic up_stalled = 1'b0;
    logic [155:0] up_held;
    int up_x=0, up_y=0, up_g=0, up_width=0, up_height=0, up_groups=0;
    int up_stall_cycles=0, up_words=0;
    always @(posedge rx_clk) begin
        if(!dut.u_service.u_engine.u_bank.rst_n_i) begin
            up_stalled <= 1'b0; up_x=0;up_y=0;up_g=0;
        end else begin
            if(dut.u_service.u_engine.u_bank.u_upsample.io_cfg_i_valid &&
               dut.u_service.u_engine.u_bank.u_upsample.io_cfg_i_ready) begin
                up_width=2*int'(dut.u_service.u_engine.width_w);
                up_height=2*int'(dut.u_service.u_engine.height_w);
                up_groups=int'(dut.u_service.u_engine.groups_w);
                up_x=0;up_y=0;up_g=0;
            end
            if(up_stalled && (up_valid !== 1'b1 || {up_tag,dut.u_service.u_engine.u_bank.u_upsample.io_output_o_payload_fragment_data} !== up_held)) begin
                $error("Upsample payload/tag unstable cycle=%0d",cycle);$stop;
            end
            up_stalled <= up_valid && !up_ready;
            up_held <= {up_tag,dut.u_service.u_engine.u_bank.u_upsample.io_output_o_payload_fragment_data};
            if(up_valid && !up_ready) up_stall_cycles++;
            if(up_valid && up_ready) begin
                if(up_tag !== {(up_x==up_width-1 && up_y==up_height-1 && up_g==up_groups-1),
                               (up_x==up_width-1 && up_y==up_height-1),6'(up_g),10'(up_y),10'(up_x)}) begin
                    $error("Upsample tag mismatch g/y/x=%0d/%0d/%0d actual=%h cycle=%0d",up_g,up_y,up_x,up_tag,cycle);$stop;
                end
                up_words++;
                if(up_x==up_width-1) begin
                    up_x=0;
                    if(up_y==up_height-1) begin up_y=0;up_g++;end
                    else up_y++;
                end else up_x++;
            end
        end
    end
    byte unsigned skip_golden [0:4095];
    task automatic check_skip;
        $readmemh({VECTOR_DIR,"encoder_skip.hex"},skip_golden);
        for(int b=0;b<4096;b++) if(get_byte(32'h03100000+b) !== skip_golden[b]) begin
            $error("encoder skip corrupted byte=%0d cycle=%0d",b,cycle);$stop;
        end
    endtask
    task automatic check_up_rejections;
        int previous_reads, previous_writes;
        previous_reads=ddr_reads;previous_writes=ddr_writes;
        for(int t=0;t<9;t++) begin
            for(int b=0;b<64;b++)request[b]=8'd0;
            request[0]=8'd10;request[4]=8'd1;request[6]=8'd1;request[8]=8'd1;
            put32(16,32'h03000000);put32(24,32'h06000000);put32(48,32'hf2000000+32'(t));
            case(t)
                0: request[4]=8'd0;
                1: request[6]=8'd0;
                2: begin request[4]=8'd1;request[5]=8'd1;end
                3: begin request[6]=8'd1;request[7]=8'd1;end
                4: request[8]=8'd0;
                5: request[8]=8'd33;
                6: request[1]=8'd1;
                7: put32(24,32'h1fffffe0); // 四倍输出越界，不能只检查输入体积
                8: put32(24,32'h03000000); // 不支持原地覆盖
                default: ;
            endcase
            rpc(8'h21,32'hf2000000+32'(t),64);check_status(8'd2);
        end
        if(ddr_reads !== previous_reads || ddr_writes !== previous_writes) begin
            $error("rejected Upsample started DDR");$stop;
        end
        $display("[CASE PASS] Upsample descriptor rejection cases=9");
    endtask

    task automatic compare_memory(input string name, input string golden_file,
                                  input int unsigned base, input int unsigned size);
        $readmemh({VECTOR_DIR,golden_file}, golden_mem, 0, size-1);
        if ((base & 32'h1f) != 0 || base + size > 32'h20000000)
            $fatal(1, "address boundary %s base=%h size=%0d", name, base, size);
        for (int b=0; b<size; b++) begin
            if (get_byte(base+b) !== golden_mem[b]) begin
                $error("fullnet Golden mismatch task=%s byte=%0d expected=%h actual=%h cycle=%0d",
                       name, b, golden_mem[b], get_byte(base+b), cycle);
                $stop;
            end
        end
    endtask

    task automatic compare_preserved(input string name, input string golden_file,
                                     input int unsigned base, input int unsigned size);
        compare_memory(name, golden_file, base, size);
        $display("[SKIP PRESERVED] %s base=%h bytes=%0d", name, base, size);
    endtask

    initial begin : fullnet_regression
        integer tasks_fd, uploads_fd, got;
        string name, descriptor_file, golden_file, upload_file;
        int result_size, input_size, task_index, polls, passed;
        int unsigned input_addr, identity, output_addr;
        passed = 0; task_index = 0;
        repeat(8) @(negedge ui_clk);
        rst_n = 1'b1;
        repeat(12) @(negedge rx_clk);

        // Seed only the physical input.  All later inputs are real DUT DDR writes.
        uploads_fd = $fopen({VECTOR_DIR,"uploads.txt"}, "r");
        if (!uploads_fd) $fatal(1, "missing fullnet uploads.txt");
        while (!$feof(uploads_fd)) begin
            got = $fscanf(uploads_fd, "%h %d %s\n", input_addr, input_size, upload_file);
            if (got == 3) begin
                $readmemh({VECTOR_DIR,upload_file}, file_mem, 0, input_size-1);
                for (int b=0; b<input_size; b++) memory_bytes[input_addr+b] = file_mem[b];
            end
        end
        $fclose(uploads_fd);
        $display("[FULLNET INPUT] uploaded P16 bytes=%0d at 0x%08x", input_size, input_addr);

        tasks_fd = $fopen({VECTOR_DIR,"tasks.txt"}, "r");
        if (!tasks_fd) $fatal(1, "missing fullnet tasks.txt");
        while (!$feof(tasks_fd)) begin
            got = $fscanf(tasks_fd, "%s %d %s %s\n", name, result_size, descriptor_file, golden_file);
            if (got == 4) begin
                $display("[FULLNET TASK %0d] %s", task_index, name);
                $readmemh({VECTOR_DIR,descriptor_file}, descriptor_mem, 0, 63);
                identity = desc32(48);
                output_addr = desc32(24);
                if (result_size <= 0 || output_addr + result_size > 32'h20000000 || (output_addr & 32'h1f) != 0)
                    $fatal(1, "invalid task range %s base=%h size=%0d", name, output_addr, result_size);

                // Exercise reset between real stages while retaining the DDR contents.
                if (task_index == 8) begin
                    @(negedge rx_clk); rst_n = 1'b0;
                    repeat(10) @(negedge rx_clk);
                    rst_n = 1'b1;
                    repeat(20) @(negedge rx_clk);
                    if (claim !== 1'b0) $fatal(1, "reset did not release UI claim");
                    $display("[RESET PASS] between e1/pool and e2");
                end

                for (int b=0; b<64; b++) request[b] = descriptor_mem[b];
                rpc(8'h21, identity, 64);
                check_status(8'd0);
                polls = 0;
                do begin
                    repeat(250) @(negedge ui_clk);
                    rpc(8'h22, identity, 0);
                    check_status(8'd0);
                    polls++;
                    if (reply[17] === 8'd3) $fatal(1, "operator failed task=%s", name);
                    if (polls > 100000) $fatal(1, "fullnet task watchdog %s", name);
                end while (reply[17] !== 8'd2);
                if ({reply[27],reply[26],reply[25],reply[24]} !== 32'(result_size))
                    $fatal(1, "result byte count task=%s expected=%0d actual=%0d", name, result_size,
                           {reply[27],reply[26],reply[25],reply[24]});

                // The scoreboard observes the bytes written by the DUT itself.
                compare_memory(name, golden_file, output_addr, result_size);
                if (name == "032_d3.concat") begin
                    compare_preserved("e3 encoder skip", "022_e3.out/golden.hex", 32'h02200000, 4096);
                end else if (name == "041_d2.concat") begin
                    compare_preserved("e2 encoder skip", "014_e2.out/golden.hex", 32'h02100000, 8192);
                end else if (name == "050_d1.concat") begin
                    compare_preserved("e1 encoder skip", "006_e1.out/golden.hex", 32'h02000000, 16384);
                end
                rpc(8'h24, identity, 0);
                check_status(8'd0);
                passed++;
                task_index++;
            end
        end
        $fclose(tasks_fd);
        if (task_index != 59 || passed != 59)
            $fatal(1, "fullnet task quantity mismatch passed=%0d tasks=%0d", passed, task_index);
        if (up_words == 0 || up_stall_cycles == 0)
            $fatal(1, "Upsample handshake/反压 coverage missing words=%0d stalls=%0d", up_words, up_stall_cycles);
        $display("[FULLNET COVERAGE] tasks=%0d up_words=%0d up_stall_cycles=%0d", task_index, up_words, up_stall_cycles);
        $fclose(csv);
        $display("[TB PASSED] fullnet vessel base16 32x32 Golden exact tasks=%0d cycles=%0d rom_reads=%0d ddr_reads=%0d ddr_writes=%0d",
                 passed, cycle, rom_reads, ddr_reads, ddr_writes);
        $finish;
    end
endmodule
