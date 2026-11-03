# Overlay 加载与 MMIO 控制

适用：PL 核通过 AXI-Lite 暴露控制寄存器，Python 端配置、启动、查询。
失效：API 以板上已安装的 `pynq` 源码为准（`python3 -c "import pynq; print(pynq.__version__, pynq.__file__)"`）。下文已对照 PYNQ v3.0.1 与 master 源码。

## 1. 加载

```python
from pynq import Overlay
ol = Overlay("design.bit")               # 默认 download=True，按同名 .hwh 解析并下载
ol = Overlay("design.bit", download=False)  # 只解析 HWH，不动 PL（适合先核对）
ol.download()                            # 显式下载；也用作 PL 侧复位屏障
print(ol.ip_dict.keys())                 # 实例名，来自 HWH
```

- `.bit` 与 `.hwh` 同目录、同主文件名，否则 `ip_dict` 为空或报找不到 HWH。
- `ignore_version=True` 只影响「HWH 里的 IP 版本与已注册驱动版本不一致时是否仍绑定该驱动」，不能用来掩盖 bit/hwh 不配对。
- 其他进程（Jupyter 内核、后台服务）正在使用 PL 时不要下载新 bitstream。先查 `ps aux | grep -i python`。

## 2. 选控制方式

| 条件 | 用法 |
|---|---|
| HWH 带寄存器描述（AMD IP、HLS 核） | `ol.<ip>.register_map.<REG>.<FIELD> = v` |
| 自定义 RTL（`module_ref`，HWH 无 `<REGISTER>`） | `ol.<ip>.write(offset, value)` / `ol.<ip>.read(offset)`，偏移来自契约 |
| 只知道物理地址 | `MMIO(base, range)`，base/range 来自 HWH 地址映射 |

`hwh_inspect.py` 输出的 `register_map` 列直接告诉你走哪条：`NO` 的实例访问 `register_map` 会抛 `AttributeError("register_map only available if the .hwh is provided")`。

MMIO 每次读写是一次 32 位事务，没有突发，只适合控制面，大数据走 DMA。

## 3. 自定义 RTL 核的寄存器契约

HWH 不描述寄存器时，契约就是唯一事实来源。最少包含：

| 偏移 | 名称 | 访问 | 语义 |
|---|---|---|---|
| 0x00 | CTRL | W | bit0 START（写 1 产生单拍脉冲）；bit1 SOFT_RESET |
| 0x04 | STATUS | R | bit0 BUSY；bit1 DONE（读清或写清，写明）；bit2 ERROR |
| 0x08 | VERSION | R | 常量，例如 `0x00010000`；主机启动时比对 |
| 0x0C~ | 参数 | R/W | 长度、阈值、地址等，写明位宽与单位 |

规则：

- **必须有只读 VERSION/ABI 寄存器。** 加载后第一件事读它；不等于契约值就停（说明板上是旧 bitstream 或 bit/hwh 错配）。这条在实际项目里抓到过多次「板上加载的不是刚编译的版本」。
- 契约用 JSON 存（`regs.json`），`hwh_inspect.py --regs regs.json --emit-stub stub.py` 生成常量文件，主机代码只引用生成的常量。
- 写 DONE 的清除方式（读清 / 写 1 清 / START 清），否则连续两次调用会读到上一次的 DONE。

## 4. PL 时钟

HWH 里记录了 PS 给 PL 的时钟请求（`PSU__CRL_APB__PLn_REF_CTRL__FREQMHZ` 或 Zynq-7000 的 `PCW_*FPGAn_PERIPHERAL_FREQMHZ`）。PYNQ 下载前会按 HWH 设置时钟。

如果时序只在更低频率签核（例如 BD 里改过时钟但 HWH 请求值不同），加载后显式设置并回读：

```python
from pynq import Clocks
Clocks.fclk0_mhz = 100.0
assert abs(Clocks.fclk0_mhz - 100.0) < 1.0
```

把实际频率写进运行记录；性能数字必须注明频率。

## 5. 自定义驱动（可选）

需要把调用封装成方法时，用 `DefaultIP` 子类按 VLNV 自动绑定：

```python
from pynq import DefaultIP

class MyCore(DefaultIP):
    bindto = ["xilinx.com:module_ref:my_core:1.0"]   # 取 hwh_inspect 输出的 VLNV
    def __init__(self, description):
        super().__init__(description=description)
    def start(self):
        self.write(0x00, 1)
```

驱动类必须在 `Overlay(...)` 之前定义（import），否则不会绑定。

## 6. 加载阶段检查清单

- [ ] bit/hwh SHA256 与构建记录一致
- [ ] `ip_dict` 包含契约里的全部实例名
- [ ] VERSION/ABI 寄存器 = 契约值
- [ ] PL 时钟回读 = 时序签核频率
- [ ] 无其他进程占用 PL
