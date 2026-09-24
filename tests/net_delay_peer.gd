extends MultiplayerPeerExtension

## Atraso de aplicação SÓ PARA TESTE (fase 4). Envolve o `MultiplayerPeer`
## real do cliente e segura pacotes numa fila FIFO antes de entregá-los, nos
## dois sentidos. Não é emulação de rede: o transporte continua WebSocket/TCP
## em loopback, sem perda nem reordenação. A ordem do fluxo é preservada
## porque o horário de liberação de cada pacote nunca é anterior ao do pacote
## anterior no mesmo sentido (jitter vira rajada, como num fluxo TCP).
##
## Carregado por `NetworkApp` apenas quando `--test-net-profile` é passado num
## binário de desenvolvimento (não exportado); `tests/` fica fora da exportação
## Windows e a Web exportada é a demo offline.
##
## Perfil: atraso de ida (cliente → servidor) e de volta (servidor → cliente)
## em ms, jitter uniforme [0, jitter] por pacote a partir de uma seed, e uma
## interrupção opcional (`stall_ms` a partir de `stall_at_ms` depois da
## conexão) durante a qual nada é liberado.

var inner: MultiplayerPeer
var up_ms := 0.0
var down_ms := 0.0
var jitter_ms := 0.0
var stall_at_ms := -1.0
var stall_ms := 0.0
var profile_name := "none"
var _rng := RandomNumberGenerator.new()
var _outgoing: Array = []
var _incoming: Array = []
var _last_out_release := 0.0
var _last_in_release := 0.0
var _target_peer := 0
var _transfer_mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _transfer_channel := 0
var _started_msec := -1.0
## Medidas do atraso realmente aplicado (ms), limitadas.
var applied_up: Array = []
var applied_down: Array = []
const MAX_SAMPLES := 4096

## Perfis nomeados (RTT-alvo = ida + volta; o jitter é somado por sentido).
const PROFILES := {
	"local": {"up": 0.0, "down": 0.0, "jitter": 0.0},
	"rtt80": {"up": 40.0, "down": 40.0, "jitter": 0.0},
	"rtt150j": {"up": 65.0, "down": 65.0, "jitter": 20.0},
	"rtt150j_stall": {"up": 65.0, "down": 65.0, "jitter": 20.0, "stall_at": 4000.0, "stall": 400.0},
}

func _init(real_peer: MultiplayerPeer, profile: String, seed_value: int) -> void:
	inner = real_peer
	profile_name = profile
	var values: Dictionary = PROFILES.get(profile, PROFILES["local"])
	up_ms = float(values.get("up", 0.0))
	down_ms = float(values.get("down", 0.0))
	jitter_ms = float(values.get("jitter", 0.0))
	stall_at_ms = float(values.get("stall_at", -1.0))
	stall_ms = float(values.get("stall", 0.0))
	_rng.seed = seed_value
	inner.peer_connected.connect(func(id: int): peer_connected.emit(id))
	inner.peer_disconnected.connect(func(id: int): peer_disconnected.emit(id))

## Interrupção comandada pelo teste: nada é liberado nos próximos `duration_ms`.
func trigger_stall(duration_ms: float) -> void:
	_started_msec = _now()
	stall_at_ms = 0.0
	stall_ms = duration_ms

static func is_known_profile(profile: String) -> bool:
	return PROFILES.has(profile)

func _now() -> float:
	return float(Time.get_ticks_usec()) / 1000.0

## Horário de liberação: base + jitter, nunca antes do anterior (FIFO) e nunca
## dentro da interrupção.
func _release_time(base_ms: float, last: float) -> float:
	var now := _now()
	var release := now + base_ms + (_rng.randf() * jitter_ms if jitter_ms > 0.0 else 0.0)
	if stall_at_ms >= 0.0 and _started_msec >= 0.0:
		var stall_start := _started_msec + stall_at_ms
		var stall_end := stall_start + stall_ms
		if release >= stall_start and release < stall_end:
			release = stall_end
	return maxf(release, last)

func _record(samples: Array, value: float) -> void:
	if samples.size() < MAX_SAMPLES:
		samples.append(value)

func _poll() -> void:
	if _started_msec < 0.0 and inner.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_started_msec = _now()
	_flush_outgoing()
	inner.poll()
	while inner.get_available_packet_count() > 0:
		var peer_id := inner.get_packet_peer()
		var channel := inner.get_packet_channel()
		var mode := inner.get_packet_mode()
		var data := inner.get_packet()
		_last_in_release = _release_time(down_ms, _last_in_release)
		_incoming.append({"peer": peer_id, "channel": channel, "mode": mode, "data": data,
			"release": _last_in_release, "queued": _now()})

## Entrega ao peer real o que já venceu. Sem atraso configurado, o pacote segue
## na mesma chamada, como sem o invólucro.
func _flush_outgoing() -> void:
	var now := _now()
	while not _outgoing.is_empty() and float(_outgoing[0]["release"]) <= now:
		var item: Dictionary = _outgoing.pop_front()
		if inner.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			continue
		inner.transfer_channel = int(item["channel"])
		inner.transfer_mode = int(item["mode"])
		inner.set_target_peer(int(item["target"]))
		inner.put_packet(item["data"])
		_record(applied_up, now - float(item["queued"]))

func _released_incoming() -> int:
	var now := _now()
	var count := 0
	for item in _incoming:
		if float(item["release"]) > now:
			break
		count += 1
	return count

func _get_available_packet_count() -> int:
	return _released_incoming()

func _get_packet_script() -> PackedByteArray:
	if _released_incoming() == 0:
		return PackedByteArray()
	var item: Dictionary = _incoming.pop_front()
	_record(applied_down, _now() - float(item["queued"]))
	return item["data"]

func _get_packet_peer() -> int:
	return int(_incoming[0]["peer"]) if not _incoming.is_empty() else 0

func _get_packet_channel() -> int:
	return int(_incoming[0]["channel"]) if not _incoming.is_empty() else 0

func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return int(_incoming[0]["mode"]) if not _incoming.is_empty() else MultiplayerPeer.TRANSFER_MODE_RELIABLE

func _put_packet_script(buffer: PackedByteArray) -> Error:
	_last_out_release = _release_time(up_ms, _last_out_release)
	_outgoing.append({"data": buffer, "target": _target_peer, "mode": _transfer_mode,
		"channel": _transfer_channel, "release": _last_out_release, "queued": _now()})
	_flush_outgoing()
	return OK

func _set_target_peer(peer: int) -> void:
	_target_peer = peer

func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_transfer_mode = mode

func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _transfer_mode

func _set_transfer_channel(channel: int) -> void:
	_transfer_channel = channel

func _get_transfer_channel() -> int:
	return _transfer_channel

func _get_max_packet_size() -> int:
	return inner.get_max_packet_size() if inner.has_method("get_max_packet_size") else 1 << 20

func _get_unique_id() -> int:
	return inner.get_unique_id()

func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return inner.get_connection_status()

func _is_server() -> bool:
	return inner.get_unique_id() == 1

func _is_server_relay_supported() -> bool:
	return false

func _is_refusing_new_connections() -> bool:
	return inner.refuse_new_connections

func _set_refuse_new_connections(enable: bool) -> void:
	inner.refuse_new_connections = enable

func _close() -> void:
	_outgoing.clear()
	_incoming.clear()
	inner.close()

func _disconnect_peer(peer: int, force: bool) -> void:
	inner.disconnect_peer(peer, force)

## Resumo do atraso aplicado (p50/p95/máx por sentido), para o log do teste.
func summary() -> String:
	return "profile=%s up_ms=%.0f down_ms=%.0f jitter_ms=%.0f up=%s down=%s" % [
		profile_name, up_ms, down_ms, jitter_ms, _stats(applied_up), _stats(applied_down)]

static func _stats(samples: Array) -> String:
	if samples.is_empty():
		return "n=0"
	var sorted := samples.duplicate()
	sorted.sort()
	var p50: float = sorted[int(sorted.size() * 0.5)]
	var p95: float = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))]
	return "n=%d,p50=%.1f,p95=%.1f,max=%.1f" % [sorted.size(), p50, p95, float(sorted[-1])]
