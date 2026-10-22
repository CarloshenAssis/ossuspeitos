extends Node3D

## Isolated deterministic server harness. Meshes only present official events;
## they never perform a second raycast or feed transforms back to the world.
var world := AuthoritativeWorld.new()
var authority: CombatAuthority
var events: Array = []
var camera := Camera3D.new()
var elapsed := 0.0
var replayed := false
var failed := false

func _ready() -> void:
	var rounds := RoundAuthority.new()
	rounds.state = RoundState.ACTIVE
	rounds.round_id = 1
	rounds.participants = {1: true, 2: true, 3: true, 4: true}
	rounds.alive = rounds.participants.duplicate()
	for peer in range(1, 5): world.add_player(peer)
	var catalog := WeaponCatalog.defaults()
	var definition: WeaponDefinition = catalog["common_pistol"]
	definition.damage = 0
	definition.magazine_capacity = 24
	definition.movement_spread_radians = 0.1
	definition.bloom_per_shot_radians = 0.02
	definition.max_bloom_radians = 0.05
	definition.bloom_recovery_radians_per_second = 0.01
	var rng := RandomNumberGenerator.new()
	rng.seed = 481
	authority = CombatAuthority.new(rounds, world, catalog, rng)
	authority.begin_round(1, [1, 2, 3, 4])
	world.states[1]["position"] = Vector3(12, MovementRules.PLAYER_HEIGHT, 15.5)
	world.states[1]["yaw"] = 0.0
	world.states[2]["position"] = Vector3(12, MovementRules.PLAYER_HEIGHT, 9)
	world.states[3]["position"] = Vector3(10, MovementRules.PLAYER_HEIGHT, 12)
	world.states[4]["position"] = Vector3(16, MovementRules.PLAYER_HEIGHT, 12)
	authority.inventory.add_ground_weapon("lab_gun", "common_pistol", world.states[1]["position"], -1, 0, 1)
	_check(authority.request_pickup(1, "lab_gun", 1, 100).get("accepted", false), "pickup")
	authority.shot_resolved.connect(_show_shot)
	# Public collision data supply obstacles; only the central-room subset is
	# displayed, with ceilings omitted for observation. Official world is intact.
	_box(Vector3(13.5, -0.1, 12), Vector3(12, 0.2, 12), Color(0.12, 0.15, 0.19))
	for blocker in MansionMap.blockers():
		var center: Vector3 = blocker["center"]
		if blocker["kind"] != "ceiling" and center.x > 7 and center.x < 20 and center.z > 6 and center.z < 18:
			_box(center, blocker["size"], Color(0.32, 0.36, 0.4))
	for peer in range(2, 5):
		_box(world.states[peer]["position"], Vector3(ArenaRules.PLAYER_HIT_RADIUS * 2, ArenaRules.PLAYER_HIT_HEIGHT, ArenaRules.PLAYER_HIT_RADIUS * 2), Color(0.2, 0.65, 0.8))
	add_child(camera)
	camera.position = Vector3(15, 5.5, 19)
	camera.look_at(Vector3(12, 1, 11))
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -20, 0)
	add_child(light)
	var label := Label.new()
	label.text = "SPEC04 • seed 481 • server-owned hitscan\nYellow: stationary bloom / Orange: moving / Green: recovered\nLab only: movement .1, bloom .02 / cap .05 / recovery .01 rad/s\nOfficial aim fixed; visual camera moves independently. Esc exits."
	label.position = Vector2(18, 18)
	add_child(label)

func _process(delta: float) -> void:
	elapsed += delta
	if not replayed:
		replayed = true
		var aim := Vector2(world.states[1]["yaw"], world.states[1]["pitch"])
		var visual := camera.transform
		# Exercise presentation movement before firing: server aim is unchanged.
		camera.rotate_x(0.03)
		camera.position += Vector3(0.02, 0, 0)
		for index in 12:
			world.states[1]["velocity"] = Vector3.ZERO if index < 6 or index == 11 else Vector3(5, 0, 0)
			var time := 1000 + index * 400 if index < 11 else 12000
			_check(authority.request_fire(1, index + 1, time).get("accepted", false), "shot %d" % index)
		_check(Vector2(world.states[1]["yaw"], world.states[1]["pitch"]) == aim, "visual transform isolation")
		camera.transform = visual
		_check(events.size() == 12, "event count")
		if events.size() == 12:
			_check((events[0]["end"] as Vector3).is_equal_approx(events[11]["end"]), "idle restores first shot endpoint")
		print("GUNPLAY_LAB_%s shots=%d seed=481 official_aim_error=0" % ["FAILED" if failed else "OK", events.size()])
	if Input.is_physical_key_pressed(KEY_ESCAPE) or ("--lab-smoke" in OS.get_cmdline_user_args() and elapsed >= 2.0):
		get_tree().quit(1 if failed else 0)

func _show_shot(event: Dictionary) -> void:
	events.append(event.duplicate(true))
	var color := Color.YELLOW if events.size() <= 6 else Color.ORANGE
	if events.size() == 12: color = Color.GREEN
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	mesh.surface_add_vertex(event["origin"])
	mesh.surface_add_vertex(event["end"])
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	add_child(instance)
	_box(event["end"], Vector3.ONE * 0.07, color)

func _box(center: Vector3, size: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = center
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.material_override = material
	add_child(node)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failed = true
		push_error("GUNPLAY_LAB " + label)
