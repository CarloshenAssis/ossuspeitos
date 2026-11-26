extends RefCounted
## Pintura e iluminação noturna da variante Nocturna. Só apresentação.

const TEX := "res://assets/textures/nocturna/%s.webp"
const WALL_SHADER := preload("res://client/nocturna_wall.gdshader")
const LANDING_SHADER := preload("res://client/nocturna_landing.gdshader")

static var _mats: Dictionary = {}
static var _wall_ground: ShaderMaterial
static var _wall_upper: ShaderMaterial
static var _landing: ShaderMaterial


static func apply_night(env: Environment, sun: DirectionalLight3D) -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.025, 0.03, 0.055)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.52, 0.72)
	env.ambient_light_energy = 0.40
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.12
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.10, 0.16)
	env.fog_density = 0.0032
	env.fog_sky_affect = 0.0
	sun.rotation_degrees = Vector3(-48.0, 38.0, 0.0)
	sun.light_color = Color(0.62, 0.73, 0.95)
	sun.light_energy = 0.22
	sun.shadow_enabled = false
	sun.name = "NocturnaMoon"


static func add_lights(root: Node3D) -> void:
	# Lustres (5) + uma lâmpada representativa por cômodo + acesso ao jardim.
	# 17 omni, sem sombra. Compatibility acende no máximo 8 omni por objeto;
	# as meshes continuam caixas separadas, então o teto global pode ser um
	# pouco maior. Novas lâmpadas ficam de alcance curto.
	var warm := Color(1.0, 0.78, 0.52)
	var garden := Color(0.92, 0.84, 0.68)
	var lamps: Array = [
		{"p": Vector3(8.0, 5.7, 8.0), "r": 11.0, "e": 2.15, "c": warm},
		{"p": Vector3(8.0, 5.7, 1.0), "r": 7.0, "e": 1.55, "c": warm},
		{"p": Vector3(12.5, 3.15, 20.25), "r": 7.5, "e": 1.75, "c": warm},
		{"p": Vector3(-5.5, 6.15, 6.8), "r": 6.5, "e": 1.55, "c": warm},
		{"p": Vector3(30.3, 6.15, 11.0), "r": 6.5, "e": 1.55, "c": warm},
		{"p": Vector3(3.1, 2.05, 13.55), "r": 5.0, "e": 0.95, "c": warm},
		{"p": Vector3(-2.6, 1.95, 12.2), "r": 7.0, "e": 1.35, "c": warm},
		{"p": Vector3(21.25, 2.35, 11.5), "r": 6.0, "e": 1.15, "c": warm},
		{"p": Vector3(-8.15, 1.55, 16.7), "r": 4.5, "e": 0.9, "c": warm},
		{"p": Vector3(3.7, 1.7, 16.45), "r": 4.8, "e": 1.15, "c": warm},
		{"p": Vector3(4.45, 1.7, 20.55), "r": 5.8, "e": 1.20, "c": warm},
		{"p": Vector3(-2.2, 1.85, 22.6), "r": 5.5, "e": 1.10, "c": warm},
		{"p": Vector3(12.0, 2.25, 26.2), "r": 6.0, "e": 0.9, "c": garden},
		{"p": Vector3(21.0, 5.05, 8.6), "r": 6.0, "e": 1.15, "c": warm},
		{"p": Vector3(-7.85, 4.55, 0.5), "r": 5.5, "e": 1.15, "c": warm},
		{"p": Vector3(28.4, 4.55, 5.5), "r": 6.0, "e": 1.15, "c": warm},
		{"p": Vector3(0.8, 1.85, 27.7), "r": 4.2, "e": 1.05, "c": garden},
	]
	for spec in lamps:
		var light := OmniLight3D.new()
		light.position = spec["p"]
		light.light_color = spec["c"]
		light.light_energy = float(spec["e"])
		light.omni_range = float(spec["r"])
		light.shadow_enabled = false
		light.light_specular = 0.35
		root.add_child(light)


static func material_for(blocker: Dictionary) -> Material:
	var kind := str(blocker.get("kind", ""))
	var id := str(blocker.get("id", ""))
	var space := str(blocker.get("space", ""))
	if kind == "ceiling":
		return _triplanar("ceiling", "grey_plaster", Color(0.26, 0.24, 0.22), 0.55, 0.92)
	if kind == "wall" or kind == "lintel":
		return _wall_material(_floor_y_of(blocker))
	if bool(blocker.get("walkable", false)) or id.begins_with("piso_"):
		var center: Vector3 = blocker["center"]
		if center.y > 2.0:
			return _landing_material()
		return floor_material(space, id)
	if id.begins_with("lance_") or id.begins_with("escada_") or id.begins_with("corrimao_"):
		return _triplanar("wood", "dark_paneled_wood", Color(0.55, 0.4, 0.28), 0.7, 0.72)
	if id.begins_with("coluna_"):
		return _wall_material(_floor_y_of(blocker))
	return _triplanar("prop", "dark_paneled_wood", Color(0.45, 0.32, 0.22), 0.8, 0.75)


static func floor_material(space: String, id := "") -> Material:
	if id == "patamar_servico" or space in ["corredor_oeste", "corredor_leste"]:
		space = "corredor"
	if space in ["lavabo", "cozinha"]:
		return _triplanar("tiles", "floor_tiles_06", Color(0.72, 0.7, 0.66), 0.55, 0.55)
	if space == "banheiro_marmore":
		return _triplanar("marble", "marble_01", Color(0.78, 0.8, 0.84), 0.7, 0.4)
	if space in ["jardim_inverno", "jardim_acesso"]:
		return _triplanar("terra", "terracotta_floor_tiles", Color(0.75, 0.62, 0.5), 0.65, 0.7)
	return _triplanar("wood_floor", "herringbone_parquet", Color(0.55, 0.42, 0.32), 0.45, 0.75)


static func _floor_y_of(blocker: Dictionary) -> float:
	var center: Vector3 = blocker["center"]
	var size: Vector3 = blocker["size"]
	return 3.5 if (center.y - size.y * 0.5) >= 3.0 else 0.0


static func _wall_material(floor_y: float) -> ShaderMaterial:
	if floor_y >= 3.0:
		if _wall_upper == null:
			_wall_upper = _make_wall(3.5)
		return _wall_upper
	if _wall_ground == null:
		_wall_ground = _make_wall(0.0)
	return _wall_ground


static func _make_wall(floor_y: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WALL_SHADER
	mat.set_shader_parameter("plaster", _tex("painted_plaster_wall"))
	mat.set_shader_parameter("panel", _tex("dark_paneled_wood"))
	mat.set_shader_parameter("floor_y", floor_y)
	return mat


static func _triplanar(key: String, texture: String, tint: Color, scale: float, roughness: float) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.resource_name = key
	mat.albedo_color = tint
	mat.albedo_texture = _tex(texture)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_triplanar_sharpness = 4.0
	mat.uv1_scale = Vector3.ONE * scale
	mat.roughness = roughness
	mat.metallic = 0.02 if key == "marble" else 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mats[key] = mat
	return mat



static func _landing_material() -> ShaderMaterial:
	if _landing != null:
		return _landing
	var mat := ShaderMaterial.new()
	mat.shader = LANDING_SHADER
	mat.set_shader_parameter("top_tex", _tex("herringbone_parquet"))
	mat.set_shader_parameter("bottom_tex", _tex("grey_plaster"))
	_landing = mat
	return mat

static func _tex(name: String) -> Texture2D:
	return load(TEX % name) as Texture2D
