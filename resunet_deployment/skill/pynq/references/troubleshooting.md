# PYNQ 排错速查

**排查顺序固定：身份 → 契约 → 传输 → 数值。** 跳层会把时间花在错误的地方。

## 1. 现象 → 根因

| 现象 | 先查 | 处置 |
|---|---|---|
| `ip_dict` 为空 / 找不到实例 | `.hwh` 是否与 `.bit` 同名同目录 | 重新拷贝成对文件；用 `hwh_inspect.py` 对比实例名 |
| `AttributeError: ... has no attribute 'dma'` | `ol.ip_dict.keys()` 里的真实实例名 | 改代码里的实例名，不改 BD |
| `register_map only available if the .hwh is provided` | 该核是否 `module_ref` 自定义 RTL | 用 `read/write` + 契约偏移 |
| VERSION/ABI 寄存器不对 | 板上是否是旧 bitstream、bit/hwh 是否错配 | 比对 SHA256，重新下载 |
| 写寄存器无反应 | 基地址/偏移是否来自 HWH；PL 时钟与复位是否释放 | 读一个只读常量寄存器确认总线通 |
| `Transfer size is N bytes, which exceeds ...` | DMA `C_SG_LENGTH_WIDTH` | 加宽到 ≤26 或分块 |
| `DMA does not support unaligned transfers` | `start` 偏移是否是数据位宽的倍数 | 对齐分块边界 |
| `DMA Internal Error (transfer length 0?)` | `nbytes` 是否为 0、数组是否为空 | 检查长度计算 |
| `DMA Decode Error` / `Slave Error` | 地址是否来自 `allocate`；HP 口地址段是否包含该地址 | 只用 `allocate` 缓冲 |
| `wait()` 永远不返回 | S2MM 是否先于 START 提交；RTL 是否给出 TLAST；输出字节数是否 ≥ 接收缓冲长度 | 改用带超时轮询，超时后走第 2 节恢复 |
| 结果偶发不一致、像旧数据 | 是否用轮询 `idle` 代替 `wait()` 却没 `invalidate()`；PL 主口是否走 HP 非一致性口 | 读前 `invalidate()`，写后 `flush()` |
| 首个/末个元素错、其余对 | TLAST 位置、打包 lane 顺序、复位后首拍 | 用小规模 known-vector 逐元素比对 |
| 比参考慢很多 | 计时是否包含 overlay 加载/allocate/Python 循环 | 分段计时，见 `dma-buffers.md` 第 5 节 |

## 2. DMA 卡死后的恢复

背压下调用 `channel.stop()` 可能卡住：`stop()` 写 Run/Stop=0 后会一直等通道停下，PL 不放行时不会返回。实测可靠的做法：

```python
def reset_hw(ol, dma_list, buffers):
    for dma in dma_list:
        for ch in (dma.sendchannel, dma.recvchannel):
            if ch is not None:
                ch._mmio.write(ch._offset, 0)   # 直接写 DMACR=0（MM2S 偏移 0x00，S2MM 偏移 0x30），不等待
    ol.download()                               # 重新下载作为 PL 复位屏障
    for b in buffers:
        del b                                   # PL 复位之后才释放 CMA
```

- `_mmio`/`_offset` 是私有属性，换 PYNQ 版本先确认仍存在。
- 恢复后先跑 known-vector，再跑真实负载。
- 保留第一次失败的日志与输入；重试使用新的运行目录。

## 3. 计时与结论的常见误判

- 一次 SSH 下的测试成功不代表桌面会话里的应用能用 PYNQ（环境变量、权限不同）。
- 改了 bitstream 之后，旧的性能数据全部作废；报告里性能数字必须带 bitstream 哈希。
- 「PL 比 CPU 慢」先查：数据规模是否太小（固定开销主导）、计时是否包含加载与分配、PL 频率是否被降。
