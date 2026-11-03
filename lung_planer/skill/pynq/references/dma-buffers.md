# AXI DMA 与缓冲区

适用：AXI DMA（`xilinx.com:ip:axi_dma:7.1`）简单模式（Direct Register），PS DDR ↔ AXI4-Stream。
失效：Scatter-Gather 模式不在本页范围；API 行为对照 PYNQ v2.7 / v3.0.1 / master 的 `pynq/lib/dma.py`、`pynq/buffer.py`，三者一致。

## 1. 分配

```python
import numpy as np
from pynq import allocate
src = allocate(shape=(n,), dtype=np.uint32)   # 物理连续、可 DMA
dst = allocate(shape=(m,), dtype=np.uint32)
src[:] = data                                  # 原地写，不要 src = data（会丢掉 PynqBuffer）
print(hex(src.physical_address))               # = device_address，填给自带 M_AXI 的核
```

- 用完 `del buf` 或 `with allocate(...) as buf:`；`.close()` 已废弃。
- **在 DMA 和 PL 都停下之后才释放。** 释放仍被 PL 访问的 CMA 内存会造成随机内存损坏。

## 2. 发送与接收（推荐顺序）

```python
dma = ol.axi_dma_0                      # 实例名来自 ip_dict
dma.recvchannel.transfer(dst)           # 1. 先挂接收
core.write(CTRL, 1)                     # 2. 启动核（如核需要显式 START）
dma.sendchannel.transfer(src)           # 3. 再发送
dma.sendchannel.wait()
dma.recvchannel.wait()
```

`transfer(array, start=0, nbytes=0)`：`nbytes=0` 表示从 `start` 到数组末尾。

## 3. 必须知道的五条事实（来自源码）

| 事实 | 后果 |
|---|---|
| 单次传输上限 = `2^C_SG_LENGTH_WIDTH − 1` 字节，默认宽度 14 → 16383 B | 超出直接 `ValueError`。改 IP 的 Buffer Length Register 宽度（最大 26），或主机侧分块；`hwh_inspect.py` 会列出每个 DMA 的上限 |
| 未启用 DRE 时，起始地址必须按数据位宽对齐（128 bit → 16 B） | 分块用 `start=` 偏移时，偏移必须是对齐倍数，否则 `RuntimeError` |
| 流端必须在最后一拍拉高 `TLAST` | S2MM 收不到 TLAST 永远不完成；**RTL 里 TLAST 的位置要与 `nbytes` 对应** |
| `sendchannel.transfer` 内部自动 `flush()`；`recvchannel.wait()` 内部自动 `invalidate()` | 用 `wait()` 时无需手动同步 |
| **改用轮询 `idle` 代替 `wait()` 时，不会自动 invalidate** | 必须手动 `dst.invalidate()`，否则读到旧缓存，表现为「偶发不一致」 |

`wait()` 本身没有超时，且只在错误位置位时抛异常：`DMA Internal Error (transfer length 0?)`、`DMA Slave Error (cannot access memory map interface)`、`DMA Decode Error (invalid address)`。

## 4. 带超时的等待

```python
import time
def wait_idle(ch, timeout_s):
    t_end = time.monotonic() + timeout_s
    while not ch.idle:
        if ch.error:
            raise RuntimeError("DMA error bit set")
        if time.monotonic() > t_end:
            raise TimeoutError("DMA not idle")
    # 轮询路径没有自动 invalidate，调用方负责
```

PL 核自带 M_AXI 直接访问 DDR（不经 AXI DMA）时：核读之前主机 `buf.flush()`，核写完之后主机 `buf.invalidate()`；通过 HP 口访问是非一致性的，通过 ACP/HPC 且开启一致性时可省略，但要在契约里写明用的哪个口。

## 5. 分段计时

| 段 | 起止 |
|---|---|
| prepare | 输入准备与打包（PS） |
| allocate | `allocate` 调用 |
| h2d | 写入 + flush（或 send transfer 到 send wait） |
| kernel | START 到 DONE/recv idle |
| d2h | invalidate + 拷出 |
| post | PS 后处理 |
| total | 墙钟 |

- 用 `time.perf_counter_ns()`；板端 RTC 可能不准，不用 `time.time()` 做区间。
- 软件墙钟里的 kernel 段包含 Python 调度开销；**只有 PL 内部计数器测得的才叫 PL 内核时间**。需要精确值就在 RTL 里加一个周期计数寄存器。
- 首次调用含缓存冷启动，至少跑 N 次取中位数，并报告 N。
- 性能数字必须同时写：bitstream 哈希、PL 频率、输入规模、N。

## 6. 契约清单（每个 DMA 通道）

- [ ] 实例名、方向（MM2S/S2MM）、流数据位宽
- [ ] 元素 dtype、字节序、打包方式（一拍几个元素、lane 0 在低位）
- [ ] 单次最大字节数及分块策略
- [ ] TLAST 产生规则（每帧/每块/整次）
- [ ] 输出长度如何确定（固定 / 由寄存器给出 / 由 TLAST 决定）
- [ ] 同步方式（`wait()` 自动 / 轮询 + 手动 invalidate）
