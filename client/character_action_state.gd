class_name CharacterActionState
extends RefCounted

## Prioridade das ações visuais recebidas de eventos oficiais.
const PRIORITY := {"interact": 1, "reload": 2, "fire": 3, "hurt": 4, "death": 5}

var kind := ""
var elapsed := 0.0
var revision := 0

func reset() -> void:
	kind = ""
	elapsed = 0.0

func trigger(value: String) -> bool:
	if not PRIORITY.has(value) or kind == "death":
		return false
	if not kind.is_empty() and int(PRIORITY[value]) < int(PRIORITY[kind]):
		return false
	kind = value
	elapsed = 0.0
	revision += 1
	return true

func advance(delta: float, duration: float) -> void:
	if kind.is_empty() or not is_finite(delta) or delta < 0.0:
		return
	elapsed = minf(elapsed + delta, duration)
	if elapsed >= duration and kind != "death":
		reset()
