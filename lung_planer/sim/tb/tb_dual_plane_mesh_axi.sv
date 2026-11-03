`timescale 1ns/1ps

// End-to-end protocol/geometry test uses the generated FP64 vendor IP models.
module tb_dual_plane_mesh_axi;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;
    reg [11:0] awaddr; reg awvalid; wire awready; reg [31:0] wdata; reg [3:0] wstrb=4'hf; reg wvalid; wire wready;
    wire [1:0] bresp; wire bvalid; reg bready=1;
    reg [11:0] araddr; reg arvalid; wire arready; wire [31:0] rdata; wire [1:0] rresp; wire rvalid; reg rready=1;
    wire [127:0] out_data; wire [15:0] out_keep; wire out_last; wire out_valid; reg out_ready=0; wire irq;
    wire [63:0] araddr_m,awaddr_m; wire [7:0] arlen_m,awlen_m; wire [2:0] arsize_m,awsize_m; wire [1:0] arburst_m,awburst_m;
    wire [2:0] arprot_m,awprot_m; wire [3:0] arcache_m; wire arvalid_m,arready_m; reg [127:0] rdata_m; reg [1:0] rresp_m=0; reg rlast_m=1; reg rvalid_m=0; wire rready_m;
    wire awvalid_m,awready_m; wire [127:0] wdata_m; wire [15:0] wstrb_m; wire wlast_m,wvalid_m,wready_m; reg bvalid_m=0; reg [1:0] bresp_m=0; wire bready_m;
    reg [127:0] mem [0:2047]; reg [63:0] pending_addr; reg pending_read;
    reg [7:0] read_remaining;
    integer i; integer write_index; integer mesh_double_cursor;
    assign arready_m=!rvalid_m && !pending_read; assign awready_m=1'b1; assign wready_m=1'b1;
    always @(posedge clk) if(rst_n && dut.geom_done && dut.tri_count==12)
        $display("TRI index=%0d polygon=%0d volume=%h area=%h ntri=%0d diag=%h v0=%h,%h,%h",
            dut.tri_index,dut.geometry.polygon_count,dut.geom_volume,dut.geom_source_area,
            dut.geom_source_triangles,dut.geom_diagnostics,
            dut.geometry.clip_x[63:0],dut.geometry.clip_y[63:0],dut.geometry.clip_z[63:0]);
    always @(posedge clk) begin
        if(!rst_n) begin rvalid_m<=0; pending_read<=0; read_remaining<=0; bvalid_m<=0; write_index<=0; end
        else begin
            if(arvalid_m && arready_m) begin
                if(arsize_m!=4 || arburst_m!=1 || araddr_m[3:0]!=0 ||
                   ({1'b0,araddr_m[11:0]} + (arlen_m+1)*16)>4096)
                    $fatal(1,"Invalid read burst");
                pending_addr<=araddr_m; pending_read<=1; read_remaining<=arlen_m;
            end
            if(pending_read && !rvalid_m) begin
                rdata_m<=mem[pending_addr[14:4]]; rvalid_m<=1;
                rlast_m<=(read_remaining==0); pending_read<=0;
            end
            if(rvalid_m && rready_m) begin
                rvalid_m<=0;
                if(read_remaining!=0) begin
                    read_remaining<=read_remaining-1; pending_addr<=pending_addr+16; pending_read<=1;
                end
            end
            if(awvalid_m && awready_m) begin write_index<=awaddr_m[14:4]; end
            if(wvalid_m && wready_m) begin mem[write_index]<=wdata_m; write_index<=write_index+1; if(wlast_m) bvalid_m<=1; end
            if(bvalid_m && bready_m) bvalid_m<=0;
        end
    end
    dual_plane_mesh_axi #(.MAX_TRIANGLES(16),.MAX_CANDIDATES(8),.ENABLE_STATUS_STREAM(1)) dut(
        .aclk(clk),.aresetn(rst_n),.s_axi_awaddr(awaddr),.s_axi_awprot(3'b0),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
        .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),.s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
        .s_axi_araddr(araddr),.s_axi_arprot(3'b0),.s_axi_arvalid(arvalid),.s_axi_arready(arready),.s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
        .m_axis_tdata(out_data),.m_axis_tkeep(out_keep),.m_axis_tlast(out_last),.m_axis_tvalid(out_valid),.m_axis_tready(out_ready),.irq(irq),
        .m_axi_araddr(araddr_m),.m_axi_arlen(arlen_m),.m_axi_arsize(arsize_m),.m_axi_arburst(arburst_m),.m_axi_arprot(arprot_m),.m_axi_arcache(arcache_m),.m_axi_arvalid(arvalid_m),.m_axi_arready(arready_m),.m_axi_rdata(rdata_m),.m_axi_rresp(rresp_m),.m_axi_rlast(rlast_m),.m_axi_rvalid(rvalid_m),.m_axi_rready(rready_m),
        .m_axi_awaddr(awaddr_m),.m_axi_awlen(awlen_m),.m_axi_awsize(awsize_m),.m_axi_awburst(awburst_m),.m_axi_awprot(awprot_m),.m_axi_awcache(arcache_m),.m_axi_awvalid(awvalid_m),.m_axi_awready(awready_m),.m_axi_wdata(wdata_m),.m_axi_wstrb(wstrb_m),.m_axi_wlast(wlast_m),.m_axi_wvalid(wvalid_m),.m_axi_wready(wready_m),.m_axi_bresp(bresp_m),.m_axi_bvalid(bvalid_m),.m_axi_bready(bready_m));
    task automatic axi_write(input [11:0] a,input [31:0] d);
        begin @(negedge clk); awaddr=a;wdata=d;awvalid=1;wvalid=1; while(!(awready&&wready)) @(negedge clk); @(negedge clk); awvalid=0;wvalid=0; while(!bvalid) @(negedge clk); end
    endtask
    task automatic mesh_double(input real value);
        begin
            mem[16'h200 + (mesh_double_cursor >> 1)][(mesh_double_cursor & 1)*64 +:64] = $realtobits(value);
            mesh_double_cursor=mesh_double_cursor+1;
        end
    endtask
    task automatic mesh_tri(input real ax,ay,az,bx,by,bz,cx,cy,cz);
        begin
            mesh_double(ax);mesh_double(ay);mesh_double(az);
            mesh_double(bx);mesh_double(by);mesh_double(bz);
            mesh_double(cx);mesh_double(cy);mesh_double(cz);
        end
    endtask
    initial begin
        awaddr=0;awvalid=0;wdata=0;wvalid=0;araddr=0;arvalid=0;
        for(i=0;i<2048;i=i+1) mem[i]=0;
        // Ten descriptor beats encode four broad half-spaces, a ridge origin,
        // and padding. Nine mesh beats encode two contiguous 72-byte triangles.
        mem[16'h100]=128'h0000000000000000_3ff0000000000000;
        mem[16'h101]=128'h4024000000000000_0000000000000000;
        mem[16'h102]=128'h0000000000000000_bff0000000000000;
        mem[16'h103]=128'h0000000000000000_0000000000000000;
        mem[16'h104]=128'h3ff0000000000000_0000000000000000;
        mem[16'h105]=128'h4024000000000000_0000000000000000;
        mem[16'h106]=128'hbff0000000000000_0000000000000000;
        mem[16'h107]=128'h0000000000000000_0000000000000000;
        mem[16'h108]=128'h0000000000000000_0000000000000000;
        mem[16'h109]=128'h0000000000000000_0000000000000000;
        mem[16'h200]=128'h0000000000000000_0000000000000000;
        mem[16'h201]=128'h3ff0000000000000_0000000000000000;
        mem[16'h202]=128'h0000000000000000_0000000000000000;
        mem[16'h203]=128'h3ff0000000000000_0000000000000000;
        mem[16'h204]=128'h0000000000000000_0000000000000000;
        mem[16'h205]=128'h0000000000000000_0000000000000000;
        mem[16'h206]=128'h0000000000000000_4000000000000000;
        mem[16'h207]=128'h0000000000000000_0000000000000000;
        mem[16'h208]=128'h0000000000000000_3ff0000000000000;
        repeat(4) @(negedge clk); rst_n=1;
        axi_write(12'h004,2); axi_write(12'h008,1); axi_write(12'h00c,7);
        axi_write(12'h020,64'h0000000000002000); axi_write(12'h028,64'h0000000000001000);
        axi_write(12'h030,64'h0000000000004000); axi_write(12'h040,16);
        axi_write(12'h038,64'h0000000000003000); axi_write(12'h044,1);
        axi_write(12'h000,1);
        wait(out_valid); if(out_data[95:64]!==32'h0000000a) $fatal(1,"mesh beat count missing: %h",out_data);
        if((out_data[63:32])!=0 || out_data[31:0]!==0 || !out_last) $fatal(1,"result framing mismatch: %h last=%b",out_data,out_last);
        if(mem[16'h302][127:96]!==0)
            $fatal(1,"unexpected candidate diagnostic: %h",mem[16'h302]);
        repeat(3) begin
            @(negedge clk);
            if(!out_valid || out_data[95:64]!==32'h0000000a || !out_last)
                $fatal(1,"status changed under backpressure");
        end
        out_ready=1;
        wait(dut.done_sticky);
        @(negedge clk);
        mem[16'h100]=0;
        mem[16'h101]={64'h4024000000000000,64'h3ff0000000000000};
        mem[16'h102]={64'h0000000000000000,64'hbff0000000000000};
        mem[16'h103]={64'hbfe0000000000000,64'h0000000000000000};
        mem[16'h104]={64'hbff0000000000000,64'h0000000000000000};
        mem[16'h105]={64'hbfe0000000000000,64'h0000000000000000};
        mem[16'h106]={64'h0000000000000000,64'h0000000000000000};
        mem[16'h107]={64'h4024000000000000,64'hbff0000000000000};
        mem[16'h108]={64'h3fe0000000000000,64'h3fe0000000000000};
        mem[16'h109]=0;
        for(i=0;i<64;i=i+1) mem[16'h200+i]=0;
        mesh_double_cursor=0;
        mesh_tri(0,0,0,0,1,0,1,0,0);
        mesh_tri(1,0,0,0,1,0,1,1,0);
        mesh_tri(0,0,1,1,0,1,0,1,1);
        mesh_tri(1,0,1,1,1,1,0,1,1);
        mesh_tri(0,0,0,0,0,1,0,1,0);
        mesh_tri(0,0,1,0,1,1,0,1,0);
        mesh_tri(1,0,0,1,1,0,1,0,1);
        mesh_tri(1,0,1,1,1,0,1,1,1);
        mesh_tri(0,0,0,1,0,0,0,0,1);
        mesh_tri(0,0,1,1,0,0,1,0,1);
        mesh_tri(0,1,0,0,1,1,1,1,0);
        mesh_tri(0,1,1,1,1,1,1,1,0);
        for(i=0;i<10;i=i+1) mem[16'h10a+i]=mem[16'h100+i];
        axi_write(12'h004,12);axi_write(12'h008,2);axi_write(12'h044,2);axi_write(12'h000,1);
        wait(out_valid);
        $display("CUBE volume=%h source_area=%h cut_area=%h source_triangles=%0d boundary=%0d flags=%h segments=%0d",
            mem[16'h300][63:0],mem[16'h300][127:64],mem[16'h301][63:0],
            mem[16'h301][95:64],mem[16'h302][63:32],mem[16'h302][127:96],dut.segment_index);
        $display("PLANES p0=%h,%h,%h,%h p1=%h,%h,%h,%h p2=%h,%h,%h,%h p3=%h,%h,%h,%h origin=%h,%h,%h",
            dut.plane_nx[0],dut.plane_ny[0],dut.plane_nz[0],dut.plane_off[0],
            dut.plane_nx[1],dut.plane_ny[1],dut.plane_nz[1],dut.plane_off[1],
            dut.plane_nx[2],dut.plane_ny[2],dut.plane_nz[2],dut.plane_off[2],
            dut.plane_nx[3],dut.plane_ny[3],dut.plane_nz[3],dut.plane_off[3],
            dut.origin_x,dut.origin_y,dut.origin_z);
        if(mem[16'h300][63:0]!==64'h3fd0000000000000)
            $fatal(1,"cube intersection volume expected=0.25 actual=%h",mem[16'h300][63:0]);
        if(mem[16'h300][127:64]!==64'h3ff8000000000000)
            $fatal(1,"cube source area expected=1.5 actual=%h",mem[16'h300][127:64]);
        if(mem[16'h301][63:0]!==64'h3ff0000000000000)
            $fatal(1,"cube cut area expected=1 actual=%h",mem[16'h301][63:0]);
        if(mem[16'h302][127:96]!==32'h00000000)
            $fatal(1,"cube diagnostic must be zero: %h",mem[16'h302]);
        wait(dut.done_sticky);
        if(mem[16'h304]!==mem[16'h300] || mem[16'h305]!==mem[16'h301] || mem[16'h306]!==mem[16'h302])
            $fatal(1,"consecutive candidates disagree: %h %h",mem[16'h300],mem[16'h304]);
        $display("DUAL_PLANE_MESH_RTL_GEOMETRY_PASS abi=0x00050000 candidates=2 volume=0.25 source_area=1.5 cut_area=1 status_stream_backpressure=1 diagnostics=0");
        $finish;
    end
    initial begin #2000000; $fatal(1,"watchdog"); end
endmodule
