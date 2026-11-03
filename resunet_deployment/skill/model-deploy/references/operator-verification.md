# 算子 RTL 与算子级验证

适用：每个算子写完、接进顶层之前。集成后定位一个算子的错误，代价远高于独立验证。

## 1. 目录结构（每个算子一份）

```
sim/standalone/op/<op>/
├── rtl/                     # 生成或拷贝的 RTL（仿真用，不是源）
├── tb/ 或 sim/              # TB（SV）或 SpinalSim（Scala）
├── tools/
│   ├── generate_vectors.py  # 只读冻结 Golden → 激励/期望 hex
│   └── check_results.py     # 可选：额外的结果表核对
├── run_sim.sh               # 一键：生成向量 → 仿真 → 判定
└── verification/
    ├── vectors/ + vector_manifest.txt   # 来源路径、形状、种子、SHA256
    ├── run.log  lint.log  result.json
    └── checklist.md                     # 模板见 ../templates/op_checklist.md
```

顶层 `run_tests.sh` 串起所有算子，任一失败即 `exit 1`。

## 2. 向量生成四条要求

1. **只读冻结源**：从冻结的 Golden（含中间节点）切片，不重新训练、不重新量化。
2. **独立实现**：需要额外期望值时，用 NumPy int64 + `scripts/fixedpoint.py` 的整数原语计算，与 RTL 实现路径无关。
3. **打包与契约一致**：lane 顺序、字节序、无效 lane 填充都按契约。无效 lane 可故意填非零垃圾值，用来验证 RTL 的掩码逻辑而不是依赖离线补零。
4. **确定性**：随机反压/间隙的种子写进 manifest。

```python
import sys; sys.path.insert(0, "<skill>/model-deploy/scripts")
import numpy as np
from fixedpoint import pack_lanes, write_hex
x = np.fromfile(FROZEN / "golden/mid.expand.bin", np.int8).reshape(C, H, W)
words = [pack_lanes(x[g*16:(g+1)*16, h, w], 8) for g in range(C // 16) for h in range(H) for w in range(W)]
write_hex(OUT / "stimulus.hex", words, 128)
```

## 3. 覆盖矩阵

| 维度 | 必须覆盖 |
|---|---|
| 数值 | 恰好 .5 的舍入点、饱和上下界、乘积接近溢出上界、全零、全最大 |
| 形状 | 最小尺寸、非 16 倍数通道（触发无效 lane）、奇数宽高、最大尺寸至少一例 |
| 握手 | 输入随机间隙、输出随机反压、连续背靠背帧 |
| 控制 | 复位在运行中途拉起后恢复（多次复位相位）、`last`/`group_last` 边界 |
| 配置 | 阵列复用时，**每一种任务配置**都至少一组向量 |
| 真实数据 | 至少一组来自冻结网络中间节点的真实张量 |

## 4. 运行与判定

```bash
wsl.exe -d Ubuntu -- bash -lc 'cd /mnt/e/<repo>/sim/standalone/op/<op> && ./run_sim.sh'
python <skill>/fpga/scripts/sim_check.py verification/run.log --expect-count <N> \
       --sources "rtl/*.v" "sim/*.scala" --out verification/result.json
verilator --lint-only -Wall -DSYNTHESIS --top-module <Top> rtl/*.v 2>&1 | tee verification/lint.log
```

PASS 行必须带比对计数（`checked=`、`int32_values=` 等），`sim_check.py --expect-count` 防止「比了 0 个也 PASS」。

## 5. SpinalHDL 要点

| 项 | 做法 |
|---|---|
| 版本锁定 | `build.sbt` 写死 `scalaVersion` 与 `spinalVersion`，加 `spinalhdl-idsl-plugin` |
| 源与仿真分离 | 仿真工程用 `Compile / unmanagedSources += baseDirectory.value / "../../../../src/scala/<op>/<op>.scala"` 引用源，不拷贝 |
| 生成入口 | `object <Op>Gen extends App { SpinalConfig(targetDirectory = "rtl", defaultConfigForClockDomains = ClockDomainConfig(resetKind = ASYNC, resetActiveLevel = LOW)).generateVerilog(new <Op>(...)) }`；所有算子复位配置一致 |
| 内存 | `fork := true`，`javaOptions += "-Xmx3G"` |
| 仿真初始化 | 所有输入端口在第一拍前显式赋值（`#= false`），否则是随机值，结果不可复现 |
| 黑匣子 | `clockDomain.onSamplings` 里写逐拍 CSV |
| 属性 | `(* use_dsp = "yes" *)` 等用 `addAttribute` 写在 Scala 信号上；生成后 `grep` 确认属性出现在 `.v` 中 |
| 回归顺序 | 改源 → 重新生成 → `git diff` 生成物 → 重跑该算子与依赖它的所有算子 → 重跑综合看资源 |

## 6. 判定档位

| 档位 | 允许的表述 |
|---|---|
| 算子仿真 PASS | 「该算子功能与整数 Golden 一致（N 个值）」 |
| 综合报告 | 「该算子资源占用 X，映射符合预期」 |
| 实现报告 | 「在 F MHz 下时序收敛」 |
| 板端一致 | 「板端结果与 PC 参考逐位一致」 |

checklist 末尾固定写：「仿真 PASS 只证明功能与整数 Golden 一致；时序需 STA 确认；本阶段未进行综合/实现/上板。」

## 7. 回归纪律

- 契约字段（shift、lane 顺序、padding）或任一共享 RTL 改动后，**全部算子**重跑，不只跑改动的那个。
- Golden、向量清单的哈希进版本控制，变了要说明原因。
- sbt `target/`、`obj_dir/`、FST 波形不进提交包。
