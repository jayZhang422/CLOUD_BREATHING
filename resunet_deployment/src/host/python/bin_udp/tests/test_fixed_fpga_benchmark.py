import hashlib
from argparse import Namespace
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

import fixed_fpga_benchmark as benchmark


class FakeClient:
    def __init__(self, *args, **kwargs):
        pass

    def upload(self, address, data):
        pass

    def run(self, descriptor):
        return struct.unpack_from("<I", descriptor, 48)[0]

    def wait(self, run_id, timeout):
        return dict(op=2, format=0, bytes=16, mac_bytes=0)

    def read(self, run_id, address, size):
        return struct.pack("<8h", 11, 22, 33, 44, 0, 0, 0, 0)

    def performance(self, run_id):
        return {"compute_hz": 125_000_000, "ddr_hz": 333_333_333,
                "cycles": {"total": 100, "load": 20, "run": 70,
                           "output_stall": 3, "memory_stall": 5},
                "seconds": 0.0000008, "ddr_counters": [0] * 8}

    def rpc(self, message, run_id=0):
        return {}

    def close(self):
        pass


class FixedBenchmarkTests(unittest.TestCase):
    def test_hardware_mean_requires_all_repeat_snapshots(self):
        self.assertAlmostEqual(benchmark.mean_hardware_seconds([
            {"hardware_seconds": 0.18}, {"hardware_seconds": 0.19},
            {"hardware_seconds": 0.20}]), 0.19)
        self.assertIsNone(benchmark.mean_hardware_seconds([]))
        self.assertIsNone(benchmark.mean_hardware_seconds([
            {"hardware_seconds": 0.18}, {"hardware_seconds": None}]))

    def test_wait_timeout_keeps_last_board_status(self):
        from src.op_client import OpClient, STATUS
        client = object.__new__(OpClient)
        last_status = dict(run_id=7, state=1, op=11, bytes=4194304)
        with patch.object(client, "rpc", return_value=last_status) as rpc, \
                patch("src.op_client.time.monotonic", side_effect=[0.0, 0.0, 2.0]), \
                patch("src.op_client.time.sleep"):
            with self.assertRaisesRegex(TimeoutError, "run_id=0x00000007.*'op': 11"):
                client.wait(7, timeout=1)
        rpc.assert_called_once_with(STATUS, 7)

    def test_frozen_p4_head_manifest_adapts_length_without_rewriting(self):
        from src.op_client import descriptor
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = bytes(16)
            (root/"input.bin").write_bytes(payload)
            desc = descriptor(1,1,width=2,height=2,cin=3,cout=1,int16=True,weights=0x00100000,params=0x00100400)
            manifest = {"format":1,"task":"vessel","input":{"path":"input.bin","bytes":16,"sha256":benchmark.sha256_bytes(payload)},
                        "output":{"bytes":32,"channels":1,"side":2},
                        "stages":[{"name":"head","bytes":32,"descriptor_hex":desc.hex()}]}
            path = root/"manifest.json"
            original = json.dumps(manifest)
            path.write_text(original,encoding="utf-8")
            adapted,_,_ = benchmark.load_manifest(path)
            self.assertEqual(adapted["stages"][0]["bytes"],64)
            self.assertEqual(adapted["output"]["bytes"],64)
            self.assertEqual(adapted["stages"][0]["descriptor_hex"],desc.hex())
            self.assertEqual(path.read_text(encoding="utf-8"),original)
            wire = b"".join(struct.pack("<8h",v,0,0,0,0,0,0,0) for v in (-100,0,12,32767))
            self.assertEqual(benchmark.decode_head(wire,1,2),struct.pack("<4h",-100,0,12,32767))

    def test_residual_plans_keep_frozen_arithmetic_and_nonoverlapping_lifetimes(self):
        from src.fullnet import NetworkPlan, coefficient_image

        image = coefficient_image()
        frozen_path = benchmark.HERE / "output/ct_01/fixed_benchmark/lobe_slices_68_136_204/fused_residual.json"
        for task in benchmark.MODEL_TASKS:
            plan = NetworkPlan(task, image, fuse_up_concat=False)
            original = {stage["name"]: stage for stage in plan.stages}
            benchmark.fuse_residual_plan(plan)
            self.assertEqual(len(plan.stages), 31)
            self.assertEqual(sum(stage["op"] == 12 for stage in plan.stages), 7)
            self.assertEqual({stage["op"] for stage in plan.stages}, {1, 2, 5, 10, 11, 12})
            for index, stage in enumerate(plan.stages):
                live = [t for t in plan.tensors.values() if t["produced"] <= index <= t["last"]]
                for i, a in enumerate(live):
                    self.assertEqual(a["address"] % 32, 0)
                    self.assertLessEqual(a["address"] + a["bytes"], 0x20000000)
                    for b in live[i + 1:]:
                        self.assertFalse(a["address"] < b["address"] + b["bytes"] and
                                         b["address"] < a["address"] + a["bytes"], (task, stage["name"]))
                desc = stage["descriptor"]
                if stage["op"] == 12:
                    block = stage["name"].rsplit(".", 1)[0]
                    project, skip = (original[block + suffix] for suffix in (".project", ".skip"))
                    self.assertEqual(desc[32:36], project["descriptor"][32:36])
                    self.assertEqual(desc[28:32], skip["descriptor"][32:36])
                    self.assertEqual(desc[36:40], original[stage["name"]]["descriptor"][36:40])
                    self.assertEqual(struct.unpack_from("<H", desc, 56)[0], skip["kwargs"]["cin"])
                    self.assertEqual(stage["kwargs"]["cin"], project["kwargs"]["cin"])
                if stage["op"] == 5:
                    # Bypass the RTL's old lobe-address compatibility remapping.
                    self.assertGreaterEqual(struct.unpack_from("<I", desc, 20)[0], 0x1E000000)
            if task == "lobe" and frozen_path.exists():
                frozen = json.loads(frozen_path.read_text(encoding="utf-8"))
                for stage, expected in zip(plan.stages, frozen["stages"]):
                    self.assertEqual((stage["name"], stage["op"], stage["bytes"]),
                                     (expected["name"], expected["op"], expected["bytes"]))
                    actual_desc, frozen_desc = bytearray(stage["descriptor"]), bytearray.fromhex(expected["descriptor_hex"])
                    for start, end in ((16, 28), (48, 52)):
                        actual_desc[start:end] = frozen_desc[start:end] = bytes(end - start)
                    self.assertEqual(actual_desc, frozen_desc, stage["name"])

    def test_four_model_suite_repeats_averages_and_rejects_changed_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            case = Path(directory)
            folder = case / "fixed_benchmark/all_models_fused_residual"
            folder.mkdir(parents=True)
            payload = bytes(range(16))
            (folder / "input.bin").write_bytes(payload)
            for task in benchmark.MODEL_TASKS:
                manifest = {
                    "format": 1, "profile": "fused_residual", "task": task,
                    "inputs": [{"slice": 1, "path": "input.bin", "address": 0x10000000,
                                "bytes": len(payload), "sha256": benchmark.sha256_bytes(payload)}],
                    "parameters": None,
                    "output": {"address": 0x01000000, "bytes": 16, "channels": 1, "side": 1},
                    "stages": [{"name": "head", "op": 2, "format": 0, "bytes": 16,
                                "descriptor_hex": bytes(64).hex()}],
                }
                (folder / f"{task}.json").write_text(json.dumps(manifest), encoding="utf-8")
            args = Namespace(case_dir=case, tasks=list(benchmark.MODEL_TASKS), slice=None,
                             host="127.0.0.1", port=8080, bind="127.0.0.1", timeout=1,
                             run_timeout=1, repeat=3, report=case / "report.json", dry_run=False)
            with patch.object(benchmark, "OpClient", FakeClient), \
                    patch.object(benchmark, "reset_session"), \
                    patch.object(benchmark, "freeze", side_effect=AssertionError("must reuse frozen files")), \
                    redirect_stdout(io.StringIO()):
                self.assertEqual(benchmark.suite(args), 0)
                report = json.loads(args.report.read_text(encoding="utf-8"))
                self.assertEqual(len(report["models"]), 4)
                for summary, model in zip(report["per_model"], report["models"]):
                    self.assertEqual(summary["repeats"], 3)
                    self.assertFalse(summary["golden_verified"])
                    self.assertEqual(model["runs"][0]["stages"][0]["hardware"]["cycles"]["total"], 100)
                    self.assertEqual(model["runs"][0]["hardware_seconds"], 0.0000008)
                    self.assertAlmostEqual(summary["mean_hardware_seconds"], 0.0000008)
                    self.assertAlmostEqual(model["per_slice"][0]["mean_hardware_seconds"], 0.0000008)
                    for key in ("upload_seconds", "fpga_run_seconds", "download_seconds", "wall_seconds"):
                        self.assertEqual(summary["mean_" + key], sum(row[key] for row in model["runs"]) / 3)
                with patch.object(FakeClient, "read", side_effect=[struct.pack("<8h", 11, 22, 33, 44, 0, 0, 0, 0),
                                                                  struct.pack("<8h", 12, 22, 33, 44, 0, 0, 0, 0)]):
                    failed = benchmark.run_manifest(args, folder / "vessel.json")
                self.assertEqual(failed["status"], "failed")
                self.assertIn("output changed between repeats", failed["error"])
                with patch.object(FakeClient, "wait", side_effect=TimeoutError("test drain deadline")):
                    failed = benchmark.run_manifest(args, folder / "vessel.json")
                self.assertEqual(failed["active"]["phase"], "wait")
                self.assertEqual(failed["active"]["stage"], "head")
                self.assertEqual(failed["active"]["op"], 2)
                self.assertGreater(failed["active"]["run_id"], 0)
                args.dry_run = True
                with patch.object(benchmark, "OpClient", side_effect=AssertionError("dry-run opened socket")):
                    self.assertEqual(benchmark.suite(args), 0)

    def test_frozen_run_decodes_and_checks_golden_without_planner(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = bytes(range(16))
            (root / "input.bin").write_bytes(payload)
            expected = struct.pack("<h", 11)
            manifest = {
                "format": 1,
                "profile": "test",
                "task": "lobe",
                "input": {"path": "input.bin", "address": 0x10000000,
                          "bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()},
                "parameters": None,
                "output": {"address": 0x01000000, "bytes": 16, "channels": 1, "side": 1,
                           "golden_sha256": hashlib.sha256(expected).hexdigest()},
                "stages": [{"name": "head", "op": 2, "format": 0, "bytes": 16,
                            "descriptor_hex": bytes(64).hex()}],
            }
            manifest_path = root / "manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            with patch.object(benchmark, "OpClient", FakeClient), \
                    patch.object(benchmark, "reset_session"):
                report = benchmark.run_manifest(
                    type("Args", (), {"host": "127.0.0.1", "port": 8080,
                                      "timeout": 1.0, "bind": "127.0.0.1",
                                      "repeat": 1, "run_timeout": 1.0})(),
                    manifest_path)

            self.assertEqual(report["status"], "complete")
            self.assertEqual(report["runs"][0]["output_sha256"], hashlib.sha256(expected).hexdigest())
            self.assertEqual(report["runs"][0]["stages"][0]["name"], "head")

            # Older firmware may reject diagnostics; inference and Golden checks
            # still complete, with an explicit unavailable hardware measurement.
            for error in (RuntimeError("diagnostics unsupported"), TimeoutError("timeout")):
                with self.subTest(error=type(error).__name__), \
                        patch.object(benchmark, "OpClient", FakeClient), \
                        patch.object(benchmark, "reset_session"), \
                        patch.object(FakeClient, "performance", side_effect=error), \
                        redirect_stdout(io.StringIO()):
                    fallback = benchmark.run_manifest(
                        type("Args", (), {"host": "127.0.0.1", "port": 8080,
                                          "timeout": 1.0, "bind": "127.0.0.1",
                                          "repeat": 1, "run_timeout": 1.0})(), manifest_path)
                self.assertEqual(fallback["status"], "complete")
                self.assertTrue(fallback["runs"][0]["golden_verified"])
                self.assertIsNone(fallback["runs"][0]["hardware_seconds"])
                self.assertIsNone(fallback["per_slice"][0]["mean_hardware_seconds"])
                self.assertIsNone(fallback["runs"][0]["stages"][0]["hardware"])

            manifest["stages"] *= 3
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            events = []

            class RecordingClient(FakeClient):
                def rpc(self, message, run_id=0):
                    events.append(("release", run_id))
                    return {}

                def performance(self, run_id):
                    events.append(("perf", run_id))
                    return super().performance(run_id)

            with patch.object(benchmark, "OpClient", RecordingClient), \
                    patch.object(benchmark, "reset_session"), \
                    patch.object(benchmark.secrets, "randbits", side_effect=[1, 65, 2, 3]), \
                    redirect_stdout(io.StringIO()):
                collision = benchmark.run_manifest(
                    type("Args", (), {"host": "127.0.0.1", "port": 8080,
                                      "timeout": 1.0, "bind": "127.0.0.1",
                                      "repeat": 1, "run_timeout": 1.0})(), manifest_path)
            self.assertEqual(collision["status"], "complete")
            self.assertEqual(events, [(kind, identity) for kind in ("release", "perf")
                                      for identity in (1, 2, 3)])

    def test_slice_set_repeats_and_averages_each_slice(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            inputs = []
            for index in (68, 136, 204):
                payload = bytes([index & 0xFF]) * 16
                name = f"input_z{index}.bin"
                (root / name).write_bytes(payload)
                inputs.append({"slice": index, "path": name, "address": 0x10000000,
                               "bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()})
            manifest = {
                "format": 1,
                "profile": "test",
                "task": "lobe",
                "inputs": inputs,
                "parameters": None,
                "output": {"address": 0x01000000, "bytes": 16, "channels": 1, "side": 1},
                "stages": [{"name": "head", "op": 2, "format": 0, "bytes": 16,
                            "descriptor_hex": bytes(64).hex()}],
            }
            manifest_path = root / "manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            with patch.object(benchmark, "OpClient", FakeClient), \
                    patch.object(benchmark, "reset_session"):
                report = benchmark.run_manifest(
                    type("Args", (), {"host": "127.0.0.1", "port": 8080,
                                      "timeout": 1.0, "bind": "127.0.0.1",
                                      "repeat": 3, "run_timeout": 1.0})(),
                    manifest_path)

            self.assertEqual(report["status"], "complete")
            self.assertEqual(len(report["runs"]), 9)
            self.assertEqual([row["repeats"] for row in report["per_slice"]], [3, 3, 3])
            self.assertEqual([row["slice"] for row in report["per_slice"]], [68, 136, 204])


if __name__ == "__main__":
    unittest.main()
