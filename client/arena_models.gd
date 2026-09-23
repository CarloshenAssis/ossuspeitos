class_name ArenaModels
extends RefCounted

## Modelos visuais da arena: personagem visto pelos outros, pistola na mão e
## pickups de arma e munição. Apresentação pura: nenhum nó tem colisão, e
## posição, rotação e visibilidade vêm sempre do estado oficial aplicado pela
## `ArenaView` (snapshot, inventário privado e `public_pickups`).
##
## Direção visual "mistério": silhuetas escuras de sobretudo e chapéu, rosto
## sem traços, só um acento de cor por jogador (cachecol e fita do
## chapéu) para diferenciar pessoas, nunca papéis. Pickups têm brilho frio
## (arma, ciano) ou quente (munição, cobre; o amarelo segue exclusivo dos
## caixotes baixos) para serem achados no escuro.
##
## Troca de modelo (fase posterior): se existir uma cena em `OVERRIDES[chave]`
## ela é instanciada no lugar da versão procedural. O personagem precisa
## manter a frente em -Z local e um filho `FacingVisor`, e nenhum modelo pode
## trazer colisão.

const OVERRIDES := {
	"character": "res://assets/models/character.tscn",
	"pistol": "res://assets/models/pistol.tscn",
	"ammo_box": "res://assets/models/ammo_box.tscn",
}

const COAT := Color(0.12, 0.12, 0.14)
const COAT_SHADE := Color(0.08, 0.08, 0.1)
const HAT := Color(0.07, 0.07, 0.08)
const SKIN := Color(0.46, 0.43, 0.4)
const VISOR := Color(0.03, 0.03, 0.04)
const GUNMETAL := Color(0.16, 0.17, 0.19)
const GRIP := Color(0.24, 0.16, 0.11)
const WEAPON_GLOW := Color(0.3, 0.85, 0.95)
const AMMO_GLOW := Color(0.95, 0.4, 0.32)
const CRATE := Color(0.25, 0.2, 0.14)
const BRASS := Color(0.78, 0.6, 0.3)

## Frente do personagem (-Z local), na altura dos olhos: faixa escura sobre o
## rosto. A `ArenaView` oculta o modelo do alvo observado pelo espectador.
const VISOR_OFFSET := Vector3(0.0, 0.76, -0.19)

## Acento discreto e estável por jogador (identidade, não papel).
static func accent_for(peer_id: int) -> Color:
	return Color.from_hsv(fmod(float(peer_id) * 0.173, 1.0), 0.5, 0.8)

## Personagem com o centro do corpo na origem (posição oficial) e 2 m de
## altura, como a cápsula anterior; pés em y = -1.
static func build_character(peer_id: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Character"
	var override := _override("character")
	if override != null:
		root.add_child(override)
		return root
	var accent := accent_for(peer_id)
	for side in [-1.0, 1.0]:
		var suffix := "L" if side < 0.0 else "R"
		_part(root, "Leg" + suffix, _cylinder(0.1, 0.1, 0.5), Vector3(0.13 * side, -0.75, 0.0), COAT_SHADE)
		_part(root, "Arm" + suffix, _capsule(0.085, 0.78), Vector3(0.36 * side, 0.08, 0.0), COAT)
	_part(root, "CoatSkirt", _cylinder(0.3, 0.44, 0.65), Vector3(0.0, -0.4, 0.0), COAT)
	_part(root, "Torso", _capsule(0.3, 1.0), Vector3(0.0, 0.08, 0.0), COAT)
	# Lapelas: duas faixas claras só na frente, reforçam o sentido do corpo.
	for side in [-1.0, 1.0]:
		var lapel := _part(root, "LapelL" if side < 0.0 else "LapelR", _box(Vector3(0.08, 0.36, 0.03)), Vector3(0.08 * side, 0.32, -0.28), COAT_SHADE.lightened(0.25))
		lapel.rotation.z = 0.25 * side
	_part(root, "Scarf", _torus(0.14, 0.26), Vector3(0.0, 0.56, 0.0), accent)
	_part(root, "Head", _sphere(0.19), Vector3(0.0, 0.76, 0.0), SKIN)
	_part(root, "FacingVisor", _box(Vector3(0.3, 0.07, 0.06)), VISOR_OFFSET, VISOR)
	_part(root, "HatBrim", _cylinder(0.33, 0.33, 0.025), Vector3(0.0, 0.92, 0.0), HAT)
	_part(root, "HatCrown", _cylinder(0.16, 0.19, 0.17), Vector3(0.0, 1.0, 0.0), HAT)
	_part(root, "HatBand", _cylinder(0.195, 0.195, 0.04), Vector3(0.0, 0.94, 0.0), accent)
	return root

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

## Pistola no chão: a mesma arma deitada sobre um halo ciano.
static func build_weapon_pickup() -> Node3D:
	var root := Node3D.new()
	root.name = "WeaponPickup"
	_halo(root, WEAPON_GLOW)
	var spin := Node3D.new()
	spin.name = "Spin"
	root.add_child(spin)
	var pistol := build_pistol()
	pistol.scale = Vector3.ONE * 2.4
	pistol.rotation = Vector3(0.0, 0.0, PI * 0.5)
	pistol.position = Vector3(0.0, 0.05, 0.0)
	spin.add_child(pistol)
	_glow_all(pistol, WEAPON_GLOW, 0.25)
	return root

## Caixa de munição: caixote escuro com pontas de latão à mostra e halo cobre.
static func build_ammo_pickup() -> Node3D:
	var root := Node3D.new()
	root.name = "AmmoPickup"
	_halo(root, AMMO_GLOW)
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
static func _halo(root: Node3D, color: Color) -> void:
	# Acima das placas de região (0,02 m), para não sumir sob elas.
	var halo := _part(root, "Halo", _cylinder(0.45, 0.45, 0.01), Vector3(0.0, -0.215, 0.0), color.darkened(0.2), 0.9)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _glow_all(root: Node, color: Color, energy: float) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var base := (mesh_node.material_override as StandardMaterial3D).albedo_color
		mesh_node.material_override = _material(base.lerp(color, 0.25), energy)

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

static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	return mesh

static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings = 12
	return mesh

static func _torus(inner: float, outer: float) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	return mesh
