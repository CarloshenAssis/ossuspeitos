extends RefCounted
## Greybox do Salão Central e da Biblioteca. Todas as coordenadas de piso estão em XZ.

const CELL := MansionMap.CELL
const WALL_TOP := 7.0 + MansionMap.SLAB_THICKNESS
const MIN_X := -10.5
const SPACES := [
	{"id": "salao", "name": "Salão Central", "kind": "room", "min": Vector2(0, 0), "max": Vector2(16, 14), "ceiling": 7.0},
	{"id": "biblioteca", "name": "Biblioteca", "kind": "room", "min": Vector2(MIN_X, 5), "max": Vector2(-0.5, 14), "ceiling": 3.5},
	{"id": "hospedes_stub", "name": "Quarto de Hóspedes", "kind": "corridor", "min": Vector2(-9.5, 14.5), "max": Vector2(-7.5, 16), "ceiling": 3.0},
	{"id": "cozinha_stub", "name": "Cozinha", "kind": "corridor", "min": Vector2(16.5, 7), "max": Vector2(18, 9), "ceiling": 3.0},
	{"id": "jantar_stub", "name": "Sala de Jantar", "kind": "corridor", "min": Vector2(7, 14.5), "max": Vector2(9, 16), "ceiling": 3.0},
]
const DOORS := [
	{"id": "porta_biblioteca", "room": "salao", "corridor": "biblioteca", "min": Vector2(-0.5, 7), "max": Vector2(0, 9)},
	{"id": "porta_hospedes", "room": "biblioteca", "corridor": "hospedes_stub", "min": Vector2(-9.5, 14), "max": Vector2(-7.5, 14.5)},
	{"id": "porta_cozinha", "room": "salao", "corridor": "cozinha_stub", "min": Vector2(16, 7), "max": Vector2(16.5, 9)},
	{"id": "porta_jantar", "room": "salao", "corridor": "jantar_stub", "min": Vector2(7, 14), "max": Vector2(9, 14.5)},
]
const FURNITURE := [
	{"id": "patamar", "min": Vector2(4, 0), "max": Vector2(12, 1), "height": 3.5},
	{"id": "lance_oeste", "min": Vector2(4, 1), "max": Vector2(6, 3), "height": 2.0},
	{"id": "lance_leste", "min": Vector2(10, 1), "max": Vector2(12, 3), "height": 2.0},
	{"id": "coluna_no", "min": Vector2(3, 6), "max": Vector2(4, 7), "height": 7.0},
	{"id": "coluna_ne", "min": Vector2(12, 6), "max": Vector2(13, 7), "height": 7.0},
	{"id": "coluna_so", "min": Vector2(3, 10), "max": Vector2(4, 11), "height": 7.0},
	{"id": "coluna_se", "min": Vector2(12, 10), "max": Vector2(13, 11), "height": 7.0},
	{"id": "estante_o", "space": "biblioteca", "min": Vector2(-10.5, 5), "max": Vector2(-9.5, 11.5), "height": 2.5},
	{"id": "estante_m", "space": "biblioteca", "min": Vector2(-7.5, 5), "max": Vector2(-6.5, 12), "height": 2.5},
	{"id": "estante_l", "space": "biblioteca", "min": Vector2(-4.5, 5), "max": Vector2(-3.5, 11.5), "height": 2.5},
]
const GALLERY := {"id": "galeria_fechada", "name": "Galeria", "min": Vector2(6, 0), "max": Vector2(10, 0.5)}
const SPAWNS := [
	Vector2(6.75, 10), Vector2(6, 10.5), Vector2(7, 8.75), Vector2(6.25, 9.25), Vector2(3.5, 0.5),
	Vector2(-1.5, 12.75), Vector2(-2, 13.5), Vector2(-2.5, 12.75),
]
const WEAPONS := [
	Vector2(14.5, 9), Vector2(13.25, 0.5), Vector2(10.75, 13.5), Vector2(15.5, 4.5), Vector2(7.5, 1.5),
	Vector2(-9, 5.5), Vector2(-3, 5.5), Vector2(-6, 9),
]
# Nove munições no Salão e três na Biblioteca preservam a folga de 4,5 m.
const AMMO := [
	Vector2(1.5, 5), Vector2(10, 9), Vector2(11, 4.5), Vector2(6, 5.75), Vector2(15.5, 13.5),
	Vector2(0.5, 0.5), Vector2(1.5, 13.5), Vector2(3, 9.25), Vector2(6.25, 13.5),
	Vector2(-1.5, 9.75), Vector2(-10, 12.75), Vector2(-5.5, 13.5),
]

static var enabled := OS.get_environment("OSSUSPEITOS_MAP") == "nocturna_salao"

static func rect(entry: Dictionary) -> Rect2:
	return Rect2(entry["min"], (entry["max"] as Vector2) - (entry["min"] as Vector2))

static func space_at(point: Vector2) -> Dictionary:
	for entry in SPACES:
		if rect(entry).has_point(point):
			return entry
	for door in DOORS:
		if rect(door).has_point(point):
			return SPACES[1] if door["room"] == "biblioteca" else SPACES[0]
	return {}

static func spawn_points() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point in SPAWNS:
		result.append(Vector3(point.x, MansionMap.BODY_CENTER_HEIGHT, point.y))
	return result

static func spawn_yaw_at(index: int) -> float:
	var point: Vector2 = SPAWNS[index]
	var target := Vector2(-0.25, 8) if point.x < 0.0 else Vector2(8, 10)
	var direction := target - point
	return atan2(-direction.x, -direction.y)

static func pickup_positions() -> Array:
	var result: Array = []
	for point in WEAPONS + AMMO:
		result.append(Vector3(point.x, MansionMap.PICKUP_HEIGHT, point.y))
	return result

static func blockers() -> Array:
	var floor_cells := {}
	for entry in SPACES + DOORS:
		var area := rect(entry)
		var first := Vector2i(area.position / CELL)
		var end := Vector2i(area.end / CELL)
		for z in range(first.y, end.y):
			for x in range(first.x, end.x):
				floor_cells[Vector2i(x, z)] = true
	var wall_cells := {}
	for cell: Vector2i in floor_cells:
		for z in range(-1, 2):
			for x in range(-1, 2):
				var neighbor := cell + Vector2i(x, z)
				if not floor_cells.has(neighbor):
					wall_cells[neighbor] = true

	var cells := wall_cells.keys()
	cells.sort()
	var result: Array = []
	for cell: Vector2i in cells:
		if wall_cells.has(cell - Vector2i(0, 1)):
			continue
		var length := 1
		while wall_cells.has(cell + Vector2i(0, length)):
			length += 1
		var wall := Rect2(Vector2(cell) * CELL, Vector2(CELL, length * CELL))
		result.append(_box("wall_x%d_z%d" % [cell.x, cell.y], "wall", wall, 0.0, WALL_TOP, ""))
	for door in DOORS:
		result.append(_box(door["id"], "lintel", rect(door), MansionMap.DOOR_HEIGHT, WALL_TOP, door["room"]))
	for entry in SPACES:
		var ceiling: float = entry["ceiling"]
		result.append(_box("teto_" + entry["id"], "ceiling", rect(entry).grow(CELL * 0.5), ceiling,
			ceiling + MansionMap.SLAB_THICKNESS, entry["id"]))
	for item in FURNITURE:
		result.append(_box(item["id"], "furniture", rect(item), 0.0, item["height"], item.get("space", "salao")))
	result.append(_box(GALLERY["id"], "furniture", rect(GALLERY), 3.5, 6.0, "salao"))
	return result

static func _box(id: String, kind: String, area: Rect2, bottom: float, top: float, space: String) -> Dictionary:
	var center := area.get_center()
	return {"id": id, "kind": kind, "space": space,
		"center": Vector3(center.x, (bottom + top) * 0.5, center.y),
		"size": Vector3(area.size.x, top - bottom, area.size.y)}
