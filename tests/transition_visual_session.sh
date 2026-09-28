#!/usr/bin/env bash
set -Eeuo pipefail

# Fase 10: medição das transições com um cliente gráfico real (xvfb, OpenGL)
# e 3 clientes headless numa sala, 2 rodadas curtas. Imprime o relatório das
# linhas TRANSITION e confere o pré-aquecimento da mansão: a primeira troca
# para a partida não pode travar como a entrada no lobby (onde a compilação de
# shaders foi colocada). Com COLD_CACHE=1, apaga antes os caches de shader do
# Godot e do Mesa deste usuário (medida de primeira execução).
# Não entra no CI: exige xvfb e mede a máquina em que roda.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$(command -v godot4 || command -v godot)}"
PORT="${TEST_PORT:-$((25080 + RANDOM % 1000))}"
OUT="${TEST_LOG_DIR:-$(mktemp -d)}"
MAX_FIRST_PLAY_HITCH_MS="${MAX_FIRST_PLAY_HITCH_MS:-500}"
mkdir -p "$OUT"
rm -f "$OUT"/*.log
PIDS=()
cleanup() { for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done; wait 2>/dev/null || true; }
trap cleanup EXIT

if [[ "${COLD_CACHE:-0}" == 1 ]]; then
  rm -rf "$HOME/.cache/mesa_shader_cache" "$HOME/.cache/mesa_shader_cache_db" \
    "$HOME/.local/share/godot/app_userdata/Armed Mystery/shader_cache"
fi

"$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 --port="$PORT" \
  --rooms=true --rooms-test=true --countdown-seconds=2 --round-end-delay-seconds=2 \
  --rooms-target-rounds=2 --rooms-expect-peers=4 --rooms-step-gap-msec=1500 \
  --transition-metrics=true >"$OUT/server.log" 2>&1 &
SERVER_PID=$!; PIDS+=("$SERVER_PID")
for _ in {1..100}; do grep -q SERVER_READY "$OUT/server.log" && break; sleep 0.1; done

ARGS=(--menu-auto=online --online-url="ws://127.0.0.1:$PORT" --menu-room-ready-min-players=4 --transition-metrics=true)
timeout 150 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT_BIN" --path "$ROOT" --rendering-driver opengl3 -- \
  --mode=menu --menu-settings-path="$OUT/settings-host.cfg" "${ARGS[@]}" --menu-name=Dona --menu-room=create \
  >"$OUT/host.log" 2>&1 &
PIDS+=("$!")
for _ in {1..600}; do grep -q 'ROOM_JOINED id=Dona code=' "$OUT/host.log" && break; sleep 0.1; done
CODE="$(sed -n 's/.*ROOM_JOINED id=Dona code=\([A-Z0-9]*\).*/\1/p' "$OUT/host.log" | head -n1)"
[[ -n "$CODE" ]] || { echo "TRANSITION_VISUAL_FAILED reason=no_room" >&2; cat "$OUT/host.log" >&2; exit 1; }
for guest in Beto Caio Duda; do
  timeout 140 "$GODOT_BIN" --headless --path "$ROOT" -- --mode=menu --menu-settings-path="$OUT/settings-$guest.cfg" \
    "${ARGS[@]}" --menu-name="$guest" --menu-room=join --room-code="$CODE" >"$OUT/$guest.log" 2>&1 &
  PIDS+=("$!")
done
# O servidor de teste encerra sozinho depois das 2 rodadas.
wait "$SERVER_PID" || true

python3 "$ROOT/tests/transition_report.py" "$OUT"/*.log || true
echo "--- cliente gráfico (ordem real) ---"
grep -hE 'TRANSITION kind=(render_hitch|play_first_snapshot)|CLIENT_VIEW|CLIENT_ARENA_PREWARM' "$OUT/host.log"

grep -q 'CLIENT_ARENA_PREWARM_DONE id=Dona' "$OUT/host.log" \
  || { echo "TRANSITION_VISUAL_FAILED reason=no_prewarm" >&2; exit 1; }
# Primeiro render_hitch depois da primeira troca para a partida.
first_play_hitch="$(awk '/CLIENT_VIEW id=Dona game=true/{seen=1} seen && /TRANSITION kind=render_hitch/{sub(/.*ms=/,""); sub(/ .*/,""); print; exit}' "$OUT/host.log")"
[[ -n "$first_play_hitch" ]] || { echo "TRANSITION_VISUAL_FAILED reason=no_play_measure" >&2; exit 1; }
if awk -v v="$first_play_hitch" -v max="$MAX_FIRST_PLAY_HITCH_MS" 'BEGIN{exit !(v > max)}'; then
  echo "TRANSITION_VISUAL_FAILED reason=first_play_hitch ms=$first_play_hitch max=$MAX_FIRST_PLAY_HITCH_MS" >&2
  exit 1
fi
echo "TRANSITION_VISUAL_OK first_play_hitch_ms=$first_play_hitch"
