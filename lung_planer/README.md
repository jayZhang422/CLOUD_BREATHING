# lung_planer：KV260 肺部手术规划 PL 几何加速

在 AMD KV260（Zynq UltraScale+ `xck26-sfvc784-2LV-c`）上运行的肺部手术规划系统。PS 端运行 Ubuntu + Python/Qt 界面，负责 CT/STL 导入、中心线骨架化、方案搜索和显示；PL 端是几何计算加速器，负责双平面楔形切除的网格裁剪与体积/面积积分、点集双平面过滤、中心线精确距离、多实体网格射线并集求交。

## PL 结构（100 MHz，单时钟域）

| BD 实例                 | RTL 顶层                    | 功能                                                                  | AXI-Lite 基址 | 数据通路                                                                   |
| --------------------- | ------------------------- | ------------------------------------------------------------------- | ----------- | ---------------------------------------------------------------------- |
| `dual_plane_mesh`     | `dual_plane_mesh_axi`     | 双平面候选 × 肺网格：三角形裁剪、BVH 剔除、FP64 体积/表面/切面积分（ABI 0x00050000）            | 0xA0012000  | 自带 AXI4 主口读 DDR                                                        |
| `dual_plane_filter`   | `dual_plane_filter_axi`   | 病灶点批量双平面过滤（单批 4096 点，软件分批）                                          | 0xA0011000  | `dual_plane_dma` 0xA00A0000                                            |
| `centerline_distance` | `centerline_distance_axi` | 体素掩膜上中心线点到边界的精确距离（Lee 候选）                                           | 0xA0090000  | `centerline_dma` 0xA0080000 + AXI4 主口                                  |
| `mesh_ray`            | `lung_ray_mesh_axi`       | BVH 网格射线求交与多实体并集（ABI 0.7，CORE_COUNT=1，MAX_HITS=128，STACK_DEPTH=128） | 0xA0040000  | `mesh_dma` / `mesh_ray_dma` / `mesh_result_dma` 0xA0050000/60000/70000 |

全部 DMA 与主口经 SmartConnect 汇入 `S_AXI_HP0_FPD`，数据位宽 128 bit，地址 64 bit。

## 实现结果（Vivado 2026.1，`build/reports/`）

| 项目      | 值                                   |
| ------- | ----------------------------------- |
| 时序      | WNS 0.416 ns，WHS 0.010 ns，TNS/THS 0 |
| CLB LUT | 65715 / 117120（56.11%）              |
| CLB 寄存器 | 76227 / 234240（32.54%）              |
| BRAM    | 18.5 / 144（12.85%）                  |
| URAM    | 2 / 64                              |
| DSP     | 228 / 1248（18.27%）                  |
| 片上功耗    | 3.329 W                             |
| 布线      | 129194 条网络全部布通，0 错误                 |

## 目录

```
lung_planer/
├── README.md
├── src/
│   ├── rtl/          # 26 个 Verilog 文件，均可从 BD 中 4 个 RTL 顶层到达
│   ├── bd/           # lung_planner_system_bd.tcl（PS + DMA + 互联 + 地址），lung_ray_mesh_abi.md（射线核寄存器与帧格式）
│   └── ps/           # 板端软件，取自板上运行版
│                     #   main.py + qml/（Qt 界面）、cas_frontend/（规划算法与 PL 驱动 pl_metrics.py）、
│                     #   tools/（pl_service、start_desktop.sh、板端准入与硬件检查）、tests/（297 项）、
│                     #   native/（Lee 骨架化、显示接触 C++ 扩展）、ctfpga/（CT→STL C++ 前端源码）
├── sim/
│   ├── tb/           # 4 个回归测试台
│   ├── run_sim.tcl   # XSim 批量回归
│   └── results/      # results.txt 与各仿真日志
├── build/
│   ├── create_project.tcl   # 重建工程（-tclargs build 同时出位流）
│   ├── export_outputs.tcl   # 导出 bit/bin/hwh 与报告
│   ├── single_thread_hook.tcl
│   ├── reports/             # 综合与实现报告
│   ├── output/              # 本目录重建得到的 lung_planner.bit/.bit.bin/.hwh
│   └── build.log
├── board/
│   ├── firmware/     # 板上实测的 lung_planner.bit/.bit.bin/.hwh、frozen_baseline.json、mesh-full.json（准入记录）
│   ├── scripts/      # deploy.sh（PC→板）、run_on_board.sh（板上检查/测试/准入/界面）
│   └── results/      # 实测输出：admission/、point_batches/、ray_union/、ray_mesh/、sw_tests/、address_map.txt
├── data/
│   ├── sim_vectors/  # 仿真输入与期望结果（全部为合成数据）
│   ├── board_vectors/ # 板上准入用的合成立方体向量（cube/）
│   └── reference/    # ray_mesh_bvh/ 射线 BVH 期望结果、双平面板端对拍摘要
├── skill/            # 技能包，见 skill/README.md
└── report/           # 设计报告相关材料；llm_collaboration/ 为大模型协作记录
```

### 目录对照与命名说明

目录结构与指南 3.3.5.4 的推荐结构一一对应（`README.md`、`src/`、`sim/`、`build/`、`board/`、`data/`、`skill/`、`report/`），没有改动层级。

所有目录名和文件名均为英文，不含中文、空格或特殊字符。除扩展名的点外，只有下表所列的文件或目录因工具、惯例或上游命名要求保留大写字母或版本号中的点，无法改成纯小写，否则对应工具或程序无法加载：

| 文件                                                                                 | 位置                                                                              | 保留原因                                  |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------- |
| `*.qml`（30 个，如 `Main.qml`、`AppButton.qml`）                                         | `src/ps/qml/`                                                                   | QML 要求组件文件名首字母大写，文件名即组件类型名，改名会使界面无法加载 |
| `README.md`、`SKILL.md`                                                             | 各目录                                                                             | 通用约定，指南的目录示例中也使用 `README.md`          |
| `CMakeLists.txt`                                                                   | `src/ps/ctfpga/`                                                                | CMake 只识别该文件名                         |
| `GPL-3.0-only.txt`、`LGPL-3.0-only.txt`、`SCIKIT_IMAGE_LICENSE.txt`、`LUCIDE-LICENSE` | `src/ps/runtime-deps/licenses/`、`src/ps/native/lee/`、`src/ps/qml/assets/icons/` | 沿用上游许可证文件名，便于对应来源                     |
| `libQt6EglFsKmsGbmSupport.so.6`                                                    | `src/ps/runtime-deps/qt-6.7.3-aarch64/`                                         | 动态库文件名由 Qt 决定，运行时按此名加载                |
| `qt-6.7.3-aarch64/`（目录名含版本号中的点）                                                    | `src/ps/runtime-deps/`                                                          | 目录名标明所随附的 Qt 版本与架构，部署脚本按此名引用                  |
| `LICENSE`                                                                          | 仓库根目录                                                                           | 开源许可文本的通用文件名                          |

## 复现步骤

环境：Vivado 2026.1（含 KV260 board file），Windows 或 Linux。以下命令在 `lung_planer` 的上一级目录执行，`vivado` 指 Vivado 2026.1 的可执行文件。

1. 重建工程并生成位流（约 40 分钟，实现阶段单线程）：
   
   ```bash
   vivado -mode batch -source lung_planer/build/create_project.tcl -tclargs build
   ```
   
   工程生成在 `build/work/lung_planner/`，位流与 HWH 导出到 `build/output/`，报告复制到 `build/reports/`。只建工程不综合时去掉 `-tclargs build`。

2. 运行 RTL 回归（需先完成第 1 步建工程，约 3 分钟）：
   
   ```bash
   vivado -mode batch -source lung_planer/sim/run_sim.tcl
   ```
   
   | simset                    | 测试台                               | 内容                                      | 通过标志                                 |
   | ------------------------- | --------------------------------- | --------------------------------------- | ------------------------------------ |
   | `sim_ray_mesh`            | `tb_lung_ray_mesh_bvh`            | 射线 BVH 求交，8 组合成向量（凸/非凸、128 交点边界、溢出、近平行） | `RAY_MESH_RTL_PASS`                  |
   | `sim_1`                   | `tb_dual_plane_mesh_axi`          | 双平面网格核 AXI 全流程几何结果                      | `DUAL_PLANE_MESH_RTL_GEOMETRY_PASS`  |
   | `sim_centerline_distance` | `tb_centerline_distance_axi`      | 中心线距离核，6 组掩膜/查询                         | `CENTERLINE_DISTANCE_CORE_TEST_PASS` |
   | `sim_branch_batch`        | `tb_dual_plane_batch_filter_core` | 点批量双平面过滤                                | `DUAL_PLANE_BATCH_RTL_PASS`          |
   
   测试向量路径通过 plusarg（`RAY_MESH_DIR`、`CL_DIR`）传入，不依赖盘符。
   
   Windows 上如果环境变量 `NoDefaultCurrentDirectoryInExePath` 已设置（部分终端会设置），XSim 的 `compile.bat` 会报 `Spawn failed`。运行仿真前需要清除这个变量。

3. 上板（KV260，Ubuntu 22.04 + PYNQ，Python 环境 `/home/ubuntu/cloud-breathing-venv`）：
   
   ```bash
   bash lung_planer/board/scripts/deploy.sh ubuntu@192.168.50.2
   ```
   
   然后在板上的应用目录执行：
   
   ```bash
   bash run_on_board.sh check
   ```
   
   `run_on_board.sh` 的子命令：
   
   | 命令        | 内容                                                                                 | 用时     |
   | --------- | ---------------------------------------------------------------------------------- | ------ |
   | `check`   | 核对 bit/hwh 哈希、准入记录与 17 个门禁源码哈希                                                     | 数秒     |
   | `tests`   | 全部 297 项单元/集成测试（PL 用 mock）                                                         | 约 1 分钟 |
   | `admit`   | 用合成立方体向量（`data/board_vectors/cube`，部署到 `vectors/`）在 PL 上重新生成 `fpga/mesh-full.json` | 约 10 秒 |
   | `points`  | 点批量双平面过滤，4096–16385 点，与 Q16.16 整数参考逐点比对，含取消/超时恢复                                   | 约 30 秒 |
   | `union`   | 多实体射线并集与并集体积（合成长方体）                                                                | 约 10 秒 |
   | `raymesh` | 射线 BVH 核容量（1、8002 个三角形）、重复任务与超时/Abort 恢复                                           | 约 1 分钟 |
   | `bench` | 合成肺形网格上双平面网格核的 PL 与 PS 耗时对比和一致性（见“性能对比”） | 约 6 分钟 |
   | `gui`     | 全屏规划界面（HDMI，最长 1 小时）                                                               | —      |
   
   `points`、`union`、`raymesh` 的 JSON 写到 `board-results/`。
   
   `deploy.sh` 默认写入板上运行版目录 `/home/ubuntu/memgmo/final/cloud-breathing-kv260`，会覆盖其中的软件与 `fpga/`。只想试跑时可传第二个参数指定其他目录，再用 `APP_DIR=<目录> bash run_on_board.sh check`。板端还需 `/home/ubuntu/cloud-breathing-venv`（PySide6 等，见 `src/ps/requirements-board.txt`）和 PYNQ 环境 `/usr/local/share/pynq-venv`。

### 关于位流哈希

重建得到的 `.bit.bin`（不含文件头）与 `board/firmware/` 中板上实测文件逐字节相同。`.bit` 和 `.hwh` 文件头含生成时间戳，每次重建 SHA256 都会变化。板端软件只接受与 `mesh-full.json` 绑定的 bit/hwh：

- 直接使用 `board/firmware/` 中的文件（默认），或
- 使用新构建（`FIRMWARE=lung_planer/build/output bash .../deploy.sh`）后，在板上运行 `bash run_on_board.sh admit` 重新生成准入记录，并同步更新 `frozen_baseline.json`。

### 准入门禁

规划使用 PL 双平面网格核前，`cas_frontend/dual_plane_mesh_gate.py` 的 `verify_admission` 检查 `mesh-full.json`：

- 是完整的板上对拍记录（ABI `0x00050000`）；
- 绑定当前的 bit/hwh，以及 17 个门禁源文件的 SHA256；
- 合成立方体的 4 个候选全部在 PL 上计算，体积、表面积、切面积与 PS FP64 参考的误差 ≤ 1e-5；
- 网格驻留复用正常，时钟 100±1 MHz，没有 CPU 回退；
- 取消和超时后硬件都能恢复。

修改 bit/hwh 或任何门禁源文件后，必须重新运行 `admit`。

## 板端实测结果（`board/results/`）

固件 `fpga/lung_planner.bit`，`.bit.bin` SHA256 `ce5fe329…a9241dbb`。以下结果都用 `src/ps` 中的软件和 `run_on_board.sh` 在板上得到。

- 准入（`admit`，`board/firmware/mesh-full.json`，摘要 `admission/dual_plane_parity_summary.json`）：合成立方体 4 个候选与 PS FP64 参考一致，最大误差 2.8e-17 mm³；取消与超时后均可恢复，CPU 回退 0 次。
- 点批量过滤（`points`，`point_batches/`）：4096、4097、4494、8192、9672、16385 点全部与整数参考一致，分别用 1/2/2/2/3/5 次 PL 调用；取消、超时后恢复。日志中的 `DUAL_PLANE_FILTER_FAILED` 和 `TimeoutError` 是有意触发的取消/超时测试。
- 射线并集（`union`，`ray_union/`）：单体、分离、重叠、嵌套、重复实体、起点在内部，以及分离实体的并集体积分数 0.447917，全部通过；时钟 99.999 MHz，能力位 `0x7f`。
- 射线 BVH 核（`raymesh`，`ray_mesh/`）：1 与 8002 个三角形的容量测试、重复任务、超时与 Abort 恢复通过。
- 软件测试（`tests`，`sw_tests/unit-tests.log`）：297 项全部通过。
- 性能对比（`bench`，`mesh_pl_vs_ps/`）：见下一节。

## 性能对比：PL 与 PS（`bench`，`board/results/mesh_pl_vs_ps/`）

**测什么。** 双平面网格核对 780 个楔形候选，各求（网格 ∩ 楔形）的体积、表面积和切面积。这是规划搜索里调用最多的一步。两侧用同一份输入，在同一块 KV260 上运行：

- **PS 基线：** 板上 ARM Cortex-A53，规划器 CPU 路径使用的 Manifold float64 布尔运算（`manifold_volume_metrics`），逐候选计算，单线程。
- **PL：** `lung_planner.bit` 中的 `dual_plane_mesh` 核（ABI `0x00050000`，100 MHz），一次批量提交 780 个候选。

**输入。** 合成的肺形闭合网格：变形椭球，20480 个三角形，约 2.7×10⁶ mm³；780 个楔形候选，随机朝向、张角 40°–130°。输入由 `gen` 子命令按固定随机种子生成，没有任何病例数据。

| 项目 | PS（Cortex-A53） | PL（100 MHz） | 加速比 |
|---|---:|---:|---:|
| 780 个候选总耗时，网格已驻留 | 77.7 s（77.6 / 78.3 / 77.7，3 次） | **9.06 s**（5 次，9.061–9.063） | **8.6×** |
| 同上，仅核计算时间（周期数 ÷ 时钟） | — | 8.63 s（8.63 亿周期） | 9.0× |
| 首次提交（含 BVH 构建和网格上传 DDR） | — | 13.1–15.1 s（2 次测量） | 5.2–5.9× |
| 单候选平均 | 99.6 ms | 11.6 ms | 8.6× |

PL 核计算 8.63 s，网格驻留后每次调用的 9.06 s 里多出的约 0.43 s 是候选打包、DMA 和结果解码。首次提交要多花 4–6 s 构建 BVH 并上传网格，两次测量分别是 13.1 s 和 15.1 s，抖动较大，所以给出范围；网格不变时这笔开销只付一次。

**一致性。** 780 个候选中 778 个 PL 与 PS 结果一致，最大绝对偏差：体积 3.7×10⁻⁹ mm³、表面积 1.3×10⁻¹⁰ mm²、切面积 5.8×10⁻¹¹ mm²，远小于 1e-5 的门限。其余 2 个（第 247、458 号）PL 返回标志位 `0x20`（`DPM_ERR_BINDING_CAP`），指标全部为 0。这是硬件有意的拒绝：楔形的辅助盖面与网格根包围盒相交时，两平面核无法表示该几何，它不返回数值，而不是返回错误数值。规划器收到标志位的候选不会采用。PS 对这两个候选给出了数值，所以 778 个才是可比较的数量，不是 780。

**这个对比说明什么，不说明什么。**

- 它测的是双平面网格核本身，在 PL 与 PS 之间的差别；不是端到端规划时间。端到端还包括候选生成、BVH 构建、点过滤核、最终复核等 PS 步骤，这些在 PL 版和 PS 版里都存在，所以整体加速比小于这里的 8.6×。
- 网格是合成的，三角形数（20480）与真实 15 万面减面后的肺网格同量级，但形状不是真实肺。真实网格上的加速比会有差异。本包不含病例数据，没有在真实病例上重复这个测试。
- PS 基线是 Manifold 的精确布尔运算，不是为 A53 优化过的手写代码。它代表规划器没有 PL 时实际使用的 CPU 路径，不代表 CPU 能达到的最快速度。
- 此前开发中测过的两病例端到端冷启动（约 40 秒降到约 21 秒）来自中间版本的位流（时序裕量和 CLB 占用都与最终版不同），未在最终位流上重复，因此本节不引用它。

复现：`bash run_on_board.sh bench`，生成、PS、PL 和比较四步自动完成，结果写入 `board-results/`。

## 数据与隐私

提交内容不含真实病例：没有 CT、STL、患者姓名、病例截图、路径，也没有由病例网格算出的数值。

- 仿真向量和准入向量全部是合成数据。射线 BVH 测试台中两组由病例网格导出的数据集不提供，回归用 `RAY_MESH_SYNTHETIC_ONLY` 跳过。
