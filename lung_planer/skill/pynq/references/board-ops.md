# 板端操作

适用：网络已配置、能 SSH 登录的 PYNQ 板。

## 1. 板卡与镜像

| 板卡 | PYNQ 来源 | 备注 |
|---|---|---|
| PYNQ-Z1 / PYNQ-Z2 | 官方 SD 卡镜像（pynq.io） | Zynq-7000，PL 时钟寄存器为 `PCW_*` |
| KV260 / KR260 | Ubuntu + Kria-PYNQ 安装脚本 | 不用老的 PYNQ SD 镜像；PL 时钟为 `PSU__*` |
| ZCU104 / Ultra96 | 官方镜像 | — |

板上第一次操作先记录：

```bash
uname -a; cat /etc/os-release | head -3
python3 -c "import pynq, sys; print(pynq.__version__, sys.executable)"
ps aux | grep -i -E "python|jupyter" | grep -v grep     # 谁在占用 PL
df -h ~                                                  # 运行目录剩余空间
```

Kria-PYNQ 的 Python 环境通常需要先 `source /etc/profile.d/pynq_venv.sh`（以板上实际脚本为准）；`sudo` 运行时注意环境变量被清掉。

## 2. 传输与校验

```bash
# 工作站
sha256sum design.bit design.hwh run.py > manifest.sha256
scp design.bit design.hwh run.py manifest.sha256 <user>@<board>:~/runs/<run_id>/
# 板端
cd ~/runs/<run_id> && sha256sum -c manifest.sha256
```

- 每次运行一个新目录 `~/runs/<run_id>/`，不覆盖上一次的结果。
- 批量操作可用 `scripts/board_session.py`（只在工作站装 Paramiko，凭据走隐藏输入，不写进命令或 JSON）。
- 不把业务数据、密钥、无关大文件一起传。

## 3. 运行

1. 激活板上的 PYNQ 环境，确认版本与第 1 节记录一致。
2. 先跑 known-vector：`python3 pynq_runner.py --bit design.bit --known-vector`。
3. 通过后跑真实负载；同一次计时只测一个 bitstream、一个算子配置。
4. 长任务写状态文件：先写 `RUNNING`，结束时只写一个 `COMPLETE` 或 `FAILED`，附 run_id 与日志路径；工作站按有界间隔轮询状态文件，而不是固定 sleep。
5. 只停止本次启动的进程。

## 4. 取回与报告

取回 `run_record.json`、日志、输出文件，在工作站再校验一次哈希。最小报告字段：板卡、OS/内核、PYNQ 版本、bit/hwh 哈希、PL 频率、run_id、确切命令、分段计时、比对结论、未覆盖项。脱敏业务标识，不写凭据。

## 5. 需要显示器输出时

SSH 启动的进程不会出现在板子的物理屏上。要在物理桌面显示，必须从本地图形会话启动，或从该会话进程读取 `DISPLAY`/`XAUTHORITY` 显式传入；`DISPLAY=:0`/`:1` 是观察结果，不是固定值。GUI 帧率与 PL 计时是两件事，分开测、分开报。
