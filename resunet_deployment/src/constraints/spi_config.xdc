# QSPI x4 配置位宽：仅影响 write_bitstream 的配置头，不参与综合/布局/布线。
# 请勿在此保存 dbg_hub 等由 Vivado 自动生成的属性（GUI 的 Save Constraints 会重写工程约束）。
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
