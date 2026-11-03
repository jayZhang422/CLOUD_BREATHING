#!/usr/bin/env python3
"""
sim_sender.py - 与 Verilator 桥接仿真对接的最小 Python 发送端

用途:
  在 WSL 内直接跑通 "Python 发 -> FPGA RTL 收/回 -> Python 收" 的完整闭环,
  不依赖真实板卡, 也不需要装 pydicom (真实工程的 main.py 只在 make-bin 阶段用)。

协议实现与真实工程 prj/src/protocol.py 完全一致:
  - 大端字段
  - CRC32 = zlib.crc32(帧[2 : 16+body_len])   <-- 独立于 C++ 版的实现, 交叉校验用
  - 位图约定: 包号 i -> 第 i/8 字节的第 (7 - i%8) 位

用法:
  # 终端 1 (WSL):   ./obj_dir/Veth_top --bind-ip 127.0.0.1 --bind-port 8080
  # 终端 2 (WSL):   python3 sim_sender.py --limit-slices 1
"""

import argparse
import socket
import struct
import sys
import time
import zlib

MAGIC = 0x55AA
TAIL = 0xAA55
VERSION = 0x01
HEADER_LEN = 16

MSG_IMAGE_DATA = 0x01
MSG_INFER_TRIGGER = 0x02
MSG_IMAGE_BEGIN = 0x03
MSG_IMAGE_END = 0x04
MSG_BATCH_END = 0x05
MSG_ACK = 0x81
MSG_INFER_DONE = 0x82
MSG_BATCH_STATUS = 0x83
MSG_IMAGE_READY = 0x84

WIDTH = 512
HEIGHT = 512
SLICE_BYTES = WIDTH * HEIGHT          # 262144
PACKET_PIXEL_BYTES = 1024
PACKETS_PER_SLICE = SLICE_BYTES // PACKET_PIXEL_BYTES   # 256
DEPTH = 33
CENTER_INDEX = 16
PATCH_SIZE = 96

ACK_ACCEPTED = 0x00
BATCH_COMPLETE = 0x00
BATCH_MISSING = 0x01
READY_OK = 0x00

_HDR = struct.Struct(">HBBIHHI")
_TRL = struct.Struct(">IH")


def build_frame(msg_type, transfer_id, sequence, body):
    header = _HDR.pack(MAGIC, VERSION, msg_type, transfer_id,
                       HEADER_LEN, len(body), sequence)
    crc = zlib.crc32(header[2:] + body) & 0xFFFFFFFF
    return header + body + _TRL.pack(crc, TAIL)


def parse_frame(data):
    if len(data) < HEADER_LEN + _TRL.size:
        raise ValueError(f"frame too short: {len(data)}")
    magic, version, msg_type, transfer_id, hlen, blen, seq = _HDR.unpack_from(data, 0)
    if magic != MAGIC:
        raise ValueError(f"bad magic 0x{magic:04X}")
    if version != VERSION:
        raise ValueError(f"bad version 0x{version:02X}")
    if hlen != HEADER_LEN:
        raise ValueError(f"bad header_len {hlen}")
    total = HEADER_LEN + blen + _TRL.size
    if len(data) < total:
        raise ValueError(f"truncated: {len(data)} < {total}")
    body = bytes(data[HEADER_LEN:HEADER_LEN + blen])
    crc_stored, tail = _TRL.unpack_from(data, HEADER_LEN + blen)
    if tail != TAIL:
        raise ValueError(f"bad tail 0x{tail:04X}")
    crc_calc = zlib.crc32(data[2:HEADER_LEN + blen]) & 0xFFFFFFFF
    if crc_stored != crc_calc:
        raise ValueError(f"CRC mismatch: stored 0x{crc_stored:08X} != calc 0x{crc_calc:08X}")
    return msg_type, transfer_id, seq, body


def image_begin_body(total_slices, total_bytes, expected_packets, whole_crc32,
                     base_addr=0x10000000, batch_slices=1):
    return struct.pack(
        ">IHHBBBBIIIQQIIIIiiBBBBHHHH",
        total_slices, WIDTH, HEIGHT, 1, 0x01, 0x01, 0x01,
        PACKET_PIXEL_BYTES, PACKETS_PER_SLICE, SLICE_BYTES,
        total_bytes, base_addr, batch_slices, expected_packets,
        whole_crc32, 0x00000001, -1024, 1000,
        0x01, 0x01, 0x01, 0, DEPTH, CENTER_INDEX, PATCH_SIZE, 0,
    )


def image_data_body(slice_id, packet_idx, pixels):
    return struct.pack(">HHHH", slice_id, packet_idx, PACKET_PIXEL_BYTES, 0) + pixels


def batch_end_body(batch_id, first_slice, slice_count, expected, crc32):
    return struct.pack(">HHHHII", batch_id, first_slice, slice_count, 0, expected, crc32)


def image_end_body(expected_packets, expected_bytes, whole_crc32):
    return struct.pack(">IQII", expected_packets, expected_bytes, whole_crc32, 0)


def infer_trigger_body(task_id, center, py=0, px=0):
    return struct.pack(">IIHHHHHHI", task_id, center, py, px,
                       DEPTH, CENTER_INDEX, PATCH_SIZE, 1, 0)


def bitmap_to_missing(bitmap, packet_count):
    out = []
    for i in range(packet_count):
        if (bitmap[i // 8] >> (7 - i % 8)) & 1:
            out.append(i)
    return out


class Link:
    def __init__(self, bind, peer):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 8 * 1024 * 1024)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 * 1024 * 1024)
        self.sock.bind(bind)
        self.peer = peer
        self.resets = 0

    def send(self, data):
        try:
            self.sock.sendto(data, self.peer)
        except ConnectionResetError:
            self.resets += 1

    def await_frame(self, pred, timeout):
        deadline = time.monotonic() + timeout
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                return None
            self.sock.settimeout(left)
            try:
                data, _ = self.sock.recvfrom(65535)
            except (socket.timeout, ConnectionResetError, OSError):
                continue
            try:
                msg_type, tid, seq, body = parse_frame(data)
            except ValueError as exc:
                print(f"  [rx] 丢弃非法帧: {exc}", flush=True)
                continue
            if pred(msg_type, tid, seq, body):
                return msg_type, tid, seq, body


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bind", default="127.0.0.1:8080")
    ap.add_argument("--peer", default="127.0.0.1:8080")
    ap.add_argument("--limit-slices", type=int, default=1)
    ap.add_argument("--drop-mod", type=int, default=0,
                    help="调试: 每 N 个包跳发 1 个 (i%%N==7), 用于验证缺包重传")
    ap.add_argument("--skip-infer", action="store_true")
    args = ap.parse_args()

    bind = (args.bind.rsplit(":", 1)[0], int(args.bind.rsplit(":", 1)[1]))
    peer = (args.peer.rsplit(":", 1)[0], int(args.peer.rsplit(":", 1)[1]))

    total_slices = args.limit_slices
    total_bytes = total_slices * SLICE_BYTES
    expected_packets = total_slices * PACKETS_PER_SLICE
    transfer_id = int(time.time()) & 0xFFFFFFFF

    # 用确定性的伪数据当整个 volume, 计算整卷 CRC
    volume = bytes(((i * 31 + (i >> 11) * 7) & 0xFF) for i in range(total_bytes))
    whole_crc = zlib.crc32(volume) & 0xFFFFFFFF

    print(f"[1/4] 生成体数据: {total_slices} 层, {total_bytes:,} 字节, "
          f"whole_crc32=0x{whole_crc:08X}", flush=True)
    link = Link(bind, peer)
    print(f"[2/4] UDP 绑定 {bind[0]}:{bind[1]}, 对端 {peer[0]}:{peer[1]}, "
          f"transfer 0x{transfer_id:08X}", flush=True)

    seq = 0

    # ---------------- IMAGE_BEGIN ----------------
    body = image_begin_body(total_slices, total_bytes, expected_packets, whole_crc)
    frame = build_frame(MSG_IMAGE_BEGIN, transfer_id, seq, body)
    seq += 1
    ack = None
    for attempt in range(1, 6):
        link.send(frame)
        ack = link.await_frame(
            lambda mt, tid, sq, bd: mt == MSG_ACK and tid == transfer_id
            and len(bd) >= 5 and bd[0] == MSG_IMAGE_BEGIN and _acked_seq(bd) == 0,
            1.0)
        if ack:
            break
        print(f"  IMAGE_BEGIN ACK 超时, 重试 {attempt}/5", flush=True)
    if not ack:
        print("[send] FAILED: 未收到 IMAGE_BEGIN 的 ACK")
        return 1
    _, _, _, ack_body = ack
    status = ack_body[1]
    if status != ACK_ACCEPTED:
        print(f"[send] FAILED: IMAGE_BEGIN 被拒绝, Status=0x{status:02X}")
        return 1
    print(f"[3/4] ACK 收到: Status=ACCEPTED(0x00), Acked_Sequence=0", flush=True)

    # ---------------- IMAGE_DATA + BATCH_END ----------------
    retransmitted = 0
    for batch in range(total_slices):
        slice_id = batch
        pending = {}
        dropped = set()
        for pkt in range(PACKETS_PER_SLICE):
            if args.drop_mod and (pkt % args.drop_mod) == 7 and batch == 0:
                dropped.add(pkt)
                continue
            px = volume[slice_id * SLICE_BYTES + pkt * PACKET_PIXEL_BYTES:
                        slice_id * SLICE_BYTES + (pkt + 1) * PACKET_PIXEL_BYTES]
            fr = build_frame(MSG_IMAGE_DATA, transfer_id, seq,
                             image_data_body(slice_id, pkt, px))
            pending[pkt] = fr
            seq += 1
            link.send(fr)
            time.sleep(0.0001)  # 100 微秒延迟，防止 UDP 缓冲区溢出
        # BATCH_END
        be = build_frame(MSG_BATCH_END, transfer_id, seq,
                         batch_end_body(batch, slice_id, 1, PACKETS_PER_SLICE, 0))
        seq += 1
        link.send(be)

        st = link.await_frame(
            lambda mt, tid, sq, bd: mt == MSG_BATCH_STATUS and tid == transfer_id
            and len(bd) >= 16 and struct.unpack_from(">H", bd, 0)[0] == batch,
            2.0)
        if not st:
            print(f"[send] FAILED: 批次 {batch} 无 BATCH_STATUS")
            return 1
        bd = st[3]
        b_status, exp, recv, bm_bytes = bd[2], struct.unpack_from(">I", bd, 4)[0], \
            struct.unpack_from(">I", bd, 8)[0], struct.unpack_from(">H", bd, 12)[0]
        bitmap = bd[16:16 + bm_bytes]
        missing = bitmap_to_missing(bitmap, PACKETS_PER_SLICE)

        expected_missing = sorted(dropped) if batch == 0 else []
        ok = (missing == expected_missing)
        print(f"  批次 {batch}: Status=0x{b_status:02X} Expected={exp} "
              f"Received={recv} Bitmap_Bytes={bm_bytes} 缺包={len(missing)}", flush=True)
        if not ok:
            print(f"    [FAIL] 缺包位图不符: FPGA={missing[:10]}... "
                  f"本地丢包={expected_missing[:10]}...")
            return 1
        print(f"    [ OK ] 缺包位图与本地丢包一致", flush=True)

        # 重传缺失的包
        if missing:
            for pkt in missing:
                px = volume[slice_id * SLICE_BYTES + pkt * PACKET_PIXEL_BYTES:
                            slice_id * SLICE_BYTES + (pkt + 1) * PACKET_PIXEL_BYTES]
                fr = build_frame(MSG_IMAGE_DATA, transfer_id, seq,
                                 image_data_body(slice_id, pkt, px))
                seq += 1
                retransmitted += 1
                link.send(fr)
                time.sleep(0.0001)  # 重传时也加延迟
            link.send(build_frame(MSG_BATCH_END, transfer_id, seq,
                                  batch_end_body(batch, slice_id, 1,
                                                 PACKETS_PER_SLICE, 0)))
            seq += 1
            st2 = link.await_frame(
                lambda mt, tid, sq, bd: mt == MSG_BATCH_STATUS and tid == transfer_id
                and len(bd) >= 16 and struct.unpack_from(">H", bd, 0)[0] == batch,
                2.0)
            if not st2:
                print(f"[send] FAILED: 重传后批次 {batch} 无 BATCH_STATUS")
                return 1
            bd2 = st2[3]
            miss2 = bitmap_to_missing(bd2[16:16 + struct.unpack_from(">H", bd2, 12)[0]],
                                      PACKETS_PER_SLICE)
            print(f"    重传 {retransmitted} 包后: Status=0x{bd2[2]:02X}, "
                  f"仍缺 {len(miss2)} 包", flush=True)
            if miss2:
                print(f"    [FAIL] 重传后仍有缺包")
                return 1
            print(f"    [ OK ] 重传后被判定为完整 (Status=0x00)", flush=True)

    # ---------------- IMAGE_END ----------------
    ie = build_frame(MSG_IMAGE_END, transfer_id, seq,
                     image_end_body(expected_packets, total_bytes, whole_crc))
    seq += 1
    link.send(ie)
    ready = None
    for attempt in range(1, 6):
        ready = link.await_frame(
            lambda mt, tid, sq, bd: mt == MSG_IMAGE_READY and tid == transfer_id,
            1.0)
        if ready:
            break
        link.send(ie)
    if not ready:
        print("[send] FAILED: 无 IMAGE_READY")
        return 1
    rb = ready[3]
    r_status = rb[0]
    r_slices = struct.unpack_from(">I", rb, 4)[0]
    r_pkts = struct.unpack_from(">I", rb, 8)[0]
    r_bytes = struct.unpack_from(">Q", rb, 12)[0]
    print(f"[4/4] IMAGE_READY: Status=0x{r_status:02X} Slices={r_slices} "
          f"Packets={r_pkts} Bytes={r_bytes}", flush=True)
    if r_status != READY_OK:
        print(f"[send] FAILED: IMAGE_READY 状态非 0")
        return 1
    if r_slices != total_slices or r_pkts != expected_packets or r_bytes != total_bytes:
        print("[send] FAILED: IMAGE_READY 统计与期望不符")
        return 1
    print("    [ OK ] IMAGE_READY 统计全部正确", flush=True)

    # ---------------- INFER_TRIGGER ----------------
    if not args.skip_infer:
        it = build_frame(MSG_INFER_TRIGGER, transfer_id, seq,
                         infer_trigger_body(transfer_id & 0xFFFF, total_slices // 2))
        seq += 1
        link.send(it)
        done = link.await_frame(
            lambda mt, tid, sq, bd: mt == MSG_INFER_DONE and tid == transfer_id
            and struct.unpack_from(">I", bd, 0)[0] == (transfer_id & 0xFFFF),
            2.0)
        if not done:
            print("[send] FAILED: 无 INFER_DONE")
            return 1
        db = done[3]
        result = struct.unpack_from(">I", db, 12)[0]
        print(f"    INFER_DONE: Status=0x{db[8]:02X} Result=0x{result:08X}", flush=True)
        if db[8] != 0x00 or result != 0xDEADBEEF:
            print("[send] FAILED: INFER_DONE 内容不符")
            return 1
        print("    [ OK ] INFER_DONE 正确 (0xDEADBEEF)", flush=True)

    print(f"\n===== 全部通过 ===== 唯一包 {expected_packets}, 重传 {retransmitted} 包")
    return 0


def _acked_seq(body):
    return struct.unpack_from(">I", body, 4)[0]


if __name__ == "__main__":
    sys.exit(main())
