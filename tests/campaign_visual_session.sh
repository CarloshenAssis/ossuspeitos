#!/usr/bin/env bash
# Fase 5, sessão gráfica: a mesma campanha de 8 clientes e 3 rodadas, com ator
# e observador em clientes gráficos reais (xvfb, OpenGL) e 6 clientes
# automatizados headless. Os dois gráficos entram primeiro (ordem de entrada
# 0 e 1); com a seed padrão nenhum deles é o assassino na rodada 1, e o
# coordenador falha explicitamente (VISUAL_SEED_UNSUITABLE) se for.
# Grava quadros JPG + telemetria CSV por cena em OUT e, se houver ffmpeg,
# uma prancha de quadros (PNG) e, se houver ffmpeg, um vídeo WebM por cena.
# Não entra no CI.
# Uso: PROFILE=local|rtt150j SEED=1 OUT=/tmp/visual [FFMPEG=...] tests/campaign_visual_session.sh
set -eEuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$(command -v godot4 || command -v godot)}"
FFMPEG="${FFMPEG:-$(command -v ffmpeg || true)}"
PROFILE="${PROFILE:-local}"
SEED="${SEED:-1}"
RESOLUTION="${RESOLUTION:-960x540}"
OUT="${OUT:-$(mktemp -d)}"; mkdir -p "$OUT/frames"
PORT="${TEST_PORT:-$((29080 + RANDOM % 1000))}"
SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
PIDS=(); NAMES=()
cleanup() { local status=$?; trap - EXIT; for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done; for pid in "${PIDS[@]:-}"; do wait "$pid" 2>/dev/null || true; done; exit "$status"; }
trap cleanup EXIT
wait_marker() { local p=$1 f=$2 pid=$3 limit=$4; for _ in $(seq 1 $((limit * 20))); do grep -qE -- "$p" "$f" && return 0; kill -0 "$pid" 2>/dev/null || return 1; sleep 0.05; done; return 1; }
echo "VISUAL_STAGE start profile=$PROFILE seed=$SEED sha=$SHA out=$OUT"
"$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 --port="$PORT" --countdown-seconds=3 \
  --round-end-delay-seconds=6 --round-seed="$SEED" --campaign-test=true --sync-visual=true --sync-profile="$PROFILE" >"$OUT/server.log" 2>&1 &
SERVER_PID=$!; PIDS+=("$SERVER_PID"); NAMES+=(server)
wait_marker 'SERVER_READY' "$OUT/server.log" "$SERVER_PID" 20
for id in $(seq 1 8); do
  NET_ARGS=()
  if [[ "$PROFILE" != local ]]; then NET_ARGS=(--test-net-profile="$PROFILE" --test-net-seed="$((SEED * 100 + id))"); fi
  if (( id <= 2 )); then
    xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT_BIN" --path "$ROOT" --rendering-driver opengl3 --resolution "$RESOLUTION" -- \
      --mode=client --client-id="client-$id" --url="ws://127.0.0.1:$PORT" --campaign-test=true --sync-visual=true \
      --sync-visual-out="$OUT/frames" --sync-visual-every=2 --sync-visual-format=jpg "${NET_ARGS[@]}" >"$OUT/client-$id.log" 2>&1 &
    PIDS+=("$!"); NAMES+=("client-$id-graphical")
    wait_marker 'JOIN_ACCEPTED' "$OUT/client-$id.log" "${PIDS[-1]}" 60
  else
    "$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id="client-$id" --url="ws://127.0.0.1:$PORT" \
      --campaign-test=true --sync-visual=true "${NET_ARGS[@]}" >"$OUT/client-$id.log" 2>&1 &
    PIDS+=("$!"); NAMES+=("client-$id")
  fi
done
STATUS=0
for i in "${!PIDS[@]}"; do
  if wait "${PIDS[$i]}"; then s=0; else s=$?; fi
  echo "PROCESS_STATUS name=${NAMES[$i]} status=$s"
  (( s == 0 )) || STATUS=1
done
PIDS=()
grep -hE 'CAMPAIGN_(VISUAL_ACTORS|ROUND_RESULT|SERVER_OK)|SYNC_TEST_FAILED|SERVER_SHUTDOWN_COMPLETE' "$OUT/server.log"
grep -hE 'SYNC_VISUAL_RECORDED' "$OUT"/client-*.log
grep -q 'CAMPAIGN_SERVER_OK clients=8 rounds=3' "$OUT/server.log" || STATUS=1
(( STATUS == 0 )) || { echo "CAMPAIGN_VISUAL_SESSION_FAILED out=$OUT" >&2; exit 1; }

# Prancha por cena (Godot, sem dependência) e vídeo WebM se houver ffmpeg.
mkdir -p "$OUT/video" "$OUT/sheets"
for first in "$OUT"/frames/*_0000.jpg; do
  scene="$(basename "$first" _0000.jpg)"
  "$GODOT_BIN" --headless --path "$ROOT" --script tests/visual_contact_sheet.gd -- "$OUT/frames" "$scene" "$OUT/sheets/$scene.png" | grep CONTACT_SHEET
  if [[ -n "$FFMPEG" ]]; then
    # Quadros concatenados num fluxo MJPEG (image2pipe): funciona também em
    # builds mínimos do ffmpeg, sem o demuxer de sequência de imagens.
    cat "$OUT"/frames/"${scene}"_*.jpg >"$OUT/video/$scene.mjpeg"
    "$FFMPEG" -loglevel error -y -framerate 15 -f image2pipe -c:v mjpeg -i "file:$OUT/video/$scene.mjpeg" \
      -c:v libvpx -b:v 1500k "file:$OUT/video/$scene.webm"
    rm -f "$OUT/video/$scene.mjpeg"
  fi
done
echo "CAMPAIGN_VISUAL_SESSION_OK profile=$PROFILE seed=$SEED sha=$SHA out=$OUT"
