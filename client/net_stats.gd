class_name NetStats
extends RefCounted

## Instrumentação de desenvolvimento/teste da fase 4. Só acumula contagens e
## amostras limitadas; o resumo sai em uma linha quando pedido (teste com
## `--net-stats`, ou no encerramento), nunca por quadro. Sem papéis nem dados
## privados de outros jogadores.

const MAX_SAMPLES := 512

var look_latency_ms: Array = []
var snapshot_interval_ms: Array = []
var action_result_ms: Array = []
var rejections: Dictionary = {}
var sent_commands := 0
var sent_packets := 0
var max_pending := 0
var max_pending_age_ms := 0.0
var snapshots := 0
var stale_snapshots := 0
var foreign_session_snapshots := 0
var _last_snapshot_usec := 0
var _action_started: Dictionary = {}

func record(samples: Array, value: float) -> void:
	if samples.size() >= MAX_SAMPLES:
		samples.pop_front()
	samples.append(value)

func count_rejection(reason: String) -> void:
	rejections[reason] = int(rejections.get(reason, 0)) + 1

func snapshot_received() -> void:
	var now := Time.get_ticks_usec()
	if _last_snapshot_usec > 0:
		record(snapshot_interval_ms, float(now - _last_snapshot_usec) / 1000.0)
	_last_snapshot_usec = now
	snapshots += 1

func snapshot_age_ms() -> float:
	return float(Time.get_ticks_usec() - _last_snapshot_usec) / 1000.0 if _last_snapshot_usec > 0 else -1.0

func pending_observed(count: int, oldest_age_usec: int) -> void:
	max_pending = maxi(max_pending, count)
	max_pending_age_ms = maxf(max_pending_age_ms, float(oldest_age_usec) / 1000.0)

## Ação local → primeiro resultado oficial (tiro público do próprio jogador,
## recusa explícita ou estado privado), distinto do efeito local previsto.
func action_started(kind: String, id: int) -> void:
	if _action_started.size() < 64:
		_action_started["%s:%d" % [kind, id]] = Time.get_ticks_usec()

func action_resolved(kind: String, id: int) -> void:
	var key := "%s:%d" % [kind, id]
	if _action_started.has(key):
		record(action_result_ms, float(Time.get_ticks_usec() - int(_action_started[key])) / 1000.0)
		_action_started.erase(key)

func oldest_action(kind: String) -> int:
	var best := -1
	for key in _action_started:
		var parts := str(key).split(":")
		if parts[0] == kind and (best < 0 or int(parts[1]) < best):
			best = int(parts[1])
	return best

func clear_actions() -> void:
	_action_started.clear()

static func describe(samples: Array) -> String:
	if samples.is_empty():
		return "n=0"
	var sorted := samples.duplicate()
	sorted.sort()
	return "n=%d,p50=%.1f,p95=%.1f,max=%.1f" % [sorted.size(), float(sorted[int(sorted.size() * 0.5)]),
		float(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))]), float(sorted[-1])]

func summary(prediction: PlayerPrediction, interpolator: RemoteInterpolator) -> String:
	var parts: Array = [
		"sent=%d packets=%d ack=%d pending=%d max_pending=%d max_pending_age_ms=%.0f" % [
			sent_commands, sent_packets, prediction.last_ack, prediction.pending.size(), max_pending, max_pending_age_ms],
		"snapshots=%d stale=%d foreign=%d interval_ms=%s" % [snapshots, stale_snapshots, foreign_session_snapshots, describe(snapshot_interval_ms)],
		"ack_error_m=%s ack_error_look=%s" % [describe(prediction.ack_errors_position), describe(prediction.ack_errors_look)],
		"corrections_small=%d corrections_large=%d look_corrections=%d recoveries=%d epoch_resets=%d local_rejections=%d" % [
			prediction.corrections_small, prediction.corrections_large, prediction.look_corrections, prediction.recoveries,
			prediction.epoch_resets, prediction.local_rejections],
		"look_to_frame_ms=%s action_to_result_ms=%s" % [describe(look_latency_ms), describe(action_result_ms)],
		"rejections=%s" % JSON.stringify(rejections),
	]
	if interpolator != null:
		parts.append("interp=%s" % JSON.stringify(interpolator.stats()))
	return " ".join(parts)
