# 三份 best 部署量化报告

版本：`20261011_ptq_qat_v2`。服务器正式运行已完成，132 个验证病例、53,412 张切片。肺叶 epoch 12、气道 epoch 27、血管联合 epoch 18 均选择 PTQ，正式 QAT 未启动。肿瘤、last 和其他历史权重不参与。

服务器目录：`<server_root>/lung_training/deployment_quantization/20261011_ptq_qat_v2`。GPU：RTX 4090 D；PyTorch 2.3.0+cu121，未启用 TF32 或 AMP。原 best 和冻结 epoch 副本共六个文件的 SHA256 前后完全相同。

## 完整验证集精度

Dice 和 Recall 下降按 FP32 减整数计算，单位为百分点；负数表示整数结果更高。每个有监督类别与数据集并集 Dice 的允许下降为 2 个百分点。验收只依据完整验证集，不依据小样本预检。

| 数据集 | 病例 / 切片 | FP32 Dice | 整数 Dice | Dice 下降 | Recall 下降 | 判定 |
|---|---:|---:|---:|---:|---:|---|
| 肺叶 / TotalSegmentator | 57 / 14095 | 0.980487 | 0.980620 | -0.0132 | +0.0031 | 通过 |
| 气道 / ATM22 | 42 / 29043 | 0.901287 | 0.900918 | +0.0369 | +0.4986 | 通过 |
| 血管 / HiPaS | 20 / 6340 | 0.857270 | 0.857034 | +0.0236 | +0.1960 | 通过 |
| 血管 / PARSE（仅动脉） | 13 / 3934 | 0.732083 | 0.732223 | -0.0140 | -0.0239 | 通过 |

| 类别 | FP32 Dice | 整数 Dice | Dice 下降（百分点） | FP32 Recall | 整数 Recall |
|---|---:|---:|---:|---:|---:|
| 肺叶 / TotalSegmentator / 左上叶 | 0.939869 | 0.939703 | +0.0166 | 0.950264 | 0.951681 |
| 肺叶 / TotalSegmentator / 左下叶 | 0.907124 | 0.907692 | -0.0567 | 0.929885 | 0.929374 |
| 肺叶 / TotalSegmentator / 右上叶 | 0.880388 | 0.879153 | +0.1235 | 0.956950 | 0.957893 |
| 肺叶 / TotalSegmentator / 右中叶 | 0.808067 | 0.807814 | +0.0254 | 0.801856 | 0.801492 |
| 肺叶 / TotalSegmentator / 右下叶 | 0.911167 | 0.913155 | -0.1988 | 0.967929 | 0.967144 |
| 气道 / ATM22 / 气道 | 0.901287 | 0.900918 | +0.0369 | 0.934113 | 0.929127 |
| 血管 / HiPaS / 动脉 | 0.778081 | 0.776900 | +0.1181 | 0.771622 | 0.770921 |
| 血管 / HiPaS / 静脉 | 0.762203 | 0.761931 | +0.0272 | 0.819625 | 0.815899 |
| 血管 / PARSE（仅动脉） / 动脉 | 0.732083 | 0.732223 | -0.0140 | 0.799963 | 0.800202 |

肺叶最大类别 Dice 下降为右上叶 0.1235 个百分点；血管 HiPaS 动脉下降 0.1181 个百分点。气道 Recall 下降 0.4986 个百分点，应保留为后续比较基准，不能只看 Dice。PARSE 没有静脉标签，静脉没有被当作背景参与训练或评分。

## 冻结数值规则

- 输入为 signed INT8，scale=1、zero point=0，直接沿用训练输入；外部补边 -128，卷积内部补边 0。
- 权重逐输出通道 symmetric INT8 [-127,127]；特征逐节点 symmetric INT8，zero point=0。
- 卷积 MAC 为 INT32；分支乘数、固定偏置及合并使用 INT64。DW3/DW5 和残差先在宽整数域合并，再进行一次 signed nearest-even 舍入和饱和。
- Conv+BN 在合法位置折叠；DW 共用 BN 的偏置只计一次。同步置换 BN 参数和 PW 输入列，消除独立 Shuffle。
- ReLU6 特征量化在激活之后；Concat 两路先对齐到较大尺度。输出 logits 为 INT16，scale 见各任务 head，判定阈值 q>=0。
- `export/contract.json` 冻结全部 scale、乘数、shift、偏置和布局；INT8 权重为 OIHW，Golden 为 NCHW、小端二补码。

## 验证与边界

- 13,944 次独立整数舍入/MAC 自检通过；BN/Shuffle 改写的浮点图等价检查通过。
- 三份实际 .bin/contract 包重载后，各 65 个节点与合成 32×32 Golden 逐元素一致；不是仅从浮点权重重新量化做比较。
- 64/128/256/512 四档尺寸的 MAC 在两个角落和中心共 216,384 个元素与独立 CPU INT64 参考一致；该项为位置抽查。
- 三任务完整 512×512 合成输入，实际冻结参数的 CPU/CUDA 输出共 2,097,152 个整数值逐位一致。
- QAT fake-quant 前向、反向和参数更新预检通过。因为完整 PTQ 精度达标，没有对原权重续训，也没有生成冒充 QAT 的权重。
- 校准来自训练集：每数据集 16 病例，每例最多 4 层，兼顾正负层。完整精度重评为验证集，测试集未用于校准或调参，本轮未做量化版独立测试集终评。
- 本轮未执行本地 WSL、RTL 仿真、Vivado 综合或上板；软件数值验证不代表硬件验收。

## 交付目录

```text
source/                              实际服务器量化源码、冻结包加载/自校验工具
lobe/ptq/                            肺叶校准、完整精度、部署包及验证证据
airway/ptq/                          气道校准、完整精度、部署包及验证证据
vessel/ptq/                          HiPaS/PARSE 校准、完整精度、部署包及验证证据
<task>/ptq/export/contract.json       整数计算契约
<task>/ptq/export/*.weight.i8.bin      实际 INT8 权重
<task>/ptq/export/*.bias_fixed.i64.bin 固定偏置
<task>/ptq/export/deployment.pt       折叠浮点参数和尺度，用于流程续接
<task>/ptq/export/golden_synthetic_32x32/ 合成输入与中间整数 Golden
acceptance.json                      最终选择与精度/整数判定
results.json / report.md             原始正式结果与中文报告
original_sha256_*.json               原权重哈希证据
delivery_manifest.json               本次交付文件清单、大小和 SHA256
local_check.json                     下载后本地核对（本地生成）
```

`deployment.pt` 不是 PyTorch 原生 INT8 模型；真正冻结的整数参数在 `.bin` 和 `contract.json`。原始 FP32 权重继续保存在既有模型归档中，本次包没有重复下载原权重或数据集。合成 Golden 不包含患者 CT 或标签。

| 任务 | INT8 权重字节数 | 同数量 FP32 权重字节数 |
|---|---:|---:|
| 肺叶 | 93,040 | 372,160 |
| 气道 | 92,976 | 371,904 |
| 血管 | 92,992 | 371,968 |

同数量卷积权重的存储降为四分之一；实际 FPGA 吞吐、DSP/BRAM 和时序仍需硬件实现测量。

在部署目录中验证冻结包（需已有 Python/PyTorch/NumPy）：

```bash
python source/verify_export.py --export lobe/ptq/export --device cpu
```

替换为 airway 或 vessel 即可。该入口只读取本次整数参数与合成 Golden，不依赖服务器的数据集或原 best。

## 后续进展

本节原为 2026-10-11 的开发计划，该计划已完成：PW、DW3/DW5 与 mkdc 整块已实现并通过验证，整网已在板上通过 Golden 并完成整卷推理，见根目录 `README.md` 的“实测结果”。原计划内容如下：

以这三份冻结契约实现 PW1×1 的 INT8×INT8→INT32 MAC，再接明确的再量化/偏置/ReLU6。先验证一层的 P=16 分组、尾通道掩码和反压，再通过 DDR 输入→单层计算→DDR 输出完成上板小闭环；随后扩展 DW3/DW5 和完整 mkdc block。不要等所有算子完成才做第一次上板。
