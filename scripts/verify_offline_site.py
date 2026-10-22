#!/usr/bin/env python3
"""Fail closed if a GitHub Pages artifact contains anything but the offline demo."""
import argparse
from pathlib import Path
import re
import sys

FORBIDDEN_PUBLIC_TEXT = (
    re.compile(rb'wss://ossuspeitos-production\.up\.railway\.app', re.I),
    re.compile(rb'(?:^|["\' ])/?playtest(?:/|["\' ?#])', re.I),
    re.compile(rb'web_playtest|online-url|CLIENT_CONNECTING|CRIAR SALA|ENTRAR EM SALA', re.I),
)
FORBIDDEN_PACKED_CODE = (
    re.compile(rb'wss://|ossuspeitos-production\.up\.railway\.app|online-url|web_playtest|CLIENT_CONNECTING', re.I),
    re.compile(rb'start_client|connect_to_url|transport\.connect_to_url', re.I),
    re.compile(rb'client/(?:online_endpoint|websocket_client_transport|desktop_menu)\.gdc', re.I),
)
REQUIRED_WEB_FILES = ('index.html', 'index.wasm', 'index.pck', 'index.js')
REQUIRED_CHARACTER_ASSETS = (
    b'mystery_character_ash', b'mystery_character_cedar',
    b'mystery_character_dawn', b'mystery_character_ember',
    b'mystery_character_moss', b'mystery_character_night',
    b'mystery_character_plum', b'mystery_character_sand',
)


def verify(site: Path):
    if not site.is_dir():
        raise ValueError(f'not a directory: {site}')
    landing = site / 'index.html'
    if not landing.is_file():
        raise ValueError('missing offline site index.html')
    public_files = [path for path in site.rglob('*') if path.is_file()]
    if (site / 'playtest').exists() or any(
            'playtest' in tuple(part.lower() for part in path.relative_to(site).parts)
            for path in public_files):
        raise ValueError('offline site contains /playtest/')
    demo = site / 'demo'
    for name in REQUIRED_WEB_FILES:
        artifact = demo / name
        if not artifact.is_file() or artifact.stat().st_size == 0:
            raise ValueError(f'missing nonempty demo/{name}')
    text_payload = b'\n'.join(
        path.read_bytes() for path in public_files
        if path.suffix.lower() in {'.html', '.js', '.css', '.json', '.svg', '.txt'})
    for forbidden in FORBIDDEN_PUBLIC_TEXT:
        if forbidden.search(text_payload):
            raise ValueError(f'offline artifact contains forbidden online content: {forbidden.pattern.decode()}')
    packed_demo = (demo / 'index.pck').read_bytes()
    for forbidden in FORBIDDEN_PACKED_CODE:
        if forbidden.search(packed_demo):
            raise ValueError(f'offline Web package contains online executable content: {forbidden.pattern.decode()}')
    if not re.search(rb'visual_demo\.gdc', packed_demo) or not re.search(rb'arena_view\.gdc', packed_demo):
        raise ValueError('offline Web package is missing the visual demo or arena presentation')
    missing_models = [name.decode() for name in REQUIRED_CHARACTER_ASSETS if name not in packed_demo]
    if missing_models:
        raise ValueError('offline Web package is missing character models: ' + ', '.join(missing_models))
    if not re.search(rb'demo/', landing.read_bytes(), re.I):
        raise ValueError('offline landing does not link to demo/')
    return len(public_files)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('site', type=Path)
    args = parser.parse_args()
    try:
        count = verify(args.site)
    except (OSError, ValueError) as error:
        print(f'OFFLINE_SITE_BLOCKED {error}', file=sys.stderr)
        return 1
    print(f'OFFLINE_SITE_OK files={count}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
