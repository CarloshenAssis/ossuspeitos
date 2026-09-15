class_name RoundState
extends RefCounted

## Máquina de estados explícita da rodada. Somente o servidor transiciona;
## clientes apenas recebem o estado público resultante.

const WAITING := 0
const COUNTDOWN := 1
const ACTIVE := 2
const ENDED := 3

const LABELS := {
	WAITING: "WAITING",
	COUNTDOWN: "COUNTDOWN",
	ACTIVE: "ACTIVE",
	ENDED: "ENDED",
}

## Transições permitidas. Qualquer par ausente é inválido e deve ser rejeitado.
const ALLOWED := {
	WAITING: [COUNTDOWN],
	COUNTDOWN: [ACTIVE, WAITING],
	ACTIVE: [ENDED],
	ENDED: [WAITING, COUNTDOWN],
}

static func is_valid(state: int) -> bool:
	return LABELS.has(state)

static func is_valid_transition(from_state: int, to_state: int) -> bool:
	if not is_valid(from_state) or not is_valid(to_state):
		return false
	return (ALLOWED[from_state] as Array).has(to_state)

static func to_label(state: int) -> String:
	return str(LABELS.get(state, "INVALID"))

## Estados em que revelar quem está vivo é seguro para o roster público.
static func reveals_alive(state: int) -> bool:
	return state == ACTIVE or state == ENDED
