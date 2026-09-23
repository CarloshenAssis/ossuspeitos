class_name Crosshair
extends Control

## Mira de quatro traços finos com vão central, ancorada ao centro real da tela
## (funciona em qualquer resolução). O acerto é um X curto no mesmo ponto,
## disparado só pela confirmação oficial do servidor (`combat_hit_confirmed`).

const GAP := 4.0
const TICK := 6.0
const WIDTH := 2.0
const HIT_SECONDS := 0.16

var hit_strength := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2.ZERO

func show_hit() -> void:
	hit_strength = 1.0
	queue_redraw()
	var tween := create_tween()
	tween.tween_method(func(value: float): hit_strength = value; queue_redraw(), 1.0, 0.0, HIT_SECONDS)

func _draw() -> void:
	var shadow := Color(0, 0, 0, 0.55)
	var ink := HudStyle.BONE
	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var start: Vector2 = direction * GAP
		var finish: Vector2 = direction * (GAP + TICK)
		draw_line(start, finish, shadow, WIDTH + 2.0)
		draw_line(start, finish, ink, WIDTH)
	if hit_strength > 0.0:
		var hit := Color(1, 1, 1, hit_strength)
		for diagonal in [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
			var start: Vector2 = diagonal.normalized() * GAP
			var finish: Vector2 = diagonal.normalized() * (GAP + 8.0)
			draw_line(start, finish, Color(0, 0, 0, 0.6 * hit_strength), WIDTH + 2.0)
			draw_line(start, finish, hit, WIDTH)
