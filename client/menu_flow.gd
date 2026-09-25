class_name MenuFlow
extends RefCounted

## Estados visuais do fluxo de conexão do menu (fase 7). Puro: nenhuma rede,
## nenhum nó. O menu desenha a partir daqui e a `NetworkApp` informa os
## eventos. Cada tentativa tem uma identidade; evento de tentativa anterior é
## ignorado (`accepts`).

enum State { IDLE, VALIDATING, STARTING_SERVER, CONNECTING, AWAITING_RESPONSE, CONNECTED, CANCELLING, FAILED, DISCONNECTED, SHUTTING_DOWN, ONLINE }

const NAMES := {
	State.IDLE: "idle", State.VALIDATING: "validating", State.STARTING_SERVER: "starting_server",
	State.CONNECTING: "connecting", State.AWAITING_RESPONSE: "awaiting_response", State.CONNECTED: "connected",
	State.CANCELLING: "cancelling", State.FAILED: "failed", State.DISCONNECTED: "disconnected", State.SHUTTING_DOWN: "shutting_down",
	State.ONLINE: "online",
}

## Por estado: texto, spinner, se pode cancelar, se os campos/botões de ação
## ficam ativos e se o painel de status aparece.
const SPEC := {
	State.IDLE: {"text": "", "spinner": false, "cancel": false, "inputs": true, "overlay": false},
	State.VALIDATING: {"text": "Conferindo os dados…", "spinner": true, "cancel": false, "inputs": false, "overlay": false},
	State.STARTING_SERVER: {"text": "Abrindo a mansão (iniciando o servidor local)…", "spinner": true, "cancel": true, "inputs": false, "overlay": true},
	State.CONNECTING: {"text": "Conectando…", "spinner": true, "cancel": true, "inputs": false, "overlay": true},
	State.AWAITING_RESPONSE: {"text": "Aguardando a resposta do anfitrião…", "spinner": true, "cancel": true, "inputs": false, "overlay": true},
	State.CONNECTED: {"text": "Entrando na mansão…", "spinner": true, "cancel": false, "inputs": false, "overlay": true},
	State.CANCELLING: {"text": "Cancelando…", "spinner": true, "cancel": false, "inputs": false, "overlay": true},
	State.FAILED: {"text": "", "spinner": false, "cancel": false, "inputs": true, "overlay": true},
	State.DISCONNECTED: {"text": "", "spinner": false, "cancel": false, "inputs": true, "overlay": true},
	State.SHUTTING_DOWN: {"text": "Encerrando…", "spinner": true, "cancel": false, "inputs": false, "overlay": true},
	## Fase 9: conectado ao servidor online, no lobby online ou numa sala. Os
	## painéis de sala ficam ativos; a conexão continua aberta.
	State.ONLINE: {"text": "", "spinner": false, "cancel": false, "inputs": true, "overlay": false},
}

## Transições permitidas (o resto é ignorado e contado).
const NEXT := {
	State.IDLE: [State.VALIDATING, State.SHUTTING_DOWN],
	State.VALIDATING: [State.IDLE, State.FAILED, State.STARTING_SERVER, State.CONNECTING],
	State.STARTING_SERVER: [State.CONNECTING, State.FAILED, State.CANCELLING, State.SHUTTING_DOWN],
	State.CONNECTING: [State.AWAITING_RESPONSE, State.FAILED, State.CANCELLING, State.SHUTTING_DOWN],
	State.AWAITING_RESPONSE: [State.CONNECTED, State.ONLINE, State.FAILED, State.CANCELLING, State.SHUTTING_DOWN],
	State.CONNECTED: [State.DISCONNECTED, State.SHUTTING_DOWN],
	State.CANCELLING: [State.IDLE],
	State.FAILED: [State.IDLE, State.VALIDATING, State.SHUTTING_DOWN],
	State.DISCONNECTED: [State.IDLE, State.VALIDATING, State.SHUTTING_DOWN],
	State.SHUTTING_DOWN: [],
	State.ONLINE: [State.CONNECTED, State.DISCONNECTED, State.SHUTTING_DOWN],
}

var state := State.IDLE
var attempt := 0
var message := ""
var ignored_events := 0
var transitions: Array = []

## Nova tentativa (a partir de IDLE, FAILED ou DISCONNECTED): devolve o id.
func begin_attempt() -> int:
	if not go(State.VALIDATING):
		return 0
	attempt += 1
	return attempt

func accepts(event_attempt: int) -> bool:
	if event_attempt != attempt or attempt == 0:
		ignored_events += 1
		return false
	return true

## Transição; `event_attempt` > 0 exige que seja a tentativa corrente.
func go(next: int, text: String = "", event_attempt: int = 0) -> bool:
	if event_attempt > 0 and not accepts(event_attempt):
		return false
	if next not in NEXT[state]:
		ignored_events += 1
		return false
	transitions.append("%s>%s" % [NAMES[state], NAMES[next]])
	state = next
	message = text if not text.is_empty() else str(SPEC[next]["text"])
	return true

func spec() -> Dictionary:
	return SPEC[state]

func state_name() -> String:
	return NAMES[state]

func busy() -> bool:
	return not bool(SPEC[state]["inputs"])
