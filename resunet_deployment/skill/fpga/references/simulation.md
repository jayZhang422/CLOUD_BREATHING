# 仿真：自校验与失败定位

适用：模块/算子功能验证、仿真失败定位、仿真与综合或上板行为不一致。
依据：UG900（Vivado 仿真）、AMD `vivado-simulate-rtl` 技能（MIT）、本项目 13 个算子仿真目录的实践。

## 1. 三条原则

1. **参考模型与 RTL 解耦。** 算法/定点运算在 Python/C++ 离线算出 `stimulus.hex` 与 `golden.hex`；TB 只负责驱动激励、处理握手反压、比对并判定。TB 里手写「简化算法」等于用两个可能同错的东西互证。
2. **自动判定，不看波形判对错。** 失败时打印时间、序号、期望、实际，立即停止；通过时打印唯一 PASS 标记和比对计数。
3. **PASS 只证明与 Golden 一致。** 不证明时序、资源、X 态安全或上板行为。每份结论都写这句边界。

## 2. TB 骨架（SystemVerilog，文件流比对）

```systemverilog
module tb;
  localparam int N = 1024;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic [127:0] stim [0:N-1];
  logic [511:0] gold [0:N-1];
  initial begin
    $readmemh("stimulus.hex", stim);
    $readmemh("golden.hex",   gold);
    repeat (10) @(posedge clk); rst_n = 1;
  end
  // ... DUT 例化、带随机反压的驱动 ...
  int unsigned n_chk = 0;
  always @(posedge clk) if (rst_n && out_valid && out_ready) begin
    if (out_data !== gold[n_chk]) begin           // 用 !== 才能抓到 X/Z
      $display("[%0t] MISMATCH #%0d exp=%h act=%h", $time, n_chk, gold[n_chk], out_data);
      $fatal(1, "TB FAILED");
    end
    n_chk <= n_chk + 1;
    if (n_chk == N-1) begin $display("[TB PASSED] checked=%0d", N); $finish; end
  end
  initial begin                                   // 看门狗：打印进度
    repeat (200000) @(posedge clk);
    $display("[TB FAILED] watchdog sent=%0d checked=%0d", n_sent, n_chk);
    $fatal(1, "timeout");
  end
endmodule
```

要点：

- 比对用 `!==`（四态），`!=` 遇到 X 结果不确定。
- 交互调试时可用 `$stop` 让 xsim 停在出错拍；批处理与回归用 `$fatal`，保证返回非零。
- 驱动端加随机反压与随机输入间隙（固定种子），否则握手 bug 只在上板时暴露。
- 变长报文用 SV 队列 `exp_q[$]`，每个元素带帧号/tag，丢包立刻错位报出。

## 3. 选仿真器

| 条件 | 工具 | 命令 |
|---|---|---|
| 纯 RTL、无 Xilinx 原语/IP，要快 | Verilator（2-state） | `verilator --binary -Wall --top-module tb tb.sv dut.sv && ./obj_dir/Vtb` |
| 需要四态、看 X 传播 | Icarus / xsim | `iverilog -g2012 -o sim tb.sv dut.sv && vvp sim` |
| 含 Xilinx 原语、IP、XPM | xsim（或 Questa） | 见下 |
| SpinalHDL 算子 | SpinalSim（Verilator 后端） | `sbt "runMain <Sim>"` |

Windows 下 Verilator 用 WSL：`wsl.exe -d Ubuntu -- bash -lc 'cd <dir> && ./run_sim.sh'`。从 `/mnt/e/...` 编译很慢，可把目录复制到 WSL 本地盘跑，日志写回仓库。

xsim 批处理（不依赖工程）：

```bash
xvlog -sv tb.sv dut.sv && xelab tb -debug typical -s tb_snap && xsim tb_snap -R
```

xsim 工程模式（Vivado Tcl / MCP）：

```tcl
set_property xsim.simulate.runtime 1us [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
# 时序仿真：-mode post-implementation -type timing
```

`launch_simulation` 在 xsim 运行时报 Fatal 时也可能返回 0，**必须读完整 transcript 判定**；不要用无界的 `run all`，TB 必须有看门狗。

## 4. PASS 判定（全部满足）

- [ ] 编译与 elaboration 无错误
- [ ] 仿真正常结束（非崩溃、非超时）
- [ ] 日志含唯一 PASS 标记，且不含 `FAILED`/`Fatal`/`ERROR`/`watchdog`
- [ ] 比对计数 = 期望计数（防止「什么都没比就 PASS」）
- [ ] 时序仿真额外确认 SDF 标注成功

`scripts/sim_check.py` 按以上规则判定日志并写 `result.json`。

## 5. 逐周期黑匣子

波形在无人值守时不可读。关键接口每拍写一行 CSV：

```systemverilog
integer fd; initial fd = $fopen("sim_trace.csv", "w");
always @(posedge clk) $fdisplay(fd, "%0d,%0b,%0b,%h,%0b,%h", cyc, in_v, in_r, in_d, out_v, out_d);
```

SpinalSim 用 `dut.clockDomain.onSamplings { ... }` 写同样的 CSV。

**PASS 不读 CSV；FAIL 只读出错周期前后 5~10 拍**，检查三件事：

1. `valid=1 && ready=0` 期间 payload 是否保持不变；
2. 下游 `ready` 拉低后，上游是否按协议拍数停住、有无溢出丢数；
3. `last`/`sof`/`valid` 与数据是否对齐，实际延迟是否等于设计值。

结论必须引用具体周期与数值，例如「第 45 拍 `in_v=1, in_r=0` 时 `in_d` 从 `0x12` 变为 `0x5A`，违反保持；原因 `core.sv:82` 输入寄存器使能未受 `in_r` 门控」。

## 6. Lint

```bash
verilator --lint-only -Wall -DSYNTHESIS --top-module <top> <files>   # SpinalHDL 生成的仿真字符串用 -DSYNTHESIS 排除
```

必须清零：`WIDTH`、`LATCH`、`MULTIDRIVEN`、`UNOPTFLAT`（组合环）、`BLKSEQ`、`IMPLICIT`。可按需关闭：`UNUSEDSIGNAL`、`UNUSEDPARAM`、`DECLFILENAME`。不靠关告警让 lint 变干净。

Vivado lint（2026.1 起输出 CSV）：`synth_design -top <top> -part <part> -lint -file lint.rpt`。

## 7. 仿真过了、上板不对

按顺序查，前两项最常见：

| # | 查什么 | 怎么查 |
|---|---|---|
| 1 | 板上是不是这次的 bitstream | 比 SHA256；读版本寄存器 |
| 2 | 主机侧数据契约 | 字节序、lane 顺序、对齐、长度、缓存同步（PYNQ 见 `../../pynq/references/troubleshooting.md`） |
| 3 | 时序 | 读 routed 后的 timing summary，不是综合估计 |
| 4 | 复位与时钟 | 复位极性/时长、MMCM locked、跨域复位同步 |
| 5 | X 态依赖 | 用四态仿真器重跑；Verilator 把 X 当 0 会掩盖未初始化寄存器 |
| 6 | 约束与引脚 | IO standard、引脚、时钟频率与仿真假设一致 |

还不清楚就上 ILA（见 `vivado-tools.md` 第 5 节），抓与 TB 相同的接口信号对比。

## 8. 证据留存

每个模块的验证目录保留：`run.log`、`result.json`（状态、比对数、周期数、种子、源文件 SHA256）、`lint.log`、向量清单（来源与哈希）、`checklist.md`。波形、`obj_dir`、sbt `target/` 不进提交包。
