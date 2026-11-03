#!/usr/bin/env python3
"""Train the compact-cache 2.5D ResUNet with an FPGA-oriented mkdc block.

The script intentionally consumes only verified cache files.  It never creates
or rewrites a cache, and it keeps the cache's signed-INT8/direct-float32
contract intact.
"""

from __future__ import annotations

import argparse
import csv
import fcntl
import hashlib
import json
import os
import random
import shutil
import subprocess
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

from compact_cache_reader import CompactCase

SEED = 20261001
LOBES = ["lung_upper_lobe_left", "lung_lower_lobe_left", "lung_upper_lobe_right",
         "lung_middle_lobe_right", "lung_lower_lobe_right"]
CONTRACT = {
    "dtype": "signed int8",
    "shape": "[Z,3,512,512]",
    "channels": "[z-1,z,z+1]",
    "boundary": "repeat edge",
    "hu_clip": [-1024, 1000],
    "round": "NumPy rint nearest-even",
    "training_cast": "direct float32",
    "target": "center slice",
}


class Cache:
    def __init__(self, root: Path, task: str):
        self.root = root
        self.task = task
        self.meta = json.loads((root / "metadata.json").read_text())
        verification_name = "verification.json" if task == "totalsegmentator" else "final_verification.json"
        verification = json.loads((root / verification_name).read_text())
        if not verification.get("passed"):
            raise RuntimeError(f"{root}: existing cache verification is not PASS")
        for key, value in CONTRACT.items():
            if self.meta["input_contract"].get(key) != value:
                raise RuntimeError(f"{root}: frozen input contract mismatch at {key}")
        self.rows = {row["case"]: row for row in self.meta["cases"]}
        self.target_names = list(self.meta["cases"][0]["target_names"])
        if task == "totalsegmentator" and self.target_names != LOBES:
            raise RuntimeError("Unexpected lobe class order")
        if len(self.rows) != len(self.meta["cases"]) or any(
                row["target_names"] != self.target_names for row in self.rows.values()):
            raise RuntimeError("Duplicate case ID or inconsistent class order")
        self.cases: dict[str, CompactCase] = {}

    def open_case(self, case_id: str) -> CompactCase:
        if case_id not in self.cases:
            self.cases.clear()  # Only the current case is needed; release old memmaps and packed labels.
            self.cases[case_id] = CompactCase(self.root / "cases" / case_id)
        return self.cases[case_id]

    def split(self) -> dict[str, list[str]]:
        if self.task == "totalsegmentator":
            result = {"train": [], "val": [], "test": []}
            for case_id, row in self.rows.items():
                name = row.get("official_metadata", {}).get("split")
                if name not in result:
                    raise RuntimeError(f"{case_id}: missing official TotalSegmentator split")
                result[name].append(case_id)
            return {key: sorted(value) for key, value in result.items()}
        if self.task == "hipas":
            split = json.loads((self.root / "patient_split.json").read_text())
            result = {"train": sorted(split["train"]), "val": sorted(split["validation"]),
                      "test": sorted(split["test"])}
            quarantined = set(split["quarantined"])
            if set(sum(result.values(), [])) & quarantined:
                raise RuntimeError("HiPaS quarantined case entered a split")
            return result
        ids = sorted(self.rows)
        shuffled = ids[:]
        random.Random(SEED).shuffle(shuffled)
        n_train = int(len(ids) * 0.70)
        n_val = int(len(ids) * 0.15)
        return {"train": sorted(shuffled[:n_train]), "val": sorted(shuffled[n_train:n_train + n_val]),
                "test": sorted(shuffled[n_train + n_val:])}

    def positive_slices(self, case_id: str) -> np.ndarray:
        row = self.rows[case_id]
        values = row["positive_slices_per_target"]
        return np.asarray(sorted({z for slices in values for z in slices}), dtype=np.int64)

    def read_batch(self, case_id: str, indices: list[int], augment: bool, rng: random.Random):
        case = self.open_case(case_id)
        xs, ys, masks = [], [], []
        for z in indices:
            x, y, valid = case.read_sample(int(z))
            # Lobe reflections need affine-aware left/right label swaps; keep native axes for this baseline.
            if augment and self.task != "totalsegmentator" and rng.random() < 0.5:
                x, y, valid = x[:, :, ::-1], y[:, :, ::-1], valid[:, :, ::-1]
            if augment and self.task != "totalsegmentator" and rng.random() < 0.5:
                x, y, valid = x[:, ::-1, :], y[:, ::-1, :], valid[:, ::-1, :]
            xs.append(np.ascontiguousarray(x))
            ys.append(np.ascontiguousarray(y.astype(np.float32)))
            masks.append(np.ascontiguousarray(valid.astype(np.float32)))
        return np.stack(xs), np.stack(ys), np.stack(masks)


class Block(nn.Module):
    def __init__(self, in_ch: int, out_ch: int):
        super().__init__()
        self.body = nn.Sequential(
            nn.Conv2d(in_ch, out_ch, 3, padding=1, bias=False),
            nn.BatchNorm2d(out_ch), nn.ReLU(inplace=True),
            nn.Conv2d(out_ch, out_ch, 3, padding=1, bias=False),
            nn.BatchNorm2d(out_ch),
        )
        self.skip = nn.Identity() if in_ch == out_ch else nn.Sequential(
            nn.Conv2d(in_ch, out_ch, 1, bias=False), nn.BatchNorm2d(out_ch))

    def forward(self, x):
        return F.relu(self.body(x) + self.skip(x), inplace=True)


class MKDCBlock(nn.Module):
    """Parallel depthwise 3x3/5x5 branches with pointwise mixing."""

    def __init__(self, in_ch: int, out_ch: int):
        super().__init__()
        self.expand = nn.Sequential(
            nn.Conv2d(in_ch, out_ch, 1, bias=False),
            nn.BatchNorm2d(out_ch),
            nn.ReLU6(inplace=True),
        )
        self.k3 = nn.Conv2d(out_ch, out_ch, 3, padding=1, groups=out_ch, bias=False)
        self.k5 = nn.Conv2d(out_ch, out_ch, 5, padding=2, groups=out_ch, bias=False)
        self.project = nn.Sequential(
            nn.BatchNorm2d(out_ch),
            nn.ReLU6(inplace=True),
            nn.Conv2d(out_ch, out_ch, 1, bias=False),
            nn.BatchNorm2d(out_ch),
        )
        self.skip = nn.Identity() if in_ch == out_ch else nn.Sequential(
            nn.Conv2d(in_ch, out_ch, 1, bias=False), nn.BatchNorm2d(out_ch)
        )

    @staticmethod
    def channel_shuffle(x):
        b, c, h, w = x.shape
        if c % 2:
            return x
        return x.reshape(b, 2, c // 2, h, w).transpose(1, 2).reshape(b, c, h, w)

    def forward(self, x):
        y = self.expand(x)
        y = self.channel_shuffle(self.k3(y) + self.k5(y))
        return F.relu6(self.project(y) + self.skip(x), inplace=True)


class ResUNet(nn.Module):
    def __init__(self, out_channels: int, base: int = 16, op: str = "mkdc"):
        super().__init__()
        c = [base, base * 2, base * 4, base * 8]
        block = MKDCBlock if op == "mkdc" else Block
        self.e1, self.e2, self.e3, self.mid = block(3, c[0]), block(c[0], c[1]), block(c[1], c[2]), block(c[2], c[3])
        self.pool = nn.MaxPool2d(2)
        self.d3, self.d2, self.d1 = block(c[3] + c[2], c[2]), block(c[2] + c[1], c[1]), block(c[1] + c[0], c[0])
        self.head = nn.Conv2d(c[0], out_channels, 1)

    def forward(self, x):
        e1 = self.e1(x)
        e2 = self.e2(self.pool(e1))
        e3 = self.e3(self.pool(e2))
        y = self.mid(self.pool(e3))
        y = self.d3(torch.cat((F.interpolate(y, size=e3.shape[-2:], mode="nearest"), e3), 1))
        y = self.d2(torch.cat((F.interpolate(y, size=e2.shape[-2:], mode="nearest"), e2), 1))
        y = self.d1(torch.cat((F.interpolate(y, size=e1.shape[-2:], mode="nearest"), e1), 1))
        return self.head(y)


def seed_all(seed: int):
    random.seed(seed); np.random.seed(seed); torch.manual_seed(seed)
    if torch.cuda.is_available(): torch.cuda.manual_seed_all(seed)


def choose_indices(cache: Cache, case_id: str, rng: np.random.Generator, max_pos: int, max_neg: int):
    zdim = cache.rows[case_id]["shape_h_w_z"][2]
    pos = cache.positive_slices(case_id)
    all_z = np.arange(zdim, dtype=np.int64)
    neg = np.setdiff1d(all_z, pos, assume_unique=True)
    if len(pos) > max_pos: pos = np.sort(rng.choice(pos, max_pos, replace=False))
    if len(neg) > max_neg: neg = np.sort(rng.choice(neg, max_neg, replace=False))
    # Keep selected slices in z order so each case is read mostly sequentially from q.npy.
    values = np.sort(np.concatenate((pos, neg)))
    return values.astype(int).tolist()


def masked_loss(logits, target, valid):
    target = target.float(); valid = valid.float()
    mask = valid.expand_as(target)
    positive = (target * mask).sum((0, 2, 3))
    negative = ((1.0 - target) * mask).sum((0, 2, 3))
    pos_weight = (negative / (positive + 1.0)).clamp(1.0, 20.0)
    bce = F.binary_cross_entropy_with_logits(logits.float(), target, pos_weight=pos_weight.view(1, -1, 1, 1), reduction="none")
    bce = (bce * mask).sum() / mask.sum().clamp_min(1.0)
    prob = torch.sigmoid(logits.float()) * mask
    inter = (prob * target).sum((0, 2, 3))
    denom = prob.sum((0, 2, 3)) + (target * mask).sum((0, 2, 3))
    dice = (1.0 - (2.0 * inter + 1.0) / (denom + 1.0)).mean()
    return 0.5 * bce + 0.5 * dice


def stats(tp, fp, fn):
    denom = 2 * tp + fp + fn
    return {"dice": float(2 * tp / denom) if denom else 1.0,
            "precision": float(tp / (tp + fp)) if tp + fp else None,
            "recall": float(tp / (tp + fn)) if tp + fn else None,
            "tp": int(tp), "fp": int(fp), "fn": int(fn)}


def batch_counts(logits, target, valid, native_valid):
    """Threshold logits at zero (= sigmoid 0.5); union includes lobe-overlap voxels."""
    pred, truth = logits.float() >= 0.0, target.bool()
    p, t = pred & valid.bool(), truth & valid.bool()
    counts = torch.stack(((p & t).sum((0, 2, 3)), (p & ~t).sum((0, 2, 3)),
                          (~p & t).sum((0, 2, 3))), 1)
    positive = t.any(dim=-1).any(dim=-1)
    hits = (p & t).any(dim=-1).any(dim=-1)
    layer_counts = torch.stack((positive.sum(0), hits.sum(0)), 1)
    pu, tu = pred.any(1) & native_valid, truth.any(1) & native_valid
    union = torch.stack(((pu & tu).sum(), (pu & ~tu).sum(), (~pu & tu).sum()))
    union_layers = torch.stack((tu.any(-1).any(-1).sum(),
                                (pu & tu).any(-1).any(-1).sum()))
    overlap = ((pred.sum(1) > 1) & native_valid).sum()
    return tuple(a.cpu().numpy() for a in (counts, layer_counts, union, union_layers, overlap))


def layer_stats(positive, hits):
    return {"positive_layers": int(positive), "hit_positive_layers": int(hits),
            "positive_layer_recall": float(hits / positive) if positive else None}


def validate(net, cache: Cache, case_ids: list[str], device, batch_size: int, amp: bool):
    net.eval(); k = len(cache.target_names)
    totals = np.zeros((k, 3), dtype=np.int64); union = np.zeros(3, dtype=np.int64)
    layers = np.zeros((k, 2), dtype=np.int64); union_layers = np.zeros(2, dtype=np.int64)
    rows = []
    total_loss = total_slices = 0
    with torch.inference_mode():
        for case_id in case_ids:
            source = cache.rows[case_id]; case = cache.open_case(case_id)
            zdim = case.zdim
            native_valid = torch.zeros((1, 512, 512), dtype=torch.bool, device=device)
            native_valid[(0,) + case.region] = True
            case_totals = np.zeros((k, 3), dtype=np.int64)
            case_layers = np.zeros((k, 2), dtype=np.int64)
            case_union = np.zeros(3, dtype=np.int64); case_union_layers = np.zeros(2, dtype=np.int64)
            overlap = 0
            for start in range(0, zdim, batch_size):
                zs = list(range(start, min(start + batch_size, zdim)))
                xb, yb, vb = cache.read_batch(case_id, zs, False, random.Random(0))
                xt, yt, vt = torch.from_numpy(xb).to(device), torch.from_numpy(yb).to(device), torch.from_numpy(vb).to(device)
                with torch.autocast(device_type="cuda", dtype=torch.float16, enabled=amp): logits = net(xt)
                loss = masked_loss(logits, yt, vt)
                total_loss += float(loss) * len(zs); total_slices += len(zs)
                a, b, u, ul, o = batch_counts(logits, yt, vt, native_valid)
                case_totals += a; case_layers += b; case_union += u; case_union_layers += ul; overlap += int(o)
            totals += case_totals; layers += case_layers; union += case_union; union_layers += case_union_layers
            rows.append({"case": case_id, "complete_lung_candidate": bool(source.get("lung_coverage", {}).get("complete_lung_candidate", False)),
                         "empty_label": not bool(sum(source["label_voxels"])), "predicted_overlap_voxels": overlap,
                         "shape_h_w_z": source["shape_h_w_z"], "spacing_xyz_mm": source.get("spacing_xyz_mm"),
                         "affine": source.get("affine"), "lung_coverage": source.get("lung_coverage", {}),
                         "classes": [{"name": cache.target_names[c], **stats(*case_totals[c]),
                                      **layer_stats(*case_layers[c])} for c in range(k)],
                         "union": {**stats(*case_union), **layer_stats(*case_union_layers)}})
    summary = {"classes": [{"name": cache.target_names[c], **stats(*totals[c]), **layer_stats(*layers[c]),
                            "mean_case_dice_present_only": float(np.mean([r["classes"][c]["dice"] for r in rows
                                if r["classes"][c]["tp"] + r["classes"][c]["fn"]]))
                            if any(r["classes"][c]["tp"] + r["classes"][c]["fn"] for r in rows) else None} for c in range(k)],
               "union": {**stats(*union), **layer_stats(*union_layers)}, "loss": total_loss / max(1, total_slices),
               "case_count": len(case_ids), "cases": rows}
    summary["complete_lung_candidates"] = sum(r["complete_lung_candidate"] for r in rows)
    summary["groups"] = {}
    for name, group in (("complete_lung_candidate_pending_visual_review", [r for r in rows if r["complete_lung_candidate"]]),
                        ("partial_or_truncated_positive", [r for r in rows if not r["complete_lung_candidate"] and not r["empty_label"]]),
                        ("empty_label", [r for r in rows if r["empty_label"]])):
        counts = [sum(r["union"][key] for r in group) for key in ("tp", "fp", "fn")]
        summary["groups"][name] = {"case_count": len(group), **stats(*counts),
            "mean_case_dice": float(np.mean([r["union"]["dice"] for r in group])) if group else None}
    return summary


def atomic_json(path: Path, value):
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")
    os.replace(tmp, path)


def atomic_torch(path: Path, value):
    tmp = path.with_suffix(".pt.tmp")
    with tmp.open("wb") as f: torch.save(value, f); f.flush(); os.fsync(f.fileno())
    os.replace(tmp, path)


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resources(path: Path):
    line = subprocess.check_output(["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total", "--format=csv,noheader,nounits"], text=True).strip().splitlines()[0]
    util, used, total = [int(x.strip()) for x in line.split(",")]
    return {"gpu_utilization_percent": util, "gpu_memory_used_mib": used, "gpu_memory_total_mib": total, "disk_free_gib": shutil.disk_usage(path).free / 1024 ** 3}


def write_csv(path: Path, rows):
    if not rows: return
    with path.open("w", newline="") as f:
        keys = list(rows[0])
        writer = csv.DictWriter(f, fieldnames=keys); writer.writeheader(); writer.writerows(rows)


def make_config(args, cache: Cache, split):
    return {"version": "compact_mkdc_v1", "task": args.task, "model": "engineering_2.5d_resunet_mkdc", "op": args.op, "base": args.base,
            "target_names": cache.target_names, "architecture": {"channels": [args.base, args.base * 2, args.base * 4, args.base * 8], "encoder_stages": 3,
                "block": "1x1 pointwise expansion; parallel depthwise 3x3/5x5 sum; channel shuffle; 1x1 pointwise projection; residual projection; ReLU6",
                "downsample": "MaxPool2d(2)", "upsample": "nearest 2x", "head": f"1x1 Conv, {len(cache.target_names)} independent logits"},
            "epochs": args.epochs, "batch_size": args.batch_size, "learning_rate": args.lr, "seed": SEED, "amp": True,
            "input_contract": cache.meta["input_contract"], "sampling": {"positive_layer_aware": True, "max_positive_slices_per_case_epoch": args.max_pos, "max_negative_slices_per_case_epoch": args.max_neg},
            "loss": "masked 0.5 class-balanced BCE + 0.5 per-class soft Dice; overlap-invalid voxels ignored by verified cache valid mask",
            "augmentation": "native-axis flips disabled for TotalSegmentator lobes because left/right class swaps require affine-aware relabeling; enabled for single-class/axis-neutral tasks",
            "split": split, "cache_root": str(cache.root), "metadata_sha256": hashlib.sha256((cache.root / "metadata.json").read_bytes()).hexdigest(),
            "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "quarantined_policy": "HiPaS quarantined cases excluded; other tasks use their saved/official split"}


def self_test(cache: Cache, run_dir: Path, config):
    split = config["split"]; case_id = next(cid for cid in split["train"] if len(cache.positive_slices(cid)))
    pos = int(cache.positive_slices(case_id)[0]); neg = next((z for z in range(cache.rows[case_id]["shape_h_w_z"][2]) if z not in set(cache.positive_slices(case_id))), pos)
    xb, yb, vb = cache.read_batch(case_id, [pos, neg], False, random.Random(0))
    assert xb.dtype == np.float32 and xb.shape == (2, 3, 512, 512)
    assert yb.shape == (2, len(cache.target_names), 512, 512) and vb.shape == (2, 1, 512, 512)
    device = torch.device("cuda"); net = ResUNet(len(cache.target_names), config["base"], config["op"]).to(device); opt = torch.optim.Adam(net.parameters(), config["learning_rate"])
    scaler = torch.cuda.amp.GradScaler(enabled=True, init_scale=32768); xt, yt, vt = map(lambda a: torch.from_numpy(a).to(device), (xb, yb, vb))
    with torch.autocast(device_type="cuda", dtype=torch.float16): loss = masked_loss(net(xt), yt, vt)
    assert torch.isfinite(loss); scaler.scale(loss).backward(); scaler.step(opt); scaler.update()
    state = {"model": net.state_dict(), "optimizer": opt.state_dict(), "scaler": scaler.state_dict()}; atomic_torch(run_dir / "smoke_checkpoint.pt", state)
    restored = ResUNet(len(cache.target_names), config["base"], config["op"]).to(device); restored.load_state_dict(torch.load(run_dir / "smoke_checkpoint.pt", map_location=device, weights_only=False)["model"])
    with torch.no_grad():
        assert torch.equal(net(xt), restored(xt))
    result = {"status": "PASS", "task": config["task"], "gpu": torch.cuda.get_device_name(0), "input_shape": list(xb.shape), "stored_dtype": "int8", "reader_dtype": str(xb.dtype), "amp": True, "loss": float(loss), "forward_backward_optimizer_checkpoint_restore": "PASS", "case": case_id, "positive_slice": pos, "negative_slice": neg, "resources": resources(run_dir)}
    atomic_json(run_dir / "smoke_check.json", result); print(json.dumps(result), flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["self-test", "train"]); ap.add_argument("--task", choices=["totalsegmentator", "atm22", "hipas"], required=True)
    ap.add_argument("--op", choices=["mkdc", "standard"], default="mkdc")
    ap.add_argument("--data-root", type=Path, required=True); ap.add_argument("--run-dir", type=Path, required=True); ap.add_argument("--epochs", type=int, default=20)
    ap.add_argument("--batch-size", type=int, default=16); ap.add_argument("--base", type=int, default=16); ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--max-pos", type=int, default=64); ap.add_argument("--max-neg", type=int, default=64); ap.add_argument("--resume", action="store_true")
    args = ap.parse_args()
    if not torch.cuda.is_available(): raise RuntimeError("CUDA is required")
    if min(args.epochs, args.batch_size, args.base, args.max_pos, args.max_neg) < 1 or args.lr <= 0: raise ValueError("invalid configuration")
    cache = Cache(args.data_root, args.task); split = cache.split(); config = make_config(args, cache, split); args.run_dir.mkdir(parents=True, exist_ok=True)
    lock = (args.run_dir / "training.lock").open("a"); fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB); seed_all(SEED); torch.set_num_threads(8); torch.backends.cudnn.deterministic = True; torch.backends.cudnn.benchmark = False
    if args.mode == "self-test":
        if (args.run_dir / "smoke_check.json").exists(): raise FileExistsError("smoke run already exists")
        self_test(cache, args.run_dir, config); return
    cfg = args.run_dir / "config.json"
    if cfg.exists() and json.loads(cfg.read_text()) != config: raise RuntimeError("config mismatch; use a new run directory")
    if not args.resume and cfg.exists(): raise FileExistsError("existing run requires --resume")
    if not cfg.exists():
        atomic_json(cfg, config); atomic_json(args.run_dir / "patient_split.json", split); (args.run_dir / "source").mkdir(exist_ok=True); shutil.copy2(__file__, args.run_dir / "source" / Path(__file__).name)
    for name in ("checkpoints", "epoch_records", "reports", "best_records"): (args.run_dir / name).mkdir(exist_ok=True)
    device = torch.device("cuda"); net = ResUNet(len(cache.target_names), args.base, args.op).to(device); opt = torch.optim.Adam(net.parameters(), lr=args.lr); scaler = torch.cuda.amp.GradScaler(enabled=True, init_scale=32768)
    start, best = 1, -1.0
    if args.resume:
        state = torch.load(args.run_dir / "last.pt", map_location="cpu", weights_only=False); net.load_state_dict(state["model"]); opt.load_state_dict(state["optimizer"]); scaler.load_state_dict(state["scaler"]); start, best = state["epoch"] + 1, state["best"]
    atomic_json(args.run_dir / "runtime.json", {"torch": torch.__version__, "cuda": torch.version.cuda, "gpu": torch.cuda.get_device_name(0), "amp": True, "resources": resources(args.run_dir)})
    train_ids, val_ids, test_ids = split["train"], split["val"], split["test"]
    control_path = args.run_dir / "next_epoch_control.json"
    control_history = args.run_dir / "control_history.jsonl"
    for epoch in range(start, args.epochs + 1):
        # A separate monitor may tune only sampling budgets between epochs.
        # The model, loss, cache contract, and patient split remain fixed.
        if control_path.exists():
            try:
                control = json.loads(control_path.read_text())
                if int(control.get("epoch", epoch)) == epoch:
                    args.max_pos = max(1, int(control.get("max_pos", args.max_pos)))
                    args.max_neg = max(1, int(control.get("max_neg", args.max_neg)))
                    with control_history.open("a") as f:
                        f.write(json.dumps({"epoch": epoch, "applied": control}, ensure_ascii=False) + "\n")
                    control_path.unlink()
            except (OSError, ValueError, TypeError, json.JSONDecodeError):
                pass
        t0 = time.time(); net.train(); rng = np.random.default_rng(SEED + epoch * 1009); order = train_ids[:]; random.Random(SEED + epoch).shuffle(order); loss_sum = n_seen = 0
        for case_id in order:
            indices = choose_indices(cache, case_id, rng, args.max_pos, args.max_neg)
            for start_i in range(0, len(indices), args.batch_size):
                xb, yb, vb = cache.read_batch(case_id, indices[start_i:start_i + args.batch_size], True, random.Random(SEED + epoch + start_i)); xt, yt, vt = map(lambda a: torch.from_numpy(a).to(device), (xb, yb, vb)); opt.zero_grad(set_to_none=True)
                with torch.autocast(device_type="cuda", dtype=torch.float16): loss = masked_loss(net(xt), yt, vt)
                if not torch.isfinite(loss): raise FloatingPointError(f"nonfinite loss in {case_id}")
                scaler.scale(loss).backward(); scaler.step(opt); scaler.update(); loss_sum += float(loss) * len(xb); n_seen += len(xb)
        val = validate(net, cache, val_ids, device, args.batch_size, True); score = float(val["union"]["dice"]); improved = score > best; best = max(best, score); record = {"epoch": epoch, "train_loss": loss_sum / max(1, n_seen), "validation": val, "validation_union_dice": score, "best_validation_union_dice": best, "epoch_seconds": time.time() - t0, "train_samples": n_seen, "resources": resources(args.run_dir)}
        atomic_json(args.run_dir / "epoch_records" / f"epoch_{epoch:04d}.json", record); atomic_torch(args.run_dir / "checkpoints" / f"epoch_{epoch:04d}.pt", {"epoch": epoch, "best": best, "model": net.state_dict(), "optimizer": opt.state_dict(), "scaler": scaler.state_dict(), "config": config}); shutil.copy2(args.run_dir / "checkpoints" / f"epoch_{epoch:04d}.pt", args.run_dir / "last.pt");
        if improved:
            best_path = args.run_dir / "checkpoints" / f"epoch_{epoch:04d}.pt"
            shutil.copy2(best_path, args.run_dir / "best.pt")
            shutil.copy2(best_path, args.run_dir / "best_records" / f"best_epoch_{epoch:04d}.pt")
            atomic_json(args.run_dir / "best_parameters.json", {"best_epoch": epoch, "validation_union_dice": score,
                "checkpoint": str(args.run_dir / "best.pt"), "immutable_checkpoint": str(args.run_dir / "best_records" / f"best_epoch_{epoch:04d}.pt"),
                "checkpoint_sha256": sha256_file(best_path), "config": config})
        atomic_json(args.run_dir / "status.json", {"state": "training", "completed_epoch": epoch, "total_epochs": args.epochs, "best_union_dice": best,
            "next_epoch": epoch + 1, "next_epoch_control": str(control_path),
            "sampling": {"max_pos": args.max_pos, "max_neg": args.max_neg}})
        if epoch % 20 == 0 or epoch == args.epochs: atomic_json(args.run_dir / "reports" / f"epoch_{epoch:04d}.json", record); print(json.dumps({"epoch": epoch, "best_union_dice": best, "current_union_dice": score, "seconds": record["epoch_seconds"]}), flush=True)
    best_state = torch.load(args.run_dir / "best.pt", map_location=device, weights_only=False); net.load_state_dict(best_state["model"]); final = {"best_epoch": best_state["epoch"], "best_validation_union_dice": best_state["best"], "config": config, "validation": validate(net, cache, val_ids, device, args.batch_size, True), "test": validate(net, cache, test_ids, device, args.batch_size, True), "resources": resources(args.run_dir)}; atomic_json(args.run_dir / "final_results.json", final); write_csv(args.run_dir / "per_case_validation.csv", [{"case": x["case"], "union_dice": x["union"]["dice"], "complete_lung_candidate": x["complete_lung_candidate"]} for x in final["validation"]["cases"]]); write_csv(args.run_dir / "per_case_test.csv", [{"case": x["case"], "union_dice": x["union"]["dice"], "complete_lung_candidate": x["complete_lung_candidate"]} for x in final["test"]["cases"]]); atomic_json(args.run_dir / "best_parameters.json", {"best_epoch": best_state["epoch"], "validation_union_dice": best_state["best"], "checkpoint": str(args.run_dir / "best.pt"), "immutable_checkpoint": str(args.run_dir / "best_records" / f"best_epoch_{best_state['epoch']:04d}.pt"), "checkpoint_sha256": sha256_file(args.run_dir / "best.pt"), "config": config, "validation": final["validation"]["union"], "test": final["test"]["union"]}); atomic_json(args.run_dir / "status.json", {"state": "complete", "completed_epoch": args.epochs, "total_epochs": args.epochs, "best_epoch": best_state["epoch"], "best_union_dice": best_state["best"]}); print(json.dumps({"state": "complete", "best_epoch": best_state["epoch"], "results": str(args.run_dir / "final_results.json")}), flush=True)


if __name__ == "__main__": main()
