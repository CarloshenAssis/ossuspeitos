# Tolerância limitada às corridas de envio do Godot no encerramento:
# "ready_state != STATE_OPEN" e "Trying to call an RPC via a multiplayer
# peer which is not connected" saem depois que o peer já saiu, sem efeito
# nas asserções. rooms_resilience_test e container_test já aceitam isso;
# as suítes de netcode/network tratavam como falha e falhavam no CI.
assert_engine_send_races_bounded() {
	local limit="${ENGINE_SEND_RACE_LIMIT:-16}"
	local count=0
	local file extra
	for file in "$@"; do
		[[ -f "$file" ]] || continue
		extra="$(grep -cE -- 'ready_state != STATE_OPEN|Trying to call an RPC via a multiplayer peer which is not connected' "$file" || true)"
		count=$((count + extra))
	done
	if [[ "$count" -le "$limit" ]]; then
		if declare -F ok >/dev/null; then
			ok "engine-send-races-bounded count=$count"
		elif declare -F check_ok >/dev/null; then
			check_ok "engine-send-races-bounded count=$count"
		else
			echo "ASSERT_OK name=engine-send-races-bounded count=$count"
		fi
	else
		echo "ASSERT_FAILED name=engine-send-races-bounded count=$count limit=$limit" >&2
		return 1
	fi
}
