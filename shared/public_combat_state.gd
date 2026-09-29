class_name PublicCombatState
extends RefCounted

## Fase 11: formato público (allowlist) do estado de cada jogador no snapshot e
## do evento público de disparo. Tudo aqui é observável no mundo: posição,
## movimento, mira, época e se a pessoa segura uma pistola. Nunca papel, vida,
## munição, inventário, alvo ou intenção de tiro.
##
## Chaves opcionais (`armed`, `shot_id`) têm padrão seguro quando faltam (um
## servidor anterior à fase 11 não as envia): desarmado e sem número de tiro.
## Qualquer chave fora da lista ou tipo errado invalida a entrada inteira.

const PLAYER_KEYS := ["peer_id", "position", "velocity", "yaw", "pitch", "spawn_index", "epoch"]
const PLAYER_OPTIONAL := ["armed"]
const SHOT_KEYS := ["round_id", "shooter_peer_id", "origin", "end", "hit_player"]
const SHOT_OPTIONAL := ["shot_id"]
## Nomes que nunca podem aparecer num DTO público (defesa extra nos testes).
const FORBIDDEN_KEYS := ["role", "health", "magazine", "reserve", "ammo", "inventory", "weapon_id",
	"hit_peer_id", "target", "reloading", "intent", "direction"]

## Estado público de um jogador vindo do snapshot, ou {} se inválido.
static func sanitize_player(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var entry: Dictionary = raw
	for key in entry.keys():
		if typeof(key) != TYPE_STRING or (str(key) not in PLAYER_KEYS and str(key) not in PLAYER_OPTIONAL):
			return {}
	for key in PLAYER_KEYS:
		if not entry.has(key):
			return {}
	if typeof(entry["peer_id"]) != TYPE_INT or typeof(entry["position"]) != TYPE_VECTOR3 \
			or typeof(entry["velocity"]) != TYPE_VECTOR3 or not _is_number(entry["yaw"]) \
			or not _is_number(entry["pitch"]) or typeof(entry["spawn_index"]) != TYPE_INT \
			or typeof(entry["epoch"]) != TYPE_INT:
		return {}
	if entry.has("armed") and typeof(entry["armed"]) != TYPE_BOOL:
		return {}
	var position: Vector3 = entry["position"]
	var velocity: Vector3 = entry["velocity"]
	if not position.is_finite() or not velocity.is_finite() or not is_finite(float(entry["yaw"])) \
			or not is_finite(float(entry["pitch"])):
		return {}
	return {"peer_id": int(entry["peer_id"]), "position": position, "velocity": velocity,
		"yaw": float(entry["yaw"]), "pitch": MovementRules.clamp_pitch(float(entry["pitch"])),
		"spawn_index": int(entry["spawn_index"]), "epoch": int(entry["epoch"]),
		"armed": bool(entry.get("armed", false))}

## Evento público de disparo, ou {} se inválido.
static func sanitize_shot(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var event: Dictionary = raw
	for key in event.keys():
		if typeof(key) != TYPE_STRING or (str(key) not in SHOT_KEYS and str(key) not in SHOT_OPTIONAL):
			return {}
	for key in SHOT_KEYS:
		if not event.has(key):
			return {}
	if typeof(event["round_id"]) != TYPE_INT or typeof(event["shooter_peer_id"]) != TYPE_INT \
			or typeof(event["origin"]) != TYPE_VECTOR3 or typeof(event["end"]) != TYPE_VECTOR3 \
			or typeof(event["hit_player"]) != TYPE_BOOL:
		return {}
	if event.has("shot_id") and (typeof(event["shot_id"]) != TYPE_INT or int(event["shot_id"]) < 1):
		return {}
	var origin: Vector3 = event["origin"]
	var finish: Vector3 = event["end"]
	if not origin.is_finite() or not finish.is_finite():
		return {}
	return {"round_id": int(event["round_id"]), "shot_id": int(event.get("shot_id", 0)),
		"shooter_peer_id": int(event["shooter_peer_id"]), "origin": origin, "end": finish,
		"hit_player": bool(event["hit_player"])}

## Superfície atingida, só com o que o evento público já mostra: jogador
## (booleano do servidor), piso (ponto final no nível do piso), nada (alcance
## máximo, sem obstáculo) ou parede.
const SURFACE_PLAYER := "player"
const SURFACE_FLOOR := "floor"
const SURFACE_WALL := "wall"
const SURFACE_NONE := "none"
const FLOOR_EPSILON := 0.05

static func impact_surface(event: Dictionary, max_distance: float) -> String:
	if bool(event.get("hit_player", false)):
		return SURFACE_PLAYER
	var origin: Vector3 = event["origin"]
	var finish: Vector3 = event["end"]
	if finish.y <= FLOOR_EPSILON:
		return SURFACE_FLOOR
	if origin.distance_to(finish) >= max_distance - 0.01:
		return SURFACE_NONE
	return SURFACE_WALL

static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT
