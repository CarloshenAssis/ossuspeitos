extends RefCounted
## Greybox do Salão Central, da Biblioteca, da Cozinha, da Sala de Jantar, do Quarto de Hóspedes, do Lavabo, do Banheiro de Mármore e do Jardim de Inverno. Todas as coordenadas de piso estão em XZ.

const CELL := MansionMap.CELL
const WALL_TOP := 7.0 + MansionMap.SLAB_THICKNESS
const MIN_X := -10.5
const SPACES := [
	{"id": "salao", "name": "Salão Central", "kind": "room", "min": Vector2(0, 0), "max": Vector2(16, 14), "ceiling": 7.0},
	{"id": "biblioteca", "name": "Biblioteca", "kind": "room", "min": Vector2(MIN_X, 5), "max": Vector2(-0.5, 14), "ceiling": 3.5},
	{"id": "hospedes", "name": "Quarto de Hóspedes", "kind": "room", "min": Vector2(MIN_X, 14.5), "max": Vector2(-4.5, 19.5), "ceiling": 3.5},
	{"id": "lavabo", "name": "Lavabo", "kind": "corridor", "min": Vector2(-4, 16), "max": Vector2(5, 19.5), "ceiling": 3.5},
	{"id": "banheiro_marmore", "name": "Banheiro de Mármore", "kind": "room", "min": Vector2(-4, 20), "max": Vector2(5, 26), "ceiling": 3.5},
	{"id": "jardim_acesso", "name": "Acesso ao Jardim de Inverno", "kind": "corridor", "min": Vector2(-4, 26.5), "max": Vector2(5, 29), "ceiling": 4.0},
	{"id": "cozinha", "name": "Cozinha", "kind": "room", "min": Vector2(16.5, 5), "max": Vector2(26.5, 14), "ceiling": 3.5},
	{"id": "jantar", "name": "Sala de Jantar", "kind": "room", "min": Vector2(5.5, 14.5), "max": Vector2(19.5, 22.5), "ceiling": 3.5},
	{"id": "jardim_inverno", "name": "Jardim de Inverno", "kind": "room", "min": Vector2(5.5, 23), "max": Vector2(19.5, 29), "ceiling": 4.0},
]
const DOORS := [
	{"id": "porta_biblioteca", "room": "salao", "corridor": "biblioteca", "min": Vector2(-0.5, 7), "max": Vector2(0, 9)},
	{"id": "porta_hospedes", "room": "biblioteca", "corridor": "hospedes", "min": Vector2(-9.5, 14), "max": Vector2(-7.5, 14.5)},
	{"id": "porta_lavabo", "room": "hospedes", "corridor": "lavabo", "min": Vector2(-4.5, 16.5), "max": Vector2(-4, 18.5)},
	{"id": "porta_lavabo_jantar", "room": "lavabo", "corridor": "jantar", "min": Vector2(5, 16.5), "max": Vector2(5.5, 18.5)},
	{"id": "porta_banheiro_marmore", "room": "lavabo", "corridor": "banheiro_marmore", "min": Vector2(0.5, 19.5), "max": Vector2(2.5, 20)},
	{"id": "porta_jardim_inverno", "room": "banheiro_marmore", "corridor": "jardim_acesso", "min": Vector2(0.5, 26), "max": Vector2(2.5, 26.5)},
	{"id": "porta_cozinha", "room": "salao", "corridor": "cozinha", "min": Vector2(16, 7), "max": Vector2(16.5, 9)},
	{"id": "porta_jantar", "room": "salao", "corridor": "jantar", "min": Vector2(7, 14), "max": Vector2(9, 14.5)},
	{"id": "porta_cozinha_jantar", "room": "cozinha", "corridor": "jantar", "min": Vector2(16.5, 14), "max": Vector2(18.5, 14.5)},
	{"id": "porta_jardim_acesso", "room": "jardim_inverno", "corridor": "jardim_acesso", "min": Vector2(5, 26.5), "max": Vector2(5.5, 28.5)},
	{"id": "porta_jardim_jantar", "room": "jantar", "corridor": "jardim_inverno", "min": Vector2(11.5, 22.5), "max": Vector2(13.5, 23)},
]
const FURNITURE := [
	{"id": "coluna_no", "min": Vector2(3, 6), "max": Vector2(4, 7), "height": 7.0},
	{"id": "coluna_ne", "min": Vector2(12, 6), "max": Vector2(13, 7), "height": 7.0},
	{"id": "coluna_so", "min": Vector2(3, 10), "max": Vector2(4, 11), "height": 7.0},
	{"id": "coluna_se", "min": Vector2(12, 10), "max": Vector2(13, 11), "height": 7.0},
	{"id": "estante_o", "space": "biblioteca", "min": Vector2(-10.5, 5), "max": Vector2(-9.5, 11.5), "height": 2.5},
	{"id": "estante_m", "space": "biblioteca", "min": Vector2(-7.5, 5), "max": Vector2(-6.5, 12), "height": 2.5},
	{"id": "estante_l", "space": "biblioteca", "min": Vector2(-4.5, 5), "max": Vector2(-3.5, 11.5), "height": 2.5},
	{"id": "ilha", "space": "cozinha", "min": Vector2(19.5, 10.5), "max": Vector2(23, 12.5), "height": 2.0},
	{"id": "mesa_jantar", "space": "jantar", "min": Vector2(9, 19.5), "max": Vector2(16, 21), "height": 1.0},
	{"id": "aparador", "space": "jantar", "min": Vector2(18.5, 16.5), "max": Vector2(19.5, 21.5), "height": 2.0},
	{"id": "cama", "space": "hospedes", "min": Vector2(-10.5, 16.5), "max": Vector2(-8.5, 18.5), "height": 1.0},
	{"id": "guarda_roupa", "space": "hospedes", "min": Vector2(-5.5, 14.5), "max": Vector2(-4.5, 16.5), "height": 2.5},
	{"id": "pia", "space": "lavabo", "min": Vector2(-3, 18.5), "max": Vector2(-1, 19.5), "height": 1.0},
	{"id": "banheira", "space": "banheiro_marmore", "min": Vector2(-4, 21.5), "max": Vector2(-1.5, 24), "height": 1.0},
	{"id": "divisoria", "space": "banheiro_marmore", "min": Vector2(3, 21), "max": Vector2(3.5, 24.5), "height": 2.5},
	{"id": "jardineira_o", "space": "jardim_inverno", "min": Vector2(5.5, 23.5), "max": Vector2(6.5, 26), "height": 1.0},
	{"id": "jardineira_s", "space": "jardim_inverno", "min": Vector2(8, 28), "max": Vector2(16, 29), "height": 1.0},
	{"id": "planta_a", "space": "jardim_inverno", "min": Vector2(8.5, 25), "max": Vector2(9.5, 26), "height": 2.5},
	{"id": "planta_b", "space": "jardim_inverno", "min": Vector2(15.5, 25), "max": Vector2(16.5, 26), "height": 2.5},
]
const GALLERY_FLOOR := 3.5
const RAMPS := [
	{"id": "lance_oeste", "space": "salao", "min": Vector2(4, 2), "max": Vector2(6, 6),
		"axis": "z", "y_at_min": GALLERY_FLOOR, "y_at_max": 0.0},
	{"id": "lance_leste", "space": "salao", "min": Vector2(10, 2), "max": Vector2(12, 6),
		"axis": "z", "y_at_min": GALLERY_FLOOR, "y_at_max": 0.0},
	{"id": "escada_servico", "space": "cozinha", "min": Vector2(18, 5), "max": Vector2(24.5, 7),
		"axis": "x", "y_at_min": 0.0, "y_at_max": GALLERY_FLOOR},
]
const GALLERY := {"id": "patamar_galeria", "name": "Galeria", "space": "salao",
	"min": Vector2(4, 0), "max": Vector2(12, 2), "y": GALLERY_FLOOR}
const LANDINGS := [
	GALLERY,
	{"id": "patamar_servico", "space": "cozinha", "min": Vector2(24.5, 5), "max": Vector2(26.5, 8), "y": GALLERY_FLOOR},
]
const HALL_RAILS := [
	Rect2(4, 0, 0.1, 2), Rect2(11.9, 0, 0.1, 2),
	Rect2(4, 2, 0.1, 4), Rect2(5.95, 2, 0.1, 4),
	Rect2(9.95, 2, 0.1, 4), Rect2(11.9, 2, 0.1, 4),
]
const SERVICE_RAILS := [
	Rect2(18, 6.9, 6.5, 0.1), Rect2(24.5, 6.9, 0.1, 1.1), Rect2(24.5, 7.9, 2, 0.1),
]
const SPAWNS := [
	Vector2(7, 8.75), Vector2(12.5, 18.5), Vector2(3.5, 0.5),
	Vector2(-1.5, 12.75), Vector2(-2, 13.5), Vector2(-8.25, 19),
	Vector2(17, 5.5), Vector2(17, 6.5),
]
const WEAPONS := [
	Vector2(25.5, 13.5), Vector2(13.25, 0.5), Vector2(10.75, 13.5), Vector2(26, 9), Vector2(6, 20.5),
	Vector2(-10, 15.25), Vector2(-3, 5.5), Vector2(-6, 9),
]
const AMMO := [
	Vector2(19, 10), Vector2(18, 27), Vector2(8, 2.5), Vector2(0.75, 1.75), Vector2(15.5, 13.5),
	Vector2(1, 24.25), Vector2(1.5, 13.5), Vector2(-0.75, 17.75), Vector2(17.5, 22),
	Vector2(-1.5, 9.75), Vector2(-5.25, 19), Vector2(-5.5, 13.5),
]

static var enabled := OS.get_environment("OSSUSPEITOS_MAP") == "nocturna_salao"

static func rect(entry: Dictionary) -> Rect2:
	return Rect2(entry["min"], (entry["max"] as Vector2) - (entry["min"] as Vector2))

static func floor_height(x: float, z: float) -> float:
	var point := Vector2(x, z)
	var height := 0.0
	for landing in LANDINGS:
		if rect(landing).has_point(point):
			height = maxf(height, landing["y"])
	for ramp in RAMPS:
		var area := rect(ramp)
		if area.has_point(point):
			var axis := 0 if ramp["axis"] == "x" else 1
			var t := clampf(inverse_lerp(area.position[axis], area.end[axis], point[axis]), 0.0, 1.0)
			height = maxf(height, lerpf(ramp["y_at_min"], ramp["y_at_max"], t))
	return height

static func space_at(point: Vector2) -> Dictionary:
	for entry in SPACES:
		if rect(entry).has_point(point):
			return entry
	for door in DOORS:
		if rect(door).has_point(point):
			for entry in SPACES:
				if entry["id"] == door["room"]:
					return entry
	return {}

static func spawn_points() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point in SPAWNS:
		result.append(Vector3(point.x, MansionMap.BODY_CENTER_HEIGHT, point.y))
	return result

static func spawn_yaw_at(index: int) -> float:
	var point: Vector2 = SPAWNS[index]
	var space := space_at(point)
	var target := Vector2(8, 10)
	match space.get("id"):
		"biblioteca":
			target = Vector2(-0.25, 8)
		"cozinha":
			target = rect(space).get_center()
		"jantar":
			target = Vector2(8, 14.25)
		"hospedes":
			target = rect(space).get_center()
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
	for ramp in RAMPS:
		result.append(_box(ramp["id"], "furniture", rect(ramp), 0.0,
			maxf(ramp["y_at_min"], ramp["y_at_max"]), ramp["space"], true))
	for landing in LANDINGS:
		var height: float = landing["y"]
		result.append(_box(landing["id"], "furniture", rect(landing), height - 0.1, height, landing["space"], true))
	for index in HALL_RAILS.size():
		result.append(_box("corrimao_salao_%d" % index, "furniture", HALL_RAILS[index], 0.0, 4.5, "salao"))
	for index in SERVICE_RAILS.size():
		result.append(_box("corrimao_servico_%d" % index, "furniture", SERVICE_RAILS[index], 0.0, 4.5, "cozinha"))
	return result

static func _box(id: String, kind: String, area: Rect2, bottom: float, top: float, space: String,
		walkable := false) -> Dictionary:
	var center := area.get_center()
	var blocker := {"id": id, "kind": kind, "space": space,
		"center": Vector3(center.x, (bottom + top) * 0.5, center.y),
		"size": Vector3(area.size.x, top - bottom, area.size.y)}
	if walkable:
		blocker["walkable"] = true
	return blocker
