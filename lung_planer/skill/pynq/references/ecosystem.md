# PYNQ 资源索引

只列用途与链接。归档仓库只借鉴思路，安装步骤以当前板卡官方说明为准。

## 官方

| 资源 | 用途 | 链接 |
|---|---|---|
| PYNQ 主仓库 | 框架源码；`pynq/lib/dma.py`、`pynq/overlay.py` 是 API 行为的最终依据 | https://github.com/Xilinx/PYNQ |
| PYNQ 文档 | Overlay、allocate、DMA、MMIO 用法 | https://pynq.readthedocs.io/ |
| Kria-PYNQ | KV260/KR260 安装脚本与示例 | https://github.com/Xilinx/Kria-PYNQ |
| PYNQ 论坛 | 排错与教程（Learn 分类） | https://discuss.pynq.io/ |
| PYNQ 视频教程脚本 | PS GPIO、AXI DMA、Stream IP 接入、重建 base overlay | https://github.com/cathalmccabe/PYNQ_tutorials |
| 自定义 Verilog overlay 教程 | 从 RTL 模块到 overlay 的完整步骤 | https://discuss.pynq.io/t/tutorial-creating-a-new-verilog-module-overlay/1530 |

## 参考项目

| 项目 | 可借鉴 | 链接 |
|---|---|---|
| PYNQ-HelloWorld | `allocate` + DMA 的最小软硬对比示例 | https://github.com/Xilinx/PYNQ-HelloWorld |
| PYNQ_Composable_Pipeline | AXI4-Stream Switch 动态重连数据流 | https://github.com/Xilinx/PYNQ_Composable_Pipeline |
| BNN-PYNQ（已归档） | 低位宽网络在 Zynq-7000 上的 overlay 组织方式 | https://github.com/Xilinx/BNN-PYNQ |
| finn-examples | 预编译 bitfile + Python 驱动的打包方式 | https://github.com/Xilinx/finn-examples |
| Hackster PYNQ 项目 | 完整应用案例 | https://www.hackster.io/projects?d=PYNQ |

## 与本 skill 的关系

本 skill 只讲「自己的 PL 核如何被 Python 可靠调用」。DPU / Vitis AI / FINN / hls4ml 走各自工具链，不在此展开；模型部署见 `../../model-deploy/`。
