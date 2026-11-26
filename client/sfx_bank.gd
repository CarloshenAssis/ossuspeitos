class_name SfxBank
extends RefCounted

## Banco de sons: arquivos OGG CC0 em `res://assets/audio/`, com síntese PCM
## de reserva se o arquivo não estiver importado (testes headless, Web Demo).

const MIX_RATE := 22050
const NOISE_SEED := 20260924
const AUDIO_DIR := "res://assets/audio"

const NAMES := ["shot", "shot_pistol", "shot_rifle", "shot_aug", "dry_fire", "hit",
	"hurt", "pickup_ok", "pickup_deny", "pickup_weapon", "pickup_ammo", "pickup_health",
	"reload_start", "reload_end", "elimination", "ui_move", "ui_confirm", "ui_error",
	"step_walk", "step_run", "door", "impact", "handle"]

const FILES := {
	"shot": "shot_pistol.ogg",
	"shot_pistol": "shot_pistol.ogg",
	"shot_rifle": "shot_rifle.ogg",
	"shot_aug": "shot_aug.ogg",
	"dry_fire": "dry_fire.ogg",
	"hit": "hit.ogg",
	"hurt": "hurt.ogg",
	"pickup_ok": "pickup_ok.ogg",
	"pickup_deny": "pickup_deny.ogg",
	"pickup_weapon": "pickup_weapon.ogg",
	"pickup_ammo": "pickup_ammo.ogg",
	"pickup_health": "pickup_health.ogg",
	"reload_start": "reload_start.ogg",
	"reload_end": "reload_end.ogg",
	"elimination": "elimination.ogg",
	"ui_move": "ui_move.ogg",
	"ui_confirm": "ui_confirm.ogg",
	"ui_error": "ui_error.ogg",
	"step_walk": "step_walk.ogg",
	"step_run": "step_run.ogg",
	"door": "door.ogg",
	"impact": "impact.ogg",
	"handle": "handle.ogg",
}

const AMBIENT_PATH := "res://assets/audio/ambient_mansion.ogg"

# Só a síntese de reserva fica em estático. Arquivos importados não podem
# ficar presos aqui: o Godot reporta "resources still in use at exit" e o
# matrix da fase 2 trata isso como falha.
static var _synth: Dictionary = {}

static func shot_for(weapon_id: String) -> String:
	match weapon_id:
		"hunting_rifle":
			return "shot_rifle"
		"aug":
			return "shot_aug"
		_:
			return "shot"

static func stream(sound_name: String) -> AudioStream:
	var file_name := str(FILES.get(sound_name, ""))
	if not file_name.is_empty():
		var loaded := _load_file("%s/%s" % [AUDIO_DIR, file_name])
		if loaded != null:
			return loaded
	if _synth.is_empty():
		_build_synth()
	return _synth.get(sound_name) as AudioStream

static func ambient_stream() -> AudioStream:
	return _load_file(AMBIENT_PATH)

static func _load_file(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var resource := load(path)
	return resource as AudioStream

static func _build_synth() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = NOISE_SEED
	_synth["shot"] = _render(0.18, func(t: float) -> float:
		return 0.55 * rng.randf_range(-1.0, 1.0) * exp(-t * 32.0) + 0.45 * sin(TAU * 85.0 * t) * exp(-t * 18.0))
	_synth["shot_pistol"] = _synth["shot"]
	_synth["shot_rifle"] = _render(0.22, func(t: float) -> float:
		return 0.6 * rng.randf_range(-1.0, 1.0) * exp(-t * 22.0) + 0.4 * sin(TAU * 60.0 * t) * exp(-t * 12.0))
	_synth["shot_aug"] = _render(0.14, func(t: float) -> float:
		return 0.5 * rng.randf_range(-1.0, 1.0) * exp(-t * 38.0) + 0.35 * sin(TAU * 110.0 * t) * exp(-t * 20.0))
	_synth["dry_fire"] = _render(0.05, func(t: float) -> float:
		return 0.35 * rng.randf_range(-1.0, 1.0) * exp(-t * 180.0) + 0.25 * sin(TAU * 900.0 * t) * exp(-t * 120.0))
	_synth["hit"] = _render(0.08, func(t: float) -> float:
		return 0.3 * (sin(TAU * 1500.0 * t) + 0.5 * sin(TAU * 2250.0 * t)) * exp(-t * 55.0))
	_synth["hurt"] = _render(0.24, func(t: float) -> float:
		var pitch := 75.0 - 30.0 * t / 0.24
		return 0.5 * sin(TAU * pitch * t) * exp(-t * 14.0) + 0.12 * rng.randf_range(-1.0, 1.0) * exp(-t * 40.0))
	_synth["pickup_ok"] = _render(0.16, func(t: float) -> float:
		var freq := 660.0 if t < 0.07 else 990.0
		var local := t if t < 0.07 else t - 0.07
		return 0.22 * sin(TAU * freq * t) * exp(-local * 30.0))
	_synth["pickup_weapon"] = _synth["pickup_ok"]
	_synth["pickup_ammo"] = _render(0.14, func(t: float) -> float:
		return 0.2 * sin(TAU * 880.0 * t) * exp(-t * 24.0) + 0.12 * rng.randf_range(-1.0, 1.0) * exp(-t * 80.0))
	_synth["pickup_health"] = _render(0.18, func(t: float) -> float:
		var freq := 523.0 if t < 0.08 else 784.0
		var local := t if t < 0.08 else t - 0.08
		return 0.2 * sin(TAU * freq * t) * exp(-local * 22.0))
	_synth["pickup_deny"] = _render(0.2, func(t: float) -> float:
		var gate := 1.0 if fmod(t, 0.1) < 0.06 else 0.0
		return 0.2 * gate * signf(sin(TAU * 140.0 * t)) * exp(-fmod(t, 0.1) * 20.0))
	_synth["reload_start"] = _render(0.09, func(t: float) -> float:
		return 0.3 * rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) + 0.2 * sin(TAU * 420.0 * t) * exp(-t * 60.0))
	_synth["reload_end"] = _render(0.16, func(t: float) -> float:
		var local := t if t < 0.07 else t - 0.07
		return 0.32 * rng.randf_range(-1.0, 1.0) * exp(-local * 110.0) + 0.18 * sin(TAU * 620.0 * t) * exp(-local * 70.0))
	_synth["elimination"] = _render(0.4, func(t: float) -> float:
		var pitch := 420.0 - 240.0 * t / 0.4
		return 0.22 * sin(TAU * pitch * t) * exp(-t * 6.0))
	_synth["ui_move"] = _render(0.05, func(t: float) -> float:
		return 0.08 * sin(TAU * 520.0 * t) * exp(-t * 90.0))
	_synth["ui_confirm"] = _render(0.18, func(t: float) -> float:
		var freq := 392.0 if t < 0.07 else 523.0
		var local := t if t < 0.07 else t - 0.07
		return 0.12 * sin(TAU * freq * t) * exp(-local * 22.0))
	_synth["ui_error"] = _render(0.22, func(t: float) -> float:
		var pitch := 300.0 - 90.0 * t / 0.22
		return 0.12 * sin(TAU * pitch * t) * exp(-t * 12.0))
	_synth["step_walk"] = _render(0.08, func(t: float) -> float:
		return 0.25 * (sin(TAU * 95.0 * t) + 0.35 * sin(TAU * 95.0 * 2.7 * t)) * exp(-t * 32.0))
	_synth["step_run"] = _render(0.07, func(t: float) -> float:
		return 0.3 * (sin(TAU * 120.0 * t) + 0.35 * sin(TAU * 120.0 * 2.7 * t)) * exp(-t * 36.0))
	_synth["door"] = _render(0.18, func(t: float) -> float:
		return 0.25 * (sin(TAU * 180.0 * t) + 0.35 * sin(TAU * 180.0 * 2.7 * t)) * exp(-t * 32.0))
	_synth["impact"] = _render(0.18, func(t: float) -> float:
		return 0.25 * (sin(TAU * 65.0 * t) + 0.35 * sin(TAU * 65.0 * 2.7 * t)) * exp(-t * 32.0))
	_synth["handle"] = _render(0.12, func(t: float) -> float:
		return 0.22 * rng.randf_range(-1.0, 1.0) * exp(-t * 70.0) + 0.15 * sin(TAU * 480.0 * t) * exp(-t * 50.0))

static func _render(seconds: float, sample: Callable) -> AudioStreamWAV:
	var count := int(seconds * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for index in count:
		var t := float(index) / MIX_RATE
		var edge := minf(1.0, minf(t, seconds - t) / 0.003)
		var value := clampf(float(sample.call(t)) * edge, -1.0, 1.0)
		data.encode_s16(index * 2, int(value * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
