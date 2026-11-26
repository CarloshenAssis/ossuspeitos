extends SceneTree

## Carrega o combate só depois de selecionar a variante, como o teste de planta.

var failures := 0
var checks := 0

static func _static_init() -> void:
	OS.set_environment("OSSUSPEITOS_MAP", "nocturna_salao")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var rounds = load("res://server/round_authority.gd").new()
	var world = load("res://server/authoritative_world.gd").new()
	for peer_id in range(1, 5):
		world.add_player(peer_id)
	var round_state = load("res://shared/round_state.gd")
	var role = load("res://shared/role.gd")
	rounds.state = round_state.ACTIVE
	rounds.round_id = 1
	rounds.participants = {1: true, 2: true, 3: true, 4: true}
	rounds.alive = {1: true, 2: true, 3: true, 4: true}
	rounds._roles = {1: role.ASSASSIN, 2: role.DETECTIVE, 3: role.VICTIM, 4: role.VICTIM}
	var CombatAuthoritySc = load("res://server/combat_authority.gd")
	var authority = CombatAuthoritySc.new(rounds, world)
	authority.begin_round(1, [1, 2, 3, 4])

	var pickups: Array = authority.public_pickups()
	_expect(pickups.size() == 25, "nocturna round has eight weapons, twelve ammo and five health")
	var counts := {"weapon": 0, "ammo": 0, "health": 0}
	for pickup in pickups:
		_expect(pickup.keys().size() == 5 and not pickup.has("weapon_id") and not pickup.has("amount"), "health snapshot stays on the public allowlist")
		var kind := str(pickup["type"])
		counts[kind] = int(counts.get(kind, 0)) + 1
	_expect(counts["weapon"] == 8 and counts["ammo"] == 12 and counts["health"] == 5, "public counts match the official list")
	_expect(authority.inventory.definitions.has("hunting_rifle") and authority.inventory.definitions.has("coach_gun"), "nocturna catalogue is armed")
	_expect(str(authority.inventory.ground_items["weapon_0"]["weapon_id"]) == "hunting_rifle", "hall weapon is the rifle")
	_expect(str(authority.inventory.ground_items["weapon_1"]["weapon_id"]) == "coach_gun", "gallery weapon is the shotgun")

	var kit_position: Vector3 = authority.inventory.ground_items["health_0"]["position"]
	world.states[1]["position"] = kit_position
	var full: Dictionary = authority.request_pickup(1, "health_0", 1, 100)
	_expect(str(full.get("reason", "")) == "health_full", "full health is rejected")
	_expect(bool(authority.inventory.ground_items["health_0"]["available"]), "rejected heal leaves the box")
	_expect(authority.health[1] == CombatAuthoritySc.MAX_HEALTH, "full health is unchanged")

	authority.health[1] = 70
	var healed: Dictionary = authority.request_pickup(1, "health_0", 2, 200)
	_expect(bool(healed.get("accepted", false)), "injured player heals")
	_expect(authority.health[1] == 100, "heal clamps to max health")
	_expect(not bool(authority.inventory.ground_items["health_0"]["available"]), "collected box disappears")

	world.states[2]["position"] = kit_position
	_expect(str(authority.request_pickup(2, "health_0", 1, 300).get("reason", "")) == "item_unavailable", "box stays down until respawn")

	authority.tick(CombatAuthoritySc.HEALTH_RESPAWN_MSEC + 199)
	_expect(not bool(authority.inventory.ground_items["health_0"]["available"]), "box does not return early")
	authority.tick(CombatAuthoritySc.HEALTH_RESPAWN_MSEC + 200)
	_expect(bool(authority.inventory.ground_items["health_0"]["available"]), "box returns after the official timer")

	if failures:
		quit(1)
		return
	print("NOCTURNA_HEALTH_TEST_OK checks=%d" % checks)
	quit(0)

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
