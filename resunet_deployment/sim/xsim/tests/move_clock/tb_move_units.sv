`timescale 1ns/1ps
// 实际官方FIFO：长反压、首尾半拍、错误排空、在途复位及重复启动。
module tb_move_units;
    logic clk=1'b0, rst_n=1'b0, start=1'b0, inject=1'b0;
    always #2 clk=!clk;
    logic valid, ready, last, read_idle, write_idle, read_error, write_error;
    logic read_req, read_prefetch, read_ready, rsp_valid, rsp_ready, write_req, write_ready;
    logic [30:0] read_addr, write_addr;
    logic [127:0] data;
    logic [255:0] rsp_data, write_data;
    logic [31:0] write_mask;
    logic [6:0] write_ack=7'd0;
    logic [30:0] addresses[0:15];
    integer due[0:15], wp=0, rp=0, count=0, cycle=0;
    integer got=0, max_credit=0, blocked=0, hint_accepts=0, csv, runs=0;
    byte unsigned input_mem[0:65535], golden_mem[0:28351], output_mem[0:28383];
    localparam integer WORDS_A=1000, WORDS_B=772, BYTES=(WORDS_A+WORDS_B)*16;
    op_move_reader reader (
        .clk_i(clk),.rst_n_i(rst_n),.start_i(start),
        .base_a_i(31'h00000010),.base_b_i(31'h00008000),
        .words_a_i(32'(WORDS_A)),.words_b_i(32'(WORDS_B)),
        .valid_o(valid),.ready_i(ready),.data_o(data),.last_o(last),
        .idle_o(read_idle),.error_o(read_error),
        .mem_valid_o(read_req),.mem_prefetch_o(read_prefetch),.mem_ready_i(read_ready),.mem_addr_o(read_addr),
        .mem_rsp_valid_i(rsp_valid),.mem_rsp_ready_o(rsp_ready),.mem_rsp_data_i(rsp_data),
        .mem_rsp_error_i(inject && rp==3)
    );
    op_move_writer writer (
        .clk_i(clk),.rst_n_i(rst_n),.start_i(start),.base_i(31'h00010000),
        .valid_i(valid),.ready_o(ready),.data_i(data),.last_i(last),
        .idle_o(write_idle),.error_o(write_error),
        .mem_valid_o(write_req),.mem_ready_i(write_ready),
        .mem_addr_o(write_addr),.mem_data_o(write_data),.mem_mask_o(write_mask),
        .mem_rsp_valid_i(write_ack[6]),.mem_rsp_error_i(inject)
    );
    assign read_ready = count < 8 && cycle%11 >= 3;
    assign rsp_valid = count != 0 && cycle >= due[rp];
    assign write_ready = cycle%503 >= 400;
    always_comb begin
        rsp_data=256'd0;
        for(int b=0;b<32;b++) rsp_data[b*8+:8]=input_mem[addresses[rp]+b];
    end
    logic held_valid=1'b0, held_read=1'b0, held_write=1'b0;
    logic [127:0] held_data;
    logic [30:0] held_read_addr;
    logic [318:0] held_write_payload;
    always @(posedge clk) begin
        if(!rst_n) begin
            wp<=0;rp<=0;count<=0;write_ack<=7'd0;got<=0;hint_accepts<=0;
            held_valid<=1'b0;held_read<=1'b0;held_write<=1'b0;
        end else begin
            cycle<=cycle+1;
            write_ack<={write_ack[5:0],write_req&&write_ready};
            if(read_req&&read_ready) begin
                addresses[wp]<=read_addr;due[wp]<=cycle+13;wp<=(wp+1)%16;
                if(read_prefetch)hint_accepts<=hint_accepts+1;
                if(read_prefetch !== ((|reader.beats_r[31:6]) ||
                    reader.beats_r[5:0] > (6'd32-{1'b0,read_addr[9:5]})))begin
                    $error("prefetch hint mismatch cycle=%0d beats=%0d addr=%h hint=%b",cycle,reader.beats_r,read_addr,read_prefetch);$stop;
                end
            end
            if(rsp_valid&&rsp_ready) rp<=(rp+1)%16;
            case({read_req&&read_ready,rsp_valid&&rsp_ready})
                2'b10:count<=count+1;
                2'b01:count<=count-1;
                default:;
            endcase
            if(reader.credit_r>max_credit)max_credit=reader.credit_r;
            if(valid&&!ready)blocked++;
            if(held_valid && (valid!==1'b1 || data!==held_data)) begin
                $error("P16 held payload cycle=%0d",cycle);$fflush(csv);$stop;
            end
            if(held_read && (read_req!==1'b1 || read_addr!==held_read_addr)) begin
                $error("read held address cycle=%0d",cycle);$fflush(csv);$stop;
            end
            if(held_write && (write_req!==1'b1 || {write_addr,write_mask,write_data}!==held_write_payload)) begin
                $error("write held payload cycle=%0d",cycle);$fflush(csv);$stop;
            end
            held_valid<=valid&&!ready;held_data<=data;
            held_read<=read_req&&!read_ready;held_read_addr<=read_addr;
            held_write<=write_req&&!write_ready;held_write_payload<={write_addr,write_mask,write_data};
            if(valid&&ready) begin
                for(int b=0;b<16;b++)if(data[b*8+:8]!==golden_mem[got*16+b])begin
                    $error("stream Golden cycle=%0d word=%0d lane=%0d expected=%h actual=%h",cycle,got,b,golden_mem[got*16+b],data[b*8+:8]);$fflush(csv);$stop;
                end
                if(last !== (got==WORDS_A+WORDS_B-1))begin $error("last cycle=%0d word=%0d",cycle,got);$stop;end
                got<=got+1;
            end
            if(write_req&&write_ready)for(int b=0;b<32;b++)if(write_mask[b])output_mem[write_addr-31'h10000+b]<=write_data[b*8+:8];
            $fdisplay(csv,"%0d,%b,%b,%h,%b,%b,%h,%b,%b,%h,%b,%b",cycle,valid,ready,data,read_req,read_ready,read_addr,write_req,write_ready,write_addr,read_error,write_error);
        end
    end
    task automatic begin_run(input bit errors);
        @(negedge clk);inject=errors;start=1'b1;
        @(negedge clk);start=1'b0;
    endtask
    task automatic finish_run(input bit errors);
        wait(got==WORDS_A+WORDS_B && read_idle && write_idle);
        @(negedge clk);
        for(int b=0;b<BYTES;b++)if(output_mem[b]!==golden_mem[b])begin
            $error("write Golden byte=%0d expected=%h actual=%h",b,golden_mem[b],output_mem[b]);$stop;
        end
        if(read_error!==errors || write_error!==errors)begin $error("error status r=%b w=%b expected=%b",read_error,write_error,errors);$stop;end
        if(hint_accepts!==864)begin $error("prefetch hint count=%0d expected=864",hint_accepts);$stop;end
        for(int b=BYTES;b<BYTES+32;b++)if(output_mem[b]!==8'hA5)begin $error("tail guard byte=%0d",b);$stop;end
        runs++;
    endtask
    initial begin
        csv=$fopen("sim_trace.csv","w");
        $fdisplay(csv,"cycle,valid,ready,data,read_valid,read_ready,read_addr,write_valid,write_ready,write_addr,read_error,write_error");
        $dumpfile("waveform.vcd");$dumpvars(0,clk,rst_n,valid,ready,data,read_req,write_req);
        $readmemh("sim/xsim/tests/move_clock/vectors/unit_input.hex",input_mem);
        $readmemh("sim/xsim/tests/move_clock/vectors/unit_golden.hex",golden_mem);
        for(int b=0;b<BYTES+32;b++)output_mem[b]=8'hA5;
        repeat(8)@(negedge clk);rst_n=1'b1;repeat(12)@(negedge clk);
        begin_run(1'b1);finish_run(1'b1);
        // 下一次运行在预取和写队列非空时复位，然后完整重新启动。
        @(negedge clk);rst_n=1'b0;repeat(8)@(negedge clk);rst_n=1'b1;repeat(12)@(negedge clk);
        begin_run(1'b0);repeat(45)@(negedge clk);rst_n=1'b0;
        repeat(8)@(negedge clk);rst_n=1'b1;repeat(12)@(negedge clk);
        begin_run(1'b0);finish_run(1'b0);
        if(max_credit!==8 || blocked==0 || runs!==2)begin $error("coverage credit=%0d blocked=%0d runs=%0d",max_credit,blocked,runs);$stop;end
        $fclose(csv);$display("[TB PASSED] 全部数据验证一致 runs=%0d max_credit=%0d blocked=%0d prefetch_hints=%0d reset_inflight=1 errors_drained=1",runs,max_credit,blocked,hint_accepts);$finish;
    end
    initial begin repeat(100000)@(posedge clk);$fatal(1,"Simulation Timeout cycle=%0d",cycle);end
endmodule
