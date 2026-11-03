`timescale 1ns/1ps
// 真实调度器和算子引擎；Python独立Golden，DDR模型只处理字节与反压。
module tb_volume_scheduler;
    localparam string ROOT="sim/xsim/tests/volume_ddr_20261025/vectors/";
    logic clk_i=1'b0,rst_n_i=1'b0,storage_idle_i=1'b1,image_ready_i=1'b1;
    logic [30:0] image_base_i=31'h00400000;
    logic [31:0] image_slices_i=32'd2;
    logic req_valid_i=1'b0,req_ready_o,resp_valid_o,claim_o;
    logic [7:0] req_msg_i=8'd0;
    logic [31:0] req_id_i=32'd0;
    logic [15:0] req_len_i=16'd0,resp_len_o;
    logic [511:0] req_body_i=512'd0;
    logic [127:0] resp_body_o;
    logic [4:0] req_data_addr_o,resp_data_addr_o;
    logic req_data_en_o,resp_data_we_o;
    logic [255:0] req_data_i=256'd0,resp_data_o;
    logic mem_valid_o,mem_ready_i,mem_write_o,mem_rsp_valid_i,mem_rsp_ready_o,mem_rsp_error_i;
    logic [30:0] mem_addr_o;
    logic [255:0] mem_data_o,mem_rsp_data_i;
    logic [31:0] mem_mask_o;
    op_volume_service #(.TRANSFORM_PIXELS(19'd16),.TRANSFORM_WIDTH(10'd16),.TRANSFORM_HEIGHT(10'd1)) dut(.*);
    logic [255:0] volume[0:16383],head[0:131071],xmap[0:63],ymap[0:63],identity[0:63];
    logic [255:0] compact_volume[0:1];
    logic [255:0] script[0:11],saved_script[0:11],pack_golden[0:2],shuffle_golden[0:7];
    logic [255:0] readback[0:31],response;
    byte unsigned writes[int unsigned];
    logic [511:0] header;
    logic [127:0] reply;
    logic [319:0] stalled_request;
    logic pending=1'b0,stalled=1'b0,response_error=1'b0,inject_error=1'b0;
    integer cycle=0,delay_r=0,csv,fences=0,operators=0;
    always #2 clk_i=~clk_i;
    assign mem_ready_i=rst_n_i&&!pending&&cycle%7!=0;
    assign mem_rsp_valid_i=pending&&delay_r==0;
    assign mem_rsp_data_i=response;
    assign mem_rsp_error_i=response_error;
    function automatic logic [255:0] model_read(input logic [30:0] address);
        logic [255:0] value;
        value=256'd0;
        if(address>=31'h00400000&&address<31'h00480000)value=volume[(address-31'h00400000)>>5];
        if(address>=31'h00600000&&address<31'h00600040)value=compact_volume[(address-31'h00600000)>>5];
        if(address>=31'h0a800000&&address<31'h0ac00000)value=head[(address-31'h0a800000)>>5];
        if(address>=31'h08800000&&address<31'h08800800)value=xmap[(address-31'h08800000)>>5];
        if(address>=31'h08800800&&address<31'h08801000)value=ymap[(address-31'h08800800)>>5];
        if(address>=31'h08801000&&address<31'h08801800)value=identity[(address-31'h08801000)>>5];
        if(address>=31'h08200000&&address<31'h08200180)value=script[(address-31'h08200000)>>5];
        for(integer b=0;b<32;b=b+1)if(writes.exists(address+b))value[b*8+:8]=writes[address+b];
        return value;
    endfunction
    always @(posedge clk_i)begin
        cycle=cycle+1;
        $fdisplay(csv,"%0d,%0d,%0d,%b,%b,%h,%b,%b,%b,%b",cycle,dut.v_r,dut.index_r,mem_valid_o,mem_ready_i,mem_addr_o,mem_write_o,mem_rsp_valid_i,dut.done_r,dut.error_r);
        if(!rst_n_i)begin pending<=1'b0;stalled<=1'b0;end
        else begin
            if(stalled&&{mem_write_o,mem_addr_o,mem_mask_o,mem_data_o}!==stalled_request)begin $error("unstable request cycle=%0d",cycle);$fflush(csv);$stop;end
            stalled<=mem_valid_o&&!mem_ready_i;stalled_request<={mem_write_o,mem_addr_o,mem_mask_o,mem_data_o};
            if(pending&&delay_r>0)delay_r<=delay_r-1;
            if(mem_rsp_valid_i&&mem_rsp_ready_o)pending<=1'b0;
            if(mem_valid_o&&mem_ready_i)begin
                pending<=1'b1;delay_r<=cycle%5+1;response<=model_read(mem_addr_o);
                response_error<=inject_error;inject_error<=1'b0;
                if(mem_write_o)begin
                    if(mem_mask_o==32'd0)fences=fences+1;
                    for(integer b=0;b<32;b=b+1)if(mem_mask_o[b])writes[mem_addr_o+b]=mem_data_o[b*8+:8];
                end
            end
            if(resp_data_we_o)readback[resp_data_addr_o]=resp_data_o;
            if(dut.v_r==dut.V_RUN&&dut.inner_ready_w)operators=operators+1;
            if(dut.v_r==dut.V_COMPLETE&&pending)begin $error("published before DDR drain cycle=%0d",cycle);$fflush(csv);$stop;end
        end
    end
    task automatic rpc(input logic [7:0] message,input logic [31:0] id,input logic [15:0] length,input logic [511:0] body,input logic [7:0] expected);
        @(negedge clk_i);while(req_ready_o!==1'b1)@(negedge clk_i);
        req_msg_i=message;req_id_i=id;req_len_i=length;req_body_i=body;req_valid_i=1'b1;
        do @(negedge clk_i);while(resp_valid_o!==1'b1);
        reply=resp_body_o;
        if(reply[7:0]!==expected)begin $error("RPC cycle=%0d msg=%h got=%h exp=%h",cycle,message,reply,expected);$fflush(csv);$stop;end
        req_valid_i=1'b0;repeat(3)@(negedge clk_i);
    endtask
    task automatic wait_complete(input logic failure);
        do @(negedge clk_i);while(dut.done_r!==1'b1);
        if((dut.error_r||dut.abort_r)!==failure||pending)begin $error("completion cycle=%0d",cycle);$fflush(csv);$stop;end
    endtask
    task automatic restore_script;
        for(integer i=0;i<12;i=i+1)script[i]=saved_script[i];
        header[127:96]=32'd4;
    endtask
    task automatic make_vol2_script(input logic bad_stride);
        logic [511:0] command;
        command=512'd0;
        command[7:0]=8'd4; command[15:8]=8'd0; command[23:16]=8'd1;
        command[63:32]=32'h00600000; command[95:64]=32'h0a000000;
        command[127:96]=32'd3; command[159:128]=32'd96;
        command[175:160]=16'd16; command[191:176]=16'd1;
        command[223:192]=bad_stride ? 32'd15 : 32'd32; command[255:224]=32'd32;
        command[287:256]=32'd0; command[319:288]=32'd0; command[351:320]=32'd1;
        for(integer i=0;i<12;i=i+1)script[i]=256'd0;
        script[0][7:0]=8'd4; script[1]=command[255:0]; script[2]=command[511:256];
        script[3][7:0]=8'd4; script[4]=command[255:0]; script[5]=command[511:256];
        script[6][7:0]=8'hff;
        header={256'd0,32'd1572864,32'h10000000,32'd3,32'h00400000,
            32'd3,32'h08200000,32'd2,32'h324c4f56};
    endtask
    initial begin
        csv=$fopen("sim_trace.csv","w");$fdisplay(csv,"cycle,state,index,valid,ready,address,write,rsp,done,error");
        $dumpfile("waveform.vcd");$dumpvars(0,clk_i,req_valid_i,resp_valid_o,mem_valid_o,mem_ready_i,mem_addr_o);
        $readmemh({ROOT,"volume.hex"},volume);$readmemh({ROOT,"head.hex"},head);
        $readmemh({ROOT,"compact_volume.hex"},compact_volume);
        $readmemh({ROOT,"xmap.hex"},xmap);$readmemh({ROOT,"ymap.hex"},ymap);$readmemh({ROOT,"identity.hex"},identity);
        $readmemh({ROOT,"scheduler.hex"},script);$readmemh({ROOT,"pack_golden.hex"},pack_golden);
        $readmemh({ROOT,"shuffle_golden.hex"},shuffle_golden);
        for(integer i=0;i<12;i=i+1)saved_script[i]=script[i];
        header={256'd0,32'd1048576,32'h10000000,32'd2,32'h00400000,32'd4,32'h08200000,32'd1,32'h314c4f56};
        repeat(8)@(negedge clk_i);rst_n_i=1'b1;
        rpc(8'h26,32'd100,16'd64,header,8'd0);
        rpc(8'h26,32'd100,16'd64,header,8'd0);
        rpc(8'h26,32'd101,16'd64,header,8'd1);
        rpc(8'h23,32'd100,16'd8,{448'd0,16'd0,16'd32,32'h10000000},8'd1);
        wait_complete(1'b0);
        if(operators!==1||fences<2)begin $error("operator/fence count %0d/%0d",operators,fences);$stop;end
        if(dut.fetch_cycles_r==0||dut.operator_cycles_r==0||dut.gather_cycles_r==0||dut.classify_cycles_r==0)begin
            $error("volume cycle counters fetch=%0d operator=%0d gather=%0d classify=%0d",
                dut.fetch_cycles_r,dut.operator_cycles_r,dut.gather_cycles_r,dut.classify_cycles_r);$stop;
        end
        for(integer i=0;i<8;i=i+1)if(model_read(31'h0a400000+i*32)!==shuffle_golden[i])begin $error("operator Golden word=%0d",i);$stop;end
        rpc(8'h27,32'd100,16'd0,512'd0,8'd0);
        if(reply[15:8]!==8'd2||reply[127:96]!==32'd4)begin $error("query complete %h",reply);$stop;end
        if(readback[0][31:0]!==32'h34474456||readback[0][223:192]==32'd0||
           readback[1][127:64]!==64'd0)begin
            $error("VDG4 baseline snapshot magic=%h fetch=%0d kind4=%h",
                readback[0][31:0],readback[0][223:192],readback[1][127:64]);$stop;
        end
        if(readback[1][255:224]!==readback[0][95:64]+readback[0][127:96])begin
            $error("VDG4 baseline DDR read/write/response counts=%0d/%0d/%0d",
                readback[0][95:64],readback[0][127:96],readback[1][255:224]);$stop;
        end
        rpc(8'h23,32'd100,16'd8,{448'd0,16'd0,16'd32,32'h10000000},8'd0);
        if(readback[0]!==pack_golden[0])begin $error("readback Golden got=%h exp=%h",readback[0],pack_golden[0]);$stop;end
        rpc(8'h27,32'd101,16'd0,512'd0,8'd6);
        rpc(8'h26,32'd100,16'd64,header^512'h10000000000000000,8'd2);
        rpc(8'h28,32'd100,16'd0,512'd0,8'd0);
        rpc(8'h28,32'd100,16'd0,512'd0,8'd0);
        rpc(8'h26,32'd100,16'd64,header,8'd6);
        $display("[CASE PASSED] autonomous gather/operator/labels/fence/readback/idempotence cycles=%0d",cycle);
        rpc(8'h26,32'd102,16'd64,header,8'd0);rpc(8'h29,32'd102,16'd0,512'd0,8'd0);wait_complete(1'b1);
        rpc(8'h23,32'd102,16'd8,{448'd0,16'd0,16'd32,32'h10000000},8'd6);rpc(8'h28,32'd102,16'd0,512'd0,8'd0);
        $display("[CASE PASSED] safe abort boundary and failed result rejection");
        script[0][7:0]=8'h81;rpc(8'h26,32'd103,16'd64,header,8'd0);wait_complete(1'b1);rpc(8'h28,32'd103,16'd0,512'd0,8'd0);restore_script();
        header[127:96]=32'd1;rpc(8'h26,32'd104,16'd64,header,8'd0);wait_complete(1'b1);rpc(8'h28,32'd104,16'd0,512'd0,8'd0);restore_script();
        script[1][95:64]=32'h00400000;rpc(8'h26,32'd105,16'd64,header,8'd0);wait_complete(1'b1);rpc(8'h28,32'd105,16'd0,512'd0,8'd0);restore_script();
        inject_error=1'b1;rpc(8'h26,32'd106,16'd64,header,8'd0);wait_complete(1'b1);rpc(8'h28,32'd106,16'd0,512'd0,8'd0);
        $display("[CASE PASSED] malformed record, missing END, protected input and DDR error fence");
        rpc(8'h26,32'd107,16'd64,header,8'd0);@(negedge clk_i);rst_n_i=1'b0;repeat(8)@(negedge clk_i);rst_n_i=1'b1;
        rpc(8'h27,32'd107,16'd0,512'd0,8'd6);
        image_ready_i=1'b0;make_vol2_script(1'b0);
        rpc(8'h26,32'd108,16'd64,header,8'd0);wait_complete(1'b0);
        rpc(8'h27,32'd108,16'd0,512'd0,8'd0);
        if(readback[0][31:0]!==32'h34474456||readback[0][95:64]==32'd0||
           readback[0][127:96]==32'd0||readback[1][95:64]==64'd0||
           readback[1][191:160]<=32'd1||
           readback[1][255:224]!==readback[0][95:64]+readback[0][127:96])begin
            $error("VDG4 kind4 snapshot reads=%0d writes=%0d kind4=%h cache_misses=%0d responses=%0d",
                readback[0][95:64],readback[0][127:96],readback[1][95:64],readback[1][191:160],readback[1][255:224]);$stop;
        end
        begin
            logic [255:0] expected_word;
            expected_word=256'd0;
            for(integer p=0;p<2;p=p+1)begin
                expected_word[p*128+:8]=compact_volume[0][p*8+:8];
                expected_word[p*128+8+:8]=compact_volume[0][p*8+:8];
                expected_word[p*128+16+:8]=compact_volume[1][p*8+:8];
            end
            if(model_read(31'h0a000000)!==expected_word)begin
                $error("VOL2 scheduler output got=%h exp=%h",model_read(31'h0a000000),expected_word);$stop;
            end
        end
        if(dut.error_r!==1'b0||!dut.vol2_r)begin $error("VOL2 accepted job status error=%b mode=%b",dut.error_r,dut.vol2_r);$stop;end
        if(dut.count_r!==32'd3||dut.volume_depth_r!==32'd3)begin
            $error("VOL2 command count/depth mixed count=%0d depth=%0d",dut.count_r,dut.volume_depth_r);$stop;
        end
        dut.kind_r=8'd3;dut.command_r=512'd0;
        dut.command_r[7:0]=8'd3;dut.command_r[15:8]=8'd0;dut.command_r[23:16]=8'd5;
        dut.command_r[63:32]=32'h0a000000;dut.command_r[95:64]=32'h10000000;
        dut.command_r[127:96]=32'd3;dut.command_r[175:160]=16'd512;dut.command_r[191:176]=16'd512;
        dut.command_r[223:192]=32'h08800000;dut.command_r[255:224]=32'h08800800;
        #1;if(dut.valid_transform_w!==1'b1)begin $error("VOL2 classify depth rejected against command count");$stop;end
        $display("[CASE PASSED] VOL2 START without IMAGE_READY, kind-4 transform and output Golden");
        rpc(8'h28,32'd108,16'd0,512'd0,8'd0);
        make_vol2_script(1'b1);rpc(8'h26,32'd109,16'd64,header,8'd0);wait_complete(1'b1);
        if(dut.error_r!==1'b1)begin $error("VOL2 invalid stride was not rejected");$stop;end
        rpc(8'h28,32'd109,16'd0,512'd0,8'd0);
        $display("[CASE PASSED] VOL2 invalid row stride rejected through fence");
        image_ready_i=1'b1;
        $display("[TB PASSED] autonomous DDR scheduler and protocol safeguards");$fclose(csv);$finish;
    end
    initial begin repeat(300000)@(posedge clk_i);$error("watchdog cycle=%0d state=%0d",cycle,dut.v_r);$fflush(csv);$stop;end
endmodule
