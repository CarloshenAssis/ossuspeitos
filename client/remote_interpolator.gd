class_name RemoteInterpolator
extends RefCounted

## Apresentação dos outros jogadores (fase 4): buffer limitado de amostras
## oficiais por jogador e um relógio de apresentação monotônico em ticks do
## servidor, atrasado de `delay()` em relação ao tick estimado.
##
## O relógio local avança pelo `delta` de cada quadro (nunca pelo relógio de
## outra máquina); o deslocamento para o tick do servidor é estimado a partir
## das chegadas e corrigido no máximo ±10% de velocidade, com ressincronização
## só acima de `CLOCK_RESYNC_TICKS`. O atraso cobre dois snapshots mais o
## jitter medido, limitado.
##
## Sem amostra futura: extrapola até `MAX_EXTRAPOLATION_TICKS` com a colisão
## oficial e depois segura. Mudança de época do jogador (reposicionamento,
## entrada de rodada, eliminação) limpa o buffer e marca descontinuidade.
## Entre duas amostras que cortariam uma quina, usa o caminho por eixos ou
## segura na amostra anterior (política conservadora).

var buffers: Dictionary = {}
var epochs: Dictionary = {}
var discontinuities: Dictionary = {}
var local_ticks := 0.0
var render_tick := 0.0
var offset := 0.0
var jitter := 0.0
var has_clock := false
var last_tick := -1
## Instrumentação.
var stale_snapshots := 0
var resyncs := 0
var extrapolated_samples := 0
var held_samples := 0
var corner_paths := 0
var corner_holds := 0

func clear() -> void:
	buffers.clear()
	epochs.clear()
	discontinuities.clear()
	has_clock = false
	last_tick = -1

func remove(peer_id: int) -> void:
	buffers.erase(peer_id)
	epochs.erase(peer_id)
	discontinuities.erase(peer_id)

func delay() -> float:
	return NetSync.INTERP_DELAY_TICKS + clampf(jitter * 2.0, 0.0, NetSync.MAX_JITTER_DELAY_TICKS)

## Um snapshot oficial. Duplicado ou antigo não retrocede nada.
func push(tick: int, players: Array) -> bool:
	if tick <= last_tick:
		stale_snapshots += 1
		return false
	last_tick = tick
	var sample_offset := float(tick) - local_ticks
	if not has_clock:
		has_clock = true
		offset = sample_offset
		render_tick = float(tick) - delay()
	else:
		var deviation := sample_offset - offset
		jitter = lerpf(jitter, absf(deviation), 0.1)
		offset += deviation * 0.05
	for raw in players:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var player: Dictionary = raw
		var peer_id := int(player.get("peer_id", 0))
		var sample_epoch := int(player.get("epoch", 0))
		if not buffers.has(peer_id) or int(epochs.get(peer_id, sample_epoch)) != sample_epoch:
			if buffers.has(peer_id):
				discontinuities[peer_id] = true
			buffers[peer_id] = []
		epochs[peer_id] = sample_epoch
		var buffer: Array = buffers[peer_id]
		# Salto impossível entre amostras seguidas (reposicionamento sem época,
		# como a preparação direta de teste): também é descontinuidade. A época
		# continua sendo o sinal principal.
		if not buffer.is_empty():
			var previous: Dictionary = buffer[-1]
			var reach := MovementRules.MAX_SPEED * float(tick - int(previous["tick"])) / NetSync.TICK_RATE * 1.5 + 0.5
			if (previous["position"] as Vector3).distance_to(player["position"]) > reach:
				discontinuities[peer_id] = true
				buffer.clear()
		buffer.append({"tick": tick, "position": player["position"], "velocity": player.get("velocity", Vector3.ZERO),
			"yaw": float(player.get("yaw", 0.0)), "pitch": MovementRules.clamp_pitch(player.get("pitch", 0.0))})
		while buffer.size() > NetSync.MAX_REMOTE_SAMPLES:
			buffer.pop_front()
	return true

## Avança o relógio de apresentação (monotônico) pelo tempo do quadro.
func advance(delta: float) -> void:
	local_ticks += delta * NetSync.TICK_RATE
	if not has_clock:
		return
	var nominal := render_tick + delta * NetSync.TICK_RATE
	var target := local_ticks + offset - delay()
	var error := target - nominal
	if absf(error) > NetSync.CLOCK_RESYNC_TICKS:
		resyncs += 1
		render_tick = maxf(render_tick, target)
		return
	var limit := NetSync.CLOCK_ADJUST_RATE * delta * NetSync.TICK_RATE
	render_tick = maxf(render_tick, nominal + clampf(error, -limit, limit))

## Tick sintético para quem aplica snapshots sem tick (demo offline, testes):
## a chegada no relógio local, sempre crescente.
func synthetic_tick() -> int:
	return maxi(last_tick + 1, int(round(local_ticks)))

## Apresentação de um jogador no `render_tick` atual. Vazio sem amostras.
## `discontinuity` vem verdadeiro uma única vez após reset do buffer.
func sample(peer_id: int) -> Dictionary:
	var buffer: Array = buffers.get(peer_id, [])
	if buffer.is_empty():
		return {}
	var discontinuity := bool(discontinuities.get(peer_id, false))
	discontinuities.erase(peer_id)
	# Descarta amostras que já não servem (mantém uma antes do relógio).
	while buffer.size() > 2 and float(buffer[1]["tick"]) <= render_tick:
		buffer.pop_front()
	var first: Dictionary = buffer[0]
	if render_tick <= float(first["tick"]):
		held_samples += 1
		return _result(first["position"], first["yaw"], first["pitch"], first["velocity"], "hold", discontinuity)
	if buffer.size() >= 2 and render_tick <= float(buffer[1]["tick"]):
		var a: Dictionary = buffer[0]
		var b: Dictionary = buffer[1]
		var span := maxf(float(b["tick"]) - float(a["tick"]), 0.0001)
		var t := clampf((render_tick - float(a["tick"])) / span, 0.0, 1.0)
		var position := _safe_lerp(a["position"], b["position"], t)
		var yaw := lerp_angle(float(a["yaw"]), float(b["yaw"]), t)
		var pitch := lerpf(float(a["pitch"]), float(b["pitch"]), t)
		var velocity: Vector3 = (a["velocity"] as Vector3).lerp(b["velocity"], t)
		return _result(position, yaw, pitch, velocity, "interpolate", discontinuity)
	var last: Dictionary = buffer[-1]
	var ahead := render_tick - float(last["tick"])
	var velocity: Vector3 = last["velocity"]
	if ahead <= NetSync.MAX_EXTRAPOLATION_TICKS and velocity.length_squared() > 0.0001:
		extrapolated_samples += 1
		var moved: Vector3 = MovementRules.resolve_step(last["position"], velocity * (ahead / NetSync.TICK_RATE))["position"]
		return _result(moved, last["yaw"], last["pitch"], velocity, "extrapolate", discontinuity)
	held_samples += 1
	var capped := minf(ahead, NetSync.MAX_EXTRAPOLATION_TICKS)
	var held: Vector3 = last["position"]
	if velocity.length_squared() > 0.0001:
		held = MovementRules.resolve_step(last["position"], velocity * (capped / NetSync.TICK_RATE))["position"]
	return _result(held, last["yaw"], last["pitch"], Vector3.ZERO, "hold", discontinuity)

func _result(position: Vector3, yaw: float, pitch: float, velocity: Vector3, mode: String, discontinuity: bool) -> Dictionary:
	return {"position": position, "yaw": yaw, "pitch": pitch, "velocity": velocity, "mode": mode,
		"discontinuity": discontinuity}

## Interpolação que não corta quina: se o ponto reto entra num volume oficial
## (com o raio do corpo apresentado), segue o caminho em L por um dos eixos;
## se os dois entrarem, segura na amostra mais próxima.
func _safe_lerp(from: Vector3, to: Vector3, t: float) -> Vector3:
	var straight := from.lerp(to, t)
	if not ArenaRules.overlaps_blocker(straight, NetSync.PRESENTATION_BODY_RADIUS):
		return straight
	for corner in [Vector3(to.x, from.y, from.z), Vector3(from.x, from.y, to.z)]:
		var point := _along_path(from, corner, to, t)
		if not ArenaRules.overlaps_blocker(point, NetSync.PRESENTATION_BODY_RADIUS):
			corner_paths += 1
			return point
	corner_holds += 1
	return from if t < 0.5 else to

static func _along_path(from: Vector3, corner: Vector3, to: Vector3, t: float) -> Vector3:
	var first := from.distance_to(corner)
	var second := corner.distance_to(to)
	var total := first + second
	if total <= 0.0001:
		return to
	var distance := t * total
	if distance <= first:
		return from.lerp(corner, distance / maxf(first, 0.0001))
	return corner.lerp(to, (distance - first) / maxf(second, 0.0001))

## Ocupação média do buffer e atraso efetivo (instrumentação).
func stats() -> Dictionary:
	var total := 0
	for buffer in buffers.values():
		total += (buffer as Array).size()
	return {"peers": buffers.size(), "samples": total, "delay_ticks": delay(), "jitter_ticks": jitter,
		"lead_ticks": (local_ticks + offset) - render_tick, "stale": stale_snapshots, "resyncs": resyncs,
		"extrapolated": extrapolated_samples, "held": held_samples, "corner_paths": corner_paths, "corner_holds": corner_holds}
