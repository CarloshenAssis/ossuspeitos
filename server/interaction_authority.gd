class_name InteractionAuthority
extends RefCounted

## Server-owned bounded deterministic objects. Only intents enter this API;
## positions, velocities, holders and collision geometry are never client input.
signal event_emitted(event: Dictionary)
const ACTION_INTERVAL_MSEC := 200
const MAX_SEQUENCE_ADVANCE := 64
const MAX_CARRY_MASS := 4.0
var rounds: RoundAuthority
var world: AuthoritativeWorld
var round_id := 0
var revision := 0
var _objects: Array=[]
var _last_ids: Dictionary={}
var _last_times: Dictionary={}

func _init(round_authority: RoundAuthority, authoritative_world: AuthoritativeWorld) -> void:
 rounds=round_authority
 world=authoritative_world
 reset(0)

func reset(id: int) -> void:
 round_id=id
 revision+=1
 _objects=EnvironmentRules.initial_objects()
 _last_ids.clear()
 _last_times.clear()
 _sync_blockers()

func snapshot() -> Dictionary:
 return {"round_id":round_id,"revision":revision,"objects":_objects.duplicate(true)}

func object_state(id: String) -> Dictionary:
 for item in _objects:
  if item.id==id: return item.duplicate(true)
 return {}

func blockers() -> Array:
 return EnvironmentRules.blockers({"objects":_objects})

func request(peer_id: int, action: Dictionary, now_msec: int) -> Dictionary:
 if rounds.state!=RoundState.ACTIVE or rounds.round_id!=round_id: return _reject("round_not_active")
 if not rounds.is_participant(peer_id) or not world.states.has(peer_id): return _reject("not_participant")
 if not rounds.is_alive(peer_id): return _reject("player_dead")
 if action.size() not in [3,4] or not action.has("id") or not action.has("object_id") or not action.has("verb"): return _reject("invalid_interaction")
 for key in action:
  if key not in ["kind","id","object_id","verb"]: return _reject("invalid_interaction")
 if typeof(action.id)!=TYPE_INT or typeof(action.object_id)!=TYPE_STRING or typeof(action.verb)!=TYPE_STRING: return _reject("invalid_interaction")
 if action.verb not in EnvironmentRules.VERBS or action.object_id.length()>64: return _reject("invalid_interaction")
 var old := int(_last_ids.get(peer_id,0))
 if int(action.id)<=old: return _reject("replay")
 if int(action.id)-old>MAX_SEQUENCE_ADVANCE: return _reject("sequence_jump")
 if now_msec-int(_last_times.get(peer_id,-1000))<ACTION_INTERVAL_MSEC: return _reject("rate_limited")
 # Commit valid intent before spatial checks so invalid range/ownership spam
 # cannot circumvent the same action budget. The command queue also bounds it.
 _last_ids[peer_id]=action.id
 _last_times[peer_id]=now_msec
 var object: Dictionary={}
 for item in _objects:
  if item.id==action.object_id:
   object=item
   break
 if object.is_empty(): return _reject("object_unavailable")
 var def := EnvironmentRules.definition(action.object_id)
 var player: Dictionary=world.states[peer_id]
 var position: Vector3=player.position
 var target: Vector3=object.position
 var eye: Vector3=position+Vector3.UP*ArenaRules.EYE_HEIGHT
 if position.distance_to(target)>EnvironmentRules.REACH: return _reject("out_of_range")
 var toward := target-eye
 var length := toward.length()
 var blocked := ArenaRules.first_blocker_distance(eye,toward.normalized(),length)
 var other_boxes: Array=[]
 for item in _objects:
  if item.id!=object.id:
   other_boxes.append_array(EnvironmentRules.blockers({"objects":[item]}))
 var dynamic_hit := EnvironmentRules.first_hit(eye,toward.normalized(),length,other_boxes)
 if (blocked>=0 and blocked<length-0.05) or (dynamic_hit>=0 and dynamic_hit<length-0.05): return _reject("interaction_blocked")
 if def.kind=="door":
  if action.verb!="toggle": return _reject("invalid_interaction")
  if object.open:
   for state in world.states.values():
    if EnvironmentRules.overlaps(state.position,ArenaRules.PLAYER_HIT_RADIUS,[{"center":object.position,"size":def.size}]): return _reject("object_occupied")
  if object.open:
   var closing := AABB(object.position-(def.size as Vector3)*0.5,def.size)
   for other in _objects:
    if other.id==object.id: continue
    var other_def := EnvironmentRules.definition(other.id)
    if other_def.kind=="prop" and closing.intersects(AABB(other.position-(other_def.size as Vector3)*0.5,other_def.size)):
     return _reject("object_occupied")
  object.open=not object.open
  _changed("door",object,peer_id)
 else:
  if action.verb=="take":
   if object.holder!=0: return _reject("object_occupied")
   if float(def.mass)>MAX_CARRY_MASS: return _reject("object_too_heavy")
   for held in _objects:
    if held.holder==peer_id: return _reject("already_carrying")
   object.holder=peer_id
   object.velocity=Vector3.ZERO
  elif action.verb=="drop":
   if object.holder!=peer_id: return _reject("not_holder")
   if not _free_position(object.position,object,0): return _reject("object_occupied")
   object.holder=0
   object.velocity=Vector3.ZERO
  elif action.verb=="push":
   if object.holder!=0: return _reject("object_occupied")
   var direction := Vector3(target.x-position.x,0,target.z-position.z).normalized()
   object.velocity=direction*EnvironmentRules.MAX_HORIZONTAL_SPEED
  else: return _reject("invalid_interaction")
  _changed("object",object,peer_id)
 _sync_blockers()
 return {"accepted":true,"object_id":object.id,"verb":action.verb}

func release_peer(peer_id: int) -> void:
 for item in _objects:
  if item.holder==peer_id:
   item.position=_safe_release_position(item)
   item.holder=0
   item.velocity=Vector3.ZERO
   _changed("object",item,peer_id)
 # Forced release can happen within a living connection. Keep its replay and
 # rate budgets; reset() alone clears them at the new round boundary.
 _sync_blockers()

func tick(delta: float) -> void:
 var changed := false
 for item in _objects:
  var def := EnvironmentRules.definition(item.id)
  if def.kind!="prop": continue
  var previous: Vector3=item.position
  if item.holder>0:
   var holder := int(item.holder)
   if not world.states.has(holder) or not rounds.is_alive(holder) or rounds.state!=RoundState.ACTIVE:
    release_peer(holder)
    changed=true
    continue
   else:
    var state: Dictionary=world.states[holder]
    var direction := MovementRules.aim_direction(float(state.yaw),0.0)
    var target: Vector3=state.position+direction*0.85+Vector3.UP*0.15
    if previous.distance_to(target)>EnvironmentRules.REACH:
     release_peer(holder)
     changed=true
     continue
    var clear := true
    var chunks := maxi(1,ceili(previous.distance_to(target)/0.15))
    for index in range(1,chunks+1):
     if not _free_position(previous.lerp(target,float(index)/float(chunks)),item,holder):
      clear=false
      break
    if clear:
     item.position=target
     changed=changed or target!=previous
    continue
  var velocity: Vector3=item.velocity
  var ground := float((def.size as Vector3).y)*0.5
  if velocity==Vector3.ZERO and float((item.position as Vector3).y)<=ground: continue
  velocity.y=maxf(-EnvironmentRules.MAX_FALL_SPEED,velocity.y-9.8*delta)
  var next: Vector3=item.position+velocity*delta
  next.x=clampf(next.x,MovementRules.MAP_MIN_X,MovementRules.MAP_MAX_X)
  next.z=clampf(next.z,MovementRules.MAP_MIN_Z,MovementRules.MAP_MAX_Z)
  var boxes := ArenaRules.MOVEMENT_BLOCKERS.duplicate()
  for other in _objects:
   if other.id!=item.id: boxes.append_array(EnvironmentRules.blockers({"objects":[other]}))
  var radius := maxf((def.size as Vector3).x,(def.size as Vector3).z)*0.5
  var collision := EnvironmentRules.overlaps(next,radius,boxes)
  for state in world.states.values():
   if Vector2(next.x-state.position.x,next.z-state.position.z).length()<radius+ArenaRules.PLAYER_HIT_RADIUS:
    collision=true
    var top := ArenaRules.PLAYER_HIT_HEIGHT+(def.size as Vector3).y*0.5
    if previous.y>=top and next.y<top:
     next.y=top
     velocity.y=0.0
  if collision:
   next.x=previous.x
   next.z=previous.z
   velocity.x=0
   velocity.z=0
  if next.y<=ground:
   if previous.y>ground+0.02: _changed("impact",item,0)
   next.y=ground
   velocity.y=0
   velocity.x=move_toward(velocity.x,0.0,3.0*delta)
   velocity.z=move_toward(velocity.z,0.0,3.0*delta)
  item.position=next
  item.velocity=velocity
  changed=changed or next!=previous
 if changed:
  revision+=1
  _sync_blockers()

func _changed(kind: String, object: Dictionary, peer_id: int) -> void:
 revision+=1
 event_emitted.emit({"kind":kind,"object_id":str(object.id),"position":object.position,"peer_id":peer_id,"round_id":round_id,"revision":revision})

func _sync_blockers() -> void:
 world.set_environment_blockers(blockers())

func _reject(reason: String) -> Dictionary:
 return {"accepted":false,"reason":reason}

# Conservative swept carry/drop collision. Ignore only the owner; other
# players, doors, props and official static geometry remain solid.
func _free_position(position: Vector3, object: Dictionary, ignore_peer: int) -> bool:
 var def := EnvironmentRules.definition(object.id)
 var radius := maxf((def.size as Vector3).x,(def.size as Vector3).z)*0.5
 var boxes := ArenaRules.MOVEMENT_BLOCKERS.duplicate()
 for other in _objects:
  if other.id!=object.id: boxes.append_array(EnvironmentRules.blockers({"objects":[other]}))
 if EnvironmentRules.overlaps(position,radius,boxes): return false
 for id in world.states:
  if int(id)==ignore_peer: continue
  var state: Dictionary=world.states[id]
  if Vector2(position.x-state.position.x,position.z-state.position.z).length()<radius+ArenaRules.PLAYER_HIT_RADIUS: return false
 return position.x>=MovementRules.MAP_MIN_X and position.x<=MovementRules.MAP_MAX_X and position.z>=MovementRules.MAP_MIN_Z and position.z<=MovementRules.MAP_MAX_Z

func _safe_release_position(object: Dictionary) -> Vector3:
 if _free_position(object.position,object,0): return object.position
 var def := EnvironmentRules.definition(object.id)
 for radius in [0.8,1.2,2.0,3.0]:
  for index in 16:
   var offset := Vector3(cos(float(index)*TAU/16.0),0,sin(float(index)*TAU/16.0))*float(radius)
   var candidate: Vector3=object.position+offset
   candidate.y=(def.size as Vector3).y*0.5
   if _free_position(candidate,object,0): return candidate
 # A server-driven displacement can exhaust nearby space. Returning the prop
 # to its build-distributed origin is safe only if clear; otherwise suspend it
 # above the movement plane until a future round reset (no blocking trap).
 if _free_position(def.position,object,0): return def.position
 return Vector3((object.position as Vector3).x,3.5,(object.position as Vector3).z)
