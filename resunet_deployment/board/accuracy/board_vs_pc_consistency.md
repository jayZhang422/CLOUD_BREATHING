# 板上输出与 PC 复现的一致性

对应赛题 3.3.5.1 要求的“上板运行的实测输出与参考结果的比对数据”。

## 结论

三例整卷 CT（case_a、case_b、case_c）上，KU5P 板子输出的 `segmentation_uint16.bin` 与 PC（GPU，CUDA）运行同一套冻结整数网络得到的文件 **SHA256 完全相同**。三例共 2.16 亿个 uint16 体素（9 个通道占低 9 位），没有一个体素不同。

| | case_a | case_b | case_c |
|---|---:|---:|---:|
| 层数 × 高 × 宽 | 334×512×512 | 245×512×512 | 245×512×512 |
| 输出体素数 | 87,556,096 | 64,225,280 | 64,225,280 |
| 输出大小（B） | 175,112,192 | 128,450,560 | 128,450,560 |
| 板上输出 SHA256 | `3304aa80c4360e87973e116a167f50bb89a455a25e1b0b8de5f432aed8bb0ebb` | `c62cecde00a8be2312ef2f1490f2a5e34d9ef5b59a1eb13840e6732313a56cc8` | `34bc5043518fe2c4b9050353a6c139edeacfb5928e650bb022ecee5ad461bc0d` |
| PC 输出 SHA256 | 同上 | 同上 | 同上 |
| 不一致体素数 | 0 | 0 | 0 |

## 比较方法

1. **输入**：同一病例的 CT 先转成 INT8 体（`ct_volume_int8.bin`），板子与 PC 使用同一份。
2. **PC 侧**：在 NVIDIA RTX 4060 GPU（元数据记录 `device=cuda`）上运行冻结的整数图，输出 `ct-segmentation-bitmask-v2` 位图（uint16，Z,Y,X，C 顺序，小端）。每个任务（lobe、airway、vessel、tumor）运行前先做 Golden 校验（65 个节点，状态 PASS），记录在 PC 侧 `prediction/metadata.json` 的 `golden_verification`。
3. **板侧**：上位机把输入压缩上传到 DDR，按调度清单下发全部命令，四个模型（lobe、airway、vessel、tumor）全部由 FPGA 执行；结果完整回读，每个 READ 帧校验 CRC32，回读完成后在本地计算 SHA256。
4. **比较**：两边输出文件的 SHA256 相同即逐字节相同。哈希相同时，不一致体素数必为 0。

## 三例对照

| 项目 | case_a | case_b | case_c |
|---|---:|---:|---:|
| 输入 INT8 体 SHA256（板上） | `95fe9273ccb85e62bb0bcab2ac1407fc9dfb25826f9bc5794289469fab40a716` | `84eb6b5922f1b97fd8a51ac03a26429ba6d263d915db87d22590e7d210b93f3c` | `77264e9adc501ad28052575ab5d743b727d36a6f502828cb95aec26811fa7324` |
| 输入 INT8 体 SHA256（PC） | 相同 | 见下方说明（逐字节比较中心通道相同） | 相同 |
| 板上调度命令 | 39,312 / 39,312 | 30,090 / 30,090 | 30,090 / 30,090 |
| 板上推理耗时（s） | 487.1 | 364.5 | 364.1 |
| PC（GPU）总耗时（s） | 484.7 | 331.6 | 371.8 |
| 空间分辨率（mm，面内） | 0.801 | 0.8125 | 0.674 |
| 层间距（mm） | 1.0 | 1.25 | 1.25 |

**case_b 的输入说明。** case_b 的 PC 侧输入文件是三通道布局（每层带相邻两层，245×3×512×512，192,675,840 B），SHA256 为 `d79d8ed83e03f8c6cceb371a6a952fca1b973ce86a48dd10cd5761e5a544b885`，与板上单通道文件的哈希自然不同。已用 numpy 逐元素比较：PC 文件的中心通道与板上 `ct_volume_int8.bin` 完全相同（另外两个通道是相邻层，不相同）。case_a、case_c 的 PC 侧输入就是板上同一格式的文件，哈希直接相同。

## 数据在哪里

提交包只带小型记录，原始 `.bin` 因体积限制没有放入。

| 内容 | 位置 |
|---|---|
| 板上输出 SHA256、形状、通道定义 | `../full_volume/<case>/run_report.json`、`prediction/metadata.json` |
| 板上输入 SHA256、命令数、耗时、回读校验 | `../full_volume/<case>/handoff/`（`job.json`、`send_receipt.json`、`inference_status.json`、`result_ready.json`、`program.json`） |
| PC 侧输出 SHA256、耗时、Golden 校验 | PC 侧 `prediction/metadata.json`，哈希已汇总在本页，原文件未提交 |

复核方法：取得两边的 `segmentation_uint16.bin` 后，分别执行 `sha256sum`，应得到上表的值。

## 含义与范围

- 一致说明：对这三例输入，板子执行的整数网络与 GPU 上的参考实现等价，板上没有引入量化误差之外的偏差。因此公开数据集上整数图的 Dice（见 `dataset_dice.md`）可以代表板子的精度。
- 一致不说明分割本身正确。分割正确性靠 `dataset_dice.md` 中的公开数据集验证，这里不涉及。
- 三例是患者 CT 的全部输出体，不是抽样。只有三例，覆盖 334 层和 245 层两种层数、三种面内分辨率，不能外推到所有 CT。
- 主机端的后处理（logit 阈值压缩、网格生成与平滑）不在板子上运行，板子只输出位图，所以这些步骤的结果不属于本结论。
- 耗时对比只有各一次：板上耗时是推理阶段（不含上传和回读），PC 耗时是整个流程的总时间，统计范围不同。case_b 的 PC 总耗时（331.6 s）比板上短，case_a、case_c 的 PC 总耗时与板上接近。这三个数只说明量级相当，不构成加速比。
- 病例名称与原始影像路径不在提交包内。
