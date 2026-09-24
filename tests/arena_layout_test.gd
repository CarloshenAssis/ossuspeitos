extends SceneTree

## Integridade e jogabilidade da mansão (`MansionMap`), sempre pelas mesmas
## funções que o servidor usa: `ArenaRules` (tiro e colisão), `MovementRules`
## (movimento integrado passo a passo) e `CombatAuthority` (disparo oficial).
##
## Cobre: nove cômodos e conexões da planta aprovada; vãos, paredes, vergas,
## tetos e fechamento externo; a cápsula real atravessando cada vão e
## percorrendo todos os corredores; tiros passando pelos vãos e parando em
## parede, batente, verga, piso, teto e móvel; spawns e pickups; tempos de
## percurso; e a correspondência exata entre meshes do cliente e volumes
## oficiais.

const GRID_STEP := 0.25
const EPSILON := 0.0001
const ROOM_NAMES := ["Escritório", "Biblioteca", "Galeria de Retratos", "Salão Central", "Cozinha",
	"Sala de Jantar", "Quarto do Fundo", "Quarto de Hóspedes", "Banheiro"]
## Conexões da planta aprovada, entre cômodos, por corredores (sem atravessar
## outro cômodo). A ala direita é uma árvore: cada quarto tem entrada própria.
const EXPECTED_ROOM_LINKS := [
	["escritorio", "biblioteca"], ["escritorio", "galeria"], ["escritorio", "salao"], ["galeria", "salao"],
	["biblioteca", "salao"], ["biblioteca", "jantar"], ["salao", "cozinha"], ["salao", "jantar"],
	["galeria", "cozinha"], ["jantar", "cozinha"],
	["jantar", "quarto_fundo"], ["jantar", "quarto_hospedes"], ["jantar", "banheiro"],
	["cozinha", "quarto_fundo"], ["cozinha", "quarto_hospedes"], ["cozinha", "banheiro"],
	["quarto_fundo", "quarto_hospedes"], ["quarto_fundo", "banheiro"], ["quarto_hospedes", "banheiro"],
]
const CORE_ROOMS := ["escritorio", "biblioteca", "galeria", "salao", "cozinha", "jantar"]
const WING_ROOMS := ["quarto_fundo", "quarto_hospedes", "banheiro"]

var failures := 0
var checks := 0
var _free_cells := PackedByteArray()
var _grid_size := Vector2i.ZERO
var _client_view: ArenaView
var _finished := false
var _report: Array = []

func _initialize() -> void:
	_build_free_grid()
	_test_nine_rooms_and_ids()
	_test_spaces_doors_and_junctions()
	_test_room_graph_matches_the_plan()
	_test_blocker_data()
	_test_house_is_sealed()
	_test_heights_and_clearances()
	_test_spawns()
	_test_spawns_have_no_line_of_sight()
	_test_pickups()
	_test_everything_is_reachable()
	_test_core_circuit_survives_any_sealed_corridor()
	_test_capsule_crosses_every_door()
	_test_door_effective_width()
	_test_tour_through_every_corridor()
	_test_movement_collides_with_walls_and_furniture()
	_test_shots_through_openings()
	_test_shots_blocked_by_geometry()
	_test_official_fire_uses_the_mansion()
	_test_travel_times()
	_test_combat_test_lanes()
	_test_zones_orient_players()
	_client_view = ArenaView.new()
	root.add_child(_client_view)

func _process(_delta: float) -> bool:
	if _finished:
		return false
	_finished = true
	_test_client_meshes_match_official_blockers()
	for line in _report:
		print(line)
	if failures > 0:
		push_error("ARENA_LAYOUT_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return false
	print("ARENA_LAYOUT_TEST_OK checks=%d blockers=%d spawns=%d pickups=%d rooms=%d" % [
		checks, ArenaRules.BLOCKERS.size(), MovementRules.SPAWN_POINTS.size(), ArenaRules.PICKUP_POSITIONS.size(), MansionMap.rooms().size()])
	quit(0)
	return false

# --- Definição -----------------------------------------------------------------

func _test_nine_rooms_and_ids() -> void:
	var names: Array = []
	for room in MansionMap.rooms():
		names.append(str(room["name"]))
	names.sort()
	var expected := ROOM_NAMES.duplicate()
	expected.sort()
	_expect(names == expected, "exactly the nine approved rooms (%s)" % str(names))
	var ids := {}
	for list in [MansionMap.SPACES, MansionMap.DOORS, MansionMap.JUNCTIONS, MansionMap.FURNITURE, MansionMap.SPAWNS, MansionMap.PICKUPS]:
		for entry in list:
			var id := str(entry["id"])
			_expect(not ids.has(id), "map id %s is unique" % id)
			ids[id] = true
	for blocker in ArenaRules.BLOCKERS:
		var id := str(blocker["id"])
		_expect(not ids.has("blocker:" + id), "blocker id %s is unique" % id)
		ids["blocker:" + id] = true
	_expect(absf(MansionMap.BODY_CENTER_HEIGHT - MovementRules.PLAYER_HEIGHT) < EPSILON and absf(MansionMap.BODY_CENTER_HEIGHT - ArenaRules.BODY_CENTER_HEIGHT) < EPSILON,
		"map body height equals the official one")
	# Dimensões internas escolhidas (documentadas em docs/mansion-plan.md).
	var dims := {"salao": Vector2(10, 9), "escritorio": Vector2(6, 5), "biblioteca": Vector2(5, 8), "galeria": Vector2(9, 5),
		"cozinha": Vector2(7, 5), "jantar": Vector2(9, 5), "quarto_fundo": Vector2(5, 6), "quarto_hospedes": Vector2(5, 5), "banheiro": Vector2(3, 3.5)}
	for room_id in dims:
		_expect(MansionMap.space_rect(room_id).size.is_equal_approx(dims[room_id]), "%s has the planned inner size %s" % [room_id, str(dims[room_id])])

func _test_spaces_doors_and_junctions() -> void:
	for entry in MansionMap.SPACES:
		var rect := _rect_of(entry)
		_expect(rect.size.x > 0.0 and rect.size.y > 0.0, "space %s has an area" % entry["id"])
		_expect(_on_grid(rect.position) and _on_grid(rect.end), "space %s sits on the 0.5 m grid" % entry["id"])
		if str(entry["kind"]) == "corridor":
			_expect(minf(rect.size.x, rect.size.y) >= 2.0 - EPSILON and maxf(rect.size.x, rect.size.y) >= 2.0, "corridor %s is at least 2 m in both directions" % entry["id"])
		for other in MansionMap.SPACES:
			if str(other["id"]) <= str(entry["id"]):
				continue
			var overlap := rect.intersection(_rect_of(other))
			_expect(overlap.size.x < EPSILON or overlap.size.y < EPSILON, "spaces %s and %s do not overlap" % [entry["id"], other["id"]])
	for door in MansionMap.DOORS:
		var rect := Rect2(door["min"], (door["max"] as Vector2) - (door["min"] as Vector2))
		var room := _rect_of(MansionMap.space(str(door["room"])))
		var corridor := _rect_of(MansionMap.space(str(door["corridor"])))
		_expect(str(MansionMap.space(str(door["room"])).get("kind", "")) == "room", "door %s opens into a room" % door["id"])
		_expect(str(MansionMap.space(str(door["corridor"])).get("kind", "")) == "corridor", "door %s opens into a corridor" % door["id"])
		var depth := minf(rect.size.x, rect.size.y)
		var width := maxf(rect.size.x, rect.size.y)
		_expect(absf(depth - MansionMap.CELL) < EPSILON, "door %s crosses a single 0.5 m wall" % door["id"])
		_expect(width >= 1.6 - EPSILON and width <= 2.0 + EPSILON, "door %s has 1.6-2.0 m of free width (%.2f)" % [door["id"], width])
		_expect(_touches_along(rect, room, width) and _touches_along(rect, corridor, width), "door %s joins %s and %s over its whole width" % [door["id"], door["room"], door["corridor"]])
	for junction in MansionMap.JUNCTIONS:
		var a := MansionMap.space(str(junction["a"]))
		var b := MansionMap.space(str(junction["b"]))
		_expect(str(a["kind"]) == "corridor" and str(b["kind"]) == "corridor", "junction %s joins corridors" % junction["id"])
		_expect(_shared_edge(_rect_of(a), _rect_of(b)) >= 2.0 - EPSILON, "junction %s is an open edge of at least 2 m" % junction["id"])
		_expect(absf(float(a["ceiling"]) - float(b["ceiling"])) < EPSILON, "junction %s joins equal ceilings (no ledge)" % junction["id"])
	# Nenhum encontro aberto além dos declarados: dois espaços contíguos só se
	# ligam por junção declarada (cômodos só por porta).
	for entry in MansionMap.SPACES:
		for other in MansionMap.SPACES:
			if str(other["id"]) <= str(entry["id"]):
				continue
			if _shared_edge(_rect_of(entry), _rect_of(other)) > EPSILON:
				_expect(_declared_junction(str(entry["id"]), str(other["id"])), "contiguous spaces %s and %s are a declared junction" % [entry["id"], other["id"]])

func _test_room_graph_matches_the_plan() -> void:
	var graph := _space_graph()
	var links := {}
	for room in MansionMap.rooms():
		var start := str(room["id"])
		# Busca só por corredores a partir das portas do cômodo.
		var seen := {start: true}
		var frontier: Array = [start]
		while not frontier.is_empty():
			var current: String = frontier.pop_back()
			for next in graph.get(current, []):
				if seen.has(next):
					continue
				seen[next] = true
				if str(MansionMap.space(next)["kind"]) == "room":
					links[_pair(start, next)] = true
				else:
					frontier.append(next)
	var expected := {}
	for pair in EXPECTED_ROOM_LINKS:
		expected[_pair(pair[0], pair[1])] = true
	for key in expected:
		_expect(links.has(key), "the plan link %s exists" % key)
	for key in links:
		_expect(expected.has(key), "no link outside the plan (%s)" % key)
	# Ala direita: cada quarto tem uma única porta, ligada a um ramal próprio.
	for room_id in WING_ROOMS:
		var doors := MansionMap.DOORS.filter(func(door): return str(door["room"]) == room_id)
		_expect(doors.size() == 1, "%s has its own single entrance" % room_id)
	var ramals := {}
	for door in MansionMap.DOORS:
		if str(door["room"]) in WING_ROOMS:
			ramals[str(door["corridor"])] = true
	_expect(ramals.size() == 3, "the three wing rooms use three independent branches")
	# Salão: entradas norte, oeste, leste e sul.
	_expect(MansionMap.DOORS.filter(func(door): return str(door["room"]) == "salao").size() == 4, "the hall has north, west, east and south entrances")

func _test_blocker_data() -> void:
	var kinds := {"wall": 0, "lintel": 0, "ceiling": 0, "furniture": 0}
	var by_id := {}
	for blocker in ArenaRules.BLOCKERS:
		by_id[str(blocker["id"])] = blocker
	for blocker in ArenaRules.BLOCKERS:
		var id := str(blocker["id"])
		var kind := str(blocker["kind"])
		_expect(kinds.has(kind), "blocker %s has a known kind" % id)
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		var center: Vector3 = blocker["center"]
		var size: Vector3 = blocker["size"]
		_expect(size.x > 0.0 and size.y > 0.0 and size.z > 0.0, "blocker %s has a positive size" % id)
		var bottom := center.y - size.y * 0.5
		var on_floor := absf(bottom) < EPSILON
		var overhead := bottom >= ArenaRules.PLAYER_HIT_HEIGHT - EPSILON
		var table_top := id.ends_with("_tampo")
		# Nada flutua sem explicação visível: ou nasce no piso, ou fica acima de
		# qualquer corpo (verga, teto), ou é tampo sobre os próprios pés.
		_expect(on_floor or overhead or table_top, "blocker %s rests on the floor, is overhead or is a table top" % id)
		if table_top:
			var base := id.trim_suffix("_tampo")
			for leg in 4:
				var leg_id := "%s_pe%d" % [base, leg]
				_expect(by_id.has(leg_id), "table %s has leg %d" % [base, leg])
				if by_id.has(leg_id):
					var leg_box: Dictionary = by_id[leg_id]
					var leg_top := (leg_box["center"] as Vector3).y + (leg_box["size"] as Vector3).y * 0.5
					_expect(absf(leg_top - bottom) < EPSILON, "leg %d of %s reaches the top" % [leg, base])
					_expect(_inside_xz(leg_box, blocker), "leg %d of %s is under the top" % [leg, base])
		_expect(ArenaRules.blocks_movement(blocker) == (not overhead), "blocker %s blocks movement iff it reaches body height" % id)
	for kind in kinds:
		_expect(int(kinds[kind]) > 0, "the mansion has %s volumes" % kind)
	_expect(int(kinds["lintel"]) == MansionMap.DOORS.size(), "one lintel per door")
	_expect(int(kinds["ceiling"]) == MansionMap.SPACES.size(), "one ceiling per space")
	# Nenhum móvel invade um vão, e todo móvel fica no próprio cômodo.
	for item in MansionMap.FURNITURE:
		var rect := Rect2(item["min"], (item["max"] as Vector2) - (item["min"] as Vector2))
		var room := _rect_of(MansionMap.space(str(item["space"])))
		_expect(room.encloses(rect), "furniture %s stays inside %s" % [item["id"], item["space"]])
		for door in MansionMap.DOORS:
			var door_rect := Rect2(door["min"], (door["max"] as Vector2) - (door["min"] as Vector2)).grow(ArenaRules.PLAYER_HIT_RADIUS * 2.0)
			_expect(not door_rect.intersects(rect), "furniture %s leaves the approach of %s clear" % [item["id"], door["id"]])

## Nenhum tiro sai da casa: raios de muitos pontos do piso em muitas direções,
## inclusive para cima e para baixo, sempre param num volume ou no piso.
func _test_house_is_sealed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260924
	var escaped := 0
	var samples := 0
	for entry in MansionMap.SPACES:
		var rect := _rect_of(entry)
		for sample in 12:
			var origin := Vector3(rng.randf_range(rect.position.x + 0.1, rect.end.x - 0.1), rng.randf_range(0.2, float(entry["ceiling"]) - 0.1),
				rng.randf_range(rect.position.y + 0.1, rect.end.y - 0.1))
			for direction_index in 24:
				var direction := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
				samples += 1
				if ArenaRules.first_blocker_distance(origin, direction, 200.0) < 0.0:
					escaped += 1
	_expect(escaped == 0, "no ray escapes the house (%d of %d escaped)" % [escaped, samples])
	# Horizontais rasantes na altura do olho, de cada vão, para os quatro lados.
	for door in MansionMap.DOORS:
		var center := ((door["min"] as Vector2) + (door["max"] as Vector2)) * 0.5
		for direction in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
			_expect(ArenaRules.first_blocker_distance(Vector3(center.x, ArenaRules.OFFICIAL_EYE_Y, center.y), direction, 200.0) >= 0.0,
				"eye-level ray from %s towards %s stops inside the house" % [door["id"], str(direction)])
	_report.append("MANSION_SEAL rays=%d escaped=%d" % [samples, escaped])

func _test_heights_and_clearances() -> void:
	_expect(absf(ArenaRules.OFFICIAL_EYE_Y - (MovementRules.PLAYER_HEIGHT + ArenaRules.EYE_HEIGHT)) < EPSILON, "official eye is body centre plus eye offset")
	_expect(MansionMap.DOOR_HEIGHT >= ArenaRules.PLAYER_HIT_HEIGHT + 0.3, "doors clear the 2 m body with margin")
	_expect(MansionMap.DOOR_HEIGHT > ArenaRules.OFFICIAL_EYE_Y + 0.5, "door lintels are well above the eye")
	for entry in MansionMap.SPACES:
		var ceiling := float(entry["ceiling"])
		_expect(ceiling > MansionMap.DOOR_HEIGHT and ceiling < MansionMap.WALL_TOP, "space %s ceiling sits between the lintel and the wall top" % entry["id"])
	_expect(float(MansionMap.space("salao")["ceiling"]) >= 4.0, "the hall has the tall ceiling")
	_expect(MovementRules.MAX_COLLISION_STEP < ArenaRules.PLAYER_HIT_RADIUS * 2.0, "collision sub-step is shorter than the body diameter")
	# O corpo nunca invade verga ou teto: não barram movimento, mas também
	# nunca começam abaixo do topo do corpo.
	for blocker in ArenaRules.BLOCKERS:
		if str(blocker["kind"]) in ["lintel", "ceiling"]:
			var bottom := (blocker["center"] as Vector3).y - (blocker["size"] as Vector3).y * 0.5
			_expect(bottom >= ArenaRules.PLAYER_HIT_HEIGHT + 0.3, "%s starts above any body" % blocker["id"])

# --- Spawns e pickups ----------------------------------------------------------

func _test_spawns() -> void:
	var spawns := MovementRules.SPAWN_POINTS
	_expect(spawns.size() == RoundRules.MAX_PLAYERS, "one spawn per supported player (%d)" % RoundRules.MAX_PLAYERS)
	var rooms := {}
	for index in spawns.size():
		var spawn: Vector3 = spawns[index]
		var entry: Dictionary = MansionMap.SPAWNS[index]
		_expect(absf(spawn.y - MovementRules.PLAYER_HEIGHT) < EPSILON, "spawn %d at body height" % index)
		_expect(str(ArenaRules.zone_at(spawn).get("id", "")) == str(entry["space"]), "spawn %d lies in %s" % [index, entry["space"]])
		_expect(not ArenaRules.overlaps_blocker(spawn), "spawn %d is not inside walls or furniture" % index)
		_expect(_cell_free(spawn), "spawn %d lies on the reachable grid" % index)
		# Os testes multiprocesso movem cada cliente numa direção qualquer.
		for angle_index in 8:
			var offset := Vector3(0.0, 0.0, -0.5).rotated(Vector3.UP, angle_index * PI / 4.0)
			_expect(not ArenaRules.overlaps_blocker(spawn + offset), "spawn %d can step %s" % [index, str(offset)])
		var facing := MovementRules.aim_direction(MovementRules.spawn_yaw(spawn), 0.0)
		var eye := spawn + Vector3.UP * ArenaRules.EYE_HEIGHT
		_expect(ArenaRules.first_blocker_distance(eye, facing, 50.0) > 1.5, "spawn %d does not start with its face against a wall" % index)
		_expect(not rooms.has(str(entry["space"])), "spawn %d has its own room" % index)
		rooms[str(entry["space"])] = true
		for other in range(index + 1, spawns.size()):
			_expect(Vector2(spawn.x, spawn.z).distance_to(Vector2(spawns[other].x, spawns[other].z)) >= ArenaRules.PLAYER_HIT_RADIUS * 4.0,
				"spawns %d and %d do not overlap" % [index, other])
		for pickup_index in ArenaRules.PICKUP_POSITIONS.size():
			_expect(spawn.distance_to(ArenaRules.PICKUP_POSITIONS[pickup_index]) > InventoryAuthority.PICKUP_RANGE_METERS + 0.5,
				"spawn %d is not on top of pickup %d" % [index, pickup_index])
	# A autoridade oficial entrega os spawns na ordem e com o yaw dos dados.
	var world := AuthoritativeWorld.new()
	for index in spawns.size():
		var state := world.add_player(index + 1)
		_expect((state["position"] as Vector3).is_equal_approx(spawns[index]) and absf(float(state["yaw"]) - MansionMap.spawn_yaw_at(index)) < EPSILON,
			"player %d spawns at marker %d facing its door" % [index + 1, index])
	_expect(world.add_player(99).is_empty(), "a ninth player gets no spawn")

## Nenhum par de spawns se enxerga: o hitscan oficial, do olho de um spawn na
## direção do outro, para num volume antes.
func _test_spawns_have_no_line_of_sight() -> void:
	var spawns := MovementRules.SPAWN_POINTS
	var fixture := _combat_fixture(spawns.size())
	var world: AuthoritativeWorld = fixture["world"]
	var combat: CombatAuthority = fixture["combat"]
	for shooter_index in spawns.size():
		for target_index in spawns.size():
			if shooter_index == target_index:
				continue
			var shooter_eye: Vector3 = world.states[shooter_index + 1]["position"] + Vector3.UP * ArenaRules.EYE_HEIGHT
			var target_position: Vector3 = world.states[target_index + 1]["position"]
			for height in [-0.9, 0.0, 0.7]:
				var direction: Vector3 = (target_position + Vector3.UP * float(height) - shooter_eye).normalized()
				var hit: Dictionary = combat._raycast(shooter_index + 1, shooter_eye, direction, 200.0)
				_expect(int(hit.get("peer_id", 0)) == 0, "spawn %d cannot shoot spawn %d at round start (h=%.1f)" % [shooter_index, target_index, height])

func _test_pickups() -> void:
	_expect(ArenaRules.PICKUP_POSITIONS.size() == 8, "four weapons and four ammo boxes")
	var spaces := {}
	for index in MansionMap.PICKUPS.size():
		var entry: Dictionary = MansionMap.PICKUPS[index]
		_expect(str(entry["type"]) == ("weapon" if index < 4 else "ammo"), "pickup %d keeps the weapon/ammo index contract" % index)
		_expect(str(entry["id"]) == ("weapon_%d" % index if index < 4 else "ammo_%d" % (index - 4)), "pickup %d keeps its official id" % index)
		var pickup: Vector3 = ArenaRules.PICKUP_POSITIONS[index]
		_expect(absf(pickup.y - 0.25) < EPSILON, "pickup %d keeps the official height" % index)
		_expect(str(ArenaRules.zone_at(pickup).get("id", "")) == str(entry["space"]), "pickup %d lies in %s" % [index, entry["space"]])
		spaces[str(entry["space"])] = true
		# Longe da boca de uma porta: não entope a passagem nem vira gargalo.
		for door in MansionMap.DOORS:
			var center := ((door["min"] as Vector2) + (door["max"] as Vector2)) * 0.5
			_expect(Vector2(pickup.x, pickup.z).distance_to(center) > 1.5, "pickup %d is not in the doorway %s" % [index, door["id"]])
	_expect(spaces.size() == 8, "the eight pickups are spread over eight different spaces")
	# Nenhuma arma num cômodo de spawn de uma sala de quatro.
	for index in 4:
		for spawn_index in 4:
			_expect(str(MansionMap.PICKUPS[index]["space"]) != str(MansionMap.SPAWNS[spawn_index]["space"]), "weapon %d is not in the room of spawn %d" % [index, spawn_index])
	var fixture := _combat_fixture(1)
	var world: AuthoritativeWorld = fixture["world"]
	var combat: CombatAuthority = fixture["combat"]
	var sequence := 0
	for index in ArenaRules.PICKUP_POSITIONS.size():
		var pickup: Vector3 = ArenaRules.PICKUP_POSITIONS[index]
		var standing := Vector3(pickup.x, MovementRules.PLAYER_HEIGHT, pickup.z)
		_expect(not ArenaRules.overlaps_blocker(standing), "a player can stand on pickup %d" % index)
		_expect(_cell_free(standing), "pickup %d lies on the reachable grid" % index)
		combat.inventory.clear_player(1)
		combat.inventory.register_player(1)
		if index >= 4:
			combat.inventory.inventories[1]["weapon_id"] = CombatAuthority.COMMON_WEAPON_ID
			combat.inventory.inventories[1]["equipped"] = true
		world.states[1]["position"] = standing
		sequence += 1
		var item_id := "weapon_%d" % index if index < 4 else "ammo_%d" % (index - 4)
		var result := combat.request_pickup(1, item_id, sequence, 1000 + sequence * 1000)
		_expect(bool(result.get("accepted", false)), "pickup %s is collectable in place (%s)" % [item_id, str(result)])

func _test_everything_is_reachable() -> void:
	var reached := _flood(MovementRules.SPAWN_POINTS[0], [])
	for index in MovementRules.SPAWN_POINTS.size():
		_expect(_reached(reached, MovementRules.SPAWN_POINTS[index]), "spawn %d reachable from spawn 0" % index)
	for index in ArenaRules.PICKUP_POSITIONS.size():
		_expect(_reached(reached, ArenaRules.PICKUP_POSITIONS[index]), "pickup %d reachable from spawn 0" % index)
	for entry in MansionMap.SPACES:
		_expect(_reached(reached, _free_point_in(str(entry["id"]))), "space %s reachable from spawn 0" % entry["id"])
	# Toda célula livre do corpo pertence a um espaço nomeado (não há bolsão
	# fora da planta, nem canto sem região).
	var orphan := 0
	for index in reached:
		if ArenaRules.zone_at(_cell_position(index)).is_empty():
			orphan += 1
	_expect(orphan == 0, "every reachable body position is inside a named space (%d orphans)" % orphan)

## Circuitos centrais e da esquerda: selar qualquer corredor (ou porta) deixa os
## seis cômodos do núcleo ligados entre si. A ala direita é uma árvore, como
## aprovado, e fica fora desta exigência.
func _test_core_circuit_survives_any_sealed_corridor() -> void:
	var seals: Array = []
	for entry in MansionMap.SPACES:
		if str(entry["kind"]) == "corridor" and not _wing_only(str(entry["id"])):
			seals.append({"id": entry["id"], "rect": _rect_of(entry)})
	for door in MansionMap.DOORS:
		if str(door["room"]) in CORE_ROOMS:
			seals.append({"id": door["id"], "rect": Rect2(door["min"], (door["max"] as Vector2) - (door["min"] as Vector2))})
	for seal in seals:
		var start := _free_point_in("salao")
		if (seal["rect"] as Rect2).has_point(Vector2(start.x, start.z)):
			continue
		var reached := _flood(start, [(seal["rect"] as Rect2).grow(0.3)])
		for room_id in CORE_ROOMS:
			_expect(_reached(reached, _free_point_in(room_id)), "%s stays reachable with %s sealed" % [room_id, seal["id"]])

# --- Movimento real ------------------------------------------------------------

## A cápsula oficial atravessa cada vão, nos dois sentidos, só com entrada de
## movimento integrada pelo servidor.
func _test_capsule_crosses_every_door() -> void:
	for door in MansionMap.DOORS:
		var rect := Rect2(door["min"], (door["max"] as Vector2) - (door["min"] as Vector2))
		var center := rect.get_center()
		var across := Vector2(1.0, 0.0) if rect.size.x < rect.size.y else Vector2(0.0, 1.0)
		var room_center := _rect_of(MansionMap.space(str(door["room"]))).get_center()
		var inward := across if (room_center - center).dot(across) > 0.0 else -across
		var outside := center - inward * 1.6
		var inside := center + inward * 1.6
		for pair in [[outside, inside], [inside, outside]]:
			var from: Vector2 = pair[0]
			var to: Vector2 = pair[1]
			var state := _moving_state(Vector3(from.x, 1.0, from.y), Vector3(to.x, 1.0, to.y))
			var ok := _drive(state, [Vector3(to.x, 1.0, to.y)], 4.0)
			_expect(ok, "the capsule crosses %s from %s to %s (ended at %s)" % [door["id"], str(from), str(to), str(state["position"])])

## Largura efetiva: centrado ou deslocado até a folga do corpo, passa; além
## disso, o batente segura o corpo.
func _test_door_effective_width() -> void:
	for door in MansionMap.DOORS:
		var rect := Rect2(door["min"], (door["max"] as Vector2) - (door["min"] as Vector2))
		var center := rect.get_center()
		var across := Vector2(1.0, 0.0) if rect.size.x < rect.size.y else Vector2(0.0, 1.0)
		var along := Vector2(across.y, across.x)
		var half_width := maxf(rect.size.x, rect.size.y) * 0.5
		var clearance := half_width - ArenaRules.PLAYER_HIT_RADIUS
		_expect(clearance >= 0.5, "door %s leaves at least 0.5 m of lateral slack per side (%.2f)" % [door["id"], clearance])
		for side in [-1.0, 1.0]:
			var offset: Vector2 = along * side * (clearance - 0.05)
			var from: Vector2 = center + offset - across * 1.2
			var to: Vector2 = center + offset + across * 1.2
			var resolved := MovementRules.resolve_step(Vector3(from.x, 1.0, from.y), Vector3(to.x - from.x, 0.0, to.y - from.y))
			_expect(not bool(resolved["blocked_x"]) and not bool(resolved["blocked_z"]), "door %s passes a body offset %.2f m" % [door["id"], clearance - 0.05])
			var blocked_offset: Vector2 = along * side * (clearance + 0.1)
			var blocked_from: Vector2 = center + blocked_offset - across * 1.2
			var blocked_to: Vector2 = center + blocked_offset + across * 1.2
			# Vão rente a uma parede contínua (banheiro): do lado sem batente o corpo
			# já nem cabe na aproximação; do lado com batente, ele segura o corpo.
			if ArenaRules.overlaps_blocker(Vector3(blocked_from.x, 1.0, blocked_from.y)):
				_expect(_flush_side(rect, along * side), "door %s is flush with a continuous wall on that side" % door["id"])
				continue
			resolved = MovementRules.resolve_step(Vector3(blocked_from.x, 1.0, blocked_from.y), Vector3(blocked_to.x - blocked_from.x, 0.0, blocked_to.y - blocked_from.y))
			_expect(bool(resolved["blocked_x"]) or bool(resolved["blocked_z"]), "the jamb of %s stops a body offset %.2f m" % [door["id"], clearance + 0.1])

## Um percurso único, integrado passo a passo, que entra em todos os espaços
## (todos os corredores, os nove cômodos e os três ramais da ala direita).
func _test_tour_through_every_corridor() -> void:
	var order := ["escritorio", "corredor_norte", "corredor_norte_salao", "salao", "corredor_biblioteca_salao", "biblioteca",
		"corredor_escritorio_biblioteca", "escritorio", "corredor_norte", "galeria", "corredor_galeria_cozinha", "cozinha",
		"corredor_salao_cozinha", "salao", "corredor_salao_jantar", "jantar", "corredor_oeste_jantar", "corredor_oeste_sul",
		"biblioteca", "corredor_oeste_sul", "corredor_oeste_jantar", "jantar", "corredor_jantar_leste", "corredor_cozinha_sul",
		"cozinha", "corredor_cozinha_sul", "ala_leste", "ramal_fundo", "quarto_fundo", "ramal_fundo", "ala_leste",
		"ramal_hospedes", "quarto_hospedes", "ramal_hospedes", "ala_leste", "ramal_banheiro", "banheiro"]
	var visited := {}
	for entry in MansionMap.SPACES:
		visited[str(entry["id"])] = false
	var position := MovementRules.SPAWN_POINTS[0]
	var total_time := 0.0
	var total_distance := 0.0
	for space_id in order:
		var goal := _free_point_in(space_id)
		var path := _path(position, goal)
		_expect(not path.is_empty(), "a path exists to %s" % space_id)
		if path.is_empty():
			return
		var state := _moving_state(position, path[0])
		var start_time := float(state["time"])
		var ok := _drive(state, path, 60.0, visited)
		_expect(ok, "the capsule walks into %s (stopped at %s)" % [space_id, str(state["position"])])
		total_time += float(state["time"]) - start_time
		total_distance += float(state["distance"])
		position = state["position"]
		if not ok:
			return
	for space_id in visited:
		_expect(bool(visited[space_id]), "the tour walked through %s" % space_id)
	_report.append("MANSION_TOUR spaces=%d distance=%.1fm time=%.1fs" % [visited.size(), total_distance, total_time])

func _test_movement_collides_with_walls_and_furniture() -> void:
	# Correndo contra a parede norte do Salão (fora da porta): para na face.
	var wall_face := 7.5
	var state := _moving_state(Vector3(10.0, 1.0, 9.0), Vector3(10.0, 1.0, 0.0))
	_run_forward(state, 120)
	var position: Vector3 = state["position"]
	_expect(position.z >= wall_face + ArenaRules.PLAYER_HIT_RADIUS - 0.001 and position.z <= wall_face + ArenaRules.PLAYER_HIT_RADIUS + 0.2,
		"the hall north wall stops the body at its face (z=%.3f)" % position.z)
	_expect(absf((state["velocity"] as Vector3).z) < EPSILON, "blocked axis loses its velocity")
	# Diagonal contra a mesma parede: desliza no eixo livre.
	state = _moving_state(Vector3(9.5, 1.0, 8.2), Vector3(12.0, 1.0, 5.7))
	_run_forward(state, 30)
	position = state["position"]
	_expect(position.x > 10.3 and position.z >= wall_face + ArenaRules.PLAYER_HIT_RADIUS - 0.001, "a diagonal push slides along the wall (%s)" % str(position))
	# Canto interno (noroeste do Salão): para nos dois eixos, sem atravessar.
	state = _moving_state(Vector3(9.8, 1.0, 8.8), Vector3(8.0, 1.0, 7.0))
	_run_forward(state, 120)
	position = state["position"]
	_expect(position.x >= 8.5 + ArenaRules.PLAYER_HIT_RADIUS - 0.001 and position.z >= 7.5 + ArenaRules.PLAYER_HIT_RADIUS - 0.001, "an inner corner holds the body (%s)" % str(position))
	# Nenhum passo grande atravessa parede.
	var resolved := MovementRules.resolve_step(Vector3(10.0, 1.0, 9.0), Vector3(0.0, 0.0, -6.0))
	_expect(bool(resolved["blocked_z"]) and (resolved["position"] as Vector3).z >= wall_face + ArenaRules.PLAYER_HIT_RADIUS - 0.001, "a single large step cannot tunnel through a wall")
	# Móveis: mesa do jantar (pelo tampo), cama, bancada e estante barram.
	for probe in [["mesa_jantar", Vector3(13.5, 1.0, 20.2), Vector3(0, 0, 3)], ["cama_fundo", Vector3(32.1, 1.0, 25.0), Vector3(0, 0, 3)],
			["bancada", Vector3(26.5, 1.0, 11.5), Vector3(3, 0, 0)], ["estante_biblioteca_oeste_norte", Vector3(2.5, 1.0, 10.0), Vector3(-3, 0, 0)], ["mesa_leitura", Vector3(3.0, 1.0, 15.0), Vector3(0, 0, -3)],
			["pedestal", Vector3(13.5, 1.0, 14.2), Vector3(0, 0, -3)]]:
		resolved = MovementRules.resolve_step(probe[1], probe[2])
		_expect(bool(resolved["blocked_x"]) or bool(resolved["blocked_z"]), "%s blocks the body" % probe[0])
	# Quem foi teleportado para dentro de um volume não fica preso.
	resolved = MovementRules.resolve_step(Vector3(13.5, 1.0, 12.0), Vector3(0.0, 0.0, 1.0))
	_expect(not bool(resolved["blocked_z"]), "a body inside furniture can walk out")
	# Limite de segurança do mapa.
	resolved = MovementRules.resolve_step(Vector3(MovementRules.MAP_MAX_X - 0.1, 1.0, 50.0), Vector3(5.0, 0.0, 0.0))
	_expect((resolved["position"] as Vector3).x <= MovementRules.MAP_MAX_X + EPSILON, "the safety bound clamps a corrupted state")

# --- Tiros ---------------------------------------------------------------------

func _test_shots_through_openings() -> void:
	# Pelo centro de cada vão, na altura do olho, do corredor até dentro do
	# cômodo: o raio passa e alcança um corpo do outro lado.
	for door in MansionMap.DOORS:
		var rect := Rect2(door["min"], (door["max"] as Vector2) - (door["min"] as Vector2))
		var center := rect.get_center()
		var across := Vector2(1.0, 0.0) if rect.size.x < rect.size.y else Vector2(0.0, 1.0)
		var room_center := _rect_of(MansionMap.space(str(door["room"]))).get_center()
		var inward := across if (room_center - center).dot(across) > 0.0 else -across
		var shooter := center - inward * 1.2
		var target := center + inward * 1.4
		_expect(_lane_free(Vector3(shooter.x, 1.0, shooter.y), Vector3(target.x, 1.0, target.y)), "an eye-level shot passes through %s" % door["id"])
	# Ao longo do corredor norte, de ponta a ponta, e pela passagem até a galeria.
	_expect(_lane_free(Vector3(7.5, 1.0, 2.5), Vector3(19.0, 1.0, 2.5)), "the north corridor is an open shooting lane")
	_expect(_lane_free(Vector3(13.5, 1.0, 2.5), Vector3(13.5, 1.0, 6.0)), "the corridor branch towards the hall is open")

func _test_shots_blocked_by_geometry() -> void:
	var eye := ArenaRules.OFFICIAL_EYE_Y
	# Parede entre dois cômodos (Salão e Jantar fora do vão).
	_expect_first_hit(Vector3(10.0, eye, 15.5), Vector3.BACK, "wall", 16.5, "the hall south wall blocks a shot into the dining room")
	_expect(not _lane_free(Vector3(10.0, 1.0, 15.5), Vector3(10.0, 1.0, 20.3)), "no hit through the hall-dining wall")
	# Batente: mirando rente à lateral de fora do vão.
	var jamb := Vector3(12.25, eye, 15.5)
	_expect_first_hit(jamb, Vector3.BACK, "wall", 16.5, "the south door jamb blocks a shot beside the opening")
	# Verga: de dentro do Salão, subindo pelo vão sul.
	var up := MovementRules.aim_direction(PI, 0.6)
	var lintel_origin := Vector3(13.5, eye, 15.0)
	var lintel_hit := _first_hit(lintel_origin, up)
	_expect(str(lintel_hit.get("kind", "")) == "lintel" or str(lintel_hit.get("kind", "")) == "wall", "a rising shot through the south door hits the lintel/wall above it (%s)" % str(lintel_hit))
	_expect(lintel_hit.get("point", Vector3.ZERO).y >= MansionMap.DOOR_HEIGHT - 0.01, "that shot stops above the door height")
	# Teto: para cima em cada cômodo e corredor, a laje do próprio espaço.
	for entry in MansionMap.SPACES:
		var point := _free_point_in(str(entry["id"]))
		var hit := _first_hit(Vector3(point.x, eye, point.z), MovementRules.aim_direction(0.3, MovementRules.MAX_PITCH))
		_expect(str(hit.get("kind", "")) in ["ceiling", "wall", "lintel", "furniture"], "a steep upward shot in %s stops on the house (%s)" % [entry["id"], str(hit)])
		var straight := _first_hit(Vector3(point.x, eye, point.z), Vector3.UP)
		_expect(str(straight.get("kind", "")) == "ceiling" and absf(float(straight.get("distance", 0.0)) - (float(entry["ceiling"]) - eye)) < 0.01,
			"straight up in %s hits its own ceiling at %.1f m" % [entry["id"], float(entry["ceiling"])])
	# Piso: para baixo, a 45°.
	var down := _first_hit(Vector3(13.5, eye, 9.0), MovementRules.aim_direction(PI, -PI * 0.25))
	_expect(str(down.get("kind", "")) == "floor" and absf((down["point"] as Vector3).y) < 0.01, "a downward shot stops on the floor (%s)" % str(down))
	# Móveis: estante, pedestal e tampo da mesa bloqueiam; embaixo da mesa passa.
	_expect_first_hit(Vector3(2.5, eye, 10.0), Vector3.LEFT, "furniture", 1.0, "a bookshelf stops a shot")
	_expect_first_hit(Vector3(13.5, 1.0, 14.2), Vector3.FORWARD, "furniture", 12.5, "the pedestal stops a waist-level shot")
	var over_table := _first_hit(Vector3(13.5, eye, 20.2), MovementRules.aim_direction(PI, -0.5))
	_expect(str(over_table.get("kind", "")) == "furniture" and str(over_table.get("id", "")) == "mesa_jantar_tampo", "a downward shot onto the dining table hits its top (%s)" % str(over_table))
	var under_table := _first_hit(Vector3(12.0, 0.4, 20.0), Vector3.BACK)
	_expect(str(under_table.get("id", "")) != "mesa_jantar_tampo" and float(under_table.get("distance", 0.0)) > 3.0, "a shot under the dining table passes between the legs (%s)" % str(under_table))
	var eye_over_bed := _first_hit(Vector3(32.1, eye, 25.0), Vector3.BACK)
	_expect(str(eye_over_bed.get("kind", "")) == "wall", "an eye-level shot passes over the low bed (%s)" % str(eye_over_bed))

## O disparo oficial (`CombatAuthority.request_fire`) no mapa novo: acerta pelo
## vão, erra através da parede, e respeita teto e piso com pitch oficial.
func _test_official_fire_uses_the_mansion() -> void:
	var cases := [
		{"name": "through the south door", "shooter": Vector3(13.5, 1.0, 20.5), "target": Vector3(13.5, 1.0, 15.0), "yaw": 0.0, "pitch": 0.0, "hit": true},
		{"name": "through the hall-dining wall", "shooter": Vector3(10.0, 1.0, 20.3), "target": Vector3(10.0, 1.0, 15.5), "yaw": 0.0, "pitch": 0.0, "hit": false},
		{"name": "under a steep upward aim", "shooter": Vector3(12.0, 1.0, 15.5), "target": Vector3(12.0, 1.0, 10.0), "yaw": 0.0, "pitch": 1.2, "hit": false},
		{"name": "down into the floor", "shooter": Vector3(12.0, 1.0, 15.5), "target": Vector3(12.0, 1.0, 10.0), "yaw": 0.0, "pitch": -0.6, "hit": false},
		{"name": "level across the hall", "shooter": Vector3(12.0, 1.0, 15.5), "target": Vector3(12.0, 1.0, 10.0), "yaw": 0.0, "pitch": 0.0, "hit": true},
		{"name": "through a bookshelf", "shooter": Vector3(2.5, 1.0, 10.0), "target": Vector3(-1.0, 1.0, 10.0), "yaw": PI * 0.5, "pitch": 0.0, "hit": false},
	]
	for entry in cases:
		var fixture := _combat_fixture(2)
		var world: AuthoritativeWorld = fixture["world"]
		var combat: CombatAuthority = fixture["combat"]
		combat.inventory.inventories[1]["weapon_id"] = CombatAuthority.COMMON_WEAPON_ID
		combat.inventory.inventories[1]["equipped"] = true
		combat.inventory.inventories[1]["magazine"] = 6
		world.states[1]["position"] = entry["shooter"]
		world.states[1]["yaw"] = float(entry["yaw"])
		world.states[1]["pitch"] = float(entry["pitch"])
		world.states[2]["position"] = entry["target"]
		var eye: Vector3 = (entry["shooter"] as Vector3) + Vector3.UP * ArenaRules.EYE_HEIGHT
		var direction := MovementRules.aim_direction(float(entry["yaw"]), float(entry["pitch"]))
		var result := combat.request_fire(1, 1, eye, direction, 5000)
		_expect(bool(result.get("accepted", false)), "official fire %s is accepted (%s)" % [entry["name"], str(result)])
		var hit := int(result.get("hit_peer_id", 0)) == 2
		_expect(hit == bool(entry["hit"]), "official fire %s %s the target (%s)" % [entry["name"], "hits" if entry["hit"] else "misses", str(result)])
		_expect(int(combat.health.get(2, 0)) == (66 if entry["hit"] else 100), "official fire %s applies the right damage" % entry["name"])

# --- Percursos -----------------------------------------------------------------

## Distância percorrível (grade do corpo) de cada spawn até a arma e a munição
## mais próximas, e o tempo à velocidade oficial. Os quatro primeiros spawns
## (sala de quatro) ficam num intervalo estreito.
func _test_travel_times() -> void:
	var weapon_times: Array = []
	for index in MovementRules.SPAWN_POINTS.size():
		var distances := _distances_from(MovementRules.SPAWN_POINTS[index])
		var nearest_weapon := INF
		var nearest_ammo := INF
		for pickup_index in ArenaRules.PICKUP_POSITIONS.size():
			var distance := float(distances.get(_index_of(ArenaRules.PICKUP_POSITIONS[pickup_index]), INF))
			if pickup_index < 4:
				nearest_weapon = minf(nearest_weapon, distance)
			else:
				nearest_ammo = minf(nearest_ammo, distance)
		var weapon_time := nearest_weapon / MovementRules.MAX_SPEED
		_expect(weapon_time > 0.5 and weapon_time < 4.0, "spawn %d reaches a weapon in %.1f s" % [index, weapon_time])
		_expect(nearest_ammo / MovementRules.MAX_SPEED < 6.0, "spawn %d reaches ammo in %.1f s" % [index, nearest_ammo / MovementRules.MAX_SPEED])
		if index < 4:
			weapon_times.append(weapon_time)
		_report.append("MANSION_TRAVEL spawn=%s weapon=%.1fm/%.1fs ammo=%.1fm/%.1fs" % [MansionMap.SPAWNS[index]["id"], nearest_weapon, weapon_time, nearest_ammo, nearest_ammo / MovementRules.MAX_SPEED])
	var fastest: float = weapon_times.min()
	var slowest: float = weapon_times.max()
	_expect(slowest - fastest <= 1.5, "four-player spawns reach a weapon within 1.5 s of each other (%.1f-%.1f s)" % [fastest, slowest])
	# Maior percurso da casa (Escritório ao Quarto de Hóspedes).
	var longest := float(_distances_from(MovementRules.SPAWN_POINTS[0]).get(_index_of(MovementRules.SPAWN_POINTS[1]), INF))
	_report.append("MANSION_TRAVEL longest=escritorio->hospedes %.1fm/%.1fs" % [longest, longest / MovementRules.MAX_SPEED])
	_expect(longest / MovementRules.MAX_SPEED < 20.0, "the farthest spawns are less than 20 s apart")

## Faixas fixas usadas pelos testes de combate continuam válidas no mapa novo.
func _test_combat_test_lanes() -> void:
	_expect(_lane_free(CombatNetworkCoordinator.LANE_SHOOTER, CombatNetworkCoordinator.LANE_TARGET), "combat network lane is open")
	_expect(not _lane_free(CombatNetworkCoordinator.WALL_SHOOTER, CombatNetworkCoordinator.WALL_TARGET), "combat network wall lane is blocked")
	for position in [CombatNetworkCoordinator.LANE_SHOOTER, CombatNetworkCoordinator.LANE_TARGET, CombatNetworkCoordinator.WALL_SHOOTER,
			CombatNetworkCoordinator.WALL_TARGET] + CombatNetworkCoordinator.SAFE_POSITIONS:
		_expect(not ArenaRules.overlaps_blocker(position), "test position %s is free" % str(position))
	for safe in CombatNetworkCoordinator.SAFE_POSITIONS:
		_expect(not _lane_free(CombatNetworkCoordinator.LANE_SHOOTER, safe), "bystander %s is out of the shooter's reach" % str(safe))

func _test_zones_orient_players() -> void:
	_expect(ArenaRules.ZONES.size() == MansionMap.SPACES.size(), "one region per space")
	_expect(ArenaRules.zone_name_at(Vector3(13.5, 1.0, 12.0)) == "Salão Central", "the hall is named")
	_expect(ArenaRules.zone_name_at(Vector3(3.0, 1.0, 5.25)) == "Escritório", "a doorway belongs to its room")
	_expect(ArenaRules.zone_name_at(Vector3(100.0, 1.0, 100.0)).is_empty(), "outside the house has no region")

# --- Cliente -------------------------------------------------------------------

## Instancia a mansão do cliente e compara nó a nó com `ArenaRules.BLOCKERS`.
## Qualquer mesh que não seja volume oficial é piso (abaixo de y = 0) ou
## recurso de inspeção, oculto na apresentação normal.
func _test_client_meshes_match_official_blockers() -> void:
	var view := _client_view
	var by_id: Dictionary = {}
	for blocker in ArenaRules.BLOCKERS:
		by_id[str(blocker["id"])] = blocker
	var matched: Dictionary = {}
	var debug_nodes := 0
	for child in view.get_children():
		var decor := str(child.get_meta("arena_decor", ""))
		if decor == "debug":
			debug_nodes += 1
			_expect(not (child as Node3D).visible, "debug overlay %s is hidden in the normal presentation" % child.name)
			continue
		if child is MeshInstance3D:
			var mesh_node := child as MeshInstance3D
			if mesh_node.has_meta("arena_blocker_id"):
				var id := str(mesh_node.get_meta("arena_blocker_id"))
				_expect(by_id.has(id), "client mesh %s is an official blocker" % id)
				_expect(not matched.has(id), "official blocker %s has a single mesh" % id)
				matched[id] = true
				if by_id.has(id):
					var box := mesh_node.mesh as BoxMesh
					_expect(box != null and box.size.is_equal_approx(by_id[id]["size"]), "mesh %s size equals the official box" % id)
					_expect(mesh_node.position.is_equal_approx(by_id[id]["center"]), "mesh %s position equals the official box" % id)
					_expect(mesh_node.rotation.is_zero_approx() and mesh_node.scale.is_equal_approx(Vector3.ONE), "mesh %s is not rotated or scaled" % id)
					_expect(mesh_node.visible, "mesh %s is visible" % id)
			else:
				_expect(decor == "floor", "unlisted mesh %s is floor decor" % mesh_node.name)
				var aabb := mesh_node.get_aabb()
				var top := mesh_node.position.y + aabb.position.y + aabb.size.y
				_expect(top <= 0.0 + EPSILON, "floor decor %s stays under the official floor (top=%.3f)" % [mesh_node.name, top])
		elif child is Label3D:
			_expect(false, "label %s is not a debug overlay" % (child as Label3D).text)
	_expect(matched.size() == ArenaRules.BLOCKERS.size(), "every official blocker is rendered (%d/%d)" % [matched.size(), ArenaRules.BLOCKERS.size()])
	_expect(debug_nodes >= MansionMap.rooms().size(), "room names exist for inspection (%d debug nodes)" % debug_nodes)
	# Inspeção: liga nomes e recorta o teto só na apresentação.
	var before := ArenaRules.first_blocker_distance(Vector3(13.5, 1.7, 12.0), Vector3.UP, 50.0)
	view.set_debug_overlay(true)
	view.set_show_ceilings(false)
	var ceilings_hidden := true
	for child in view.get_children():
		if str(child.get_meta("arena_blocker_kind", "")) == "ceiling":
			ceilings_hidden = ceilings_hidden and not (child as Node3D).visible
		if str(child.get_meta("arena_decor", "")) == "debug":
			_expect((child as Node3D).visible, "debug overlay %s can be shown" % child.name)
	_expect(ceilings_hidden, "the ceiling cut hides every ceiling mesh")
	_expect(absf(ArenaRules.first_blocker_distance(Vector3(13.5, 1.7, 12.0), Vector3.UP, 50.0) - before) < EPSILON, "the ceiling cut never changes the official simulation")
	_expect(absf(view.camera.position.y - ArenaRules.EYE_HEIGHT) < EPSILON, "client camera sits at the official eye offset")
	# Fim de rodada e rodada nova: a mansão não é remontada e os pickups não
	# se duplicam (mesmos ids, uma mesh cada).
	var blocker_nodes_before := _count_blocker_nodes(view)
	for round_id in [1, 2, 3]:
		view.apply_pickups(_pickup_entries(round_id))
		view.apply_pickups([])
		view.apply_pickups(_pickup_entries(round_id))
	_expect(view.pickup_nodes.size() == 8, "three round resets keep exactly eight pickup nodes (%d)" % view.pickup_nodes.size())
	_expect(_count_blocker_nodes(view) == blocker_nodes_before and blocker_nodes_before == ArenaRules.BLOCKERS.size(), "round resets never rebuild or duplicate the mansion")
	view.free()

func _count_blocker_nodes(view: ArenaView) -> int:
	var count := 0
	for child in view.get_children():
		if child.has_meta("arena_blocker_id") and not child.is_queued_for_deletion():
			count += 1
	return count

func _pickup_entries(round_id: int) -> Array:
	var entries: Array = []
	for index in MansionMap.PICKUPS.size():
		var entry: Dictionary = MansionMap.PICKUPS[index]
		entries.append({"pickup_id": entry["id"], "type": entry["type"], "position": ArenaRules.PICKUP_POSITIONS[index], "available": true, "round_id": round_id})
	return entries

# --- Utilitários ---------------------------------------------------------------

func _combat_fixture(players: int) -> Dictionary:
	var rounds := RoundAuthority.new()
	var world := AuthoritativeWorld.new()
	var peers: Array = []
	for index in players:
		var peer_id := index + 1
		world.add_player(peer_id)
		peers.append(peer_id)
		rounds.participants[peer_id] = true
		rounds.alive[peer_id] = true
	rounds.state = RoundState.ACTIVE
	rounds.round_id = 1
	var combat := CombatAuthority.new(rounds, world)
	combat.begin_round(1, peers)
	return {"world": world, "combat": combat, "rounds": rounds}

## Primeiro contato de um raio: piso, volume oficial (com tipo e id) ou nada.
func _first_hit(origin: Vector3, direction: Vector3) -> Dictionary:
	var best := {"kind": "", "distance": INF}
	var floor_distance := ArenaRules.ray_floor(origin, direction, 200.0)
	if floor_distance >= 0.0:
		best = {"kind": "floor", "id": "floor", "distance": floor_distance}
	for blocker in ArenaRules.BLOCKERS:
		var distance := ArenaRules.ray_aabb(origin, direction, 200.0, blocker["center"], blocker["size"])
		if distance >= 0.0 and distance < float(best["distance"]):
			best = {"kind": str(blocker["kind"]), "id": str(blocker["id"]), "distance": distance}
	if best.has("id"):
		best["point"] = origin + direction * float(best["distance"])
	var official := ArenaRules.first_blocker_distance(origin, direction, 200.0)
	_expect((official < 0.0 and not best.has("id")) or absf(official - float(best["distance"])) < EPSILON, "helper agrees with the official raycast")
	return best

func _expect_first_hit(origin: Vector3, direction: Vector3, kind: String, face: float, description: String) -> void:
	var hit := _first_hit(origin, direction)
	var point: Vector3 = hit.get("point", Vector3.INF)
	var coordinate := point.x if absf(direction.x) > 0.5 else point.z
	_expect(str(hit.get("kind", "")) == kind and absf(coordinate - face) < 0.01, "%s (%s)" % [description, str(hit)])

func _lane_free(shooter: Vector3, target: Vector3) -> bool:
	var origin := shooter + Vector3.UP * ArenaRules.EYE_HEIGHT
	var direction := (target - shooter).normalized()
	var target_distance := ArenaRules.ray_player(origin, direction, 50.0, target)
	var blocker := ArenaRules.first_blocker_distance(origin, direction, 50.0)
	return target_distance >= 0.0 and (blocker < 0.0 or blocker > target_distance)

func _moving_state(position: Vector3, looking_at: Vector3) -> Dictionary:
	return {"position": position, "velocity": Vector3.ZERO, "yaw": _yaw_to(position, looking_at), "input": Vector2(0.0, -1.0),
		"last_input_msec": 0, "time": 0.0, "distance": 0.0}

func _yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))

func _run_forward(state: Dictionary, ticks: int) -> void:
	for tick in ticks:
		state["last_input_msec"] = tick * 16
		MovementRules.integrate(state, 1.0 / 60.0, tick * 16)

## Segue os pontos só com "para frente" e yaw (como um jogador com mouse),
## integrando o movimento oficial a 60 Hz. Retorna se chegou ao último ponto.
func _drive(state: Dictionary, points: Array, timeout: float, visited: Dictionary = {}) -> bool:
	var tick := 0
	var index := 0
	var elapsed := 0.0
	while index < points.size() and elapsed < timeout:
		var position: Vector3 = state["position"]
		var goal: Vector3 = points[index]
		if Vector2(goal.x - position.x, goal.z - position.z).length() < (0.3 if index == points.size() - 1 else 0.6):
			index += 1
			continue
		state["yaw"] = _yaw_to(position, goal)
		state["last_input_msec"] = tick * 16
		MovementRules.integrate(state, 1.0 / 60.0, tick * 16)
		state["distance"] = float(state["distance"]) + (state["position"] as Vector3).distance_to(position)
		var zone := str(ArenaRules.zone_at(state["position"]).get("id", ""))
		if visited.has(zone):
			visited[zone] = true
		tick += 1
		elapsed += 1.0 / 60.0
	state["time"] = float(state["time"]) + elapsed
	return index >= points.size()

## Verdadeiro se, logo além da borda do vão no sentido `direction`, as duas
## faces (dos dois espaços) já são parede: o vão encosta num canto.
func _flush_side(door: Rect2, direction: Vector2) -> bool:
	var edge := door.get_center() + direction * (maxf(door.size.x, door.size.y) * 0.5 + MansionMap.CELL * 0.5)
	var across := Vector2(1.0, 0.0) if door.size.x < door.size.y else Vector2(0.0, 1.0)
	for side in [-1.0, 1.0]:
		var probe: Vector2 = edge + across * side * MansionMap.CELL
		if MansionMap.is_walkable_cell(MansionMap.cell_of(probe)):
			return false
	return true

func _rect_of(entry: Dictionary) -> Rect2:
	return Rect2(entry["min"], (entry["max"] as Vector2) - (entry["min"] as Vector2))

func _on_grid(point: Vector2) -> bool:
	return absf(point.x / MansionMap.CELL - round(point.x / MansionMap.CELL)) < EPSILON and absf(point.y / MansionMap.CELL - round(point.y / MansionMap.CELL)) < EPSILON

## Comprimento da aresta compartilhada por dois retângulos que se encostam.
func _shared_edge(a: Rect2, b: Rect2) -> float:
	var overlap_x := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
	var overlap_y := minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
	if absf(overlap_x) < EPSILON and overlap_y > EPSILON:
		return overlap_y
	if absf(overlap_y) < EPSILON and overlap_x > EPSILON:
		return overlap_x
	return 0.0

func _touches_along(door: Rect2, space_rect: Rect2, width: float) -> bool:
	return absf(_shared_edge(door, space_rect) - width) < EPSILON

func _declared_junction(a: String, b: String) -> bool:
	for junction in MansionMap.JUNCTIONS:
		if (str(junction["a"]) == a and str(junction["b"]) == b) or (str(junction["a"]) == b and str(junction["b"]) == a):
			return true
	return false

func _space_graph() -> Dictionary:
	var graph := {}
	var link := func(a: String, b: String):
		if not graph.has(a): graph[a] = []
		if not graph.has(b): graph[b] = []
		graph[a].append(b)
		graph[b].append(a)
	for door in MansionMap.DOORS:
		link.call(str(door["room"]), str(door["corridor"]))
	for junction in MansionMap.JUNCTIONS:
		link.call(str(junction["a"]), str(junction["b"]))
	return graph

func _pair(a: String, b: String) -> String:
	return "%s-%s" % ([a, b] if a < b else [b, a])

## Corredores cujo único papel é servir a ala direita.
func _wing_only(space_id: String) -> bool:
	return space_id in ["ala_leste", "ramal_fundo", "ramal_hospedes", "ramal_banheiro"]

func _inside_xz(inner: Dictionary, outer: Dictionary) -> bool:
	var inner_center: Vector3 = inner["center"]
	var inner_half: Vector3 = (inner["size"] as Vector3) * 0.5
	var outer_center: Vector3 = outer["center"]
	var outer_half: Vector3 = (outer["size"] as Vector3) * 0.5
	return inner_center.x - inner_half.x >= outer_center.x - outer_half.x - EPSILON and inner_center.x + inner_half.x <= outer_center.x + outer_half.x + EPSILON \
		and inner_center.z - inner_half.z >= outer_center.z - outer_half.z - EPSILON and inner_center.z + inner_half.z <= outer_center.z + outer_half.z + EPSILON

# Grade do corpo: células de 0,25 m onde o corpo oficial cabe.

func _build_free_grid() -> void:
	_grid_size = Vector2i(int(round((MovementRules.MAP_MAX_X - MovementRules.MAP_MIN_X) / GRID_STEP)) + 1,
		int(round((MovementRules.MAP_MAX_Z - MovementRules.MAP_MIN_Z) / GRID_STEP)) + 1)
	_free_cells.resize(_grid_size.x * _grid_size.y)
	for ix in _grid_size.x:
		for iz in _grid_size.y:
			var position := _cell_position(ix * _grid_size.y + iz)
			_free_cells[ix * _grid_size.y + iz] = 0 if ArenaRules.overlaps_blocker(position) or ArenaRules.zone_at(position).is_empty() else 1

func _cell_position(index: int) -> Vector3:
	var ix := index / _grid_size.y
	var iz := index % _grid_size.y
	return Vector3(MovementRules.MAP_MIN_X + ix * GRID_STEP, MovementRules.PLAYER_HEIGHT, MovementRules.MAP_MIN_Z + iz * GRID_STEP)

func _index_of(position: Vector3) -> int:
	var ix := int(round((position.x - MovementRules.MAP_MIN_X) / GRID_STEP))
	var iz := int(round((position.z - MovementRules.MAP_MIN_Z) / GRID_STEP))
	if ix < 0 or iz < 0 or ix >= _grid_size.x or iz >= _grid_size.y:
		return -1
	return ix * _grid_size.y + iz

func _cell_free(position: Vector3) -> bool:
	var index := _index_of(position)
	return index >= 0 and _free_cells[index] == 1

func _neighbors(index: int) -> Array:
	var ix := index / _grid_size.y
	var iz := index % _grid_size.y
	var result: Array = []
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = ix + offset.x
		var nz: int = iz + offset.y
		if nx >= 0 and nz >= 0 and nx < _grid_size.x and nz < _grid_size.y:
			result.append(nx * _grid_size.y + nz)
	return result

## Busca em largura sobre a grade livre. `seals` bloqueia retângulos XZ.
func _flood(start: Vector3, seals: Array) -> Dictionary:
	var reached := {}
	var first := _index_of(start)
	if first < 0 or _free_cells[first] == 0:
		return reached
	reached[first] = true
	var frontier: Array = [first]
	while not frontier.is_empty():
		var current: int = frontier.pop_back()
		for next in _neighbors(current):
			if reached.has(next) or _free_cells[next] == 0:
				continue
			var position := _cell_position(next)
			var sealed := false
			for seal in seals:
				if (seal as Rect2).has_point(Vector2(position.x, position.z)):
					sealed = true
					break
			if sealed:
				continue
			reached[next] = true
			frontier.append(next)
	return reached

func _reached(reached: Dictionary, position: Vector3) -> bool:
	return reached.has(_index_of(position))

## Distância percorrível (m) de `start` a cada célula, com passos de 0,25 m em
## oito direções (diagonais só quando os dois lados estão livres).
func _distances_from(start: Vector3) -> Dictionary:
	var distances := {}
	var first := _index_of(start)
	if first < 0 or _free_cells[first] == 0:
		return distances
	distances[first] = 0.0
	var open: Array = [[0.0, first]]
	var done := {}
	while not open.is_empty():
		var best := 0
		for candidate in open.size():
			if float(open[candidate][0]) < float(open[best][0]):
				best = candidate
		var current: Array = open[best]
		open.remove_at(best)
		var index := int(current[1])
		if done.has(index):
			continue
		done[index] = true
		var ix := index / _grid_size.y
		var iz := index % _grid_size.y
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var nx: int = ix + dx
				var nz: int = iz + dz
				if nx < 0 or nz < 0 or nx >= _grid_size.x or nz >= _grid_size.y:
					continue
				var next: int = nx * _grid_size.y + nz
				if _free_cells[next] == 0:
					continue
				if dx != 0 and dz != 0 and (_free_cells[nx * _grid_size.y + iz] == 0 or _free_cells[ix * _grid_size.y + nz] == 0):
					continue
				var cost := float(current[0]) + GRID_STEP * (1.41421356 if dx != 0 and dz != 0 else 1.0)
				if cost < float(distances.get(next, INF)):
					distances[next] = cost
					open.append([cost, next])
	return distances

## Caminho livre (lista de pontos) entre duas posições: busca em largura na
## grade e depois só os pontos onde a reta deixaria de caber o corpo.
func _path(from: Vector3, to: Vector3) -> Array:
	var start := _index_of(from)
	var goal := _index_of(to)
	if start < 0 or goal < 0 or _free_cells[start] == 0 or _free_cells[goal] == 0:
		return []
	var previous := {start: -1}
	var frontier: Array = [start]
	var head := 0
	while head < frontier.size():
		var current: int = frontier[head]
		head += 1
		if current == goal:
			break
		for next in _neighbors(current):
			if previous.has(next) or _free_cells[next] == 0:
				continue
			previous[next] = current
			frontier.append(next)
	if not previous.has(goal):
		return []
	var cells: Array = []
	var cursor := goal
	while cursor != -1:
		cells.push_front(_cell_position(cursor))
		cursor = previous[cursor]
	var points: Array = []
	var anchor: Vector3 = cells[0]
	for index in range(1, cells.size()):
		if not _straight_clear(anchor, cells[index]):
			anchor = cells[index - 1]
			points.append(anchor)
	points.append(cells.back())
	return points

func _straight_clear(from: Vector3, to: Vector3) -> bool:
	var steps := maxi(1, int(ceil(from.distance_to(to) / 0.1)))
	for step in steps + 1:
		if ArenaRules.overlaps_blocker(from.lerp(to, float(step) / steps), ArenaRules.PLAYER_HIT_RADIUS + 0.05):
			return false
	return true

## Um ponto livre para o corpo dentro do espaço, o mais perto possível do centro.
func _free_point_in(space_id: String) -> Vector3:
	var rect := MansionMap.space_rect(space_id)
	var center := rect.get_center()
	var best := Vector3.INF
	var best_distance := INF
	var x := rect.position.x + 0.5
	while x <= rect.end.x - 0.5 + EPSILON:
		var z := rect.position.y + 0.5
		while z <= rect.end.y - 0.5 + EPSILON:
			var candidate := Vector3(x, 1.0, z)
			var distance := Vector2(x, z).distance_to(center)
			if distance < best_distance and _cell_free(candidate) and not ArenaRules.overlaps_blocker(candidate, ArenaRules.PLAYER_HIT_RADIUS + 0.3):
				best = candidate
				best_distance = distance
			z += GRID_STEP
		x += GRID_STEP
	return best

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("ARENA_LAYOUT_CHECK_FAILED %s" % description)
