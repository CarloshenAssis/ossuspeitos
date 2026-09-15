class_name RoundHud
extends CanvasLayer

## HUD provisório do ciclo de partida. É apresentação pura: não calcula papel,
## vitória, contagem regressiva nem estado de vida — apenas mostra o que o
## servidor publicou. Existe somente no cliente gráfico.

const STATE_TEXT := {
	RoundState.WAITING: "Aguardando",
	RoundState.COUNTDOWN: "Contagem regressiva",
	RoundState.ACTIVE: "Em partida",
	RoundState.ENDED: "Encerrada",
}

const ROLE_TEXT := {
	Role.ASSASSIN: "Assassino",
	Role.DETECTIVE: "Detetive",
	Role.VICTIM: "Vítima",
}

const TEAM_TEXT := {
	Role.TEAM_ASSASSIN: "Assassino",
	Role.TEAM_INNOCENTS: "Inocentes",
}

var _public: Dictionary = {}
var _role := Role.NONE
var _round_id := 0
var _own_peer_id := 0
var _roster: Array = []
var _label: Label
var _background: ColorRect

func _ready() -> void:
	_background = ColorRect.new()
	_background.color = Color(0.03, 0.04, 0.08, 0.78)
	_background.position = Vector2(16.0, 16.0)
	_background.size = Vector2(420.0, 168.0)
	add_child(_background)
	_label = Label.new()
	_label.position = Vector2(28.0, 26.0)
	_label.add_theme_font_size_override("font_size", 16)
	add_child(_label)
	_render()

func apply_round_state(payload: Dictionary, role: int, round_id: int, own_peer_id: int) -> void:
	_public = payload
	_role = role
	_round_id = round_id
	_own_peer_id = own_peer_id
	_render()

func apply_roster(entries: Array) -> void:
	_roster = entries
	_render()

func _render() -> void:
	if _label == null:
		return
	_label.text = "\n".join(compose_lines(_public, _role, _own_peer_id, _roster))

## Composição pura do texto do HUD, a partir exclusivamente do que o servidor
## publicou. Estática e sem nó, portanto verificável sem renderização.
static func compose_lines(public_state: Dictionary, role: int, own_peer_id: int, roster: Array) -> Array:
	var state := int(public_state.get("state", RoundState.WAITING))
	var entry := own_entry(roster, own_peer_id)
	var lines: Array = []
	lines.append("Estado: %s" % str(STATE_TEXT.get(state, "Aguardando")))
	lines.append("Jogadores conectados: %d/%d" % [
		int(public_state.get("connected", 0)),
		int(public_state.get("max_players", RoundRules.MAX_PLAYERS))])
	if state == RoundState.WAITING:
		lines.append("Faltam %d jogadores para começar" % maxi(0,
			int(public_state.get("min_players", RoundRules.MIN_PLAYERS))
			- int(public_state.get("connected", 0))))
	if state == RoundState.COUNTDOWN:
		lines.append("Início em: %ds" % int(ceil(
			float(int(public_state.get("countdown_msec", 0))) / 1000.0)))
	# Durante WAITING e COUNTDOWN não existe papel para mostrar, e o HUD só
	# exibe o papel local: nunca o de outro jogador.
	if (state == RoundState.ACTIVE or state == RoundState.ENDED) and Role.is_valid(role):
		lines.append("Seu papel: %s" % str(ROLE_TEXT.get(role, "—")))
		# O estado de vida vem do roster oficial; nada é deduzido aqui.
		lines.append("Você está: %s" % ("Vivo" if bool(entry.get("alive", true)) else "Morto"))
	if state == RoundState.ENDED:
		lines.append("Vencedor: %s" % str(TEAM_TEXT.get(
			int(public_state.get("winning_team", Role.TEAM_NONE)), "—")))
	if (state == RoundState.ACTIVE or state == RoundState.ENDED) \
			and not entry.is_empty() and not bool(entry.get("participant", false)):
		lines.append("Você entra na próxima rodada")
	return lines

static func own_entry(roster: Array, own_peer_id: int) -> Dictionary:
	for raw_entry in roster:
		var entry: Dictionary = raw_entry
		if int(entry.get("peer_id", 0)) == own_peer_id:
			return entry
	return {}
