class_name MenuTheme
extends RefCounted

## Identidade visual do menu (fase 7): madeira escura, papel de parede
## envelhecido, vinho, dourado discreto e creme, tirados da paleta da mansão.
## Tudo construído no Godot (StyleBoxFlat, gradientes e desenho vetorial); não
## há imagem nem fonte externa. O título usa uma fonte serifada do sistema
## (`SystemFont`), sem arquivo empacotado: onde nenhuma existir (Web), cai na
## fonte padrão do Godot.

const INK := Color("#0D0907")
const WOOD_DARK := Color("#1B110C")
const WOOD := Color("#2A1A12")
const WOOD_LIGHT := Color("#3A2519")
const WALLPAPER := Color("#35261F")
const WALLPAPER_STRIPE := Color("#3E2C23")
const WINE := Color("#5B1E24")
const WINE_LIGHT := Color("#7A2B32")
const GOLD := Color("#C19A55")
const GOLD_SOFT := Color("#8D7040")
const CREAM := Color("#EFE5D0")
const PARCHMENT := Color("#D8CBB0")
const MUTED := Color("#B5A58C")
const ERROR := Color("#E8A08E")
const OK := Color("#B9D3A8")
const CARD := Color(0.075, 0.048, 0.035, 0.94)

## Tamanhos na base 960×540 (o `canvas_items` escala o resto).
const TITLE_SIZE := 50
const SUBTITLE_SIZE := 17
const HEADING_SIZE := 26
const BODY_SIZE := 16
const BUTTON_SIZE := 17
const SMALL_SIZE := 14
const BUTTON_HEIGHT := 40.0

static var _theme: Theme
static var _serif: Font

static func serif() -> Font:
	if _serif == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Book Antiqua", "Garamond", "DejaVu Serif", "Liberation Serif", "Noto Serif", "serif"])
		font.font_weight = 600
		_serif = font
	return _serif

static func box(background: Color, border: Color = Color(0, 0, 0, 0), border_width: int = 0, radius: int = 3, padding: Vector2 = Vector2(14, 8)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding.x
	style.content_margin_right = padding.x
	style.content_margin_top = padding.y
	style.content_margin_bottom = padding.y
	style.anti_aliasing = true
	return style

## Foco de teclado: contorno creme bem visível, por fora do botão.
static func focus_box() -> StyleBoxFlat:
	var style := box(Color(0, 0, 0, 0), CREAM, 2, 4)
	style.expand_margin_left = 3
	style.expand_margin_right = 3
	style.expand_margin_top = 3
	style.expand_margin_bottom = 3
	return style

static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = BODY_SIZE
	# Botões: madeira com filete dourado; passar o mouse clareia; pressionado é vinho.
	t.set_stylebox("normal", "Button", box(WOOD, GOLD_SOFT, 1))
	t.set_stylebox("hover", "Button", box(WOOD_LIGHT, GOLD, 1))
	t.set_stylebox("pressed", "Button", box(WINE, GOLD, 1))
	t.set_stylebox("disabled", "Button", box(Color(WOOD, 0.55), Color(GOLD_SOFT, 0.35), 1))
	t.set_stylebox("focus", "Button", focus_box())
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", CREAM)
	t.set_color("font_pressed_color", "Button", CREAM)
	t.set_color("font_focus_color", "Button", CREAM)
	t.set_color("font_disabled_color", "Button", Color(MUTED, 0.55))
	t.set_font_size("font_size", "Button", BUTTON_SIZE)
	# Ação principal: vinho com dourado (variação "PrimaryButton").
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", box(WINE, GOLD, 1))
	t.set_stylebox("hover", "PrimaryButton", box(WINE_LIGHT, GOLD, 2))
	t.set_stylebox("pressed", "PrimaryButton", box(WINE.darkened(0.25), GOLD, 2))
	t.set_stylebox("disabled", "PrimaryButton", box(Color(WINE, 0.45), Color(GOLD_SOFT, 0.4), 1))
	t.set_stylebox("focus", "PrimaryButton", focus_box())
	# Campos de texto: fundo quase preto, borda dourada que acende no foco.
	t.set_stylebox("normal", "LineEdit", box(INK, GOLD_SOFT, 1, 3, Vector2(10, 7)))
	t.set_stylebox("focus", "LineEdit", box(INK, CREAM, 2, 3, Vector2(10, 7)))
	t.set_stylebox("read_only", "LineEdit", box(Color(INK, 0.6), Color(GOLD_SOFT, 0.4), 1, 3, Vector2(10, 7)))
	t.set_color("font_color", "LineEdit", CREAM)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.6))
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(WINE_LIGHT, 0.8))
	t.set_font_size("font_size", "LineEdit", BODY_SIZE)
	t.set_color("font_color", "Label", CREAM)
	t.set_font_size("font_size", "Label", BODY_SIZE)
	# Caixa de seleção e opções.
	for type_name in ["CheckBox", "OptionButton"]:
		t.set_stylebox("normal", type_name, box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 3, Vector2(6, 6)))
		t.set_stylebox("hover", type_name, box(Color(WOOD_LIGHT, 0.6), Color(0, 0, 0, 0), 0, 3, Vector2(6, 6)))
		t.set_stylebox("pressed", type_name, box(Color(WOOD_LIGHT, 0.6), Color(0, 0, 0, 0), 0, 3, Vector2(6, 6)))
		t.set_stylebox("focus", type_name, focus_box())
		t.set_color("font_color", type_name, CREAM)
		t.set_color("font_hover_color", type_name, CREAM)
		t.set_color("font_pressed_color", type_name, CREAM)
		t.set_color("font_focus_color", type_name, CREAM)
		t.set_font_size("font_size", type_name, BODY_SIZE)
	# Caixa de marcação visível no fundo escuro: quadro dourado; marcada, preenchida.
	t.set_icon("unchecked", "CheckBox", _check_icon(false))
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_icon("unchecked_disabled", "CheckBox", _check_icon(false))
	t.set_icon("checked_disabled", "CheckBox", _check_icon(true))
	t.set_constant("h_separation", "CheckBox", 10)
	t.set_stylebox("normal", "OptionButton", box(INK, GOLD_SOFT, 1, 3, Vector2(10, 6)))
	t.set_stylebox("hover", "OptionButton", box(WOOD, GOLD, 1, 3, Vector2(10, 6)))
	# Controle deslizante: trilho escuro, preenchimento dourado.
	t.set_stylebox("slider", "HSlider", box(INK, GOLD_SOFT, 1, 3, Vector2(0, 3)))
	t.set_stylebox("grabber_area", "HSlider", box(GOLD_SOFT, Color(0, 0, 0, 0), 0, 3, Vector2(0, 3)))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(GOLD, Color(0, 0, 0, 0), 0, 3, Vector2(0, 3)))
	t.set_stylebox("focus", "HSlider", focus_box())
	# Rolagem discreta.
	t.set_stylebox("scroll", "VScrollBar", box(Color(INK, 0.6), Color(0, 0, 0, 0), 0, 3, Vector2(3, 3)))
	t.set_stylebox("grabber", "VScrollBar", box(GOLD_SOFT, Color(0, 0, 0, 0), 0, 3, Vector2(3, 3)))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(GOLD, Color(0, 0, 0, 0), 0, 3, Vector2(3, 3)))
	t.set_stylebox("panel", "PopupMenu", box(WOOD_DARK, GOLD_SOFT, 1))
	t.set_color("font_color", "PopupMenu", CREAM)
	t.set_color("font_hover_color", "PopupMenu", CREAM)
	t.set_stylebox("hover", "PopupMenu", box(WINE, Color(0, 0, 0, 0), 0))
	t.set_stylebox("separator", "HSeparator", box(Color(GOLD_SOFT, 0.5), Color(0, 0, 0, 0), 0, 0, Vector2(0, 0)))
	t.set_constant("separation", "HSeparator", 10)
	_theme = t
	return t

## Ícone de 20 px da caixa de marcação, desenhado em pixels (sem arquivo).
static func _check_icon(checked: bool) -> ImageTexture:
	var n := 20
	var image := Image.create(n, n, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var edge := x < 2 or y < 2 or x >= n - 2 or y >= n - 2
			if edge:
				image.set_pixel(x, y, GOLD)
			elif checked:
				image.set_pixel(x, y, WINE)
			else:
				image.set_pixel(x, y, INK)
	if checked:
		# Visto creme: perna curta descendo e perna longa subindo.
		for i in 5:
			for t in 2:
				image.set_pixel(5 + i, 9 + i + t, CREAM)
		for i in 8:
			for t in 2:
				image.set_pixel(9 + i, 13 - i + t - 1, CREAM)
	return ImageTexture.create_from_image(image)

## Moldura do cartão central: couro escuro com filete dourado duplo.
static func card_style() -> StyleBoxFlat:
	var style := box(CARD, GOLD_SOFT, 1, 4, Vector2(28, 22))
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 14
	return style

static func label(text: String, size: int = BODY_SIZE, color: Color = CREAM, wrap: bool = false) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	if wrap:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

static func heading(text: String) -> Label:
	var node := label(text, HEADING_SIZE, GOLD)
	node.add_theme_font_override("font", serif())
	return node

static func button(text: String, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	node.focus_mode = Control.FOCUS_ALL
	if primary:
		node.theme_type_variation = "PrimaryButton"
	return node
