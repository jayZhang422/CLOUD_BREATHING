`timescale 1ns/1ps
// 【文件类型：.sv】op_volume_transform 在扩展 DDR 窗口（0x20000000..0x30000000）的 compact gather 地址自校验。
// 背景：kind-4 视图上限由 0x20000000 放宽到 0x30000000（op_volume_service.VIEW_TOP）。
//       本测试证明 31 位读地址、缓存标签（address[30:5]）、平面偏移乘法（索引×plane_stride）
//       与行偏移乘法（行×row_stride）在 0x20000000 之后的高地址下与低地址同样正确。
// 方法：DDR 模型按地址用 murmur3 fmix32 哈希生成字节（永不等于填充字节 0x80），与 DUT 实现完全独立；
//       每个输出像素的期望值由 TB 按地址公式直接算出，不依赖向量文件。输出网格 32×2、有效 16×2，含左右填充。
// 覆盖：低区对照、末地址恰为 0x30000000、扩展区起点（三个不同平面）、大平面步长（1MiB）、平面跨越 0x20000000。
// 另检：读请求掩码提示 6、读地址落在视图窗口内、读次数 = 未命中次数、命中/未命中计数、写地址/掩码/数据、
//       请求在 valid&&!ready 期间保持不变、响应标签排空。
// 自校验：全等比较 !==；任何不一致 $error + $stop；全部通过打印 [TB PASSED] 并 $finish；含看门狗。
// 运行（单文件，无 IP 依赖，Vivado xsim）：
//   xvlog -sv <Op/control>/op_volume_transform.sv tb_volume_ext_transform.sv && xelab tb_volume_ext_transform -s ext_tr -debug typical && xsim ext_tr -runall
module tb_volume_ext_transform;
    localparam int OUT_W=32,OUT_H=2,GRID_W=16,GRID_H=2,PIXELS=OUT_W*OUT_H;
    localparam int CASES=5;
    logic clk_i=1'b0,rst_n_i=1'b0,start_i=1'b0;
    logic [511:0] command_i=512'd0;
    logic busy_o,done_o,error_o,mem_valid_o,mem_ready_i,mem_write_o,mem_rsp_valid_i,mem_rsp_ready_o,mem_rsp_error_i=1'b0;
    logic [30:0] mem_addr_o;
    logic [255:0] mem_data_o,mem_rsp_data_i;
    logic [31:0] mem_mask_o;
    logic [31:0] compact_hit_count_o,compact_miss_count_o;
    op_volume_transform #(.PIXELS(19'(PIXELS)),.OUTPUT_WIDTH(10'(OUT_W)),.OUTPUT_HEIGHT(10'(OUT_H))) dut(.*);

    // ---------------- 当前用例参数 ----------------
    logic [30:0] c_base,c_dest;
    logic [31:0] c_planes,c_ps,c_rs,c_bytes;
    logic [31:0] c_n[0:2];
    integer case_id=0,expect_miss=0,expect_hit=0;

    // ---------------- 与 DUT 无关的字节源与期望值 ----------------
    function automatic logic [7:0] src_byte(input logic [30:0] address);
        logic [31:0] h;
        begin
            h={1'b0,address};
            h=h^(h>>16);h=h*32'h85ebca6b;
            h=h^(h>>13);h=h*32'hc2b2ae35;
            h=h^(h>>16);
            src_byte=(h[7:0]==8'h80) ? 8'h81 : h[7:0];
        end
    endfunction
    function automatic logic [255:0] model_read(input logic [30:0] address);
        logic [255:0] line;
        begin
            line=256'd0;
            for(int i=0;i<32;i++)line[i*8+:8]=src_byte({address[30:5],5'd0}+31'(i));
            model_read=line;
        end
    endfunction
    // 输出像素 p（0..PIXELS-1）的 128 位期望：{104'd0,ch2,ch1,ch0}，越界为 24'h808080。
    function automatic logic [127:0] expect_pixel(input int p);
        int x,y,nx;
        logic [30:0] a;
        logic [127:0] v;
        begin
            x=p%OUT_W;y=p/OUT_W;nx=x-((OUT_W-GRID_W)>>1);
            v={104'd0,24'h808080};
            if(nx>=0&&nx<GRID_W)begin
                for(int c=0;c<3;c++)begin
                    a=c_base+31'(c_n[c]*c_ps)+31'(y*c_rs)+31'(nx);
                    v[c*8+:8]=src_byte(a);
                end
            end
            expect_pixel=v;
        end
    endfunction

    // ---------------- DDR 模型：一次一笔，确定性反压 ----------------
    logic pending=1'b0,held=1'b0;
    logic [255:0] response=256'd0;
    logic [319:0] held_request;
    integer cycle=0,delay_r=0,csv,wr_idx=0,reads=0;
    always #2 clk_i=~clk_i;
    assign mem_ready_i=rst_n_i&&!pending&&cycle%7!=0;
    assign mem_rsp_valid_i=pending&&delay_r==0;
    assign mem_rsp_data_i=response;

    task automatic fail(input string text);
        begin $error("%s case=%0d cycle=%0d wr_idx=%0d reads=%0d addr=%h",text,case_id,cycle,wr_idx,reads,mem_addr_o);$fflush(csv);$stop; end
    endtask

    always @(posedge clk_i)begin
        cycle=cycle+1;
        $fdisplay(csv,"%0d,%0d,%0d,%b,%b,%b,%h,%b,%b,%0d,%0d",cycle,case_id,dut.state_r,mem_valid_o,mem_ready_i,
                  mem_write_o,mem_addr_o,mem_rsp_valid_i,mem_rsp_ready_o,wr_idx,reads);
        if(held&&{mem_write_o,mem_addr_o,mem_mask_o,mem_data_o}!==held_request)fail("request changed while stalled");
        held=mem_valid_o&&!mem_ready_i;
        held_request={mem_write_o,mem_addr_o,mem_mask_o,mem_data_o};
        if(pending&&delay_r>0)delay_r<=delay_r-1;
        if(mem_rsp_valid_i&&mem_rsp_ready_o)pending<=1'b0;
        if(mem_valid_o&&mem_ready_i)begin
            pending<=1'b1;delay_r<=cycle%5+1;response<=model_read(mem_addr_o);
            if(mem_write_o)begin
                if(mem_addr_o!==c_dest+31'(wr_idx*32)||mem_mask_o!==32'hffffffff)fail("gather write address/mask");
                if(mem_data_o[127:0]!==expect_pixel(2*wr_idx))fail("gather write even pixel data");
                if(mem_data_o[255:128]!==expect_pixel(2*wr_idx+1))fail("gather write odd pixel data");
                wr_idx=wr_idx+1;
            end else begin
                if(mem_mask_o!==32'd6)fail("compact read hint mask");
                if(mem_addr_o[4:0]!==5'd0)fail("compact read not line aligned");
                if({1'b0,mem_addr_o}<{1'b0,c_base[30:5],5'd0}||{1'b0,mem_addr_o}>={1'b0,c_base}+c_bytes)fail("compact read outside view window");
                reads=reads+1;
            end
        end
    end

    // ---------------- 用例 ----------------
    task automatic load_case(input int n);
        int distinct;
        begin
            c_dest=31'h0a000000;c_rs=32'd64;c_ps=32'd128;c_planes=32'd2;
            c_n[0]=32'd0;c_n[1]=32'd0;c_n[2]=32'd1;
            case(n)
                0: c_base=31'h00600000;                                                             // 低区对照
                1: begin c_base=31'h2fffff00;c_n[0]=32'd1;c_n[1]=32'd0;c_n[2]=32'd1; end            // 末地址恰为 0x30000000
                2: begin c_base=31'h20000000;c_planes=32'd3;c_n[0]=32'd2;c_n[1]=32'd1;c_n[2]=32'd0; end // 扩展区起点，三个不同平面
                3: begin c_base=31'h24000000;c_planes=32'd4;c_ps=32'h00100000;
                         c_n[0]=32'd3;c_n[1]=32'd0;c_n[2]=32'd2; end                                // 1MiB 平面步长
                4: begin c_base=31'h1fffff80;c_planes=32'd3;c_n[0]=32'd0;c_n[1]=32'd1;c_n[2]=32'd2; end // 平面跨越 0x20000000（仅验证地址算术）
                default: fail("bad case index");
            endcase
            c_bytes=c_planes*c_ps;
            distinct=1+(c_n[1]!==c_n[0])+((c_n[2]!==c_n[0])&&(c_n[2]!==c_n[1]));
            // 每个不同平面在每个有效行各占一条 32B 行：缓存 8 行足够，无替换。
            expect_miss=distinct*GRID_H;
            expect_hit=3*GRID_W*GRID_H-expect_miss;
            command_i=512'd0;
            command_i[7:0]=8'd4;command_i[15:8]=8'd0;command_i[23:16]=8'd1;
            command_i[63:32]={1'b0,c_base};command_i[95:64]={1'b0,c_dest};
            command_i[127:96]=c_planes;command_i[159:128]=c_bytes;
            command_i[175:160]=16'(GRID_W);command_i[191:176]=16'(GRID_H);
            command_i[223:192]=c_rs;command_i[255:224]=c_ps;
            command_i[287:256]=c_n[0];command_i[319:288]=c_n[1];command_i[351:320]=c_n[2];
        end
    endtask

    task automatic run_case(input int n);
        integer guard;
        begin
            @(negedge clk_i);case_id=n;wr_idx=0;reads=0;load_case(n);
            start_i=1'b1;
            @(negedge clk_i);start_i=1'b0;
            guard=0;
            do begin @(negedge clk_i);guard=guard+1;if(guard>60000)fail("transform never finished");end while(done_o!==1'b1);
            if(error_o!==1'b0)fail("transform error flag");
            if(pending)fail("response still pending at done");
            if(wr_idx!==PIXELS/2)fail("gather write count");
            if(reads!==expect_miss)fail("compact line reads != expected cache misses");
            if(dut.compact_miss_count_o!==32'(expect_miss)||dut.compact_hit_count_o!==32'(expect_hit))begin
                $error("cache counters hit=%0d miss=%0d expected hit=%0d miss=%0d case=%0d",
                       dut.compact_hit_count_o,dut.compact_miss_count_o,expect_hit,expect_miss,n);$fflush(csv);$stop;
            end
            if(dut.response_tag_count_r!==4'd0||dut.gather_count_r!==2'd0)fail("tracking state not drained");
            $display("[CASE PASSED] ext transform case=%0d base=%h planes=%0d plane_stride=%h hit=%0d miss=%0d",
                     n,c_base,c_planes,c_ps,dut.compact_hit_count_o,dut.compact_miss_count_o);
            repeat(4)@(negedge clk_i);
        end
    endtask

    initial begin
        csv=$fopen("sim_trace.csv","w");
        $fdisplay(csv,"cycle,case,state,mem_valid,mem_ready,mem_write,mem_addr,rsp_valid,rsp_ready,wr_idx,reads");
        $dumpfile("waveform.vcd");$dumpvars(0,tb_volume_ext_transform);
        repeat(8)@(negedge clk_i);rst_n_i=1'b1;repeat(4)@(negedge clk_i);
        for(int n=0;n<CASES;n++)run_case(n);
        $display("[TB PASSED] 全部数据验证一致 cases=%0d cycles=%0d",CASES,cycle);
        $fclose(csv);$finish;
    end
    initial begin repeat(600000)@(posedge clk_i);$fatal(1,"Simulation Timeout! case=%0d cycle=%0d state=%0d",case_id,cycle,dut.state_r);end
endmodule
