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
			if salao_map.space_floor(entries[index]) != salao_map.space_floor(entries[other]):
				continue
			_expect(not area.intersects(salao_map.rect(entries[other])), "non-overlapping spaces and doors")
	for door in salao_map.DOORS:
		var area: Rect2 = salao_map.rect(door)
		_expect(minf(area.size.x, area.size.y) == 0.5 and maxf(area.size.x, area.size.y) == 2.0, "door dimensions")
		var center: Vector2 = area.get_center()
		var lintel: float = arena_rules.first_blocker_distance(Vector3(center.x, salao_map.space_floor(door) + 1.0, center.y), Vector3.UP, 10.0)
		_expect(is_equal_approx(lintel, MansionMap.DOOR_HEIGHT - 1.0), "door lintel height")

	var free := {}
	for x in range(int(salao_map.MIN_X / GRID), int(26.5 / GRID) + 1):
		for z in range(int(29.0 / GRID) + 1):
			var cell := Vector2i(x, z)
			var point := Vector2(cell) * GRID
			if not salao_map.space_at(point).is_empty() and not arena_rules.overlaps_blocker(_at(point)):
				free[cell] = true
	_check_floor(free)
	_check_items(free)
	_check_walls()
	_check_gallery()
	_check_upper_rooms()
	_check_dining_room()
	_check_guest_room()
	_check_lavatory()
	_check_marble_bathroom()
	_check_winter_garden()

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
		var from := _at(Vector2(cell) * GRID)
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			var point := Vector2(next) * GRID
			var target := _at(point)
			var resolved: Vector3 = movement_rules.resolve_step(from, target - from)["position"]
			if salao_map.space_at(point).is_empty():
				_expect(not resolved.is_equal_approx(target), "capsule stays within sealed floor")
			if free.has(next) and not visited.has(next) and resolved.is_equal_approx(target):
				visited[next] = true
				queue.append(next)
	_expect(free.has(start) and visited.size() == free.size(), "all capsule-clear floor is connected")
	for door in salao_map.DOORS:
		if salao_map.space_floor(door) != 0.0:
			continue
		var center: Vector2 = salao_map.rect(door).get_center()
		_expect(visited.has(Vector2i(center / GRID)), "door center is reachable")
	for entry in salao_map.SPACES:
		if salao_map.space_floor(entry) != 0.0:
			continue
		var center: Vector2 = salao_map.rect(entry).get_center()
		_expect(visited.has(Vector2i(center / GRID)), "space center is reachable")

func _room(id: String) -> Rect2:
	for entry in salao_map.SPACES:
		if entry["id"] == id:
			return salao_map.rect(entry)
	return Rect2()

func _check_items(free: Dictionary) -> void:
	var weapons: Array = salao_map.pickups_of_type("weapon")
	var ammo: Array = salao_map.pickups_of_type("ammo")
	var health: Array = salao_map.pickups_of_type("health")
	_expect(salao_map.SPAWNS.size() == 8 and weapons.size() == 8 and ammo.size() == 12 and health.size() == 5,
		"eight spawns, eight weapons, twelve ammo, five health")
	var ground_spawns := 0
	var upper_spawns := 0
	for index in salao_map.SPAWNS.size():
		var entry: Dictionary = salao_map.SPAWNS[index]
		var spawn: Vector2 = salao_map.item_point(entry)
		var floor_y: float = salao_map.item_floor(entry)
		var body: Vector3 = movement_rules.SPAWN_POINTS[index]
		_expect(is_equal_approx(body.y, MansionMap.BODY_CENTER_HEIGHT + floor_y), "spawn height matches listed floor")
		_expect(_space_contains(spawn, floor_y, str(entry["space"])) and not arena_rules.overlaps_blocker(body),
			"spawn inside its room with capsule clearance")
		if floor_y > 0.0:
			upper_spawns += 1
		else:
			ground_spawns += 1
			_expect(free.has(Vector2i(spawn / GRID)), "ground spawn sits on capsule-clear floor")
		for other in range(index + 1, salao_map.SPAWNS.size()):
			var other_point: Vector2 = salao_map.item_point(salao_map.SPAWNS[other])
			_expect(spawn.distance_to(other_point) >= arena_rules.PLAYER_HIT_RADIUS * 2.0, "spawns do not overlap")
	_expect(ground_spawns >= 3 and upper_spawns >= 3, "spawns are spread across both floors")
	_expect(ammo.any(func(entry: Dictionary) -> bool: return _room("lavabo").has_point(salao_map.item_point(entry))),
		"lavatory keeps its ammo")
	_expect(ammo.any(func(entry: Dictionary) -> bool: return _room("banheiro_marmore").has_point(salao_map.item_point(entry))),
		"marble bathroom has ammo")
	_expect(ammo.any(func(entry: Dictionary) -> bool: return _room("jardim_inverno").has_point(salao_map.item_point(entry))),
		"greenhouse has ammo")
	_expect(weapons.any(func(entry: Dictionary) -> bool: return str(entry.get("weapon_id", "")) == "hunting_rifle" and str(entry["space"]) == "salao"),
		"strong rifle sits in the hall")
	_expect(weapons.any(func(entry: Dictionary) -> bool: return str(entry.get("weapon_id", "")) == "coach_gun" and str(entry["space"]).begins_with("galeria")),
		"strong shotgun sits in the gallery")
	var health_rooms: Dictionary = {}
	var health_floors: Dictionary = {}
	for entry in health:
		health_rooms[str(entry["space"])] = true
		health_floors[salao_map.item_floor(entry)] = true
	_expect(health_rooms.size() == 5 and health_floors.has(0.0) and health_floors.has(salao_map.GALLERY_FLOOR),
		"health boxes occupy five rooms on both floors")
	var pickups: Array = salao_map.PICKUPS
	for index in pickups.size():
		var entry: Dictionary = pickups[index]
		var point: Vector2 = salao_map.item_point(entry)
		var floor_y: float = salao_map.item_floor(entry)
		var pickup: Vector3 = arena_rules.PICKUP_POSITIONS[index]
		var body := Vector3(point.x, movement_rules.PLAYER_HEIGHT + floor_y, point.y)
		_expect(_space_contains(point, floor_y, str(entry["space"])) and not arena_rules.overlaps_blocker(body),
			"pickup inside its room with capsule clearance")
		_expect(is_equal_approx(pickup.y, MansionMap.PICKUP_HEIGHT + floor_y), "pickup height")
		_expect(is_equal_approx(salao_map.walk_height(point.x, point.y, body.y), floor_y), "pickup floor is stair-reachable")
		for door in salao_map.DOORS:
			var center: Vector2 = salao_map.rect(door).get_center()
			var door_position := Vector3(center.x, salao_map.space_floor(door) + MansionMap.PICKUP_HEIGHT, center.y)
			_expect(pickup.distance_to(door_position) >= 1.8, "pickup clearance from door")
		var kind := str(entry["type"])
		var spawn_gap := 4.0 if kind == "weapon" else 3.0
		for spawn in movement_rules.SPAWN_POINTS:
			_expect(pickup.distance_to(spawn + Vector3.UP * (MansionMap.PICKUP_HEIGHT - movement_rules.PLAYER_HEIGHT)) >= spawn_gap,
				"pickup clearance from spawn")
		for other in range(index + 1, pickups.size()):
			_expect(pickup.distance_to(arena_rules.PICKUP_POSITIONS[other]) >= PICKUP_GAP, "pickup pair clearance")

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
	var library_south := _body(Vector2(-5.5, 12))
	_expect(is_equal_approx(arena_rules.first_blocker_distance(library_south, Vector3.UP, 10.0), 2.5),
		"library ceiling seals the room at 3.5 m")
	_expect(is_equal_approx(arena_rules.first_blocker_distance(start, Vector3.UP, 10.0), 6.0), "hall ceiling seals the hall at 7 m")
	var gallery := Vector3(8, 4.75, 2)
	_expect(is_equal_approx(arena_rules.first_blocker_distance(gallery, Vector3.FORWARD, 10.0), 2.0), "gallery shot reaches the north wall")

	var kitchen_center := _body(_room("cozinha").get_center())
	var east_wall: Dictionary = movement_rules.resolve_step(kitchen_center, Vector3.RIGHT * 7)
	_expect(east_wall["blocked_x"] and east_wall["position"].x <= 26.5 - arena_rules.PLAYER_HIT_RADIUS,
		"solid east wall closes the kitchen")
	_expect(movement_rules.resolve_step(kitchen_center, Vector3.BACK * 4)["blocked_z"], "island blocks the capsule")
	var under_service: Vector3 = movement_rules.resolve_step(_body(Vector2(25, 9.5)), Vector3.FORWARD * 5)["position"]
	_expect(under_service.z >= 5.0 + arena_rules.PLAYER_HIT_RADIUS and under_service.z < 5.75
		and is_equal_approx(under_service.y, 1.0), "ground capsule reaches the north wall under the service landing")
	var eye := Vector3(kitchen_center.x, 1.7, kitchen_center.z)
	_expect(is_equal_approx(arena_rules.first_blocker_distance(eye, Vector3.BACK, 4.0), 1.0),
		"island blocks shots at eye height")
	_expect(is_equal_approx(arena_rules.first_blocker_distance(Vector3(21.5, 2.1, 12), Vector3.UP, 10.0), 1.4),
		"kitchen ceiling seals the room at 3.5 m")

func _check_gallery() -> void:
	var route := [Vector2(5, 7), Vector2(5, 1), Vector2(15.25, 1), Vector2(15.25, 6),
		Vector2(17.25, 6), Vector2(17.25, 8.5), Vector2(25.5, 8.5), Vector2(25.5, 6), Vector2(17.5, 6)]
	for _direction in 2:
		var position := _body(route.front())
		for index in route.size():
			var waypoint: Vector2 = route[index]
			var target := _body(waypoint)
			if index > 0 and index < route.size() - 1:
				target.y += salao_map.GALLERY_FLOOR
			position = movement_rules.resolve_step(position, target - position)["position"]
			_expect(position.is_equal_approx(target), "upper loop reaches %s from %s" % [waypoint, route.front()])
		route.reverse()

	var plug: Dictionary = movement_rules.resolve_step(_body(Vector2(15, 6)), Vector3.RIGHT * 2)
	_expect(plug["blocked_x"] and plug["position"].x < 16.0, "upper doorway remains sealed at ground level")
	var balcony := Vector3(8, 4.5, 3)
	var rail: Dictionary = movement_rules.resolve_step(balcony, Vector3.BACK * 3)
	_expect(rail["blocked_z"] and is_equal_approx(rail["position"].y, balcony.y), "balcony rail keeps capsule upstairs")
	_expect(arena_rules.first_blocker_distance(balcony + Vector3.UP * arena_rules.EYE_HEIGHT, Vector3.BACK, 4.0) < 0.0,
		"eye-height shot clears the balcony rail")
	var under := _body(Vector2(8, 3))
	_expect(is_equal_approx(arena_rules.first_blocker_distance(under, Vector3.UP, 10.0), 2.4),
		"upward shot from the hall hits the underside of the balcony at 3.4 m")
	_expect(movement_rules.resolve_step(_body(Vector2(8, 6)), Vector3.FORWARD * 3)["position"].is_equal_approx(under),
		"ground capsule stays below the balcony")
	_expect(arena_rules.zone_name_at(under) == "Salão Central" and arena_rules.zone_name_at(balcony) == "Galeria",
		"zone name distinguishes the floors at the same XZ")
	_expect(is_equal_approx(arena_rules.first_blocker_distance(Vector3(25.5, 4.5, 6), Vector3.UP, 10.0), 2.5),
		"service landing ceiling is at 7 m")

func _check_upper_rooms() -> void:
	var upstairs: Vector3 = Vector3.UP * salao_map.GALLERY_FLOOR
	var north := _room("quarto_norte").get_center()
	var suite := _room("suite").get_center()
	var observatory := _room("observatorio").get_center()
	var music := _room("musica").get_center()
	for route in [
		[Vector2(1, 1), Vector2(north.x, 1), north, Vector2(-7, north.y),
			Vector2(-7, suite.y), suite, Vector2(suite.x, 4), Vector2(1, 4), Vector2(1, 1)],
		[Vector2(25.5, 6), Vector2(observatory.x, 6), observatory, Vector2(30, observatory.y),
			Vector2(30, music.y), music, Vector2(music.x, 9), Vector2(25.5, 9), Vector2(25.5, 6)],
	]:
		for _direction in 2:
			var position := _body(route.front()) + upstairs
			for point in route:
				var target := _body(point) + upstairs
				position = movement_rules.resolve_step(position, target - position)["position"]
				_expect(position.is_equal_approx(target), "upper room loop reaches %s from %s" % [point, route.front()])
			route.reverse()

	for wall in [
		[Vector2(-7, 2.7), Vector3.LEFT, 3.5],
		[Vector2(-7, 4.5), Vector3.LEFT, 3.5],
		[Vector2(31, 7.5), Vector3.RIGHT, 3.0],
		[Vector2(32.5, 13), Vector3.RIGHT, 1.5],
		[suite, Vector3.BACK, 10.0 - suite.y],
	]:
		var start := _body(wall[0]) + upstairs
		var direction: Vector3 = wall[1]
		var distance: float = wall[2]
		var result: Dictionary = movement_rules.resolve_step(start, direction * (distance + 1.0))
		_expect(result["blocked_x"] if direction.x != 0 else result["blocked_z"], "upper wall stops capsule from %s" % start)
		_expect(is_equal_approx(arena_rules.first_blocker_distance(start + Vector3.UP * 0.7, direction, distance + 1.0), distance),
			"upper wall seals the room at %s" % (start + direction * distance))

	for furniture in [
		["cama_norte", Vector2(-7, 2), Vector3.LEFT, 1.0, false],
		["cama_suite", Vector2(-7, 8), Vector3.LEFT, 1.0, false],
		["piano", Vector2(30, 11), Vector3.BACK, 0.75, false],
		["guarda_norte", Vector2(-7, 1), Vector3.LEFT, 2.5, true],
		["guarda_suite", Vector2(-2.5, 8), Vector3.RIGHT, 1.0, true],
		["pedestal_observatorio", Vector2(31, 6.5), Vector3.RIGHT, 1.0, true],
		["armario_musica", Vector2(32, 10), Vector3.RIGHT, 1.0, true],
	]:
		var start := _body(furniture[1]) + upstairs
		var direction: Vector3 = furniture[2]
		var distance: float = furniture[3]
		var result: Dictionary = movement_rules.resolve_step(start, direction * (distance + 0.25))
		_expect(result["blocked_x"] if direction.x != 0 else result["blocked_z"], "%s stops the capsule" % furniture[0])
		var hit: float = arena_rules.first_blocker_distance(start + Vector3.UP * 0.7, direction, distance + 0.25)
		_expect(is_equal_approx(hit, distance) if furniture[4] else hit < 0.0, "%s eye-height shot behavior" % furniture[0])

	var under_suite := _body(suite)
	_expect(is_equal_approx(arena_rules.first_blocker_distance(under_suite + upstairs, Vector3.UP, 10.0), 2.5),
		"suite ceiling seals at 7 m")
	_expect(is_equal_approx(arena_rules.first_blocker_distance(under_suite, Vector3.UP, 10.0), 2.4),
		"library ray hits the underside of the suite at 3.4 m")

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
		var spawn: Vector2 = salao_map.item_point(salao_map.SPAWNS[index])
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
	_expect(guest == Rect2(-10.5, 14.5, 6, 5), "guest room footprint")
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
				_expect(door["room"] == "hospedes" and door["corridor"] == "lavabo"
					and salao_map.rect(door).get_center() == east_door, "east door connects guest room and lavatory")
	_expect(guest_doors.size() == 2 and guest_doors.has("porta_hospedes") and guest_doors.has("porta_lavabo"),
		"guest room has only the library and lavatory doors")

	var center := guest.get_center()
	var position := _body(_room("biblioteca").get_center())
	for waypoint in [Vector2(-5.5, 13), Vector2(-8.5, 13), north_door,
			Vector2(-8.5, 15.5), Vector2(-7.5, 15.5), center,
			Vector2(-7.5, 17.5), east_door, Vector2(0.5, 17.5), _room("lavabo").get_center()]:
		var target := _body(waypoint)
		position = movement_rules.resolve_step(position, target - position)["position"]
		_expect(position.is_equal_approx(target), "capsule follows the library through the guest room to the lavatory to %s" % waypoint)

	var radius: float = arena_rules.PLAYER_HIT_RADIUS
	var south_wall: Dictionary = movement_rules.resolve_step(_body(center), Vector3.BACK * 5)
	_expect(south_wall["blocked_z"] and south_wall["position"].z <= guest.end.y - radius,
		"solid south wall closes the guest room")

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

	for index in salao_map.SPAWNS.size():
		var spawn: Vector2 = salao_map.item_point(salao_map.SPAWNS[index])
		if guest.has_point(spawn):
			var yaw: float = salao_map.spawn_yaw_at(index)
			var facing := Vector2(-sin(yaw), -cos(yaw))
			_expect(facing.is_equal_approx(spawn.direction_to(north_door))
				or facing.is_equal_approx(spawn.direction_to(center)), "guest spawn faces the north door or the room center")

func _check_lavatory() -> void:
	var lavatory := _room("lavabo")
	_expect(lavatory == Rect2(-4, 16, 9, 3.5), "lavatory footprint")
	if not lavatory.has_area():
		return

	var east_door := Rect2(5, 16.5, 0.5, 2)
	var south_door := Rect2(0.5, 19.5, 2, 0.5)
	_expect(salao_map.DOORS.any(func(door: Dictionary) -> bool:
		return (door["id"] == "porta_lavabo_jantar" and door["room"] == "lavabo"
			and door["corridor"] == "jantar" and salao_map.rect(door) == east_door)
	), "east doorway connects the lavatory and dining room")
	_expect(salao_map.DOORS.any(func(door: Dictionary) -> bool:
		return (door["id"] == "porta_banheiro_marmore" and door["room"] == "lavabo"
			and door["corridor"] == "banheiro_marmore" and salao_map.rect(door) == south_door)
	), "south doorway connects the lavatory and marble bathroom")

	var center := lavatory.get_center()
	var dining := _room("jantar").get_center()
	var position := _body(center)
	for waypoint in [Vector2(center.x, 17.5), east_door.get_center(), Vector2(dining.x, 17.5), dining]:
		var target := _body(waypoint)
		position = movement_rules.resolve_step(position, target - position)["position"]
		_expect(position.is_equal_approx(target), "capsule closes the west loop to the dining room at %s" % waypoint)

	var radius: float = arena_rules.PLAYER_HIT_RADIUS
	var north_wall: Dictionary = movement_rules.resolve_step(_body(center), Vector3.FORWARD * 3)
	_expect(north_wall["blocked_z"] and north_wall["position"].z >= lavatory.position.y + radius,
		"solid north wall closes the lavatory")
	var south_wall: Dictionary = movement_rules.resolve_step(_body(Vector2(3.5, 17.5)), Vector3.BACK * 4)
	_expect(south_wall["blocked_z"] and south_wall["position"].z <= lavatory.end.y - radius,
		"solid south wall closes the lavatory beside the doorway")
	var east_wall: Dictionary = movement_rules.resolve_step(_body(Vector2(3.5, 19)), Vector3.RIGHT * 4)
	_expect(east_wall["blocked_x"] and east_wall["position"].x <= lavatory.end.x - radius,
		"solid east wall separates the lavatory and dining room beside the doorway")

	var sink_start := _body(Vector2(-2, 17.5))
	var sink: Dictionary = movement_rules.resolve_step(sink_start, Vector3.BACK * 1.5)
	_expect(sink["blocked_z"] and sink["position"].z <= 18.5 - radius, "sink blocks the capsule")
	var eye := Vector3(sink_start.x, 1.7, sink_start.z)
	_expect(arena_rules.first_blocker_distance(eye, Vector3.BACK, 1.5) < 0.0, "shots pass over the sink")
	_expect(is_equal_approx(arena_rules.first_blocker_distance(_body(center), Vector3.UP, 10.0), 2.5),
		"lavatory ceiling seals at 3.5 m")

func _check_marble_bathroom() -> void:
	var bathroom := _room("banheiro_marmore")
	_expect(bathroom == Rect2(-4, 20, 9, 6), "marble bathroom footprint")
	_expect(salao_map.DOORS.any(func(door: Dictionary) -> bool:
		return (door["id"] == "porta_jardim_inverno" and door["room"] == "banheiro_marmore"
			and door["corridor"] == "jardim_acesso" and salao_map.rect(door) == Rect2(0.5, 26, 2, 0.5))
	), "bathroom south doorway leads into the winter garden access")

	var position := _body(_room("lavabo").get_center())
	for waypoint in [Vector2(1.5, position.z), Vector2(1.5, 19.75), Vector2(1.5, 23), bathroom.get_center()]:
		var target := _body(waypoint)
		position = movement_rules.resolve_step(position, target - position)["position"]
		_expect(position.is_equal_approx(target), "capsule crosses from lavatory to bathroom at %s" % waypoint)

	var radius: float = arena_rules.PLAYER_HIT_RADIUS
	for x in [-3.0, 4.0]:
		var south_wall: Dictionary = movement_rules.resolve_step(_body(Vector2(x, 25)), Vector3.BACK * 3)
		_expect(south_wall["blocked_z"] and south_wall["position"].z <= bathroom.end.y - radius,
			"solid bathroom south wall beside the doorway at x=%s" % x)

	var tub_start := _body(Vector2(-2.5, 20.75))
	var tub: Dictionary = movement_rules.resolve_step(tub_start, Vector3.BACK * 2)
	_expect(tub["blocked_z"] and tub["position"].z <= 21.5 - radius, "bathtub blocks the capsule")
	var tub_eye := Vector3(tub_start.x, 1.7, tub_start.z)
	_expect(arena_rules.first_blocker_distance(tub_eye, Vector3.BACK, 2.0) < 0.0, "shots pass over the bathtub")

	var partition: Dictionary = movement_rules.resolve_step(_body(bathroom.get_center()), Vector3.RIGHT * 4)
	_expect(partition["blocked_x"] and partition["position"].x <= 3.0 - radius, "partition blocks the capsule")
	var partition_eye := Vector3(bathroom.get_center().x, 1.7, bathroom.get_center().y)
	_expect(is_equal_approx(arena_rules.first_blocker_distance(partition_eye, Vector3.RIGHT, 4.0), 2.5),
		"partition blocks shots at eye height")
	_expect(is_equal_approx(arena_rules.first_blocker_distance(_body(bathroom.get_center()), Vector3.UP, 10.0), 2.5),
		"marble bathroom ceiling seals at 3.5 m")

func _check_winter_garden() -> void:
	var access := _room("jardim_acesso")
	var greenhouse := _room("jardim_inverno")
	_expect(access == Rect2(-4, 26.5, 9, 2.5), "winter garden access footprint")
	_expect(greenhouse == Rect2(5.5, 23, 14, 6), "greenhouse footprint")
	var east_door := Rect2(5, 26.5, 0.5, 2)
	var dining_door := Rect2(11.5, 22.5, 2, 0.5)
	_expect(salao_map.DOORS.any(func(door: Dictionary) -> bool:
		return (door["id"] == "porta_jardim_acesso" and door["room"] == "jardim_inverno"
			and door["corridor"] == "jardim_acesso" and salao_map.rect(door) == east_door)
	), "east doorway connects the access and greenhouse")
	_expect(salao_map.DOORS.any(func(door: Dictionary) -> bool:
		return (door["id"] == "porta_jardim_jantar" and door["room"] == "jantar"
			and door["corridor"] == "jardim_inverno" and salao_map.rect(door) == dining_door)
	), "north doorway connects the greenhouse and dining room")

	var position := _body(_room("banheiro_marmore").get_center())
	for waypoint in [Vector2(1.5, 23), Vector2(1.5, 26.25), Vector2(1.5, 27.75), access.get_center(),
			Vector2(4, 27.75), Vector2(4, 27.5), east_door.get_center(), Vector2(12.5, 27.5),
			greenhouse.get_center(), dining_door.get_center(), Vector2(12.5, 21.75),
			Vector2(17, 21.75), Vector2(17, 18.5), _room("jantar").get_center()]:
		var target := _body(waypoint)
		position = movement_rules.resolve_step(position, target - position)["position"]
		_expect(position.is_equal_approx(target), "capsule closes the winter garden loop at %s" % waypoint)

	var radius: float = arena_rules.PLAYER_HIT_RADIUS
	for point in [access.get_center(), Vector2(18, 27)]:
		var start := _body(point)
		var south_wall: Dictionary = movement_rules.resolve_step(start, Vector3.BACK * 4)
		_expect(south_wall["blocked_z"] and south_wall["position"].z <= 29.0 - radius,
			"solid winter garden south wall stops the capsule")
		_expect(is_equal_approx(arena_rules.first_blocker_distance(start, Vector3.BACK, 4.0), 29.0 - start.z),
			"winter garden south wall starts at z=29")
	for room in [access, greenhouse]:
		_expect(is_equal_approx(arena_rules.first_blocker_distance(_body(room.get_center()), Vector3.UP, 10.0), 3.0),
			"winter garden ceiling seals at 4 m")

	var west_planter := _body(Vector2(7.5, 24.5))
	var center := _body(greenhouse.get_center())
	_expect(movement_rules.resolve_step(west_planter, Vector3.LEFT * 1.5)["blocked_x"], "west planter blocks the capsule")
	_expect(movement_rules.resolve_step(center, Vector3.BACK * 2.5)["blocked_z"], "south planter blocks the capsule")
	_expect(arena_rules.first_blocker_distance(Vector3(7.5, 1.7, 24.5), Vector3.LEFT, 1.5) < 0.0,
		"shots pass over the west planter")
	_expect(arena_rules.first_blocker_distance(Vector3(12.5, 1.7, 26), Vector3.BACK, 2.5) < 0.0,
		"shots pass over the south planter")

	var plant_start := _body(Vector2(12.5, 25.5))
	var eye := Vector3(plant_start.x, 1.7, plant_start.z)
	for direction in [Vector3.LEFT, Vector3.RIGHT]:
		_expect(movement_rules.resolve_step(plant_start, direction * 4)["blocked_x"], "plant column blocks the capsule")
		_expect(is_equal_approx(arena_rules.first_blocker_distance(eye, direction, 4.0), 3.0),
			"plant column blocks shots at eye height")

func _space_contains(point: Vector2, floor_y: float, space_id: String) -> bool:
	var space: Dictionary = salao_map.space_at(point, floor_y + 0.1)
	if space.is_empty():
		return false
	var sid := str(space["id"])
	if sid == space_id:
		return true
	# Galeria é um conjunto de vãos com o mesmo nome de família.
	return space_id.begins_with("galeria") and sid.begins_with("galeria")

func _at(point: Vector2) -> Vector3:
	return _body(point) + Vector3.UP * salao_map.walk_height(point.x, point.y, movement_rules.PLAYER_HEIGHT)

func _body(point: Vector2) -> Vector3:
	return Vector3(point.x, movement_rules.PLAYER_HEIGHT, point.y)

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
