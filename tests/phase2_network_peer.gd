extends "res://shared/network_app.gd"

## Test-only subclass. Production RPC implementations are inherited unchanged.
const DOOR := "porta_escritorio_leste"
const PROP := "prop_escritorio"
const DOOR_NEAR := Vector3(5.15,1,2.5)
const DOOR_FAR := Vector3(7.3,1,2.5)
const PROP_NEAR := Vector3(2.1,1,3.5)
var fixture_peers: Array=[]
var fixture_results: Array=[]
var fixture_stage := 0
var fixture_acks: Dictionary={}
var fixture_instruction: Dictionary={}
var fixture_enqueued := false
var fixture_move_left := 0
var fixture_move := Vector2.ZERO
var fixture_move_ack := 0
var fixture_rounds := 1
var fixture_count := 4
var fixture_deadline := 0
var fixture_finished := false
var fixture_sounds: Dictionary={}
var fixture_sounds_round := 0
var fixture_last_action: Dictionary={}

func _ready() -> void:
	super._ready()
	fixture_count=NetworkConfig.integer_argument(arguments,"phase2-clients",4)
	fixture_rounds=NetworkConfig.integer_argument(arguments,"phase2-rounds",1)
	fixture_deadline=Time.get_ticks_msec()+180000
	if mode=="server": call_deferred("fixture_server")

func _process(delta: float) -> void:
	super._process(delta)
	if fixture_finished: return
	if Time.get_ticks_msec()>fixture_deadline:
		fixture_fail("global deadline")
		return
	if mode!="client" or fixture_instruction.is_empty(): return
	var rid := int(fixture_instruction.round_id)
	if int(local_environment.get("round_id",0))!=rid: return
	if fixture_sounds_round!=rid:
		fixture_sounds_round=rid
		fixture_sounds.clear()
	for event in local_sound_events:
		if SoundEventRules.sanitize(event).is_empty():
			fixture_fail("invalid sound DTO"); return
		fixture_sounds[int(event.id)]=event
	if not fixture_enqueued:
		var operation: Dictionary=fixture_instruction.operation
		var op := str(operation.get("op","observe"))
		if op not in ["observe","raw_interact"] and (not _commands_enabled() or prediction.epoch!=int(fixture_instruction.epoch)): return
		if op=="raw_interact" and (not joined or prediction.epoch!=int(fixture_instruction.epoch)): return
		if op=="interact":
			if not queue_environment_interaction(str(operation.verb),str(operation.target)): return
			fixture_last_action={"kind":"interact","id":int(action_ids.interact),"object_id":str(operation.target),"verb":str(operation.verb)}
		elif op=="raw_interact":
			send_test_packet([{"kind":"interact","id":999,"object_id":str(operation.target),"verb":str(operation.verb)}])
		elif op=="replay":
			if not prediction.queue_action(fixture_last_action.duplicate()): return
		elif op=="pickup":
			if not _queue_local_action(NetSync.ACTION_PICKUP,str(operation.target)): return
		elif op=="fire":
			if not _queue_local_action(NetSync.ACTION_FIRE): return
		elif op=="reload":
			if not _queue_local_action(NetSync.ACTION_RELOAD): return
		elif op=="move":
			fixture_move=operation.direction
			fixture_move_left=int(operation.ticks)
			fixture_move_ack=0
		fixture_enqueued=true
	if fixture_move_left>0 or (fixture_move_ack>0 and prediction.last_ack<fixture_move_ack): return
	if not fixture_client_condition(fixture_instruction.expected): return
	fixture_enqueued=false
	var stage_id := int(fixture_instruction.stage)
	fixture_instruction={}
	test_observation.rpc_id(1,stage_id,{"round_id":rid,"revision":int(local_environment.revision),"sound_ids":fixture_sounds.keys(),"bodies":local_bodies.size()})

func _sample_move() -> Vector2:
	if fixture_move_left>0:
		fixture_move_left-=1
		return fixture_move
	return Vector2.ZERO

func _client_command_tick() -> void:
	var final_move := fixture_move_left==1
	super._client_command_tick()
	if final_move and fixture_move_left==0:
		fixture_move_ack=prediction.next_seq-1

func _report_action_result(peer_id: int,kind: String,id: int,result: Dictionary) -> void:
	super._report_action_result(peer_id,kind,id,result)
	fixture_results.append({"peer":peer_id,"kind":kind,"id":id,"result":result.duplicate(true)})

@rpc("authority","call_remote","reliable")
func test_instruction(stage_id: int,instruction: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id()!=1: return
	if bool(instruction.get("finish",false)):
		fixture_finished=true
		print("PHASE2_CLIENT_OK id=%s rounds=%d" % [client_label,fixture_rounds])
		return
	if stage_id<=int(fixture_instruction.get("stage",0)): return
	fixture_instruction=instruction.duplicate(true)
	fixture_instruction.stage=stage_id
	fixture_enqueued=false

@rpc("any_peer","call_remote","reliable")
func test_observation(stage_id: int,observation: Dictionary) -> void:
	if not multiplayer.is_server() or stage_id!=fixture_stage: return
	var sender := multiplayer.get_remote_sender_id()
	if sender not in fixture_peers or fixture_acks.has(sender): return
	if int(observation.get("round_id",0))!=round_authority.round_id: return
	fixture_acks[sender]=observation.duplicate(true)

func fixture_client_condition(expected: Dictionary) -> bool:
	if prediction.environment_blockers!=EnvironmentRules.blockers(local_environment): return false
	if bool(expected.get("inspection_empty",false)) and not local_inspection.is_empty(): return false
	if expected.has("inspection"):
		if InvestigationRules.sanitize(local_inspection).is_empty(): return false
		for key in expected.inspection:
			if local_inspection.get(key)!=expected.inspection[key]: return false
	if int(local_environment.get("revision",0))<int(expected.get("revision",0)): return false
	for raw in expected.get("objects",[]):
		var found := false
		for item in local_environment.get("objects",[]):
			if item.id!=raw.id: continue
			found=true
			for key in raw:
				if key!="id" and item.get(key)!=raw[key]: return false
		if not found: return false
	if expected.has("body_count") and local_bodies.size()!=int(expected.body_count): return false
	if expected.has("sound_kind"):
		var found := false
		for event in fixture_sounds.values():
			if event.kind==expected.sound_kind: found=true
		if not found: return false
	return true

func fixture_fail(reason: String) -> void:
	if fixture_finished: return
	fixture_finished=true
	printerr("PHASE2_NETWORK_FAILED stage=%d reason=%s" % [fixture_stage,reason])
	get_tree().quit(1)

func fixture_require(ok: bool,label: String) -> bool:
	if not ok:
		fixture_fail(label)
		return false
	print("PHASE2_ASSERT_OK name=%s" % label)
	return true

func fixture_wait(condition: Callable,label: String,seconds: float=12.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not fixture_finished:
		if condition.call(): return true
		if Time.get_ticks_msec()>deadline:
			fixture_fail("timeout "+label+" acks="+str(fixture_acks.keys())+" results="+str(fixture_results))
			return false
		await get_tree().process_frame
	return false

func fixture_teleport(peer: int,point: Vector3,yaw: float=0.0) -> void:
	authoritative_world.teleport(peer,point,yaw,0.0)

func fixture_stage_run(operations: Dictionary,expected: Dictionary={},result_count: int=0) -> bool:
	fixture_stage+=1
	fixture_acks.clear()
	fixture_results.clear()
	for peer in fixture_peers:
		var individual := expected.duplicate(true)
		individual.erase("private_by_peer")
		if expected.has("private_by_peer"):
			if expected.private_by_peer.has(peer):
				individual.inspection=expected.private_by_peer[peer]
			else:
				individual.inspection_empty=true
		test_instruction.rpc_id(peer,fixture_stage,{"round_id":round_authority.round_id,"epoch":authoritative_world.states[peer].epoch,"operation":operations.get(peer,{"op":"observe"}),"expected":individual})
	if not await fixture_wait(func(): return fixture_acks.size()==fixture_count and fixture_results.size()>=result_count,"barrier"): return false
	return true

func fixture_one(peer: int,verb: String,target: String,expected: Dictionary={}) -> bool:
	var op := {peer:{"op":"interact","verb":verb,"target":target}}
	return await fixture_stage_run(op,expected,1)

func fixture_accepted(label: String) -> bool:
	return fixture_require(fixture_results.size()==1 and bool(fixture_results[0].result.get("accepted",false)),label)

func fixture_door(open_value: bool) -> Dictionary:
	return {"objects":[{"id":DOOR,"open":open_value}],"revision":interaction_authority.revision+1,"sound_kind":"door"}

func fixture_server() -> void:
	if not await fixture_wait(func(): return lobby.size()==fixture_count and round_authority.state==RoundState.ACTIVE,"initial active",30.0): return
	fixture_peers=lobby.peer_ids()
	fixture_peers.sort()
	for campaign in fixture_rounds:
		if not await fixture_round(campaign): return
	fixture_finished=true
	for peer in fixture_peers: test_instruction.rpc_id(peer,fixture_stage+1,{"finish":true})
	print("PHASE2_SERVER_OK clients=%d rounds=%d" % [fixture_count,fixture_rounds])
	_begin_server_shutdown(fixture_peers)

func fixture_round(campaign: int) -> bool:
	if not await fixture_wait(func(): return round_authority.state==RoundState.ACTIVE and round_authority.round_id==campaign+1,"campaign active",20.0): return false
	var rid := round_authority.round_id
	var actor := 0
	var victim := 0
	var opponent := 0
	# Fixture choices remain entirely server-side; no roles enter test RPCs.
	for peer in fixture_peers:
		var role := round_authority.get_role_for_peer(peer)
		if role==Role.ASSASSIN: opponent=peer
		elif role==Role.DETECTIVE: actor=peer
		elif victim==0: victim=peer
	if not fixture_require(actor>0 and victim>0 and opponent>0,"fixture actors"): return false
	for peer in fixture_peers:
		fixture_teleport(peer,MovementRules.SPAWN_POINTS[fixture_peers.find(peer)])
	fixture_teleport(actor,DOOR_NEAR,-PI/2)
	fixture_teleport(victim,DOOR_FAR)
	if not await fixture_stage_run({}, {"body_count":0,"inspection_empty":true,"objects":[{"id":DOOR,"open":true}]}): return false
	if not await fixture_one(actor,"toggle",DOOR,fixture_door(false)): return false
	if not fixture_accepted("door close authorized"): return false
	# Same weapon/official aim shot in closed/open states, not a mocked ray.
	var gun := "phase2_gun_%d" % rid
	combat_authority.inventory.add_ground_weapon(gun,"common_pistol",DOOR_NEAR,6,18,rid)
	if not await fixture_stage_run({actor:{"op":"pickup","target":gun}}, {},1): return false
	if not fixture_accepted("weapon collected over transport"): return false
	if not await fixture_stage_run({actor:{"op":"fire"}}, {},1): return false
	if not fixture_accepted("closed door shot accepted"): return false
	if not fixture_require(int(combat_authority.health[victim])==100,"closed door blocks damage"): return false
	if not await fixture_stage_run({actor:{"op":"move","direction":Vector2(0,-1),"ticks":30}}): return false
	if not fixture_require(float((authoritative_world.states[actor].position as Vector3).x)<5.81,"closed door blocks movement"): return false
	fixture_teleport(actor,DOOR_NEAR,-PI/2)
	if not await fixture_one(actor,"toggle",DOOR,fixture_door(true)): return false
	if not fixture_accepted("door opens authorized"): return false
	await get_tree().create_timer(0.45).timeout
	if not await fixture_stage_run({actor:{"op":"fire"}}, {},1): return false
	if not fixture_accepted("open door shot accepted"): return false
	if not fixture_require(int(combat_authority.health[victim])==66,"open door passes damage"): return false
	# Move target out of the passage before testing actual crossing.
	fixture_teleport(victim,Vector3(26,1,2.5))
	if not await fixture_stage_run({actor:{"op":"move","direction":Vector2(0,-1),"ticks":30}}, {"sound_kind":"step_walk"}): return false
	if not fixture_require(float((authoritative_world.states[actor].position as Vector3).x)>6.55,"open door passes movement"): return false
	fixture_teleport(actor,PROP_NEAR,-PI/2)
	fixture_teleport(victim,Vector3(3,1,2.6),PI)
	var next_revision := interaction_authority.revision+1
	if not await fixture_stage_run({actor:{"op":"interact","verb":"take","target":PROP},victim:{"op":"interact","verb":"take","target":PROP}}, {"revision":next_revision},2): return false
	var accepted := 0
	for result in fixture_results:
		if bool(result.result.get("accepted",false)): accepted+=1
	var holder := int(interaction_authority.object_state(PROP).holder)
	if not fixture_require(accepted==1 and holder in [actor,victim],"single prop owner under contest"): return false
	if not await fixture_wait(func(): return float((interaction_authority.object_state(PROP).position as Vector3).y)>1.0,"carried prop lifted"): return false
	await get_tree().create_timer(0.25).timeout
	if not await fixture_one(holder,"drop",PROP,{"objects":[{"id":PROP,"holder":0}]}): return false
	if not fixture_accepted("drop authorized"): return false
	if not await fixture_wait(func(): return float((interaction_authority.object_state(PROP).position as Vector3).y)<0.31,"prop settles"): return false
	if not await fixture_stage_run({}, {"sound_kind":"impact"}): return false
	var prop: Vector3=interaction_authority.object_state(PROP).position
	fixture_teleport(actor,Vector3(prop.x-1.0,1,prop.z),-PI/2)
	fixture_teleport(victim,Vector3(26,1,2.5))
	await get_tree().create_timer(0.25).timeout
	if not await fixture_one(actor,"push",PROP): return false
	if not fixture_accepted("push authorized"): return false
	if not await fixture_wait(func(): return (interaction_authority.object_state(PROP).position as Vector3).distance_to(prop)>0.05,"prop moves"): return false
	fixture_teleport(actor,Vector3(26,1,2.5))
	await get_tree().create_timer(0.25).timeout
	var sound_before := sound_authority.snapshot().duplicate(true)
	if not await fixture_one(actor,"toggle",DOOR): return false
	if not fixture_require(not bool(fixture_results[0].result.accepted) and fixture_results[0].result.reason=="out_of_range","far interaction rejected"): return false
	if not fixture_require(sound_authority.snapshot()==sound_before,"rejected interaction emits no sound"): return false
	var doors := 0
	for sound in sound_authority.snapshot():
		if sound.kind=="door": doors+=1
	if not fixture_require(doors==2,"exactly two authorized door sounds"): return false
	if not await fixture_stage_run({actor:{"op":"replay"}}, {},1): return false
	if not fixture_require(not bool(fixture_results[0].result.accepted) and fixture_results[0].result.reason=="replay","action replay rejected"): return false
	# Reload event follows accepted command, then existing combat kills chosen
	# opponent to end the round. No direct eliminate/end method is used.
	fixture_teleport(actor,Vector3(12,1,15.5),0.0)
	fixture_teleport(opponent,Vector3(12,1,10))
	for peer in fixture_peers:
		if peer!=actor and peer!=opponent:
			fixture_teleport(peer,MovementRules.SPAWN_POINTS[fixture_peers.find(peer)])
	if not await fixture_stage_run({actor:{"op":"reload"}}, {"sound_kind":"reload"},1): return false
	if not fixture_accepted("reload authorized"): return false
	if not await fixture_wait(func(): return not bool(combat_authority.private_state(actor).reloading),"reload completes"): return false
	# Eliminate the already wounded public target while the round continues.
	fixture_teleport(opponent,Vector3(26,1,2.5))
	fixture_teleport(victim,Vector3(12,1,10))
	for shot in 2:
		await get_tree().create_timer(0.45).timeout
		if not await fixture_stage_run({actor:{"op":"fire"}}, {},1): return false
		if not fixture_accepted("body generating shot accepted"): return false
	if not fixture_require(round_authority.state==RoundState.ACTIVE and not round_authority.is_alive(victim),"corpse exists before round end"): return false
	if not await fixture_stage_run({}, {"body_count":1}): return false
	var body_id := int(body_registry.public_list()[0].body_id)
	var body_target := "body:%d" % body_id
	fixture_teleport(actor,Vector3(12,1,11.5))
	fixture_teleport(opponent,Vector3(13,1,10))
	var inspection := {"round_id":rid,"body_id":body_id,"label":lobby.label_for(victim),"condition":"eliminado"}
	var private_expected := {actor:inspection}
	if not await fixture_one(actor,"inspect",body_target,{"private_by_peer":private_expected}): return false
	if not fixture_accepted("first private body inspection"): return false
	private_expected[opponent]=inspection
	if not await fixture_one(opponent,"inspect",body_target,{"private_by_peer":private_expected}): return false
	if not fixture_accepted("second independent private body inspection"): return false
	if not await fixture_stage_run({victim:{"op":"raw_interact","verb":"inspect","target":body_target}}, {"private_by_peer":private_expected},1): return false
	if not fixture_require(not bool(fixture_results[0].result.accepted) and fixture_results[0].result.reason=="player_dead","dead inspection rejected"): return false
	fixture_teleport(actor,Vector3(26,1,2.5))
	await get_tree().create_timer(0.25).timeout
	if not await fixture_one(actor,"inspect",body_target,{"private_by_peer":private_expected}): return false
	if not fixture_require(not bool(fixture_results[0].result.accepted) and fixture_results[0].result.reason=="out_of_range","distant inspection rejected"): return false
	fixture_teleport(actor,Vector3(12,1,15.5),0.0)
	fixture_teleport(opponent,Vector3(12,1,10))
	for shot in 3:
		await get_tree().create_timer(0.45).timeout
		if not await fixture_stage_run({actor:{"op":"fire"}}, {},1): return false
		if not fixture_accepted("ending shot accepted"): return false
	if not await fixture_wait(func(): return round_authority.state==RoundState.ENDED,"round ended by accepted combat"): return false
	if not await fixture_stage_run({}, {"body_count":2}): return false
	print("PHASE2_ROUND_OK round=%d clients=%d door=1 prop=1 sound=1 combat=1 inspection=1" % [rid,fixture_count])
	if campaign+1<fixture_rounds:
		if not await fixture_wait(func(): return round_authority.state==RoundState.ACTIVE and round_authority.round_id==rid+1,"reset",20.0): return false
	return true

func _exit_tree() -> void:
	# The delayed test transport can still own a packet peer at engine shutdown.
	# Release this fixture-owned wrapper before SceneTree destroys resources.
	if test_net_peer != null:
		var inner: MultiplayerPeer=test_net_peer.get("inner")
		# net_delay_peer's forwarding lambdas retain the wrapper, which owns
		# inner: break that test-only reference cycle before releasing it.
		for signal_name in ["peer_connected","peer_disconnected"]:
			for connection in inner.get_signal_connection_list(signal_name):
				inner.disconnect(signal_name,connection.callable)
		test_net_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		test_net_peer = null
	super._exit_tree()
