---
name: pynq
description: 在 PYNQ 板卡（PYNQ-Z2、KV260/KR260 等 Zynq-7000 / Zynq UltraScale+ 平台）上用 Python 加载 Overlay、通过 MMIO/register_map 控制 PL 核、用 AXI DMA 搬运数据并校验结果的通用流程。适用于"把自己的 RTL/HLS 核接进 PYNQ 并上板验证"的任何题目；含离线 HWH 检查脚本与板端调用模板。不适用于 DPU/Vitis AI 推理、外部 FPGA 板卡的以太网通信、纯 PS 软件性能调优。
metadata:
  short-description: PYNQ Overlay/MMIO/DMA 上板契约与排错
---

# PYNQ 上板通用流程

目标：把一个 PL 核从「Vivado 出了 .bit/.hwh」走到「Python 调用结果与参考一致、计时可信、失败可恢复」。与题目无关，换核、换板只需替换契约文件。

## 先确认这一步属于 PYNQ

| 任务 | 归属 |
|---|---|
| Python 经 AXI-Lite 配寄存器、经 AXI DMA 送/取数据 | 本 skill |
| PL 核自带 M_AXI 主口直接读写 DDR | 本 skill（缓存一致性规则不同，见 `references/dma-buffers.md` 第 4 节） |
| 写 RTL、仿真、时序收敛 | `../fpga/` |
| 模型定点化、算子 Golden | `../model-deploy/` |
| 外部 FPGA 板经网口/串口与主机通信 | 不属于 PYNQ，不要叫它 "PYNQ DMA" |

## 七步流程（不可跳步）

| # | 动作 | 通过判据 | 参考 |
|---|---|---|---|
| 1 | 离线检查 HWH：`python scripts/hwh_inspect.py design.hwh --json hwh.json` | 地址映射、DMA 单次上限、PL 时钟、register_map 可用性全部列出 | `scripts/hwh_inspect.py` |
| 2 | 写接口契约：寄存器偏移、启动/完成语义、缓冲区 shape/dtype/字节序、最大长度 | 契约里每个偏移都能在 HWH 或 RTL 源码找到出处 | `references/overlay-mmio.md` |
| 3 | 传文件到板：`.bit` + 同名 `.hwh` + 脚本，校验 SHA256 | 板端哈希 = 工作站哈希 | `references/board-ops.md` |
| 4 | 加载并核身份：Overlay、`ip_dict`、版本/ABI 寄存器、PL 时钟回读 | 版本寄存器值 = 契约值；`fclk` = 时序签核频率 | `references/overlay-mmio.md` |
| 5 | 已知向量（known-vector）测试：小、确定、期望值独立可得 | 逐元素一致 | `scripts/pynq_runner.py` |
| 6 | 真实负载 + 分段计时 | 与 PS 参考一致；计时拆成准备/传输/内核/回收 | `references/dma-buffers.md` |
| 7 | 落运行记录 JSON（哈希、版本、计时、结论） | 记录可让别人复现 | `scripts/pynq_runner.py` |

## 六条硬规则

1. **bit 与 hwh 必须同名、同一次构建。** PYNQ 按 `.bit` 同名找 `.hwh`；混搭不会报错，只会地址或驱动错位。两者 SHA256 一起记录。
2. **寄存器偏移只来自 HWH 或 RTL 契约。** 自定义 RTL（`module_ref`）的 HWH 通常没有寄存器描述，`register_map` 会抛 `AttributeError`，此时用 `MMIO`/`DefaultIP.read/write` 加契约偏移，不要猜。
3. **DMA 缓冲只用 `pynq.allocate`。** 普通 NumPy 数组没有物理连续地址。
4. **先挂接收、再启动、再发送。** S2MM `transfer` 先提交，再写 START，再 MM2S；顺序反了，输出流开头会丢失或 DMA 永远等不到。
5. **等待必须有上限。** `wait()` 内部无超时；可能卡死的场合轮询 `channel.idle` 并设截止时间。超时后按 `references/troubleshooting.md` 恢复，不要直接重跑。
6. **不一致就停。** 结果不符时保留缓冲区与日志，标记失败；不静默回退到 CPU 结果，不临时放宽容差。

## 文件导航

| 文件 | 内容 |
|---|---|
| [references/overlay-mmio.md](references/overlay-mmio.md) | Overlay 加载、`ip_dict`、register_map vs MMIO、版本/ABI 寄存器、PL 时钟、自定义驱动 `bindto` |
| [references/dma-buffers.md](references/dma-buffers.md) | `allocate`、单次传输上限、对齐、TLAST、flush/invalidate 的真实行为、分段计时 |
| [references/board-ops.md](references/board-ops.md) | 板卡与镜像选择、传输与校验、运行目录、状态文件、凭据与进程归属 |
| [references/troubleshooting.md](references/troubleshooting.md) | 现象 → 根因 → 处置速查表；DMA 卡死恢复步骤 |
| [references/ecosystem.md](references/ecosystem.md) | 官方仓库、教程、参考项目（只列链接与用途） |
| [scripts/hwh_inspect.py](scripts/hwh_inspect.py) | 工作站离线解析 HWH，可生成主机侧常量骨架 |
| [scripts/pynq_runner.py](scripts/pynq_runner.py) | 板端模板：身份校验 → DMA 往返 → 比对 → 计时 → 记录 → 失败恢复 |
| [scripts/board_session.py](scripts/board_session.py) | 工作站侧单会话 SSH/SFTP 批量操作（Paramiko 只装在工作站） |

## 失效条件

- PYNQ 大版本变化（2.x → 3.x）后，API 细节以板上已安装版本源码为准，重新跑第 1、4 步。
- 不覆盖 Scatter-Gather DMA、DFX 部分重构、DPU overlay。
- 未覆盖首次烧写 SD 卡镜像与网络配置。
