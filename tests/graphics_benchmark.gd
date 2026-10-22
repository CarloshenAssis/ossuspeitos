extends Node3D
## Real presented-frame wall time, including driver scheduling; never GPU-only time.
var samples: Array[float] = []
var frame := 0
var previous := 0
var view: ArenaView
var profile := "baseline"
const WARMUP := 120
const SAMPLES := 300
func _ready() -> void:
	if DisplayServer.get_name() in ["headless", "dummy"]:
		push_error("RENDER_BENCHMARK_REJECTED headless/dummy")
		get_tree().quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="): profile = arg.trim_prefix("--profile=")
	DisplayServer.window_set_size(Vector2i(960, 540))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	view = ArenaView.new()
	add_child(view)
	view.set_gameplay_visuals(false)
	view.set_process(false)
	view.camera.current = true
	view.player_rig.position = Vector3(3, 0, 4)
	view.player_rig.rotation.y = 0.0
	if view.has_method("set_graphics_profile"): view.call("set_graphics_profile", profile)
	previous = Time.get_ticks_usec()
func _process(_delta: float) -> void:
	if view == null: return
	var now := Time.get_ticks_usec()
	var elapsed := float(now - previous) / 1000.0
	previous = now
	frame += 1
	if frame > WARMUP: samples.append(elapsed)
	if samples.size() < SAMPLES: return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--screenshot="))
	samples.sort()
	print("GRAPHICS_BENCHMARK ", JSON.stringify({"profile": profile, "warmup": WARMUP, "samples": SAMPLES, "p50_ms": samples[149], "p95_ms": samples[284], "p99_ms": samples[296], "cpu": OS.get_processor_name(), "nodes": view.get_child_count(), "meshes": view.art.meshes.size(), "lights": view.art.lights.size(), "max_ms": samples[299], "renderer": RenderingServer.get_current_rendering_method(), "device": RenderingServer.get_video_adapter_name(), "resolution": str(DisplayServer.window_get_size()), "version": Engine.get_version_info().string, "display": DisplayServer.get_name()}))
	get_tree().quit()
