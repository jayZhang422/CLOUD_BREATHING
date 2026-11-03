"""Frozen mkdc graphs on the existing FPGA operator RPC (no host convolution)."""

import csv
import hashlib
import json
from pathlib import Path
import secrets
import struct
from time import perf_counter, monotonic

import numpy as np

from .io.prediction_io import file_sha256
from .op_client import descriptor, RELEASE, STATUS, COEFF_BASE, PARAM_DDR_BASE
from .protocol import (ImageBegin, build_frame, parse_frame, FrameError,
                       MSG_IMAGE_BEGIN, MSG_TRANSFER_ABORT, MSG_ACK, parse_ack_body)

ROOT = Path(__file__).resolve().parents[5]
QUANT_ROOT = ROOT / "src/params/int8"
SOURCE = ROOT / "src/params"
ASSETS = Path(__file__).resolve().parents[1] / "assets"
TUMOR_FIRST, TUMOR_END = 0x00159600, 0x002BD240
ARENA_BASE, DDR_END = 0x09000000, 0x20000000
TASKS = (("lobe", 5, 0, "nifti-ras", 1.5), ("airway", 1, 5, "transpose", 0),
         ("vessel", 2, 6, "native", 0), ("tumor", 1, 8, "transpose", 0))


def export_path(task, quant_root=QUANT_ROOT):
    return Path(quant_root) / task


def read_coe(path):
    vector = Path(path).read_text(encoding="ascii").split("memory_initialization_vector=", 1)[1]
    return b"".join(int(word.strip(), 16).to_bytes(8, "little")
                    for word in vector.strip().rstrip(";").split(","))


def coefficient_image():
    image = read_coe(ASSETS / "quantized_params_rom_full.coe")
    rom = read_coe(SOURCE / "quantized_params_rom.coe")
    if image[:len(rom)] != rom or len(rom) != TUMOR_FIRST - COEFF_BASE:
        raise ValueError("Full parameter image differs from the project's small-model ROM")
    return image


def pack_input(sample):
    if sample.dtype != np.int8 or sample.ndim != 3 or sample.shape[0] != 3:
        raise ValueError("Expected signed INT8 [3,H,W]")
    # Only Cin=3 lanes are consumed; unused lanes never participate in MAC.
    padded = np.zeros((16, *sample.shape[1:]), np.int8)
    padded[:3] = sample
    return padded.transpose(1, 2, 0).tobytes()


def decode_logits(data, channels, side=512):
    groups = (channels + 7) // 8
    if len(data) != groups * side * side * 16:
        raise ValueError("FPGA INT16 head BIN length mismatch")
    return np.frombuffer(data, "<i2").reshape(groups, side, side, 8).transpose(0, 3, 1, 2).reshape(-1, side, side)[:channels]


def classify(logits):
    # NumPy argmax chooses the first channel on ties, including zero ties.
    return np.where(logits.max(axis=0) >= 0, logits.argmax(axis=0) + 1, 0).astype(np.uint8)


def caps(config):
    bits = config["bits"]
    upper = (1 << (bits - 1)) - 1
    return (0, min(upper, round(6 / config["output_scale"]))) if config["relu6"] else (-(1 << (bits - 1)), upper)


class NetworkPlan:
    def __init__(self, task, image, side=512, quant_root=QUANT_ROOT, fuse_dw_add=True, fuse_up_concat=True):
        if task not in {t[0] for t in TASKS} or side < 8 or side > 512 or side % 8:
            raise ValueError("Unsupported model or plane size")
        self.task, self.side, self.fuse_dw_add = task, side, fuse_dw_add
        self.fuse_up_concat = fuse_dw_add and fuse_up_concat
        self.export = export_path(task, quant_root)
        hashes = json.loads((self.export / "sha256.json").read_text(encoding="utf-8"))
        for name, expected in hashes.items():
            if file_sha256(self.export / name) != expected:
                raise ValueError(f"Frozen SHA256 mismatch: {task}/{name}")
        self.export_sha256 = file_sha256(self.export / "sha256.json")
        self.contract = json.loads((self.export / "contract.json").read_text(encoding="utf-8"))
        self.contract_sha256 = file_sha256(self.export / "contract.json")
        self.channels = self.contract["convolutions"]["head"]["shape"][0]
        with (SOURCE / "quantized_params_rom_address_map.tsv").open(encoding="utf-8") as stream:
            self.rows = {r["file"]: r for r in csv.DictReader(stream, delimiter="\t") if r["model"] == task}
        self.validate_coefficients(image)
        self.parameters = image[TUMOR_FIRST - COEFF_BASE:TUMOR_END - COEFF_BASE] if task == "tumor" else b""
        self.stages = []
        self.tensors = {"input": dict(shape=(3, side, side), bytes=16*side*side, produced=-1, last=-1)}
        self.build_graph()
        self.allocate()

    def address(self, name):
        address = int(self.rows[name]["request_byte_addr"], 16)
        return PARAM_DDR_BASE + address - TUMOR_FIRST if self.task == "tumor" else address

    def validate_coefficients(self, image):
        """Check actual PE4/SIMD16 ROM/DDR bytes against the frozen exports."""
        for name, config in self.contract["convolutions"].items():
            weights = np.fromfile(self.export / config["file"], np.int8).reshape(config["shape"])
            if weights.shape[2:] == (1, 1):
                co, ci = weights.shape[:2]
                padded = np.zeros(((co+3)//4*4, (ci+15)//16*16), np.int8)
                padded[:co, :ci] = weights[:, :, 0, 0]
                expected = padded.reshape((co+3)//4, 4, (ci+15)//16, 16).transpose(0, 2, 1, 3).tobytes()
            else:
                expected = weights.tobytes()
            self.check_image(image, config["file"], expected)
        for name, config in self.contract["merges"].items():
            multipliers = config["multipliers"]
            bias = np.fromfile(self.export / config["bias_file"], "<i8")
            if ".concat_" in name:
                if len(multipliers) != 1 or np.any(np.asarray(multipliers[0]) != 1 << config["shift"]) or np.any(bias):
                    raise ValueError(f"{self.task}/{name}: Concat needs rescaling unsupported by current RTL")
                continue
            lower, upper = caps(config)
            if len(multipliers) == 1:
                expected = b"".join(struct.pack("<iqhh", int(m), int(b), lower, upper)
                                    for m, b in zip(multipliers[0], bias))
            else:
                if len(multipliers) != 2 or lower != 0 or upper != 127:
                    raise ValueError(f"Unsupported Add contract: {self.task}/{name}")
                if any(abs(int(m)) >= 2**21 for branch in multipliers for m in branch):
                    raise ValueError("Add multiplier exceeds signed 22-bit hardware range")
                expected = b"".join(struct.pack("<iiq", int(a), int(b), int(c))
                                    for a, b, c in zip(*multipliers, bias))
            self.check_image(image, name + ".params", expected)

    def check_image(self, image, name, expected):
        row = self.rows[name]
        start = int(row["start_word"]) * 8
        if image[start:start+len(expected)] != expected:
            raise ValueError(f"{self.task}/{name}: parameter image differs from frozen contract")

    def add(self, name, op, reads, shape, bits=8, **kwargs):
        index = len(self.stages)
        c, h, w = shape
        size = ((c+7)//8*8 if bits == 16 else (c+15)//16*16) * h * w * (bits//8)
        self.tensors[name] = dict(shape=shape, bytes=size, produced=index, last=index)
        for source in reads:
            self.tensors[source]["last"] = index
        self.stages.append(dict(name=name, op=op, reads=reads, bytes=size,
                                format=1 if bits == 16 else 5 if bits == 32 else 0, kwargs=kwargs))

    def block(self, name, source, n):
        conv = self.contract["convolutions"]
        cout = conv[name+".expand"]["shape"][0]
        for suffix, src, raw in (("expand", source, False), ("project", name+".mix", True), ("skip", source, True)):
            key = name+"."+suffix
            cin = conv[key]["shape"][1]
            self.add(key, 1, [src], (cout, n, n), 32 if raw else 8,
                     width=n, height=n, groups=cout//16, cin=cin, cout=cout,
                     weights=self.address(key+".weight.i8.bin"), params=self.address(key+".params"),
                     shift=self.contract["merges"][name+".out" if raw else key]["shift"], raw=raw, raw_p16=raw)
            if suffix == "expand":
                if self.fuse_dw_add:
                    # op=11 在 FPGA 内完成 DW3、DW5 和 mix；中间 INT32 不落 DDR。
                    self.add(name+".mix", 11, [key], (cout, n, n),
                             width=n, height=n, groups=cout//16, cin=cout, cout=cout,
                             weights=self.address(name+".dw3.weight.i8.bin"),
                             mac=self.address(name+".dw5.weight.i8.bin"),
                             params=self.address(name+".mix.params"),
                             shift=self.contract["merges"][name+".mix"]["shift"],
                             lower=0, upper=127)
                else:
                    for dw, op in (("dw3", 8), ("dw5", 9)):
                        self.add(name+"."+dw, op, [key], (cout, n, n), 32,
                                 width=n, height=n, groups=cout//16, cin=cout, cout=cout,
                                 weights=self.address(name+"."+dw+".weight.i8.bin"))
                    self.add_merge(name+".mix", [name+".dw3", name+".dw5"], cout, n)
        self.add_merge(name+".out", [name+".project", name+".skip"], cout, n)

    def add_merge(self, name, reads, channels, n):
        cfg = self.contract["merges"][name]
        self.add(name, 6, reads, (channels, n, n), width=n, height=n, groups=channels//16,
                 cin=channels, cout=channels, params=self.address(name+".params"),
                 shift=cfg["shift"], lower=0, upper=127)

    def build_graph(self):
        base = self.contract["convolutions"]["e1.expand"]["shape"][0]
        source = "input"
        for i, name in enumerate(("e1", "e2", "e3", "mid")):
            n, c = self.side >> i, base << i
            self.block(name, source, n)
            source = name+".out"
            if i < 3:
                pooled = "pool"+str(i+1)
                self.add(pooled, 2, [source], (c, n//2, n//2), width=n, height=n, groups=c//16, cin=c, cout=c)
                source = pooled
        previous = "mid.out"
        for name, skip, c, n in (("d3", "e3.out", base*4, self.side//4),
                                  ("d2", "e2.out", base*2, self.side//2), ("d1", "e1.out", base, self.side)):
            if name == "d1" and self.fuse_up_concat:
                # 先输出放大后的A组，再接skip组；中间up张量不落DDR。
                self.add(name+".concat", 13, [previous, skip], (c*3, n, n), width=n//2, height=n//2,
                         groups=c*2//16, groups_b=c//16, cin=0, cout=0)
            else:
                self.add(name+".up", 10, [previous], (c*2, n, n), width=n//2, height=n//2,
                         groups=c*2//16, cin=0, cout=0, groups_b=0)
                self.add(name+".concat", 5, [name+".up", skip], (c*3, n, n), width=n, height=n,
                         groups=c*2//16, groups_b=c//16, cin=0, cout=0)
            self.block(name, name+".concat", n)
            previous = name+".out"
        self.add("head", 1, [previous], (self.channels, self.side, self.side), 16,
                 width=self.side, height=self.side, groups=1, cin=base, cout=self.channels,
                 weights=self.address("head.weight.i8.bin"), params=self.address("head.params"),
                 shift=self.contract["merges"]["head"]["shift"], int16=True)
        expected = (44 if self.fuse_up_concat else 45) if self.fuse_dw_add else 59
        if len(self.stages) != expected:
            raise ValueError(f"Expected {expected} frozen graph stages")

    def allocate(self):
        # First fit among tensors still needed in this stage; inputs and outputs
        # cannot alias until the final consumer has completed.
        self.arena_end = ARENA_BASE
        self.peak_live_bytes = 0
        allocated = []
        for name, tensor in self.tensors.items():
            index = tensor["produced"]
            live = sorted((t for t in allocated if t["last"] >= index), key=lambda t: t["address"])
            cursor = ARENA_BASE
            size = (tensor["bytes"]+31) & ~31
            for other in live:
                if cursor+size <= other["address"]:
                    break
                cursor = max(cursor, other["address"]+((other["bytes"]+31) & ~31))
            if cursor+size > DDR_END:
                raise ValueError(f"{self.task}/{name}: DDR capacity exceeded")
            tensor["address"] = cursor
            allocated.append(tensor)
            self.arena_end = max(self.arena_end, cursor+size)
            self.peak_live_bytes = max(self.peak_live_bytes, size+sum((t["bytes"]+31) & ~31 for t in live))
        for stage in self.stages:
            reads = [self.tensors[n] for n in stage["reads"]]
            kwargs = {"groups_b": 0, "mac": 0} | stage["kwargs"]
            stage["descriptor"] = descriptor(stage["op"], 1, base_a=reads[0]["address"],
                base_b=reads[1]["address"] if len(reads)>1 else 0, output=self.tensors[stage["name"]]["address"],
                **kwargs)
        self.schedule_sha256 = hashlib.sha256(b"".join(s["descriptor"] for s in self.stages)).hexdigest()

    def summary(self):
        return dict(model=self.task, contract_sha256=self.contract_sha256, stages=len(self.stages),
                    export_sha256=self.export_sha256,
                    schedule_sha256=self.schedule_sha256,
                    side=self.side, outputs=self.channels, arena_base=ARENA_BASE, arena_end=self.arena_end,
                    arena_bytes=self.arena_end-ARENA_BASE, peak_live_bytes=self.peak_live_bytes,
                    input_bytes=self.tensors["input"]["bytes"], head_bytes=self.tensors["head"]["bytes"],
                    tumor_parameter_bytes=len(self.parameters), fuse_dw_add=self.fuse_dw_add,
                    fuse_up_concat=self.fuse_up_concat)


def prepare_session(client):
    status = client.rpc(STATUS)
    if status["state"] != 0:
        raise RuntimeError(f"FPGA holds run 0x{status['run_id']:08x}, state={status['state']}; preserve evidence and reset/release it before inference")
    # A previous legacy IMAGE_READY protects its volume from WRITE/RUN. Start
    # and abort a fresh empty transfer to invalidate only that old descriptor.
    identity = secrets.randbits(32) or 1
    client.sequence = (client.sequence+1) & 0xffffffff
    sequence = client.sequence
    params = ImageBegin(total_slices=1, total_bytes=262144, expected_packets=256,
                        image_base_addr=0x10000000)
    packet = build_frame(MSG_IMAGE_BEGIN, identity, sequence, params.body())
    for _ in range(client.retries):
        client.socket.sendto(packet, client.peer)
        deadline = monotonic()+client.socket.gettimeout()
        while monotonic() < deadline:
            try:
                data, peer = client.socket.recvfrom(2048)
            except TimeoutError:
                break
            if peer != client.peer:
                continue
            try:
                frame = parse_frame(data)
            except FrameError:
                continue
            # Legacy ACK header increments the sequence; its body echoes the request.
            if (frame.msg_type, frame.transfer_id, frame.sequence) != (MSG_ACK, identity, (sequence+1) & 0xffffffff):
                continue
            ack = parse_ack_body(frame.body)
            if ack.status or ack.acked_msg_type != MSG_IMAGE_BEGIN or ack.acked_sequence != sequence:
                raise RuntimeError(f"FPGA rejected new session: {ack}")
            client.sequence = (client.sequence+1) & 0xffffffff
            client.socket.sendto(build_frame(MSG_TRANSFER_ABORT, identity, client.sequence, b""), client.peer)
            return
    raise TimeoutError("FPGA did not acknowledge a fresh inference session")


def run_plane(client, plan, sample, run_timeout, record):
    started = perf_counter()
    payload = pack_input(sample)
    print(f"[FPGA INPUT] upload {len(payload)} bytes", flush=True)
    client.upload(plan.tensors["input"]["address"], payload)
    upload_s = perf_counter()-started
    print(f"[FPGA INPUT] upload done {upload_s:.3f}s", flush=True)
    stages = []
    head_data = None
    for stage_index, stage in enumerate(plan.stages, 1):
        desc = bytearray(stage["descriptor"])
        run_id = secrets.randbits(32) or 1
        struct.pack_into("<I", desc, 48, run_id)
        record.update(active_stage=stage["name"], run_id=run_id, descriptor_hex=desc.hex())
        print(f"[FPGA STAGE] {stage_index}/{len(plan.stages)} {stage['name']} op={stage['op']} start", flush=True)
        t = perf_counter()
        client.run(desc)
        status = client.wait(run_id, timeout=run_timeout)
        elapsed = perf_counter()-t
        if (status["op"], status["format"], status["bytes"], status["mac_bytes"]) != (stage["op"], stage["format"], stage["bytes"], 0):
            raise RuntimeError(f"{plan.task}/{stage['name']}: unexpected FPGA STATUS {status}")
        read_s = 0.0
        if stage["name"] == "head":
            t = perf_counter()
            head_data = client.read(run_id, plan.tensors["head"]["address"], stage["bytes"])
            read_s = perf_counter()-t
            if len(head_data) != stage["bytes"]:
                raise RuntimeError("Truncated INT16 head result")
        client.rpc(RELEASE, run_id)
        stages.append(dict(name=stage["name"], op=stage["op"], descriptor_hex=desc.hex(),
                           run_wait_seconds=elapsed, read_seconds=read_s))
        record["completed_stages"] = stages
        print(f"[FPGA STAGE] {stage_index}/{len(plan.stages)} {stage['name']} op={stage['op']} done {elapsed:.3f}s", flush=True)
    record.pop("active_stage", None)
    record.update(upload_seconds=upload_s, run_wait_seconds=sum(s["run_wait_seconds"] for s in stages),
                  download_seconds=sum(s["read_seconds"] for s in stages), elapsed_seconds=perf_counter()-started)
    return decode_logits(head_data, plan.channels, plan.side)
