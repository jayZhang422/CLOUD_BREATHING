# eth_rgmii_top专用约束；DDR顶层应使用独立的DDR约束。
set_property PACKAGE_PIN K9 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]
create_clock -period 8.000 -name eth_rxc -waveform {0.000 4.000} [get_ports eth_rxc]
set_clock_uncertainty 0.100 [get_clocks eth_rxc]
# 按键复位异步断言，仅外部按键到复位同步器的路径豁免。
# rst_n_sync2到内部寄存器的Recovery/Removal仍必须正常收敛。
set_false_path -from [get_ports sys_rst_n]

################################################################################
# 以太网 RGMII 接口 - RX (接收)
################################################################################
set_property PACKAGE_PIN K22 [get_ports eth_rxc]
set_property IOSTANDARD LVCMOS18 [get_ports eth_rxc]

set_property PACKAGE_PIN K23 [get_ports eth_rx_ctl]
set_property IOSTANDARD LVCMOS18 [get_ports eth_rx_ctl]

set_property PACKAGE_PIN K26 [get_ports eth_rxd[3]]
set_property IOSTANDARD LVCMOS18 [get_ports eth_rxd[3]]

set_property PACKAGE_PIN K25 [get_ports eth_rxd[2]]
set_property IOSTANDARD LVCMOS18 [get_ports eth_rxd[2]]

set_property PACKAGE_PIN L25 [get_ports eth_rxd[1]]
set_property IOSTANDARD LVCMOS18 [get_ports eth_rxd[1]]

set_property PACKAGE_PIN L24 [get_ports eth_rxd[0]]
set_property IOSTANDARD LVCMOS18 [get_ports eth_rxd[0]]

################################################################################
# 以太网 RGMII 接口 - TX (发送)
################################################################################
set_property PACKAGE_PIN M25 [get_ports eth_txc]
set_property IOSTANDARD LVCMOS18 [get_ports eth_txc]

set_property PACKAGE_PIN M26 [get_ports eth_tx_ctl]
set_property IOSTANDARD LVCMOS18 [get_ports eth_tx_ctl]

set_property PACKAGE_PIN K20 [get_ports eth_txd[3]]
set_property IOSTANDARD LVCMOS18 [get_ports eth_txd[3]]

set_property PACKAGE_PIN L20 [get_ports eth_txd[2]]
set_property IOSTANDARD LVCMOS18 [get_ports eth_txd[2]]

set_property PACKAGE_PIN L22 [get_ports eth_txd[1]]
set_property IOSTANDARD LVCMOS18 [get_ports eth_txd[1]]

set_property PACKAGE_PIN L23 [get_ports eth_txd[0]]
set_property IOSTANDARD LVCMOS18 [get_ports eth_txd[0]]

# 原理图第13页R84/R86上拉RXDLY/TXDLY：采用RGMII-ID。
# RX数据先于同名RXC边沿1.0..2.6ns，另留0.1ns板级偏斜。
# 虚拟数据时钟比RXC提前2ns；双沿均为[-0.7,+1.1]ns的变化窗口。
# 显式相位使hold检查下一个半周期的数据，避免把前一字节当作hold边沿。
create_clock -name phy_rx_data -period 8.000 -waveform {6.000 10.000}
set rx_ports [get_ports {eth_rxd[*] eth_rx_ctl}]
set_input_delay -clock phy_rx_data -max 1.100 $rx_ports
set_input_delay -clock phy_rx_data -min -0.700 $rx_ports
set_input_delay -clock phy_rx_data -clock_fall -add_delay -max 1.100 $rx_ports
set_input_delay -clock phy_rx_data -clock_fall -add_delay -min -0.700 $rx_ports

# PHY内部TX采样时钟比TXC延迟约2ns；setup/hold按1ns，加0.1ns预算。
# 此generated clock表达PHY端的采样相位，包含转发时钟的FPGA路径。
create_generated_clock -name phy_tx_sample -source [get_pins u_endpoint/u_eth_txc_oddr/C] -edges {1 2 3} -edge_shift {2.000 2.000 2.000} [get_ports eth_txc]
set tx_ports [get_ports {eth_txd[*] eth_tx_ctl}]
set_output_delay -clock phy_tx_sample -max 1.100 $tx_ports
set_output_delay -clock phy_tx_sample -min -1.100 $tx_ports
set_output_delay -clock phy_tx_sample -clock_fall -add_delay -max 1.100 $tx_ports
set_output_delay -clock phy_tx_sample -clock_fall -add_delay -min -1.100 $tx_ports

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 63.8 [current_design]
