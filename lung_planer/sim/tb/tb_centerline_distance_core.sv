`timescale 1ns/1ps
module tb_centerline_distance_core #(parameter USE_AXI=0);
    string vec_dir;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,start=0,abort_job=0;
    reg [31:0] nx,ny,nz,count,wx,wy,wz,timeout;
    reg [15:0] limit;
    reg [127:0] s_data=0;
    reg s_valid=0,s_last=0;
    reg [15:0] s_keep=16'hffff;
    wire s_ready,m_valid,m_last,mem_valid,mem_data_ready,busy,done;
    wire [127:0] m_data;
    wire [15:0] m_keep;
    wire [63:0] mem_address;
    reg m_ready=0,mem_ready=0,mem_data_valid=0,mem_error=0;
    reg [127:0] mem_data=0;
    wire [31:0] errors,processed,cycles,reads,candidates;
    reg [11:0] awaddr=0,araddr=0;
    reg [31:0] wdata=0;
    reg [3:0] wstrb=15;
    reg awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
    wire awready,wready,bvalid,arready,rvalid;
    wire [1:0] bresp,rresp;
    wire [31:0] rdata;
    generate if(!USE_AXI) begin:g_core
    centerline_distance_core dut(.clk(clk),.rst_n(rst_n),.start(start),.abort_job(abort_job),
        .nx(nx),.ny(ny),.nz(nz),.query_count(count),.weight_x(wx),.weight_y(wy),.weight_z(wz),
        .max_radius(limit),.timeout_cycles(timeout),.mask_base(64'h1000),
        .s_data(s_data),.s_keep(s_keep),.s_last(s_last),.s_valid(s_valid),.s_ready(s_ready),
        .m_data(m_data),.m_keep(m_keep),.m_last(m_last),.m_valid(m_valid),.m_ready(m_ready),
        .mem_valid(mem_valid),.mem_address(mem_address),.mem_ready(mem_ready),
        .mem_data(mem_data),.mem_data_valid(mem_data_valid),.mem_error(mem_error),.mem_data_ready(mem_data_ready),
        .busy(busy),.done(done),.errors(errors),.processed(processed),.cycles(cycles),.reads(reads),.candidates(candidates));
    end else begin:g_axi
        wire [7:0] arlen;
        wire [2:0] arsize,arprot;
        wire [1:0] arburst;
        wire [3:0] arcache;
        centerline_distance_axi dut(.aclk(clk),.aresetn(rst_n),
            .s_axi_awaddr(awaddr),.s_axi_awprot(3'b0),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
            .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
            .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
            .s_axi_araddr(araddr),.s_axi_arprot(3'b0),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
            .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
            .s_axis_tdata(s_data),.s_axis_tkeep(s_keep),.s_axis_tlast(s_last),.s_axis_tvalid(s_valid),.s_axis_tready(s_ready),
            .m_axis_tdata(m_data),.m_axis_tkeep(m_keep),.m_axis_tlast(m_last),.m_axis_tvalid(m_valid),.m_axis_tready(m_ready),
            .m_axi_araddr(mem_address),.m_axi_arlen(arlen),.m_axi_arsize(arsize),.m_axi_arburst(arburst),
            .m_axi_arprot(arprot),.m_axi_arcache(arcache),.m_axi_arvalid(mem_valid),.m_axi_arready(mem_ready),
            .m_axi_rdata(mem_data),.m_axi_rresp(mem_error?2'b10:2'b00),.m_axi_rlast(1'b1),
            .m_axi_rvalid(mem_data_valid),.m_axi_rready(mem_data_ready));
        assign busy=dut.busy; assign done=dut.done; assign errors=dut.errors;
        assign processed=dut.processed;assign cycles=dut.cycles;assign reads=dut.reads;assign candidates=dut.candidates;
        always @(posedge clk) if(rst_n&&mem_valid)
            if(arlen!=0||arsize!=4||arburst!=1) $fatal(1,"AXI mask read protocol");
    end endgenerate
    task axi_write(input [11:0] addr,input [31:0] value);
        begin
            // Alternate address-first/data-first, with B-channel backpressure.
            if(addr[2]) begin
                @(negedge clk);wdata=value;wvalid=1;
                do @(posedge clk); while(!wready);
                @(negedge clk);wvalid=0;
                repeat(2) @(negedge clk);
                awaddr=addr;awvalid=1;
                do @(posedge clk); while(!awready);
                @(negedge clk);awvalid=0;
            end else begin
                @(negedge clk);awaddr=addr;awvalid=1;
                do @(posedge clk); while(!awready);
                @(negedge clk);awvalid=0;
                repeat(2) @(negedge clk);
                wdata=value;wvalid=1;
                do @(posedge clk); while(!wready);
                @(negedge clk);wvalid=0;
            end
            wait(bvalid);repeat(3) @(negedge clk);
            if(!bvalid||bresp!=0) $fatal(1,"AXI write failed addr=%h resp=%h",addr,bresp);
            bready=1;@(negedge clk);bready=0;
        end
    endtask
    task axi_read_check(input [11:0] addr,input [31:0] expected_value);
        reg [31:0] captured;
        begin
            @(negedge clk);araddr=addr;arvalid=1;
            do @(posedge clk); while(!arready);
            @(negedge clk);arvalid=0;
            wait(rvalid);captured=rdata;
            repeat(3) @(negedge clk);
            if(!rvalid||rresp!=0||rdata!==captured||captured!==expected_value)
                $fatal(1,"AXI read/backpressure mismatch addr=%h actual=%h expected=%h",addr,rdata,expected_value);
            rready=1;@(negedge clk);rready=0;
        end
    endtask
    reg [7:0] memory[0:65535];
    reg [127:0] queries[0:1023];
    reg [63:0] expected[0:1023];
    reg [31:0] cfg_words[0:7];
    reg [31:0] rng=32'h791a31ab;
    integer sent=0,received=0,delay_count=0,read_index=0,i,case_index;
    integer qx,qy,qz,dx,dy,dz,px,py,pz;
    reg [63:0] actual;
    reg pending=0,check_results=0,inject_bus_error=0,hold_memory=0;
    reg output_stalled=0,request_stalled=0;
    reg [127:0] held_output;
    reg [63:0] held_address;
    always @(negedge clk) begin
        if(!rst_n) begin s_valid=0;m_ready=0;mem_ready=0;end
        else begin
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            m_ready=rng[0]|rng[1];
            mem_ready=!pending&&!hold_memory&&(rng[2]|rng[3]);
            if(!s_valid||s_ready) begin
                s_valid=sent<count && busy && (rng[4]|rng[5]);
                if(sent<count) begin s_data=queries[sent];s_last=sent==count-1;end
            end
        end
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            sent<=0;received<=0;pending<=0;mem_data_valid<=0;delay_count<=0;
            output_stalled<=0;request_stalled<=0;
        end else begin
            if(output_stalled && (!m_valid || m_data!==held_output)) $fatal(1,"Output changed under backpressure");
            if(request_stalled && (!mem_valid || mem_address!==held_address)) $fatal(1,"AXI request changed while stalled");
            output_stalled<=m_valid&&!m_ready; held_output<=m_data;
            request_stalled<=mem_valid&&!mem_ready; held_address<=mem_address;
            if(s_valid&&s_ready) sent<=sent+1;
            if(mem_valid&&mem_ready) begin
                if(mem_address[3:0]!=0 || mem_address<64'h1000 || mem_address>=64'h1000+nx*ny*nz+15)
                    $fatal(1,"Read outside aligned mask storage %h",mem_address);
                pending<=1;delay_count<=2+(rng[7:6]);
                read_index=mem_address-64'h1000;
                for(i=0;i<16;i=i+1) mem_data[i*8+:8]<=memory[read_index+i];
                mem_error<=inject_bus_error;
            end
            if(pending&&!mem_data_valid) begin
                if(delay_count==0) mem_data_valid<=1;
                else delay_count<=delay_count-1;
            end
            if(mem_data_valid&&mem_data_ready) begin mem_data_valid<=0;pending<=0;end
            if(m_valid&&m_ready) begin
                if(check_results) begin
                    if(m_keep!=16'hffff || m_last!=(received==count-1) || m_data[95:64]!=received || m_data[63:48]!=0)
                        $fatal(1,"Output framing/tag mismatch");
                    qx=queries[received][15:0];qy=queries[received][31:16];qz=queries[received][47:32];
                    dx=$signed(m_data[15:0]);dy=$signed(m_data[31:16]);dz=$signed(m_data[47:32]);
                    px=qx+dx;py=qy+dy;pz=qz+dz;
                    if(px<0||py<0||pz<0||px>=nx||py>=ny||pz>=nz) $fatal(1,"Invalid nearest point");
                    if(memory[(px*ny+py)*nz+pz]!=0) $fatal(1,"Nearest point is foreground");
                    actual=64'(dx*dx)*wx+64'(dy*dy)*wy+64'(dz*dz)*wz;
                    if(actual!==expected[received]) $fatal(1,"Distance mismatch case=%0d query=%0d actual=%0d expected=%0d delta=%0d,%0d,%0d",case_index,received,actual,expected[received],dx,dy,dz);
                end
                received<=received+1;
            end
        end
    end
    task reset_core;
        begin
            @(negedge clk);rst_n=0;start=0;abort_job=0;check_results=0;
            inject_bus_error=0;hold_memory=0;s_keep=16'hffff;timeout=10000000;
            repeat(5) @(negedge clk);
            rst_n=1;
        end
    endtask
    task start_core;
        begin
            if(USE_AXI) begin
                axi_write('h024,count);axi_write('h028,nx);axi_write('h02c,ny);axi_write('h030,nz);
                axi_write('h034,wx);axi_write('h038,wy);axi_write('h03c,wz);axi_write('h040,'h1000);
                axi_write('h044,0);axi_write('h048,limit);axi_write('h04c,timeout);axi_write(0,1);
            end else begin @(negedge clk);start=1;@(negedge clk);start=0;end
        end
    endtask
    task expect_error(input [31:0] value);
        begin
            wait(!busy&&errors!=0);@(negedge clk);
            if(errors!=value||busy) $fatal(1,"Expected error %h got %h",value,errors);
            $display("ERROR_CASE_PASS flag=%h cycles=%0d",value,cycles);
        end
    endtask
    initial begin
        reset_core;
        if(USE_AXI) begin
            axi_read_check('h004,'h434c4431);axi_read_check('h008,'h00010000);axi_read_check('h00c,7);
            axi_write('h034,'haabbccdd);
            wstrb=4'b0101;axi_write('h034,'h11223344);wstrb=15;
            axi_read_check('h034,'haa22cc44);
            axi_write('h044,'habcdef12);axi_read_check('h044,'habcdef12);
            $display("AXIL_READBACK_STROBE_PASS");
        end
        if(!$value$plusargs("CL_DIR=%s",vec_dir)) $fatal(1,"missing +CL_DIR=<data/sim_vectors/centerline_distance>");
        for(case_index=0;case_index<6;case_index=case_index+1) begin
            reset_core;
            $readmemh($sformatf("%0s/case%0d.config",vec_dir,case_index),cfg_words);
            nx=cfg_words[0];ny=cfg_words[1];nz=cfg_words[2];wx=cfg_words[3];wy=cfg_words[4];wz=cfg_words[5];count=cfg_words[6];limit=cfg_words[7];
            $readmemh($sformatf("%0s/case%0d.mask",vec_dir,case_index),memory,0,nx*ny*nz-1);
            $readmemh($sformatf("%0s/case%0d.queries",vec_dir,case_index),queries,0,count-1);
            $readmemh($sformatf("%0s/case%0d.expected",vec_dir,case_index),expected,0,count-1);
            check_results=1;
            start_core;
            wait(done);@(negedge clk);
            if(errors!=0||processed!=count||received!=count) $fatal(1,"Incomplete case %0d err=%h processed=%0d received=%0d",case_index,errors,processed,received);
            $display("DISTANCE_CASE_PASS case=%0d queries=%0d cycles=%0d reads=%0d",case_index,count,cycles,reads);
        end
        reset_core;nx=0;start_core;expect_error(1);
        reset_core;nx=31;count=1;queries[0]=128'hffff;start_core;expect_error(2);
        reset_core;queries[0]=0;s_keep=0;start_core;expect_error(4);
        reset_core;queries[0]=0;inject_bus_error=1;start_core;expect_error(8);
        reset_core;nx=5;ny=5;nz=5;count=1;limit=1;wx=1;wy=1;wz=1;queries[0]=128'h000200020002;
        for(i=0;i<125;i=i+1) memory[i]=1;
        start_core;expect_error(16);
        reset_core;timeout=20;hold_memory=1;start_core;
        // Timeout cannot retract a stalled read request. Release the bus and
        // require the outstanding response to drain before terminal failure.
        repeat(50) @(negedge clk);
        if(!busy||!mem_valid) $fatal(1,"Timeout abandoned outstanding request");
        hold_memory=0;expect_error(32);
        reset_core;start_core;wait(mem_valid);
        if(USE_AXI) axi_write(0,2);
        else begin @(negedge clk);abort_job=1;@(negedge clk);abort_job=0;end
        expect_error(64);
        $display("CENTERLINE_DISTANCE_CORE_TEST_PASS");$finish;
    end
    initial begin #300000000; $fatal(1,"Watchdog timeout");end
endmodule

module tb_centerline_distance_axi;
    tb_centerline_distance_core #(.USE_AXI(1)) runner();
endmodule
