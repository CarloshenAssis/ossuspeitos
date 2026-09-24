#!/usr/bin/env bash
# Medida reproduzível de resposta local e suavidade remota (fase 4).
# Servidor headless + observador e "mover" gráficos (xvfb) + 2 clientes
# headless parados, para a rodada entrar em ACTIVE (mínimo de 4).
# Uso: PROFILE=local|rtt80|rtt150j SEED=1 tests/latency_probe.sh
# Não entra no CI: exige xvfb e mede o ambiente em que roda.
set -eEuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$(command -v godot4 || command -v godot)}"
PROFILE="${PROFILE:-local}"
SEED="${SEED:-1}"
RESOLUTION="${RESOLUTION:-640x360}"
PORT="${TEST_PORT:-$((25080 + RANDOM % 1000))}"
OUT="${TEST_LOG_DIR:-$(mktemp -d)}"; mkdir -p "$OUT"
PIDS=()

cleanup() {
  local status=$?
  trap - EXIT
  for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  for pid in "${PIDS[@]:-}"; do wait "$pid" 2>/dev/null || true; done
  exit "$status"
}
trap cleanup EXIT

wait_marker() { local p=$1 f=$2 pid=$3 limit=$4; for _ in $(seq 1 $((limit * 20))); do grep -qE -- "$p" "$f" && return 0; kill -0 "$pid" 2>/dev/null || return 1; sleep 0.05; done; return 1; }

NET_ARGS=()
if [[ "$PROFILE" != "none" ]]; then NET_ARGS=(--test-net-profile="$PROFILE" --test-net-seed="$SEED"); fi

"$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 --port="$PORT" \
  --countdown-seconds=1 --round-seed="$SEED" >"$OUT/server.log" 2>&1 &
SERVER_PID=$!; PIDS+=("$SERVER_PID")
wait_marker 'SERVER_READY' "$OUT/server.log" "$SERVER_PID" 20
xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT_BIN" --path "$ROOT" --rendering-driver opengl3 --resolution "$RESOLUTION" -- \
  --mode=client --client-id=observer --url="ws://127.0.0.1:$PORT" --latency-probe=observer --latency-probe-seed="$SEED" \
  "${NET_ARGS[@]}" >"$OUT/observer.log" 2>&1 &
OBSERVER_PID=$!; PIDS+=("$OBSERVER_PID")
wait_marker 'JOIN_ACCEPTED' "$OUT/observer.log" "$OBSERVER_PID" 60
xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT_BIN" --path "$ROOT" --rendering-driver opengl3 --resolution "$RESOLUTION" -- \
  --mode=client --client-id=mover --url="ws://127.0.0.1:$PORT" --latency-probe=mover "${NET_ARGS[@]}" >"$OUT/mover.log" 2>&1 &
MOVER_PID=$!; PIDS+=("$MOVER_PID")
wait_marker 'JOIN_ACCEPTED' "$OUT/mover.log" "$MOVER_PID" 60
for id in 1 2; do
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id="idle-$id" --url="ws://127.0.0.1:$PORT" >"$OUT/idle-$id.log" 2>&1 &
  PIDS+=("$!")
done
wait_marker 'LATENCY_PROBE_DONE' "$OUT/observer.log" "$OBSERVER_PID" 180
echo "LATENCY_PROBE profile=$PROFILE seed=$SEED resolution=$RESOLUTION commit=$(git -C "$ROOT" rev-parse --short HEAD)"
grep -E 'LATENCY_PROBE_(RESULT|NET|TIMEOUT)|TEST_NET_PROFILE' "$OUT/observer.log"
