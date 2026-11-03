"""上板第一步：不跑推理，只确认链路与新比特流的地址窗口。

做三件事（都不改变板上运行状态）：
  1. STATUS 必须是空闲(state=0)，否则说明板上还留着上一次运行，先 Receive/释放再来；
  2. 向三个暂存地址各写 1 KiB 随机图样，再用诊断读读回逐字节比较：
       0x1C000000  结果区之后、skip 区之前（旧比特流也能写）
       0x20000000  扩展区起点（旧比特流会返回 INVALID，这一步能区分新旧比特流）
       0x2FFFFC00  扩展区末尾（1 KiB 的末地址恰为 0x30000000）
  3. 打印每步结果；任何一步失败立即退出码 1。
这些地址在后续 Send/Reasoning 里都会被重新上传覆盖，不会残留影响。

用法（PC_FPGA 目录）：
  .\\.venv\\Scripts\\python.exe -X utf8 -B tools\\link_check.py
"""
import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pc_fpga.ethernet.op_client import OpClient, STATUS  # noqa: E402

CHECKS = (
    (0x1C000000, "结果区之后(旧窗口内)", False),
    (0x20000000, "扩展区起点 0x20000000", True),
    (0x2FFFFC00, "扩展区末尾(止于 0x30000000)", True),
)


def run(client, size=1024, rng=os.urandom):
    state = client.rpc(STATUS)["state"]
    print(f"STATUS state={state}")
    if state != 0:
        print("失败：板上仍保留上一次运行，请先完成 Receive 或释放后再测")
        return 1
    for address, name, extension in CHECKS:
        pattern = rng(size)
        try:
            client.upload(address, pattern, block_size=1024)
        except (RuntimeError, ValueError) as error:
            hint = "（疑似仍是旧比特流：扩展区写入被拒绝）" if extension else ""
            print(f"失败：写 {name} @0x{address:08X} 被板端拒绝：{error}{hint}")
            return 1
        back = client.read(0, address, size, diagnostic=True)
        if back != pattern:
            bad = next(i for i, (a, b) in enumerate(zip(back, pattern)) if a != b)
            print(f"失败：读回 {name} @0x{address:08X} 第 {bad} 字节不一致")
            return 1
        print(f"通过：{name} @0x{address:08X} 写读 {size} B 一致")
    print("链路自检全部通过")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="192.168.1.10")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--bind", default="192.168.1.102")
    parser.add_argument("--timeout", type=float, default=1.0)
    args = parser.parse_args(argv)
    client = OpClient(args.host, args.port, args.timeout, bind=args.bind)
    try:
        return run(client)
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
