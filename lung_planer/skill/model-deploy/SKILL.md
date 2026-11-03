---
name: model-deploy
description: 把训练好的神经网络用手写 Verilog/SystemVerilog 或 SpinalHDL 部署到 AMD FPGA 的流程，不使用 Vitis AI、不使用 HLS。覆盖定点数值契约（舍入、饱和、padding、lane 打包）与冻结、Golden 向量生成、算子级验证闭环、SpinalHDL 生成规范、系统集成与时序门禁、PYNQ 或外部链路上板、板端与 PC 逐位一致性验收。附定点原语库、哈希清单、张量比对脚本与契约/清单模板。不覆盖模型训练与结构搜索。
metadata:
  short-description: 手写 RTL/SpinalHDL 的模型定点化、验证与上板
---

# FPGA 模型部署（手写 RTL / SpinalHDL）

目标：训练好的模型在 FPGA 上的输出，与 PC 上运行同一套冻结整数网络的输出**逐位一致**，并给出可复现的性能与资源数据。

## 全链路与五道门禁

```
训练侧量化 → [门禁1 契约冻结] → 算子 RTL → [门禁2 算子级验证] → 集成
          → [门禁3 改源不改产物] → 综合实现 → [门禁4 时序门禁] → 上板 → [门禁5 逐位一致]
```

| 门禁 | 通过条件 | 工具 | 参考 |
|---|---|---|---|
| 1 契约冻结 | 契约回答了舍入/饱和/padding/打包等全部问题；契约+权重+Golden 有 `sha256.json`；训练侧证明 CPU/GPU 整数一致 | `scripts/hash_manifest.py`、`templates/contract.template.json` | [numeric-contract.md](references/numeric-contract.md) |
| 2 算子级验证 | 每个算子独立 PASS，比对计数正确，lint 清零，checklist 填完 | `scripts/fixedpoint.py`、`../fpga/scripts/sim_check.py`、`templates/op_checklist.md` | [operator-verification.md](references/operator-verification.md) |
| 3 改源不改产物 | 属性与修正只在 Scala/RTL 源上；重新生成后生成物 diff 可解释 | `git diff` | [operator-verification.md](references/operator-verification.md) §5 |
| 4 时序门禁 | 构建脚本 WNS ≥ 0 且 WHS ≥ 0 才出 bitstream；资源单项 ≤ 85% 或已说明 | `../fpga/scripts/qor_check.py` | [integration-board.md](references/integration-board.md) §2 |
| 5 逐位一致 | 板端输出 SHA256 = PC 整数图输出；任务指标相对 FP32 下降在阈值内 | `scripts/compare_tensors.py` | [integration-board.md](references/integration-board.md) §5 |

## 常见错误

| 错误 | 后果 | 正确做法 |
|---|---|---|
| RTL 写完再定量化格式 | 返工 | 门禁 1 |
| Golden 用浮点算完再 `round()` | .5 处与 RTL 差 1 LSB | 用 `fixedpoint.py` 的整数原语 |
| 混淆外部填充与卷积 padding | 只有边界一圈错 | 契约分开写；`compare_tensors.py` 看边界差异比例 |
| lane 顺序改了没更新向量 | 全错且无规律 | lane 顺序写进契约并计入哈希 |
| 在生成的 Verilog 上改属性 | 下次生成丢失，DSP 退化为 LUT | 门禁 3 |
| 只报 PASS 不报比对数 | 无法证明覆盖 | `sim_check.py --expect-count` |
| 只比最终输出 | 中间层错误被掩盖 | 调试阶段逐层回读比对 |
| 新 bitstream 未上板却引用旧上板结论 | 证据断档 | 上板记录绑定 bitstream 哈希 |

## 文件导航

| 文件 | 内容 |
|---|---|
| [references/numeric-contract.md](references/numeric-contract.md) | 契约字段、舍入模式、两种 padding、算子取舍、冻结纪律 |
| [references/operator-verification.md](references/operator-verification.md) | 算子目录结构、向量生成、覆盖矩阵、SpinalHDL 规范、判定档位 |
| [references/integration-board.md](references/integration-board.md) | 系统分层、预算、PYNQ / 外部链路、协议要点、逐位一致验收、报告分层 |
| [references/routes-and-resources.md](references/routes-and-resources.md) | 与 Vitis AI / FINN / hls4ml 的对照、量化工具与参考项目 |
| [scripts/fixedpoint.py](scripts/fixedpoint.py) | RNE/half-away/floor 舍入、饱和、再量化、lane 打包、hex 导出（`--selftest` 自测） |
| [scripts/hash_manifest.py](scripts/hash_manifest.py) | 冻结物 SHA256 清单生成与校验 |
| [scripts/compare_tensors.py](scripts/compare_tensors.py) | 逐元素比对，输出首个差异坐标、边界差异比例 |
| [templates/contract.template.json](templates/contract.template.json) | 契约模板 |
| [templates/op_checklist.md](templates/op_checklist.md) | 算子校验清单模板 |

## 与其他子 skill 的分工

- RTL 写法、仿真 TB、时序收敛、Vivado 操作 → `../fpga/`
- PYNQ 上板（Overlay、DMA、缓存同步）→ `../pynq/`
- 本 skill 决定「数值契约与验收标准」，工具报绿但契约未验，仍算未通过。

## 失效条件

- 数值约定示例（INT8 权重、INT32 累加、INT64 再量化、shift=24、16 lane）来自本项目的 CT 分割网络；其他网络沿用方法，数值重新定义。
- 逐位一致的结论只覆盖已测的输入与冻结权重。
- 不覆盖浮点推理、Transformer 的 softmax/LayerNorm 等非线性算子的定点化方法。
