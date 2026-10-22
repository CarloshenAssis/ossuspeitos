import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/pages_release_policy.py'
SHA = 'a' * 40

class PagesReleasePolicyTest(unittest.TestCase):
    def policy(self, event, ref, sha, approved):
        env = dict(os.environ, RELEASE_EVENT=event, RELEASE_REF=ref,
                   RELEASE_SHA=sha, RELEASE_APPROVED_SHA=approved,
                   RELEASE_MODE='online')
        return subprocess.run(['python3', str(SCRIPT)], env=env, capture_output=True, text=True)

    def test_only_explicit_dispatch_for_exact_main_commit_can_publish(self):
        for event, ref, sha, approved, expected in [
            ('push', 'refs/heads/main', SHA, SHA, False),
            ('pull_request', 'refs/heads/main', SHA, SHA, False),
            ('workflow_dispatch', 'refs/heads/feature', SHA, SHA, False),
            ('workflow_dispatch', 'refs/heads/main', SHA, '', False),
            ('workflow_dispatch', 'refs/heads/main', SHA, 'b'*40, False),
            ('workflow_dispatch', 'refs/heads/main', 'short', 'short', False),
            ('workflow_dispatch', 'refs/heads/main', SHA, SHA, True),
        ]:
            with self.subTest(event=event, ref=ref, approved=approved):
                result = self.policy(event, ref, sha, approved)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('allowed=' + str(expected).lower(), result.stdout)

    def test_probe_requires_joined_snapshot_matching_protocol_and_clean_exit(self):
        good = 'PROBE_OK url=wss://example.invalid result=joined detail=peer_id=123 snapshots=2 round_state=WAITING room=private protocol=12 elapsed_ms=42\n'
        for code, log, protocol, accepted in [
            (0, good, '12', True),
            (0, good, '11', False),
            (1, good, '12', False),
            (0, good.replace('snapshots=2', 'snapshots=0'), '12', False),
            (0, 'PROBE_FAILED id=release reason=join_rejected:protocol_version\n', '12', False),
            (0, 'PROBE_OK id=release result=refused detail=room_full protocol=12\n', '12', False),
            (0, good + 'SCRIPT ERROR: invalid data\n', '12', False),
            (0, good + 'ERROR: rpc failed\n', '12', False),
            (0, '', '12', False),
        ]:
            with self.subTest(code=code, log=log):
                with tempfile.TemporaryDirectory() as directory:
                    path = Path(directory) / 'probe.log'
                    path.write_text(log)
                    result = subprocess.run(['python3', str(SCRIPT), '--verify-probe', str(path), '--exit-code', str(code), '--protocol', protocol], capture_output=True, text=True)
                    self.assertEqual(result.returncode == 0, accepted, result.stdout + result.stderr)

if __name__ == '__main__':
    unittest.main()
