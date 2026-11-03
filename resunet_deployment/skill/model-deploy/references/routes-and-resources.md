# 路线对照与参考资源

## 1. 为什么选手写 RTL / SpinalHDL

| 维度 | 手写 RTL / SpinalHDL（本 skill） | Vitis AI（DPU） | FINN / hls4ml（HLS 生成） |
|---|---|---|---|
| 精度 | 任意定点，可逐层不同 | 基本固定 INT8 | 任意低位宽 |
| 与 PC 逐位一致 | 可以（冻结整数契约） | 通常只保证精度接近 | 取决于导出与 HLS 实现 |
| 换模型 | 可能要改 RTL、重出 bitstream | 只重编译 xmodel | 重新生成、重出 bitstream |
| 可控性 | 逐周期可控，可做算子级验证 | 黑盒 | 中等 |
| 代价 | 量化契约、验证闭环全部自己做 | 低 | 中 |
| 适合 | 自定义协议/接口、流式低延迟、需要逐位可复现 | 通用 CNN 快速落地 | 小而固定的低延迟网络 |

选手写路线的前提：模型结构已冻结、算子种类有限、愿意为验证投入时间。

## 2. 训练侧量化工具（产出冻结整数图）

| 工具 | 用途 | 链接 |
|---|---|---|
| Brevitas | PyTorch QAT，任意位宽，导出 QONNX | https://github.com/Xilinx/brevitas |
| QONNX | 在 ONNX 上表达任意精度量化，便于检查与转换 | https://github.com/fastmachinelearning/qonnx |
| QKeras | Keras 侧量化层 | https://github.com/google/qkeras |
| HGQ2 | 逐权重/逐激活学习位宽，可估算资源 | https://github.com/calad0i/HGQ2 |

无论用哪个，最终都要导出到本 skill 的契约格式（整数权重、逐层乘数/shift、舍入模式），并验证「导出重载一致」「CPU/GPU 整数一致」。

## 3. 可借鉴的 RTL / 架构参考

| 项目 | 可借鉴 | 链接 |
|---|---|---|
| finn-hlslib | 数据流算子（滑窗、MVAU、阈值激活）的结构划分 | https://github.com/Xilinx/finn-hlslib |
| FINN | 逐层流水的数据流架构、折叠（folding）与并行度权衡 | https://github.com/Xilinx/finn |
| hls4ml | reuse factor 对资源/延迟的权衡思路 | https://github.com/fastmachinelearning/hls4ml |
| AccDNN | Caffe → RTL 自动生成与 DSE，纯 RTL 路径的参考 | https://github.com/IBM/AccDNN |
| NVDLA | 工业级加速器 RTL 的模块划分与接口 | https://github.com/nvdla/hw |
| llama-fpga | 嵌入式 FPGA 上 LLM 加速器的完整 Vivado 工程 | https://github.com/XDillusion/llama-fpga |
| LogicNets | 把量化网络直接映射为 LUT 的极低延迟思路 | https://github.com/Xilinx/LogicNets |
| SpinalHDL 文档 | `Stream`/`Flow`、`StreamFifo`、仿真 API | https://spinalhdl.github.io/SpinalDoc-RTD/ |

借鉴结构与方法，不照搬实现；任何外部模块接入后都要走算子级验证。
