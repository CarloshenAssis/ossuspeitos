class_name Role
extends RefCounted

## Papéis secretos de uma rodada. O mapa completo vive apenas no servidor;
## cada cliente recebe somente o próprio papel por RPC direcionada.

const NONE := 0
const ASSASSIN := 1
const DETECTIVE := 2
const VICTIM := 3

## Times usados apenas no resultado público da rodada.
const TEAM_NONE := 0
const TEAM_ASSASSIN := 1
const TEAM_INNOCENTS := 2

const LABELS := {
	NONE: "NONE",
	ASSASSIN: "ASSASSIN",
	DETECTIVE: "DETECTIVE",
	VICTIM: "VICTIM",
}

const TEAM_LABELS := {
	TEAM_NONE: "NONE",
	TEAM_ASSASSIN: "ASSASSIN",
	TEAM_INNOCENTS: "INNOCENTS",
}

static func is_valid(role: int) -> bool:
	return role == ASSASSIN or role == DETECTIVE or role == VICTIM

## Inocente é DETECTIVE ou VICTIM neste marco.
static func is_innocent(role: int) -> bool:
	return role == DETECTIVE or role == VICTIM

static func to_label(role: int) -> String:
	return str(LABELS.get(role, "NONE"))

static func team_to_label(team: int) -> String:
	return str(TEAM_LABELS.get(team, "NONE"))

static func is_valid_team(team: int) -> bool:
	return team == TEAM_ASSASSIN or team == TEAM_INNOCENTS
