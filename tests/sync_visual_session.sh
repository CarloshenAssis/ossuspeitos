#!/usr/bin/env bash
# Fase 4, camada C: sessão gráfica real (xvfb) com o coordenador de
# sincronização em modo visual. Servidor headless, três clientes gráficos
# (ator e observador saem deles) e um headless. Grava quadros PNG e telemetria
# por cena em OUT. Não entra no CI (exige xvfb e renderização).
# Uso: PROFILE=local|rtt80|rtt150j SEED=1 OUT=/tmp/visual tests/sync_visual_session.sh
set -eEuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$(command -v godot4 || command -v godot)}"
PROFILE="${PROFILE:-rtt150j}"
SEED="${SEED:-1}"
RESOLUTION="${RESOLUTION:-640x360}"
OUT="${OUT:-$(mktemp -d)}"; mkdir -p "$OUT"
PORT="${TEST_PORT:-$((27080 + RANDOM % 1000))}"
PIDS=()
cleanup() { local status=$?; trap - EXIT; for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done; for pid in "${PIDS[@]:-}"; do wait "$pid" 2>/dev/null || true; done; exit "$status"; }
trap cleanup EXIT
wait_marker() { local p=$1 f=$2 pid=$3 limit=$4; for _ in $(seq 1 $((limit * 20))); do grep -qE -- "$p" "$f" && return 0; kill -0 "$pid" 2>/dev/null || return 1; sleep 0.05; done; return 1; }
NET_ARGS=()
if [[ "$PROFILE" != "local" ]]; then NET_ARGS=(--test-net-profile="$PROFILE"); fi
"$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 --port="$PORT" --countdown-seconds=0.5 \
  --round-end-delay-seconds=2 --round-seed="$SEED" --sync-test=true --sync-visual=true --sync-profile="$PROFILE" >"$OUT/server.log" 2>&1 &
SERVER_PID=$!; PIDS+=("$SERVER_PID")
wait_marker 'SERVER_READY' "$OUT/server.log" "$SERVER_PID" 20
for id in 1 2 3; do
  xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT_BIN" --path "$ROOT" --rendering-driver opengl3 --resolution "$RESOLUTION" -- \
    --mode=client --client-id="client-$id" --url="ws://127.0.0.1:$PORT" --sync-test=true --sync-visual=true \
    --sync-visual-out="$OUT" "${NET_ARGS[@]}" --test-net-seed="$((SEED * 10 + id))" >"$OUT/client-$id.log" 2>&1 &
  PIDS+=("$!")
  wait_marker 'JOIN_ACCEPTED' "$OUT/client-$id.log" "${PIDS[-1]}" 60
done
"$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id=client-4 --url="ws://127.0.0.1:$PORT" --sync-test=true \
  --sync-visual=true "${NET_ARGS[@]}" --test-net-seed="$((SEED * 10 + 4))" >"$OUT/client-4.log" 2>&1 &
PIDS+=("$!")
wait_marker 'SERVER_SHUTDOWN_COMPLETE' "$OUT/server.log" "$SERVER_PID" 240
grep -hE 'SYNC_(ROLES|VISUAL|STAGE_ENTER)|SERVER_SHUTDOWN_COMPLETE' "$OUT/server.log"
grep -hE 'SYNC_VISUAL_RECORDED' "$OUT"/client-*.log
echo "SYNC_VISUAL_SESSION_OK profile=$PROFILE seed=$SEED out=$OUT commit=$(git -C "$ROOT" rev-parse --short HEAD)"
