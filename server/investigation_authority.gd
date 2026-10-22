class_name InvestigationAuthority
extends RefCounted

## Called after InteractionAuthority's shared replay/rate/epoch/round gate.
## Owns only each participant's last private authorized inspection.
var rounds: RoundAuthority
var world: AuthoritativeWorld
var bodies: BodyRegistry
var lobby: LobbyRegistry
var _last: Dictionary={}
func _init(round_authority: RoundAuthority, authoritative_world: AuthoritativeWorld, registry: BodyRegistry, members: LobbyRegistry) -> void:
	rounds=round_authority
	world=authoritative_world
	bodies=registry
	lobby=members
func reset() -> void:
	_last.clear()
func clear_peer(peer_id: int) -> void:
	_last.erase(peer_id)
func last_for_peer(peer_id: int) -> Dictionary:
	return (_last.get(peer_id,{}) as Dictionary).duplicate()
func inspect_body(peer_id: int, target: String, request_id: int) -> Dictionary:
	if rounds.state!=RoundState.ACTIVE: return _reject("round_not_active")
	if not rounds.is_participant(peer_id) or not lobby.has(peer_id) or not world.states.has(peer_id): return _reject("not_participant")
	if not rounds.is_alive(peer_id): return _reject("player_dead")
	var id := InvestigationRules.body_id(target)
	if not bodies.bodies.has(id): return _reject("body_unavailable")
	var body := BodyRules.sanitize(bodies.bodies[id])
	if body.is_empty() or int(body.round_id)!=rounds.round_id: return _reject("body_unavailable")
	var position: Vector3=world.states[peer_id].position
	var point: Vector3=body.position
	if position.distance_to(point)>EnvironmentRules.REACH: return _reject("out_of_range")
	var eye := position+Vector3.UP*ArenaRules.EYE_HEIGHT
	var offset := point-eye
	var distance := offset.length()
	var direction := offset.normalized()
	var wall := ArenaRules.first_blocker_distance(eye,direction,distance)
	var object := EnvironmentRules.first_hit(eye,direction,distance,world.environment_blockers)
	if (wall>=0 and wall<distance-0.05) or (object>=0 and object<distance-0.05): return _reject("interaction_blocked")
	var label := lobby.label_for(int(body.peer_id))
	if label.is_empty(): label="(saiu)"
	var response := {"request_id":request_id,"round_id":rounds.round_id,"body_id":id,"label":label,"condition":"eliminado"}
	response=InvestigationRules.sanitize(response)
	if response.is_empty(): return _reject("body_unavailable")
	_last[peer_id]=response
	return {"accepted":true,"body_id":id}
func _reject(reason: String) -> Dictionary:
	return {"accepted":false,"reason":reason}
