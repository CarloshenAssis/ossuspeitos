extends SceneTree

## Testes determinísticos da arena graybox. Verificam, com as mesmas funções que
## o servidor usa, que spawns são livres, pickups são alcançáveis por mais de
## uma rota, nenhum spawn enxerga outro, coberturas visíveis bloqueiam o hitscan
## oficial, caixotes baixos não bloqueiam, e que cada mesh da arena no cliente
## corresponde exatamente a um bloco oficial.

const GRID_STEP := 0.25
const EPSILON := 0.0001
const KIND_HEIGHTS := {
	"outer": ArenaRules.OUTER_WALL_HEIGHT,
	"wall": ArenaRules.TALL_HEIGHT,
	"cover": ArenaRules.COVER_HEIGHT,
	"low": ArenaRules.LOW_HEIGHT,
}

var failures := 0
var checks := 0
var _free_cells: PackedByteArray
var _grid_size := 0
var _client_view: ArenaView
var _finished := false

func _initialize() -> void:
	_build_free_grid()
	_test_blocker_data_is_consistent()
	_test_heights_match_the_official_eye()
	_test_bounds_are_enclosed_by_outer_walls()
	_test_spawns_are_free_and_distinct()
	_test_spawns_have_no_line_of_sight()
	_test_pickups_are_standable_and_collectable()
	_test_everything_is_reachable()
	_test_opposite_sides_have_redundant_routes()
	_test_pickups_survive_any_single_sealed_route()
	_test_visible_cover_blocks_official_shots()
	_test_openings_do_not_block_official_shots()
	_test_legacy_test_lanes_are_preserved()
	_test_movement_collides_with_blockers()
	_test_zones_orient_players()
	# A arena do cliente precisa de um quadro para executar `_ready` na árvore.
	_client_view = ArenaView.new()
	root.add_child(_client_view)

func _process(_delta: float) -> bool:
	if _finished:
		return false
	_finished = true
	_test_client_meshes_match_official_blockers()
	if failures > 0:
		push_error("ARENA_LAYOUT_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return false
	print("ARENA_LAYOUT_TEST_OK checks=%d blockers=%d spawns=%d pickups=%d" % [
		checks, ArenaRules.BLOCKERS.size(), MovementRules.SPAWN_POINTS.size(), ArenaRules.PICKUP_POSITIONS.size()])
	quit(0)
	return false

# --- Dados ---------------------------------------------------------------------

func _test_blocker_data_is_consistent() -> void:
	var ids: Dictionary = {}
	for blocker in ArenaRules.BLOCKERS:
		var id := str(blocker["id"])
		_expect(not ids.has(id), "blocker id %s is unique" % id)
		ids[id] = true
		_expect(KIND_HEIGHTS.has(str(blocker["kind"])), "blocker %s has a known kind" % id)
		var center: Vector3 = blocker["center"]
		var size: Vector3 = blocker["size"]
		_expect(size.x > 0.0 and size.y > 0.0 and size.z > 0.0, "blocker %s has a positive size" % id)
		# Todo bloco nasce no piso: não existe fresta por baixo que deixe passar
		# tiro ou jogador sem que isso seja visível.
		_expect(absf(center.y - size.y * 0.5) < EPSILON, "blocker %s rests on the floor" % id)
		_expect(minf(size.x, size.z) >= 0.5, "blocker %s is thicker than the collision sub-step" % id)
		if str(blocker["kind"]) != "outer":
			_expect(absf(center.x) + size.x * 0.5 <= ArenaRules.INNER_HALF_EXTENT + EPSILON
				and absf(center.z) + size.z * 0.5 <= ArenaRules.INNER_HALF_EXTENT + EPSILON,
				"interior blocker %s stays inside the outer walls" % id)
	_expect(MovementRules.MAX_COLLISION_STEP < 0.5, "collision sub-step is thinner than any blocker")

func _test_heights_match_the_official_eye() -> void:
	_expect(absf(ArenaRules.OFFICIAL_EYE_Y - (MovementRules.PLAYER_HEIGHT + ArenaRules.EYE_HEIGHT)) < EPSILON,
		"official eye height is body centre plus eye offset")
	for blocker in ArenaRules.BLOCKERS:
		var kind := str(blocker["kind"])
		var top: float = (blocker["size"] as Vector3).y
		_expect(absf(top - float(KIND_HEIGHTS[kind])) < EPSILON, "blocker %s uses the %s height" % [blocker["id"], kind])
		if kind == "low":
			# Caixote baixo: o olho oficial (e a câmera) ficam claramente acima.
			_expect(top <= ArenaRules.OFFICIAL_EYE_Y - 0.5, "low blocker %s is clearly below eye level" % blocker["id"])
		else:
			# Cobertura cheia: topo claramente acima do olho, tiro não passa rente.
			_expect(top >= ArenaRules.OFFICIAL_EYE_Y + 0.5, "full blocker %s is clearly above eye level" % blocker["id"])
			_expect(top >= MovementRules.PLAYER_HEIGHT + ArenaRules.PLAYER_HIT_HEIGHT * 0.5,
				"full blocker %s hides a whole standing body" % blocker["id"])

func _test_bounds_are_enclosed_by_outer_walls() -> void:
	_expect(MovementRules.ARENA_HALF_EXTENT + ArenaRules.PLAYER_HIT_RADIUS <= ArenaRules.INNER_HALF_EXTENT,
		"movement limit keeps the body inside the visible outer walls")
	var outer := 0
	for blocker in ArenaRules.BLOCKERS:
		if str(blocker["kind"]) != "outer":
			continue
		outer += 1
		var center: Vector3 = blocker["center"]
		var size: Vector3 = blocker["size"]
		var along_x := size.x > size.z
		var inner_face := (absf(center.z) - size.z * 0.5) if along_x else (absf(center.x) - size.x * 0.5)
		var span := size.x if along_x else size.z
		_expect(absf(inner_face - ArenaRules.INNER_HALF_EXTENT) < EPSILON, "outer wall %s inner face" % blocker["id"])
		_expect(span >= ArenaRules.INNER_HALF_EXTENT * 2.0 + ArenaRules.OUTER_WALL_THICKNESS * 2.0 - EPSILON,
			"outer wall %s closes both corners" % blocker["id"])
	_expect(outer == 4, "four outer walls")
	# Um tiro oficial em direção a qualquer muro externo sempre para nele.
	for direction in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var origin: Vector3 = Vector3(12.0 * direction.z, ArenaRules.OFFICIAL_EYE_Y, 12.0 * direction.x)
		_expect(ArenaRules.first_blocker_distance(origin, direction, 100.0) >= 0.0, "no shot leaves the arena towards %s" % str(direction))

# --- Spawns --------------------------------------------------------------------

func _test_spawns_are_free_and_distinct() -> void:
	var spawns := MovementRules.SPAWN_POINTS
	_expect(spawns.size() == RoundRules.MAX_PLAYERS, "one spawn per supported player")
	var seen_zones: Dictionary = {}
	for index in spawns.size():
		var spawn: Vector3 = spawns[index]
		_expect(absf(spawn.y - MovementRules.PLAYER_HEIGHT) < EPSILON, "spawn %d at body height" % index)
		_expect(absf(spawn.x) <= MovementRules.ARENA_HALF_EXTENT and absf(spawn.z) <= MovementRules.ARENA_HALF_EXTENT, "spawn %d inside bounds" % index)
		_expect(not ArenaRules.overlaps_blocker(spawn), "spawn %d is not stuck in geometry" % index)
		# Os testes multiprocesso movem cada cliente numa direção qualquer a partir
		# do spawn que recebeu; todas as quatro precisam estar livres.
		# O yaw inicial gira as direções locais, então as diagonais também contam.
		for angle_index in 8:
			var offset := Vector3(0.0, 0.0, -0.5).rotated(Vector3.UP, angle_index * PI / 4.0)
			_expect(not ArenaRules.overlaps_blocker(spawn + offset), "spawn %d can step %s" % [index, str(offset)])
		# Começa olhando para o centro: o que está à frente é a saída, não o muro.
		var yaw := MovementRules.spawn_yaw(spawn)
		var facing := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, yaw)
		_expect(facing.dot(-Vector3(spawn.x, 0.0, spawn.z).normalized()) > 0.999, "spawn %d starts facing the arena centre" % index)
		var eye := spawn + Vector3.UP * ArenaRules.EYE_HEIGHT
		_expect(ArenaRules.first_blocker_distance(eye, facing, 50.0) > 1.5, "spawn %d does not start with its face against a wall" % index)
		for other in range(index + 1, spawns.size()):
			_expect(Vector2(spawn.x, spawn.z).distance_to(Vector2(spawns[other].x, spawns[other].z)) >= ArenaRules.PLAYER_HIT_RADIUS * 4.0,
				"spawns %d and %d do not overlap" % [index, other])
		for pickup_index in ArenaRules.PICKUP_POSITIONS.size():
			_expect(spawn.distance_to(ArenaRules.PICKUP_POSITIONS[pickup_index]) > InventoryAuthority.PICKUP_RANGE_METERS + 0.5,
				"spawn %d is not on top of pickup %d" % [index, pickup_index])
		var zone := str(ArenaRules.zone_at(spawn).get("id", ""))
		_expect(zone != "" and zone != "center", "spawn %d is in an edge region" % index)
		_expect(not seen_zones.has(zone), "spawn %d has its own region" % index)
		seen_zones[zone] = true
	for index in 4:
		var corner := str(ArenaRules.zone_at(spawns[index]).get("id", ""))
		_expect(corner in ["northwest", "northeast", "southwest", "southeast"], "four-player spawn %d is inside a corner room" % index)

## Nenhum par de spawns se enxerga: o hitscan oficial de `CombatAuthority`,
## disparado do olho de um spawn na direção do outro, para num bloco antes.
func _test_spawns_have_no_line_of_sight() -> void:
	var spawns := MovementRules.SPAWN_POINTS
	var rounds := RoundAuthority.new()
	var world := AuthoritativeWorld.new()
	var peers: Array = []
	for index in spawns.size():
		var peer_id := index + 1
		world.add_player(peer_id)
		peers.append(peer_id)
		rounds.participants[peer_id] = true
		rounds.alive[peer_id] = true
	rounds.state = RoundState.ACTIVE
	rounds.round_id = 1
	var combat := CombatAuthority.new(rounds, world)
	combat.begin_round(1, peers)
	for shooter_index in spawns.size():
		for target_index in spawns.size():
			if shooter_index == target_index:
				continue
			var shooter_eye: Vector3 = world.states[shooter_index + 1]["position"] + Vector3.UP * ArenaRules.EYE_HEIGHT
			var target_position: Vector3 = world.states[target_index + 1]["position"]
			var direction := (target_position + Vector3.UP * ArenaRules.EYE_HEIGHT - shooter_eye).normalized()
			var hit: Dictionary = combat._raycast(shooter_index + 1, shooter_eye, direction, 100.0)
			_expect(int(hit.get("peer_id", 0)) == 0,
				"spawn %d cannot shoot spawn %d at round start (hit=%s)" % [shooter_index, target_index, str(hit)])

# --- Pickups e alcance ---------------------------------------------------------

func _test_pickups_are_standable_and_collectable() -> void:
	var rounds := RoundAuthority.new()
	var world := AuthoritativeWorld.new()
	world.add_player(1)
	rounds.participants[1] = true
	rounds.alive[1] = true
	rounds.state = RoundState.ACTIVE
	rounds.round_id = 1
	var combat := CombatAuthority.new(rounds, world)
	combat.begin_round(1, [1])
	_expect(ArenaRules.PICKUP_POSITIONS.size() == 8, "four weapons and four ammo boxes")
	var sequence := 0
	for index in ArenaRules.PICKUP_POSITIONS.size():
		var pickup: Vector3 = ArenaRules.PICKUP_POSITIONS[index]
		var standing := Vector3(pickup.x, MovementRules.PLAYER_HEIGHT, pickup.z)
		_expect(absf(pickup.x) <= MovementRules.ARENA_HALF_EXTENT and absf(pickup.z) <= MovementRules.ARENA_HALF_EXTENT, "pickup %d inside bounds" % index)
		_expect(not ArenaRules.overlaps_blocker(standing), "a player can stand on pickup %d" % index)
		_expect(_cell_free(standing), "pickup %d lies on the reachable grid" % index)
		# Coleta pelo caminho oficial, com o corpo exatamente sobre o pickup.
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
	var start: Vector3 = MovementRules.SPAWN_POINTS[0]
	var reached := _flood(start, [])
	for index in MovementRules.SPAWN_POINTS.size():
		_expect(_reached(reached, MovementRules.SPAWN_POINTS[index]), "spawn %d reachable from spawn 0" % index)
	for index in ArenaRules.PICKUP_POSITIONS.size():
		_expect(_reached(reached, ArenaRules.PICKUP_POSITIONS[index]), "pickup %d reachable from spawn 0" % index)

## Lados opostos se ligam pelo pátio e por dois corredores laterais. Selar
## qualquer um deles (ou dois) não desconecta os lados.
func _test_opposite_sides_have_redundant_routes() -> void:
	var north := Vector3(0.0, 1.0, -8.0)
	var south := Vector3(0.0, 1.0, 8.0)
	var west := Vector3(-8.0, 1.0, 0.0)
	var east := Vector3(8.0, 1.0, 0.0)
	var plaza := _rect(-5.0, -5.0, 5.0, 5.0)
	var west_lane := _rect(-14.5, -2.5, -5.0, 2.5)
	var east_lane := _rect(5.0, -2.5, 14.5, 2.5)
	var north_lane := _rect(-2.5, -14.5, 2.5, -5.0)
	var south_lane := _rect(-2.5, 5.0, 2.5, 14.5)
	_expect(_reached(_flood(north, [plaza, east_lane]), south), "north reaches south through the west route alone")
	_expect(_reached(_flood(north, [plaza, west_lane]), south), "north reaches south through the east route alone")
	_expect(_reached(_flood(north, [west_lane, east_lane]), south), "north reaches south through the plaza alone")
	_expect(_reached(_flood(west, [plaza, north_lane]), east), "west reaches east through the south route alone")
	_expect(_reached(_flood(west, [plaza, south_lane]), east), "west reaches east through the north route alone")
	_expect(_reached(_flood(west, [north_lane, south_lane]), east), "west reaches east through the plaza alone")

## Nenhum pickup fica atrás de um gargalo único: selando qualquer um dos cinco
## corredores principais, todo pickup fora dele continua alcançável de todo
## spawn fora dele.
func _test_pickups_survive_any_single_sealed_route() -> void:
	var seals := {
		"plaza": _rect(-5.0, -5.0, 5.0, 5.0),
		"west_lane": _rect(-14.5, -2.5, -5.0, 2.5),
		"east_lane": _rect(5.0, -2.5, 14.5, 2.5),
		"north_lane": _rect(-2.5, -14.5, 2.5, -5.0),
		"south_lane": _rect(-2.5, 5.0, 2.5, 14.5),
	}
	for seal_name in seals:
		var seal: Rect2 = seals[seal_name]
		for spawn_index in MovementRules.SPAWN_POINTS.size():
			var spawn: Vector3 = MovementRules.SPAWN_POINTS[spawn_index]
			if seal.has_point(Vector2(spawn.x, spawn.z)):
				continue
			var reached := _flood(spawn, [seal])
			for pickup_index in ArenaRules.PICKUP_POSITIONS.size():
				var pickup: Vector3 = ArenaRules.PICKUP_POSITIONS[pickup_index]
				if seal.has_point(Vector2(pickup.x, pickup.z)):
					continue
				_expect(_reached(reached, pickup), "pickup %d reachable from spawn %d with %s sealed" % [pickup_index, spawn_index, seal_name])

# --- Concordância entre o que se vê e o hitscan oficial ------------------------

## Para cada bloco, um tiro oficial na altura do olho mirando seu centro: se o
## topo passa do olho, o tiro para exatamente na face; se não, passa por cima.
func _test_visible_cover_blocks_official_shots() -> void:
	for blocker in ArenaRules.BLOCKERS:
		if str(blocker["kind"]) == "outer":
			continue
		var center: Vector3 = blocker["center"]
		var size: Vector3 = blocker["size"]
		for direction in [Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT]:
			var half: float = (size.x if direction.x != 0.0 else size.z) * 0.5
			var origin: Vector3 = Vector3(center.x, ArenaRules.OFFICIAL_EYE_Y, center.z) - direction * (half + 0.6)
			if ArenaRules.overlaps_blocker(Vector3(origin.x, MovementRules.PLAYER_HEIGHT, origin.z), 0.05) \
					or absf(origin.x) > ArenaRules.INNER_HALF_EXTENT or absf(origin.z) > ArenaRules.INNER_HALF_EXTENT:
				continue
			var own := ArenaRules.ray_aabb(origin, direction, 50.0, center, size)
			var first := ArenaRules.first_blocker_distance(origin, direction, 50.0)
			if str(blocker["kind"]) == "low":
				_expect(own < 0.0, "shot at eye height passes over low blocker %s" % blocker["id"])
			else:
				_expect(absf(own - 0.6) < 0.001 and absf(first - 0.6) < 0.001,
					"visible blocker %s stops an eye-level shot at its face (own=%.3f first=%.3f)" % [blocker["id"], own, first])
		# O mesmo bloco, visto no nível da cintura, bloqueia sempre (nada passa
		# por baixo de um bloco apoiado no piso).
		var low_origin := Vector3(center.x, 0.5, center.z - size.z * 0.5 - 0.6)
		_expect(ArenaRules.ray_aabb(low_origin, Vector3.BACK, 50.0, center, size) >= 0.0, "blocker %s is solid down to the floor" % blocker["id"])

func _test_openings_do_not_block_official_shots() -> void:
	# Portas diagonais das salas de canto: o tiro que sai da sala pela porta só
	# para bem depois dela (na cobertura em cata-vento), nunca num muro da sala.
	for corner in [Vector3(12.3, 0, 12.3), Vector3(-12.3, 0, 12.3), Vector3(12.3, 0, -12.3), Vector3(-12.3, 0, -12.3)]:
		var origin: Vector3 = Vector3(corner.x, ArenaRules.OFFICIAL_EYE_Y, corner.z)
		var direction: Vector3 = Vector3(-corner.x, 0.0, -corner.z).normalized()
		var doorway_distance := (absf(corner.x) - 10.2) * sqrt(2.0)
		var first := ArenaRules.first_blocker_distance(origin, direction, 50.0)
		_expect(first > doorway_distance + 5.0, "corner room doorway at %s is open for shots (first blocker at %.2f m)" % [str(corner), first])
		for blocker in ArenaRules.BLOCKERS:
			if str(blocker["id"]).begins_with("room_"):
				_expect(ArenaRules.ray_aabb(origin, direction, 50.0, blocker["center"], blocker["size"]) < 0.0,
					"doorway shot from %s misses room wall %s" % [str(corner), blocker["id"]])
	# Linha que cruza o pátio por cima de dois caixotes baixos até o muro oeste.
	var origin := Vector3(8.0, ArenaRules.OFFICIAL_EYE_Y, 2.9)
	var outer := ArenaRules.ray_aabb(origin, Vector3.LEFT, 50.0, Vector3(-14.75, 1.75, 0.0), Vector3(0.5, 3.5, 30.0))
	_expect(absf(ArenaRules.first_blocker_distance(origin, Vector3.LEFT, 50.0) - outer) < 0.001, "low plaza crates never stop an eye-level shot")

## Faixas usadas pelos testes de combate existentes continuam com o mesmo
## significado: livres onde o combate espera acerto, bloqueadas onde espera parede.
func _test_legacy_test_lanes_are_preserved() -> void:
	_expect(_lane_free(Vector3(8, 1, 8), Vector3(8, 1, 2)), "combat network lane x=8 is open")
	_expect(_lane_free(Vector3(6, 0, 6), Vector3(6, 0, 1)), "combat authority lane x=6 (body at y=0) is open")
	_expect(_lane_free(Vector3(6, 0, 8), Vector3(6, 0, 2)), "combat authority raycast lane is open")
	_expect(not _lane_free(Vector3(0, 1, 5), Vector3(0, 1, -5)), "central monument blocks the wall probe")
	_expect(not _lane_free(Vector3(0, 0, 8), Vector3(0, 0, -5)), "central monument blocks the unit wall probe")
	for position in [Vector3(-8, 1, -8), Vector3(-8, 1, 8), Vector3(8, 1, 8), Vector3(8, 1, 2), Vector3(0, 1, 5), Vector3(0, 1, -5)]:
		_expect(not ArenaRules.overlaps_blocker(position), "test position %s is free" % str(position))

# --- Movimento autoritativo ----------------------------------------------------

func _test_movement_collides_with_blockers() -> void:
	# Correndo para o norte, direto no monumento: para na face, sem atravessar.
	var state := _moving_state(Vector3(0.0, 1.0, 5.0), Vector2.UP)
	_run(state, 180)
	var position: Vector3 = state["position"]
	_expect(position.z >= 1.2 + ArenaRules.PLAYER_HIT_RADIUS - 0.001, "monument stops the body at its face (z=%.3f)" % position.z)
	_expect(position.z <= 1.2 + ArenaRules.PLAYER_HIT_RADIUS + 0.2, "body reaches the monument face (z=%.3f)" % position.z)
	_expect(absf((state["velocity"] as Vector3).z) < EPSILON, "blocked axis loses its velocity")
	# Diagonal contra a mesma face: desliza no eixo livre, preso no bloqueado.
	state = _moving_state(Vector3(-1.2, 1.0, 1.7), Vector2(1.0, -1.0).normalized())
	_run(state, 30)
	position = state["position"]
	_expect(position.x > -1.2 + 0.8 and position.x < 1.2, "body slides along a wall on the free axis (x=%.3f)" % position.x)
	_expect(position.z >= 1.2 + ArenaRules.PLAYER_HIT_RADIUS - 0.001, "sliding body never enters the wall (z=%.3f)" % position.z)
	# Nenhum delta grande atravessa parede: passo único de 3 m contra o monumento.
	var resolved := MovementRules.resolve_step(Vector3(0.0, 1.0, 4.0), Vector3(0.0, 0.0, -3.0))
	_expect(bool(resolved["blocked_z"]) and (resolved["position"] as Vector3).z >= 1.2 + ArenaRules.PLAYER_HIT_RADIUS - 0.001,
		"a single large step cannot tunnel through a blocker")
	# Caixote baixo também bloqueia passagem (não há pulo).
	resolved = MovementRules.resolve_step(Vector3(2.9, 1.0, 4.5), Vector3(0.0, 0.0, -2.0))
	_expect(bool(resolved["blocked_z"]), "low crates block movement")
	# Limite externo continua valendo.
	resolved = MovementRules.resolve_step(Vector3(0.0, 1.0, -13.0), Vector3(0.0, 0.0, -5.0))
	_expect(absf((resolved["position"] as Vector3).z + MovementRules.ARENA_HALF_EXTENT) < EPSILON, "outer bound clamps movement")
	# Quem foi teleportado para dentro de um bloco não fica preso.
	resolved = MovementRules.resolve_step(Vector3(0.0, 1.0, 0.5), Vector3(0.0, 0.0, 0.2))
	_expect(not bool(resolved["blocked_z"]), "a body inside a blocker can walk out")
	# Do spawn de canto até o pátio pela porta diagonal, só com entrada de
	# movimento autoritativa: a sala tem saída real.
	state = _moving_state(MovementRules.SPAWN_POINTS[1], Vector2(-1.0, -1.0).normalized())
	_run(state, 150)
	position = state["position"]
	_expect(position.x < 8.0 and position.z < 8.0, "corner room exit leads towards the plaza (%s)" % str(position))

# --- Orientação ----------------------------------------------------------------

func _test_zones_orient_players() -> void:
	var names: Dictionary = {}
	for zone in ArenaRules.ZONES:
		_expect(not names.has(str(zone["name"])), "zone name %s is unique" % zone["name"])
		names[str(zone["name"])] = true
	_expect(names.size() == 9, "nine named regions")
	_expect(ArenaRules.zone_name_at(Vector3.ZERO) == "Pátio central", "the monument is in the plaza")
	_expect(ArenaRules.zone_name_at(Vector3(0, 1, -10)) == "Norte", "negative Z is north")
	_expect(ArenaRules.zone_name_at(Vector3(10, 1, 0)) == "Leste", "positive X is east")
	# Toda posição jogável cai em exatamente uma região nomeada.
	for x in range(-14, 15, 2):
		for z in range(-14, 15, 2):
			_expect(not ArenaRules.zone_name_at(Vector3(x, 1, z)).is_empty(), "position %d,%d has a region" % [x, z])

# --- Cliente -------------------------------------------------------------------

## Instancia a arena do cliente e compara nó a nó com `ArenaRules.BLOCKERS`.
## Qualquer mesh que não seja bloco oficial precisa ser decoração plana de piso
## (não esconde nem protege ninguém); placas ficam coladas nos muros externos.
func _test_client_meshes_match_official_blockers() -> void:
	var view := _client_view
	var by_id: Dictionary = {}
	for blocker in ArenaRules.BLOCKERS:
		by_id[str(blocker["id"])] = blocker
	var matched: Dictionary = {}
	for child in view.get_children():
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
			else:
				_expect(str(mesh_node.get_meta("arena_decor", "")) == "floor", "unlisted mesh %s is floor decor" % mesh_node.name)
				var aabb := mesh_node.get_aabb()
				var top := mesh_node.position.y + aabb.position.y + aabb.size.y
				_expect(top <= 0.05, "floor decor %s never rises above the floor (top=%.3f)" % [mesh_node.name, top])
		elif child is Label3D:
			var label := child as Label3D
			var edge := maxf(absf(label.position.x), absf(label.position.z))
			_expect(edge >= ArenaRules.INNER_HALF_EXTENT - 0.05, "sign %s is flat on an outer wall" % label.text)
			# A face legível (+Z local) aponta para dentro da arena, não para o muro.
			var facing := label.transform.basis.z.normalized()
			var inward := -Vector3(label.position.x, 0.0, label.position.z).normalized()
			if absf(label.position.x) > absf(label.position.z):
				inward = Vector3(-signf(label.position.x), 0.0, 0.0)
			else:
				inward = Vector3(0.0, 0.0, -signf(label.position.z))
			_expect(facing.dot(inward) > 0.99, "sign %s is readable from inside the arena" % label.text)
	_expect(matched.size() == ArenaRules.BLOCKERS.size(), "every official blocker is rendered (%d/%d)" % [matched.size(), ArenaRules.BLOCKERS.size()])
	_expect(absf(view.camera.position.y - ArenaRules.EYE_HEIGHT) < EPSILON, "client camera sits at the official eye offset")
	view.free()

# --- Utilitários ---------------------------------------------------------------

func _moving_state(position: Vector3, move: Vector2) -> Dictionary:
	return {"position": position, "velocity": Vector3.ZERO, "yaw": 0.0, "input": move, "last_input_msec": 0}

func _run(state: Dictionary, ticks: int) -> void:
	for tick in ticks:
		state["last_input_msec"] = tick * 16
		MovementRules.integrate(state, 1.0 / 60.0, tick * 16)

func _lane_free(shooter: Vector3, target: Vector3) -> bool:
	var origin := shooter + Vector3.UP * ArenaRules.EYE_HEIGHT
	var direction := (target - shooter).normalized()
	var target_distance := ArenaRules.ray_player(origin, direction, 50.0, target)
	var blocker := ArenaRules.first_blocker_distance(origin, direction, 50.0)
	return target_distance >= 0.0 and (blocker < 0.0 or blocker > target_distance)

func _rect(min_x: float, min_z: float, max_x: float, max_z: float) -> Rect2:
	return Rect2(Vector2(min_x, min_z), Vector2(max_x - min_x, max_z - min_z))

func _build_free_grid() -> void:
	_grid_size = int(round(MovementRules.ARENA_HALF_EXTENT * 2.0 / GRID_STEP)) + 1
	_free_cells.resize(_grid_size * _grid_size)
	for ix in _grid_size:
		for iz in _grid_size:
			var position := _cell_position(ix, iz)
			_free_cells[ix * _grid_size + iz] = 0 if ArenaRules.overlaps_blocker(position) else 1

func _cell_position(ix: int, iz: int) -> Vector3:
	return Vector3(ix * GRID_STEP - MovementRules.ARENA_HALF_EXTENT, MovementRules.PLAYER_HEIGHT, iz * GRID_STEP - MovementRules.ARENA_HALF_EXTENT)

func _cell_of(position: Vector3) -> Vector2i:
	return Vector2i(int(round((position.x + MovementRules.ARENA_HALF_EXTENT) / GRID_STEP)),
		int(round((position.z + MovementRules.ARENA_HALF_EXTENT) / GRID_STEP)))

func _cell_free(position: Vector3) -> bool:
	var cell := _cell_of(position)
	return _free_cells[cell.x * _grid_size + cell.y] == 1

## Busca em largura sobre a grade de posições livres do corpo oficial. `seals`
## são retângulos XZ tratados como bloqueados (corredores fechados).
func _flood(start: Vector3, seals: Array) -> PackedByteArray:
	var reached := PackedByteArray()
	reached.resize(_grid_size * _grid_size)
	var first := _cell_of(start)
	if not _cell_open(first, seals):
		return reached
	var queue: Array[Vector2i] = [first]
	reached[first.x * _grid_size + first.y] = 1
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + offset
			if next.x < 0 or next.y < 0 or next.x >= _grid_size or next.y >= _grid_size:
				continue
			var index := next.x * _grid_size + next.y
			if reached[index] == 1 or not _cell_open(next, seals):
				continue
			reached[index] = 1
			queue.append(next)
	return reached

func _cell_open(cell: Vector2i, seals: Array) -> bool:
	if _free_cells[cell.x * _grid_size + cell.y] != 1:
		return false
	var position := _cell_position(cell.x, cell.y)
	for seal in seals:
		if (seal as Rect2).has_point(Vector2(position.x, position.z)):
			return false
	return true

func _reached(reached: PackedByteArray, position: Vector3) -> bool:
	var cell := _cell_of(position)
	return reached[cell.x * _grid_size + cell.y] == 1

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ARENA_LAYOUT_CHECK_FAILED %s" % message)
