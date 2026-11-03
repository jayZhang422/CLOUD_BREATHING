"""Detect a successful exit without the expected XRT metadata file."""
import contextlib
import io
import json
import subprocess
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.check_xclbinutil import check_xclbinutil


class GenerationTests(unittest.TestCase):
    def run_check(self, returncode, create_output):
        module = types.ModuleType('pynq.pl_server.embedded_device')
        module.BLANK_METADATA = '<project/>'
        module._ip_to_topology = lambda _: {'mem_topology': {}}
        log = io.StringIO()

        def run(command, cwd, **kwargs):
            self.assertIn('--skip-bank-grouping', command)
            self.assertEqual(json.loads((cwd / 'mem.json').read_text()),
                             {'mem_topology': {}})
            if create_output:
                (cwd / 't.xclbin').write_bytes(b'generated data')
            return subprocess.CompletedProcess(command, returncode, stdout=b'tool detail')

        with patch.dict(sys.modules, {'pynq.pl_server.embedded_device': module}), \
                patch('tools.check_xclbinutil.shutil.which', return_value='/usr/bin/xclbinutil'), \
                patch('tools.check_xclbinutil.subprocess.run', side_effect=run), \
                contextlib.redirect_stderr(log):
            if returncode != 0 or not create_output:
                with self.assertRaisesRegex(RuntimeError, 'PL_XCLBINUTIL'):
                    check_xclbinutil()
            else:
                check_xclbinutil()
        details = json.loads(log.getvalue().split(' ', 1)[1])
        self.assertEqual(details['returncode'], returncode)
        self.assertEqual(details['output_created'], create_output)
        self.assertEqual(details['output'], 'tool detail')

    def test_exit_zero_without_output(self):
        self.run_check(0, False)

    def test_tool_error(self):
        self.run_check(1, False)

    def test_output_generated(self):
        self.run_check(0, True)


if __name__ == '__main__':
    unittest.main()
