# `mesh_ray`（`lung_ray_mesh_axi`）寄存器与数据格式

ABI `0x00070000`，魔数 `0x4c524d32`。AXI-Lite 基址 `0xA0040000`。网格与 BVH 驻留在 PS 分配的连续 DDR 缓冲区，由核内 AXI4 主口读取；射线经 `mesh_ray_dma`（`0xA0060000`）输入，结果经 `mesh_result_dma`（`0xA0070000`）输出。`mesh_dma`（`0xA0050000`）保留旧的流式装载通路，当前驱动不用。驱动实现见 `src/ps/cas_frontend/pl_metrics.py`（`evaluate_mesh_rays`）。

构建参数（BD）：`CORE_COUNT=1`、`MAX_HITS=128`、`STACK_DEPTH=128`、`MAX_TRIANGLES=8192`、`FAST_DIVIDE=0`。

## AXI-Lite

| 偏移 | 读写 | 含义 |
|---:|:---:|---|
| `0x000` | W/R | 写：bit0 启动射线任务，bit1 Abort，bit2 装载 DDR 网格，bit8 中断使能。读：bit1 busy，bit2 done，bit3 有错误 |
| `0x004` | W/R | 三角形数量 |
| `0x008` | W/R | 射线数量 |
| `0x00c` | W/R | 软件任务编号 |
| `0x010` | R | 已完成射线数 |
| `0x014` | R | 原始命中总数 |
| `0x018` | R | 粘性错误：bit0 stream/TLAST/RLAST，bit1 KEEP，bit2 超时，bit3 DDR RRESP，bit4 算术范围，bit5 交点容量溢出，bit6 BVH 遍历栈溢出，bit7 Abort |
| `0x01c` | W/R | 写 bit0 清除 done |
| `0x020` | R | 任务周期数 |
| `0x024` | R | 已装载三角形数 |
| `0x028` | R | 魔数 `0x4c524d32` |
| `0x02c` | R | ABI `0x00070000` |
| `0x030` | W/R | 超时周期，0 关闭 |
| `0x034/038` | W/R | 网格物理地址低/高 32 位（16 字节对齐） |
| `0x03c` | W/R | 模式：bit0 DDR 网格，bit1 完整交点帧，bit2 体积积分，bit3 点距；驱动写 1/3/7/9。读回另含 loaded 与错误状态 |
| `0x040/044` | W/R | BVH 物理地址低/高 32 位（16 字节对齐） |
| `0x048` | W/R | BVH 节点数 |
| `0x04c` | R | BVH 节点字节数，48 |
| `0x050` | R | 能力位 `0x7f`：bit0 DDR 网格，bit1 BVH 元数据，bit2/3 BVH 遍历与完整交点帧，bit4 体积积分，bit5 点距，bit6 多实体并集 |
| `0x054` | R | 求交核数量，1 |
| `0x058` | W/R | 本次任务交点上限，≤ `MAX_HITS` |
| `0x05c` | R | 交点溢出的射线数 |
| `0x060` | R | `MAX_HITS`（128） |
| `0x064` | R | 结果帧字节数，`(4+MAX_HITS/4)*16` = 576 |
| `0x068` | R | `STACK_DEPTH`（128） |
| `0x06c/070` | R | 体积分数和（Q30）低/高 32 位 |
| `0x074` | R | 体积有效射线数 |
| `0x078` | R | 体积分数均值（Q30） |
| `0x07c` | R | 体积分数格式位数，30 |
| `0x080–0x088` | R | 批内最小平方距离（96 位无符号 Q32） |
| `0x08c` | R | 点距有效点数 |
| `0x098` | W/R | 实体数 `solid_count`，1–32 |
| `0x09c` | R | 各实体交点事件数 |
| `0x0a0` | R | 最大实体数，32 |
| `0x0a4` | R | 并集边界数 |

任务运行中写配置寄存器返回 SLVERR。地址未按 4 字节对齐、或访问未定义偏移，均返回 SLVERR。

## DDR 记录

三角形 48 字节：`v0(x,y,z) v1(x,y,z) v2(x,y,z)` 九个 signed Q16.16 词，第 10 词为实体编号（单实体时为 0），后两词填充。

BVH 节点 48 字节，12 个小端 32 位词：`min_x min_y min_z max_x max_y max_z left right first count type reserved`。前六词为向外取整的 signed Q16.16 AABB；`type=1` 为叶节点，`first/count` 指向按 BVH 重新排序后的三角形；根为 0，无效子节点为 `0xffffffff`。布局由 `cas_frontend/mesh_bvh.py` 生成。

## 射线与结果帧

射线 32 字节：`ray_id origin_x origin_y origin_z direction_x direction_y direction_z padding`（signed Q16.16）。

完整交点模式下每条射线输出 576 字节的结果帧：4 个 16 字节头部 beat，后接 32 个 beat 共 128 个交点参数 `t`（signed Q16.16，已排序并去重，未用位置为 0）。头部 16 个小端 32 位词：

| 词 | 内容 |
|---:|---|
| 0–3 | `ray_id`；错误位（低 8 位）与提示位（bit8–15）；原始命中数；去重后交点数 |
| 4–7 | 最近交点 `t_near`；最远交点 `t_far`；起点在内部标志；区间数 |
| 8–11 | 体积分数（Q30）；固定为 1；平行三角形数；射线长度（Q16，体积模式） |
| 12–15 | 体积有效标志；各实体事件数；并集边界数；`solid_count` |解码见 `cas_frontend/ray_bvh.py`，体积与距离字段见 `ray_mesh.py`、`mesh_distance.py`。

## 多实体并集语义

- 每个三角形按第 10 词归属实体。同一实体内相差 ≤ 1 LSB 的交点合并；不同实体的交点，与组内首个交点相差 ≤ 1 LSB 时一起处理。
- 闭合实体的初始内外状态等于其正向不同交点数的奇偶性；射线起点的并集状态是各实体状态的 OR。
- 只有活动实体数在 0 与非 0 之间变化时才输出并集边界，所以内部界面、重叠、嵌套、重合和重复几何都不会产生多余边界。
- 原始交点与并集边界各最多 128 个。容量溢出、实体编号非法或实体数非法时，整条射线无效，不返回截断结果。
- 表面积和底面连续性仍由 PS 端 Boolean 计算；严格 PL 模式下不会用 CPU 结果替代 PL 的射线或体积结果。
