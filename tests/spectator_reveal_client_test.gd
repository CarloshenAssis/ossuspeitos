extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	_test_eliminated_hud()
	_test_reveal_hud_and_reset()
	_test_client_security_surface()
	if failures:
		push_error("SPECTATOR_REVEAL_CLIENT_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return
	print("SPECTATOR_REVEAL_CLIENT_TEST_OK checks=%d" % checks)
	quit(0)

func _test_eliminated_hud() -> void:
	var roster := [{"peer_id": 7, "label": "Ana", "connected": true, "participant": true, "alive": false},
		{"peer_id": 8, "label": "Beto", "connected": true, "participant": true, "alive": true}]
	var text := "\n".join(RoundHud.compose_lines(_public(RoundState.ACTIVE), Role.VICTIM, 7, roster,
		{"eliminated": true, "targets": [8], "target": 8}, {}))
	_expect(text.contains("ELIMINADO") and text.contains("Q / E trocar jogador"), "eliminated HUD is explicit")
	_expect(text.contains("OBSERVANDO · 1/1") and text.contains("Beto"), "HUD presents the authorized public target")
	var empty := "\n".join(RoundHud.compose_lines(_public(RoundState.ACTIVE), Role.VICTIM, 7, roster,
		{"eliminated": true, "targets": [], "target": 0}, {}))
	_expect(empty.contains("AGUARDANDO FIM DA RODADA"), "empty target list is presented safely")

## Formato exato que `RoundAuthority._build_final_reveal_once()` publica e que
## `NetworkApp.round_final_reveal()` aceita: papel como texto e sem rótulo; os
## nomes vêm do roster público.
func _test_reveal_hud_and_reset() -> void:
	var reveal := {"round_id": 4, "winner": "INNOCENTS", "reason": "assassin_down", "players": [
		{"peer_id": 7, "role": "ASSASSIN"},
		{"peer_id": 8, "role": "DETECTIVE"},
		{"peer_id": 9, "role": "VICTIM"}]}
	var roster := [{"peer_id": 7, "label": "Ana", "connected": true, "participant": true, "alive": false},
		{"peer_id": 8, "label": "Beto", "connected": true, "participant": true, "alive": true},
		{"peer_id": 9, "label": "Caio", "connected": true, "participant": true, "alive": true}]
	var ended := _public(RoundState.ENDED)
	ended["round_id"] = 4
	ended["winning_team"] = Role.TEAM_INNOCENTS
	ended["winner_reason"] = "assassin_down"
	var text := "\n".join(RoundHud.compose_lines(ended, Role.VICTIM, 9, roster, {}, reveal))
	_expect(text.contains("PAPÉIS REVELADOS"), "ended HUD shows the reveal")
	_expect(text.contains("Ana  ◆ ASSASSINO  Eliminado"), "ended HUD names the assassin from the real payload")
	_expect(text.contains("Beto  ▲ DETETIVE  Vivo") and text.contains("Caio (VOCÊ)  ● VÍTIMA  Vivo"), "ended HUD shows every revealed role and marks the local player")
	_expect(text.contains("O assassino foi eliminado.") and text.contains("retornando ao lobby"), "ended HUD presents reason and lobby return")
	var waiting := "\n".join(RoundHud.compose_lines(_public(RoundState.WAITING), Role.NONE, 9, roster, {}, reveal))
	_expect(not waiting.contains("PAPÉIS REVELADOS") and not waiting.contains("ASSASSINO"), "next round hides prior reveal")

func _test_client_security_surface() -> void:
	var source := FileAccess.get_file_as_string("res://shared/network_app.gd")
	_expect(source.contains("multiplayer.get_remote_sender_id()"), "RPC identity uses the remote sender")
	_expect(not source.contains("func request_reveal") and not source.contains("func request_spectator_target"), "client has no reveal or arbitrary-target request RPC")
	_expect(source.contains("and (_client_can_gameplay() or _movement_test_client())"), "dead client does not send movement commands")
	_expect(source.contains("if not _client_can_gameplay():"), "dead client routes keys locally before combat")
	_expect(source.contains("round_private_spectator_targets.rpc_id(peer_id"), "spectator targets are delivered privately")
	_expect(source.contains("round_final_reveal.rpc_id(peer_id"), "reveal is sent only to each connected participant")
	var server_source := FileAccess.get_file_as_string("res://server/round_authority.gd")
	_expect(server_source.contains("state != RoundState.ENDED") and server_source.contains("final_reveal.clear()"), "reveal is guarded and cleared")
	var scene_source := FileAccess.get_file_as_string("res://shared/network_app.gd")
	_expect(scene_source.contains("DisplayServer.get_name() != \"headless\""), "headless server does not instantiate presentation")

func _public(state: int) -> Dictionary:
	return {"state": state, "round_id": 1, "connected": 4, "max_players": 8,
		"min_players": 4, "countdown_msec": 0, "winning_team": Role.TEAM_NONE, "winner_reason": ""}

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error("SPECTATOR_REVEAL_CLIENT_CHECK_FAILED %s" % description)
