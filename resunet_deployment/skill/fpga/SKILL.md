---
name: fpga
description: AMD/Xilinx FPGA 通用开发与排错流程，覆盖 RTL 编码规范（Verilog-2001 / SystemVerilog / SpinalHDL 场景分流）、自校验仿真与失败定位、时序收敛与 XDC 约束、Vivado 构建门禁与日志/报告解读、IP 配置、ILA/VIO 上板调试、工程可重建。附报告解析与仿真判定脚本。适用于任何 7 系列 / UltraScale(+) / Zynq 工程的写代码、仿真、综合实现与上板排错；不覆盖 HLS、Vitis AI、ASIC 后端。
metadata:
  short-description: RTL 编码、仿真、时序、Vivado 与上板排错
---

# FPGA 通用开发与排错

目标：从写 RTL 到板上跑通，每一步都有可执行的判据和留档证据，而不是凭经验猜。

## 按症状进入

| 你遇到的情况 | 先读 |
|---|---|
| 要写/改 RTL，或不确定用哪种语言 | [references/rtl-coding.md](references/rtl-coding.md) |
| 写 TB、仿真失败、仿真过了上板不对 | [references/simulation.md](references/simulation.md) |
| WNS/WHS 为负，或怀疑约束有问题 | [references/timing-closure.md](references/timing-closure.md) |
| 跑构建、读日志、配 IP、ILA/VIO、导出工程 | [references/vivado-tools.md](references/vivado-tools.md) |
| 只想按症状查一下 | [references/common-issues.md](references/common-issues.md) |
| 找工具或文档链接 | [references/resources.md](references/resources.md) |

## 标准流程

| 阶段 | 动作 | 通过判据 | 证据 |
|---|---|---|---|
| 1 编码 | 判定场景 A/B/C，按规范写 | lint 无 `WIDTH`/`LATCH`/多驱动/组合环 | `lint.log` |
| 2 仿真 | Golden 文件比对 + 随机反压 + 看门狗 | `python scripts/sim_check.py run.log --expect-count N` 返回 0 | `run.log`、`result.json` |
| 3 综合实现 | 带门禁的构建脚本 | WNS ≥ 0 且 WHS ≥ 0，脚本失败即不出 bitstream | 五份报告 |
| 4 报告复核 | `python scripts/qor_check.py --timing ... --util ... --history qor_history.csv` 与 `python scripts/vivado_log_triage.py runme.log` | 无门禁失败；资源突变与 CRITICAL WARNING 已逐条解释 | `qor_history.csv`、`messages.csv` |
| 5 上板 | 核对 bitstream 哈希/版本寄存器，必要时 ILA | 输出与参考一致 | 运行记录、ILA CSV |

## 硬规则

1. **结论分档**：「仿真 PASS」「时序收敛」「上板一致」不互相替代，报告里写清处于哪一档。
2. **证据带位置**：每个结论指向 `文件:行号` 或日志行号；不说「大概是握手问题」。
3. **先分类再修**：时序问题先看资源 diff 与端点分布，再看路径；不降频、不无依据加 false path。
4. **改源不改产物**：属性与修正写在 RTL/Scala 源上，不改生成的 Verilog 或 `.gen` 目录。
5. **耗时操作需授权**：全流程综合实现、写 bitstream、烧写器件需用户明确要求；只读诊断与 lint 可直接做。
6. **一次一个变量**：每轮改动留可比数据，未重跑的轮次写 `not_resynthesized`。

## 脚本

| 脚本 | 作用 | 依赖 |
|---|---|---|
| [scripts/qor_check.py](scripts/qor_check.py) | 解析 timing summary / utilization，WNS/WHS/WPWS 门禁、按时钟分解、资源红线与突变提示、追加历史 CSV | Python 3 标准库 |
| [scripts/vivado_log_triage.py](scripts/vivado_log_triage.py) | 日志按消息 ID 归并、过滤 INFO、导出 CSV | Python 3 标准库 |
| [scripts/sim_check.py](scripts/sim_check.py) | 统一判定仿真日志 PASS/FAIL、核对比对计数、记录源文件哈希 | Python 3 标准库 |

## 失效条件

- 资源与时序数值案例来自 XCKU5P @250 MHz 与 KV260 @100 MHz，换器件只保留判断顺序。
- Tcl 命令与消息 ID 随 Vivado 版本变化，以已安装版本的 UG835 与日志为准（已在 2026.1 验证）。
- 不覆盖官方 IP（MIG、PCIe）内部问题、DFX 部分重构、Versal AI Engine。
