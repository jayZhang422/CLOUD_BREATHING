# KU5P 肺部结构分割模型 FPGA 部署

在 AMD Kintex UltraScale+ `xcku5p-ffvb676-2-i`（开发板 RK-XCKU5P-F V1.2）上部署 2.5D ResUNet + MKDC 分割网络。主机通过千兆网口把整卷胸部 CT 上传到板载 DDR4，FPGA 按执行清单自主调度全部算子，主机再回读结果并生成 STL 网格。网络输出九类结构：五个肺叶、气道、肺动脉、肺静脉和肺肿瘤，由肺叶、气道、血管、肿瘤四个模型分别完成。

实现方式：手写 RTL（SystemVerilog/Verilog）加 SpinalHDL 生成的算子，主机侧用 Python 与 C++17 上位机驱动。不使用 HLS、Vitis AI 或 DPU。

## 器件与工具

| 项目 | 内容 |
|---|---|
| 器件 | `xcku5p-ffvb676-2-i`（Kintex UltraScale+） |
| 开发板 | RK-XCKU5P-F V1.2，QSPI Flash MX25U51245G |
| 综合与实现 | Vivado 2026.1 |
| 烧录 | Vitis 2026.1 `program_flash` |
| 仿真 | Vivado XSim 2026.1；Verilator 5.032、SpinalHDL 1.12.3、Scala 2.13.14（WSL Ubuntu） |
| 上位机 | Python 3.12+（numpy、scipy、pydicom、scikit-image、vtk，见 `src/host/python/pc_fpga_app/requirements.txt`）；C++17、CMake 3.16+ |
| 训练与量化 | PyTorch 2.3.0+cu121 |
| 网络 | 板卡 `192.168.1.10:8080`， 上位机网卡 `192.168.1.102/24` |

## 实测结果

**最终实现**（布线后，报告在 `build/reports/final/`）：

| 指标 | 数值 |
|---|---|
| 时序 | WNS +0.050 ns、TNS 0、WHS +0.010 ns，用户时序约束全部满足 |
| 时钟 | 算子计算 250 MHz，DDR4 MIG 用户时钟 333.333 MHz，RGMII 125 MHz |
| 资源 | LUT 99,355（45.79%）、FF 168,007（38.72%）、BRAM 434.5（90.52%）、URAM 56（87.50%）、DSP 1,440（78.95%） |
| 功耗 | 3.511 W，为工具估算值 |

**整卷上板**（四个模型全部由 FPGA 执行，结果完整回读并校验 CRC32 与 SHA256，运行记录在 `board/full_volume/`）：

| 病例 | 层数 | 调度命令 | 推理耗时 |
|---|---:|---:|---:|
| case_a | 334 | 39,312 / 39,312 | 487.1 s |
| case_b | 245 | 30,090 / 30,090 | 364.5 s |
| case_c | 245 | 30,090 / 30,090 | 364.1 s |

三例的板上输出（共 2.16 亿个 uint16 体素）与 PC（GPU）运行同一套冻结整数网络的输出 SHA256 完全相同，比对记录见 `board/accuracy/board_vs_pc_consistency.md`。公开数据集上 FP32 与整数图的 Dice 对比见 `board/accuracy/dataset_dice.md`，整数图相对 FP32 的下降均不超过 0.2 个百分点。

## 目录结构与对照

本仓库的组织方式与选题指南 3.3.5.4 的推荐结构略有不同，对照如下。

| 推荐目录 | 本仓库位置 | 内容 |
|---|---|---|
| `README.md` | 本文件 | 简介、复现步骤、目录对照 |
| `src/` | `src/` | `rtl/`（RTL）、`scala/`（SpinalHDL 算子）、`ip/`（26 个 Vivado IP 的 `.xci`）、`constraints/`（约束）、`params/`（INT8 权重、参数 ROM、整数 Golden）、`host/`（上位机）、`training/`（训练与量化源码） |
| `sim/` | `sim/` | `standalone/`（Verilator/SpinalSim 算子级与链路级）、`xsim/tests/`（Vivado XSim 系统级，每个子目录一个专题） |
| `build/` | `build/` | 构建脚本（`create_project.tcl`、`run_flow.tcl`、`gen_mcs.tcl`）、综合与实现报告（`reports/`）、可烧录文件（`flash/`） |
| `board/` 上板工程 | `build/flash/` | `top.bit`、`top.ltx`、`top.mmi`、`program_qspi.bat` |
| `board/` 运行脚本 | `src/host/` | Python 版 `python/pc_fpga_app/`、C++ 版 `cpp/ctfpga/`、逐算子自检 `python/bin_udp/` |
| `board/` 实测输出 | `board/` | 三例整卷运行记录、性能汇总、精度与一致性结论 |
| `data/` | `data/manifest.csv`、`src/params/int8/*/golden_synthetic_32x32/` | 三例整卷的哈希清单；不含患者数据的合成 32×32 整数 Golden |
| `skill/` | `skill/` | 技能包，含 `pynq/`、`fpga/`、`model-deploy/` 三个子技能，入口为 `skill/README.md` |
| `report/` | `report/collaboration_llm/`、技术文档 | 大模型协作记录，五个案例以及技术文档 |

命名说明：目录名与文件名均为小写英文、数字、下划线或连字符。例外：`README.md`、`skill/*/SKILL.md`（智能体按固定文件名加载技能）、`src/host/cpp/ctfpga/CMakeLists.txt`（CMake 要求）、上一级仓库根目录的 `LICENSE`。`sim/` 下 `verification/` 中形如 `airway_d1.mix` 的名称是用例标识，由生成脚本产生并被同目录 CSV 引用。

## 复现步骤

### 1. 重建 Vivado 工程并生成比特流

在本目录（`resunet_deployment/`）执行。工程写到 `build/vivado/`，结果写到 `build/out/`，均不入库：

```bash
vivado -mode batch -source build/create_project.tcl
```

```bash
vivado -mode batch -source build/run_flow.tcl
```

脚本路径从自身位置推算，不依赖绝对路径。`run_flow.tcl` 使用 Vivado 默认策略，WNS 或 WHS 为负时以错误退出，不会覆盖 `build/flash/top.bit`。需要 QSPI 固化镜像时再执行 `build/gen_mcs.tcl`。

重建耗时：`create_project.tcl` 约 2.5 分钟，`run_flow.tcl` 约 2 小时 25 分钟，峰值内存约 10.5 GB。重建得到的时序与资源数字与已提交报告完全一致；重建出的 `top.bit` 与 `build/flash/top.bit` 大小相同，仅文件头 6 个字节（生成时间）不同，同步字之后的配置数据逐字节一致，因此核对时请比较配置数据，不要比较整文件哈希。

### 2. 烧录

不重新综合时，直接使用 `build/flash/top.bit`（SHA256 `bec4216815c7563107cf64417dc15adeef16d3a3da9402b827eef45b9263f218`）：用 Vivado Hardware Manager 经 JTAG 下载，或运行 `build/flash/program_qspi.bat` 固化到 QSPI。该脚本里写的是作者本机的 Vitis 路径 `D:\Xilinx\2026.1\Vitis\bin\program_flash`，换机器时先改路径，并在 `flash/` 目录下运行。

### 3. 上板运行

在 `src/host/python/pc_fpga_app/` 下建立 Python 3.12+ 环境并安装 `requirements.txt`，然后执行整卷流程（CT2BIN → Send → Reasoning → Receive → BIN2STL → Smooth → Cut）：

```powershell
python -X utf8 -B -u main.py --stage all --data-dir <DICOM 目录或 .zip> --case-dir output/<case> --image-base 0x00400000 --batch-slices 8 --run-timeout 7200 --plain
```

分阶段运行时把 `--stage` 依次换成 `ct2bin`、`send`、`reasoning`、`receive`。推理中断后，用同一 `--case-dir` 重跑 `--stage reasoning`；回读中断后重跑 `--stage receive`。

C++ 版（case_c 使用）在 WSL（Ubuntu）内构建，依赖 `g++ cmake ninja-build nlohmann-json3-dev zlib1g-dev libgdcm-dev libvtk9-dev`：

```bash
src/host/cpp/ctfpga/scripts/build.sh ~/ctfpga_build_vtk
```

```bash
~/ctfpga_build_vtk/ctfpga --stage all --data-dir <DICOM 目录或 .zip> --case-dir <case> --assets src/host/python/pc_fpga_app/assets --host 192.168.1.10 --bind 192.168.1.102
```

### 4. 核对结果

回读完成后，对 `<case>/prediction/segmentation_uint16.bin` 计算 SHA256，与 `data/manifest.csv` 中对应病例的 `output_sha256` 比较。换用自己的 CT 时，判据是板上输出与同一套冻结整数网络（`src/training/quantization/mkdc_int8.py`，参数在 `src/params/int8/`）在 GPU 上的输出哈希相同。

不依赖患者数据的核对：每个模型的 `src/params/int8/<model>/golden_synthetic_32x32/` 带有合成输入和 65 个节点的整数参考结果，`src/training/quantization/verify_export.py` 会逐节点比对冻结整数网络的输出，全部相等时输出 `"status": "PASS"`：

```bash
python -X utf8 -B src/training/quantization/verify_export.py --export src/params/int8/lobe
```

### 5. 运行仿真

仿真在 WSL（Ubuntu）中运行，所有仿真自校验，输出 `[TB PASSED]`（或 `result.json` 中 `"status":"PASS"`）才算通过。向量文件（`.hex`、`.bin.gz`，以及部分 `vectors/` 下的索引文件）体积大、可重建，未入库，首次运行前先执行对应目录的 `generate_vectors.py`（或 `prepare*.py`、`generate_fast_vectors.py`）。例如：

```bash
wsl.exe -d Ubuntu -- bash <仓库在 WSL 中的路径>/sim/standalone/run_in_wsl.sh ddr make
```

`run_in_wsl.sh` 从自身位置推算仓库路径。从 Git Bash 调用 `wsl.exe` 时需先设 `MSYS_NO_PATHCONV=1`。`sim/standalone/*/rtl/` 里是各独立仿真当时使用的 RTL 副本，不一定与 `src/rtl/` 一致；上板与综合使用的是 `src/rtl/`，其后续修改由 `sim/xsim/tests/` 中针对 `src/rtl/` 的仿真覆盖。

## 已知限制

- 真实 CT 来自患者，不随仓库提供。`data/manifest.csv` 与 `board/` 只有哈希和小型 JSON 记录，三例原始 `.bin` 因体积限制未提交；板上与 PC 一致的结论依据是 SHA256。
- 板上输出与 PC 逐位一致只说明板子执行的整数网络与 GPU 参考等价。分割精度来自公开数据集上的软件侧 Dice。
- 板上耗时是推理阶段（不含上传与回读），PC 耗时是整个流程，二者统计范围不同，不构成加速比。
- DDR4 仿真模型因 AMD Xilinx 与 Micron 的再分发条款未能确认，未随仓库提供，因此 `sim/xsim/tests/ddr/` 不能直接运行，且仓库内未保存该仿真的日志；DDR4 读写通路由整卷上板验证。需要时在自己的 Vivado 安装中打开 `ddr4_0` 的 Example Design，取出 `ddr4_model.sv` 等文件放到 `sim/xsim/imports/`。

## 许可

本仓库自有代码与文档按 [Apache License 2.0](../LICENSE) 发布。

- `src/rtl/op/` 下的 `dw3x3.v`、`dw5x5.v`、`pwmac*.v`、`elementadd_p16.v`、`linebuffer_*.v`、`maxpool2d_512x512_c16.v`、`upsample.v` 由 `src/scala/` 经 SpinalHDL 1.12.3 生成（SpinalHDL 核心库 LGPL-3.0，其余 MIT）。
- `src/ip/` 的 `.xci` 是 Vivado IP 的配置文件，IP 核本身属 AMD，随 Vivado 授权使用，不随库携带。
- 仓库不分发任何训练数据集。训练使用 TotalSegmentator（CC BY 4.0）、ATM'22（须注册获取）、HiPaS（MIT）、PARSE 2022、MSD Task06（CC-BY-SA 4.0）和 NSCLC-Radiomics（CC BY-NC 3.0，仅限非商业），请按各自条款自行下载与引用。
- `src/params/int8/tumor/` 的肿瘤权重使用过 NSCLC-Radiomics 训练。该非商业许可是否延伸到权重尚未核实，商业使用前请向数据提供方确认；Apache-2.0 只覆盖代码。
