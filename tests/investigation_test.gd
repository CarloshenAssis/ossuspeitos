extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("INVESTIGATION_ASSERT "+label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var rules=load("res://shared/investigation_rules.gd")
	check(rules!=null,"private investigation contract exists")
	if rules==null:
		quit(1)
		return
	var room:=MatchRoom.new(1,"ABC234",0,false,0.1,1.0,8)
	for peer in range(1,5): room.add_member(peer,"Player%d"%peer,0)
	room.round_authority.tick(1000)
	room.interactions.reset(room.round_authority.round_id)
	room.round_authority.alive[4]=false
	var body:=room.bodies.add(room.round_authority.round_id,4,Vector3(3,1,3.5),0.0,CharacterAppearance.IDS[0])
	room.world.teleport(1,Vector3(2,1,3.5))
	room.world.teleport(2,Vector3(2,1,4))
	var action={"kind":"interact","id":1,"object_id":"body:%d"%int(body.body_id),"verb":"inspect"}
	check(NetSync.parse_action(NetSync.encode_action(action))==action,"inspect uses existing bounded command format")
	var result: Dictionary=room.interactions.request(1,action,2000)
	check(result.accepted,"living participant inspects official body")
	var info: Dictionary=room.investigations.last_for_peer(1)
	check(info.label=="Player4" and info.condition=="eliminado" and info.body_id==body.body_id,"only useful public facts returned")
	check(room.investigations.last_for_peer(2).is_empty(),"other peer receives no private response")
	check(room.interactions.request(2,action,2000).accepted,"two actors may independently inspect same body")
	check(not room.interactions.request(99,action,2000).accepted,"unknown actor has no permission")
	room.world.teleport(1,Vector3(40,1,24))
	action.id=2
	check(room.interactions.request(1,action,2300).reason=="out_of_range","distant actor denied")
	check(room.investigations.last_for_peer(1)==info,"rejection cannot replace last authorized fact")
	room.round_authority.alive[1]=false
	action.id=3
	check(room.interactions.request(1,action,2600).reason=="player_dead","dead actor denied")
	room.round_authority.alive[1]=true
	room.world.teleport(1,Vector3(2,1,3.5))
	action.id=4
	action.object_id="body:999"
	check(room.interactions.request(1,action,2900).reason=="body_unavailable","missing or removed body denied")
	var forged:=info.duplicate(); forged.role="assassin"
	check(rules.sanitize(forged).is_empty(),"private response still rejects secret field")
	check(rules.sanitize(info)==info,"response allowlist roundtrip")
	for bad in [null,[],{}, {"body_id":1}]: check(rules.sanitize(bad).is_empty(),"malformed response refused")
	# Both mechanisms consume the SAME ID stream, even after 64 inspections.
	for index in range(5,71):
		action.id=index
		action.object_id="body:%d"%int(body.body_id)
		check(room.interactions.request(1,action,3000+index*250).accepted,"inspection sequence stays continuous")
	room.world.teleport(1,Vector3(5.05,1,2.5))
	var door_action={"kind":"interact","id":71,"object_id":str(MansionMap.DOORS[0].id),"verb":"toggle"}
	check(room.interactions.request(1,door_action,22000).accepted,"door after many inspections does not sequence-jump")
	room.round_authority.alive[3]=false
	var blocked_body:=room.bodies.add(room.round_authority.round_id,3,Vector3(7.4,1,2.5),0.0,CharacterAppearance.IDS[0])
	var blocked_action={"kind":"interact","id":72,"object_id":"body:%d"%int(blocked_body.body_id),"verb":"inspect"}
	check(room.interactions.request(1,blocked_action,22300).reason=="interaction_blocked","closed door blocks investigation ray")
	door_action.id=73
	check(room.interactions.request(1,door_action,22600).accepted,"door opens through same shared action budget")
	blocked_action.id=74
	check(room.interactions.request(1,blocked_action,22900).accepted,"open door permits same investigation ray")
	var view:=ArenaView.new()
	root.add_child(view)
	view.local_peer_id=1
	view.player_rig.position=Vector3(2,1,3.5)
	check(view.add_body(body),"official body presentation reused")
	check(view.nearest_investigation()=="body:%d"%int(body.body_id),"human input can resolve nearby body")
	view.apply_inspection(info)
	check(view.inspection_label.text.contains("Player4") and not view.inspection_label.text.contains("assassin"),"private feedback is clear and role-free")
	view.apply_inspection({})
	check(view.inspection_label.text.is_empty(),"cleared response removes old feedback")
	view.free()
	var other:=MatchRoom.new(2,"DEF234",0,false,0.1,1.0,8)
	check(other.investigations.last_for_peer(1).is_empty(),"private inspection isolated by room")
	room.investigations.reset()
	check(room.investigations.last_for_peer(1).is_empty(),"reset clears private evidence")
	room.clear();other.clear()
	print("INVESTIGATION_TEST_%s checks=%d failures=%d"%["OK" if failures==0 else "FAILED",checks,failures])
	quit(0 if failures==0 else 1)
