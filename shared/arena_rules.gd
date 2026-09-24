class_name ArenaRules
extends RefCounted

## Geometria oficial da partida: a mansão de `MansionMap`. Servidor e cliente
## leem exatamente estes volumes: o servidor para colisão de movimento e
## hitscan, o cliente para montar as meshes. Nenhuma parede visível existe fora
## de `BLOCKERS`, e nenhuma entrada de `BLOCKERS` fica sem mesh correspondente.
##
## Eixos: +X é leste, -Z é norte (a direção "para frente" com yaw 0). O piso
## fica em y = 0 e não há pulo nem agachamento. Tipos de volume:
##
## - `wall`: paredes do piso até acima do teto mais alto;
## - `lintel`: verga sobre um vão de porta (de `MansionMap.DOOR_HEIGHT` para
##   cima);
## - `ceiling`: laje de teto de cada ambiente, que barra tiros para cima;
## - `furniture`: móveis grandes. Mesas são tampo e pés, e o vão embaixo do
##   tampo deixa o tiro passar.
##
## O movimento só considera volumes cuja base fica abaixo do topo do corpo
## (`PLAYER_HIT_HEIGHT`); vergas e tetos ficam acima de qualquer jogador.

const EYE_HEIGHT := 0.7
const PLAYER_HIT_RADIUS := 0.45
const PLAYER_HIT_HEIGHT := 2.0
## A posição oficial é o centro do corpo (`MovementRules.PLAYER_HEIGHT`, 1 m):
## o corpo vai do piso até 2 m, e o olho fica 0,7 m acima do centro.
const BODY_CENTER_HEIGHT := 1.0
const OFFICIAL_EYE_Y := BODY_CENTER_HEIGHT + EYE_HEIGHT

## Índices 0..3: armas comuns. Índices 4..7: caixas de munição.
static var PICKUP_POSITIONS: Array = MansionMap.pickup_positions()

## Lista única usada por hitscan, colisão e apresentação.
static var BLOCKERS: Array = MansionMap.blockers()

## Regiões nomeadas para orientação: um retângulo por cômodo ou trecho de
## corredor. `min`/`max` em XZ.
static var ZONES: Array = _zones()

static func _zones() -> Array:
	var result: Array = []
	for entry in MansionMap.SPACES:
		result.append({"id": str(entry["id"]), "name": str(entry["name"]), "kind": str(entry["kind"]),
			"min": entry["min"], "max": entry["max"]})
	return result

static func ray_aabb(origin: Vector3, direction: Vector3, max_distance: float, center: Vector3, size: Vector3) -> float:
	var minimum := center - size * 0.5
	var maximum := center + size * 0.5
	var near := 0.0
	var far := max_distance
	for axis in 3:
		var component := direction[axis]
		if absf(component) < 0.000001:
			if origin[axis] < minimum[axis] or origin[axis] > maximum[axis]:
				return -1.0
			continue
		var first := (minimum[axis] - origin[axis]) / component
		var second := (maximum[axis] - origin[axis]) / component
		if first > second:
			var swap := first
			first = second
			second = swap
		near = maxf(near, first)
		far = minf(far, second)
		if near > far:
			return -1.0
	return near if near <= max_distance else -1.0

static func ray_player(origin: Vector3, direction: Vector3, max_distance: float, position: Vector3) -> float:
	# A conservative authoritative body AABB; no headshot distinction. The box is
	# centred on the official position, exactly like the client capsule, so the
	# hittable body spans the same 0..2 m the players see.
	return ray_aabb(origin, direction, max_distance, position,
		Vector3(PLAYER_HIT_RADIUS * 2.0, PLAYER_HIT_HEIGHT, PLAYER_HIT_RADIUS * 2.0))

## Distância até o piso (y = 0) para um raio que desce, ou -1.
static func ray_floor(origin: Vector3, direction: Vector3, max_distance: float) -> float:
	if direction.y >= -0.000001 or origin.y < 0.0:
		return -1.0
	var distance := origin.y / -direction.y
	return distance if distance <= max_distance else -1.0

## Distância até o primeiro bloco atingido (ou o piso), ou -1. Mesmo laço que o
## hitscan oficial de `CombatAuthority` percorre antes de testar jogadores.
static func first_blocker_distance(origin: Vector3, direction: Vector3, max_distance: float) -> float:
	var closest := ray_floor(origin, direction, max_distance)
	for blocker in BLOCKERS:
		var distance := ray_aabb(origin, direction, max_distance, blocker["center"], blocker["size"])
		if distance >= 0.0 and (closest < 0.0 or distance < closest):
			closest = distance
	return closest

## Verdadeiro quando um corpo de raio `radius` centrado em `position` (XZ)
## invade algum volume que barra movimento. Esses volumes começam abaixo do
## topo do corpo e não há pulo, então a altura não entra no teste.
static func overlaps_blocker(position: Vector3, radius: float = PLAYER_HIT_RADIUS) -> bool:
	var candidates: Array = MOVEMENT_BLOCKERS
	if radius <= BUCKET_MARGIN:
		candidates = _movement_buckets.get(_bucket_of(position), [])
	for blocker in candidates:
		if _circle_hits_box(position, radius, blocker["center"], blocker["size"]):
			return true
	return false

static func blocks_movement(blocker: Dictionary) -> bool:
	var center: Vector3 = blocker["center"]
	var size: Vector3 = blocker["size"]
	return center.y - size.y * 0.5 < PLAYER_HIT_HEIGHT

## Volumes que barram o corpo, e um índice espacial deles em baldes de 4 m. Cada
## volume entra em todo balde que seu retângulo, alargado por `BUCKET_MARGIN`,
## toca; a consulta lê só o balde da posição.
static var MOVEMENT_BLOCKERS: Array = BLOCKERS.filter(func(blocker): return blocks_movement(blocker))
const BUCKET_SIZE := 4.0
const BUCKET_MARGIN := 0.5
static var _movement_buckets: Dictionary = _build_buckets()

static func _build_buckets() -> Dictionary:
	var buckets := {}
	for blocker in MOVEMENT_BLOCKERS:
		var center: Vector3 = blocker["center"]
		var half: Vector3 = (blocker["size"] as Vector3) * 0.5
		var first := _bucket_of(center - half - Vector3(BUCKET_MARGIN, 0.0, BUCKET_MARGIN))
		var last := _bucket_of(center + half + Vector3(BUCKET_MARGIN, 0.0, BUCKET_MARGIN))
		for bx in range(first.x, last.x + 1):
			for bz in range(first.y, last.y + 1):
				var key := Vector2i(bx, bz)
				if not buckets.has(key):
					buckets[key] = []
				(buckets[key] as Array).append(blocker)
	return buckets

static func _bucket_of(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / BUCKET_SIZE), floori(position.z / BUCKET_SIZE))

static func _circle_hits_box(position: Vector3, radius: float, center: Vector3, size: Vector3) -> bool:
	var dx := maxf(absf(position.x - center.x) - size.x * 0.5, 0.0)
	var dz := maxf(absf(position.z - center.z) - size.z * 0.5, 0.0)
	return dx * dx + dz * dz < radius * radius

static func zone_at(position: Vector3) -> Dictionary:
	var entry := MansionMap.space_at(position)
	if entry.is_empty():
		return {}
	for zone in ZONES:
		if str(zone["id"]) == str(entry["id"]):
			return zone
	return {}

static func zone_name_at(position: Vector3) -> String:
	return str(zone_at(position).get("name", ""))
