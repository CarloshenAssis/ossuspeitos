class_name ArenaView
extends Node3D

var local_peer_id := 0
var avatars: Dictionary = {}
var targets: Dictionary = {}
var camera: Camera3D
var player_rig: Node3D

func _ready() -> void:
	_ensure_input_actions()
	_build_arena()
	player_rig = Node3D.new()
	add_child(player_rig)
	camera = Camera3D.new()
	camera.position.y = 0.7
	player_rig.add_child(camera)

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
		if peer_id == local_peer_id:
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
