class_name ArenaView
extends Node3D

var local_peer_id := 0
var avatars: Dictionary = {}
var targets: Dictionary = {}
var camera: Camera3D
var player_rig: Node3D
var pickup_nodes: Dictionary = {}
var pickup_states: Dictionary = {}
var weapon_model: MeshInstance3D
var hit_marker: Label
var crosshair: Label
var spectator_target_peer_id := 0

func _ready() -> void:
	_ensure_input_actions()
	_build_arena()
	player_rig = Node3D.new()
	add_child(player_rig)
	camera = Camera3D.new()
	camera.position.y = 0.7
	player_rig.add_child(camera)
	weapon_model = MeshInstance3D.new()
	var weapon_mesh := BoxMesh.new()
	weapon_mesh.size = Vector3(0.16, 0.16, 0.65)
	weapon_model.mesh = weapon_mesh
	weapon_model.position = Vector3(0.28, -0.22, -0.55)
	weapon_model.visible = false
	camera.add_child(weapon_model)
	var overlay := CanvasLayer.new()
	add_child(overlay)
	crosshair = Label.new()
	crosshair.text = "+"
	crosshair.position = Vector2(474, 258)
	crosshair.add_theme_font_size_override("font_size", 24)
	overlay.add_child(crosshair)
	hit_marker = Label.new()
	hit_marker.text = "✕"
	hit_marker.position = Vector2(473, 258)
	hit_marker.modulate = Color(1, 0.25, 0.2, 0)
	overlay.add_child(hit_marker)

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
			player_rig.position = state["position"]
			player_rig.rotation.y = float(state["yaw"])
		if peer_id == local_peer_id and spectator_target_peer_id == 0:
			player_rig.position = state["position"]
			player_rig.rotation.y = float(state["yaw"])
			continue
		if not avatars.has(peer_id):
			avatars[peer_id] = _create_avatar(peer_id, state["position"])
		targets[peer_id] = state
	for peer_id in avatars.keys():
		if not present.has(peer_id):
			avatars[peer_id].queue_free()
			avatars.erase(peer_id)
			targets.erase(peer_id)

func _process(delta: float) -> void:
	var weight := 1.0 - exp(-12.0 * delta)
	for peer_id in targets:
		if not avatars.has(peer_id):
			continue
		var avatar: Node3D = avatars[peer_id]
		var state: Dictionary = targets[peer_id]
		avatar.position = avatar.position.lerp(state["position"], weight)
		avatar.rotation.y = lerp_angle(avatar.rotation.y, float(state["yaw"]), weight)

func _build_arena() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.1, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.7, 0.8)
	env.ambient_light_energy = 0.8
	environment.environment = env
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	light.shadow_enabled = true
	add_child(light)
	_add_box(Vector3(0.0, -0.25, 0.0), Vector3(25.0, 0.5, 25.0), Color(0.22, 0.25, 0.3))
	_add_box(Vector3(-12.25, 1.5, 0.0), Vector3(0.5, 3.5, 25.0), Color(0.35, 0.4, 0.5))
	_add_box(Vector3(12.25, 1.5, 0.0), Vector3(0.5, 3.5, 25.0), Color(0.35, 0.4, 0.5))
	_add_box(Vector3(0.0, 1.5, -12.25), Vector3(25.0, 3.5, 0.5), Color(0.35, 0.4, 0.5))
	_add_box(Vector3(0.0, 1.5, 12.25), Vector3(25.0, 3.5, 0.5), Color(0.35, 0.4, 0.5))
	_add_box(Vector3(0.0, 1.0, 0.0), Vector3(1.0, 2.0, 7.0), Color(0.45, 0.32, 0.25))

func _add_box(box_position: Vector3, size: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = box_position
	add_child(mesh_instance)

func _create_avatar(peer_id: int, initial_position: Vector3) -> Node3D:
	var avatar := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.height = 2.0
	mesh.radius = 0.45
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.from_hsv(fmod(float(peer_id) * 0.173, 1.0), 0.7, 0.95)
	mesh.material = material
	avatar.mesh = mesh
	avatar.position = initial_position
	add_child(avatar)
	return avatar

func camera_origin() -> Vector3:
	return camera.global_position if camera != null else Vector3.ZERO

func camera_direction() -> Vector3:
	return -camera.global_transform.basis.z.normalized() if camera != null else Vector3.FORWARD

func apply_combat_state(state: Dictionary) -> void:
	if weapon_model != null:
		weapon_model.visible = not str(state.get("weapon_id", "")).is_empty() and int(state.get("health", 0)) > 0

## Seleciona apenas um ID previamente autorizado pela camada de rede. A camera
## segue posicao/yaw oficiais recebidos em snapshots; nunca envia controle.
func set_spectator_target(peer_id: int, spectator_active: bool = true) -> void:
	spectator_target_peer_id = peer_id
	if crosshair != null: crosshair.visible = not spectator_active
	if weapon_model != null and spectator_active: weapon_model.visible = false

func apply_pickups(entries: Array) -> void:
	pickup_states.clear()
	for raw_entry in entries:
		if typeof(raw_entry) != TYPE_DICTIONARY: continue
		var entry: Dictionary = raw_entry
		var pickup_id := str(entry.get("pickup_id", ""))
		pickup_states[pickup_id] = entry
		if not pickup_nodes.has(pickup_id):
			pickup_nodes[pickup_id] = _create_pickup(entry)
		(pickup_nodes[pickup_id] as Node3D).visible = bool(entry.get("available", false))
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

func show_hit_marker() -> void:
	if hit_marker == null: return
	hit_marker.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(hit_marker, "modulate:a", 0.0, 0.2)

func set_player_alive(peer_id: int, alive: bool) -> void:
	if avatars.has(peer_id):
		(avatars[peer_id] as Node3D).visible = alive

func _create_pickup(entry: Dictionary) -> Node3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 0.25, 0.8) if str(entry.get("type", "")) == "weapon" else Vector3(0.5, 0.4, 0.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.55, 0.95) if str(entry.get("type", "")) == "weapon" else Color(0.95, 0.72, 0.2)
	mesh.material = material
	node.mesh = mesh
	node.position = entry.get("position", Vector3.ZERO)
	add_child(node)
	return node
