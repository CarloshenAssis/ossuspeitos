extends SceneTree

## Mira vertical de ponta a ponta: entrada de pitch no servidor (limites,
## NaN/infinito, taxa), snapshot, disparo com o pitch oficial (acima e abaixo
## da horizontal, piso, paredes, regressão horizontal, autoridade) e o cliente
## (câmera FPS, espectador e a cabeça do corpo remoto, sem inclinar o corpo).

const SHOOTER := 1
const TARGET := 2
const OTHER := 3

var failures := 0
var checks := 0
var rounds: RoundAuthority
var world: AuthoritativeWorld
var authority: CombatAuthority
var _now := 10_000
var _sequence := 0
var _arena: ArenaView
var _frame := 0

func _initialize() -> void:
	_test_aim_math()
	_test_pitch_input_authority()
	_setup_combat()
	_test_horizontal_regression()
	_test_shooting_up_and_down()
	_test_claimed_direction_is_not_trusted()
	_test_walls_still_block()
	_arena = ArenaView.new()
	_arena.local_peer_id = SHOOTER
	root.add_child(_arena)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_test_client_camera_follows_official_pitch()
	_test_spectator_sees_target_pitch()
	_test_remote_head_follows_pitch()
	if failures > 0:
		push_error("VERTICAL_AIM_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return true
	print("VERTICAL_AIM_TEST_OK checks=%d" % checks)
	quit(0)
	return true

# --- Regras e entrada -----------------------------------------------------------

func _test_aim_math() -> void:
	_expect(MovementRules.aim_direction(0.0, 0.0).is_equal_approx(Vector3.FORWARD), "pitch 0 is the old horizontal forward")
	_expect(MovementRules.aim_direction(0.0, 0.5).y > 0.47 and MovementRules.aim_direction(0.0, -0.5).y < -0.47, "positive pitch looks up, negative looks down")
	_expect(is_equal_approx(MovementRules.aim_direction(1.2, 0.4).length(), 1.0), "aim direction is normalised")
	for bad in [NAN, INF, -INF, "up", null, Vector3.UP]:
		_expect(MovementRules.clamp_pitch(bad) == 0.0, "invalid pitch %s becomes level" % str(bad))
	_expect(is_equal_approx(MovementRules.clamp_pitch(9.0), MovementRules.MAX_PITCH) and is_equal_approx(MovementRules.clamp_pitch(-9.0), -MovementRules.MAX_PITCH), "pitch clamps to the limit")
	_expect(MovementRules.MAX_PITCH < PI * 0.5 - 0.1, "the limit stays away from straight up/down")

func _test_pitch_input_authority() -> void:
	var input_world := AuthoritativeWorld.new()
	input_world.add_player(SHOOTER)
	var state: Dictionary = input_world.states[SHOOTER]
	_expect(float(state["pitch"]) == 0.0, "players spawn looking level")
	var sequence := 0
	var now := 1_000
	# Olhar para cima em passos válidos até o limite, sem passar dele.
	for step in 12:
		sequence += 1
		now += 200
		input_world.accept_input(SHOOTER, sequence, Vector2.ZERO, 0.0, now, 0.3)
	_expect(is_equal_approx(float(state["pitch"]), MovementRules.MAX_PITCH), "looking up stops at the official limit (%.3f)" % float(state["pitch"]))
	for step in 24:
		sequence += 1
		now += 200
		input_world.accept_input(SHOOTER, sequence, Vector2.ZERO, 0.0, now, -0.3)
	_expect(is_equal_approx(float(state["pitch"]), -MovementRules.MAX_PITCH), "looking down stops at the official limit")
	var before := float(state["pitch"])
	for bad in [NAN, INF, -INF]:
		sequence += 1
		now += 200
		_expect(input_world.accept_input(SHOOTER, sequence, Vector2.ZERO, 0.0, now, bad) == "non_finite", "pitch %s is rejected" % str(bad))
		_expect(float(state["pitch"]) == before, "rejected pitch %s changes nothing" % str(bad))
	sequence += 1
	now += 200
	_expect(input_world.accept_input(SHOOTER, sequence, Vector2.ZERO, 0.0, now, MovementRules.MAX_PITCH_DELTA + 0.01) == "pitch_delta", "oversized pitch step is rejected")
	# Rajada: sem tempo para repor os tokens, o terceiro passo grande é recusado.
	var reasons := []
	for step in 3:
		sequence += 1
		now += 1
		reasons.append(input_world.accept_input(SHOOTER, sequence, Vector2.ZERO, 0.0, now, 0.35))
	_expect(reasons.has("pitch_rate"), "pitch has a rate limit like yaw (%s)" % str(reasons))
	var snapshot: Dictionary = input_world.snapshot()[0]
	_expect(snapshot.has("pitch") and is_equal_approx(float(snapshot["pitch"]), MovementRules.clamp_pitch(state["pitch"])), "snapshot carries the official pitch")
	state["pitch"] = NAN
	_expect(float(input_world.snapshot()[0]["pitch"]) == 0.0, "a corrupted pitch never leaves the server")

# --- Disparo com o pitch oficial -------------------------------------------------

func _setup_combat() -> void:
	rounds = RoundAuthority.new()
	world = AuthoritativeWorld.new()
	for peer_id in [SHOOTER, TARGET, OTHER, 4]:
		world.add_player(peer_id)
	rounds.state = RoundState.ACTIVE
	rounds.round_id = 1
	rounds.participants = {1: true, 2: true, 3: true, 4: true}
	rounds.alive = {1: true, 2: true, 3: true, 4: true}
	rounds._roles = {1: Role.VICTIM, 2: Role.VICTIM, 3: Role.VICTIM, 4: Role.ASSASSIN}
	authority = CombatAuthority.new(rounds, world)
	authority.begin_round(1, [1, 2, 3, 4])
	world.states[SHOOTER]["position"] = ArenaRules.PICKUP_POSITIONS[0] + Vector3(0, 0.75, 0)
	_expect(authority.request_pickup(SHOOTER, "weapon_0", 1, 100)["accepted"], "shooter picks up the pistol")
	world.states[OTHER]["position"] = CombatNetworkCoordinator.SAFE_POSITIONS[0]
	world.states[4]["position"] = CombatNetworkCoordinator.SAFE_POSITIONS[1]

## Dispara para o norte pela faixa livre do Salão (x = 12, longe de colunas e
## pedestal; teto a 4,5 m) com a mira oficial dada; o alvo fica `distance`
## metros à frente.
const LANE_START := Vector3(12, MovementRules.PLAYER_HEIGHT, 16)

func _shot(pitch: float, distance: float, claimed: Variant = null) -> Dictionary:
	world.states[SHOOTER]["position"] = LANE_START
	world.states[SHOOTER]["yaw"] = 0.0
	world.states[SHOOTER]["pitch"] = pitch
	world.states[TARGET]["position"] = LANE_START - Vector3(0, 0, distance)
	authority.health[TARGET] = 100
	rounds.alive[TARGET] = true
	authority.inventory.inventories[SHOOTER]["magazine"] = 6
	_now += 1000
	_sequence += 1
	var eye: Vector3 = world.states[SHOOTER]["position"] + Vector3.UP * ArenaRules.EYE_HEIGHT
	var direction: Vector3 = claimed if claimed != null else MovementRules.aim_direction(0.0, pitch)
	var events: Array = []
	var capture := func(event: Dictionary): events.append(event)
	authority.shot_resolved.connect(capture)
	var result := authority.request_fire(SHOOTER, _sequence, eye, direction, _now)
	authority.shot_resolved.disconnect(capture)
	result["event"] = events[0] if not events.is_empty() else {}
	result["target_health"] = authority.health[TARGET]
	return result

func _test_horizontal_regression() -> void:
	var level := _shot(0.0, 5.0)
	_expect(level["accepted"] and level["hit"] and level["target_health"] == 66, "level shot still hits for 34")
	var event: Dictionary = level["event"]
	_expect(is_equal_approx((event["end"] as Vector3).y, (event["origin"] as Vector3).y), "level shot stays level")

func _test_shooting_up_and_down() -> void:
	var up := _shot(0.5, 5.0)
	var up_event: Dictionary = up["event"]
	_expect(up["accepted"] and not up["hit"] and up["target_health"] == 100, "aiming 0.5 rad up passes over a target 5 m away")
	var hall_ceiling := float(MansionMap.space("salao")["ceiling"])
	_expect(absf((up_event["end"] as Vector3).y - hall_ceiling) < 0.01, "the upward shot stops on the hall ceiling (end y=%.2f)" % (up_event["end"] as Vector3).y)
	var down_far := _shot(-0.5, 5.0)
	var far_event: Dictionary = down_far["event"]
	_expect(down_far["accepted"] and not down_far["hit"], "aiming 0.5 rad down hits the floor before a target 5 m away")
	_expect(absf((far_event["end"] as Vector3).y) < 0.01, "the downward shot ends on the official floor (y=%.3f)" % (far_event["end"] as Vector3).y)
	var down_near := _shot(-0.5, 2.0)
	_expect(down_near["hit"] and down_near["target_health"] == 66, "aiming down hits a target 2 m away")
	var up_near := _shot(0.5, 2.0)
	_expect(not up_near["hit"], "aiming up misses the same close target")
	var slight_up := _shot(0.05, 5.0)
	_expect(slight_up["hit"], "a slight upward aim still hits the body")
	# Pitch fora do limite no estado nunca vira disparo absurdo: usa o limite.
	var over := _shot(9.0, 5.0, MovementRules.aim_direction(0.0, MovementRules.MAX_PITCH))
	var over_event: Dictionary = over["event"]
	var slope := ((over_event["end"] as Vector3).y - (over_event["origin"] as Vector3).y) / absf((over_event["end"] as Vector3).z - (over_event["origin"] as Vector3).z)
	_expect(over["accepted"] and is_equal_approx(slope, tan(MovementRules.MAX_PITCH)), "an out-of-range official pitch fires at the limit")

func _test_claimed_direction_is_not_trusted() -> void:
	# O cliente não escolhe a vertical: mirar para cima com o pitch oficial
	# nivelado é recusado, e o alvo não perde vida.
	var cheat_up := _shot(0.0, 5.0, MovementRules.aim_direction(0.0, 0.8))
	_expect(not cheat_up["accepted"] and cheat_up["reason"] == "direction_pitch_divergence" and cheat_up["target_health"] == 100, "claimed pitch far from the official pitch is rejected")
	var cheat_level := _shot(0.8, 5.0, Vector3.FORWARD)
	_expect(not cheat_level["accepted"] and cheat_level["reason"] == "direction_pitch_divergence", "a level claim while the official aim is high is rejected")
	# Dentro da tolerância de latência, o disparo usa o pitch oficial, não o declarado.
	var near_claim := _shot(-0.5, 2.0, MovementRules.aim_direction(0.0, -0.3))
	var near_event: Dictionary = near_claim["event"]
	var near_slope := ((near_event["end"] as Vector3).y - (near_event["origin"] as Vector3).y) / absf((near_event["end"] as Vector3).z - (near_event["origin"] as Vector3).z)
	_expect(near_claim["accepted"] and is_equal_approx(near_slope, tan(-0.5)), "the shot follows the official pitch, not the claimed one")
	for bad in [Vector3(NAN, 0, -1), Vector3(0, INF, -1), Vector3(0, 0, -INF)]:
		var result := _shot(0.0, 5.0, bad)
		_expect(not result["accepted"] and result["reason"] == "non_finite", "non-finite direction %s is rejected" % str(bad))
	_expect(not _shot(0.0, 5.0, Vector3(0, 1, 0))["accepted"], "straight up is never a valid claim")
	var forged := CombatRules.new(authority.inventory).request_shot(SHOOTER, {"sequence": 999, "origin": Vector3.ZERO, "direction": Vector3.FORWARD, "end": Vector3(6, 1, 3), "hit": true}, {"alive": true, "round_active": true, "eye_position": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0}, _now + 5000)
	_expect(not forged["accepted"] and forged["reason"] == "forbidden_field", "a declared impact point or hit is refused")

func _test_walls_still_block() -> void:
	# Parede entre a Sala de Jantar e o Salão: nem nivelado nem levemente para cima.
	world.states[SHOOTER]["position"] = CombatNetworkCoordinator.WALL_SHOOTER
	world.states[TARGET]["position"] = CombatNetworkCoordinator.WALL_TARGET
	for pitch in [0.0, 0.1, -0.1]:
		world.states[SHOOTER]["yaw"] = 0.0
		world.states[SHOOTER]["pitch"] = pitch
		authority.health[TARGET] = 100
		authority.inventory.inventories[SHOOTER]["magazine"] = 6
		_now += 1000
		_sequence += 1
		var eye: Vector3 = world.states[SHOOTER]["position"] + Vector3.UP * ArenaRules.EYE_HEIGHT
		var result := authority.request_fire(SHOOTER, _sequence, eye, MovementRules.aim_direction(0.0, pitch), _now)
		_expect(result["accepted"] and not result["hit"] and authority.health[TARGET] == 100, "the dining-hall wall blocks a shot at pitch %.1f" % pitch)

# --- Cliente --------------------------------------------------------------------

func _state(peer_id: int, position: Vector3, yaw: float, pitch: Variant) -> Dictionary:
	return {"peer_id": peer_id, "position": position, "yaw": yaw, "pitch": pitch, "velocity": Vector3.ZERO, "spawn_index": 0}

func _test_client_camera_follows_official_pitch() -> void:
	for pitch in [0.0, 0.6, -0.6, MovementRules.MAX_PITCH]:
		_arena.apply_snapshot([_state(SHOOTER, Vector3(0, 1, 0), 0.7, pitch)])
		_expect(is_equal_approx(_arena.camera.rotation.x, pitch), "camera pitch follows the official pitch %.2f" % pitch)
		_expect(_arena.camera_direction().distance_to(MovementRules.aim_direction(0.7, pitch)) < 0.001, "the fired direction is the official aim at pitch %.2f" % pitch)
	_arena.apply_snapshot([_state(SHOOTER, Vector3(0, 1, 0), 0.0, 5.0)])
	_expect(is_equal_approx(_arena.camera.rotation.x, MovementRules.MAX_PITCH), "an out-of-range snapshot pitch is clamped on the client")
	_arena.apply_snapshot([_state(SHOOTER, Vector3(0, 1, 0), 0.0, NAN)])
	_expect(_arena.camera.rotation.x == 0.0, "a NaN snapshot pitch levels the camera")
	_arena.apply_snapshot([{"peer_id": SHOOTER, "position": Vector3(0, 1, 0), "yaw": 0.0, "velocity": Vector3.ZERO, "spawn_index": 0}])
	_expect(_arena.camera.rotation.x == 0.0, "a snapshot without pitch is level")
	_expect(_arena.camera.global_position.is_equal_approx(Vector3(0, 1 + ArenaRules.EYE_HEIGHT, 0)), "pitch never moves the eye (shot origin)")

func _test_spectator_sees_target_pitch() -> void:
	_arena.apply_snapshot([_state(SHOOTER, Vector3(0, 1, 0), 0.0, 0.0), _state(TARGET, Vector3(3, 1, 3), 1.0, -0.4)])
	_arena.set_spectator_target(TARGET)
	_arena.apply_snapshot([_state(SHOOTER, Vector3(0, 1, 0), 0.0, 0.0), _state(TARGET, Vector3(3, 1, 3), 1.0, -0.4)])
	_expect(is_equal_approx(_arena.camera.rotation.x, -0.4) and _arena.camera_direction().distance_to(MovementRules.aim_direction(1.0, -0.4)) < 0.001, "the spectator camera looks where the target officially aims")
	_arena.set_spectator_target(0, false)
	_expect(is_equal_approx(_arena.camera.rotation.x, 0.0), "leaving spectator returns to the own pitch")

func _test_remote_head_follows_pitch() -> void:
	var levels := {}
	for pitch in [0.0, 0.5, -0.5, MovementRules.MAX_PITCH]:
		_arena.apply_snapshot([_state(SHOOTER, Vector3(0, 1, 0), 0.0, 0.0), _state(TARGET, Vector3(3, 1, 3), 0.0, pitch)])
		for _i in 40: _arena._process(0.1)
		var avatar: Node3D = _arena.avatars[TARGET]
		var head := avatar.find_child(ArenaModels.HEAD_PIVOT, true, false) as Node3D
		var nose := avatar.find_child("Nose", true, false) as MeshInstance3D
		var head_mesh := avatar.find_child("Head", true, false) as MeshInstance3D
		var neck := avatar.find_child("Neck", true, false) as MeshInstance3D
		_expect(head != null and nose.get_parent() == head and head_mesh.get_parent() == head, "head, nose and hair hang from the head pivot")
		_expect(neck != null and neck.get_parent() != head, "the neck and body do not tilt")
		_expect(is_zero_approx(avatar.rotation.x) and is_zero_approx(avatar.rotation.z), "the body root never tilts (pitch %.2f)" % pitch)
		var face := (nose.global_transform * nose.get_aabb()).get_center() - (head_mesh.global_transform * head_mesh.get_aabb()).get_center()
		levels[pitch] = face.y
		_expect(absf(head.rotation.x) <= ArenaModels.HEAD_PITCH_LIMIT + 0.001, "head tilt stays natural at pitch %.2f" % pitch)
		_expect(_collision_nodes(avatar) == 0, "no collision added")
	_expect(levels[0.5] > levels[0.0] + 0.02 and levels[-0.5] < levels[0.0] - 0.02, "others see the face rise and drop with the official pitch (%s)" % str(levels))
	_expect(is_equal_approx(levels[MovementRules.MAX_PITCH], levels[MovementRules.MAX_PITCH]) and levels[MovementRules.MAX_PITCH] >= levels[0.5], "extreme aim keeps the head at its limit")
	# Em repouso a cabeça fica exatamente onde o GLB a desenhou.
	var fresh := ArenaModels.build_character("ember")
	root.add_child(fresh)
	var original := (load(CharacterAppearance.scene_path("ember")) as PackedScene).instantiate() as Node3D
	root.add_child(original)
	original.position = (fresh.get_node(ArenaModels.CHARACTER_MODEL) as Node3D).position
	original.rotation.y = ArenaModels.CHARACTER_YAW
	var moved := (fresh.find_child("Nose", true, false) as MeshInstance3D).global_position
	var reference := (original.find_child("Nose", true, false) as MeshInstance3D).global_position
	_expect(moved.distance_to(reference) < 0.001, "at rest the head pivot leaves the GLB head exactly in place")
	fresh.free()
	original.free()

func _collision_nodes(node: Node) -> int:
	var count := 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children():
		count += _collision_nodes(child)
	return count

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("VERTICAL_AIM_CHECK_FAILED %s" % description)
