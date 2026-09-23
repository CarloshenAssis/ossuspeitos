class_name RoundAuthority
extends RefCounted

## Autoridade headless do ciclo de partida. Não instancia câmera, HUD, meshes,
## luzes nem áudio, não conhece o transporte e não depende de cenas: a camada de
## rede apenas chama `tick()` com o tempo do servidor e reage aos sinais.
##
## O mapa completo de papéis vive aqui e nunca sai por broadcast. A camada de
## rede obtém um papel por vez com `get_role_for_peer()` e o envia por RPC
## direcionada ao próprio dono.

## Estado público da rodada mudou (inclui contagem regressiva e resultado).
signal state_changed(state: int, round_id: int)
## A rodada começou e os papéis foram sorteados. Entregue apenas à camada de
## rede do servidor, que distribui um papel por peer.
signal roles_ready(round_id: int, participant_ids: Array)
## Estado oficial de vida mudou. `alive` é público; o papel não acompanha.
signal alive_changed(round_id: int, peer_id: int, alive: bool)
signal round_ended(round_id: int, winning_team: int, reason: String)
## Resultado final sanitizado, criado somente depois da transicao para ENDED.
signal reveal_ready(round_id: int, result: Dictionary)
## Solicita que a rede atualize, em privado, os alvos dos participantes mortos.
signal spectator_targets_changed(round_id: int)
signal round_reset(round_id: int)
signal invalid_transition(from_state: int, to_state: int)

var lobby: LobbyRegistry
var state := RoundState.WAITING
var round_id := 0
var winning_team := Role.TEAM_NONE
var winner_reason := ""
## DTO publico final. Vazio em WAITING, COUNTDOWN e ACTIVE.
var final_reveal: Dictionary = {}
var invalid_transition_count := 0
## peer_id -> true. Congelado na transição para ACTIVE.
var participants: Dictionary = {}
## peer_id -> bool. Estado oficial de vida dos participantes da rodada.
var alive: Dictionary = {}

var _roles: Dictionary = {}
var _eliminations: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _countdown_seconds := RoundRules.COUNTDOWN_SECONDS
var _round_end_delay_seconds := RoundRules.ROUND_END_DELAY_SECONDS
var _countdown_deadline_msec := 0
var _countdown_round_id := 0
var _reset_deadline_msec := 0
var _reset_round_id := 0
var _published_countdown_seconds := -1

func _init(lobby_registry: LobbyRegistry = null, seed_value: int = 0) -> void:
	lobby = lobby_registry if lobby_registry != null else LobbyRegistry.new()
	set_seed(seed_value)

func configure(countdown_seconds: float, round_end_delay_seconds: float) -> void:
	_countdown_seconds = RoundRules.sanitize_countdown_seconds(countdown_seconds)
	_round_end_delay_seconds = RoundRules.sanitize_countdown_seconds(round_end_delay_seconds)

## Seed injetável. Sem chamada explícita o sorteio usa uma seed aleatória.
func set_seed(seed_value: int) -> void:
	if seed_value == 0:
		_rng.randomize()
		return
	_rng.seed = seed_value

# --- Lobby -------------------------------------------------------------------

## Registra uma sessão. Devolve "" ou o motivo público da recusa.
func join(peer_id: int, raw_label: String, now_msec: int) -> String:
	var reason := lobby.add(peer_id, raw_label)
	if not reason.is_empty():
		return reason
	_evaluate_lobby(now_msec)
	return ""

## Remove a sessão e aplica a política de desconexão do estado atual.
func leave(peer_id: int, now_msec: int) -> void:
	if not lobby.remove(peer_id):
		return
	if state == RoundState.ACTIVE and participants.has(peer_id) and bool(alive.get(peer_id, false)):
		# Não anuncia o papel do jogador que saiu: apenas o estado de vida muda.
		_set_alive(peer_id, false, RoundRules.sanitize_cause("disconnect"), 0)
		_evaluate_victory(now_msec)
		return
	_evaluate_lobby(now_msec)

## Peers conectados que não participam da rodada corrente.
func waiting_peer_ids() -> Array:
	var result: Array = []
	for peer_id in lobby.peer_ids():
		if not participants.has(peer_id):
			result.append(int(peer_id))
	return result

func is_waiting_for_next_round(peer_id: int) -> bool:
	if state == RoundState.WAITING or state == RoundState.COUNTDOWN:
		return false
	return lobby.has(peer_id) and not participants.has(peer_id)

# --- Tempo do servidor -------------------------------------------------------

## Avança o relógio autoritativo. `now_msec` vem sempre do servidor.
func tick(now_msec: int) -> void:
	if state == RoundState.COUNTDOWN and _countdown_round_id == round_id and now_msec >= _countdown_deadline_msec:
		_begin_active(now_msec)
		return
	if state == RoundState.ENDED and _reset_round_id == round_id and now_msec >= _reset_deadline_msec:
		reset_for_next_round(now_msec)

func countdown_remaining_msec(now_msec: int) -> int:
	if state != RoundState.COUNTDOWN:
		return 0
	return maxi(0, _countdown_deadline_msec - now_msec)

## Segundo cheio publicado no estado público; muda no máximo uma vez por segundo.
func countdown_display_seconds(now_msec: int) -> int:
	return int(ceil(float(countdown_remaining_msec(now_msec)) / 1000.0))

## Indica se o estado público precisa ser republicado por causa do contador.
func consume_countdown_tick(now_msec: int) -> bool:
	var seconds := countdown_display_seconds(now_msec) if state == RoundState.COUNTDOWN else -1
	if seconds == _published_countdown_seconds:
		return false
	_published_countdown_seconds = seconds
	return true

# --- Papéis secretos ---------------------------------------------------------

## Consulta interna do servidor. Nunca exposta como RPC ao cliente.
func get_role_for_peer(peer_id: int) -> int:
	if state != RoundState.ACTIVE and state != RoundState.ENDED:
		return Role.NONE
	return int(_roles.get(peer_id, Role.NONE))

## Verifica se o papel pode ser enviado a este destinatário agora.
func can_deliver_role(peer_id: int) -> bool:
	if state != RoundState.ACTIVE:
		return false
	if not participants.has(peer_id) or not lobby.has(peer_id):
		return false
	return Role.is_valid(int(_roles.get(peer_id, Role.NONE)))

## Contagem agregada, sem associação entre papel e peer. Seguro para log.
func role_counts() -> Dictionary:
	return RoundRules.role_counts(_roles)

func has_roles() -> bool:
	return not _roles.is_empty()

## Copia defensiva do resultado final. Nunca produz uma revelacao fora de ENDED.
func get_final_reveal() -> Dictionary:
	if state != RoundState.ENDED:
		return {}
	return final_reveal.duplicate(true)

## Lista privada calculada exclusivamente a partir do estado oficial.
func spectator_targets_for(peer_id: int) -> Array:
	var result: Array = []
	if state != RoundState.ACTIVE or not participants.has(peer_id) \
			or not lobby.has(peer_id) or is_alive(peer_id):
		return result
	for raw_target in participants.keys():
		var target := int(raw_target)
		if target != peer_id and lobby.has(target) and is_alive(target):
			result.append(target)
	result.sort()
	return result

func can_spectate(peer_id: int, target_peer_id: int) -> bool:
	return target_peer_id in spectator_targets_for(peer_id)

# --- Estado vivo/morto -------------------------------------------------------

func is_participant(peer_id: int) -> bool:
	return participants.has(peer_id)

func is_alive(peer_id: int) -> bool:
	return bool(alive.get(peer_id, false))

## Registro interno e sanitizado da eliminação: rodada, causa e instigador
## validado. Serve de base para o sistema de combate futuro e nunca é publicado.
func last_elimination(peer_id: int) -> Dictionary:
	return (_eliminations.get(peer_id, {}) as Dictionary).duplicate()

func elimination_count() -> int:
	return _eliminations.size()

func alive_count() -> int:
	var total := 0
	for peer_id in alive:
		if bool(alive[peer_id]):
			total += 1
	return total

## API interna de eliminação. Somente código do servidor a chama; não existe
## nenhuma RPC de cliente equivalente. Devolve "" ou o motivo da recusa.
##
## `now_msec` permite injetar o tempo do servidor; -1 lê o relógio do processo.
func eliminate_player(peer_id: int, cause: String, instigator_peer_id: int = 0, now_msec: int = -1) -> String:
	if state != RoundState.ACTIVE:
		return "round_not_active"
	if not participants.has(peer_id):
		return "unknown_peer" if not lobby.has(peer_id) else "not_in_round"
	if not bool(alive.get(peer_id, false)):
		return "already_eliminated"
	var instigator := instigator_peer_id if participants.has(instigator_peer_id) else 0
	_set_alive(peer_id, false, RoundRules.sanitize_cause(cause), instigator)
	_evaluate_victory(now_msec if now_msec >= 0 else Time.get_ticks_msec())
	return ""

# --- Estado público ----------------------------------------------------------

## Somente campos seguros. Nenhum papel, seed ou mapa interno.
func public_state(now_msec: int) -> Dictionary:
	return {
		"state": state,
		"round_id": round_id,
		"countdown_msec": countdown_remaining_msec(now_msec),
		"connected": lobby.size(),
		"participants": participants.size(),
		"alive": alive_count(),
		"winning_team": winning_team,
		"winner_reason": winner_reason,
		"min_players": RoundRules.MIN_PLAYERS,
		"max_players": RoundRules.MAX_PLAYERS,
	}

## Roster público: identificador, conexão, participação e vida. Sem papel.
func public_roster() -> Array:
	var result: Array = []
	for entry in lobby.public_entries():
		var peer_id := int(entry["peer_id"])
		result.append({
			"peer_id": peer_id,
			"label": str(entry["label"]),
			"connected": bool(entry["connected"]),
			"participant": participants.has(peer_id),
			"alive": bool(alive.get(peer_id, true)),
		})
	return result

# --- Transições --------------------------------------------------------------

func _transition(to_state: int) -> bool:
	if not RoundState.is_valid_transition(state, to_state):
		invalid_transition_count += 1
		invalid_transition.emit(state, to_state)
		return false
	state = to_state
	return true

func _evaluate_lobby(now_msec: int) -> void:
	if state == RoundState.WAITING and RoundRules.can_start_countdown(lobby.size()):
		_begin_countdown(now_msec)
		return
	if state == RoundState.COUNTDOWN and not RoundRules.can_start_countdown(lobby.size()):
		_cancel_countdown()

func _begin_countdown(now_msec: int) -> void:
	if not _transition(RoundState.COUNTDOWN):
		return
	round_id += 1
	# A contagem regressiva nunca carrega estado de rodada. Hoje só se chega
	# aqui a partir de WAITING, já limpo, mas ENDED->COUNTDOWN é uma transição
	# declarada válida: limpar aqui garante que nenhum papel da rodada anterior
	# sobreviva caso esse caminho passe a ser usado.
	_roles.clear()
	final_reveal.clear()
	_eliminations.clear()
	participants.clear()
	alive.clear()
	winning_team = Role.TEAM_NONE
	winner_reason = ""
	_countdown_round_id = round_id
	_countdown_deadline_msec = now_msec + int(_countdown_seconds * 1000.0)
	_published_countdown_seconds = -1
	state_changed.emit(state, round_id)

func _cancel_countdown() -> void:
	if not _transition(RoundState.WAITING):
		return
	_countdown_deadline_msec = 0
	_countdown_round_id = 0
	_published_countdown_seconds = -1
	state_changed.emit(state, round_id)

func _begin_active(now_msec: int) -> void:
	# Revalida logo antes da transição: o lobby pode ter encolhido.
	if not RoundRules.can_start_countdown(lobby.size()):
		_cancel_countdown()
		return
	var frozen := lobby.peer_ids()
	var roles := RoundRules.assign_roles(frozen, _rng)
	if not RoundRules.is_valid_distribution(roles):
		_cancel_countdown()
		return
	if not _transition(RoundState.ACTIVE):
		return
	participants.clear()
	alive.clear()
	_eliminations.clear()
	_roles = roles
	final_reveal.clear()
	for peer_id in frozen:
		participants[int(peer_id)] = true
		alive[int(peer_id)] = true
	_countdown_deadline_msec = 0
	_countdown_round_id = 0
	_published_countdown_seconds = -1
	state_changed.emit(state, round_id)
	roles_ready.emit(round_id, frozen)
	_evaluate_victory(now_msec)

func _set_alive(peer_id: int, value: bool, cause: String, instigator_peer_id: int) -> void:
	alive[peer_id] = value
	if not value:
		_eliminations[peer_id] = {
			"round_id": round_id,
			"cause": cause,
			"instigator": instigator_peer_id,
		}
	alive_changed.emit(round_id, peer_id, value)
	spectator_targets_changed.emit(round_id)

func _evaluate_victory(now_msec: int) -> void:
	if state != RoundState.ACTIVE:
		return
	var outcome := RoundRules.evaluate_winner(_roles, alive)
	if outcome.is_empty():
		return
	_end_round(int(outcome["team"]), str(outcome["reason"]), now_msec)

func _end_round(team: int, reason: String, now_msec: int) -> void:
	if not _transition(RoundState.ENDED):
		return
	winning_team = team
	winner_reason = reason
	# A revelacao nasce somente apos ENDED e antes que o mapa privado seja limpo.
	# A allowlist impede vida, inventario, municao, seed ou eliminacoes no DTO.
	var revealed_players: Array = []
	var sorted_peers := participants.keys()
	sorted_peers.sort()
	for raw_peer_id in sorted_peers:
		var peer_id := int(raw_peer_id)
		revealed_players.append({
			"peer_id": peer_id,
			"label": lobby.label_for(peer_id),
			"role": int(_roles.get(peer_id, Role.NONE)),
		})
	final_reveal = {
		"round_id": round_id,
		"winning_team": winning_team,
		"reason": winner_reason,
		"players": revealed_players,
	}
	_reset_round_id = round_id
	_reset_deadline_msec = now_msec + int(_round_end_delay_seconds * 1000.0)
	_published_countdown_seconds = -1
	state_changed.emit(state, round_id)
	round_ended.emit(round_id, winning_team, winner_reason)
	reveal_ready.emit(round_id, get_final_reveal())

## Apaga papéis, vivos, resultado, eliminações e prazos da rodada anterior e
## devolve o lobby ao ciclo. Nenhum callback atrasado da rodada anterior
## sobrevive: os prazos guardam o `round_id` que os criou.
##
## O reinício só existe a partir de ENDED. Como COUNTDOWN->WAITING é uma
## transição legítima de cancelamento, delegar a checagem apenas a
## `_transition` deixaria um reset indevido cancelar uma contagem regressiva
## válida e consumir um identificador de rodada.
func reset_for_next_round(now_msec: int) -> void:
	if state != RoundState.ENDED:
		invalid_transition_count += 1
		invalid_transition.emit(state, RoundState.WAITING)
		return
	if not _transition(RoundState.WAITING):
		return
	_roles.clear()
	final_reveal.clear()
	_eliminations.clear()
	participants.clear()
	alive.clear()
	winning_team = Role.TEAM_NONE
	winner_reason = ""
	_countdown_deadline_msec = 0
	_countdown_round_id = 0
	_reset_deadline_msec = 0
	_reset_round_id = 0
	_published_countdown_seconds = -1
	state_changed.emit(state, round_id)
	round_reset.emit(round_id)
	_evaluate_lobby(now_msec)

## Limpeza terminal, usada no encerramento do servidor.
func clear() -> void:
	_roles.clear()
	final_reveal.clear()
	_eliminations.clear()
	participants.clear()
	alive.clear()
	lobby.clear()
	state = RoundState.WAITING
	winning_team = Role.TEAM_NONE
	winner_reason = ""
	_countdown_deadline_msec = 0
	_countdown_round_id = 0
	_reset_deadline_msec = 0
	_reset_round_id = 0
	_published_countdown_seconds = -1
