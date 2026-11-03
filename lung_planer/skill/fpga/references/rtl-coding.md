# RTL 编码与设计决策

适用：写或改任何可综合 RTL（Verilog-2001 / SystemVerilog / SpinalHDL）。
依据：UG901（综合与 HDL 编码）、UG949（UltraFast 方法学）；以及本项目 KU5P/KV260 工程的返工记录。

## 1. 先定场景，再定语言

| 场景 | 语言 | 硬约束 |
|---|---|---|
| A. 要放进 Block Design（IPI module reference / 打包 IP） | Verilog-2001 `.v` | 不用 `logic`/`always_ff`/`interface`/`package`/二维端口；端口展平；AXI 端口保留标准前缀（`s_axi_`、`m_axis_`）；时钟复位命名 `aclk`/`aresetn` 或 `<if>_aclk`/`<if>_aresetn`，否则 BD 推断不出接口时钟域 |
| B. 独立算子 / 控制逻辑（默认） | SystemVerilog `.sv` | 组合 `always_comb` + `=`；时序 `always_ff` + `<=`；状态 `typedef enum logic [N:0]` |
| C. 参数化数据通路 | SpinalHDL `.scala` → 生成 Verilog | 流控用 `Stream`（有反压）/`Flow`（无反压）/`Fragment`（帧边界）；切长路径用 `.m2sPipe()`/`.s2mPipe()`/`.stage()`；仿真用 SpinalSim |

混合工程：顶层与接口层手写 Verilog/SV，SpinalHDL 只做算子生成器。**属性、修正只写在 Scala 源上，不改生成的 `.v`**，否则下次生成丢失（见 `timing-closure.md` 案例 A）。

## 2. 可综合红线

- 组合块开头给所有输出赋默认值；`case` 带 `default`。否则推断 latch（lint `LATCH`/Vivado `Synth 8-327`）。
- 常量显式位宽与进制：`8'd0`、`{W{1'b0}}`。位宽不一致会隐式截断，定点算子里等于数值错误。
- 可综合代码里不出现 `#delay`、`initial`（ROM 初始化除外，用 `$readmemh`）、`===`。
- 不用信号当时钟；门控时钟用 `BUFGCE` 或时钟使能。
- 同一寄存器不在多个 always 块赋值；同一 always 块不混用阻塞与非阻塞。
- 不对同一寄存器同时写同步置位和复位（Vivado 报 `Synth 8-7137 ... both Set and reset with same priority`，仿真与综合可能不一致）。

## 3. 命名

| 类别 | 规则 |
|---|---|
| 输入/输出端口 | `_i` / `_o`（AXI 标准端口除外，保持协议原名） |
| 寄存器 | `_r`，多拍 `_r1`、`_r2` |
| 组合信号 | `_w` 或 `_nxt` |
| 参数 | 全大写 |
| 跨域同步寄存器 | `_meta`、`_sync`，并加 `(* ASYNC_REG = "TRUE" *)` |

端口顺序：时钟 → 复位 → 控制/握手 → 数据。名字要能被约束通配符精确匹配（见 `timing-closure.md` 第 5 节）。

## 4. 复位策略

| 逻辑 | 复位方式 | 原因 |
|---|---|---|
| 状态机、握手、计数器 | 异步断言、同步释放，低有效 | 任意时刻可回到确定态 |
| 数据通路（MAC、宽流水、RAM 输出寄存器） | 同步复位或不复位 | DSP48/BRAM 内部寄存器只支持同步复位；异步复位会阻止吸收，FF 暴涨、时序变差 |

跨时钟域的复位每个域单独做两级同步释放。复位同步器之后的 Recovery/Removal 检查必须正常收敛，不能整条豁免。

## 5. 流水线、延迟与握手

- 宽乘法（>16 bit）、MAC 链：2~3 级流水，让 DSP 的 AREG/BREG/MREG/PREG 吸收寄存器。
- 每加一级流水，同步更新：接口文档里的 Latency、TB 期望、上层等待逻辑。TB 用「第 N 次握手」比对，而不是「第 N 拍」，就不怕延迟变化。
- valid/ready：`valid` 拉高后，`ready` 为 0 期间 payload 必须保持；不能用 `ready` 组合决定 `valid`（会成环）。
- 对外暴露 `busy_o`/`done_o`；上层等 `done_o` 且 `!busy_o`，不是「输入送完」就读结果。

## 6. 资源映射

| 目标 | 写法 | 退化表现 |
|---|---|---|
| DSP | `(* use_dsp = "yes" *)` 加在乘法结果信号上（UG901：信号级优先于模块级） | 小位宽乘法被映射到 LUT，`report_drc` 里出现 `SYNTH-9` |
| BRAM | `logic [W-1:0] mem [0:D-1]` + 同步读 + 输出寄存器 | 深度太浅、异步读、复杂初始化 → 分布式 RAM 或寄存器（`Synth 8-4767 Trying to implement RAM ... in registers`） |
| URAM | `(* ram_style = "ultra" *)`（仅 UltraScale+） | 容量不够会静默退化 |
| SRL | 无复位的移位寄存器链 | 加复位就变成 FF 链 |

**规则：单项资源 > 85% 是红线**（布线拥塞、后续无扩展空间）；双缓冲会让存储翻倍，预算时算进去。

## 7. 跨时钟域（CDC）

| 信号 | 做法 |
|---|---|
| 单 bit 电平 | 两级 `ASYNC_REG` 同步器 |
| 单 bit 脉冲 | toggle + 同步 + 边沿检测 |
| 多 bit 数据 | 异步 FIFO（XPM/FIFO Generator）或 req/ack 握手 + 目的域捕获寄存器 |
| 多 bit 计数 | 格雷码 |

不要把源域寄存器组合逻辑直接送进目的域（典型：用 RX 域的 bank 选择直接做计算域 RAM 地址），这会产生几十到上千条大 hold 违例。修法是在目的域新增捕获寄存器，见 `timing-closure.md` 案例 C。

## 8. 交付前自查

- [ ] 场景 A/B/C 判定正确，语法子集一致
- [ ] Verilator `--lint-only -Wall` 或 Vivado `synth_design -lint` 无 `WIDTH`/`LATCH`/`MULTIDRIVEN`/组合环
- [ ] 复位按逻辑类型分流，跨域复位已同步
- [ ] Latency 写进接口文档并与 TB 一致
- [ ] DSP/RAM 属性在源上，不在生成物上
- [ ] 所有 CDC 有同步结构，且可被约束精确匹配
