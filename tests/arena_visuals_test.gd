extends SceneTree

## Modelos visuais da arena seguem só o estado oficial: pickups nas posições
## oficiais e visíveis só quando disponíveis, arma na mão só com arma no
## inventário privado, e nenhum modelo com colisão, papel ou efeito na mira.

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
	_test_pickups_sit_on_official_positions()
	_test_pickups_follow_official_availability()
	_test_weapon_in_hand_follows_official_inventory()
	_test_models_are_visual_only()
	_test_character_does_not_reveal_roles()
	if failures > 0:
		push_error("ARENA_VISUALS_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return true
	print("ARENA_VISUALS_TEST_OK checks=%d" % checks)
	quit(0)
	return true

func _pickups(unavailable: Array = []) -> Array:
	var result: Array = []
	for index in ArenaRules.PICKUP_POSITIONS.size():
		var pickup_id := "p%d" % index
		result.append({"pickup_id": pickup_id, "type": "weapon" if index < 4 else "ammo",
			"position": ArenaRules.PICKUP_POSITIONS[index], "available": not unavailable.has(pickup_id), "round_id": 1})
	return result

func _test_pickups_sit_on_official_positions() -> void:
	_arena.apply_pickups(_pickups())
	for _i in 20: _arena._process(0.1)
	for index in ArenaRules.PICKUP_POSITIONS.size():
		var node: Node3D = _arena.pickup_nodes["p%d" % index]
		_expect(node.position.is_equal_approx(ArenaRules.PICKUP_POSITIONS[index]), "pickup p%d stays on its official position while spinning" % index)
		var expected_part := "Pistol" if index < 4 else "Crate"
		_expect(node.find_child(expected_part, true, false) != null, "pickup p%d shows a %s" % [index, expected_part])
	var weapon_parts := (_arena.pickup_nodes["p0"] as Node).find_children("*", "MeshInstance3D", true, false).size()
	var ammo_parts := (_arena.pickup_nodes["p4"] as Node).find_children("*", "MeshInstance3D", true, false).size()
	_expect(weapon_parts > 2 and ammo_parts > 2 and weapon_parts != ammo_parts, "weapon and ammo pickups are distinct shapes")

func _test_pickups_follow_official_availability() -> void:
	_arena.apply_pickups(_pickups(["p0", "p5"]))
	_expect(not (_arena.pickup_nodes["p0"] as Node3D).visible and not (_arena.pickup_nodes["p5"] as Node3D).visible, "collected weapon and ammo disappear")
	_expect((_arena.pickup_nodes["p1"] as Node3D).visible and (_arena.pickup_nodes["p4"] as Node3D).visible, "other pickups stay visible")
	_arena.apply_snapshot([_state(LOCAL, ArenaRules.PICKUP_POSITIONS[0] + Vector3(0.5, 0.75, 0.0), 0.0)])
	_expect(_arena.nearest_available_pickup() != "p0", "an unavailable pickup is never offered for E")
	_arena.apply_pickups(_pickups())
	_expect((_arena.pickup_nodes["p0"] as Node3D).visible and (_arena.pickup_nodes["p5"] as Node3D).visible, "a new round shows the pickups again")
	_expect(_arena.nearest_available_pickup() == "p0", "the nearest official position is still what E requests")
	_arena.apply_pickups([])
	_expect(_arena.pickup_nodes.is_empty(), "pickups removed by the server leave no node")

func _test_weapon_in_hand_follows_official_inventory() -> void:
	_arena.set_spectator_target(0, false)
	_arena.set_gameplay_visuals(true)
	_arena.apply_combat_state({})
	_expect(not _arena.weapon_model.visible, "no official weapon, nothing in hand")
	_arena.apply_pickups(_pickups(["p0"]))
	_expect(not _arena.weapon_model.visible, "a pickup vanishing (public) does not put a weapon in hand")
	_arena.apply_combat_state(_combat("common_pistol", 100))
	_expect(_arena.weapon_model.visible, "official weapon in the private inventory shows the pistol")
	_expect(_arena.weapon_model.find_children("*", "MeshInstance3D", true, false).size() >= 4, "the held weapon is a pistol model, not a box")
	_arena.apply_snapshot([_state(LOCAL, Vector3(0, 1, 0), 1.1)])
	_expect(_arena.camera_direction().distance_to(Vector3.FORWARD.rotated(Vector3.UP, 1.1)) < 0.001, "the pistol model does not change the aim")
	_arena.apply_combat_state(_combat("common_pistol", 0))
	_expect(not _arena.weapon_model.visible, "a dead player holds nothing")
	_arena.apply_combat_state(_combat("common_pistol", 100))
	_arena.set_spectator_target(REMOTE)
	_expect(not _arena.weapon_model.visible, "spectators hold nothing")
	_arena.set_spectator_target(0, false)
	_arena.set_gameplay_visuals(true)
	_arena.apply_combat_state(_combat("", 100))
	_expect(not _arena.weapon_model.visible, "dropping the weapon officially empties the hand")

func _test_models_are_visual_only() -> void:
	_arena.apply_pickups(_pickups())
	_arena.apply_snapshot([_state(LOCAL, Vector3(0, 1, 0), 0.0), _state(REMOTE, Vector3(3, 1, 3), 0.5)])
	var nodes: Array = [_arena.weapon_model, _arena.avatars[REMOTE]]
	nodes.append_array(_arena.pickup_nodes.values())
	for node in nodes:
		_expect(_collision_nodes(node) == 0, "%s has no collision" % (node as Node).name)
	# Personagem: pés no chão e 2 m de altura, como a cápsula oficial anterior.
	var avatar: Node3D = _arena.avatars[REMOTE]
	var bounds := _bounds(avatar)
	_expect(absf(bounds.position.y - (avatar.global_position.y - 1.0)) < 0.05, "character feet touch the floor (bottom %.2f)" % bounds.position.y)
	_expect(bounds.size.x < 1.0 and bounds.size.z < 1.0, "character stays inside a 1 m footprint")

func _test_character_does_not_reveal_roles() -> void:
	# O modelo só recebe o peer_id (acento de cor por pessoa); papéis nunca
	# chegam aqui. Dois jogadores têm a mesma silhueta peça por peça.
	var first := ArenaModels.build_character(REMOTE)
	var second := ArenaModels.build_character(OTHER)
	var names_first := first.get_children().map(func(node): return node.name)
	var names_second := second.get_children().map(func(node): return node.name)
	_expect(names_first == names_second, "every player uses the same silhouette")
	first.free()
	second.free()

func _combat(weapon_id: String, health: int) -> Dictionary:
	return {"round_id": 1, "health": health, "weapon_id": weapon_id, "magazine": 6, "reserve": 0, "reloading": false}

func _state(peer_id: int, position: Vector3, yaw: float) -> Dictionary:
	return {"peer_id": peer_id, "position": position, "yaw": yaw, "velocity": Vector3.ZERO, "spawn_index": 0}

func _bounds(root_node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var box := mesh_node.global_transform * mesh_node.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

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
	push_error("ARENA_VISUALS_CHECK_FAILED %s" % description)
