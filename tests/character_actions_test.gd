extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("CHARACTER_ACTION_ASSERT "+label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var action_script=load("res://client/character_action_state.gd")
	check(action_script!=null,"character action state exists")
	if action_script==null:
		quit(1)
		return
	var action=action_script.new()
	check(action.trigger("interact"),"interaction accepted")
	action.advance(0.1, 1.25)
	check(action.kind == "interact" and is_equal_approx(action.elapsed, 0.1), "interaction timer advances")
	check(action.trigger("reload"),"reload interrupts interaction")
	check(not action.trigger("interact"),"low priority cannot interrupt reload")
	check(action.trigger("fire"),"shot interrupts reload")
	check(action.trigger("hurt"),"impact interrupts shot")
	check(action.trigger("death"),"death interrupts every pose")
	check(not action.trigger("fire"),"dead visual cannot resume firing")
	action.reset()
	check(action.kind=="" and action.trigger("fire"),"reset permits new round")
	for fps in [30, 60, 120]:
		var state = action_script.new()
		state.trigger("reload")
		for frame in int(fps * 0.5):
			state.advance(1.0 / fps, 1.25)
		check(is_equal_approx(state.elapsed, 0.5), "action timing independent of FPS %d" % fps)
		for frame in int(fps):
			state.advance(1.0 / fps, 1.25)
		check(state.kind == "", "action expires at FPS %d" % fps)
	var view:=ArenaView.new()
	root.add_child(view)
	view.set_process(false)
	view.local_peer_id=1
	var states=[{"peer_id":1,"position":Vector3(12,1,15),"velocity":Vector3.ZERO,"yaw":0.0,"pitch":0.0,"epoch":1},
		{"peer_id":2,"position":Vector3(12,1,10),"velocity":Vector3.ZERO,"yaw":0.0,"pitch":0.0,"epoch":1}]
	view.apply_snapshot(states,1)
	view._process(0.016)
	var animator: CharacterAnimator=view.animators[2]
	var official_transform: Transform3D=(view.avatars[2] as Node3D).transform
	var camera_transform: Transform3D=view.camera.global_transform
	view.spatial_audio.configure(0.0,0.0)
	view.apply_sound_events([SoundEventRules.make(1,1,"door",Vector3(12,1,10),2)],1)
	check(animator.actions.kind=="interact","authorized door event animates muted remote")
	animator.update(Vector3(12,1,9.9),0.0,0.1)
	check(animator.player.current_animation == "CharacterArmature|PickUp", "interaction plays PickUp while moving")
	check((view.avatars[2] as Node3D).transform==official_transform and view.camera.global_transform==camera_transform,"action leaves official root and aim untouched")
	view.apply_sound_events([SoundEventRules.make(1,1,"door",Vector3(12,1,10),2)],1)
	check(animator.actions.elapsed>0.0,"duplicate event does not restart visual pose")
	view.show_shot({"shooter_peer_id":2,"origin":Vector3(12,1.7,10),"end":Vector3(12,1.7,8),"hit_player":false})
	check(animator.actions.kind=="fire","official shot animates remote")
	view.show_shot({"shooter_peer_id":1,"origin":Vector3(12,1.7,15),"end":Vector3(12,1.7,10),"hit_player":true})
	check(animator.actions.kind=="hurt","public impact endpoint gives cosmetic reaction without private target data")
	view.set_player_alive(2,false)
	check(animator.actions.kind=="death","death cancels interaction/fire")
	view.apply_sound_events([SoundEventRules.make(2,1,"reload",Vector3(12,1,10),2)],1)
	check(animator.actions.kind=="death","late event cannot animate dead actor")
	view.set_player_alive(2,true)
	check(animator.actions.kind=="","respawn resets action state")
	view.apply_sound_events([SoundEventRules.make(1,2,"reload",Vector3(12,1,10),2)],2)
	check(animator.actions.kind=="reload","new round id may start new remote action")
	view.apply_sound_events([SoundEventRules.make(99,1,"door",Vector3(12,1,10),2)],1)
	check(animator.actions.kind=="reload","old round event cannot overwrite current pose")
	animator.reset(Vector3(3,1,2))
	check(animator.actions.kind=="","epoch/teleport resets transient pose")
	var body := BodyRules.make(1, 2, 2, Vector3(12, 1, 10), 0.0, "ninja")
	check(view.add_body(body), "official body added")
	var body_root := view.bodies[1] as Node3D
	var body_skeleton := body_root.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
	var torso := body_skeleton.find_bone("Torso")
	var pose := body_skeleton.get_bone_global_pose(torso)
	var root_before := body_root.transform
	var fall := body_root.get_node_or_null("Fall") as Node3D
	check(fall != null and is_equal_approx(fall.rotation.x, PI * 0.5), "corpse uses the 90-degree fall tilt")
	view._process(0.5)
	check(body_skeleton.get_bone_global_pose(torso).is_equal_approx(pose), "corpse holds the pose")
	check(body_root.transform == root_before, "corpse animation preserves official body placement")
	view.clear_bodies()
	body.body_id = 2
	check(view.add_body(body), "body may be rebuilt after cleanup")
	if DisplayServer.get_name()!="headless" and OS.get_cmdline_user_args().has("--capture"):
		view.set_player_alive(2,true)
		view.apply_sound_events([SoundEventRules.make(2,2,"reload",Vector3(12,1,10),2)],2)
		animator.update(Vector3(12,1,10),0.0,0.4)
		await process_frame
		await RenderingServer.frame_post_draw
		var path:="/workspace/.ossuspeitos-state/phase2/spec11/character-actions.png"
		check(root.get_texture().get_image().save_png(path)==OK,"graphical action screenshot saved")
	await create_timer(0.8).timeout
	for voice in view.fx._ui_players: voice.stop()
	for voice in view.fx._world_players: voice.stop()
	view.free()
	print("CHARACTER_ACTIONS_TEST_%s checks=%d failures=%d" % ["OK" if failures==0 else "FAILED",checks,failures])
	quit(0 if failures==0 else 1)
