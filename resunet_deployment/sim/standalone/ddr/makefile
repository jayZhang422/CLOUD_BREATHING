#------------------------------------------------------------------------------
# Makefile for Verilator standalone simulation of aq_axi_master V3.0 (256-bit)
#   在 WSL 的本目录下:  make        (编译并运行, 终端打印每个测试的结果)
#                       make lint   (只做 Verilator -Wall 静态检查)
#                       make wave   (gtkwave 打开 waveform.vcd)
#   WIDTH 类警告没有被屏蔽, 出现请当作真问题看待
#------------------------------------------------------------------------------

TOP      = tb_aq_axi_master
RTL_DIR  = rtl
SRC_DIR  = tb
CACHE_DIR = build_cache/obj_dir
RESULT_DIR = results
SRCS     = $(RTL_DIR)/tb_aq_axi_master.v $(RTL_DIR)/aq_axi_master.v $(RTL_DIR)/axi_slave_ram.v
CPP_SRCS = $(SRC_DIR)/sim_main.cpp
VFLAGS   = -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PINCONNECTEMPTY

.PHONY: all sim lint clean wave

all: sim

lint:
	verilator --lint-only $(VFLAGS) $(SRCS) --top-module $(TOP)

sim:
	@echo ">>> [1/3] Running Verilator compilation..."
	mkdir -p $(CACHE_DIR) $(RESULT_DIR)
	verilator --cc --exe --trace $(VFLAGS) $(SRCS) $(CPP_SRCS) --Mdir $(CACHE_DIR) --top-module $(TOP)
	@echo ">>> [2/3] Building C++ simulation binary..."
	$(MAKE) -C $(CACHE_DIR) -f V$(TOP).mk -j$$(nproc)
	@echo ">>> [3/3] Executing simulation..."
	./$(CACHE_DIR)/V$(TOP)

wave:
	gtkwave $(RESULT_DIR)/waveform.vcd &

clean:
	rm -rf $(CACHE_DIR) $(RESULT_DIR)/waveform.vcd
