class_name CharacterAnimator
extends RefCounted

const IDLE := &"CharacterArmature|Idle"
const WALK := &"CharacterArmature|Walk"
const DEFEAT := &"CharacterArmature|Defeat"
const ACTION_CLIPS := {
	"fire": &"CharacterArmature|Shoot_OneHanded",
	"hurt": &"CharacterArmature|RecieveHit",
	"death": DEFEAT,
	"interact": &"CharacterArmature|PickUp",
	"reload": &"CharacterArmature|PickUp",
}
const BLEND_TIME := 0.15
const IDLE_SPEED := 0.3
const WALK_SPEED := 2.0
const TELEPORT_DISTANCE := 1.5

var actions := CharacterActionState.new()
var player: AnimationPlayer
var skeleton: Skeleton3D
var head_pivot: Node3D
var speed := 0.0
var amplitude := 0.0

var _head_bone := -1
var _clip_head_rotation := Quaternion.IDENTITY
var _last_position := Vector3.INF
var _action_revision := -1
var _idle_offset := 0.0

func _init(model: Node3D, breath_offset: float = 0.0) -> void:
	player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	head_pivot = model.get_node_or_null(ArenaModels.HEAD_PIVOT) as Node3D
	if skeleton != null:
		_head_bone = skeleton.find_bone("Head")
	if not is_valid():
		return
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip in [IDLE, WALK]:
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_idle_offset = fposmod(breath_offset, player.get_animation(IDLE).length)
	_clip_head_rotation = skeleton.get_bone_pose_rotation(_head_bone)
	rest()

func is_valid() -> bool:
	return player != null and _head_bone >= 0 and head_pivot != null and player.has_animation(IDLE) and player.has_animation(WALK) and player.has_animation(DEFEAT)

func reset(position: Vector3 = Vector3.INF) -> void:
	rest()
	_last_position = position

func rest() -> void:
	actions.reset()
	speed = 0.0
	amplitude = 0.0
	_last_position = Vector3.INF
	if not is_valid():
		return
	skeleton.set_bone_pose_rotation(_head_bone, _clip_head_rotation)
	player.stop()
	player.speed_scale = 1.0
	player.play(IDLE)
	player.seek(_idle_offset, true)
	_apply_head_pitch()

func update(position: Vector3, _yaw: float, delta: float) -> void:
	if not is_valid() or not is_finite(delta) or delta <= 0.0:
		return
	var distance := 0.0
	if _last_position != Vector3.INF:
		distance = Vector2(position.x - _last_position.x, position.z - _last_position.z).length()
	_last_position = position
	var measured := minf(distance / delta, MovementRules.MAX_SPEED * 1.5) if distance <= TELEPORT_DISTANCE else 0.0
	speed = lerpf(speed, measured, 1.0 - exp(-10.0 * delta))
	amplitude = clampf(speed / WALK_SPEED, 0.0, 1.0) if speed > IDLE_SPEED else 0.0
	skeleton.set_bone_pose_rotation(_head_bone, _clip_head_rotation)

	if actions.kind.is_empty():
		var clip := WALK if speed > IDLE_SPEED else IDLE
		player.speed_scale = clampf(speed / WALK_SPEED, 0.2, 2.5) if clip == WALK else 1.0
		if player.assigned_animation != clip or not player.is_playing():
			var previous := player.assigned_animation
			var blend := BLEND_TIME if previous == IDLE or previous == WALK else 0.0
			player.play(clip, blend)
		player.advance(delta)
	else:
		var clip: StringName = ACTION_CLIPS[actions.kind]
		player.speed_scale = 1.0
		if _action_revision != actions.revision:
			_action_revision = actions.revision
			player.stop()
			player.play(clip)
			player.advance(0.0)
		var duration := player.get_animation(clip).length
		if clip == DEFEAT and actions.elapsed + delta >= duration:
			player.seek(duration, true)
			player.pause()
		else:
			player.advance(delta)
		actions.advance(delta, duration)

	_apply_head_pitch()

func _apply_head_pitch() -> void:
	_clip_head_rotation = skeleton.get_bone_pose_rotation(_head_bone)
	skeleton.set_bone_pose_rotation(_head_bone,
		_clip_head_rotation * Quaternion(Vector3.RIGHT, head_pivot.rotation.x))
