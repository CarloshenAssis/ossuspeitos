class_name HudStyle
extends RefCounted

## Paleta e peças visuais do HUD de partida (referência: protótipo de interface).
## Base de desenho 960×540; com `stretch/mode=canvas_items` tudo escala junto
## em 1920×1080. Apresentação pura: nenhuma regra de jogo mora aqui.

const INK := Color("#0E1013")
const SOLID := Color("#171A1F")
const LINE := Color("#2E333B")
const BONE := Color("#ECE8DF")
const MUTED := Color("#A3A6AC")
const AMBER := Color("#F2B84B")
const RED := Color("#E5484D")
const BLUE := Color("#5BA7F7")
## Mesmos acentos dos objetos da arena (`ArenaModels`): arma fria, munição cobre.
const CYAN := ArenaModels.WEAPON_GLOW
const COPPER := ArenaModels.AMMO_GLOW
const PANEL := Color(0.063, 0.071, 0.086, 0.72)
const MARGIN := 16.0

## Papéis se distinguem por símbolo + nome, legíveis sem depender da cor.
const ROLE_GLYPHS := {Role.VICTIM: "●", Role.DETECTIVE: "▲", Role.ASSASSIN: "◆"}
const ROLE_NAMES := {Role.VICTIM: "VÍTIMA", Role.DETECTIVE: "DETETIVE", Role.ASSASSIN: "ASSASSINO"}
const ROLE_COLORS := {Role.VICTIM: BONE, Role.DETECTIVE: BLUE, Role.ASSASSIN: RED}

static func panel_style(background: Color = PANEL, border: Color = LINE, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style

static func panel(background: Color = PANEL, border: Color = LINE, border_width: int = 1) -> PanelContainer:
	var container := PanelContainer.new()
	container.add_theme_stylebox_override("panel", panel_style(background, border, border_width))
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return container

static func label(text: String, size: int, color: Color = BONE, outline: bool = false) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	if outline:
		node.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		node.add_theme_constant_override("outline_size", 4)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

## Tecla desenhada como uma caixa com a letra: Q, E, R.
static func key_cap(letter: String, color: Color = BONE) -> PanelContainer:
	var cap := panel(Color(0, 0, 0, 0), color, 1)
	var style := cap.get_theme_stylebox("panel") as StyleBoxFlat
	style.content_margin_left = 5.0
	style.content_margin_right = 5.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	cap.add_child(label(letter, 13, color))
	return cap

static func anchor_corner(control: Control, preset: int) -> void:
	control.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	# Painéis ancorados à direita/embaixo crescem para dentro da tela.
	control.grow_horizontal = Control.GROW_DIRECTION_BEGIN if preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_RIGHT] else Control.GROW_DIRECTION_END
	control.grow_vertical = Control.GROW_DIRECTION_BEGIN if preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM] else Control.GROW_DIRECTION_END
	if preset in [Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM]:
		control.grow_horizontal = Control.GROW_DIRECTION_BOTH
