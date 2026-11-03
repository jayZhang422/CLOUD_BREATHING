# Vivado 工具：构建、报告、IP、调试、工程可重建

适用：需要实际驱动 Vivado（批处理 Tcl 或 Vivado MCP），或解读它的报告与日志。
依据：UG835（Tcl）、UG894（Tcl 脚本）、UG892/UG895（工程与源码管理）、UG908（编程与调试）；AMD Vivado 技能包（`vivado-rtl-lint`、`vivado-rtl-elaboration-analysis`、`vivado-ip-configurator`、`vivado-revision-control`、`hw-ila-debug`、`hw-vio-debug`，MIT，© 2026 AMD）；Vivado MCP 2026.9.1。

## 1. 两种驱动方式

| 方式 | 何时用 | 规则 |
|---|---|---|
| 批处理：`vivado -mode batch -source build.tcl -tclargs ...` | 可复现构建、CI、交付给别人重跑 | 脚本进版本库；路径全部相对、由参数传入 |
| Vivado MCP（`vivado_execute` 等） | 交互诊断、读工程状态、查报告 | 同一 `session_id` 串行；不在工程树里落临时 `.tcl`；长命令用 `vivado_status` 轮询 |

Vivado MCP 常用工具：`vivado_list_sessions`、`vivado_start`（`vivado_path`、`working_dir`）、`vivado_execute`（`session_id`、`command`）、`vivado_status`、`vivado_log_messages`、`vivado_doc_search`（AMD 文档、Answer Record、Known Issues 检索）、`vivado_stop`。工具名与参数以本机 MCP 的工具列表为准。

**耗时操作需明确授权**：`synth_design`、`launch_runs`、`write_bitstream`、`program_hw_devices`。只读诊断与 lint 可以直接做。KU5P 规模的全流程约 1.5~2.4 小时，不确定时先用已有报告定位。

## 2. 带门禁的构建脚本

```tcl
launch_runs synth_1 -jobs $jobs; wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "synth_1 failed" }
launch_runs impl_1 -to_step write_bitstream -jobs $jobs; wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "impl_1 failed" }
open_run impl_1
report_timing_summary -file $out/top_timing_summary_routed.rpt
report_utilization    -file $out/top_utilization_placed.rpt
report_drc            -file $out/top_drc_routed.rpt
report_methodology    -file $out/top_methodology_routed.rpt
report_route_status   -file $out/top_route_status.rpt
report_power          -file $out/top_power_routed.rpt
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
if {$wns < 0 || $whs < 0} { error "Timing not met (WNS=$wns WHS=$whs); do not program this bitstream." }
```

- 门禁读 routed 后的真实 slack；setup 与 hold 都查；失败就 `error` 退出，不只是打印警告。
- 新 bitstream 写到 `build/out/`，复制到发布位置是人工确认动作。
- 构建结束跑 `python scripts/qor_check.py --timing ... --util ... --history qor_history.csv`。

## 3. 读日志与报告

```bash
python scripts/vivado_log_triage.py synth_1/runme.log impl_1/runme.log --csv messages.csv
```

按消息 ID 归并后，先 ERROR，再 CRITICAL WARNING，再按数量看 WARNING。常见 ID：

| ID | 含义 | 动作 |
|---|---|---|
| `Synth 8-327` | 推断 latch | 组合块补默认值/`default` |
| `Synth 8-3332` / `8-6014` | 寄存器未使用被删除 | 确认是否本应有负载；大批出现常是端口未连 |
| `Synth 8-7129` | 端口未连接或无负载 | 多为未用 AXI 通道，可接受；数据端口出现要查 |
| `Synth 8-7137` | 同一寄存器置位复位同优先级 | 改写复位逻辑，避免仿真/综合不一致 |
| `Synth 8-4767` | RAM 无法推断，改用寄存器 | 查读写方式、深度、初始化，见 `rtl-coding.md` 第 6 节 |
| `Synth 8-3917` | 端口被常量驱动 | 确认是参数化预期还是连线错误 |
| `Constraints 18-402` | 约束对象不是合法起点/终点 | 通配符过宽或对象被优化；按 XDC 行号收窄 |
| `Timing 38-316` | OOC 综合时钟与实际不同 | OOC 时钟周期改为实际值，否则 IP 内部时序估计失真 |
| `DRC SYNTH-9` | 小乘法映射到 LUT | 查 `use_dsp`，见 `timing-closure.md` 案例 A |

分析报告只汇报：CRITICAL WARNING/ERROR、违例路径（起点、终点、逻辑级数、逻辑/布线占比）、DSP/BRAM 映射状态、RTL 级修改建议。结论带 `文件:行号`。不把整份日志读进上下文。

## 4. IP 配置

```tcl
set vlnv [get_ipdefs -filter {NAME == axi_dma}]           ;# 取当前版本真实 VLNV，不凭记忆
create_ip -vlnv $vlnv -module_name dma0
set before [list_property [get_ips dma0] CONFIG.*]
set_property -dict [list CONFIG.c_sg_length_width {26} CONFIG.c_include_sg {0}] [get_ips dma0]
puts [get_property CONFIG.c_sg_length_width [get_ips dma0]]   ;# 读回验证
generate_target all [get_ips dma0]
```

- 参数名与合法值先查 PG 文档或 `vivado_doc_search`。
- **BD 里未知参数不会抛异常**，只报 `[BD 41-1276]` 或 `[IP_Flow 19-7090]` 警告，`catch` 返回 0。所以必须读回 + 扫描输出警告，三者都过才算配置生效。
- `VALUE_OUT_OF_RANGE` 报错文本里给出了合法范围，直接按它修正。
- IP 用 `write_ip_tcl` 或 `.xci` + 版本锁定管理；生成完即止，不顺手跑综合。

## 5. 上板调试（ILA / VIO）

前提：`.bit` 与 `.ltx` 同一次构建。不匹配不会报错，只会抓到错位的信号。Vivado 与 hw_server 版本不一致报 `[Labtools 27-3366]`，换匹配版本，不要反复重试。

```tcl
open_hw_manager; connect_hw_server -url localhost:3121; open_hw_target
set_property PROBES.FILE top.ltx [current_hw_device]; refresh_hw_device [current_hw_device]
set ila [lindex [get_hw_ilas] 0]
set_property CONTROL.TRIGGER_POSITION 512 $ila
set_property TRIGGER_COMPARE_VALUE eq1'b1 [get_hw_probes <probe> -of_objects $ila]
run_hw_ila $ila
wait_on_hw_ila -timeout 1 $ila                ;# 单位是分钟；不写则无限等待
write_hw_ila_data -csv_file capture.csv [upload_hw_ila_data $ila]
```

- 不确定触发会不会发生，先 `run_hw_ila -trigger_now` 验证采集通路。
- 不用 `display_hw_ila_data`（需要 GUI），用 `write_hw_ila_data` 导出 CSV。
- VIO：`set_property OUTPUT_VALUE 1 [get_hw_probes <p> -of_objects [get_hw_vios hw_vio_1]]` 后必须 `commit_hw_vio`；重新烧写后先 `refresh_hw_vio -update_output_values`。VIO 改出来的结果不能作为验收证据。

## 6. 工程可重建

可重建的最小集：RTL、XDC、IP 配置（`write_ip_tcl` 或 `.xci`）、BD（`write_bd_tcl`）、仿真源、数据文件、一个 `create_project.tcl`/`build.tcl`。不进版本库：`.runs`、`.cache`、`.gen`、`.sim`、日志、波形。

```tcl
write_bd_tcl -force -include_layout bd/system.tcl
write_project_tcl -force -no_copy_sources -use_bd_files build/create_project.tcl   ;# 生成后检查并改成相对路径
```

验证：在空目录执行重建脚本，比较 top、part、IP 实例与关键 CONFIG、约束文件列表、源文件 SHA256。只生成脚本不重建，等于没验证。

## 7. 文档检索

| 场景 | 文档 |
|---|---|
| HDL 写法、综合属性 | UG901 |
| 时序分析、收敛 | UG906、UG949 |
| 约束 | UG903 |
| Tcl 命令 | UG835 |
| 仿真 | UG900 |
| 调试（ILA/VIO） | UG908 |
| IP 参数 | 各 IP 的 PG（如 AXI DMA PG021） |
| 工具缺陷、版本问题 | AMD Adaptive Support Answer Record |

入口：https://docs.amd.com/ ，https://adaptivesupport.amd.com/ 。引用写到「文档号 + 章节」，查不到就说查不到。
