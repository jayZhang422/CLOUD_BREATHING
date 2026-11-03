"""Regression for PYNQ's asyncio setup on a Qt-created Python Dummy thread."""
import asyncio
import os
import sys
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from PySide6.QtCore import QThread
from cas_frontend import pl_metrics as pl


class Worker(QThread):
    def run(self):
        self.error = None
        self.client = pl.PlMetrics()
        try:
            self.python_thread = threading.current_thread().name
            with self._assert_no_loop():
                asyncio.get_event_loop()
            self.client._load()
            self.loop = asyncio.get_event_loop()
            self.client._load()
            assert asyncio.get_event_loop() is self.loop
            assert not self.loop.is_closed()
        except BaseException as exc:
            self.error = exc
        finally:
            self.client.close()

    @staticmethod
    def _assert_no_loop():
        return unittest.TestCase().assertRaises(RuntimeError)


class WorkerLoopTest(unittest.TestCase):
    def test_overlay_initialization_in_qt_worker(self):
        loops = []

        def overlay(*args, **kwargs):
            # Reproduce PYNQ's requirement at Overlay/interrupt setup time.
            loops.append(asyncio.get_event_loop())
            return type("Overlay", (), {"dma": object()})()

        class MMIO:
            def __init__(self, *args):
                pass

            def read(self, offset):
                return pl.ABI_VERSION

        with patch.dict(os.environ, {'LUNG_PL_BIT': __file__, 'LUNG_PL_ENABLE': '1'}), \
                patch.object(pl, "_import_pynq", return_value=(overlay, None, MMIO)):
            worker = Worker()
            worker.start()
            self.assertTrue(worker.wait(10000))
        if worker.error:
            raise worker.error
        self.assertTrue(worker.python_thread.startswith("Dummy-"))
        self.assertEqual(len(loops), 1)
        self.assertIs(loops[0], worker.loop)
        self.assertTrue(worker.loop.is_closed())


if __name__ == "__main__":
    unittest.main()
