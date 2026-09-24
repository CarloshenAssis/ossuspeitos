class_name SfxBank
extends RefCounted

## Sons curtos sintetizados no próprio jogo (PCM 16 bits, mono). Não há arquivo
## de áudio externo nem licença de terceiros: cada som é uma soma simples de
## seno, ruído e envelope exponencial gerada na inicialização. Funciona igual
## no Windows e na Web (AudioStreamWAV em memória).

const MIX_RATE := 22050
## Ruído determinístico: o mesmo som em toda build.
const NOISE_SEED := 20260924

const NAMES := ["shot", "dry_fire", "hit", "hurt", "pickup_ok", "pickup_deny",
	"reload_start", "reload_end", "elimination"]

static var _cache: Dictionary = {}

static func stream(sound_name: String) -> AudioStreamWAV:
	if _cache.is_empty():
		_build_all()
	return _cache.get(sound_name) as AudioStreamWAV

static func _build_all() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = NOISE_SEED
	# Disparo: estalo de ruído com corpo grave, cai em ~0,15 s.
	_cache["shot"] = _render(0.18, func(t: float) -> float:
		return 0.55 * rng.randf_range(-1.0, 1.0) * exp(-t * 32.0) + 0.45 * sin(TAU * 85.0 * t) * exp(-t * 18.0))
	# Gatilho sem munição: clique seco e baixo.
	_cache["dry_fire"] = _render(0.05, func(t: float) -> float:
		return 0.35 * rng.randf_range(-1.0, 1.0) * exp(-t * 180.0) + 0.25 * sin(TAU * 900.0 * t) * exp(-t * 120.0))
	# Acerto confirmado (só quem atirou recebe): "tic" agudo e curto.
	_cache["hit"] = _render(0.08, func(t: float) -> float:
		return 0.3 * (sin(TAU * 1500.0 * t) + 0.5 * sin(TAU * 2250.0 * t)) * exp(-t * 55.0))
	# Dano recebido: baque grave que desce de tom.
	_cache["hurt"] = _render(0.24, func(t: float) -> float:
		var pitch := 75.0 - 30.0 * t / 0.24
		return 0.5 * sin(TAU * pitch * t) * exp(-t * 14.0) + 0.12 * rng.randf_range(-1.0, 1.0) * exp(-t * 40.0))
	# Coleta aceita: duas notas subindo.
	_cache["pickup_ok"] = _render(0.16, func(t: float) -> float:
		var freq := 660.0 if t < 0.07 else 990.0
		var local := t if t < 0.07 else t - 0.07
		return 0.22 * sin(TAU * freq * t) * exp(-local * 30.0))
	# Ação recusada: dois pulsos graves e ásperos (nunca soa como sucesso).
	_cache["pickup_deny"] = _render(0.2, func(t: float) -> float:
		var gate := 1.0 if fmod(t, 0.1) < 0.06 else 0.0
		return 0.2 * gate * signf(sin(TAU * 140.0 * t)) * exp(-fmod(t, 0.1) * 20.0))
	# Início da recarga: pente saindo.
	_cache["reload_start"] = _render(0.09, func(t: float) -> float:
		return 0.3 * rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) + 0.2 * sin(TAU * 420.0 * t) * exp(-t * 60.0))
	# Fim da recarga: pente entrando e ferrolho (dois cliques).
	_cache["reload_end"] = _render(0.16, func(t: float) -> float:
		var local := t if t < 0.07 else t - 0.07
		return 0.32 * rng.randf_range(-1.0, 1.0) * exp(-local * 110.0) + 0.18 * sin(TAU * 620.0 * t) * exp(-local * 70.0))
	# Eliminação pública: tom neutro que desce (igual para qualquer papel).
	_cache["elimination"] = _render(0.4, func(t: float) -> float:
		var pitch := 420.0 - 240.0 * t / 0.4
		return 0.22 * sin(TAU * pitch * t) * exp(-t * 6.0))

static func _render(seconds: float, sample: Callable) -> AudioStreamWAV:
	var count := int(seconds * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for index in count:
		var t := float(index) / MIX_RATE
		# Rampa de 3 ms nas pontas: sem estalo de corte.
		var edge := minf(1.0, minf(t, seconds - t) / 0.003)
		var value := clampf(float(sample.call(t)) * edge, -1.0, 1.0)
		data.encode_s16(index * 2, int(value * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
