`timescale 1ns/1ps
// 流控自检；数学答案由Python独立生成。
module tb_volume_transform;
    localparam string ROOT="sim/xsim/tests/volume_ddr_20261025/vectors/";
    logic clk_i=1'b0,rst_n_i=1'b0,start_i=1'b0;
    logic [511:0] command_i=512'd0;
    logic busy_o,done_o,error_o,mem_valid_o,mem_ready_i,mem_write_o,mem_rsp_valid_i,mem_rsp_ready_o,mem_rsp_error_i=1'b0;
    logic [30:0] mem_addr_o;
    logic [255:0] mem_data_o,mem_rsp_data_i;
    logic [31:0] mem_mask_o;
    logic [31:0] compact_hit_count_o,compact_miss_count_o;
    op_volume_transform #(.PIXELS(19'd32),.OUTPUT_WIDTH(10'd32),.OUTPUT_HEIGHT(10'd1)) dut(.*);
    logic [255:0] volume[0:16383],compact_volume[0:1],head[0:131071],xmap[0:63],ymap[0:63],identity[0:63];
    logic [511:0] commands[0:2],pack_commands[0:2],compact_commands[0:2];
    logic [127:0] golden[0:95],compact_golden[0:95];
    logic [255:0] pack_golden32[0:5],response;
    logic [319:0] held_request;
    logic pending=1'b0,held=1'b0,packing=1'b0,compact_test=1'b0;
    integer cycle=0,delay_r=0,checks=0,case_id=0,csv,gather_writes=0,result_reads=0,compact_reads=0,case_start_cycle=0;
    integer compact_hint_errors=0;
    integer gather_pushes=0,gather_pops=0,pack_writes=0;
    always #2 clk_i=~clk_i;
    always_comb begin
        mem_ready_i=rst_n_i&&!pending&&cycle%7!=0;
        mem_rsp_valid_i=pending&&delay_r==0;
        mem_rsp_data_i=response;
    end
    function automatic logic [255:0] model_read(input logic [30:0] address);
        if(address>=31'h00400000&&address<31'h00480000)return volume[(address-31'h00400000)>>5];
        if(address>=31'h00600000&&address<31'h00600040)return compact_volume[(address-31'h00600000)>>5];
        if(address>=31'h0a000000&&address<31'h0a400000)return head[(address-31'h0a000000)>>5];
        if(address>=31'h08800000&&address<31'h08800800)return xmap[(address-31'h08800000)>>5];
        if(address>=31'h08800800&&address<31'h08801000)return ymap[(address-31'h08800800)>>5];
        if(address>=31'h08801000&&address<31'h08801800)return identity[(address-31'h08801000)>>5];
        return 256'd0;
    endfunction
    always @(posedge clk_i)begin
        cycle=cycle+1;
        $fdisplay(csv,"%0d,%0d,%0d,%0d,%b,%b,%h,%b,%b,%0d",cycle,case_id,packing,dut.state_r,mem_valid_o,mem_ready_i,mem_addr_o,mem_rsp_valid_i,mem_rsp_ready_o,checks);
        if(held&&{mem_write_o,mem_addr_o,mem_mask_o,mem_data_o}!==held_request)begin $error("request changed cycle=%0d",cycle);$fflush(csv);$stop;end
        held=mem_valid_o&&!mem_ready_i;held_request={mem_write_o,mem_addr_o,mem_mask_o,mem_data_o};
        if(dut.gather_push_w)gather_pushes=gather_pushes+1;
        if(dut.gather_pop_w)gather_pops=gather_pops+1;
        if(pending&&delay_r>0)delay_r<=delay_r-1;
        if(mem_rsp_valid_i&&mem_rsp_ready_o)pending<=1'b0;
        if(mem_valid_o&&mem_ready_i)begin
            pending<=1'b1;delay_r<=cycle%5+1;response<=model_read(mem_addr_o);
            if (!mem_write_o && mem_addr_o>=31'h10000000 && mem_addr_o<31'h10080000) result_reads<=result_reads+1;
            if (!mem_write_o && mem_addr_o>=31'h00600000 && mem_addr_o<31'h00600040) compact_reads<=compact_reads+1;
            if (compact_test && !mem_write_o && mem_addr_o>=31'h00600000 && mem_addr_o<31'h00600040 && mem_mask_o!==32'd6)
                compact_hint_errors<=compact_hint_errors+1;
            if(mem_write_o)begin
                if(packing)begin
                    if(mem_addr_o!==31'h10000000+pack_writes*32||mem_mask_o!==32'hffffffff||
                       mem_data_o!==pack_golden32[case_id*2+pack_writes])begin
                        $error("pack mismatch cycle=%0d case=%0d block=%0d got=%h exp=%h",cycle,case_id,pack_writes,mem_data_o,pack_golden32[case_id*2+pack_writes]);$fflush(csv);$stop;
                    end
                    pack_writes=pack_writes+1;
                    checks=checks+16;
                end else begin
                    gather_writes<=gather_writes+1;
                    for(integer half=0;half<2;half=half+1)if(mem_mask_o[half*16+:16]!==16'd0)begin
                        if(mem_addr_o+half*16!==31'h0a000000+checks*16||mem_mask_o[half*16+:16]!==16'hffff||
                           mem_data_o[half*128+:128] !== (compact_test ? compact_golden[case_id*32+checks] : golden[case_id*32+checks]))begin
                            $error("gather mismatch cycle=%0d case=%0d pixel=%0d compact=%b got=%h exp=%h",cycle,case_id,checks,compact_test,mem_data_o[half*128+:128],compact_test ? compact_golden[case_id*32+checks] : golden[case_id*32+checks]);$fflush(csv);$stop;
                        end
                        checks=checks+1;
                    end
                end
            end
        end
    end
    task automatic run_case(input integer c,input logic pack_mode);
        @(negedge clk_i);case_id=c;packing=pack_mode;compact_test=1'b0;checks=0;gather_writes=0;result_reads=0;
        gather_pushes=0;gather_pops=0;pack_writes=0;case_start_cycle=cycle;
        command_i=pack_mode ? pack_commands[c] : commands[c];
        if(pack_mode&&c==0)command_i[31:24]=8'd0;
        start_i=1'b1;
        @(negedge clk_i);start_i=1'b0;
        do @(negedge clk_i);while(done_o!==1'b1);
        if(error_o!==1'b0||pending||checks!==32)begin $error("completion c=%0d packing=%b checks=%0d",c,pack_mode,checks);$stop;end
        if(!pack_mode&&(gather_writes!==16||gather_pushes!==16||gather_pops!==16||dut.response_tag_count_r!==0))begin
            $error("gather FIFO/drain mismatch writes=%0d pushes=%0d pops=%0d responses=%0d",
                gather_writes,gather_pushes,gather_pops,dut.response_tag_count_r);$stop;
        end
        if(pack_mode&&pack_writes!==2)begin $error("classify block writes=%0d",pack_writes);$stop;end
        if(pack_mode&&c==0&&result_reads!==0)begin $error("first model read old result blocks=%0d",result_reads);$stop;end
        $display("[CASE PASSED] transform orientation=%0d packing=%b",c,pack_mode);
        $display("[TRANSFORM PERF] orientation=%0d packing=%b cycles=%0d gather_writes=%0d result_reads=%0d",c,pack_mode,cycle-case_start_cycle,gather_writes,result_reads);
        repeat(4)@(negedge clk_i);
    endtask
    task automatic run_compact_case(input integer c);
        @(negedge clk_i);case_id=c;packing=1'b0;compact_test=1'b1;checks=0;gather_writes=0;result_reads=0;compact_reads=0;compact_hint_errors=0;
        gather_pushes=0;gather_pops=0;case_start_cycle=cycle;command_i=compact_commands[c];start_i=1'b1;
        @(negedge clk_i);start_i=1'b0;
        do @(negedge clk_i);while(done_o!==1'b1);
        if(error_o!==1'b0||pending||checks!==32||gather_writes!==16||gather_pushes!==16||gather_pops!==16||compact_reads!==2||
           compact_hint_errors!==0||dut.compact_hit_count_o!==32'd46||dut.compact_miss_count_o!==32'd2||dut.response_tag_count_r!==0)begin
            $error("VOL2 completion c=%0d checks=%0d writes=%0d pushes=%0d pops=%0d reads=%0d hints=%0d hit=%0d miss=%0d",
                c,checks,gather_writes,gather_pushes,gather_pops,compact_reads,compact_hint_errors,dut.compact_hit_count_o,dut.compact_miss_count_o);$stop;
        end
        $display("[CASE PASSED] VOL2 direction=%0d lobe_q16_rne=1 boundary_neighbors=%h",compact_commands[c][15:8],compact_commands[c][351:256]);
        $display("[VOL2 PERF] direction=%0d cycles=%0d compact_line_reads=%0d cache_hits=%0d cache_misses=%0d",
            compact_commands[c][15:8],cycle-case_start_cycle,compact_reads,dut.compact_hit_count_o,dut.compact_miss_count_o);
        repeat(4)@(negedge clk_i);
    endtask
    initial begin
        csv=$fopen("sim_trace.csv","w");$fdisplay(csv,"cycle,case,packing,state,valid,ready,address,rsp_valid,rsp_ready,checks");
        $dumpfile("waveform.vcd");$dumpvars(0,clk_i,start_i,done_o,mem_valid_o,mem_ready_i);
        $readmemh({ROOT,"volume.hex"},volume);$readmemh({ROOT,"compact_volume.hex"},compact_volume);$readmemh({ROOT,"head.hex"},head);
        $readmemh({ROOT,"xmap.hex"},xmap);$readmemh({ROOT,"ymap.hex"},ymap);$readmemh({ROOT,"identity.hex"},identity);
        $readmemh({ROOT,"commands.hex"},commands);$readmemh({ROOT,"pack_commands.hex"},pack_commands);
        $readmemh({ROOT,"compact_commands.hex"},compact_commands);
        $readmemh({ROOT,"golden.hex"},golden);$readmemh({ROOT,"compact_golden.hex"},compact_golden);$readmemh({ROOT,"pack_golden32.hex"},pack_golden32);
        repeat(8)@(negedge clk_i);rst_n_i=1'b1;
        for(integer c=0;c<3;c=c+1)run_case(c,1'b0);
        for(integer c=0;c<3;c=c+1)run_case(c,1'b1);
        for(integer c=0;c<3;c=c+1)run_compact_case(c);
        $display("[TB PASSED] VOL1 gather/classify and VOL2 compact continuous-read Golden");$fclose(csv);$finish;
    end
    initial begin repeat(100000)@(posedge clk_i);$error("watchdog");$fflush(csv);$stop;end
endmodule
