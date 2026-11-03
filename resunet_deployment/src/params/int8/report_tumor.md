# 肿瘤 base64 第70轮部署量化报告

版本：`20261012_tumor_base64_epoch70_v1`。最终选择 **PTQ**，完整验证集通过；正式 QAT 未启动。验收见 [acceptance_tumor.json](acceptance_tumor.json)。

## 权重与运行来源

- 模型：2.5D ResUNet + mkdc + MaxPool + ReLU6，base=64，通道 [64,128,256,512]，输出1通道。
- 原权重：服务器 `tumor_base64_supervised_100e_v1/stop_snapshot_20261012_epoch0090/checkpoint/best_epoch_0070.pt`；与该训练目录的 best.pt 相同。
- SHA256：`556d048f668560c66789369bcc491351a76249de820353c6b52d1ce645849f45`。
- 本地原权重已在 [best_epoch_0070.pt](../../training/models/tumor/weights_fp32/best_epoch_0070.pt)，本次不重复下载；原权重、last及此前三任务best未覆盖、未删除，九份源文件哈希前后相同。
- 独立服务器输出：`<server_root>/lung_training/deployment_quantization/20261012_tumor_base64_epoch70_v1`；RTX4090D，PyTorch2.3.0+cu121，禁用 AMP/TF32；没有运行本地 WSL、RTL 或 Vivado。

## 完整验证集精度

同一输入重新计算原始 FP32 和冻结整数图。允许每来源 union 及每个有监督类别 Dice 下降不超过0.02绝对值，即2个百分点。下表下降=FP32−整数，负数表示上升。没有用测试集校准、调参或选择量化版本。

| 来源 | 病例 / 切片 | FP32 Dice | 整数 Dice | Dice下降（百分点） | 判定 |
|---|---:|---:|---:|---:|---|
| Task06 | 10 / 2668 | 0.69103281 | 0.68957879 | +0.1454 | 通过 |
| NSCLC | 63 / 7786 | 0.66629146 | 0.66430627 | +0.1985 | 通过 |

| 来源 | FP32 Precision | 整数 Precision | FP32 Recall | 整数 Recall | FP32阳性层召回 | 整数阳性层召回 |
|---|---:|---:|---:|---:|---:|---:|
| Task06 | 0.60459805 | 0.60218860 | 0.80630392 | 0.80663902 | 0.86394558 | 0.87074830 |
| NSCLC | 0.59640681 | 0.59322168 | 0.75472751 | 0.75474601 | 0.82816901 | 0.82910798 |

完整73例、10,454张切片。校准只取训练划分：Task06与NSCLC各16病例，共32病例、128层，确定性选择并兼顾正负层。逐病例统计、TP/FP/FN及类别结果在 `tumor/ptq/full_validation.json`。此前第70轮浮点独立测试使用FP16 AMP；本次是禁用AMP的验证集比较，不能混用两者数字。本轮没有量化版独立测试集终评。

## 冻结数值规则

- 输入signed INT8，scale=1、zero point=0，直接沿用训练缓存数值；外部补边−128，内部卷积补边0。
- 权重逐输出通道symmetric INT8 [-127,127]，OIHW；特征逐节点INT8，zero point=0。ReLU6后各节点scale=6/127。
- 原始MAC为INT32；乘数、固定偏置及分支合并使用INT64。合并后一次有符号最近偶数舍入，再饱和；契约冻结逐通道整数乘数和shift。
- Conv+BN合法折叠，DW3/DW5保留独立权重和scale，共用BN偏置只计一次；同步置换BN与PW权重列消除独立Shuffle。
- Concat两路先对齐尺度；本套6处concat对齐为恒等映射。输出logits采用INT16，head scale=0.001706111040754787，阈值q>=0。
- 硬件参数以实际 `.weight.i8.bin`、`.bias_fixed.i64.bin` 和 `contract.json` 为准。`deployment.pt` 保存折叠浮点参数与尺度，用于流程续接，不能当作PyTorch原生INT8模型。

## 数值验证与覆盖

- 13,944次独立舍入/MAC自检通过；BN/Shuffle折叠后的浮点图等价检查通过，最大绝对误差2.0981e-5。
- 从实际冻结bin和contract重载，65个节点、2,249,728个合成32×32 Golden元素逐位一致；134个导出文件哈希核对通过。
- 64/128/256/512四档输入，全部卷积节点的两个角及中心共84,492个MAC与独立CPU INT64乘加一致。此项为位置抽查，非全部MAC穷举。
- 实际冻结包完整512×512合成输入，262,144个CPU/CUDA输出整数值逐位一致，检查耗时约10.4秒。仅保存512检查报告，不保存患者CT或标签。
- 严格MAC绝对值上界为3,647,488<2^24，保证禁用TF32/AMP时FP32仅作为精确整数卷积载体；乘数/偏置合并绝对值上界为998,184,438,056<2^62，完整逐通道证明见 `export/integer_bounds.json`。
- 软件精度与整数参考已通过。本报告不含硬件验收；肿瘤模型随整体设计的综合实现与整卷上板结果见 根目录 `README.md` 的“实测结果”。

## 交付与硬件接口影响

- 36个INT8权重bin，共1,342,656字节（约1.280MiB）；同数量FP32卷积权重为5,370,624字节，权重存储降为1/4。
- 28个INT64固定偏置bin、1份量化契约、65个合成Golden张量及manifest。
- `source/`：本次肿瘤适配、复用量化流程、整数图、实际bin验证工具及原模型/数据读取/损失源码；原始数据集不随包下载。
- `tumor/ptq/`：校准、完整验证、冻结权重/契约/Golden及一致性证据；根目录保存验收、运行日志、哈希和交付清单。
- 与前三套base16相比，本套最大PW Cin=768、Cout=512。P=16时输入最多48组、输出最多32组；输入3通道和输出1通道仍需有效通道掩码。后续复用核心的容量及层描述必须覆盖这些上限，不能只按前三套的192通道设计。

在本版本目录离线检查实际冻结包与Golden（需已有Python/PyTorch/NumPy，不依赖服务器数据集）：

```bash
python source/verify_export.py --export tumor/ptq/export --device cpu
```

原始FP32权重及前三任务量化历史版本均保留；本次没有改写架构或启动算子开发。
