`timescale 1ns/1ps
// Finite self-checking DDR mesh/BVH ray interface test.
module tb_lung_ray_mesh_bvh;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0;
    reg [11:0] awaddr = 0; reg [2:0] awprot = 0; reg awvalid = 0; wire awready;
    reg [31:0] wdata = 0; reg [3:0] wstrb = 4'hf; reg wvalid = 0; wire wready;
    wire [1:0] bresp; wire bvalid; reg bready = 0;
    reg [11:0] araddr = 0; reg [2:0] arprot = 0; reg arvalid = 0; wire arready;
    wire [31:0] rdata; wire [1:0] rresp; wire rvalid; reg rready = 0;
    wire [127:0] m_data; wire [15:0] m_keep; wire m_last; wire m_valid; reg m_ready = 0; wire irq;
    wire [63:0] m_axi_araddr; wire [7:0] m_axi_arlen; wire [2:0] m_axi_arsize;
    wire [1:0] m_axi_arburst; wire [2:0] m_axi_arprot; wire [3:0] m_axi_arcache;
    wire m_axi_arvalid; reg m_axi_arready = 0;
    reg [127:0] m_axi_rdata = 0; reg [1:0] m_axi_rresp = 0;
    reg m_axi_rlast = 0; reg m_axi_rvalid = 0; wire m_axi_rready;
    reg [127:0] ray_data = 0; reg [15:0] ray_keep = 16'hffff;
    reg ray_last = 0; reg ray_valid = 0; wire ray_ready;
    reg [127:0] ddr [0:299999]; reg [127:0] nodes[0:99999]; reg ddr_active = 0; reg [1:0] ddr_beat = 0;
    reg [63:0] ddr_addr = 0;
    localparam [63:0] DDR_BASE = 64'h0000000800000ff0;
    reg [31:0] triangle_count = 1, node_count=1;
    localparam [63:0] BVH_BASE=64'h0000000820000ff0;
    reg inject_error = 0, stall_ddr = 0;
    integer read_count = 0;

    lung_ray_mesh_axi #(.CORE_COUNT(1), .FAST_DIVIDE(0)) dut (
        .aclk(clk), .aresetn(rst_n),
        .s_axi_awaddr(awaddr), .s_axi_awprot(awprot), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arprot(arprot), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .s_mesh_tdata(128'd0), .s_mesh_tkeep(16'd0), .s_mesh_tlast(1'b0), .s_mesh_tvalid(1'b0), .s_mesh_tready(),
        .s_ray_tdata(ray_data), .s_ray_tkeep(ray_keep), .s_ray_tlast(ray_last), .s_ray_tvalid(ray_valid), .s_ray_tready(ray_ready),
        .m_axis_tdata(m_data), .m_axis_tkeep(m_keep), .m_axis_tlast(m_last), .m_axis_tvalid(m_valid), .m_axis_tready(m_ready), .irq(irq),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arprot(m_axi_arprot), .m_axi_arcache(m_axi_arcache), .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp), .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready));

    always @(posedge clk) begin
        if(!rst_n) begin m_axi_arready<=0;m_axi_rvalid<=0;m_axi_rlast<=0;ddr_active<=0;end
        else begin
            m_axi_arready<=!ddr_active&&!m_axi_rvalid&&!stall_ddr;
            if(m_axi_arvalid&&m_axi_arready)begin
                if(m_axi_arlen!==0||m_axi_arsize!==4||m_axi_araddr[3:0]!=0)$fatal(1,"AR protocol");
                ddr_active<=1;ddr_addr<=m_axi_araddr;read_count<=read_count+1;
            end
            if(ddr_active&&!stall_ddr)begin
                if(ddr_addr>=DDR_BASE&&ddr_addr<DDR_BASE+triangle_count*48)m_axi_rdata<=ddr[(ddr_addr-DDR_BASE)/16];
                else if(ddr_addr>=BVH_BASE&&ddr_addr<BVH_BASE+node_count*48)m_axi_rdata<=nodes[(ddr_addr-BVH_BASE)/16];
                else $fatal(1,"DDR invalid address %h",ddr_addr);
                m_axi_rresp<=inject_error?2:0;m_axi_rlast<=1;m_axi_rvalid<=1;ddr_active<=0;
            end else if(m_axi_rvalid&&m_axi_rready)m_axi_rvalid<=0;
        end
    end
    task axi_write(input [11:0] address, input [31:0] value);
        begin
            @(negedge clk); awaddr=address; wdata=value; awvalid=1; wvalid=1;
            while (!(awready && wready)) @(posedge clk);
            @(negedge clk); awvalid=0; wvalid=0; bready=1;
            while (!bvalid) @(posedge clk);
            if (bresp !== 0) $fatal(1, "FAIL AXI write %h", address);
            @(negedge clk); bready=0;
        end
    endtask
    task axi_read(input [11:0] address, output [31:0] value);
        begin
            @(negedge clk); araddr=address; arvalid=1;
            while (!arready) @(posedge clk);
            @(negedge clk); arvalid=0; rready=1;
            while (!rvalid) @(posedge clk);
            if (rresp !== 0) $fatal(1, "FAIL AXI read %h", address);
            value=rdata; @(negedge clk); rready=0;
        end
    endtask
    task send_ray(input [127:0] value, input last_value);
        begin
            @(negedge clk); ray_data=value; ray_last=last_value; ray_valid=1;
            while (!ray_ready) @(posedge clk);
            @(negedge clk); ray_valid=0; ray_last=0;
        end
    endtask

    reg [31:0] ray_words[0:7], expected_words[0:143];
    integer fd,rc,ds,i,j,nr,max_hits,ri,beat,total_rays=0,ds_start,ds_end;
    string vector_dir,filename,name;
    reg [31:0] value;
    reg [127:0] expected_beat;
    reg [127:0] stalled_data;
    task receive_complete(input final_ray);
        begin
            for(beat=0;beat<36;beat=beat+1)begin
                while(!m_valid)@(negedge clk);
                stalled_data=m_data;
                repeat(3)begin @(negedge clk);if(!m_valid||m_data!==stalled_data)$fatal(1,"backpressure ds=%0d ray=%0d beat=%0d",ds,ri,beat);end
                expected_beat={expected_words[beat*4+3],expected_words[beat*4+2],expected_words[beat*4+1],expected_words[beat*4]};
                if(beat==0)begin
                    // Advisory parallel/degenerate flags depend on visited leaves.
                    if(m_data[127:64]!==expected_beat[127:64]||m_data[31:0]!==expected_beat[31:0]||
                       (expected_beat[39:32] != 0 ? (m_data[39:32]!==expected_beat[39:32] &&
                                  m_data[39:32]!== (expected_beat[39:32] | 8'h10)) :
                                 m_data[39:32]!==expected_beat[39:32]))
                        $fatal(1,"header ds=%0d ray=%0d got=%h expected=%h",ds,ri,m_data,expected_beat);
                end else if(beat==3)begin
                    // ABI v0.7 assigns the old reserved words to union diagnostics.
                    if(m_data[31:0]!==expected_beat[31:0] || m_data[127:96]!==32'd1 ||
                       m_data[95:64]>m_data[63:32] || m_data[95:64]>128 || m_data[63:32]>128)
                        $fatal(1,"union diagnostics ds=%0d ray=%0d got=%h",ds,ri,m_data);
                end else if(beat!=2 && m_data!==expected_beat)$fatal(1,"payload ds=%0d ray=%0d beat=%0d got=%h expected=%h",ds,ri,beat,m_data,expected_beat);
                if(m_last!==(final_ray&&beat==35)||m_keep!==16'hffff)$fatal(1,"TLAST/KEEP");
                m_ready=1;@(posedge clk);@(negedge clk);m_ready=0;
            end
        end
    endtask
    task configure;
        begin
            axi_write(12'h004,triangle_count);axi_write(12'h034,DDR_BASE[31:0]);axi_write(12'h038,DDR_BASE[63:32]);
            axi_write(12'h040,BVH_BASE[31:0]);axi_write(12'h044,BVH_BASE[63:32]);axi_write(12'h048,node_count);
            axi_write(12'h03c,3);axi_write(12'h030,100000000);axi_write(12'h058,max_hits);axi_write(12'h000,4);
        end
    endtask
    initial begin #(64'd10000000000); $fatal(1,"RAY_MESH watchdog ds=%0d ray=%0d",ds,ri);end
    initial begin
        if(!$value$plusargs("RAY_MESH_DIR=%s",vector_dir))$fatal(1,"missing +RAY_MESH_DIR=<data/sim_vectors/ray_mesh_bvh>");
        ds_start=0;ds_end=9;
        if($value$plusargs("RAY_MESH_START=%d",ds_start))begin end
        if($value$plusargs("RAY_MESH_END=%d",ds_end))begin end
        repeat(20)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
        for(ds=ds_start;ds<=ds_end;ds=ds+1)begin
            // Keep the final miss fixture used by fault injection, while
            // allowing regressions that exclude all patient-derived data.
            if($test$plusargs("RAY_MESH_SYNTHETIC_ONLY") && (ds==2 || ds==3))continue;
            case(ds)
                0:name="convex";1:name="nonconvex";2:name="lung_8002";3:name="all_structures";
                4:name="hits_exact_128";5:name="hits_over_128";6:name="hits_runtime_limit";
                7:name="wide_difference";8:name="true_t_overflow";9:name="near_parallel_miss";
            endcase
            filename=$sformatf("%0s/%0s.txt",vector_dir,name);fd=$fopen(filename,"r");if(!fd)$fatal(1,"vector missing %0s",filename);
            rc=$fscanf(fd,"%d %d %d %d",triangle_count,node_count,nr,max_hits);if(rc!=4)$fatal(1,"header");
            for(i=0;i<triangle_count*3;i=i+1)begin rc=$fscanf(fd,"%h %h %h %h",ddr[i][31:0],ddr[i][63:32],ddr[i][95:64],ddr[i][127:96]);if(rc!=4)$fatal(1,"tri");end
            for(i=0;i<node_count*3;i=i+1)begin rc=$fscanf(fd,"%h %h %h %h",nodes[i][31:0],nodes[i][63:32],nodes[i][95:64],nodes[i][127:96]);if(rc!=4)$fatal(1,"node");end
            configure();axi_write(12'h008,nr);axi_write(12'h000,1);
            for(ri=0;ri<nr;ri=ri+1)begin
                for(j=0;j<8;j=j+1)begin rc=$fscanf(fd,"%h",ray_words[j]);if(rc!=1)$fatal(1,"ray");end
                for(j=0;j<144;j=j+1)begin rc=$fscanf(fd,"%h",expected_words[j]);if(rc!=1)$fatal(1,"expected");end
                send_ray({ray_words[3],ray_words[2],ray_words[1],ray_words[0]},0);
                send_ray({ray_words[7],ray_words[6],ray_words[5],ray_words[4]},ri==nr-1);
                receive_complete(ri==nr-1);total_rays=total_rays+1;
            end
            $fclose(fd);axi_read(12'h010,value);if(value!=nr)$fatal(1,"processed");
            $display("RAY_MESH_DATASET_PASS %0s rays=%0d reads=%0d",name,nr,read_count);
        end
        // Last case is a harmless miss. Check repeat jobs and cache reuse.
        for(i=0;i<100;i=i+1)begin axi_write(12'h008,1);axi_write(12'h000,1);send_ray({ray_words[3],ray_words[2],ray_words[1],ray_words[0]},0);send_ray({ray_words[7],ray_words[6],ray_words[5],ray_words[4]},1);receive_complete(1);end
        // Receive timeout and recovery.
        axi_write(12'h030,8);axi_write(12'h000,1);repeat(20)@(negedge clk);axi_read(12'h018,value);if(!(value&4))$fatal(1,"timeout");
        axi_write(12'h030,100000000);axi_write(12'h000,1);repeat(5)@(negedge clk);axi_write(12'h000,2);repeat(5)@(negedge clk);axi_read(12'h018,value);if(!(value&128))$fatal(1,"abort");
        // Address-stalled Abort must retain ARVALID until accepted and drain R.
        stall_ddr=1;axi_write(12'h000,1);send_ray({ray_words[3],ray_words[2],ray_words[1],ray_words[0]},0);send_ray({ray_words[7],ray_words[6],ray_words[5],ray_words[4]},1);
        repeat(5)@(negedge clk);axi_write(12'h000,2);repeat(5)@(negedge clk);
        if(!m_axi_arvalid||m_axi_araddr!=BVH_BASE)$fatal(1,"abort lost AR");stall_ddr=0;repeat(20)@(negedge clk);
        axi_read(12'h000,value);if(value&2)$fatal(1,"abort did not drain");
        axi_write(12'h000,1);send_ray({ray_words[3],ray_words[2],ray_words[1],ray_words[0]},0);send_ray({ray_words[7],ray_words[6],ray_words[5],ray_words[4]},1);receive_complete(1);
        // RRESP must be retained in a failed, drained complete frame.
        inject_error=1;expected_words[1]=8;
        axi_write(12'h000,1);send_ray({ray_words[3],ray_words[2],ray_words[1],ray_words[0]},0);send_ray({ray_words[7],ray_words[6],ray_words[5],ray_words[4]},1);receive_complete(1);inject_error=0;
        // KEEP and TLAST errors on the same beat must both survive.
        ray_keep=16'h0fff;expected_words[1]=3;
        axi_write(12'h000,1);send_ray({ray_words[3],ray_words[2],ray_words[1],ray_words[0]},1);send_ray({ray_words[7],ray_words[6],ray_words[5],ray_words[4]},0);receive_complete(1);ray_keep=16'hffff;
        // Reset while receiving must leave no stale ray/result/DDR request.
        axi_write(12'h000,1);send_ray({ray_words[3],ray_words[2],ray_words[1],ray_words[0]},0);
        @(negedge clk);rst_n=0;repeat(5)@(negedge clk);rst_n=1;repeat(5)@(negedge clk);
        if(m_valid||ray_ready||m_axi_arvalid)$fatal(1,"reset stale state");
        configure();axi_write(12'h008,1);expected_words[1]=0;
        axi_write(12'h000,1);send_ray({ray_words[3],ray_words[2],ray_words[1],ray_words[0]},0);send_ray({ray_words[7],ray_words[6],ray_words[5],ray_words[4]},1);receive_complete(1);
        // Invalid BVH child must return an explicit failure, never read out of bounds.
        nodes[2][95:64]=0; // type becomes internal; children are invalid
        axi_write(12'h000,1);send_ray({ray_words[3],ray_words[2],ray_words[1],ray_words[0]},0);send_ray({ray_words[7],ray_words[6],ray_words[5],ray_words[4]},1);
        expected_words[1]=64;receive_complete(1);axi_read(12'h018,value);if(!(value&64))$fatal(1,"invalid node");
        node_count=259;
        for(i=0;i<259;i=i+1)begin
            nodes[i*3]={32'd65536,32'hffff0000,32'hffff0000,32'hffff0000};
            nodes[i*3+1]={32'hffffffff,32'hffffffff,32'd65536,32'd65536};
            nodes[i*3+2]={32'd0,32'd1,32'd1,32'd0};
        end
        for(i=0;i<129;i=i+1)begin nodes[i*3+1][95:64]=i+1;nodes[i*3+1][127:96]=130+i;nodes[i*3+2]=0;end
        nodes[129*3+2]={32'd0,32'd1,32'd1,32'd0};
        configure();expected_words[1]=64;
        axi_write(12'h000,1);send_ray({32'd0,32'd0,32'd0,32'd1},0);send_ray({32'd0,32'd0,32'd0,32'd65536},1);receive_complete(1);
        $display("RAY_MESH_RTL_PASS golden_rays=%0d repeated_jobs=100 timeout=1 abort_drain=1 invalid_bvh=1 stack_overflow=1 rresp=1 keep_tlast=1 reset=1",total_rays);$finish;
    end
endmodule

