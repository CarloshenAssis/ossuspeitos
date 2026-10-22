class_name CharacterActionState
extends RefCounted

## Presentation only. Trusted event -> finite, bounded pose; no gameplay writes.
const DURATIONS := {"interact":0.45,"reload":1.2,"fire":0.22,"hurt":0.28,"death":0.4}
const PRIORITY := {"interact":1,"reload":2,"fire":3,"hurt":4,"death":5}
var kind := ""
var elapsed := 0.0
func reset() -> void:
	kind=""
	elapsed=0.0
func trigger(value: String) -> bool:
	if not DURATIONS.has(value) or kind=="death": return false
	if not kind.is_empty() and int(PRIORITY[value])<int(PRIORITY[kind]): return false
	kind=value
	elapsed=0.0
	return true
func advance(delta: float) -> Dictionary:
	var result := {"shoulder_x":0.0,"elbow_x":0.0,"torso_x":0.0}
	if kind.is_empty(): return result
	if not is_finite(delta) or delta<0.0: return result
	elapsed+=delta
	var duration := float(DURATIONS[kind])
	if elapsed>=duration:
		if kind!="death": reset()
		return result
	var weight := sin(PI*clampf(elapsed/duration,0.0,1.0))
	match kind:
		"interact":
			result.shoulder_x=-0.75*weight
			result.elbow_x=-0.35*weight
		"reload":
			result.shoulder_x=-0.65*weight
			result.elbow_x=-0.9*weight
			result.torso_x=0.035*weight
		"fire":
			result.shoulder_x=-0.85*weight
			result.elbow_x=-0.3*weight
			result.torso_x=-0.045*weight
		"hurt": result.torso_x=0.12*weight
	return result
