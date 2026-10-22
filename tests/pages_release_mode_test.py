import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/pages_release_policy.py'
SHA = 'a' * 40


class PagesReleaseModeTest(unittest.TestCase):
    def policy(self, mode, event='workflow_dispatch', ref='refs/heads/main', sha=SHA, approved=SHA):
        env = dict(os.environ, RELEASE_EVENT=event, RELEASE_REF=ref,
                   RELEASE_SHA=sha, RELEASE_APPROVED_SHA=approved,
                   RELEASE_MODE=mode)
        return subprocess.run(['python3', str(SCRIPT)], env=env, capture_output=True, text=True)

    def test_offline_and_online_modes_require_explicit_exact_main_dispatch(self):
        for mode in ('offline', 'online'):
            for event, ref, sha, approved, expected in [
                ('workflow_dispatch', 'refs/heads/main', SHA, SHA, True),
                ('workflow_dispatch', 'refs/heads/main', SHA, '', False),
                ('workflow_dispatch', 'refs/heads/main', SHA, 'b' * 40, False),
                ('workflow_dispatch', 'refs/heads/main', 'short', 'short', False),
                ('workflow_dispatch', 'refs/heads/feature', SHA, SHA, False),
                ('push', 'refs/heads/main', SHA, SHA, False),
                ('pull_request', 'refs/heads/main', SHA, SHA, False),
            ]:
                with self.subTest(mode=mode, event=event, ref=ref, approved=approved):
                    result = self.policy(mode, event, ref, sha, approved)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn('allowed=' + str(expected).lower(), result.stdout)
                    self.assertIn('publication_mode=' + mode, result.stdout)

        for mode in ('', 'railway', 'OFFLINE'):
            with self.subTest(mode=mode):
                result = self.policy(mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('allowed=false', result.stdout)
                self.assertIn('publication_mode=invalid', result.stdout)


if __name__ == '__main__':
    unittest.main()
