"""Apply Taubin smoothing to binary STL meshes without changing their topology."""

from __future__ import annotations

import argparse
import json
import shutil
import struct
from pathlib import Path

import numpy as np
from scipy.sparse import coo_matrix


STL_NAMES = [
    "s0423_lung_upper_lobe_left_pred.stl",
    "s0423_lung_lower_lobe_left_pred.stl",
    "s0423_lung_upper_lobe_right_pred.stl",
    "s0423_lung_middle_lobe_right_pred.stl",
    "s0423_lung_lower_lobe_right_pred.stl",
    "s0423_all_lobes_pred.stl",
]


def read_binary_stl(path: Path) -> tuple[np.ndarray, np.ndarray]:
    with path.open("rb") as stream:
        header = stream.read(80)
        count_bytes = stream.read(4)
        if len(header) != 80 or len(count_bytes) != 4:
            raise ValueError(f"Invalid STL header: {path}")
        count = struct.unpack("<I", count_bytes)[0]
        if path.stat().st_size != 84 + count * 50:
            raise ValueError(f"Expected a binary STL with {count} facets: {path}")
        dtype = np.dtype([
            ("normal", "<f4", (3,)),
            ("vertices", "<f4", (3, 3)),
            ("attribute", "<u2"),
        ])
        triangles = np.fromfile(stream, dtype=dtype, count=count)
    vertices, inverse = np.unique(
        triangles["vertices"].reshape(-1, 3), axis=0, return_inverse=True
    )
    return vertices.astype(np.float64), inverse.reshape(-1, 3)


def mesh_stats(vertices: np.ndarray, faces: np.ndarray) -> dict:
    triangles = vertices[faces]
    cross = np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0])
    area = np.linalg.norm(cross, axis=1).sum() * 0.5
    volume = np.einsum(
        "ij,ij->i", triangles[:, 0], np.cross(triangles[:, 1], triangles[:, 2])
    ).sum() / 6.0
    return {
        "vertices": int(len(vertices)),
        "faces": int(len(faces)),
        "surface_area_mm2": float(area),
        "signed_volume_mm3": float(volume),
        "bounds_mm": [vertices.min(axis=0).tolist(), vertices.max(axis=0).tolist()],
    }


def taubin_smooth(
    vertices: np.ndarray,
    faces: np.ndarray,
    iterations: int = 8,
    lam: float = 0.5,
    mu: float = -0.53,
) -> np.ndarray:
    edges = np.concatenate((faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]))
    edges.sort(axis=1)
    edges = np.unique(edges, axis=0)
    rows = np.concatenate((edges[:, 0], edges[:, 1]))
    cols = np.concatenate((edges[:, 1], edges[:, 0]))
    adjacency = coo_matrix(
        (np.ones(len(rows), dtype=np.float64), (rows, cols)),
        shape=(len(vertices), len(vertices)),
    ).tocsr()
    degree = np.asarray(adjacency.sum(axis=1)).reshape(-1, 1)
    if np.any(degree == 0):
        raise ValueError("Mesh contains an isolated vertex")

    result = vertices.copy()
    for _ in range(iterations):
        average = adjacency @ result / degree
        result += lam * (average - result)
        average = adjacency @ result / degree
        result += mu * (average - result)
    return result


def write_binary_stl(path: Path, vertices: np.ndarray, faces: np.ndarray, header: bytes) -> None:
    tri = vertices[faces]
    normals = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    lengths = np.linalg.norm(normals, axis=1, keepdims=True)
    if np.any(lengths == 0) or not np.isfinite(tri).all():
        raise ValueError("Smoothing produced invalid or degenerate facets")
    normals /= lengths
    dtype = np.dtype([
        ("normal", "<f4", (3,)),
        ("vertices", "<f4", (3, 3)),
        ("attribute", "<u2"),
    ])
    data = np.zeros(len(faces), dtype=dtype)
    data["normal"] = normals.astype(np.float32)
    data["vertices"] = tri.astype(np.float32)
    with path.open("wb") as stream:
        stream.write(header[:80].ljust(80, b" "))
        stream.write(struct.pack("<I", len(faces)))
        data.tofile(stream)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--iterations", type=int, default=8)
    args = parser.parse_args()
    if args.iterations < 1:
        raise ValueError("iterations must be positive")
    args.output_dir.mkdir(parents=True, exist_ok=False)

    summary = {
        "status": "PASS",
        "method": "Taubin mesh smoothing on existing binary STL surfaces",
        "parameters": {"iterations": args.iterations, "lambda": 0.5, "mu": -0.53},
        "input_note": "Existing binary masks/STLs were used; no model inference or training was run.",
        "meshes": [],
    }
    raw_dir = args.output_dir / "original_meshes"
    raw_dir.mkdir()
    for name in STL_NAMES:
        source = args.input_dir / name
        if not source.is_file():
            raise FileNotFoundError(source)
        shutil.copy2(source, raw_dir / name)
        with source.open("rb") as stream:
            header = stream.read(80)
        original, faces = read_binary_stl(source)
        before = mesh_stats(original, faces)
        smoothed = taubin_smooth(original, faces, iterations=args.iterations)
        after = mesh_stats(smoothed, faces)
        displacement = np.linalg.norm(smoothed - original, axis=1)
        volume_before = abs(before["signed_volume_mm3"])
        volume_after = abs(after["signed_volume_mm3"])
        volume_delta = 100.0 * (volume_after - volume_before) / max(volume_before, 1e-12)
        if abs(volume_delta) > 5.0:
            raise ValueError(f"{name}: volume changed by {volume_delta:.2f}%")
        output_path = args.output_dir / name
        write_binary_stl(output_path, smoothed, faces, header)
        written_vertices, written_faces = read_binary_stl(output_path)
        if len(written_vertices) != len(original) or len(written_faces) != len(faces):
            raise ValueError(f"{name}: STL read-back changed mesh topology")
        if not np.isfinite(written_vertices).all():
            raise ValueError(f"{name}: STL read-back contains non-finite coordinates")
        after = mesh_stats(written_vertices, written_faces)
        summary["meshes"].append({
            "file": name,
            "before": before,
            "after": after,
            "volume_change_percent": float(volume_delta),
            "vertex_displacement_mm": {
                "mean": float(displacement.mean()),
                "p95": float(np.percentile(displacement, 95)),
                "max": float(displacement.max()),
            },
        })

    npz_path = args.input_dir / "s0423_pred_native.npz"
    if npz_path.exists():
        shutil.copy2(npz_path, args.output_dir / npz_path.name)
    report_path = args.input_dir / "report.json"
    if report_path.exists():
        shutil.copy2(report_path, args.output_dir / "source_report.json")
        report = json.loads(report_path.read_text(encoding="utf-8"))
        report["output_dir"] = "."
        report["postprocessing"] = {
            "method": "Taubin smoothing applied to the existing STL meshes",
            "parameters": summary["parameters"],
            "geometry": "Original physical coordinate frame and affine retained; vertices moved in millimeters.",
            "prediction": "Binary mask/STL postprocessing only; model inference was not rerun and logits were unavailable.",
            "original_meshes": "original_meshes/",
        }
        per_file = {item["file"]: item for item in summary["meshes"]}
        for mesh in report.get("meshes", []):
            name = Path(mesh["path"]).name
            if name in per_file:
                mesh["source_path"] = mesh["path"]
                mesh["path"] = name
                mesh["smoothing"] = per_file[name]
        (args.output_dir / "report.json").write_text(
            json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
    (args.output_dir / "smoothing_report.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
