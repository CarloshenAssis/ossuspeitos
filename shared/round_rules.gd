class_name RoundRules
extends RefCounted

## Regras determinísticas da rodada, sem estado, sem rede e sem renderização.
## Nenhuma função aqui guarda segredos: quem armazena o mapa de papéis é o
## servidor, em `RoundAuthority`.

const MIN_PLAYERS := 4
const MAX_PLAYERS := 8
const COUNTDOWN_SECONDS := 5.0
const ROUND_END_DELAY_SECONDS := 5.0
const MIN_COUNTDOWN_SECONDS := 0.5
const MAX_COUNTDOWN_SECONDS := 120.0
const MAX_LABEL_LENGTH := 32
const MAX_CAUSE_LENGTH := 24
const DEFAULT_CAUSE := "unknown"

## Causas de eliminação aceitas neste marco. O sistema de combate futuro
## acrescenta as suas; qualquer valor fora da lista vira `DEFAULT_CAUSE`.
const ALLOWED_CAUSES := ["unknown", "test", "disconnect", "round_reset"]

## Razões públicas do resultado. Nunca citam peer, papel ou nome.
const REASON_ASSASSIN_DOWN := "assassin_down"
const REASON_INNOCENTS_DOWN := "innocents_down"

static func can_hold(player_count: int) -> bool:
	return player_count >= 0 and player_count <= MAX_PLAYERS

static func can_start_countdown(player_count: int) -> bool:
	return player_count >= MIN_PLAYERS and player_count <= MAX_PLAYERS

static func sanitize_countdown_seconds(seconds: float) -> float:
	if not is_finite(seconds):
		return COUNTDOWN_SECONDS
	return clampf(seconds, MIN_COUNTDOWN_SECONDS, MAX_COUNTDOWN_SECONDS)

static func sanitize_cause(cause: String) -> String:
	var clean := cause.strip_edges().to_lower()
	if clean.length() > MAX_CAUSE_LENGTH or not ALLOWED_CAUSES.has(clean):
		return DEFAULT_CAUSE
	return clean

## Valida um identificador público enviado pelo cliente. Devolve "" quando é
## aceitável ou o motivo da recusa. O valor nunca é usado como identidade de
## rede: essa vem sempre de `multiplayer.get_remote_sender_id()`.
static func validate_label(raw_label: String) -> String:
	var clean := raw_label.strip_edges()
	if clean.is_empty() or clean.length() > MAX_LABEL_LENGTH:
		return "invalid_client"
	if not clean.replace("-", "_").is_valid_identifier():
		return "invalid_client"
	return ""

static func sanitize_label(raw_label: String) -> String:
	return raw_label.strip_edges()

## Sorteia os papéis de uma rodada. `rng` é injetável para tornar o resultado
## determinístico nos testes. Devolve {} se a quantidade for inválida.
##
## Exatamente 1 ASSASSIN, exatamente 1 DETECTIVE, o restante VICTIM.
static func assign_roles(peer_ids: Array, rng: RandomNumberGenerator) -> Dictionary:
	if rng == null or not can_start_countdown(peer_ids.size()):
		return {}
	var shuffled := shuffled_copy(peer_ids, rng)
	if shuffled.size() != peer_ids.size():
		return {}
	var roles: Dictionary = {}
	for index in shuffled.size():
		var peer_id := int(shuffled[index])
		if roles.has(peer_id):
			return {}
		if index == 0:
			roles[peer_id] = Role.ASSASSIN
		elif index == 1:
			roles[peer_id] = Role.DETECTIVE
		else:
			roles[peer_id] = Role.VICTIM
	return roles

## Fisher-Yates com o RNG injetado. `Array.shuffle()` usa o RNG global do
## engine e não seria reproduzível a partir de uma seed.
static func shuffled_copy(peer_ids: Array, rng: RandomNumberGenerator) -> Array:
	var values := peer_ids.duplicate()
	for index in range(values.size() - 1, 0, -1):
		var target := rng.randi_range(0, index)
		var swap = values[index]
		values[index] = values[target]
		values[target] = swap
	return values

## Contagem agregada de papéis, sem associação com peer. Seguro para log.
static func role_counts(roles: Dictionary) -> Dictionary:
	var counts := {"assassin": 0, "detective": 0, "victim": 0}
	for peer_id in roles:
		match int(roles[peer_id]):
			Role.ASSASSIN:
				counts["assassin"] = int(counts["assassin"]) + 1
			Role.DETECTIVE:
				counts["detective"] = int(counts["detective"]) + 1
			Role.VICTIM:
				counts["victim"] = int(counts["victim"]) + 1
	return counts

static func is_valid_distribution(roles: Dictionary) -> bool:
	if not can_start_countdown(roles.size()):
		return false
	var counts := role_counts(roles)
	if int(counts["assassin"]) != 1 or int(counts["detective"]) != 1:
		return false
	return int(counts["victim"]) == roles.size() - 2

## Avalia a vitória a partir do mapa interno de papéis e do estado oficial de
## vida. Devolve {} enquanto não houver vencedor.
##
## - Inocentes vencem quando o assassino não está mais vivo.
## - Assassino vence quando está vivo e nenhum inocente continua vivo.
static func evaluate_winner(roles: Dictionary, alive: Dictionary) -> Dictionary:
	if roles.is_empty():
		return {}
	var assassin_alive := false
	var innocents_alive := 0
	for peer_id in roles:
		var role := int(roles[peer_id])
		var is_alive := bool(alive.get(peer_id, false))
		if role == Role.ASSASSIN:
			assassin_alive = assassin_alive or is_alive
		elif Role.is_innocent(role) and is_alive:
			innocents_alive += 1
	if not assassin_alive:
		return {"team": Role.TEAM_INNOCENTS, "reason": REASON_ASSASSIN_DOWN}
	if innocents_alive == 0:
		return {"team": Role.TEAM_ASSASSIN, "reason": REASON_INNOCENTS_DOWN}
	return {}
