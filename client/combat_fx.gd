class_name CombatFx
extends Node3D

## Efeitos breves de combate: clarão de disparo, impacto, sumiço de pickup,
## eliminação e os sons correspondentes. Só apresentação: cada chamada vem de
## um evento oficial já recebido pela `ArenaView` (disparo público, confirmação
## privada de acerto, estado privado do inventário, recusa da própria ação,
## pickups e eliminações públicas). Nenhum nó tem colisão, nada toca na câmera
## nem na mira, e todo efeito some sozinho em menos de 1 s.
##
## `events` guarda os últimos efeitos disparados, para os testes conferirem que
## cada evento produz o efeito certo (e só ele).

## Clarões fracos e curtos: nada de flash de tela.
const FLASH_SECONDS := 0.06
const FLASH_LIGHT_ENERGY := 0.9
const FLASH_LIGHT_RANGE := 2.5
const IMPACT_SECONDS := 0.18
const IMPACT_GROWTH := 2.2
const IMPACT_ALPHA := 0.6
const VANISH_SECONDS := 0.35
const ELIMINATION_SECONDS := 0.7
const MAX_EVENTS := 64
## Volumes moderados; o disparo alheio atenua com a distância.
const UI_VOLUME_DB := -8.0
const WORLD_VOLUME_DB := -4.0
const WORLD_MAX_DISTANCE := 40.0

const WALL_IMPACT := Color(0.85, 0.8, 0.7)
const PLAYER_IMPACT := Color(0.7, 0.22, 0.2)
const SMOKE := Color(0.35, 0.36, 0.4)

var events: Array = []
var _ui_players: Array = []
var _world_players: Array = []
var _next_ui := 0
var _next_world := 0

func _ready() -> void:
	name = "CombatFx"
	for index in 4:
		var player := AudioStreamPlayer.new()
		player.volume_db = UI_VOLUME_DB
		add_child(player)
		_ui_players.append(player)
	for index in 6:
		var player := AudioStreamPlayer3D.new()
		player.volume_db = WORLD_VOLUME_DB
		player.max_distance = WORLD_MAX_DISTANCE
		player.unit_size = 6.0
		add_child(player)
		_world_players.append(player)

# --- Sons ------------------------------------------------------------------------

## Som do próprio jogador (não posicional).
func play_ui(sound_name: String) -> void:
	_log(sound_name, Vector3.ZERO)
	var player: AudioStreamPlayer = _ui_players[_next_ui]
	_next_ui = (_next_ui + 1) % _ui_players.size()
	player.stream = SfxBank.stream(sound_name)
	player.play()

## Som de um evento público no mundo, na posição oficial do evento.
func play_world(sound_name: String, position: Vector3) -> void:
	_log(sound_name + "@world", position)
	var player: AudioStreamPlayer3D = _world_players[_next_world]
	_next_world = (_next_world + 1) % _world_players.size()
	player.stream = SfxBank.stream(sound_name)
	player.global_position = position
	player.play()

# --- Efeitos visuais ------------------------------------------------------------

## Clarão pequeno na boca da arma de outro jogador (origem oficial do tiro).
func muzzle_flash(origin: Vector3, direction: Vector3) -> void:
	_log("muzzle_flash", origin)
	var at := origin + direction.normalized() * 0.45
	var flash := _blob(at, 0.07, Color(1.0, 0.85, 0.55), 1.6)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.5)
	light.light_energy = FLASH_LIGHT_ENERGY
	light.omni_range = FLASH_LIGHT_RANGE
	light.shadow_enabled = false
	flash.add_child(light)
	_expire(flash, FLASH_SECONDS)

## Marca de impacto no fim oficial do tiro. `hit_player` é público no evento de
## disparo; quem foi atingido não é.
func impact(point: Vector3, hit_player: bool) -> void:
	_log("impact_player" if hit_player else "impact_wall", point)
	var puff := _blob(point, 0.06, PLAYER_IMPACT if hit_player else WALL_IMPACT, 0.4)
	(puff.material_override as StandardMaterial3D).albedo_color.a = IMPACT_ALPHA
	var tween := puff.create_tween()
	tween.set_parallel(true)
	tween.tween_property(puff, "scale", Vector3.ONE * IMPACT_GROWTH, IMPACT_SECONDS)
	tween.tween_property(puff.material_override, "albedo_color:a", 0.0, IMPACT_SECONDS)
	_expire(puff, IMPACT_SECONDS)

## Anel curto onde um pickup deixou de estar disponível (estado público).
func pickup_vanish(point: Vector3, color: Color) -> void:
	_log("pickup_vanish", point)
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.3
	mesh.outer_radius = 0.36
	ring.mesh = mesh
	ring.material_override = _material(color, 1.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = point
	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * 2.2, VANISH_SECONDS)
	tween.tween_property(ring.material_override, "albedo_color:a", 0.0, VANISH_SECONDS)
	_expire(ring, VANISH_SECONDS)

## Fumaça neutra onde um jogador foi eliminado (evento público). Mesma cor para
## qualquer papel.
func elimination(point: Vector3) -> void:
	_log("elimination", point)
	for index in 5:
		var offset := Vector3(sin(index * 1.3) * 0.25, -0.6 + index * 0.3, cos(index * 1.3) * 0.25)
		var smoke := _blob(point + offset, 0.22, SMOKE, 0.0)
		var tween := smoke.create_tween()
		tween.set_parallel(true)
		tween.tween_property(smoke, "position:y", smoke.position.y + 0.6, ELIMINATION_SECONDS)
		tween.tween_property(smoke, "scale", Vector3.ONE * 1.8, ELIMINATION_SECONDS)
		tween.tween_property(smoke.material_override, "albedo_color:a", 0.0, ELIMINATION_SECONDS)
		_expire(smoke, ELIMINATION_SECONDS)
	play_world("elimination", point)

## Rodada nova ou limpeza: nenhum efeito antigo sobra na cena.
func clear() -> void:
	for child in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			continue
		child.queue_free()

func has_event(kind: String) -> bool:
	for entry in events:
		if str(entry["kind"]) == kind:
			return true
	return false

func count_event(kind: String) -> int:
	var total := 0
	for entry in events:
		if str(entry["kind"]) == kind:
			total += 1
	return total

# --- Peças -----------------------------------------------------------------------

func _log(kind: String, position: Vector3) -> void:
	events.append({"kind": kind, "position": position})
	while events.size() > MAX_EVENTS:
		events.pop_front()

func _blob(point: Vector3, radius: float, color: Color, glow: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	node.mesh = mesh
	node.material_override = _material(color, glow)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_position = point
	return node

func _material(color: Color, glow: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color, 0.85)
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	return material

func _expire(node: Node, seconds: float) -> void:
	get_tree().create_timer(seconds).timeout.connect(func():
		if is_instance_valid(node):
			node.queue_free())
