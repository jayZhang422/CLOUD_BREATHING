import base64
from hashlib import sha256
import io
import json
import tempfile
import unittest
from unittest.mock import Mock, patch

import numpy as np

from cas_frontend.pl_metrics import PlMetrics
from cas_frontend.voxel_mask import VoxelMask
from tools.pl_service import serve


class DistanceTransportTests(unittest.TestCase):
    def volume(self):
        data = np.zeros((7, 6, 5), np.uint8)
        data[2:5, 2:4, 1:4] = 1
        return VoxelMask(data, [.8]*3, [10, 20, 30], np.eye(3), dict(synthetic=True))

    def test_service_decodes_packed_mask_and_checks_hash_and_metadata(self):
        volume = self.volume()
        packed = np.packbits(volume.data.ravel(), bitorder='little').tobytes()
        request = dict(op='evaluate_mask_distances', metadata=volume.metadata(),
                       mask_bits=base64.b64encode(packed).decode(),
                       mask_bits_sha256=sha256(packed).hexdigest(),
                       coordinates=base64.b64encode(np.array([[3, 3, 2]], dtype='<u2').tobytes()).decode())
        client = Mock()
        client.evaluate_mask_distances.return_value = dict(ok=True, pl_calls=1, cpu_fallback_count=0)
        wrong = dict(request, mask_bits_sha256='wrong')
        output = io.StringIO()
        with patch('cas_frontend.voxel_mask.VoxelMask', wraps=VoxelMask) as volume_factory:
            serve(client, io.StringIO(json.dumps(request)+'\n'+json.dumps(wrong)+'\n'), output)
        replies = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertTrue(replies[1]['ok'])
        self.assertFalse(replies[2]['ok'])
        self.assertEqual(client.evaluate_mask_distances.call_count, 1)
        self.assertEqual(volume_factory.call_args.args[0].dtype, np.bool_)
        decoded, coords = client.evaluate_mask_distances.call_args.args
        np.testing.assert_array_equal(decoded.data, volume.data)
        np.testing.assert_array_equal(coords, [[3, 3, 2]])

    def test_missing_capability_and_service_failure_do_not_fallback(self):
        client = PlMetrics(require_strict_pl=True)
        coords = np.array([[3, 3, 2]], dtype=np.int64)
        with patch('cas_frontend.pl_distance.sys.platform', 'win32'), patch.object(client, '_load'):
            with self.assertRaisesRegex(RuntimeError, '没有 CPU 回退'):
                client.evaluate_mask_distances(self.volume(), coords)
        helper = Mock()
        helper.evaluate_mask_distances.return_value = dict(ok=False, error='explicit hardware failure')
        client._privileged = helper
        with patch('cas_frontend.pl_distance.sys.platform', 'linux'), patch('os.geteuid', return_value=1000, create=True):
            with self.assertRaisesRegex(RuntimeError, 'explicit hardware failure'):
                client.evaluate_mask_distances(self.volume(), coords)
        client._privileged = None
        client.close()


if __name__ == '__main__':
    unittest.main()
