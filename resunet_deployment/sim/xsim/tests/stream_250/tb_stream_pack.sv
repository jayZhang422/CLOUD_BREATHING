`timescale 1ns/1ps
// 官方非对称BRAM重排和分段writer联合自校验；仅检查布局、掩码和握手。
module tb_stream_pack;
    logic clk=0, rst_n=0, start=0;
    always #2 clk=~clk;
    logic [18:0] pixels;
    logic [9:0] cout;
    logic iv=0, ir, ov, ory, last, pack_idle, idle, err;
    logic [31:0] idata;
    logic [18:0] pixel;
    logic [6:0] group_id;
    logic [127:0] odata;
    logic [30:0] addr, ma;
    logic mv, mr, rv=0;
    logic [255:0] md;
    logic [31:0] mask;
    localparam logic [30:0] BASE=31'h02400000;
    byte unsigned memory[int unsigned];
    integer cycle=0, csv, count=0, delay_q[$], outputs=0, writes=0;
    logic held_valid=0;
    logic [159:0] held;
    function automatic byte unsigned value(input int p, input int ch);
        return 8'(p*17+ch*3+29);
    endfunction
    op_pw_pack packer(.clk_i(clk),.rst_n_i(rst_n),.start_i(start),.base_i(BASE),
        .pixels_i(pixels),.cout_i(cout),.valid_i(iv),.ready_o(ir),.data_i(idata),
        .pixel_i(pixel),.group_i(group_id),.valid_o(ov),.ready_i(ory),.data_o(odata),
        .address_o(addr),.last_o(last),.idle_o(pack_idle));
    op_move_writer #(.ADDRESS_PER_WORD(1'b1)) writer(.clk_i(clk),.rst_n_i(rst_n),
        .start_i(start),.base_i(BASE),.address_i(addr),.valid_i(ov),.ready_o(ory),
        .data_i(odata),.last_i(last),.idle_o(idle),.error_o(err),.mem_valid_o(mv),
        .mem_ready_i(mr),.mem_addr_o(ma),.mem_data_o(md),.mem_mask_o(mask),
        .mem_rsp_valid_i(rv),.mem_rsp_error_i(1'b0));
    assign mr=cycle%271>=75;
    always @(negedge clk) begin
        rv=0;
        if(delay_q.size()>0) begin
            if(delay_q[0]<=cycle) begin rv=1; count=delay_q.pop_front(); end
        end
    end
    always @(posedge clk) begin
        cycle++;
        $fdisplay(csv,"%0d,%b,%b,%0d,%0d,%h,%b,%b,%h,%h,%b,%b,%h,%h",cycle,
            iv,ir,pixel,group_id,idata,ov,ory,addr,odata,mv,mr,ma,mask);
        if(rst_n) begin
            if(held_valid && (!ov || {last,addr,odata} !== held)) begin
                $error("pack payload changed under backpressure cycle=%0d",cycle); $fflush(csv); $stop;
            end
            held_valid=ov&&!ory;
            held={last,addr,odata};
            if(ov&&ory) begin
                int index,p,g;
                index=(addr-BASE)/16; p=index%pixels; g=index/pixels;
                for(int l=0;l<16;l++) begin
                    byte unsigned expected;
                    expected=g*16+l<cout ? value(p,g*16+l) : 8'd0;
                    if(odata[l*8+:8] !== expected) begin
                        $error("pack cycle=%0d pixel=%0d group=%0d lane=%0d expected=%h actual=%h",cycle,p,g,l,expected,odata[l*8+:8]);
                        $fflush(csv); $stop;
                    end
                end
                outputs++;
            end
            if(mv&&mr) begin
                for(int b=0;b<32;b++) if(mask[b]) memory[ma-BASE+b]=md[b*8+:8];
                delay_q.push_back(cycle+31); writes++;
            end
        end
    end
    task automatic run_case(input int np,input int nc);
        @(negedge clk); start=1; pixels=19'(np); cout=10'(nc);
        outputs=0; writes=0; memory.delete();
        @(negedge clk); start=0;
        for(int tile=0;tile<np;tile+=16)
            for(int g=0;g<(nc+15)/16;g++)
                for(int part=0;part<4 && g*16+part*4<nc;part++)
                    for(int p=tile;p<np && p<tile+16;p++) begin
                        @(negedge clk);
                        iv=1; pixel=19'(p); group_id=7'(g*4+part);
                        for(int l=0;l<4;l++) idata[l*8+:8]=g*16+part*4+l<nc ? value(p,g*16+part*4+l) : 8'd0;
                        do @(posedge clk); while(!ir);
                        @(negedge clk); iv=0;
                    end
        wait(pack_idle&&idle);
        @(negedge clk);
        if(err || outputs!==np*((nc+15)/16)) begin $error("pack count/status"); $stop; end
        for(int b=0;b<np*((nc+15)/16)*16;b++) begin
            int p,ch;
            byte unsigned expected;
            p=(b/16)%np; ch=(b/(16*np))*16+b%16;
            expected=ch<nc ? value(p,ch) : 8'd0;
            if(!memory.exists(b) || memory[b] !== expected) begin
                $error("writer byte=%0d expected=%h actual=%h",b,expected,memory[b]); $fflush(csv); $stop;
            end
        end
        $display("[CASE PASSED] pack pixels=%0d cout=%0d outputs=%0d writes=%0d",np,nc,outputs,writes);
    endtask
    initial begin
        csv=$fopen("sim_trace.csv","w");
        $fdisplay(csv,"cycle,in_valid,in_ready,pixel,group,data,out_valid,out_ready,address,payload,mem_valid,mem_ready,mem_addr,mask");
        $dumpfile("waveform.vcd"); $dumpvars(1,tb_stream_pack);
        repeat(10) @(negedge clk); rst_n=1;
        repeat(10) @(negedge clk);
        run_case(16,128); run_case(19,21); run_case(1,1); run_case(17,512);
        run_case(3,5); run_case(32,17);
        $fclose(csv); $display("[TB PASSED] P4/P16 pack and segmented writeback"); $finish;
    end
    initial begin repeat(300000) @(posedge clk); $fatal(1,"pack watchdog"); end
endmodule
