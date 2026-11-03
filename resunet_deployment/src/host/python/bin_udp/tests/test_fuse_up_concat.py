"""Production plans and immutable benchmark inputs for the selected d1 fusion."""
import json
import struct
import unittest

import fixed_fpga_benchmark as benchmark
from src.fullnet import NetworkPlan, coefficient_image
from src.op_client import descriptor


class FuseUpConcatTests(unittest.TestCase):
    def test_four_model_production_plans_and_frozen_manifests(self):
        image = coefficient_image()
        for task in benchmark.MODEL_TASKS:
            old = NetworkPlan(task, image, fuse_up_concat=False)
            new = NetworkPlan(task, image)
            self.assertEqual(len(new.stages), 44)
            self.assertNotIn('d1.up', new.tensors)
            fused = next(s for s in new.stages if s['op'] == 13)
            self.assertEqual(fused['reads'], ['d2.out', 'e1.out'])
            self.assertEqual(fused['name'], 'd1.concat')
            self.assertEqual(fused['bytes'], old.tensors['d1.concat']['bytes'])
            self.assertEqual(struct.unpack_from('<HH', fused['descriptor'], 4), (256, 256))
            # Address allocation follows the changed lifetimes, including encoder skips.
            for index, stage in enumerate(new.stages):
                live = [t for t in new.tensors.values() if t['produced'] <= index <= t['last']]
                for i, a in enumerate(live):
                    for b in live[i+1:]:
                        self.assertFalse(a['address'] < b['address']+b['bytes'] and
                                         b['address'] < a['address']+a['bytes'], (task, stage['name']))
            benchmark.fuse_residual_plan(new)
            self.assertEqual(len(new.stages), 30)
            self.assertEqual(sum(s['op'] == 13 for s in new.stages), 1)
            path = benchmark.HERE / 'output/ct_01/fixed_benchmark/all_models_fused_residual' / (task+'.json')
            original = path.read_bytes()
            saved = json.loads(original)
            loaded, inputs, _ = benchmark.load_manifest(path)
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual(len(loaded['stages']), 30)
            before = {s['name']: s for s in saved['stages']}
            f = next(s for s in loaded['stages'] if s['op'] == 13)
            d = bytes.fromhex(f['descriptor_hex'])
            self.assertEqual(d[16:20], bytes.fromhex(before['d1.up']['descriptor_hex'])[16:20])
            self.assertEqual(d[20:28], bytes.fromhex(before['d1.concat']['descriptor_hex'])[20:28])
            self.assertEqual(inputs[0]['sha256'], saved['inputs'][0]['sha256'])
            self.assertEqual(loaded['output'].get('golden_sha256'), saved['output'].get('golden_sha256'))
            self.assertEqual(loaded['execution_schedule_sha256'], benchmark.sha256_bytes(b''.join(
                bytes.fromhex(s['descriptor_hex']) for s in loaded['stages'])))
            self.assertEqual([s['name'] for s in loaded['stages'] if s['op'] == 13], ['d1.concat'])
            for stage in loaded['stages']:
                if stage['op'] not in (13, 1):
                    self.assertEqual(stage, before[stage['name']])

    def test_descriptor_rejects_unsafe_skip_or_expanded_output(self):
        good = dict(width=256, height=256, groups=2, groups_b=1, cin=0, cout=0,
                    base_a=0x09000000, base_b=0x1e000000, output=0x10000000)
        self.assertEqual(descriptor(13, 1, **good)[0], 13)
        for bad in (dict(width=257), dict(groups_b=0), dict(groups_b=33),
                    dict(base_b=0x1ffffff0), dict(output=0x1ff00000),
                    dict(output=0x08e00000), dict(output=0x1df00000), dict(raw=True)):
            with self.assertRaises(ValueError, msg=str(bad)):
                descriptor(13, 1, **(good | bad))


if __name__ == '__main__':
    unittest.main()
