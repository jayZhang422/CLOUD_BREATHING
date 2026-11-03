"""Header-only inventory; does not decompress NIfTI voxel arrays."""

import csv
import json
from collections import Counter
from pathlib import Path

import nibabel as nib
import numpy as np


ROOT = Path("/root/autodl-tmp/datasets")
LOBES = (
    "lung_upper_lobe_left", "lung_lower_lobe_left",
    "lung_upper_lobe_right", "lung_middle_lobe_right", "lung_lower_lobe_right",
)


def summary(cases):
    voxels = sum(int(np.prod(case[1].shape)) for case in cases)
    return {
        "cases": len(cases),
        "xy_shapes": dict(Counter(f"{img.shape[0]}x{img.shape[1]}" for _, img in cases)),
        "z_total": sum(img.shape[2] for _, img in cases),
        "q8_plus_u8_native_gib": voxels * 2 / 2**30,
        "q8_plus_u8_512_gib": sum(img.shape[2] for _, img in cases) * 512 * 512 * 2 / 2**30,
        "ct_dtypes": dict(Counter(str(img.get_data_dtype()) for _, img in cases)),
        "axis_codes": dict(Counter("".join(nib.aff2axcodes(img.affine)) for _, img in cases)),
    }


output = {}
atm_cases = []
atm_names = []
atm_errors = []
atm_batches = {}
for batch in sorted((ROOT / "ATM22").glob("TrainBatch*")):
    images = sorted((batch / "imagesTr").glob("*.nii*"))
    atm_batches[batch.name] = len(images)
    for path in images:
        stem = path.name.removesuffix(".nii.gz").removesuffix(".nii").removesuffix("_0000")
        label_path = batch / "labelsTr" / f"{stem}_0000.nii.gz"
        image = nib.load(path)
        atm_cases.append((str(path), image))
        atm_names.append(stem)
        if not label_path.exists():
            atm_errors.append({"case": stem, "error": "missing_label"})
            continue
        label = nib.load(label_path)
        if image.shape != label.shape or not np.allclose(image.affine, label.affine, atol=1e-4):
            atm_errors.append({"case": stem, "error": "shape_or_affine"})
output["atm22"] = summary(atm_cases)
output["atm22"].update({
    "batches": atm_batches,
    "duplicate_patient_names": [name for name, count in Counter(atm_names).items() if count > 1],
    "error_counts": dict(Counter(x["error"] for x in atm_errors)),
    "error_examples": atm_errors[:10],
})

total_root = ROOT / "TotalSegmentator" / "Totalsegmentator_dataset"
total_cases = []
complete = []
errors = []
missing_counts = Counter()
for path in sorted(total_root.glob("s*/ct.nii.gz")):
    image = nib.load(path)
    total_cases.append((str(path), image))
    valid = True
    for lobe in LOBES:
        label_path = path.parent / "segmentations" / f"{lobe}.nii.gz"
        if not label_path.exists():
            missing_counts[lobe] += 1
            valid = False
            continue
        label = nib.load(label_path)
        if image.shape != label.shape or not np.allclose(image.affine, label.affine, atol=1e-4):
            errors.append({"case": path.parent.name, "label": lobe, "error": "shape_or_affine"})
            valid = False
    if valid:
        complete.append((str(path), image))
output["totalsegmentator"] = summary(total_cases)
output["totalsegmentator"].update({
    "five_lobes_complete": summary(complete),
    "missing_lobe_file_counts": dict(missing_counts),
    "error_counts": dict(Counter(x["error"] for x in errors)),
    "error_examples": errors[:10],
})
meta = total_root / "meta.csv"
if meta.exists():
    with meta.open(newline="") as stream:
        reader = csv.DictReader(stream, delimiter=";")
        rows = list(reader)
    output["totalsegmentator"]["meta_fields"] = reader.fieldnames
    output["totalsegmentator"]["meta_rows"] = len(rows)
    output["totalsegmentator"]["meta_first_row"] = rows[0] if rows else {}
print(json.dumps(output, indent=2))
