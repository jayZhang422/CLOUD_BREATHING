"""仅本地文件和合成 CT；不连接 FPGA，不依赖 Model 工程。"""
import tempfile
import unittest
from pathlib import Path

import numpy as np
from scipy import ndimage

from main import demo_prediction
from pc_fpga.ct.convert import quantize_hu
from pc_fpga.ct.prediction_io import CHANNELS, file_sha256, read_prediction, write_packed_prediction
from pc_fpga.files import write_json
from pc_fpga.mesh.branch_repair import repair_branches
from pc_fpga.mesh.pipeline import load_ct
from pc_fpga.mesh.stages import bin_to_stl, process_meshes


def ct_case(case):
    demo_prediction(case)
    prediction, contract = read_prediction(case / "prediction")
    labels = np.array(prediction)
    del prediction
    # 软组织外壳包住低 HU 肺区；气道断口位于可桥接的低 HU 区。
    hu = np.full(labels.shape, -1000., dtype=np.float32)
    hu[:, 2:-2, 2:-2] = 0
    hu[:, 3:-3, 3:-3] = -700
    # 血管、肿瘤和附近断口为软组织；不改变 CT→BIN 实现。
    tissue = ndimage.binary_dilation((labels & (64 | 128 | 256)) != 0, iterations=2)
    hu[tissue] = 40
    labels[16, 39, 39] |= 1  # 远处单体素肺叶孤岛，应从派生掩膜移除。
    folder = case / "input"
    folder.mkdir()
    path = folder / "ct_volume_int8.bin"
    quantize_hu(hu).tofile(path)
    metadata = dict(affine_z_y_x_to_lps_mm=contract["affine_z_y_x_to_lps_mm"],
                    model_input=dict(file=path.name, dtype="int8", layout="Z,Y,X", shape=list(labels.shape),
                                     hu_clip=[-1024., 1000.], sha256=file_sha256(path)))
    write_json(folder / "metadata.json", metadata)
    contract = write_packed_prediction(case / "prediction", labels,
        np.asarray(contract["affine_z_y_x_to_lps_mm"]), dict(input_sha256=file_sha256(path)))
    return contract


class ModelMeshChecks(unittest.TestCase):
    def test_ct_repair_structure_smoothing_and_input_immutable(self):
        with tempfile.TemporaryDirectory() as temp:
            case = Path(temp)
            contract = ct_case(case)
            inputs = [case / "prediction" / contract["file"], case / "input/ct_volume_int8.bin"]
            hashes = [file_sha256(p) for p in inputs]
            raw = bin_to_stl(case / "prediction", case / "raw")
            self.assertFalse(raw["synthetic_mask_only"])
            self.assertEqual(np.load(case / "raw/masks/LeftUpperLobe.npy")[16, 39, 39], 0)
            self.assertGreater(raw["objects"][0]["raw_voxels"], raw["objects"][0]["voxels"])
            smoothed = process_meshes(case / "raw", case / "smooth", "Smooth")
            self.assertEqual([e["name"] for e in smoothed["objects"]], CHANNELS)
            for i, entry in enumerate(smoothed["objects"]):
                self.assertEqual(entry["after"]["boundary_nonmanifold_edges"], 0)
                if i < 5:
                    self.assertEqual(entry["smoothing"]["surface_smoothing_iterations"], 60)
                    self.assertLessEqual(entry["smoothing"]["measured_maximum_move_mm"], 2.500001)
                else:
                    self.assertFalse(entry["smoothing"]["reduction_applied"])
                if i in (6, 7):
                    vessel = entry["vessel_smoothing"]
                    self.assertLessEqual(max(abs(v) for v in vessel["component_volume_changes_percent"]), 5.)
                    self.assertEqual(vessel["supported_skeleton_samples"], vessel["retained_skeleton_samples"])
            self.assertEqual([file_sha256(p) for p in inputs], hashes)

    def test_wrong_ct_identity_grid_and_mask_tampering_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            case = Path(temp)
            contract = ct_case(case)
            bad = {**contract, "provenance": {"input_sha256": "0" * 64}}
            with self.assertRaisesRegex(ValueError, "SHA256"):
                load_ct(case / "prediction", bad, (32, 64, 64))
            with self.assertRaisesRegex(ValueError, "网格"):
                load_ct(case / "prediction", contract, (31, 64, 64))
            bin_to_stl(case / "prediction", case / "raw")
            (case / "raw/masks/Bronchus.npy").write_bytes(b"invalid")
            with self.assertRaisesRegex(ValueError, "SHA256"):
                process_meshes(case / "raw", case / "smooth", "Smooth")
            self.assertFalse((case / "smooth/manifest.json").exists())

    def test_bridging_requires_ct_supported_path(self):
        mask = np.zeros((24, 24, 24), bool)
        mask[8:16, 8:16, 3:9] = True
        mask[8:16, 8:16, 12:18] = True
        repaired, rejected, info = repair_branches(mask, np.ones_like(mask), np.ones(3))
        self.assertEqual(ndimage.label(repaired)[1], 1)
        self.assertGreater(len(info["accepted_bridges"]), 0)
        blocked, rejected, info = repair_branches(mask, mask.copy(), np.ones(3))
        self.assertFalse(info["accepted_bridges"])
        self.assertTrue(rejected.any())
        self.assertFalse((blocked & ~mask).any())

    def test_all_empty_prediction_publishes_no_stl(self):
        with tempfile.TemporaryDirectory() as temp:
            case = Path(temp)
            contract = ct_case(case)
            write_packed_prediction(case / "prediction", np.zeros((32, 64, 64), np.uint16),
                np.asarray(contract["affine_z_y_x_to_lps_mm"]), contract["provenance"])
            bin_to_stl(case / "prediction", case / "raw")
            process_meshes(case / "raw", case / "smooth", "Smooth")
            cut = process_meshes(case / "smooth", case / "cut", "Cut")
            self.assertTrue(all(e["status"] == "empty_prediction" for e in cut["objects"]))
            self.assertFalse(list((case / "cut").rglob("*.stl")))

    def test_explicit_reference_selects_prediction_without_copying_reference_voxels(self):
        with tempfile.TemporaryDirectory() as temp:
            case = Path(temp)
            contract = ct_case(case)
            support = np.zeros((32, 64, 64), bool)
            # 参考存在而预测不存在的位置，不得生成肿瘤；不回退到最大候选。
            support[4:8, 4:8, 4:8] = True
            np.savez_compressed(case / "reference.npz", LungTumor=support)
            report = bin_to_stl(case / "prediction", case / "raw", reference_support=case / "reference.npz")
            tumor = report["objects"][8]
            self.assertGreater(tumor["raw_voxels"], 0)
            self.assertEqual(tumor["voxels"], 0)
            self.assertEqual(tumor["status"], "empty_prediction")
            self.assertTrue(tumor["repair"]["reference_supported_component_selection"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
