extends SceneTree

## Aparência cosmética pública dos jogadores (protocolo 7): o servidor atribui
## uma das oito variantes na entrada da sessão, distinta enquanto houver até
## oito sessões, estável durante a sessão e independente de papel, rodada ou
## qualquer estado privado. O roster público a leva; o cliente só aceita chaves
## e ids da allowlist.

const BASE_MSEC := 10_000
const SEED := 20_250_924

var failures := 0
var checks := 0

func _initialize() -> void:
	_test_allowlist()
	_test_distinct_and_stable_assignment()
	_test_independent_of_roles_and_rounds()
	_test_client_roster_allowlist()
	_test_protocol_version()
	if failures > 0:
		push_error("CHARACTER_APPEARANCE_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return
	print("CHARACTER_APPEARANCE_TEST_OK checks=%d" % checks)
	quit(0)

func _test_allowlist() -> void:
	_expect(CharacterAppearance.IDS.size() == 8, "eight appearances")
	for appearance_id in CharacterAppearance.IDS:
		_expect(ResourceLoader.exists(CharacterAppearance.scene_path(appearance_id)), "%s GLB is in the project (no runtime download)" % appearance_id)
		_expect(CharacterAppearance.sanitize(appearance_id) == appearance_id, "%s is allowed" % appearance_id)
	for bad in ["", "ASSASSIN", "detective", "../../etc", "res://x.glb", 3, null, ["ash"], {"id": "ash"}]:
		_expect(CharacterAppearance.sanitize(bad) == CharacterAppearance.FALLBACK, "invalid appearance %s falls back" % str(bad))
		_expect(CharacterAppearance.scene_path(bad) == CharacterAppearance.scene_path(CharacterAppearance.FALLBACK), "invalid appearance %s never builds a path" % str(bad))

func _test_distinct_and_stable_assignment() -> void:
	var lobby := LobbyRegistry.new()
	for index in 8:
		_expect(lobby.add(100 + index, "client-%d" % index).is_empty(), "client %d joins" % index)
	var seen := {}
	for peer_id in lobby.peer_ids():
		var appearance := lobby.appearance_for(peer_id)
		_expect(CharacterAppearance.is_valid(appearance), "peer %d has an allowlisted appearance" % peer_id)
		seen[appearance] = true
	_expect(seen.size() == 8, "eight sessions get eight distinct appearances")
	_expect(lobby.appearance_for(100) == CharacterAppearance.IDS[0] and lobby.appearance_for(107) == CharacterAppearance.IDS[7], "assignment follows join order")
	# Quem sai libera a variante; a próxima entrada a reaproveita e os demais
	# não mudam.
	var before := _appearance_map(lobby)
	var freed := lobby.appearance_for(103)
	lobby.remove(103)
	_expect(lobby.add(200, "late-client").is_empty(), "a late client joins")
	_expect(lobby.appearance_for(200) == freed, "the late client receives the freed appearance")
	for peer_id in before:
		if peer_id != 103:
			_expect(lobby.appearance_for(peer_id) == before[peer_id], "peer %d keeps its appearance after others leave or join" % peer_id)
	# Entradas públicas levam a mesma aparência.
	for entry in lobby.public_entries():
		_expect(str(entry["appearance"]) == lobby.appearance_for(int(entry["peer_id"])), "public entry of %d carries its appearance" % int(entry["peer_id"]))

func _test_independent_of_roles_and_rounds() -> void:
	# Duas salas com as mesmas entradas e sementes diferentes: os papéis
	# mudam, as aparências não.
	var maps: Array = []
	var roles: Array = []
	for round_seed in [SEED, SEED + 7]:
		var authority := RoundAuthority.new(LobbyRegistry.new(), round_seed)
		authority.configure(1.0, 1.0)
		for index in 5:
			authority.join(300 + index, "client-%d" % index, BASE_MSEC)
		var before_roles := _roster_appearances(authority)
		authority.tick(BASE_MSEC + 60_000)
		authority.tick(BASE_MSEC + 61_000)
		_expect(authority.state == RoundState.ACTIVE, "round starts (seed %d)" % round_seed)
		var after_roles := _roster_appearances(authority)
		_expect(before_roles == after_roles, "role assignment does not change appearances (seed %d)" % round_seed)
		var role_map := {}
		for index in 5:
			role_map[300 + index] = authority.get_role_for_peer(300 + index)
		maps.append(after_roles)
		roles.append(role_map)
		for entry in authority.public_roster():
			for key in entry:
				_expect(not str(key).to_lower().contains("role"), "public roster has no role key (%s)" % key)
	_expect(roles[0] != roles[1], "the two seeds really deal different roles")
	_expect(maps[0] == maps[1], "same joins, different roles: same appearances")

func _test_client_roster_allowlist() -> void:
	var app_script := load("res://shared/network_app.gd")
	var hostile := {"peer_id": 7, "label": "Ana", "connected": true, "participant": true, "alive": true,
		"appearance": "ash", "inventory": {"weapon_id": "common_pistol"}, "team": 2, "secret": "x"}
	var clean: Dictionary = app_script.sanitize_roster_entry(hostile)
	_expect(clean.keys().size() <= 6 and not clean.has("inventory") and not clean.has("team") and not clean.has("secret"), "unknown roster keys are dropped")
	_expect(clean["appearance"] == "ash" and clean["label"] == "Ana" and int(clean["peer_id"]) == 7, "allowed keys survive")
	var bad: Dictionary = app_script.sanitize_roster_entry({"peer_id": 8, "label": "Beto", "appearance": "ASSASSIN"})
	_expect(bad["appearance"] == CharacterAppearance.FALLBACK, "unknown appearance id becomes the fallback")
	var missing: Dictionary = app_script.sanitize_roster_entry({"peer_id": 9, "label": "Caio"})
	_expect(missing["appearance"] == CharacterAppearance.FALLBACK, "missing appearance becomes the fallback")
	var bogus_peer: Dictionary = app_script.sanitize_roster_entry({"peer_id": "9", "appearance": "moss"})
	_expect(int(bogus_peer["peer_id"]) == 0, "non-integer peer id is not trusted")

func _test_protocol_version() -> void:
	_expect(NetworkConfig.PROTOCOL_VERSION == 7, "roster appearance bumps the protocol to 7")

func _appearance_map(lobby: LobbyRegistry) -> Dictionary:
	var result := {}
	for peer_id in lobby.peer_ids():
		result[peer_id] = lobby.appearance_for(peer_id)
	return result

func _roster_appearances(authority: RoundAuthority) -> Dictionary:
	var result := {}
	for entry in authority.public_roster():
		result[int(entry["peer_id"])] = str(entry["appearance"])
	return result

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("CHARACTER_APPEARANCE_CHECK_FAILED %s" % description)
