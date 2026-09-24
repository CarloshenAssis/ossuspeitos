#!/usr/bin/env bash
# Fase 5, cenário principal: servidor e oito clientes reais, três rodadas na
# mesma sessão (tests/campaign_coordinator.gd). Depois do encerramento
# coordenado, prova que nenhum processo do harness sobrou, que a porta ficou
# livre e roda uma sessão de controle na MESMA porta.
# Uso: PROFILE=local|rtt80|rtt150j SEED=1 [TEST_LOG_DIR=...] tests/campaign_test.sh
set -eEuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "$GODOT_BIN" ]]; then
  if command -v godot4 >/dev/null; then GODOT_BIN="$(command -v godot4)";
  elif command -v godot >/dev/null; then GODOT_BIN="$(command -v godot)"; fi
fi
PROFILE="${PROFILE:-local}"
SEED="${SEED:-1}"
CLIENTS=8
PORT="${TEST_PORT:-$((28080 + RANDOM % 1000))}"
SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
RUN_ID="campaign-$PROFILE-s$SEED-$SHA-$$"
if [[ -n "${TEST_LOG_DIR:-}" ]]; then
  TMP_DIR="$TEST_LOG_DIR"; mkdir -p "$TMP_DIR"; REMOVE_TMP_DIR=false
else
  TMP_DIR="$(mktemp -d)"; REMOVE_TMP_DIR=true
fi
PIDS=(); NAMES=(); STATUSES=(); WATCHDOG_PID=""; SERVER_CONTAINER=""

cleanup() {
  local status=$?
  trap - EXIT
  [[ -z "$WATCHDOG_PID" ]] || kill "$WATCHDOG_PID" 2>/dev/null || true
  # Só encerra processos iniciados por este harness (PIDs próprios).
  for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  for pid in "${PIDS[@]:-}"; do wait "$pid" 2>/dev/null || true; done
  # Só o container criado por este harness.
  [[ -z "${SERVER_CONTAINER:-}" ]] || docker rm -f "$SERVER_CONTAINER" >/dev/null 2>&1 || true
  [[ "$REMOVE_TMP_DIR" != true ]] || rm -rf "$TMP_DIR"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
  local status="${1:-1}"
  echo "CAMPAIGN_HARNESS_ERROR status=$status run=$RUN_ID logs=$TMP_DIR" >&2
  for log in "$TMP_DIR"/*.log; do [[ ! -f "$log" ]] || { echo "===== $log (tail) =====" >&2; tail -n 60 "$log" >&2; }; done
  exit "$status"
}
trap 'fail $?' ERR
ok() { echo "ASSERT_OK name=$1"; }
assert_grep() { local n=$1 p=$2; shift 2; grep -qE -- "$p" "$@" && ok "$n" || { echo "ASSERT_FAILED name=$n expected_pattern=$p files=$*" >&2; return 1; }; }
assert_no_grep() { local n=$1 p=$2; shift 2; if grep -qE -- "$p" "$@"; then echo "ASSERT_FAILED name=$n forbidden=$p observed=$(grep -hE -- "$p" "$@" | head -1)" >&2; return 1; else ok "$n"; fi; }
assert_equal() { [[ "$2" == "$3" ]] && ok "$1" || { echo "ASSERT_FAILED name=$1 expected=$3 observed=$2" >&2; return 1; }; }
wait_marker() { local p=$1 f=$2 pid=$3; for _ in {1..600}; do grep -qE -- "$p" "$f" && return; kill -0 "$pid" 2>/dev/null || return 1; sleep 0.05; done; return 1; }
stage() { echo "HARNESS_STAGE $1 run=$RUN_ID t=$(date +%s)"; }

[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || { echo "Godot 4 not found. Set GODOT_BIN." >&2; exit 127; }
stage "start profile=$PROFILE seed=$SEED port=$PORT sha=$SHA"

NET_ARGS=()
# Fase 8: CAMPAIGN_SERVER_IMAGE roda o servidor dentro do container de teste
# (mesmo export dedicado da produção, com os coordenadores) e os oito clientes
# continuam fora dele.
if [[ -n "${CAMPAIGN_SERVER_IMAGE:-}" ]]; then
  SERVER_CONTAINER="am-campaign-$$"
  SERVER_CMD=(docker run --rm --name "$SERVER_CONTAINER" -p "127.0.0.1:$PORT:$PORT" "$CAMPAIGN_SERVER_IMAGE"
    -- --mode=server --bind=0.0.0.0 --port="$PORT")
else
  SERVER_CMD=("$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 --port="$PORT")
fi
"${SERVER_CMD[@]}" \
  --countdown-seconds=3 --round-end-delay-seconds=3 --round-seed="$SEED" --campaign-test=true \
  --sync-profile="$PROFILE" >"$TMP_DIR/server.log" 2>&1 &
PIDS+=("$!"); NAMES+=(server); SERVER_PID=$!
wait_marker 'SERVER_READY' "$TMP_DIR/server.log" "$SERVER_PID"
stage "server_ready"
for id in $(seq 1 "$CLIENTS"); do
  NET_ARGS=()
  if [[ "$PROFILE" != "local" ]]; then NET_ARGS=(--test-net-profile="$PROFILE" --test-net-seed="$((SEED * 100 + id))"); fi
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id="client-$id" --url="ws://127.0.0.1:$PORT" \
    --campaign-test=true "${NET_ARGS[@]}" >"$TMP_DIR/client-$id.log" 2>&1 &
  PIDS+=("$!"); NAMES+=("client-$id")
done
stage "clients_started count=$CLIENTS"
(
  trap 'kill "$sleep_pid" 2>/dev/null; exit 0' TERM
  sleep 420 & sleep_pid=$!
  wait "$sleep_pid"
  echo "watchdog run=$RUN_ID" >"$TMP_DIR/timeout.log"
  for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
) >/dev/null 2>&1 & WATCHDOG_PID=$!

for i in "${!PIDS[@]}"; do
  if wait "${PIDS[$i]}"; then status=0; else status=$?; fi
  STATUSES+=("$status"); echo "PROCESS_STATUS name=${NAMES[$i]} pid=${PIDS[$i]} status=$status"
done
kill "$WATCHDOG_PID" 2>/dev/null || true; wait "$WATCHDOG_PID" 2>/dev/null || true; WATCHDOG_PID=""
stage "processes_exited"
for i in "${!STATUSES[@]}"; do assert_equal "process-${NAMES[$i]}-exit" "${STATUSES[$i]}" 0; done
[[ ! -f "$TMP_DIR/timeout.log" ]] && ok watchdog-not-used || { echo "ASSERT_FAILED name=watchdog-not-used" >&2; fail 1; }

# Nenhum processo do harness vivo e porta livre (outro bind funciona).
for pid in "${PIDS[@]}"; do
  if kill -0 "$pid" 2>/dev/null; then echo "ASSERT_FAILED name=no-orphan pid=$pid" >&2; fail 1; fi
done
ok no-orphan-processes
python3 - "$PORT" <<'PY' && ok port-released || { echo "ASSERT_FAILED name=port-released port=$PORT" >&2; fail 1; }
import socket, sys
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", int(sys.argv[1]))); s.close()
PY

# --- Estado oficial (servidor) --------------------------------------------------
for round in 1 2 3; do
  assert_grep "round-$round-begin" "CAMPAIGN_ROUND_BEGIN round=$round round_id=[0-9]+ participants=8" "$TMP_DIR/server.log"
  assert_grep "round-$round-resources" "CAMPAIGN_RESOURCES round=$round " "$TMP_DIR/server.log"
  assert_grep "round-$round-reveal" "CAMPAIGN_REVEAL_OK round=$round clients=8" "$TMP_DIR/server.log"
done
assert_grep round-1-result 'CAMPAIGN_ROUND_RESULT round=1 team=INNOCENTS reason=assassin_down' "$TMP_DIR/server.log"
assert_grep round-2-result 'CAMPAIGN_ROUND_RESULT round=2 team=ASSASSIN reason=innocents_down' "$TMP_DIR/server.log"
assert_grep round-3-result 'CAMPAIGN_ROUND_RESULT round=3 team=INNOCENTS reason=assassin_down' "$TMP_DIR/server.log"
for marker in 'CAMPAIGN_NAVIGATION ' 'CAMPAIGN_DEAD_ACTIONS_BLOCKED round=1' 'CAMPAIGN_SPECTATOR round=1' \
    'CAMPAIGN_STALE_CALLBACKS_REJECTED round=2 clients=8' 'CAMPAIGN_STALE_CALLBACKS_REJECTED round=3 clients=8' \
    "CAMPAIGN_SERVER_OK clients=8 rounds=3 profile=$PROFILE" 'SERVER_SHUTDOWN_COMPLETE closed=8'; do
  assert_grep "server-${marker%% *}" "$marker" "$TMP_DIR/server.log"
done
# Fase 6: corpos iguais em todos os clientes (2 em pontos diferentes na
# rodada 1) e reset completo (spawns, 8+12 pickups, nenhum corpo) no início
# das rodadas 2 e 3.
assert_grep round-1-two-bodies 'CAMPAIGN_BODIES_OK round=1 bodies=2 clients=8' "$TMP_DIR/server.log"
for round in 1 2 3; do
  assert_grep "round-$round-bodies-at-end" "CAMPAIGN_BODIES_OK round=$round bodies=[0-9]+ clients=8" "$TMP_DIR/server.log"
  assert_grep "round-$round-reset" "CAMPAIGN_ROUND_RESET_OK round=$round clients=8 spawns=8 pickups=20 bodies=0" "$TMP_DIR/server.log"
done
assert_equal body-added-lines "$(grep -c 'ROUND_BODY_ADDED ' "$TMP_DIR/server.log")" "$(grep -c 'ROUND_ALIVE_CHANGED round_id=[0-9]* peer_id=[0-9]* alive=false' "$TMP_DIR/server.log")"
assert_no_grep no-duplicate-bodies 'CLIENT_BODY_DUPLICATE_IGNORED' "$TMP_DIR"/client-*.log
assert_equal round-result-lines "$(grep -c 'ROUND_RESULT round_id=' "$TMP_DIR/server.log")" 3
assert_equal reveal-sent-once-per-round "$(grep -c 'ROUND_REVEAL_SENT round_id=[0-9]* peers=8' "$TMP_DIR/server.log")" 3

# --- O que cada cliente recebeu -------------------------------------------------
for id in $(seq 1 "$CLIENTS"); do
  log="$TMP_DIR/client-$id.log"
  assert_equal "client-$id-three-private-roles" "$(grep -c "CLIENT_PRIVATE_ROLE_RECEIVED id=client-$id " "$log")" 3
  assert_equal "client-$id-three-reveals" "$(grep -c 'ROUND_REVEAL_OK players=8' "$log")" 3
  assert_grep "client-$id-shutdown" "CLIENT_SHUTDOWN_COMPLETE id=client-$id" "$log"
done
# Escopo: o time vencedor público (CLIENT_ROUND_RESULT, após ENDED) pode
# dizer ASSASSIN; papéis de jogadores nunca aparecem nos logs dos clientes.
if grep -hE 'ASSASSIN|DETECTIVE|VICTIM' "$TMP_DIR"/client-*.log | grep -vE '^CLIENT_ROUND_RESULT id=client-[0-9]+ round_id=[0-9]+ team=(ASSASSIN|INNOCENTS) reason=' | grep -q .; then
  echo "ASSERT_FAILED name=no-role-names-in-client-logs observed=$(grep -hE 'ASSASSIN|DETECTIVE|VICTIM' "$TMP_DIR"/client-*.log | grep -vE '^CLIENT_ROUND_RESULT' | head -1)" >&2; fail 1
fi
ok no-role-names-in-client-logs
assert_no_grep no-peer-role-association 'peer_id=[0-9]+.*role=' "$TMP_DIR"/*.log
assert_no_grep no-runtime-errors 'SCRIPT ERROR|SYNC_TEST_FAILED|ready_state != STATE_OPEN|Trying to call an RPC via a multiplayer peer which is not connected' "$TMP_DIR"/*.log
# Recursos: coleções limitadas e sem crescimento monotônico entre rodadas
# (baseline = rodada 1, depois do aquecimento; bytes exatos não são exigidos).
python3 - "$TMP_DIR/server.log" <<'PY' && ok resources-bounded || { echo "ASSERT_FAILED name=resources-bounded" >&2; fail 1; }
import json, re, sys
text = open(sys.argv[1]).read()
data = json.loads(re.search(r"CAMPAIGN_RESOURCES_SUMMARY (\[.*\])", text).group(1))
base = data[0]
problems = []
for entry in data:
    if entry["world_states"] != 8 or entry["health"] != 8 or entry["inventories"] != 8 or entry["ground"] != 20 or entry.get("bodies", -1) != 0 or entry["lobby"] != 8:
        problems.append("round %d official collections %s" % (entry["round"], entry))
    if entry["queued"] > 8 * 32:
        problems.append("round %d queued %d" % (entry["round"], entry["queued"]))
    if abs(entry["server_objects"] - base["server_objects"]) > base["server_objects"] * 0.02:
        problems.append("round %d server objects %d vs %d" % (entry["round"], entry["server_objects"], base["server_objects"]))
    for peer, client in entry["clients"].items():
        b = base["clients"].get(peer)
        if b and abs(client["objects"] - b["objects"]) > b["objects"] * 0.02:
            problems.append("round %d client %s objects %d vs %d" % (entry["round"], peer, client["objects"], b["objects"]))
        if client["pending"] > 90 or client["outbox"] > 8 or client["net_stats_actions"] > 8:
            problems.append("round %d client %s buffers %s" % (entry["round"], peer, client))
mem = [e["server_static_mem"] for e in data]
print("RESOURCES server_static_mem=%s server_objects=%s" % (mem, [e["server_objects"] for e in data]))
for p in problems: print("RESOURCE_PROBLEM " + p)
sys.exit(1 if problems else 0)
PY
grep -hE 'CAMPAIGN_(ROUND|STEP_OK|RESOURCES |SPECTATOR|REVEAL|STALE|DEAD|NAVIGATION)' "$TMP_DIR/server.log" | head -120
stage "assertions_done"

# --- Sessão de controle na mesma porta -------------------------------------------
if [[ "${CONTROL_SESSION:-true}" == true ]]; then
  CONTROL_DIR="$TMP_DIR/control"
  mkdir -p "$CONTROL_DIR"
  set +e
  TEST_PORT="$PORT" TEST_LOG_DIR="$CONTROL_DIR" GODOT_BIN="$GODOT_BIN" "$ROOT/tests/network_smoke_test.sh" >"$TMP_DIR/control-session.log" 2>&1
  control_status=$?
  set -e
  assert_equal control-session-same-port "$control_status" 0
  assert_grep control-session-used-port "SERVER_READY address=127.0.0.1 port=$PORT" "$CONTROL_DIR/server.log"
fi
stage "done"
echo "CAMPAIGN_TEST_OK profile=$PROFILE seed=$SEED clients=$CLIENTS rounds=3 run=$RUN_ID"
