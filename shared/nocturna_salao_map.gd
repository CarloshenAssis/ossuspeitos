extends RefCounted
## Greybox do Salão Central, da Biblioteca, da Cozinha, da Sala de Jantar, do Quarto de Hóspedes, do Lavabo, do Banheiro de Mármore e do Jardim de Inverno. Todas as coordenadas de piso estão em XZ.

const CELL := MansionMap.CELL
const WALL_TOP := 7.0 + MansionMap.SLAB_THICKNESS
const MIN_X := -10.5
const GALLERY_FLOOR := 3.5
const GALLERY := {"id": "galeria", "name": "Galeria", "kind": "room", "min": Vector2(0, 0), "max": Vector2(16, 2), "floor": GALLERY_FLOOR, "ceiling": 7.0, "space": "salao", "y": GALLERY_FLOOR}
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
	# A extensão da asa leste dá largura útil à curva para a porta.
	GALLERY,
	{"id": "galeria_oeste", "name": "Galeria", "kind": "room", "min": Vector2(0, 2), "max": Vector2(4, 5), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "galeria_vao", "name": "Galeria", "kind": "room", "min": Vector2(6, 2), "max": Vector2(10, 5), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "galeria_leste", "name": "Galeria", "kind": "room", "min": Vector2(12, 2), "max": Vector2(16, 5), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "galeria_acesso", "name": "Galeria", "kind": "room", "min": Vector2(14.5, 5), "max": Vector2(16, 7), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "corredor_oeste", "name": "Corredor Superior", "kind": "corridor", "min": Vector2(16.5, 5), "max": Vector2(18, 10), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "corredor_leste", "name": "Corredor Superior", "kind": "corridor", "min": Vector2(18, 7), "max": Vector2(26.5, 10), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "patamar_servico", "name": "Patamar de Serviço", "kind": "corridor", "min": Vector2(24.5, 5), "max": Vector2(26.5, 7), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "quarto_norte", "name": "Quarto Norte", "kind": "room", "min": Vector2(MIN_X, 0), "max": Vector2(-0.5, 3), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "suite", "name": "Suíte", "kind": "room", "min": Vector2(MIN_X, 3.5), "max": Vector2(-0.5, 10), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "observatorio", "name": "Observatório", "kind": "room", "min": Vector2(27, 5), "max": Vector2(34, 8), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "musica", "name": "Sala de Música", "kind": "room", "min": Vector2(27, 8.5), "max": Vector2(34, 14), "floor": GALLERY_FLOOR, "ceiling": 7.0},
	{"id": "musica_acesso", "name": "Sala de Música", "kind": "room", "min": Vector2(27, 8), "max": Vector2(29, 8.5), "floor": GALLERY_FLOOR, "ceiling": 7.0},
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
	{"id": "porta_galeria_corredor", "room": "galeria_leste", "corridor": "corredor_oeste", "min": Vector2(16, 5), "max": Vector2(16.5, 7), "floor": GALLERY_FLOOR},
	{"id": "porta_quarto_norte", "room": "quarto_norte", "corridor": "galeria", "min": Vector2(-0.5, 0), "max": Vector2(0, 2), "floor": GALLERY_FLOOR},
	{"id": "porta_suite", "room": "suite", "corridor": "galeria_oeste", "min": Vector2(-0.5, 3), "max": Vector2(0, 5), "floor": GALLERY_FLOOR},
	{"id": "porta_observatorio", "room": "observatorio", "corridor": "patamar_servico", "min": Vector2(26.5, 5), "max": Vector2(27, 7), "floor": GALLERY_FLOOR},
	{"id": "porta_musica", "room": "musica", "corridor": "corredor_leste", "min": Vector2(26.5, 8), "max": Vector2(27, 10), "floor": GALLERY_FLOOR},
	{"id": "porta_suite_norte", "room": "suite", "corridor": "quarto_norte", "min": Vector2(-8, 3), "max": Vector2(-6, 3.5), "floor": GALLERY_FLOOR},
	{"id": "porta_musica_observatorio", "room": "musica", "corridor": "observatorio", "min": Vector2(29, 8), "max": Vector2(31, 8.5), "floor": GALLERY_FLOOR},
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
	{"id": "cama_norte", "space": "quarto_norte", "min": Vector2(MIN_X, 0.5), "max": Vector2(-8, 2.5), "height": 1.0, "floor": GALLERY_FLOOR},
	{"id": "guarda_norte", "space": "quarto_norte", "min": Vector2(MIN_X, 0), "max": Vector2(-9.5, 1.5), "height": 2.5, "floor": GALLERY_FLOOR},
	{"id": "cama_suite", "space": "suite", "min": Vector2(MIN_X, 6), "max": Vector2(-8, 9), "height": 1.0, "floor": GALLERY_FLOOR},
	{"id": "guarda_suite", "space": "suite", "min": Vector2(-1.5, 7), "max": Vector2(-0.5, 9.5), "height": 2.5, "floor": GALLERY_FLOOR},
	{"id": "pedestal_observatorio", "space": "observatorio", "min": Vector2(32, 6), "max": Vector2(33, 7), "height": 2.5, "floor": GALLERY_FLOOR},
	{"id": "piano", "space": "musica", "min": Vector2(28, 11.75), "max": Vector2(32, 13.75), "height": 1.0, "floor": GALLERY_FLOOR},
	{"id": "armario_musica", "space": "musica", "min": Vector2(33, 9), "max": Vector2(34, 12), "height": 2.5, "floor": GALLERY_FLOOR},
]
const RAMPS := [
	{"id": "lance_oeste", "space": "salao", "min": Vector2(4, 2), "max": Vector2(6, 6),
		"axis": "z", "y_at_min": GALLERY_FLOOR, "y_at_max": 0.0},
	{"id": "lance_leste", "space": "salao", "min": Vector2(10, 2), "max": Vector2(12, 6),
		"axis": "z", "y_at_min": GALLERY_FLOOR, "y_at_max": 0.0},
	{"id": "escada_servico", "space": "cozinha", "min": Vector2(18, 5), "max": Vector2(24.5, 7),
		"axis": "x", "y_at_min": 0.0, "y_at_max": GALLERY_FLOOR},
]
# O metro ao sul do espaço do patamar coincide com o corredor.
const SERVICE_LANDING := {"id": "patamar_servico", "space": "cozinha",
	"min": Vector2(24.5, 5), "max": Vector2(26.5, 8), "y": GALLERY_FLOOR}
static var LANDINGS: Array = _landings()

static func _landings() -> Array:
	var result := [SERVICE_LANDING]
	for entry in SPACES + DOORS:
		if space_floor(entry) > 0.0 and entry["id"] != SERVICE_LANDING["id"]:
			var id: String = entry["id"]
			result.append({"id": "piso_" + id if entry.has("room") else id, "space": entry.get("room", id),
				"min": entry["min"], "max": entry["max"], "y": GALLERY_FLOOR})
	return result
const HALL_RAILS := [
	Rect2(4, 2, 0.1, 4), Rect2(5.95, 2, 0.1, 4),
	Rect2(9.95, 2, 0.1, 4), Rect2(11.9, 2, 0.1, 4),
]
const SERVICE_RAILS := [
	Rect2(18, 6.9, 6.5, 0.1),
]
const UPPER_RAILS := [
	Rect2(0, 4.9, 4, 0.1), Rect2(6, 4.9, 4, 0.1), Rect2(12, 4.9, 2.5, 0.1),
	Rect2(14.5, 5, 0.1, 2), Rect2(14.5, 6.9, 1.5, 0.1),
	Rect2(16.5, 9.9, 10, 0.1), Rect2(17.9, 5, 0.1, 2),
]
const SPAWNS := [
	{"id": "spawn_salao", "space": "salao", "position": Vector2(1.8, 12.6), "floor": 0.0, "face": Vector2(8, 10)},
	{"id": "spawn_biblioteca", "space": "biblioteca", "position": Vector2(-2.0, 12.4), "floor": 0.0, "face": Vector2(-0.25, 8)},
	{"id": "spawn_jantar", "space": "jantar", "position": Vector2(7.2, 21.6), "floor": 0.0, "face": Vector2(8, 14.25)},
	{"id": "spawn_hospedes", "space": "hospedes", "position": Vector2(-6.5, 18.8), "floor": 0.0, "face": Vector2(-8.5, 14.25)},
	{"id": "spawn_galeria", "space": "galeria_leste", "position": Vector2(14.4, 3.4), "floor": GALLERY_FLOOR, "face": Vector2(8, 1)},
	{"id": "spawn_quarto_norte", "space": "quarto_norte", "position": Vector2(-2.2, 1.5), "floor": GALLERY_FLOOR, "face": Vector2(0, 1)},
	{"id": "spawn_suite", "space": "suite", "position": Vector2(-4.8, 4.6), "floor": GALLERY_FLOOR, "face": Vector2(0, 4)},
	{"id": "spawn_musica", "space": "musica", "position": Vector2(28.6, 9.4), "floor": GALLERY_FLOOR, "face": Vector2(30, 11)},
]
const PICKUPS := [
	{"id": "weapon_0", "type": "weapon", "weapon_id": "hunting_rifle", "space": "salao", "position": Vector2(10.8, 12.8), "floor": 0.0},
	{"id": "weapon_1", "type": "weapon", "weapon_id": "hunting_rifle", "space": "galeria", "position": Vector2(2.0, 0.8), "floor": GALLERY_FLOOR},
	{"id": "weapon_2", "type": "weapon", "weapon_id": "hunting_rifle", "space": "jantar", "position": Vector2(7.5, 16.2), "floor": 0.0},
	{"id": "weapon_3", "type": "weapon", "weapon_id": "hunting_rifle", "space": "cozinha", "position": Vector2(25.2, 13.0), "floor": 0.0},
	{"id": "weapon_4", "type": "weapon", "weapon_id": "aug", "space": "biblioteca", "position": Vector2(-8.5, 8.0), "floor": 0.0},
	{"id": "weapon_5", "type": "weapon", "weapon_id": "aug", "space": "galeria", "position": Vector2(11.4, 0.6), "floor": GALLERY_FLOOR},
	{"id": "weapon_6", "type": "weapon", "weapon_id": "aug", "space": "observatorio", "position": Vector2(33.4, 5.6), "floor": GALLERY_FLOOR},
	{"id": "weapon_7", "type": "weapon", "weapon_id": "aug", "space": "salao", "position": Vector2(6.2, 0.6), "floor": 0.0},
	{"id": "weapon_8", "type": "weapon", "weapon_id": "common_pistol", "space": "hospedes", "position": Vector2(-9.8, 16.0), "floor": 0.0},
	{"id": "weapon_9", "type": "weapon", "weapon_id": "common_pistol", "space": "jardim_inverno", "position": Vector2(17.5, 27.2), "floor": 0.0},
	{"id": "weapon_10", "type": "weapon", "weapon_id": "common_pistol", "space": "suite", "position": Vector2(-8.8, 4.8), "floor": GALLERY_FLOOR},
	{"id": "weapon_11", "type": "weapon", "weapon_id": "common_pistol", "space": "jantar", "position": Vector2(12.2, 18.7), "floor": 0.0},
	{"id": "ammo_0", "type": "ammo", "space": "lavabo", "position": Vector2(-0.3, 18.7), "floor": 0.0},
	{"id": "ammo_1", "type": "ammo", "space": "banheiro_marmore", "position": Vector2(-3.3, 25.2), "floor": 0.0},
	{"id": "ammo_2", "type": "ammo", "space": "jardim_inverno", "position": Vector2(11.2, 24.2), "floor": 0.0},
	{"id": "ammo_3", "type": "ammo", "space": "salao", "position": Vector2(14.7, 0.7), "floor": 0.0},
	{"id": "ammo_4", "type": "ammo", "space": "corredor_oeste", "position": Vector2(17.2, 8.2), "floor": GALLERY_FLOOR},
	{"id": "ammo_5", "type": "ammo", "space": "galeria_vao", "position": Vector2(8.7, 4.2), "floor": GALLERY_FLOOR},
	{"id": "ammo_6", "type": "ammo", "space": "jantar", "position": Vector2(17.7, 18.2), "floor": 0.0},
	{"id": "ammo_7", "type": "ammo", "space": "salao", "position": Vector2(2.2, 8.7), "floor": 0.0},
	{"id": "ammo_8", "type": "ammo", "space": "quarto_norte", "position": Vector2(-5.3, 0.7), "floor": GALLERY_FLOOR},
	{"id": "ammo_9", "type": "ammo", "space": "corredor_leste", "position": Vector2(22.2, 9.2), "floor": GALLERY_FLOOR},
	{"id": "ammo_10", "type": "ammo", "space": "jardim_acesso", "position": Vector2(0.2, 28.2), "floor": 0.0},
	{"id": "ammo_11", "type": "ammo", "space": "jardim_inverno", "position": Vector2(7.3, 28.4), "floor": 0.0},
	{"id": "health_0", "type": "health", "space": "biblioteca", "position": Vector2(-5.5, 13.0), "floor": 0.0},
	{"id": "health_1", "type": "health", "space": "banheiro_marmore", "position": Vector2(4.0, 25.2), "floor": 0.0},
	{"id": "health_2", "type": "health", "space": "cozinha", "position": Vector2(25.2, 8.2), "floor": 0.0},
	{"id": "health_3", "type": "health", "space": "musica", "position": Vector2(32.5, 10.5), "floor": GALLERY_FLOOR},
	{"id": "health_4", "type": "health", "space": "suite", "position": Vector2(-3.0, 9.3), "floor": GALLERY_FLOOR},
]

static var enabled := OS.get_environment("OSSUSPEITOS_MAP") == "nocturna_salao"

static func rect(entry: Dictionary) -> Rect2:
	return Rect2(entry["min"], (entry["max"] as Vector2) - (entry["min"] as Vector2))

static func space_floor(entry: Dictionary) -> float:
	return float(entry.get("floor", 0.0))

static func floor_height(x: float, z: float) -> float:
	return walk_height(x, z, GALLERY_FLOOR + MansionMap.BODY_CENTER_HEIGHT)

static func walk_height(x: float, z: float, body_y: float) -> float:
	var point := Vector2(x, z)
	for ramp in RAMPS:
		var area := rect(ramp)
		if area.has_point(point):
			var axis := 0 if ramp["axis"] == "x" else 1
			var t := inverse_lerp(area.position[axis], area.end[axis], point[axis])
			return lerpf(ramp["y_at_min"], ramp["y_at_max"], t)
	if body_y - MansionMap.BODY_CENTER_HEIGHT > GALLERY_FLOOR * 0.5:
		for landing in LANDINGS:
			if rect(landing).has_point(point):
				return GALLERY_FLOOR
	return 0.0

static func space_at(point: Vector2, y: float = 0.0) -> Dictionary:
	var result := {}
	for entry in SPACES:
		var floor_y := space_floor(entry)
		if floor_y <= y and y <= float(entry["ceiling"]) and rect(entry).has_point(point):
			if result.is_empty() or floor_y > space_floor(result):
				result = entry
	if not result.is_empty():
		return result
	for door in DOORS:
		if y >= space_floor(door) and rect(door).has_point(point):
			for entry in SPACES:
				if entry["id"] == door["room"] and y <= float(entry["ceiling"]):
					return entry
	return {}

static func pickups() -> Array:
	return PICKUPS

static func pickups_of_type(kind: String) -> Array:
	return PICKUPS.filter(func(entry): return str(entry["type"]) == kind)

static func weapon_id_of(pickup_id: String) -> String:
	for entry in PICKUPS:
		if str(entry["id"]) == pickup_id and str(entry["type"]) == "weapon":
			return str(entry.get("weapon_id", "common_pistol"))
	return "common_pistol"

static func item_floor(entry: Dictionary) -> float:
	return float(entry.get("floor", 0.0))

static func item_point(entry: Dictionary) -> Vector2:
	return entry["position"]

static func item_position(entry: Dictionary, height: float) -> Vector3:
	var point: Vector2 = entry["position"]
	return Vector3(point.x, height + item_floor(entry), point.y)

static func spawn_points() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for entry in SPAWNS:
		result.append(item_position(entry, MansionMap.BODY_CENTER_HEIGHT))
	return result

static func spawn_yaw_at(index: int) -> float:
	var entry: Dictionary = SPAWNS[index]
	var from: Vector2 = entry["position"]
	var to: Vector2 = entry["face"]
	return atan2(-(to.x - from.x), -(to.y - from.y))

static func pickup_positions() -> Array:
	var result: Array = []
	for entry in PICKUPS:
		result.append(item_position(entry, MansionMap.PICKUP_HEIGHT))
	return result

static func _cells(entries: Array, floor_y: float) -> Dictionary:
	var cells := {}
	for entry in entries:
		if space_floor(entry) != floor_y:
			continue
		var area := rect(entry)
		var first := Vector2i(area.position / CELL)
		var end := Vector2i(area.end / CELL)
		for z in range(first.y, end.y):
			for x in range(first.x, end.x):
				cells[Vector2i(x, z)] = true
	return cells

static func _wall_cells(floor_cells: Dictionary) -> Dictionary:
	var wall_cells := {}
	for cell: Vector2i in floor_cells:
		for z in range(-1, 2):
			for x in range(-1, 2):
				var neighbor := cell + Vector2i(x, z)
				if not floor_cells.has(neighbor):
					wall_cells[neighbor] = true

	return wall_cells

static func _append_walls(result: Array, wall_cells: Dictionary, bottom: float, top: float, prefix: String) -> void:
	var cells := wall_cells.keys()
	cells.sort()
	for cell: Vector2i in cells:
		if wall_cells.has(cell - Vector2i(0, 1)):
			continue
		var length := 1
		while wall_cells.has(cell + Vector2i(0, length)):
			length += 1
		var wall := Rect2(Vector2(cell) * CELL, Vector2(CELL, length * CELL))
		result.append(_box("%s_x%d_z%d" % [prefix, cell.x, cell.y], "wall", wall, bottom, top, ""))

static func blockers() -> Array:
	var ground := _cells(SPACES + DOORS, 0.0)
	var ground_walls := _wall_cells(ground)
	var upper := _cells(SPACES + DOORS, GALLERY_FLOOR)
	var upper_walls := _wall_cells(upper)
	for cell in upper_walls.keys():
		if ground.has(cell) or ground_walls.has(cell):
			upper_walls.erase(cell)
	for cell in _cells(DOORS, GALLERY_FLOOR):
		ground_walls.erase(cell)
	# Onde o piso superior cruza uma parede térrea, mantenha só a parte sob a laje.
	var low_walls := {}
	for cell in ground_walls.keys():
		if upper.has(cell):
			low_walls[cell] = ground_walls[cell]
			ground_walls.erase(cell)
	var result: Array = []
	_append_walls(result, low_walls, 0.0, GALLERY_FLOOR, "wall_ate_galeria")
	_append_walls(result, ground_walls, 0.0, WALL_TOP, "wall")
	_append_walls(result, upper_walls, GALLERY_FLOOR, WALL_TOP, "wall_superior")
	# O piso da Biblioteca suprime a parede gerada no limite sul da Suíte.
	result.append(_box("parede_suite_sul", "wall", Rect2(MIN_X, 10, 10, 0.5), GALLERY_FLOOR, WALL_TOP, "suite"))
	for door in DOORS:
		var floor_y := space_floor(door)
		if floor_y > 0.0:
			result.append(_box("base_" + door["id"], "wall", rect(door), 0.0, floor_y, door["room"]))
		result.append(_box(door["id"], "lintel", rect(door), floor_y + MansionMap.DOOR_HEIGHT, WALL_TOP, door["room"]))
	for entry in SPACES:
		if entry["id"] in ["cozinha", "biblioteca"]:
			continue
		var ceiling: float = entry["ceiling"]
		var area := rect(entry).grow(CELL * 0.5) if space_floor(entry) == 0.0 else rect(entry)
		result.append(_box("teto_" + entry["id"], "ceiling", area, ceiling,
			ceiling + MansionMap.SLAB_THICKNESS, entry["id"]))
	result.append(_box("teto_cozinha", "ceiling", Rect2(16.5, 10, 10, 4), 3.5, 3.5 + MansionMap.SLAB_THICKNESS, "cozinha"))
	result.append(_box("teto_vao_cozinha", "ceiling", Rect2(16.5, 5, 10, 5), 7.0, WALL_TOP, "cozinha"))
	result.append(_box("teto_biblioteca", "ceiling", Rect2(MIN_X, 10, 10, 4), GALLERY_FLOOR,
		GALLERY_FLOOR + MansionMap.SLAB_THICKNESS, "biblioteca"))
	result.append(_box("teto_vao_biblioteca", "ceiling", Rect2(MIN_X, 5, 10, 5), 7.0, WALL_TOP, "biblioteca"))
	for item in FURNITURE:
		var bottom: float = item.get("floor", 0.0)
		result.append(_box(item["id"], "furniture", rect(item), bottom, bottom + item["height"], item.get("space", "salao")))
	for ramp in RAMPS:
		result.append(_box(ramp["id"], "furniture", rect(ramp), 0.0,
			maxf(ramp["y_at_min"], ramp["y_at_max"]), ramp["space"], true))
	for landing in LANDINGS:
		result.append(_box(landing["id"], "furniture", rect(landing), GALLERY_FLOOR - 0.1,
			GALLERY_FLOOR, landing["space"], true))
	for index in UPPER_RAILS.size():
		result.append(_box("corrimao_superior_%d" % index, "furniture", UPPER_RAILS[index], GALLERY_FLOOR, 4.5, ""))
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
