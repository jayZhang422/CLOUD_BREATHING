`timescale 1ns/1ps
// 【文件类型：.sv】op_volume_service 的 DDR 上限放宽（0x20000000 → 0x30000000）定向自校验（真实 DUT）。
// 一、kind-4 视图范围（op_volume_service.VIEW_TOP）：脚本为 1 条 kind-4 记录 + END；DDR 为稀疏模型，
//     接受判据 = FSM 进入过 V_TRANSFORM 且 error_r=0；拒绝判据 = 从未进入 V_TRANSFORM 且 error_r=1。
//     接受：低区、结果区末尾、旧上限 0x20000000 前、扩展区起点、恰好 0x30000000、480 平面大视图。
//     拒绝：越过 0x30000000（1 个 32B 与整块）、落入结果区、落入参数区缺口、低于图像基址、
//           低区溢出、32 位回绕、基址未 32B 对齐、字节数小于 平面数×平面步长、平面步长小于 行步长×高度、
//           邻层索引越界、目的地址低于下限、保留位非零。
// 二、主机 WRITE/READ 上限（op_service.HOST_DDR_TOP）：0x2fffffc0..0x30000000 与 0x20000000 起点可写可读，
//     越界请求返回状态 2 且 DDR 无写入；读回数据逐行与写入图样全等。
// 自校验：全等比较 !==；任何不一致 $error + $stop；全部通过打印 [TB PASSED] 并 $finish；含看门狗。
// 运行：与 tb_volume_start_check 相同（工程仿真集，含 op_perf_bram IP），顶层选 tb_volume_ext_range。
module tb_volume_ext_range;
    logic clk_i=1'b0,rst_n_i=1'b0,storage_idle_i=1'b1,image_ready_i=1'b0;
    logic [30:0] image_base_i=31'h00400000;
    logic [31:0] image_slices_i=32'd0;
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
    // 变换缩到 32 像素：接受用例只需走完 V_TRANSFORM，不必跑 512×512。
    op_volume_service #(.TRANSFORM_PIXELS(19'd32),.TRANSFORM_WIDTH(10'd32),.TRANSFORM_HEIGHT(10'd1)) dut(.*);

    // ---------------- 稀疏 DDR 模型：一次一笔，确定性反压 ----------------
    logic [255:0] store [int unsigned];
    logic pending=1'b0;
    logic [255:0] response=256'd0;
    integer cycle=0,delay_r=0,csv,ddr_writes=0,case_id=0;
    always #2 clk_i=~clk_i;
    assign mem_ready_i=rst_n_i&&!pending&&cycle%5!=0;
    assign mem_rsp_valid_i=pending&&delay_r==0;
    assign mem_rsp_data_i=response;
    assign mem_rsp_error_i=1'b0;
    function automatic logic [255:0] line_at(input logic [30:0] address);
        int unsigned key;
        begin key=address[30:5];line_at=store.exists(key) ? store[key] : 256'd0; end
    endfunction
    task automatic apply_write(input logic [30:0] address,input logic [255:0] data,input logic [31:0] mask);
        logic [255:0] line;
        int unsigned key;
        begin
            key=address[30:5];line=store.exists(key) ? store[key] : 256'd0;
            for(int i=0;i<32;i++)if(mask[i])line[i*8+:8]=data[i*8+:8];
            store[key]=line;
        end
    endtask

    // 主机 WRITE 的数据图样：每次写入用不同 tag，行序号参与，便于识别陈旧或错位数据。
    logic [31:0] wr_tag=32'd0;
    function automatic logic [255:0] wr_pattern(input logic [31:0] tag,input logic [4:0] idx);
        return {8{32'h5a000000+tag*32'h00001001+{27'd0,idx}*32'h00010203}};
    endfunction
    always @(posedge clk_i)req_data_i<=wr_pattern(wr_tag,req_data_addr_o); // 模拟 BRAM 一拍读延迟

    logic [255:0] readback[0:31];
    logic saw_transform=1'b0;
    always @(posedge clk_i)begin
        cycle=cycle+1;
        $fdisplay(csv,"%0d,%0d,%0d,%0d,%b,%b,%h,%b,%b,%b,%b,%b,%b",cycle,case_id,dut.r_r,dut.v_r,mem_valid_o,mem_ready_i,
                  mem_addr_o,mem_write_o,dut.held_r,dut.done_r,dut.error_r,saw_transform,resp_valid_o);
        if(pending&&delay_r>0)delay_r<=delay_r-1;
        if(mem_rsp_valid_i&&mem_rsp_ready_o)pending<=1'b0;
        if(mem_valid_o&&mem_ready_i)begin
            pending<=1'b1;delay_r<=cycle%3+1;response<=line_at(mem_addr_o);
            if(mem_write_o&&mem_mask_o!==32'd0)begin apply_write(mem_addr_o,mem_data_o,mem_mask_o);ddr_writes=ddr_writes+1;end
        end
        if(resp_data_we_o)readback[resp_data_addr_o]=resp_data_o;
        if(rst_n_i&&dut.v_r===dut.V_TRANSFORM)saw_transform=1'b1;
    end

    task automatic fail(input string text);
        begin $error("%s case=%0d cycle=%0d rpc=%0d vol=%0d",text,case_id,cycle,dut.r_r,dut.v_r);$fflush(csv);$stop; end
    endtask
    logic [127:0] reply;
    task automatic rpc(input logic [7:0] message,input logic [31:0] id,input logic [15:0] length,
                       input logic [511:0] body,input logic [7:0] expected);
        integer guard;
        begin
            @(negedge clk_i);guard=0;
            while(req_ready_o!==1'b1)begin @(negedge clk_i);guard=guard+1;if(guard>20000)fail("req_ready_o never returned");end
            req_msg_i=message;req_id_i=id;req_len_i=length;req_body_i=body;req_valid_i=1'b1;
            guard=0;
            do begin @(negedge clk_i);guard=guard+1;if(guard>20000)fail("no RPC reply");end while(resp_valid_o!==1'b1);
            reply=resp_body_o;
            if(reply[7:0]!==expected)begin
                $error("RPC msg=%h id=%0d len=%0d status got=%0d expected=%0d case=%0d cycle=%0d",
                       message,id,length,reply[7:0],expected,case_id,cycle);
                $fflush(csv);$stop;
            end
            req_valid_i=1'b0;repeat(4)@(negedge clk_i);
        end
    endtask

    // ---------------- 一、kind-4 视图范围 ----------------
    // START 头：VOL2、脚本 0x08200000、2 条记录、深度 3（结果区 [0x10000000,0x10180000)）。
    function automatic logic [511:0] mk(input logic [31:0] count,input logic [31:0] depth);
        return {256'd0,depth<<19,32'h10000000,depth,32'h00400000,count,32'h08200000,32'd2,32'h324c4f56};
    endfunction
    logic [511:0] cmd;
    bit k_accept,k_reserved;
    logic [31:0] k_base,k_dest,k_p,k_bytes,k_ps,k_rs,k_n0,k_n1,k_n2;
    logic [15:0] k_w,k_h;
    string k_name;
    localparam int KCASES=19;
    task automatic build_cmd(input int n);
        begin
            k_base=32'h00600000;k_dest=32'h0a000000;k_p=32'd2;k_ps=32'd128;k_rs=32'd64;k_bytes=32'd256;
            k_w=16'd16;k_h=16'd1;k_n0=32'd0;k_n1=32'd0;k_n2=32'd1;k_reserved=1'b0;k_accept=1'b1;k_name="low window";
            case(n)
                0:  ;
                1:  begin k_base=32'h10180000;k_name="result end"; end
                2:  begin k_base=32'h1fffff00;k_name="old top (ends 0x20000000)"; end
                3:  begin k_base=32'h20000000;k_name="extension start"; end
                4:  begin k_base=32'h2fffff00;k_name="new top (ends 0x30000000)"; end
                5:  begin k_base=32'h28800000;k_p=32'd480;k_ps=32'h00040000;k_bytes=32'h07800000;
                          k_n1=32'd479;k_name="480-plane view ending at top"; end
                6:  begin k_base=32'h2fffff20;k_accept=1'b0;k_name="one line over top"; end
                7:  begin k_base=32'h30000000;k_accept=1'b0;k_name="starts at top"; end
                8:  begin k_base=32'h10000000;k_accept=1'b0;k_name="inside result region"; end
                9:  begin k_base=32'h08000000;k_accept=1'b0;k_name="parameter window gap"; end
                10: begin k_base=32'h00200000;k_accept=1'b0;k_name="below image base"; end
                11: begin k_base=32'h07ffff00;k_bytes=32'h200;k_accept=1'b0;k_name="low window overflow"; end
                12: begin k_base=32'hfffffe00;k_bytes=32'h200;k_accept=1'b0;k_name="32-bit wrap"; end
                13: begin k_base=32'h20000010;k_accept=1'b0;k_name="base not 32B aligned"; end
                14: begin k_base=32'h20000000;k_bytes=32'd255;k_accept=1'b0;k_name="bytes < planes*plane_stride"; end
                15: begin k_base=32'h20000000;k_ps=32'd63;k_accept=1'b0;k_name="plane_stride < row_stride*height"; end
                16: begin k_base=32'h20000000;k_n2=32'd2;k_accept=1'b0;k_name="neighbor index == planes"; end
                17: begin k_dest=32'h09ffffe0;k_accept=1'b0;k_name="destination below window"; end
                18: begin k_base=32'h20000000;k_reserved=1'b1;k_accept=1'b0;k_name="reserved bits set"; end
                default: fail("bad kind-4 case index");
            endcase
            cmd=512'd0;
            cmd[7:0]=8'd4;cmd[23:16]=8'd1;
            cmd[63:32]=k_base;cmd[95:64]=k_dest;cmd[127:96]=k_p;cmd[159:128]=k_bytes;
            cmd[175:160]=k_w;cmd[191:176]=k_h;cmd[223:192]=k_rs;cmd[255:224]=k_ps;
            cmd[287:256]=k_n0;cmd[319:288]=k_n1;cmd[351:320]=k_n2;
            cmd[400]=k_reserved;
        end
    endtask
    task automatic fill_script(input logic [511:0] command);
        begin // 记录 0：kind=4 + 64B 命令；记录 1：END(0xff) + 全零命令（未写入的行读出为 0）。
            store[32'h08200000>>5]=256'd4;
            store[(32'h08200000>>5)+1]=command[255:0];
            store[(32'h08200000>>5)+2]=command[511:256];
            store[(32'h08200000>>5)+3]=256'hff;
            store[(32'h08200000>>5)+4]=256'd0;
            store[(32'h08200000>>5)+5]=256'd0;
        end
    endtask
    integer kind4_accepted=0,kind4_rejected=0,next_id=2000;
    task automatic run_kind4(input int n);
        logic [31:0] id;
        integer guard;
        begin
            build_cmd(n);id=next_id;next_id=next_id+1;case_id=n;saw_transform=1'b0;
            fill_script(cmd);
            rpc(8'h26,id,16'd64,mk(32'd2,32'd3),8'd0);
            guard=0;
            do begin @(negedge clk_i);guard=guard+1;if(guard>60000)fail("job never completed");end while(dut.done_r!==1'b1);
            if(saw_transform!==k_accept)fail("V_TRANSFORM visited / not visited contrary to expectation");
            if(dut.error_r!==(k_accept ? 1'b0 : 1'b1))fail("error_r contrary to expectation");
            if(pending)fail("response still pending at job end");
            rpc(8'h28,id,16'd0,512'd0,8'd0);
            if(k_accept)kind4_accepted=kind4_accepted+1;else kind4_rejected=kind4_rejected+1;
            $display("[CASE PASSED] kind-4 view range case=%0d %s -> %s",n,k_name,k_accept ? "accepted" : "rejected");
        end
    endtask

    // ---------------- 二、主机 WRITE / 诊断 READ ----------------
    integer host_writes_ok=0,host_reads_ok=0,host_rejects=0;
    task automatic host_write(input logic [30:0] addr,input int len,input logic [31:0] tag,input logic [7:0] expected);
        logic [511:0] body;
        integer writes_before;
        begin
            body=512'd0;body[31:0]={1'b0,addr};body[47:32]=16'(len);body[63:48]=16'd0;
            wr_tag=tag;writes_before=ddr_writes;
            rpc(8'h20,32'd0,16'(8+len),body,expected);
            if(expected===8'd0)begin
                if(ddr_writes-writes_before!==len/32)fail("accepted WRITE issued wrong number of DDR writes");
                for(int k=0;k<len/32;k++)
                    if(line_at(addr+31'(k*32))!==wr_pattern(tag,5'(k)))fail("WRITE data not stored at expected address");
                host_writes_ok=host_writes_ok+1;
            end else begin
                if(ddr_writes!==writes_before)fail("rejected WRITE reached DDR");
                host_rejects=host_rejects+1;
            end
            $display("[CASE PASSED] host WRITE addr=%h len=%0d status=%0d",addr,len,expected);
        end
    endtask
    task automatic host_read(input logic [30:0] addr,input int len,input logic [31:0] tag,input logic [7:0] expected);
        logic [511:0] body;
        begin
            body=512'd0;body[31:0]={1'b0,addr};body[47:32]=16'(len);body[63:48]=16'd1; // 诊断读：id=0、flags=1
            for(int k=0;k<32;k++)readback[k]=256'd0;
            rpc(8'h23,32'd0,16'd8,body,expected);
            if(expected===8'd0)begin
                for(int k=0;k<len/32;k++)
                    if(readback[k]!==wr_pattern(tag,5'(k)))fail("READ data differs from written pattern");
                host_reads_ok=host_reads_ok+1;
            end else host_rejects=host_rejects+1;
            $display("[CASE PASSED] host READ addr=%h len=%0d status=%0d",addr,len,expected);
        end
    endtask

    initial begin
        csv=$fopen("sim_trace.csv","w");
        $fdisplay(csv,"cycle,case,rpc_state,vol_state,mem_valid,mem_ready,mem_addr,mem_write,held,done,error,saw_transform,resp_valid");
        $dumpfile("waveform.vcd");$dumpvars(1,tb_volume_ext_range);
        $dumpvars(0,dut.r_r,dut.v_r,dut.held_r,dut.done_r,dut.error_r,dut.command_r);
        for(int k=0;k<32;k++)readback[k]=256'd0;
        repeat(8)@(negedge clk_i);rst_n_i=1'b1;repeat(4)@(negedge clk_i);

        // 阶段 A：主机 WRITE/READ 上限。
        case_id=100;
        host_write(31'h09000000,64,32'd1,8'd0);            // 低区对照
        host_write(31'h20000000,64,32'd2,8'd0);            // 原先越界的扩展区起点
        host_write(31'h2fffffc0,64,32'd3,8'd0);            // 末地址恰为 0x30000000
        host_write(31'h2fffffe0,64,32'd4,8'd2);            // 越过 0x30000000 一行：拒绝且无 DDR 写
        host_write(31'h30000000,64,32'd5,8'd2);            // 完全越界
        host_read(31'h20000000,64,32'd2,8'd0);
        host_read(31'h2fffffc0,64,32'd3,8'd0);
        host_read(31'h2fffffe0,64,32'd3,8'd2);             // 读越界：拒绝
        host_read(31'h30000000,64,32'd3,8'd2);
        $display("[CASE PASSED] host WRITE/READ range matrix writes=%0d reads=%0d rejects=%0d",host_writes_ok,host_reads_ok,host_rejects);

        // 阶段 B：kind-4 视图范围。
        for(int n=0;n<KCASES;n++)run_kind4(n);
        $display("[CASE PASSED] kind-4 view range matrix accepted=%0d rejected=%0d",kind4_accepted,kind4_rejected);

        if(kind4_accepted!==6||kind4_rejected!==13||host_writes_ok!==3||host_reads_ok!==2||host_rejects!==4)begin
            $error("coverage mismatch acc=%0d rej=%0d w=%0d r=%0d hrej=%0d",kind4_accepted,kind4_rejected,host_writes_ok,host_reads_ok,host_rejects);$stop;
        end
        $display("[TB PASSED] 全部数据验证一致 kind4=%0d/%0d host=%0d/%0d/%0d cycles=%0d",
                 kind4_accepted,kind4_rejected,host_writes_ok,host_reads_ok,host_rejects,cycle);
        $fclose(csv);$finish;
    end
    initial begin repeat(3000000)@(posedge clk_i);$fatal(1,"Simulation Timeout! case=%0d cycle=%0d rpc=%0d vol=%0d",case_id,cycle,dut.r_r,dut.v_r);end
endmodule
