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

## Protocol12 retains a bounded event history over potentially unreliable
## snapshots; compact encoding removes repeated keys/round ids, not events.
static func encode_wire(events: Array) -> Array:
	if events.is_empty(): return []
	if events.size()>MAX_EVENTS: return []
	var first := sanitize(events[0])
	if first.is_empty(): return []
	var rows: Array=[]
	for index in events.size():
		var event := sanitize(events[index])
		if event.is_empty() or event.round_id!=first.round_id or event.id!=int(first.id)+index: return []
		rows.append([KINDS.find(str(event.kind)),event.position,event.peer_id])
	return [first.round_id,first.id,rows]

static func decode_wire(raw: Variant) -> Array:
	if typeof(raw)!=TYPE_ARRAY: return []
	var wire: Array=raw
	if wire.is_empty(): return []
	if wire.size()!=3 or typeof(wire[0])!=TYPE_INT or typeof(wire[1])!=TYPE_INT or typeof(wire[2])!=TYPE_ARRAY: return []
	var round_id := int(wire[0])
	var first := int(wire[1])
	var rows: Array=wire[2]
	if round_id<=0 or first<=0 or first>9223372036854775775 or rows.size()>MAX_EVENTS: return []
	var result: Array=[]
	for index in rows.size():
		var raw_row: Variant=rows[index]
		if typeof(raw_row)!=TYPE_ARRAY or raw_row.size()!=3: return []
		var row: Array=raw_row
		if typeof(row[0])!=TYPE_INT or int(row[0])<0 or int(row[0])>=KINDS.size() or typeof(row[1])!=TYPE_VECTOR3 or typeof(row[2])!=TYPE_INT: return []
		var event := sanitize(make(first+index,round_id,KINDS[int(row[0])],row[1],row[2]))
		if event.is_empty(): return []
		result.append(event)
	return result
