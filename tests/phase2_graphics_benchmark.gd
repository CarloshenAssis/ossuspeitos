extends Node3D
## Loaded presentation fixture, not gameplay authority or native-GPU certification.
var view: ArenaView
var room
var phase2 := false
var frozen: Array=[]
var visual_states: Array=[]
var environment: Dictionary={}
var samples: Array[float]=[]
var frame := 0
var previous := 0
var profile := "baseline"
var screenshot := ""
var sound_id := 0
var aim_origin: Vector3
var aim_direction: Vector3
var failures := 0
const WARMUP := 120
const SAMPLES := 300
func _ready() -> void:
 if DisplayServer.get_name() in ["headless","dummy"]:
  push_error("PHASE2_GRAPHICS_REJECTED headless")
  get_tree().quit(2)
  return
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--profile="): profile=arg.trim_prefix("--profile=")
  if arg.begins_with("--screenshot="): screenshot=arg.trim_prefix("--screenshot=")
 DisplayServer.window_set_size(Vector2i(960,540))
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 room=MatchRoom.new(1,"ABC234",0,false,0.1,1.0,8)
 for peer in range(1,9): room.add_member(peer,"Bench%d" % peer,0)
 room.round_authority.tick(1000)
 for entry in room.get_property_list():
  if str(entry.name)=="interactions": phase2=true
 if phase2:
  room.get("interactions").reset(room.round_authority.round_id)
  environment=room.get("interactions").snapshot()
 for peer in range(1,9):
  room.world.teleport(peer,Vector3(9.5+float((peer-1)%4)*1.3,1,9.0+floorf(float(peer-1)/4.0)*1.4),PI)
 frozen=room.world.snapshot().duplicate(true)
 visual_states=frozen.duplicate(true)
 view=ArenaView.new()
 add_child(view)
 view.set_process(false)
 view.local_peer_id=99
 view.player_rig.position=Vector3(12,1,13)
 view.player_rig.rotation.y=0
 view.camera.current=true
 view.set_graphics_profile(profile)
 view.apply_snapshot(visual_states,0)
 view.apply_combat_state({"weapon_id":"common_pistol","magazine":6,"reserve":18,"reloading":false})
 if phase2:
  view.call("apply_environment",environment)
  view.call("apply_inspection",{"request_id":1,"round_id":1,"body_id":1,"label":"Bench body","condition":"eliminado"})
 var body := BodyRules.make(1,1,20,Vector3(10,1,11.7),0.0,"default")
 view.add_body(body)
 view._process(0.0)
 aim_origin=view.camera_origin()
 aim_direction=view.camera_direction()
 previous=Time.get_ticks_usec()

func _process(delta: float) -> void:
 if view==null or samples.size()>=SAMPLES: return
 var now := Time.get_ticks_usec()
 var elapsed := float(now-previous)/1000.0
 previous=now
 frame+=1
 # Same eight-avatar snapshot/interpolation and shot workload on both sources.
 if frame%3==0:
  visual_states=frozen.duplicate(true)
  for item in visual_states:
   item.position.x+=sin(float(frame)*0.04+float(item.peer_id))*0.15
  view.apply_snapshot(visual_states,frame)
  if phase2: view.call("apply_environment",environment)
 if frame%30==0:
  var peer := 1+(frame/30)%8
  view.show_shot({"shooter_peer_id":peer,"origin":visual_states[peer-1].position+Vector3.UP*0.7,"end":Vector3(12,1.7,8),"hit_player":false})
  if phase2:
   sound_id+=1
   var event := {"id":sound_id,"round_id":1,"kind":"reload" if frame%60==0 else "handle","position":visual_states[peer-1].position,"peer_id":peer}
   view.call("apply_sound_events",[event],1,false)
 view._process(delta)
 if room.world.snapshot()!=frozen or view.camera_origin()!=aim_origin or view.camera_direction()!=aim_direction:
  failures+=1
 if frame>WARMUP: samples.append(elapsed)
 if samples.size()!=SAMPLES: return
 call_deferred("finish")

func _node_count(node: Node) -> int:
 var count := 1
 for child in node.get_children(): count+=_node_count(child)
 return count
func finish() -> void:
 if not screenshot.is_empty(): get_viewport().get_texture().get_image().save_png(screenshot)
 samples.sort()
 var audio_count := 0
 var audio_nodes := 0
 if phase2:
  var audio: Object=view.get("spatial_audio")
  audio_count=int(audio.get("played_events"))
  audio_nodes=audio.get_child_count()
 var result := {"phase2":phase2,"profile":profile,"warmup":WARMUP,"samples":SAMPLES,"p50_ms":samples[149],"p95_ms":samples[284],"p99_ms":samples[296],"max_ms":samples[299],"cpu":OS.get_processor_name(),"device":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(DisplayServer.window_get_size()),"version":Engine.get_version_info().string,"remote_avatars":view.avatars.size(),"bodies":view.bodies.size(),"environment_objects":environment.get("objects",[]).size(),"map_meshes":view.art.meshes.size(),"map_lights":view.art.lights.size(),"nodes_recursive":_node_count(view),"process_objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"process_static_memory_bytes":OS.get_static_memory_usage(),"spatial_audio_events_played":audio_count,"spatial_voice_nodes":audio_nodes,"official_state_or_aim_mutations":failures}
 print("PHASE2_GRAPHICS_BENCHMARK ",JSON.stringify(result))
 if failures>0: push_error("PHASE2_GRAPHICS_OFFICIAL_STATE_MUTATED")
 # Let the final short combat/audio timer complete before freeing its owner.
 await get_tree().create_timer(0.5).timeout
 view.queue_free()
 room.clear()
 room=null
 await get_tree().process_frame
 get_tree().quit(1 if failures>0 else 0)
