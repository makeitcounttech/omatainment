"""Remote handoff must be explicitly configured, not use a private host alias."""
from pathlib import Path
import os
import runpy
import unittest
from unittest.mock import Mock, patch
import shlex
import subprocess

class HandoffTests(unittest.TestCase):
    def test_unconfigured_remote_fails_before_credentials_or_network(self):
        with patch.dict(os.environ, {}, clear=True):
            module = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'oma-remux'))
        with self.assertRaisesRegex(RuntimeError, 'OMATAINMENT_REMOTE_SSH'):
            module['handoff']('example-item', 40)

    def configured_handoff(self, destination, url):
        with patch.dict(os.environ, {'OMATAINMENT_REMOTE_SSH': destination, 'OMATAINMENT_REMOTE_REMUX': url}, clear=True):
            module = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'oma-remux'))
        return module['handoff']

    def test_invalid_configuration_fails_before_credentials_or_network(self):
        cases = [
            ('-oProxyCommand=printf BAD', 'http://127.0.0.1:18096'),
            ('alice@' + '-example.com', 'http://127.0.0.1:18096'),
            ('alice@example.com; true', 'http://127.0.0.1:18096'),
            ('alice@exa mple.com', 'http://127.0.0.1:18096'),
            ('alice@example.com', 'http://127.0.0.1:18096; printf BAD'),
            ('alice@example.com', "http://127.0.0.1:18096/a'quote"),
            ('alice@example.com', 'http://127.0.0.1:18096/a space'),
            ('alice@example.com', 'http://127.0.0.1:18096/a;true'),
            ('alice@example.com', 'file:///etc/hosts'),
            ('alice@example.com', 'https://example.com'),
            ('alice@example.com', 'http://alice@localhost:8096'),
            ('alice@example.com', 'http://localhost:99999'),
        ]
        for destination, url in cases:
            with self.subTest(destination=destination, url=url):
                handoff = self.configured_handoff(destination, url)
                config = Mock(return_value=('http://localhost', 'synthetic-token', 'example-user'))
                api = Mock(return_value={'Name': 'Example movie'})
                remote = Mock(return_value=subprocess.CompletedProcess([], 0, '{}', ''))
                with patch.dict(handoff.__globals__, {'config': config, 'api': api}), patch('subprocess.run', remote):
                    with self.assertRaisesRegex(RuntimeError, 'Invalid remote'):
                        handoff('example-item', 40)
                config.assert_not_called()
                api.assert_not_called()
                remote.assert_not_called()

    def test_configured_handoff_preserves_remote_arguments_and_stdin(self):
        for url in ('http://127.0.0.1:18096', 'http://localhost:8096/remux', 'https://[::1]:8096'):
            with self.subTest(url=url):
                handoff = self.configured_handoff('alice@example.com', url)
                remote = Mock(return_value=subprocess.CompletedProcess([], 0, '{"serverId":"example-server","ticks":370000000}', ''))
                with patch.dict(handoff.__globals__, {'config': lambda: ('http://localhost', 'synthetic-token', 'example-user'), 'api': lambda path: {'Name': 'Example movie'}}), patch('subprocess.run', remote):
                    result = handoff('example-item', 40)
                argv = remote.call_args.args[0]
                self.assertEqual(argv[-2], 'alice@example.com')
                self.assertEqual(argv[-3], '--')
                command = shlex.split(argv[-1])
                self.assertEqual(command[:2], ['python3', '-c'])
                self.assertEqual(command[-1], url)
                self.assertEqual(len(command), 4)
                self.assertNotIn('synthetic-token', argv[-1])
                self.assertEqual(remote.call_args.kwargs['input'], 'synthetic-token example-user example-item 370000000\n')
                self.assertTrue(result['positionSynced'])
                # Parse via a real local shell, replacing Python with a no-op argument counter.
                probe = subprocess.run(['/bin/sh', '-c', 'python3() { printf "%s\\n" "$#"; }; ' + argv[-1]], capture_output=True, text=True, check=True)
                self.assertEqual(probe.stdout.strip(), '3')

if __name__ == '__main__':
    unittest.main()
