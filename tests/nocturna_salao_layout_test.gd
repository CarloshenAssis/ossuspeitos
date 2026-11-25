extends SceneTree

const GRID := 0.25
const PICKUP_GAP := 4.5

var salao_map: GDScript
var arena_rules: GDScript
var movement_rules: GDScript

var checks := 0
var failures := 0

static func _static_init() -> void:
	OS.set_environment("OSSUSPEITOS_MAP", "nocturna_salao")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Load the map consumers after the test script has selected the variant.
	salao_map = load("res://shared/nocturna_salao_map.gd")
	arena_rules = load("res://shared/arena_rules.gd")
	movement_rules = load("res://shared/movement_rules.gd")
	_expect(salao_map.enabled and arena_rules.BLOCKERS == salao_map.blockers(), "active map uses variant geometry")
	_expect(movement_rules.SPAWN_POINTS == salao_map.spawn_points(), "active spawns")
	_expect(arena_rules.PICKUP_POSITIONS == salao_map.pickup_positions(), "active pickups")

	var entries: Array = salao_map.SPACES + salao_map.DOORS
	for index in entries.size():
		var area: Rect2 = salao_map.rect(entries[index])
		for other in range(index + 1, entries.size()):
			_expect(not area.intersects(salao_map.rect(entries[other])), "non-overlapping spaces and doors")
	for door in salao_map.DOORS:
		var area: Rect2 = salao_map.rect(door)
		_expect(minf(area.size.x, area.size.y) == 0.5 and maxf(area.size.x, area.size.y) == 2.0, "door dimensions")
		var center: Vector2 = area.get_center()
		var lintel: float = arena_rules.first_blocker_distance(Vector3(center.x, 1.0, center.y), Vector3.UP, 10.0)
		_expect(is_equal_approx(lintel, MansionMap.DOOR_HEIGHT - 1.0), "door lintel height")

	var free := {}
	for x in range(int(salao_map.MIN_X / GRID), int(26.5 / GRID) + 1):
		for z in range(int(22.5 / GRID) + 1):
			var cell := Vector2i(x, z)
			var point := Vector2(cell) * GRID
			if not salao_map.space_at(point).is_empty() and not arena_rules.overlaps_blocker(_body(point)):
				free[cell] = true
	_check_floor(free)
	_check_items(free)
	_check_walls()
	_check_dining_room()
	_check_guest_room()

	if failures == 0:
		print("NOCTURNA_SALAO_LAYOUT_TEST_OK checks=%d blockers=%d spawns=%d pickups=%d" % [
			checks, arena_rules.BLOCKERS.size(), movement_rules.SPAWN_POINTS.size(), arena_rules.PICKUP_POSITIONS.size()])
	quit(0 if failures == 0 else 1)

func _check_floor(free: Dictionary) -> void:
	var start := Vector2i(_room("salao").get_center() / GRID)
	var queue: Array[Vector2i] = [start]
	var visited := {start: true}
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		var from := _body(Vector2(cell) * GRID)
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			var point := Vector2(next) * GRID
			var target := _body(point)
			var resolved: Vector3 = movement_rules.resolve_step(from, target - from)["position"]
			if salao_map.space_at(point).is_empty():
				_expect(not resolved.is_equal_approx(target), "capsule stays within sealed floor")
			if free.has(next) and not visited.has(next) and resolved.is_equal_approx(target):
				visited[next] = true
				queue.append(next)
	_expect(free.has(start) and visited.size() == free.size(), "all capsule-clear floor is connected")
	for door in salao_map.DOORS:
		var center: Vector2 = salao_map.rect(door).get_center()
		_expect(visited.has(Vector2i(center / GRID)), "door center is reachable")
	for entry in salao_map.SPACES:
		var center: Vector2 = salao_map.rect(entry).get_center()
		_expect(visited.has(Vector2i(center / GRID)), "space center is reachable")

func _room(id: String) -> Rect2:
	for entry in salao_map.SPACES:
		if entry["id"] == id:
			return salao_map.rect(entry)
	return Rect2()

func _check_items(free: Dictionary) -> void:
	var rooms: Array[Rect2] = []
	for id in ["salao", "biblioteca", "cozinha", "jantar", "hospedes"]:
		var room := _room(id)
		rooms.append(room)
		for group in [salao_map.SPAWNS, salao_map.WEAPONS, salao_map.AMMO]:
			_expect(group.any(room.has_point), "%s has at least one entry of each item type" % id)
	var pickups: Array = salao_map.WEAPONS + salao_map.AMMO
	_expect(salao_map.SPAWNS.size() == 8 and salao_map.WEAPONS.size() == 8 and salao_map.AMMO.size() == 12, "eight spawns, eight weapons, twelve ammo")
	for index in salao_map.SPAWNS.size():
		var spawn: Vector2 = salao_map.SPAWNS[index]
		_expect(rooms.any(func(room: Rect2) -> bool: return room.has_point(spawn)) and free.has(Vector2i(spawn / GRID)),
			"spawn inside a room with capsule clearance")
		for other in range(index + 1, salao_map.SPAWNS.size()):
			_expect(spawn.distance_to(salao_map.SPAWNS[other]) >= arena_rules.PLAYER_HIT_RADIUS * 2.0, "spawns do not overlap")
	for index in pickups.size():
		var point: Vector2 = pickups[index]
		var pickup: Vector3 = arena_rules.PICKUP_POSITIONS[index]
		_expect(rooms.any(func(room: Rect2) -> bool: return room.has_point(point)) and free.has(Vector2i(point / GRID)),
			"pickup inside a room with capsule clearance")
		_expect(is_equal_approx(pickup.y, MansionMap.PICKUP_HEIGHT), "pickup height")
		for door in salao_map.DOORS:
			_expect(point.distance_to(salao_map.rect(door).get_center()) >= 1.8, "pickup clearance from door")
		for spawn in salao_map.SPAWNS:
			_expect(point.distance_to(spawn) >= (4.0 if index < salao_map.WEAPONS.size() else 3.0), "pickup clearance from spawn")
		for other in range(index + 1, pickups.size()):
			_expect(point.distance_to(pickups[other]) >= PICKUP_GAP, "pickup pair clearance")

func _check_walls() -> void:
	var start := _body(Vector2(8, 12))
	var south_wall: Dictionary = movement_rules.resolve_step(start + Vector3.LEFT * 2, Vector3.BACK * 8)
	_expect(south_wall["blocked_z"] and south_wall["position"].z <= 14.0 - arena_rules.PLAYER_HIT_RADIUS,
		"capsule cannot cross solid south wall in a long step")
	var library_door: Dictionary = movement_rules.resolve_step(_body(Vector2(1, 8)), Vector3.LEFT * 3)
	_expect(library_door["position"].is_equal_approx(_body(Vector2(-2, 8))), "capsule crosses the hall and library doorway")
	var west_wall: Dictionary = movement_rules.resolve_step(_body(Vector2(-9, 13)), Vector3.LEFT * 3)
	_expect(west_wall["blocked_x"] and west_wall["position"].x >= salao_map.MIN_X + arena_rules.PLAYER_HIT_RADIUS,
		"solid west wall closes the library")
	for x in [-10.0, -7.0, -4.0]:
		var shelf: Dictionary = movement_rules.resolve_step(_body(Vector2(x, 13)), Vector3.FORWARD * 4)
		_expect(shelf["blocked_z"] and shelf["position"].z > 11.5, "capsule cannot cross a library shelf")
	var library_center := _body(Vector2(-5.5, 9.5))
	_expect(is_equal_approx(arena_rules.first_blocker_distance(library_center, Vector3.UP, 10.0), 2.5),
		"library ceiling seals the room at 3.5 m")
	_expect(is_equal_approx(arena_rules.first_blocker_distance(start, Vector3.UP, 10.0), 6.0), "hall ceiling seals the hall at 7 m")
	var gallery := Vector3(8, 4.75, 2)
	_expect(is_equal_approx(arena_rules.first_blocker_distance(gallery, Vector3.FORWARD, 10.0), 1.5), "gallery opening is sealed")

	var kitchen_center := _body(_room("cozinha").get_center())
	var east_wall: Dictionary = movement_rules.resolve_step(kitchen_center, Vector3.RIGHT * 7)
	_expect(east_wall["blocked_x"] and east_wall["position"].x <= 26.5 - arena_rules.PLAYER_HIT_RADIUS,
		"solid east wall closes the kitchen")
	_expect(movement_rules.resolve_step(kitchen_center, Vector3.BACK * 4)["blocked_z"], "island blocks the capsule")
	_expect(movement_rules.resolve_step(_body(Vector2(25, 9.5)), Vector3.FORWARD * 4)["blocked_z"],
		"service stairs block the capsule")
	var eye := Vector3(kitchen_center.x, 1.7, kitchen_center.z)
	_expect(is_equal_approx(arena_rules.first_blocker_distance(eye, Vector3.BACK, 4.0), 1.0),
		"island blocks shots at eye height")
	_expect(is_equal_approx(arena_rules.first_blocker_distance(kitchen_center, Vector3.UP, 10.0), 2.5),
		"kitchen ceiling seals the room at 3.5 m")

func _check_dining_room() -> void:
	var dining := _room("jantar")
	_expect(dining == Rect2(5.5, 14.5, 14, 8), "dining room footprint")
	if not dining.has_area():
		return
	var door_centers := {}
	for door in salao_map.DOORS:
		door_centers[door["id"]] = salao_map.rect(door).get_center()
		if door["id"] in ["porta_jantar", "porta_cozinha_jantar"]:
			_expect(door["corridor"] == "jantar", "south doorway connects to the dining room")

	var hall_center := _room("salao").get_center()
	var kitchen_center := _room("cozinha").get_center()
	var dining_center := dining.get_center()
	var position := _body(hall_center)
	for waypoint in [Vector2(8, 8), door_centers["porta_cozinha"], Vector2(21.5, 8), kitchen_center,
			Vector2(17.5, 9.5), door_centers["porta_cozinha_jantar"], Vector2(17.5, 18.5), dining_center,
			Vector2(8, 18.5), door_centers["porta_jantar"], hall_center]:
		var target := _body(waypoint)
		position = movement_rules.resolve_step(position, target - position)["position"]
		_expect(position.is_equal_approx(target), "capsule follows the ground-floor loop to %s" % waypoint)

	for index in salao_map.SPAWNS.size():
		var spawn: Vector2 = salao_map.SPAWNS[index]
		if dining.has_point(spawn):
			var yaw: float = salao_map.spawn_yaw_at(index)
			var facing := Vector2(-sin(yaw), -cos(yaw))
			var to_door := spawn.direction_to(door_centers["porta_jantar"])
			_expect(facing.is_equal_approx(to_door) or facing.is_equal_approx(spawn.direction_to(dining_center)),
				"dining spawn faces the hall door or the room center")

	var south_wall: Dictionary = movement_rules.resolve_step(_body(Vector2(8, 18.5)), Vector3.BACK * 7)
	_expect(south_wall["blocked_z"] and south_wall["position"].z <= dining.end.y - arena_rules.PLAYER_HIT_RADIUS,
		"solid south wall closes the dining room")
	var table: Dictionary = movement_rules.resolve_step(_body(dining_center), Vector3.BACK * 3)
	_expect(table["blocked_z"] and table["position"].z <= 19.5 - arena_rules.PLAYER_HIT_RADIUS,
		"table blocks the capsule")
	var sideboard: Dictionary = movement_rules.resolve_step(_body(dining_center), Vector3.RIGHT * 7)
	_expect(sideboard["blocked_x"] and sideboard["position"].x <= 18.5 - arena_rules.PLAYER_HIT_RADIUS,
		"sideboard blocks the capsule")
	var eye := Vector3(dining_center.x, 1.7, dining_center.y)
	_expect(arena_rules.first_blocker_distance(eye, Vector3.BACK, 3.0) < 0.0, "shots pass over the table")
	_expect(is_equal_approx(arena_rules.first_blocker_distance(eye, Vector3.RIGHT, 7.0), 6.0),
		"sideboard blocks shots at eye height")
	_expect(is_equal_approx(arena_rules.first_blocker_distance(_body(dining_center), Vector3.UP, 10.0), 2.5),
		"dining ceiling seals the room at 3.5 m")

func _check_guest_room() -> void:
	var guest := _room("hospedes")
	var stub := _room("lavabo_stub")
	_expect(guest == Rect2(-10.5, 14.5, 6, 5), "guest room footprint")
	_expect(stub == Rect2(-4, 16.5, 1.5, 2), "lavatory recess footprint")
	var north_door := Vector2(-8.5, 14.25)
	var east_door := Vector2(-4.25, 17.5)
	var guest_doors := []
	for door in salao_map.DOORS:
		if "hospedes" in [door["room"], door["corridor"]]:
			guest_doors.append(door["id"])
			if door["id"] == "porta_hospedes":
				_expect(door["room"] == "biblioteca" and door["corridor"] == "hospedes"
					and salao_map.rect(door).get_center() == north_door, "north door connects library and guest room")
			if door["id"] == "porta_lavabo":
				_expect(door["room"] == "hospedes" and door["corridor"] == "lavabo_stub"
					and salao_map.rect(door).get_center() == east_door, "east door connects guest room and lavatory recess")
	_expect(guest_doors.size() == 2 and guest_doors.has("porta_hospedes") and guest_doors.has("porta_lavabo"),
		"guest room has only the library and lavatory doors")

	var center := guest.get_center()
	var position := _body(_room("biblioteca").get_center())
	for waypoint in [Vector2(-5.5, 13), Vector2(-8.5, 13), north_door,
			Vector2(-8.5, 15.5), Vector2(-7.5, 15.5), center,
			Vector2(-7.5, 17.5), east_door, stub.get_center()]:
		var target := _body(waypoint)
		position = movement_rules.resolve_step(position, target - position)["position"]
		_expect(position.is_equal_approx(target), "capsule follows library through guest room into recess to %s" % waypoint)

	var radius: float = arena_rules.PLAYER_HIT_RADIUS
	var south_wall: Dictionary = movement_rules.resolve_step(_body(center), Vector3.BACK * 5)
	_expect(south_wall["blocked_z"] and south_wall["position"].z <= guest.end.y - radius,
		"solid south wall closes the guest room")
	var east_wall: Dictionary = movement_rules.resolve_step(_body(stub.get_center()), Vector3.RIGHT * 4)
	_expect(east_wall["blocked_x"] and east_wall["position"].x <= stub.end.x - radius,
		"solid east wall closes the lavatory recess")

	var bed: Dictionary = movement_rules.resolve_step(_body(center), Vector3.LEFT * 2.5)
	_expect(bed["blocked_x"] and bed["position"].x >= -8.5 + radius, "bed blocks the capsule")
	var eye := Vector3(center.x, 1.7, center.y)
	_expect(arena_rules.first_blocker_distance(eye, Vector3.LEFT, 2.5) < 0.0, "shots pass over the bed")
	var wardrobe_start := _body(Vector2(-7.5, 15.5))
	var wardrobe: Dictionary = movement_rules.resolve_step(wardrobe_start, Vector3.RIGHT * 2.5)
	_expect(wardrobe["blocked_x"] and wardrobe["position"].x <= -5.5 - radius, "wardrobe blocks the capsule")
	eye = Vector3(wardrobe_start.x, 1.7, wardrobe_start.z)
	_expect(is_equal_approx(arena_rules.first_blocker_distance(eye, Vector3.RIGHT, 2.5), 2.0),
		"wardrobe blocks shots at eye height")
	_expect(is_equal_approx(arena_rules.first_blocker_distance(_body(center), Vector3.UP, 10.0), 2.5),
		"guest room ceiling seals at 3.5 m")
	_expect(is_equal_approx(arena_rules.first_blocker_distance(_body(stub.get_center()), Vector3.UP, 10.0), 2.0),
		"lavatory recess ceiling seals at 3 m")

	for index in salao_map.SPAWNS.size():
		var spawn: Vector2 = salao_map.SPAWNS[index]
		if guest.has_point(spawn):
			var yaw: float = salao_map.spawn_yaw_at(index)
			var facing := Vector2(-sin(yaw), -cos(yaw))
			_expect(facing.is_equal_approx(spawn.direction_to(north_door))
				or facing.is_equal_approx(spawn.direction_to(center)), "guest spawn faces the north door or the room center")

func _body(point: Vector2) -> Vector3:
	return Vector3(point.x, movement_rules.PLAYER_HEIGHT, point.y)

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
