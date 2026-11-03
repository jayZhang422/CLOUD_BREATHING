"""Board operator RPC; V1 framing, little-endian tensor/control body."""
import socket
import struct
import time

from .protocol import build_frame, parse_frame, FrameError

WRITE, RUN, STATUS, READ, RELEASE, ABORT = range(0x20, 0x26)
OP_NAMES = {1: "PW", 2: "MaxPool", 3: "LineBuffer3", 4: "LineBuffer5",
            5: "Concat", 6: "ElementAdd", 7: "Shuffle16", 8: "DW3", 9: "DW5",
            10: "Upsample", 11: "FusedDW3DW5Add", 12: "FusedResidual", 13: "FusedUpsampleConcat"}
STATUS_NAMES = {1: "BUSY", 2: "INVALID", 3: "DDR_ERROR",
                5: "INPUT_NOT_READY", 6: "STALE"}
COEFF_BASE, COEFF_LIMIT = 0x00100000, 0x00159600
PARAM_DDR_BASE, PARAM_DDR_LIMIT = 0x08000000, 0x08200000
TUMOR_COEFF_BASE, TUMOR_COEFF_LIMIT = 0x00159600, 0x002BD240
PERF_BASE = 0x1FFF0000
PERF_CORE_NAMES = (
    "total", "load", "run", "inputs", "outputs", "reader_request_stall",
    "reader_memory_stall", "output_stall", "memory_reads", "memory_writes",
    "memory_stall", "memory_pending", "read_errors", "writer_stall", "flush",
    "input_wait",
)


def descriptor(op, run_id, *, width, height, groups=1, groups_b=1,
               cin=3, cout=16, shift=24, lower=-128, upper=127,
               base_a=0x10000000, base_b=0x04000000, output=0x01000000,
               mac=0x02000000, weights=None, params=None,
               slices=1, center=0, online=False, debug_mac=False,
               raw=False, int16=False, raw_p16=False):
    if not 0 <= cin <= 768 or not 0 <= cout <= 512:
        raise ValueError("Cin/Cout exceed FPGA limits (768/512)")
    if op == 1 and (cin == 0 or cout == 0):
        raise ValueError("PW requires nonzero Cin/Cout")
    if ((op in (1, 8, 9, 11) and weights is None) or
            (op in (1, 6, 11) and params is None) or
            (op == 11 and mac is None)):
        raise ValueError("supply this layer's coefficient addresses")
    if raw_p16 and (op != 1 or not raw or int16 or cout % 16):
        raise ValueError("raw_p16 requires PW raw INT32 and Cout divisible by 16")
    if op in (8, 9):
        if online or debug_mac or raw or int16 or raw_p16:
            raise ValueError("DW requires flags=0; output is always raw P16 INT32")
        if not (1 <= width <= 512 and 1 <= height <= 512 and 1 <= groups <= 32):
            raise ValueError("DW requires W/H=1..512 and groups=1..32")
        if weights % 64:
            raise ValueError("DW weights must be 64-byte aligned")
    if op in (10, 13):
        if online or debug_mac or raw or int16 or raw_p16:
            raise ValueError("Upsample requires flags=0; output is P16 INT8")
        if not (1 <= width <= 256 and 1 <= height <= 256 and 1 <= groups <= 32):
            raise ValueError("Upsample requires input W/H=1..256 and groups=1..32")
        size = 16 * width * height * groups
        if (base_a < 0 or base_a % 16 or base_a + size > 0x20000000 or
                output < 0 or output % 32 or output + 4 * size > 0x20000000):
            raise ValueError("Upsample requires aligned input/output ranges inside DDR")
        if base_a < output + 4 * size and output < base_a + size:
            raise ValueError("Upsample input/output ranges must not overlap")
        if op == 13:
            skip_size = 64 * width * height * groups_b
            total_size = 4 * size + skip_size
            if not 1 <= groups_b <= 32 or base_b < 0 or base_b % 16 or base_b + skip_size > 0x20000000:
                raise ValueError("Fused Upsample/Concat requires groups_b=1..32 and aligned skip inside DDR")
            if output + total_size > 0x20000000 or (base_a < output + total_size and output < base_a + size) or (base_b < output + total_size and output < base_b + skip_size):
                raise ValueError("Fused Upsample/Concat output must fit DDR and not overlap either input")
    if op == 11:
        if online or debug_mac or raw or int16 or raw_p16:
            raise ValueError("Fused DW3/DW5/Add requires flags=0; output is P16 INT8")
        if not (1 <= width <= 512 and 1 <= height <= 512 and 1 <= groups <= 32 and 0 <= shift <= 63):
            raise ValueError("Fused DW3/DW5/Add requires W/H=1..512, groups=1..32, shift=0..63")
        for address, size in ((weights, groups*144), (mac, groups*400), (params, groups*256)):
            if address % 64 or not (COEFF_BASE <= address and address+size <= COEFF_LIMIT or
                                   PARAM_DDR_BASE <= address and address+size <= PARAM_DDR_LIMIT or
                                   TUMOR_COEFF_BASE <= address and address+size <= TUMOR_COEFF_LIMIT):
                raise ValueError("Fused DW3/DW5/Add requires 64-byte aligned DW3/DW5/mix coefficients inside ROM or parameter DDR")
        size = 16 * width * height * groups
        if (base_a < 0 or base_a % 16 or base_a+size > 0x20000000 or
                output < 0 or output % 32 or output+size > 0x20000000):
            raise ValueError("Fused DW3/DW5/Add input/output must be aligned and inside DDR")
        if base_a < output+size and output < base_a+size:
            raise ValueError("Fused DW3/DW5/Add input/output ranges must not overlap")
    b = bytearray(64)
    flags = online | (debug_mac << 1) | (raw << 2) | (int16 << 3) | (raw_p16 << 4)
    struct.pack_into("<BBBBHHHBBB", b, 0, op, flags, cin & 255, cout & 255, width, height,
                     groups, shift, lower & 255, upper & 255)
    struct.pack_into("<H", b, 14, groups_b)
    struct.pack_into("<9I", b, 16, base_a, base_b, output, mac, weights or 0, params or 0,
                     slices, center, run_id)
    if cin > 255 or cout > 255:
        struct.pack_into("<HH", b, 52, cin, cout)
    return bytes(b)


class OpClient:
    def __init__(self, host="192.168.1.10", port=8080, timeout=1.0, retries=8,
                 bind="0.0.0.0"):
        self.peer = (socket.gethostbyname(host), port)
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.bind((bind, 0))  # FPGA replies to the request's source port.
        self.socket.settimeout(timeout)
        self.sequence = 0
        self.retries = retries

    def close(self):
        self.socket.close()

    def rpc(self, msg, run_id=0, body=b""):
        self.sequence = (self.sequence + 1) & 0xFFFFFFFF
        packet = build_frame(msg, run_id, self.sequence, body)
        for _ in range(self.retries):
            self.socket.sendto(packet, self.peer)
            deadline = time.monotonic() + self.socket.gettimeout()
            while time.monotonic() < deadline:
                try:
                    data, peer = self.socket.recvfrom(2048)
                except socket.timeout:
                    break
                if peer != self.peer:
                    continue
                try:
                    frame = parse_frame(data)
                except FrameError:
                    continue
                if (frame.msg_type, frame.transfer_id, frame.sequence) != (msg | 0x80, run_id, self.sequence):
                    continue
                if len(frame.body) < 16:
                    raise RuntimeError("truncated operator reply")
                status, state, op, fmt, identity, size, mac_size = struct.unpack_from("<BBBBIII", frame.body)
                if status == 1:
                    time.sleep(0.01)
                    break
                if status:
                    raise RuntimeError(f"RPC 0x{msg:02x}: {STATUS_NAMES.get(status, status)}, "
                                       f"state={state}, run_id=0x{identity:08x}")
                if msg in (RUN, READ, RELEASE, ABORT) and run_id != identity and not (msg == READ and run_id == 0):
                    raise RuntimeError("reply body run identity mismatch")
                return dict(state=state, op=op, format=fmt, run_id=identity,
                            bytes=size, mac_bytes=mac_size, data=frame.body[16:])
        raise TimeoutError(f"operator RPC 0x{msg:02x} timed out")

    def upload(self, address, data):
        if address % 32:
            raise ValueError("upload address must be 32-byte aligned")
        data = bytes(data)
        padded = data + bytes((-len(data)) % 32)
        if address < 0 or address + len(padded) > 0x20000000:
            raise ValueError("upload is outside DDR address range")
        if address < COEFF_LIMIT and address + len(padded) > COEFF_BASE:
            raise ValueError("coefficient space is read-only ROM; upload feature data or DDR parameters")
        for offset in range(0, len(padded), 1024):
            chunk = padded[offset:offset + 1024]
            self.rpc(WRITE, body=struct.pack("<IHH", address + offset, len(chunk), 0) + chunk)

    def run(self, desc):
        if len(desc) != 64:
            raise ValueError("operator descriptor must contain 64 bytes")
        run_id = struct.unpack_from("<I", desc, 48)[0]
        self.rpc(RUN, run_id, desc)
        return run_id

    def wait(self, run_id, timeout=120):
        deadline = time.monotonic() + timeout
        last_status = None
        while time.monotonic() < deadline:
            r = self.rpc(STATUS, run_id)
            last_status = r
            if r["run_id"] != run_id:
                raise RuntimeError("run identity changed")
            if r["state"] == 2:
                return r
            if r["state"] == 3:
                raise RuntimeError("operator run failed or was aborted")
            time.sleep(0.02)
        raise TimeoutError(f"operator run did not drain before deadline: "
                           f"run_id=0x{run_id:08x}, timeout={timeout}s, status={last_status}")

    def read(self, run_id, address, size, diagnostic=False):
        if address < 0 or address % 32 or size < 0 or address + ((size + 31) & ~31) > 0x20000000:
            raise ValueError("read must be 32-byte aligned and inside DDR address range")
        result = bytearray()
        for offset in range(0, (size + 31) & ~31, 1024):
            count = min(1024, ((size + 31) & ~31) - offset)
            r = self.rpc(READ, run_id, struct.pack("<IHH", address + offset, count, int(diagnostic)))
            if len(r["data"]) != count:
                raise RuntimeError("result packet length mismatch")
            result.extend(r["data"])
        return bytes(result[:size])

    def performance(self, run_id):
        """Read the completed run's hardware snapshot; wait stalls may overlap."""
        # Diagnostic reads are an idle-service alias and must use transfer ID 0.
        data = self.read(0, PERF_BASE + (run_id & 63) * 256, 256, diagnostic=True)
        magic, size, version, identity, op_format, hz, ddr_hz, flags = struct.unpack_from("<8I", data)
        if (magic, size, version, identity) != (0x4650504F, 256, 1, run_id):
            raise RuntimeError("missing or stale FPGA performance snapshot")
        if hz == 0 or flags:
            raise RuntimeError(f"invalid FPGA performance snapshot: Hz={hz}, flags={flags}")
        cycles = dict(zip(PERF_CORE_NAMES, struct.unpack_from("<16Q", data, 32)))
        return {"compute_hz": hz, "ddr_hz": ddr_hz, "op": op_format & 255,
                "format": (op_format >> 8) & 255, "cycles": cycles,
                "seconds": cycles["total"] / hz,
                "ddr_counters": list(struct.unpack_from("<8I", data, 160))}
