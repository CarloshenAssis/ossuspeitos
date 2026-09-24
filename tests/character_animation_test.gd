extends SceneTree

## Repouso e locomoção procedurais (fase 3), medidos pelo que se vê:
## - pivôs de `CharacterRig` preservam a pose de repouso das oito variantes e
##   não se duplicam ao reconstruir;
## - pés no piso e pé de apoio sem deslizar (frente, trás), pernas que não se
##   cruzam (lado), mistura na diagonal;
## - início/parada sem estalo e volta ao repouso sem perna suspensa;
## - cadência pela distância, igual a 20, 60 e 144 quadros por segundo;
## - contra a parede não há ciclo; snapshot atrasado e teleporte não geram
##   passadas gigantes;
## - pitch da cabeça coexistindo com a caminhada, raiz/câmera/hitbox oficiais
##   intocadas, reinstanciação sem restos e as oito variantes compatíveis.

const EPS := 0.0001
var failures := 0
var checks := 0
var _view: ArenaView
var _frames := 0
var _report: Array = []

func _initialize() -> void:
	for appearance_id in CharacterAppearance.IDS:
		_test_rig_preserves_rest(appearance_id)
	_test_forward_and_backward_plant_the_feet()
	_test_side_steps_never_cross()
	_test_diagonal_blends()
	_test_start_and_stop()
	_test_cadence_ignores_frame_rate()
	_test_blocked_against_wall()
	_test_late_snapshot_and_teleport()
	_test_all_variants_walk()
	_view = ArenaView.new()
	_view.local_peer_id = 1
	root.add_child(_view)

func _process(delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_test_view_integration()
		for line in _report:
			print(line)
		if failures > 0:
			push_error("CHARACTER_ANIMATION_TEST_FAILED failures=%d checks=%d" % [failures, checks])
			quit(1)
		else:
			print("CHARACTER_ANIMATION_TEST_OK checks=%d" % checks)
			quit(0)
	return false

# --- Rig ------------------------------------------------------------------------

func _test_rig_preserves_rest(appearance_id: String) -> void:
	var avatar := ArenaModels.build_character(appearance_id)
	var model := avatar.get_node(ArenaModels.CHARACTER_MODEL) as Node3D
	var before := {}
	for node in model.find_children("*", "MeshInstance3D", true, false):
		before[str(node.name)] = _global_of(node)
	var rig := CharacterRig.build(model)
	_expect(not rig.is_empty(), "%s gets a rig" % appearance_id)
	var moved := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var after := _global_of(node)
		if not after.is_equal_approx(before[str(node.name)]):
			moved += 1
	_expect(moved == 0 and before.size() == model.find_children("*", "MeshInstance3D", true, false).size(), "%s keeps every part exactly in its rest pose (%d moved)" % [appearance_id, moved])
	var visual := model.find_child("CharacterVisual", true, false)
	for child in visual.get_children():
		_expect(not (child is MeshInstance3D), "%s: part %s was adopted by a pivot" % [appearance_id, child.name])
	var pivots: Dictionary = rig["pivots"]
	_expect((pivots["Ankle_L"] as Node).find_child("Shoe_L", false, false) != null and (pivots["Ankle_L"] as Node).get_parent() == pivots["Knee_L"] and (pivots["Elbow_R"] as Node).find_child("Hand_R", false, false) != null, "%s: shoe on the ankle below the knee, hand on the elbow" % appearance_id)
	_expect((pivots[CharacterRig.TORSO] as Node).get_node_or_null(ArenaModels.HEAD_PIVOT) != null, "%s: the head pivot rides on the torso" % appearance_id)
	_expect((pivots["Hip_L"] as Node).get_parent() == visual and (pivots["Shoulder_L"] as Node).get_parent() == pivots[CharacterRig.TORSO], "%s: legs hang from the model, arms from the torso" % appearance_id)
	# Extras de cada variante vão para o segmento que os contém.
	var assigned: Dictionary = rig["assigned"]
	for part in ["Pocket_L", "Band_L", "Cuff_L", "Knee_L"]:
		if assigned.has(part):
			var expected: String = {"Pocket_L": "Hip_L", "Band_L": "Shoulder_L", "Cuff_L": "Elbow_L", "Knee_L": "Knee_L"}[part]
			_expect(str(assigned[part]) == expected, "%s: %s rides on %s (got %s)" % [appearance_id, part, expected, assigned[part]])
	# Reconstruir não duplica pivôs.
	var count := model.find_children("*", "Node3D", true, false).size()
	CharacterRig.build(model)
	_expect(model.find_children("*", "Node3D", true, false).size() == count, "%s: building the rig twice adds nothing" % appearance_id)
	avatar.free()

# --- Locomoção ------------------------------------------------------------------

## Corpo andando em linha reta com velocidade constante; devolve amostras.
func _walk(appearance_id: String, yaw: float, world_direction: Vector3, speed: float, seconds: float, fps: float, stop_after: float = INF) -> Dictionary:
	var avatar := ArenaModels.build_character(appearance_id)
	var model := avatar.get_node(ArenaModels.CHARACTER_MODEL) as Node3D
	var animator := CharacterAnimator.new(model)
	avatar.rotation.y = yaw
	var dt := 1.0 / fps
	var samples: Array = []
	var time := 0.0
	var position := Vector3.ZERO
	animator.reset(position)
	for frame in int(round(seconds * fps)):
		time += dt
		if time <= stop_after:
			position += world_direction.normalized() * speed * dt
		avatar.position = position
		animator.update(position, yaw, dt)
		samples.append(_sample(avatar, model, animator, time))
	var result := {"samples": samples, "animator": animator, "avatar": avatar, "model": model}
	return result

func _sample(avatar: Node3D, model: Node3D, animator: CharacterAnimator, time: float) -> Dictionary:
	var feet := []
	for side in ["L", "R"]:
		var shoe := model.find_child("Shoe_" + side, true, false) as MeshInstance3D
		var box := _global_of(shoe) * shoe.get_aabb()
		feet.append(box)
	var pivots: Dictionary = animator.rig["pivots"]
	return {"t": time, "feet": feet, "root": avatar.position, "phase": animator.phase, "amp": animator.amplitude,
		"hip_l": (pivots["Hip_L"] as Node3D).rotation, "hip_r": (pivots["Hip_R"] as Node3D).rotation,
		"knee_l": (pivots["Knee_L"] as Node3D).rotation.x, "knee_r": (pivots["Knee_R"] as Node3D).rotation.x,
		"shoulder_l": (pivots["Shoulder_L"] as Node3D).rotation.x, "model_y": model.position.y}

## Pé mais baixo em cada quadro: altura (piso = 0 no mundo, raiz no centro do
## corpo a 1 m) e deslizamento enquanto o mesmo pé segue como apoio.
func _feet_report(samples: Array, root_height: float) -> Dictionary:
	var lowest_min := INF
	var lowest_max := -INF
	var slide := 0.0
	var worst_slide := 0.0
	var stance := -1
	var anchor := Vector3.ZERO
	for sample in samples:
		var feet: Array = sample["feet"]
		var left: AABB = feet[0]
		var right: AABB = feet[1]
		var index := 0 if left.position.y <= right.position.y else 1
		var foot: AABB = feet[index]
		var bottom := foot.position.y + root_height
		lowest_min = minf(lowest_min, bottom)
		lowest_max = maxf(lowest_max, bottom)
		var center := foot.get_center()
		center.y = 0.0
		if index != stance:
			stance = index
			anchor = center
			worst_slide = maxf(worst_slide, slide)
			slide = 0.0
		else:
			slide = maxf(slide, center.distance_to(anchor))
	return {"lowest_min": lowest_min, "lowest_max": lowest_max, "worst_slide": maxf(worst_slide, slide)}

func _test_forward_and_backward_plant_the_feet() -> void:
	for case in [["forward", 0.0, Vector3.FORWARD], ["backward", 0.0, Vector3.BACK]]:
		var run := _walk("ember", case[1], case[2], MovementRules.MAX_SPEED, 3.0, 60.0)
		var samples: Array = run["samples"]
		var steady := samples.slice(60)
		var feet := _feet_report(steady, 1.0)
		_report.append("ANIM_%s lowest_foot=%.3f..%.3f stance_slide=%.3f" % [str(case[0]).to_upper(), feet["lowest_min"], feet["lowest_max"], feet["worst_slide"]])
		_expect(feet["lowest_min"] > -0.04 and feet["lowest_max"] < 0.04, "%s: the supporting foot stays on the floor (%.3f..%.3f)" % [case[0], feet["lowest_min"], feet["lowest_max"]])
		_expect(feet["worst_slide"] < 0.2, "%s: the supporting foot barely slides (%.3f m per stance)" % [case[0], feet["worst_slide"]])
		# Alternância: as pernas trocam de lado com a cadência da distância.
		var flips := 0
		var previous := 0.0
		for sample in steady:
			var hip: Vector3 = sample["hip_l"]
			if absf(hip.x) > 0.05:
				if previous != 0.0 and signf(hip.x) != signf(previous):
					flips += 1
				previous = hip.x
		var distance := MovementRules.MAX_SPEED * 2.0
		var expected := distance / (run["animator"] as CharacterAnimator).cycle_length() * 2.0
		_expect(absf(flips - expected) <= 2.0, "%s: legs alternate %.0f times in %.0f m (%d)" % [case[0], expected, distance, flips])
		# Pernas opostas e braço oposto à perna do mesmo lado.
		var mid: Dictionary = steady[steady.size() / 2]
		var hl: Vector3 = mid["hip_l"]
		var hr: Vector3 = mid["hip_r"]
		_expect(hl.x * hr.x <= 0.0001, "%s: the legs swing in opposition" % case[0])
		_expect(float(mid["shoulder_l"]) * hl.x <= 0.0001, "%s: each arm swings against its own leg" % case[0])
		(run["avatar"] as Node).free()
	# Para trás: o pé de apoio avança em relação ao corpo (movimento contrário
	# ao de andar para frente), e a fase gira no mesmo sentido do percurso.
	var back := _walk("ember", 0.0, Vector3.BACK, 3.0, 2.0, 60.0)
	var forward := _walk("ember", 0.0, Vector3.FORWARD, 3.0, 2.0, 60.0)
	var b: Dictionary = (back["samples"] as Array)[90]
	var f: Dictionary = (forward["samples"] as Array)[90]
	_expect(absf(float(b["phase"]) - float(f["phase"])) < 0.01 and absf((b["hip_l"] as Vector3).x + (f["hip_l"] as Vector3).x) < 0.01,
		"walking backwards mirrors the forward swing at the same distance")
	(back["avatar"] as Node).free()
	(forward["avatar"] as Node).free()

func _test_side_steps_never_cross() -> void:
	for direction in [Vector3.RIGHT, Vector3.LEFT]:
		var run := _walk("dawn", 0.0, direction, 3.0, 2.5, 60.0)
		var samples: Array = run["samples"]
		var crossed := 0
		var abducted := 0.0
		for sample in samples.slice(30):
			var feet: Array = sample["feet"]
			var root: Vector3 = sample["root"]
			# Os dois pés mantêm a mesma ordem lateral em relação ao corpo.
			var l_side := (feet[0] as AABB).get_center().x - root.x
			var r_side := (feet[1] as AABB).get_center().x - root.x
			if signf(l_side) == signf(r_side) and absf(l_side - r_side) < 0.05:
				crossed += 1
			abducted = maxf(abducted, absf((sample["hip_l"] as Vector3).z) + absf((sample["hip_r"] as Vector3).z))
			_expect(absf((sample["hip_l"] as Vector3).x) < 0.02, "side steps do not swing the legs forward")
		_expect(crossed == 0, "side steps never cross the legs (%s)" % str(direction))
		_expect(abducted > CharacterAnimator.SIDE_ABDUCT * 0.5, "side steps open the legs sideways (%.2f)" % abducted)
		var feet := _feet_report(samples.slice(30), 1.0)
		_expect(feet["lowest_min"] > -0.04 and feet["lowest_max"] < 0.04, "side steps keep a foot on the floor")
		(run["avatar"] as Node).free()

func _test_diagonal_blends() -> void:
	var run := _walk("sand", 0.0, Vector3(1, 0, -1), MovementRules.MAX_SPEED, 2.0, 60.0)
	var swing := 0.0
	var abduct := 0.0
	for sample in (run["samples"] as Array).slice(40):
		swing = maxf(swing, absf((sample["hip_l"] as Vector3).x))
		abduct = maxf(abduct, absf((sample["hip_l"] as Vector3).z) + absf((sample["hip_r"] as Vector3).z))
	_expect(swing > 0.15 and swing < CharacterAnimator.HIP_SWING and abduct > 0.03 and abduct < CharacterAnimator.SIDE_ABDUCT * 2.0,
		"a diagonal blends forward swing (%.2f) and side opening (%.2f)" % [swing, abduct])
	(run["avatar"] as Node).free()

func _test_start_and_stop() -> void:
	var run := _walk("ember", 0.0, Vector3.FORWARD, MovementRules.MAX_SPEED, 3.0, 60.0, 1.5)
	var samples: Array = run["samples"]
	# Nenhum estalo: no início (primeiros 0,3 s) e na parada (0,5 s depois de
	# parar) nenhuma junta anda mais rápido que no passo regular.
	var steady := _max_joint_step(samples, 45, 90)
	var start := _max_joint_step(samples, 1, 18)
	var stop := _max_joint_step(samples, 90, 120)
	_expect(start <= steady * 1.05 + 0.005 and stop <= steady * 1.05 + 0.005, "start (%.3f) and stop (%.3f) are no faster than the steady walk (%.3f rad/frame)" % [start, stop, steady])
	var worst_jump := maxf(start, stop)
	var last: Dictionary = samples.back()
	_expect((last["hip_l"] as Vector3).length() < 0.02 and (last["hip_r"] as Vector3).length() < 0.02 and absf(float(last["knee_l"])) < 0.02 and absf(float(last["knee_r"])) < 0.02,
		"1.5 s after stopping every leg is back at rest")
	var feet: Array = last["feet"]
	_expect(absf((feet[0] as AABB).position.y + 1.0) < 0.012 and absf((feet[1] as AABB).position.y + 1.0) < 0.012, "no leg stays lifted after stopping")
	_report.append("ANIM_START_STOP worst_joint_step=%.3f rad" % worst_jump)
	(run["avatar"] as Node).free()

func _max_joint_step(samples: Array, from: int, to: int) -> float:
	var worst := 0.0
	for index in range(maxi(from, 1), mini(to, samples.size())):
		for key in ["hip_l", "hip_r"]:
			worst = maxf(worst, ((samples[index][key] as Vector3) - (samples[index - 1][key] as Vector3)).length())
		for key in ["knee_l", "knee_r", "shoulder_l"]:
			worst = maxf(worst, absf(float(samples[index][key]) - float(samples[index - 1][key])))
	return worst

func _test_cadence_ignores_frame_rate() -> void:
	var phases := []
	for fps in [20.0, 60.0, 144.0]:
		var run := _walk("ember", 0.0, Vector3.FORWARD, 3.5, 2.0, fps)
		phases.append(float((run["samples"] as Array).back()["phase"]))
		(run["avatar"] as Node).free()
	_expect(absf(angle_difference(phases[0], phases[1])) < 0.05 and absf(angle_difference(phases[1], phases[2])) < 0.05,
		"the walk cycle depends on distance, not frame rate (%s)" % str(phases))
	# E acompanha a velocidade: metade da velocidade, metade do ciclo.
	var slow := _walk("ember", 0.0, Vector3.FORWARD, 1.75, 2.0, 60.0)
	var fast := _walk("ember", 0.0, Vector3.FORWARD, 3.5, 2.0, 60.0)
	# Mesma distância percorrida ⇒ mesma fase, qualquer que seja a velocidade.
	var half := _walk("ember", 0.0, Vector3.FORWARD, 1.75, 4.0, 60.0)
	_expect(absf(angle_difference(float((half["samples"] as Array).back()["phase"]), float((fast["samples"] as Array).back()["phase"]))) < 0.01,
		"cadence follows the presented distance: half speed for twice the time lands on the same phase")
	var fast_last: Dictionary = (fast["samples"] as Array).back()
	_expect(absf(angle_difference(float(fast_last["phase"]), fposmod(3.5 * 2.0 / (fast["animator"] as CharacterAnimator).cycle_length() * TAU, TAU))) < 0.01,
		"the phase is exactly the walked distance over the cycle length")
	(half["avatar"] as Node).free()
	(slow["avatar"] as Node).free()
	(fast["avatar"] as Node).free()
	_report.append("ANIM_CADENCE phases_20_60_144=%s" % str(phases))

func _test_blocked_against_wall() -> void:
	# Tecla pressionada contra a parede: o estado oficial não muda, então a
	# posição apresentada fica parada.
	var run := _walk("ember", 0.0, Vector3.FORWARD, 0.0, 2.0, 60.0)
	var samples: Array = run["samples"]
	var biggest := 0.0
	for sample in samples:
		biggest = maxf(biggest, (sample["hip_l"] as Vector3).length())
	_expect(biggest < 0.001 and float(samples.back()["amp"]) == 0.0, "a player held against a wall does not walk in place")
	(run["avatar"] as Node).free()
	# Deslizando rente à parede (movimento real bem lento): no máximo passos curtos.
	var creep := _walk("ember", 0.0, Vector3.FORWARD, 0.2, 2.0, 60.0)
	_expect(float((creep["samples"] as Array).back()["amp"]) < 0.05, "a tiny corrective drift stays idle")
	(creep["avatar"] as Node).free()

func _test_late_snapshot_and_teleport() -> void:
	var avatar := ArenaModels.build_character("ember")
	var model := avatar.get_node(ArenaModels.CHARACTER_MODEL) as Node3D
	var animator := CharacterAnimator.new(model)
	var position := Vector3.ZERO
	animator.reset(position)
	for frame in 60:
		position += Vector3.FORWARD * MovementRules.MAX_SPEED / 60.0
		animator.update(position, 0.0, 1.0 / 60.0)
	# Snapshot atrasado: meio segundo parado, depois alcança 0,8 m de uma vez.
	for frame in 30:
		animator.update(position, 0.0, 1.0 / 60.0)
	var phase_before := animator.phase
	position += Vector3.FORWARD * 0.8
	animator.update(position, 0.0, 1.0 / 60.0)
	var max_advance := CharacterAnimator.MAX_PRESENTED_SPEED / 60.0 / minf(CharacterAnimator.SIDE_CYCLE_LENGTH, animator.cycle_length()) * TAU
	_expect(absf(angle_difference(phase_before, animator.phase)) <= max_advance + 0.001, "a late catch-up snapshot advances at most one frame of top speed (%.3f rad)" % absf(angle_difference(phase_before, animator.phase)))
	_expect(animator.amplitude <= 1.0, "amplitude stays bounded after a catch-up")
	# Teleporte: sem avanço de fase, conta como reposicionamento.
	phase_before = animator.phase
	position += Vector3(20, 0, -15)
	animator.update(position, 0.0, 1.0 / 60.0)
	_expect(absf(angle_difference(phase_before, animator.phase)) < 0.0001 and animator.teleports == 1, "a teleport resets the reference without a giant stride")
	# Reset explícito (rodada nova): a próxima posição não conta distância.
	animator.reset()
	phase_before = animator.phase
	animator.update(Vector3(-30, 1, 40), 0.0, 1.0 / 60.0)
	_expect(absf(angle_difference(phase_before, animator.phase)) < 0.0001, "after a reset the first sample carries no movement")
	avatar.free()

func _test_all_variants_walk() -> void:
	for appearance_id in CharacterAppearance.IDS:
		var run := _walk(appearance_id, 0.7, Vector3.FORWARD.rotated(Vector3.UP, 0.7), MovementRules.MAX_SPEED, 2.0, 60.0)
		var samples: Array = run["samples"]
		var feet := _feet_report(samples.slice(40), 1.0)
		var swing := 0.0
		var reach := 0.0
		for sample in samples.slice(40):
			swing = maxf(swing, absf((sample["hip_l"] as Vector3).x))
		# Alcance visual dos membros em relação à hitbox oficial (0,45 m).
		var avatar := run["avatar"] as Node3D
		for node in avatar.find_children("*", "MeshInstance3D", true, false):
			var box := _global_of(node) * (node as MeshInstance3D).get_aabb()
			for corner_index in 8:
				var corner := box.get_endpoint(corner_index) - avatar.position
				reach = maxf(reach, maxf(absf(corner.x), absf(corner.z)))
		_expect(swing > CharacterAnimator.HIP_SWING * 0.8, "%s walks with full strides" % appearance_id)
		_expect(feet["lowest_min"] > -0.04 and feet["lowest_max"] < 0.04, "%s keeps its feet on the floor" % appearance_id)
		_report.append("ANIM_VARIANT %s stance_slide=%.3f max_limb_reach=%.2f m (hitbox half-width %.2f)" % [appearance_id, feet["worst_slide"], reach, ArenaRules.PLAYER_HIT_RADIUS])
		avatar.free()

# --- Integração na ArenaView -----------------------------------------------------

func _test_view_integration() -> void:
	var peer := 7
	_view.set_appearance(peer, "night")
	var start := Vector3(12.0, 1.0, 13.0)
	_view.apply_snapshot([_state(1, Vector3(13.5, 1, 9.0), 0.0, 0.0), _state(peer, start, 0.0, 0.5)])
	var avatar: Node3D = _view.avatars[peer]
	var animator: CharacterAnimator = _view.animators[peer]
	_expect(animator != null and animator.is_valid(), "remote avatars get an animator")
	# A câmera local vai para o estado oficial no primeiro quadro; daí em diante
	# nada dos remotos pode movê-la.
	_view._process(0.0)
	var camera_before := _view.camera.global_transform
	var position := start
	for frame in 90:
		position += Vector3.FORWARD * MovementRules.MAX_SPEED / 60.0
		_view.apply_snapshot([_state(1, Vector3(13.5, 1, 9.0), 0.0, 0.0), _state(peer, position, 0.0, 0.5)])
		_view._process(1.0 / 60.0)
		# A raiz do avatar é só a apresentação do estado oficial.
		_expect(avatar.rotation.x == 0.0 and avatar.rotation.z == 0.0, "the animation never tilts the avatar root")
	var head := animator.rig["head"] as Node3D
	_expect(absf(head.rotation.x - ArenaModels.head_rotation_for_pitch(0.5)) < 0.02 and animator.amplitude > 0.5,
		"the head keeps the official pitch while the legs walk (head %.3f, amplitude %.2f)" % [head.rotation.x, animator.amplitude])
	_expect(head.get_parent().name == CharacterRig.TORSO, "the head pitch composes with the torso sway instead of overwriting it")
	_expect(_view.camera.global_transform.is_equal_approx(camera_before), "remote animation never moves the local camera")
	var model := avatar.get_node(ArenaModels.CHARACTER_MODEL) as Node3D
	_expect(is_equal_approx(model.position.x, 0.0) and is_equal_approx(model.position.z, 0.0) and model.position.y <= ArenaModels.CHARACTER_OFFSET.y + 0.05 and model.position.y > ArenaModels.CHARACTER_OFFSET.y - 0.15,
		"only the visual height of the model changes (feet on the floor), never its horizontal place")
	# Hitbox e tiro oficiais não dependem do visual.
	_expect(ArenaRules.ray_player(Vector3(position.x, 1.7, position.z + 3.0), Vector3.FORWARD, 10.0, avatar.position) >= 0.0, "the official hitbox follows the official position only")
	# Parar: o personagem volta ao repouso.
	for frame in 90:
		_view.apply_snapshot([_state(1, Vector3(13.5, 1, 9.0), 0.0, 0.0), _state(peer, position, 0.0, 0.0)])
		_view._process(1.0 / 60.0)
	_expect(animator.amplitude < 0.02 and (animator.rig["pivots"]["Hip_L"] as Node3D).rotation.length() < 0.02, "stopping returns to idle within 1.5 s (amplitude %.3f)" % animator.amplitude)
	# Reposicionamento grande: salta, sem passada.
	var phase := animator.phase
	_view.apply_snapshot([_state(1, Vector3(13.5, 1, 9.0), 0.0, 0.0), _state(peer, Vector3(3.0, 1.0, 11.0), 0.0, 0.0)])
	_view._process(1.0 / 60.0)
	_expect(avatar.position.is_equal_approx(Vector3(3.0, 1.0, 11.0)) and absf(angle_difference(phase, animator.phase)) < 0.0001, "a large official jump snaps the body without a stride")
	# Eliminado / espectador: pose de repouso e nada de caminhada.
	_view.set_player_alive(peer, false)
	_expect(animator.amplitude == 0.0 and (animator.rig["pivots"]["Hip_L"] as Node3D).rotation.is_zero_approx(), "an eliminated body rests")
	_view.set_player_alive(peer, true)
	_view.set_spectator_target(peer)
	for frame in 10:
		_view.apply_snapshot([_state(1, Vector3(13.5, 1, 9.0), 0.0, 0.0), _state(peer, Vector3(3.0, 1.0, 11.0 - frame * 0.08), 0.0, 0.0)])
		_view._process(1.0 / 60.0)
	_expect(not (avatar.get_node(ArenaModels.CHARACTER_MODEL) as Node3D).visible and animator.amplitude == 0.0, "the spectated body stays hidden and idle")
	_view.set_spectator_target(0, false)
	# Trocar aparência: um modelo, um animador, sem pivôs duplicados.
	_view.set_appearance(peer, "plum")
	var fresh: Node3D = _view.avatars[peer]
	_expect(fresh != avatar and _view.animators[peer] != animator and (_view.animators[peer] as CharacterAnimator).is_valid(), "rebuilding the appearance creates a fresh animator")
	_expect(fresh.find_children(ArenaModels.CHARACTER_MODEL, "", false, false).size() == 1 and fresh.find_children(CharacterRig.TORSO, "", true, false).size() == 1, "no duplicated model or pivots after rebuilding")
	# Saída do jogador: o animador vai junto.
	_view.apply_snapshot([_state(1, Vector3(13.5, 1, 9.0), 0.0, 0.0)])
	_expect(not _view.animators.has(peer), "a peer that leaves takes its animator along")

func _state(peer_id: int, position: Vector3, yaw: float, pitch: float) -> Dictionary:
	return {"peer_id": peer_id, "position": position, "yaw": yaw, "pitch": pitch, "velocity": Vector3.ZERO, "spawn_index": 0}

func _global_of(node: Node) -> Transform3D:
	var result := (node as Node3D).transform
	var current := node.get_parent()
	while current is Node3D:
		result = (current as Node3D).transform * result
		current = current.get_parent()
	return result

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("CHARACTER_ANIMATION_CHECK_FAILED %s" % description)
