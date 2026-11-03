#!/usr/bin/env python3
"""只核对最终PASS、结果表及版本；PASS不读取黑匣子CSV。"""
from pathlib import Path
import csv, hashlib, json, re
root=Path(__file__).resolve().parents[1]
log=(root/"verification/run.log").read_text()
assert "[success]" in log and not re.search(r"\[TB FAILED\]|\[error\]|Simulation failed|watchdog timeout",log)
mac=re.search(r"\[TB PASSED\] ALL MAC cases=(\d+) outputs=(\d+) cycles=(\d+) reset_phases=4 frozen_layers=66",log)
quant=re.search(r"\[TB PASSED\] REQUANT cases=(\d+) numeric_boundaries=(\d+) raw_cases=32 cycles=(\d+).*signed_RNE=PASS",log)
assert mac and quant, "missing final MAC/REQUANT PASS"
with (root/"verification/mac_results.csv").open() as f:
    rows=list(csv.DictReader(f))
assert len(rows)==int(mac[1]) and all(r["status"]=="PASS" for r in rows)
assert sum(int(r["outputs"]) for r in rows)==int(mac[2])
assert any(r["case"]=="full_frame_512" and int(r["outputs"])==262144 for r in rows)
assert int(quant[1])==int(quant[2])+32
result={"status":"PASS","mac_cases":int(mac[1]),"mac_output_beats":int(mac[2]),"mac_cycles":int(mac[3]),
        "frozen_pw_layers":66,"reset_phases":4,"requant_cases":int(quant[1]),
        "requant_numeric_boundaries":int(quant[2]),"source_sha256":{}}
for directory in ("sim","tools","rtl"):
 for p in sorted((root/directory).glob("*")):
  if p.is_file(): result["source_sha256"][str(p.relative_to(root))]=hashlib.sha256(p.read_bytes()).hexdigest()
scala_source=root/"../../../../src/scala/pw/pwmac.scala"
result["source_sha256"]["../../../../src/scala/pw/pwmac.scala"]=hashlib.sha256(scala_source.read_bytes()).hexdigest()
(root/"verification/result.json").write_text(json.dumps(result,indent=2))
print("[TB PASSED] DELIVERY mac_cases=%d outputs=%d requant_cases=%d exit=0"%(result["mac_cases"],result["mac_output_beats"],result["requant_cases"]))
