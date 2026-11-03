import os
import unittest
from unittest.mock import patch

from cas_frontend.pl_privileged import PrivilegedPlClient


class AuthorizationTests(unittest.TestCase):
    def test_explicit_sudo_remains_noninteractive_and_uses_same_helper(self):
        with patch.dict(os.environ, {'CLOUD_BREATHING_PL_AUTH': 'sudo'}), \
                patch('shutil.which', return_value='/usr/bin/sudo'), \
                patch('pathlib.Path.is_file', return_value=True):
            command = PrivilegedPlClient('unused.bit', require_strict_pl=True)._command()
        self.assertEqual(command[:3], ['/usr/bin/sudo', '-n', '/bin/bash'])
        self.assertTrue(command[3].endswith('start_pl_service.sh'))
        self.assertIn('--strict-pl', command)

    def test_default_pkexec_and_invalid_choice(self):
        with patch.dict(os.environ, {'CLOUD_BREATHING_PL_AUTH': 'pkexec'}), \
                patch('shutil.which', return_value='/usr/bin/pkexec'), \
                patch('pathlib.Path.is_file', return_value=True):
            self.assertEqual(PrivilegedPlClient('unused.bit')._command()[:2],
                             ['/usr/bin/pkexec', '--disable-internal-agent'])
        with patch.dict(os.environ, {'CLOUD_BREATHING_PL_AUTH': 'unknown'}):
            with self.assertRaises(ValueError):
                PrivilegedPlClient('unused.bit')._command()
