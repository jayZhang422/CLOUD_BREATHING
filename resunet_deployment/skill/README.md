# skill 技能包

本目录是一个总技能包，包含三个可独立使用的子技能。每个子技能目录有一个 `SKILL.md` 作为入口（含 frontmatter，可直接被智能体加载），`references/` 放按需阅读的细节，`scripts/` 放可直接运行的工具。

| 子技能 | 解决什么 | 入口 |
|---|---|---|
| [pynq/](pynq/) | 自己的 PL 核如何被 Python 可靠调用：Overlay/HWH 核对、MMIO、AXI DMA、缓存同步、计时、失败恢复 | [pynq/SKILL.md](pynq/SKILL.md) |
| [fpga/](fpga/) | FPGA 通用问题：RTL 编码、仿真与失败定位、时序收敛与约束、Vivado 构建/日志/IP/ILA、工程可重建 | [fpga/SKILL.md](fpga/SKILL.md) |
| [model-deploy/](model-deploy/) | 用手写 Verilog/SV 或 SpinalHDL（不用 Vitis AI、不用 HLS）部署神经网络：数值契约、算子验证、集成、板端逐位一致 | [model-deploy/SKILL.md](model-deploy/SKILL.md) |

## 怎么选

| 任务 | 先读 | 再读 |
|---|---|---|
| 写/改 RTL | `fpga/SKILL.md` | `fpga/references/rtl-coding.md` |
| 仿真不过、上板与仿真不一致 | `fpga/references/simulation.md` | `fpga/references/common-issues.md` |
| 时序不收敛 | `fpga/references/timing-closure.md` | `fpga/references/vivado-tools.md` |
| 把 PL 核接进 PYNQ | `pynq/SKILL.md` | `pynq/references/dma-buffers.md` |
| 把训练好的模型落到 RTL | `model-deploy/SKILL.md` | `model-deploy/references/numeric-contract.md` |

三者的关系：`model-deploy` 规定数值契约与验收标准；`fpga` 提供把 RTL 做对、做快的方法；`pynq` 负责板内软硬件接口。跨子技能的引用都用相对路径。

## 快速试用

所有脚本只依赖 Python 3（`compare_tensors.py`、`fixedpoint.py` 需要 numpy；`pynq_runner.py` 在板端运行，需要 pynq）。

```bash
python fpga/scripts/qor_check.py --timing <impl>/top_timing_summary_routed.rpt --util <impl>/top_utilization_placed.rpt
python fpga/scripts/vivado_log_triage.py <synth>/runme.log <impl>/runme.log --csv messages.csv
python fpga/scripts/sim_check.py <op>/verification/run.log --expect-count <N>
python pynq/scripts/hwh_inspect.py <design>.hwh --emit-stub driver_consts.py
python model-deploy/scripts/fixedpoint.py --selftest
python model-deploy/scripts/hash_manifest.py check <frozen_dir> --manifest sha256.json
python model-deploy/scripts/compare_tensors.py board_out.bin golden.bin --dtype int32 --shape C,H,W --layout CHW
```

---

## 每项的适用范围、使用方法、失效条件与验证

### pynq/

- **适用范围**：Zynq-7000、Zynq UltraScale+（PYNQ-Z2、KV260/KR260 等）上，Python 经 AXI-Lite 控制、经 AXI DMA（简单模式）或 PL 主口与 PL 核交换数据。不与具体题目绑定：换核只换契约 JSON，换板只重跑 HWH 检查。
- **使用方法**：按 `SKILL.md` 的七步走。工作站先 `hwh_inspect.py` 离线核对地址映射、DMA 单次上限、PL 时钟、register_map 可用性；板端用 `pynq_runner.py <contract.json>` 完成「版本寄存器 → DMA 往返 → 逐元素比对 → 分段计时 → 运行记录」，失败时自动执行 DMA 复位与 PL 重新下载。
- **失效条件**：PYNQ 大版本变化需按板上源码复核 API；不覆盖 Scatter-Gather DMA、DFX、DPU；`pynq_runner.py` 的恢复逻辑用到 PYNQ 私有属性 `_mmio`/`_offset`。
- **已验证**：`hwh_inspect.py` 在 KV260 工程的真实 HWH（Vivado 2026.1，9 个 PS 可见实例、5 个 AXI DMA）上运行，地址映射与板端代码使用的基地址一致，并正确识别出自定义 RTL 核没有寄存器描述（`register_map` 不可用）、一个 DMA 单次上限只有 16383 B。`pynq_runner.py` 在模拟 pynq 环境下验证了一致、数据不一致、版本寄存器不符三条路径的判定与退出码；**尚未在实板上重新运行**。DMA 行为（transfer 自动 flush、wait 自动 invalidate、轮询 idle 不 invalidate、单次上限 = 2^width−1、对齐要求）逐条对照 PYNQ v2.7 / v3.0.1 / master 源码。
- **从哪来**：KV260 联调中的实际问题——bit/hwh 不是同一次构建导致 ABI 不符；S2MM 晚于 START 提交导致 DMA 超时；HP0 非一致性访问漏了 invalidate 导致结果偶发不一致；背压下 `channel.stop()` 卡死，改为直接写 DMACR 再 `download()`；HWH 请求时钟与时序签核频率不同，需加载后强制并回读。

### fpga/

- **适用范围**：AMD 7 系列 / UltraScale(+) / Zynq 的 RTL 工程，从编码、仿真、综合实现到上板调试。
- **使用方法**：`SKILL.md` 按症状路由到五篇参考；构建后用 `qor_check.py` 做时序/资源门禁并追加历史 CSV，用 `vivado_log_triage.py` 把日志按消息 ID 归并，用 `sim_check.py` 统一判定仿真日志（PASS 标记 + 无失败标记 + 比对计数）。
- **失效条件**：案例数值来自 XCKU5P @250 MHz，换器件只保留判断顺序；Tcl 命令与消息 ID 以已安装 Vivado 版本为准（已在 2026.1 核对）；不覆盖官方 IP 内部问题、HLS、ASIC。
- **已验证**：三个脚本在本项目 KU5P 最终实现报告上运行，解析出 WNS +0.050 / WHS +0.010 ns、按时钟分解、BRAM 90.5% / URAM 87.5% / CLB 86.8% 超红线提示；日志归并把 3106 条 WARNING 归为 21 个 ID，其中 `Constraints 18-402` 的 536 条定位到 XDC 第 178、184 行的通配符约束；`sim_check.py` 对 PW、DW3x3 算子日志判定 PASS 并核对比对计数（79 例、2048 值），对构造的失败日志判定 FAIL。
- **从哪来**：KU5P 工程从 WNS −1.185 ns 到 +0.050 ns 的修复记录——SpinalHDL 重新生成后 `use_dsp` 丢失导致 DSP 1232→428、LUT 暴增；控制链复用导致 21 级路径，靠失败端点聚类而非最差路径定位；通配符约束把同域路径误放宽造成假通过；跨域 bank 选择造成 768 条 hold 违例，靠目的域捕获寄存器而不是 false path 解决；XDC 不支持 `if`、诊断约束误入正式约束集。另有 AMD Vivado 技能包中的规则（lint 用 `-file`、BD 中未知 IP 参数只报警告、`launch_simulation` 失败也可能返回 0、`wait_on_hw_ila` 超时单位为分钟、`.ltx` 与 `.bit` 必须同批）。

### model-deploy/

- **适用范围**：模型结构与权重已冻结，用手写 RTL 或 SpinalHDL 实现算子，要求板端结果可与 PC 逐位核对。
- **使用方法**：按五道门禁推进。用 `model-deploy/templates/contract.template.json` 写契约，`hash_manifest.py make` 冻结；向量生成调用 `fixedpoint.py` 的整数原语；算子按 `model-deploy/templates/op_checklist.md` 验收；上板后 `compare_tensors.py` 比对，给出首个差异坐标与边界差异比例。
- **失效条件**：数值约定示例来自 CT 分割网络（INT8/INT32/INT64、shift=24、16 lane），其他网络沿用方法、重定数值；不覆盖训练、浮点推理、softmax/LayerNorm 的定点化。
- **已验证**：`fixedpoint.py` 自测覆盖 RNE 与 `numpy.rint` 在 ±4096、三种移位下的一致性及饱和、打包、溢出检查；`hash_manifest.py` 校验 airway 冻结目录 133 项清单，132 项一致、1 项缺失（`deployment.pt` 不在当前交付目录中），证明它能发现冻结物被改动或遗漏；`compare_tensors.py` 用构造数据验证一致/不一致两条路径及边界统计。方法本身支撑了本项目三例整卷 CT 的板端输出与 PC（GPU）整数网络 SHA256 完全相同（共 2.16 亿体素）。
- **从哪来**：契约里「signed RNE」的 even 最容易漏写；外部填充 −128 与卷积 padding 0 混用只会让边界一圈错；无效 lane 故意填垃圾值才能测出掩码缺陷；lane 顺序必须计入哈希；以太网协议解析的字节错位、FCS 与 zlib CRC 位序不同；只比最终输出会掩盖中间层错误。

---

## 换一个题目怎么用

| 场景 | 直接复用 | 需要重做 |
|---|---|---|
| 换 PYNQ 板 | 七步流程、全部脚本、排错表 | HWH 检查结果、契约 JSON |
| 换非 PYNQ 的 FPGA 工程 | `fpga/` 全部 | — |
| 换模型 | 契约模板、门禁、脚本、清单模板 | 契约数值、算子 RTL、Golden |
| SpinalHDL ↔ 手写 Verilog | 验证闭环、门禁、比对方法 | 生成入口、TB 写法 |

## 约定

- 目录与文件名为英文小写，正文中文。不含绝对路径、板卡 IP、凭据。
- 历史数值只作线索，换器件或版本要重新测量。
- 技能包只放规范、脚本与模板，不放日志、波形、综合目录；大件证据在工程的 `build/reports/`、`sim/`、`board/`。

## 参考来源与许可

- `fpga/references/vivado-tools.md`、`simulation.md`、`timing-closure.md` 中关于 Vivado lint、elaboration 分析、仿真判定、时序方法学检查、IP 配置、工程版本控制、ILA/VIO 调试的规则，归纳自 AMD Vivado 技能包（`vivado-rtl-lint`、`vivado-rtl-elaboration-analysis`、`vivado-simulate-rtl`、`vivado-timing-methodology-checks`、`vivado-ip-configurator`、`vivado-revision-control`、`hw-ila-debug`、`hw-vio-debug`），Copyright (C) 2026 Advanced Micro Devices, Inc.，SPDX-License-Identifier: MIT。本包为中文重写摘要，未包含上游脚本与原文。
- PYNQ API 行为依据 https://github.com/Xilinx/PYNQ 源码（BSD-3-Clause）。
- AMD 文档：UG835、UG900、UG901、UG903、UG906、UG908、UG949、PG021。
- 资源索引中的第三方项目链接见各子技能 `references/` 下的资源文件。
