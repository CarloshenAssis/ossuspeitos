#!/usr/bin/env bash
# Fase 11, sessão gráfica de rede: o teste de combate real (servidor
# autoritativo, coleta oficial, disparos, impacto em parede e em jogador,
# eliminação, espectador e rodada seguinte) com 4 clientes, dois deles com
# janela (xvfb, OpenGL). Os gráficos gravam uma captura por situação oficial
# (`--presence-capture-dir`, só binário de desenvolvimento). Não entra no CI:
# exige xvfb e renderiza por software (sem GPU real).
# Uso: OUT=/tmp/presence CLIENTS=4 tests/presence_visual_session.sh
set -eEuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$(command -v godot4 || command -v godot)}"
CLIENTS="${CLIENTS:-4}"
RESOLUTION="${RESOLUTION:-960x540}"
OUT="${OUT:-$(mktemp -d)}"; mkdir -p "$OUT/captures"
PORT="${TEST_PORT:-$((27080 + RANDOM % 1000))}"
PIDS=(); NAMES=()
cleanup() { local status=$?; trap - EXIT; for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done; wait 2>/dev/null || true; exit "$status"; }
trap cleanup EXIT
"$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 --port="$PORT" --countdown-seconds=3 \
  --round-end-delay-seconds=4 --round-seed=20250915 --combat-test=true --combat-clients="$CLIENTS" \
  --combat-extended=true >"$OUT/server.log" 2>&1 &
SERVER_PID=$!; PIDS+=("$SERVER_PID"); NAMES+=(server)
for _ in {1..200}; do grep -q SERVER_READY "$OUT/server.log" && break; sleep 0.05; done
for id in $(seq 1 "$CLIENTS"); do
  if (( id <= 2 )); then
    xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT_BIN" --path "$ROOT" --rendering-driver opengl3 --resolution "$RESOLUTION" -- \
      --mode=client --client-id="client-$id" --url="ws://127.0.0.1:$PORT" --combat-test=true --combat-clients="$CLIENTS" \
      --combat-extended=true --presence-capture-dir="$OUT/captures" >"$OUT/client-$id.log" 2>&1 &
    NAMES+=("client-$id-graphical")
  else
    "$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id="client-$id" --url="ws://127.0.0.1:$PORT" \
      --combat-test=true --combat-clients="$CLIENTS" --combat-extended=true >"$OUT/client-$id.log" 2>&1 &
    NAMES+=("client-$id")
  fi
  PIDS+=("$!")
done
STATUS=0
for i in "${!PIDS[@]}"; do
  if wait "${PIDS[$i]}"; then s=0; else s=$?; fi
  echo "PROCESS_STATUS name=${NAMES[$i]} status=$s"
  (( s == 0 )) || STATUS=1
done
PIDS=()
grep -hE "COMBAT_SERVER_TEST_OK|COMBAT_NEW_ROUND_OK|COMBAT_SPECTATOR_SERVER_OK" "$OUT/server.log" || STATUS=1
grep -hE "PRESENCE_SESSION_CAPTURE" "$OUT"/client-*.log | sort
grep -hE "SCRIPT ERROR" "$OUT"/*.log && STATUS=1
(( STATUS == 0 )) || { echo "PRESENCE_VISUAL_SESSION_FAILED out=$OUT" >&2; exit 1; }
echo "PRESENCE_VISUAL_SESSION_OK clients=$CLIENTS graphical=2 captures=$(ls "$OUT/captures" | wc -l | tr -d ' ') out=$OUT"
