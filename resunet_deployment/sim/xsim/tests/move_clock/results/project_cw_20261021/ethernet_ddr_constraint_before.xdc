# top.sv Ethernet+DDR专用约束；MIG自带board.xdc提供DDR电气标准和5ns参考时钟。
set_property PACKAGE_PIN K9 [get_ports sys_rst]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst]
create_clock -period 8.000 -name eth_rxc_i -waveform {0.000 4.000} [get_ports eth_rxc_i]
set_clock_uncertainty 0.100 [get_clocks eth_rxc_i]
# 按键复位异步断言，仅外部按键到复位同步器的路径豁免。
# rst_n_sync2到内部寄存器的Recovery/Removal仍必须正常收敛。
set_false_path -from [get_ports sys_rst]

################################################################################
# 以太网 RGMII 接口 - RX (接收)
################################################################################
set_property PACKAGE_PIN K22 [get_ports eth_rxc_i]
set_property IOSTANDARD LVCMOS18 [get_ports eth_rxc_i]

set_property PACKAGE_PIN K23 [get_ports eth_rx_ctl_i]
set_property IOSTANDARD LVCMOS18 [get_ports eth_rx_ctl_i]

set_property PACKAGE_PIN K26 [get_ports eth_rxd_i[3]]
set_property IOSTANDARD LVCMOS18 [get_ports eth_rxd_i[3]]

set_property PACKAGE_PIN K25 [get_ports eth_rxd_i[2]]
set_property IOSTANDARD LVCMOS18 [get_ports eth_rxd_i[2]]

set_property PACKAGE_PIN L25 [get_ports eth_rxd_i[1]]
set_property IOSTANDARD LVCMOS18 [get_ports eth_rxd_i[1]]

set_property PACKAGE_PIN L24 [get_ports eth_rxd_i[0]]
set_property IOSTANDARD LVCMOS18 [get_ports eth_rxd_i[0]]

################################################################################
# 以太网 RGMII 接口 - TX (发送)
################################################################################
set_property PACKAGE_PIN M25 [get_ports eth_txc_o]
set_property IOSTANDARD LVCMOS18 [get_ports eth_txc_o]

set_property PACKAGE_PIN M26 [get_ports eth_tx_ctl_o]
set_property IOSTANDARD LVCMOS18 [get_ports eth_tx_ctl_o]

set_property PACKAGE_PIN K20 [get_ports eth_txd_o[3]]
set_property IOSTANDARD LVCMOS18 [get_ports eth_txd_o[3]]

set_property PACKAGE_PIN L20 [get_ports eth_txd_o[2]]
set_property IOSTANDARD LVCMOS18 [get_ports eth_txd_o[2]]

set_property PACKAGE_PIN L22 [get_ports eth_txd_o[1]]
set_property IOSTANDARD LVCMOS18 [get_ports eth_txd_o[1]]

set_property PACKAGE_PIN L23 [get_ports eth_txd_o[0]]
set_property IOSTANDARD LVCMOS18 [get_ports eth_txd_o[0]]

# 原理图第13页R84/R86上拉RXDLY/TXDLY：采用RGMII-ID。
# RX数据先于同名RXC边沿1.0..2.6ns，另留0.1ns板级偏斜。
# 虚拟数据时钟比RXC提前2ns；双沿均为[-0.7,+1.1]ns的变化窗口。
# 显式相位使hold检查下一个半周期的数据，避免把前一字节当作hold边沿。
create_clock -name phy_rx_data -period 8.000 -waveform {6.000 10.000}
set rx_ports [get_ports {eth_rxd_i[*] eth_rx_ctl_i}]
set_input_delay -clock phy_rx_data -max 1.100 $rx_ports
set_input_delay -clock phy_rx_data -min -0.700 $rx_ports
set_input_delay -clock phy_rx_data -clock_fall -add_delay -max 1.100 $rx_ports
set_input_delay -clock phy_rx_data -clock_fall -add_delay -min -0.700 $rx_ports

# PHY内部TX采样时钟比TXC延迟约2ns；setup/hold按1ns，加0.1ns预算。
# 此generated clock表达PHY端的采样相位，包含转发时钟的FPGA路径。
# ODDRE1综合网表映射为OSERDESE3，时钟引脚由C变为CLK。
create_generated_clock -name phy_tx_sample -source [get_pins -hier -filter {NAME =~ *u_ethernet/u_eth_txc_oddr/C || NAME =~ *u_ethernet/u_eth_txc_oddr/CLK}] -edges {1 2 3} -edge_shift {2.000 2.000 2.000} [get_ports eth_txc_o]
set tx_ports [get_ports {eth_txd_o[*] eth_tx_ctl_o}]
set_output_delay -clock phy_tx_sample -max 1.100 $tx_ports
set_output_delay -clock phy_tx_sample -min -1.100 $tx_ports
set_output_delay -clock phy_tx_sample -clock_fall -add_delay -max 1.100 $tx_ports
set_output_delay -clock phy_tx_sample -clock_fall -add_delay -min -1.100 $tx_ports

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 63.8 [current_design]

# 已有板卡DDR引脚映射；复位K9已在上面约束。
set_property PACKAGE_PIN G11 [get_ports error]
set_property PACKAGE_PIN H11 [get_ports c0_init_calib_complete]
set_property IOSTANDARD LVCMOS33 [get_ports error]
set_property IOSTANDARD LVCMOS33 [get_ports c0_init_calib_complete]

set_property PACKAGE_PIN T24 [get_ports c0_sys_clk_p]

set_property PACKAGE_PIN AC26 [get_ports {c0_ddr4_dqs_t[0]}]
set_property PACKAGE_PIN AA22 [get_ports {c0_ddr4_dqs_t[1]}]
set_property PACKAGE_PIN AC18 [get_ports {c0_ddr4_dqs_t[2]}]
set_property PACKAGE_PIN AB17 [get_ports {c0_ddr4_dqs_t[3]}]

set_property PACKAGE_PIN AE25 [get_ports {c0_ddr4_dm_dbi_n[0]}]
set_property PACKAGE_PIN AE22 [get_ports {c0_ddr4_dm_dbi_n[1]}]
set_property PACKAGE_PIN AD20 [get_ports {c0_ddr4_dm_dbi_n[2]}]
set_property PACKAGE_PIN Y20 [get_ports {c0_ddr4_dm_dbi_n[3]}]

set_property PACKAGE_PIN P19 [get_ports c0_ddr4_reset_n]
set_property PACKAGE_PIN R23 [get_ports {c0_ddr4_odt[0]}]
set_property PACKAGE_PIN P25 [get_ports {c0_ddr4_cs_n[0]}]
set_property PACKAGE_PIN V24 [get_ports {c0_ddr4_ck_t[0]}]
set_property PACKAGE_PIN P24 [get_ports c0_ddr4_act_n]
set_property PACKAGE_PIN R22 [get_ports {c0_ddr4_bg[0]}]
set_property PACKAGE_PIN P20 [get_ports {c0_ddr4_cke[0]}]
# DDR ADDR PIN
set_property PACKAGE_PIN Y22 [get_ports {c0_ddr4_adr[0]}]
set_property PACKAGE_PIN Y25 [get_ports {c0_ddr4_adr[1]}]
set_property PACKAGE_PIN W23 [get_ports {c0_ddr4_adr[2]}]
set_property PACKAGE_PIN V26 [get_ports {c0_ddr4_adr[3]}]
set_property PACKAGE_PIN R26 [get_ports {c0_ddr4_adr[4]}]
set_property PACKAGE_PIN U26 [get_ports {c0_ddr4_adr[5]}]
set_property PACKAGE_PIN R21 [get_ports {c0_ddr4_adr[6]}]
set_property PACKAGE_PIN W25 [get_ports {c0_ddr4_adr[7]}]
set_property PACKAGE_PIN R20 [get_ports {c0_ddr4_adr[8]}]
set_property PACKAGE_PIN Y26 [get_ports {c0_ddr4_adr[9]}]
set_property PACKAGE_PIN R25 [get_ports {c0_ddr4_adr[10]}]
set_property PACKAGE_PIN V23 [get_ports {c0_ddr4_adr[11]}]
set_property PACKAGE_PIN AA24 [get_ports {c0_ddr4_adr[12]}]
set_property PACKAGE_PIN W26 [get_ports {c0_ddr4_adr[13]}]
set_property PACKAGE_PIN P23 [get_ports {c0_ddr4_adr[14]}]
set_property PACKAGE_PIN AA25 [get_ports {c0_ddr4_adr[15]}]
set_property PACKAGE_PIN T25 [get_ports {c0_ddr4_adr[16]}]

set_property PACKAGE_PIN P21 [get_ports {c0_ddr4_ba[0]}]
set_property PACKAGE_PIN P26 [get_ports {c0_ddr4_ba[1]}]


# DDR DATA PIN
set_property PACKAGE_PIN AF24 [get_ports {c0_ddr4_dq[0]}]
set_property PACKAGE_PIN AF25 [get_ports {c0_ddr4_dq[1]}]
set_property PACKAGE_PIN AD24 [get_ports {c0_ddr4_dq[2]}]
set_property PACKAGE_PIN AB26 [get_ports {c0_ddr4_dq[3]}]
set_property PACKAGE_PIN AC24 [get_ports {c0_ddr4_dq[4]}]
set_property PACKAGE_PIN AB25 [get_ports {c0_ddr4_dq[5]}]
set_property PACKAGE_PIN AD25 [get_ports {c0_ddr4_dq[6]}]
set_property PACKAGE_PIN AB24 [get_ports {c0_ddr4_dq[7]}]
set_property PACKAGE_PIN AC21 [get_ports {c0_ddr4_dq[8]}]
set_property PACKAGE_PIN AD23 [get_ports {c0_ddr4_dq[9]}]
set_property PACKAGE_PIN AD21 [get_ports {c0_ddr4_dq[10]}]
set_property PACKAGE_PIN AC22 [get_ports {c0_ddr4_dq[11]}]
set_property PACKAGE_PIN AB21 [get_ports {c0_ddr4_dq[12]}]
set_property PACKAGE_PIN AE23 [get_ports {c0_ddr4_dq[13]}]
set_property PACKAGE_PIN AE21 [get_ports {c0_ddr4_dq[14]}]
set_property PACKAGE_PIN AC23 [get_ports {c0_ddr4_dq[15]}]
set_property PACKAGE_PIN AE16 [get_ports {c0_ddr4_dq[16]}]
set_property PACKAGE_PIN AD19 [get_ports {c0_ddr4_dq[17]}]
set_property PACKAGE_PIN AD16 [get_ports {c0_ddr4_dq[18]}]
set_property PACKAGE_PIN AF17 [get_ports {c0_ddr4_dq[19]}]
set_property PACKAGE_PIN AC19 [get_ports {c0_ddr4_dq[20]}]
set_property PACKAGE_PIN AF19 [get_ports {c0_ddr4_dq[21]}]
set_property PACKAGE_PIN AF18 [get_ports {c0_ddr4_dq[22]}]
set_property PACKAGE_PIN AE17 [get_ports {c0_ddr4_dq[23]}]
set_property PACKAGE_PIN AA20 [get_ports {c0_ddr4_dq[24]}]
set_property PACKAGE_PIN AA18 [get_ports {c0_ddr4_dq[25]}]
set_property PACKAGE_PIN AA19 [get_ports {c0_ddr4_dq[26]}]
set_property PACKAGE_PIN Y18 [get_ports {c0_ddr4_dq[27]}]
set_property PACKAGE_PIN AB20 [get_ports {c0_ddr4_dq[28]}]
set_property PACKAGE_PIN Y17 [get_ports {c0_ddr4_dq[29]}]
set_property PACKAGE_PIN AB19 [get_ports {c0_ddr4_dq[30]}]
set_property PACKAGE_PIN AA17 [get_ports {c0_ddr4_dq[31]}]


# 仅CDC同步器第一级豁免异步采样；后续同步器级间路径仍做真实时序检查。
set_false_path -to [get_pins -hier -filter {NAME =~ *u_bridge/*sync1_r_reg/D}]
# generate块在综合网表中为g_ethernet.u_bridge（点号），不能按g_ethernet/u_bridge查询。
# 复位链两级的CLR均由异步复位驱动；仅豁免入口，sync1/Q到sync2/D仍正常检查。
set_false_path -to [get_pins -hier -filter {NAME =~ *bridge_reset_sync*_r_reg/CLR || NAME =~ *u_ethernet/rst_n_sync*_reg/CLR}]
# 125MHz↔MIG UI的稳定命令/结果总线：toggle握手前后保持，约束真实数据传播上限。
set_max_delay -datapath_only 6.000 -from [get_cells -hier -filter {NAME =~ *u_bridge/cmd_*_r_reg*}] -to [get_cells -hier -filter {NAME =~ *u_bridge/operation_*_r_reg* || NAME =~ *u_bridge/bytes_left_r_reg*}]
set_max_delay -datapath_only 6.000 -from [get_cells -hier -filter {NAME =~ *u_bridge/result_*_r_reg*}] -to [get_cells -hier -filter {NAME =~ *u_bridge/verify_*_o_reg* || NAME =~ *u_bridge/packet_error_o_reg*}]

# RX↔独立计算域：只豁免控制toggle/状态同步器第一级，级间仍检查setup/hold。
set_false_path -to [get_pins -of_objects [get_cells -hier -filter {NAME =~ *u_op_board/u_mem_cdc/*sync1_r_reg* || NAME =~ *u_op_board/u_transport/*sync1_r_reg* || NAME =~ *u_op_board/claim_sync1_r_reg* || NAME =~ *u_op_board/storage_idle_sync1_r_reg*}] -filter {REF_PIN_NAME == D}]
set_false_path -to [get_pins -hier -filter {NAME =~ *u_op_board/compute_reset_sync*_r_reg/CLR || NAME =~ *u_op_board/rx_reset_sync*_r_reg/CLR || NAME =~ *u_op_board/ui_reset_sync*_r_reg/CLR || NAME =~ *u_op_board/u_mem_cdc/compute_reset_sync*_r_reg/CLR || NAME =~ *u_op_board/u_mem_cdc/ui_reset_sync*_r_reg/CLR}]
# 请求总线从CRC接收直到UDP回复完成保持；两拍toggle同步后才在计算域捕获。
# 6ns约束真实传播，不对业务路径或整个时钟组作false-path处理。
set_max_delay -datapath_only 6.000 -from [get_cells -hier -filter {NAME =~ *u_op_board/u_transport/request_*_r_reg*}] -to [get_cells -hier -filter {NAME =~ *u_op_board/u_service/body_r_reg* || NAME =~ *u_op_board/u_service/msg_r_reg* || NAME =~ *u_op_board/u_service/id_r_reg* || NAME =~ *u_op_board/u_service/len_r_reg*}]
# 请求在两级toggle同步后才被消费，最早采样距提交为2个计算周期。
# 补齐长度译码、transfer_len及DSP吸收的入口；按1.5周期限延迟，留0.5周期裕量。
# 125MHz为12ns、250MHz为6ns；上面的直接捕获路径仍保留更严格的6ns约束。
# 综合时Clock Wizard为OOC黑盒；实现链接IP后才有可查询的派生时钟。
set op_request_cdc_clk [get_clocks -quiet -of_objects [get_pins -hier -filter {NAME =~ *u_op_board/u_transport/req_sync2_r_reg/C}]]
if {[llength $op_request_cdc_clk] > 0} {
    set_max_delay -datapath_only [expr {1.5 * [get_property PERIOD $op_request_cdc_clk]}] -from [get_cells -hier -filter {NAME =~ *u_op_board/u_transport/request_*_r_reg*}] -to $op_request_cdc_clk
}
set_max_delay -datapath_only 6.000 -from [get_cells -hier -filter {NAME =~ *u_op_board/image_*_snapshot_r_reg*}] -to [get_cells -hier -filter {NAME =~ *u_op_board/image_base_r_reg* || NAME =~ *u_op_board/image_slices_r_reg* || NAME =~ *u_op_board/image_ready_r_reg*}]
# 回复头/长度在reply toggle到达后整体锁存，再由RX域builder读取。
set_max_delay -datapath_only 6.000 -from [get_cells -hier -filter {NAME =~ *u_op_board/u_service/response_r_reg* || NAME =~ *u_op_board/u_service/msg_r_reg* || NAME =~ *u_op_board/u_service/status_r_reg* || NAME =~ *u_op_board/u_service/transfer_len_r_reg*}] -to [get_cells -hier -filter {NAME =~ *u_op_board/u_transport/reply_header_rx_r_reg* || NAME =~ *u_op_board/u_transport/reply_len_rx_r_reg*}]
# 请求/响应已改为FIFO Generator独立时钟IP，内部XPM负责格雷码CDC约束。
# 原toggle桥的request_payload/ui_request等寄存器已不存在，删除其失效约束。
# 业务端仅使用本域同步释放复位；不豁免业务数据、使能或同步器级间路径。
