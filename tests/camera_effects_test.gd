extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var script = load("res://client/camera_effects.gd")
	check(script != null, "camera effects module exists")
	if script == null:
		quit(1)
		return
	var disabled = script.new()
	disabled.strength = 0.0
	check(disabled.sample(100.0, 1.0) == Transform3D.IDENTITY, "disabled strength identity")
	var endpoints: Array = []
	for fps in [20, 60, 144]:
		var effects = script.new()
		check(effects.sample(0.0, 0.0) == Transform3D.IDENTITY, "zero identity")
		for frame in fps:
			var pose: Transform3D = effects.sample(4.0, 1.0 / fps)
			check(pose.origin.is_finite() and pose.origin.length() < 0.025, "bounded visual translation")
		endpoints.append(effects.sample(4.0, 0.0))
		for frame in fps * 3:
			effects.sample(0.0, 1.0 / fps)
		check(effects.sample(0.0, 0.0).origin.length() < 0.00001, "stop settles")
	check(endpoints[0].is_equal_approx(endpoints[1]) and endpoints[1].is_equal_approx(endpoints[2]), "equal elapsed frames")
	var arena := ArenaView.new()
	root.add_child(arena)
	arena.set_process(false)
	arena.apply_snapshot([{"peer_id": 1, "position": Vector3.ZERO, "yaw": 0.3, "pitch": 0.2, "velocity": Vector3(4,0,0)}])
	arena.local_peer_id = 1
	arena.apply_snapshot([{"peer_id": 1, "position": Vector3.ZERO, "yaw": 0.3, "pitch": 0.2, "velocity": Vector3(4,0,0)}])
	arena.apply_combat_state({"round_id": 1, "health": 100, "weapon_id": "common_pistol"})
	arena._process(0.0)
	var official := arena._local_state.duplicate(true)
	var origin := arena.camera_origin()
	var direction := arena.camera_direction()
	for i in 60: arena._process(1.0/60)
	check(arena.camera_origin() == origin and arena.camera_direction() == direction and arena._local_state == official, "exact official aim/origin/state invariant")
	check(arena.motion_pivot.transform != Transform3D.IDENTITY, "moving viewmodel animates")
	arena._recoil()
	for frame in 30: await process_frame
	check(arena.weapon_pivot.position.is_equal_approx(ArenaView.VIEWMODEL_OFFSET) and arena.weapon_pivot.rotation.is_equal_approx(Vector3.ZERO), "recoil recovers on its own pivot")
	var app = load("res://shared/network_app.gd").new()
	app.arena_view = arena
	var preferences := MenuSettings.new()
	preferences.reduce_motion = true
	app._apply_menu_settings(preferences)
	check(not arena.presentation_motion and arena.motion_pivot.transform == Transform3D.IDENTITY, "live reduce motion settings propagate")
	app.arena_view = null
	app.free()
	arena.set_presentation_motion(false)
	check(arena.motion_pivot.transform == Transform3D.IDENTITY, "disable immediate reset")
	arena.set_presentation_motion(true)
	arena._process(0.1)
	arena.apply_combat_state({"round_id": 1, "health": 0, "weapon_id": "common_pistol"})
	check(arena.camera.h_offset == 0.0 and arena.camera.v_offset == 0.0, "lethal damage resets projection immediately")
	arena.set_player_alive(1, false)
	check(arena.motion_pivot.transform == Transform3D.IDENTITY, "death reset")
	arena.set_spectator_target(0)
	check(arena.motion_pivot.transform == Transform3D.IDENTITY, "spectator reset")
	# Real tracer regression: correct world-space forward after entering tree.
	arena.show_shot({"origin": Vector3(1,2,3), "end": Vector3(5,3,-4)})
	var tracer := arena.get_child(arena.get_child_count()-1) as MeshInstance3D
	check(tracer != null and (-tracer.global_basis.z).normalized().is_equal_approx(Vector3(4,1,-7).normalized()), "tracer faces endpoint without engine error")
	await create_timer(0.6).timeout
	arena.free()
	if failures == 0: print("CAMERA_EFFECTS_TEST_OK")
	quit(0 if failures == 0 else 1)
