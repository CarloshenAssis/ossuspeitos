extends SceneTree
## Same deterministic model workload can run from the frozen SPEC08 archive.
## Wall CPU-process elapsed and Variant estimates; not socket or GPU metrics.
var room
var phase2 := false
var accepted_interactions := 0
var rejected_commands := 0
var action_id := 0
var active_workload := false
var compact := false
var environment_codec
var sound_codec
const WARMUP := 120
const TICKS := 1200

func _initialize() -> void:
 call_deferred("run")

func _has_property(value: Object, key: String) -> bool:
 for entry in value.get_property_list():
  if str(entry.name)==key: return true
 return false

func _gate(peer: int) -> String:
 if room.round_authority.state!=RoundState.ACTIVE: return "round_not_active"
 if not room.round_authority.is_alive(peer): return "player_dead"
 return ""

func _action(peer: int, action: Dictionary, _seq: int) -> void:
 if phase2 and action.get("kind","")=="interact":
  var result: Dictionary=room.get("interactions").request(peer,action,_now)
  if result.accepted: accepted_interactions+=1

func _reject(_peer: int, _seq: int, _action_value: Dictionary, _reason: String) -> void:
 rejected_commands+=1

var _now := 0
func _tick(index: int, count: int, with_snapshot: bool) -> int:
 _now=2000+int(float(index)*1000.0/60.0)
 var seq := index+1
 for peer in range(1,count+1):
  var move := Vector2.ZERO
  if active_workload and peer!=1:
   move=Vector2(0,-0.6 if (index/60)%2==0 else 0.6)
  var action: Array=[]
  if phase2 and active_workload and peer==1 and index%240==0:
   action_id+=1
   action=["interact",action_id,"prop_escritorio","take" if (index/240)%2==0 else "drop"]
  var epoch: int=room.world.states[peer].epoch
  var command := NetSync.encode_command(move,0.0,0.0,action)
  room.world.receive_commands(peer,NetSync.encode_packet(epoch,seq,[command]),_now)
 if phase2: room.get("interactions").tick(NetSync.TICK_SECONDS)
 room.world.step(_gate,_action,_reject)
 if phase2: room.get("sounds").observe_movement()
 room.combat.tick(_now)
 room.round_authority.tick(_now)
 if not with_snapshot or index%NetSync.SNAPSHOT_INTERVAL_TICKS!=0: return 0
 var bytes := 0
 var states: Array=room.world.snapshot()
 var environment_wire: Array=[]
 var sound_wire: Array=[]
 if compact:
  # Same public-once-per-room hoist as NetworkApp._broadcast_snapshot.
  environment_wire=environment_codec.encode_wire(room.get("interactions").snapshot())
  sound_wire=sound_codec.encode_wire(room.get("sounds").snapshot())
 for peer in range(1,count+1):
  var payload := {"tick":index,"session":123456,"players":states,"ack":room.world.ack_for(peer)}
  if phase2:
   payload.environment=environment_wire if compact else room.get("interactions").snapshot()
   payload.sounds=sound_wire if compact else room.get("sounds").snapshot()
   payload.inspection=room.get("investigations").last_for_peer(peer)
  bytes+=var_to_bytes(payload).size()
 return bytes

func _workload(count: int, active: bool) -> Dictionary:
 room=MatchRoom.new(1,"ABC234",0,false,0.1,1.0,8)
 phase2=_has_property(room,"interactions")
 if phase2:
  environment_codec=load("res://shared/environment_rules.gd")
  sound_codec=load("res://shared/sound_event_rules.gd")
  compact=environment_codec.has_method("encode_wire") and sound_codec.has_method("encode_wire")
 else: compact=false
 active_workload=active
 accepted_interactions=0
 rejected_commands=0
 action_id=0
 for peer in range(1,count+1): room.add_member(peer,"Bench%d" % peer,0)
 room.round_authority.tick(1000)
 room.combat.begin_round(room.round_authority.round_id,room.lobby.peer_ids())
 for peer in range(1,count+1): room.world.reset_to_spawn(peer)
 room.world.teleport(1,Vector3(2.2,1,3.5),-PI/2,0.0)
 if phase2:
  room.get("interactions").reset(room.round_authority.round_id)
  room.get("sounds").reset(room.round_authority.round_id)
 for tick in WARMUP: _tick(tick,count,false)
 var samples: Array[int]=[]
 var total_bytes := 0
 var snapshot_frames := 0
 var memory_before := OS.get_static_memory_usage()
 var objects_before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
 var started := Time.get_ticks_usec()
 for tick in range(WARMUP,WARMUP+TICKS):
  var tick_start := Time.get_ticks_usec()
  total_bytes+=_tick(tick,count,true)
  samples.append(Time.get_ticks_usec()-tick_start)
  if tick%NetSync.SNAPSHOT_INTERVAL_TICKS==0: snapshot_frames+=1
 var elapsed := Time.get_ticks_usec()-started
 var memory_after := OS.get_static_memory_usage()
 var objects_after := int(Performance.get_monitor(Performance.OBJECT_COUNT))
 var env_count := 0
 var sound_count := 0
 if phase2:
  env_count=room.get("interactions").snapshot().objects.size()
  sound_count=room.get("sounds").snapshot().size()
 var simulated := 0
 for state in room.world.states.values(): simulated+=int(state.simulated_commands)
 samples.sort()
 var result := {"phase2":phase2,"wire_encoding":"compact" if compact else "dto","peers":count,"workload":"active" if active else "static","ticks":TICKS,"warmup":WARMUP,"configured_tick_hz":NetSync.TICK_RATE,"configured_snapshot_hz":NetSync.TICK_RATE/NetSync.SNAPSHOT_INTERVAL_TICKS,"elapsed_usec":elapsed,"mean_usec_per_tick":float(elapsed)/TICKS,"p50_usec":samples[599],"p95_usec":samples[1139],"p99_usec":samples[1187],"max_usec":samples[1199],"process_static_memory_before_bytes":memory_before,"process_static_memory_after_bytes":memory_after,"process_static_memory_delta_bytes":int(memory_after)-int(memory_before),"process_objects_before":objects_before,"process_objects_after":objects_after,"estimated_variant_snapshot_bytes_all_recipients":total_bytes,"snapshots_per_recipient":snapshot_frames,"mean_variant_snapshot_bytes_per_recipient":float(total_bytes)/float(snapshot_frames*count),"estimated_variant_bytes_per_second_all_recipients_at_20hz":float(total_bytes)/float(TICKS)*60.0,"simulated_commands_including_warmup":simulated,"accepted_interactions_including_warmup":accepted_interactions,"rejected_commands":rejected_commands,"environment_objects":env_count,"retained_sound_events":sound_count}
 if compact:
  var env_wire: Array=environment_codec.encode_wire(room.get("interactions").snapshot())
  var sounds_wire: Array=sound_codec.encode_wire(room.get("sounds").snapshot())
  var decode_started := Time.get_ticks_usec()
  var decoded_environment: Dictionary={}
  var decoded_sounds: Array=[]
  for iteration in 1000:
   decoded_environment=environment_codec.decode_wire(env_wire)
   decoded_sounds=sound_codec.decode_wire(sounds_wire)
  result["decode_mean_usec_per_snapshot"] = float(Time.get_ticks_usec()-decode_started)/1000.0
  result["decode_iterations"] = 1000
  result["decoded_environment_objects"] = decoded_environment.get("objects",[]).size()
  result["decoded_sound_events"] = decoded_sounds.size()
 room.clear()
 room=null
 return result

func run() -> void:
 var results: Array=[]
 for count in [4,8]:
  for active in [false,true]: results.append(_workload(count,active))
 print("PHASE2_RUNTIME_BENCHMARK ",JSON.stringify({"version":Engine.get_version_info().string,"cpu":OS.get_processor_name(),"results":results}))
 quit()
