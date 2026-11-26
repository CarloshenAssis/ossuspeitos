extends SceneTree

const PREFIX := "CharacterArmature|"
const CLIPS := ["Idle", "Walk", "Run", "Shoot_OneHanded", "Defeat", "RecieveHit", "PickUp", "Punch"]
const ACTION_CLIPS := {"interact": "PickUp", "reload": "PickUp", "fire": "Shoot_OneHanded", "hurt": "RecieveHit", "death": "Defeat"}
const DT := 1.0 / 60.0

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for appearance_id in CharacterAppearance.IDS:
		_test_variant(appearance_id)
	_test_actions_and_head_pitch()
	_test_view_integration()
	print("CHARACTER_ANIMATION_TEST_%s checks=%d failures=%d" % ["OK" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)

func _test_variant(appearance_id: String) -> void:
	var scene := load(CharacterAppearance.SCENE_PATH % appearance_id) as PackedScene
	_expect(scene != null, "%s GLB loads" % appearance_id)
	var avatar := _add_avatar(appearance_id)
	var animator := _animator(avatar)
	_expect(animator.is_valid(), "%s has a valid Skeleton3D and AnimationPlayer" % appearance_id)
	if animator.is_valid():
		for clip in CLIPS:
			_expect(animator.player.has_animation(PREFIX + clip), "%s has %s" % [appearance_id, clip])
		animator.reset(Vector3.ZERO)
		animator.update(Vector3.ZERO, 0.0, DT)
		_expect(animator.player.current_animation == PREFIX + "Idle", "%s plays Idle at rest" % appearance_id)
		_expect(animator.player.get_animation(PREFIX + "Idle").loop_mode == Animation.LOOP_LINEAR, "%s Idle loops" % appearance_id)
		var position := _walk(animator, Vector3.ZERO, 1.5)
		_expect(animator.player.current_animation == PREFIX + "Walk", "%s walks when moving slowly" % appearance_id)
		_expect(animator.player.get_animation(PREFIX + "Walk").loop_mode == Animation.LOOP_LINEAR, "%s Walk loops" % appearance_id)
		_expect(animator.player.get_animation(PREFIX + "Run").loop_mode == Animation.LOOP_LINEAR, "%s Run loops" % appearance_id)
		_walk(animator, position, MovementRules.MAX_SPEED)
		_expect(animator.player.current_animation == PREFIX + "Run", "%s runs at max movement speed" % appearance_id)
		animator.rest()
		_expect(animator.player.current_animation == PREFIX + "Idle", "%s returns to Idle on rest" % appearance_id)
	avatar.free()

func _test_actions_and_head_pitch() -> void:
	var avatar := _add_avatar("knight")
	var animator := _animator(avatar)
	var neutral_avatar := _add_avatar("knight")
	var neutral := _animator(neutral_avatar)
	var head_pivot := avatar.find_child(ArenaModels.HEAD_PIVOT, true, false) as Node3D
	_expect(animator.is_valid() and neutral.is_valid() and head_pivot != null, "head pitch test has two rigs and a HeadPivot")
	if animator.is_valid() and neutral.is_valid() and head_pivot != null:
		var head := animator.skeleton.find_bone("Head")
		_expect(head >= 0, "the skeleton includes the Head bone")
		if head >= 0:
			animator.reset(Vector3.ZERO)
			neutral.reset(Vector3.ZERO)
			head_pivot.rotation.x = ArenaModels.head_rotation_for_pitch(0.5)
			_walk(animator, Vector3.ZERO, 2.0)
			_walk(neutral, Vector3.ZERO, 2.0)
			var pitched := animator.skeleton.get_bone_pose_rotation(head)
			var baseline := neutral.skeleton.get_bone_pose_rotation(head)
			_expect(absf(pitched.angle_to(baseline) - absf(head_pivot.rotation.x)) < 0.01,
				"look pitch tilts the animated Head by the requested angle")
			head_pivot.rotation.x = 0.0
			var next_position := Vector3.FORWARD * 2.0 * (30.0 + 1.0) * DT
			animator.update(next_position, 0.0, DT)
			neutral.update(next_position, 0.0, DT)
			_expect(animator.skeleton.get_bone_pose_rotation(head).angle_to(neutral.skeleton.get_bone_pose_rotation(head)) < 0.01,
				"clearing look pitch restores the clip's Head pose")
		for action in ACTION_CLIPS:
			_expect(animator.actions.trigger(action), "%s action accepted" % action)
			animator.update(Vector3.ZERO, 0.0, DT)
			var clip: String = ACTION_CLIPS[action]
			_expect(animator.player.current_animation == PREFIX + clip, "%s plays %s" % [action, clip])
		var defeat := animator.player.get_animation(PREFIX + "Defeat")
		_expect(defeat.loop_mode == Animation.LOOP_NONE, "Defeat plays once")
		_expect(is_equal_approx(defeat.length, 2.5), "Defeat keeps its 2.5-second duration")
		var torso := animator.skeleton.find_bone("Torso")
		animator.update(Vector3.ZERO, 0.0, 1.0)
		_expect(animator.player.current_animation == PREFIX + "Defeat" and animator.player.is_playing(),
			"death continues playing through the first second")
		animator.update(Vector3.ZERO, 0.0, defeat.length)
		var held_pose := animator.skeleton.get_bone_global_pose(torso)
		neutral.player.play(PREFIX + "Defeat")
		neutral.player.seek(defeat.length, true)
		_expect(held_pose.is_equal_approx(neutral.skeleton.get_bone_global_pose(torso)), "death reaches the final Defeat frame")
		animator.update(Vector3.FORWARD * DT, 0.0, 1.0)
		_expect(animator.skeleton.get_bone_global_pose(torso).is_equal_approx(held_pose), "death holds the final pose while positions change")
	avatar.free()
	neutral_avatar.free()

func _test_view_integration() -> void:
	var view := ArenaView.new()
	view.local_peer_id = 1
	root.add_child(view)
	view.set_process(false)
	var peer := 7
	var start := Vector3(12.0, 1.0, 13.0)
	var local := _state(1, Vector3(13.5, 1.0, 9.0), 0.0)
	view.set_appearance(peer, "knight")
	view.apply_snapshot([local, _state(peer, start, 0.5)])
	view._process(DT)
	var avatar: Node3D = view.avatars[peer]
	var animator: CharacterAnimator = view.animators[peer]
	_expect(animator != null and animator.is_valid(), "remote avatar gets a valid animator")
	var camera_before := view.camera.global_transform
	var position := start
	for frame in 60:
		position += Vector3.FORWARD * MovementRules.MAX_SPEED * DT
		view.apply_snapshot([local, _state(peer, position, 0.5)])
		view._process(DT)
	if animator != null and animator.is_valid():
		_expect(animator.player.current_animation == PREFIX + "Run", "remote snapshots drive Run at max speed")
	var pivot := avatar.find_child(ArenaModels.HEAD_PIVOT, true, false) as Node3D
	_expect(pivot != null and is_equal_approx(pivot.rotation.x, ArenaModels.head_rotation_for_pitch(0.5)),
		"remote snapshots apply the official pitch")
	_expect(avatar.rotation.x == 0.0 and avatar.rotation.z == 0.0, "animation leaves the authoritative root upright")
	_expect(view.camera.global_transform.is_equal_approx(camera_before), "remote animation leaves the local camera unchanged")

	view.set_appearance(peer, "ninja")
	var fresh: Node3D = view.avatars[peer]
	var fresh_animator: CharacterAnimator = view.animators[peer]
	_expect(fresh != avatar and fresh_animator != animator and fresh_animator.is_valid(), "replacing the appearance rebuilds a valid animator")
	_expect(fresh.find_children(ArenaModels.CHARACTER_MODEL, "Node3D", false, false).size() == 1, "replacement has one character model")
	view.apply_snapshot([local])
	_expect(not view.animators.has(peer), "departed peers release their animator")
	view.free()

func _add_avatar(appearance_id: String) -> Node3D:
	var avatar := ArenaModels.build_character(appearance_id)
	root.add_child(avatar)
	return avatar

func _animator(avatar: Node3D) -> CharacterAnimator:
	return CharacterAnimator.new(avatar.get_node(ArenaModels.CHARACTER_MODEL))

func _walk(animator: CharacterAnimator, position: Vector3, speed: float) -> Vector3:
	for frame in 30:
		position += Vector3.FORWARD * speed * DT
		animator.update(position, 0.0, DT)
	return position

func _state(peer_id: int, position: Vector3, pitch: float) -> Dictionary:
	return {"peer_id": peer_id, "position": position, "yaw": 0.0, "pitch": pitch, "velocity": Vector3.ZERO, "spawn_index": 0}

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CHARACTER_ANIMATION_CHECK_FAILED %s" % description)
