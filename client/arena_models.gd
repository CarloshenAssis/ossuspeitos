class_name ArenaModels
extends RefCounted

## Modelos visuais da arena: personagem visto pelos outros, pistola na mão e
## pickups de arma e munição. Apresentação pura: nenhum nó tem colisão, e
## posição, rotação e visibilidade vêm sempre do estado oficial aplicado pela
## `ArenaView` (snapshot, inventário privado, `public_pickups` e roster).
##
## Personagem: um dos oito GLBs de `res://assets/characters/` (pacote
## de Quaternius), escolhido pela aparência cosmética pública do roster,
## nunca pelo papel. Pickups têm brilho frio (arma, ciano) ou quente
## (munição, cobre; o amarelo segue exclusivo dos caixotes baixos).
##
## Troca de pistola ou caixa de munição: se existir uma cena em
## `OVERRIDES[chave]` ela é instanciada no lugar da versão procedural, sem
## colisão.

const OVERRIDES := {
	"pistol": "res://assets/models/pistol.tscn",
	"ammo_box": "res://assets/models/ammo_box.tscn",
}

const VISOR := Color(0.03, 0.03, 0.04)
const GUNMETAL := Color(0.16, 0.17, 0.19)
const GRIP := Color(0.24, 0.16, 0.11)
const WEAPON_GLOW := Color(0.3, 0.85, 0.95)
const AMMO_GLOW := Color(0.95, 0.4, 0.32)
const HEALTH_GLOW := Color(0.95, 0.2, 0.22)
const CRATE := Color(0.25, 0.2, 0.14)
const HEALTH_BOX := Color(0.86, 0.86, 0.88)
const BRASS := Color(0.78, 0.6, 0.3)

## Nome do nó com o GLB dentro da raiz do avatar.
const CHARACTER_MODEL := "CharacterModel"
## GLBs animados com Skeleton3D, origem nos pés, +Y para cima e frente em +Z.
## A posição oficial fica acima do piso e a frente da câmera é -Z.
const CHARACTER_OFFSET := Vector3(0.0, -MovementRules.PLAYER_HEIGHT, 0.0)
const CHARACTER_YAW := PI
## Entrada de pitch aplicada ao osso Head depois de amostrar a animação.
const HEAD_PIVOT := "HeadPivot"
const HEAD_PIVOT_HEIGHT := 1.57
## Inclinação natural da cabeça: a mira pode ir além (MAX_PITCH), a cabeça não.
const HEAD_PITCH_LIMIT := deg_to_rad(40.0)

## Raiz do avatar (recebe posição e yaw oficiais) com o GLB da aparência
## pública. `appearance_id` fora da allowlist cai no padrão.
static func build_character(appearance_id: Variant) -> Node3D:
	var root := Node3D.new()
	root.name = "Character"
	var clean := CharacterAppearance.sanitize(appearance_id)
	root.set_meta("appearance", clean)
	var model := _instantiate_character(clean)
	model.name = CHARACTER_MODEL
	model.position = CHARACTER_OFFSET
	model.rotation.y = CHARACTER_YAW
	var pivot := Node3D.new()
	pivot.name = HEAD_PIVOT
	pivot.position.y = HEAD_PIVOT_HEIGHT
	model.add_child(pivot)
	root.add_child(model)
	return root

## Instancia o GLB importado; se o cache ainda não existir (o `--editor --quit`
## do CI pode abortar o scan), lê o arquivo-fonte com GLTFDocument.
static func _instantiate_character(appearance_id: String) -> Node3D:
	var path := CharacterAppearance.scene_path(appearance_id)
	if _imported_scene_ready(path):
		var scene := load(path) as PackedScene
		if scene != null:
			var model := scene.instantiate() as Node3D
			if model != null:
				return model
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) == OK:
		var generated := document.generate_scene(state) as Node3D
		if generated != null:
			return generated
	return Node3D.new()

static func _imported_scene_ready(path: String) -> bool:
	var import_path := "%s.import" % path
	if not FileAccess.file_exists(import_path):
		return false
	var cfg := ConfigFile.new()
	if cfg.load(import_path) != OK:
		return false
	var dest := str(cfg.get_value("remap", "path", ""))
	return not dest.is_empty() and FileAccess.file_exists(dest)


## Limites da malha já deformada, em coordenadas globais.
static func posed_mesh_bounds(mesh: MeshInstance3D) -> AABB:
	var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
	if mesh.skin == null or skeleton == null:
		return mesh.global_transform * mesh.get_aabb()
	var bind_transforms: Array[Transform3D] = []
	for bind in mesh.skin.get_bind_count():
		var bind_name := mesh.skin.get_bind_name(bind)
		var bone := skeleton.find_bone(bind_name) if bind_name != &"" else mesh.skin.get_bind_bone(bind)
		bind_transforms.append(skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
	# Calcula a pose também no servidor de renderização dummy dos testes.
	var bounds := AABB()
	var has_vertex := false
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		@warning_ignore("integer_division")
		var influences := bones.size() / vertices.size()
		for index in vertices.size():
			var vertex := Vector3.ZERO if influences > 0 else vertices[index]
			for influence in influences:
				var slot := index * influences + influence
				if weights[slot] > 0.0:
					vertex += (bind_transforms[bones[slot]] * vertices[index]) * weights[slot]
			vertex = mesh.global_transform * vertex
			bounds = bounds.expand(vertex) if has_vertex else AABB(vertex, Vector3.ZERO)
			has_vertex = true
	return bounds


## Rotação da cabeça (no pivô) para um pitch oficial. O modelo olha para +Z
## no próprio espaço; girar em X com ângulo negativo levanta o rosto.
static func head_rotation_for_pitch(pitch: float) -> float:
	return -clampf(MovementRules.clamp_pitch(pitch), -HEAD_PITCH_LIMIT, HEAD_PITCH_LIMIT)

## Pistola com o cano em -Z local (mesma frente da câmera).
static func build_pistol() -> Node3D:
	var root := Node3D.new()
	root.name = "Pistol"
	var override := _override("pistol")
	if override != null:
		root.add_child(override)
		return root
	_part(root, "Slide", _box(Vector3(0.05, 0.05, 0.26)), Vector3(0.0, 0.03, -0.02), GUNMETAL.lightened(0.1))
	_part(root, "Frame", _box(Vector3(0.045, 0.035, 0.22)), Vector3(0.0, -0.01, -0.01), GUNMETAL)
	var grip := _part(root, "Grip", _box(Vector3(0.045, 0.14, 0.07)), Vector3(0.0, -0.08, 0.07), GRIP)
	grip.rotation.x = -0.28
	_part(root, "TriggerGuard", _box(Vector3(0.012, 0.035, 0.06)), Vector3(0.0, -0.045, -0.005), GUNMETAL)
	_part(root, "Muzzle", _cylinder(0.014, 0.014, 0.02), Vector3(0.0, 0.03, -0.155), VISOR).rotation.x = PI * 0.5
	_part(root, "FrontSight", _box(Vector3(0.008, 0.014, 0.012)), Vector3(0.0, 0.062, -0.135), WEAPON_GLOW, 0.6)
	return root

const AUG_SCENE := "res://assets/weapons/aug_a4/aug_a4.glb"
const AUG_WORLD_SCALE := 0.10
const AUG_HELD_SCALE := 0.055

static func build_aug(model_scale: float = AUG_WORLD_SCALE) -> Node3D:
	var root := Node3D.new()
	root.name = "Aug"
	var scene := load(AUG_SCENE) as PackedScene if ResourceLoader.exists(AUG_SCENE) else null
	if scene == null:
		return build_pistol()
	var model := scene.instantiate() as Node3D
	# O eixo longo do glTF é +X; gira para a boca apontar a -Z da visão.
	model.scale = Vector3.ONE * model_scale
	model.rotation.y = PI * 0.5
	root.add_child(model)
	return root

const RIFLE_SCENE := "res://assets/weapons/bolt_action_rifle_7_62/bolt_action_rifle_7_62.glb"
const RIFLE_WORLD_SCALE := 0.75
const RIFLE_HELD_SCALE := 0.35

static func build_hunting_rifle(model_scale: float = RIFLE_WORLD_SCALE) -> Node3D:
	var root := Node3D.new()
	root.name = "HuntingRifle"
	var scene := load(RIFLE_SCENE) as PackedScene if ResourceLoader.exists(RIFLE_SCENE) else null
	if scene == null:
		return build_pistol()
	var model := scene.instantiate() as Node3D
	# O eixo longo do glTF é +X; gira para a boca apontar a -Z da visão.
	model.scale = Vector3.ONE * model_scale
	model.rotation.y = PI * 0.5
	root.add_child(model)
	return root

static func build_held_weapon(weapon_id: String) -> Node3D:
	if weapon_id == "aug":
		return build_aug(AUG_HELD_SCALE)
	if weapon_id == "hunting_rifle":
		return build_hunting_rifle(RIFLE_HELD_SCALE)
	return build_pistol()

static func muzzle_offset(weapon_id: String) -> Vector3:
	if weapon_id == "aug":
		return Vector3(0.0, 0.02, -0.32)
	if weapon_id == "hunting_rifle":
		return Vector3(0.0, 0.02, -0.22)
	return Vector3(0.0, 0.03, -0.19)

## Deslocamento e escala da arma na câmera. A pistola permanece no enquadramento
## original; o rifle e a AUG, mais longos, aproximam-se um pouco do canto
## inferior direito para não parecerem miniaturas a 0,5 m.
const VIEWMODEL_OFFSET := Vector3(0.19, -0.16, -0.5)
const VIEWMODEL_SCALE := 0.8

static func viewmodel_offset(weapon_id: String) -> Vector3:
	if weapon_id == "hunting_rifle":
		return Vector3(0.18, -0.12, -0.36)
	if weapon_id == "aug":
		return Vector3(0.20, -0.14, -0.40)
	return VIEWMODEL_OFFSET

static func viewmodel_scale(weapon_id: String) -> float:
	if weapon_id == "hunting_rifle":
		return 0.95
	if weapon_id == "aug":
		return 0.88
	return VIEWMODEL_SCALE

## Arma no chão: pistola procedural, AUG ou rifle, deitada sobre um halo ciano.
static func build_weapon_pickup(weapon_id: String = "common_pistol") -> Node3D:
	var root := Node3D.new()
	root.name = "WeaponPickup"
	_halo(root, WEAPON_GLOW, 0.28, 0.45)
	var spin := Node3D.new()
	spin.name = "Spin"
	root.add_child(spin)
	var gun: Node3D
	if weapon_id == "aug":
		gun = build_aug(AUG_WORLD_SCALE)
	elif weapon_id == "hunting_rifle":
		gun = build_hunting_rifle(RIFLE_WORLD_SCALE)
	else:
		gun = build_pistol()
		gun.scale = Vector3.ONE * 2.4
	gun.rotation = Vector3(0.0, 0.0, PI * 0.5)
	# The official pickup point sits 0.25 m above the floor; drop the longer
	# rifles onto the halo instead of leaving them floating at that height.
	if weapon_id == "hunting_rifle":
		gun.position = Vector3(0.0, -0.14, 0.0)
	elif weapon_id == "aug":
		gun.position = Vector3(0.0, -0.06, 0.0)
	else:
		gun.position = Vector3(0.0, 0.05, 0.0)
	spin.add_child(gun)
	_glow_all(gun, WEAPON_GLOW, 0.25)
	return root

## Caixa de munição: caixote escuro com pontas de latão à mostra e halo cobre.
static func build_ammo_pickup() -> Node3D:
	var root := Node3D.new()
	root.name = "AmmoPickup"
	_halo(root, AMMO_GLOW, 0.30, 0.50)
	var spin := Node3D.new()
	spin.name = "Spin"
	root.add_child(spin)
	var override := _override("ammo_box")
	if override != null:
		spin.add_child(override)
		return root
	_part(spin, "Crate", _box(Vector3(0.4, 0.22, 0.28)), Vector3(0.0, -0.1, 0.0), CRATE)
	_part(spin, "Lid", _box(Vector3(0.42, 0.03, 0.3)), Vector3(0.0, 0.02, 0.0), CRATE.darkened(0.3))
	_part(spin, "Stripe", _box(Vector3(0.41, 0.05, 0.285)), Vector3(0.0, -0.1, 0.0), AMMO_GLOW, 0.8)
	for column in 3:
		for row in 2:
			_part(spin, "Round%d" % (column * 2 + row), _cylinder(0.022, 0.028, 0.09), Vector3(-0.1 + 0.1 * column, 0.08, -0.06 + 0.12 * row), BRASS, 0.15)
	return root

## Caixa de vida: caixote claro com cruz vermelha e halo vermelho. Sem modelo
## CC0 no repositório; a forma é procedural, no mesmo padrão da munição.
static func build_health_pickup() -> Node3D:
	var root := Node3D.new()
	root.name = "HealthPickup"
	_halo(root, HEALTH_GLOW, 0.32, 0.70)
	var spin := Node3D.new()
	spin.name = "Spin"
	root.add_child(spin)
	_part(spin, "Crate", _box(Vector3(0.36, 0.24, 0.36)), Vector3(0.0, -0.1, 0.0), HEALTH_BOX)
	_part(spin, "CrossV", _box(Vector3(0.08, 0.04, 0.28)), Vector3(0.0, 0.03, 0.0), HEALTH_GLOW, 1.05)
	_part(spin, "CrossH", _box(Vector3(0.28, 0.04, 0.08)), Vector3(0.0, 0.03, 0.0), HEALTH_GLOW, 1.05)
	return root

# --- Peças -------------------------------------------------------------------------

static var _materials: Dictionary = {}

static func _material(color: Color, glow: float) -> StandardMaterial3D:
	var key := "%s/%.2f" % [color.to_html(), glow]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	_materials[key] = material
	return material

static func _part(parent: Node3D, part_name: String, mesh: Mesh, position: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = part_name
	node.mesh = mesh
	node.material_override = _material(color, glow)
	node.position = position
	parent.add_child(node)
	return node

## Disco luminoso rente ao chão sob o pickup (a posição oficial fica 0,25 m
## acima do piso).
static func _halo(root: Node3D, color: Color, radius: float = 0.45, energy: float = 0.9) -> void:
	# Acima das placas de região (0,02 m), para não sumir sob elas.
	var halo := _part(root, "Halo", _cylinder(radius, radius, 0.01), Vector3(0.0, -0.215, 0.0), color.darkened(0.2), energy)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _glow_all(root: Node, color: Color, energy: float) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var override := mesh_node.material_override as StandardMaterial3D
		if override == null:
			continue
		mesh_node.material_override = _material(override.albedo_color.lerp(color, 0.25), energy)

static func _override(key: String) -> Node3D:
	var path := str(OVERRIDES.get(key, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	return scene.instantiate() as Node3D if scene != null else null

static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 16
	return mesh
