import json, os, sys, time, urllib.request, urllib.parse, subprocess, re
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

BASE = "https://hf-mirror.com"
REPO = "farrell236/NSCLC-Radiomics-NIFTI"
ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else "/root/autodl-tmp/datasets/NSCLC-Radiomics-NIFTI")
ROOT.mkdir(parents=True, exist_ok=True)

def fetch(url, target):
    tmp = target.with_suffix(target.suffix + ".part")
    cmd = ["curl", "-L", "--fail", "--retry", "5", "--retry-delay", "3",
           "-A", "Mozilla/5.0", "-C", "-", "-o", str(tmp), url]
    subprocess.run(cmd, check=True, timeout=3600)
    tmp.replace(target)

def tree_pages():
    url = f"{BASE}/api/datasets/{REPO}/tree/main?recursive=true&limit=1000"
    while url:
        hdr = Path("/tmp/hf_tree_headers")
        body = Path("/tmp/hf_tree_body")
        subprocess.run(["curl", "-sS", "--fail", "-A", "Mozilla/5.0", "-D", str(hdr), "-o", str(body), url], check=True, timeout=120)
        yield from json.loads(body.read_text())
        link = hdr.read_text(errors="replace")
        m = re.search(r'<https://[^>]+/api/datasets/[^>]+/tree/main\?([^>]+)>; rel="next"', link)
        if not m:
            break
        query = m.group(1).replace("&amp;", "&")
        url = f"{BASE}/api/datasets/{REPO}/tree/main?{query}"

files = [x for x in tree_pages() if x.get("type") == "file"]
total = sum(int(x.get("size", 0)) for x in files)
done = sum((ROOT / x["path"]).stat().st_size for x in files if (ROOT / x["path"]).is_file())
print(json.dumps({"event":"start","files":len(files),"total":total,"done":done}, ensure_ascii=False), flush=True)
def download_one(x):
    rel = x["path"]
    dst = ROOT / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() and dst.stat().st_size == int(x.get("size", -1)):
        return 0
    url = f"{BASE}/datasets/{REPO}/resolve/main/{urllib.parse.quote(rel, safe='/')}"
    for attempt in range(5):
        try:
            fetch(url, dst)
            break
        except Exception as e:
            print(json.dumps({"event":"retry","file":rel,"attempt":attempt+1,"error":str(e)}), flush=True)
            time.sleep(3 * (attempt + 1))
    else:
        raise RuntimeError(f"failed: {rel}")
    return dst.stat().st_size

remaining = [x for x in files if not ((ROOT / x["path"]).is_file() and (ROOT / x["path"]).stat().st_size == int(x.get("size", -1)))]
with ThreadPoolExecutor(max_workers=8) as pool:
    futures = [pool.submit(download_one, x) for x in remaining]
    for i, future in enumerate(as_completed(futures), 1):
        done += future.result()
        if i % 5 == 0 or i == len(futures):
            print(json.dumps({"event":"progress","completed_new":i,"remaining":len(futures),"done":done,"total":total,"pct":100*done/total}), flush=True)
print(json.dumps({"event":"complete","files":len(files),"total":total,"done":done}, ensure_ascii=False), flush=True)
