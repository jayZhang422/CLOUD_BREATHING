`timescale 1ns/1ps
// 【文件类型：.sv】三源请求经两级仲裁、参数分流和实际异步FIFO的协议自校验。
module tb_continuous_route;
    logic clk=1'b0,ui_clk=1'b0,rst_n=1'b0,ui_rst_n=1'b0;
    realtime ch=4.0,uh=1.5;
    always #(ch) clk=~clk;
    initial begin #0.37;forever #(uh)ui_clk=~ui_clk;end
    logic [2:0] valid=3'd0,ready,write=3'd0,rvalid,rready=3'd0;
    logic [30:0] addr[0:2];
    logic [255:0] data[0:2];
    logic [31:0] mask[0:2];
    logic ev,er,ew,erv,err,sv,sr,sw,srv,srr,pending0,pending1;
    logic [30:0] ea,sa;
    logic [255:0] ed,sd,returned_data;
    logic [31:0] em,sm;
    logic [1:0] evs,svs,srs;
    logic split_ready,returned_valid,returned_ready,returned_error;
    logic dq,dr,drv,drr,de,cq,cr,cv,cready,ce;
    logic [30:0] ca;
    logic [255:0] cd,dd;
    logic uq,ur,uw,uv,urr,ue,active;
    logic [30:0] ua;
    logic [255:0] ud,urd;
    logic [31:0] um;
    logic [256:0] dresponse=257'd0,cresponse=257'd0;
    logic dp=1'b0,cp=1'b0,allow_return=1'b1,allow_accept=1'b1;
    integer delay_d=0,delay_c=0,cycle=0,ui_cycle=0,phase=0,csv;
    logic [256:0] expected[0:2][0:511];
    integer sent[0:2],received[0:2];
    integer max_engine=0,max_service=0,checks=0;
    logic request_stalled=1'b0,response_stalled=1'b0,consume_enable=1'b1;
    logic [319:0] held_request;
    logic [256:0] held_response;
    assign ready[1:0]=srs;
    assign ready[2]=svs[1];
    assign rvalid[1:0]=evs;
    assign rvalid[2]=srv && svs[0]; // overwritten below by explicit service response
    logic [1:0] service_responses;
    // 每个源都通过自身valid分发；数据和错误由当前保序队首共同提供。
    op_mem_arbiter engine (
        .clk_i(clk),.rst_n_i(rst_n),.req_valid_i(valid[1:0]),.req_ready_o(srs),
        .req_write_i(write[1:0]),.req_addr_i({addr[1],addr[0]}),.req_data_i({data[1],data[0]}),
        .req_mask_i({mask[1],mask[0]}),.rsp_valid_o(evs),.rsp_ready_i(rready[1:0]),.pending_o(pending0),
        .mem_valid_o(ev),.mem_ready_i(er),.mem_write_o(ew),.mem_addr_o(ea),.mem_data_o(ed),.mem_mask_o(em),
        .mem_rsp_valid_i(service_responses[0]),.mem_rsp_ready_o(err));
    op_mem_arbiter service (
        .clk_i(clk),.rst_n_i(rst_n),.req_valid_i({valid[2],ev}),.req_ready_o(svs),
        .req_write_i({write[2],ew}),.req_addr_i({addr[2],ea}),.req_data_i({data[2],ed}),
        .req_mask_i({mask[2],em}),.rsp_valid_o(service_responses),.rsp_ready_i({rready[2],err}),.pending_o(pending1),
        .mem_valid_o(sv),.mem_ready_i(split_ready),.mem_write_o(sw),.mem_addr_o(sa),.mem_data_o(sd),.mem_mask_o(sm),
        .mem_rsp_valid_i(returned_valid),.mem_rsp_ready_o(returned_ready));
    assign er=svs[0];
    op_coeff_split split (
        .clk_i(clk),.rst_n_i(rst_n),.req_valid_i(sv),.req_ready_o(split_ready),.req_write_i(sw),.req_addr_i(sa),
        .rsp_valid_o(returned_valid),.rsp_ready_i(returned_ready),.rsp_data_o(returned_data),.rsp_error_o(returned_error),
        .ddr_req_valid_o(dq),.ddr_req_ready_i(dr),.ddr_rsp_valid_i(drv),.ddr_rsp_ready_o(drr),.ddr_rsp_data_i(dd),.ddr_rsp_error_i(de),
        .coeff_req_valid_o(cq),.coeff_req_ready_i(cr),.coeff_req_addr_o(ca),.coeff_rsp_valid_i(cv),.coeff_rsp_ready_o(cready),
        .coeff_rsp_data_i(cd),.coeff_rsp_error_i(ce));
    op_mem_cdc cdc (
        .compute_clk_i(clk),.compute_rst_n_i(rst_n),.ui_clk_i(ui_clk),.ui_rst_n_i(ui_rst_n),
        .req_valid_i(dq),.req_ready_o(dr),.req_write_i(sw),.req_addr_i(sa),.req_data_i(sd),.req_mask_i(sm),
        .rsp_valid_o(drv),.rsp_ready_i(drr),.rsp_data_o(dd),.rsp_error_o(de),
        .ui_req_valid_o(uq),.ui_req_ready_i(ur),.ui_req_write_o(uw),.ui_req_addr_o(ua),.ui_req_data_o(ud),.ui_req_mask_o(um),
        .ui_rsp_valid_i(uv),.ui_rsp_ready_o(urr),.ui_rsp_data_i(urd),.ui_rsp_error_i(ue),.active_ui_o(active));
    assign ur=allow_accept && !dp && ui_cycle%5!=0;
    assign uv=dp && delay_d==0 && allow_return;
    assign {ue,urd}=dresponse;
    assign cr=!cp && cycle%7!=0;
    assign cv=cp && delay_c==0 && allow_return;
    assign {ce,cd}=cresponse;
    function automatic logic [256:0] echo_response(input bit rom,input bit wr,
        input logic [30:0] a,input logic [255:0] d,input logic [31:0] m);
        if(rom && wr)return {1'b1,256'd0};
        return {rom ? 1'b0 : a[8],wr ? d^{8{m}} : {8{{1'b0,a}}}};
    endfunction
    always @(posedge ui_clk) begin
        ui_cycle<=ui_cycle+1;
        if(!rst_n || !ui_rst_n)begin dp<=1'b0;delay_d<=0;request_stalled<=1'b0;end
        else begin
            if(request_stalled && (uq !== 1'b1 || {uw,ua,um,ud} !== held_request))begin
                $error("UI request changed under backpressure phase=%0d cycle=%0d",phase,ui_cycle);$stop;
            end
            request_stalled<=uq && !ur;held_request<={uw,ua,um,ud};
            if(uq && ur)begin dp<=1'b1;delay_d<=3+ui_cycle%9;dresponse<=echo_response(0,uw,ua,ud,um);end
            else if(uv && urr)dp<=1'b0;
            else if(delay_d>0)delay_d<=delay_d-1;
        end
    end
    always @(posedge clk)begin
        cycle<=cycle+1;
        if(!rst_n)begin
            cp<=1'b0;delay_c<=0;response_stalled<=1'b0;
            for(int s=0;s<3;s++)begin sent[s]=0;received[s]=0;end
        end else begin
            if(cq && cr)begin cp<=1'b1;delay_c<=2+cycle%11;cresponse<=echo_response(1,0,ca,256'd0,32'd0);end
            else if(cv && cready)cp<=1'b0;
            else if(delay_c>0)delay_c<=delay_c-1;
            if(response_stalled && (returned_valid !== 1'b1 || {returned_error,returned_data} !== held_response))begin
                $error("ordered response changed under backpressure phase=%0d cycle=%0d",phase,cycle);$stop;
            end
            response_stalled<=returned_valid && !returned_ready;held_response<={returned_error,returned_data};
            for(int s=0;s<3;s++) begin
                if(valid[s] && ready[s])begin
                    expected[s][sent[s]]=echo_response(addr[s]>=31'h100000 && addr[s]<31'h159600,write[s],addr[s],data[s],mask[s]);
                    sent[s]++;
                end
                if((s==2 ? service_responses[1] : evs[s]) && rready[s])begin
                    if(received[s]>=sent[s] || {returned_error,returned_data} !== expected[s][received[s]])begin
                        $error("source/order/payload mismatch phase=%0d source=%0d item=%0d cycle=%0d",phase,s,received[s],cycle);$stop;
                    end
                    received[s]++;checks++;
                end
            end
            if(engine.count_r>max_engine)max_engine=engine.count_r;
            if(service.count_r>max_service)max_service=service.count_r;
            $fdisplay(csv,"%0d,%0d,%b,%b,%b,%b,%b,%b,%b,%0d,%0d",cycle,phase,valid,ready,evs,service_responses,uq,ur,uv,engine.count_r,service.count_r);
        end
    end
    task automatic send(input int source,input int count,input int salt);
        for(int n=0;n<count;n++)begin
            @(negedge clk);valid[source]=1'b1;
            write[source]=(n+source)%3==0;
            addr[source]=((n+source)%4==0 ? 31'h100000 : 31'h200000)+31'((n+salt+source*128)*32);
            data[source]={8{32'hac130000^32'(n+salt+source*128)}};
            mask[source]=32'hf00f0101^32'(n+source);
            do @(posedge clk);while(ready[source] !== 1'b1);
        end
        @(negedge clk);valid[source]=1'b0;
    endtask
    always @(negedge clk) begin
        if(consume_enable)rready={cycle%5!=0,cycle%7!=0,cycle%3!=0};
        else rready=3'd0;
    end
    task automatic drain;
        while(received[0]<sent[0] || received[1]<sent[1] || received[2]<sent[2])begin
            @(negedge clk);
        end
        @(negedge clk);
        repeat(40)@(negedge clk);
    endtask
    initial begin
        csv=$fopen("sim_trace.csv","w");
        $fdisplay(csv,"cycle,phase,valid,ready,engine_rsp,service_rsp,ui_req,ui_ready,ui_rsp,engine_pending,service_pending");
        $dumpfile("waveform.vcd");$dumpvars(0,clk,ui_clk,rst_n,ui_rst_n,valid,ready,rready,evs,service_responses,uq,ur,uv);
        for(int s=0;s<3;s++)begin addr[s]=31'd0;data[s]=256'd0;mask[s]=32'd0;end
        repeat(20)@(negedge clk);ui_rst_n=1'b1;repeat(20)@(negedge clk);
        if(dr !== 1'b0 || drv !== 1'b0 || uq !== 1'b0 || urr !== 1'b0)begin
            $error("CDC enabled before compute reset release");$stop;
        end
        rst_n=1'b1;repeat(32)@(negedge clk);
        for(int ratio=0;ratio<3;ratio++)begin
            phase=ratio;
            case(ratio)0:begin ch=4.0;uh=1.5;end 1:begin ch=2.5;uh=5.5;end 2:begin ch=4.13;uh=1.49;end endcase
            fork send(0,64,ratio*64);send(1,64,ratio*64);send(2,64,ratio*64);drain();join
            drain();
        end
        if(max_engine<4 || max_service<4 || checks!==576)begin
            $error("insufficient concurrency checks=%0d engine=%0d service=%0d",checks,max_engine,max_service);$stop;
        end
        phase=3;allow_return=1'b0;consume_enable=1'b0;
        send(0,4,400);repeat(12)@(negedge clk);
        ui_rst_n=1'b0;#0.2;rst_n=1'b0;valid=3'd0;repeat(20)@(negedge clk);
        allow_return=1'b1;consume_enable=1'b1;rst_n=1'b1;repeat(20)@(negedge clk);
        if(dr !== 1'b0 || drv !== 1'b0 || uq !== 1'b0 || urr !== 1'b0)begin
            $error("CDC enabled before UI reset release");$stop;
        end
        ui_rst_n=1'b1;repeat(40)@(negedge clk);
        if(returned_valid !== 1'b0 || active !== 1'b0)begin $error("stale response after reset");$stop;end
        fork send(0,16,500);send(1,16,500);send(2,16,500);drain();join
        drain();
        if(checks!==624)begin $error("reset recovery count=%0d",checks);$stop;end
        phase=4;ui_rst_n=1'b0;repeat(20)@(negedge clk);
        if(dr !== 1'b0 || drv !== 1'b0 || uq !== 1'b0 || urr !== 1'b0)begin
            $error("CDC not quiescent during UI-only reset");$stop;
        end
        ui_rst_n=1'b1;repeat(40)@(negedge clk);send(0,8,600);drain();
        phase=5;rst_n=1'b0;repeat(20)@(negedge clk);rst_n=1'b1;
        repeat(40)@(negedge clk);send(0,8,700);drain();
        if(checks!==640)begin $error("independent reset recovery count=%0d",checks);$stop;end
        $fclose(csv);$display("[TB PASSED] routed_responses=%0d ratios=3 independent_resets=both_orders+each_domain engine_depth=%0d service_depth=%0d",checks,max_engine,max_service);$finish;
    end
    initial begin repeat(1000000)@(posedge clk);$fatal(1,"Simulation Timeout");end
endmodule
