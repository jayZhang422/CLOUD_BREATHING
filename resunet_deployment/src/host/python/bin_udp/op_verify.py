"""Run op_rom, mkdc, decoder_d3 or fullnet HEX vectors and compare every returned byte."""
import argparse
from datetime import datetime
import json
from pathlib import Path
import re
import secrets
import struct

from src.op_client import (COEFF_BASE, COEFF_LIMIT, PARAM_DDR_BASE, PARAM_DDR_LIMIT,
                           OpClient, RELEASE, STATUS)

VECTORS = Path(__file__).resolve().parents[4] / "sim/xsim/tests/op_rom/vectors"
MKDC_VECTORS = VECTORS.parent.parent / "mkdc/vectors"
DECODER_VECTORS = VECTORS.parent.parent / "decoder_d3/vectors"
FULLNET_ROOT = VECTORS.parent.parent / "fullnet"
FULLNET_VECTORS = FULLNET_ROOT / "vectors"
FULLNET_SIZE_VECTORS = {
    "32": FULLNET_ROOT / "vectors",
    "128": FULLNET_ROOT / "vessel/128x128/vectors",
    "512": FULLNET_ROOT / "vessel/512x512/vectors",
}
FULLNET_SKIP_SPECS = {
    "032_d3.concat": (0x02200000, "022_e3.out", 4096),
    "041_d2.concat": (0x02100000, "014_e2.out", 8192),
    "050_d1.concat": (0x02000000, "006_e1.out", 16384),
}
TUMOR_ROM_BASE, TUMOR_ROM_LIMIT = 0x00159600, 0x002BD240
PARAM_COE = Path(__file__).resolve().parent / "assets" / "quantized_params_rom_full.coe"
DEPENDENCIES = {
    f"{child}_{suffix}": (f"{parent}_{suffix}",)
    for suffix in ("fast", "round2")
    for child, parent in (("pool_from_tumor_pw", "tumor_e1"),
                          ("concat_pool", "pool_from_tumor_pw"),
                          ("pw_from_concat_rom", "concat_pool"))
}
DEPENDENCIES.update({f"legacy_{child}": tuple(f"legacy_{p}" for p in parents)
                     for child, parents in list(DEPENDENCIES.items())})
MKDC_DEPENDENCIES = {
    f"{model}_mid_{child}": tuple(f"{model}_mid_{p}" for p in parents)
    for model in ("vessel", "airway", "lobe", "tumor")
    for child, parents in (("dw3", ("expand",)), ("dw5", ("expand",)),
                           ("mix", ("dw3", "dw5")), ("project", ("mix",)),
                           ("skip", ("expand",)), ("out", ("project", "skip")))
}
DECODER_DEPENDENCIES = {
    f"vessel_d3_{child}": tuple(f"vessel_d3_{p}" for p in parents)
    for child, parents in (("concat", ("up",)), ("expand", ("concat",)),
                           ("dw3", ("expand",)), ("dw5", ("expand",)),
                           ("mix", ("dw3", "dw5")), ("project", ("mix",)),
                           ("skip", ("concat",)), ("out", ("project", "skip")))
}


def select_cases(rows, name=None, *, mkdc=False, decoder=False):
    by_name = {row[0]: row for row in rows}
    if not rows or len(by_name) != len(rows):
        raise ValueError("case list is empty or contains duplicate names")
    selected = []
    dependencies = DEPENDENCIES | MKDC_DEPENDENCIES if mkdc else DEPENDENCIES
    if decoder:
        dependencies = dependencies | DECODER_DEPENDENCIES

    def include(key):
        if key not in by_name:
            raise ValueError(f"unknown case or missing prerequisite: {key}")
        for parent in dependencies.get(key, ()):
            include(parent)
        if by_name[key] not in selected:
            selected.append(by_name[key])

    for key in ([name] if name else by_name):
        include(key)
    return selected


def select_fullnet_cases(rows, name=None):
    """Select the complete prefix ending at one fullnet task.

    fullnet descriptors point at the previous task's DDR output, so a selected
    task is only valid after every earlier task has run in file order.
    """
    if not rows or any(len(row) != 4 for row in rows):
        raise ValueError("fullnet task list must contain four columns")
    names = [row[0] for row in rows]
    if len(set(names)) != len(names):
        raise ValueError("fullnet task list contains duplicate names")
    if name is None:
        return list(rows)
    try:
        end = names.index(name) + 1
    except ValueError as exc:
        raise ValueError(f"unknown case or missing prerequisite: {name}") from exc
    return rows[:end]


def read_hex(path, size):
    data = bytes.fromhex(path.read_text(encoding="ascii"))
    if len(data) != size:
        raise ValueError(f"{path}: expected {size} bytes, got {len(data)}")
    return data


def adapt_p4_head_golden(desc, data):
    """既有冻结HEX使用P4；只重排普通INT16头，不重算数学Golden。"""
    if desc[0] != 1 or desc[1] & 14 != 8:
        return data
    width,height = struct.unpack_from("<HH",desc,4)
    cout = struct.unpack_from("<H",desc,54)[0] or desc[3]
    pixels,groups4 = width*height,(cout+3)//4
    if len(data) != groups4*pixels*8:
        raise ValueError("Frozen P4 INT16 Golden length mismatch")
    result = bytearray(((cout+7)//8)*pixels*16)
    for group in range(groups4):
        for pixel in range(pixels):
            source = (group*pixels+pixel)*8
            target = ((group//2)*pixels+pixel)*16+(group%2)*8
            result[target:target+8] = data[source:source+8]
    return bytes(result)


def read_tumor_params():
    """Extract the tumor words from the shared 64-bit ROM COE as DDR bytes."""
    text = PARAM_COE.read_text(encoding="ascii")
    vector = text.split("memory_initialization_vector=", 1)[1]
    words = [int(token, 16) for token in re.findall(r"[0-9A-Fa-f]{1,16}", vector)]
    first = (TUMOR_ROM_BASE - COEFF_BASE) // 8
    count = (TUMOR_ROM_LIMIT - TUMOR_ROM_BASE) // 8
    if len(words) < first + count:
        raise ValueError(f"{PARAM_COE}: expected {first + count} words, got {len(words)}")
    return b"".join(word.to_bytes(8, "little") for word in words[first:first + count])


def coefficient_fields(op):
    return ((28, 32, 36) if op == 11 else
            (32, 36) if op == 1 else (36,) if op == 6 else
            (32,) if op in (8, 9) else ())


def result_format(desc):
    op, flags = desc[:2]
    if op in (8, 9) or flags & 16:
        return 5  # P16 INT32, little endian
    if flags & 4:
        return 2
    if flags & 8:
        return 1
    return {3: 3, 4: 4}.get(op, 0)


def remap_tumor_descriptor(desc):
    """Move tumor coefficient references from the former ROM window into DDR."""
    desc = bytearray(desc)
    fields = coefficient_fields(desc[0])
    needs_params = False
    for field in fields:
        address = struct.unpack_from("<I", desc, field)[0]
        if TUMOR_ROM_BASE <= address < TUMOR_ROM_LIMIT:
            struct.pack_into("<I", desc, field, PARAM_DDR_BASE + address - TUMOR_ROM_BASE)
            needs_params = True
        elif PARAM_DDR_BASE <= address < PARAM_DDR_BASE + TUMOR_ROM_LIMIT - TUMOR_ROM_BASE:
            needs_params = True
    return bytes(desc), needs_params


def load_case(root, row):
    name, result_size, mac_size = row
    result_size, mac_size = int(result_size), int(mac_size)
    if result_size <= 0 or mac_size < 0:
        raise ValueError(f"{name}: invalid result sizes")
    folder = root / name
    desc = read_hex(folder / "descriptor.hex", 64)
    if desc[1] & 1:
        raise ValueError(f"{name}: this runner requires offline feature vectors")
    desc, tumor_params = remap_tumor_descriptor(desc)
    # 小模型仍使用片上 ROM；tumor 系数已改为 DDR 参数区。
    for field in coefficient_fields(desc[0]):
        addr = struct.unpack_from("<I", desc, field)[0]
        if not ((COEFF_BASE <= addr < COEFF_LIMIT) or
                (PARAM_DDR_BASE <= addr < PARAM_DDR_LIMIT)) or addr % 64:
            raise ValueError(f"{name}: coefficient address 0x{addr:08x} is outside ROM/DDR windows")
    uploads = []
    for line in (folder / "uploads.txt").read_text(encoding="ascii").splitlines():
        if not line.strip():
            continue
        address, size, filename = line.split()
        address, size = int(address, 16), int(size)
        end = (address + size + 31) & ~31
        if size <= 0 or address < 0 or address % 16 or end > 0x20000000:
            raise ValueError(f"{name}: invalid feature upload range")
        if address < COEFF_LIMIT and end > COEFF_BASE:
            raise ValueError(f"{name}: coefficient space is read-only")
        uploads.append((address, read_hex(root / filename, size)))
    golden = adapt_p4_head_golden(desc, read_hex(folder / "golden.hex", result_size))
    for field, size in ((24, len(golden)), (28, mac_size)):
        address = struct.unpack_from("<I", desc, field)[0]
        if size and (address % 32 or address + ((size + 31) & ~31) > 0x20000000):
            raise ValueError(f"{name}: invalid result read range")
    return dict(name=name, descriptor=desc, uploads=uploads, tumor_params=tumor_params,
                golden=golden,
                mac=read_hex(folder / "mac.hex", mac_size) if mac_size else b"")


def load_fullnet_case(root, row):
    """Load one four-column fullnet task; only the first task has an upload."""
    name, result_size, descriptor_path, golden_path = row
    result_size = int(result_size)
    if result_size <= 0:
        raise ValueError(f"{name}: invalid result size")
    desc = read_hex(root / descriptor_path, 64)
    if desc[1] & 1:
        raise ValueError(f"{name}: fullnet runner requires offline feature vectors")
    desc, tumor_params = remap_tumor_descriptor(desc)
    for field in coefficient_fields(desc[0]):
        addr = struct.unpack_from("<I", desc, field)[0]
        if not ((COEFF_BASE <= addr < COEFF_LIMIT) or
                (PARAM_DDR_BASE <= addr < PARAM_DDR_LIMIT)) or addr % 64:
            raise ValueError(f"{name}: coefficient address 0x{addr:08x} is outside ROM/DDR windows")
    golden = adapt_p4_head_golden(desc, read_hex(root / golden_path, result_size))
    address = struct.unpack_from("<I", desc, 24)[0]
    if address % 32 or address + ((len(golden) + 31) & ~31) > 0x20000000:
        raise ValueError(f"{name}: invalid result read range")
    return dict(name=name, descriptor=desc, uploads=[], tumor_params=tumor_params,
                golden=golden, mac=b"")


def load_fullnet_uploads(root):
    uploads = []
    for line in (root / "uploads.txt").read_text(encoding="ascii").splitlines():
        if not line.strip():
            continue
        address, size, filename = line.split()
        address, size = int(address, 16), int(size)
        end = (address + size + 31) & ~31
        if size <= 0 or address < 0 or address % 16 or end > 0x20000000:
            raise ValueError(f"fullnet upload: invalid feature range 0x{address:08x}")
        if address < COEFF_LIMIT and end > COEFF_BASE:
            raise ValueError("fullnet upload overlaps coefficient ROM")
        uploads.append((address, read_hex(root / filename, size)))
    if not uploads:
        raise ValueError("fullnet uploads.txt is empty")
    return uploads


def configure_fullnet_cases(root, cases):
    """Attach the one initial input upload and post-CONCAT skip checks."""
    if not cases:
        raise ValueError("fullnet task selection is empty")
    cases[0]["uploads"] = load_fullnet_uploads(root)
    for case in cases:
        if case["name"] not in FULLNET_SKIP_SPECS:
            continue
        _, golden_name, _ = FULLNET_SKIP_SPECS[case["name"]]
        producer = next(c for c in cases if c["name"] == golden_name)
        address = struct.unpack_from("<I", producer["descriptor"], 24)[0]
        size = len(producer["golden"])
        width, height = struct.unpack_from("<HH", case["descriptor"], 4)
        groups_b = struct.unpack_from("<H", case["descriptor"], 14)[0]
        if (struct.unpack_from("<I", case["descriptor"], 20)[0] != address or
                size != width * height * groups_b * 16):
            raise ValueError(f"{case['name']}: encoder skip address/shape mismatch")
        case["ddr_checks"] = [dict(name=golden_name.replace(".", "_"),
                                    address=address,
                                    expected=producer["golden"])]
    return cases


def prepare_tumor_params(cases):
    """一次装载完整 tumor 映像；校验并去除仿真向量内相同的重复装载。"""
    if not any(case["tumor_params"] for case in cases):
        return b""
    payload = read_tumor_params()
    for case in cases:
        uploads = []
        for address, data in case["uploads"]:
            if address == PARAM_DDR_BASE and len(data) == len(payload):
                if data != payload:
                    raise ValueError(f"{case['name']}: tumor upload differs from full parameter COE")
            else:
                uploads.append((address, data))
        case["uploads"] = uploads
    return payload


def upload_feature(client, address, data):
    """16B 对齐向量通过原有 32B WRITE 上传；保留同一首尾块的相邻数据。"""
    if address % 32:
        start = address & ~31
        end = address + len(data)
        first = client.read(0, start, 32, diagnostic=True)
        prefix = first[:address - start]
        suffix = b""
        if end % 32:
            last = first if (end & ~31) == start else client.read(0, end & ~31, 32, diagnostic=True)
            suffix = last[end % 32:]
        data = prefix + data + suffix
        address = start
    client.upload(address, data)


def run_case(client, case, output, run_timeout):
    name = case["name"]
    folder = output / name
    folder.mkdir(parents=True, exist_ok=True)
    desc = bytearray(case["descriptor"])
    struct.pack_into("<I", desc, 48, secrets.randbits(32) or 1)
    (folder / "descriptor.bin").write_bytes(desc)
    print(f"[BOARD RUN] {name}", flush=True)
    for address, data in case["uploads"]:
        upload_feature(client, address, data)
    run_id = client.run(desc)
    status = client.wait(run_id, timeout=run_timeout)
    (folder / "status.json").write_text(json.dumps(
        {k: v for k, v in status.items() if k != "data"}, indent=2) + "\n", encoding="utf-8")
    if (status["op"], status["format"]) != (desc[0], result_format(desc)):
        raise RuntimeError(f"{name}: FPGA op/format {status['op']}/{status['format']} "
                           f"!= expected {desc[0]}/{result_format(desc)}")
    if (status["bytes"], status["mac_bytes"]) != (len(case["golden"]), len(case["mac"])):
        raise RuntimeError(f"{name}: FPGA result sizes {status['bytes']}/{status['mac_bytes']} "
                           f"!= expected {len(case['golden'])}/{len(case['mac'])}")
    for kind, field in (("golden", 24), ("mac", 28)):
        expected = case[kind]
        if not expected:
            continue
        base = struct.unpack_from("<I", desc, field)[0]
        actual = client.read(run_id, base, len(expected))
        (folder / f"{kind}_actual.bin").write_bytes(actual)
        if len(actual) != len(expected):
            raise RuntimeError(f"{name}/{kind}: returned length {len(actual)} != {len(expected)}")
        if actual != expected:
            first = next(i for i, (a, b) in enumerate(zip(actual, expected)) if a != b)
            raise AssertionError(f"{name}/{kind}: byte={first}, expected={expected[first]:02x}, actual={actual[first]:02x}")
    client.rpc(RELEASE, run_id)
    # 现有服务仅在释放结果后允许 run_id=0 的诊断读取；释放不会清空 DDR。
    checks = list(case.get("ddr_checks", ()))
    if "encoder_skip" in case:
        checks.append(dict(name="encoder_skip", address=0x03100000,
                           expected=case["encoder_skip"]))
    for check in checks:
        check_name, expected = check["name"], check["expected"]
        actual = client.read(0, check["address"], len(expected), diagnostic=True)
        (folder / f"{check_name}_actual.bin").write_bytes(actual)
        if len(actual) != len(expected):
            raise RuntimeError(f"{name}/{check_name} after RELEASE: returned length "
                               f"{len(actual)} != {len(expected)}")
        if actual != expected:
            first = next(i for i, (a, b) in enumerate(zip(actual, expected)) if a != b)
            raise AssertionError(f"{name}/{check_name} after RELEASE: byte={first}, "
                                 f"expected={expected[first]:02x}, actual={actual[first]:02x}")
    print(f"[BOARD PASSED] {name}: result={status['bytes']} MAC={status['mac_bytes']} bytes", flush=True)
    return dict(name=name, run_id=run_id, op=status["op"], format=status["format"],
                result_bytes=status["bytes"], mac_bytes=status["mac_bytes"],
                encoder_skip_bytes=len(case.get("encoder_skip", b"")),
                ddr_check_bytes=sum(len(c["expected"]) for c in checks))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="192.168.1.10")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--bind", default="0.0.0.0", help="local NIC IPv4; ephemeral UDP source port")
    parser.add_argument("--timeout", type=float, default=1.0, help="seconds per RPC attempt")
    parser.add_argument("--run-timeout", type=float, default=120)
    parser.add_argument("--suite", choices=("legacy", "mkdc", "decoder", "fullnet"), default="legacy",
                        help="legacy: 25 cases; mkdc: 52 stages; decoder: vessel d3 / 9 stages; fullnet: 59 stages")
    parser.add_argument("--cases", type=Path, help="override suite vector directory")
    parser.add_argument("--fullnet-size", choices=tuple(FULLNET_SIZE_VECTORS),
                        help="fullnet vector profile: 32, 128, or 512 (requires --suite fullnet)")
    parser.add_argument("--case-list", help="override suite list, e.g. cases_all.txt / cases_edge.txt / cases_max.txt")
    parser.add_argument("--case", help="one case plus all required predecessors; default: whole suite")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--list", action="store_true", help="list selected cases without UDP")
    mode.add_argument("--dry-run", action="store_true", help="validate vectors without UDP")
    mode.add_argument("--probe", action="store_true", help="STATUS only; tests communication, not computation")
    parser.add_argument("--out", type=Path, default=Path(__file__).resolve().parent / "output" /
                        datetime.now().strftime("board_%Y%m%d_%H%M%S_%f"))
    args = parser.parse_args(argv)
    if args.fullnet_size and args.suite != "fullnet":
        parser.error("--fullnet-size requires --suite fullnet")
    if args.fullnet_size and args.cases is not None:
        parser.error("--fullnet-size and --cases are mutually exclusive")
    if args.suite == "fullnet" and args.fullnet_size:
        args.cases = FULLNET_SIZE_VECTORS[args.fullnet_size]
    else:
        args.cases = args.cases or {"legacy": VECTORS, "mkdc": MKDC_VECTORS,
                                    "decoder": DECODER_VECTORS, "fullnet": FULLNET_VECTORS}[args.suite]
    args.case_list = args.case_list or ("cases_round2.txt" if args.suite == "legacy" else
                                        "tasks.txt" if args.suite == "fullnet" else "cases_chain.txt")
    client, report = None, None
    try:
        if not 1 <= args.port <= 65535 or args.timeout <= 0 or args.run_timeout <= 0:
            raise ValueError("port must be 1..65535 and timeouts must be positive")
        if not args.probe:
            rows = [line.split() for line in (args.cases / args.case_list).read_text(encoding="ascii").splitlines()
                    if line.strip()]
            selected = (select_fullnet_cases(rows, args.case) if args.suite == "fullnet" else
                        select_cases(rows, args.case, mkdc=args.suite == "mkdc",
                                     decoder=args.suite == "decoder"))
            if args.list:
                for row in selected:
                    print(" ".join(row))
                return 0
            cases = ([load_fullnet_case(args.cases, row) for row in selected]
                     if args.suite == "fullnet" else [load_case(args.cases, row) for row in selected])
            if args.suite == "fullnet":
                configure_fullnet_cases(args.cases, cases)
            if args.suite == "decoder":
                for case in cases:
                    if case["name"] == "vessel_d3_up" or case["name"] in DECODER_DEPENDENCIES:
                        case["encoder_skip"] = read_hex(args.cases / "encoder_skip.hex", 4096)
            payload = prepare_tumor_params(cases)
            if args.dry_run:
                print(f"[VECTORS PASSED] cases={len(cases)}; no UDP sent")
                return 0
            args.out.mkdir(parents=True, exist_ok=False)
            report = dict(host=args.host, port=args.port, suite=args.suite,
                          vectors=str(args.cases.resolve()), case_list=args.case_list,
                          selected=[case["name"] for case in cases], passed=[], verdict="FAIL")
            if args.fullnet_size:
                report["fullnet_size"] = int(args.fullnet_size)
        client = OpClient(args.host, args.port, timeout=args.timeout, bind=args.bind)
        if args.probe:
            print(f"[LINK PASSED] STATUS={client.rpc(STATUS)}; communication only")
            return 0
        parameter_uploads = []
        if payload:
            print(f"[PARAM UPLOAD] tumor: {len(payload)} bytes -> DDR 0x{PARAM_DDR_BASE:08x}", flush=True)
            client.upload(PARAM_DDR_BASE, payload)
            parameter_uploads.append(dict(model="tumor", address=PARAM_DDR_BASE, bytes=len(payload)))
            report["parameter_uploads"] = parameter_uploads
        for case in cases:
            report["active_case"] = case["name"]
            report["passed"].append(run_case(client, case, args.out, args.run_timeout))
        report.pop("active_case", None)
        report["verdict"] = "PASS"
        print(f"[BOARD ALL PASSED] cases={len(cases)}; output={args.out}")
        return 0
    except (OSError, ValueError, RuntimeError, AssertionError) as exc:
        print(f"[FAILED] {exc}", flush=True)
        if report is not None:
            report["error"] = str(exc)
            print(f"Evidence: {args.out}. Reset FPGA before retrying; no recovery commands sent. "
                  "Encoder-skip checks run after normal RELEASE.")
        return 1
    except KeyboardInterrupt:
        if report is not None:
            report["error"] = "interrupted; reset FPGA before retrying"
        print("[INTERRUPTED] Reset FPGA before retrying.")
        return 130
    finally:
        if client is not None:
            client.close()
        if report is not None:
            (args.out / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
