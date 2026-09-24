class_name MenuBackdrop
extends Control

## Fundo do menu (fase 7): uma parede da mansão desenhada no próprio Godot
## (papel de parede listrado com florões, lambri de madeira com filete
## dourado, dois retratos em moldura dourada, uma porta entreaberta com luz e
## um abajur aceso). Vetorial e barato: um `_draw` redesenhado só ao mudar de
## tamanho, mais a luz do abajur como gradiente radial. Com "reduzir
## movimento", a luz não oscila.

var reduce_motion := false
var _glow: TextureRect
var _vignette: TextureRect
var _time := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow = TextureRect.new()
	_glow.texture = _radial(Color(1.0, 0.78, 0.45, 0.42), Color(1.0, 0.7, 0.35, 0.0))
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glow)
	_vignette = TextureRect.new()
	_vignette.texture = _radial(Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.78), 0.35)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)
	resized.connect(_layout)
	_layout()

static func _radial(inner: Color, outer: Color, start: float = 0.0) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([start, 1.0])
	gradient.colors = PackedColorArray([inner, outer])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	return texture

func _layout() -> void:
	var lamp := _lamp_position()
	var glow_size := Vector2(size.y * 1.3, size.y * 1.3)
	_glow.position = lamp - glow_size * 0.5
	_glow.size = glow_size
	queue_redraw()

func _lamp_position() -> Vector2:
	return Vector2(size.x * 0.78, size.y * 0.52)

func _process(delta: float) -> void:
	if reduce_motion:
		_glow.modulate.a = 1.0
		return
	_time += delta
	# Oscilação lenta e pequena da chama (nada de piscar).
	_glow.modulate.a = 0.92 + 0.06 * sin(_time * 1.7) + 0.02 * sin(_time * 4.3)

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var wainscot_top := h * 0.68
	# Papel de parede: listras verticais e florões discretos.
	draw_rect(Rect2(0, 0, w, wainscot_top), MenuTheme.WALLPAPER)
	var stripe := maxf(18.0, w / 48.0)
	var x := 0.0
	var index := 0
	while x < w:
		if index % 2 == 0:
			draw_rect(Rect2(x, 0, stripe * 0.55, wainscot_top), MenuTheme.WALLPAPER_STRIPE)
		x += stripe
		index += 1
	var motif := Color(MenuTheme.GOLD_SOFT, 0.10)
	var row := 0
	var y := stripe * 1.4
	while y < wainscot_top - stripe:
		var offset := stripe * (0.55 if row % 2 == 0 else 1.55)
		var mx := offset
		while mx < w:
			_draw_fleur(Vector2(mx, y), stripe * 0.28, motif)
			mx += stripe * 2.0
		y += stripe * 1.6
		row += 1
	# Sanca escura no topo.
	draw_rect(Rect2(0, 0, w, h * 0.035), MenuTheme.WOOD_DARK)
	draw_line(Vector2(0, h * 0.035), Vector2(w, h * 0.035), Color(MenuTheme.GOLD_SOFT, 0.5), 1.0)
	# Retratos (à direita, longe do cartão do menu).
	_draw_portrait(Rect2(w * 0.56, h * 0.13, h * 0.20, h * 0.27))
	_draw_portrait(Rect2(w * 0.86, h * 0.10, h * 0.22, h * 0.30))
	# Porta entreaberta com luz do corredor.
	_draw_door(Rect2(w * 0.63, h * 0.30, h * 0.26, h * 0.62))
	# Lambri: madeira com painéis e filete dourado.
	draw_rect(Rect2(0, wainscot_top, w, h - wainscot_top), MenuTheme.WOOD)
	draw_line(Vector2(0, wainscot_top), Vector2(w, wainscot_top), MenuTheme.GOLD_SOFT, 2.0)
	draw_rect(Rect2(0, wainscot_top + 2, w, h * 0.02), MenuTheme.WOOD_LIGHT)
	var panel_w := maxf(90.0, w / 9.0)
	var px := panel_w * 0.15
	while px < w:
		var panel := Rect2(px, wainscot_top + h * 0.05, panel_w * 0.8, h - wainscot_top - h * 0.11)
		draw_rect(panel, MenuTheme.WOOD_DARK, false, 2.0)
		draw_rect(panel.grow(-4), Color(MenuTheme.WOOD_LIGHT, 0.5), false, 1.0)
		px += panel_w
	draw_rect(Rect2(0, h * 0.965, w, h * 0.035), MenuTheme.INK)
	# Abajur sobre um aparador (a luz é o gradiente `_glow`).
	var lamp := _lamp_position()
	var base_y := wainscot_top - h * 0.01
	draw_rect(Rect2(lamp.x - h * 0.16, base_y, h * 0.32, h * 0.03), MenuTheme.WOOD_LIGHT)
	draw_rect(Rect2(lamp.x - h * 0.006, lamp.y + h * 0.02, h * 0.012, base_y - lamp.y - h * 0.02), MenuTheme.GOLD_SOFT)
	var shade := PackedVector2Array([
		Vector2(lamp.x - h * 0.035, lamp.y - h * 0.06), Vector2(lamp.x + h * 0.035, lamp.y - h * 0.06),
		Vector2(lamp.x + h * 0.06, lamp.y + h * 0.025), Vector2(lamp.x - h * 0.06, lamp.y + h * 0.025)])
	draw_colored_polygon(shade, Color("#E8C98E"))
	draw_polyline(PackedVector2Array([shade[0], shade[1], shade[2], shade[3], shade[0]]), Color(MenuTheme.GOLD_SOFT, 0.9), 1.5)

func _draw_fleur(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center, radius * 0.45, color)
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		draw_circle(center + Vector2(radius, 0).rotated(angle), radius * 0.3, color)

func _draw_portrait(rect: Rect2) -> void:
	draw_rect(rect.grow(6), Color(0, 0, 0, 0.35))
	draw_rect(rect, MenuTheme.GOLD_SOFT)
	draw_rect(rect.grow(-3), MenuTheme.GOLD)
	var canvas := rect.grow(-rect.size.x * 0.1)
	draw_rect(canvas, Color("#1E1714"))
	# Silhueta sem rosto: ninguém sabe quem é quem.
	var head := canvas.position + Vector2(canvas.size.x * 0.5, canvas.size.y * 0.38)
	draw_circle(head, canvas.size.x * 0.17, Color("#0F0B09"))
	var shoulders := PackedVector2Array([
		Vector2(canvas.position.x + canvas.size.x * 0.12, canvas.end.y),
		Vector2(canvas.position.x + canvas.size.x * 0.3, canvas.position.y + canvas.size.y * 0.62),
		Vector2(canvas.position.x + canvas.size.x * 0.7, canvas.position.y + canvas.size.y * 0.62),
		Vector2(canvas.position.x + canvas.size.x * 0.88, canvas.end.y)])
	draw_colored_polygon(shoulders, Color("#0F0B09"))

func _draw_door(rect: Rect2) -> void:
	draw_rect(rect.grow(5), MenuTheme.WOOD_DARK)
	draw_rect(rect, Color("#2E1E14"))
	# Fresta de luz do corredor, à esquerda da folha.
	var gap := Rect2(rect.position.x, rect.position.y, rect.size.x * 0.12, rect.size.y)
	draw_rect(gap, Color(0.95, 0.72, 0.4, 0.28))
	var leaf := Rect2(rect.position.x + rect.size.x * 0.12, rect.position.y, rect.size.x * 0.88, rect.size.y)
	draw_rect(leaf, MenuTheme.WOOD)
	for part in [0.08, 0.55]:
		draw_rect(Rect2(leaf.position.x + leaf.size.x * 0.14, leaf.position.y + leaf.size.y * part, leaf.size.x * 0.72, leaf.size.y * 0.37), MenuTheme.WOOD_DARK, false, 2.0)
	draw_circle(Vector2(leaf.position.x + leaf.size.x * 0.12, leaf.position.y + leaf.size.y * 0.52), rect.size.x * 0.03, MenuTheme.GOLD)
