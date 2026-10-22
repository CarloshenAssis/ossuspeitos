extends SceneTree
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("ENVIRONMENT_WIRE_ASSERT "+label)
func _initialize() -> void:
	var rules=load("res://shared/environment_rules.gd")
	check(rules.has_method("encode_wire"),"compact authoritative environment codec exists")
	if not rules.has_method("encode_wire"):
		quit(1)
		return
	var state={"round_id":3,"revision":17,"objects":rules.initial_objects()}
	state.objects[0].open=false
	state.objects[20].position=Vector3(3.3,1.1,3.5)
	state.objects[20].holder=15
	state.objects[21].velocity=Vector3(1,0,0)
	var encoded: Array=rules.encode_wire(state)
	check(rules.decode_wire(encoded)==state,"all shared authoritative data roundtrips exactly")
	check(var_to_bytes(encoded).size()<var_to_bytes(state).size()/3,"static catalog not retransmitted as dictionaries")
	for bad in [null,{},[],[1],[1,1,-1,[]],[1,1,1<<25,[]],[1,1,0,[]],[1,1,0,[[Vector3.INF,Vector3.ZERO,0]]]]:
		check(rules.decode_wire(bad).is_empty(),"malformed environment wire rejected")
	var sound_rules=load("res://shared/sound_event_rules.gd")
	var events: Array=[]
	for index in 32: events.append(SoundEventRules.make(index+1,3,SoundEventRules.KINDS[index%SoundEventRules.KINDS.size()],Vector3(3,1,3),index%8+1))
	var sounds: Array=sound_rules.encode_wire(events)
	check(sound_rules.decode_wire(sounds)==events,"sound ids kind position and peer roundtrip exactly")
	check(var_to_bytes(sounds).size()<var_to_bytes(events).size()/2,"event keys and repeated round ids not retransmitted")
	check(sound_rules.decode_wire([]).is_empty(),"empty sound ring valid")
	for bad in [null,{},[1,1],[1,-1,[]],[1,1,[[999,Vector3.ZERO,1]]],[1,1,[[0,Vector3.INF,1]]],[1,1,[[0,Vector3.ZERO,-1]]]]:
		check(sound_rules.decode_wire(bad).is_empty(),"malformed sound wire rejected")
	var gap:=events.duplicate(true);gap[3].id=99
	check(sound_rules.encode_wire(gap).is_empty(),"codec refuses discontinuous event ids")
	check(rules.sanitize(state)==state,"codec leaves DTO contract unchanged")
	print("ENVIRONMENT_WIRE_TEST_%s checks=%d failures=%d"%["OK" if failures==0 else "FAILED",checks,failures])
	quit(0 if failures==0 else 1)
