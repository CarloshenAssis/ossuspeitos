#!/usr/bin/env bash
# Deterministic wrapper lifecycle tests; no Godot or production endpoints.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT/tests/gameplay_integration_test.sh" <<'PY'
import os, pathlib, signal, subprocess, sys, tempfile, time
with tempfile.TemporaryDirectory() as temp:
    root = pathlib.Path(temp)
    tests = root / 'tests'
    tests.mkdir()
    wrapper = tests / 'gameplay_integration_test.sh'
    wrapper.write_text(pathlib.Path(sys.argv[1]).read_text())
    fake = root / 'godot'
    fake.write_text('''#!/usr/bin/env bash
if [[ "$STAGE" == fail ]]; then exit 37; fi
if [[ "$STAGE" != scene ]]; then echo 'GAMEPLAY_INTEGRATION_SCENE_OK checks=1'; exit; fi
exec bash "$FIXTURE_TESTS/hold.sh"
''')
    fake.chmod(0o755)
    (tests / 'hold.sh').write_text('''#!/usr/bin/env bash
sleep 60 & child=$!
echo "$BASHPID $child" > "$PID_FILE"
trap 'kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; exit 143' TERM
wait "$child"
''')
    (tests / 'combat_network_test.sh').write_text('''#!/usr/bin/env bash
if [[ "$STAGE" == campaign ]]; then echo 'COMBAT_NETWORK_TEST_OK server=1 clients=4 extended=false'; exit; fi
exec bash "$FIXTURE_TESTS/hold.sh"
''')
    (tests / 'campaign_test.sh').write_text('exec bash "$FIXTURE_TESTS/hold.sh"\n')
    for stage in ['fail', 'scene', 'combat', 'campaign']:
        pid_file = root / ('pids-' + stage)
        env = dict(os.environ, GODOT_BIN=str(fake), FIXTURE_TESTS=str(tests),
                   PID_FILE=str(pid_file), STAGE=stage, TEST_LOG_DIR=str(root / 'logs'), RUN_CAMPAIGN='true')
        process = subprocess.Popen(['bash', str(wrapper)], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if stage == 'fail':
            output, _ = process.communicate(timeout=5)
            assert process.returncode == 37 and 'GAMEPLAY_INTEGRATION_TEST_OK' not in output
            continue
        deadline = time.monotonic() + 5
        while not pid_file.exists() and time.monotonic() < deadline:
            assert process.poll() is None
            time.sleep(.01)
        assert pid_file.exists(), stage
        pids = [int(value) for value in pid_file.read_text().split()]
        process.send_signal(signal.SIGTERM)
        output, _ = process.communicate(timeout=5)
        assert process.returncode == 143 and 'GAMEPLAY_INTEGRATION_TEST_OK' not in output, (stage, output)
        for pid in pids:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                pass
            else:
                raise AssertionError((stage, 'owned process survived', pid))
print('GAMEPLAY_INTEGRATION_WRAPPER_TEST_OK exit37=true term=scene,combat,campaign')
PY
