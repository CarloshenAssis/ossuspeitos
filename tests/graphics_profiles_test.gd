extends SceneTree
var failures := 0
func expect(ok: bool, why: String) -> void:
	if not ok:
		failures += 1
		push_error(why)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var a := ArenaView.new()
	var b := ArenaView.new()
	root.add_child(a)
	root.add_child(b)
	expect(a.has_method("set_graphics_profile"), "graphics profile API missing")
	if not a.has_method("set_graphics_profile"):
		quit(1)
		return
	var state := {"peer_id": 7, "position": Vector3(3, 0, 3), "velocity": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0}
	a.apply_snapshot([state], 1)
	b.apply_snapshot([state], 1)
	var fingerprint: String = preload("res://tests/mansion_art_test.gd").physical_fingerprint()
	var geometry := a.art.items.duplicate(true)
	var original: Material = a.art.meshes[0].mesh.surface_get_material(0)
	var original_color: Color = original.albedo_color
	var original_opacities := []
	for light in a.art.lights: original_opacities.append(light.shadow_opacity)
	var originals := []
	for node in a.art.meshes:
		originals.append(material_state(node.mesh.surface_get_material(0)))
	for profile in ["low", "high", "baseline", "baseline", "invalid"]:
		a.call("set_graphics_profile", profile)
		expect(a.art.items == geometry, "geometry unchanged " + profile)
		expect(preload("res://tests/mansion_art_test.gd").physical_fingerprint() == fingerprint, "official blockers unchanged")
		expect(b.art.meshes[0].material_override == null, "second view isolated")
		expect(original.albedo_color == original_color, "cached original unchanged")
		expect(a.targets == b.targets and a.targets[7] == state, "official state identical across profiles")
		expect(a.avatars[7].visible and b.avatars[7].visible, "target visibility preserved")
		var shadows := 0
		var light_index := 0
		for light in a.art.lights:
			expect(is_equal_approx(light.shadow_opacity, original_opacities[light_index]), "shadow contrast bounded and restored")
			light_index += 1
			if light.shadow_enabled: shadows += 1
		expect(shadows == 0, "selected shadow budget applied")
		expect(shadows <= 2 and a.art.lights.size() <= 32, "bounded light budget")
		var mesh_index := 0
		for node in a.art.meshes:
			expect(material_state(node.mesh.surface_get_material(0)) == originals[mesh_index], "cached material fully unchanged")
			mesh_index += 1
			var mat: Material = node.material_override
			expect(mat == null or mat is StandardMaterial3D, "Compatibility materials")
			if profile == "high":
				var source := node.mesh.surface_get_material(0) as StandardMaterial3D
				expect(mat.texture_filter == (BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC if source.albedo_texture != null else source.texture_filter), "high filters textured materials only")
			if profile == "low": expect(mat.shading_mode == BaseMaterial3D.SHADING_MODE_PER_VERTEX and mat.specular_mode == BaseMaterial3D.SPECULAR_DISABLED, "low reduces shading cost")
			expect(node.visible or str(node.get_meta("arena_blocker_kind", "")) == "ceiling", "geometry visibility preserved")
		expect(a.find_children("*", "CollisionObject3D", true, false).is_empty(), "no physics added")
	expect(a.get("graphics_profile") == "baseline", "invalid falls back")
	expect(a.art.meshes[0].material_override == null, "baseline restores original material")
	MenuSettings.path_override = "user://spec06-test.cfg"
	DirAccess.remove_absolute(MenuSettings.file_path())
	var settings := MenuSettings.load_saved()
	var initial_scale := root.scaling_3d_scale
	expect(not TouchControls.touch_device(), "headless does not select the mobile preset")
	expect(settings.graphics_profile == "baseline", "old/missing settings default baseline")
	a.apply_graphics_settings(settings)
	expect(a.graphics_profile == "baseline" and is_equal_approx(root.scaling_3d_scale, initial_scale),
		"headless preserves baseline shading and scale")
	expect(settings.save() == OK, "save unrelated preferences")
	settings = MenuSettings.load_saved()
	expect(not settings.graphics_profile_saved, "unrelated saves preserve automatic graphics")
	a.apply_graphics_settings(settings, true)
	var mobile_material := a.art.meshes[0].material_override as StandardMaterial3D
	expect(a.graphics_profile == "low" and mobile_material != null
		and mobile_material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_VERTEX
		and mobile_material.specular_mode == BaseMaterial3D.SPECULAR_DISABLED,
		"mobile preset uses low shading")
	expect(is_equal_approx(root.scaling_3d_scale, 0.7), "mobile preset lowers 3D scale")
	settings.graphics_profile = "baseline"
	expect(settings.save() == OK, "save explicit baseline")
	a.apply_graphics_settings(MenuSettings.load_saved(), true)
	expect(a.graphics_profile == "baseline", "explicit baseline overrides mobile low shading")
	settings.set("graphics_profile", "high")
	expect(settings.save() == OK, "save preference")
	expect(MenuSettings.load_saved().get("graphics_profile") == "high", "reload preference")
	settings.set("graphics_profile", "nonsense")
	settings.save()
	expect(MenuSettings.load_saved().get("graphics_profile") == "baseline", "sanitize saved preference")
	DirAccess.remove_absolute(MenuSettings.file_path())
	MenuSettings.path_override = ""
	a.free()
	expect(is_equal_approx(root.scaling_3d_scale, initial_scale), "leaving the mobile arena restores scale")
	b.free()
	if failures == 0: print("GRAPHICS_PROFILES_TEST_OK")
	quit(1 if failures else 0)

func material_state(mat: StandardMaterial3D) -> Array:
	return [mat.albedo_color, mat.albedo_texture, mat.roughness, mat.metallic, mat.shading_mode, mat.specular_mode, mat.texture_filter, mat.emission_enabled, mat.emission, mat.emission_energy_multiplier, mat.uv1_triplanar, mat.uv1_world_triplanar, mat.uv1_scale]
