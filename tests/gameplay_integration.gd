extends Node

## Cross-system fixture: production authorities, integrator, prediction and view.
## No alternate simulation or transport; real transport is mandatory in wrapper.
var failures := 0
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("GAMEPLAY_INTEGRATION_ASSERT " + label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var room := MatchRoom.new(1, "ABC234", 0, true, 0.2, 0.2, 8)
	var other := MatchRoom.new(2, "DEF234", 0, true, 0.2, 0.2, 8)
	other.add_member(99, "Other", 0)
	other.world.set_telemetry_enabled(true)
	var other_before := other.world.snapshot().duplicate(true)
	var other_ack := other.world.ack_for(99)
	for peer in range(1, 5):
		check(room.add_member(peer, "Player%d" % peer, 0).reason == "", "same four peers join")
	check(room.round_authority.state == RoundState.WAITING, "ready gate holds lobby")
	check(room.public_state(0).result.is_empty(), "no premature reveal")
	for peer in range(1, 5):
		check(room.set_ready(peer, true, 10) == "", "ready accepted")
	check(room.round_authority.state == RoundState.COUNTDOWN, "all ready enters countdown")
	room.round_authority.tick(1000)
	check(room.round_authority.state == RoundState.ACTIVE, "countdown enters round")
	room.combat.begin_round(room.round_authority.round_id, room.lobby.peer_ids())
	for peer in room.lobby.peer_ids(): room.world.reset_to_spawn(peer)
	room.world.set_telemetry_enabled(true)
	var prediction := PlayerPrediction.new()
	prediction.reconcile(room.world.ack_for(1), room.world.states[1])
	var initial: Vector3 = prediction.state.position
	for tick in 12:
		var command := prediction.build_command(Vector2(0, -1))
		var packet := NetSync.encode_packet(command.epoch, command.seq, [NetSync.encode_command(command.move, command.yaw_delta, command.pitch_delta, [])])
		room.world.receive_commands(1, packet, tick * 20)
		room.world.step(func(_peer): return "", func(_peer, _action, _seq): pass, func(_peer, _seq, _action, _reason): pass)
		check(prediction.state.position.is_equal_approx(room.world.states[1].position), "prediction matches command before authoritative ACK")
		prediction.reconcile(room.world.ack_for(1), room.world.states[1])
		check(prediction.state.position.is_equal_approx(room.world.states[1].position), "shared movement and replay agree")
	check(prediction.state.position.distance_to(initial) > 0.05, "movement changes official position")
	check(room.world.telemetry_snapshot().queued == 12 and other.world.telemetry_snapshot().queued == 0, "actual commands measured and rooms isolated")
	# Feed the actual simulated movement velocity into configured accuracy.
	var definition := WeaponDefinition.new("lab", 0, 6, 0, 400, 20, 1200, 0.0, 0.1, 0.02, 0.05, 0.01)
	var inventory := InventoryAuthority.new({"lab": definition})
	inventory.register_player(1)
	inventory.add_ground_weapon("lab_gun", "lab", prediction.state.position)
	check(inventory.pickup_weapon(1, "lab_gun", true, true, prediction.state.position) == "", "configured lab catalog pickup")
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var rules := CombatRules.new(inventory, rng)
	var configured := rules.request_shot(1, {"sequence": 1, "origin": Vector3.ZERO, "direction": Vector3.FORWARD}, {"alive": true, "round_active": true, "eye_position": Vector3.ZERO, "yaw": 0.0, "velocity": prediction.state.velocity}, 1000)
	check(configured.accepted and configured.direction != Vector3.FORWARD and configured.direction.is_finite(), "real movement drives configured authoritative spread")
	check(is_equal_approx(inventory.get_inventory(1).shot_bloom_radians, 0.02), "configured shot records bloom")
	var arena := ArenaView.new()
	add_child(arena)
	arena.set_process(false)
	arena.local_peer_id = 1
	arena.apply_snapshot(room.world.snapshot(), 1)
	arena._process(0.0)
	# Use the real pickup/catalog/reload/raycast path with injected server times.
	room.world.teleport(1, Vector3(12, 1, 16), 0.0, 0.0)
	room.combat.inventory.ground_items.weapon_0.position = room.world.states[1].position
	check(room.combat.request_pickup(1, "weapon_0", 1, 2000).accepted, "pickup arms player")
	room.combat.inventory.ground_items.ammo_0.position = room.world.states[1].position
	check(room.combat.request_pickup(1, "ammo_0", 2, 2200).accepted, "ammo pickup supplies reload reserve")
	check(room.combat.private_state(1).weapon_id == "common_pistol", "trusted catalog weapon")
	arena.apply_combat_state(room.combat.private_state(1))
	var origin := arena.camera_origin()
	var direction := arena.camera_direction()
	var official := room.world.snapshot().duplicate(true)
	for profile in ["low", "high", "baseline"]:
		arena.set_graphics_profile(profile)
		arena.set_presentation_motion(true)
		arena._process(0.1)
		check(arena.motion_pivot.transform != Transform3D.IDENTITY, "live equipped movement animates before reset")
		check(arena.camera_origin() == origin and arena.camera_direction() == direction, "presentation preserves official aim")
		check(room.world.snapshot() == official, "graphics never mutates authority")
	arena.set_presentation_motion(false)
	check(arena.motion_pivot.transform == Transform3D.IDENTITY, "reduce motion clears offset")
	for peer in [2, 3, 4]: room.world.teleport(peer, Vector3(3 + peer, 1, 12))
	room.world.teleport(2, Vector3(12, 1, 13))
	var shot := room.combat.request_fire(1, 1, 3000)
	check(shot.accepted and room.combat.health[2] == 66, "zero default spread hits official target for 34")
	check(room.combat.request_fire(1, 1, 3400).reason == "replay" and room.combat.health[2] == 66, "replayed shot cannot damage")
	check(room.combat.request_reload(1, 1, 3500).accepted, "reload starts")
	room.combat.tick(4700)
	check(room.combat.private_state(1).magazine == 6 and not room.combat.private_state(1).reloading, "reload timer completes")
	check(room.combat.request_fire(1, 2, 5000).accepted, "second shot")
	arena.set_presentation_motion(true)
	arena._process(0.1)
	check(arena.motion_pivot.transform != Transform3D.IDENTITY, "live presentation active before lethal event")
	check(room.combat.request_fire(1, 3, 5400).accepted, "lethal shot")
	check(room.combat.health[2] == 0 and not room.round_authority.is_alive(2), "damage drives authoritative death")
	# Exercise local death reset with its own authoritative DTO, never another peer's.
	room.combat._apply_damage(1, 3, 100, 5500)
	check(room.combat.health[1] == 0, "local presentation receives actual authoritative death")
	arena.apply_combat_state(room.combat.private_state(1))
	arena.set_player_alive(1, false)
	check(arena.motion_pivot.transform == Transform3D.IDENTITY, "death clears presentation")
	# A stale queued fire must not cross the very same peer's control epoch.
	prediction.queue_action({"kind": "fire", "id": 99})
	prediction.add_look(0.1, 0.1, 123)
	room.world.reset_to_spawn(1)
	prediction.reconcile(room.world.ack_for(1), room.world.states[1])
	var fresh := prediction.build_command(Vector2.ZERO)
	check(fresh.action.is_empty() and fresh.yaw_delta == 0 and fresh.pitch_delta == 0, "epoch discards queued action and look")
	check(prediction.pending.size() == 1, "only new epoch command remains")
	for state in room.world.snapshot():
		check(state.keys() == ["peer_id", "position", "velocity", "yaw", "pitch", "spawn_index", "epoch"], "public world exact allowlist")
	for pickup in room.combat.public_pickups():
		check(not pickup.has("weapon_id") and not pickup.has("magazine") and not pickup.has("role"), "pickup public privacy")
	for peer in room.lobby.peer_ids():
		if room.round_authority.get_role_for_peer(peer) == Role.ASSASSIN and room.round_authority.is_alive(peer):
			room.round_authority.eliminate_player(peer, "shot", 1, 6000)
	check(room.round_authority.state == RoundState.ENDED, "victory ends round")
	check(not room.round_authority.final_reveal.is_empty(), "reveal only after result")
	check(room.combat.request_fire(1, 4, 6100).reason == "round_not_active", "post-result actions rejected")
	room.round_authority.tick(7000)
	check(room.round_authority.state == RoundState.WAITING and room.round_authority.ready_count() == 0, "result timer returns ready-gated lobby")
	check(room.lobby.peer_ids() == [1, 2, 3, 4] and other.lobby.peer_ids() == [99], "same peers retained and other room untouched")
	check(other.world.snapshot() == other_before and other.world.ack_for(99) == other_ack and other.world.telemetry_snapshot().queued == 0, "other occupied room state ACK and telemetry unchanged")
	print("GAMEPLAY_INTEGRATION_METRICS seed=8 profile=local commands=12 telemetry=" + str(room.world.telemetry_snapshot()))
	await get_tree().create_timer(0.6).timeout
	arena.free()
	room.clear()
	other.clear()
	if failures == 0: print("GAMEPLAY_INTEGRATION_SCENE_OK checks=%d" % checks)
	get_tree().quit(0 if failures == 0 else 1)
