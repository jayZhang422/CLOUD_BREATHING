"""Entry point for the Ethernet send/recv verification (protocol V1).

Subcommands:
  upload     DICOM series -> signed int8 BIN -> reliable full-volume UDP upload
  make-bin   DICOM series -> output/volume_int8.bin ([N,512,512] signed int8)
  send       send a volume BIN to the FPGA address (or a local receiver)
  recv       run the FPGA-side simulator and receive a volume
  verify     byte-compare the sent BIN and the received BIN
  selfcheck  offline codec + in-process loopback self-test (synthetic data)
  ct         CT ZIP -> FPGA inference -> UINT16 BIN -> verified STL/smoothing
"""

import argparse
from dataclasses import asdict
import json
from pathlib import Path
import sys
from time import perf_counter, time

from src import receiver as receiver_mod
from src import sender as sender_mod
from src import udp_link, volume_bin
from src.protocol import (
    ImageBegin,
    InferTrigger,
    PACKETS_PER_SLICE,
    READY_OK,
    SLICE_BYTES,
)

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATA_DIR = PROJECT_ROOT / "data"
DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "output"

READY_NAMES = {
    READY_OK: "OK",
    0x01: "MISSING_PACKETS",
    0x02: "CRC_ERROR",
    0x03: "DDR_ERROR",
    0x04: "PARAM_MISMATCH",
}


def parse_addr(text: str | tuple[str, int]) -> tuple[str, int]:
    if isinstance(text, tuple):
        return text
    host, sep, port_text = text.rpartition(":")
    if not sep or not host or not port_text.isdigit():
        raise argparse.ArgumentTypeError(f"expected HOST:PORT, got {text!r}")
    port = int(port_text)
    if not 1 <= port <= 65535:
        raise argparse.ArgumentTypeError(f"port out of range: {port}")
    return host, port


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
                    encoding="utf-8")


# --- make-bin -----------------------------------------------------------------

def cmd_make_bin(args: argparse.Namespace) -> int:
    print(f"[1/3] Reading DICOM series from {args.data_dir}", flush=True)
    out_path: Path = args.out
    metadata = volume_bin.make_volume_bin(args.data_dir, out_path, args.series_uid)
    timings = metadata["stage_timings_s"]
    spacing = [round(value, 3) if value is not None else None
               for value in metadata["spacing_z_y_x_mm"]]
    print(f"      {metadata['slice_count']} slices, {metadata['rows']}x"
          f"{metadata['columns']}, HU range {metadata['hu_range_in_source'][0]:.0f}"
          f"..{metadata['hu_range_in_source'][1]:.0f}, spacing (z,y,x) "
          f"{spacing} mm, "
          f"{timings['read_dicom']:.2f}s", flush=True)
    print(f"[2/3] Quantized (HU[-1024,1000] -> int8, np.rint) and wrote "
          f"{out_path} ({metadata['total_bytes']:,} bytes), "
          f"{timings['quantize_write']:.2f}s", flush=True)
    print(f"[3/3] CRC32 0x{metadata['crc32']:08X}, sha256 {metadata['sha256'][:16]}..., "
          f"metadata -> {metadata['meta_file']}, {timings['verify']:.2f}s", flush=True)
    return 0


# --- upload -------------------------------------------------------------------

def cmd_upload(args: argparse.Namespace) -> int:
    print("[upload] DICOM -> [N,512,512] signed int8 BIN -> full-volume UDP transfer",
          flush=True)
    try:
        result = cmd_make_bin(args)
    except (OSError, ValueError) as exc:
        print(f"[upload] FAILED: {exc}", flush=True)
        return 1
    if result != 0:
        return result
    args.bin = args.out
    return cmd_send(args)


# --- send ---------------------------------------------------------------------

def cmd_send(args: argparse.Namespace) -> int:
    started = perf_counter()
    bin_path: Path = args.bin
    size = bin_path.stat().st_size
    if size == 0 or size % SLICE_BYTES != 0:
        print(f"[send] FAILED: {bin_path} size {size} is not a multiple of "
              f"{SLICE_BYTES}")
        return 1
    slices_total = size // SLICE_BYTES
    slice_count = args.limit_slices if args.limit_slices else slices_total
    if not 1 <= slice_count <= slices_total:
        print(f"[send] FAILED: --limit-slices {args.limit_slices} outside "
              f"1..{slices_total}")
        return 1
    total_bytes = slice_count * SLICE_BYTES
    expected_packets = slice_count * PACKETS_PER_SLICE
    print(f"[1/4] Inspecting {bin_path}: {slice_count}/{slices_total} slices, "
          f"{total_bytes:,} bytes", flush=True)
    whole_crc = volume_bin.crc32_file(bin_path, total_bytes)
    print(f"      whole-image CRC32 0x{whole_crc:08X}", flush=True)

    params = ImageBegin(
        total_slices=slice_count, total_bytes=total_bytes,
        expected_packets=expected_packets, whole_crc32=whole_crc,
        image_base_addr=args.image_base_addr, batch_slices=args.batch_slices,
    )
    try:
        link = udp_link.UdpPeer(parse_addr(args.bind))
    except OSError as exc:
        print(f"[send] FAILED: {exc}")
        return 1
    peer = parse_addr(args.peer)
    transfer_id = args.transfer_id if args.transfer_id is not None else int(time()) & 0xFFFFFFFF
    print(f"[2/4] UDP bound on {link.local_addr[0]}:{link.local_addr[1]}, peer "
          f"{peer[0]}:{peer[1]}, transfer 0x{transfer_id:08X}", flush=True)

    trigger = None
    if not args.skip_infer:
        center = args.infer_center if args.infer_center is not None else slice_count // 2
        trigger = InferTrigger(task_id=transfer_id & 0xFFFF,
                               center_slice_id=center,
                               patch_start_y=args.infer_y,
                               patch_start_x=args.infer_x)
    config = sender_mod.SenderConfig(
        begin_retries=args.begin_retries,
        status_timeout=args.status_timeout,
        max_batch_attempts=args.max_batch_attempts,
        ready_retries=args.ready_retries,
        pace_us=args.pace_us,
    )
    sender = sender_mod.VolumeSender(link, peer, bin_path, params, transfer_id,
                                     config)
    print(f"[3/4] Transferring ({(slice_count + args.batch_slices - 1) // args.batch_slices} "
          f"batches, {expected_packets} packets)", flush=True)
    try:
        stats = sender.run(trigger)
    except sender_mod.TransferError as exc:
        print(f"[send] FAILED: {exc}", flush=True)
        stats = dict(sender.stats)
        stats["error"] = str(exc)
        stats["params"] = asdict(params)
        write_json(args.report, stats)
        link.close()
        return 1
    except KeyboardInterrupt:
        print("[send] interrupted, aborting transfer", flush=True)
        sender._send_abort_quietly()
        link.close()
        return 130

    stats["params"] = asdict(params)
    write_json(args.report, stats)
    link.close()
    print(f"[4/4] Done: {stats['packets_unique']} packets "
          f"(+{stats['retransmitted']} retransmitted, "
          f"{stats['loss_events']} loss events), "
          f"{stats['throughput_mib_s']:.1f} MiB/s, "
          f"{perf_counter() - started:.2f}s, report -> {args.report}", flush=True)
    if args.skip_infer:
        print("TRANSFER PASS: IMAGE_READY received; transferred bytes and CRC32 verified",
              flush=True)
    return 0


# --- recv ---------------------------------------------------------------------

def cmd_recv(args: argparse.Namespace) -> int:
    try:
        link = udp_link.UdpPeer(parse_addr(args.bind))
    except OSError as exc:
        print(f"[recv] FAILED: {exc}")
        return 1
    print(f"[1/2] FPGA simulator starting on {args.bind}, output {args.out}, "
          f"drop_rate {args.drop_rate}, idle timeout {args.idle_timeout}s",
          flush=True)
    print("[2/2] Waiting for traffic (Ctrl+C stops)...", flush=True)
    config = receiver_mod.SimulatorConfig(drop_rate=args.drop_rate,
                                          drop_seed=args.drop_seed,
                                          idle_timeout=args.idle_timeout)
    simulator = receiver_mod.FpgaSimulator(link, args.out, config)
    report = simulator.run()
    write_json(args.report, report)
    link.close()

    counters = report["counters"]
    ready_name = READY_NAMES.get(report["ready_status"], str(report["ready_status"]))
    print(f"[recv] Summary: ready={ready_name}, "
          f"{report['received_packets']}/{report['params']['expected_packets'] if report['params'] else 0} "
          f"packets, {report['received_slices']} slices, "
          f"{counters['duplicates']} duplicates, "
          f"{counters['dropped_simulated']} simulated drops, "
          f"{report['duration_s']:.2f}s, report -> {args.report}", flush=True)
    if report["ready_status"] == READY_OK:
        print(f"[recv] Hint: python src/host/python/bin_udp/main.py verify "
              f"--sent {DEFAULT_OUTPUT_DIR / 'volume_int8.bin'} "
              f"--received {args.out}", flush=True)
        return 0
    return 1


# --- verify -------------------------------------------------------------------

def cmd_verify(args: argparse.Namespace) -> int:
    sent: Path = args.sent
    received: Path = args.received
    for path in (sent, received):
        if not path.exists():
            print(f"[verify] FAILED: {path} does not exist")
            return 1
    sent_size = sent.stat().st_size
    received_size = received.stat().st_size
    print(f"[1/2] Comparing {sent} ({sent_size:,} bytes) with {received} "
          f"({received_size:,} bytes)", flush=True)
    if sent_size != received_size:
        print("[verify] FAILED: file sizes differ")
        return 1
    identical = True
    with sent.open("rb") as left, received.open("rb") as right:
        while True:
            left_chunk = left.read(4 * 1024 * 1024)
            right_chunk = right.read(4 * 1024 * 1024)
            if left_chunk != right_chunk:
                identical = False
                break
            if not left_chunk:
                break
    sent_crc = volume_bin.crc32_file(sent)
    received_crc = volume_bin.crc32_file(received)
    print(f"[2/2] sent CRC32 0x{sent_crc:08X}, received CRC32 "
          f"0x{received_crc:08X}", flush=True)
    if identical and sent_crc == received_crc:
        print("VERIFY PASS: received file is byte-identical to the sent file")
        return 0
    print("VERIFY FAIL: content differs")
    return 1


# --- selfcheck ------------------------------------------------------------------

def cmd_selfcheck(args: argparse.Namespace) -> int:
    from src.selfcheck import run_selfcheck
    return 0 if run_selfcheck() else 1


# --- CLI ----------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="src/host/python/bin_udp/main.py", description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "local loopback test (two terminals):\n"
            "  python src/host/python/bin_udp/main.py recv --bind 127.0.0.1:8081 --drop-rate 0.0\n"
            "  python src/host/python/bin_udp/main.py send --bind 127.0.0.1:8080 --peer 127.0.0.1:8081\n"
            "\n"
            "against the real FPGA (defaults, NIC must own these addresses):\n"
            "  python src/host/python/bin_udp/main.py upload --data-dir data\n"
            "  python src/host/python/bin_udp/main.py send --skip-infer   # upload an existing BIN\n"
        ),
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    make_bin = subparsers.add_parser(
        "make-bin", help="DICOM series -> [N,512,512] signed int8 BIN")
    make_bin.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    make_bin.add_argument("--out", type=Path,
                          default=DEFAULT_OUTPUT_DIR / "volume_int8.bin")
    make_bin.add_argument("--series-uid",
                          help="required when the folder holds multiple CT series")
    make_bin.set_defaults(func=cmd_make_bin)

    # Both entry points use the same existing sender and wire protocol.
    transfer = argparse.ArgumentParser(add_help=False)
    transfer.add_argument("--bind", type=parse_addr, default=("192.168.1.102", 8080),
                          help="local PC/ARM addr (doc §2 default 192.168.1.102:8080)")
    transfer.add_argument("--peer", type=parse_addr, default=("192.168.1.10", 8080),
                          help="FPGA addr (doc §2 default 192.168.1.10:8080)")
    transfer.add_argument("--transfer-id", type=lambda s: int(s, 0), default=None)
    transfer.add_argument("--image-base-addr", type=lambda s: int(s, 0),
                          default=0x10000000, help="DDR base, must be 4KB aligned")
    transfer.add_argument("--batch-slices", type=int, default=1,
                          help="slices per batch (doc first version: 1)")
    transfer.add_argument("--begin-retries", type=int, default=5)
    transfer.add_argument("--status-timeout", type=float, default=0.5)
    transfer.add_argument("--max-batch-attempts", type=int, default=4)
    transfer.add_argument("--ready-retries", type=int, default=3)
    transfer.add_argument("--pace-us", type=int, default=0,
                          help="optional pacing: sleep every 32 packets (real FPGA)")
    transfer.add_argument("--report", type=Path,
                          default=DEFAULT_OUTPUT_DIR / "send_report.json")

    upload = subparsers.add_parser(
        "upload", parents=[transfer],
        help="DICOM -> BIN -> send all slices; stop at IMAGE_READY")
    upload.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    upload.add_argument("--out", type=Path,
                        default=DEFAULT_OUTPUT_DIR / "volume_int8.bin")
    upload.add_argument("--series-uid",
                        help="required when the folder holds multiple CT series")
    upload.set_defaults(func=cmd_upload, skip_infer=True, limit_slices=0)

    send = subparsers.add_parser("send", parents=[transfer],
                                help="send a volume BIN over UDP")
    send.add_argument("--bin", type=Path,
                      default=DEFAULT_OUTPUT_DIR / "volume_int8.bin")
    send.add_argument("--limit-slices", type=int, default=0,
                      help="send only the first N slices (0 = all); quick tests")
    infer_mode = send.add_mutually_exclusive_group()
    infer_mode.add_argument("--skip-infer", dest="skip_infer", action="store_true",
                            help="stop after IMAGE_READY (default for the current FPGA)")
    infer_mode.add_argument("--legacy-infer", dest="skip_infer", action="store_false",
                            help="send legacy INFER_TRIGGER for the software simulator; current FPGA returns NOT_READY")
    send.add_argument("--infer-center", type=int, default=None,
                      help="center slice for INFER_TRIGGER (default N//2)")
    send.add_argument("--infer-y", type=int, default=208)
    send.add_argument("--infer-x", type=int, default=208)
    send.set_defaults(func=cmd_send, skip_infer=True)

    recv = subparsers.add_parser("recv", help="run the FPGA-side simulator")
    recv.add_argument("--bind", type=parse_addr, default=("192.168.1.10", 8080),
                      help="FPGA addr (doc §2 default 192.168.1.10:8080)")
    recv.add_argument("--out", type=Path,
                      default=DEFAULT_OUTPUT_DIR / "recv_volume_int8.bin")
    recv.add_argument("--drop-rate", type=float, default=0.0,
                      help="simulated RX loss on IMAGE_DATA (0..1), e.g. 0.05")
    recv.add_argument("--drop-seed", type=int, default=1)
    recv.add_argument("--idle-timeout", type=float, default=10.0,
                      help="stop N seconds after the last traffic")
    recv.add_argument("--report", type=Path,
                      default=DEFAULT_OUTPUT_DIR / "recv_report.json")
    recv.set_defaults(func=cmd_recv)

    verify = subparsers.add_parser("verify", help="compare sent and received BINs")
    verify.add_argument("--sent", type=Path,
                        default=DEFAULT_OUTPUT_DIR / "volume_int8.bin")
    verify.add_argument("--received", type=Path,
                        default=DEFAULT_OUTPUT_DIR / "recv_volume_int8.bin")
    verify.set_defaults(func=cmd_verify)

    selfcheck = subparsers.add_parser(
        "selfcheck", help="offline codec + loopback self-test (synthetic data)")
    selfcheck.set_defaults(func=cmd_selfcheck)

    subparsers.add_parser("ct", help="CT ZIP -> FPGA -> UINT16 -> STL; use ct --help")

    return parser


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] == "ct":
        from src.ct_pipeline import main as ct_main
        try:
            sys.exit(ct_main(sys.argv[2:]))
        except (OSError, ValueError, RuntimeError) as exc:
            print(f"[CT FAILED] {exc}", flush=True)
            sys.exit(1)
    args = build_parser().parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
