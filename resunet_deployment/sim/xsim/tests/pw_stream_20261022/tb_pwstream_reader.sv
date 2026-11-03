`timescale 1ns/1ps
// 官方FIFO的定向协议自校验；数据只是地址图样，不在TB重写算子算法。
module tb_pwstream_reader;
 logic clk=1'b0, rst_n=1'b0, clear=1'b0;
 always #2 clk=~clk;
 logic req_valid,req_ready,req_source,rsp_valid,rsp_ready,rsp_source,error,idle;
 logic [30:0] req_addr,mem_addr;
 logic [127:0] rsp_data;
 logic mem_valid,mem_ready,mem_rsp_valid,mem_rsp_ready,mem_error;
 logic [255:0] mem_data;
 integer sent=0,received=0,reads=0,responses=0,cycle=0,phase=0,csv,max_pending=0;
 logic [30:0] return_addr[0:255];
 logic held=1'b0;
 logic [128:0] held_data;
 function automatic logic [30:0] address(input integer n);
   address=(n%2 ? 31'h02200000 : 31'h02000000)+31'((n/2)*16);
 endfunction
 function automatic logic [7:0] pattern(input logic [30:0] a);
   pattern=a[7:0]^a[15:8]^a[23:16]^8'h5a;
 endfunction
 assign req_valid=rst_n && phase!=0 && sent<128;
 assign req_source=1'(sent%2);
 assign req_addr=address(sent);
 assign mem_ready=rst_n && cycle%9!=2;
 assign mem_rsp_valid=rst_n && responses<reads && cycle%7!=1;
 assign mem_error=phase==2 && responses==5;
 assign rsp_ready=phase==2 && cycle>200 && cycle%11>=4;
 always_comb begin
   mem_data=256'd0;
   for(integer b=0;b<32;b++) mem_data[b*8+:8]=pattern(return_addr[responses]+31'(b));
 end
 op_pw_reader dut(.clk_i(clk),.rst_n_i(rst_n),.clear_i(clear),
   .req_valid_i(req_valid),.req_ready_o(req_ready),.req_addr_i(req_addr),.req_source_i(req_source),
   .rsp_valid_o(rsp_valid),.rsp_ready_i(rsp_ready),.rsp_data_o(rsp_data),.rsp_source_o(rsp_source),
   .error_o(error),.idle_o(idle),.mem_valid_o(mem_valid),.mem_ready_i(mem_ready),.mem_addr_o(mem_addr),
   .mem_rsp_valid_i(mem_rsp_valid),.mem_rsp_ready_o(mem_rsp_ready),.mem_rsp_data_i(mem_data),.mem_rsp_error_i(mem_error));
 always @(posedge clk) begin
   if(!rst_n) begin sent=0;received=0;reads=0;responses=0;cycle=0;held=1'b0;max_pending=0;end
   else begin
     cycle=cycle+1;
     $fdisplay(csv,"%0d,%0d,%0d,%0d,%0d,%0d,%b,%b,%h",cycle,phase,sent,received,reads,responses,rsp_valid,rsp_ready,rsp_data);
     if(held && (rsp_valid!==1'b1 || {rsp_source,rsp_data}!==held_data))begin $error("response changed while stalled cycle=%0d",cycle);$stop;end
     held=rsp_valid&&!rsp_ready;held_data={rsp_source,rsp_data};
     if(dut.count_r>8)begin $error("credit overflow cycle=%0d",cycle);$stop;end
     if(dut.count_r>max_pending)max_pending=dut.count_r;
     if(req_valid&&req_ready)sent=sent+1;
     if(mem_valid&&mem_ready)begin
       return_addr[reads]=mem_addr;reads=reads+1;
     end
     if(mem_rsp_valid&&mem_rsp_ready)responses=responses+1;
     if(rsp_valid&&rsp_ready)begin
       if(rsp_source!==1'(received%2))begin $error("source order cycle=%0d index=%0d",cycle,received);$stop;end
       for(integer b=0;b<16;b++)if(rsp_data[b*8+:8]!==pattern(address(received)+31'(b)))begin
         $error("reader data cycle=%0d index=%0d byte=%0d expected=%h actual=%h",cycle,received,b,pattern(address(received)+31'(b)),rsp_data[b*8+:8]);$stop;end
       received=received+1;
     end
   end
 end
 initial begin
   csv=$fopen("sim_trace.csv","w");$fdisplay(csv,"cycle,phase,sent,received,reads,responses,valid,ready,data");
   $dumpfile("waveform.vcd");$dumpvars(0,tb_pwstream_reader);
   repeat(8)@(negedge clk);rst_n=1'b1;phase=1;
   repeat(120)@(negedge clk);
   if(sent<8||idle!==1'b0)begin $error("reset cancellation not exercised");$stop;end
   rst_n=1'b0;phase=0;repeat(8)@(negedge clk);rst_n=1'b1;phase=2;
   wait(received==128);wait(idle);@(negedge clk);
   if(reads!==64||responses!==64||error!==1'b1||max_pending!==8)begin
     $error("reader coverage reads=%0d responses=%0d error=%b peak=%0d",reads,responses,error,max_pending);$stop;end
   clear=1'b1;@(negedge clk);clear=1'b0;@(negedge clk);
   if(error!==1'b0||idle!==1'b1)begin $error("clear failed");$stop;end
   $display("[TB PASSED] reader 128 ordered P16,64 reads,two sources,8 credits,long stalls,reset cancellation,error clear");$fclose(csv);$finish;
 end
 initial begin repeat(20000)@(posedge clk);$fatal(1,"reader watchdog");end
endmodule
