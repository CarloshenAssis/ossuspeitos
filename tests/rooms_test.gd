extends SceneTree

## Fase 9: salas privadas sem rede. RoomRules (códigos, DTO), MatchRoom
## (entrada, saída, anfitrião, PRONTO, contagem, fim de rodada, volta ao lobby)
## e RoomRegistry (unicidade, limite, limpeza), mais o isolamento entre duas
## salas no mesmo processo.

var failures := 0
var checks := 0

func _initialize() -> void:
	_test_codes()
	_test_registry_create_find_limit()
	_test_join_rules()
	_test_host_transfer_and_empty_destroy()
	_test_lobby_idle_expiry()
	_test_ready_gate_countdown()
	_test_round_end_returns_to_lobby()
	_test_two_rooms_isolated()
	_test_room_state_dto()
	_test_legacy_room_unchanged()
	if failures > 0:
		push_error("ROOMS_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return
	print("ROOMS_TEST_OK checks=%d" % checks)
	quit(0)

func _test_codes() -> void:
	var crypto := Crypto.new()
	var seen := {}
	for _i in 500:
		var code := RoomRules.code_from_bytes(crypto.generate_random_bytes(RoomRules.CODE_LENGTH))
		_expect(RoomRules.is_valid_code(code), "generated code %s is valid" % code)
		for forbidden in ["O", "0", "I", "1"]:
			_expect(not code.contains(forbidden), "code avoids %s" % forbidden)
		seen[code] = true
	_expect(seen.size() >= 495, "random codes are practically unique (%d/500)" % seen.size())
	_expect(RoomRules.normalize_code("abc-234") == "ABC234", "lowercase and hyphen normalized")
	_expect(RoomRules.normalize_code(" AB C23 4 ") == "ABC234", "spaces removed")
	for bad in ["", "ABC23", "ABC2345", "ABCO23", "ABC1ZZ", "ÁBC234", "ABC 23!", "ABCDEFGHIJKLMNOPQRS"]:
		_expect(RoomRules.normalize_code(bad) == "", "bad code rejected: %s" % bad)
	for bad_type in [123456, null, ["ABC234"], {"code": "ABC234"}, 1.5]:
		_expect(RoomRules.normalize_code(bad_type) == "", "non-string code rejected")
	_expect(RoomRules.display_code("ABC234") == "ABC-234", "display form")

func _test_registry_create_find_limit() -> void:
	var registry := RoomRegistry.new()
	registry.max_rooms = 3
	var a := registry.create_room(0)
	var b := registry.create_room(0)
	var c := registry.create_room(0)
	_expect(a != null and b != null and c != null, "rooms created up to the limit")
	_expect(registry.create_room(0) == null, "limit enforced")
	_expect(a.code != b.code and b.code != c.code and a.code != c.code, "codes unique among active rooms")
	_expect(registry.find_by_code(b.code) == b and registry.find_by_code("ZZZZZZ") == null, "find by code")
	# Colisão forçada: a mesma sequência de bytes nunca gera código repetido.
	var fixed := RoomRegistry.new()
	var calls := [0]
	var source := func() -> PackedByteArray:
		calls[0] += 1
		return PackedByteArray([calls[0] if calls[0] > 2 else 1, 2, 3, 4, 5, 6])
	var first := fixed.create_room(0, source)
	var second := fixed.create_room(0, source)
	_expect(first != null and second != null and first.code != second.code, "collision retried to a new code")
	registry.destroy(a)
	_expect(registry.find_by_code(a.code) == null and registry.can_create(), "destroyed room frees code and slot")

func _test_join_rules() -> void:
	var registry := RoomRegistry.new()
	var room := registry.create_room(0)
	for index in 8:
		var result := room.add_member(100 + index, "Jogador %d" % index, 0)
		_expect(str(result["reason"]) == "", "member %d joins" % index)
	_expect(str(room.add_member(200, "Nono", 0)["reason"]) == "room_full", "ninth refused: room_full")
	var other := registry.create_room(0)
	_expect(str(other.add_member(300, "Ana", 0)["reason"]) == "", "join ok")
	_expect(str(other.add_member(301, "Ana", 0)["reason"]) == "name_taken", "duplicate name in the same room")
	_expect(str(other.add_member(302, "ab\ncd", 0)["reason"]) == "invalid_name", "invalid name")
	# Nome igual em outra sala é permitido (salas isoladas).
	_expect(str(room.lobby.label_for(100)) == "Jogador 0" and str(registry.create_room(0).add_member(400, "Jogador 0", 0)["reason"]) == "", "same name allowed in another room")
	# Em andamento: ninguém entra.
	var playing := _room_with_active_round(registry)
	_expect(str(playing.add_member(900, "Atrasado", 0)["reason"]) == "round_in_progress", "join refused mid-round")

func _test_host_transfer_and_empty_destroy() -> void:
	var registry := RoomRegistry.new()
	var room := registry.create_room(0)
	room.add_member(10, "Primeiro", 0)
	room.add_member(20, "Segundo", 10)
	room.add_member(30, "Terceiro", 20)
	_expect(room.host_peer_id == 10, "creator is host")
	room.remove_member(10, 100)
	_expect(room.host_peer_id == 20, "host passes to the longest connected")
	room.remove_member(30, 110)
	_expect(room.host_peer_id == 20, "host kept when someone else leaves")
	room.remove_member(20, 120)
	_expect(room.host_peer_id == 0 and room.is_empty(), "empty room has no host")
	_expect(registry.due_for_removal(120 + RoomRegistry.EMPTY_ROOM_GRACE_MSEC - 1).is_empty(), "empty room kept during grace")
	var due := registry.due_for_removal(120 + RoomRegistry.EMPTY_ROOM_GRACE_MSEC)
	_expect(due.size() == 1 and str(due[0]["reason"]) == "empty", "empty room due after grace")
	registry.destroy(due[0]["room"])
	_expect(registry.room_count() == 0, "empty room destroyed")

func _test_lobby_idle_expiry() -> void:
	var registry := RoomRegistry.new()
	var room := registry.create_room(0)
	room.add_member(1, "Parado", 0)
	_expect(registry.due_for_removal(RoomRegistry.LOBBY_IDLE_MSEC - 1).is_empty(), "active lobby kept")
	var due := registry.due_for_removal(RoomRegistry.LOBBY_IDLE_MSEC)
	_expect(due.size() == 1 and str(due[0]["reason"]) == "idle", "idle lobby expires")
	# Rodada em andamento com gente conectada nunca expira por inatividade.
	var playing := _room_with_active_round(RoomRegistry.new())
	_expect(playing.destroy_reason(10 * RoomRegistry.LOBBY_IDLE_MSEC, RoomRegistry.EMPTY_ROOM_GRACE_MSEC, RoomRegistry.LOBBY_IDLE_MSEC) == "", "active round never expires by idleness")

func _test_ready_gate_countdown() -> void:
	var room := RoomRegistry.new().create_room(0)
	var authority := room.round_authority
	for peer_id in [1, 2, 3, 4]:
		room.add_member(peer_id, "P%d" % peer_id, 0)
	_expect(authority.state == RoundState.WAITING, "four players alone do not start (gate)")
	for peer_id in [1, 2, 3]:
		room.set_ready(peer_id, true, 0)
	_expect(authority.state == RoundState.WAITING and authority.ready_count() == 3, "three of four ready: still waiting")
	room.set_ready(4, true, 100)
	_expect(authority.state == RoundState.COUNTDOWN, "all ready starts the countdown")
	_expect(authority.countdown_remaining_msec(100) == int(RoomRules.COUNTDOWN_SECONDS * 1000.0), "10 s countdown")
	room.set_ready(2, false, 200)
	_expect(authority.state == RoundState.WAITING, "cancel ready stops the countdown")
	room.set_ready(2, true, 300)
	_expect(authority.state == RoundState.COUNTDOWN, "ready again restarts")
	room.remove_member(3, 400)
	_expect(authority.state == RoundState.WAITING, "disconnect during countdown stops it (3 < min)")
	room.add_member(3, "P3b", 500)
	_expect(authority.state == RoundState.WAITING, "newcomer is not ready: no countdown")
	room.set_ready(3, true, 600)
	_expect(authority.state == RoundState.COUNTDOWN, "everyone ready again")
	authority.tick(600 + int(RoomRules.COUNTDOWN_SECONDS * 1000.0))
	_expect(authority.state == RoundState.ACTIVE and authority.participants.size() == 4, "round starts after the countdown")
	_expect(room.set_ready(1, false, 20000) == "not_ready_phase", "ready is locked mid-round")
	# Menos que o mínimo, mesmo todos prontos: não começa.
	var small := RoomRegistry.new().create_room(0)
	small.add_member(1, "A", 0)
	small.add_member(2, "B", 0)
	small.set_ready(1, true, 0)
	small.set_ready(2, true, 0)
	_expect(small.round_authority.state == RoundState.WAITING, "below the minimum never starts")
	_expect(small.set_ready(99, true, 0) == "not_in_room", "stranger cannot mark ready")

func _test_round_end_returns_to_lobby() -> void:
	var room := _room_with_active_round(RoomRegistry.new())
	var authority := room.round_authority
	var assassin := 0
	for peer_id in authority.participants:
		if authority.get_role_for_peer(int(peer_id)) == Role.ASSASSIN:
			assassin = int(peer_id)
	authority.eliminate_player(assassin, "test", 0, 30000)
	_expect(authority.state == RoundState.ENDED and room.phase() == RoomRules.PHASE_RESULTS, "round ends")
	room.record_result(authority.get_final_reveal())
	_expect(str(room.last_result["winner"]) == "INNOCENTS" and (room.last_result["players"] as Array).size() == 4, "result recorded with revealed roles")
	authority.tick(30000 + int(RoomRules.RESULTS_SECONDS * 1000.0))
	_expect(authority.state == RoundState.WAITING and room.phase() == RoomRules.PHASE_LOBBY, "back to the room lobby after results")
	_expect(authority.ready_count() == 0, "everyone must mark ready again")
	_expect(not authority.has_roles() and authority.participants.is_empty() and authority.final_reveal.is_empty(), "round state reset")
	authority.tick(99999999)
	_expect(authority.state == RoundState.WAITING, "no automatic next round")
	for peer_id in room.lobby.peer_ids():
		room.set_ready(int(peer_id), true, 100000)
	_expect(authority.state == RoundState.COUNTDOWN and authority.round_id == 2, "new round only after everyone is ready again")
	_expect(not room.public_state(100000)["result"].is_empty(), "previous result still shown in the lobby")

func _test_two_rooms_isolated() -> void:
	var registry := RoomRegistry.new()
	var red := _room_with_active_round(registry, 1)
	var blue := registry.create_room(0)
	for peer_id in [51, 52, 53, 54]:
		blue.add_member(peer_id, "Azul %d" % peer_id, 0)
	_expect(red.lobby != blue.lobby and red.world != blue.world and red.combat != blue.combat and red.bodies != blue.bodies and red.round_authority != blue.round_authority, "every authority is per room")
	for peer_id in [51, 52, 53, 54]:
		_expect(not red.lobby.has(peer_id) and not red.world.states.has(peer_id), "blue peer %d absent from red" % peer_id)
	for peer_id in red.lobby.peer_ids():
		_expect(not blue.lobby.has(int(peer_id)) and not blue.world.states.has(int(peer_id)), "red peer absent from blue")
	# Fim de rodada numa sala não afeta a outra.
	var assassin := 0
	for peer_id in red.round_authority.participants:
		if red.round_authority.get_role_for_peer(int(peer_id)) == Role.ASSASSIN:
			assassin = int(peer_id)
	red.round_authority.eliminate_player(assassin, "test", 0, 40000)
	_expect(red.round_authority.state == RoundState.ENDED, "red ended")
	_expect(blue.round_authority.state == RoundState.WAITING and blue.round_authority.round_id == 0 and not blue.round_authority.has_roles(), "blue untouched")
	_expect(blue.public_state(40000)["result"].is_empty(), "no result leaks to blue")
	var blue_labels: Array = []
	for entry in blue.public_state(0)["players"]:
		blue_labels.append(str(entry["label"]))
	for label in blue_labels:
		_expect(label.begins_with("Azul"), "blue DTO lists only blue players")
	_expect(registry.room_of(51) == null, "registry binding is explicit (assign)")
	registry.assign(51, blue)
	_expect(registry.room_of(51) == blue, "peer bound to its room")

func _test_room_state_dto() -> void:
	var room := _room_with_active_round(RoomRegistry.new())
	var dto := room.public_state(0)
	for key in dto.keys():
		_expect(str(key) in ["code", "phase", "round_id", "countdown_msec", "min_players", "max_players", "players", "ready_count", "result"], "DTO key allowlisted: %s" % key)
	for entry in dto["players"]:
		for key in (entry as Dictionary).keys():
			_expect(str(key) in ["peer_id", "label", "appearance", "ready", "host"], "player key allowlisted: %s" % key)
		_expect(not str(entry).contains("ASSASSIN") and not str(entry).contains("DETECTIVE"), "no role in player entry")
	_expect((dto["result"] as Dictionary).is_empty(), "no result during the round")
	var clean := RoomRules.sanitize_room_state({"code": room.code, "phase": "hacked", "players": [{"peer_id": 5, "label": "x", "role": "ASSASSIN", "appearance": "../../etc"}], "extra": 1})
	_expect(clean["phase"] == RoomRules.PHASE_LOBBY and not clean.has("extra"), "client sanitizer drops unknowns")
	_expect(not (clean["players"][0] as Dictionary).has("role") and clean["players"][0]["appearance"] == CharacterAppearance.FALLBACK, "client sanitizer allowlists player fields")
	_expect(RoomRules.sanitize_room_state({"code": "bad"}).is_empty() and RoomRules.sanitize_room_state("x").is_empty(), "bad DTO rejected")
	var many: Array = []
	for index in 20:
		many.append({"peer_id": index + 1, "label": "p%d" % index})
	_expect((RoomRules.sanitize_room_state({"code": "ABC234", "players": many})["players"] as Array).size() == RoundRules.MAX_PLAYERS, "player list capped at 8")

func _test_legacy_room_unchanged() -> void:
	# Sala única de local/LAN: sem gate, começa sozinha com o mínimo.
	var legacy := MatchRoom.new(0, "", 0, false, RoundRules.COUNTDOWN_SECONDS, RoundRules.ROUND_END_DELAY_SECONDS)
	for peer_id in [1, 2, 3, 4]:
		legacy.round_authority.join(peer_id, "L%d" % peer_id, 0)
	_expect(legacy.round_authority.state == RoundState.COUNTDOWN, "legacy room starts without ready gate")
	_expect(legacy.round_authority.set_ready(1, true, 0) == "rooms_unavailable", "ready not used without the gate")

## Sala com 4 jogadores já em rodada ACTIVE.
func _room_with_active_round(registry: RoomRegistry, base: int = 700) -> MatchRoom:
	var room := registry.create_room(0)
	for index in 4:
		room.add_member(base + index, "R%d_%d" % [base, index], 0)
	for peer_id in room.lobby.peer_ids():
		room.set_ready(int(peer_id), true, 0)
	room.round_authority.tick(int(RoomRules.COUNTDOWN_SECONDS * 1000.0))
	return room

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ROOMS_TEST_FAILED %s" % message)
