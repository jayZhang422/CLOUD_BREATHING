`timescale 1ns/1ps
// Independent ABI1 centreline distance block; existing planning ABI is unchanged.
module centerline_distance_axi (
(* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF s_axi:s_axis:m_axis:M_AXI, ASSOCIATED_RESET aresetn, FREQ_HZ 99999001" *)
(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *) input wire aclk,
(* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *) input wire aresetn,
input wire [11:0] s_axi_awaddr, input wire [2:0] s_axi_awprot,
input wire s_axi_awvalid, output wire s_axi_awready,
input wire [31:0] s_axi_wdata, input wire [3:0] s_axi_wstrb,
input wire s_axi_wvalid, output wire s_axi_wready,
output reg [1:0] s_axi_bresp, output reg s_axi_bvalid, input wire s_axi_bready,
input wire [11:0] s_axi_araddr, input wire [2:0] s_axi_arprot,
input wire s_axi_arvalid, output wire s_axi_arready,
output reg [31:0] s_axi_rdata, output reg [1:0] s_axi_rresp,
output reg s_axi_rvalid, input wire s_axi_rready,
input wire [127:0] s_axis_tdata, input wire [15:0] s_axis_tkeep,
input wire s_axis_tlast, s_axis_tvalid, output wire s_axis_tready,
output wire [127:0] m_axis_tdata, output wire [15:0] m_axis_tkeep,
output wire m_axis_tlast, m_axis_tvalid, input wire m_axis_tready,
(* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXI, DATA_WIDTH 128, PROTOCOL AXI4, ADDR_WIDTH 64, READ_WRITE_MODE READ_ONLY, FREQ_HZ 99999001, MAX_BURST_LENGTH 1, NUM_READ_OUTSTANDING 1" *)
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARADDR" *) output wire [63:0] m_axi_araddr,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLEN" *) output wire [7:0] m_axi_arlen,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARSIZE" *) output wire [2:0] m_axi_arsize,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARBURST" *) output wire [1:0] m_axi_arburst,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARPROT" *) output wire [2:0] m_axi_arprot,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARCACHE" *) output wire [3:0] m_axi_arcache,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARVALID" *) output wire m_axi_arvalid,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARREADY" *) input wire m_axi_arready,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RDATA" *) input wire [127:0] m_axi_rdata,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RRESP" *) input wire [1:0] m_axi_rresp,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RLAST" *) input wire m_axi_rlast,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RVALID" *) input wire m_axi_rvalid,
(* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RREADY" *) output wire m_axi_rready
);
    reg [31:0] nx,ny,nz,count,weight_x,weight_y,weight_z,limit,timeout;
    reg [63:0] base;
    reg start_pulse,abort_pulse,done_sticky,aw_pending,w_pending;
    reg [11:0] awaddr;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    reg lee_select, job_lee;
    wire busy,done, distance_busy,distance_done,lee_busy,lee_done;
    wire [31:0] errors,processed,cycles,reads,candidates;
    wire [31:0] distance_errors,distance_processed,distance_cycles,distance_reads,distance_candidates;
    wire [31:0] lee_errors,lee_processed,lee_cycles,lee_input_beats,lee_output_beats,lee_accepted;
    wire distance_s_ready,distance_m_valid,distance_m_last,lee_s_ready,lee_m_valid,lee_m_last;
    wire [127:0] distance_m_data,lee_m_data;
    wire [15:0] distance_m_keep,lee_m_keep;
    assign busy=distance_busy|lee_busy;
    assign done=distance_done|lee_done;
    assign errors=job_lee?lee_errors:distance_errors;
    assign processed=job_lee?lee_processed:distance_processed;
    assign cycles=job_lee?lee_cycles:distance_cycles;
    assign reads=job_lee?32'd0:distance_reads;
    assign candidates=job_lee?lee_accepted:distance_candidates;
    assign s_axis_tready=job_lee?lee_s_ready:distance_s_ready;
    assign m_axis_tdata=job_lee?lee_m_data:distance_m_data;
    assign m_axis_tkeep=job_lee?lee_m_keep:distance_m_keep;
    assign m_axis_tlast=job_lee?lee_m_last:distance_m_last;
    assign m_axis_tvalid=job_lee?lee_m_valid:distance_m_valid;
    wire locked=busy||start_pulse;
    assign s_axi_awready=!aw_pending&&!s_axi_bvalid;
    assign s_axi_wready=!w_pending&&!s_axi_bvalid;
    assign s_axi_arready=!s_axi_rvalid;
    assign m_axi_arlen=0;
    assign m_axi_arsize=4;
    assign m_axi_arburst=1;
    assign m_axi_arprot=0;
    assign m_axi_arcache=4'b0011;
    centerline_distance_core core (
        .clk(aclk),.rst_n(aresetn),.start(start_pulse&&!job_lee),.abort_job(abort_pulse&&!job_lee),
        .nx(nx),.ny(ny),.nz(nz),.query_count(count),.weight_x(weight_x),.weight_y(weight_y),.weight_z(weight_z),
        .max_radius(limit[15:0]),.timeout_cycles(timeout),.mask_base(base),
        .s_data(s_axis_tdata),.s_keep(s_axis_tkeep),.s_last(s_axis_tlast),.s_valid(s_axis_tvalid&&!job_lee),.s_ready(distance_s_ready),
        .m_data(distance_m_data),.m_keep(distance_m_keep),.m_last(distance_m_last),.m_valid(distance_m_valid),.m_ready(m_axis_tready&&!job_lee),
        .mem_valid(m_axi_arvalid),.mem_address(m_axi_araddr),.mem_ready(m_axi_arready),
        .mem_data(m_axi_rdata),.mem_data_valid(m_axi_rvalid),.mem_error(m_axi_rresp!=0||!m_axi_rlast),
        .mem_data_ready(m_axi_rready),.busy(distance_busy),.done(distance_done),.errors(distance_errors),.processed(distance_processed),
        .cycles(distance_cycles),.reads(distance_reads),.candidates(distance_candidates)
    );
    centerline_lee_axis lee (
        .clk(aclk),.rst_n(aresetn),.start(start_pulse&&job_lee),.abort_job(abort_pulse&&job_lee),
        .query_count(count),.timeout_cycles(timeout),.s_data(s_axis_tdata),.s_keep(s_axis_tkeep),
        .s_last(s_axis_tlast),.s_valid(s_axis_tvalid&&job_lee),.s_ready(lee_s_ready),
        .m_data(lee_m_data),.m_keep(lee_m_keep),.m_last(lee_m_last),.m_valid(lee_m_valid),
        .m_ready(m_axis_tready&&job_lee),.busy(lee_busy),.done(lee_done),.errors(lee_errors),
        .processed(lee_processed),.cycles(lee_cycles),.input_beats(lee_input_beats),
        .output_beats(lee_output_beats),.accepted(lee_accepted)
    );
    function [31:0] merge(input [31:0] old_value,new_value,input [3:0] strobes);
        integer i;
        begin
            merge=old_value;
            for(i=0;i<4;i=i+1) if(strobes[i]) merge[i*8+:8]=new_value[i*8+:8];
        end
    endfunction
    always @(posedge aclk) begin
        if(!aresetn) begin
            nx<=0;ny<=0;nz<=0;count<=0;weight_x<=1;weight_y<=1;weight_z<=1;
            limit<=64;timeout<=1000000000;base<=0;start_pulse<=0;abort_pulse<=0;done_sticky<=0;
            lee_select<=0;job_lee<=0;
            aw_pending<=0;w_pending<=0;awaddr<=0;wdata<=0;wstrb<=0;
            s_axi_bvalid<=0;s_axi_bresp<=0;s_axi_rvalid<=0;s_axi_rresp<=0;s_axi_rdata<=0;
        end else begin
            start_pulse<=0;abort_pulse<=0;
            if(done) done_sticky<=1;
            if(s_axi_bvalid&&s_axi_bready) s_axi_bvalid<=0;
            if(s_axi_rvalid&&s_axi_rready) s_axi_rvalid<=0;
            if(s_axi_awvalid&&s_axi_awready) begin aw_pending<=1;awaddr<=s_axi_awaddr;end
            if(s_axi_wvalid&&s_axi_wready) begin w_pending<=1;wdata<=s_axi_wdata;wstrb<=s_axi_wstrb;end
            if(aw_pending&&w_pending&&!s_axi_bvalid) begin
                aw_pending<=0;w_pending<=0;s_axi_bvalid<=1;s_axi_bresp<=0;
                if(awaddr[1:0]!=0) s_axi_bresp<=2;
                else if(awaddr==0) begin
                    if(wstrb[0]&&wdata[0]) begin
                        if(locked) s_axi_bresp<=2;
                        else begin start_pulse<=1;done_sticky<=0;job_lee<=lee_select;lee_select<=0;end
                    end
                    if(wstrb[0]&&wdata[1]&&busy) abort_pulse<=1;
                end else if(locked) s_axi_bresp<=2;
                else case(awaddr)
                    12'h024: count<=merge(count,wdata,wstrb);
                    12'h028: nx<=merge(nx,wdata,wstrb);
                    12'h02c: ny<=merge(ny,wdata,wstrb);
                    12'h030: nz<=merge(nz,wdata,wstrb);
                    12'h034: weight_x<=merge(weight_x,wdata,wstrb);
                    12'h038: weight_y<=merge(weight_y,wdata,wstrb);
                    12'h03c: weight_z<=merge(weight_z,wdata,wstrb);
                    12'h040: base[31:0]<=merge(base[31:0],wdata,wstrb);
                    12'h044: base[63:32]<=merge(base[63:32],wdata,wstrb);
                    12'h048: limit<=merge(limit,wdata,wstrb);
                    12'h04c: timeout<=merge(timeout,wdata,wstrb);
                    12'h050: if(wstrb[0]) lee_select<=wdata[0];
                    default:s_axi_bresp<=2;
                endcase
            end
            if(s_axi_arvalid&&s_axi_arready) begin
                s_axi_rvalid<=1;s_axi_rresp<=0;s_axi_rdata<=0;
                if(s_axi_araddr[1:0]!=0) s_axi_rresp<=2;
                else case(s_axi_araddr)
                    12'h000:s_axi_rdata<={30'b0,done_sticky,busy};
                    12'h004:s_axi_rdata<=32'h434c4431;
                    12'h008:s_axi_rdata<=32'h00010000;
                    12'h00c:s_axi_rdata<=32'h00000007; // exact queries, integer axis weights, DDR mask
                    12'h010:s_axi_rdata<=errors;
                    12'h014:s_axi_rdata<=processed;
                    12'h018:s_axi_rdata<=cycles;
                    12'h01c:s_axi_rdata<=reads;
                    12'h020:s_axi_rdata<=candidates;
                    12'h024:s_axi_rdata<=count;
                    12'h028:s_axi_rdata<=nx;
                    12'h02c:s_axi_rdata<=ny;
                    12'h030:s_axi_rdata<=nz;
                    12'h034:s_axi_rdata<=weight_x;
                    12'h038:s_axi_rdata<=weight_y;
                    12'h03c:s_axi_rdata<=weight_z;
                    12'h040:s_axi_rdata<=base[31:0];
                    12'h044:s_axi_rdata<=base[63:32];
                    12'h048:s_axi_rdata<=limit;
                    12'h04c:s_axi_rdata<=timeout;
                    // New registers do not change the existing ABI1 map or capability word.
                    // Select is consumed by START; every unselected subsequent job is distance.
                    12'h050:s_axi_rdata<={31'd0,lee_select};
                    12'h054:s_axi_rdata<=32'h4c454531;
                    12'h058:s_axi_rdata<=32'h00010000;
                    12'h05c:s_axi_rdata<=32'h00000007;
                    12'h060:s_axi_rdata<=lee_input_beats;
                    12'h064:s_axi_rdata<=lee_output_beats;
                    12'h068:s_axi_rdata<=lee_accepted;
                    12'h06c:s_axi_rdata<={31'd0,job_lee};
                    default:s_axi_rresp<=2;
                endcase
            end
        end
    end
endmodule
