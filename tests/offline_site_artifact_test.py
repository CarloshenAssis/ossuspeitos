from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/verify_offline_site.py'


class OfflineSiteArtifactTest(unittest.TestCase):
    def make_site(self, directory):
        site = Path(directory)
        demo = site / 'demo'
        demo.mkdir(parents=True)
        (site / 'index.html').write_text(
            '<!doctype html><title>Demonstração offline</title><a href="demo/">Abrir demo</a>', encoding='utf-8')
        for name in ('index.html', 'index.wasm', 'index.pck', 'index.js'):
            (demo / name).write_bytes(b'fake-web-' + name.encode())
        (demo / 'index.pck').write_bytes(
            b'client/visual_demo.gdc client/arena_view.gdc '
            b'mystery_character_ash mystery_character_cedar mystery_character_dawn '
            b'mystery_character_ember mystery_character_moss mystery_character_night '
            b'mystery_character_plum mystery_character_sand offline only')
        return site

    def run_check(self, site):
        return subprocess.run(['python3', str(SCRIPT), str(site)], capture_output=True, text=True)

    def test_accepts_offline_site_with_complete_demo(self):
        with tempfile.TemporaryDirectory() as directory:
            self.make_site(directory)
            result = self.run_check(directory)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('OFFLINE_SITE_OK', result.stdout)

    def test_rejects_missing_web_files(self):
        with tempfile.TemporaryDirectory() as directory:
            self.make_site(directory)
            (Path(directory) / 'demo/index.wasm').unlink()
            self.assertNotEqual(self.run_check(directory).returncode, 0)

    def test_rejects_missing_character_asset(self):
        with tempfile.TemporaryDirectory() as directory:
            self.make_site(directory)
            package = Path(directory) / 'demo/index.pck'
            package.write_bytes(package.read_bytes().replace(b'mystery_character_sand', b'missing_character_sand'))
            self.assertNotEqual(self.run_check(directory).returncode, 0)

    def test_rejects_full_playtest_path(self):
        with tempfile.TemporaryDirectory() as directory:
            self.make_site(directory)
            (Path(directory) / 'playtest').mkdir()
            self.assertNotEqual(self.run_check(directory).returncode, 0)

    def test_rejects_online_link_or_server_endpoint(self):
        for forbidden in ('playtest/', 'wss://ossuspeitos-production.up.railway.app'):
            with self.subTest(forbidden=forbidden), tempfile.TemporaryDirectory() as directory:
                self.make_site(directory)
                (Path(directory) / 'index.html').write_text(forbidden, encoding='utf-8')
                self.assertNotEqual(self.run_check(directory).returncode, 0)

    def test_rejects_online_client_code_in_packed_demo(self):
        with tempfile.TemporaryDirectory() as directory:
            self.make_site(directory)
            (Path(directory) / 'demo/index.pck').write_bytes(b'visual only; connect_to_url')
            self.assertNotEqual(self.run_check(directory).returncode, 0)


if __name__ == '__main__':
    unittest.main()
