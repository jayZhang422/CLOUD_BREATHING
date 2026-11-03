# cloud_breathing

全国大学生嵌入式芯片与系统设计竞赛 2026（AMD）FPGA 创新设计赛道，自主选题赛道（3.3）参赛作品。

## 作品概述

作品围绕**肺部CT分析与手术规划**，用两块 AMD FPGA 板卡分别完成"分割"和"规划"两个环节：

1. **`resunet_deployment`（分割）**：在 Kintex UltraScale+ 板卡上部署 2.5D ResUNet + MKDC 分割网络。PC 通过千兆网口把整卷 CT 送入板载 DDR4，FPGA 自主调度全部网络算子完成推理，PC 回读结果并生成三维 STL 网格。输出五个肺叶、气道、肺动脉、肺静脉和肺肿瘤九类结构。
2. **`lung_planer`（规划）**：在 KV260 上以肺部网格为输入做手术规划。PS 运行 Ubuntu + Python/Qt 规划界面和算法，PL 用 4 个手写 RTL 几何核加速双平面楔形切除的网格裁剪与体积/面积积分、点集过滤、中心线距离和多实体射线并集。

```
 CT 影像 ──▶ resunet_deployment（KU5P）──▶ 五叶/气道/血管/肿瘤分割 ──▶ STL 网格
                                                                        │
                                                                        ▼
                                   lung_planer（KV260）：PL 几何加速 + 规划界面 ──▶ 手术规划方案
```

两个工程在接口上衔接：`resunet_deployment` 的上位机输出 STL 网格，`lung_planer` 导入 CT/STL 后做规划。`lung_planer` 的 PS 端自带 CT 到 STL 的 C++ 前端 `ctfpga`，其命令行的 `--host`、`--bind` 参数可经网口访问 KU5P 板（默认 `192.168.1.10`）。该前端与 `resunet_deployment` 的同名前端同源一致。

## 工程一览

| | [`resunet_deployment/`](resunet_deployment/README.md) | [`lung_planer/`](lung_planer/README.md) |
|---|---|---|
| 作用 | 肺部结构分割网络的 FPGA 部署 | 肺部手术规划与 PL 几何加速 |
| 板卡与器件 | RK-XCKU5P-F V1.2，`xcku5p-ffvb676-2-i`（Kintex UltraScale+） | AMD KV260，`xck26-sfvc784-2LV-c`（Zynq UltraScale+） |
| 实现方式 | 手写 RTL + SpinalHDL 算子；不使用 HLS、Vitis AI、DPU | 手写 RTL（4 个 PL 核）+ PS 端 Python/Qt、C++ 扩展 |
| 主机/软件 | 上位机（Python、C++17），经千兆网口通信 | 板上 Ubuntu 22.04 + PYNQ，Python/Qt 界面 |
| 工具 | Vivado 2026.1 | Vivado 2026.1 |

## 关键实测

| 指标 | resunet_deployment | lung_planer |
|---|---|---|
| 时钟 | 算子 250 MHz，DDR4 用户时钟 333.333 MHz，RGMII 125 MHz | PL 单时钟域 100 MHz |
| 时序（布线后） | WNS +0.050 ns，WHS +0.010 ns | WNS +0.416 ns，WHS +0.010 ns |
| 资源 | LUT 45.79%，BRAM 90.52%，URAM 87.50%，DSP 78.95% | LUT 56.11%，BRAM 12.85%，DSP 18.27% |
| 板上验证 | 三例整卷 CT（334 层、245 层 ×2）全部由 FPGA 推理，耗时约 364 至 487 s；板上输出与 GPU 上同一套冻结整数网络的输出 SHA256 完全相同 | 合成立方体 4 个候选与 PS 的 FP64 参考一致，最大误差 2.8e-17 mm³；点批量过滤 4,096 至 16,385 点逐点一致；射线并集与射线 BVH 核通过；PS 软件 297 项测试通过 |
| 功耗 | 3.511 W（工具估算） | 3.329 W（工具估算） |

功耗均为工具估算值。各项数据的来源和细节见两个工程的 README。

## 目录结构

两个工程的结构都对应选题指南 3.3.5.4 的推荐目录（`src/`、`sim/`、`build/`、`board/`、`data/`、`skill/`、`report/`），各自独立，可以单独阅读和复现。`resunet_deployment` 有几处不同，逐项对照见其 README 的"目录结构与对照"一节。

| 推荐目录 | `resunet_deployment/` | `lung_planer/` |
|---|---|---|
| `src/` | [src/](resunet_deployment/src/) | [src/](lung_planer/src/)（`rtl/`、`bd/`、`ps/`） |
| `sim/` | [sim/](resunet_deployment/sim/) | [sim/](lung_planer/sim/) |
| `build/` | [build/](resunet_deployment/build/) | [build/](lung_planer/build/) |
| `board/` | [board/](resunet_deployment/board/) | [board/](lung_planer/board/) |
| `data/` | [data/](resunet_deployment/data/) | [data/](lung_planer/data/) |
| `skill/` | [skill/](resunet_deployment/skill/README.md) | [skill/](lung_planer/skill/README.md) |
| `report/` | [大模型协作记录](resunet_deployment/report/collaboration_llm/README.md)、技术文档 | [大模型协作记录](lung_planer/report/llm_collaboration/README.md)、技术文档 |

两个工程的 `skill/` 内容相同（`pynq/`、`fpga/`、`model-deploy/` 三个子技能），是同一套技能包的两份拷贝。

## 快速开始

### resunet_deployment

在 `resunet_deployment/` 目录下执行：

```bash
vivado -mode batch -source build/create_project.tcl
```

```bash
vivado -mode batch -source build/run_flow.tcl
```

重建约需 2 小时 25 分钟，也可以直接使用 `build/flash/top.bit` 烧录。上板运行与结果核对见其 README 的"复现步骤"。

### lung_planer

在本目录（`cloud_breathing/`）下执行：

```bash
vivado -mode batch -source lung_planer/build/create_project.tcl -tclargs build
```

```bash
vivado -mode batch -source lung_planer/sim/run_sim.tcl
```

重建约需 40 分钟，RTL 回归约 6 分钟。上板部署与检查见其 README 的"复现步骤"。

## 已知限制

- **不含真实病例。** 为保护患者隐私，两个工程都不提供患者 CT 或由病例得到的网格。`resunet_deployment` 只提供三例整卷的哈希清单和合成 32×32 整数 Golden；`lung_planer` 的仿真与准入数据全部为合成数据。
- `resunet_deployment`：三例原始 `.bin` 因体积限制未提交，可核对的是记录中的哈希；DDR4 仿真模型因再分发条款未能确认而未随仓库提供。详见其 README 的"已知限制"。
- `lung_planer`：射线 BVH 测试台中由病例网格导出的两组数据集不提供，回归时跳过；重建得到的 `.bit`、`.hwh` 文件头含时间戳，哈希每次不同，板端软件只接受与准入记录绑定的固件。详见其 README 的"关于位流哈希"和"数据与隐私"。

## 许可

本仓库自有代码与文档按 [Apache License 2.0](LICENSE) 发布。第三方内容：

- `resunet_deployment`：见其 README 的"许可"一节，含训练数据集的许可和 SpinalHDL 生成物说明。
- `lung_planer`：随附的 Qt 运行库按 LGPL-3.0 提供，许可文本和对应源码地址见 [`lung_planer/src/ps/runtime-deps/README.md`](lung_planer/src/ps/runtime-deps/README.md)，其他上游许可文件保留在 `lung_planer/src/ps/` 下对应目录。
