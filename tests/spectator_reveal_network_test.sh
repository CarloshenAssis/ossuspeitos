#!/usr/bin/env bash
set -eEuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$(command -v godot4 2>/dev/null || command -v godot 2>/dev/null || true)}"
PORT="${TEST_PORT:-$((26080 + RANDOM % 1000))}"
if [[ -n "${TEST_LOG_DIR:-}" ]]; then TMP_DIR="$TEST_LOG_DIR"; mkdir -p "$TMP_DIR"; REMOVE=false
else TMP_DIR="$(mktemp -d)"; REMOVE=true; fi
PIDS=(); NAMES=(); STATUSES=(); WATCHDOG_PID=""

cleanup() {
  local status=$?; trap - EXIT
  [[ -z "$WATCHDOG_PID" ]] || kill "$WATCHDOG_PID" 2>/dev/null || true
  for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  for pid in "${PIDS[@]:-}"; do wait "$pid" 2>/dev/null || true; done
  [[ "$REMOVE" != true ]] || rm -rf "$TMP_DIR"
  exit "$status"
}
trap cleanup EXIT; trap 'exit 130' INT; trap 'exit 143' TERM
fail() { local status="${1:-1}"; echo "SPECTATOR_REVEAL_HARNESS_ERROR status=$status" >&2; for log in "$TMP_DIR"/*.log; do [[ ! -f "$log" ]] || { echo "===== $log =====" >&2; cat "$log" >&2; }; done; exit "$status"; }
trap 'fail $?' ERR
ok() { echo "ASSERT_OK name=$1"; }
assert_grep() { local n=$1 p=$2; shift 2; grep -qE -- "$p" "$@" && ok "$n" || { echo "ASSERT_FAILED name=$n pattern=$p" >&2; return 1; }; }
assert_no_grep() { local n=$1 p=$2; shift 2; if grep -qE -- "$p" "$@"; then echo "ASSERT_FAILED name=$n forbidden=$p" >&2; return 1; else ok "$n"; fi; }
assert_equal() { [[ "$2" == "$3" ]] && ok "$1" || { echo "ASSERT_FAILED name=$1 expected=$3 actual=$2" >&2; return 1; }; }
wait_marker() { local p=$1 f=$2 pid=$3; for _ in {1..600}; do grep -qE -- "$p" "$f" && return; kill -0 "$pid" 2>/dev/null || return 1; sleep 0.05; done; return 1; }

[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || { echo "Godot 4 not found. Set GODOT_BIN." >&2; exit 127; }
"$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 --port="$PORT" \
  --countdown-seconds=0.2 --round-end-delay-seconds=1 --round-seed=20260923 \
  --spectator-reveal-test=true --stop-after-round-active=4 >"$TMP_DIR/server.log" 2>&1 &
PIDS+=("$!"); NAMES+=(server); SERVER_PID=$!
wait_marker 'SERVER_READY' "$TMP_DIR/server.log" "$SERVER_PID"
for id in 1 2 3 4; do
  # Nomes exclusivos deste harness evitam acionar a sonda legada client-1,
  # que tenta RPC client->client com relay desabilitado e testa apenas um peer
  # local desconhecido. A privacidade aqui e validada pelo caminho conectado.
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id="spectator-$id" \
    --url="ws://127.0.0.1:$PORT" --spectator-reveal-test=true >"$TMP_DIR/client-$id.log" 2>&1 &
  PIDS+=("$!"); NAMES+=("client-$id")
done
( sleep 45; echo timeout >"$TMP_DIR/timeout.log"; for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done ) & WATCHDOG_PID=$!
for i in "${!PIDS[@]}"; do if wait "${PIDS[$i]}"; then status=0; else status=$?; fi; STATUSES+=("$status"); echo "PROCESS_STATUS name=${NAMES[$i]} status=$status"; done
kill "$WATCHDOG_PID" 2>/dev/null || true; wait "$WATCHDOG_PID" 2>/dev/null || true; WATCHDOG_PID=""
for i in "${!STATUSES[@]}"; do assert_equal "process-${NAMES[$i]}" "${STATUSES[$i]}" 0; done
[[ ! -f "$TMP_DIR/timeout.log" ]] || fail 1

assert_equal four-joins "$(grep -c 'CLIENT_JOINED id=spectator-' "$TMP_DIR/server.log")" 4
JOINED_PEERS="$(sed -n 's/.*CLIENT_JOINED id=spectator-[1-4] peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -n -u)"
assert_equal four-unique-connected-participants "$(wc -l <<<"$JOINED_PEERS" | tr -d ' ')" 4
assert_equal four-private-roles "$(grep -h -c 'CLIENT_PRIVATE_ROLE_RECEIVED' "$TMP_DIR"/client-*.log | awk '{s+=$1} END{print s}')" 4
for id in 1 2 3 4; do
  assert_equal "client-$id-only-own-role" "$(grep -c 'CLIENT_PRIVATE_ROLE_RECEIVED' "$TMP_DIR/client-$id.log")" 1
done

mapfile -t ELIMINATED_PEERS < <(sed -n 's/.*ROUND_ALIVE_CHANGED.*peer_id=\([0-9][0-9]*\).*alive=false.*/\1/p' "$TMP_DIR/server.log")
assert_equal two-official-eliminations "${#ELIMINATED_PEERS[@]}" 2
mapfile -t SPECTATOR_LOGS < <(grep -l 'SPECTATOR_TARGETS_PRIVATE_OK' "$TMP_DIR"/client-*.log)
assert_equal spectator-private-updates-only-to-eliminated "${#SPECTATOR_LOGS[@]}" 2
assert_equal spectator-private-delivery-count "$(grep -h -c 'SPECTATOR_TARGETS_PRIVATE_OK' "${SPECTATOR_LOGS[@]}" | awk '{s+=$1} END{print s}')" 3

ELIMINATED_LOGS=()
for index in 0 1; do
  peer_id="${ELIMINATED_PEERS[$index]}"
  client_label="$(sed -n "s/.*CLIENT_JOINED id=\([^ ]*\) peer_id=$peer_id .*/\1/p" "$TMP_DIR/server.log")"
  client_number="${client_label#spectator-}"
  client_log="$TMP_DIR/client-$client_number.log"
  [[ -n "$client_label" && -f "$client_log" ]] || fail 1
  ELIMINATED_LOGS+=("$client_log")
  grep -qx "$peer_id" <<<"$JOINED_PEERS" && ok "eliminated-peer-$peer_id-was-connected-participant" || fail 1
done
assert_equal eliminated-clients-are-distinct "$(printf '%s\n' "${ELIMINATED_LOGS[@]}" | sort -u | wc -l | tr -d ' ')" 2

mapfile -t FIRST_TARGET_COUNTS < <(sed -n 's/.*SPECTATOR_TARGETS_PRIVATE_OK.*targets=\([0-9][0-9]*\).*/\1/p' "${ELIMINATED_LOGS[0]}")
assert_equal first-eliminated-private-update-count "${#FIRST_TARGET_COUNTS[@]}" 2
assert_equal spectator-first-live-target-count "$(printf '%s\n' "${FIRST_TARGET_COUNTS[@]}" | grep -c '^3$')" 1
assert_equal spectator-targets-refresh-after-elimination "$(printf '%s\n' "${FIRST_TARGET_COUNTS[@]}" | grep -c '^2$')" 1
assert_equal no-identical-spectator-refresh "$(printf '%s\n' "${FIRST_TARGET_COUNTS[@]}" | sort -u | wc -l | tr -d ' ')" 2

mapfile -t SECOND_TARGET_COUNTS < <(sed -n 's/.*SPECTATOR_TARGETS_PRIVATE_OK.*targets=\([0-9][0-9]*\).*/\1/p' "${ELIMINATED_LOGS[1]}")
assert_equal second-eliminated-private-update-count "${#SECOND_TARGET_COUNTS[@]}" 1
assert_equal second-eliminated-live-target-count "$(printf '%s\n' "${SECOND_TARGET_COUNTS[@]}" | grep -c '^2$')" 1
assert_equal refresh-excludes-newly-eliminated 2 "$((4 - ${#ELIMINATED_PEERS[@]}))"
assert_no_grep living-clients-receive-no-spectator-state 'SPECTATOR_TARGETS_PRIVATE_OK' \
  $(printf '%s\n' "$TMP_DIR"/client-*.log | grep -vFx -f <(printf '%s\n' "${ELIMINATED_LOGS[@]}"))
assert_grep spectator-follow 'SPECTATOR_FOLLOW_OK' "$TMP_DIR"/client-*.log
assert_grep actions-blocked 'SPECTATOR_ACTIONS_BLOCKED' "$TMP_DIR/server.log"
assert_equal four-reveals "$(grep -h -c 'ROUND_REVEAL_OK players=4' "$TMP_DIR"/client-*.log | awk '{s+=$1} END{print s}')" 4
assert_equal four-reveal-privacy "$(grep -h -c 'ROUND_REVEAL_PRIVACY_OK' "$TMP_DIR"/client-*.log | awk '{s+=$1} END{print s}')" 4
assert_grep reveal-after-ended 'ROUND_STATE state=ENDED.*round_id=1' "$TMP_DIR/server.log"
assert_grep reveal-sent-once 'ROUND_REVEAL_SENT round_id=1 peers=4' "$TMP_DIR/server.log"
assert_equal reveal-sent-exactly-once "$(grep -c 'ROUND_REVEAL_SENT round_id=1' "$TMP_DIR/server.log")" 1
assert_grep next-round-clears 'ROUND_REVEAL_CLEARED_OK' "$TMP_DIR/server.log"
assert_grep shutdown-ready 'SERVER_SHUTDOWN_READY clients=4' "$TMP_DIR/server.log"
assert_grep shutdown-complete 'SERVER_SHUTDOWN_COMPLETE closed=4' "$TMP_DIR/server.log"
assert_no_grep no-private-fields-in-reveal 'ROUND_REVEAL.*(health|inventory|magazine|reserve|seed)' "$TMP_DIR"/*.log
assert_no_grep no-role-before-ended 'CLIENT_ROUND_STATE.*state=(WAITING|COUNTDOWN|ACTIVE).*role=' "$TMP_DIR"/*.log
assert_no_grep no-peer-role-association 'peer_id=[0-9]+.*(ASSASSIN|DETECTIVE|VICTIM)|(ASSASSIN|DETECTIVE|VICTIM).*peer_id=[0-9]+' "$TMP_DIR"/*.log
assert_no_grep no-role-forgery-delivered 'ROLE_SPOOF_REJECTED|CLIENT_PRIVATE_ROLE_RECEIVED.*count=[2-9]' "$TMP_DIR"/*.log
assert_no_grep no-runtime-errors 'SCRIPT ERROR|ready_state != STATE_OPEN|Trying to call an RPC via a multiplayer peer which is not connected|SERVER_SHUTDOWN_TIMEOUT' "$TMP_DIR"/*.log
cat "$TMP_DIR/server.log"
echo 'SPECTATOR_REVEAL_NETWORK_TEST_OK clients=4'
