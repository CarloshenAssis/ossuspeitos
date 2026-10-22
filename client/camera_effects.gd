extends RefCounted
## Pure viewmodel presentation. Never receives or writes authoritative state.
const MAX_SPEED := 6.0
const RESPONSE := 12.0
const FREQUENCY := 9.0
var strength := 1.0
var _time := 0.0
var _amplitude := 0.0
func reset() -> void:
	_time = 0.0
	_amplitude = 0.0
func sample(speed: float, delta: float) -> Transform3D:
	if not is_finite(strength) or strength <= 0.0:
		reset()
		return Transform3D.IDENTITY
	if not is_finite(speed) or not is_finite(delta) or delta < 0.0:
		reset()
		return Transform3D.IDENTITY
	_time += delta
	_amplitude = lerpf(_amplitude, clampf(speed / MAX_SPEED, 0.0, 1.0), 1.0 - exp(-RESPONSE * delta))
	var amount := _amplitude * clampf(strength, 0.0, 1.0)
	var phase := _time * FREQUENCY
	var offset := Vector3(sin(phase) * 0.009, sin(phase * 2.0) * 0.006, 0.0) * amount
	return Transform3D(Basis.from_euler(Vector3(0.0, sin(phase) * 0.012, cos(phase) * 0.009) * amount), offset)
