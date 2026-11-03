# MKDC 从独立算子接入工程并完成分层板测协作记录（三）

| 项目 | 内容 |
|---|---|
| 阶段 | 算子集成与联合上板 |
| 工具 | 大模型 + Vivado XSim + UDP 上位机 |
| 来源说明 | 真实协作线程 |
| 相关文件 | [`sim/xsim/tests/mkdc/`](../../sim/xsim/tests/mkdc/)、[`sim/xsim/tests/decoder_d3/`](../../sim/xsim/tests/decoder_d3/)、[`src/rtl/op/`](../../src/rtl/op/)、[`board/history/bin_udp_run_history.json`](../../board/history/bin_udp_run_history.json) |
| 提炼出的技能 | 分层 Golden 集成验收（见 [README](README.md)） |

## 用户提示词

> 把尚未上板的 MKDC 算子接入实际工程，尽量不要修改 Ethernet 接收和 DDR 读写；使用 XSim 和 Golden 验证，保留后续 Python 测试需要的发送逻辑。不要执行综合、实现或 bitstream。

提示词中的算子来自原工程的独立仿真目录，本仓库对应 `sim/standalone/op/`。

## 模型回答

模型按现有工程接口接入 DW3、DW5、Merge、project/skip、final Add，并采用逐算子 RUN、逐阶段 Golden 和旧算子回归三层验证。Ethernet、DDR 读写和结果 READ/UDP 回传路径保持不变。

## 自我纠错轨迹

第一次板测中，`vessel_mid_expand` 通过，但 `vessel_mid_dw3` 返回 `RPC 0x21: INVALID`，证据表明失败发生在描述符校验阶段，还没有进入 DW3 计算。模型因此回查 descriptor、RTL 校验条件、仿真向量和 bitstream 记录，没有把它误报为乘法或量化错误。

后续完整回归中，记录明确发现并修复了另一个真实问题：**DW 装载 32 组权重后覆盖了第 0 组**（原生成 RTL 的 RAM 写使能恒为 1，已在 Scala 中改为实际 Stream 握手并重新生成，见 [`src/rtl/op/`](../../src/rtl/op/)）。修复后 32 组 DW3/DW5 满容量 Golden 均通过，project/skip、mix Add 和 final Add 也通过。当前材料证明了“描述符失败”和“权重装载覆盖”分别存在；不能仅凭现有记录断言二者是同一个直接根因。

## 验证结果

- UDP 链路通过；
- vessel MKDC：`7/7` 阶段通过；
- 四模型 MKDC：`28/28` 阶段通过；
- 扩展回归：`52/52` 通过；
- XSim 正常 `$finish`，共约 `5,870,053` 个 UI 周期；
- 验证范围是 4×4 特征图和指定回归，不等于 512×512 整网已通过。

[`bin_udp_run_history.json`](../../board/history/bin_udp_run_history.json) 记录了同一过程：10 月 16 日 12:52 的 7/28/52 项批次均卡在 `vessel_mid_dw3`，错误为 `RPC 0x21 INVALID`；17:27 的 7/28/52 项随后全部通过。

## 可复用经验与边界

- 先测链路，再测 descriptor，再测单阶段、整链和旧算子回归；记录首个失败阶段、返回码和输入描述符。
- 发现 `INVALID` 时，优先区分协议/描述符校验失败和算术计算失败。
- 常见失败来源：描述符校验失败、满容量权重装载覆盖、把小尺寸链路误称为完整模型。
- 不能替代物理 PHY/MIG 的完整板级验证、512×512 验证或最终 STA。

## 后续结果

整网随后完成综合、实现与三次整卷上板，板上输出与 GPU 参考的 SHA256 一致，见 [`README.md`](../../README.md)。
