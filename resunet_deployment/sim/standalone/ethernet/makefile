# Ethernet_Sim Makefile - Verilator 仿真
#
# 目标:
#   make            编译
#   make selftest   编译并跑内建自测(不用 socket, 完整协议流程)
#   make drop       自测 + 故意丢包, 校验缺包位图与重传路径
#   make bridge     编译并跑 UDP 桥接(等 PC 端 python prj/main.py send)
#   make wave       自测 + 出波形
#   make clean      清理

VERILATOR ?= verilator

RTL_DIR := ../../../src/rtl/ethernet

# 工程文件 (sim 目录内新增 + 用户例程只读引用)
RTL := \
	rtl/crc32_iso_hdlc.sv   \
	rtl/protocol_parser.sv  \
	rtl/protocol_builder.sv \
	rtl/eth_top.sv          \
	$(RTL_DIR)/udp/udp_rx.v    \
	$(RTL_DIR)/udp/udp_tx.v    \
	$(RTL_DIR)/arp/crc32_d8.v

SRC_DIR := tb
CACHE_DIR := build_cache/obj_dir
RESULT_DIR := results
CPP   := $(SRC_DIR)/sim_main.cpp
TOP   := eth_top
BIN   := $(CACHE_DIR)/V$(TOP)

VFLAGS := --cc --exe --build -O2 --trace \
	--Mdir $(CACHE_DIR) \
	-Wno-WIDTH -Wno-UNUSED -Wno-UNDRIVEN -Wno-CASEINCOMPLETE \
	-Wno-DECLFILENAME -Wno-VARHIDDEN -Wno-PINMISSING \
	-I$(RTL_DIR)/udp -I$(RTL_DIR)/arp \
	--top-module $(TOP)

# 需要波形时再加 --trace 与 -DVM_TRACE
VFLAGS_TRACE := $(VFLAGS) --trace

.PHONY: all build selftest drop bridge wave clean

all: $(BIN)

build: $(BIN)

$(BIN): $(RTL) $(CPP) $(wildcard $(SRC_DIR)/*.cpp $(SRC_DIR)/*.h)
	mkdir -p $(CACHE_DIR) $(RESULT_DIR)
	$(VERILATOR) $(VFLAGS) $(RTL) $(CPP)

# 内建自测: 不依赖 socket, 先确认 RTL 自身正确（默认生成波形）
selftest: $(BIN)
	mkdir -p $(RESULT_DIR)
	./$(BIN) --selftest --trace
	@echo "================================================================"
	@echo " 仿真完成! 波形文件: $(RESULT_DIR)/wave.vcd"
	@echo " 查看波形: gtkwave $(RESULT_DIR)/wave.vcd &"
	@echo "================================================================"

# 故意丢包: 每 8 个包丢 1 个, 校验 FPGA 回传的缺包位图
drop: $(BIN)
	mkdir -p $(RESULT_DIR)
	./$(BIN) --selftest --drop-mod 8 --trace
	@echo "================================================================"
	@echo " 丢包测试完成! 波形文件: $(RESULT_DIR)/wave.vcd"
	@echo "================================================================"

# UDP 桥接: 绑定 192.168.1.10:8080, 等 PC 端 Python 发送
bridge: $(BIN)
	mkdir -p $(RESULT_DIR)
	./$(BIN)

# 快速测试（无波形，适合 CI 或快速验证）
nowave: $(BIN)
	mkdir -p $(RESULT_DIR)
	./$(BIN) --selftest
	@echo "快速自测完成（无波形）"

clean:
	rm -rf $(CACHE_DIR) probe_obj crc_obj $(RESULT_DIR)/wave.vcd
