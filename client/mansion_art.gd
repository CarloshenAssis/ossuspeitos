class_name MansionArt
extends RefCounted

## Identidade visual da mansão (fase 2): mansão estilizada low-poly com gesso
## creme fosco, lambris de madeira, pisos por ambiente e pontos de luz quente.
## Apresentação pura. A geometria física continua a de `MansionMap` /
## `ArenaRules.BLOCKERS`: cada volume oficial é desenhado com o mesmo centro e
## tamanho, e toda decoração fica colada às paredes, acima das cabeças, sobre
## móveis ou rente ao piso, sem ocupar caminho livre (ver `mansion_art_test`).
##
## Tudo é caixa: geometria agrupada por espaço e material num único
## `ArrayMesh`, o que mantém poucos draw calls e poucas luzes por malha
## (o renderer Compatibility aplica no máximo 8 luzes por objeto). Texturas são
## procedurais, pequenas e geradas no próprio projeto; nada é baixado.
##
## `items` registra cada peça: `{kind, space, id, aabb}`. Tipos:
## - `blocker`: volume oficial (parede, verga, teto ou peça de móvel), idêntico;
## - `furniture`: detalhe dentro do volume oficial de um móvel (`id`);
## - `floor`: piso e tapetes, com topo no máximo 3 cm acima do piso;
## - `trim`: lambri, rodapé, molduras, quadros e espelhos, colados à parede;
## - `fixture`: arandelas e lustre, sempre acima de qualquer cabeça;
## - `prop`: objetos sobre móveis ou encostados neles (`id` do móvel).

const WAINSCOT_HEIGHT := 1.0
const TRIM_DEPTH := 0.04
const RAIL_DEPTH := 0.06
const CASING_WIDTH := 0.12
const FIXTURE_MIN_Y := 2.05
const CEILING_KIND := "ceiling"

var items: Array = []
var lights: Array = []
var meshes: Array = []
var _batches: Dictionary = {}
var _root: Node3D

# --- Materiais -------------------------------------------------------------------

static var _materials: Dictionary = {}

## Material compartilhado por nome. Pisos e paredes usam mapeamento triplanar em
## coordenadas do mundo: a textura tem escala real (1 m) em qualquer caixa.
static func material(key: String) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var spec: Dictionary = MATERIALS.get(key, {"color": Color.MAGENTA})
	var result := StandardMaterial3D.new()
	result.resource_name = key
	result.albedo_color = spec["color"]
	result.roughness = float(spec.get("roughness", 0.9))
	result.metallic = float(spec.get("metallic", 0.0))
	if spec.has("glow"):
		result.emission_enabled = true
		result.emission = spec["color"]
		result.emission_energy_multiplier = float(spec["glow"])
	if spec.has("texture"):
		result.albedo_texture = _texture(str(spec["texture"]))
		result.uv1_triplanar = true
		result.uv1_world_triplanar = true
		result.uv1_scale = Vector3.ONE * float(spec.get("scale", 1.0))
		result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS if str(spec["texture"]) == "checker" else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_materials[key] = result
	return result

const MATERIALS := {
	"plaster": {"color": Color(0.86, 0.8, 0.69)},
	"ceiling": {"color": Color(0.78, 0.74, 0.66)},
	"wainscot": {"color": Color(0.42, 0.26, 0.15), "texture": "panel", "scale": 1.0, "roughness": 0.7},
	"trim": {"color": Color(0.3, 0.18, 0.1), "roughness": 0.6},
	"floor_planks": {"color": Color(0.62, 0.43, 0.27), "texture": "planks", "scale": 0.5, "roughness": 0.75},
	"floor_planks_dark": {"color": Color(0.45, 0.3, 0.19), "texture": "planks", "scale": 0.5, "roughness": 0.75},
	"floor_checker": {"color": Color(1, 1, 1), "texture": "checker", "scale": 0.5, "roughness": 0.45},
	"floor_tile": {"color": Color(0.9, 0.9, 0.86), "texture": "tile", "scale": 1.0, "roughness": 0.5},
	"floor_tile_small": {"color": Color(0.86, 0.9, 0.92), "texture": "tile", "scale": 2.0, "roughness": 0.4},
	"carpet_earth": {"color": Color(0.5, 0.36, 0.26)},
	"carpet_blue": {"color": Color(0.33, 0.4, 0.52)},
	"rug_red": {"color": Color(0.46, 0.13, 0.12)},
	"rug_green": {"color": Color(0.22, 0.34, 0.26)},
	"rug_gold": {"color": Color(0.6, 0.46, 0.26)},
	"wood": {"color": Color(0.45, 0.29, 0.17), "texture": "planks", "scale": 1.0, "roughness": 0.7},
	"wood_dark": {"color": Color(0.26, 0.16, 0.1), "roughness": 0.7},
	"stone": {"color": Color(0.6, 0.57, 0.52)},
	"soot": {"color": Color(0.06, 0.05, 0.05)},
	"ember": {"color": Color(0.95, 0.32, 0.08), "glow": 1.1},
	"cabinet": {"color": Color(0.55, 0.65, 0.6), "roughness": 0.6},
	"counter": {"color": Color(0.9, 0.89, 0.85), "roughness": 0.35},
	"porcelain": {"color": Color(0.94, 0.95, 0.96), "roughness": 0.25},
	"linen": {"color": Color(0.9, 0.88, 0.82)},
	"fabric_earth": {"color": Color(0.62, 0.38, 0.24)},
	"fabric_blue": {"color": Color(0.3, 0.42, 0.62)},
	"velvet": {"color": Color(0.42, 0.1, 0.12)},
	"office_green": {"color": Color(0.24, 0.38, 0.29)},
	"brass": {"color": Color(0.74, 0.58, 0.32), "metallic": 0.6, "roughness": 0.4},
	"glow_warm": {"color": Color(1.0, 0.74, 0.42), "glow": 0.9},
	"glow_green": {"color": Color(0.3, 0.75, 0.35), "glow": 1.2},
	"glass_dark": {"color": Color(0.16, 0.2, 0.24), "roughness": 0.2},
	"book_red": {"color": Color(0.5, 0.14, 0.12)},
	"book_blue": {"color": Color(0.16, 0.26, 0.42)},
	"book_green": {"color": Color(0.2, 0.36, 0.22)},
	"book_tan": {"color": Color(0.62, 0.5, 0.3)},
	"paint_a": {"color": Color(0.72, 0.32, 0.2)},
	"paint_b": {"color": Color(0.2, 0.36, 0.5)},
	"paint_c": {"color": Color(0.86, 0.72, 0.36)},
	"paint_d": {"color": Color(0.18, 0.22, 0.2)},
	"paint_e": {"color": Color(0.55, 0.6, 0.42)},
}

## Texturas procedurais de 64×64 (determinísticas, sem arquivo externo).
static var _textures: Dictionary = {}

static func _texture(key: String) -> Texture2D:
	if _textures.has(key):
		return _textures[key]
	var size := 2 if key == "checker" else 64
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for y in size:
		for x in size:
			var value := 1.0
			match key:
				"checker":
					value = 0.95 if (x + y) % 2 == 0 else 0.2
				"plaster":
					value = 0.93 + rng.randf() * 0.07
				"planks":
					# Tábuas de 16 px (0,25 m com escala 0,5) com juntas e veio.
					var board := x / 16
					var offset := (board * 23) % 64
					value = 0.82 + 0.12 * sin(float(y + offset) * 0.35 + board) * 0.5 + rng.randf() * 0.05
					if x % 16 == 0 or (y + offset) % 64 == 0:
						value = 0.55
				"tile":
					value = 0.97 - rng.randf() * 0.03
					if x % 32 == 0 or y % 32 == 0:
						value = 0.62
				"panel":
					# Almofadas do lambri: moldura mais escura a cada 32 px (0,5 m).
					value = 0.95
					var px := x % 32
					if px < 3 or px > 28 or y < 4 or y > 59:
						value = 0.72
			image.set_pixel(x, y, Color(value, value, value))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture

# --- Montagem ----------------------------------------------------------------------

## Pisos por ambiente (o vermelho da planta é só legenda).
const FLOORS := {
	"salao": "floor_checker", "escritorio": "floor_planks", "biblioteca": "floor_planks_dark",
	"galeria": "floor_planks_dark", "cozinha": "floor_tile", "jantar": "floor_planks",
	"quarto_fundo": "carpet_earth", "quarto_hospedes": "carpet_blue", "banheiro": "floor_tile_small",
}
const CORRIDOR_FLOOR := "floor_planks"

func build(root: Node3D) -> void:
	_root = root
	for entry in MansionMap.SPACES:
		var rect := MansionMap.space_rect(str(entry["id"]))
		_floor_box(str(entry["id"]), rect, str(FLOORS.get(str(entry["id"]), CORRIDOR_FLOOR)))
		_perimeter_trims(entry)
	for door in MansionMap.DOORS:
		var rect := Rect2(door["min"], (door["max"] as Vector2) - (door["min"] as Vector2))
		_floor_box(str(door["room"]), rect, str(FLOORS.get(str(door["room"]), CORRIDOR_FLOOR)))
		_door_casings(door)
	for blocker in ArenaRules.BLOCKERS:
		_official(blocker)
	for item in MansionMap.FURNITURE:
		_furniture_props(item)
	_rugs()
	_paintings()
	_sconces()
	_chandelier()
	_lights()
	_flush()

## Volume oficial. Paredes, vergas, tetos e móveis simples: a própria caixa.
## Móveis com receita (`_compose`): peças que preenchem exatamente o volume
## (a união das caixas é o volume), para que o detalhe apareça por fora.
func _official(blocker: Dictionary) -> void:
	var kind := str(blocker["kind"])
	var id := str(blocker["id"])
	var space_id := str(blocker.get("space", ""))
	if space_id.is_empty():
		space_id = _nearest_space(blocker["center"])
	var box := AABB((blocker["center"] as Vector3) - (blocker["size"] as Vector3) * 0.5, blocker["size"])
	if kind == "furniture":
		items.append({"kind": "volume", "space": space_id, "id": id, "aabb": box, "material": "", "group": ""})
		if not _compose(id, box, space_id):
			_add(space_id, _furniture_material(id), box, "furniture", space_id, id)
		return
	var key := "ceiling" if kind == CEILING_KIND else "plaster"
	var group := space_id + ("|ceiling" if kind == CEILING_KIND else "")
	_add(group, key, box, "blocker", space_id, id)

func _furniture_material(id: String) -> String:
	for prefix in FURNITURE_LOOK:
		if id.begins_with(prefix):
			return FURNITURE_LOOK[prefix]
	return "wood"

## Material do volume principal de cada móvel.
const FURNITURE_LOOK := {
	"escrivaninha": "wood_dark", "estante": "wood_dark", "lareira": "stone", "mesa_leitura": "wood",
	"banco_galeria": "wood_dark", "coluna": "plaster", "pedestal": "wood_dark", "armario_cozinha": "cabinet",
	"bancada": "cabinet", "mesa_jantar": "wood", "aparador": "wood_dark", "cama_fundo": "wood_dark",
	"cama_hospedes": "wood", "armario": "wood_dark", "criado": "wood", "banheira": "porcelain",
	"vaso": "porcelain", "pia": "porcelain",
}

func _floor_box(space_id: String, rect: Rect2, key: String) -> void:
	_add(space_id, key, AABB(Vector3(rect.position.x, -0.1, rect.position.y), Vector3(rect.size.x, 0.1, rect.size.y)), "floor", space_id)

## Lambri, rodapé, guarda-cadeira e sanca ao longo de cada trecho de parede do
## espaço (bordas menos portas e encontros abertos).
func _perimeter_trims(entry: Dictionary) -> void:
	var space_id := str(entry["id"])
	var ceiling := float(entry["ceiling"])
	for segment in wall_segments(space_id):
		var a: Vector2 = segment["from"]
		var b: Vector2 = segment["to"]
		var inward: Vector2 = segment["inward"]
		_strip(space_id, a, b, inward, 0.0, WAINSCOT_HEIGHT, TRIM_DEPTH, "wainscot")
		_strip(space_id, a, b, inward, 0.0, 0.14, 0.05, "trim")
		_strip(space_id, a, b, inward, WAINSCOT_HEIGHT, WAINSCOT_HEIGHT + 0.06, RAIL_DEPTH, "trim")
		_strip(space_id, a, b, inward, ceiling - 0.12, ceiling, RAIL_DEPTH, "trim")

## Faixa colada à parede entre `a` e `b` (na borda do espaço), com `depth`
## para dentro.
func _strip(space_id: String, a: Vector2, b: Vector2, inward: Vector2, bottom: float, top: float, depth: float, key: String, kind: String = "trim") -> void:
	_add(space_id, key, _flat_box(a, b, inward, bottom, top, depth), kind, space_id)

## Trechos de parede de um espaço: cada borda do retângulo menos vãos de porta e
## encontros abertos. `inward` aponta da parede para dentro do espaço.
static func wall_segments(space_id: String) -> Array:
	var rect := MansionMap.space_rect(space_id)
	var edges := [
		{"from": rect.position, "to": Vector2(rect.end.x, rect.position.y), "inward": Vector2(0, 1)},
		{"from": Vector2(rect.position.x, rect.end.y), "to": rect.end, "inward": Vector2(0, -1)},
		{"from": rect.position, "to": Vector2(rect.position.x, rect.end.y), "inward": Vector2(1, 0)},
		{"from": Vector2(rect.end.x, rect.position.y), "to": rect.end, "inward": Vector2(-1, 0)},
	]
	var gaps: Array = []
	for door in MansionMap.DOORS:
		if str(door["room"]) == space_id or str(door["corridor"]) == space_id:
			gaps.append(Rect2(door["min"], (door["max"] as Vector2) - (door["min"] as Vector2)))
	for junction in MansionMap.JUNCTIONS:
		var other := ""
		if str(junction["a"]) == space_id: other = str(junction["b"])
		elif str(junction["b"]) == space_id: other = str(junction["a"])
		if not other.is_empty():
			gaps.append(MansionMap.space_rect(other))
	var result: Array = []
	for edge in edges:
		var a: Vector2 = edge["from"]
		var b: Vector2 = edge["to"]
		var horizontal := absf(a.y - b.y) < 0.0001
		var start := a.x if horizontal else a.y
		var finish := b.x if horizontal else b.y
		var line := a.y if horizontal else a.x
		var cuts: Array = []
		for gap in gaps:
			var g := gap as Rect2
			var touches := (g.position.y <= line + 0.0001 and g.end.y >= line - 0.0001) if horizontal else (g.position.x <= line + 0.0001 and g.end.x >= line - 0.0001)
			if not touches:
				continue
			var lo := g.position.x if horizontal else g.position.y
			var hi := g.end.x if horizontal else g.end.y
			if hi > start and lo < finish:
				cuts.append(Vector2(maxf(lo, start), minf(hi, finish)))
		cuts.sort_custom(func(p, q): return p.x < q.x)
		var cursor := start
		for cut in cuts:
			if cut.x > cursor + 0.001:
				result.append(_segment(horizontal, line, cursor, cut.x, edge["inward"]))
			cursor = maxf(cursor, cut.y)
		if finish > cursor + 0.001:
			result.append(_segment(horizontal, line, cursor, finish, edge["inward"]))
	return result

static func _segment(horizontal: bool, line: float, from: float, to: float, inward: Vector2) -> Dictionary:
	if horizontal:
		return {"from": Vector2(from, line), "to": Vector2(to, line), "inward": inward}
	return {"from": Vector2(line, from), "to": Vector2(line, to), "inward": inward}

## Guarnição de madeira em volta de cada vão, nas duas faces da parede.
func _door_casings(door: Dictionary) -> void:
	var rect := Rect2(door["min"], (door["max"] as Vector2) - (door["min"] as Vector2))
	var across_x := rect.size.x < rect.size.y
	var top := MansionMap.DOOR_HEIGHT
	for side in [-1.0, 1.0]:
		var space_id := str(door["room"])
		# Face voltada para o espaço do lado `side`.
		var face := (rect.end.x if side > 0.0 else rect.position.x) if across_x else (rect.end.y if side > 0.0 else rect.position.y)
		var room_rect := MansionMap.space_rect(str(door["room"]))
		var room_side := (room_rect.get_center().x > rect.get_center().x) if across_x else (room_rect.get_center().y > rect.get_center().y)
		if (side > 0.0) != room_side:
			space_id = str(door["corridor"])
		var inward := Vector2(side, 0.0) if across_x else Vector2(0.0, side)
		var along_lo := rect.position.y if across_x else rect.position.x
		var along_hi := rect.end.y if across_x else rect.end.x
		for jamb in [[along_lo - CASING_WIDTH, along_lo], [along_hi, along_hi + CASING_WIDTH]]:
			var a := Vector2(face, jamb[0]) if across_x else Vector2(jamb[0], face)
			var b := Vector2(face, jamb[1]) if across_x else Vector2(jamb[1], face)
			_strip(space_id, a, b, inward, 0.0, top + CASING_WIDTH, TRIM_DEPTH + 0.02, "trim")
		var head_a := Vector2(face, along_lo - CASING_WIDTH) if across_x else Vector2(along_lo - CASING_WIDTH, face)
		var head_b := Vector2(face, along_hi + CASING_WIDTH) if across_x else Vector2(along_hi + CASING_WIDTH, face)
		_strip(space_id, head_a, head_b, inward, top, top + CASING_WIDTH, TRIM_DEPTH + 0.02, "trim")

# --- Móveis --------------------------------------------------------------------------

## Peça de móvel entre alturas `y0`..`y1`, com recuo lateral `inset`.
func _part(space_id: String, id: String, key: String, box: AABB, y0: float, y1: float, inset: float = 0.0) -> void:
	_add(space_id, key, AABB(Vector3(box.position.x + inset, y0, box.position.z + inset), Vector3(box.size.x - inset * 2.0, y1 - y0, box.size.z - inset * 2.0)), "furniture", space_id, id)

func _part_box(space_id: String, id: String, key: String, lo: Vector3, hi: Vector3) -> void:
	_add(space_id, key, AABB(lo, hi - lo), "furniture", space_id, id)

## Receitas por volume. Retorna falso quando o móvel é desenhado maciço.
func _compose(id: String, box: AABB, space_id: String) -> bool:
	var h := box.end.y
	var p := box.position
	var e := box.end
	if id.begins_with("estante"):
		_bookcase(id, box, space_id)
	elif id == "lareira":
		# Encostada à parede norte: boca da lareira aberta para o sul.
		var inner0 := p.x + 0.35
		var inner1 := e.x - 0.35
		_part_box(space_id, id, "stone", Vector3(p.x, 0.0, p.z), Vector3(inner0, h - 0.15, e.z))
		_part_box(space_id, id, "stone", Vector3(inner1, 0.0, p.z), Vector3(e.x, h - 0.15, e.z))
		_part_box(space_id, id, "stone", Vector3(inner0, 0.85, p.z), Vector3(inner1, h - 0.15, e.z))
		_part_box(space_id, id, "soot", Vector3(inner0, 0.0, p.z), Vector3(inner1, 0.85, p.z + 0.12))
		_part_box(space_id, id, "stone", Vector3(inner0, 0.0, p.z + 0.12), Vector3(inner1, 0.05, e.z))
		_part_box(space_id, id, "ember", Vector3(inner0 + 0.25, 0.05, p.z + 0.18), Vector3(inner1 - 0.25, 0.17, p.z + 0.36))
		_part_box(space_id, id, "wood_dark", Vector3(p.x, h - 0.15, p.z), Vector3(e.x, h, e.z))
	elif id.begins_with("coluna"):
		_part(space_id, id, "wood_dark", box, 0.0, 0.35)
		_part(space_id, id, "plaster", box, 0.35, h - 0.4, 0.06)
		_part(space_id, id, "wood_dark", box, h - 0.4, h)
	elif id == "pedestal":
		_part(space_id, id, "wood_dark", box, 0.0, 0.18)
		_part(space_id, id, "wainscot", box, 0.18, h - 0.06, 0.05)
		_part(space_id, id, "brass", box, h - 0.06, h)
	elif id.begins_with("banco_galeria"):
		_part(space_id, id, "wood_dark", box, 0.0, h - 0.1, 0.03)
		_part(space_id, id, "velvet", box, h - 0.1, h)
	elif id == "armario_cozinha" or id == "bancada":
		_part(space_id, id, "wood_dark", box, 0.0, 0.1)
		_part(space_id, id, "cabinet", box, 0.1, h - 0.05)
		_part(space_id, id, "counter" if id == "bancada" else "wood_dark", box, h - 0.05, h)
	elif id == "aparador" or id.begins_with("criado"):
		_part(space_id, id, "wood_dark" if id == "aparador" else "wood", box, 0.0, h - 0.05)
		_part(space_id, id, "wood" if id == "aparador" else "wood_dark", box, h - 0.05, h)
	elif id.begins_with("armario"):
		_part(space_id, id, "wood_dark", box, 0.0, h - 0.08)
		_part(space_id, id, "wood", box, h - 0.08, h)
	elif id.begins_with("cama"):
		_bed_parts(id, box, space_id)
	elif id == "banheira":
		_part(space_id, id, "porcelain", box, 0.0, 0.12)
		_part_box(space_id, id, "porcelain", Vector3(p.x, 0.12, p.z), Vector3(p.x + 0.08, h, e.z))
		_part_box(space_id, id, "porcelain", Vector3(e.x - 0.08, 0.12, p.z), Vector3(e.x, h, e.z))
		_part_box(space_id, id, "porcelain", Vector3(p.x + 0.08, 0.12, p.z), Vector3(e.x - 0.08, h, p.z + 0.08))
		_part_box(space_id, id, "porcelain", Vector3(p.x + 0.08, 0.12, e.z - 0.08), Vector3(e.x - 0.08, h, e.z))
		_part_box(space_id, id, "glass_dark", Vector3(p.x + 0.08, 0.12, p.z + 0.08), Vector3(e.x - 0.08, h - 0.15, e.z - 0.08))
	elif id == "vaso":
		_part(space_id, id, "porcelain", box, 0.0, h - 0.04, 0.05)
		_part(space_id, id, "linen", box, h - 0.04, h)
	elif id == "pia":
		_part(space_id, id, "porcelain", box, 0.0, h - 0.15, 0.12)
		_part(space_id, id, "porcelain", box, h - 0.15, h)
	else:
		return false
	return true

## Estante: fundo contra a parede, laterais, base e topo fecham o volume; as
## prateleiras e os livros ficam recuados 2 cm da face aberta.
func _bookcase(id: String, box: AABB, space_id: String) -> void:
	var p := box.position
	var e := box.end
	var h := e.y
	var room := MansionMap.space_rect(space_id).get_center()
	var along_z := box.size.x < box.size.z
	var into_room := signf(room.x - box.get_center().x) if along_z else signf(room.y - box.get_center().z)
	if along_z:
		var back_x0 := p.x if into_room > 0.0 else e.x - 0.04
		_part_box(space_id, id, "wood_dark", Vector3(back_x0, 0.0, p.z), Vector3(back_x0 + 0.04, h, e.z))
		_part_box(space_id, id, "wood_dark", Vector3(p.x, 0.0, p.z), Vector3(e.x, h, p.z + 0.04))
		_part_box(space_id, id, "wood_dark", Vector3(p.x, 0.0, e.z - 0.04), Vector3(e.x, h, e.z))
	else:
		var back_z0 := p.z if into_room > 0.0 else e.z - 0.04
		_part_box(space_id, id, "wood_dark", Vector3(p.x, 0.0, back_z0), Vector3(e.x, h, back_z0 + 0.04))
		_part_box(space_id, id, "wood_dark", Vector3(p.x, 0.0, p.z), Vector3(p.x + 0.04, h, e.z))
		_part_box(space_id, id, "wood_dark", Vector3(e.x - 0.04, 0.0, p.z), Vector3(e.x, h, e.z))
	_part(space_id, id, "wood_dark", box, 0.0, 0.1)
	_part(space_id, id, "wood_dark", box, h - 0.05, h)
	var books := ["book_red", "book_blue", "book_green", "book_tan"]
	var levels := 5
	var spacing := (h - 0.15) / levels
	var length := box.size.z if along_z else box.size.x
	var depth := box.size.x if along_z else box.size.z
	for level in levels:
		var y := 0.1 + level * spacing
		if level > 0:
			_add_shelf_board(space_id, id, box, along_z, y)
		var cursor := 0.06
		var index := level * 3
		while true:
			var width := 0.07 + float((index * 7) % 5) * 0.025
			var height := minf(spacing - 0.06, 0.2 + float((index * 3) % 4) * 0.035)
			if cursor + width > length - 0.06:
				break
			var inset := 0.02
			var book_depth := depth - 0.04 - inset - 0.02
			if along_z:
				var x0 := p.x + 0.04 + 0.02 if into_room > 0.0 else p.x + inset
				_part_box(space_id, id, books[index % books.size()], Vector3(x0, y + 0.025, p.z + cursor), Vector3(x0 + book_depth, y + 0.025 + height, p.z + cursor + width))
			else:
				var z0 := p.z + 0.04 + 0.02 if into_room > 0.0 else p.z + inset
				_part_box(space_id, id, books[index % books.size()], Vector3(p.x + cursor, y + 0.025, z0), Vector3(p.x + cursor + width, y + 0.025 + height, z0 + book_depth))
			cursor += width + 0.012
			index += 1

func _add_shelf_board(space_id: String, id: String, box: AABB, along_z: bool, y: float) -> void:
	var inset := Vector3(0.0 if along_z else 0.04, 0.0, 0.04 if along_z else 0.0)
	_part_box(space_id, id, "wood", Vector3(box.position.x, y, box.position.z) + inset, Vector3(box.end.x, y + 0.025, box.end.z) - inset)

## Cama: base, colchão, cobertor nos pés e travesseiro na cabeceira. A
## cabeceira alta é um objeto encostado (`prop`), fora do volume baixo.
func _bed_parts(id: String, box: AABB, space_id: String) -> void:
	var h := box.end.y
	var blanket := "fabric_earth" if id == "cama_fundo" else "fabric_blue"
	_part(space_id, id, "wood_dark", box, 0.0, 0.3)
	_part(space_id, id, "linen", box, 0.3, 0.48, 0.03)
	var room := MansionMap.space_rect(space_id)
	var p := box.position
	var e := box.end
	if box.size.x > box.size.z:
		var at_east := absf(e.x - room.end.x) < absf(p.x - room.position.x)
		var head := e.x if at_east else p.x
		var foot0 := p.x if at_east else p.x + 0.6
		var foot1 := e.x - 0.6 if at_east else e.x
		_part_box(space_id, id, blanket, Vector3(foot0, 0.48, p.z + 0.02), Vector3(foot1, h, e.z - 0.02))
		var pillow0 := head - 0.5 if at_east else head + 0.1
		_part_box(space_id, id, "linen", Vector3(pillow0, 0.48, p.z + 0.15), Vector3(pillow0 + 0.4, h - 0.02, e.z - 0.15))
		_prop(space_id, id, "wood_dark", Vector3(head - 0.08 if at_east else head, h, p.z), Vector3(0.08, 0.5, box.size.z))
	else:
		var at_south := absf(e.z - room.end.y) < absf(p.z - room.position.y)
		var head := e.z if at_south else p.z
		var foot0 := p.z if at_south else p.z + 0.6
		var foot1 := e.z - 0.6 if at_south else e.z
		_part_box(space_id, id, blanket, Vector3(p.x + 0.02, 0.48, foot0), Vector3(e.x - 0.02, h, foot1))
		var pillow0 := head - 0.5 if at_south else head + 0.1
		_part_box(space_id, id, "linen", Vector3(p.x + 0.15, 0.48, pillow0), Vector3(e.x - 0.15, h - 0.02, pillow0 + 0.4))
		_prop(space_id, id, "wood_dark", Vector3(p.x, h, head - 0.08 if at_south else head), Vector3(box.size.x, 0.5, 0.08))

## Objetos sobre ou encostados aos móveis (`prop`, sem física).
func _furniture_props(item: Dictionary) -> void:
	var id := str(item["id"])
	var space_id := str(item["space"])
	var lo: Vector2 = item["min"]
	var hi: Vector2 = item["max"]
	var h := float(item["height"])
	var size := hi - lo
	var center := (lo + hi) * 0.5
	if id == "lareira":
		_prop(space_id, id, "brass", Vector3(lo.x + 0.2, h, lo.y + 0.15), Vector3(0.08, 0.3, 0.08))
		_prop(space_id, id, "brass", Vector3(hi.x - 0.28, h, lo.y + 0.15), Vector3(0.08, 0.3, 0.08))
		_prop(space_id, id, "wood_dark", Vector3(center.x - 0.12, h, lo.y + 0.12), Vector3(0.24, 0.32, 0.14))
	elif id == "escrivaninha" or id == "mesa_leitura":
		_prop(space_id, id, "office_green" if id == "escrivaninha" else "rug_green", Vector3(lo.x + 0.15, h, lo.y + 0.12), Vector3(size.x - 0.3, 0.004, size.y - 0.24))
		# Luminária de banqueiro com cúpula verde e livros.
		var lamp := Vector3(hi.x - 0.35, h, lo.y + 0.25)
		_prop(space_id, id, "brass", lamp + Vector3(-0.06, 0, -0.06), Vector3(0.12, 0.3, 0.12))
		_prop(space_id, id, "glow_green", lamp + Vector3(-0.14, 0.3, -0.1), Vector3(0.28, 0.1, 0.2))
		_prop(space_id, id, "book_red", Vector3(lo.x + 0.25, h, center.y - 0.15), Vector3(0.3, 0.05, 0.22))
		_prop(space_id, id, "linen", Vector3(lo.x + 0.28, h + 0.05, center.y - 0.12), Vector3(0.24, 0.01, 0.18))
		_chairs_for(space_id, id, lo, hi, 1)
	elif id == "mesa_jantar":
		_prop(space_id, id, "linen", Vector3(lo.x + 0.4, h, center.y - 0.25), Vector3(size.x - 0.8, 0.004, 0.5))
		for index in 3:
			var x := lo.x + 1.0 + index * 1.5
			_prop(space_id, id, "brass", Vector3(x - 0.05, h, center.y - 0.05), Vector3(0.1, 0.35, 0.1))
			_prop(space_id, id, "glow_warm", Vector3(x - 0.03, h + 0.35, center.y - 0.03), Vector3(0.06, 0.08, 0.06))
		for index in 5:
			var x := lo.x + 0.6 + index * 0.95
			_prop(space_id, id, "porcelain", Vector3(x - 0.13, h, lo.y + 0.08), Vector3(0.26, 0.02, 0.26))
			_prop(space_id, id, "porcelain", Vector3(x - 0.13, h, hi.y - 0.34), Vector3(0.26, 0.02, 0.26))
		_chairs_for(space_id, id, lo, hi, 5)
	elif id == "pedestal":
		# Busto estilizado: referência espacial no centro da casa.
		_prop(space_id, id, "stone", Vector3(center.x - 0.2, h, center.y - 0.15), Vector3(0.4, 0.12, 0.3))
		_prop(space_id, id, "stone", Vector3(center.x - 0.15, h + 0.12, center.y - 0.1), Vector3(0.3, 0.22, 0.2))
		_prop(space_id, id, "stone", Vector3(center.x - 0.1, h + 0.34, center.y - 0.1), Vector3(0.2, 0.22, 0.2))
	elif id == "bancada":
		for index in 3:
			_prop(space_id, id, "soot", Vector3(lo.x + 0.15, h, lo.y + 0.5 + index * 1.2), Vector3(0.3, 0.16, 0.3))
		_prop(space_id, id, "wood", Vector3(lo.x + 0.12, h, hi.y - 0.7), Vector3(0.36, 0.03, 0.5))
		_prop(space_id, id, "glass_dark", Vector3(lo.x + 0.2, h, hi.y - 0.2), Vector3(0.1, 0.25, 0.1))
	elif id == "aparador":
		_prop(space_id, id, "porcelain", Vector3(center.x - 0.12, h, center.y - 0.12), Vector3(0.24, 0.4, 0.24))
		_prop(space_id, id, "brass", Vector3(lo.x + 0.2, h, center.y - 0.05), Vector3(0.1, 0.3, 0.1))
		_prop(space_id, id, "brass", Vector3(hi.x - 0.3, h, center.y - 0.05), Vector3(0.1, 0.3, 0.1))
	elif id.begins_with("armario"):
		# Puxadores na face voltada para o cômodo.
		var room := MansionMap.space_rect(space_id).get_center()
		if size.x < size.y:
			var face := hi.x if room.x > center.x else lo.x - 0.03
			_prop(space_id, id, "brass", Vector3(face, 1.0, center.y - 0.14), Vector3(0.03, 0.22, 0.04))
			_prop(space_id, id, "brass", Vector3(face, 1.0, center.y + 0.1), Vector3(0.03, 0.22, 0.04))
		else:
			var face := hi.y if room.y > center.y else lo.y - 0.03
			_prop(space_id, id, "brass", Vector3(center.x - 0.14, 1.0, face), Vector3(0.04, 0.22, 0.03))
			_prop(space_id, id, "brass", Vector3(center.x + 0.1, 1.0, face), Vector3(0.04, 0.22, 0.03))
	elif id.begins_with("criado"):
		_prop(space_id, id, "brass", Vector3(center.x - 0.05, h, center.y - 0.05), Vector3(0.1, 0.25, 0.1))
		_prop(space_id, id, "glow_warm", Vector3(center.x - 0.1, h + 0.25, center.y - 0.1), Vector3(0.2, 0.14, 0.2))
	elif id == "banheira":
		_prop(space_id, id, "brass", Vector3(lo.x + 0.1, h, lo.y + 0.02), Vector3(0.08, 0.2, 0.08))
	elif id == "vaso":
		# Caixa acoplada contra a parede leste.
		_prop(space_id, id, "porcelain", Vector3(hi.x - 0.2, h, lo.y + 0.05), Vector3(0.2, 0.35, size.y - 0.1))
	elif id == "pia":
		_prop(space_id, id, "brass", Vector3(hi.x - 0.1, h, center.y - 0.03), Vector3(0.06, 0.18, 0.06))
		# Espelho na parede leste, acima da pia (sem reflexo real).
		_add(space_id, "brass", AABB(Vector3(hi.x - 0.04, 1.25, lo.y - 0.05), Vector3(0.04, 0.8, size.y + 0.1)), "trim", space_id)
		_add(space_id, "glass_dark", AABB(Vector3(hi.x - 0.05, 1.3, lo.y), Vector3(0.05, 0.7, size.y)), "trim", space_id)

## Cadeiras encostadas à mesa, sem ocupar o caminho: assento sob o tampo e
## encosto a menos de 0,2 m da borda (a cápsula para 0,45 m antes da mesa).
func _chairs_for(space_id: String, id: String, lo: Vector2, hi: Vector2, per_side: int) -> void:
	var length := hi.x - lo.x
	for index in per_side:
		var x := lo.x + length * (index + 0.5) / per_side
		for side in ([-1.0, 1.0] if id == "mesa_jantar" else [1.0]):
			var edge := lo.y if side < 0.0 else hi.y
			var seat_z := edge - 0.18 if side < 0.0 else edge - 0.27
			_prop(space_id, id, "wood_dark", Vector3(x - 0.22, 0.44, seat_z), Vector3(0.44, 0.05, 0.45))
			var back_z := edge - 0.17 if side < 0.0 else edge + 0.12
			_prop(space_id, id, "wood_dark", Vector3(x - 0.22, 0.44, back_z), Vector3(0.44, 0.5, 0.05))
			for leg_x in [x - 0.2, x + 0.16]:
				for leg_z in [seat_z + 0.02, seat_z + 0.39]:
					_prop(space_id, id, "wood_dark", Vector3(leg_x, 0.0, leg_z), Vector3(0.04, 0.44, 0.04))

func _prop(space_id: String, id: String, key: String, position: Vector3, size: Vector3) -> void:
	_add(space_id, key, AABB(position, size), "prop", space_id, id)

# --- Decoração de ambiente -------------------------------------------------------------

## Tapetes rentes ao piso (1,5 cm).
const RUGS := [
	{"space": "escritorio", "key": "rug_green", "min": Vector2(1.6, 1.8), "max": Vector2(4.6, 4.0)},
	{"space": "biblioteca", "key": "rug_red", "min": Vector2(2.2, 8.3), "max": Vector2(3.8, 15.7)},
	{"space": "jantar", "key": "rug_red", "min": Vector2(10.4, 20.8), "max": Vector2(16.6, 23.2)},
	{"space": "quarto_fundo", "key": "rug_gold", "min": Vector2(31.0, 24.4), "max": Vector2(34.0, 26.1)},
	{"space": "quarto_hospedes", "key": "rug_gold", "min": Vector2(39.2, 23.8), "max": Vector2(40.6, 26.2)},
	{"space": "galeria", "key": "rug_red", "min": Vector2(21.5, 1.6), "max": Vector2(29.5, 3.4)},
	{"space": "ala_leste", "key": "rug_red", "min": Vector2(27.0, 18.0), "max": Vector2(45.0, 19.0)},
	{"space": "corredor_norte", "key": "rug_red", "min": Vector2(6.5, 2.0), "max": Vector2(20.5, 3.0)},
]

func _rugs() -> void:
	for rug in RUGS:
		var lo: Vector2 = rug["min"]
		var hi: Vector2 = rug["max"]
		_add(str(rug["space"]), str(rug["key"]), AABB(Vector3(lo.x, 0.0, lo.y), Vector3(hi.x - lo.x, 0.015, hi.y - lo.y)), "floor", str(rug["space"]))

## Quadros próprios, abstratos: moldura dourada e composição de blocos de cor.
## Galeria (repetição que ajuda a reconhecer o ambiente), Salão e corredores.
func _paintings() -> void:
	var palettes := [["paint_a", "paint_c", "paint_d"], ["paint_b", "paint_e", "paint_c"], ["paint_d", "paint_a", "paint_e"], ["paint_c", "paint_b", "paint_a"]]
	var count := 0
	for space_id in ["galeria", "salao", "corredor_norte", "ala_leste", "jantar", "escritorio"]:
		for segment in wall_segments(space_id):
			var a: Vector2 = segment["from"]
			var b: Vector2 = segment["to"]
			var length := a.distance_to(b)
			if length < 2.2:
				continue
			var per := 3 if space_id == "galeria" else 1
			if space_id == "galeria" and length < 6.0:
				per = 1
			for index in per:
				var t := (index + 0.5) / per
				var mid := a.lerp(b, t)
				var along := (b - a).normalized()
				var inward: Vector2 = segment["inward"]
				var width := 1.2 if space_id != "salao" else 1.6
				var p0 := mid - along * width * 0.5
				var p1 := mid + along * width * 0.5
				var palette: Array = palettes[count % palettes.size()]
				_strip(space_id, p0, p1, inward, 1.35, 2.35, RAIL_DEPTH, "brass")
				var inner0 := mid - along * (width * 0.5 - 0.08)
				var inner1 := mid + along * (width * 0.5 - 0.08)
				_strip(space_id, inner0, inner1, inward, 1.43, 2.27, RAIL_DEPTH + 0.015, str(palette[0]))
				_strip(space_id, mid - along * 0.25, mid + along * 0.3, inward, 1.6, 2.1, RAIL_DEPTH + 0.03, str(palette[1]))
				_strip(space_id, mid - along * 0.45, mid - along * 0.15, inward, 1.5, 1.8, RAIL_DEPTH + 0.045, str(palette[2]))
				count += 1

## Arandelas nos corredores (a cada ~4,5 m, lados alternados) e ao lado das
## portas do Salão: suporte de latão e vidro aceso, acima de 2 m.
func _sconces() -> void:
	for entry in MansionMap.SPACES:
		var space_id := str(entry["id"])
		if str(entry["kind"]) != "corridor" and space_id != "salao" and space_id != "galeria":
			continue
		var index := 0
		for segment in wall_segments(space_id):
			var a: Vector2 = segment["from"]
			var b: Vector2 = segment["to"]
			var length := a.distance_to(b)
			if length < 1.5:
				continue
			var step := 4.5
			var count := maxi(1, int(floor(length / step)))
			for k in count:
				index += 1
				if space_id != "salao" and index % 2 == 0:
					continue
				var mid := a.lerp(b, (k + 0.5) / count)
				var along := (b - a).normalized()
				var inward: Vector2 = segment["inward"]
				_strip(space_id, mid - along * 0.04, mid + along * 0.04, inward, 2.1, 2.2, 0.16, "brass", "fixture")
				var glow_a := mid - along * 0.08 + inward * 0.08
				var glow_b := mid + along * 0.08 + inward * 0.08
				_add(space_id, "glow_warm", _flat_box(glow_a, glow_b, inward, 2.2, 2.42, 0.16), "fixture", space_id)

func _flat_box(a: Vector2, b: Vector2, inward: Vector2, bottom: float, top: float, depth: float) -> AABB:
	var low := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var high := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	if inward.x != 0.0:
		var x0 := low.x if inward.x > 0.0 else low.x - depth
		return AABB(Vector3(x0, bottom, low.y), Vector3(depth, top - bottom, maxf(high.y - low.y, 0.01)))
	var z0 := low.y if inward.y > 0.0 else low.y - depth
	return AABB(Vector3(low.x, bottom, z0), Vector3(maxf(high.x - low.x, 0.01), top - bottom, depth))

## Lustre simples no centro do Salão, bem acima das cabeças.
func _chandelier() -> void:
	var rect := MansionMap.space_rect("salao")
	var center := rect.get_center()
	var ceiling := float(MansionMap.space("salao")["ceiling"])
	_add("salao", "brass", AABB(Vector3(center.x - 0.03, ceiling - 0.9, center.y - 0.03), Vector3(0.06, 0.9, 0.06)), "fixture", "salao")
	_add("salao", "brass", AABB(Vector3(center.x - 0.7, ceiling - 1.0, center.y - 0.7), Vector3(1.4, 0.06, 1.4)), "fixture", "salao")
	for angle_index in 6:
		var angle := angle_index * TAU / 6.0
		var p := center + Vector2(cos(angle), sin(angle)) * 0.62
		_add("salao", "glow_warm", AABB(Vector3(p.x - 0.06, ceiling - 0.94, p.y - 0.06), Vector3(0.12, 0.16, 0.12)), "fixture", "salao")

## Luzes quentes sem sombra: uma por cômodo (duas na Galeria, três no Salão)
## e uma a cada ~7 m de corredor. Orçamento fixo e medido nos testes.
func _lights() -> void:
	for entry in MansionMap.SPACES:
		var space_id := str(entry["id"])
		var rect := MansionMap.space_rect(space_id)
		var ceiling := float(entry["ceiling"])
		var points: Array = []
		if space_id == "salao":
			points = [rect.get_center() + Vector2(-2.5, 0.0), rect.get_center() + Vector2(2.5, 0.0)]
		elif str(entry["kind"]) == "room":
			var count := 2 if maxf(rect.size.x, rect.size.y) >= 8.0 else 1
			for index in count:
				var t := (index + 0.5) / count
				points.append(rect.position + Vector2(rect.size.x * (t if rect.size.x >= rect.size.y else 0.5), rect.size.y * (t if rect.size.y > rect.size.x else 0.5)))
		else:
			var length := maxf(rect.size.x, rect.size.y)
			if length < 3.5:
				continue
			var count := maxi(1, int(round(length / 6.0)))
			for index in count:
				var t := (index + 0.5) / count
				points.append(rect.position + Vector2(rect.size.x * (t if rect.size.x >= rect.size.y else 0.5), rect.size.y * (t if rect.size.y > rect.size.x else 0.5)))
		for point in points:
			var light := OmniLight3D.new()
			light.position = Vector3(point.x, ceiling - 0.5, point.y)
			light.light_color = Color(1.0, 0.84, 0.64)
			light.light_energy = 1.4 if str(entry["kind"]) == "room" else 1.1
			light.omni_range = clampf(maxf(rect.size.x, rect.size.y) * 0.6, 4.0, 6.5) if str(entry["kind"]) == "room" else 4.5
			light.omni_attenuation = 0.8
			light.shadow_enabled = false
			light.set_meta("arena_light", space_id)
			_root.add_child(light)
			lights.append(light)

# --- Lotes ------------------------------------------------------------------------------

func _add(group: String, key: String, box: AABB, kind: String, space_id: String, id: String = "") -> void:
	items.append({"kind": kind, "space": space_id, "id": id, "aabb": box, "material": key, "group": group})
	var batch_key := group + "#" + key
	if not _batches.has(batch_key):
		_batches[batch_key] = {"group": group, "key": key, "verts": PackedVector3Array(), "normals": PackedVector3Array()}
	var batch: Dictionary = _batches[batch_key]
	_append_box(batch["verts"], batch["normals"], box)

static func _append_box(verts: PackedVector3Array, normals: PackedVector3Array, box: AABB) -> void:
	var p := box.position
	var e := box.end
	var faces := [
		[Vector3(1, 0, 0), [Vector3(e.x, p.y, p.z), Vector3(e.x, e.y, p.z), Vector3(e.x, e.y, e.z), Vector3(e.x, p.y, e.z)]],
		[Vector3(-1, 0, 0), [Vector3(p.x, p.y, e.z), Vector3(p.x, e.y, e.z), Vector3(p.x, e.y, p.z), Vector3(p.x, p.y, p.z)]],
		[Vector3(0, 1, 0), [Vector3(p.x, e.y, p.z), Vector3(p.x, e.y, e.z), Vector3(e.x, e.y, e.z), Vector3(e.x, e.y, p.z)]],
		[Vector3(0, -1, 0), [Vector3(p.x, p.y, e.z), Vector3(p.x, p.y, p.z), Vector3(e.x, p.y, p.z), Vector3(e.x, p.y, e.z)]],
		[Vector3(0, 0, 1), [Vector3(e.x, p.y, e.z), Vector3(e.x, e.y, e.z), Vector3(p.x, e.y, e.z), Vector3(p.x, p.y, e.z)]],
		[Vector3(0, 0, -1), [Vector3(p.x, p.y, p.z), Vector3(p.x, e.y, p.z), Vector3(e.x, e.y, p.z), Vector3(e.x, p.y, p.z)]],
	]
	for face in faces:
		var normal: Vector3 = face[0]
		var q: Array = face[1]
		# Godot trata a ordem horária como face da frente.
		for index in [0, 2, 1, 0, 3, 2]:
			verts.append(q[index])
			normals.append(normal)

func _flush() -> void:
	var keys := _batches.keys()
	keys.sort()
	for batch_key in keys:
		var batch: Dictionary = _batches[batch_key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = batch["verts"]
		arrays[Mesh.ARRAY_NORMAL] = batch["normals"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material(str(batch["key"])))
		var node := MeshInstance3D.new()
		node.name = "Art_%s_%s" % [str(batch["group"]).replace("|", "_"), str(batch["key"])]
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.set_meta("arena_art_group", str(batch["group"]))
		if str(batch["group"]).ends_with("|ceiling"):
			node.set_meta("arena_blocker_kind", CEILING_KIND)
		_root.add_child(node)
		meshes.append(node)
	_batches.clear()

static func _nearest_space(center: Vector3) -> String:
	var best := ""
	var best_distance := INF
	var point := Vector2(center.x, center.z)
	for entry in MansionMap.SPACES:
		var rect := MansionMap.space_rect(str(entry["id"]))
		var dx := maxf(maxf(rect.position.x - point.x, point.x - rect.end.x), 0.0)
		var dz := maxf(maxf(rect.position.y - point.y, point.y - rect.end.y), 0.0)
		var distance := dx * dx + dz * dz
		if distance < best_distance:
			best_distance = distance
			best = str(entry["id"])
	return best
