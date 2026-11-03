"""DMA timeout recovery tests using a small in-process PYNQ double."""
import os
import struct
import sys
import types
import numpy as np
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from cas_frontend.pl_metrics import PlMetrics


class Buffer:
    def __init__(self, size):
        self.data = bytearray(size)
        self.freed = False
        self.device_address = 0x800000000

    def __len__(self):
        return len(self.data)

    def __getitem__(self, key):
        return self.data[key]

    def __setitem__(self, key, value):
        if isinstance(value, int):
            if isinstance(key, slice):
                start, stop, step = key.indices(len(self.data))
                self.data[key] = bytes([value]) * len(range(start, stop, step))
            else:
                self.data[key] = value
        else:
            self.data[key] = bytes(value)

    def flush(self):
        pass

    def invalidate(self):
        pass

    def freebuffer(self):
        self.freed = True


class Channel:
    def __init__(self, idle, output_data=None):
        self._idle = idle
        self.output_data = output_data
        self.stopped = False

    @property
    def idle(self):
        return self._idle

    def transfer(self, buffer):
        self.buffer = buffer
        if self.output_data is not None:
            buffer[:len(self.output_data)] = self.output_data

    def wait(self):
        self._idle = True

    def stop(self):
        self.stopped = True
        self._idle = True


class Dma:
    def __init__(self, recv_idle, output_data=None):
        self.recvchannel = Channel(recv_idle, output_data)
        self.sendchannel = Channel(True)


class Mmio:
    def __init__(self):
        self.count = 0

    def write(self, offset, value):
        if offset == 0x004:
            self.count = int(value)

    def read(self, offset):
        return {0x010: self.count, 0x014: 0, 0x018: 0, 0x020: 11}.get(offset, 0)


class MetricsRecoveryTest(unittest.TestCase):
    def setUp(self):
        # These tests exercise direct DMA with fake PYNQ, including on Linux.
        direct = patch('cas_frontend.pl_metrics.os.geteuid', return_value=0, create=True)
        direct.start()
        self.addCleanup(direct.stop)

    def test_unprivileged_triangle_ray_forwards_supported_arguments(self):
        from unittest.mock import Mock
        client = PlMetrics()
        service = Mock()
        service.evaluate_rays.return_value = {'ok': True}
        client._privileged = service
        raw = bytes(80)
        with patch.dict(os.environ, {'LUNG_PL_ENABLE': '1'}), \
                patch('cas_frontend.pl_metrics.sys.platform', 'linux'), \
                patch('cas_frontend.pl_metrics.os.geteuid', return_value=1000):
            self.assertTrue(client.evaluate_rays(raw, 1, timeout_seconds=.25)['ok'])
        service.evaluate_rays.assert_called_once_with(raw, 1,
            timeout_cycles=50000000, timeout_seconds=.25)

    def test_small_mesh_buffers_reuse_exact_count_and_stride(self):
        client = PlMetrics()
        allocated = []

        def allocate(shape, dtype):
            buffer = Buffer(shape[0])
            allocated.append(buffer)
            return buffer

        self.assertFalse(client._select_mesh_io_buffers(1, 32, allocate))
        first = (client._mesh_ray_input_buf, client._mesh_result_buf)
        self.assertFalse(client._select_mesh_io_buffers(2, 32, allocate))
        second = (client._mesh_ray_input_buf, client._mesh_result_buf)
        self.assertTrue(client._select_mesh_io_buffers(1, 32, allocate))
        self.assertEqual((client._mesh_ray_input_buf, client._mesh_result_buf), first)
        self.assertFalse(client._select_mesh_io_buffers(1, 576, allocate))
        self.assertTrue(client._select_mesh_io_buffers(2, 32, allocate))
        self.assertEqual((client._mesh_ray_input_buf, client._mesh_result_buf), second)
        self.assertEqual(len(allocated), 6)
        client._reset_hardware_state()
        self.assertTrue(all(buffer.freed for buffer in allocated))

    def test_mesh_timeout_resets_fabric_before_free_and_reloads(self):
        client = PlMetrics()
        events = []
        buffers = []
        loads = []
        output = struct.pack('<4I', 1, 1, 20 << 16, 20 << 16)

        class MeshMmio:
            def __init__(self): self.words = {}
            def write(self, offset, value): self.words[offset] = value
            def read(self, offset):
                return {0x000: 0, 0x024: self.words.get(4, 0),
                        0x010: self.words.get(8, 0), 0x014: 1,
                        0x020: 20}.get(offset, self.words.get(offset, 0))

        def load():
            if client._overlay is not None: return
            loads.append(True)
            client._overlay = types.SimpleNamespace(download=lambda: events.append('reset'))
            client._mesh_ddr_mode = client._mesh_metadata = True
            client._mesh_mmio = MeshMmio()
            client._mesh_ray_dma = Dma(True)
            client._mesh_result_dma = Dma(len(loads) > 1, output)

        def allocate(shape, dtype):
            buffer = Buffer(int(shape[0]))
            original = buffer.freebuffer
            def free(): events.append('free'); original()
            buffer.freebuffer = free
            buffers.append(buffer)
            return buffer

        mesh = np.array([[[-10,-10,0],[10,-10,0],[-10,10,0]]],float)
        with patch.dict(os.environ, {'LUNG_PL_ENABLE': '1'}), \
                patch.object(client, '_load', side_effect=load), \
                patch.dict(sys.modules, {'pynq': types.SimpleNamespace(allocate=allocate)}):
            first = client.evaluate_mesh_rays(mesh, [[0,0,20]], [[0,0,-1]], timeout_seconds=.001)
            self.assertFalse(first['ok'])
            self.assertEqual(events[0], 'reset')
            self.assertTrue(all(x.freed for x in buffers))
            second = client.evaluate_mesh_rays(mesh, [[0,0,20]], [[0,0,-1]])
            third = client.evaluate_mesh_rays(mesh, [[0,0,20]], [[0,0,-1]])
            self.assertTrue(second['ok'], second)
            self.assertTrue(third['mesh_reused'])
            self.assertEqual(len(loads), 2)
            self.assertEqual(client._mesh_mmio.read(0x044), 8)
            fourth = client.evaluate_mesh_rays(mesh + [1,0,0], [[0,0,20]], [[0,0,-1]])
            self.assertTrue(fourth['ok'], fourth)
            self.assertFalse(fourth['mesh_reused'])
            client.close()

    def test_reset_failure_retains_ddr_buffers(self):
        client = PlMetrics()
        buffer = Buffer(48)
        client._mesh_buf = buffer
        client._overlay = types.SimpleNamespace(download=lambda: (_ for _ in ()).throw(RuntimeError('download failed')))
        with self.assertRaisesRegex(RuntimeError, 'download failed'):
            client._reset_hardware_state()
        self.assertFalse(buffer.freed)
        self.assertIs(client._mesh_buf, buffer)
        self.assertTrue(client._hardware_reset_failed)
        with self.assertRaisesRegex(RuntimeError, 'download failed'):
            client.close()
        self.assertFalse(buffer.freed)

    def test_recovery_avoids_blocking_pynq_stop(self):
        events=[]
        client=PlMetrics()
        mmio=types.SimpleNamespace(write=lambda offset,value: events.append((offset,value)))
        channel=types.SimpleNamespace(_mmio=mmio,_offset=0x30,
                  stop=lambda: self.fail('blocking stop called'))
        client._mesh_result_dma=types.SimpleNamespace(recvchannel=channel)
        client._overlay=types.SimpleNamespace(download=lambda: events.append('reset'))
        client._reset_hardware_state()
        self.assertEqual(events,[(0x30,0),'reset'])

    def test_ray_timeout_discards_state_and_next_call_reloads(self):
        client = PlMetrics()
        loads = []
        output = struct.pack('<6I', 1, 2, 0, 0, 0, 0) + bytes(8)
        dmas = [Dma(False), Dma(True, output)]

        def load():
            loads.append(True)
            client._ray_dma = dmas.pop(0)
            client._ray_mmio = Mmio()

        def allocate(shape, dtype):
            return Buffer(int(shape[0]))

        raw = struct.pack('<II18i', 1, 2, *([0] * 18))
        fake_pynq = types.SimpleNamespace(allocate=allocate)
        with patch.dict(os.environ, {'LUNG_PL_ENABLE': '1'}), \
                patch.object(client, '_load', side_effect=load), \
                patch.dict(sys.modules, {'pynq': fake_pynq}):
            first = client.evaluate_rays(raw, 1, timeout_seconds=0.001)
            self.assertFalse(first['ok'])
            self.assertIn('timeout', first['error'].lower())
            self.assertIsNone(client._ray_dma)
            self.assertIsNone(client._ray_input_buf)

            # The second fake channel is already idle and returns one valid
            # non-hit record, proving the transaction starts from fresh state.
            second = client.evaluate_rays(raw, 1, timeout_seconds=0.1)

        self.assertTrue(second['ok'], second)
        self.assertEqual(len(loads), 2)
        self.assertEqual(second['processed'], 1)


if __name__ == '__main__':
    unittest.main()
