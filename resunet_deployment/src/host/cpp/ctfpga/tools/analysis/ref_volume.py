"""Compare reference-STL volume (reference model zip) with prediction mask volume, per structure."""
import json, struct, sys, zipfile
import numpy as np

case = sys.argv[1]; name_zip = sys.argv[2] if len(sys.argv) > 2 else case
work = f"data/ct_stl_work/{case}"
meta = json.load(open(f"{work}/prediction/metadata.json", encoding="utf-8"))
shape = meta["shape"]
im = json.load(open(f"{work}/input/metadata.json", encoding="utf-8"))
sp = None
for k in ("spacing_z_y_x_mm",):
    if k in im:
        sp = im[k]; break
if sp is None:
    print("input meta keys:", list(im.keys())); sys.exit(1)
sp = [float(x) for x in sp][-3:] if len(sp) >= 3 else sp
vox = float(np.prod(sp))
if meta.get("layout") == "Z,C,Y,X":
    seg8 = np.memmap(f"{work}/prediction/segmentation_uint8.bin", dtype=np.uint8, mode="r", shape=tuple(shape))
    seg = None
else:
    seg = np.fromfile(f"{work}/prediction/segmentation_uint16.bin", dtype=np.uint16).reshape(shape)
z = zipfile.ZipFile(f"data/reference_models/{name_zip}_model.zip")


def stl_volume(data):
    n = struct.unpack("<I", data[80:84])[0]
    a = np.frombuffer(data[84:84 + n * 50], dtype=np.dtype([("n", "<f4", 3), ("v", "<f4", (3, 3)), ("a", "<u2")]))
    v = a["v"].astype(np.float64)
    return abs(np.einsum("ij,ij->i", v[:, 0], np.cross(v[:, 1], v[:, 2])).sum() / 6.0), n


for ch, name in ((5, "Bronchus"), (6, "PulmonaryArtery"), (7, "PulmonaryVenous"), (8, "LungTumor1")):
    key = "LungTumor" if ch == 8 else name
    m = (int(seg8[:, ch].sum()) if seg is None else int(((seg >> ch) & 1).sum())) * vox
    try:
        vol, n = stl_volume(z.read(name + ".stl"))
    except KeyError:
        vol, n = float("nan"), 0
    print(f"{name:16s} mask={m:10.0f} mm3  refSTL={vol:10.0f} mm3 faces={n:8d}  ref/mask={vol / m if m else 0:.3f}")
