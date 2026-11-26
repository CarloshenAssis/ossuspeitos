class_name SpatialAudioController
extends Node3D

## Fixed-size voice pool; no per-event nodes. Streams come from SfxBank (OGG or synth).
const MAX_VOICES := 12
const MAX_DISTANCE := 24.0
var movement_volume := 0.8
var environment_volume := 0.8
var combat_volume := 0.8
var occlusion_enabled := false
var _round_id := 0
var _last_id := 0
var _voice_index := 0
var _priorities: Array=[]
var _streams: Dictionary={}
var played_events := 0
var dropped_events := 0
func _ready() -> void:
	for index in MAX_VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.max_distance=MAX_DISTANCE
		voice.unit_size=4.0
		add_child(voice)
		_priorities.append(0)
func configure(movement: float, environment: float, combat: float=0.8) -> void:
	movement_volume=clampf(movement,0.0,1.0) if is_finite(movement) else 0.8
	environment_volume=clampf(environment,0.0,1.0) if is_finite(environment) else 0.8
	combat_volume=clampf(combat,0.0,1.0) if is_finite(combat) else 0.8
	# Live muting must also stop a sound already playing.
	for voice in get_children(): voice.stop()
func reset(round_id: int=0) -> void:
	_round_id=round_id
	_last_id=0
	for voice in get_children(): voice.stop()
func prime(events: Array, round_id: int) -> void:
	reset(round_id)
	for raw in events:
		var event := SoundEventRules.sanitize(raw)
		if not event.is_empty() and event.round_id==round_id: _last_id=maxi(_last_id,int(event.id))
func attenuation(listener: Vector3, source: Vector3, blockers: Array) -> float:
	var distance := listener.distance_to(source)
	if distance>=MAX_DISTANCE: return 0.0
	var gain := 1.0/(1.0+distance*0.15)
	var direction := source-listener
	if distance>0.01:
		var wall := ArenaRules.first_blocker_distance(listener,direction/distance,distance)
		var object := EnvironmentRules.first_hit(listener,direction/distance,distance,blockers)
		if (wall>=0 and wall<distance-0.05) or (object>=0 and object<distance-0.05): gain*=0.35
	return gain
func consume(events: Variant, round_id: int, listener: Vector3, own_peer: int, blockers: Array) -> int:
	if typeof(events)!=TYPE_ARRAY or (events as Array).size()>SoundEventRules.MAX_EVENTS or round_id<=0 or not listener.is_finite(): return 0
	if round_id<_round_id: return 0
	if round_id!=_round_id: reset(round_id)
	var count := 0
	for raw in events:
		var event := SoundEventRules.sanitize(raw)
		if event.is_empty() or event.round_id!=round_id or event.id<=_last_id: continue
		_last_id=event.id
		if event.kind=="reload" and event.peer_id==own_peer: continue
		var category := SoundEventRules.category(event.kind)
		var volume := combat_volume if category=="combat" else (movement_volume if category=="movement" else environment_volume)
		if volume<=0 or listener.distance_to(event.position)>=MAX_DISTANCE: continue
		var priority := SoundEventRules.priority(event.kind)
		var slot := -1
		for offset in MAX_VOICES:
			var candidate := (_voice_index+offset)%MAX_VOICES
			var player := get_child(candidate) as AudioStreamPlayer3D
			if not player.playing or int(_priorities[candidate])<=priority:
				slot=candidate
				break
		if slot<0:
			dropped_events+=1
			continue
		var voice := get_child(slot) as AudioStreamPlayer3D
		voice.stop()
		voice.stream=_stream(event.kind)
		voice.global_position=event.position
		var gain := attenuation(listener,event.position,blockers) if occlusion_enabled else 1.0
		voice.volume_db=linear_to_db(maxf(0.0001,volume*gain))-10.0
		_priorities[slot]=priority
		_voice_index=(slot+1)%MAX_VOICES
		if DisplayServer.get_name() != "headless":
			voice.play()
		played_events+=1
		count+=1
	return count
func _stream(kind: String) -> AudioStream:
	var name := "reload_start" if kind == "reload" else kind
	var sound := SfxBank.stream(name)
	if sound != null:
		return sound
	if _streams.has(kind):
		return _streams[kind]
	var fallback := SfxBank.stream("step_walk")
	_streams[kind] = fallback
	return fallback
func _exit_tree() -> void:
	for voice in get_children():
		if voice is AudioStreamPlayer3D:
			voice.stop()
			voice.stream = null
	_streams.clear()
