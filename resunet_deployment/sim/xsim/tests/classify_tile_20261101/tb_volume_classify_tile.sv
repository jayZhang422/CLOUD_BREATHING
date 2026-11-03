`timescale 1ns/1ps
// 【文件类型：.sv】op_volume_transform kind=3 分块（16x16）classify 路径的自校验，与逐像素路径对照。
// 背景：朝向 1/2 的头特征地址 {head_y,head_x} 对相邻像素跨 8KB，逐像素必然完整未命中（约 98~116 周期/像素）。
//       分块路径按列走 16 行并在列首预取 8 条 32B 头行；结果在片上 16x16 槽缓冲累积后整行写回。
// 方法：DDR 为保序流水存储模型（多笔在途、延迟+抖动、响应随机抖动），内容全部由地址哈希生成，与 DUT 无关：
//       头特征 logit = (fmix(hy,hx,k) % 7) - 3（小范围，频繁出现并列与全负值）；xmap/ymap 有三种形态
//       （恒等 / 类 lobe 的 3:4 缩放+偏移（含重复项）/ 伪随机）；旧结果行仅含低于本模型位的位（BIT=0 时填充垃圾，证明被忽略）。
//       期望整行由 TB 按公式直接算出，不依赖向量文件；DUT 写回的每一行逐位全等比较。
// 覆盖：朝向 1/2、BIT=0/5/6/8、通道数 1/2/5、两个块行（PIX=16384）、朝向 0（应走旧路径）、
//       xmap 越界(>511) 与 ymap 越界出错路径（须排空在途写响应后再结束、error_o=1）、
//       每个分块用例都有同参数的逐像素路径对照实例（TILE_ENABLE=0），并打印周期对比。
// 另检：每行恰写一次且掩码全 1、无区域外写、请求在 valid&&!ready 期间保持、结束时响应标签/队列排空、
//       dut.tile_r 与预期路径一致。
// 自校验：全等比较 !==；任何不一致 $error + $stop；全部通过打印 [TB PASSED] 并 $finish；含看门狗。
// 运行（单文件，无 IP 依赖）：
//   xvlog -sv <Op/control>/op_volume_transform.sv tb_volume_classify_tile.sv && xelab tb_volume_classify_tile -s ctile -debug typical && xsim ctile -runall
package ctile_pkg;
    function automatic logic [31:0] fmix(input logic [31:0] x);
        logic [31:0] h;
        begin
            h=x;h=h^(h>>16);h=h*32'h85ebca6b;h=h^(h>>13);h=h*32'hc2b2ae35;h=h^(h>>16);
            return h;
        end
    endfunction
    // 头特征第 k 个 logit：范围 [-3,3]，使并列、全负值、正值都频繁出现。
    function automatic logic signed [15:0] logit(input int hy,input int hx,input int k);
        logic [31:0] h;
        begin
            h=fmix({7'd0,9'(hy),9'(hx),3'(k),4'd0}^32'ha5a50000);
            return 16'(int'(h%7)-3);
        end
    endfunction
endpackage

module harness_tile #(
    parameter bit TILE=1'b1,       // DUT 的 TILE_ENABLE
    parameter int ORI=1,           // 朝向 0/1/2
    parameter int BIT=5,           // 结果位偏移（0=不读旧值）
    parameter int CH=1,            // 通道数 1..7
    parameter int MAP=0,           // xmap/ymap 形态 0/1/2
    parameter int PIX=8192,        // 像素数（8192 的整数倍=块行数x8192）
    parameter int ERR=0,           // 0 无；1 xmap[100]=600；2 ymap[5]=700
    parameter int LATENCY=50,parameter int JITTER=8,parameter int SEED=1
)(
    input logic clk_i,input logic rst_n_i,
    output logic done_o,output int cycles_o,output int reads_o,output logic [6:0] state_o
);
    import ctile_pkg::*;
    localparam logic [30:0] HB=31'h0a000000,XB=31'h08800000,YB=31'h08801000,RB=31'h10000000;
    localparam int LINES=PIX/16;
    localparam bit EXPECT_TILE=TILE&&(ORI==1||ORI==2);

    logic start_i=1'b0;
    logic [511:0] command_i;
    logic busy_o,dut_done_o,error_o,mem_valid_o,mem_ready_i,mem_write_o,mem_rsp_valid_i,mem_rsp_ready_o,mem_rsp_error_i;
    logic [30:0] mem_addr_o;logic [255:0] mem_data_o,mem_rsp_data_i;logic [31:0] mem_mask_o;
    logic [31:0] hit_count_o,miss_count_o;
    op_volume_transform #(.PIXELS(19'(PIX)),.TILE_ENABLE(TILE)) dut(.clk_i(clk_i),.rst_n_i(rst_n_i),.start_i(start_i),.command_i(command_i),
        .busy_o(busy_o),.done_o(dut_done_o),.error_o(error_o),.mem_valid_o(mem_valid_o),.mem_ready_i(mem_ready_i),.mem_write_o(mem_write_o),
        .mem_addr_o(mem_addr_o),.mem_data_o(mem_data_o),.mem_mask_o(mem_mask_o),.mem_rsp_valid_i(mem_rsp_valid_i),
        .mem_rsp_ready_o(mem_rsp_ready_o),.mem_rsp_data_i(mem_rsp_data_i),.mem_rsp_error_i(mem_rsp_error_i),
        .compact_hit_count_o(hit_count_o),.compact_miss_count_o(miss_count_o));
    assign mem_rsp_error_i=1'b0;
    assign state_o=7'(dut.state_r);
    always_comb begin
        command_i=512'd0;
        command_i[7:0]=8'd3;command_i[15:8]=8'(ORI);command_i[23:16]=8'(CH);command_i[31:24]=8'(BIT);
        command_i[62:32]=HB;command_i[94:64]=RB;command_i[222:192]=XB;command_i[254:224]=YB;
    end

    // ---------------- 映射表与期望（与 DUT 无关） ----------------
    function automatic int xm(input int i);
        begin
            case(MAP)
                0: return i;
                1: return (i*3)/4+60;                    // 3:4 缩放，含重复项
                default: return int'(fmix(32'(i)^32'h1234)%512);
            endcase
        end
    endfunction
    function automatic int ym(input int i);
        begin
            case(MAP)
                0: return i;
                1: return (i*5)/8+40;
                default: return int'(fmix(32'(i)^32'h9876)%512);
            endcase
        end
    endfunction
    function automatic logic [31:0] xm_word(input int i);
        begin
            if(i>=512)return 32'd0;
            if(ERR==1&&i==100)return 32'd600;
            return 32'(xm(i));
        end
    endfunction
    function automatic logic [31:0] ym_word(input int i);
        begin
            if(i>=512)return 32'd0;
            if(ERR==2&&i==5)return 32'd700;
            return 32'(ym(i));
        end
    endfunction
    function automatic logic [15:0] old_slot(input int line,input int k);
        logic [31:0] f;
        begin
            f=fmix(32'(line*16+k)^32'hc0de0000);
            return BIT==0 ? f[15:0] : (f[15:0]&((16'd1<<BIT)-16'd1));
        end
    endfunction
    function automatic logic [15:0] new_class(input int x,input int y);
        int xq,yq,hx,hy,best;
        logic signed [15:0] mx,lv;
        begin
            xq=xm(x);yq=ym(y);
            case(ORI)
                1: begin hx=yq;hy=xq; end
                2: begin hx=511-yq;hy=511-xq; end
                default: begin hx=xq;hy=yq; end
            endcase
            mx=16'sh8000;best=0;
            for(int k=0;k<CH;k++)begin lv=logit(hy,hx,k);if(lv>mx)begin mx=lv;best=k; end end
            return mx>=0 ? (16'd1<<(BIT+best)) : 16'd0;
        end
    endfunction
    function automatic logic [255:0] expected_line(input int line);
        int y,tx;
        logic [255:0] v;
        begin
            y=line/32;tx=line%32;v=256'd0;
            for(int c=0;c<16;c++)v[c*16+:16]=(BIT==0 ? 16'd0 : old_slot(line,c))|new_class(tx*16+c,y);
            return v;
        end
    endfunction

    // ---------------- 存储模型：保序流水，多笔在途 ----------------
    typedef struct {logic [255:0] data;longint ready_at;} item_t;
    item_t queue[$];
    logic [255:0] written[int];
    longint now=0;
    logic allow_r=1'b1,rsp_valid_r=1'b0;
    logic [255:0] rsp_data_r=256'd0;
    logic [31:0] rng=32'h600d0000+SEED;
    logic held=1'b0;logic [319:0] held_req;
    int cycle=0,t0=-1,writes=0,reads=0;
    assign mem_ready_i=rst_n_i&&allow_r;
    assign mem_rsp_valid_i=rsp_valid_r;
    assign mem_rsp_data_i=rsp_data_r;
    assign reads_o=reads;
    function automatic logic [255:0] mem_line(input logic [30:0] a);
        logic [255:0] v;
        int off,line,hy,hx0;
        begin
            v=256'd0;
            off=int'(a)-int'(XB);
            if(off>=0&&off<4096&&int'(a)<int'(YB))begin
                for(int i=0;i<8;i++)v[i*32+:32]=xm_word((off>>5)*8+i);
            end
            off=int'(a)-int'(YB);
            if(off>=0&&off<2048)begin
                for(int i=0;i<8;i++)v[i*32+:32]=ym_word((off>>5)*8+i);
            end
            off=int'(a)-int'(HB);
            if(off>=0&&off<512*8192)begin
                hy=off>>13;hx0=((off>>5)&255)*2;
                for(int p=0;p<2;p++)for(int k=0;k<8;k++)v[p*128+k*16+:16]=logit(hy,hx0+p,k);
            end
            off=int'(a)-int'(RB);
            if(off>=0&&off<LINES*32)begin
                line=off>>5;
                if(written.exists(line))v=written[line];
                else for(int k=0;k<16;k++)v[k*16+:16]=old_slot(line,k);
            end
            return v;
        end
    endfunction

    task automatic fail(input string text);
        begin $error("%s ORI=%0d BIT=%0d CH=%0d MAP=%0d TILE=%0b PIX=%0d ERR=%0d cycle=%0d state=%0d wr=%0d rd=%0d",
                     text,ORI,BIT,CH,MAP,TILE,PIX,ERR,cycle,dut.state_r,writes,reads);$stop; end
    endtask

    always @(posedge clk_i)begin
        cycle<=cycle+1;now<=now+1;
        rng<=fmix(rng+32'd1);
        allow_r<=(rng[10:8]!=3'd0); // 约 1/8 拍不接收：使 "valid&&!ready 期间载荷保持" 检查真正生效
        if(!rst_n_i)begin
            queue.delete();rsp_valid_r<=1'b0;held<=1'b0;
        end else begin
            // 请求在 valid&&!ready 期间保持不变（读请求不比较数据线）
            if(held&&{mem_write_o,mem_addr_o,mem_mask_o,(mem_write_o ? mem_data_o : 256'd0)}!==held_req)fail("request changed while stalled");
            held<=mem_valid_o&&!mem_ready_i;
            held_req<={mem_write_o,mem_addr_o,mem_mask_o,(mem_write_o ? mem_data_o : 256'd0)};
            if(rsp_valid_r&&mem_rsp_ready_o)void'(queue.pop_front());
            if(mem_valid_o&&mem_ready_i)begin
                item_t it;
                it.ready_at=now+LATENCY+int'(rng[7:0]%(JITTER+1));
                if(queue.size()!=0&&it.ready_at<queue[$].ready_at)it.ready_at=queue[$].ready_at; // 保序
                if(mem_write_o)begin
                    int off,line;
                    off=int'(mem_addr_o)-int'(RB);line=off>>5;
                    if(off<0||off>=LINES*32||mem_addr_o[4:0]!==5'd0)fail("write outside result region / unaligned");
                    if(mem_mask_o!==32'hffffffff)fail("write mask not full");
                    if(written.exists(line))fail("result line written twice");
                    if(ERR==0&&mem_data_o!==expected_line(line))begin
                        $error("result line %0d mismatch (y=%0d tx=%0d)\n  got=%h\n  exp=%h",line,line/32,line%32,mem_data_o,expected_line(line));
                        fail("data mismatch");
                    end
                    written[line]=mem_data_o;writes=writes+1;
                    it.data=256'd0;
                end else begin
                    it.data=mem_line(mem_addr_o);reads=reads+1;
                end
                queue.push_back(it);
            end
            if(queue.size()!=0&&(now+1)>=queue[0].ready_at)begin
                rsp_valid_r<=1'b1;rsp_data_r<=queue[0].data;
            end else rsp_valid_r<=1'b0;
        end
    end

    initial begin
        done_o=1'b0;cycles_o=0;
        wait(rst_n_i);repeat(4)@(negedge clk_i);
        t0=cycle;start_i=1'b1;
        @(negedge clk_i);start_i=1'b0;
        begin : wait_done
            int guard;guard=0;
            do begin @(negedge clk_i);guard=guard+1;if(guard>3000000)fail("never finished");end while(dut_done_o!==1'b1);
        end
        cycles_o=cycle-t0;
        repeat(3)@(negedge clk_i);
        if(dut.tile_r!==EXPECT_TILE)fail("path selection (tile_r) differs from expectation");
        if(dut.response_tag_count_r!==4'd0||queue.size()!=0)fail("responses not drained at finish");
        if(ERR==0)begin
            if(error_o!==1'b0)fail("unexpected error flag");
            if(writes!==LINES)fail("not every result line was written exactly once");
        end else begin
            if(error_o!==1'b1)fail("error flag not set for illegal map entry");
        end
        $display("[CASE PASSED] classify %s ORI=%0d BIT=%0d CH=%0d MAP=%0d PIX=%0d ERR=%0d cycles=%0d reads=%0d writes=%0d",
                 EXPECT_TILE ? "tile  " : "legacy",ORI,BIT,CH,MAP,PIX,ERR,cycles_o,reads,writes);
        done_o=1'b1;
    end
endmodule

module tb_volume_classify_tile;
    logic clk_i=1'b0,rst_n_i=1'b0;
    always #2 clk_i=~clk_i;
    logic d_t1,d_t2,d_t3,d_t4,d_t5,d_l1,d_l2,d_l3,d_l4,d_o0,d_e1,d_e2,d_e3;
    int c_t1,c_t2,c_t3,c_t4,c_t5,c_l1,c_l2,c_l3,c_l4,c_o0,c_e1,c_e2,c_e3;
    int r_t1,r_t2,r_t3,r_t4,r_t5,r_l1,r_l2,r_l3,r_l4,r_o0,r_e1,r_e2,r_e3;
    logic [6:0] s_t1,s_t2,s_t3,s_t4,s_t5,s_l1,s_l2,s_l3,s_l4,s_o0,s_e1,s_e2,s_e3;
    // 分块路径
    harness_tile #(.TILE(1),.ORI(1),.BIT(0),.CH(5),.MAP(0),.SEED(1)) h_t1(clk_i,rst_n_i,d_t1,c_t1,r_t1,s_t1);
    harness_tile #(.TILE(1),.ORI(1),.BIT(5),.CH(1),.MAP(1),.SEED(2)) h_t2(clk_i,rst_n_i,d_t2,c_t2,r_t2,s_t2);
    harness_tile #(.TILE(1),.ORI(2),.BIT(8),.CH(1),.MAP(2),.SEED(3)) h_t3(clk_i,rst_n_i,d_t3,c_t3,r_t3,s_t3);
    harness_tile #(.TILE(1),.ORI(2),.BIT(0),.CH(5),.MAP(1),.SEED(4)) h_t4(clk_i,rst_n_i,d_t4,c_t4,r_t4,s_t4);
    harness_tile #(.TILE(1),.ORI(1),.BIT(6),.CH(2),.MAP(0),.PIX(16384),.SEED(5)) h_t5(clk_i,rst_n_i,d_t5,c_t5,r_t5,s_t5);
    // 逐像素对照（同参数，TILE_ENABLE=0）
    harness_tile #(.TILE(0),.ORI(1),.BIT(0),.CH(5),.MAP(0),.SEED(1)) h_l1(clk_i,rst_n_i,d_l1,c_l1,r_l1,s_l1);
    harness_tile #(.TILE(0),.ORI(1),.BIT(5),.CH(1),.MAP(1),.SEED(2)) h_l2(clk_i,rst_n_i,d_l2,c_l2,r_l2,s_l2);
    harness_tile #(.TILE(0),.ORI(2),.BIT(8),.CH(1),.MAP(2),.SEED(3)) h_l3(clk_i,rst_n_i,d_l3,c_l3,r_l3,s_l3);
    harness_tile #(.TILE(0),.ORI(2),.BIT(0),.CH(5),.MAP(1),.SEED(4)) h_l4(clk_i,rst_n_i,d_l4,c_l4,r_l4,s_l4);
    // 朝向 0：即使 TILE_ENABLE=1 也必须走旧路径
    harness_tile #(.TILE(1),.ORI(0),.BIT(6),.CH(2),.MAP(1),.SEED(6)) h_o0(clk_i,rst_n_i,d_o0,c_o0,r_o0,s_o0);
    // 出错路径
    harness_tile #(.TILE(1),.ORI(1),.BIT(5),.CH(1),.MAP(0),.ERR(1),.SEED(7)) h_e1(clk_i,rst_n_i,d_e1,c_e1,r_e1,s_e1);
    harness_tile #(.TILE(1),.ORI(2),.BIT(5),.CH(1),.MAP(0),.ERR(2),.SEED(8)) h_e2(clk_i,rst_n_i,d_e2,c_e2,r_e2,s_e2);
    harness_tile #(.TILE(0),.ORI(1),.BIT(5),.CH(1),.MAP(0),.ERR(1),.SEED(9)) h_e3(clk_i,rst_n_i,d_e3,c_e3,r_e3,s_e3);

    integer csv,cycle=0;
    always @(posedge clk_i)begin
        cycle<=cycle+1;
        $fdisplay(csv,"%0d,%b%b%b%b%b,%b%b%b%b,%b%b%b%b,%0d,%0d,%0d,%0d",cycle,d_t1,d_t2,d_t3,d_t4,d_t5,d_l1,d_l2,d_l3,d_l4,d_o0,d_e1,d_e2,d_e3,s_t1,s_t2,s_l1,s_l2);
    end
    function automatic string ratio(input int tile,input int legacy);
        return $sformatf("%0.2fx",real'(legacy)/real'(tile));
    endfunction
    initial begin
        csv=$fopen("sim_trace.csv","w");
        $fdisplay(csv,"cycle,done_tile,done_legacy,done_ori0_err,state_t1,state_t2,state_l1,state_l2");
        $dumpfile("waveform.vcd");$dumpvars(1,tb_volume_classify_tile);
        repeat(8)@(negedge clk_i);rst_n_i=1'b1;
        wait(d_t1&&d_t2&&d_t3&&d_t4&&d_t5&&d_l1&&d_l2&&d_l3&&d_l4&&d_o0&&d_e1&&d_e2&&d_e3);
        @(negedge clk_i);
        $display("[TILE PERF] case1 ORI1 BIT0 CH5  tile=%0d legacy=%0d speedup %s (tile reads %0d, legacy reads %0d)",c_t1,c_l1,ratio(c_t1,c_l1),r_t1,r_l1);
        $display("[TILE PERF] case2 ORI1 BIT5 CH1  tile=%0d legacy=%0d speedup %s (tile reads %0d, legacy reads %0d)",c_t2,c_l2,ratio(c_t2,c_l2),r_t2,r_l2);
        $display("[TILE PERF] case3 ORI2 BIT8 CH1  tile=%0d legacy=%0d speedup %s (tile reads %0d, legacy reads %0d)",c_t3,c_l3,ratio(c_t3,c_l3),r_t3,r_l3);
        $display("[TILE PERF] case4 ORI2 BIT0 CH5  tile=%0d legacy=%0d speedup %s (tile reads %0d, legacy reads %0d)",c_t4,c_l4,ratio(c_t4,c_l4),r_t4,r_l4);
        // 性能不是正确性判据，仅提示；目标是分块明显快于逐像素。
        if(real'(c_l1)/real'(c_t1)<1.5)$warning("tile path less than 1.5x faster than legacy on case1");
        if(real'(c_l2)/real'(c_t2)<1.5)$warning("tile path less than 1.5x faster than legacy on case2");
        $display("[TB PASSED] 全部数据验证一致 tile=5 legacy=5 error=3 cycles=%0d",cycle);
        $fclose(csv);$finish;
    end
    initial begin repeat(4000000)@(posedge clk_i);$fatal(1,"Simulation Timeout! cycle=%0d",cycle);end
endmodule
