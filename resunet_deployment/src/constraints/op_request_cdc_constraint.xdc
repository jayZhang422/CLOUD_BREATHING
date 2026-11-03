# 仅用于implementation，PROCESSING_ORDER=LATE：在Clock Wizard派生时钟建立后求值。
# 两级toggle同步后才消费请求，最早等待2个计算周期；按1.5周期限延迟。
# 125MHz为12ns、250MHz为6ns；主XDC中直接捕获路径仍保留6ns上限。
# 仅 RX 域元数据；禁止用 request_* 通配符误匹配计算域 request_body_ui_r。
# 描述符及 bank 的握手捕获边界由主 XDC 单独约束，本域路径保持正常时序检查。
set op_request_cdc_clk [get_clocks -of_objects [get_pins -of_objects [get_cells -hier -filter {NAME =~ *u_op_board/u_transport/req_sync2_r_reg}] -filter {REF_PIN_NAME == C}]]
set_max_delay -datapath_only [expr {1.5 * [get_property PERIOD $op_request_cdc_clk]}] -from [get_cells -hier -filter {IS_SEQUENTIAL && (NAME =~ *u_op_board/u_transport/request_msg_r_reg* || NAME =~ *u_op_board/u_transport/request_id_r_reg* || NAME =~ *u_op_board/u_transport/request_len_r_reg*)}] -to $op_request_cdc_clk
