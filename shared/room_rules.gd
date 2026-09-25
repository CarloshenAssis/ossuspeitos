class_name RoomRules
extends RefCounted

## Salas privadas do servidor online (fase 9). Regras compartilhadas entre
## servidor e cliente: formato do código de convite, fases públicas da sala,
## allowlist do DTO `room_state` e mensagens em português.
##
## O código é um CONVITE de playtest, não autenticação: quem o conhece entra
## (sujeito a sala cheia, rodada em andamento e limite de tentativas).

## Sem O/0, I/1: fácil de ditar e de ler. 32 símbolos ^ 6 ≈ 1,07 bilhão.
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 6
## Entrada crua aceita antes de normalizar (espaços e hífens de quem digita).
const MAX_RAW_CODE_LENGTH := 16

const PHASE_LOBBY := "lobby"
const PHASE_COUNTDOWN := "countdown"
const PHASE_PLAYING := "playing"
const PHASE_RESULTS := "results"
const PHASES := [PHASE_LOBBY, PHASE_COUNTDOWN, PHASE_PLAYING, PHASE_RESULTS]

## Contagem regressiva depois que todos marcam PRONTO e tempo em que o
## resultado fica na tela da partida antes da volta ao lobby da sala.
const COUNTDOWN_SECONDS := 10.0
const RESULTS_SECONDS := 8.0

## Motivos públicos de recusa/erro de sala (allowlist do cliente).
const ERRORS := {
	"invalid_code": "Código inválido. Confira as 6 letras e números.",
	"room_not_found": "Nenhuma sala com esse código. Confira o código com quem criou a sala.",
	"room_full": "A sala está cheia (8 jogadores).",
	"round_in_progress": "Partida em andamento nesta sala. Tente de novo quando ela voltar ao lobby.",
	"name_taken": "Já existe alguém com esse nome nesta sala. Escolha outro nome.",
	"invalid_name": "Nome inválido. Use até 20 letras, números, espaço, - ou _.",
	"server_full": "O servidor está lotado no momento. Tente mais tarde.",
	"already_in_room": "Você já está em uma sala.",
	"not_in_room": "Você não está em uma sala.",
	"too_many_attempts": "Tentativas demais. Conecte de novo para tentar outra vez.",
	"room_expired": "A sala expirou por inatividade.",
	"not_ready_phase": "Só dá para marcar pronto no lobby da sala.",
	"rooms_unavailable": "Este servidor não tem salas online.",
}

static func error_message(reason: String) -> String:
	return str(ERRORS.get(reason, "Não foi possível completar a ação na sala."))

## Código em forma canônica, ou "" se inválido. Aceita minúsculas, espaços e
## hífens digitados; recusa qualquer outro tipo ou símbolo.
static func normalize_code(raw: Variant) -> String:
	if typeof(raw) != TYPE_STRING:
		return ""
	var text := str(raw)
	if text.length() > MAX_RAW_CODE_LENGTH:
		return ""
	var clean := text.strip_edges().to_upper().replace(" ", "").replace("-", "")
	if clean.length() != CODE_LENGTH:
		return ""
	for character in clean:
		if not CODE_ALPHABET.contains(character):
			return ""
	return clean

static func is_valid_code(code: Variant) -> bool:
	return typeof(code) == TYPE_STRING and normalize_code(code) == code

## Código novo a partir de bytes aleatórios (Crypto no servidor). Cada byte
## escolhe um símbolo por módulo 32: sem viés, 256 é múltiplo de 32.
static func code_from_bytes(bytes: PackedByteArray) -> String:
	var result := ""
	for index in CODE_LENGTH:
		var value := int(bytes[index]) if index < bytes.size() else 0
		result += CODE_ALPHABET[value % CODE_ALPHABET.length()]
	return result

## Forma legível para mostrar/ditar: "ABC-234".
static func display_code(code: String) -> String:
	if code.length() != CODE_LENGTH:
		return code
	return "%s-%s" % [code.substr(0, 3), code.substr(3, 3)]

static func phase_for_round_state(state: int) -> String:
	match state:
		RoundState.COUNTDOWN: return PHASE_COUNTDOWN
		RoundState.ACTIVE: return PHASE_PLAYING
		RoundState.ENDED: return PHASE_RESULTS
	return PHASE_LOBBY

## Cópia defensiva e tipada do `room_state` recebido pelo cliente. Chave
## desconhecida some; tipo errado vira padrão seguro; no máximo 8 jogadores.
static func sanitize_room_state(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var source: Dictionary = raw
	var code := normalize_code(source.get("code", ""))
	if code.is_empty():
		return {}
	var phase := str(source.get("phase", PHASE_LOBBY))
	if phase not in PHASES:
		phase = PHASE_LOBBY
	var players: Array = []
	var raw_players: Variant = source.get("players", [])
	if typeof(raw_players) == TYPE_ARRAY:
		for raw_player in raw_players:
			if players.size() >= RoundRules.MAX_PLAYERS:
				break
			if typeof(raw_player) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = raw_player
			var peer_id: Variant = entry.get("peer_id", 0)
			if typeof(peer_id) != TYPE_INT or int(peer_id) <= 0:
				continue
			players.append({
				"peer_id": int(peer_id),
				"label": RoundRules.sanitize_label(str(entry.get("label", ""))).left(RoundRules.MAX_LABEL_LENGTH),
				"appearance": CharacterAppearance.sanitize(entry.get("appearance", "")),
				"ready": entry.get("ready", false) == true,
				"host": entry.get("host", false) == true,
			})
	var result := {}
	var raw_result: Variant = source.get("result", {})
	if typeof(raw_result) == TYPE_DICTIONARY and not (raw_result as Dictionary).is_empty():
		result = sanitize_result(raw_result)
	return {
		"code": code,
		"phase": phase,
		"round_id": maxi(0, _int_or(source.get("round_id", 0), 0)),
		"countdown_msec": clampi(_int_or(source.get("countdown_msec", 0), 0), 0, int(COUNTDOWN_SECONDS * 1000.0) + 1000),
		"min_players": RoundRules.MIN_PLAYERS,
		"max_players": RoundRules.MAX_PLAYERS,
		"players": players,
		"ready_count": clampi(_int_or(source.get("ready_count", 0), 0), 0, RoundRules.MAX_PLAYERS),
		"result": result,
	}

## Resultado da última rodada: vencedor, motivo e papéis revelados por rótulo.
static func sanitize_result(raw: Dictionary) -> Dictionary:
	var winner := str(raw.get("winner", ""))
	if winner not in ["ASSASSIN", "INNOCENTS"]:
		return {}
	var reason := str(raw.get("reason", ""))
	if reason not in [RoundRules.REASON_ASSASSIN_DOWN, RoundRules.REASON_INNOCENTS_DOWN]:
		reason = ""
	var players: Array = []
	var raw_players: Variant = raw.get("players", [])
	if typeof(raw_players) == TYPE_ARRAY:
		for raw_player in raw_players:
			if players.size() >= RoundRules.MAX_PLAYERS or typeof(raw_player) != TYPE_DICTIONARY:
				continue
			var role := str((raw_player as Dictionary).get("role", ""))
			if role not in ["ASSASSIN", "DETECTIVE", "VICTIM"]:
				continue
			players.append({
				"label": RoundRules.sanitize_label(str((raw_player as Dictionary).get("label", ""))).left(RoundRules.MAX_LABEL_LENGTH),
				"role": role,
			})
	return {
		"round_id": maxi(0, _int_or(raw.get("round_id", 0), 0)),
		"winner": winner,
		"reason": reason,
		"players": players,
	}

static func _int_or(value: Variant, fallback: int) -> int:
	return int(value) if typeof(value) == TYPE_INT else fallback
