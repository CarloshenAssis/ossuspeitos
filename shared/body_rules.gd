class_name BodyRules
extends RefCounted

## Corpo de jogador eliminado (fase 6): DTO público e sanitizado, igual para
## todos. Allowlist exata: nada de papel, inventário, munição, vida ou autor do
## tiro. Só uma eliminação oficial aceita pelo servidor cria um corpo.

const PUBLIC_KEYS := ["body_id", "round_id", "peer_id", "position", "yaw", "appearance"]

static func make(body_id: int, round_id: int, peer_id: int, position: Vector3, yaw: float, appearance: String) -> Dictionary:
	return {"body_id": body_id, "round_id": round_id, "peer_id": peer_id,
		"position": position, "yaw": wrapf(yaw, -PI, PI), "appearance": CharacterAppearance.sanitize(appearance)}

## Validação do lado de quem recebe: chaves exatas e tipos exatos. Devolve o
## DTO limpo ou vazio.
static func sanitize(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var payload: Dictionary = raw
	if payload.size() != PUBLIC_KEYS.size():
		return {}
	for key in PUBLIC_KEYS:
		if not payload.has(key):
			return {}
	if typeof(payload["body_id"]) != TYPE_INT or typeof(payload["round_id"]) != TYPE_INT or typeof(payload["peer_id"]) != TYPE_INT \
			or typeof(payload["position"]) != TYPE_VECTOR3 or typeof(payload["yaw"]) != TYPE_FLOAT or typeof(payload["appearance"]) != TYPE_STRING:
		return {}
	var position: Vector3 = payload["position"]
	if not (is_finite(position.x) and is_finite(position.y) and is_finite(position.z)) or not is_finite(float(payload["yaw"])):
		return {}
	if int(payload["body_id"]) <= 0 or int(payload["round_id"]) <= 0:
		return {}
	return make(int(payload["body_id"]), int(payload["round_id"]), int(payload["peer_id"]), position, float(payload["yaw"]), str(payload["appearance"]))
