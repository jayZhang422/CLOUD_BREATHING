#!/usr/bin/env python3
"""Fine-tune the existing mkdc tumour model with the proven Task06 recipe."""

import argparse
import csv
import fcntl
import hashlib
import importlib.util
import json
import os
import random
import shutil
import statistics
import subprocess
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F

from task06_cache_reader_v2 import Task06Case
from task06_tumor_loss_v3 import loss_value
from tumor_model import ResUNet

SEED = 20261001
TRAIN_CASES = [
    "lung_001", "lung_003", "lung_004", "lung_005", "lung_006", "lung_009",
    "lung_010", "lung_015", "lung_016", "lung_018", "lung_020", "lung_022",
    "lung_023", "lung_025", "lung_027", "lung_028", "lung_029", "lung_031",
    "lung_034", "lung_036", "lung_038", "lung_042", "lung_043", "lung_044",
    "lung_045", "lung_046", "lung_047", "lung_048", "lung_051", "lung_053",
    "lung_054", "lung_058", "lung_061", "lung_062", "lung_064", "lung_065",
    "lung_069", "lung_070", "lung_071", "lung_073", "lung_075", "lung_080",
    "lung_081", "lung_083", "lung_084", "lung_086", "lung_092", "lung_093",
    "lung_095", "lung_096",
]
VAL_CASES = ["lung_014", "lung_041", "lung_049", "lung_055", "lung_057", "lung_059", "lung_066", "lung_074", "lung_078", "lung_079"]
TEST_CASES = ["lung_026", "lung_033", "lung_037"]


class Task06Cache:
    def __init__(self, root):
        self.root = Path(root)
        self.metadata = json.loads((self.root / "metadata.json").read_text())
        verification = json.loads((self.root / "verification.json").read_text())
        if not verification["passed"] or verification["checked_cases"] != 63:
            raise RuntimeError("Existing Task06 verification is not PASS for 63 cases")
        self.input_contract = self.metadata["input_contract"]
        expected = {"dtype": "signed int8", "shape": "[N,3,512,512]", "channels": "[z-1,z,z+1]",
                    "boundary": "repeat edge", "hu_clip": [-1024, 1000], "round": "NumPy rint nearest-even",
                    "training_cast": "direct float32", "target": "center slice"}
        if self.input_contract != expected or not self.metadata["all_slices"]:
            raise RuntimeError("Frozen input contract mismatch")
        self.case_metadata = {m["case"]: m for m in self.metadata["cases"]}
        self.case_ids = sorted(self.case_metadata)
        if len(self.case_ids) != 63 or set(self.case_ids) != set(TRAIN_CASES + VAL_CASES + TEST_CASES):
            raise RuntimeError("Patient split/cache mismatch")
        with (self.root / "per_case_verification.csv").open(newline="") as f:
            rows = list(csv.DictReader(f))
        if len(rows) != 63 or {r["case"] for r in rows} != set(self.case_ids) or any(r["status"] != "PASS" for r in rows):
            raise RuntimeError("Existing per-case verification is not PASS")
        self.open_cases = {}

    def open_case(self, case_id):
        if case_id not in self.open_cases:
            self.open_cases[case_id] = Task06Case(self.root, self.case_metadata[case_id])
        return self.open_cases[case_id]

    def read_sample(self, case_id, z):
        x, y = self.open_case(case_id).read_sample(z)
        return x, y.astype(np.float32)


class Net(ResUNet):
    def __init__(self, base=16):
        super().__init__(out_channels=1, base=base)


def load_initial(net, config):
    path = Path(config["initial_checkpoint"])
    if hashlib.sha256(path.read_bytes()).hexdigest() != config["initial_checkpoint_sha256"]:
        raise RuntimeError("Initial checkpoint changed")
    state = torch.load(path, map_location="cpu", weights_only=False)
    net.load_state_dict(state["model"], strict=True)
    return state["epoch"]


def load_teacher(config):
    if not config.get("teacher_checkpoint"):
        return None
    source = Path(__file__).with_name("teacher_resunet.py")
    assert hashlib.sha256(source.read_bytes()).hexdigest() == config["teacher_source_sha256"]
    path = Path(config["teacher_checkpoint"])
    assert hashlib.sha256(path.read_bytes()).hexdigest() == config["teacher_checkpoint_sha256"]
    spec = importlib.util.spec_from_file_location("teacher_resunet", source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    teacher = module.Net(config["base"]).cuda()
    teacher.load_state_dict(torch.load(path, map_location="cpu", weights_only=False)["model"], strict=True)
    teacher.requires_grad_(False)
    return teacher.eval()


def training_loss(logits, target, teacher, inputs):
    supervised = loss_value(logits, target)
    if teacher is None:
        return supervised
    with torch.no_grad(), torch.autocast(device_type="cuda", enabled=False):
        teacher_logits = teacher(inputs.float())
        soft_target = (teacher_logits / 2.0).sigmoid()
        foreground = (target > 0) | (teacher_logits >= 0)
    # Balance tumour/background regions so sparse teacher foreground is retained.
    soft_bce = F.binary_cross_entropy_with_logits(logits.float() / 2.0, soft_target, reduction="none")
    if foreground.any() and (~foreground).any():
        kd = 0.5 * soft_bce[foreground].mean() + 0.5 * soft_bce[~foreground].mean()
    else:
        kd = soft_bce.mean()
    return supervised + 0.25 * (2.0 ** 2) * kd


def epoch_lr(initial_lr, epoch, epochs):
    progress = (epoch - 1) / max(1, epochs - 1)
    return initial_lr * (0.01 + 0.99 * (1 + np.cos(np.pi * progress)) / 2)


def seed_all(seed):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


def checkpoint_state(epoch, best_dice, net, opt, scaler, config, best_epoch=0):
    return {
        "epoch": epoch,
        "best_dice": best_dice,
        "best_epoch": best_epoch,
        "model": net.state_dict(),
        "optimizer": opt.state_dict(),
        "scaler": scaler.state_dict(),
        "config": config,
        "python_random_state": random.getstate(),
        "numpy_random_state": np.random.get_state(),
        "torch_random_state": torch.get_rng_state(),
        "torch_cuda_random_state": torch.cuda.get_rng_state_all() if torch.cuda.is_available() else None,
    }


def restore_random_state(state):
    random.setstate(state["python_random_state"])
    np.random.set_state(state["numpy_random_state"])
    torch.set_rng_state(state["torch_random_state"])
    if torch.cuda.is_available() and state.get("torch_cuda_random_state") is not None:
        torch.cuda.set_rng_state_all(state["torch_cuda_random_state"])


def sample_indices(cache, case_id, epoch, seed):
    meta = cache.case_metadata[case_id]
    pos = np.asarray(meta["positive_slices"], dtype=np.int64)
    neg = np.asarray(meta["negative_slices"], dtype=np.int64)
    rng = np.random.default_rng(seed + epoch * 1009 + int(case_id.split("_")[-1]))
    chosen_neg = rng.choice(neg, size=min(len(pos), len(neg)), replace=False) if len(neg) else np.empty(0, dtype=np.int64)
    indices = np.concatenate((pos, chosen_neg))
    rng.shuffle(indices)
    return indices.tolist()


def batch_arrays(cache, case_id, indices, augment, rng):
    xs, ys = [], []
    for z in indices:
        x, y = cache.read_sample(case_id, z)
        if augment and rng.random() < 0.5:
            x = x[:, :, ::-1]
            y = y[:, :, ::-1]
        if augment and rng.random() < 0.5:
            x = x[:, ::-1, :]
            y = y[:, ::-1, :]
        xs.append(np.ascontiguousarray(x))
        ys.append(np.ascontiguousarray(y))
    return np.stack(xs), np.stack(ys)


def metrics(tp, fp, fn):
    dice = 2.0 * tp / (2.0 * tp + fp + fn) if tp + fp + fn else 1.0
    precision = tp / max(1.0, tp + fp)
    recall = tp / max(1.0, tp + fn)
    return dice, precision, recall


def validate(net, cache, cases, device, batch_size, amp):
    net.eval()
    total_loss = 0.0
    total_n = 0
    total_tp = total_fp = total_fn = 0.0
    rows = []
    with torch.inference_mode():
        for case_id in cases:
            zdim = cache.case_metadata[case_id]["shape"][2]
            tp = fp = fn = 0.0
            positive_layers = hit_layers = empty_layers = 0
            for start in range(0, zdim, batch_size):
                zs = list(range(start, min(start + batch_size, zdim)))
                xb, yb = batch_arrays(cache, case_id, zs, False, random.Random(0))
                xt = torch.from_numpy(xb).to(device, non_blocking=True)
                yt = torch.from_numpy(yb).to(device, non_blocking=True)
                with torch.autocast(device_type="cuda", dtype=torch.float16, enabled=amp):
                    logits = net(xt)
                    loss = loss_value(logits, yt)
                if not torch.isfinite(loss): raise FloatingPointError(f"Nonfinite validation loss: {case_id}")
                total_loss += float(loss) * len(zs)
                total_n += len(zs)
                pred = (logits >= 0).cpu().numpy()
                target = yb.astype(bool)
                for i in range(len(zs)):
                    p = pred[i, 0]
                    t = target[i, 0]
                    p_sum, t_sum = int(p.sum()), int(t.sum())
                    if t_sum:
                        positive_layers += 1
                        hit_layers += int(np.logical_and(p, t).any())
                    else:
                        empty_layers += 1
                    tp += float(np.logical_and(p, t).sum())
                    fp += float(np.logical_and(p, ~t).sum())
                    fn += float(np.logical_and(~p, t).sum())
            d, pr, rc = metrics(tp, fp, fn)
            layer_recall = hit_layers / max(1, positive_layers)
            rows.append({"case": case_id, "dice": d, "precision": pr, "recall": rc, "tp": int(tp), "fp": int(fp), "fn": int(fn),
                         "positive_layer_recall": layer_recall, "positive_layers": positive_layers,
                         "hit_positive_layers": hit_layers, "empty_label_layers": empty_layers, "effective_slices": zdim,
                         "empty_label_case": positive_layers == 0})
            total_tp += tp
            total_fp += fp
            total_fn += fn
    d, pr, rc = metrics(total_tp, total_fp, total_fn)
    return {"loss": total_loss / max(1, total_n), "dice": d, "precision": pr, "recall": rc,
            "positive_layer_recall": sum(r["hit_positive_layers"] for r in rows) / max(1, sum(r["positive_layers"] for r in rows)),
            "empty_label_cases": sum(r["positive_layers"] == 0 for r in rows),
            "case_dice_min": min(r["dice"] for r in rows), "case_dice_median": statistics.median(r["dice"] for r in rows),
            "case_dice_max": max(r["dice"] for r in rows), "case_count": len(rows), "cases": rows}


def atomic_json(path, value):
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w") as f:
        json.dump(value, f, indent=2, allow_nan=False)
        f.write("\n")
        f.flush(); os.fsync(f.fileno())
    os.replace(tmp, path)


def atomic_checkpoint(path, state):
    tmp = path.with_suffix(".pt.tmp")
    with tmp.open("wb") as f:
        torch.save(state, f)
        f.flush(); os.fsync(f.fileno())
    os.replace(tmp, path)


def checkpoint_alias(source, destination):
    tmp = destination.with_suffix(".pt.tmp")
    if tmp.exists(): tmp.unlink()
    os.link(source, tmp)
    os.replace(tmp, destination)


def resources(run_dir):
    output = subprocess.check_output([
        "nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total",
        "--format=csv,noheader,nounits"], text=True).strip().splitlines()[0]
    utilization, used, total = [int(v.strip()) for v in output.split(",")]
    return {"gpu_utilization_percent": utilization, "gpu_memory_used_mib": used,
            "gpu_memory_total_mib": total, "disk_free_gib": shutil.disk_usage(run_dir).free / 1024 ** 3}


def write_csv(path, rows):
    if not rows: return
    tmp = path.with_suffix(".csv.tmp")
    with tmp.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys())
        writer.writeheader(); writer.writerows(rows)
        f.flush(); os.fsync(f.fileno())
    os.replace(tmp, path)


def update_history(run_dir, epoch):
    records = [json.loads((run_dir / "epoch_records" / f"epoch_{i:04d}.json").read_text()) for i in range(1, epoch + 1)]
    write_csv(run_dir / "epochs.csv", [r["row"] for r in records])
    write_csv(run_dir / "validation_per_case.csv", [{"epoch": r["row"]["epoch"], **c} for r in records for c in r["validation"]["cases"]])
    return records


def self_test(data_root, run_dir, config):
    cache = Task06Cache(data_root)
    for case_id in TRAIN_CASES:
        zs = sample_indices(cache, case_id, 1, config["seed"])
        meta = cache.case_metadata[case_id]
        assert zs and len(zs) == len(set(zs))
        assert set(zs) & set(meta["positive_slices"]) == set(meta["positive_slices"])
        assert len(zs) == len(meta["positive_slices"]) + min(len(meta["positive_slices"]), len(meta["negative_slices"]))
    horizon = config.get("schedule_epochs", config["epochs"])
    lrs = [epoch_lr(config["learning_rate"], e, horizon) for e in range(1, horizon + 1)]
    assert np.isclose(lrs[0], config["learning_rate"]) and np.isclose(lrs[-1], config["learning_rate"] * 0.01)
    assert all(a >= b for a, b in zip(lrs, lrs[1:]))
    case_id = cache.case_ids[0]
    representative = cache.open_case(case_id).check_representative()
    z = cache.case_metadata[case_id]["positive_slices"][0]
    neg = cache.case_metadata[case_id]["negative_slices"][0]
    zs = [z, neg] * (config["batch_size"] // 2)
    if config["batch_size"] % 2: zs.append(z)
    x, y = batch_arrays(cache, case_id, zs, False, random.Random(0))
    assert x.shape == (config["batch_size"], 3, 512, 512) and x.dtype == np.float32
    assert y.shape == (config["batch_size"], 1, 512, 512) and y.dtype == np.float32
    assert np.isfinite(x).all() and y.sum() > 0
    device = torch.device("cuda")
    net = Net(config["base"]).to(device)
    initial_epoch = load_initial(net, config)
    teacher = load_teacher(config)
    teacher_before = {k: v.detach().clone() for k, v in teacher.state_dict().items()} if teacher else {}
    opt = torch.optim.Adam(net.parameters(), config["learning_rate"])
    scaler = torch.cuda.amp.GradScaler(enabled=True, init_scale=1024)
    xt, yt = torch.from_numpy(x).to(device), torch.from_numpy(y).to(device)
    before = net.head.weight.detach().clone()
    opt.zero_grad(set_to_none=True)
    with torch.autocast(device_type="cuda", dtype=torch.float16):
        logits = net(xt)
        assert logits.dtype == torch.float16
        loss = training_loss(logits, yt, teacher, xt)
    assert torch.isfinite(loss)
    scaler.scale(loss).backward()
    scaler.unscale_(opt)
    assert all(p.grad is None or torch.isfinite(p.grad).all() for p in net.parameters())
    scaler.step(opt); scaler.update()
    assert opt.state and not torch.equal(before, net.head.weight)
    p = run_dir / "smoke_checkpoint.pt"
    atomic_checkpoint(p, checkpoint_state(0, -1.0, net, opt, scaler, config))
    expected_rng = (random.random(), np.random.rand(), torch.rand(1).item(), torch.rand(1, device=device).item())
    restored_net = Net(config["base"]).to(device)
    restored_opt = torch.optim.Adam(restored_net.parameters(), config["learning_rate"])
    restored_scaler = torch.cuda.amp.GradScaler(enabled=True, init_scale=1024)
    state = torch.load(p, map_location="cpu", weights_only=False)
    restored_net.load_state_dict(state["model"])
    restored_opt.load_state_dict(state["optimizer"])
    restored_scaler.load_state_dict(state["scaler"])
    restore_random_state(state)
    actual_rng = (random.random(), np.random.rand(), torch.rand(1).item(), torch.rand(1, device=device).item())
    assert expected_rng == actual_rng
    assert restored_scaler.state_dict() == scaler.state_dict()
    assert restored_opt.param_groups[0]["lr"] == opt.param_groups[0]["lr"]
    net.eval(); restored_net.eval()
    with torch.no_grad(): assert torch.equal(net(xt), restored_net(xt))
    restored_net.train()
    restored_opt.zero_grad(set_to_none=True)
    with torch.autocast(device_type="cuda", dtype=torch.float16):
        restored_loss = training_loss(restored_net(xt), yt, teacher, xt)
    restored_scaler.scale(restored_loss).backward()
    restored_scaler.unscale_(restored_opt)
    assert all(p.grad is None or torch.isfinite(p.grad).all() for p in restored_net.parameters())
    restored_scaler.step(restored_opt); restored_scaler.update()
    assert max(int(v["step"].item()) for v in restored_opt.state.values()) == 2
    if teacher is not None:
        assert not teacher.training and all(p.grad is None for p in teacher.parameters())
        assert all(torch.equal(v, teacher_before[k]) for k, v in teacher.state_dict().items())
        probe = torch.zeros((1, 1, 2, 2), device=device, requires_grad=True)
        assert torch.equal(training_loss(probe, torch.zeros_like(probe), None, None), loss_value(probe, torch.zeros_like(probe)))
    result = {"status": "PASS", "initial_epoch": initial_epoch, "all_positive_sampling": "PASS", "cosine_schedule": "PASS", "device": torch.cuda.get_device_name(0), "input_batch_shape": list(x.shape),
              "stored_dtype": "int8", "reader_dtype": str(x.dtype), "amp": scaler.is_enabled(),
              "loss": float(loss), "restored_step_loss": float(restored_loss), "restore_model_optimizer_scaler_rng": "PASS",
              "representative_reader_check": representative, "teacher_frozen": teacher is not None,
              "resources": resources(run_dir)}
    atomic_json(run_dir / "smoke_check.json", result)
    print(json.dumps(result), flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["train", "self-test"])
    ap.add_argument("--data-root", required=True)
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--epochs", type=int, default=100)
    ap.add_argument("--batch-size", type=int, default=8)
    ap.add_argument("--base", type=int, default=16)
    ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--initial-checkpoint", type=Path, required=True)
    ap.add_argument("--seed", type=int, default=SEED)
    ap.add_argument("--resume", action="store_true")
    ap.add_argument("--teacher-checkpoint", type=Path)
    ap.add_argument("--patience", type=int, default=0)
    ap.add_argument("--schedule-epochs", type=int)
    ap.add_argument("--amp-init-scale", type=float, default=1024)
    ap.add_argument("--skip-test", action="store_true")
    args = ap.parse_args()
    if not torch.cuda.is_available():
        raise RuntimeError("CUDA is required")
    data_root, run_dir = Path(args.data_root), Path(args.run_dir)
    if min(args.epochs, args.batch_size, args.base) < 1 or args.lr <= 0: raise ValueError("Invalid configuration")
    if args.schedule_epochs is not None and args.schedule_epochs < args.epochs: raise ValueError("Schedule shorter than run")
    run_dir.mkdir(parents=True, exist_ok=True)
    lock = (run_dir / "training.lock").open("a")
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    seed_all(args.seed)
    torch.set_num_threads(8)
    torch.backends.cudnn.benchmark = False
    torch.backends.cudnn.deterministic = True
    cache = Task06Cache(data_root)
    split_source = Path("/root/autodl-tmp/lung_training/task06_tumor_v1/runs/full_unet_20e_v2/config.json")
    source_split = json.loads(split_source.read_text())
    if source_split["train_cases"] != TRAIN_CASES or source_split["val_cases"] != VAL_CASES or source_split["seed"] != args.seed:
        raise RuntimeError("Existing patient split differs; do not silently change it")
    if len(set(TRAIN_CASES + VAL_CASES + TEST_CASES)) != len(TRAIN_CASES + VAL_CASES + TEST_CASES):
        raise RuntimeError("Patient split overlap")
    config = {"version": "task06_mkdc_finetune_100_v1", "model": "2.5d_resunet_mkdc_relu6", "base": args.base,
              "architecture": {"channels": [args.base, args.base * 2, args.base * 4, args.base * 8], "encoder_stages": 3,
                               "convolution": "unchanged mkdc 3x3+5x5 depthwise, channel shuffle, residual, BN, ReLU6", "downsample": "MaxPool2d(2)",
                               "upsample": "nearest 2x", "skip": "concat", "head": "1x1 Conv, 1 centre-layer logit"},
              "epochs": args.epochs, "batch_size": args.batch_size, "learning_rate": args.lr,
              "seed": args.seed, "amp": True, "amp_init_scale": 1024, "amp_dtype": "float16; loss and Dice reductions float32",
              "loss": "0.5 voxel-class-balanced BCE + 0.5 batch-pooled foreground soft Dice (smooth=1); empty-target batch has zero Dice contribution",
              "loss_reason": "restore proven ResUNet voxel-balanced loss for sparse tumour foreground",
              "initialization": "20-epoch mkdc run validation-best weights; fresh Adam and scaler; 100 additional epochs",
              "initial_checkpoint": str(args.initial_checkpoint.resolve()),
              "initial_checkpoint_sha256": hashlib.sha256(args.initial_checkpoint.read_bytes()).hexdigest(),
              "optimizer": "Adam", "lr_schedule": f"cosine over {args.epochs} additional epochs, minimum initial_lr*0.01",
              "cudnn_deterministic": True, "cudnn_benchmark": False, "workers": 0, "torch_cpu_threads": 8,
              "augmentation": "horizontal/vertical flips shared by all three channels and centre mask, each p=0.5; no intensity changes",
              "sampling": "all positive layers plus equal per-case negative layers, reshuffled per epoch",
              "train_cases": TRAIN_CASES, "val_cases": VAL_CASES, "test_cases": TEST_CASES,
              "split_source": str(split_source), "test_policy": "already evaluated in previous runs; excluded from selection; evaluate after final validation-best selection",
              "data_root": str(data_root), "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "reader_sha256": hashlib.sha256(Path(__file__).with_name("task06_cache_reader_v2.py").read_bytes()).hexdigest(),
              "loss_sha256": hashlib.sha256(Path(__file__).with_name("task06_tumor_loss_v3.py").read_bytes()).hexdigest(),
              "model_sha256": hashlib.sha256(Path(__file__).with_name("tumor_model.py").read_bytes()).hexdigest(),
              "metadata_sha256": hashlib.sha256((data_root / "metadata.json").read_bytes()).hexdigest(),
              "input_contract": cache.input_contract, "cache_verification": "verification.json passed=true checked_cases=63",
              "validation": "complete cases and slices; centre-layer predictions at threshold logit 0; global voxel Dice selects best",
              "metric_policy": {"dice_empty_target_empty_prediction": 1, "precision_zero_predictions": 0,
                                "recall_empty_target": 0, "positive_layer_recall": "GT-positive layers with >=1 correctly overlapping predicted voxel / GT-positive layers",
                                "empty_cases": "included, explicitly counted; per-case GT positives and FP recorded"}}
    if args.teacher_checkpoint or args.schedule_epochs or args.patience or args.amp_init_scale != 1024 or args.skip_test:
        config.update({"version": "task06_mkdc_distill_then_baseline_v1", "amp_init_scale": args.amp_init_scale,
                       "schedule_epochs": args.schedule_epochs or args.epochs, "patience": args.patience,
                       "skip_test": args.skip_test,
                       "initialization": "validation-best mkdc weights; fresh original Adam and scaler",
                       "lr_schedule": f"original cosine formula over {args.schedule_epochs or args.epochs} epochs; execute at most {args.epochs}"})
    if args.teacher_checkpoint:
        config.update({"teacher_checkpoint": str(args.teacher_checkpoint.resolve()),
                       "teacher_checkpoint_sha256": hashlib.sha256(args.teacher_checkpoint.read_bytes()).hexdigest(),
                       "teacher_source_sha256": hashlib.sha256(Path(__file__).with_name("teacher_resunet.py").read_bytes()).hexdigest(),
                       "distillation": "unchanged supervised loss + 0.25*T^2 region-balanced soft BCE; T=2; frozen FP32 eval teacher; identical augmented train inputs only"})
    cfg_path = run_dir / "config.json"
    last_path, best_path = run_dir / "last.pt", run_dir / "best.pt"
    if args.mode == "self-test":
        if cfg_path.exists() or last_path.exists(): raise FileExistsError("Use a separate smoke directory")
        self_test(data_root, run_dir, config); return
    if not args.resume and (cfg_path.exists() or last_path.exists() or (run_dir / "epochs.csv").exists()):
        raise FileExistsError("Existing run requires --resume; do not restart")
    if args.resume and not cfg_path.exists(): raise FileNotFoundError(cfg_path)
    if cfg_path.exists() and json.loads(cfg_path.read_text()) != config:
        raise RuntimeError("config mismatch; use a new run directory")
    if not cfg_path.exists():
        atomic_json(cfg_path, config)
        atomic_json(run_dir / "patient_split.json", {"seed": args.seed, "source": str(split_source), "train": TRAIN_CASES, "val": VAL_CASES, "test": TEST_CASES})
        (run_dir / "source").mkdir()
        for name in (Path(__file__).name, "task06_cache_reader_v2.py", "task06_tumor_loss_v3.py", "tumor_model.py"):
            shutil.copy2(Path(__file__).with_name(name), run_dir / "source" / name)
        if args.teacher_checkpoint:
            shutil.copy2(Path(__file__).with_name("teacher_resunet.py"), run_dir / "source" / "teacher_resunet.py")
    (run_dir / "checkpoints").mkdir(exist_ok=True)
    (run_dir / "epoch_records").mkdir(exist_ok=True)
    (run_dir / "reports").mkdir(exist_ok=True)
    net = Net(args.base).cuda()
    teacher = load_teacher(config)
    (run_dir / "model.txt").write_text(str(net) + f"\nparameters={sum(p.numel() for p in net.parameters())}\n")
    opt = torch.optim.Adam(net.parameters(), lr=args.lr)
    amp_enabled = True
    scaler = torch.cuda.amp.GradScaler(enabled=amp_enabled, init_scale=args.amp_init_scale)
    start_epoch, best_dice, restored = 1, -1.0, False
    best_epoch = 0
    if args.resume:
        if not last_path.exists(): raise FileNotFoundError(last_path)
        state = torch.load(last_path, map_location="cpu", weights_only=False)
        if state["config"] != config: raise RuntimeError("checkpoint config mismatch")
        net.load_state_dict(state["model"]); opt.load_state_dict(state["optimizer"]); scaler.load_state_dict(state["scaler"])
        restore_random_state(state); start_epoch, best_dice, restored = state["epoch"] + 1, state["best_dice"], True
        records = update_history(run_dir, state["epoch"])
        best_epoch = state["best_epoch"]
        checkpoint_alias(run_dir / "checkpoints" / f"epoch_{best_epoch:04d}.pt", best_path)
    device = torch.device("cuda")
    if not args.resume:
        atomic_json(run_dir / "status.json", {"state": "initial_evaluation", "completed_epoch": 0, "total_epochs": args.epochs, "pid": os.getpid()})
        initial_epoch = load_initial(net, config)
        initial_val = validate(net, cache, VAL_CASES, device, args.batch_size, amp_enabled)
        if teacher is not None:
            teacher_val = validate(teacher, cache, VAL_CASES, device, args.batch_size, False)
            atomic_json(run_dir / "teacher_validation.json", teacher_val)
            if abs(teacher_val["dice"] - 0.731169954032855) > 0.002:
                raise RuntimeError("Teacher validation does not reproduce the original best")
            print(f"Teacher | Dice={teacher_val['dice']:.6f}", flush=True)
        best_dice = initial_val["dice"]
        atomic_json(run_dir / "initial_validation.json", {"source_epoch": initial_epoch, "validation": initial_val})
        checkpoint = run_dir / "checkpoints" / "epoch_0000.pt"
        atomic_checkpoint(checkpoint, checkpoint_state(0, best_dice, net, opt, scaler, config))
        checkpoint_alias(checkpoint, best_path)
        print(f"Initial | Dice={best_dice:.6f} Recall={initial_val['recall']:.6f} Precision={initial_val['precision']:.6f}", flush=True)
    atomic_json(run_dir / "runtime.json", {"torch": torch.__version__, "cuda": torch.version.cuda,
                "gpu": torch.cuda.get_device_name(0), "pid": os.getpid(), "amp": scaler.is_enabled(),
                "cgroup_memory_max": Path("/sys/fs/cgroup/memory.max").read_text().strip(),
                "cgroup_cpu_max": Path("/sys/fs/cgroup/cpu.max").read_text().strip(), "resources": resources(run_dir)})
    print(json.dumps({"state": "started", "run": str(run_dir), "start_epoch": start_epoch, "total_epochs": args.epochs,
                      "gpu": torch.cuda.get_device_name(0), "amp": scaler.is_enabled(), "restored": restored}), flush=True)
    atomic_json(run_dir / "status.json", {"state": "training", "completed_epoch": start_epoch - 1, "total_epochs": args.epochs, "pid": os.getpid(), "restored": restored})
    for epoch in range(start_epoch, args.epochs + 1):
        started = time.time(); net.train(); loss_sum = 0.0; sample_count = 0; skipped_steps = 0
        torch.cuda.reset_peak_memory_stats()
        rng = random.Random(args.seed + epoch * 1009)
        case_order = list(TRAIN_CASES); rng.shuffle(case_order)
        lr = epoch_lr(args.lr, epoch, args.schedule_epochs or args.epochs)
        for group in opt.param_groups: group["lr"] = lr
        atomic_json(run_dir / "status.json", {"state": "training", "stage": "train", "current_epoch": epoch, "completed_epoch": epoch - 1, "total_epochs": args.epochs, "pid": os.getpid(), "restored": restored})
        try:
            for case_id in case_order:
                zs = sample_indices(cache, case_id, epoch, args.seed)
                for start in range(0, len(zs), args.batch_size):
                    xb, yb = batch_arrays(cache, case_id, zs[start:start + args.batch_size], True, rng)
                    xt = torch.from_numpy(xb).to(device, non_blocking=True)
                    yt = torch.from_numpy(yb).to(device, non_blocking=True)
                    opt.zero_grad(set_to_none=True)
                    with torch.autocast(device_type="cuda", dtype=torch.float16, enabled=amp_enabled):
                        logits = net(xt)
                        loss = training_loss(logits, yt, teacher, xt)
                    if not torch.isfinite(loss): raise FloatingPointError(f"Nonfinite training loss: {case_id}")
                    scaler.scale(loss).backward()
                    scale_before = scaler.get_scale()
                    scaler.step(opt); scaler.update()
                    skipped_steps += int(scaler.get_scale() < scale_before)
                    n = len(xb); loss_sum += float(loss.detach()) * n; sample_count += n
            atomic_json(run_dir / "status.json", {"state": "training", "stage": "validation", "current_epoch": epoch, "completed_epoch": epoch - 1, "total_epochs": args.epochs, "pid": os.getpid()})
            val = validate(net, cache, VAL_CASES, device, args.batch_size, amp_enabled)
            elapsed = time.time() - started
            improved = val["dice"] > best_dice
            if improved: best_dice, best_epoch = val["dice"], epoch
            resource = resources(run_dir)
            row = {"epoch": epoch, "train_loss": loss_sum / sample_count, "validation_loss": val["loss"], "validation_dice": val["dice"], "best_validation_dice": best_dice,
                   "precision": val["precision"], "recall": val["recall"], "positive_layer_recall": val["positive_layer_recall"],
                   "effective_case_count": val["case_count"], "empty_label_cases": val["empty_label_cases"],
                   "validation_slices": sum(c["effective_slices"] for c in val["cases"]), "train_samples": sample_count,
                   "case_dice_min": val["case_dice_min"], "case_dice_median": val["case_dice_median"], "case_dice_max": val["case_dice_max"],
                   "epoch_seconds": elapsed, "gpu_peak_allocated_gib": torch.cuda.max_memory_allocated() / 1024 ** 3,
                   "learning_rate": opt.param_groups[0]["lr"], "restored": restored, "amp_skipped_optimizer_steps": skipped_steps,
                   "data_skipped": 0, "oom": False, "error": "", "timestamp_unix": time.time(), **resource}
            atomic_json(run_dir / "epoch_records" / f"epoch_{epoch:04d}.json", {"row": row, "validation": val})
            checkpoint = run_dir / "checkpoints" / f"epoch_{epoch:04d}.pt"
            atomic_checkpoint(checkpoint, checkpoint_state(epoch, best_dice, net, opt, scaler, config, best_epoch))
            checkpoint_alias(checkpoint, last_path)
            if improved: checkpoint_alias(checkpoint, best_path)
            records = update_history(run_dir, epoch)
            atomic_json(run_dir / "status.json", {"state": "training", "stage": "epoch_complete", "completed_epoch": epoch, "total_epochs": args.epochs, "pid": os.getpid(), "best_dice": best_dice})
            print(f"Epoch {epoch}/{args.epochs} | Dice={val['dice']:.6f} Recall={val['recall']:.6f} Precision={val['precision']:.6f} Best={best_dice:.6f} TrainLoss={row['train_loss']:.6f} ValLoss={val['loss']:.6f} LR={lr:.8f} Stage={'distill' if teacher is not None else 'supervised'}", flush=True)
            if epoch % 20 == 0:
                recent = [r["row"] for r in records[-20:]]
                report = {"epoch": epoch, "total_epochs": args.epochs, "mean_last_20_epoch_seconds": statistics.mean(r["epoch_seconds"] for r in recent),
                          "current": row, "best_checkpoint": str(best_path), "last_checkpoint": str(last_path),
                          "restores_last_20": sum(r["restored"] for r in recent), "amp_skipped_steps_last_20": sum(r["amp_skipped_optimizer_steps"] for r in recent),
                          "data_skipped": 0, "oom": False, "exceptions": [], "continues": epoch < args.epochs}
                atomic_json(run_dir / "reports" / f"epoch_{epoch:04d}.json", report)
                print(json.dumps(report, separators=(",", ":")), flush=True)
            restored = False
            if args.patience and epoch - best_epoch >= args.patience:
                print(f"EarlyStop | no validation improvement for {args.patience} epochs; retained best={best_dice:.6f}", flush=True)
                break
        except Exception as exc:
            atomic_json(run_dir / "status.json", {"state": "error", "current_epoch": epoch, "total_epochs": args.epochs, "error": repr(exc), "data_skipped": 0, "pid": os.getpid()})
            raise
    best_state = torch.load(best_path, map_location="cpu", weights_only=False)
    net.load_state_dict(best_state["model"])
    completed_epoch = epoch if start_epoch <= args.epochs else start_epoch - 1
    atomic_json(run_dir / "status.json", {"state": "final_evaluation", "completed_epoch": completed_epoch, "total_epochs": args.epochs, "pid": os.getpid()})
    final = {"best_epoch": best_state["epoch"], "best_validation_dice": best_state["best_dice"], "config": config,
             "validation": validate(net, cache, VAL_CASES, device, args.batch_size, True),
             "test": None if args.skip_test else validate(net, cache, TEST_CASES, device, args.batch_size, True), "resources": resources(run_dir)}
    atomic_json(run_dir / "final_results.json", final)
    write_csv(run_dir / "best_validation_per_case.csv", final["validation"]["cases"])
    if final["test"] is not None: write_csv(run_dir / "best_test_per_case.csv", final["test"]["cases"])
    atomic_json(run_dir / "status.json", {"state": "complete", "completed_epoch": completed_epoch, "total_epochs": args.epochs, "best_epoch": best_state["epoch"], "best_dice": best_state["best_dice"]})
    print(json.dumps({"state": "complete", "best_epoch": best_state["epoch"], "results": str(run_dir / "final_results.json")}), flush=True)


if __name__ == "__main__":
    main()


