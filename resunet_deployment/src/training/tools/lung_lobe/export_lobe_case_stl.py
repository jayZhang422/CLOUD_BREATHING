#!/usr/bin/env python3
"""Run one trained mkdc lobe model case and export affine-aware STL meshes."""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import sys
from pathlib import Path

import numpy as np
import torch
from skimage.measure import marching_cubes
import trimesh


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--train-dir", type=Path, required=True)
    parser.add_argument("--cache-root", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--case", default="", help="Case ID; empty selects a deterministic random complete candidate.")
    parser.add_argument("--seed", type=int, default=20261004)
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--cpu", action="store_true")
    return parser.parse_args()


def stats(pred: np.ndarray, truth: np.ndarray) -> dict:
    p = pred.astype(bool)
    t = truth.astype(bool)
    tp = int(np.count_nonzero(p & t))
    fp = int(np.count_nonzero(p & ~t))
    fn = int(np.count_nonzero(~p & t))
    denom = 2 * tp + fp + fn
    return {
        "predicted_voxels": int(p.sum()),
        "truth_voxels": int(t.sum()),
        "tp": tp,
        "fp": fp,
        "fn": fn,
        "dice": float(2 * tp / denom) if denom else 1.0,
        "precision": float(tp / (tp + fp)) if tp + fp else None,
        "recall": float(tp / (tp + fn)) if tp + fn else None,
        "positive_layers": int(t.any(axis=(1, 2)).sum()),
        "predicted_positive_layers": int(p.any(axis=(1, 2)).sum()),
        "positive_layer_recall": float((p & t).any(axis=(1, 2)).sum() / t.any(axis=(1, 2)).sum())
        if t.any(axis=(1, 2)).sum() else None,
    }


def export_mesh(mask_zhw: np.ndarray, affine: np.ndarray, path: Path) -> dict:
    """Export a native [Z,H,W] mask after restoring [H,W,Z] affine axes."""
    volume = np.pad(mask_zhw.transpose(1, 2, 0).astype(np.uint8), 1, mode="constant")
    if not np.any(volume):
        return {"path": str(path), "voxels": 0, "vertices": 0, "faces": 0, "status": "empty"}
    vertices, faces, normals, values = marching_cubes(volume, level=0.5, spacing=(1.0, 1.0, 1.0))
    vertices -= 1.0
    world = vertices @ affine[:3, :3].T + affine[:3, 3]
    mesh = trimesh.Trimesh(vertices=world, faces=faces, process=False)
    mesh.export(path)
    return {
        "path": str(path),
        "voxels": int(mask_zhw.sum()),
        "vertices": int(len(mesh.vertices)),
        "faces": int(len(mesh.faces)),
        "status": "ok",
    }


def main() -> None:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    train_dir = args.train_dir.resolve()
    shared_dir = train_dir.parents[1] / "shared"
    for import_dir in (shared_dir, train_dir):
        if str(import_dir) not in sys.path:
            sys.path.insert(0, str(import_dir))
    from compact_cache_reader import CompactCase
    from train_compact_mkdc_v1 import ResUNet

    metadata = json.loads((args.cache_root / "metadata.json").read_text(encoding="utf-8"))
    rows = {row["case"]: row for row in metadata["cases"]}
    candidates = [
        row["case"]
        for row in metadata["cases"]
        if row.get("lung_coverage", {}).get("complete_lung_candidate")
        and row.get("lung_coverage", {}).get("all_five_lobes_nonempty")
    ]
    if not candidates:
        raise RuntimeError("No complete five-lobe visualization candidate found")
    case_id = args.case or random.Random(args.seed).choice(sorted(candidates))
    if case_id not in rows:
        raise KeyError(f"Unknown case: {case_id}")
    row = rows[case_id]
    target_names = list(row["target_names"])
    case = CompactCase(args.cache_root / "cases" / case_id)
    config = json.loads((args.checkpoint.parent / "config.json").read_text(encoding="utf-8"))
    device = torch.device("cpu" if args.cpu or not torch.cuda.is_available() else "cuda")
    checkpoint = torch.load(args.checkpoint, map_location=device, weights_only=False)
    base = int(checkpoint.get("config", config).get("base", 16))
    net = ResUNet(len(target_names), base=base, op="mkdc").to(device)
    net.load_state_dict(checkpoint["model"])
    net.eval()

    zdim, h, w = case.zdim, case.h, case.w
    predicted = np.zeros((len(target_names), zdim, h, w), dtype=np.uint8)
    with torch.inference_mode():
        for start in range(0, zdim, args.batch_size):
            zs = list(range(start, min(start + args.batch_size, zdim)))
            xb = np.stack([case.read_sample(z)[0] for z in zs]).astype(np.float32, copy=False)
            xt = torch.from_numpy(xb).to(device)
            with torch.autocast(device_type="cuda", dtype=torch.float16, enabled=device.type == "cuda"):
                logits = net(xt)
            y = (logits.float() >= 0.0).cpu().numpy().astype(np.uint8)
            h0, h1 = case.region[0].start, case.region[0].stop
            w0, w1 = case.region[1].start, case.region[1].stop
            predicted[:, zs] = y[:, :, h0:h1, w0:w1].transpose(1, 0, 2, 3)

    truth = np.zeros_like(predicted)
    for z in range(zdim):
        y = case.read_sample(z, float32=False)[1]
        truth[:, z] = y[:, case.region[0], case.region[1]]
    affine = np.asarray(row["affine"], dtype=np.float64)
    mesh_rows = []
    for index, name in enumerate(target_names):
        mesh_rows.append(export_mesh(predicted[index], affine, args.output_dir / f"{case_id}_{name}_pred.stl"))
    combined = np.any(predicted.astype(bool), axis=0).astype(np.uint8)
    mesh_rows.append(export_mesh(combined, affine, args.output_dir / f"{case_id}_all_lobes_pred.stl"))

    np.savez_compressed(args.output_dir / f"{case_id}_pred_native.npz", predicted=predicted, truth=truth)
    report = {
        "status": "PASS",
        "case": case_id,
        "case_selection_seed": args.seed,
        "candidate_count": len(candidates),
        "checkpoint": str(args.checkpoint),
        "checkpoint_sha256": hashlib.sha256(args.checkpoint.read_bytes()).hexdigest(),
        "checkpoint_epoch": checkpoint.get("epoch"),
        "model": checkpoint.get("config", config),
        "device": str(device),
        "input_shape": [zdim, 3, 512, 512],
        "native_shape_h_w_z": [h, w, zdim],
        "spacing_xyz_mm": row.get("spacing_xyz_mm"),
        "affine": row.get("affine"),
        "target_names": target_names,
        "source_metadata": row.get("official_metadata"),
        "lung_coverage": row.get("lung_coverage"),
        "per_lobe": {name: stats(predicted[i], truth[i]) for i, name in enumerate(target_names)},
        "meshes": mesh_rows,
        "output_dir": str(args.output_dir),
    }
    (args.output_dir / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, ensure_ascii=True), flush=True)


if __name__ == "__main__":
    main()
