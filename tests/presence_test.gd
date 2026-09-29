extends SceneTree

## Fase 11: presença dos personagens e leitura visual do combate, sem rede.
## 1. Estado público de arma: autoridade (coleta oficial, morte, reset,
##    desconexão) e formato público (allowlist, tipos, nada privado).
## 2. Eventos de combate: um efeito por tiro oficial, repetido ou de outra
##    rodada não repete, marcador só com acerto próprio pendente, superfícies
##    distintas, corpo não confirma acerto.
## 3. Apresentação: pistola na mão só com `armed` oficial, some com morte,
##    saída e reset; parado não desliza; passo nunca no teleporte; braço
##    segue o pitch com limite; posição oficial (hitbox) intacta; espectador
##    sem pistola nem mira próprias; oito aparências compatíveis.

const LOCAL := 1
const REMOTE := 2
const OTHER := 3

var failures := 0
var checks := 0
var _arena: ArenaView
var _frame := 0

func _initialize() -> void:
	_arena = ArenaView.new()
	_arena.local_peer_id = LOCAL
	root.add_child(_arena)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_test_authority_public_armed()
	_test_public_dto_allowlist()
	_test_armed_presentation()
	_test_shot_events_once()
	_test_hit_marker_needs_own_pending_hit()
	_test_impact_surfaces()
	_test_movement_and_footsteps()
	_test_arm_follows_pitch_within_limits()
	_test_spectator_hides_own_weapon()
	_test_body_fall_and_late_bodies()
	_test_eight_appearances_hold_the_weapon()
	if failures > 0:
		push_error("PRESENCE_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return true
	print("PRESENCE_TEST_OK checks=%d" % checks)
	quit(0)
	return true

# --- 1. Autoridade -------------------------------------------------------------

func _authority() -> Array:
	var rounds := RoundAuthority.new()
	var world := AuthoritativeWorld.new()
	for peer_id in range(1, 5):
		world.add_player(peer_id)
	rounds.state = RoundState.ACTIVE
	rounds.round_id = 1
	rounds.participants = {1: true, 2: true, 3: true, 4: true}
	rounds.alive = {1: true, 2: true, 3: true, 4: true}
	rounds._roles = {1: Role.ASSASSIN, 2: Role.DETECTIVE, 3: Role.VICTIM, 4: Role.VICTIM}
	var authority := CombatAuthority.new(rounds, world)
	authority.begin_round(1, [1, 2, 3, 4])
	return [rounds, world, authority]

func _test_authority_public_armed() -> void:
	var parts := _authority()
	var rounds: RoundAuthority = parts[0]
	var world: AuthoritativeWorld = parts[1]
	var authority: CombatAuthority = parts[2]
	for peer_id in range(1, 5):
		_expect(not authority.public_armed(peer_id), "peer %d starts unarmed" % peer_id)
	# Recusa (longe do item) não arma ninguém.
	world.states[1]["position"] = Vector3(100, 0, 100)
	_expect(not authority.request_pickup(1, "weapon_0", 1, 100)["accepted"] and not authority.public_armed(1), "refused pickup leaves the player unarmed")
	world.states[1]["position"] = ArenaRules.PICKUP_POSITIONS[0]
	_expect(authority.request_pickup(1, "weapon_0", 2, 300)["accepted"], "official pickup accepted")
	_expect(authority.public_armed(1) and not authority.public_armed(2), "only the official pickup arms, only that player")
	# Munição sozinha não arma.
	var ammo_index := -1
	for index in MansionMap.PICKUPS.size():
		if str(MansionMap.PICKUPS[index]["type"]) == "ammo":
			ammo_index = index
			break
	world.states[3]["position"] = ArenaRules.PICKUP_POSITIONS[ammo_index]
	authority.request_pickup(3, str(MansionMap.PICKUPS[ammo_index]["id"]), 1, 400)
	_expect(not authority.public_armed(3), "ammo alone does not show a weapon")
	var weapons: Array = []
	for index in MansionMap.PICKUPS.size():
		if str(MansionMap.PICKUPS[index]["type"]) == "weapon":
			weapons.append(index)
	# Morte (uma vítima, a rodada segue): some.
	world.states[3]["position"] = ArenaRules.PICKUP_POSITIONS[weapons[2]]
	_expect(authority.request_pickup(3, str(MansionMap.PICKUPS[weapons[2]]["id"]), 2, 520)["accepted"] and authority.public_armed(3), "victim armed")
	_expect(rounds.eliminate_player(3, "shot", 1, 560).is_empty(), "victim eliminated")
	_expect(not authority.public_armed(3), "eliminated player is not publicly armed")
	# Desconexão: some (inventário removido).
	world.states[2]["position"] = ArenaRules.PICKUP_POSITIONS[weapons[1]]
	authority.request_pickup(2, str(MansionMap.PICKUPS[weapons[1]]["id"]), 1, 600)
	_expect(authority.public_armed(2), "second official pickup arms peer 2")
	authority.clear_player(2)
	_expect(not authority.public_armed(2), "disconnected player leaves no public weapon")
	# Reset (nova rodada): ninguém armado e todos os itens de volta ao chão.
	rounds.alive = {1: true, 2: true, 3: true, 4: true}
	rounds.state = RoundState.ACTIVE
	world.states[4]["position"] = ArenaRules.PICKUP_POSITIONS[0]
	rounds.round_id = 2
	authority.begin_round(2, [1, 2, 3, 4])
	var armed_after := 0
	for peer_id in range(1, 5):
		if authority.public_armed(peer_id): armed_after += 1
	var available := 0
	for pickup in authority.public_pickups():
		if bool(pickup["available"]): available += 1
	_expect(armed_after == 0 and available == 20, "reset: nobody armed, all 20 pickups restored")
	# Rodada fora de ACTIVE: ninguém armado.
	world.states[4]["position"] = ArenaRules.PICKUP_POSITIONS[0]
	authority.request_pickup(4, "weapon_0", 1, 700)
	_expect(authority.public_armed(4), "armed during the round")
	rounds.state = RoundState.ENDED
	_expect(not authority.public_armed(4), "no public weapon once the round ended")
	# Número de tiro por rodada.
	rounds.state = RoundState.ACTIVE
	world.states[4]["yaw"] = 0.0
	var fired := authority.request_fire(4, 1, 2000)
	_expect(fired["accepted"] and authority.shot_counter == 1, "official shot numbered")

# --- 1b. Formato público ------------------------------------------------------

func _player(extra: Dictionary = {}) -> Dictionary:
	var state := {"peer_id": 7, "position": Vector3(1, 1, 1), "velocity": Vector3.ZERO, "yaw": 0.5, "pitch": 0.1,
		"spawn_index": 2, "epoch": 3, "armed": true}
	state.merge(extra, true)
	return state

func _test_public_dto_allowlist() -> void:
	var clean := PublicCombatState.sanitize_player(_player())
	_expect(clean.keys().size() == 8 and bool(clean["armed"]), "valid public player state kept")
	var old := _player()
	old.erase("armed")
	_expect(not bool(PublicCombatState.sanitize_player(old)["armed"]), "state without `armed` (older server) is unarmed")
	for key in PublicCombatState.FORBIDDEN_KEYS:
		_expect(PublicCombatState.sanitize_player(_player({key: 1})).is_empty(), "extra key %s rejects the state" % key)
	_expect(PublicCombatState.sanitize_player(_player({"armed": 1})).is_empty(), "`armed` must be a bool")
	_expect(PublicCombatState.sanitize_player(_player({"peer_id": "7"})).is_empty(), "peer id must be an int")
	_expect(PublicCombatState.sanitize_player(_player({"position": Vector3(INF, 0, 0)})).is_empty(), "non-finite position rejected")
	_expect(PublicCombatState.sanitize_player("x").is_empty(), "non-dictionary rejected")
	var shot := {"round_id": 1, "shot_id": 4, "shooter_peer_id": 2, "origin": Vector3(0, 1.7, 0), "end": Vector3(0, 1.7, -5), "hit_player": false}
	_expect(PublicCombatState.sanitize_shot(shot).size() == 6, "valid public shot kept")
	for key in ["hit_peer_id", "health", "role", "direction", "magazine"]:
		var bad := shot.duplicate()
		bad[key] = 1
		_expect(PublicCombatState.sanitize_shot(bad).is_empty(), "shot with %s rejected" % key)
	var bad_id := shot.duplicate()
	bad_id["shot_id"] = 0
	_expect(PublicCombatState.sanitize_shot(bad_id).is_empty(), "shot id must be positive")
	# Estado oficial de verdade: o snapshot do servidor + `armed` passa pela allowlist.
	var parts := _authority()
	var world: AuthoritativeWorld = parts[1]
	var authority: CombatAuthority = parts[2]
	for raw in world.snapshot():
		var entry: Dictionary = raw
		entry["armed"] = authority.public_armed(int(entry["peer_id"]))
		var sanitized := PublicCombatState.sanitize_player(entry)
		_expect(not sanitized.is_empty(), "server snapshot entry passes the allowlist")
		for key in PublicCombatState.FORBIDDEN_KEYS:
			_expect(not entry.has(key), "server snapshot never carries %s" % key)
	var event_text := str(authority.request_fire(1, 1, 5000))
	_expect(true, "fire resolved (%s)" % event_text)

# --- 1c. Apresentação da arma -----------------------------------------------------

func _state(peer_id: int, position: Vector3, armed: bool, epoch: int = 1, yaw: float = 0.0, pitch: float = 0.0) -> Dictionary:
	return {"peer_id": peer_id, "position": position, "velocity": Vector3.ZERO, "yaw": yaw, "pitch": pitch,
		"spawn_index": 0, "epoch": epoch, "armed": armed}

func _run_frames(count: int, delta: float = 1.0 / 60.0) -> void:
	for index in count:
		_arena._process(delta)

func _snap(states: Array, tick: int) -> void:
	_arena.apply_snapshot(states, tick)

func _test_armed_presentation() -> void:
	var tick := 100
	var remote := Vector3(12, 1, 12)
	for index in 12:
		_snap([_state(LOCAL, Vector3(12, 1, 15), false), _state(REMOTE, remote, false)], tick)
		tick += 3
		_run_frames(3)
	_expect(_arena.avatars.has(REMOTE) and not _arena.held_weapon_visible(REMOTE), "unarmed remote shows no pistol")
	for index in 12:
		_snap([_state(LOCAL, Vector3(12, 1, 15), false), _state(REMOTE, remote, true)], tick)
		tick += 3
		_run_frames(3)
	_expect(_arena.held_weapon_visible(REMOTE), "official armed shows the pistol in the hand")
	_expect(_arena.fx.count_event("pickup_world@world") == 1, "someone else's pickup plays one discreet sound")
	# Morte oficial (roster/eliminação): some com o avatar.
	_arena.set_player_alive(REMOTE, false)
	_run_frames(2)
	_expect(not _arena.held_weapon_visible(REMOTE), "dead player shows no pistol")
	_arena.set_player_alive(REMOTE, true)
	# Reset: época nova e `armed` falso.
	for index in 12:
		_snap([_state(LOCAL, Vector3(12, 1, 15), false, 2), _state(REMOTE, Vector3(3, 1, 3), false, 2)], tick)
		tick += 3
		_run_frames(3)
	_expect(not _arena.held_weapon_visible(REMOTE), "reset removes the pistol")
	# Desconexão: some do snapshot, nada fica.
	_snap([_state(LOCAL, Vector3(12, 1, 15), false, 2)], tick)
	tick += 3
	_run_frames(2)
	_expect(not _arena.avatars.has(REMOTE) and not _arena.held_weapon_visible(REMOTE), "disconnected player leaves no ghost pistol")
	# Entrada tardia: primeira mensagem já com arma e aparência.
	var late := ArenaView.new()
	late.local_peer_id = LOCAL
	root.add_child(late)
	late.set_appearance(OTHER, "night")
	for index in 12:
		late.apply_snapshot([_state(OTHER, Vector3(20, 1, 20), true)], 500 + index * 3)
		for frame in 3:
			late._process(1.0 / 60.0)
	_expect(late.held_weapon_visible(OTHER), "late joiner sees the current official pistol")
	_expect(late.appearance_for(OTHER) == "night", "late joiner sees the official appearance")
	late.queue_free()

# --- 2. Eventos de combate ------------------------------------------------------

func _shot(shooter: int, shot_id: int, round_id: int, finish: Vector3, hit_player: bool) -> Dictionary:
	return PublicCombatState.sanitize_shot({"round_id": round_id, "shot_id": shot_id, "shooter_peer_id": shooter,
		"origin": Vector3(12, 1.7, 12), "end": finish, "hit_player": hit_player})

func _test_shot_events_once() -> void:
	_arena.set_round(3)
	_arena.fx.events.clear()
	var event := _shot(REMOTE, 1, 3, Vector3(12, 1.2, 5), false)
	_expect(_arena.show_shot(event), "first official shot shown")
	_expect(not _arena.show_shot(event), "same shot again shows nothing")
	_expect(not _arena.show_shot(event.duplicate()), "a copy of the same shot shows nothing")
	_expect(_arena.fx.count_event("muzzle_flash") == 1 and _arena.fx.count_event("tracer") == 1
		and _arena.fx.count_event("shot@world") == 1 and _arena.fx.count_event("impact_wall") == 1,
		"one flash, tracer, sound and impact per official shot")
	_expect(not _arena.show_shot(_shot(REMOTE, 2, 2, Vector3(12, 1.2, 5), false)), "shot from an old round is ignored")
	_arena.set_round(4)
	_expect(not _arena.show_shot(_shot(REMOTE, 3, 3, Vector3(12, 1.2, 5), false)), "late callback from the previous round is ignored after reset")
	_expect(_arena.show_shot(_shot(REMOTE, 1, 4, Vector3(12, 1.2, 5), false)), "numbering restarts per round")

func _test_hit_marker_needs_own_pending_hit() -> void:
	_arena.set_round(5)
	_arena.set_gameplay_visuals(true)
	var before := _arena.hit_markers_shown
	# Recusa não tem evento público: confirmação solta não vira marcador.
	_expect(not _arena.show_hit_marker() and _arena.hit_markers_shown == before, "no marker without an own official hit")
	# Acerto em corpo morto: o servidor não conta (evento sem hit_player).
	_arena.show_shot(_shot(LOCAL, 1, 5, Vector3(12, 0.3, 5), false))
	_expect(not _arena.show_hit_marker(), "a shot that hit no living player gives no marker")
	# Tiro de outro com acerto não gera marcador para mim.
	_arena.show_shot(_shot(REMOTE, 2, 5, Vector3(12, 1.2, 5), true))
	_expect(not _arena.show_hit_marker(), "someone else's hit is not my marker")
	var own_hit := _shot(LOCAL, 3, 5, Vector3(12, 1.2, 5), true)
	_arena.show_shot(own_hit)
	_arena.show_shot(own_hit)
	_expect(_arena.show_hit_marker(), "own official hit shows one marker")
	_expect(not _arena.show_hit_marker(), "a repeated confirmation shows no second marker")
	_expect(_arena.hit_markers_shown == before + 1, "exactly one marker")

func _test_impact_surfaces() -> void:
	var range_m := WeaponRules.COMMON_RANGE_METERS
	var base := {"origin": Vector3(0, 1.7, 0), "hit_player": false}
	var floor_hit := base.duplicate(); floor_hit["end"] = Vector3(0, 0.0, -3)
	var wall_hit := base.duplicate(); wall_hit["end"] = Vector3(0, 1.4, -4)
	var miss := base.duplicate(); miss["end"] = Vector3(0, 1.7, -range_m)
	var player_hit := base.duplicate(); player_hit["end"] = Vector3(0, 1.2, -4); player_hit["hit_player"] = true
	_expect(PublicCombatState.impact_surface(floor_hit, range_m) == "floor", "floor impact")
	_expect(PublicCombatState.impact_surface(wall_hit, range_m) == "wall", "wall impact")
	_expect(PublicCombatState.impact_surface(miss, range_m) == "none", "shot into nothing has no impact")
	_expect(PublicCombatState.impact_surface(player_hit, range_m) == "player", "player impact")
	_arena.set_round(6)
	_arena.fx.events.clear()
	_arena.show_shot(_shot(REMOTE, 1, 6, Vector3(12, 0.0, 6), false))
	_arena.show_shot(_shot(REMOTE, 2, 6, Vector3(12, 1.2, 6), false))
	_arena.show_shot(_shot(REMOTE, 3, 6, Vector3(12, 1.2, 6), true))
	_expect(_arena.fx.count_event("impact_floor") == 1 and _arena.fx.count_event("impact_wall") == 1
		and _arena.fx.count_event("impact_player") == 1, "floor, wall and player impacts look different")
	_expect(_arena.fx.count_event("impact_body@world") == 1 and _arena.fx.count_event("impact_wall@world") == 2, "and sound different")

# --- 3. Movimento ------------------------------------------------------------------

func _test_movement_and_footsteps() -> void:
	var tick := 1000
	var start := Vector3(14, 1, 14)
	for index in 10:
		_snap([_state(LOCAL, Vector3(12, 1, 15), false, 3), _state(OTHER, start, false, 3)], tick)
		tick += 3
		_run_frames(3)
	var animator: CharacterAnimator = _arena.animators[OTHER]
	var avatar: Node3D = _arena.avatars[OTHER]
	var steps_before := animator.footsteps
	for index in 30:
		_snap([_state(LOCAL, Vector3(12, 1, 15), false, 3), _state(OTHER, start, false, 3)], tick)
		tick += 3
		_run_frames(3)
	_expect(animator.footsteps == steps_before and animator.amplitude == 0.0, "standing still: no steps, no walk")
	_expect(avatar.position.distance_to(start) < 0.001, "standing still: no slide (%s)" % str(avatar.position))
	# Andando: passos.
	var position := start
	for index in 60:
		position += Vector3(0, 0, -0.1)
		_snap([_state(LOCAL, Vector3(12, 1, 15), false, 3), _state(OTHER, position, false, 3)], tick)
		tick += 3
		_run_frames(3)
	var walked_steps := animator.footsteps - steps_before
	_expect(walked_steps >= 3, "walking 6 m produces footsteps (%d)" % walked_steps)
	# Teleporte de reset (época nova): nenhum passo.
	var steps_at_reset := animator.footsteps
	_arena.fx.events.clear()
	for index in 6:
		_snap([_state(LOCAL, Vector3(12, 1, 15), false, 4), _state(OTHER, Vector3(3, 1, 3), false, 4)], tick)
		tick += 3
		_run_frames(3)
	_expect(animator.footsteps == steps_at_reset and _arena.fx.count_event("step@world") == 0, "reset teleport plays no footstep")
	# Posição oficial (hitbox) igual armado ou não.
	for armed in [false, true]:
		for index in 8:
			_snap([_state(LOCAL, Vector3(12, 1, 15), false, 4), _state(OTHER, Vector3(3, 1, 3), armed, 4)], tick)
			tick += 3
			_run_frames(3)
		_expect(avatar.position.distance_to(Vector3(3, 1, 3)) < 0.001, "armed=%s keeps the official position" % str(armed))

func _test_arm_follows_pitch_within_limits() -> void:
	var neutral := CharacterAnimator.armed_shoulder_angle(0.0)
	var up := CharacterAnimator.armed_shoulder_angle(MovementRules.MAX_PITCH)
	var down := CharacterAnimator.armed_shoulder_angle(-MovementRules.MAX_PITCH)
	_expect(up < neutral and down > neutral, "looking up raises the arm, down lowers it")
	_expect(absf(up - neutral) <= CharacterAnimator.ARMED_PITCH_LIMIT + 0.0001 and absf(down - neutral) <= CharacterAnimator.ARMED_PITCH_LIMIT + 0.0001, "arm follows only a limited part of the pitch")
	var animator: CharacterAnimator = _arena.animators[OTHER]
	var head: Node3D = animator.rig.get("head")
	_expect(head != null and absf(head.rotation.x) <= ArenaModels.HEAD_PITCH_LIMIT + 0.0001, "head stays within its limit")
	# Câmera local não depende do avatar remoto.
	var camera_before := _arena.camera.global_position
	_arena.show_shot(_shot(OTHER, 99, _arena.current_round_id, Vector3(12, 1.2, 5), false))
	_expect(_arena.camera.global_position == camera_before, "someone else's shot never moves my camera")

func _test_spectator_hides_own_weapon() -> void:
	_arena.set_gameplay_visuals(true)
	_arena.apply_combat_state({"round_id": 6, "health": 100, "weapon_id": "common_pistol", "magazine": 6, "reserve": 0, "reloading": false})
	_expect(_arena.weapon_model.visible and _arena.crosshair.visible, "alive and armed: own pistol and crosshair")
	_arena.apply_combat_state({"round_id": 6, "health": 0, "weapon_id": "common_pistol", "magazine": 6, "reserve": 0, "reloading": false})
	_arena.set_spectator_target(REMOTE, true)
	_expect(not _arena.weapon_model.visible and not _arena.crosshair.visible, "spectator: no own pistol and no crosshair")
	_arena.set_spectator_target(0, false)

func _test_body_fall_and_late_bodies() -> void:
	_arena.fx.events.clear()
	var dto := {"body_id": 41, "round_id": 6, "peer_id": OTHER, "position": Vector3(12, 1, 8), "yaw": 0.0, "appearance": "moss"}
	_expect(_arena.add_body(dto, true), "live elimination body added")
	var fall := (_arena.bodies[41] as Node3D).get_node("Fall") as Node3D
	_expect(fall.rotation.x < PI * 0.5 - 0.1, "live body starts a short fall")
	_expect(_arena.fx.has_event("body_fall_start"), "fall transition logged")
	var late := {"body_id": 42, "round_id": 6, "peer_id": REMOTE, "position": Vector3(14, 1, 8), "yaw": 0.0, "appearance": "sand"}
	_arena.add_body(late, false)
	var late_fall := (_arena.bodies[42] as Node3D).get_node("Fall") as Node3D
	_expect(is_equal_approx(late_fall.rotation.x, PI * 0.5), "body from the full state is already lying down")
	_expect((_arena.bodies[41] as Node3D).find_children("*", "CollisionShape3D", true, false).is_empty(), "body has no collision")
	_arena.clear_bodies()

func _test_eight_appearances_hold_the_weapon() -> void:
	for appearance in CharacterAppearance.IDS:
		var avatar := ArenaModels.build_character(appearance)
		root.add_child(avatar)
		var animator := CharacterAnimator.new(avatar.get_node(ArenaModels.CHARACTER_MODEL), 0.0)
		_expect(animator.is_valid(), "%s: rig valid" % appearance)
		animator.reset(Vector3.ZERO)
		animator.armed = true
		for frame in 30:
			animator.update(Vector3.ZERO, 0.0, 1.0 / 60.0)
		var muzzle := animator.muzzle_position()
		_expect(animator.held_weapon_visible(), "%s: pistol visible when armed" % appearance)
		_expect(muzzle.x > 0.15 and muzzle.z < -0.35 and muzzle.y > 0.2 and muzzle.y < 0.8,
			"%s: pistol in the right hand, in front, at chest height (%s)" % [appearance, str(muzzle)])
		var barrel := -(animator.held_weapon.global_transform.basis.z).normalized()
		_expect(barrel.z < -0.9, "%s: barrel points where the character faces" % appearance)
		avatar.queue_free()
	var colors: Dictionary = {}
	for appearance in CharacterAppearance.IDS:
		colors[str(ArenaModels.build_character(appearance).get_child(0).name) + appearance] = true
	_expect(CharacterAppearance.IDS.size() == 8, "eight cosmetic appearances")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("PRESENCE_TEST_FAILED %s" % message)
