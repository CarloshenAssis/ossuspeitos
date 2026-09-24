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
## Sigla de cada região no chip (cômodos; corredores usam "CR").
const ZONE_SIDES := {
	"escritorio": "ES", "biblioteca": "BI", "galeria": "GA", "salao": "SC", "cozinha": "CO",
	"jantar": "SJ", "quarto_fundo": "QF", "quarto_hospedes": "QH", "banheiro": "BA",
}
const CORRIDOR_SIDE := "CR"

## Cores de orientação por cômodo (blockout neutro com um matiz por ambiente).
## Apresentação pura: geometria e nomes vêm de `MansionMap`, a mesma fonte que
## o servidor usa para colisão e tiro.
const ZONE_COLORS := {
	"escritorio": Color(0.42, 0.52, 0.44),
	"biblioteca": Color(0.5, 0.4, 0.3),
	"galeria": Color(0.56, 0.44, 0.56),
	"salao": Color(0.62, 0.6, 0.57),
	"cozinha": Color(0.55, 0.62, 0.66),
	"jantar": Color(0.62, 0.46, 0.34),
	"quarto_fundo": Color(0.6, 0.5, 0.4),
	"quarto_hospedes": Color(0.44, 0.52, 0.66),
	"banheiro": Color(0.66, 0.7, 0.72),
}
const CORRIDOR_COLOR := Color(0.56, 0.36, 0.34)
## Recursos de inspeção (nomes dos cômodos, marcadores de spawn e teto
## recortado). Desligados na apresentação normal; ligar só muda o que se vê,
## nunca a simulação.
var debug_overlay := false
var show_ceilings := true
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

## Mansão montada por `MansionArt` (identidade visual da fase 2) a partir dos
## mesmos volumes oficiais usados pelo servidor.
var art: MansionArt

func _build_arena() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.035, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.84, 0.7)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	environment.environment = env
	add_child(environment)
	# Interior fechado por lajes: a luz vem dos pontos quentes de `MansionArt`
	# (sem sombra) e de uma direcional fraca, também sem sombra.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60.0, -35.0, 0.0)
	light.light_color = Color(1.0, 0.9, 0.78)
	light.light_energy = 0.25
	light.shadow_enabled = false
	add_child(light)
	art = MansionArt.new()
	art.build(self)
	for index in MovementRules.SPAWN_POINTS.size():
		_add_spawn_marker(MovementRules.SPAWN_POINTS[index])
	for room in MansionMap.rooms():
		_add_room_label(room)
	set_debug_overlay(debug_overlay)
	set_show_ceilings(show_ceilings)

## Liga os recursos de inspeção (nomes, spawns). Só apresentação.
func set_debug_overlay(enabled: bool) -> void:
	debug_overlay = enabled
	for node in get_children():
		if str(node.get_meta("arena_decor", "")) == "debug":
			(node as Node3D).visible = enabled

## Recorte visual do teto para inspeção de cima. As lajes oficiais continuam
## barrando tiros no servidor; aqui só a mesh some.
func set_show_ceilings(enabled: bool) -> void:
	show_ceilings = enabled
	for node in get_children():
		if node.has_meta("arena_blocker_kind") and str(node.get_meta("arena_blocker_kind")) == "ceiling":
			(node as Node3D).visible = enabled

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
	node.position = Vector3(spawn.x, 0.005, spawn.z)
	node.set_meta("arena_decor", "debug")
	add_child(node)

## Nome do cômodo flutuando no centro, para inspeção (visível de cima e de
## dentro). Só existe com `debug_overlay`.
func _add_room_label(room: Dictionary) -> void:
	var center := ((room["min"] as Vector2) + (room["max"] as Vector2)) * 0.5
	var label := Label3D.new()
	label.text = str(room["name"]).to_upper()
	label.font_size = 96
	label.pixel_size = 0.012
	label.outline_size = 18
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(center.x, 2.6, center.y)
	label.set_meta("arena_decor", "debug")
	add_child(label)

static func zone_color(position: Vector3) -> Color:
	return zone_color_by_id(str(ArenaRules.zone_at(position).get("id", "")))

static func zone_color_by_id(zone_id: String) -> Color:
	return ZONE_COLORS.get(zone_id, CORRIDOR_COLOR)

func _update_zone_label(position: Vector3) -> void:
	var zone := ArenaRules.zone_at(position)
	var zone_name := str(zone.get("name", ""))
	if zone_name == current_zone_name or region_chip == null:
		return
	current_zone_name = zone_name
	region_chip.visible = not zone_name.is_empty()
	region_name.text = zone_name.to_upper()
	region_side.text = str(ZONE_SIDES.get(str(zone.get("id", "")), CORRIDOR_SIDE))
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
