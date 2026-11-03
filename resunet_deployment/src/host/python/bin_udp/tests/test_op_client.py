"""Offline checks only: mock UDP, current ROM vectors, no FPGA traffic."""
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import socket
import struct
import tempfile
import unittest
from unittest.mock import Mock, patch

import main as transfer_cli
import op_verify
from src.op_client import OpClient, READ, RELEASE, RUN, descriptor
from src.protocol import build_frame, parse_frame


class HostAdapterTest(unittest.TestCase):
    def test_frozen_int16_golden_reorders_groups_and_preserves_debug(self):
        desc = descriptor(1,1,width=2,height=1,cin=3,cout=5,int16=True,
                          weights=0x00100000,params=0x00100400)
        old = struct.pack("<16h",1,2,3,4,11,12,13,14,5,0,0,0,15,0,0,0)
        expected = struct.pack("<16h",1,2,3,4,5,0,0,0,11,12,13,14,15,0,0,0)
        self.assertEqual(op_verify.adapt_p4_head_golden(desc,old),expected)
        debug = bytearray(desc)
        debug[1] |= 2
        self.assertEqual(op_verify.adapt_p4_head_golden(debug,old),old)

    def test_performance_snapshot_uses_idle_alias_and_rejects_stale_data(self):
        from src.op_client import PERF_BASE, PERF_CORE_NAMES

        client, _ = self.client()
        run_id = 0x12345679
        data = bytearray(256)
        struct.pack_into("<8I", data, 0, 0x4650504F, 256, 1, run_id,
                         12, 250_000_000, 333_333_333, 0)
        struct.pack_into("<16Q", data, 32, *range(100, 116))
        struct.pack_into("<8I", data, 160, *range(8))
        with patch.object(client, "read", return_value=bytes(data)) as read:
            result = client.performance(run_id)
            read.assert_called_once_with(0, PERF_BASE + (run_id & 63) * 256,
                                         256, diagnostic=True)
        self.assertEqual(result["cycles"], dict(zip(PERF_CORE_NAMES, range(100, 116))))
        self.assertEqual(result["seconds"], 100 / 250_000_000)
        self.assertEqual(result["ddr_counters"], list(range(8)))
        for offset, value in ((12, run_id + 1), (20, 0), (28, 1)):
            bad = bytearray(data)
            struct.pack_into("<I", bad, offset, value)
            with self.subTest(offset=offset), patch.object(client, "read", return_value=bytes(bad)):
                with self.assertRaises(RuntimeError):
                    client.performance(run_id)

    def client(self):
        sock = Mock()
        sock.gettimeout.return_value = 1.0
        with patch("src.op_client.socket.socket", return_value=sock):
            client = OpClient("127.0.0.1", bind="127.0.0.1")
        self.addCleanup(client.close)
        return client, sock

    def test_descriptor_and_transfer_defaults(self):
        for cin, cout in ((3, 16), (768, 256), (256, 512)):
            desc = descriptor(1, 123, width=2, height=2, cin=cin, cout=cout,
                              weights=0x100000, params=0x100100)
            self.assertEqual(len(desc), 64)
            extended = struct.unpack_from("<HH", desc, 52)
            self.assertEqual(extended, (cin, cout) if max(cin, cout) > 255 else (0, 0))
            self.assertEqual(desc[2:4], bytes((cin & 255, cout & 255)))
        for op in (1, 6):
            with self.assertRaises(ValueError):
                descriptor(op, 1, width=1, height=1)
        parser = transfer_cli.build_parser()
        self.assertTrue(parser.parse_args(["send"]).skip_infer)
        self.assertTrue(parser.parse_args(["upload"]).skip_infer)
        self.assertFalse(parser.parse_args(["send", "--legacy-infer"]).skip_infer)

    def test_current_vectors_and_dependencies(self):
        rows = [line.split() for line in (op_verify.VECTORS / "cases_round2.txt").read_text().splitlines()]
        cases = [op_verify.load_case(op_verify.VECTORS, row) for row in op_verify.select_cases(rows)]
        self.assertEqual(len(cases), 25)
        chain = op_verify.select_cases(rows, "pw_from_concat_rom_round2")
        self.assertEqual([r[0] for r in chain], ["tumor_e1_round2", "pool_from_tumor_pw_round2",
                                               "concat_pool_round2", "pw_from_concat_rom_round2"])
        with self.assertRaises(ValueError):
            op_verify.select_cases(rows, "does_not_exist")
        with self.assertRaises(ValueError):
            op_verify.select_cases([])
        with patch("op_verify.OpClient") as client, redirect_stdout(io.StringIO()):
            self.assertEqual(op_verify.main(["--dry-run"]), 0)
            self.assertEqual(op_verify.main(["--case", "does_not_exist"]), 1)
            client.assert_not_called()

    def test_tumor_coefficients_remap_and_payload_size(self):
        row = ["tumor_e1_round2", "6400", "25600"]
        case = op_verify.load_case(op_verify.VECTORS, row)
        self.assertTrue(case["tumor_params"])
        self.assertEqual(struct.unpack_from("<I", case["descriptor"], 32)[0], op_verify.PARAM_DDR_BASE)
        self.assertEqual(struct.unpack_from("<I", case["descriptor"], 36)[0], op_verify.PARAM_DDR_BASE + 0x400)
        payload = op_verify.read_tumor_params()
        self.assertEqual(len(payload), op_verify.TUMOR_ROM_LIMIT - op_verify.TUMOR_ROM_BASE)

    def test_mkdc_descriptors_and_remap(self):
        for op in (8, 9):
            desc = descriptor(op, 42, width=4, height=4, groups=32, weights=0x159600)
            remapped, needs_params = op_verify.remap_tumor_descriptor(desc)
            self.assertTrue(needs_params)
            self.assertEqual(struct.unpack_from("<I", remapped, 32)[0], 0x08000000)
            self.assertEqual((desc[1], op_verify.result_format(desc)), (0, 5))
            for kwargs in ({"groups": 33}, {"raw": True}, {"weights": 0x100001}):
                with self.assertRaises(ValueError):
                    descriptor(op, 42, **(dict(width=4, height=4, weights=0x100000) | kwargs))
        desc = descriptor(1, 42, width=4, height=4, cout=32, raw=True, raw_p16=True,
                          weights=0x100000, params=0x100100)
        self.assertEqual((desc[1], op_verify.result_format(desc)), (20, 5))
        for kwargs in ({"raw": False}, {"cout": 17}, {"int16": True}):
            with self.assertRaises(ValueError):
                descriptor(1, 42, **(dict(width=4, height=4, cout=32, raw=True, raw_p16=True,
                                        weights=0x100000, params=0x100100) | kwargs))

    def test_upsample_descriptor_limits(self):
        for width, height, groups in ((1, 1, 1), (5, 3, 32), (256, 256, 32)):
            desc = descriptor(10, 42, width=width, height=height, groups=groups,
                              base_a=0x03000010, output=0x06000000)
            self.assertEqual((desc[0], desc[1], op_verify.result_format(desc)), (10, 0, 0))
            self.assertEqual(struct.unpack_from("<HHH", desc, 4), (width, height, groups))
        for kwargs in ({"width": 0}, {"width": 257}, {"height": 0}, {"height": 257},
                       {"groups": 0}, {"groups": 33}, {"online": True}, {"debug_mac": True},
                       {"raw": True}, {"int16": True}, {"raw": True, "raw_p16": True},
                       {"base_a": 0x3000001}, {"output": 0x6000010}, {"output": 0x3000000},
                       {"base_a": 0x1ffffff0}, {"output": 0x1fffffe0}, {"base_a": -16}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                descriptor(10, 42, **(dict(width=4, height=4, base_a=0x03000010,
                                          output=0x06000000) | kwargs))

    def test_fused_dw_add_descriptor_limits_and_weight_addresses(self):
        options = dict(width=512,height=512,groups=1,base_a=0x09000000,output=0x0a000000,
                       weights=0x100000,mac=0x100100,params=0x100300,shift=24,lower=0,upper=127)
        d=descriptor(11,42,**options)
        self.assertEqual((d[0],d[1],op_verify.result_format(d)),(11,0,0))
        self.assertEqual(struct.unpack_from("<III",d,28),(options["mac"],options["weights"],options["params"]))
        for kwargs in ({"weights":None},{"params":None},{"mac":0},{"mac":0x100101},
                       {"weights":0x159580},{"params":0x81fffc0},{"groups":33},
                       {"width":513},{"shift":64},{"raw":True},{"int16":True},
                       {"output":0x09000000},{"base_a":0x1ffffff0},{"output":0x0a000010}):
            with self.subTest(kwargs=kwargs),self.assertRaises(ValueError):
                descriptor(11,42,**(options|kwargs))

    def test_decoder_vectors_dependencies_and_dry_run(self):
        root = op_verify.DECODER_VECTORS
        rows = [line.split() for line in (root / "cases_all.txt").read_text().splitlines()]
        chain = op_verify.select_cases(rows, "vessel_d3_out", decoder=True)
        stages = ("up", "concat", "expand", "dw3", "dw5", "mix", "project", "skip", "out")
        self.assertEqual([r[0] for r in chain], [f"vessel_d3_{s}" for s in stages])
        cases = [op_verify.load_case(root, row) for row in chain]
        self.assertEqual([len(c["uploads"]) for c in cases], [2] + [0] * 8)
        outputs = {s: struct.unpack_from("<I", c["descriptor"], 24)[0] for s, c in zip(stages, cases)}
        inputs = {"concat": ("up",), "expand": ("concat",), "dw3": ("expand",),
                  "dw5": ("expand",), "mix": ("dw3", "dw5"), "project": ("mix",),
                  "skip": ("concat",), "out": ("project", "skip")}
        for stage, case in zip(stages[1:], cases[1:]):
            for offset, parent in zip((16, 20), inputs[stage]):
                self.assertEqual(struct.unpack_from("<I", case["descriptor"], offset)[0], outputs[parent])
        self.assertEqual(struct.unpack_from("<I", cases[1]["descriptor"], 20)[0], 0x03100000)
        self.assertEqual(cases[0]["uploads"][1], (0x03100000, op_verify.read_hex(root / "encoder_skip.hex", 4096)))
        self.assertEqual([op_verify.result_format(c["descriptor"]) for c in cases], [0, 0, 0, 5, 5, 0, 5, 5, 0])
        with patch("op_verify.OpClient") as client, redirect_stdout(io.StringIO()):
            for case_list in ("cases_chain.txt", "cases_quick.txt", "cases_edge.txt", "cases_max.txt", "cases_all.txt"):
                self.assertEqual(op_verify.main(["--suite", "decoder", "--case-list", case_list, "--dry-run"]), 0)
            client.assert_not_called()

    def test_fullnet_prefix_input_and_skip_checks(self):
        root = op_verify.FULLNET_VECTORS
        rows = [line.split() for line in (root / "tasks.txt").read_text().splitlines()
                if line.strip()]
        self.assertEqual(len(op_verify.select_fullnet_cases(rows)), 59)
        selected = op_verify.select_fullnet_cases(rows, "058_head")
        self.assertEqual(len(selected), 59)
        self.assertEqual([row[0] for row in selected[:2]], ["000_e1.expand", "001_e1.dw3"])
        cases = [op_verify.load_fullnet_case(root, row) for row in selected]
        op_verify.configure_fullnet_cases(root, cases)
        self.assertEqual(cases[0]["uploads"], [(0x01000000, op_verify.read_hex(root / "input.hex", 16384))])
        self.assertEqual([len(c["uploads"]) for c in cases], [1] + [0] * 58)
        self.assertEqual(set(c["name"] for c in cases if c.get("ddr_checks")),
                         set(op_verify.FULLNET_SKIP_SPECS))
        self.assertEqual([(c["ddr_checks"][0]["address"], len(c["ddr_checks"][0]["expected"]))
                          for c in cases if c.get("ddr_checks")],
                         [(0x02200000, 4096), (0x02100000, 8192), (0x02000000, 16384)])
        with patch("op_verify.OpClient") as client, redirect_stdout(io.StringIO()):
            self.assertEqual(op_verify.main(["--suite", "fullnet", "--case", "058_head", "--dry-run"]), 0)
            client.assert_not_called()

    def test_fullnet_size_selector_512(self):
        output = io.StringIO()
        with patch("op_verify.OpClient") as client, redirect_stdout(output):
            self.assertEqual(op_verify.main([
                "--suite", "fullnet", "--fullnet-size", "512",
                "--case", "058_head", "--list",
            ]), 0)
            client.assert_not_called()
        rows = [line.split() for line in output.getvalue().splitlines() if line.strip()]
        self.assertEqual(len(rows), 59)
        self.assertEqual(rows[0][0], "000_e1.expand")
        self.assertEqual(rows[-1][0], "058_head")

    def test_fullnet128_skip_addresses_and_no_intermediate_uploads(self):
        root = op_verify.FULLNET_VECTORS.parent / "vessel/128x128/vectors"
        rows = [line.split() for line in (root / "tasks.txt").read_text().splitlines()]
        cases = [op_verify.load_fullnet_case(root, row) for row in rows]
        op_verify.configure_fullnet_cases(root, cases)
        self.assertEqual(len(cases), 59)
        self.assertEqual([len(c["uploads"]) for c in cases], [1] + [0] * 58)
        self.assertEqual(len(cases[0]["uploads"][0][1]), 262144)
        self.assertEqual([(c["ddr_checks"][0]["address"], len(c["ddr_checks"][0]["expected"]))
                          for c in cases if c.get("ddr_checks")],
                         [(0x09a00000, 65536), (0x09800000, 131072), (0x09400000, 262144)])
        self.assertEqual(len(cases[-1]["golden"]), 262144)
        cases[32]["descriptor"] = bytearray(cases[32]["descriptor"])
        cases[32]["descriptor"][20] ^= 32
        with self.assertRaisesRegex(ValueError, "skip address/shape mismatch"):
            op_verify.configure_fullnet_cases(root, cases)

    def test_unaligned_feature_upload_preserves_neighbor_bytes(self):
        # 跨块、单块和 1024B 分片边界均使用真实 upload/read 打包逻辑，RPC 仅访问内存。
        for size in (16, 32, 48, 1056):
            with self.subTest(size=size):
                client, sock = self.client()
                base = 0x03000000
                memory = bytearray(bytes(range(256)) * 8)
                original = bytes(memory)
                payload = bytes((i * 19 + 7) % 256 for i in range(size))

                def rpc(msg, run_id=0, body=b""):
                    address, count, flags = struct.unpack_from("<IHH", body)
                    self.assertEqual(address % 32, 0)
                    start = address - base
                    if msg == READ:
                        self.assertEqual((run_id, flags), (0, 1))
                        return {"data": bytes(memory[start:start + count])}
                    self.assertEqual((msg, flags), (0x20, 0))
                    memory[start:start + count] = body[8:]

                client.rpc = rpc
                op_verify.upload_feature(client, base + 16, payload)
                self.assertEqual(memory, original[:16] + payload + original[16 + size:])
                sock.sendto.assert_not_called()

    def test_decoder_runner_mock_success_and_failure_stops(self):
        root = op_verify.DECODER_VECTORS
        rows = [line.split() for line in (root / "cases_chain.txt").read_text().splitlines()]
        cases = [op_verify.load_case(root, row) for row in rows]
        skip = op_verify.read_hex(root / "encoder_skip.hex", 4096)
        for failure in (None, "golden", "encoder_skip"):
            with self.subTest(failure=failure):
                client = Mock()
                index, released = -1, False

                def run(desc):
                    nonlocal index, released
                    index += 1
                    released = False
                    self.assertEqual(desc[:48], cases[index]["descriptor"][:48])
                    return struct.unpack_from("<I", desc, 48)[0]

                def wait(run_id, timeout):
                    case = cases[index]
                    return dict(op=case["descriptor"][0], format=op_verify.result_format(case["descriptor"]),
                                bytes=len(case["golden"]), mac_bytes=0)

                def rpc(msg, run_id):
                    nonlocal released
                    self.assertEqual(msg, RELEASE)
                    released = True

                def read(run_id, base, size, diagnostic=False):
                    if diagnostic:
                        self.assertTrue(released)
                        self.assertEqual((run_id, base, size), (0, 0x03100000, 4096))
                        expected, kind = skip, "encoder_skip"
                    else:
                        self.assertFalse(released)
                        self.assertEqual(base, struct.unpack_from("<I", cases[index]["descriptor"], 24)[0])
                        expected, kind = cases[index]["golden"], "golden"
                        self.assertEqual(size, len(expected))
                    if failure == kind and index == 1:
                        return expected[:-1] + bytes([expected[-1] ^ 1])
                    return expected

                client.run.side_effect, client.wait.side_effect = run, wait
                client.rpc.side_effect, client.read.side_effect = rpc, read
                with tempfile.TemporaryDirectory() as temp, redirect_stdout(io.StringIO()), \
                        patch("op_verify.OpClient", return_value=client):
                    output = Path(temp) / "result"
                    rc = op_verify.main(["--suite", "decoder", "--case", "vessel_d3_out", "--out", str(output)])
                    report = json.loads((output / "report.json").read_text(encoding="utf-8"))
                    self.assertEqual(rc, int(failure is not None))
                    self.assertEqual(report["verdict"], "FAIL" if failure else "PASS")
                    self.assertEqual(index, 1 if failure else 8)
                    self.assertEqual(len(report["passed"]), 1 if failure else 9)
                    self.assertEqual(client.rpc.call_count, 1 if failure == "golden" else 2 if failure else 9)
                    if failure:
                        self.assertIn(f"/{failure}", report["error"])
                        self.assertEqual(report["active_case"], "vessel_d3_concat")
                    else:
                        self.assertTrue(all(c["encoder_skip_bytes"] == 4096 for c in report["passed"]))
                    evidence = output / ("vessel_d3_concat" if failure else "vessel_d3_out")
                    self.assertTrue((evidence / "golden_actual.bin").exists())
                    if failure != "golden":
                        self.assertTrue((evidence / "encoder_skip_actual.bin").exists())
                self.assertEqual([c.args for c in client.upload.call_args_list], cases[0]["uploads"])
                client.close.assert_called_once()

    def test_mkdc_chain_dependencies_and_uploads(self):
        root = op_verify.MKDC_VECTORS
        rows = [line.split() for line in (root / "cases_all.txt").read_text().splitlines()]
        self.assertEqual(len(op_verify.select_cases(rows, mkdc=True)), 52)
        for model in ("vessel", "airway", "lobe", "tumor"):
            chain = op_verify.select_cases(rows, f"{model}_mid_out", mkdc=True)
            self.assertEqual([r[0] for r in chain], [f"{model}_mid_{stage}" for stage in
                             ("expand", "dw3", "dw5", "mix", "project", "skip", "out")])
            cases = [op_verify.load_case(root, row) for row in chain]
            payload = op_verify.prepare_tumor_params(cases)
            self.assertEqual(bool(payload), model == "tumor")
            # 仅上传初始输入；后续阶段必须消费 FPGA 自己留在 DDR 的结果。
            self.assertEqual([len(c["uploads"]) for c in cases], [1, 0, 0, 0, 0, 0, 0])
            self.assertEqual([op_verify.result_format(c["descriptor"]) for c in cases],
                             [0, 5, 5, 0, 5, 5, 0])
        chain = op_verify.select_cases(rows, "legacy_pw_from_concat_rom_fast")
        self.assertEqual(len(chain), 4)
        with patch("op_verify.OpClient") as client, redirect_stdout(io.StringIO()):
            for case_list in ("cases_chain.txt", "cases_all.txt", "cases_edge.txt"):
                self.assertEqual(op_verify.main(["--suite", "mkdc", "--case-list", case_list,
                                                 "--dry-run"]), 0)
            client.assert_not_called()

    def test_mkdc_runner_end_to_end_without_network(self):
        root = op_verify.MKDC_VECTORS
        rows = [line.split() for line in (root / "cases_chain.txt").read_text().splitlines()]
        cases = [op_verify.load_case(root, row) for row in
                 op_verify.select_cases(rows, "tumor_mid_out", mkdc=True)]
        client = Mock()
        index = -1
        completed = []

        def run(desc):
            nonlocal index
            index += 1
            self.assertEqual(desc[:48], cases[index]["descriptor"][:48])
            return struct.unpack_from("<I", desc, 48)[0]

        def wait(run_id, timeout):
            case = cases[index]
            return dict(op=case["descriptor"][0], format=op_verify.result_format(case["descriptor"]),
                        bytes=len(case["golden"]), mac_bytes=0)

        def read(run_id, base, size):
            case = cases[index]
            self.assertEqual(base, struct.unpack_from("<I", case["descriptor"], 24)[0])
            self.assertEqual(size, len(case["golden"]))
            return case["golden"]

        client.run.side_effect = run
        client.wait.side_effect = wait
        client.read.side_effect = read
        client.rpc.side_effect = lambda msg, run_id: completed.append(msg)
        with tempfile.TemporaryDirectory() as temp, redirect_stdout(io.StringIO()), \
                patch("op_verify.OpClient", return_value=client):
            self.assertEqual(op_verify.main(["--suite", "mkdc", "--case", "tumor_mid_out",
                                             "--out", str(Path(temp) / "result")]), 0)
        self.assertEqual(index, 6)
        self.assertEqual(completed, [RELEASE] * 7)
        self.assertEqual([call.args[0] for call in client.upload.call_args_list],
                         [op_verify.PARAM_DDR_BASE, 0x03000000])
        self.assertEqual(len(client.upload.call_args_list[0].args[1]), 1457216)
        client.close.assert_called_once()

    def test_rpc_filters_crc_peer_identity_and_retries_identically(self):
        client, sock = self.client()
        body = struct.pack("<BBBBIII", 0, 2, 1, 0, 42, 64, 0)
        good = build_frame(RUN | 0x80, 42, 1, body)
        bad = bytearray(good)
        bad[16] ^= 1
        sock.recvfrom.side_effect = [socket.timeout(), (good, ("127.0.0.2", 8080)),
                                    (bytes(bad), client.peer),
                                    (build_frame(RUN | 0x80, 43, 1, body), client.peer),
                                    (build_frame(RUN | 0x80, 42, 2, body), client.peer),
                                    (good, client.peer)]
        self.assertEqual(client.rpc(RUN, 42, bytes(64))["run_id"], 42)
        self.assertEqual(sock.sendto.call_count, 2)
        self.assertEqual(sock.sendto.call_args_list[0], sock.sendto.call_args_list[1])
        sock.bind.assert_called_once_with(("127.0.0.1", 0))

    def test_rpc_status_and_body_identity(self):
        for status, identity, message in ((2, 42, "INVALID"), (0, 43, "identity mismatch")):
            client, sock = self.client()
            body = struct.pack("<BBBBIII", status, 2, 1, 0, identity, 64, 0)
            sock.recvfrom.return_value = (build_frame(RUN | 0x80, 42, 1, body), client.peer)
            with self.assertRaisesRegex(RuntimeError, message):
                client.rpc(RUN, 42)

    def test_diagnostic_read_after_released_run(self):
        client, sock = self.client()
        body = struct.pack("<BBBBIII", 0, 0, 1, 0, 99, 64, 0) + bytes(range(32))
        sock.recvfrom.return_value = (build_frame(READ | 0x80, 0, 1, body), client.peer)
        self.assertEqual(client.read(0, 0x1000000, 31, diagnostic=True), bytes(range(31)))
        frame = parse_frame(sock.sendto.call_args.args[0])
        self.assertEqual(struct.unpack("<IHH", frame.body), (0x1000000, 32, 1))

    def test_write_read_chunking_padding_and_rom_protection(self):
        client, sock = self.client()
        calls = []
        data = bytes(i % 256 for i in range(1057))

        def rpc(msg, run_id=0, body=b""):
            calls.append((msg, run_id, body))
            addr, count, flags = struct.unpack_from("<IHH", body)
            offset = addr - 0x3000000
            return {"data": (data + bytes(31))[offset:offset + count]}

        client.rpc = rpc
        client.upload(0x3000000, data)
        self.assertEqual([len(c[2]) - 8 for c in calls], [1024, 64])
        self.assertEqual(b"".join(c[2][8:] for c in calls), data + bytes(31))
        calls.clear()
        self.assertEqual(client.read(7, 0x3000000, len(data)), data)
        self.assertEqual([struct.unpack("<IHH", c[2]) for c in calls],
                         [(0x3000000, 1024, 0), (0x3000400, 64, 0)])
        for addr in (0x100000, 0xFFFE0, -32, 0x20000000):
            with self.assertRaises(ValueError):
                client.upload(addr, bytes(64))
        sock.sendto.assert_not_called()

    def test_run_case_compares_and_only_releases_on_success(self):
        case = op_verify.load_case(op_verify.VECTORS, ["shuffle16", "64", "0"])
        for failure in (None, "data", "size", "format", "op"):
            client = Mock()
            client.run.side_effect = lambda desc: struct.unpack_from("<I", desc, 48)[0]
            client.wait.return_value = {"bytes": 32 if failure == "size" else 64, "mac_bytes": 0,
                                        "op": 8 if failure == "op" else 7,
                                        "format": 5 if failure == "format" else 0}
            client.read.return_value = bytes(64) if failure == "data" else case["golden"]
            with tempfile.TemporaryDirectory() as temp, redirect_stdout(io.StringIO()):
                if failure:
                    with self.assertRaises((AssertionError, RuntimeError)):
                        op_verify.run_case(client, case, Path(temp), 120)
                    client.rpc.assert_not_called()
                else:
                    result = op_verify.run_case(client, case, Path(temp), 120)
                    client.rpc.assert_called_once_with(RELEASE, result["run_id"])
                    self.assertEqual((Path(temp) / "shuffle16/golden_actual.bin").read_bytes(), case["golden"])


if __name__ == "__main__":
    unittest.main()
