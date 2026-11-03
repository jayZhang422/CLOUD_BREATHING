# 参数ROM地址在IP展开后驱动多块BRAM；由placer按时钟区域复制驱动寄存器。
# 此处只控制物理扇出，不修改时钟、路径要求或任何时序例外。
# UG912: MAX_FANOUT_MODE / FORCE_MAX_FANOUT（Place Design阶段）。
set op_coeff_address_regs [get_cells -hier -quiet -filter {NAME =~ *u_coeff_rom/word_addr_r_reg*}]
set op_coeff_address_nets [get_nets -quiet -of_objects [get_pins -quiet -of_objects $op_coeff_address_regs -filter {REF_PIN_NAME == Q}]]
set_property MAX_FANOUT_MODE CLOCK_REGION $op_coeff_address_nets
set_property FORCE_MAX_FANOUT 16 $op_coeff_address_nets
