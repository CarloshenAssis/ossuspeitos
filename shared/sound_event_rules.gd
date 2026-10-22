class_name SoundEventRules
extends RefCounted

## Public, role-free events derived exclusively from accepted server actions.
const MAX_EVENTS := 32
const KINDS := ["step_walk", "step_run", "door", "impact", "reload", "handle"]
const KEYS := ["id", "round_id", "kind", "position", "peer_id"]
static func make(id: int, round_id: int, kind: String, position: Vector3, peer_id: int) -> Dictionary:
	return {"id":id,"round_id":round_id,"kind":kind,"position":position,"peer_id":peer_id}
static func sanitize(raw: Variant) -> Dictionary:
	if typeof(raw)!=TYPE_DICTIONARY: return {}
	var value: Dictionary=raw
	if value.size()!=KEYS.size(): return {}
	for key in KEYS:
		if not value.has(key): return {}
	if typeof(value.id)!=TYPE_INT or typeof(value.round_id)!=TYPE_INT or typeof(value.kind)!=TYPE_STRING or typeof(value.position)!=TYPE_VECTOR3 or typeof(value.peer_id)!=TYPE_INT: return {}
	if value.id<=0 or value.round_id<=0 or value.peer_id<0 or value.kind not in KINDS: return {}
	var position: Vector3=value.position
	if not position.is_finite(): return {}
	return value.duplicate()
static func category(kind: String) -> String:
	return "movement" if kind in ["step_walk","step_run"] else "environment"
static func priority(kind: String) -> int:
	return 1 if category(kind)=="movement" else 2
