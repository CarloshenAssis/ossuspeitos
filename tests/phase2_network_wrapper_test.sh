#!/usr/bin/env bash
# Lifecycle checks use fake executable processes; gameplay is tested separately.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
WRAPPER_PID=""
cleanup() {
 local code=$?
 trap - EXIT INT TERM
 if [[ -n "$WRAPPER_PID" ]]; then kill -TERM "$WRAPPER_PID" 2>/dev/null || true; wait "$WRAPPER_PID" 2>/dev/null || true; fi
 rm -rf "$TMP_DIR"
 exit "$code"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
cat > "$TMP_DIR/godot" <<'FAKE'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$$" >> "$FIXTURE_PIDS"
server=false
for arg in "$@"; do [[ "$arg" != --mode=server ]] || server=true; done
if [[ "$server" == true ]]; then echo SERVER_READY; else [[ "$FIXTURE_CASE" != failure ]] || exit 37; fi
exec sleep 60
FAKE
chmod +x "$TMP_DIR/godot"
export GODOT_BIN="$TMP_DIR/godot"
export FIXTURE_PIDS="$TMP_DIR/pids"
export FIXTURE_CASE=failure
code=0
TEST_LOG_DIR="$TMP_DIR/failure" bash "$ROOT/tests/phase2_network_test.sh" > "$TMP_DIR/failure.log" 2>&1 || code=$?
[[ "$code" == 37 ]]
while read -r pid; do ! kill -0 "$pid" 2>/dev/null; done < "$FIXTURE_PIDS"
echo "ASSERT_OK name=original-exit-37-preserved-and-children-reaped"
: > "$FIXTURE_PIDS"
export FIXTURE_CASE=term
TEST_LOG_DIR="$TMP_DIR/term" bash "$ROOT/tests/phase2_network_test.sh" > "$TMP_DIR/term.log" 2>&1 &
WRAPPER_PID=$!
for _ in {1..200}; do [[ "$(wc -l < "$FIXTURE_PIDS")" -ge 5 ]] && break; sleep 0.02; done
[[ "$(wc -l < "$FIXTURE_PIDS")" == 5 ]]
kill -TERM "$WRAPPER_PID"
code=0
wait "$WRAPPER_PID" || code=$?
WRAPPER_PID=""
[[ "$code" == 143 ]]
while read -r pid; do ! kill -0 "$pid" 2>/dev/null; done < "$FIXTURE_PIDS"
echo "ASSERT_OK name=term-143-preserved-and-children-reaped"
echo PHASE2_NETWORK_WRAPPER_TEST_OK
