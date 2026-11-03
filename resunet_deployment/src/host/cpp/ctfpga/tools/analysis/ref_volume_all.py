"""Run ref_volume over every CT_STL_Work case whose *_模型.zip exists; print ref/mask ratios."""
import json, os, subprocess, sys
root = "data/ct_stl_work"
for c in sorted(os.listdir(root)):
    try:
        z = json.load(open(f"{root}/{c}/input/metadata.json", encoding="utf-8"))["source_dicom_zip"]
    except Exception:
        continue
    name = os.path.basename(z).replace("_CT.zip", "")
    if not os.path.exists(f"data/reference_models/{name}_model.zip"):
        continue
    print("==", c, name.encode("utf-8").decode("utf-8"), flush=True)
    sys.argv = ["x", name]
    subprocess.run([sys.executable, "-X", "utf8", "tools/analysis/ref_volume.py", c, name])
