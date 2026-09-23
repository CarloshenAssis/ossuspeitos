class_name ArenaRules
extends RefCounted

## Geometria oficial da arena graybox. Servidor e cliente leem exatamente estes
## dados: o servidor para colisão de movimento e hitscan, o cliente para montar
## as meshes. Nenhuma parede visível existe fora de `BLOCKERS`, e nenhuma
## entrada de `BLOCKERS` fica sem mesh correspondente.
##
## Eixos: +X é leste, -Z é norte (a direção "para frente" com yaw 0). O piso
## fica em y = 0 e não há pulo: todo bloco apoiado no piso bloqueia movimento.
## Tiros saem na altura do olho, sempre horizontais, e só param em blocos cujo
## topo passa dessa altura. Por isso existem três alturas bem distintas:
##
## - `wall` (3,0 m) e muro externo (3,5 m): bloqueiam visão, tiro e passagem;
## - `cover` (2,4 m): cobertura cheia, bloqueia visão, tiro e passagem;
## - `low` (1,0 m): caixote baixo, bloqueia passagem mas a câmera e o tiro
##   passam por cima — o que se vê por cima dele também pode ser atingido.

const EYE_HEIGHT := 0.7
const PLAYER_HIT_RADIUS := 0.45
const PLAYER_HIT_HEIGHT := 2.0
## A posição oficial é o centro do corpo (`MovementRules.PLAYER_HEIGHT`, 1 m):
## o corpo vai do piso até 2 m, e o olho fica 0,7 m acima do centro.
const BODY_CENTER_HEIGHT := 1.0
const OFFICIAL_EYE_Y := BODY_CENTER_HEIGHT + EYE_HEIGHT

const TALL_HEIGHT := 3.0
const COVER_HEIGHT := 2.4
const LOW_HEIGHT := 1.0
const OUTER_WALL_HEIGHT := 3.5
const OUTER_WALL_THICKNESS := 0.5
## Face interna dos muros externos.
const INNER_HALF_EXTENT := 14.5

## Índices 0..3: armas comuns, uma em cada lado da arena. Índices 4..7: caixas
## de munição nas quatro entradas do pátio central.
const PICKUP_POSITIONS := [
	Vector3(3.2, 0.25, 8.4), Vector3(-8.4, 0.25, 3.2),
	Vector3(-3.2, 0.25, -8.4), Vector3(8.4, 0.25, -3.2),
	Vector3(0.0, 0.25, 4.2), Vector3(-4.2, 0.25, 0.0),
	Vector3(0.0, 0.25, -4.2), Vector3(4.2, 0.25, 0.0),
]

const OUTER_WALLS := [
	{"id": "outer_west", "kind": "outer", "center": Vector3(-14.75, 1.75, 0.0), "size": Vector3(0.5, 3.5, 30.0)},
	{"id": "outer_east", "kind": "outer", "center": Vector3(14.75, 1.75, 0.0), "size": Vector3(0.5, 3.5, 30.0)},
	{"id": "outer_north", "kind": "outer", "center": Vector3(0.0, 1.75, -14.75), "size": Vector3(30.0, 3.5, 0.5)},
	{"id": "outer_south", "kind": "outer", "center": Vector3(0.0, 1.75, 14.75), "size": Vector3(30.0, 3.5, 0.5)},
]

## Obstáculos internos. O layout tem simetria rotacional de 90°, portanto
## nenhum spawn ou lado é favorecido.
const INTERIOR := [
	# Pátio central: monumento alto e quatro caixotes baixos (tiro passa por cima).
	{"id": "monument", "kind": "wall", "center": Vector3(0.0, 1.5, 0.0), "size": Vector3(2.4, 3.0, 2.4)},
	{"id": "plaza_crate_0", "kind": "low", "center": Vector3(2.9, 0.5, 2.9), "size": Vector3(1.0, 1.0, 1.0)},
	{"id": "plaza_crate_1", "kind": "low", "center": Vector3(-2.9, 0.5, 2.9), "size": Vector3(1.0, 1.0, 1.0)},
	{"id": "plaza_crate_2", "kind": "low", "center": Vector3(-2.9, 0.5, -2.9), "size": Vector3(1.0, 1.0, 1.0)},
	{"id": "plaza_crate_3", "kind": "low", "center": Vector3(2.9, 0.5, -2.9), "size": Vector3(1.0, 1.0, 1.0)},
	# Norte (z < 0)
	{"id": "north_spawn_shield", "kind": "cover", "center": Vector3(0.0, 1.2, -10.8), "size": Vector3(4.8, 2.4, 0.6)},
	{"id": "north_pinwheel", "kind": "cover", "center": Vector3(-4.2, 1.2, -5.6), "size": Vector3(0.6, 2.4, 2.6)},
	{"id": "north_crate", "kind": "low", "center": Vector3(4.6, 0.5, -11.4), "size": Vector3(1.4, 1.0, 1.4)},
	{"id": "north_flank_wall", "kind": "cover", "center": Vector3(-6.6, 1.2, -10.4), "size": Vector3(2.4, 2.4, 0.6)},
	{"id": "north_pillar", "kind": "wall", "center": Vector3(-9.0, 1.5, -4.6), "size": Vector3(0.9, 3.0, 0.9)},
	# Sul (z > 0)
	{"id": "south_spawn_shield", "kind": "cover", "center": Vector3(0.0, 1.2, 10.8), "size": Vector3(4.8, 2.4, 0.6)},
	{"id": "south_pinwheel", "kind": "cover", "center": Vector3(4.2, 1.2, 5.6), "size": Vector3(0.6, 2.4, 2.6)},
	{"id": "south_crate", "kind": "low", "center": Vector3(-4.6, 0.5, 11.4), "size": Vector3(1.4, 1.0, 1.4)},
	{"id": "south_flank_wall", "kind": "cover", "center": Vector3(6.6, 1.2, 10.4), "size": Vector3(2.4, 2.4, 0.6)},
	{"id": "south_pillar", "kind": "wall", "center": Vector3(9.0, 1.5, 4.6), "size": Vector3(0.9, 3.0, 0.9)},
	# Leste (x > 0)
	{"id": "east_spawn_shield", "kind": "cover", "center": Vector3(10.8, 1.2, 0.0), "size": Vector3(0.6, 2.4, 4.8)},
	{"id": "east_pinwheel", "kind": "cover", "center": Vector3(5.6, 1.2, -4.2), "size": Vector3(2.6, 2.4, 0.6)},
	{"id": "east_crate", "kind": "low", "center": Vector3(11.4, 0.5, 4.6), "size": Vector3(1.4, 1.0, 1.4)},
	{"id": "east_flank_wall", "kind": "cover", "center": Vector3(10.4, 1.2, -6.6), "size": Vector3(0.6, 2.4, 2.4)},
	{"id": "east_pillar", "kind": "wall", "center": Vector3(4.6, 1.5, -9.0), "size": Vector3(0.9, 3.0, 0.9)},
	# Oeste (x < 0)
	{"id": "west_spawn_shield", "kind": "cover", "center": Vector3(-10.8, 1.2, 0.0), "size": Vector3(0.6, 2.4, 4.8)},
	{"id": "west_pinwheel", "kind": "cover", "center": Vector3(-5.6, 1.2, 4.2), "size": Vector3(2.6, 2.4, 0.6)},
	{"id": "west_crate", "kind": "low", "center": Vector3(-11.4, 0.5, -4.6), "size": Vector3(1.4, 1.0, 1.4)},
	{"id": "west_flank_wall", "kind": "cover", "center": Vector3(-10.4, 1.2, 6.6), "size": Vector3(0.6, 2.4, 2.4)},
	{"id": "west_pillar", "kind": "wall", "center": Vector3(-4.6, 1.5, 9.0), "size": Vector3(0.9, 3.0, 0.9)},
	# Salas de spawn nos quatro cantos: duas pernas altas e porta diagonal.
	{"id": "room_northeast_wall_x", "kind": "wall", "center": Vector3(13.0, 1.5, -10.2), "size": Vector3(3.0, 3.0, 0.6)},
	{"id": "room_northeast_wall_z", "kind": "wall", "center": Vector3(10.2, 1.5, -13.0), "size": Vector3(0.6, 3.0, 3.0)},
	{"id": "room_northwest_wall_x", "kind": "wall", "center": Vector3(-13.0, 1.5, -10.2), "size": Vector3(3.0, 3.0, 0.6)},
	{"id": "room_northwest_wall_z", "kind": "wall", "center": Vector3(-10.2, 1.5, -13.0), "size": Vector3(0.6, 3.0, 3.0)},
	{"id": "room_southeast_wall_x", "kind": "wall", "center": Vector3(13.0, 1.5, 10.2), "size": Vector3(3.0, 3.0, 0.6)},
	{"id": "room_southeast_wall_z", "kind": "wall", "center": Vector3(10.2, 1.5, 13.0), "size": Vector3(0.6, 3.0, 3.0)},
	{"id": "room_southwest_wall_x", "kind": "wall", "center": Vector3(-13.0, 1.5, 10.2), "size": Vector3(3.0, 3.0, 0.6)},
	{"id": "room_southwest_wall_z", "kind": "wall", "center": Vector3(-10.2, 1.5, 13.0), "size": Vector3(0.6, 3.0, 3.0)},
]

## Lista única usada por hitscan, colisão e apresentação.
const BLOCKERS := OUTER_WALLS + INTERIOR

## Regiões nomeadas para orientação. Grade 3x3: pátio no meio, quatro bordas
## e quatro cantos (onde ficam as salas de spawn). `min`/`max` em XZ.
const ZONE_EDGE := 5.0
const ZONES := [
	{"id": "center", "name": "Pátio central", "min": Vector2(-5.0, -5.0), "max": Vector2(5.0, 5.0)},
	{"id": "north", "name": "Norte", "min": Vector2(-5.0, -14.5), "max": Vector2(5.0, -5.0)},
	{"id": "south", "name": "Sul", "min": Vector2(-5.0, 5.0), "max": Vector2(5.0, 14.5)},
	{"id": "west", "name": "Oeste", "min": Vector2(-14.5, -5.0), "max": Vector2(-5.0, 5.0)},
	{"id": "east", "name": "Leste", "min": Vector2(5.0, -5.0), "max": Vector2(14.5, 5.0)},
	{"id": "northwest", "name": "Canto noroeste", "min": Vector2(-14.5, -14.5), "max": Vector2(-5.0, -5.0)},
	{"id": "northeast", "name": "Canto nordeste", "min": Vector2(5.0, -14.5), "max": Vector2(14.5, -5.0)},
	{"id": "southwest", "name": "Canto sudoeste", "min": Vector2(-14.5, 5.0), "max": Vector2(-5.0, 14.5)},
	{"id": "southeast", "name": "Canto sudeste", "min": Vector2(5.0, 5.0), "max": Vector2(14.5, 14.5)},
]

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

## Distância até o primeiro bloco atingido, ou -1. Mesmo laço que o hitscan
## oficial de `CombatAuthority` percorre antes de testar jogadores.
static func first_blocker_distance(origin: Vector3, direction: Vector3, max_distance: float) -> float:
	var closest := -1.0
	for blocker in BLOCKERS:
		var distance := ray_aabb(origin, direction, max_distance, blocker["center"], blocker["size"])
		if distance >= 0.0 and (closest < 0.0 or distance < closest):
			closest = distance
	return closest

## Verdadeiro quando um corpo de raio `radius` centrado em `position` (XZ)
## invade algum bloco. Blocos começam no piso e não há pulo, então a altura
## não entra no teste.
static func overlaps_blocker(position: Vector3, radius: float = PLAYER_HIT_RADIUS) -> bool:
	for blocker in BLOCKERS:
		if _circle_hits_box(position, radius, blocker["center"], blocker["size"]):
			return true
	return false

static func _circle_hits_box(position: Vector3, radius: float, center: Vector3, size: Vector3) -> bool:
	var dx := maxf(absf(position.x - center.x) - size.x * 0.5, 0.0)
	var dz := maxf(absf(position.z - center.z) - size.z * 0.5, 0.0)
	return dx * dx + dz * dz < radius * radius

static func zone_at(position: Vector3) -> Dictionary:
	for zone in ZONES:
		var minimum: Vector2 = zone["min"]
		var maximum: Vector2 = zone["max"]
		if position.x >= minimum.x and position.x <= maximum.x and position.z >= minimum.y and position.z <= maximum.y:
			return zone
	return {}

static func zone_name_at(position: Vector3) -> String:
	return str(zone_at(position).get("name", ""))
