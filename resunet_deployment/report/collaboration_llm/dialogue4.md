# 从 hold 违例和 CDC 报告定位真实时序根因协作记录（四）

| 项目 | 内容 |
|---|---|
| 阶段 | 优化与时序收敛 |
| 工具 | 大模型 + Vivado MCP（连接已打开的 Vivado GUI 会话） |
| 来源说明 | 真实协作线程 |
| 对应修复记录 | [`build/reports/history/`](../../build/reports/history/) 中的时序历史 CSV |
| 修改的源文件 | [`src/rtl/op/control/op_transport.sv`](../../src/rtl/op/control/op_transport.sv)、[`src/constraints/ethernet_ddr_constraint.xdc`](../../src/constraints/ethernet_ddr_constraint.xdc) |
| 提炼出的技能 | Vivado 时序与 CDC 证据化诊断（见 [README](README.md)） |

## 用户提示词

> 请通过 Vivado MCP 连接已有 `http://127.0.0.1:8088` 会话，检查当前 Vivado 实现的时序情况，重点分析最差路径和违例类型，优先排查时序约束（尤其是时钟分组和 CDC 路径）是否准确，再排除是否存在过长路径。需要结合实际报告判断是局部控制逻辑问题，还是需要改数据流或算子架构。修复建议要同时考虑 CLB、DSP 和布线资源，保留之前表现较好的资源基线。只依据当前实现证据下结论，不要把估算当作已验证结果；不用 false path 或异步时钟组掩盖问题。

## 模型回答

模型先确认当前打开的 Vivado 工程、实现 run 和报告时间，再从时序约束与时钟关系开始检查：核对主时钟、生成时钟、时钟交互和 CDC 相关 methodology 检查，确认跨域路径是否被正确识别、例外约束是否覆盖了预期端点。随后分别查看 setup 和 hold 路径，避免只看 WNS 就把 CDC 或约束问题误判成组合逻辑过长。对真实的同域 setup 违例，再按起点、终点、逻辑级数和逻辑/布线延迟判断是局部控制链、扇出和布线问题，还是需要更大范围的数据流调整。

## 报告证据与分析

phys-opt 检查点的 setup WNS 为 `+0.149 ns`、TNS 为 `0`，但 hold WHS 为 `-5.302 ns`、THS 为 `-3688.314 ns`。因此，仅凭 setup WNS 为正不能判断设计时序整体通过。

最差 hold 路径从 RX 域的 `active_bank_r_reg` 复制寄存器到计算域请求队列中的 RAM 输入端，路径只有 1 级 LUT，数据延迟 `0.445 ns`，主要问题是 RX 与计算域之间没有共同主时钟，时钟偏斜达到 `5.443 ns`。提取的 768 条大 hold 违例都与这个 bank 选择信号及其复制寄存器有关。methodology 报告也记录了 TIMING-6、TIMING-7 和 TIMING-15 检查结果。

约束检查还发现，旧的 `request_*_r_reg*` 通配符把 `request_body` 到计算域 `body_r` 的同域路径纳入了 6 ns datapath-only 约束。该路径两端实际都属于 4 ns 计算时钟域，不能用旧的正 slack 作为 250 MHz 同域时序通过的证据。

## 修复思路与实际修改

针对跨域 bank 选择路径，修复采用了局部 CDC 捕获：在计算域增加 `active_bank_ui_r`，在请求 toggle 同步后与请求头一起捕获，再由该计算域寄存器选择载荷。这样避免 RX 域的 bank 信号直接组合驱动计算域队列，同时保留原来的请求握手时序。该修改只增加必要寄存器，不新增 BRAM/DSP，也没有修改官方 MIG 生成 RTL。

XDC 的 datapath-only 约束也收窄到握手捕获寄存器，避免将捕获之后的计算域业务路径一并排除在正常 4 ns 检查之外。修复明确没有添加 false path、异步时钟组或 waiver。

## 自我纠错轨迹

初看 setup 汇总时，容易把正 WNS 当作“时序已通过”，或把负 slack 一概归因于 250 MHz 下组合路径太长。进一步查看 hold 报告、时钟关系和 methodology 检查后，判断需要修正：这批最严重的 hold 违例并非计算域算术路径过长，而是跨时钟域 bank 选择信号进入计算域，以及约束范围过宽造成的检查边界不准确。因此处理顺序改为先确认约束和 CDC 路径，再分析同域 setup 关键路径，而不是直接增加流水或扩大时序例外。

## 智能体工作流设计

1. 通过 Vivado MCP 连接用户已有会话，确认当前工程、实现 run 和报告时间。
2. 先查看 clock interaction、时序约束检查和 methodology 报告，确认时钟关系、CDC 分类和例外约束端点。
3. 分开检查 setup 与 hold 路径，并按逻辑延迟、布线延迟、扇出和端点所在时钟域分类。
4. 将路径分类与 RTL、XDC 差异及层级资源报告对应，提出范围尽量局部的修改。
5. 修改后用对应版本的新综合/实现报告确认；没有新报告时，只记录已修改的源文件和静态检查结果，不宣称 STA 已通过。

## 验证结果

- `xvlog` 语法编译通过；
- XDC Tcl 完整性、选择器匹配和 diff 检查通过；
- 改前快照、hold 端点和修复报告已保存；
- 修改当时尚未重新综合/实现，因此该记录本身没有宣称 routed timing 已通过。

## 可复用经验与边界

- STA 诊断必须同时看 setup、hold、时钟关系和 methodology；先确认约束是否准确，再讨论 RTL 是否太慢。
- CDC 约束应精确到握手捕获端点，不能用宽泛通配符排除正常业务路径。
- 静态检查通过不等于修改后的综合、布局布线和最终时序通过；资源基线也要绑定到具体实现版本。

## 后续结果

[`README.md`](../../README.md) 记录这次修复位于 V8 与 V9 之间。setup 收敛过程中，布线中间 WNS 曾为 `-0.171 ns`（见 [`build/reports/final/impl/runme.log`](../../build/reports/final/impl/runme.log) 第 2585 行），最终实现 WNS 为 `+0.050 ns`、WHS 为 `+0.010 ns`、TNS 与 THS 均为 `0`。由于本记录写成时新增寄存器尚未经综合与布线，“该修复在最终比特流中生效”需要结合最终报告另行核对，不由本文单独证明。
