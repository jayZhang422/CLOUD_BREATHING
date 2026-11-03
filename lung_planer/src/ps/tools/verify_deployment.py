#!/usr/bin/env python3
"""Read-only deployment preflight for fpga/lung_planner.bit; touches no hardware.

Checks, before the desktop session takes over the display:
  * the bit/bin/hwh match the frozen baseline hashes,
  * the board-parity admission receipt is complete, is bound to that exact bit/hwh,
    and every software source it covers still has the hash the receipt was made with.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

SOURCES_KEY = 'source_sha256'


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def verify(root, directory, *, bit_name='lung_planner.bit'):
    root, directory = Path(root).resolve(), Path(directory).resolve()
    frozen = json.loads((directory / 'frozen_baseline.json').read_text(encoding='utf-8'))
    for name, expected in frozen['firmware'].items():
        if sha256(directory / name) != expected:
            raise SystemExit('firmware differs from the frozen baseline: ' + name)
    receipt_path = directory / 'mesh-full.json'
    report = json.loads(receipt_path.read_text(encoding='utf-8'))
    if (report.get('kind') != 'dual_plane_mesh_hardware_parity'
            or report.get('board_validated') is not True or report.get('full') is not True
            or report.get('abi') != '0x00050000'):
        raise SystemExit('admission receipt is not a complete board parity report')
    recovery = report.get('control_recovery', {})
    if not (recovery.get('cancelled_then_recovered') is True
            and recovery.get('timed_out_then_recovered') is True
            and recovery.get('cpu_fallback_count') == 0):
        raise SystemExit('admission receipt lacks cancellation/timeout recovery evidence')
    if bit_name != 'lung_planner.bit':
        raise SystemExit('unsupported dual-plane firmware name')
    bit = directory / bit_name
    required = (bit.name, bit.with_suffix('.hwh').name)
    if not all(name in frozen['firmware'] for name in required):
        raise SystemExit('frozen firmware manifest does not cover bitstream/HWH')
    if report.get('bit_sha256') != sha256(bit) or report.get('hwh_sha256') != sha256(bit.with_suffix('.hwh')):
        raise SystemExit('admission receipt is bound to a different bitstream/HWH')
    changed = [name for name, expected in report.get(SOURCES_KEY, {}).items()
               if sha256(root / name) != expected]
    if changed:
        raise SystemExit('deployed software differs from the admitted sources: ' + ', '.join(changed))
    # Validate all required source hashes and the synthetic-cube parity case.
    from cas_frontend.dual_plane_mesh_gate import verify_admission
    verify_admission(receipt_path, bit)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--directory', type=Path,
                        help='directory holding lung_planner.bit/hwh, frozen_baseline.json and mesh-full.json')
    args = parser.parse_args()
    directory = args.directory or args.root / 'fpga'
    report = verify(args.root, directory)
    print('DEPLOYMENT_PASS sources=%d cases=%s' % (
        len(report.get(SOURCES_KEY, {})), ','.join(sorted(
            c['name'] if isinstance(c, dict) else c for c in (report['cases'] if isinstance(report['cases'], list)
                                                                 else report['cases'])))))


if __name__ == '__main__':
    sys.exit(main())
