#!/usr/bin/env python3
"""Fail-closed Pages release approval and strict production probe validation."""
import argparse
import os
from pathlib import Path
import re


def allow_release(event, ref, sha, approved, mode):
    return (event == 'workflow_dispatch' and ref == 'refs/heads/main'
            and mode in {'offline', 'online'}
            and re.fullmatch(r'[0-9a-f]{40}', sha) is not None and approved == sha)


def valid_probe(code, log, protocol):
    if code != 0 or not re.fullmatch(r'[1-9][0-9]*', protocol):
        return False
    if any('SCRIPT ERROR' in line or 'Parse Error' in line or line.startswith('ERROR:') for line in log.splitlines()):
        return False
    pattern = (r'^PROBE_OK \S+ result=joined detail=peer_id=[1-9][0-9]* '
               r'snapshots=[1-9][0-9]* round_state=[A-Z]+(?: room=[a-z]+)? protocol='
               + re.escape(protocol) + r' elapsed_ms=[0-9]+$')
    return any(re.fullmatch(pattern, line) for line in log.splitlines())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--verify-probe', type=Path)
    parser.add_argument('--exit-code', type=int)
    parser.add_argument('--protocol')
    args = parser.parse_args()
    if args.verify_probe is not None:
        accepted = valid_probe(args.exit_code, args.verify_probe.read_text(), args.protocol or '')
        print('PAGES_PRODUCTION_PROTOCOL_' + ('OK' if accepted else 'BLOCKED'))
        return 0 if accepted else 1
    mode = os.environ.get('RELEASE_MODE', '')
    allowed = allow_release(*(os.environ.get(key, '') for key in
        ['RELEASE_EVENT', 'RELEASE_REF', 'RELEASE_SHA', 'RELEASE_APPROVED_SHA']), mode)
    print('allowed=' + str(allowed).lower())
    print('publication_mode=' + (mode if mode in {'offline', 'online'} else 'invalid'))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
