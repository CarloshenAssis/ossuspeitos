class_name ArenaView
extends Node3D

var local_peer_id := 0
var avatars: Dictionary = {}
var targets: Dictionary = {}
var camera: Camera3D
var player_rig: Node3D
var pickup_nodes: Dictionary = {}
var pickup_states: Dictionary = {}
var weapon_model: Node3D
## Pivô entre a câmera e a pistola: recuo e pose de recarga mexem só aqui,
## nunca na câmera (a direção do disparo vem da câmera).
var weapon_pivot: Node3D
var fx: CombatFx
var _muzzle_flash: MeshInstance3D
var _combat_prev: Dictionary = {}
var _reload_pose := false
var _pose_tween: Tween
var _kick_tween: Tween
var crosshair: Crosshair
var spectator_target_peer_id := 0
## Chip da região (canto superior esquerdo): lado + nome, na cor do mapa.
var region_chip: PanelContainer
var region_side: Label
var region_name: Label
var current_zone_name := ""
## Distância do topo do chip de região; a demo offline o desce abaixo do banner.
var region_chip_top := HudStyle.MARGIN
var gameplay_visuals := true
var _alive_flags: Dictionary = {}
## Aparência cosmética pública por jogador (roster oficial). Nunca vem de papel.
var _appearances: Dictionary = {}
## Último estado oficial do próprio jogador (chega em todo snapshot).
var _local_state: Dictionary = {}
const ZONE_SIDES := {
	"center": "C", "north": "N", "south": "S", "west": "O", "east": "L",
	"northwest": "NO", "northeast": "NE", "southwest": "SO", "southeast": "SE",
}

## Cores de orientação por região. Apresentação pura: a geometria e os nomes
## vêm de `ArenaRules`, a mesma fonte que o servidor usa para colisão e tiro.
const ZONE_COLORS := {
	"center": Color(0.62, 0.6, 0.57),
	"north": Color(0.2, 0.38, 0.86),
	"south": Color(0.9, 0.4, 0.12),
	"west": Color(0.16, 0.62, 0.3),
	"east": Color(0.56, 0.26, 0.82),
}
const OUTER_WALL_COLOR := Color(0.24, 0.26, 0.31)
## Amarelo é exclusivo dos caixotes baixos: "bloqueia passagem, tiro passa por cima".
const LOW_CRATE_COLOR := Color(1.0, 0.86, 0.1)
const FLOOR_COLOR := Color(0.1, 0.11, 0.13)
const ZONE_TILE_HEIGHT := 0.02
const VIEWMODEL_OFFSET := Vector3(0.19, -0.16, -0.5)
const VIEWMODEL_SCALE := 0.8
## Giro lento dos pickups disponíveis (só visual; a posição oficial não muda).
const PICKUP_SPIN_SPEED := 0.9
var _visual_time := 0.0

func _ready() -> void:
	_ensure_input_actions()
	_build_arena()
	player_rig = Node3D.new()
	add_child(player_rig)
	camera = Camera3D.new()
	camera.position.y = ArenaRules.EYE_HEIGHT
	player_rig.add_child(camera)
	# Pistola na mão no canto inferior direito da visão: não cobre o centro
	# nem o painel de munição. Só aparece com arma no inventário oficial.
	weapon_model = ArenaModels.build_pistol()
	weapon_model.scale = Vector3.ONE * VIEWMODEL_SCALE
	weapon_model.rotation = Vector3(0.04, 0.06, 0.0)
	weapon_model.visible = false
	weapon_pivot = Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	# O pivô fica na própria arma: recuo e recarga são inclinações curtas no
	# lugar, sem varrer a pistola pela tela.
	weapon_pivot.position = VIEWMODEL_OFFSET
	camera.add_child(weapon_pivot)
	weapon_pivot.add_child(weapon_model)
	# Clarão da própria arma: pequeno, na boca do cano, só por um instante.
	_muzzle_flash = MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.035
	flash_mesh.height = 0.07
	_muzzle_flash.mesh = flash_mesh
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.albedo_color = Color(1.0, 0.85, 0.55)
	_muzzle_flash.material_override = flash_material
	_muzzle_flash.position = Vector3(0.0, 0.03, -0.19)
	_muzzle_flash.visible = false
	weapon_model.add_child(_muzzle_flash)
	fx = CombatFx.new()
	add_child(fx)
	var overlay := CanvasLayer.new()
	add_child(overlay)
	var overlay_root := Control.new()
	overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(overlay_root)
	crosshair = Crosshair.new()
	overlay_root.add_child(crosshair)
	region_chip = HudStyle.panel()
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 8)
	region_side = HudStyle.label("", 12, HudStyle.INK)
	region_side.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	region_side.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	region_side.custom_minimum_size = Vector2(24, 20)
	var side_box := PanelContainer.new()
	side_box.add_theme_stylebox_override("panel", HudStyle.panel_style(HudStyle.MUTED, HudStyle.MUTED, 0))
	(side_box.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = 2.0
	(side_box.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 2.0
	(side_box.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_top = 0.0
	(side_box.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_bottom = 0.0
	side_box.add_child(region_side)
	chip_row.add_child(side_box)
	region_name = HudStyle.label("", 15)
	chip_row.add_child(region_name)
	region_chip.add_child(chip_row)
	region_chip.visible = false
	overlay_root.add_child(region_chip)
	HudStyle.anchor_corner(region_chip, Control.PRESET_TOP_LEFT)
	region_chip.offset_top = region_chip_top

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _ensure_input_actions() -> void:
	var bindings := {
		"move_forward": KEY_W,
		"move_backward": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
	}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = bindings[action]
		InputMap.action_add_event(action, event)

func apply_snapshot(states: Array) -> void:
	var present: Dictionary = {}
	for raw_state in states:
		var state: Dictionary = raw_state
		var peer_id := int(state["peer_id"])
		present[peer_id] = true
		if spectator_target_peer_id == peer_id:
			_place_rig(state)
		# O próprio jogador nunca tem corpo visível: a câmera fica dentro dele.
		# Vale também como espectador, senão o corpo criado nessa fase fica em
		# volta da câmera na rodada seguinte.
		if peer_id == local_peer_id:
			_local_state = state
			if spectator_target_peer_id == 0:
				_place_rig(state)
			continue
		if not avatars.has(peer_id):
			avatars[peer_id] = _create_avatar(peer_id, state["position"])
			(avatars[peer_id] as Node3D).visible = bool(_alive_flags.get(peer_id, true))
		targets[peer_id] = state
	for peer_id in avatars.keys():
		if not present.has(peer_id):
			avatars[peer_id].queue_free()
			avatars.erase(peer_id)
			targets.erase(peer_id)

func _place_rig(state: Dictionary) -> void:
	player_rig.position = state["position"]
	player_rig.rotation.y = float(state["yaw"])
	# Pitch oficial na câmera (próprio jogador, ou o alvo observado): a mira,
	# o retículo no centro e a pistola na mão sobem e descem juntos.
	camera.rotation.x = MovementRules.clamp_pitch(state.get("pitch", 0.0))
	_update_zone_label(player_rig.position)

func _process(delta: float) -> void:
	var weight := 1.0 - exp(-12.0 * delta)
	for peer_id in targets:
		if not avatars.has(peer_id):
			continue
		var avatar: Node3D = avatars[peer_id]
		var state: Dictionary = targets[peer_id]
		avatar.position = avatar.position.lerp(state["position"], weight)
		avatar.rotation.y = lerp_angle(avatar.rotation.y, float(state["yaw"]), weight)
		# Só a cabeça acompanha o pitch oficial; o corpo continua de pé.
		var head := avatar.find_child(ArenaModels.HEAD_PIVOT, true, false) as Node3D
		if head != null:
			head.rotation.x = lerpf(head.rotation.x, ArenaModels.head_rotation_for_pitch(state.get("pitch", 0.0)), weight)
		# Em primeira pessoa como espectador, a câmera fica dentro do alvo:
		# chapéu, braços e visor dele ficariam colados à lente.
		var show_model: bool = peer_id != spectator_target_peer_id
		for part in avatar.get_children():
			(part as Node3D).visible = show_model
	_visual_time += delta
	for pickup_id in pickup_nodes:
		var spin := (pickup_nodes[pickup_id] as Node3D).get_node_or_null("Spin") as Node3D
		if spin != null:
			spin.rotation.y = _visual_time * PICKUP_SPIN_SPEED
			spin.position.y = sin(_visual_time * 2.0) * 0.03

func _build_arena() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.37, 0.48)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.84)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.3, 0.37, 0.48)
	env.fog_density = 0.005
	environment.environment = env
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	light.light_energy = 1.0
	light.shadow_enabled = true
	add_child(light)
	# Piso visual abaixo de y = 0; tiros oficiais são horizontais e nunca o tocam.
	_add_decor_box(Vector3(0.0, -0.25, 0.0), Vector3(30.0, 0.5, 30.0), FLOOR_COLOR)
	for zone in ArenaRules.ZONES:
		_add_zone_tile(zone)
	for blocker in ArenaRules.BLOCKERS:
		_add_blocker(blocker)
	for index in MovementRules.SPAWN_POINTS.size():
		_add_spawn_marker(MovementRules.SPAWN_POINTS[index])
	_add_zone_signs()
	_add_zone_lights()

## Cada bloco oficial vira exatamente uma mesh com o mesmo centro e tamanho.
func _add_blocker(blocker: Dictionary) -> void:
	var kind := str(blocker["kind"])
	var color := OUTER_WALL_COLOR
	if kind == "low":
		color = LOW_CRATE_COLOR
	elif kind != "outer":
		color = zone_color(blocker["center"]).darkened(0.15)
		if kind == "cover":
			color = zone_color(blocker["center"]).lightened(0.12)
	var node := _add_box(blocker["center"], blocker["size"], color)
	node.name = "Blocker_%s" % str(blocker["id"])
	node.set_meta("arena_blocker_id", str(blocker["id"]))

func _add_zone_tile(zone: Dictionary) -> void:
	var minimum: Vector2 = zone["min"]
	var maximum: Vector2 = zone["max"]
	var center := (minimum + maximum) * 0.5
	var size := maximum - minimum
	var color := zone_color(Vector3(center.x, 0.0, center.y)).darkened(0.5)
	# Placas encostadas, na mesma altura: a troca de cor marca a região sem
	# criar degrau ou junta que pareça obstáculo.
	var node := _add_decor_box(Vector3(center.x, ZONE_TILE_HEIGHT * 0.5, center.y),
		Vector3(size.x, ZONE_TILE_HEIGHT, size.y), color)
	node.name = "ZoneTile_%s" % str(zone["id"])

func _add_spawn_marker(spawn: Vector3) -> void:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.6
	mesh.bottom_radius = 0.6
	mesh.height = 0.01
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.9, 0.95, 1.0, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	node.mesh = mesh
	node.position = Vector3(spawn.x, ZONE_TILE_HEIGHT + 0.005, spawn.z)
	node.set_meta("arena_decor", "floor")
	add_child(node)

## Placas planas nos muros externos, legíveis de dentro da arena (a face de
## leitura de um Label3D é o seu +Z local). Não têm volume nem colisão.
func _add_zone_signs() -> void:
	var inner := ArenaRules.INNER_HALF_EXTENT - 0.02
	var signs := [
		{"text": "NORTE", "position": Vector3(0.0, 2.7, -inner), "yaw": 0.0},
		{"text": "SUL", "position": Vector3(0.0, 2.7, inner), "yaw": PI},
		{"text": "OESTE", "position": Vector3(-inner, 2.7, 0.0), "yaw": PI * 0.5},
		{"text": "LESTE", "position": Vector3(inner, 2.7, 0.0), "yaw": -PI * 0.5},
		{"text": "SALA NO", "position": Vector3(-12.3, 2.7, -inner), "yaw": 0.0},
		{"text": "SALA NE", "position": Vector3(12.3, 2.7, -inner), "yaw": 0.0},
		{"text": "SALA SO", "position": Vector3(-12.3, 2.7, inner), "yaw": PI},
		{"text": "SALA SE", "position": Vector3(12.3, 2.7, inner), "yaw": PI},
	]
	for entry in signs:
		var label := Label3D.new()
		label.text = str(entry["text"])
		label.font_size = 96
		label.pixel_size = 0.01
		label.outline_size = 18
		label.modulate = Color(1.0, 1.0, 1.0)
		label.position = entry["position"]
		label.rotation.y = float(entry["yaw"])
		label.set_meta("arena_decor", "sign")
		add_child(label)

## Luzes pontuais coloridas por região, sem sombra, para leitura de lugar.
func _add_zone_lights() -> void:
	for zone_id in ["center", "north", "south", "west", "east"]:
		var zone := _zone_by_id(zone_id)
		var minimum: Vector2 = zone["min"]
		var maximum: Vector2 = zone["max"]
		var center := (minimum + maximum) * 0.5
		var light := OmniLight3D.new()
		light.position = Vector3(center.x, 3.8, center.y)
		light.light_color = zone_color(Vector3(center.x, 0.0, center.y)).lightened(0.3)
		light.light_energy = 0.6
		light.omni_range = 9.0
		light.shadow_enabled = false
		add_child(light)

static func zone_color(position: Vector3) -> Color:
	var zone_id := str(ArenaRules.zone_at(position).get("id", "center"))
	if ZONE_COLORS.has(zone_id):
		return ZONE_COLORS[zone_id]
	# Cantos misturam as duas bordas vizinhas: "northeast" = norte + leste.
	var vertical := "north" if zone_id.begins_with("north") else "south"
	var horizontal := "east" if zone_id.ends_with("east") else "west"
	return (ZONE_COLORS[vertical] as Color).lerp(ZONE_COLORS[horizontal], 0.5)

static func _zone_by_id(zone_id: String) -> Dictionary:
	for zone in ArenaRules.ZONES:
		if str(zone["id"]) == zone_id:
			return zone
	return {}

func _add_decor_box(box_position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := _add_box(box_position, size, color)
	node.set_meta("arena_decor", "floor")
	return node

func _add_box(box_position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = box_position
	add_child(mesh_instance)
	return mesh_instance

func _update_zone_label(position: Vector3) -> void:
	var zone := ArenaRules.zone_at(position)
	var zone_name := str(zone.get("name", ""))
	if zone_name == current_zone_name or region_chip == null:
		return
	current_zone_name = zone_name
	region_chip.visible = not zone_name.is_empty()
	region_name.text = zone_name.to_upper()
	region_side.text = str(ZONE_SIDES.get(str(zone.get("id", "")), "?"))
	# Reancora ao tamanho mínimo: nome curto depois de um longo encolhe o chip.
	HudStyle.anchor_corner(region_chip, Control.PRESET_TOP_LEFT)
	region_chip.offset_top = region_chip_top
	region_chip.offset_bottom = region_chip_top + region_chip.get_combined_minimum_size().y
	var side_style := (region_side.get_parent() as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	side_style.bg_color = zone_color(position).lightened(0.25)

func _create_avatar(peer_id: int, initial_position: Vector3) -> Node3D:
	# O nó raiz recebe a posição e o yaw oficiais; o modelo tem a frente em -Z
	# local (visor, lapelas), a mesma convenção da câmera. É só malha, sem
	# colisão: disparo e acerto seguem a direção oficial e a autoridade do
	# servidor, nunca este nó. O modelo é igual para todos os papéis.
	var avatar := ArenaModels.build_character(appearance_for(peer_id))
	avatar.position = initial_position
	add_child(avatar)
	return avatar

func camera_origin() -> Vector3:
	return camera.global_position if camera != null else Vector3.ZERO

func camera_direction() -> Vector3:
	return -camera.global_transform.basis.z.normalized() if camera != null else Vector3.FORWARD

var _combat_has_weapon := false

const RELOAD_POSE := Vector3(-0.45, 0.25, 0.2)
const RELOAD_DROP := Vector3(0.0, -0.04, 0.02)
const RECOIL_BACK := Vector3(0.0, 0.01, 0.05)
const RECOIL_TILT := 0.14
const DAMAGE_KICK := 0.035
const IMPACT_CAMERA_CLEARANCE := 1.2

func apply_combat_state(state: Dictionary) -> void:
	_combat_has_weapon = not str(state.get("weapon_id", "")).is_empty() and int(state.get("health", 0)) > 0
	_refresh_gameplay_visuals()
	for feedback in combat_feedback(_combat_prev, state):
		match feedback:
			"pickup_ok", "reload_start", "reload_end": fx.play_ui(feedback)
			"hurt":
				fx.play_ui("hurt")
				_damage_kick()
	if state.is_empty():
		# Estado limpo (nova rodada, fim): nenhum efeito ou pose antiga.
		fx.clear()
	_combat_prev = state.duplicate(true)
	_set_reload_pose(bool(state.get("reloading", false)) and _combat_has_weapon)

## Retorno sonoro das mudanças do estado privado oficial entre duas versões
## seguidas da mesma rodada. Coleta só conta se o servidor já a aplicou (arma
## nova ou reserva maior sem recarga); recusas nunca chegam aqui.
static func combat_feedback(before: Dictionary, after: Dictionary) -> Array:
	var result: Array = []
	if before.is_empty() or after.is_empty() or int(before.get("round_id", -1)) != int(after.get("round_id", -2)):
		return result
	var health_before := int(before.get("health", 0))
	var health_after := int(after.get("health", 0))
	if health_after < health_before:
		result.append("hurt")
	if health_after <= 0:
		return result
	var weapon_before := str(before.get("weapon_id", ""))
	var weapon_after := str(after.get("weapon_id", ""))
	var reloading_before := bool(before.get("reloading", false))
	var reloading_after := bool(after.get("reloading", false))
	if weapon_before.is_empty() and not weapon_after.is_empty():
		result.append("pickup_ok")
	elif not weapon_after.is_empty() and int(after.get("reserve", 0)) > int(before.get("reserve", 0)) and not reloading_before:
		result.append("pickup_ok")
	if not reloading_before and reloading_after:
		result.append("reload_start")
	elif reloading_before and not reloading_after and int(after.get("magazine", 0)) > int(before.get("magazine", 0)):
		result.append("reload_end")
	return result

## Recusa oficial de uma ação do próprio jogador: som de "não", nunca o de
## sucesso. Motivos silenciosos no HUD (cadência, técnicos) ficam mudos aqui.
func show_rejection(action: String, reason: String) -> void:
	if RoundHud.rejection_notice(action, reason).is_empty():
		return
	fx.play_ui("dry_fire" if action == "fire" and reason == "empty_magazine" else "pickup_deny")

## Eliminação pública: fumaça neutra onde o corpo estava e o corpo some.
func show_elimination(peer_id: int) -> void:
	if peer_id == local_peer_id:
		fx.play_ui("elimination")
	elif avatars.has(peer_id):
		fx.elimination((avatars[peer_id] as Node3D).global_position)
	elif targets.has(peer_id):
		fx.elimination(targets[peer_id]["position"])
	set_player_alive(peer_id, false)

func _set_reload_pose(active: bool) -> void:
	if active == _reload_pose:
		return
	_reload_pose = active
	if _pose_tween != null: _pose_tween.kill()
	_pose_tween = weapon_pivot.create_tween().set_parallel(true)
	_pose_tween.tween_property(weapon_pivot, "rotation", RELOAD_POSE if active else Vector3.ZERO, 0.18)
	_pose_tween.tween_property(weapon_pivot, "position", VIEWMODEL_OFFSET + (RELOAD_DROP if active else Vector3.ZERO), 0.18)

func _recoil() -> void:
	if _reload_pose:
		return
	if _pose_tween != null: _pose_tween.kill()
	_pose_tween = weapon_pivot.create_tween()
	_pose_tween.tween_property(weapon_pivot, "position", VIEWMODEL_OFFSET + RECOIL_BACK, 0.04)
	_pose_tween.parallel().tween_property(weapon_pivot, "rotation:x", RECOIL_TILT, 0.04)
	_pose_tween.tween_property(weapon_pivot, "position", VIEWMODEL_OFFSET, 0.12)
	_pose_tween.parallel().tween_property(weapon_pivot, "rotation:x", 0.0, 0.12)
	_muzzle_flash.visible = true
	get_tree().create_timer(CombatFx.FLASH_SECONDS).timeout.connect(func(): _muzzle_flash.visible = false)

## Dano recebido: tranco curto só no deslocamento de projeção da câmera
## (`v_offset`/`h_offset`); a orientação e a origem da mira não mudam.
func _damage_kick() -> void:
	if _kick_tween != null: _kick_tween.kill()
	camera.v_offset = -DAMAGE_KICK
	camera.h_offset = DAMAGE_KICK * 0.5
	_kick_tween = camera.create_tween().set_parallel(true)
	_kick_tween.tween_property(camera, "v_offset", 0.0, 0.16)
	_kick_tween.tween_property(camera, "h_offset", 0.0, 0.16)

## Seleciona apenas um ID previamente autorizado pela camada de rede. A camera
## segue posicao/yaw oficiais recebidos em snapshots; nunca envia controle.
func set_spectator_target(peer_id: int, spectator_active: bool = true) -> void:
	spectator_target_peer_id = peer_id
	# Fim do modo espectador: volta já à última posição oficial do próprio
	# jogador. Esperar o próximo snapshot deixaria a câmera, por alguns quadros,
	# dentro do corpo (agora visível de novo) de quem era observado.
	if peer_id == 0 and not _local_state.is_empty():
		_place_rig(_local_state)
	if spectator_active:
		gameplay_visuals = false
	_refresh_gameplay_visuals()

## Mira e arma na mão só enquanto a camada de rede diz que o jogador pode agir
## (vivo, participante, rodada ACTIVE). Fora disso — espectador, lobby, fim da
## rodada — nada de mira nem arma, e nenhum dado de combate antigo aparece.
func set_gameplay_visuals(active: bool) -> void:
	gameplay_visuals = active
	_refresh_gameplay_visuals()

func _refresh_gameplay_visuals() -> void:
	if crosshair != null: crosshair.visible = gameplay_visuals
	if weapon_model != null: weapon_model.visible = gameplay_visuals and _combat_has_weapon

func apply_pickups(entries: Array) -> void:
	pickup_states.clear()
	for raw_entry in entries:
		if typeof(raw_entry) != TYPE_DICTIONARY: continue
		var entry: Dictionary = raw_entry
		var pickup_id := str(entry.get("pickup_id", ""))
		pickup_states[pickup_id] = entry
		if not pickup_nodes.has(pickup_id):
			pickup_nodes[pickup_id] = _create_pickup(entry)
		var node := pickup_nodes[pickup_id] as Node3D
		var available := bool(entry.get("available", false))
		# Sumiu agora (público): anel neutro no lugar, igual para todos. Quem
		# pegou não é revelado.
		if node.visible and not available:
			var color := ArenaModels.WEAPON_GLOW if str(entry.get("type", "")) == "weapon" else ArenaModels.AMMO_GLOW
			fx.pickup_vanish(entry.get("position", node.position), color)
		node.visible = available
	for pickup_id in pickup_nodes.keys():
		if not pickup_states.has(pickup_id):
			(pickup_nodes[pickup_id] as Node).queue_free()
			pickup_nodes.erase(pickup_id)

func nearest_available_pickup() -> String:
	if player_rig == null: return ""
	var nearest := ""
	var distance := 2.0
	for pickup_id in pickup_states:
		var entry: Dictionary = pickup_states[pickup_id]
		if not bool(entry.get("available", false)): continue
		var candidate := player_rig.global_position.distance_to(entry["position"])
		if candidate <= distance:
			distance = candidate
			nearest = pickup_id
	return nearest

func show_shot(payload: Dictionary) -> void:
	if not payload.has("origin") or not payload.has("end"): return
	var tracer := MeshInstance3D.new()
	var start: Vector3 = payload["origin"]
	var finish: Vector3 = payload["end"]
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.025, start.distance_to(finish))
	tracer.mesh = mesh
	tracer.position = (start + finish) * 0.5
	tracer.look_at(finish, Vector3.UP)
	add_child(tracer)
	var timer := get_tree().create_timer(0.08)
	timer.timeout.connect(tracer.queue_free)
	# Quem atirou vem no evento público; o alvo não. O próprio disparo tem som
	# e recuo na primeira pessoa; o dos outros tem clarão e som na origem.
	if int(payload.get("shooter_peer_id", 0)) == local_peer_id and local_peer_id != 0:
		fx.play_ui("shot")
		_recoil()
	else:
		fx.muzzle_flash(start, finish - start)
		fx.play_world("shot", start)
	# Impacto colado na própria câmera (é você quem foi atingido) viraria uma
	# mancha no centro da tela; aí basta o retorno de dano do estado privado.
	if finish.distance_to(camera_origin()) > IMPACT_CAMERA_CLEARANCE:
		fx.impact(finish, bool(payload.get("hit_player", false)))

func show_hit_marker() -> void:
	if crosshair != null and crosshair.visible:
		crosshair.show_hit()
		fx.play_ui("hit")

func set_player_alive(peer_id: int, alive: bool) -> void:
	_alive_flags[peer_id] = alive
	if avatars.has(peer_id):
		(avatars[peer_id] as Node3D).visible = alive

## Vivo/eliminado do roster oficial: quem caiu some e, na rodada seguinte,
## volta a aparecer quando o servidor o marca vivo de novo.
func apply_roster_alive(entries: Array) -> void:
	for raw_entry in entries:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw_entry
		var peer_id := int(entry.get("peer_id", 0))
		if entry.has("appearance"):
			set_appearance(peer_id, entry["appearance"])
		set_player_alive(peer_id, bool(entry.get("alive", true)))

## Aparência pública (allowlist) de um jogador. Se o corpo já existe com outra
## aparência, só o nó visual é trocado; posição, yaw e visibilidade ficam.
func set_appearance(peer_id: int, appearance_id: Variant) -> void:
	var clean := CharacterAppearance.sanitize(appearance_id)
	if str(_appearances.get(peer_id, "")) == clean:
		return
	_appearances[peer_id] = clean
	if not avatars.has(peer_id):
		return
	var old: Node3D = avatars[peer_id]
	var fresh := _create_avatar(peer_id, old.position)
	fresh.rotation = old.rotation
	fresh.visible = old.visible
	avatars[peer_id] = fresh
	old.queue_free()

func appearance_for(peer_id: int) -> String:
	return CharacterAppearance.sanitize(_appearances.get(peer_id, CharacterAppearance.FALLBACK))

func _create_pickup(entry: Dictionary) -> Node3D:
	var is_weapon := str(entry.get("type", "")) == "weapon"
	var node := ArenaModels.build_weapon_pickup() if is_weapon else ArenaModels.build_ammo_pickup()
	# Mesma posição oficial de coleta; o servidor valida a distância por ela.
	node.position = entry.get("position", Vector3.ZERO)
	add_child(node)
	return node
