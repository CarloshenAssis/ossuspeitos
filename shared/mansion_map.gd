class_name MansionMap
extends RefCounted

## Fonte única do mapa da mansão (planta aprovada, um único piso). Servidor,
## cliente, demo e testes leem estes dados; nada aqui depende de cena, mesh,
## luz ou áudio, então o servidor headless carrega só isto.
##
## Eixos: +X é leste, +Z é sul (a frente com yaw 0 é -Z, norte). Piso em y = 0.
## Coordenadas em metros, múltiplos de `CELL` (0,5 m), com origem no canto
## noroeste do Escritório.
##
## O que é declarado:
## - `SPACES`: cômodos e corredores, retângulos de piso livre (XZ) com teto;
## - `DOORS`: vãos nas paredes entre um cômodo e um corredor (célula de parede
##   livre, com verga acima de `DOOR_HEIGHT`);
## - `JUNCTIONS`: encontros abertos entre corredores contíguos;
## - `FURNITURE`: volumes físicos dos móveis grandes (peças AABB);
## - `SPAWNS` e `PICKUPS`: marcadores.
##
## O que é derivado (determinístico, `blockers()`): paredes (toda célula não
## livre vizinha de uma livre, fundida em caixas), vergas dos vãos, lajes de teto
## e as peças dos móveis. Não existe parede declarada à mão: um canto não fica
## aberto por esquecimento, e o fechamento externo é o anel de paredes.

const CELL := 0.5
## Altura livre das portas; acima delas fica a verga.
const DOOR_HEIGHT := 2.4
const ROOM_CEILING := 3.2
const HALL_CEILING := 4.5
const CORRIDOR_CEILING := 3.0
const SLAB_THICKNESS := 0.2
## Todas as paredes sobem até acima do teto mais alto (Salão), então nenhum
## tiro passa por cima de uma parede para outro ambiente.
const WALL_TOP := HALL_CEILING + SLAB_THICKNESS
## Mesmos valores das regras oficiais (duplicados aqui para o mapa não depender
## de outras classes; `arena_layout_test` confere a igualdade).
const BODY_CENTER_HEIGHT := 1.0
const PICKUP_HEIGHT := 0.25

const SPACES := [
	# Cômodos (nove, nomes da planta aprovada).
	{"id": "escritorio", "name": "Escritório", "kind": "room", "min": Vector2(0.0, 0.0), "max": Vector2(6.0, 5.0), "ceiling": ROOM_CEILING},
	{"id": "biblioteca", "name": "Biblioteca", "kind": "room", "min": Vector2(0.5, 8.0), "max": Vector2(5.5, 16.0), "ceiling": ROOM_CEILING},
	{"id": "galeria", "name": "Galeria de Retratos", "kind": "room", "min": Vector2(21.0, -0.5), "max": Vector2(30.0, 4.5), "ceiling": ROOM_CEILING},
	{"id": "salao", "name": "Salão Central", "kind": "room", "min": Vector2(8.5, 7.5), "max": Vector2(18.5, 16.5), "ceiling": HALL_CEILING},
	{"id": "cozinha", "name": "Cozinha", "kind": "room", "min": Vector2(21.5, 9.0), "max": Vector2(28.5, 14.0), "ceiling": ROOM_CEILING},
	{"id": "jantar", "name": "Sala de Jantar", "kind": "room", "min": Vector2(9.0, 19.5), "max": Vector2(18.0, 24.5), "ceiling": ROOM_CEILING},
	{"id": "quarto_fundo", "name": "Quarto do Fundo", "kind": "room", "min": Vector2(30.5, 22.5), "max": Vector2(35.5, 28.5), "ceiling": ROOM_CEILING},
	{"id": "quarto_hospedes", "name": "Quarto de Hóspedes", "kind": "room", "min": Vector2(38.0, 22.5), "max": Vector2(43.0, 27.5), "ceiling": ROOM_CEILING},
	{"id": "banheiro", "name": "Banheiro", "kind": "room", "min": Vector2(42.5, 10.0), "max": Vector2(45.5, 13.5), "ceiling": ROOM_CEILING},
	# Corredores (vermelho na planta). Largura livre de 3 m (2 m nos trechos
	# curtos entre cômodos vizinhos).
	{"id": "corredor_norte", "name": "Corredor norte", "kind": "corridor", "min": Vector2(6.5, 1.0), "max": Vector2(20.5, 4.0), "ceiling": CORRIDOR_CEILING},
	{"id": "corredor_norte_salao", "name": "Corredor norte", "kind": "corridor", "min": Vector2(12.0, 4.0), "max": Vector2(15.0, 7.0), "ceiling": CORRIDOR_CEILING},
	{"id": "corredor_escritorio_biblioteca", "name": "Corredor oeste", "kind": "corridor", "min": Vector2(1.5, 5.5), "max": Vector2(4.5, 7.5), "ceiling": CORRIDOR_CEILING},
	{"id": "corredor_biblioteca_salao", "name": "Passagem da biblioteca", "kind": "corridor", "min": Vector2(6.0, 10.5), "max": Vector2(8.0, 13.5), "ceiling": CORRIDOR_CEILING},
	{"id": "corredor_oeste_sul", "name": "Corredor sudoeste", "kind": "corridor", "min": Vector2(1.5, 16.5), "max": Vector2(4.5, 23.5), "ceiling": CORRIDOR_CEILING},
	{"id": "corredor_oeste_jantar", "name": "Corredor sudoeste", "kind": "corridor", "min": Vector2(4.5, 20.5), "max": Vector2(8.5, 23.5), "ceiling": CORRIDOR_CEILING},
	{"id": "corredor_salao_cozinha", "name": "Passagem da cozinha", "kind": "corridor", "min": Vector2(19.0, 10.0), "max": Vector2(21.0, 13.0), "ceiling": CORRIDOR_CEILING},
	{"id": "corredor_salao_jantar", "name": "Passagem do jantar", "kind": "corridor", "min": Vector2(12.0, 17.0), "max": Vector2(15.0, 19.0), "ceiling": CORRIDOR_CEILING},
	{"id": "corredor_galeria_cozinha", "name": "Corredor da galeria", "kind": "corridor", "min": Vector2(23.5, 5.0), "max": Vector2(26.5, 8.5), "ceiling": CORRIDOR_CEILING},
	{"id": "corredor_jantar_leste", "name": "Corredor sudeste", "kind": "corridor", "min": Vector2(18.5, 21.0), "max": Vector2(23.5, 24.0), "ceiling": CORRIDOR_CEILING},
	{"id": "corredor_cozinha_sul", "name": "Corredor sudeste", "kind": "corridor", "min": Vector2(23.5, 14.5), "max": Vector2(26.5, 24.0), "ceiling": CORRIDOR_CEILING},
	# Ala direita: um corredor reto com três ramais independentes (a planta tem
	# um vão branco sem nome entre os trechos; aqui ele foi simplificado).
	{"id": "ala_leste", "name": "Ala leste", "kind": "corridor", "min": Vector2(26.5, 17.0), "max": Vector2(45.5, 20.0), "ceiling": CORRIDOR_CEILING},
	{"id": "ramal_fundo", "name": "Ala leste", "kind": "corridor", "min": Vector2(31.5, 20.0), "max": Vector2(34.5, 22.0), "ceiling": CORRIDOR_CEILING},
	{"id": "ramal_hospedes", "name": "Ala leste", "kind": "corridor", "min": Vector2(39.0, 20.0), "max": Vector2(42.0, 22.0), "ceiling": CORRIDOR_CEILING},
	{"id": "ramal_banheiro", "name": "Ala leste", "kind": "corridor", "min": Vector2(42.5, 14.0), "max": Vector2(45.5, 17.0), "ceiling": CORRIDOR_CEILING},
]

## Vãos de 2 m livres (4 células) na parede de 0,5 m entre `room` e `corridor`.
const DOORS := [
	{"id": "porta_escritorio_leste", "room": "escritorio", "corridor": "corredor_norte", "min": Vector2(6.0, 1.5), "max": Vector2(6.5, 3.5)},
	{"id": "porta_escritorio_sul", "room": "escritorio", "corridor": "corredor_escritorio_biblioteca", "min": Vector2(2.0, 5.0), "max": Vector2(4.0, 5.5)},
	{"id": "porta_biblioteca_norte", "room": "biblioteca", "corridor": "corredor_escritorio_biblioteca", "min": Vector2(2.0, 7.5), "max": Vector2(4.0, 8.0)},
	{"id": "porta_biblioteca_leste", "room": "biblioteca", "corridor": "corredor_biblioteca_salao", "min": Vector2(5.5, 11.0), "max": Vector2(6.0, 13.0)},
	{"id": "porta_biblioteca_sul", "room": "biblioteca", "corridor": "corredor_oeste_sul", "min": Vector2(2.0, 16.0), "max": Vector2(4.0, 16.5)},
	{"id": "porta_galeria_oeste", "room": "galeria", "corridor": "corredor_norte", "min": Vector2(20.5, 1.5), "max": Vector2(21.0, 3.5)},
	{"id": "porta_galeria_sul", "room": "galeria", "corridor": "corredor_galeria_cozinha", "min": Vector2(24.0, 4.5), "max": Vector2(26.0, 5.0)},
	{"id": "porta_salao_norte", "room": "salao", "corridor": "corredor_norte_salao", "min": Vector2(12.5, 7.0), "max": Vector2(14.5, 7.5)},
	{"id": "porta_salao_oeste", "room": "salao", "corridor": "corredor_biblioteca_salao", "min": Vector2(8.0, 11.0), "max": Vector2(8.5, 13.0)},
	{"id": "porta_salao_leste", "room": "salao", "corridor": "corredor_salao_cozinha", "min": Vector2(18.5, 10.5), "max": Vector2(19.0, 12.5)},
	{"id": "porta_salao_sul", "room": "salao", "corridor": "corredor_salao_jantar", "min": Vector2(12.5, 16.5), "max": Vector2(14.5, 17.0)},
	{"id": "porta_cozinha_oeste", "room": "cozinha", "corridor": "corredor_salao_cozinha", "min": Vector2(21.0, 10.5), "max": Vector2(21.5, 12.5)},
	{"id": "porta_cozinha_norte", "room": "cozinha", "corridor": "corredor_galeria_cozinha", "min": Vector2(24.0, 8.5), "max": Vector2(26.0, 9.0)},
	{"id": "porta_cozinha_sul", "room": "cozinha", "corridor": "corredor_cozinha_sul", "min": Vector2(24.0, 14.0), "max": Vector2(26.0, 14.5)},
	{"id": "porta_jantar_norte", "room": "jantar", "corridor": "corredor_salao_jantar", "min": Vector2(12.5, 19.0), "max": Vector2(14.5, 19.5)},
	{"id": "porta_jantar_oeste", "room": "jantar", "corridor": "corredor_oeste_jantar", "min": Vector2(8.5, 21.0), "max": Vector2(9.0, 23.0)},
	{"id": "porta_jantar_leste", "room": "jantar", "corridor": "corredor_jantar_leste", "min": Vector2(18.0, 21.5), "max": Vector2(18.5, 23.5)},
	{"id": "porta_quarto_fundo", "room": "quarto_fundo", "corridor": "ramal_fundo", "min": Vector2(32.0, 22.0), "max": Vector2(34.0, 22.5)},
	{"id": "porta_quarto_hospedes", "room": "quarto_hospedes", "corridor": "ramal_hospedes", "min": Vector2(39.5, 22.0), "max": Vector2(41.5, 22.5)},
	{"id": "porta_banheiro", "room": "banheiro", "corridor": "ramal_banheiro", "min": Vector2(43.5, 13.5), "max": Vector2(45.5, 14.0)},
]

## Encontros abertos (sem parede) entre corredores contíguos de mesmo teto.
const JUNCTIONS := [
	{"id": "juncao_norte_salao", "a": "corredor_norte", "b": "corredor_norte_salao"},
	{"id": "juncao_sudoeste", "a": "corredor_oeste_sul", "b": "corredor_oeste_jantar"},
	{"id": "juncao_sudeste", "a": "corredor_jantar_leste", "b": "corredor_cozinha_sul"},
	{"id": "juncao_ala_leste", "a": "corredor_cozinha_sul", "b": "ala_leste"},
	{"id": "juncao_ramal_fundo", "a": "ala_leste", "b": "ramal_fundo"},
	{"id": "juncao_ramal_hospedes", "a": "ala_leste", "b": "ramal_hospedes"},
	{"id": "juncao_ramal_banheiro", "a": "ala_leste", "b": "ramal_banheiro"},
]

## Móveis grandes: cada peça é um volume oficial (movimento e tiro). Mesas têm
## tampo e pés; o vão embaixo do tampo fica aberto para tiro, e o corpo é
## barrado pela projeção do tampo (não há agachamento). Os demais móveis são
## maciços até o piso, e a apresentação precisa mostrá-los assim.
const FURNITURE := [
	{"id": "escrivaninha", "space": "escritorio", "shape": "table", "min": Vector2(1.0, 0.4), "max": Vector2(2.8, 1.2), "height": 0.76},
	{"id": "estante_escritorio", "space": "escritorio", "shape": "solid", "min": Vector2(0.0, 1.8), "max": Vector2(0.45, 4.2), "height": 2.0},
	{"id": "lareira", "space": "escritorio", "shape": "solid", "min": Vector2(3.6, 0.0), "max": Vector2(5.4, 0.5), "height": 1.3},
	{"id": "estante_biblioteca_oeste_norte", "space": "biblioteca", "shape": "solid", "min": Vector2(0.5, 8.6), "max": Vector2(1.0, 11.6), "height": 2.2},
	{"id": "estante_biblioteca_oeste_sul", "space": "biblioteca", "shape": "solid", "min": Vector2(0.5, 12.4), "max": Vector2(1.0, 15.4), "height": 2.2},
	{"id": "estante_biblioteca_leste", "space": "biblioteca", "shape": "solid", "min": Vector2(5.0, 8.4), "max": Vector2(5.5, 10.0), "height": 2.2},
	{"id": "mesa_leitura", "space": "biblioteca", "shape": "table", "min": Vector2(2.4, 12.6), "max": Vector2(3.6, 13.6), "height": 0.76},
	{"id": "banco_galeria_oeste", "space": "galeria", "shape": "solid", "min": Vector2(22.5, 0.6), "max": Vector2(24.5, 1.1), "height": 0.45},
	{"id": "banco_galeria_leste", "space": "galeria", "shape": "solid", "min": Vector2(26.5, 0.6), "max": Vector2(28.5, 1.1), "height": 0.45},
	{"id": "coluna_salao_noroeste", "space": "salao", "shape": "solid", "min": Vector2(10.15, 9.15), "max": Vector2(10.85, 9.85), "height": HALL_CEILING},
	{"id": "coluna_salao_nordeste", "space": "salao", "shape": "solid", "min": Vector2(16.15, 9.15), "max": Vector2(16.85, 9.85), "height": HALL_CEILING},
	{"id": "coluna_salao_sudoeste", "space": "salao", "shape": "solid", "min": Vector2(10.15, 14.15), "max": Vector2(10.85, 14.85), "height": HALL_CEILING},
	{"id": "coluna_salao_sudeste", "space": "salao", "shape": "solid", "min": Vector2(16.15, 14.15), "max": Vector2(16.85, 14.85), "height": HALL_CEILING},
	{"id": "pedestal", "space": "salao", "shape": "solid", "min": Vector2(13.0, 11.5), "max": Vector2(14.0, 12.5), "height": 1.1},
	{"id": "armario_cozinha", "space": "cozinha", "shape": "solid", "min": Vector2(21.5, 9.0), "max": Vector2(23.0, 9.5), "height": 2.0},
	{"id": "bancada", "space": "cozinha", "shape": "solid", "min": Vector2(27.85, 9.6), "max": Vector2(28.5, 13.4), "height": 0.95},
	{"id": "mesa_jantar", "space": "jantar", "shape": "table", "min": Vector2(11.0, 21.4), "max": Vector2(16.0, 22.6), "height": 0.78},
	{"id": "aparador", "space": "jantar", "shape": "solid", "min": Vector2(9.6, 24.0), "max": Vector2(11.6, 24.5), "height": 0.9},
	{"id": "cama_fundo", "space": "quarto_fundo", "shape": "solid", "min": Vector2(31.2, 26.3), "max": Vector2(33.0, 28.5), "height": 0.6},
	{"id": "armario_fundo", "space": "quarto_fundo", "shape": "solid", "min": Vector2(34.9, 24.0), "max": Vector2(35.5, 26.0), "height": 2.0},
	{"id": "criado_fundo", "space": "quarto_fundo", "shape": "solid", "min": Vector2(33.2, 28.0), "max": Vector2(33.7, 28.5), "height": 0.55},
	{"id": "cama_hospedes", "space": "quarto_hospedes", "shape": "solid", "min": Vector2(40.8, 24.2), "max": Vector2(43.0, 25.8), "height": 0.6},
	{"id": "armario_hospedes", "space": "quarto_hospedes", "shape": "solid", "min": Vector2(38.0, 25.0), "max": Vector2(38.6, 27.0), "height": 2.0},
	{"id": "criado_hospedes", "space": "quarto_hospedes", "shape": "solid", "min": Vector2(42.5, 26.0), "max": Vector2(43.0, 26.5), "height": 0.55},
	{"id": "banheira", "space": "banheiro", "shape": "solid", "min": Vector2(42.5, 10.0), "max": Vector2(44.2, 10.8), "height": 0.6},
	{"id": "vaso", "space": "banheiro", "shape": "solid", "min": Vector2(44.85, 10.0), "max": Vector2(45.5, 10.6), "height": 0.45},
	{"id": "pia", "space": "banheiro", "shape": "solid", "min": Vector2(45.0, 11.4), "max": Vector2(45.5, 12.2), "height": 0.85},
]
const TABLE_TOP_THICKNESS := 0.06
const TABLE_LEG_SIZE := 0.08

## Oito spawns candidatos, um por cômodo (o Salão, eixo da casa, não tem). A
## ordem importa: `AuthoritativeWorld` ocupa do primeiro livre em diante, então
## uma sala de quatro usa os quatro primeiros, espalhados pelos cantos da casa.
## `face` é o ponto para onde o jogador começa olhando (a porta do cômodo).
const SPAWNS := [
	{"id": "spawn_escritorio", "space": "escritorio", "position": Vector2(1.6, 4.0), "face": Vector2(6.25, 2.5)},
	{"id": "spawn_hospedes", "space": "quarto_hospedes", "position": Vector2(39.8, 26.2), "face": Vector2(40.5, 22.25)},
	{"id": "spawn_galeria", "space": "galeria", "position": Vector2(28.8, 3.4), "face": Vector2(20.75, 2.5)},
	{"id": "spawn_jantar", "space": "jantar", "position": Vector2(16.9, 20.5), "face": Vector2(13.5, 19.25)},
	{"id": "spawn_biblioteca", "space": "biblioteca", "position": Vector2(4.0, 15.0), "face": Vector2(3.0, 8.0)},
	{"id": "spawn_cozinha", "space": "cozinha", "position": Vector2(22.6, 12.9), "face": Vector2(25.0, 8.75)},
	{"id": "spawn_fundo", "space": "quarto_fundo", "position": Vector2(31.5, 23.6), "face": Vector2(33.0, 22.25)},
	{"id": "spawn_banheiro", "space": "banheiro", "position": Vector2(43.5, 12.3), "face": Vector2(44.5, 13.75)},
]

## Pontos candidatos de pickups. Os índices seguem o contrato atual de
## `CombatAuthority`: 0..3 armas comuns, 4..7 caixas de munição. Nenhuma arma
## fica num cômodo com spawn de uma sala de quatro jogadores.
const PICKUPS := [
	{"id": "weapon_0", "type": "weapon", "space": "biblioteca", "position": Vector2(1.8, 12.0)},
	{"id": "weapon_1", "type": "weapon", "space": "cozinha", "position": Vector2(26.5, 12.8)},
	{"id": "weapon_2", "type": "weapon", "space": "salao", "position": Vector2(15.5, 12.0)},
	{"id": "weapon_3", "type": "weapon", "space": "ala_leste", "position": Vector2(36.8, 18.5)},
	{"id": "ammo_0", "type": "ammo", "space": "escritorio", "position": Vector2(4.8, 4.0)},
	{"id": "ammo_1", "type": "ammo", "space": "galeria", "position": Vector2(22.2, 3.8)},
	{"id": "ammo_2", "type": "ammo", "space": "jantar", "position": Vector2(10.0, 20.2)},
	{"id": "ammo_3", "type": "ammo", "space": "quarto_fundo", "position": Vector2(34.4, 27.2)},
]

# --- Consultas -----------------------------------------------------------------

static func space(space_id: String) -> Dictionary:
	for entry in SPACES:
		if str(entry["id"]) == space_id:
			return entry
	return {}

static func space_rect(space_id: String) -> Rect2:
	var entry := space(space_id)
	if entry.is_empty():
		return Rect2()
	return Rect2(entry["min"], (entry["max"] as Vector2) - (entry["min"] as Vector2))

static func rooms() -> Array:
	return SPACES.filter(func(entry): return str(entry["kind"]) == "room")

## Espaço (cômodo ou corredor) que contém o ponto XZ, ou vazio. Vãos de porta
## pertencem ao cômodo.
static func space_at(position: Vector3) -> Dictionary:
	var point := Vector2(position.x, position.z)
	for entry in SPACES:
		var rect := Rect2(entry["min"], (entry["max"] as Vector2) - (entry["min"] as Vector2))
		if _contains(rect, point):
			return entry
	for door in DOORS:
		if _contains(Rect2(door["min"], (door["max"] as Vector2) - (door["min"] as Vector2)), point):
			return space(str(door["room"]))
	return {}

static func spawn_points() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for entry in SPAWNS:
		var point: Vector2 = entry["position"]
		result.append(Vector3(point.x, BODY_CENTER_HEIGHT, point.y))
	return result

## Yaw inicial olhando para `face` (yaw 0 olha para -Z).
static func spawn_yaw_at(index: int) -> float:
	var entry: Dictionary = SPAWNS[index]
	var from: Vector2 = entry["position"]
	var to: Vector2 = entry["face"]
	return atan2(-(to.x - from.x), -(to.y - from.y))

static func pickup_positions() -> Array:
	var result: Array = []
	for entry in PICKUPS:
		var point: Vector2 = entry["position"]
		result.append(Vector3(point.x, PICKUP_HEIGHT, point.y))
	return result

## Retângulo XZ que contém todo o piso livre (cômodos, corredores e vãos).
static func walkable_bounds() -> Rect2:
	var result := Rect2(SPACES[0]["min"], Vector2.ZERO)
	for entry in SPACES:
		result = result.expand(entry["min"]).expand(entry["max"])
	return result

# --- Geometria derivada ----------------------------------------------------------

static var _blockers: Array = []
static var _grid_origin := Vector2i.ZERO
static var _grid_size := Vector2i.ZERO
static var _walkable := PackedByteArray()

## Todos os volumes oficiais, na ordem: paredes, vergas, tetos, móveis. Cada um
## tem `id`, `kind`, `center`, `size` e, quando se aplica, `space`.
static func blockers() -> Array:
	if _blockers.is_empty():
		_build()
	return _blockers

static func is_walkable_cell(cell: Vector2i) -> bool:
	if _walkable.is_empty():
		_build()
	var local := cell - _grid_origin
	if local.x < 0 or local.y < 0 or local.x >= _grid_size.x or local.y >= _grid_size.y:
		return false
	return _walkable[local.y * _grid_size.x + local.x] == 1

static func cell_of(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL + 0.0001), floori(point.y / CELL + 0.0001))

static func _build() -> void:
	var bounds := walkable_bounds()
	# Uma célula de margem para o anel de paredes externo.
	_grid_origin = cell_of(bounds.position) - Vector2i.ONE
	var far := cell_of(bounds.end) + Vector2i.ONE
	_grid_size = far - _grid_origin + Vector2i.ONE
	_walkable = PackedByteArray()
	_walkable.resize(_grid_size.x * _grid_size.y)
	for entry in SPACES:
		_mark(entry["min"], entry["max"])
	for door in DOORS:
		_mark(door["min"], door["max"])
	var solid := PackedByteArray()
	solid.resize(_walkable.size())
	for y in _grid_size.y:
		for x in _grid_size.x:
			if _walkable[y * _grid_size.x + x] == 1:
				continue
			if _touches_walkable(x, y):
				solid[y * _grid_size.x + x] = 1
	var result: Array = []
	for box in _merge(solid):
		var cell_min: Vector2i = box[0] + _grid_origin
		var cell_max: Vector2i = box[1] + _grid_origin
		var min_point := Vector2(cell_min) * CELL
		var max_point := Vector2(cell_max + Vector2i.ONE) * CELL
		result.append(_box("wall_x%d_z%d" % [cell_min.x, cell_min.y], "wall", min_point, max_point, 0.0, WALL_TOP, ""))
	for door in DOORS:
		result.append(_box("verga_%s" % str(door["id"]).trim_prefix("porta_"), "lintel", door["min"], door["max"], DOOR_HEIGHT, WALL_TOP, str(door["room"])))
	for entry in SPACES:
		# A laje entra até o meio da parede em volta: nenhum tiro sobe por uma
		# fresta entre laje e parede, e a borda fica escondida dentro da parede
		# (sem face coplanar com a parede do cômodo vizinho).
		var ceiling := float(entry["ceiling"])
		var margin := Vector2(CELL, CELL) * 0.5
		result.append(_box("teto_%s" % str(entry["id"]), "ceiling", (entry["min"] as Vector2) - margin, (entry["max"] as Vector2) + margin,
			ceiling, ceiling + SLAB_THICKNESS, str(entry["id"])))
	for item in FURNITURE:
		result.append_array(_furniture_parts(item))
	_blockers = result

static func _furniture_parts(item: Dictionary) -> Array:
	var id := str(item["id"])
	var min_point: Vector2 = item["min"]
	var max_point: Vector2 = item["max"]
	var height := float(item["height"])
	var space_id := str(item["space"])
	if str(item["shape"]) != "table":
		return [_box(id, "furniture", min_point, max_point, 0.0, height, space_id)]
	var parts := [_box(id + "_tampo", "furniture", min_point, max_point, height - TABLE_TOP_THICKNESS, height, space_id)]
	var leg := Vector2(TABLE_LEG_SIZE, TABLE_LEG_SIZE)
	var corners := [min_point, Vector2(max_point.x - leg.x, min_point.y), Vector2(min_point.x, max_point.y - leg.y), max_point - leg]
	for index in corners.size():
		var corner: Vector2 = corners[index]
		parts.append(_box("%s_pe%d" % [id, index], "furniture", corner, corner + leg, 0.0, height - TABLE_TOP_THICKNESS, space_id))
	return parts

static func _box(id: String, kind: String, min_point: Vector2, max_point: Vector2, bottom: float, top: float, space_id: String) -> Dictionary:
	var center := (min_point + max_point) * 0.5
	var size := max_point - min_point
	return {"id": id, "kind": kind, "space": space_id,
		"center": Vector3(center.x, (bottom + top) * 0.5, center.y),
		"size": Vector3(size.x, top - bottom, size.y)}

static func _mark(min_point: Vector2, max_point: Vector2) -> void:
	var first := cell_of(min_point) - _grid_origin
	var last := cell_of(max_point) - _grid_origin - Vector2i.ONE
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			_walkable[y * _grid_size.x + x] = 1

static func _touches_walkable(x: int, y: int) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var nx: int = x + dx
			var ny: int = y + dy
			if nx < 0 or ny < 0 or nx >= _grid_size.x or ny >= _grid_size.y:
				continue
			if _walkable[ny * _grid_size.x + nx] == 1:
				return true
	return false

## Fusão gulosa de células sólidas em retângulos (linha a linha, depois para
## baixo enquanto a largura inteira continuar sólida). Determinística.
static func _merge(solid: PackedByteArray) -> Array:
	var used := PackedByteArray()
	used.resize(solid.size())
	var boxes: Array = []
	for y in _grid_size.y:
		for x in _grid_size.x:
			var index := y * _grid_size.x + x
			if solid[index] == 0 or used[index] == 1:
				continue
			var end_x := x
			while end_x + 1 < _grid_size.x and solid[y * _grid_size.x + end_x + 1] == 1 and used[y * _grid_size.x + end_x + 1] == 0:
				end_x += 1
			var end_y := y
			while end_y + 1 < _grid_size.y:
				var row_ok := true
				for scan in range(x, end_x + 1):
					var next := (end_y + 1) * _grid_size.x + scan
					if solid[next] == 0 or used[next] == 1:
						row_ok = false
						break
				if not row_ok:
					break
				end_y += 1
			for fill_y in range(y, end_y + 1):
				for fill_x in range(x, end_x + 1):
					used[fill_y * _grid_size.x + fill_x] = 1
			boxes.append([Vector2i(x, y), Vector2i(end_x, end_y)])
	return boxes

static func _contains(rect: Rect2, point: Vector2) -> bool:
	return point.x >= rect.position.x and point.x <= rect.end.x and point.y >= rect.position.y and point.y <= rect.end.y
