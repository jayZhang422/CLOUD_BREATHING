`timescale 1ns/1ps
// 【文件类型：.sv】op_volume_service 的 START 合法性检查定向自校验（真实 DUT，无向量文件）。
// 目标：验证“START 检查结果先寄存（R_CHECK）再驱动 1000+ 触发器使能”的改动与原组合实现行为一致。
// 脚本只有一条 END 记录（kind=0xFF），算子/变换均不运行；DDR 模型仅应答 END 记录与排空栅栏。
// 覆盖：VOL1/VOL2 全字段边界与拒绝、环境信号（storage_idle/image_*）拒绝、被拒 START 不改任何状态、
//       幂等重发/冲突/过期/重复释放状态码、接受时计数器清零、每次 RPC 必经 R_CHECK、
//       零间隔背靠背随机混合（接受与拒绝交替，验证无陈旧采样）。
// 自校验：全等比较 !==；任何不一致 $error + $stop；全部通过打印 [TB PASSED] 并 $finish；含看门狗。
module tb_volume_start_check;
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
    op_volume_service dut(.*);

    // ---------------- 简单 DDR 模型：一次一笔，确定性反压 ----------------
    logic pending=1'b0;
    logic [255:0] response=256'd0;
    integer cycle=0,delay_r=0,csv;
    always #2 clk_i=~clk_i;
    assign mem_ready_i=rst_n_i&&!pending&&cycle%5!=0;
    assign mem_rsp_valid_i=pending&&delay_r==0;
    assign mem_rsp_data_i=response;
    assign mem_rsp_error_i=1'b0;
    function automatic logic [255:0] model_read(input logic [30:0] address);
        logic [255:0] value;
        value=256'd0;
        if(address==31'h08200000)value[7:0]=8'hff; // END 记录首字节；其余 64B 为 0
        return value;
    endfunction
    always @(posedge clk_i)begin
        if(!rst_n_i)begin pending<=1'b0;end
        else begin
            if(pending&&delay_r>0)delay_r<=delay_r-1;
            if(mem_rsp_valid_i&&mem_rsp_ready_o)pending<=1'b0;
            if(mem_valid_o&&mem_ready_i)begin pending<=1'b1;delay_r<=cycle%3+1;response<=model_read(mem_addr_o);end
        end
    end

    // ---------------- 观测与监视 ----------------
    logic [255:0] readback[0:3];
    logic [2:0] prev_state=3'd0;
    integer accepts=0,rejects=0,jobs_done=0,last_fetch=0,gap=3,next_id=1000;
    logic [31:0] rng=32'h1badc0de;
    logic [127:0] reply;

    task automatic fail(input string text);
        begin $error("%s cycle=%0d state=%0d msg=%h", text, cycle, dut.r_r, dut.msg_r);$fflush(csv);$stop; end
    endtask

    always @(posedge clk_i)begin
        cycle<=cycle+1;
        $fdisplay(csv,"%0d,%0d,%0d,%b,%b,%b,%h,%0d,%0d,%b,%b,%b",cycle,dut.r_r,dut.v_r,req_valid_i,req_ready_o,
                  resp_valid_o,resp_body_o[7:0],accepts,rejects,dut.held_r,dut.done_r,dut.error_r);
        prev_state<=dut.r_r;
        if(resp_data_we_o)readback[resp_data_addr_o]=resp_data_o;
        if(rst_n_i)begin
            // 每次 RPC 必经 R_IDLE→R_CHECK→R_DECODE，且 R_CHECK 恰好一拍。
            if(dut.r_r===dut.R_CHECK&&prev_state!==dut.R_IDLE)fail("R_CHECK not entered from R_IDLE");
            if(dut.r_r===dut.R_DECODE&&prev_state!==dut.R_CHECK)fail("R_DECODE not preceded by R_CHECK");
            if(dut.r_r!==dut.R_IDLE&&claim_o!==1'b1)fail("claim dropped while RPC in flight");
            if(resp_valid_o!==(dut.r_r===dut.R_REPLY))fail("resp_valid_o does not follow R_REPLY");
            if(req_ready_o!==(dut.r_r===dut.R_IDLE))fail("req_ready_o does not follow R_IDLE");
            // 接受点：start_go_r 在 R_REPLY 拍有效一次；此刻状态必须已装载且计数器已清零。
            if(dut.r_r===dut.R_REPLY&&dut.msg_r===8'h26&&dut.start_go_r===1'b1)begin
                accepts<=accepts+1;
                if(dut.held_r!==1'b1||dut.done_r!==1'b0||dut.error_r!==1'b0||dut.abort_r!==1'b0||dut.seen_r!==1'b1)
                    fail("accepted START flags");
                if(dut.identity_r!==dut.id_r||dut.start_header_r!==dut.body_r)fail("accepted START identity/header latch");
                if(dut.fetch_cycles_r!==64'd0||dut.operator_cycles_r!==64'd0||dut.gather_cycles_r!==64'd0||
                   dut.classify_cycles_r!==64'd0||dut.transform_kind4_cycles_r!==64'd0||
                   dut.transform_read_count_r!==64'd0||dut.transform_write_count_r!==64'd0||
                   dut.transform_response_wait_r!==64'd0||dut.transform_response_count_r!==64'd0||
                   dut.transform_stall_count_r!==32'd0||dut.transform_cache_hit_total_r!==32'd0||
                   dut.transform_cache_miss_total_r!==32'd0)
                    fail("counters not cleared on accepted START");
                if(dut.index_r!==32'd0||dut.beat_r!==2'd0||dut.cursor_r!==31'h08200000||dut.script_r!==32'h08200000)
                    fail("script cursor not initialised on accepted START");
                if(dut.result_base_r!==32'h10000000||dut.result_size_r!==dut.body_r[255:224]||
                   dut.result_limit_r!==dut.body_r[255:224]+32'h0ff80000||dut.volume_depth_r!==dut.body_r[191:160]||
                   dut.count_r!==dut.body_r[127:96]||dut.vol2_r!==(dut.body_r[31:0]===32'h324c4f56))
                    fail("result window / mode not latched on accepted START");
                if(last_fetch==0&&accepts>0)fail("TB internal: previous job never counted cycles");
            end
        end
    end

    // ---------------- RPC / 辅助任务 ----------------
    task automatic rpc(input logic [7:0] message,input logic [31:0] id,input logic [15:0] length,
                       input logic [511:0] body,input logic [7:0] expected);
        begin
            @(negedge clk_i);while(req_ready_o!==1'b1)@(negedge clk_i);
            req_msg_i=message;req_id_i=id;req_len_i=length;req_body_i=body;req_valid_i=1'b1;
            do @(negedge clk_i);while(resp_valid_o!==1'b1);
            reply=resp_body_o;
            if(reply[7:0]!==expected)begin
                $error("RPC msg=%h id=%0d len=%0d got=%0d expected=%0d cycle=%0d",message,id,length,reply[7:0],expected,cycle);
                $fflush(csv);$stop;
            end
            req_valid_i=1'b0;repeat(gap)@(negedge clk_i);
        end
    endtask
    task automatic wait_complete(input logic failure);
        integer guard;
        begin
            guard=0;
            do begin @(negedge clk_i);guard=guard+1;if(guard>4000)fail("job never completed");end while(dut.done_r!==1'b1);
            if((dut.error_r||dut.abort_r)!==failure)fail("job completion status");
        end
    endtask
    function automatic logic [511:0] mk(input bit vol2,input logic [31:0] count,input logic [31:0] depth);
        // magic[31:0] version[63:32] script[95:64] count[127:96] image_base[159:128]
        // depth[191:160] result_base[223:192] result_size[255:224]
        return {256'd0,depth<<19,32'h10000000,depth,32'h00400000,count,32'h08200000,
                vol2 ? 32'd2 : 32'd1, vol2 ? 32'h324c4f56 : 32'h314c4f56};
    endfunction
    function automatic logic [1599:0] snap();
        return {dut.held_r,dut.done_r,dut.error_r,dut.abort_r,dut.seen_r,dut.identity_r,dut.start_header_r,
                dut.fetch_cycles_r,dut.operator_cycles_r,dut.gather_cycles_r,dut.classify_cycles_r,
                dut.transform_read_count_r,dut.transform_write_count_r,dut.transform_stall_count_r,
                dut.transform_response_wait_r,dut.transform_response_count_r,dut.transform_kind4_cycles_r,
                dut.transform_pending_r,dut.transform_pending_peak_r,dut.transform_cache_hit_total_r,
                dut.transform_cache_miss_total_r,dut.script_r,dut.cursor_r,dut.count_r,dut.volume_depth_r,
                dut.index_r,dut.result_base_r,dut.result_size_r,dut.result_limit_r,dut.vol2_r,dut.beat_r,dut.v_r};
    endfunction
    function automatic logic [31:0] next_rand(input logic [31:0] value);
        logic [31:0] x;
        begin x=value;x=x^(x<<13);x=x^(x>>17);x=x^(x<<5);return x; end
    endfunction

    // 环境（storage_idle/image_*）与用例描述
    logic [511:0] c_header;
    logic [15:0] c_len;
    bit c_accept,c_job_error,c_idle,c_ready;
    logic [30:0] c_ibase;
    logic [31:0] c_islices;
    localparam int CASES=32;
    task automatic build_case(input int n);
        begin
            c_header=mk(1'b1,32'd1,32'd3);c_len=16'd64;c_accept=1'b0;c_job_error=1'b0;
            c_idle=1'b1;c_ready=1'b1;c_ibase=31'h00400000;c_islices=32'd2;
            case(n)
                0:  begin c_header=mk(1'b0,32'd1,32'd2);c_accept=1'b1; end                  // VOL1 合法
                1:  begin c_accept=1'b1; end                                                // VOL2 合法
                2:  begin c_header=mk(1'b1,32'd1,32'd1);c_accept=1'b1; end                  // 最小深度
                3:  begin c_header=mk(1'b1,32'd1,32'd480);c_accept=1'b1; end                // 最大深度
                4:  begin c_header=mk(1'b1,32'd2,32'd3);c_accept=1'b1;c_job_error=1'b1; end // 接受后因 END 位置错误失败
                5:  begin c_header=mk(1'b1,32'd65536,32'd3);c_accept=1'b1;c_job_error=1'b1; end
                6:  begin c_ready=1'b0;c_accept=1'b1; end                                   // VOL2 不检查 image_ready
                7:  begin c_header=mk(1'b0,32'd1,32'd5);c_islices=32'd5;c_accept=1'b1; end  // VOL1 深度=image_slices
                8:  c_len=16'd63;
                9:  c_len=16'd65;
                10: c_len=16'd0;
                11: c_header[95:64]=32'h08200020;
                12: c_header=mk(1'b1,32'd0,32'd3);
                13: c_header=mk(1'b1,32'd65537,32'd3);
                14: c_header[159:128]=32'h00400020;
                15: c_header=mk(1'b1,32'd1,32'd0);
                16: c_header=mk(1'b1,32'd1,32'd481);
                17: c_header[255:224]=c_header[255:224]+32'd32;
                18: c_header[223:192]=32'h10000020;
                19: c_header[288]=1'b1;
                20: c_header[511]=1'b1;
                21: c_header[256]=1'b1;
                22: begin c_header=mk(1'b0,32'd1,32'd2);c_header[63:32]=32'd2; end         // VOL1 魔数配 v2
                23: c_header[63:32]=32'd1;                                                 // VOL2 魔数配 v1
                24: c_header[31:0]=32'hdeadbeef;
                25: begin c_header=mk(1'b0,32'd1,32'd2);c_header[63:32]=32'd0; end
                26: begin c_header=mk(1'b0,32'd1,32'd2);c_idle=1'b0; end
                27: c_idle=1'b0;
                28: begin c_header=mk(1'b0,32'd1,32'd2);c_ready=1'b0; end
                29: begin c_header=mk(1'b0,32'd1,32'd2);c_ibase=31'h00400020; end
                30: begin c_header=mk(1'b0,32'd1,32'd2);c_islices=32'd3; end
                31: begin c_header=mk(1'b0,32'd1,32'd2);c_islices=32'd1; end
                default: fail("bad case index");
            endcase
        end
    endtask
    task automatic apply_env;
        begin storage_idle_i=c_idle;image_ready_i=c_ready;image_base_i=c_ibase;image_slices_i=c_islices; end
    endtask
    task automatic restore_env;
        begin storage_idle_i=1'b1;image_ready_i=1'b1;image_base_i=31'h00400000;image_slices_i=32'd2; end
    endtask

    task automatic run_case(input int n);
        logic [1599:0] snap_pre;
        logic [31:0] id;
        begin
            build_case(n);id=next_id;next_id=next_id+1;
            @(negedge clk_i);apply_env();
            if(c_accept)begin
                rpc(8'h26,id,c_len,c_header,8'd0);
                wait_complete(c_job_error);
                last_fetch=dut.fetch_cycles_r[31:0];
                rpc(8'h27,id,16'd0,512'd0,8'd0);
                repeat(3)@(negedge clk_i); // 第三个诊断字在 R_REPLY 之后一拍写入，零间隔时需等待
                if(reply[15:8]!==(c_job_error ? 8'd3 : 8'd2)||reply[127:96]!==32'd1||reply[63:32]!==id)
                    fail("QUERY after job");
                if(readback[0][31:0]!==32'h34474456||readback[0][223:192]==32'd0||
                   readback[0][223:192]!==dut.fetch_cycles_r[31:0]||readback[2][31:0]!==32'd0)
                    fail("VDG4 snapshot after job");
                rpc(8'h28,id,16'd0,512'd0,8'd0);
                jobs_done=jobs_done+1;
            end else begin
                snap_pre=snap();
                rpc(8'h26,id,c_len,c_header,8'd2);
                if(snap()!==snap_pre)fail("rejected START changed state");
                rejects=rejects+1;
            end
            restore_env();
        end
    endtask

    // ---------------- 主流程 ----------------
    integer accepted_expected=0;
    initial begin
        csv=$fopen("sim_trace.csv","w");
        $fdisplay(csv,"cycle,rpc_state,vol_state,req_valid,req_ready,resp_valid,status,accepts,rejects,held,done,error");
        $dumpfile("waveform.vcd");$dumpvars(1,tb_volume_start_check);
        $dumpvars(0,dut.r_r,dut.v_r,dut.held_r,dut.done_r,dut.error_r,dut.start_ok_r,dut.id_match_r,dut.start_go_r);
        readback[0]=256'd0;readback[1]=256'd0;readback[2]=256'd0;readback[3]=256'd0;
        repeat(8)@(negedge clk_i);rst_n_i=1'b1;repeat(4)@(negedge clk_i);

        // 阶段 A：全部用例各一次，间隔 3 拍
        gap=3;
        for(int n=0;n<CASES;n++)begin
            build_case(n);if(c_accept)accepted_expected=accepted_expected+1;
            run_case(n);
        end
        $display("[CASE PASSED] directed START matrix: %0d cases, accepts=%0d rejects=%0d",CASES,accepts,rejects);

        // 阶段 B：幂等重发 / 冲突 / 过期 / 重复释放
        begin
            logic [31:0] id;
            logic [511:0] h,other;
            logic [1599:0] s0,s1;
            id=32'd5000;h=mk(1'b1,32'd1,32'd3);other=h;other[64]=1'b1;                    // 脚本地址位 0 改变
            rpc(8'h26,id,16'd64,h,8'd0);accepted_expected=accepted_expected+1;
            wait_complete(1'b0);last_fetch=dut.fetch_cycles_r[31:0];s0=snap();
            rpc(8'h26,id,16'd64,h,8'd0);                       if(snap()!==s0)fail("idempotent retransmit changed state");
            rpc(8'h26,id,16'd64,other,8'd2);                   if(snap()!==s0)fail("conflicting header changed state");
            rpc(8'h26,id,16'd63,h,8'd2);                       if(snap()!==s0)fail("short retransmit changed state");
            rpc(8'h26,id+32'd1,16'd64,h,8'd1);                 if(snap()!==s0)fail("other-id START while held changed state");
            rpc(8'h27,id+32'd1,16'd0,512'd0,8'd6);             // 其他身份 QUERY：STALE
            rpc(8'h28,id,16'd0,512'd0,8'd0);s1=snap();
            if(dut.held_r!==1'b0)fail("RELEASE did not drop held");
            rpc(8'h26,id,16'd64,h,8'd6);                       if(snap()!==s1)fail("stale START changed state");
            rpc(8'h26,id,16'd64,other,8'd6);                   if(snap()!==s1)fail("stale mismatched START changed state");
            rpc(8'h28,id,16'd0,512'd0,8'd0);                   if(snap()!==s1)fail("second RELEASE changed state");
            rpc(8'h28,id+32'd1,16'd0,512'd0,8'd6);             // 未知身份 RELEASE：STALE
            rpc(8'h26,id+32'd2,16'd64,h,8'd0);accepted_expected=accepted_expected+1;
            wait_complete(1'b0);rpc(8'h28,id+32'd2,16'd0,512'd0,8'd0);
        end
        $display("[CASE PASSED] retransmit / conflict / stale / duplicate release status and state invariance");

        // 阶段 C：零间隔背靠背；先连续 6 个不同拒绝紧跟 1 个合法，再随机混合
        gap=0;
        for(int round=0;round<4;round++)begin
            for(int k=0;k<6;k++)run_case(8+((round*6+k)%24));
            build_case(1);accepted_expected=accepted_expected+1;run_case(1);
        end
        for(int i=0;i<120;i++)begin
            rng=next_rand(rng);
            build_case(int'(rng%CASES));
            if(c_accept)accepted_expected=accepted_expected+1;
            run_case(int'(rng%CASES));
        end
        gap=3;
        $display("[CASE PASSED] zero-gap back-to-back accept/reject mixture, accepts=%0d rejects=%0d",accepts,rejects);

        repeat(10)@(negedge clk_i);
        if(accepts!==accepted_expected)begin
            $error("accept count monitor=%0d expected=%0d",accepts,accepted_expected);$fflush(csv);$stop;
        end
        if(jobs_done<12||rejects<48)begin $error("coverage too small jobs=%0d rejects=%0d",jobs_done,rejects);$stop; end
        $display("[TB PASSED] 全部数据验证一致 accepts=%0d rejects=%0d cycles=%0d",accepts,rejects,cycle);
        $fclose(csv);$finish;
    end
    initial begin repeat(900000)@(posedge clk_i);$error("Simulation Timeout! cycle=%0d r=%0d v=%0d",cycle,dut.r_r,dut.v_r);$fflush(csv);$stop; end
endmodule
