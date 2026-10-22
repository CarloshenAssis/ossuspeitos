class_name InvestigationRules
extends RefCounted

## Deliberately small PRIVATE response. No role/weapon/instigator/health facts.
const KEYS := ["request_id","round_id","body_id","label","condition"]
static func sanitize(raw: Variant) -> Dictionary:
	if typeof(raw)!=TYPE_DICTIONARY: return {}
	var value: Dictionary=raw
	if value.size()!=KEYS.size(): return {}
	for key in KEYS:
		if not value.has(key): return {}
	for key in ["request_id","round_id","body_id"]:
		if typeof(value[key])!=TYPE_INT or int(value[key])<=0: return {}
	if typeof(value.label)!=TYPE_STRING or typeof(value.condition)!=TYPE_STRING: return {}
	if not RoundRules.label_problem(value.label).is_empty() or value.condition!="eliminado": return {}
	return value.duplicate()
static func body_id(target: String) -> int:
	if not target.begins_with("body:"): return 0
	var suffix := target.substr(5)
	var id := suffix.to_int()
	return id if id>0 and str(id)==suffix else 0
