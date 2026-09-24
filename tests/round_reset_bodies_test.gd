extends SceneTree

## Fase 6: reset completo da rodada, pickups oficiais (8 + 12) e corpos.
## Determinístico, sem rede: autoridades, previsão, interpolação e a
## apresentação (`ArenaView`) usadas diretamente.

var failures := 0
var checks := 0
var _frame := 0
var _arena: ArenaView

func _initialize() -> void:
	_arena = ArenaView.new()
	_arena.local_peer_id = 1
	root.add_child(_arena)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_test_reset_to_spawn()
	_test_pickups_restore_once_per_round()
	_test_prediction_teleports_on_new_round()
	_test_interpolator_teleports_on_new_round()
	_test_body_registry_and_dto()
	_test_body_needs_official_elimination()
	_test_body_does_not_block_or_absorb_shots()
	_test_body_presentation()
	if failures > 0:
		push_error("ROUND_RESET_BODIES_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return true
	print("ROUND_RESET_BODIES_TEST_OK checks=%d" % checks)
	quit(0)
	return true

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ROUND_RESET_BODIES_CHECK_FAILED %s" % message)

func _fixture(players: int) -> Dictionary:
	var lobby := LobbyRegistry.new()
	var rounds := RoundAuthority.new(lobby, 7)
	var world := AuthoritativeWorld.new()
	var peers: Array = []
	for index in players:
		var peer_id := index + 1
		world.add_player(peer_id)
		lobby.add(peer_id, "p%d" % peer_id)
		peers.append(peer_id)
		rounds.participants[peer_id] = true
		rounds.alive[peer_id] = true
	rounds.state = RoundState.ACTIVE
	rounds.round_id = 1
	var combat := CombatAuthority.new(rounds, world)
	combat.begin_round(1, peers)
	return {"world": world, "combat": combat, "rounds": rounds, "lobby": lobby, "peers": peers}

# --- Reset --------------------------------------------------------------------------

func _test_reset_to_spawn() -> void:
	var fixture := _fixture(8)
	var world: AuthoritativeWorld = fixture["world"]
	# Rodada anterior: todos longe do spawn, andando, olhando para cima, com
	# comandos na fila (um sobrevivente e um eliminado entre eles).
	for peer_id in fixture["peers"]:
		var state: Dictionary = world.states[peer_id]
		state["position"] = Vector3(13.5, 1.0, 14.0)
		state["velocity"] = Vector3(4.0, 0.0, 1.0)
		state["yaw"] = 2.0
		state["pitch"] = 0.8
		state["yaw_tokens"] = 0.0
		state["pitch_tokens"] = 0.0
		state["catch_up"] = true
		world.receive_commands(int(peer_id), NetSync.encode_packet(int(state["epoch"]), 1,
			[NetSync.encode_command(Vector2(0, -1), 0.0, 0.0, ["fire", 1])]), 1000 + int(peer_id))
	var epochs := {}
	for peer_id in fixture["peers"]:
		epochs[peer_id] = int(world.states[peer_id]["epoch"])
	for peer_id in fixture["peers"]:
		world.reset_to_spawn(int(peer_id))
	var positions := {}
	for peer_id in fixture["peers"]:
		var state: Dictionary = world.states[peer_id]
		var index := int(state["spawn_index"])
		_expect((state["position"] as Vector3).is_equal_approx(MovementRules.SPAWN_POINTS[index]), "peer %d back on its spawn %d" % [peer_id, index])
		_expect(absf(float(state["yaw"]) - MansionMap.spawn_yaw_at(index)) < 1e-6, "peer %d faces its spawn door" % peer_id)
		_expect(float(state["pitch"]) == 0.0 and (state["velocity"] as Vector3) == Vector3.ZERO, "peer %d stands still, pitch zero" % peer_id)
		_expect(float(state["yaw_tokens"]) == MovementRules.MAX_YAW_DELTA * 2.0 and not state.has("catch_up"), "peer %d look budget and catch-up reset" % peer_id)
		_expect(int(state["epoch"]) == int(epochs[peer_id]) + 1, "peer %d gets a new epoch" % peer_id)
		positions["%.2f,%.2f" % [(state["position"] as Vector3).x, (state["position"] as Vector3).z]] = true
	_expect(positions.size() == 8, "eight participants on eight distinct spawns")
	# O que estava na fila é recusado pela época, sem mover nem atirar.
	var refused: Array = []
	world.step(func(_p): return "", func(_p, _a, _s): _expect(false, "stale action must not run"), func(p, _s, _a, reason): refused.append(reason))
	_expect(refused.size() == 8 and refused.all(func(r): return r == "stale_epoch"), "queued commands of the old round refused as stale_epoch (%s)" % str(refused))
	for peer_id in fixture["peers"]:
		var state: Dictionary = world.states[peer_id]
		_expect((state["position"] as Vector3).is_equal_approx(MovementRules.SPAWN_POINTS[int(state["spawn_index"])]), "peer %d not moved by old commands" % peer_id)

func _test_pickups_restore_once_per_round() -> void:
	var fixture := _fixture(8)
	var combat: CombatAuthority = fixture["combat"]
	var world: AuthoritativeWorld = fixture["world"]
	for round_id in [1, 2, 3]:
		if round_id > 1:
			combat.begin_round(round_id, fixture["peers"])
		var pickups := combat.public_pickups()
		var weapons := pickups.filter(func(e): return str(e["type"]) == "weapon")
		var ammo := pickups.filter(func(e): return str(e["type"]) == "ammo")
		_expect(weapons.size() == 8 and ammo.size() == 12, "round %d: exactly 8 pistols and 12 ammo boxes" % round_id)
		_expect(combat.inventory.ground_items.size() == 20, "round %d: no duplicated ground records (%d)" % [round_id, combat.inventory.ground_items.size()])
		for entry in pickups:
			_expect(bool(entry["available"]) and int(entry["round_id"]) == round_id, "round %d: %s available" % [round_id, entry["pickup_id"]])
			_expect((entry["position"] as Vector3).is_equal_approx(MansionMap.pickup_position(str(entry["pickup_id"]))), "round %d: %s at its official position" % [round_id, entry["pickup_id"]])
		# Coleta única: o primeiro leva, o segundo recebe indisponível.
		var at := MansionMap.pickup_position("weapon_3")
		world.states[1]["position"] = Vector3(at.x, 1.0, at.z)
		world.states[2]["position"] = Vector3(at.x, 1.0, at.z)
		_expect(bool(combat.request_pickup(1, "weapon_3", 1, round_id * 10000)["accepted"]), "round %d: first pickup accepted" % round_id)
		_expect(str(combat.request_pickup(2, "weapon_3", 1, round_id * 10000 + 100)["reason"]) == "item_unavailable", "round %d: second pickup refused" % round_id)
		fixture["rounds"].round_id = round_id + 1

func _test_prediction_teleports_on_new_round() -> void:
	var prediction := PlayerPrediction.new()
	var far := {"peer_id": 1, "position": Vector3(13.5, 1.0, 14.0), "velocity": Vector3(4, 0, 0), "yaw": 1.0, "pitch": 0.5, "epoch": 3}
	prediction.reconcile({"seq": 0, "epoch": 3}, far)
	for i in 5:
		prediction.build_command(Vector2(1, 0))
	prediction.position_offset = Vector3(0.2, 0, 0)
	var spawn := MovementRules.SPAWN_POINTS[0]
	var result := prediction.reconcile({"seq": 2, "epoch": 4}, {"peer_id": 1, "position": spawn, "velocity": Vector3.ZERO, "yaw": MansionMap.spawn_yaw_at(0), "pitch": 0.0, "epoch": 4})
	_expect(bool(result.get("reset", false)), "new epoch resets prediction")
	_expect(prediction.pending.is_empty() and prediction.position_offset == Vector3.ZERO, "no pending commands or visual offset survive the reset")
	var presented := prediction.presented(0.5, 0.016)
	_expect((presented["position"] as Vector3).is_equal_approx(spawn), "local view jumps to the spawn (no lerp across the mansion)")
	_expect(absf(float(presented["pitch"])) < 1e-6, "local pitch back to zero")

func _test_interpolator_teleports_on_new_round() -> void:
	var interpolator := RemoteInterpolator.new()
	var old_position := Vector3(13.5, 1.0, 14.0)
	for tick in range(1, 40, 3):
		interpolator.push(tick, [{"peer_id": 2, "position": old_position, "yaw": 0.0, "pitch": 0.3, "epoch": 5}])
		interpolator.advance(3.0 / NetSync.TICK_RATE)
	var spawn := MovementRules.SPAWN_POINTS[3]
	for tick in range(40, 80, 3):
		interpolator.push(tick, [{"peer_id": 2, "position": spawn, "yaw": 1.0, "pitch": 0.0, "epoch": 6}])
	var first := true
	for step in 30:
		interpolator.advance(1.0 / NetSync.TICK_RATE)
		var sample := interpolator.sample(2)
		if sample.is_empty():
			continue
		var position: Vector3 = sample["position"]
		# Nunca um ponto no meio do caminho entre a posição velha e o spawn.
		_expect(position.is_equal_approx(old_position) or position.is_equal_approx(spawn), "remote never presented between rounds (%s)" % str(position))
		if position.is_equal_approx(spawn) and first:
			first = false
			_expect(bool(sample["discontinuity"]), "the jump to the spawn is flagged as a discontinuity")
	_expect(not first, "remote reaches its spawn")

# --- Corpos: autoridade e DTO ------------------------------------------------------

func _test_body_registry_and_dto() -> void:
	var registry := BodyRegistry.new()
	var dto := registry.add(4, 7, Vector3(10, 1, 12), 0.5, "moss")
	_expect(not dto.is_empty(), "body registered")
	_expect(dto.keys() == BodyRules.PUBLIC_KEYS, "body DTO is the exact public allowlist (%s)" % str(dto.keys()))
	for forbidden in ["role", "inventory", "weapon_id", "magazine", "reserve", "health", "instigator", "shooter_peer_id"]:
		_expect(not dto.has(forbidden), "body DTO has no %s" % forbidden)
	_expect(registry.add(4, 7, Vector3(0, 1, 0), 0.0, "moss").is_empty(), "duplicate elimination creates no second body")
	_expect(registry.size() == 1, "one body per eliminated player per round")
	_expect(not registry.add(4, 8, Vector3(1, 1, 1), 0.0, "ember").is_empty(), "another player gets its own body")
	_expect(registry.public_list().size() == 2, "public list holds both bodies")
	registry.clear()
	_expect(registry.size() == 0 and registry.public_list().is_empty(), "reset removes every body")
	# Validação no cliente: chave extra, papel ou tipo errado viram vazio.
	var clean := BodyRules.make(1, 2, 3, Vector3(1, 1, 1), 0.0, "ember")
	_expect(BodyRules.sanitize(clean) == clean, "valid DTO passes")
	var with_role := clean.duplicate(); with_role["role"] = "ASSASSIN"
	_expect(BodyRules.sanitize(with_role).is_empty(), "DTO with a role is refused")
	var wrong := clean.duplicate(); wrong["position"] = "10,1,12"
	_expect(BodyRules.sanitize(wrong).is_empty(), "DTO with a wrong type is refused")
	var nan := clean.duplicate(); nan["position"] = Vector3(NAN, 0, 0)
	_expect(BodyRules.sanitize(nan).is_empty(), "DTO with a non-finite position is refused")
	var bad_look := clean.duplicate(); bad_look["appearance"] = "../../x"
	_expect(str(BodyRules.sanitize(bad_look)["appearance"]) == CharacterAppearance.FALLBACK, "unknown appearance falls back")

## Só a eliminação de combate emite `player_eliminated` (que cria o corpo no
## servidor). Sair vivo é a política de desconexão, sem corpo.
func _test_body_needs_official_elimination() -> void:
	var fixture := _fixture(4)
	var combat: CombatAuthority = fixture["combat"]
	var rounds: RoundAuthority = fixture["rounds"]
	var emitted: Array = []
	combat.player_eliminated.connect(func(peer_id, _by): emitted.append(peer_id))
	rounds.leave(4, 1000)
	_expect(emitted.is_empty(), "an alive player leaving creates no elimination event")
	# Tiros reais até a eliminação.
	var world: AuthoritativeWorld = fixture["world"]
	combat.inventory.inventories[1]["weapon_id"] = CombatAuthority.COMMON_WEAPON_ID
	combat.inventory.inventories[1]["equipped"] = true
	combat.inventory.inventories[1]["magazine"] = 6
	world.states[1]["position"] = Vector3(12.0, 1.0, 15.5)
	world.states[1]["yaw"] = PI * 0.5
	world.states[2]["position"] = Vector3(9.0, 1.0, 15.5)
	world.states[3]["position"] = Vector3(30.0, 1.0, 18.5)
	for shot in 3:
		combat.request_fire(1, shot + 1, 5000 + shot * 1000)
	_expect(emitted == [2], "the official elimination emits exactly once (%s)" % str(emitted))

func _test_body_does_not_block_or_absorb_shots() -> void:
	var fixture := _fixture(3)
	var combat: CombatAuthority = fixture["combat"]
	var world: AuthoritativeWorld = fixture["world"]
	var rounds: RoundAuthority = fixture["rounds"]
	combat.inventory.inventories[1]["weapon_id"] = CombatAuthority.COMMON_WEAPON_ID
	combat.inventory.inventories[1]["equipped"] = true
	combat.inventory.inventories[1]["magazine"] = 6
	# O eliminado (corpo) está entre o atirador e o alvo vivo.
	world.states[1]["position"] = Vector3(12.0, 1.0, 15.5)
	world.states[1]["yaw"] = PI * 0.5
	world.states[2]["position"] = Vector3(10.5, 1.0, 15.5)
	world.states[3]["position"] = Vector3(9.0, 1.0, 15.5)
	rounds.alive[2] = false
	var result := combat.request_fire(1, 1, 5000)
	_expect(int(result.get("hit_peer_id", 0)) == 3, "a shot passes the body and hits the living player behind (%s)" % str(result))
	# Movimento: o corpo não é volume oficial.
	_expect(not ArenaRules.overlaps_blocker(Vector3(10.5, 1.0, 15.5)), "the body spot stays walkable")

# --- Corpos: apresentação ----------------------------------------------------------

func _test_body_presentation() -> void:
	var dto := BodyRules.make(11, 5, 2, Vector3(13.5, 1.0, 14.8), 0.7, "moss")
	_expect(_arena.add_body(dto), "body shown")
	_expect(not _arena.add_body(dto), "same body is not shown twice")
	var again := BodyRules.make(12, 5, 2, Vector3(20, 1, 2), 0.0, "moss")
	_expect(not _arena.add_body(again), "a second body of the same player in the same round is ignored")
	_expect(_arena.bodies.size() == 1 and not _arena.avatars.has(2), "body is separate from the living avatars")
	var node: Node3D = _arena.bodies[11]
	_expect(node.find_children("*", "CollisionObject3D", true, false).is_empty() and node.find_children("*", "CollisionShape3D", true, false).is_empty(), "body has no collision")
	var character := node.find_child("Character", true, false) as Node3D
	_expect(character != null and str(character.get_meta("appearance", "")) == "moss", "body keeps the player's appearance")
	var official: Vector3 = dto["position"]
	_expect(Vector2(node.position.x, node.position.z).distance_to(Vector2(official.x, official.z)) <= ArenaView.BODY_MAX_NUDGE + 1e-4, "body stays at the official death spot")
	_expect(absf(node.position.y) < 1e-4, "body root on the official floor")
	var box := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var part: AABB = (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
		box = part if first else box.merge(part)
		first = false
	_expect(box.position.y > -0.02 and box.position.y < 0.05, "body rests on the floor (lowest %.3f)" % box.position.y)
	_expect(box.size.y < 0.75, "body is lying down (height %.2f)" % box.size.y)
	_expect(maxf(box.size.x, box.size.z) > 1.4, "body is stretched on the floor (%.2f x %.2f)" % [box.size.x, box.size.z])
	print("BODY_POSE lowest=%.3f height=%.2f length=%.2f" % [box.position.y, box.size.y, maxf(box.size.x, box.size.z)])
	# Snapshots não tocam o corpo.
	var before := node.global_transform
	_arena.apply_snapshot([{"peer_id": 2, "position": Vector3(30, 1, 18.5), "yaw": 0.0, "pitch": 0.9, "epoch": 9, "velocity": Vector3.ZERO}], 500)
	_arena._process(0.1)
	_expect(node.global_transform.is_equal_approx(before), "snapshots, pitch and movement never move the body")
	# Junto à parede: a apresentação corrige pouco e não muda de cômodo.
	var near_wall := ArenaView.body_placement(Vector3(1.6, 1.0, 4.4), 0.0)
	_expect(float(near_wall["nudge"]) <= ArenaView.BODY_MAX_NUDGE + 1e-4, "wall correction stays within the documented limit")
	_expect(str(MansionMap.space_at(near_wall["position"] + Vector3.UP).get("id", "")) == "escritorio", "wall correction keeps the body in its room")
	_expect(not bool(near_wall.get("clipped", false)), "a fitting pose is found next to the wall")
	# Reset: a rodada seguinte remove os corpos da anterior.
	_arena.add_body(BodyRules.make(13, 6, 3, Vector3(24.0, 1.0, 11.5), 0.0, "ember"))
	_arena.clear_bodies(6)
	_expect(_arena.bodies.size() == 1 and _arena.bodies.has(13), "bodies of other rounds removed, current round kept")
	_arena.clear_bodies()
	_expect(_arena.bodies.is_empty(), "round reset removes every body")
