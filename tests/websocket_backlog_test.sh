#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
LOG_DIR="${TEST_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$LOG_DIR"
FIXTURE="$LOG_DIR/fixture"
mkdir -p "$FIXTURE/client" "$FIXTURE/build"
cp "$ROOT/client/websocket_client_transport.gd" "$FIXTURE/client/"
cp "$ROOT/tests/websocket_backlog_client.gd" "$FIXTURE/backlog_client.gd"
PORT="${TEST_PORT:-$((47000+RANDOM%1000))}"
cat > "$FIXTURE/project.godot" <<CONFIG
config_version=5
[application]
config/name="WebSocket bounded backlog regression"
run/main_scene="res://backlog.tscn"
[rendering]
renderer/rendering_method="gl_compatibility"
[test]
backlog_url="ws://127.0.0.1:$PORT"
CONFIG
cat > "$FIXTURE/backlog.tscn" <<'SCENE'
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://backlog_client.gd" id="1"]
[node name="BacklogClient" type="Node"]
script=ExtResource("1")
SCENE
cat > "$FIXTURE/export_presets.cfg" <<'PRESET'
[preset.0]
name="Web Backlog"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter="build/*"
export_path="build/index.html"
[preset.0.options]
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
PRESET
"$GODOT_BIN" --headless --path "$FIXTURE" --import > "$LOG_DIR/import.log" 2>&1
"$GODOT_BIN" --headless --path "$FIXTURE" --export-release "Web Backlog" "$FIXTURE/build/index.html" > "$LOG_DIR/export.log" 2>&1
"$GODOT_BIN" --headless --path "$ROOT" --script tests/websocket_backlog_server.gd -- "$PORT" > "$LOG_DIR/server.log" 2>&1 &
SERVER_PID=$!
cleanup() { kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true; }
trap cleanup EXIT
for _ in {1..100}; do
 if grep -q '^WEBSOCKET_BACKLOG_SERVER_READY' "$LOG_DIR/server.log"; then break; fi
 if ! kill -0 "$SERVER_PID" 2>/dev/null; then cat "$LOG_DIR/server.log"; exit 1; fi
 sleep 0.05
done
node "$ROOT/tests/websocket_backlog_browser.mjs" "$FIXTURE/build" 2>&1 | tee "$LOG_DIR/browser.log"
wait "$SERVER_PID"
grep -q '^WEBSOCKET_BACKLOG_SERVER_DONE sent=50 tail=true' "$LOG_DIR/server.log"
if grep -Eq 'SCRIPT ERROR|Parse Error|^ERROR:' "$LOG_DIR/import.log" "$LOG_DIR/export.log" "$LOG_DIR/server.log"; then exit 1; fi
printf 'WEBSOCKET_BACKLOG_NETWORK_TEST_OK\n'
