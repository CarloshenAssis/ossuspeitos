extends Node3D
## Apresentação do térreo. Os volumes de colisão continuam no mapa compartilhado.

const SalaoMap = ArenaRules.SalaoMap

var _wood := StandardMaterial3D.new()
var _tile := StandardMaterial3D.new()

func build(greyboxes: Dictionary) -> void:
	_wood.albedo_color = Color(0.29, 0.15, 0.075)
	_tile.albedo_color = Color(0.49, 0.43, 0.34)

	# --- Salão: estar a sul das colunas oeste; lustre ao centro. Fora do spawn (7, 8.75),
	# das portas e dos pickups (8, 2.5), (0.75, 1.75), (10.75, 13.5), (15.5, 13.5), (1.5, 13.5).
	_model("chandelier_01", Vector3(8, 7, 8), 0.0, Vector3.ZERO, true)
	_model("sofa_03", Vector3(1.2, 0, 12.3), PI / 2)
	_model("sofa_03", Vector3(5.0, 0, 12.3), -PI / 2)
	_model("gothic_coffee_table", Vector3(3.1, 0, 12.3))
	_model("dining_chair", Vector3(3.1, 0, 11.12), 0.0)
	_model("gothic_commode", Vector3(3.1, 0, 13.55), PI)
	_model("lampara_ar", Vector3(3.1, 1.22, 13.55))
	_model("coffee_cart", Vector3(14.0, 0, 11.7), PI)
	_model("vintage_drawer", Vector3(15.25, 0, 10.85), -PI / 2)
	_model("lampara_ar", Vector3(15.25, 1.1, 10.85))
	_model("ceramic_pot", Vector3(2.1, 0, 13.45))
	_model("ceramic_pot", Vector3(4.15, 0, 13.45))
	_model("ceramic_pot", Vector3(13.3, 0, 11.5))
	_model("ceramic_pot", Vector3(2.55, 0, 4.2))
	_model("ceramic_pot", Vector3(13.7, 0, 5.4))
	_model("ceramic_pot", Vector3(2.7, 0, 10.45))

	# --- Biblioteca (escrivaninha longe dos spawns -1.5,12.75 e -2,13.5).
	_table(Vector3(-2.6, 0, 12.2), Vector3(1.2, 0.75, 0.7))
	_model("lampara_ar", Vector3(-2.9, 0.75, 12.2))
	_model("book_set", Vector3(-2.3, 0.75, 12.2))
	_model("dining_chair", Vector3(-2.6, 0, 11.3), 0.0)
	_model("vintage_drawer", Vector3(-8.8, 0, 5.7), PI)
	_model("ceramic_pot", Vector3(-0.95, 0, 6.15))
	_model("ceramic_pot", Vector3(-8.9, 0, 12.35))

	# --- Cozinha: parede leste livre das armas (26, 9) e (25.5, 13.5); sul longe da porta.
	for z in [8.15, 10.25, 10.9, 11.55, 12.2]:
		_model("kitchen_cabinet", Vector3(26.17, 0, z), -PI / 2)
	_model("steel_shelves", Vector3(16.88, 0, 11.75), PI / 2)
	_model("washer", Vector3(26.1, 0, 13.35), -PI / 2)
	_model("coffee_cart", Vector3(24.25, 0, 12.55), -PI / 2)
	_model("kitchen_cabinet", Vector3(21.0, 0, 13.6), 0.0)
	_model("kitchen_cabinet", Vector3(22.5, 0, 13.6), 0.0)
	_model("ceramic_pot", Vector3(20.2, 0, 13.55))
	_model("ceramic_pot", Vector3(23.6, 0, 13.55))

	# --- Quarto de Hóspedes (spawn -8.25,19; arma -10,15.25; munição -5.25,19).
	# Cômoda no tamanho de criado-mudo, à cabeceira norte, para não tapar a cama.
	_model("vintage_drawer", Vector3(-8.15, 0, 16.65), -PI / 2, Vector3(0.55, 0.72, 0.45))
	_model("lampara_ar", Vector3(-8.15, 0.72, 16.65))
	_model("book_set", Vector3(-8.15, 0.72, 16.5))
	_model("dining_chair", Vector3(-6.9, 0, 17.7), PI / 2)
	_model("ceramic_pot", Vector3(-10.15, 0, 19.15))

	# --- Lavabo (muniçao -0.75,17.75; portas a oeste, leste e sul).
	_model("kitchen_cabinet", Vector3(3.7, 0, 16.45), PI)
	_model("lampara_ar", Vector3(3.7, 0.88, 16.45))
	_model("ceramic_pot", Vector3(4.5, 0, 16.45))

	# --- Banheiro de Mármore (vão norte/sul em x=0,5–2,5; munição 1, 24.25).
	_model("toilet", Vector3(4.6, 0, 22.8), -PI / 2)
	_model("kitchen_cabinet", Vector3(4.45, 0, 24.85), -PI / 2)
	_model("lampara_ar", Vector3(4.45, 0.88, 20.55))
	_model("ceramic_pot", Vector3(-3.6, 0, 20.55))
	_model("ceramic_pot", Vector3(3.7, 0, 25.35))
	_model("ceramic_pot", Vector3(-3.5, 0, 25.3))

	# --- Sala de Jantar (spawn 12.5,18.5; arma 6,20.5; munição 17.5,22; porta sul 11,5–13,5).
	_model("sofa_03", Vector3(8.4, 0, 21.95), PI)
	_model("dining_chair", Vector3(6.4, 0, 16.3), -PI / 2)
	_model("ceramic_pot", Vector3(6.35, 0, 15.0))
	_model("lampara_ar", Vector3(19.0, 1.7, 17.3))
	_model("lampara_ar", Vector3(19.0, 1.7, 20.8))
	_model("ceramic_pot", Vector3(19.0, 1.7, 19.0))

	# --- Jardim de Inverno (porta norte 11,5–13,5; acesso oeste z=26,5–28,5; munição 18,27).
	_model("tree_medium", Vector3(7.0, 0, 24.0), 0.6, Vector3(1.35, 2.5, 1.48))
	_model("tree_medium", Vector3(17.3, 0, 24.2), -0.4, Vector3(1.35, 2.5, 1.48))
	_model("dining_chair", Vector3(10.0, 0, 24.15), PI / 2)
	_model("dining_chair", Vector3(14.8, 0, 24.15), -PI / 2)
	_model("ceramic_pot", Vector3(10.5, 0, 27.6))
	_model("ceramic_pot", Vector3(14.2, 0, 27.6))
	_model("ceramic_pot", Vector3(16.4, 0, 28.35))
	_model("ceramic_pot", Vector3(-3.4, 0, 27.6))
	_model("lampara_ar", Vector3(-3.4, 0, 28.4))

	for item in SalaoMap.FURNITURE:
		var id: String = item["id"]
		var area := SalaoMap.rect(item)
		var center := area.get_center()
		var floor_center := Vector3(center.x, 0, center.y)
		var size := Vector3(area.size.x, item["height"], area.size.y)
		match id:
			"estante_o", "estante_m", "estante_l":
				_bookshelves(area, size.y)
			"ilha":
				_box(floor_center, Vector3(size.x, size.y * 0.5, size.z), _tile)
				_model("electric_stove", floor_center + Vector3(-0.95, 1, 0))
				_model("kettle", floor_center + Vector3(-0.5, 1, -0.28))
				_model("tea_set", floor_center + Vector3(0, 1, 0.45))
				_model("ceramic_pot", floor_center + Vector3(1, 1, -0.35))
				_model("pears", floor_center + Vector3(0.55, 1, 0.35))
				_model("brass_goblets", floor_center + Vector3(-0.15, 1, -0.7))
			"mesa_jantar":
				_dining(area, floor_center, size)
			"aparador":
				var segment := size.z / 4.0
				for index in 4:
					var z := area.position.y + segment * (index + 0.5)
					_model("gothic_commode", Vector3(center.x, 0, z), -PI / 2,
						Vector3(size.x, 1.7, segment))
			"cama":
				_model("bed", floor_center, PI / 2, Vector3(size.x, 0.75, size.z))
			"guarda_roupa":
				_model("gothic_commode", floor_center, PI / 2, size)
			"pia":
				for x_offset in [-size.x / 3.0, 0.0, size.x / 3.0]:
					_model("kitchen_cabinet", floor_center + Vector3(x_offset, 0, 0), PI,
						Vector3(size.x / 3.0, 0.85, size.z))
				_model("faucet", floor_center + Vector3(0, 0.85, 0.35), PI,
					Vector3(0.13, 0.15, 0.23))
			"banheira":
				_model("bathtub", floor_center, PI / 2, Vector3(1.8, 0.6, size.z))
				_model("faucet", floor_center + Vector3(0, 0.6, 1.1), PI,
					Vector3(0.16, 0.4, 0.28))
			"jardineira_o", "jardineira_s":
				_box(floor_center, Vector3(size.x, 0.6, size.z), _tile)
				var offset := Vector3(size.x * 0.1, 0, size.z * 0.23)
				_model("ceramic_pot", floor_center + Vector3.UP * 0.6 - offset)
				_model("ceramic_pot", floor_center + Vector3.UP * 0.6 + offset)
				_model("ceramic_pot", floor_center + Vector3.UP * 0.6)
			"planta_a":
				# Mudas de verão (tronco + folhagem), altura 2,5 m.
				_model("tree_medium", floor_center, 0, Vector3(1.35, size.y, 1.48))
			"planta_b":
				_model("tree_large", floor_center, 0, Vector3(2.61, size.y, 1.76))
			_:
				continue
		(greyboxes[id] as MeshInstance3D).hide()

func _bookshelves(area: Rect2, height: float) -> void:
	var segment := area.size.y / 5.0
	var x := area.position.x + 0.35
	for index in 5:
		var z := area.position.y + segment * (index + 0.5)
		_model("wooden_bookshelf", Vector3(x, 0, z), PI / 2, Vector3(0.7, height, segment))
		# Tampos medidos nas prateleiras do modelo de 2,06 m.
		for shelf_y in [0.36, 0.66, 1.26, 1.86]:
			if (index + int(shelf_y * 10.0)) % 2 == 0:
				continue
			_model("book_set", Vector3(x + 0.17, height * shelf_y / 2.06, z), PI / 2)

func _dining(area: Rect2, center: Vector3, size: Vector3) -> void:
	_table(center, size)
	# A cadeira olha para +Z (encosto em -Z). Recuo para o assento entrar 15 cm sob o tampo.
	const CHAIR_HALF := 0.25
	const TUCK := 0.15
	var inset := CHAIR_HALF - TUCK
	for index in 3:
		var x := area.position.x + area.size.x * (index + 0.5) / 3.0
		_model("dining_chair", Vector3(x, 0, area.position.y - inset), 0.0)
		_model("dining_chair", Vector3(x, 0, area.end.y + inset), PI)
	_model("dining_chair", Vector3(area.position.x - inset, 0, center.z), -PI / 2)
	_model("dining_chair", Vector3(area.end.x + inset, 0, center.z), PI / 2)
	_model("brass_goblets", center + Vector3(-1, size.y, 0))
	_model("brass_goblets", center + Vector3(1.6, size.y, 0.15))
	_model("tea_set", center + Vector3(0.8, size.y, 0))
	_model("pears", center + Vector3(-0.15, size.y, 0.2))
	_model("chandelier_03", center + Vector3.UP * 3.5, 0.0, Vector3.ZERO, true)

func _table(center: Vector3, size: Vector3) -> void:
	const TOP := 0.1
	const LEG := 0.12
	_box(center + Vector3.UP * (size.y - TOP), Vector3(size.x, TOP, size.z), _wood)
	for x in [-1, 1]:
		for z in [-1, 1]:
			_box(center + Vector3(x * (size.x * 0.5 - LEG), 0, z * (size.z * 0.5 - LEG)),
				Vector3(LEG, size.y - TOP, LEG), _wood)

func _box(base: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	instance.mesh = mesh
	instance.position = base + Vector3.UP * size.y * 0.5
	add_child(instance)

func _model(asset: String, anchor: Vector3, yaw := 0.0, size := Vector3.ZERO, hang := false) -> void:
	var scene := load("res://assets/furniture/%s/%s.glb" % [asset, asset]) as PackedScene
	var model := scene.instantiate() as Node3D
	var mount := Node3D.new()
	mount.name = asset
	mount.add_child(model)
	model.rotation.y = yaw
	if asset.begins_with("tree_"):
		_prepare_tree(model)
	# Meça após girar para ajustar nos eixos do volume oficial.
	var bounds := _mesh_bounds(model, model.transform)
	if size != Vector3.ZERO:
		mount.scale = size / bounds.size
	var pivot := bounds.get_center()
	pivot.y = bounds.end.y if hang else bounds.position.y
	mount.position = anchor - pivot * mount.scale
	add_child(mount, true)


func _prepare_tree(node: Node) -> void:
	# A folhagem usa COLOR_0 (verde) e alpha MASK; o pack guarda o alpha do vértice em 0.
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh:
			for surface in mesh.get_surface_count():
				var material := mesh_instance.get_active_material(surface)
				if material is StandardMaterial3D:
					var prepared := material.duplicate() as StandardMaterial3D
					prepared.vertex_color_use_as_albedo = true
					if prepared.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
						prepared.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
						prepared.alpha_scissor_threshold = 0.4
						prepared.cull_mode = BaseMaterial3D.CULL_DISABLED
					mesh_instance.set_surface_override_material(surface, prepared)
	for child in node.get_children():
		_prepare_tree(child)

func _mesh_bounds(node: Node3D, relative: Transform3D) -> AABB:
	var bounds := AABB()
	if node is MeshInstance3D:
		bounds = relative * node.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var child_bounds := _mesh_bounds(child, relative * child.transform)
			if child_bounds.has_volume():
				bounds = bounds.merge(child_bounds) if bounds.has_volume() else child_bounds
	return bounds
