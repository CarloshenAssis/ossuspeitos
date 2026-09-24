class_name NetworkConfig
extends RefCounted

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_BIND_ADDRESS := "127.0.0.1"
const DEFAULT_PORT := 9080
## Os limites de sala vivem em `RoundRules`; aqui ficam apenas os apelidos
## usados pela camada de rede, para que não existam dois valores divergentes.
const MIN_PLAYERS := RoundRules.MIN_PLAYERS
const MAX_PLAYERS := RoundRules.MAX_PLAYERS
## 5: adds private spectator targets and the sanitized final role reveal.
## 6: shutdown_prepare/shutdown_ready carry the shutdown generation and a
## per-peer token, so only a confirmation of a received preparation counts.
## 7: round_roster entries carry the public cosmetic `appearance` id
## (allowlisted by CharacterAppearance); clients drop unknown roster keys.
## 8: submit_input carries pitch_delta and world snapshots carry the official
## pitch (vertical aim), which the server also uses for every shot.
const PROTOCOL_VERSION := 8
const CONNECT_TIMEOUT_SECONDS := 10.0

static func user_arguments() -> Dictionary:
	var values := {}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--"):
			continue
		var parts := argument.trim_prefix("--").split("=", true, 1)
		values[parts[0]] = parts[1] if parts.size() == 2 else "true"
	return values

static func integer_argument(arguments: Dictionary, key: String, fallback: int) -> int:
	var value := str(arguments.get(key, fallback))
	return value.to_int() if value.is_valid_int() else fallback

static func float_argument(arguments: Dictionary, key: String, fallback: float) -> float:
	var value := str(arguments.get(key, fallback))
	return value.to_float() if value.is_valid_float() else fallback

static func bool_argument(arguments: Dictionary, key: String) -> bool:
	return str(arguments.get(key, "false")) == "true"

static func should_poll_human_input(
	is_joined: bool,
	expected_test_clients: int,
	is_round_test: bool,
	is_combat_test: bool,
	has_graphical_arena: bool
) -> bool:
	return is_joined and expected_test_clients == 0 and not is_round_test \
		and not is_combat_test and has_graphical_arena
