extends Node3D
## Apresentação do térreo. Os volumes de colisão continuam no mapa compartilhado.

const SalaoMap = ArenaRules.SalaoMap

var _wood := StandardMaterial3D.new()
var _tile := StandardMaterial3D.new()

func build(greyboxes: Dictionary) -> void:
	_wood.albedo_color = Color(0.29, 0.15, 0.075)
	_tile.albedo_color = Color(0.49, 0.43, 0.34)

	_model("chandelier_01", Vector3(8, 7, 8), 0.0, Vector3.ZERO, true)
	_model("sofa_03", Vector3(0.47, 0, 11.5), PI / 2)
	_model("gothic_coffee_table", Vector3(1.94, 0, 11.5))

	_table(Vector3(-2.6, 0, 12.2), Vector3(1.2, 0.75, 0.7))
	_model("lampara_ar", Vector3(-2.9, 0.75, 12.2))

	# Preserve os dois pontos de arma na cozinha, junto à parede leste.
	for z in [8.15, 10.25, 10.9, 11.55, 12.2]:
		_model("kitchen_cabinet", Vector3(26.17, 0, z), -PI / 2)
	_model("steel_shelves", Vector3(16.88, 0, 11.75), PI / 2)
	_model("washer", Vector3(26.1, 0, 13.35), -PI / 2)
	_model("coffee_cart", Vector3(24.25, 0, 12.55), -PI / 2)

	_model("lampara_ar", Vector3(-8, 0, 16.3))
	_model("toilet", Vector3(4.6, 0, 22.8), -PI / 2)

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
			"planta_a":
				_model("tree_medium", floor_center, 0, Vector3(0.63, size.y, 0.78))
			"planta_b":
				_model("tree_large", floor_center, 0, Vector3(1.54, size.y, 1.59))
			_:
				continue
		(greyboxes[id] as MeshInstance3D).hide()

func _bookshelves(area: Rect2, height: float) -> void:
	var segment := area.size.y / 5.0
	var x := area.position.x + 0.35
	for index in 5:
		var z := area.position.y + segment * (index + 0.5)
		_model("wooden_bookshelf", Vector3(x, 0, z), PI / 2, Vector3(0.7, height, segment))
		if index % 2 == 0:
			# Tampos medidos nas prateleiras do modelo de 2,06 m.
			for shelf_y in [0.66, 1.26]:
				_model("book_set", Vector3(x + 0.17, height * shelf_y / 2.06, z), PI / 2)

func _dining(area: Rect2, center: Vector3, size: Vector3) -> void:
	_table(center, size)
	for index in 3:
		var x := area.position.x + area.size.x * (index + 0.5) / 3.0
		_model("dining_chair", Vector3(x, 0, area.position.y + 0.08))
		_model("dining_chair", Vector3(x, 0, area.end.y - 0.08), PI)
	_model("brass_goblets", center + Vector3(-1, size.y, 0))
	_model("tea_set", center + Vector3(0.8, size.y, 0))
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
	# Meça após girar para ajustar nos eixos do volume oficial.
	var bounds := _mesh_bounds(model, model.transform)
	if size != Vector3.ZERO:
		mount.scale = size / bounds.size
	var pivot := bounds.get_center()
	pivot.y = bounds.end.y if hang else bounds.position.y
	mount.position = anchor - pivot * mount.scale
	add_child(mount, true)

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
