# FPGA 常见问题速查

按「症状 → 先查什么 → 去哪一页」组织。每条都来自实际踩坑或 AMD 技能包中的明确规则。

## 1. 编码 / 综合

| 症状 | 先查 | 参考 |
|---|---|---|
| 综合出 latch | 组合块默认值、`case default` | `rtl-coding.md` §2 |
| LUT 暴增、DSP/BRAM 骤降 | 映射属性是否丢失、RAM 是否退化为寄存器 | `rtl-coding.md` §6，`timing-closure.md` §3 |
| BD 里接口没折叠、没有时钟关联 | 端口前缀与 `aclk/aresetn` 命名，是否用了 SV 语法 | `rtl-coding.md` §1 |
| 大量 `Synth 8-3332` 寄存器被删 | 输出端口是否未连、上层是否用了结果 | `vivado-tools.md` §3 |
| 重新生成 SpinalHDL 后行为/资源变了 | 生成物是否被手改过；`git diff` 生成物 | `rtl-coding.md` §1 |

## 2. 仿真

| 症状 | 先查 | 参考 |
|---|---|---|
| 仿真挂死 | 看门狗是否存在、握手是否死锁 | `simulation.md` §2 |
| 结果偶发错 | 反压下 payload 保持、随机种子 | `simulation.md` §5 |
| Verilator 过、xsim/上板不过 | X 态依赖、未复位寄存器 | `simulation.md` §7 |
| `launch_simulation` 返回 0 但实际失败 | 读完整 transcript，用 `sim_check.py` 判定 | `simulation.md` §4 |
| 仿真结果不可复现 | 输入端口是否全部初始化、随机种子是否固定 | `simulation.md` §2 |

## 3. 时序

| 症状 | 先查 | 参考 |
|---|---|---|
| setup 违例，端点分散，级数高 | 流水线、重定时 | `timing-closure.md` §1 |
| setup 违例，端点聚集 | 控制链复用、扇出 | `timing-closure.md` §4 |
| hold 大违例，级数 1 级 | 跨时钟域、时钟偏斜 | `timing-closure.md` §5，`rtl-coding.md` §7 |
| 报告绿但上板不稳 | 通配符/false path 是否掩盖了路径；`report_methodology` | `timing-closure.md` §5、§7 |
| 大量 `Constraints 18-402` | 约束对象匹配错误 | `vivado-tools.md` §3 |

## 4. 上板

| 症状 | 先查 | 参考 |
|---|---|---|
| 完全无反应 | 板上是不是本次 bitstream；时钟是否起振、MMCM locked；复位极性 | `simulation.md` §7 |
| ILA 波形明显错位 | `.ltx` 是否与 `.bit` 同批 | `vivado-tools.md` §5 |
| `[Labtools 27-3366]` | Vivado 与 hw_server 版本不一致 | `vivado-tools.md` §5 |
| 数据首尾/边界错 | lane 顺序、字节序、TLAST、padding | `../../model-deploy/references/numeric-contract.md` |
| PYNQ 相关 | — | `../../pynq/references/troubleshooting.md` |

## 5. 纪律

- 「仿真 PASS」「时序收敛」「上板一致」是三个结论，不互相替代。
- 一次只改一个变量，每轮留可比证据（资源、WNS/WHS、失败端点数、lint 结果）。
- 结论带证据位置：`文件:行号` 或日志行号。
- 不确定的工具行为先查文档（`vivado_doc_search` 或 UG），不用记忆补。
