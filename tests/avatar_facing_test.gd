extends SceneTree

## Regressão: o avatar remoto precisa mostrar para onde está virado usando o yaw
## oficial do snapshot, com ou sem arma. A cápsula é simétrica em Y, então girar
## o nó sozinho não aparece. O teste mede a frente visível no mundo, não só
## `rotation.y`. Também confere que a mira local continua na direção oficial e
## que a frente visual não tem colisão nem influência no disparo.

const LOCAL := 1
const REMOTE := 2
const OTHER := 3
const YAWS := [0.0, PI * 0.5, -2.0, 3.0, -PI * 0.25]

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
	_test_unarmed_remote_body_turns()
	_test_armed_and_unarmed_look_the_same()
	_test_local_aim_follows_the_official_yaw()
	_test_facing_is_visual_only()
	_test_spectated_target_hides_its_visor()
	if failures > 0:
		push_error("AVATAR_FACING_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return true
	print("AVATAR_FACING_TEST_OK checks=%d" % checks)
	quit(0)
	return true

func _test_unarmed_remote_body_turns() -> void:
	_arena.apply_combat_state({})
	var seen: Array = []
	for yaw in YAWS:
		var facing := _remote_facing(yaw)
		var expected := _official_forward(yaw)
		_expect(facing.distance_to(expected) < 0.02, "unarmed remote body faces official yaw %.2f (visible %s, expected %s)" % [yaw, str(facing), str(expected)])
		seen.append(facing)
	# Um corpo "olhando fixo" produziria a mesma frente para todo yaw.
	_expect((seen[0] as Vector3).distance_to(seen[1]) > 1.0 and (seen[0] as Vector3).distance_to(seen[3]) > 1.0, "different official yaws give visibly different fronts")

func _test_armed_and_unarmed_look_the_same() -> void:
	for yaw in YAWS:
		_arena.apply_combat_state({})
		var unarmed := _remote_facing(yaw)
		_arena.apply_combat_state({"round_id": 1, "health": 100, "weapon_id": "common_pistol", "magazine": 6, "reserve": 0, "reloading": false})
		var armed := _remote_facing(yaw)
		_expect(unarmed.distance_to(armed) < 0.001, "weapon state does not change the remote front at yaw %.2f" % yaw)

func _test_local_aim_follows_the_official_yaw() -> void:
	for armed in [false, true]:
		_arena.apply_combat_state({"round_id": 1, "health": 100, "weapon_id": "common_pistol" if armed else "", "magazine": 6, "reserve": 0, "reloading": false})
		for yaw in YAWS:
			_arena.apply_snapshot([_state(LOCAL, Vector3(0, 1, 0), yaw), _state(REMOTE, Vector3(3, 1, 3), 0.0)])
			var aim := _arena.camera_direction()
			_expect(aim.distance_to(_official_forward(yaw)) < 0.001, "local aim follows official yaw %.2f (armed=%s)" % [yaw, str(armed)])

func _test_facing_is_visual_only() -> void:
	_remote_facing(1.0)
	var avatar: Node3D = _arena.avatars[REMOTE]
	_expect(_visible_front(avatar) != Vector3.ZERO, "remote avatar has a visible front")
	_expect(_collision_nodes(avatar) == 0, "remote avatar and its front have no collision")
	# Girar outro corpo não mexe na mira local.
	_arena.apply_snapshot([_state(LOCAL, Vector3(0, 1, 0), 0.3), _state(REMOTE, Vector3(3, 1, 3), -2.5)])
	for _i in 30: _arena._process(0.1)
	_expect(_arena.camera_direction().distance_to(_official_forward(0.3)) < 0.001, "remote body rotation never changes the local aim")

func _test_spectated_target_hides_its_visor() -> void:
	_arena.apply_snapshot([_state(LOCAL, Vector3(0, 1, 0), 0.0), _state(REMOTE, Vector3(3, 1, 3), 0.5), _state(OTHER, Vector3(-3, 1, 3), 1.0)])
	_arena.set_spectator_target(REMOTE)
	_arena._process(0.1)
	_expect(_visor(REMOTE) != null and not _visor(REMOTE).visible, "first-person spectator does not see the target's own visor")
	_expect(_visor(OTHER) != null and _visor(OTHER).visible, "other players keep their visible front while spectating")
	_arena.set_spectator_target(0, false)
	_arena._process(0.1)
	_expect(_visor(REMOTE) != null and _visor(REMOTE).visible, "visor returns after spectating ends")

## Frente horizontal visível do avatar remoto depois de estabilizar no yaw oficial.
func _remote_facing(yaw: float) -> Vector3:
	_arena.apply_snapshot([_state(LOCAL, Vector3(0, 1, 0), 0.0), _state(REMOTE, Vector3(4, 1, -2), yaw)])
	for _i in 30: _arena._process(0.1)
	return _visible_front(_arena.avatars[REMOTE])

## Direção horizontal da geometria que se afasta do eixo do corpo. Só a cápsula
## (simétrica) não tem frente: devolve zero e as checagens falham.
func _visible_front(avatar: Node3D) -> Vector3:
	var best := Vector3.ZERO
	for node in avatar.find_children("*", "MeshInstance3D", true, false):
		var offset: Vector3 = (node as Node3D).global_position - avatar.global_position
		offset.y = 0.0
		if offset.length() > best.length():
			best = offset
	return best.normalized() if best.length() > 0.1 else Vector3.ZERO

func _visor(peer_id: int) -> Node3D:
	var avatar: Node3D = _arena.avatars.get(peer_id)
	return avatar.get_node_or_null("FacingVisor") as Node3D if avatar != null else null

func _official_forward(yaw: float) -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, yaw)

func _state(peer_id: int, position: Vector3, yaw: float) -> Dictionary:
	return {"peer_id": peer_id, "position": position, "yaw": yaw, "velocity": Vector3.ZERO, "spawn_index": 0}

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
	push_error("AVATAR_FACING_CHECK_FAILED %s" % description)
