class_name NetworkConfig
extends RefCounted

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_BIND_ADDRESS := "127.0.0.1"
const DEFAULT_PORT := 9080
const MIN_PLAYERS := 4
const MAX_PLAYERS := 8
const PROTOCOL_VERSION := 1
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

