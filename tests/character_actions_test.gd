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
	check(action_script!=null,"procedural action state exists")
	if action_script==null:
		quit(1)
		return
	var action=action_script.new()
	check(action.trigger("interact"),"interaction accepted")
	check(action.advance(0.1).shoulder_x< -0.05,"interaction reaches forward")
	check(action.trigger("reload"),"reload interrupts interaction")
	check(not action.trigger("interact"),"low priority cannot interrupt reload")
	check(action.trigger("fire"),"shot interrupts reload")
	check(action.trigger("hurt"),"impact interrupts shot")
	check(action.trigger("death"),"death interrupts every pose")
	check(not action.trigger("fire"),"dead visual cannot resume firing")
	action.reset()
	check(action.kind=="" and action.trigger("fire"),"reset permits new round")
	var reference: Dictionary={}
	for fps in [30,60,120]:
		var state=action_script.new()
		state.trigger("reload")
		var sample: Dictionary={}
		for frame in int(fps*0.5): sample=state.advance(1.0/fps)
		if reference.is_empty(): reference=sample
		check(absf(float(sample.shoulder_x)-float(reference.shoulder_x))<0.00001,"action pose independent of FPS%d" % fps)
		for frame in fps*2: state.advance(1.0/fps)
		check(state.kind=="","pose expires at FPS%d" % fps)
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
	check((animator.rig.pivots.Shoulder_R as Node3D).rotation.x< -0.1,"real shoulder shows action while moving")
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
	var body:=BodyRules.make(1,2,2,Vector3(12,1,10),0.0,"night")
	check(view.add_body(body),"official body added")
	check(view._body_transitions.size()==1,"death settling transition runs on body")
	var root_before: Transform3D=(view.bodies[1] as Node3D).transform
	var left: Node3D=view._body_transitions[1].left
	var rest_rotation: Vector3=left.rotation
	view._update_body_transitions(0.1)
	check(not left.rotation.is_equal_approx(rest_rotation),"death transition visibly settles body arms")
	for frame in 60: view._update_body_transitions(1.0/120.0)
	check(view._body_transitions.is_empty(),"death settling completes")
	check((view.bodies[1] as Node3D).transform==root_before,"death transition preserves official body root")
	view.clear_bodies()
	body.body_id=2
	check(view.add_body(body),"body may be rebuilt after cleanup")
	view._update_body_transitions(0.1)
	view.set_presentation_motion(false)
	check(view._body_transitions.is_empty(),"reduce motion cancels corpse transition immediately")
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
