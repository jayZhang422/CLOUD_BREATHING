`timescale 1ns/1ps
// AXI-Lite + AXI-Stream wrapper for dual_plane_filter_core.
// ABI 0x00030000 batches the shared point cloud and candidate plane records.
module dual_plane_filter_axi (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK",
       X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI:S_AXIS:M_AXIS, ASSOCIATED_RESET aresetn, FREQ_HZ 99999001" *) input wire aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *) input wire aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR",
       X_INTERFACE_PARAMETER = "PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 12" *) input wire [11:0] s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *) input wire [2:0] s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *) input wire s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *) output wire s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *) input wire [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *) input wire [3:0] s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *) input wire s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *) output wire s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *) output reg [1:0] s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *) output reg s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *) input wire s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *) input wire [11:0] s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *) input wire [2:0] s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *) input wire s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *) output wire s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *) output reg [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *) output reg [1:0] s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *) output reg s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *) input wire s_axi_rready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TDATA" *) input wire [127:0] s_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TKEEP" *) input wire [15:0] s_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TLAST" *) input wire s_axis_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TVALID" *) input wire s_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS TREADY" *) output wire s_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA" *) output wire [127:0] m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TKEEP" *) output wire [15:0] m_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *) output wire m_axis_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *) output wire m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *) input wire m_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq INTERRUPT",
       X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *) output wire irq
);
    localparam [31:0] ABI=32'h00030000;
    reg [31:0] point_count, candidate_count, margin, timeout_cycles, job_id;
    reg [31:0] reuse_points;
    reg irq_enable, done_sticky, start_pulse, abort_pulse, aw_pending, w_pending;
    reg [11:0] aw_addr; reg [31:0] w_data; reg [3:0] w_strb;
    wire busy, done_pulse; wire [31:0] processed, accepted, cycles; wire signed [31:0] min_margin; wire [7:0] errors;
    wire result_valid, core_m_valid; wire locked=busy || start_pulse; wire result_ready=m_axis_tready;
    assign irq=irq_enable && done_sticky;
    assign s_axi_awready=!aw_pending && !s_axi_bvalid; assign s_axi_wready=!w_pending && !s_axi_bvalid; assign s_axi_arready=!s_axi_rvalid;
    dual_plane_batch_filter_core core(.clk(aclk),.rst_n(aresetn),.start(start_pulse),.abort_job(abort_pulse),
        .cfg_point_count(point_count),.cfg_candidate_count(candidate_count),
        .cfg_reuse_points(reuse_points[0]),
        .cfg_margin($signed(margin)),.cfg_timeout_cycles(timeout_cycles),.cfg_job_id(job_id),
        .s_data(s_axis_tdata),.s_keep(s_axis_tkeep),.s_last(s_axis_tlast),.s_valid(s_axis_tvalid),.s_ready(s_axis_tready),
        .m_data(m_axis_tdata),.m_keep(m_axis_tkeep),.m_last(m_axis_tlast),.m_valid(core_m_valid),.m_ready(result_ready),.busy(busy),
        .done_pulse(done_pulse),.processed_count(processed),.accepted_count(accepted),.min_margin_q16(min_margin),.error_flags(errors),.cycle_count(cycles),.result_valid(result_valid));
    assign m_axis_tvalid = core_m_valid;
    function automatic [31:0] merge_bytes(input [31:0] old_value,input [31:0] new_value,input [3:0] strobe);
        integer b; begin merge_bytes=old_value; for (b=0;b<4;b=b+1) if(strobe[b]) merge_bytes[b*8 +: 8]=new_value[b*8 +: 8]; end
    endfunction
    integer index;
    always @(posedge aclk) begin
        if(!aresetn) begin point_count<=0;candidate_count<=0;margin<=32'h00010000;timeout_cycles<=1000000;job_id<=0;reuse_points<=0;irq_enable<=0;done_sticky<=0;start_pulse<=0;abort_pulse<=0;aw_pending<=0;w_pending<=0;aw_addr<=0;w_data<=0;w_strb<=0;s_axi_bvalid<=0;s_axi_bresp<=0;s_axi_rvalid<=0;s_axi_rresp<=0;s_axi_rdata<=0; end
        else begin
            start_pulse<=0; abort_pulse<=0;
            if(s_axi_bvalid&&s_axi_bready)s_axi_bvalid<=0; if(s_axi_rvalid&&s_axi_rready)s_axi_rvalid<=0;
            if(s_axi_awvalid&&s_axi_awready)begin aw_pending<=1;aw_addr<=s_axi_awaddr;end
            if(s_axi_wvalid&&s_axi_wready)begin w_pending<=1;w_data<=s_axi_wdata;w_strb<=s_axi_wstrb;end
            if(aw_pending&&w_pending&&!s_axi_bvalid)begin aw_pending<=0;w_pending<=0;s_axi_bvalid<=1;s_axi_bresp<=0;
                if(aw_addr[1:0]!=0)s_axi_bresp<=2'b10;
                else if(aw_addr==12'h000)begin if(w_strb[1])irq_enable<=w_data[8];if(w_strb[0]&&w_data[0])begin if(locked)s_axi_bresp<=2'b10;else begin start_pulse<=1;done_sticky<=0;end end;if(w_strb[0]&&w_data[1]&&busy)abort_pulse<=1;end
                else if(aw_addr==12'h01c)begin if(w_strb[0]&&w_data[0])done_sticky<=0;end
                else if(aw_addr==12'h004||aw_addr==12'h008||aw_addr==12'h00c||aw_addr==12'h010||aw_addr==12'h030||aw_addr==12'h034)begin if(locked)s_axi_bresp<=2'b10;else case(aw_addr)
                    12'h004:point_count<=merge_bytes(point_count,w_data,w_strb);12'h008:margin<=merge_bytes(margin,w_data,w_strb);12'h00c:job_id<=merge_bytes(job_id,w_data,w_strb);12'h010:timeout_cycles<=merge_bytes(timeout_cycles,w_data,w_strb);12'h030:candidate_count<=merge_bytes(candidate_count,w_data,w_strb);12'h034:reuse_points<=merge_bytes(reuse_points,w_data,w_strb);default:begin end endcase end else s_axi_bresp<=2'b10;
            end
            if(s_axi_arvalid&&s_axi_arready)begin s_axi_rvalid<=1;s_axi_rresp<=0;s_axi_rdata<=0;if(s_axi_araddr[1:0]!=0)s_axi_rresp<=2'b10;else case(s_axi_araddr)
                12'h000:s_axi_rdata<={23'b0,irq_enable,3'b0,(errors!=0),done_sticky,locked,1'b0};12'h004:s_axi_rdata<=point_count;12'h008:s_axi_rdata<=margin;12'h00c:s_axi_rdata<=job_id;12'h010:s_axi_rdata<=timeout_cycles;12'h014:s_axi_rdata<=ABI;12'h018:s_axi_rdata<={24'b0,errors};12'h01c:s_axi_rdata<={31'b0,done_sticky};12'h020:s_axi_rdata<=processed;12'h024:s_axi_rdata<=accepted;12'h028:s_axi_rdata<=min_margin;12'h02c:s_axi_rdata<=cycles;12'h030:s_axi_rdata<=candidate_count;12'h034:s_axi_rdata<=reuse_points;default:s_axi_rresp<=2'b10;endcase end
            if(done_pulse)done_sticky<=1;
        end
    end
endmodule
