"""Verify PL pipe transport/cache/error handling without board hardware."""
import base64
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import numpy as np
from cas_frontend.pl_privileged import PrivilegedPlClient
from cas_frontend import pl_metrics
from tools.pl_service import serve

CHILD = '''
import sys
from tools.pl_service import serve
class Fake:
    def __init__(self):
        self.job = 0
        self.previous = None
    def evaluate(self, points, vertices, margin):
        self.job += 1
        reused = points is self.previous
        self.previous = points
        print("library diagnostic", file=sys.stdout)
        return dict(ok=True, job_id=self.job, processed=len(points),
                    inside=len(points), cycles=200, coverage_percent=100.,
                    clearance_mm=margin, reused=reused, vertex=float(vertices[0,0]))
    def close(self):
        print("FAKE_CLOSED", file=sys.stderr)
serve(Fake(), sys.stdin, sys.stdout)
'''


class ServiceTests(unittest.TestCase):
    def test_mesh_decoder_cache_and_case_change(self):
        from cas_frontend.ray_mesh import pack_mesh, pack_rays
        mesh = np.array([[[-1,-1,0],[1,-1,0],[-1,1,0]]],float)
        fake = unittest.mock.Mock()
        fake.evaluate_mesh_rays.return_value = dict(ok=True, processed=1)
        requests=[]
        for changed, include in ((False,True),(False,False),(True,True)):
            raw=pack_mesh(mesh + (1 if changed else 0))
            request=dict(op='evaluate_mesh_rays', triangle_count=1, ray_count=1,
                         mesh_key=hashlib.sha256(raw).hexdigest(),
                         rays=base64.b64encode(pack_rays([[0,0,20]],[[0,0,-1]])).decode())
            if include:request['mesh']=base64.b64encode(raw).decode()
            requests.append(request)
        destination=io.StringIO()
        serve(fake,io.StringIO(''.join(json.dumps(x)+'\n' for x in requests)),destination)
        self.assertTrue(all(x['ok'] for x in [json.loads(x) for x in destination.getvalue().splitlines()][1:]))
        calls=fake.evaluate_mesh_rays.call_args_list
        np.testing.assert_array_equal(calls[0].args[0],mesh)
        self.assertIs(calls[0].args[0],calls[1].args[0])
        np.testing.assert_array_equal(calls[2].args[0],mesh+1)
        np.testing.assert_array_equal(calls[0].args[2],[[0,0,-1]])

    def test_bootstrap_restores_xrt_before_interpreter_starts(self):
        bash = shutil.which('bash')
        if not bash and Path('C:/Program Files/Git/bin/bash.exe').is_file():
            bash = 'C:/Program Files/Git/bin/bash.exe'
        if not bash:
            self.skipTest('Bash unavailable')
        with tempfile.TemporaryDirectory(prefix='pl runtime ') as directory:
            root = Path(directory)
            (root / 'lib').mkdir()
            (root / 'lib/libxrt_core.so').write_bytes(b'test library placeholder')
            (root / 'setup.sh').write_text(
                "printf 'setup diagnostic\\n'\nexport PL_TEST_SETUP=loaded\n", encoding='utf-8')
            probe = root / 'probe.sh'
            probe.write_text('printf \'%s\\n\' "$XILINX_XRT" "$PL_TEST_SETUP" "$LD_LIBRARY_PATH"\n',
                             encoding='utf-8')
            script = Path(__file__).resolve().parents[1] / 'tools/start_pl_service.sh'
            environment = dict(os.environ)
            environment.pop('XILINX_XRT', None)
            environment.pop('LD_LIBRARY_PATH', None)
            run = subprocess.run([bash, script.as_posix(), '/bin/bash',
                                  probe.as_posix(), root.as_posix()], env=environment,
                                 capture_output=True, text=True, timeout=20)
            self.assertEqual(run.returncode, 0, run.stderr)
            xrt, setup, loader = run.stdout.splitlines()
            self.assertEqual(xrt, root.as_posix())
            self.assertEqual(setup, 'loaded')
            self.assertIn(root.as_posix() + '/lib', loader)
            self.assertIn('setup diagnostic', run.stderr)

    def test_startup_error_is_returned_and_helper_exits(self):
        client = PrivilegedPlClient('unused.bit')
        command = [sys.executable, '-u', '-c',
                   'import json; print(json.dumps(dict(ready=False, startup_error="XRT unavailable")))']
        with patch.object(client, '_command', return_value=command):
            with self.assertRaisesRegex(RuntimeError, 'XRT unavailable'):
                client.prepare()
        self.assertIsNone(client.process)

    def test_unprivileged_metrics_routes_to_service_and_preserves_errors(self):
        metrics = pl_metrics.PlMetrics()
        points = np.ones((2, 3))
        vertices = np.zeros((4, 3))
        fake = unittest.mock.Mock()
        fake.evaluate.side_effect = [dict(ok=True, cycles=300),
                                     dict(ok=False, error='authorization denied')]
        with patch.object(pl_metrics.sys, 'platform', 'linux'), \
                patch.object(pl_metrics.os, 'geteuid', return_value=1000, create=True), \
                patch('cas_frontend.pl_privileged.PrivilegedPlClient', return_value=fake), \
                patch.object(metrics, '_load') as direct:
            first = metrics.evaluate(points, vertices, 1)
            self.assertTrue(first['ok'])
            self.assertEqual(metrics.status, 'ready')
            second = metrics.evaluate(points, vertices, 1)
            self.assertFalse(second['ok'])
            self.assertEqual(metrics.last_error, 'authorization denied')
            self.assertEqual(metrics.status, 'unavailable')
            direct.assert_not_called()
        metrics.close()
        fake.close.assert_called_once()

    def test_real_pipes_reuse_points_and_process(self):
        client = PrivilegedPlClient('unused.bit')
        points = np.arange(4494 * 3, dtype=float).reshape(-1, 3) / 100
        vertices = np.arange(12, dtype=float).reshape(4, 3)
        try:
            with patch.object(client, '_command', return_value=[sys.executable, '-u', '-c', CHILD]):
                first = client.evaluate(points, vertices, 1.)
                process = client.process
                vertices[0, 0] = 10
                second = client.evaluate(points, vertices, 2.)
                changed = client.evaluate(points + 1, vertices, 2.)
            self.assertIs(client.process, process)
            self.assertTrue(first['ok'])
            self.assertEqual(first['processed'], 4494)
            self.assertEqual(second['job_id'], 2)
            self.assertEqual(second['vertex'], 10)
            self.assertEqual(second['clearance_mm'], 2)
            self.assertTrue(second['reused'])
            self.assertFalse(changed['reused'])
            self.assertGreater(second['service_ms'], 0)
        finally:
            client.close()
        self.assertEqual(process.poll(), 0)

    def test_authorization_cancel_closes_process(self):
        client = PrivilegedPlClient('unused.bit')
        command = [sys.executable, '-c', 'import sys; sys.exit(126)']
        with patch.object(client, '_command', return_value=command):
            with self.assertRaisesRegex(RuntimeError, 'code 126.*Authorization'):
                client.evaluate([[1, 2, 3]], np.zeros((4, 3)), 0)
        self.assertIsNone(client.process)

    def test_concurrent_ray_requests_are_serialized(self):
        client = PrivilegedPlClient('unused.bit')
        raw = b'\0' * 80
        entered = threading.Event()
        release = threading.Event()
        received = []

        class Stdin:
            def write(self, value):
                received.append(value)

            def flush(self):
                pass

        class Process:
            stdin = Stdin()

            def poll(self):
                return None

        client.process = Process()
        client._start = lambda: None

        def receive(timeout):
            entered.set()
            release.wait(2)
            return dict(ok=True, results=[], processed=1, hits=0, errors=0)

        client._receive = receive
        results = []

        def call():
            results.append(client.evaluate_rays(raw, 1))

        first = threading.Thread(target=call)
        second = threading.Thread(target=call)
        first.start()
        self.assertTrue(entered.wait(1))
        second.start()
        time.sleep(.05)
        self.assertEqual(len(received), 1)
        release.set()
        first.join(2)
        second.join(2)
        self.assertEqual(len(results), 2)
        self.assertEqual(len(received), 2)

    def test_mesh_request_labels_follow_bvh_wire_order(self):
        from cas_frontend.mesh_bvh import build_mesh_image

        positions = [10, 0, 14, 2, 12, 4, 8, 6, 1, 15, 3, 13, 5, 11, 7, 9]
        triangles = np.asarray([
            [[float(x), 0., 0.], [float(x) + .5, 0., 0.], [float(x), .5, 0.]]
            for x in positions
        ])
        labels = np.asarray([x % 2 for x in range(16)])
        image = build_mesh_image(triangles, solid_ids=labels)
        self.assertFalse(np.array_equal(image.solid_ids, labels))

        client = PrivilegedPlClient('unused.bit')
        client.process = unittest.mock.Mock()
        client._start = lambda: None
        client._receive = lambda timeout: dict(ok=True, solid_count=2)
        try:
            result = client.evaluate_mesh_rays(
                triangles, [[0., 0., -1.]], [[0., 0., 1.]], solid_ids=labels)
            self.assertTrue(result['ok'])
            request = json.loads(client.process.stdin.write.call_args.args[0])
            self.assertEqual(request['solid_ids'], image.solid_ids.tolist())
            client.evaluate_mesh_rays(triangles, [[0., 0., -1.]], [[0., 0., 0.]],
                                      _distance=True, solid_ids=labels)
            cached = json.loads(client.process.stdin.write.call_args.args[0])
            self.assertEqual(cached['mesh_key'], request['mesh_key'])
            self.assertNotIn('mesh', cached)
            self.assertNotIn('solid_ids', cached)
        finally:
            client.process = None

    def test_protocol_rejects_bad_inputs_and_frees_client(self):
        fake = unittest.mock.Mock()
        raw = np.zeros((1, 3), dtype='<f8').tobytes()
        key = hashlib.sha256(raw).hexdigest()
        invalid = [dict(op='other'),
                   dict(op='evaluate', points_key=key),
                   dict(op='evaluate', points_key='wrong', points=base64.b64encode(raw).decode()),
                   dict(op='evaluate', points_key=key, points=base64.b64encode(raw).decode(),
                        vertices=[[float('nan')] * 3] * 4, minimum_clearance=0)]
        source = io.StringIO(''.join(json.dumps(item) + '\n' for item in invalid))
        destination = io.StringIO()
        serve(fake, source, destination)
        records = [json.loads(line) for line in destination.getvalue().splitlines()]
        self.assertEqual(records[0], dict(ready=True, protocol=1))
        self.assertEqual(len(records), 5)
        self.assertTrue(all(item['ok'] is False for item in records[1:]))
        fake.evaluate.assert_not_called()
        fake.close.assert_called_once()


if __name__ == '__main__':
    unittest.main()
