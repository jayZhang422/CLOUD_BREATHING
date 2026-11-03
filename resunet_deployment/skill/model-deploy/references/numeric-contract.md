# 定点数值契约

适用：训练好的模型要落到手写 RTL 之前，定义并冻结「模型 ↔ 硬件」的数值接口。
合格标准：另一个人不看训练代码，只看契约，就能写出逐位正确的 RTL 和 Golden。

## 1. 契约必须回答的问题

| 问题 | 写什么 | 不写清的后果 |
|---|---|---|
| 权重 | dtype、范围（如 INT8 `[-127,127]`）、量化轴（per-tensor / per-channel）、文件布局（如 `OIHW`） | 布局错不报错，只会算错 |
| 激活 | dtype、zero_point、**每个节点**的 scale | 用全局 scale 会在某几层溢出 |
| 输入 | dtype、预处理（裁剪、归一化、取整方式）、外部填充值 | 第一层就偏 |
| 乘加 | 累加位宽（如 INT32）、卷积内部 padding 值 | 边界像素错 |
| 再量化 | 公式、乘数位宽、`shift`、中间位宽与溢出上界、**舍入模式**、饱和/截断 | 恰好 .5 的输入差 1 LSB |
| 激活函数 | ReLU/ReLU6 在再量化前还是后、上界的整数值 | 上限错一档 |
| 输出 | dtype、scale、判定规则（如「符号位为 0 即前景」） | 反量化再比阈值会引入误差 |
| 总线打包 | 一字几个 lane、**lane 0 在最低位还是最高位**、字节序、无效 lane 填什么 | 全部错且看不出规律 |
| 拓扑 | 每层的输入来源、concat/add 的顺序、channel shuffle 的置换 | 结构错 |

## 2. 契约文件（JSON）

```json
{
  "task": "<name>",
  "source": {"checkpoint": "<path>", "sha256": "<训练产物哈希>"},
  "weights":  "signed INT8 [-127,127], per output channel",
  "features": "signed INT8, zero_point=0, per activation node",
  "input_contract": "INT8, NumPy rint (nearest-even), external padding=-128",
  "mac": "INT32; convolution padding integer 0",
  "rescale": "INT64; checked bound <2**62; signed RNE",
  "activation_scales": {"input": 1.0, "e1.expand": 0.0472},
  "convolutions": {
    "e1.expand": {"file": "e1.expand.weight.i8.bin", "shape": [16, 3, 1, 1], "layout": "OIHW",
                  "groups": 1, "padding": 0}
  },
  "merges": {
    "e1.expand": {"shift": 24, "bits": 8, "relu6": true, "bias_file": "e1.expand.bias_fixed.i64.bin",
                  "multipliers": [[25340, 28591]],
                  "formula": "RNE((sum(INT32_acc_i * multiplier_i) + bias_fixed) / 2**shift), then clamp"}
  },
  "packing": {"lanes": 16, "lane_bits": 8, "lane0": "LSB", "invalid_lane_fill": "don't care, masked"}
}
```

模板见 `../templates/contract.template.json`。契约、权重、Golden 一起用 `scripts/hash_manifest.py make` 生成 `sha256.json`。

## 3. 舍入：最容易错的一处

| 模式 | 定义 | RTL 写法要点 |
|---|---|---|
| RNE（就近取偶） | 恰好一半时取偶数 | 需要看商的最低位；`numpy.rint` 等价 |
| round-half-away | 恰好一半时远离 0 | 「加半再右移」只对正数成立，负数要按绝对值处理 |
| floor | 向负无穷 | 直接算术右移 `>>>` |
| trunc | 向 0 | 负数需要修正 |

Golden 必须用与 RTL 相同的整数算法（`scripts/fixedpoint.py` 的 `rne_shift`/`requant`），**不要用浮点算完再 `round()`**：Python 的 `round` 是 RNE，C 的 `round` 是 half-away，两者在 .5 上不同。

测试向量必须包含：恰好 .5 的正负数、饱和上下界、乘积接近溢出上界的值。

## 4. 两种 padding 与 zero point

| | 填什么 | 用在哪 |
|---|---|---|
| 外部填充 | 输入准备阶段图像边界，按契约（例：`-128`） | 输入预处理 |
| 卷积内部 padding | 实数 0 对应的量化值，即 **zero_point**；zero_point=0 时为整数 0 | 卷积窗口越界 |

两者混用的症状：**图像中间全对，只有边界一圈错**。`compare_tensors.py` 会统计边界像素上的差异比例。zero_point 改变时，所有补边逻辑与 MAC 的减零点处理都要重验。

## 5. 算子清单与取舍

开发前把网络里的每个算子列表，标注：类型（数据搬运 / 卷积 / 逐元素 / 激活）、是否依赖量化参数、优先级、状态。

- 先做不依赖量化参数的数据搬运算子（line buffer、pool、upsample、concat），可立即验证。
- **能在导出阶段吸收的就不做硬件**：BN 融进卷积权重与偏置；channel shuffle 改成权重重排；常量乘融进再量化乘数。
- 写明范围外的算子（例：「普通 3×3 密集卷积不在本设计内」），防止需求蔓延。

## 6. 冻结纪律

- 契约冻结后才开始写 RTL；之后任何数值改动都要重走 Golden 生成与全部算子回归。
- 冻结物：契约 JSON、权重、偏置、Golden（含中间节点）、`sha256.json`。
- 训练侧要提供两项一致性证明：导出后重新加载的整数网络与导出前一致；CPU 与 GPU 跑整数网络逐位一致。这两项不成立，后面的板端一致性没有意义。
