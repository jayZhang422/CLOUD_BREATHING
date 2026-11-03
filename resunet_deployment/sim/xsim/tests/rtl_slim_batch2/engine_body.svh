localparam string HERE = "sim/xsim/tests/rtl_slim_batch2/";
localparam string MKDC = "sim/xsim/tests/mkdc/vectors/";
byte unsigned memory_bytes [int unsigned];
logic [7:0] file_mem [0:366079], descriptor_mem [0:63];
integer cycle=0, csv, report, cases_fd, uploads_fd, scanned, size_q, size_mac, input_size;
integer delay_r=0, writes=0, stalls=0, started=0, cases_done=0;
int unsigned input_addr, q_base, mac_base;
logic pending=1'b0, active=1'b0, stalled=1'b0;
logic [319:0] held;
logic [255:0] pending_data;
string folder, filename, case_list;
always #4 clk_i=~clk_i;
function automatic logic [7:0] model_byte(input int unsigned address);
    if (memory_bytes.exists(address)) return memory_bytes[address];
    return 8'd0;
endfunction
always @(negedge clk_i) begin
    mem_ready_i=rst_n_i && !pending && cycle%13>=4;
    mem_rsp_valid_i=rst_n_i && pending && delay_r==0;
    mem_rsp_data_i=pending_data;
end
always @(posedge clk_i) begin
    cycle=cycle+1;
    if (rst_n_i && active) begin
        if ({check_done_o,run_ready_o,descriptor_ok_o,busy_o,done_o,error_o,aborted_o,mem_valid_o,mem_rsp_ready_o} !==
            {check_done_o_before,run_ready_o_before,descriptor_ok_o_before,busy_o_before,done_o_before,error_o_before,aborted_o_before,mem_valid_o_before,mem_rsp_ready_o_before}) begin
            $error("engine control differs case=%s cycle=%0d",folder,cycle); $fflush(csv); $stop;
        end
        if (mem_valid_o && {mem_write_o,mem_addr_o,mem_mask_o} !== {mem_write_o_before,mem_addr_o_before,mem_mask_o_before}) begin
            $error("engine transaction differs case=%s cycle=%0d",folder,cycle); $fflush(csv); $stop;
        end
        // 该内部仲裁口允许尚未接收的读被写抢占；逐拍与基线对照覆盖该行为。
        // 写事务优先级最高，等待接收期间必须保持地址、掩码和载荷不变。
        if (stalled && held[319] && (!mem_valid_o || {mem_write_o,mem_addr_o,mem_mask_o,mem_data_o} !== held)) begin
            $error("engine payload changed under backpressure cycle=%0d",cycle); $fflush(csv); $stop;
        end
        stalled=mem_valid_o && !mem_ready_i;
        held={mem_write_o,mem_addr_o,mem_mask_o,mem_data_o};
        if (stalled) stalls=stalls+1;
        if (pending && delay_r>0) delay_r=delay_r-1;
        if (mem_rsp_valid_i && mem_rsp_ready_o) pending=1'b0;
        if (mem_valid_o && mem_ready_i) begin
            if (pending) begin $error("overlapping memory request"); $stop; end
            if (mem_write_o) begin
                for (integer b=0;b<32;b=b+1) if (mem_mask_o[b]) begin
                    if (mem_data_o[b*8+:8] !== mem_data_o_before[b*8+:8]) begin
                        $error("engine byte differs case=%s cycle=%0d addr=%h lane=%0d",folder,cycle,mem_addr_o,b); $fflush(csv); $stop;
                    end
                    memory_bytes[mem_addr_o+b]=mem_data_o[b*8+:8];
                    writes=writes+1;
                end
                pending_data=256'd0;
            end else for (integer b=0;b<32;b=b+1) pending_data[b*8+:8]=model_byte(mem_addr_o+b);
            pending=1'b1; delay_r=cycle%5+1;
        end
    end
    $fdisplay(csv,"%0d,%s,%0d,%b,%b,%b,%h,%b,%b,%b,%b",cycle,folder,dut.state_r,mem_valid_o,mem_ready_i,mem_write_o,mem_addr_o,mem_rsp_valid_i,mem_rsp_ready_o,done_o,error_o);
end
task automatic compare_file(input string name, input int unsigned address, input integer count);
    $readmemh({folder,"/",name},file_mem,0,count-1);
    for (integer b=0;b<count;b=b+1) begin
        if (!memory_bytes.exists(address+b) || model_byte(address+b) !== file_mem[b]) begin
            $error("Golden mismatch case=%s file=%s byte=%0d got=%h expected=%h",folder,name,b,model_byte(address+b),file_mem[b]); $fflush(csv); $stop;
        end
    end
endtask
task automatic load_descriptor;
    $readmemh({folder,"/descriptor.hex"},descriptor_mem);
    for (integer b=0;b<64;b=b+1) descriptor_i[b*8+:8]=descriptor_mem[b];
endtask
initial begin
    if ($bits(dut.saved_data_r) !== (WIDE_DEBUG ? 3200 : 128) ||
        $bits(dut.writer_data_w) !== (WIDE_DEBUG ? 3200 : 256) ||
        $bits(dut.u_bank.window5_w) !== 3200) $fatal(1,"incorrect production/debug data widths");
    clk_i=1'b0; rst_n_i=1'b0; run_valid_i=1'b0; check_valid_i=1'b0; abort_i=1'b0;
    mem_rsp_error_i=1'b0; descriptor_i=512'd0;
    csv=$fopen("sim_trace.csv","w"); report=$fopen("checks.txt","w");
    $fdisplay(csv,"cycle,case,state,mem_valid,mem_ready,write,address,rsp_valid,rsp_ready,done,error");
    $dumpfile("waveform.vcd");
    $dumpvars(0,clk_i,rst_n_i,mem_valid_o,mem_ready_i,mem_write_o,mem_addr_o,done_o,error_o);
    repeat (6) @(negedge clk_i); rst_n_i=1'b1;
    if (!WIDE_DEBUG) begin
        cases_fd=$fopen({HERE,"debug_cases.txt"},"r");
        if (!cases_fd) $fatal(1,"missing disabled descriptor list");
        while (!$feof(cases_fd)) begin
            scanned=$fscanf(cases_fd,"%s %d %d\n",folder,size_q,size_mac);
            if (scanned==3) begin
                load_descriptor(); check_valid_i=1'b1;
                do @(negedge clk_i); while (check_done_o !== 1'b1);
                if (descriptor_ok_o !== 1'b0 || descriptor_ok_o_before !== 1'b1 || mem_valid_o !== 1'b0) begin
                    $error("disabled debug descriptor accepted case=%s",folder); $stop;
                end
                check_valid_i=1'b0; repeat (3) @(negedge clk_i);
            end
        end
        $fclose(cases_fd);
        $display("[CASE PASSED] production rejects op3/op4/op8/op9");
    end
    case_list=WIDE_DEBUG ? "debug_cases.txt" : "production_cases.txt";
    cases_fd=$fopen({HERE,case_list},"r");
    if (!cases_fd) $fatal(1,"missing engine case list");
    while (!$feof(cases_fd)) begin
        scanned=$fscanf(cases_fd,"%s %d %d\n",folder,size_q,size_mac);
        if (scanned==3) begin
            memory_bytes.delete();
            $readmemh({HERE,"vectors/coeff.hex"},file_mem);
            for (integer b=0;b<366080;b=b+1) memory_bytes[32'h00100000+b]=file_mem[b];
            uploads_fd=$fopen({folder,"/uploads.txt"},"r");
            if (!uploads_fd) $fatal(1,"missing uploads %s",folder);
            while (!$feof(uploads_fd)) begin
                scanned=$fscanf(uploads_fd,"%h %d %s\n",input_addr,input_size,filename);
                if (scanned==3) begin
                    if (filename.substr(1,1) != ":") filename={MKDC,filename};
                    $readmemh(filename,file_mem,0,input_size-1);
                    for (integer b=0;b<input_size;b=b+1) memory_bytes[input_addr+b]=file_mem[b];
                end
            end
            $fclose(uploads_fd);
            load_descriptor(); q_base=descriptor_i[223:192]; mac_base=descriptor_i[255:224];
            // 先填毒值，能检测遗漏写回与尾通道清零，而非默认零掩盖漏写。
            for (integer b=0;b<size_q;b=b+1) memory_bytes[q_base+b]=8'hcc;
            active=1'b0; pending=1'b0; stalled=1'b0; writes=0;
            check_valid_i=1'b1;
            do @(negedge clk_i); while (check_done_o !== 1'b1);
            if (descriptor_ok_o !== 1'b1 || candidate_bytes_o !== size_q || candidate_mac_bytes_o !== size_mac) begin
                $error("descriptor rejected case=%s ok=%b bytes=%0d/%0d mac=%0d/%0d",folder,descriptor_ok_o,candidate_bytes_o,size_q,candidate_mac_bytes_o,size_mac); $stop;
            end
            check_valid_i=1'b0; active=1'b1; @(negedge clk_i); run_valid_i=1'b1;
            do @(posedge clk_i); while (run_ready_o !== 1'b1);
            started=cycle; @(negedge clk_i); run_valid_i=1'b0;
            do @(negedge clk_i); while (done_o !== 1'b1);
            if (error_o !== 1'b0 || pending || result_bytes_o !== size_q || mac_bytes_o !== size_mac) begin
                $error("engine final state case=%s error=%b pending=%b",folder,error_o,pending); $stop;
            end
            compare_file("golden.hex",q_base,size_q);
            if (size_mac>0) compare_file("mac.hex",mac_base,size_mac);
            $display("[CASE PASSED] engine debug=%b case=%s bytes=%0d mac=%0d cycles=%0d exact_cycle_equivalence",WIDE_DEBUG,folder,size_q,size_mac,cycle-started);
            $fdisplay(report,"[CASE PASSED] engine debug=%b case=%s bytes=%0d mac=%0d cycles=%0d exact_cycle_equivalence",WIDE_DEBUG,folder,size_q,size_mac,cycle-started);
            cases_done=cases_done+1; repeat (3) @(negedge clk_i); active=1'b0;
        end
    end
    if (cases_done !== (WIDE_DEBUG ? 4 : 12) || stalls==0) $fatal(1,"engine coverage incomplete");
    $display("[TB PASSED] engine debug=%b cases=%0d stalls=%0d exact_cycle_equivalence",WIDE_DEBUG,cases_done,stalls);
    $fdisplay(report,"[TB PASSED] engine debug=%b cases=%0d stalls=%0d exact_cycle_equivalence",WIDE_DEBUG,cases_done,stalls);
    $fclose(cases_fd); $fclose(csv); $fclose(report); $finish;
end
initial begin
    repeat (2000000) @(posedge clk_i);
    $error("engine watchdog case=%s state=%0d",folder,dut.state_r); $fflush(csv); $stop;
end
endmodule
