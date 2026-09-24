extends SceneTree

## Identidade visual da mansão (fase 2) sem mudar o mapa físico da fase 1.
##
## - O mapa físico (volumes, vãos, spawns e pickups) tem a mesma impressão
##   digital aprovada na fase 1.
## - Cada volume oficial é desenhado exatamente uma vez, com a mesma caixa, e
##   todo detalhe de móvel fica dentro do volume do próprio móvel.
## - Decoração não ocupa caminho: piso rente, frisos colados às paredes,
##   luminárias acima das cabeças e objetos sobre os móveis; nada invade vãos
##   de porta nem cobre pickups.
## - Nenhuma física nova no cliente; luzes sem sombra dentro do orçamento do
##   renderer Compatibility (32 visíveis, 8 por malha); materiais e texturas
##   compartilhados e pequenos.

## SHA-256 do mapa físico aprovado na fase 1 (`_physical_fingerprint`).
## Paredes, vergas, tetos, móveis, spawns e portas (sem pickups): o mesmo
## valor em `main` antes e depois da fase 6.
const PHASE_ONE_FINGERPRINT := "10ecd14bb78f09944ca37a0eba798b1ba6c542acb97e7bf74462e7774f5c3915"
## Pickups da fase 6 (8 pistolas e 12 munições).
const PHASE_SIX_PICKUP_FINGERPRINT := "19bef63df879570d7d74abcf97f2d65b029a9aacaab99f41fa2d8eaa32ccfbb6"
const TOLERANCE := 0.006
const TRIM_BAND := 0.12
const PROP_REACH := 0.2
const MAX_LIGHTS := 32
const MAX_LIGHTS_PER_MESH := 8

var failures := 0
var checks := 0
var _view: ArenaView
var _frames := 0

func _initialize() -> void:
	_test_physical_map_is_the_phase_one_map()
	_view = ArenaView.new()
	root.add_child(_view)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	var art := _view.art
	_expect(art != null and not art.items.is_empty(), "the view builds the mansion art")
	if art != null:
		_test_official_volumes_are_drawn(art)
		_test_furniture_detail_stays_inside(art)
		_test_decor_never_takes_a_path(art)
		_test_no_client_physics()
		_test_lights_and_resources(art)
		_test_every_room_has_its_identity(art)
	if failures > 0:
		push_error("MANSION_ART_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return true
	print("MANSION_ART_TEST_OK checks=%d items=%d meshes=%d lights=%d materials=%d" % [
		checks, art.items.size(), art.meshes.size(), art.lights.size(), _materials_in_use(art).size()])
	quit(0)
	return true

static func physical_fingerprint() -> String:
	var parts: Array = []
	for blocker in ArenaRules.BLOCKERS:
		parts.append("%s|%s|%s|%s" % [blocker["id"], blocker["kind"], _v(blocker["center"]), _v(blocker["size"])])
	for spawn in MovementRules.SPAWN_POINTS:
		parts.append("spawn|%s" % _v(spawn))
	for door in MansionMap.DOORS:
		parts.append("door|%s|%s|%s" % [door["id"], door["min"], door["max"]])
	return "\n".join(parts).sha256_text()

## Pickups oficiais (redistribuídos na fase 6), à parte das paredes.
static func pickup_fingerprint() -> String:
	var parts: Array = []
	for pickup in ArenaRules.PICKUP_POSITIONS:
		parts.append("pickup|%s" % _v(pickup))
	return "\n".join(parts).sha256_text()

static func _v(value: Vector3) -> String:
	return "%.4f,%.4f,%.4f" % [value.x, value.y, value.z]

func _test_physical_map_is_the_phase_one_map() -> void:
	var fingerprint := physical_fingerprint()
	print("MANSION_PHYSICAL_FINGERPRINT %s" % fingerprint)
	_expect(fingerprint == PHASE_ONE_FINGERPRINT, "the physical map is unchanged since phase 1 (%s)" % fingerprint)
	_expect(pickup_fingerprint() == PHASE_SIX_PICKUP_FINGERPRINT, "the pickups are the phase 6 set (%s)" % pickup_fingerprint())

## Paredes, vergas e tetos: a própria caixa. Móveis: peças cuja união é
## exatamente o volume oficial (ou a caixa maciça).
func _test_official_volumes_are_drawn(art: MansionArt) -> void:
	var drawn := {}
	var volumes := {}
	var parts := {}
	for item in art.items:
		var id := str(item["id"])
		match str(item["kind"]):
			"blocker":
				_expect(not drawn.has(id), "official volume %s is drawn once" % id)
				drawn[id] = item["aabb"]
			"volume":
				_expect(not volumes.has(id), "furniture volume %s is registered once" % id)
				volumes[id] = item["aabb"]
			"furniture":
				parts[id] = (item["aabb"] as AABB) if not parts.has(id) else (parts[id] as AABB).merge(item["aabb"])
	for blocker in ArenaRules.BLOCKERS:
		var id := str(blocker["id"])
		var box := AABB((blocker["center"] as Vector3) - (blocker["size"] as Vector3) * 0.5, blocker["size"])
		if str(blocker["kind"]) == "furniture":
			_expect(volumes.has(id) and (volumes[id] as AABB).is_equal_approx(box), "furniture volume %s is registered with its exact box" % id)
			_expect(parts.has(id) and (parts[id] as AABB).is_equal_approx(box), "the drawn pieces of %s fill exactly its official volume (%s vs %s)" % [id, str(parts.get(id, AABB())), str(box)])
		else:
			_expect(drawn.has(id) and (drawn[id] as AABB).is_equal_approx(box), "official volume %s is drawn with its exact box" % id)
	_expect(drawn.size() + volumes.size() == ArenaRules.BLOCKERS.size(), "only official volumes are drawn as volumes")
	# As malhas agrupadas contêm tudo o que foi registrado.
	var bounds := AABB()
	var first := true
	for node in art.meshes:
		var mesh_node := node as MeshInstance3D
		_expect(mesh_node.is_inside_tree() and mesh_node.visible or str(mesh_node.get_meta("arena_blocker_kind", "")) == "ceiling", "art mesh %s is shown" % mesh_node.name)
		var aabb := mesh_node.global_transform * mesh_node.get_aabb()
		bounds = aabb if first else bounds.merge(aabb)
		first = false
	for item in art.items:
		_expect(bounds.grow(0.001).encloses(item["aabb"]), "item %s/%s is inside the built meshes" % [item["kind"], item["id"]])

func _test_furniture_detail_stays_inside(art: MansionArt) -> void:
	var volumes := {}
	for blocker in ArenaRules.BLOCKERS:
		if str(blocker["kind"]) == "furniture":
			volumes[str(blocker["id"])] = AABB((blocker["center"] as Vector3) - (blocker["size"] as Vector3) * 0.5, blocker["size"])
	var detailed := {}
	for item in art.items:
		if str(item["kind"]) != "furniture":
			continue
		var owner := str(item["id"])
		_expect(volumes.has(owner), "furniture piece belongs to an official volume (%s)" % owner)
		if volumes.has(owner):
			_expect((volumes[owner] as AABB).grow(0.0005).encloses(item["aabb"]), "piece of %s stays inside its official volume (%s)" % [owner, str(item["aabb"])])
		detailed[_furniture_owner(owner)] = int(detailed.get(_furniture_owner(owner), 0)) + 1
	for owner in ["estante_escritorio", "lareira", "bancada", "cama_fundo", "cama_hospedes", "coluna_salao_noroeste", "pedestal", "banheira"]:
		_expect(int(detailed.get(owner, 0)) >= 3, "%s is drawn with detail (%d pieces)" % [owner, int(detailed.get(owner, 0))])

func _test_decor_never_takes_a_path(art: MansionArt) -> void:
	var furniture := {}
	for item in MansionMap.FURNITURE:
		furniture[str(item["id"])] = item
	for item in art.items:
		var kind := str(item["kind"])
		var box: AABB = item["aabb"]
		var space_id := str(item["space"])
		var rect := MansionMap.space_rect(space_id)
		var flat := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
		var ceiling := float(MansionMap.space(space_id).get("ceiling", MansionMap.WALL_TOP))
		match kind:
			"floor":
				_expect(box.end.y <= 0.03 + 0.0001 and box.position.y >= -0.15, "floor piece in %s stays flush with the floor" % space_id)
				_expect(_inside_floor(flat), "floor piece in %s covers only walkable floor" % space_id)
			"trim":
				var band := rect.grow(TRIM_BAND)
				var core := rect.grow(-TRIM_BAND)
				_expect(band.encloses(flat) and not core.intersects(flat), "trim in %s hugs a wall (%s)" % [space_id, str(box)])
				_expect(box.position.y >= -0.001 and box.end.y <= ceiling + 0.001, "trim in %s stays between floor and ceiling" % space_id)
			"fixture":
				_expect(box.position.y >= MansionArt.FIXTURE_MIN_Y - 0.0001 and box.position.y >= ArenaRules.PLAYER_HIT_HEIGHT, "fixture in %s hangs above every head (bottom %.2f)" % [space_id, box.position.y])
				_expect(box.end.y <= ceiling + 0.001 and rect.grow(0.001).encloses(flat), "fixture in %s stays in its space" % space_id)
			"prop":
				var owner := str(item["id"])
				_expect(furniture.has(owner), "prop belongs to a piece of furniture (%s)" % owner)
				if furniture.has(owner):
					var entry: Dictionary = furniture[owner]
					var footprint := Rect2(entry["min"], (entry["max"] as Vector2) - (entry["min"] as Vector2)).grow(PROP_REACH)
					_expect(footprint.encloses(flat), "prop of %s stays on or against it (%s)" % [owner, str(box)])
					_expect(box.end.y <= float(entry["height"]) + 0.7, "prop of %s is small (top %.2f)" % [owner, box.end.y])
					# Nada que encoste no móvel alcança um corpo: a cápsula para a
					# 0,45 m do volume, mais do que o alcance permitido.
					_expect(PROP_REACH < ArenaRules.PLAYER_HIT_RADIUS, "props stay inside the body standoff")
		if kind in ["floor", "blocker", "furniture"]:
			continue
		for door in MansionMap.DOORS:
			var passage := Rect2(door["min"], (door["max"] as Vector2) - (door["min"] as Vector2))
			_expect(not passage.intersects(flat) or box.position.y >= MansionMap.DOOR_HEIGHT, "decor never enters doorway %s (%s %s)" % [door["id"], kind, str(box)])
		if kind != "fixture":
			for index in ArenaRules.PICKUP_POSITIONS.size():
				var pickup: Vector3 = ArenaRules.PICKUP_POSITIONS[index]
				_expect(Vector2(pickup.x, pickup.z).distance_to(flat.get_center()) > 0.5 or flat.size.length() > 1.5 or box.position.y > 1.0, "decor does not sit on pickup %d" % index)

func _test_no_client_physics() -> void:
	var bodies := _view.find_children("*", "CollisionObject3D", true, false)
	_expect(bodies.is_empty(), "the client mansion adds no physics bodies (%d)" % bodies.size())
	var shapes := _view.find_children("*", "CollisionShape3D", true, false)
	_expect(shapes.is_empty(), "the client mansion adds no collision shapes")

func _test_lights_and_resources(art: MansionArt) -> void:
	var omni: Array = _view.find_children("*", "OmniLight3D", true, false)
	_expect(omni.size() <= MAX_LIGHTS, "at most %d point lights (%d)" % [MAX_LIGHTS, omni.size()])
	for light in _view.find_children("*", "Light3D", true, false):
		_expect(not (light as Light3D).shadow_enabled, "light %s casts no shadow" % light.name)
	var worst := 0
	for node in art.meshes:
		var mesh_node := node as MeshInstance3D
		var aabb := mesh_node.global_transform * mesh_node.get_aabb()
		var touching := 0
		for light in omni:
			var omni_light := light as OmniLight3D
			# Conservador: a caixa do alcance da luz, como no descarte do renderer.
			var reach := AABB(omni_light.global_position - Vector3.ONE * omni_light.omni_range, Vector3.ONE * omni_light.omni_range * 2.0)
			if reach.intersects(aabb):
				touching += 1
		worst = maxi(worst, touching)
		_expect(touching <= MAX_LIGHTS_PER_MESH, "mesh %s is reached by at most %d lights (%d)" % [mesh_node.name, MAX_LIGHTS_PER_MESH, touching])
	print("MANSION_ART_LIGHTS point=%d worst_per_mesh=%d meshes=%d" % [omni.size(), worst, art.meshes.size()])
	var materials := _materials_in_use(art)
	_expect(materials.size() <= MansionArt.MATERIALS.size(), "materials are shared (%d)" % materials.size())
	for material in materials.values():
		var texture := (material as StandardMaterial3D).albedo_texture
		if texture != null:
			_expect(texture.get_width() <= 64 and texture.get_height() <= 64, "texture of %s is small and procedural" % (material as Resource).resource_name)

func _test_every_room_has_its_identity(art: MansionArt) -> void:
	var floors := {}
	for item in art.items:
		if str(item["kind"]) == "floor" and str(item["space"]) != "" and (item["aabb"] as AABB).position.y < -0.05:
			floors[str(item["space"])] = str(item["material"])
	for room in MansionMap.rooms():
		_expect(floors.has(str(room["id"])), "%s has a floor" % room["id"])
	_expect(floors.get("salao", "") == "floor_checker", "the hall has the chequered floor")
	_expect(floors.get("cozinha", "") == "floor_tile" and floors.get("banheiro", "") == "floor_tile_small", "kitchen and bathroom have light tiles")
	_expect(floors.get("quarto_fundo", "") != floors.get("quarto_hospedes", ""), "the two bedrooms differ")
	var fixtures := {}
	for item in art.items:
		if str(item["kind"]) == "fixture":
			fixtures[str(item["space"])] = true
	for entry in MansionMap.SPACES:
		var rect := MansionMap.space_rect(str(entry["id"]))
		if str(entry["kind"]) == "corridor" and maxf(rect.size.x, rect.size.y) >= 6.0:
			_expect(fixtures.has(str(entry["id"])), "long corridor %s has sconces" % entry["id"])
	_expect(fixtures.has("salao"), "the hall has a chandelier")

func _materials_in_use(art: MansionArt) -> Dictionary:
	var result := {}
	for node in art.meshes:
		var mesh_node := node as MeshInstance3D
		var material := mesh_node.mesh.surface_get_material(0)
		result[material.get_instance_id()] = material
	return result

func _inside_floor(flat: Rect2) -> bool:
	for entry in MansionMap.SPACES:
		if MansionMap.space_rect(str(entry["id"])).grow(0.001).encloses(flat):
			return true
	for door in MansionMap.DOORS:
		if Rect2(door["min"], (door["max"] as Vector2) - (door["min"] as Vector2)).grow(0.001).encloses(flat):
			return true
	return false

static func _furniture_owner(blocker_id: String) -> String:
	for item in MansionMap.FURNITURE:
		var id := str(item["id"])
		if blocker_id == id or blocker_id.begins_with(id + "_"):
			return id
	return blocker_id

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("MANSION_ART_CHECK_FAILED %s" % description)
