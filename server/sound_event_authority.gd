class_name SoundEventAuthority
extends RefCounted

## Owned by one MatchRoom. No client payload is accepted here.
const STEP_DISTANCE := 0.65
var rounds: RoundAuthority
var world: AuthoritativeWorld
var _round_id := 0
var _next_id := 1
var _events: Array=[]
var _movement: Dictionary={}
func _init(round_authority: RoundAuthority, authoritative_world: AuthoritativeWorld) -> void:
	rounds=round_authority
	world=authoritative_world
func reset(round_id: int) -> void:
	_round_id=round_id
	_next_id=1
	_events.clear()
	_movement.clear()
func snapshot() -> Array:
	return _events.duplicate(true)
func emit_authorized(kind: String, position: Vector3, peer_id: int=0) -> bool:
	if _round_id<=0 or rounds.round_id!=_round_id or rounds.state!=RoundState.ACTIVE or kind not in SoundEventRules.KINDS or not position.is_finite(): return false
	_events.append(SoundEventRules.make(_next_id,_round_id,kind,position,peer_id))
	_next_id+=1
	while _events.size()>SoundEventRules.MAX_EVENTS: _events.pop_front()
	return true
func observe_movement() -> void:
	if rounds.state!=RoundState.ACTIVE or rounds.round_id!=_round_id: return
	for peer in world.states:
		if not rounds.is_alive(peer):
			_movement.erase(peer)
			continue
		var state: Dictionary=world.states[peer]
		var position: Vector3=state.position
		var epoch: int=state.epoch
		var old: Dictionary=_movement.get(peer,{})
		if old.is_empty() or old.epoch!=epoch or position.distance_to(old.position)>1.0:
			_movement[peer]={"position":position,"epoch":epoch,"distance":0.0}
			continue
		var distance := Vector2(position.x-old.position.x,position.z-old.position.z).length()
		old.position=position
		old.distance=float(old.distance)+distance
		if float(old.distance)>=STEP_DISTANCE:
			old.distance=fmod(float(old.distance),STEP_DISTANCE)
			# No sprint exists. The run category is reserved, never inferred from
			# client keys or introduced as a new movement rule.
			emit_authorized("step_walk",position,peer)
	for peer in _movement.keys():
		if not world.states.has(peer): _movement.erase(peer)

func observe_interaction(event: Dictionary) -> void:
	var kind := str(event.get("kind",""))
	if kind=="object": kind="handle"
	if kind in ["door","impact","handle"]:
		emit_authorized(kind,event.get("position",Vector3.ZERO),int(event.get("peer_id",0)))
