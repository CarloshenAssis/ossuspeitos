class_name MenuSpinner
extends Control

## Indicador de progresso do menu: um arco dourado que gira devagar. Com
## "reduzir movimento", fica parado (o texto do estado continua dizendo o que
## está acontecendo).

var animate := true
var _angle := 0.0

func _init() -> void:
	custom_minimum_size = Vector2(30, 30)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if not visible or not animate:
		return
	_angle = wrapf(_angle + delta * 4.0, 0.0, TAU)
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.4
	draw_arc(center, radius, 0.0, TAU, 32, Color(MenuTheme.GOLD_SOFT, 0.35), 3.0, true)
	draw_arc(center, radius, _angle, _angle + PI * 0.6, 16, MenuTheme.GOLD, 3.0, true)
