# ctfpga（C++17）

CT 打包 BIN → UDP 发送 → 推理等待 → 回读 BIN → BIN→STL → 平滑 → 减面。病例目录布局、`job.json`、`status.json`、`manifest.json` 与 `script/python/PC_FPGA` 一致，两边产物可互读。

## 构建（WSL / Ubuntu）

依赖：`g++ cmake ninja-build nlohmann-json3-dev zlib1g-dev libgdcm-dev libvtk9-dev`

```bash
scripts/build.sh ~/ctfpga_build_vtk                       # 完整（含网格阶段）
scripts/build.sh ~/ctfpga_build -DCTFPGA_WITH_VTK=OFF     # 仅数据面，无需 VTK
```

## 用法

```bash
ctfpga --stage all --data-dir <DICOM 目录或 .zip> --case-dir <病例目录> --host 192.168.1.10 --bind 192.168.1.102
ctfpga --stage bin2stl --prediction-dir <已有 prediction> --ct-metadata <input/metadata.json> --case-dir <新目录>
```

阶段：`ct2bin send reasoning receive bin2stl smooth cut all`。冻结资产（`volume_plans.json`、`tumor.params.bin`、`volume_assets.json`）
用 `--assets` 或环境变量 `CTFPGA_ASSETS` 指定，当前可直接指向 `script/python/PC_FPGA/assets`。

## 源码结构

| 目录 | 内容 |
|---|---|
| `src/app/` | `main.cpp`：命令行参数、阶段调度 |
| `src/common/` | 工具函数（SHA256/CRC32、JSON、文件）、病例流程 `case_flow` |
| `src/ct/` | DICOM 读取、CT→INT8 BIN / VOL2 转换 |
| `src/net/` | UDP 协议、板端操作客户端、体数据控制 |
| `src/mesh/` | 网格三阶段（需 VTK），见下表 |
| `tests/` | `ctest` 单元测试 |
| `tools/` | `mockboard.cpp` 软件板端；`analysis/` 参考体积对比脚本 |
| `scripts/` | 构建、验证、复现配方脚本 |

`src/mesh/` 内：

| 文件 | 作用 |
|---|---|
| `repair.cpp` | 掩膜修补：肺叶联合、静脉碎片桥接（`--far-bridge-mm`）、肿瘤修补 |
| `surface.cpp` | 掩膜→表面：距离场（SDF）高斯、骨架钳制、体积匹配等值面、Flying Edges、Windowed Sinc |
| `decimate.cpp` | 减面：保闭合流形的 QEM 边折叠（link condition + 法向翻转检查） |
| `stages.cpp` | `bin2stl` / `smooth` / `cut` 三阶段的调度与质量守卫 |
| `mesh_io.cpp` | STL 读写、质量检查（闭合、连通块、体积）、Taubin |
| `morph.cpp` `volume3d.cpp` | 形态学与三维体数据工具 |

## 网格平滑与减面

各结构的处理方式：

| 结构 | 平滑（`smooth`） | 减面（`cut`） |
|---|---|---|
| 肺叶 | 沿用原流程 | 每个 5,000 面 |
| 气管 | SDF 高斯 σ0.7 / σz1.1 mm，不钳制 | 38,000 面 |
| 动脉 / 静脉 | SDF 高斯 σ1.0 / σz1.5 mm，骨架钳制，体积匹配等值面（下限 −0.12 mm），Sinc 30 轮 | 55,000 / 65,000 面 |
| 肿瘤 | 高斯 σ1.0 mm，Taubin 5 轮，平滑阶段内减到 2,000 面 | 2,000 面 |

关键参数（均有命令行开关，默认值见 `src/mesh/stages.hpp`）：

| 参数 | 默认 | 说明 |
|---|---|---|
| `--vessel-sigma` / `--vessel-sigma-z` | 1.0 / 1.5 | 血管距离场高斯，z 向更大以压层间半径跳变（环纹） |
| `--vessel-skeleton 0\|1` | 1 | 只钳制 3D 骨架及一个体素邻域，其余体素可被平滑，避免保留台阶 |
| `--vessel-match-volume 0\|1` | 1 | 按原体素数选等值面，抵消平滑造成的体积缩小 |
| `--vessel-min-level` | −0.12 | 匹配体积时等值面外扩上限（mm），防止相邻静脉分支被填成薄片 |
| `--vessel-taubin` | 10 | 复现配方里用 0 |
| `--airway-sigma` / `--airway-sigma-z` | 0.7 / 1.1 | 气管 |
| `--tumor-sigma` / `--tumor-taubin` / `--tumor-faces` | 1.0 / 5 / 2000 | 肿瘤 |
| `--cut-{lobe,airway,artery,vein,tumor}-faces` | 0（用 `--max-faces`） | 分器官减面目标 |
| `--cut-smooth` | 0 | 减面后 Taubin 轮数，磨去低面数产生的棱角；复现配方用 12 |

减面不用 VTK 的 `vtkQuadricDecimation`：它在大比例减面时会产生非流形边并拆出碎片，实测被质量守卫拒绝。`cut` 阶段若体积变化超过 5%、出现开放/非流形边或连通块数变化，会把目标面数放宽 25% 重试，最多 4 次。

一键复现（从已有 `stl/raw` 出发，不覆盖原目录）：

```bash
scripts/run_smooth_cut.sh <含stl/raw的病例目录> <新病例目录>
```

参考病例（王凤红）结果：总 185,000 面；体积变化 −2.2% 到 +0.9%；所有对象闭合流形，连通块数与减面前一致。

**适用范围**：算法（骨架钳制、体积匹配、保流形减面）与病例无关，但上面的默认参数和面数预算只在一个病例（间距 1.0/0.80/0.80 mm）上调过，未在其他间距或掩膜质量差的病例上验证。`tools/analysis/ref_volume*.py` 可对比标准模型与掩膜体积，11 个病例的比值在 0.67 到 3.1 之间，说明掩膜质量差异很大。换病例时请先看渲染和 `run_report.json`。

## 验证脚本（均在 WSL 内运行）

| 脚本 | 内容 |
|---|---|
| `build/ctest` | SHA256/CRC32 已知向量、帧编解码与篡改拒收、预转置与硬件 gather 逐像素等价、位掩码合法性 |
| `scripts/verify_ct2bin.sh` | 真实 DICOM → INT8 BIN / VOL2，与 Python 版 SHA256 和元数据逐项比对（需 `output/ct_03_q4` 参考，现已不在仓库） |
| `scripts/verify_ct2bin_zip.sh <CT.zip> <Python 参考病例目录>` | ZIP 病例 → BIN / VOL2，逐文件 SHA256、sidecar、metadata、job.json 与 Python 输出比对（`BATCH` 默认 8） |
| `scripts/e2e_loopback.sh [丢包间隔] [超时]` | `mockboard` 充当板端：DDR 实收内容哈希、执行清单/坐标表哈希、回读哈希、RELEASE。`DATA`、`REF`、`BATCH` 环境变量可覆盖输入；参考目录无 prediction 时合成合法 UINT16 结果回放 |
| `scripts/run_mesh.sh` / `bench_cores.sh` | 网格三阶段耗时与峰值内存，可限定核数 |
| `scripts/compare_mesh.py` | 与 Python 版逐结构比较掩膜、面数、体积、最近顶点距离 |

`tools/mockboard.cpp` 是主机侧的软件替身，只用于联调，不是 RTL 仿真，也不是交付物。

## 与 Python 版的差异（未覆盖项）

- 血管厚度自适应平滑（`vessel_surface.refine_stl`）**未按原样移植**；C++ 版改用 SDF 高斯 + 骨架钳制 + 体积匹配等值面，效果不同于 Python 版。
- `reference_support` 参考掩膜分支未移植；只读 `ct-segmentation-bitmask-v2` 预测。
- `skimage.MCP_Geometric` 以 6 邻域 Dijkstra 替代；路径等长，但并列时可能取不同路径。
- 行进立方体用 VTK Flying Edges，三角划分与 skimage 不同，面数会有小幅差异。
- ZIP 读取已用真实 ZIP（334 层）验证，BIN / VOL2 与 Python 版逐字节一致。DICOM 仅验证过 Explicit VR Big Endian、未压缩、有符号 16 位。
- 未在 aarch64 上编译或运行。

## VOL2 布局 v4

与 Python 版 `vol2.py` 同步（`LAYOUT_VERSION=4`）：视图按 低区 → 结果区之后（0x1E000000 以下）→ 扩展区（0x20000000..0x30000000）依次放置，任何视图不得落入 0x1E000000..0x20000000 的 skip 区。334 层整卷的 `native_t` 约 84 MiB，只能放扩展区。主机读写 DDR 上限 `DDR_TOP` 同步为 0x30000000（与 RTL `HOST_DDR_TOP` 一致）；描述符地址范围仍受 0x20000000 约束。放不下的派生视图会告警并退回原朝向 gather。
