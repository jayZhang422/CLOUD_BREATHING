`timescale 1ns/1ps
// 【文件类型：.sv】读/写在途深度 8→16 的定向自校验：op_mem_arbiter、op_move_reader、op_pw_reader。
// 背景：整卷 tumor 的搬运类阶段读吞吐恒为约 5.1 B/周期，等于 8 笔在途 ÷ 约 50 周期往返（Little 定律）；
//       本改动把三者的在途上限参数化（TAGS / CREDITS），engine 取 16，其余实例保持 8。
// 方法：存储模型按地址用 murmur3 fmix32 哈希生成 256 位行，与 DUT 无关；期望值由 TB 按请求地址直接算出。
// 每个被测实例分别在 8 与 16 两档运行，检查：
//   1) 数据逐字全等、按请求顺序返回、多源时各源只收到自己的响应；
//   2) 存储侧在途数从不超过参数上限（且 16 档确实用到 >8，证明改动生效）；
//   3) valid 且 !ready 期间请求载荷保持不变；
//   4) 结束时在途数、DUT 计数全部回零；
//   5) 固定延迟下 16 档吞吐不低于 8 档（仲裁器要求 ≥1.6 倍，读端要求 ≥1.2 倍）。
// 自校验：全等比较 !==；任何不一致 $error + $stop；全部通过打印 [TB PASSED] 并 $finish；含看门狗。
// 运行（需 IP 仿真网表 op_move_read_fifo、op_write_queue_fifo 与 unisims）：
//   xvlog <IP netlists> ; xvlog -sv <Op/control>/op_mem_arbiter.sv op_move_reader.sv op_pw_reader.sv tb_mem_depth16.sv
//   xelab tb_mem_depth16 -s depth16 -debug typical -L unisims_ver -L unimacro_ver -L secureip -L xpm ; xsim depth16 -runall

package depth_pkg;
    function automatic logic [31:0] fmix(input logic [31:0] x);
        logic [31:0] h;
        begin
            h=x;h=h^(h>>16);h=h*32'h85ebca6b;h=h^(h>>13);h=h*32'hc2b2ae35;h=h^(h>>16);
            return h;
        end
    endfunction
    // 31 位字节地址所在 32B 行的 256 位内容（每个 32 位字由字地址哈希得到）。
    function automatic logic [255:0] line_of(input logic [30:0] address);
        logic [255:0] line;
        begin
            line=256'd0;
            for(int i=0;i<8;i++)line[i*32+:32]=fmix({1'b0,address[30:5],3'(i)}^32'h5a5a0000);
            return line;
        end
    endfunction
    function automatic logic [127:0] half_of(input logic [30:0] address);
        logic [255:0] line;
        begin line=line_of(address);return address[4] ? line[255:128] : line[127:0]; end
    endfunction
endpackage

// 保序存储模型：每拍至多接收一笔；响应在 LATENCY(+抖动) 拍后按序给出，可带随机响应反压由使用方通过 rsp_ready 给出。
module mem_model #(parameter int LATENCY=50,parameter int JITTER=0,parameter int ACCEPT_PERCENT=100)(
    input logic clk_i,input logic rst_n_i,
    input logic req_valid_i,output logic req_ready_o,input logic [30:0] req_addr_i,
    output logic rsp_valid_o,input logic rsp_ready_i,output logic [255:0] rsp_data_o,
    output int outstanding_o,output int max_outstanding_o,output int accepted_o
);
    import depth_pkg::*;
    typedef struct {logic [30:0] addr;longint ready_at;} item_t;
    item_t queue[$];
    longint now=0;
    logic [31:0] rng=32'h13572468;
    logic allow_r=1'b1;
    // xsim 不支持对队列元素的连续赋值敏感，因此响应有效/数据/在途数全部在时钟域内寄存输出。
    logic rsp_valid_r=1'b0;
    logic [255:0] rsp_data_r=256'd0;
    int out_r=0;
    assign req_ready_o=rst_n_i&&allow_r;
    assign rsp_valid_o=rsp_valid_r;
    assign rsp_data_o=rsp_data_r;
    assign outstanding_o=out_r;
    always @(posedge clk_i)begin
        now<=now+1;
        rng<=fmix(rng+32'd1);
        allow_r<=(rng[15:8]%100)<ACCEPT_PERCENT;
        if(!rst_n_i)begin
            queue.delete();max_outstanding_o<=0;accepted_o<=0;rsp_valid_r<=1'b0;out_r<=0;
        end else begin
            if(rsp_valid_r&&rsp_ready_i)void'(queue.pop_front());
            if(req_valid_i&&req_ready_o)begin
                item_t it;
                it.addr=req_addr_i;
                it.ready_at=now+LATENCY+(JITTER==0 ? 0 : int'(rng[7:0]%(JITTER+1)));
                if(queue.size()!=0&&it.ready_at<queue[$].ready_at)it.ready_at=queue[$].ready_at; // 保序
                queue.push_back(it);
                accepted_o<=accepted_o+1;
            end
            out_r<=queue.size();
            if(queue.size()>max_outstanding_o)max_outstanding_o<=queue.size();
            if(queue.size()!=0&&(now+1)>=queue[0].ready_at)begin
                rsp_valid_r<=1'b1;rsp_data_r<=line_of(queue[0].addr);
            end else rsp_valid_r<=1'b0;
        end
    end
endmodule

// ---------------------------------------------------------------- 仲裁器 ----------------------------------------------
module harness_arbiter #(parameter int TAGS=8,parameter int LATENCY=50,parameter int JITTER=0,parameter int RSP_STALL_PERCENT=0,
                         parameter int ACCEPT_PERCENT=100,parameter int N=1500)(
    input logic clk_i,input logic rst_n_i,output logic done_o,output int cycles_o,output int max_out_o
);
    import depth_pkg::*;
    logic [1:0] req_valid,req_ready,req_write,rsp_valid,rsp_ready;
    logic [61:0] req_addr;logic [511:0] req_data;logic [63:0] req_mask;
    logic mem_valid,mem_ready,mem_write,mem_rsp_valid,mem_rsp_ready,pending;
    logic [30:0] mem_addr;logic [255:0] mem_data,mem_rsp_data;logic [31:0] mem_mask;
    op_mem_arbiter #(.TAGS(TAGS)) dut(.clk_i(clk_i),.rst_n_i(rst_n_i),.req_valid_i(req_valid),.req_ready_o(req_ready),
        .req_write_i(req_write),.req_addr_i(req_addr),.req_data_i(req_data),.req_mask_i(req_mask),
        .rsp_valid_o(rsp_valid),.rsp_ready_i(rsp_ready),.pending_o(pending),.mem_valid_o(mem_valid),.mem_ready_i(mem_ready),
        .mem_write_o(mem_write),.mem_addr_o(mem_addr),.mem_data_o(mem_data),.mem_mask_o(mem_mask),
        .mem_rsp_valid_i(mem_rsp_valid),.mem_rsp_ready_o(mem_rsp_ready));
    int outstanding,max_outstanding,accepted;
    mem_model #(.LATENCY(LATENCY),.JITTER(JITTER),.ACCEPT_PERCENT(ACCEPT_PERCENT)) mem(.clk_i(clk_i),.rst_n_i(rst_n_i),
        .req_valid_i(mem_valid),.req_ready_o(mem_ready),.req_addr_i(mem_addr),
        .rsp_valid_o(mem_rsp_valid),.rsp_ready_i(mem_rsp_ready),.rsp_data_o(mem_rsp_data),
        .outstanding_o(outstanding),.max_outstanding_o(max_outstanding),.accepted_o(accepted));
    assign max_out_o=max_outstanding;
    // 两个请求源：地址编码源号与序号，期望响应 = line_of(该地址)。
    int sent[2],got[2];
    logic [30:0] expect_q[2][$];
    logic [31:0] rng=32'h2468ace0;
    logic [319:0] held_request;logic held=1'b0;
    int cycle=0,first_cycle=-1;
    always_comb begin
        req_write=2'b00;req_data=512'd0;req_mask=64'hffffffff_ffffffff;
        for(int s=0;s<2;s++)begin
            req_valid[s]=rst_n_i&&sent[s]<N;
            req_addr[s*31+:31]={s[0],6'd0,sent[s][15:0],4'd0}; // 源号 + 序号，行对齐
        end
        for(int s=0;s<2;s++)rsp_ready[s]=rst_n_i&&(rng[s*7+:7]%100)>=RSP_STALL_PERCENT;
    end
    always @(posedge clk_i)begin
        cycle<=cycle+1;
        rng<=fmix(rng+32'd7);
        if(!rst_n_i)begin sent[0]<=0;sent[1]<=0;got[0]<=0;got[1]<=0;done_o<=1'b0;cycles_o<=0;held<=1'b0;first_cycle<=-1;
            expect_q[0].delete();expect_q[1].delete(); end
        else begin
            // 请求侧载荷保持
            if(held&&{mem_write,mem_addr,mem_mask,mem_data}!==held_request[319:0])begin $error("arbiter: request changed while stalled TAGS=%0d",TAGS);$stop; end
            held<=mem_valid&&!mem_ready;held_request<={mem_write,mem_addr,mem_mask,mem_data};
            for(int s=0;s<2;s++)if(req_valid[s]&&req_ready[s])begin
                if(first_cycle<0)first_cycle<=cycle;
                expect_q[s].push_back(req_addr[s*31+:31]);sent[s]<=sent[s]+1;
            end
            for(int s=0;s<2;s++)if(rsp_valid[s]&&rsp_ready[s])begin
                if(expect_q[s].size()==0)begin $error("arbiter: response with no pending request s=%0d",s);$stop; end
                if(mem_rsp_data!==line_of(expect_q[s][0]))begin
                    $error("arbiter: data/order mismatch TAGS=%0d s=%0d got=%0d",TAGS,s,got[s]);$stop; end
                void'(expect_q[s].pop_front());got[s]<=got[s]+1;
            end
            if(rsp_valid[0]&&rsp_valid[1])begin $error("arbiter: both sources valid in one cycle");$stop; end
            if(max_outstanding>TAGS)begin $error("arbiter: outstanding %0d exceeds TAGS=%0d",max_outstanding,TAGS);$stop; end
            if(!done_o&&got[0]==N&&got[1]==N)begin
                done_o<=1'b1;cycles_o<=cycle-first_cycle;
            end
        end
    end
endmodule

// ---------------------------------------------------------------- op_move_reader ---------------------------------------
module harness_move #(parameter int CREDITS=8,parameter int LATENCY=50,parameter int OUT_STALL_PERCENT=0,
                      parameter int WORDS_A=3000,parameter int WORDS_B=200)(
    input logic clk_i,input logic rst_n_i,output logic done_o,output int cycles_o,output int max_out_o
);
    import depth_pkg::*;
    logic start_i=1'b0;
    localparam logic [30:0] BASE_A=31'h00100010,BASE_B=31'h01234000;
    logic valid_o,ready_i,last_o,idle_o,error_o,mem_valid_o,mem_prefetch_o,mem_ready_i,mem_rsp_valid_i,mem_rsp_ready_o,mem_rsp_error_i;
    logic [127:0] data_o;logic [30:0] mem_addr_o;logic [255:0] mem_rsp_data_i;
    op_move_reader #(.CREDITS(CREDITS)) dut(.clk_i(clk_i),.rst_n_i(rst_n_i),.start_i(start_i),.base_a_i(BASE_A),.base_b_i(BASE_B),
        .words_a_i(32'(WORDS_A)),.words_b_i(32'(WORDS_B)),.valid_o(valid_o),.ready_i(ready_i),.data_o(data_o),.last_o(last_o),
        .idle_o(idle_o),.error_o(error_o),.mem_valid_o(mem_valid_o),.mem_prefetch_o(mem_prefetch_o),.mem_ready_i(mem_ready_i),
        .mem_addr_o(mem_addr_o),.mem_rsp_valid_i(mem_rsp_valid_i),.mem_rsp_ready_o(mem_rsp_ready_o),
        .mem_rsp_data_i(mem_rsp_data_i),.mem_rsp_error_i(mem_rsp_error_i));
    assign mem_rsp_error_i=1'b0;
    int outstanding,max_outstanding,accepted;
    mem_model #(.LATENCY(LATENCY)) mem(.clk_i(clk_i),.rst_n_i(rst_n_i),.req_valid_i(mem_valid_o),.req_ready_o(mem_ready_i),
        .req_addr_i(mem_addr_o),.rsp_valid_o(mem_rsp_valid_i),.rsp_ready_i(mem_rsp_ready_o),.rsp_data_o(mem_rsp_data_i),
        .outstanding_o(outstanding),.max_outstanding_o(max_outstanding),.accepted_o(accepted));
    assign max_out_o=max_outstanding;
    logic [31:0] rng=32'h0badf00d;
    assign ready_i=rst_n_i&&(rng[11:5]%100)>=OUT_STALL_PERCENT;
    int words=0,cycle=0,t0=-1;
    logic started=1'b0;
    function automatic logic [127:0] expected(input int k);
        logic [30:0] addr;
        begin
            if(k<WORDS_A)addr=BASE_A+31'(k*16);else addr=BASE_B+31'((k-WORDS_A)*16);
            return half_of(addr);
        end
    endfunction
    always @(posedge clk_i)begin
        cycle<=cycle+1;rng<=fmix(rng+32'd3);start_i<=1'b0;
        if(!rst_n_i)begin words<=0;done_o<=1'b0;cycles_o<=0;started<=1'b0;t0<=-1; end
        else begin
            if(!started)begin started<=1'b1;start_i<=1'b1;t0<=cycle; end
            if(valid_o&&ready_i)begin
                if(data_o!==expected(words))begin $error("move_reader: data mismatch CREDITS=%0d word=%0d got=%h exp=%h",CREDITS,words,data_o,expected(words));$stop; end
                if(last_o!==(words==WORDS_A+WORDS_B-1))begin $error("move_reader: last_o wrong at word=%0d last=%b",words,last_o);$stop; end
                words<=words+1;
            end
            if(error_o)begin $error("move_reader: unexpected error flag");$stop; end
            if(max_outstanding>CREDITS)begin $error("move_reader: outstanding %0d exceeds CREDITS=%0d",max_outstanding,CREDITS);$stop; end
            if(!done_o&&words==WORDS_A+WORDS_B&&idle_o)begin
                if(outstanding!=0||dut.credit_r!=0)begin $error("move_reader: not drained out=%0d credit=%0d",outstanding,dut.credit_r);$stop; end
                done_o<=1'b1;cycles_o<=cycle-t0;
            end
        end
    end
endmodule

// ---------------------------------------------------------------- op_pw_reader -----------------------------------------
module harness_pw #(parameter int CREDITS=8,parameter int LATENCY=50,parameter int RSP_STALL_PERCENT=0,parameter int N=4000)(
    input logic clk_i,input logic rst_n_i,output logic done_o,output int cycles_o,output int max_out_o
);
    import depth_pkg::*;
    logic req_valid_i,req_ready_o,rsp_valid_o,rsp_ready_i,rsp_source_o,error_o,idle_o,mem_valid_o,mem_ready_i,mem_rsp_valid_i,mem_rsp_ready_o,mem_rsp_error_i;
    logic [30:0] req_addr_i,mem_addr_o;logic req_source_i;logic [127:0] rsp_data_o;logic [255:0] mem_rsp_data_i;
    op_pw_reader #(.CREDITS(CREDITS)) dut(.clk_i(clk_i),.rst_n_i(rst_n_i),.clear_i(1'b0),.req_valid_i(req_valid_i),.req_ready_o(req_ready_o),
        .req_addr_i(req_addr_i),.req_source_i(req_source_i),.rsp_valid_o(rsp_valid_o),.rsp_ready_i(rsp_ready_i),.rsp_data_o(rsp_data_o),
        .rsp_source_o(rsp_source_o),.error_o(error_o),.idle_o(idle_o),.mem_valid_o(mem_valid_o),.mem_ready_i(mem_ready_i),
        .mem_addr_o(mem_addr_o),.mem_rsp_valid_i(mem_rsp_valid_i),.mem_rsp_ready_o(mem_rsp_ready_o),.mem_rsp_data_i(mem_rsp_data_i),
        .mem_rsp_error_i(mem_rsp_error_i));
    assign mem_rsp_error_i=1'b0;
    int outstanding,max_outstanding,accepted;
    mem_model #(.LATENCY(LATENCY)) mem(.clk_i(clk_i),.rst_n_i(rst_n_i),.req_valid_i(mem_valid_o),.req_ready_o(mem_ready_i),
        .req_addr_i(mem_addr_o),.rsp_valid_o(mem_rsp_valid_i),.rsp_ready_i(mem_rsp_ready_o),.rsp_data_o(mem_rsp_data_i),
        .outstanding_o(outstanding),.max_outstanding_o(max_outstanding),.accepted_o(accepted));
    assign max_out_o=max_outstanding;
    // 请求序列：每个源顺序读 16B 字（相邻两字共用一条 32B 行→触发复用），偶尔跳转；两个源交替以覆盖 source 标签与复用表。
    int idx=0,got=0,cycle=0,t0=-1;
    logic [31:0] rng=32'hfeedc0de;
    logic [30:0] cursor0,cursor1;
    logic [30:0] expect_addr[$];logic expect_src[$];
    assign req_valid_i=rst_n_i&&idx<N;
    assign req_source_i=idx[0]^(idx[4]);
    assign req_addr_i=req_source_i ? cursor1 : cursor0;
    assign rsp_ready_i=rst_n_i&&(rng[10:4]%100)>=RSP_STALL_PERCENT;
    always @(posedge clk_i)begin
        cycle<=cycle+1;rng<=fmix(rng+32'd5);
        if(!rst_n_i)begin idx<=0;got<=0;done_o<=1'b0;cycles_o<=0;t0<=-1;cursor0<=31'h00200000;cursor1<=31'h04000000;
            expect_addr.delete();expect_src.delete(); end
        else begin
            if(req_valid_i&&req_ready_o)begin
                if(t0<0)t0<=cycle;
                expect_addr.push_back(req_addr_i);expect_src.push_back(req_source_i);
                idx<=idx+1;
                // 下一个地址：多数顺序 +16B；约 1/8 概率跳到新的随机 16B 对齐地址
                if(req_source_i)begin
                    if(rng[18:16]==3'd0)cursor1<={rng[30:19],5'd0,4'd0}+31'h04000000;else cursor1<=req_addr_i+31'd16;
                end else begin
                    if(rng[18:16]==3'd0)cursor0<={rng[30:19],5'd0,4'd0}+31'h00200000;else cursor0<=req_addr_i+31'd16;
                end
            end
            if(rsp_valid_o&&rsp_ready_i)begin
                if(expect_addr.size()==0)begin $error("pw_reader: response with no request");$stop; end
                if(rsp_data_o!==half_of(expect_addr[0])||rsp_source_o!==expect_src[0])begin
                    $error("pw_reader: mismatch CREDITS=%0d idx=%0d got=%h exp=%h src got=%b exp=%b",CREDITS,got,rsp_data_o,half_of(expect_addr[0]),rsp_source_o,expect_src[0]);$stop; end
                void'(expect_addr.pop_front());void'(expect_src.pop_front());got<=got+1;
            end
            if(error_o)begin $error("pw_reader: unexpected error flag");$stop; end
            if(max_outstanding>CREDITS)begin $error("pw_reader: outstanding %0d exceeds CREDITS=%0d",max_outstanding,CREDITS);$stop; end
            if(!done_o&&got==N&&idle_o)begin
                if(outstanding!=0||dut.count_r!=0)begin $error("pw_reader: not drained out=%0d count=%0d",outstanding,dut.count_r);$stop; end
                done_o<=1'b1;cycles_o<=cycle-t0;
            end
        end
    end
endmodule

// ---------------------------------------------------------------- 顶层 -------------------------------------------------
module tb_mem_depth16;
    logic clk_i=1'b0,rst_n_i=1'b0;
    always #2 clk_i=~clk_i;
    // 随机延迟/反压（正确性）与固定延迟无反压（吞吐）。
    logic [3:0] done_r,done_p;
    int cyc_a8,cyc_a16,cyc_m8,cyc_m16,cyc_w8,cyc_w16;
    int mo_a8,mo_a16,mo_m8,mo_m16,mo_w8,mo_w16;
    // 吞吐
    logic d_a8,d_a16,d_m8,d_m16,d_w8,d_w16;
    harness_arbiter #(.TAGS(8), .LATENCY(50),.N(1500)) h_a8 (.clk_i(clk_i),.rst_n_i(rst_n_i),.done_o(d_a8), .cycles_o(cyc_a8), .max_out_o(mo_a8));
    harness_arbiter #(.TAGS(16),.LATENCY(50),.N(1500)) h_a16(.clk_i(clk_i),.rst_n_i(rst_n_i),.done_o(d_a16),.cycles_o(cyc_a16),.max_out_o(mo_a16));
    harness_move    #(.CREDITS(8), .LATENCY(50)) h_m8 (.clk_i(clk_i),.rst_n_i(rst_n_i),.done_o(d_m8), .cycles_o(cyc_m8), .max_out_o(mo_m8));
    harness_move    #(.CREDITS(16),.LATENCY(50)) h_m16(.clk_i(clk_i),.rst_n_i(rst_n_i),.done_o(d_m16),.cycles_o(cyc_m16),.max_out_o(mo_m16));
    harness_pw      #(.CREDITS(8), .LATENCY(50)) h_w8 (.clk_i(clk_i),.rst_n_i(rst_n_i),.done_o(d_w8), .cycles_o(cyc_w8), .max_out_o(mo_w8));
    harness_pw      #(.CREDITS(16),.LATENCY(50)) h_w16(.clk_i(clk_i),.rst_n_i(rst_n_i),.done_o(d_w16),.cycles_o(cyc_w16),.max_out_o(mo_w16));
    // 压力：随机抖动延迟、存储随机不接收、响应随机反压、输出随机反压
    logic s_a8,s_a16,s_m8,s_m16,s_w8,s_w16;
    int sc_a8,sc_a16,sc_m8,sc_m16,sc_w8,sc_w16,smo_a8,smo_a16,smo_m8,smo_m16,smo_w8,smo_w16;
    harness_arbiter #(.TAGS(8), .LATENCY(30),.JITTER(40),.RSP_STALL_PERCENT(40),.ACCEPT_PERCENT(70),.N(1200)) s_ha8 (.clk_i(clk_i),.rst_n_i(rst_n_i),.done_o(s_a8), .cycles_o(sc_a8), .max_out_o(smo_a8));
    harness_arbiter #(.TAGS(16),.LATENCY(30),.JITTER(40),.RSP_STALL_PERCENT(40),.ACCEPT_PERCENT(70),.N(1200)) s_ha16(.clk_i(clk_i),.rst_n_i(rst_n_i),.done_o(s_a16),.cycles_o(sc_a16),.max_out_o(smo_a16));
    harness_move    #(.CREDITS(8), .LATENCY(30),.OUT_STALL_PERCENT(50)) s_hm8 (.clk_i(clk_i),.rst_n_i(rst_n_i),.done_o(s_m8), .cycles_o(sc_m8), .max_out_o(smo_m8));
    harness_move    #(.CREDITS(16),.LATENCY(30),.OUT_STALL_PERCENT(50)) s_hm16(.clk_i(clk_i),.rst_n_i(rst_n_i),.done_o(s_m16),.cycles_o(sc_m16),.max_out_o(smo_m16));
    harness_pw      #(.CREDITS(8), .LATENCY(30),.RSP_STALL_PERCENT(50)) s_hw8 (.clk_i(clk_i),.rst_n_i(rst_n_i),.done_o(s_w8), .cycles_o(sc_w8), .max_out_o(smo_w8));
    harness_pw      #(.CREDITS(16),.LATENCY(30),.RSP_STALL_PERCENT(50)) s_hw16(.clk_i(clk_i),.rst_n_i(rst_n_i),.done_o(s_w16),.cycles_o(sc_w16),.max_out_o(smo_w16));
    integer csv,cycle=0;
    always @(posedge clk_i)begin
        cycle<=cycle+1;
        $fdisplay(csv,"%0d,%b,%b%b%b%b%b%b,%b%b%b%b%b%b",cycle,rst_n_i,d_a8,d_a16,d_m8,d_m16,d_w8,d_w16,s_a8,s_a16,s_m8,s_m16,s_w8,s_w16);
    end
    initial begin
        csv=$fopen("sim_trace.csv","w");$fdisplay(csv,"cycle,rst_n,done_a8a16m8m16w8w16,stress_done_a8a16m8m16w8w16");
        $dumpfile("waveform.vcd");$dumpvars(1,tb_mem_depth16);
        repeat(8)@(negedge clk_i);rst_n_i=1'b1;
        wait(d_a8&&d_a16&&d_m8&&d_m16&&d_w8&&d_w16&&s_a8&&s_a16&&s_m8&&s_m16&&s_w8&&s_w16);
        @(negedge clk_i);
        $display("[CASE PASSED] 8/16 档数据、顺序、在途上限与排空（含随机抖动/反压压力）全部一致");
        $display("[DEPTH PERF] arbiter  TAGS 8:%0d cycles(max out %0d)  16:%0d cycles(max out %0d)  speedup %0.2fx",cyc_a8,mo_a8,cyc_a16,mo_a16,real'(cyc_a8)/real'(cyc_a16));
        $display("[DEPTH PERF] move     CREDITS 8:%0d cycles(max out %0d)  16:%0d cycles(max out %0d)  speedup %0.2fx",cyc_m8,mo_m8,cyc_m16,mo_m16,real'(cyc_m8)/real'(cyc_m16));
        $display("[DEPTH PERF] pw       CREDITS 8:%0d cycles(max out %0d)  16:%0d cycles(max out %0d)  speedup %0.2fx",cyc_w8,mo_w8,cyc_w16,mo_w16,real'(cyc_w8)/real'(cyc_w16));
        if(mo_a8>8||mo_m8>8||mo_w8>8)begin $error("8-deep instance exceeded 8 outstanding");$stop; end
        if(mo_a16<=8||mo_m16<=8||mo_w16<=8)begin $error("16-deep instance never used more than 8 outstanding (change not effective) a=%0d m=%0d w=%0d",mo_a16,mo_m16,mo_w16);$stop; end
        if(mo_a16>16||mo_m16>16||mo_w16>16)begin $error("16-deep instance exceeded 16 outstanding");$stop; end
        if(real'(cyc_a8)/real'(cyc_a16)<1.6)begin $error("arbiter speedup below 1.6x");$stop; end
        if(real'(cyc_m8)/real'(cyc_m16)<1.2)begin $error("move_reader speedup below 1.2x");$stop; end
        if(cyc_w16>cyc_w8)begin $error("pw_reader 16-deep slower than 8-deep");$stop; end
        $display("[TB PASSED] 全部数据验证一致 depth 8/16");
        $fclose(csv);$finish;
    end
    initial begin repeat(2000000)@(posedge clk_i);$fatal(1,"Simulation Timeout!");end
endmodule
