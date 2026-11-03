"""Board check: multi-solid ray union and union volume on mesh_ray ABI 0x00070000 (synthetic boxes)."""
import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cas_frontend.pl_metrics import PlMetrics


def box(lo, hi):
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    vertices = np.asarray(((x0,y0,z0),(x1,y0,z0),(x1,y1,z0),(x0,y1,z0),
                           (x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1)), dtype=float)
    faces = ((0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0))
    return np.asarray([vertices[list(face)][list(ids)] for face in faces for ids in ((0,1,2),(0,2,3))])


def case_mesh(boxes):
    triangles = np.concatenate([box(*bounds) for bounds in boxes])
    solid_ids = np.concatenate([np.full(12, sid, dtype=np.uint32) for sid in range(len(boxes))])
    return triangles, solid_ids


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bit', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('ray-union.json'))
    args = parser.parse_args()
    os.environ['LUNG_PL_BIT'] = str(args.bit.resolve())
    os.environ['LUNG_PL_ENABLE'] = '1'
    records = []
    client = PlMetrics(require_strict_pl=True)
    try:
        client.prepare()
        mmio = client._mesh_mmio
        if mmio is None or mmio.read(0x02c) != 0x00070000:
            raise RuntimeError('ABI 0x00070000 is required')
        caps = mmio.read(0x050)
        if caps & 0x7f != 0x7f or mmio.read(0x060) != 128 or mmio.read(0x0a0) != 32:
            raise RuntimeError('union capabilities or resource limits mismatch')
        if abs(client.clock_mhz - 100.) > 1.:
            raise RuntimeError('PL clock is not 100 MHz')
        image_hashes = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                        for path in (args.bit, args.bit.with_suffix('.bit.bin'), args.bit.with_suffix('.hwh'))}
        print('RAY_UNION_READY', json.dumps(dict(clock_mhz=client.clock_mhz, capabilities=hex(caps),
                                            max_hits=mmio.read(0x060), max_solids=mmio.read(0x0a0),
                                            image_hashes=image_hashes)), flush=True)
        origin = np.asarray([[-6., 0., 0.]])
        direction = np.asarray([[1., 0., 0.]])
        cases = (
            ('single', [((-4.,-1.,-1.),(4.,1.,1.))], [2 << 16, 10 << 16], False),
            ('separated', [((-4.,-1.,-1.),(-1.,1.,1.)),((1.,-1.,-1.),(4.,1.,1.))],
             [2 << 16, 5 << 16, 7 << 16, 10 << 16], False),
            ('overlap', [((-4.,-1.,-1.),(0.,1.,1.)),((-1.,-1.,-1.),(4.,1.,1.))],
             [2 << 16, 10 << 16], False),
            ('nested', [((-4.,-1.,-1.),(4.,1.,1.)),((-2.,-.5,-.5),(2.,.5,.5))],
             [2 << 16, 10 << 16], False),
            ('duplicate', [((-4.,-1.,-1.),(4.,1.,1.)),((-4.,-1.,-1.),(4.,1.,1.))],
             [2 << 16, 10 << 16], False),
        )
        for name, boxes, expected, expected_inside in cases:
            triangles, solid_ids = case_mesh(boxes)
            result = client.evaluate_mesh_rays(triangles, origin, direction, solid_ids=solid_ids,
                                               timeout_cycles=0xffffffff, timeout_seconds=120)
            row = result['results'][0] if result.get('results') else {}
            observed = row.get('crossings_q16')
            if (not result.get('ok') or row.get('errors') or observed != expected
                    or row.get('inside') is not expected_inside
                    or row.get('solid_count') != len(boxes)
                    or row.get('union_boundary_count') != len(expected)):
                raise RuntimeError(name + ' union golden mismatch: ' + json.dumps(result))
            records.append(dict(name=name, expected=expected, result=result))
            print('RAY_UNION_PASS', name, 'raw', row['hit_count'],
                  'events', row['event_count'], 'boundaries', row['union_boundary_count'], flush=True)

        separated_triangles, separated_ids = case_mesh(cases[1][1])
        volume_result = client.evaluate_mesh_rays(separated_triangles, origin, direction,
                                                  solid_ids=separated_ids, lengths=[12.],
                                                  timeout_cycles=0xffffffff, timeout_seconds=120)
        expected_fraction = ((5**3 - 2**3) + (10**3 - 7**3)) / (12**3)
        observed_fraction = volume_result.get('volume_mean_q30', -1) / float(1 << 30)
        if (not volume_result.get('ok') or volume_result.get('errors')
                or abs(observed_fraction - expected_fraction) > 2e-5):
            raise RuntimeError('overlap-aware volume mismatch: ' + json.dumps(volume_result))
        records.append(dict(name='separated_volume', expected_fraction=expected_fraction,
                            result=volume_result))
        print('RAY_UNION_VOLUME_PASS', observed_fraction, flush=True)

        inside_triangles, inside_ids = case_mesh([((-2.,-1.,-1.),(2.,1.,1.)),
                                                  ((-1.,-1.,-1.),(3.,1.,1.))])
        inside_result = client.evaluate_mesh_rays(inside_triangles, [[0.,0.,0.]], [[1.,0.,0.]],
                                                  solid_ids=inside_ids, timeout_cycles=0xffffffff,
                                                  timeout_seconds=120)
        inside_row = inside_result['results'][0]
        if (not inside_result.get('ok') or inside_row.get('errors') or not inside_row.get('inside')
                or inside_row.get('crossings_q16') != [3 << 16]):
            raise RuntimeError('inside OR semantics mismatch: ' + json.dumps(inside_result))
        records.append(dict(name='origin_inside_or', result=inside_result))
        print('RAY_UNION_ORIGIN_INSIDE_PASS', flush=True)
        args.output.write_text(json.dumps(dict(abi='0x00070000', board_validated=True,
                                               clock_mhz=client.clock_mhz, results=records), indent=2))
        print('RAY_UNION_BOARD_PASS', flush=True)
    except Exception as exc:
        args.output.write_text(json.dumps(dict(abi='0x00070000', board_validated=False,
                                               error=str(exc), results=records), indent=2))
        raise
    finally:
        client.close()


if __name__ == '__main__':
    main()
