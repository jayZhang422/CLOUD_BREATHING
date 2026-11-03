# 时序收敛与约束

适用：综合/实现后 WNS、WHS、WPWS 为负；报告变绿但怀疑约束有问题；编写或评审 XDC。
依据：UG906（设计分析与收敛）、UG903（约束）、UG949（方法学）、AMD `vivado-timing-methodology-checks` 技能（MIT）；案例来自本项目 XCKU5P @250 MHz 的修复记录（WNS −1.185 → +0.050 ns）。数值只作线索，换器件/频率后只保留判断顺序。

## 1. 先分类，再动手

```
1. qor_check.py：WNS/WHS/WPWS、按时钟分解、资源与上一版 diff
2. report_methodology：约束有无漏写/矛盾/未约束路径          ← 先排除约束层问题
3. 资源是否突变（某类硬核骤降 + LUT 暴增）                   ← 是 → 映射问题，案例 A
4. 失败端点是否高度聚集在少数起终点                          ← 是 → 结构/控制链问题，案例 B
5. hold 违例：逻辑级数 1~2 级但 slack 很负、时钟偏斜大         ← 是 → 跨域问题，案例 C
6. 以上都不是，且路径级数确实高                              ← 才考虑流水线/重定时/物理优化
```

| 判据 | 逻辑太长 | 映射/结构错误 |
|---|---|---|
| 资源 | 与上一版接近 | 某类资源突变 |
| 失败端点 | 分散 | 集中在少数寄存器 |
| 逻辑级数 | 普遍偏高 | 单条不高，但同一源点复制出大量路径 |
| 报告 | 无异常 | `SYNTH-9`、`Synth 8-4767` 等提示退化 |

## 2. 三个禁止

1. **不为让报告变绿而降频。** 等于放弃目标，掩盖根因。
2. **不无依据加 `set_false_path` / `set_clock_groups -asynchronous`。** 只有两端确实无时钟关系、且已有正确同步结构时才可用，并写明理由。
3. **不在 1 级逻辑的 hold 违例上加流水线。** 问题在跨域或偏斜，不在级数。

## 3. 案例 A：映射属性丢失（资源 → 时序）

- 现象：重新生成 SpinalHDL RTL 后，DSP 1232 → 428、LUT +2.5 万、CLB 69% → 91%，WNS −0.829 ns，8444 个失败端点。
- 定位：逐模块统计 DSP 归属（含大量 8×8 乘法的 DW 模块 DSP 为 0）；`report_drc -checks SYNTH-9` 列出「乘法因尺寸小映射到 LUT」；对比提交版与新生成版，`(* use_dsp = "yes" *)` 消失。
- 修复：属性加在 **Scala 源** 的乘法结果信号上（576 处），重新生成。LUT −33.6%，DSP 428 → 1028，WNS 转正。
- 可迁移结论：**「LUT 暴增 + 某类硬核骤降」先查映射属性**；任何由脚本/生成器产出的 RTL，属性必须落在生成器源上。

## 4. 案例 B：控制链复用（结构 → 时序）

- 现象：最差路径 21 级逻辑（逻辑 1.77 ns + 布线 2.88 ns，周期 4 ns），终点为计数器 CE。
- 定位：导出全部失败端点聚类，发现是少数控制信号（装载/运行/排空共用的 ready、全局 `state_nxt`）被多个场景复用，而不是数据通路太长。只看最差路径会误判。
- 修复（未加数据流水级）：装载计数不再依赖全局次态；`core_done` 先寄存再用于退出判断；用已有 FIFO 缓存请求，切断「reader → 两级仲裁 → 地址分类 → ready」长链。
- 代价必须如实记录：FIFO 让部分层周期数增加 5.8%~17.9%（同频同夹具对照）。**这类改动换来的是收敛，不能宣称提速。**

```tcl
# 导出失败端点并统计起终点频次
set paths [get_timing_paths -setup -slack_lesser_than 0 -max_paths 100000 -nworst 1]
foreach p $paths { puts "[get_property STARTPOINT_PIN $p] -> [get_property ENDPOINT_PIN $p] [get_property SLACK $p]" }
```

## 5. 案例 C：通配符约束造成假通过 + 跨域 hold

- 现象 1：`request_*_r_reg*` 通配符把两端同为 4 ns 时钟的路径误套 6 ns `-datapath_only`，报告显示正 slack，实际是**假通过**。
- 现象 2：RX 域 `active_bank_r` 组合驱动计算域 RAM 地址，768 条 hold 违例，最差 −5.302 ns，偏斜 5.443 ns，逻辑 1 级。
- 修复：在计算域新增 `active_bank_ui_r` 与请求头同拍捕获；6 ns 约束只覆盖到捕获寄存器；通配符收窄到 RX 域的确切寄存器名。没有加 false path、异步组或 waiver。
- 反查规则：**写了通配符，就检查同域路径是否仍按目标周期检查**；日志里大量 `Constraints 18-402 ... is not a valid startpoint` 说明通配符匹配到了不该匹配的对象（组合单元、被优化掉的寄存器），约束可能没按预期生效。

## 6. XDC 写法要点

```tcl
# 主时钟与派生时钟
create_clock -name sys_clk -period 5.000 [get_ports sys_clk_p]
create_generated_clock -name clk_div2 -source [get_pins u_mmcm/CLKIN1] -divide_by 2 [get_pins u_mmcm/CLKOUT0]

# 跨域：有同步结构时，约束数据传播上限，而不是整条豁免
set_max_delay -datapath_only [expr 1.5 * 4.0] \
  -from [get_cells -hier -filter {NAME =~ *u_tx/req_data_r_reg*}] \
  -to   [get_cells -hier -filter {NAME =~ *u_rx/req_data_capture_r_reg*}]

# 外部异步复位：只豁免「端口 → 同步器第一级」
set_false_path -from [get_ports rst_btn_n] -to [get_cells -hier -filter {NAME =~ *rst_sync_r1_reg*}]
```

- 外部接口 `set_input_delay`/`set_output_delay` 写 max/min 两套；DDR 接口覆盖双沿；数值来自器件手册或原理图。
- XDC 里不支持 `if` 等控制流，需要条件约束时拆到单独文件，用文件属性 `PROCESSING_ORDER LATE`、`USED_IN_SYNTHESIS false` 控制加载时机。
- 只用于实现的约束（引用综合后才存在的单元）设 `set_property USED_IN_SYNTHESIS false`，用 `report_compile_order -constraints` 核对加载顺序。
- 诊断用的约束快照不要加入正式 `constrs_1`。

## 7. report_methodology 流程

```tcl
open_checkpoint top_routed.dcp          ;# 或 open_project + open_run impl_1
report_methodology -file methodology.rpt
write_xdc -force -exclude_physical constraints_before.xdc
```

- 先修 `TIMING-*` 中涉及时钟定义、未约束路径、跨域的条目，再看路径 slack。
- 按规则号分组，组内一次收集数据，改完一组复跑一次，比较违例数；**总数不变但规则号变了，说明改错了对象**。
- 能直接改的：漏写 `set_clock_uncertainty`、派生时钟未建模等写法缺漏。必须问人的：两个时钟是否真异步、某路径是否该被检查。
- 豁免用 `create_waiver -of_objects [get_methodology_violations <ID>] -user <name> -description <理由>`，理由写进报告。

## 8. 迭代纪律

- 一次只改一个变量；每轮跑 `scripts/qor_check.py --history qor_history.csv --tag <round>` 记录。
- 没重新综合实现的轮次，不写数值，写 `not_resynthesized`；不用旧检查点的数字下结论。
- 一份上板证据只对应一个 bitstream；生成新 bitstream 而未上板，要在报告里写明断点。
- 官方 IP（MIG/PLL）内部路径不改 IP，记录现象与版本，查 Answer Record。
