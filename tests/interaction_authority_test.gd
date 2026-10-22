extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  printerr("INTERACTION_ASSERT " + label)
func _initialize() -> void:
 var authority_script = load("res://server/interaction_authority.gd")
 check(authority_script != null, "interactive authority exists")
 if authority_script == null:
  quit(1)
  return
 var EnvironmentRules = load("res://shared/environment_rules.gd")
 var room := MatchRoom.new(1, "ABC234", 0, false, 0.1, 1.0, 8)
 for peer in range(1,5): room.add_member(peer,"Player%d" % peer,0)
 room.round_authority.tick(1000)
 var authority = authority_script.new(room.round_authority,room.world)
 authority.reset(room.round_authority.round_id)
 var before: Dictionary = authority.snapshot()
 check(before.objects.size() == MansionMap.DOORS.size()+3,"bounded catalog")
 var door_id := str(MansionMap.DOORS[0].id)
 var door: Dictionary = EnvironmentRules.definition(door_id)
 var p: Vector3 = door.position
 room.world.teleport(1,p+Vector3(-1.2,0,0)); room.world.states[1].position.y=1.0
 room.world.teleport(2,p+Vector3(-1.2,0,0.8)); room.world.states[2].position.y=1.0
 var result: Dictionary = authority.request(1,{"id":1,"object_id":door_id,"verb":"toggle"},2000)
 check(result.accepted,"near player closes door")
 check(authority.blockers().size()==4,"closed door shared collision")
 check(not authority.request(1,{"id":1,"object_id":door_id,"verb":"toggle"},2300).accepted,"replayed action refused")
 check(not authority.request(1,{"id":2,"object_id":door_id,"verb":"toggle"},2050).accepted,"rate limit")
 check(not authority.request(4,{"id":1,"object_id":door_id,"verb":"toggle"},2300).accepted,"out of range")
 result=authority.request(2,{"id":1,"object_id":door_id,"verb":"toggle"},2300)
 check(result.accepted,"second player opens same shared door")
 check(authority.blockers().size()==3,"open door does not block")
 room.world.teleport(1,Vector3(p.x,1,p.z))
 check(not authority.request(2,{"id":2,"object_id":door_id,"verb":"toggle"},2600).accepted,"close cannot trap player")
 var prop := "prop_escritorio"
 var prop_def: Dictionary=EnvironmentRules.definition(prop)
 room.world.teleport(1,prop_def.position+Vector3(-0.8,1-prop_def.position.y,0))
 room.world.teleport(2,prop_def.position+Vector3(-1.0,1-prop_def.position.y,0.3))
 check(authority.request(1,{"id":3,"object_id":prop,"verb":"take"},2900).accepted,"take light object")
 check(not authority.request(2,{"id":3,"object_id":prop,"verb":"take"},2900).accepted,"concurrent owner denied")
 check(not authority.request(1,{"id":4,"object_id":prop,"verb":"teleport","position":Vector3(40,0,20)},3200).accepted,"client teleport impossible")
 authority.release_peer(1)
 check(int(authority.object_state(prop).holder)==0,"disconnect releases held prop")
 room.round_authority.alive[1]=false
 check(not authority.request(1,{"id":5,"object_id":prop,"verb":"push"},3500).accepted,"dead player denied")
 var frozen: Dictionary=authority.snapshot()
 var copy: Dictionary=authority.snapshot()
 copy.objects[0].open=false
 check(authority.snapshot()==frozen,"snapshot copy independent")
 check(EnvironmentRules.sanitize(frozen)==frozen,"snapshot strict sanitizer roundtrips")
 var forged: Dictionary=frozen.duplicate(true); forged.objects[0]["role"]="assassin"
 check(EnvironmentRules.sanitize(forged).is_empty(),"secret/unknown snapshot keys rejected")
 check(NetSync.parse_action(["interact",1,prop,"push"]).get("object_id","")==prop,"bounded action protocol")
 check(NetSync.parse_action(["interact",1,prop,"teleport",Vector3.ZERO]).has("reason"),"malformed teleport payload denied")
 var other=authority_script.new(room.round_authority,AuthoritativeWorld.new())
 other.reset(9)
 check(other.snapshot().round_id==9 and authority.snapshot().round_id!=9,"room isolation")
 authority.reset(2)
 check(authority.blockers().size()==3 and authority.snapshot().round_id==2,"round reset restores environment")
 room.round_authority.alive[1]=true
 # Shared dynamic collision and replay from the same authoritative blockers.
 room.world.teleport(1,p+Vector3(-1.2,1-p.y,0))
 room.world.teleport(2,Vector3(12,1,16))
 authority.reset(room.round_authority.round_id)
 check(authority.request(1,{"id":1,"object_id":door_id,"verb":"toggle"},4000).accepted,"door closes for geometry fixture")
 var closed_boxes: Array=authority.blockers()
 var toward := Vector3.RIGHT
 check(EnvironmentRules.first_hit(Vector3(p.x-1.2,1.7,p.z),toward,3,closed_boxes)>0,"closed door blocks bullet at eye height")
 var moved := MovementRules.resolve_step(Vector3(p.x-1.2,1,p.z),toward*2.4,closed_boxes)
 check(float((moved.position as Vector3).x)<p.x,"closed door blocks player sweep")
 var predicted := PlayerPrediction.new()
 predicted.set_environment_blockers(closed_boxes)
 var official: Dictionary=room.world.states[1]
 predicted.reconcile(room.world.ack_for(1),official)
 for tick in 60:
  var command := predicted.build_command(Vector2.RIGHT.rotated(float(official.yaw)))
  room.world.receive_commands(1,NetSync.encode_packet(command.epoch,command.seq,[NetSync.encode_command(command.move,command.yaw_delta,command.pitch_delta,[])]),5000+tick*17)
  room.world.step(func(_id): return "",func(_id,_action,_seq): pass,func(_id,_seq,_action,_why): pass)
 check(predicted.state.position.is_equal_approx(room.world.states[1].position),"dynamic blocker prediction matches before ACK")
 check((predicted.state.position as Vector3).x>p.x-1.1 and (predicted.state.position as Vector3).x<p.x,"actual commanded movement approaches and stops at dynamic door")
 predicted.reset_all()
 check(predicted.environment_blockers.is_empty(),"prediction reset cannot retain room blockers")
 room.world.teleport(1,p+Vector3(-1.2,1-p.y,0))
 check(authority.request(1,{"id":2,"object_id":door_id,"verb":"toggle"},7000).accepted,"open door geometry")
 check(EnvironmentRules.first_hit(Vector3(p.x-1.2,1.7,p.z),toward,3,authority.blockers())<0,"open door passes same ray")
 check(not authority.request(1,{"id":3,"object_id":"missing","verb":"take"},7300).accepted,"removed object rejected")
 room.world.teleport(1,Vector3(23,1,11.5))
 check(not authority.request(1,{"id":4,"object_id":"prop_cozinha","verb":"take"},7600).accepted,"mass limit rejects heavy prop")
 # LOS through the office wall cannot be bypassed by short reach.
 room.world.teleport(1,Vector3(6.8,1,3.5))
 check(not authority.request(1,{"id":5,"object_id":"prop_escritorio","verb":"push"},7900).accepted,"out of range or wall refuses interaction")
 room.round_authority.alive[1]=true
 room.world.teleport(1,Vector3(2.2,1,3.5),-PI/2)
 check(authority.request(1,{"id":6,"object_id":prop,"verb":"take"},8200).accepted,"take for carry movement")
 var carried_before: Dictionary=authority.snapshot()
 authority.tick(NetSync.TICK_SECONDS)
 check(authority.snapshot().revision>carried_before.revision,"carried transform increments revision")
 var held_position: Vector3=authority.object_state(prop).position
 check(held_position.y>0.3,"held object raised above floor")
 check(authority.request(1,{"id":7,"object_id":prop,"verb":"drop"},8500).accepted,"drop permitted in clear space")
 for tick in 120: authority.tick(NetSync.TICK_SECONDS)
 check(is_equal_approx((authority.object_state(prop).position as Vector3).y,0.3),"dropped object falls to floor")
 check(authority.request(1,{"id":8,"object_id":prop,"verb":"push"},8800).accepted,"push intent accepted")
 var pushed_from: Vector3=authority.object_state(prop).position
 for tick in 20: authority.tick(NetSync.TICK_SECONDS)
 check((authority.object_state(prop).position as Vector3).distance_to(pushed_from)>0.05,"push moves object through authoritative integrator")
 # The round can end between take and the first held-object tick. The
 # authority must restore collision even though the prop still rests on floor.
 authority.reset(room.round_authority.round_id)
 room.world.teleport(1,Vector3(2.2,1,3.5),-PI/2)
 check(authority.request(1,{"id":1,"object_id":prop,"verb":"take"},9100).accepted,"take before round-end transition")
 room.round_authority.state=RoundState.ENDED
 authority.tick(NetSync.TICK_SECONDS)
 check(authority.object_state(prop).holder==0,"ended round releases holder")
 check(EnvironmentRules.blockers(authority.snapshot())==room.world.environment_blockers,"ended round collision cannot retain held-object exemption")
 # A forced drop must not reset a still-connected player's action budget.
 room.round_authority.state=RoundState.ACTIVE
 room.round_authority.alive[1]=true
 authority.reset(room.round_authority.round_id)
 room.world.teleport(1,p+Vector3(-1.2,-0.2,0))
 room.world.teleport(2,Vector3(25,1,2.5))
 var accepted_count := 0
 for index in range(1,66):
  var toggle: Dictionary=authority.request(1,{"id":index,"object_id":door_id,"verb":"toggle"},10000+index*250)
  if toggle.accepted: accepted_count+=1
 check(accepted_count==65,"long connected action history accepted")
 authority.release_peer(1)
 check(authority.request(1,{"id":66,"object_id":door_id,"verb":"toggle"},27000).accepted,"forced release preserves live action sequence")
 room.clear()
 print("INTERACTION_AUTHORITY_TEST_%s checks=%d failures=%d" % ["OK" if failures==0 else "FAILED",checks,failures])
 quit(0 if failures==0 else 1)
