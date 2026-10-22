#!/usr/bin/env python3
"""Run every SceneTree suite with bounded runtime and strict engine-error gates."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--logs', required=True, type=Path)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    root = args.root.resolve()
    args.logs.mkdir(parents=True, exist_ok=True)
    godot = os.environ.get('GODOT_BIN', 'godot')
    version = subprocess.check_output([godot, '--version'], text=True).strip()
    if not version.startswith('4.4.1.'):
        raise SystemExit(f'Expected Godot4.4.1; received {version}')
    results = []
    for path in sorted((root / 'tests').glob('*_test.gd')):
        if 'extends SceneTree' not in path.read_text():
            continue
        started = time.monotonic()
        log = args.logs / (path.stem + '.log')
        with log.open('w') as stream:
            try:
                code = subprocess.run([godot, '--headless', '--path', str(root), '--script', str(path.relative_to(root))], cwd=root, stdout=stream, stderr=subprocess.STDOUT, timeout=120).returncode
            except subprocess.TimeoutExpired:
                code = 124
        lines = log.read_text().splitlines()
        errors = [line for line in lines if 'SCRIPT ERROR' in line or 'Parse Error' in line or line.startswith('ERROR:')]
        markers = [line for line in lines if '_TEST_OK' in line or line.startswith('GAMEPLAY_INTEGRATION_SCENE_OK checks=')]
        result = {'test': path.name, 'exit': code, 'seconds': round(time.monotonic() - started, 3), 'errors': errors, 'markers': markers, 'status': 'PASS' if code == 0 and markers and not errors else 'FAIL'}
        results.append(result)
        print(json.dumps(result), flush=True)
        (args.logs / 'results.json').write_text(json.dumps({'godot': version, 'results': results}, indent=2))
    return 0 if results and all(row['status'] == 'PASS' for row in results) else 1


if __name__ == '__main__':
    sys.exit(main())
