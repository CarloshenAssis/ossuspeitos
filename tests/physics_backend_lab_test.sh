#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
LAB_DIR="$(mktemp -d)"
trap 'rm -rf "$LAB_DIR"' EXIT
for backend in 'GodotPhysics3D' 'Jolt Physics'; do
  printf 'config_version=5\n[application]\nconfig/name="IsolatedPhysicsLab"\n[physics]\n3d/physics_engine="%s"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n' "$backend" > "$LAB_DIR/project.godot"
  cp "$ROOT/tests/physics_backend_lab.gd" "$LAB_DIR/lab.gd"
  result=0
  "$GODOT_BIN" --headless --path "$LAB_DIR" --fixed-fps 60 --script "$LAB_DIR/lab.gd" > "$LAB_DIR/result.log" 2>&1 || result=$?
  cat "$LAB_DIR/result.log"
  [[ "$result" == 0 ]] || exit "$result"
  if grep -qE 'SCRIPT ERROR|Parse Error|ERROR:' "$LAB_DIR/result.log"; then exit 1; fi
  grep -q 'result=OK' "$LAB_DIR/result.log"
done
echo PHYSICS_BACKEND_LAB_TEST_OK
