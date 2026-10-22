extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("SPATIAL_AUDIO_ASSERT " + label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var rules = load("res://shared/sound_event_rules.gd")
	check(rules != null, "authorized sound catalog exists")
	if rules == null:
		quit(1)
		return
	var authority_script = load("res://server/sound_event_authority.gd")
	var controller_script = load("res://client/spatial_audio_controller.gd")
	var room := MatchRoom.new(1,"ABC234",0,false,0.1,2.0,8)
	for peer in range(1,5): room.add_member(peer,"Player%d" % peer,0)
	room.round_authority.tick(1000)
	check(room.get("sounds")!=null,"match room owns sound authority")
	var sounds = authority_script.new(room.round_authority,room.world)
	sounds.reset(room.round_authority.round_id)
	check(sounds.snapshot().is_empty(),"no invented initial event")
	sounds.observe_movement()
	var initial: Vector3=room.world.states[1].position
	room.world.states[1].position=initial+Vector3(0.7,0,0)
	sounds.observe_movement()
	check(sounds.snapshot().size()==1,"official movement produces one footstep")
	check(sounds.snapshot()[0].kind=="step_walk" and sounds.snapshot()[0].peer_id==1,"step has authorized source")
	sounds.observe_movement()
	check(sounds.snapshot().size()==1,"stationary actor produces no duplicate")
	room.world.teleport(1,initial+Vector3(8,0,0))
	sounds.observe_movement()
	check(sounds.snapshot().size()==1,"epoch teleport does not create footsteps")
	room.round_authority.alive[1]=false
	room.world.states[1].position+=Vector3(0.7,0,0)
	sounds.observe_movement()
	check(sounds.snapshot().size()==1,"dead actor cannot produce footsteps")
	check(not sounds.emit_authorized("forged",Vector3.ZERO,1),"unknown event kind refused")
	for index in 90: sounds.emit_authorized("door",Vector3(3,1,3),0)
	check(sounds.snapshot().size()<=rules.MAX_EVENTS,"event ring bounded")
	var event: Dictionary=rules.make(1,1,"door",Vector3(3,1,3),2)
	check(rules.sanitize(event)==event,"public DTO roundtrip")
	var forged:=event.duplicate(); forged["role"]="assassin"
	check(rules.sanitize(forged).is_empty(),"secret and extra fields rejected")
	for bad in [null,[],{"kind":"door"}]: check(rules.sanitize(bad).is_empty(),"malformed event refused")
	var audio = controller_script.new()
	root.add_child(audio)
	audio.configure(1.0,1.0)
	check(audio.consume([event],1,Vector3(3,1,2),99,[])==1,"near spatial event accepted without device")
	check(audio.consume([event],1,Vector3(3,1,2),99,[])==0,"duplicate does not play again")
	var distant: Dictionary=rules.make(2,1,"door",Vector3(40,1,27),2)
	check(audio.consume([distant],1,Vector3.ZERO,99,[])==0,"distant event culled")
	audio.configure(0.0,0.0)
	check(audio.consume([rules.make(3,1,"impact",Vector3.ZERO,2)],1,Vector3.ZERO,99,[])==0,"category volume zero silent")
	audio.configure(1.0,1.0)
	check(audio.consume([rules.make(4,1,"reload",Vector3.ZERO,99)],1,Vector3.ZERO,99,[])==0,"own reload already rendered privately")
	check(audio.consume([rules.make(5,2,"door",Vector3.ZERO,2)],1,Vector3.ZERO,99,[])==0,"foreign round sound refused")
	check(audio.consume([rules.make(1,2,"door",Vector3.ZERO,2)],2,Vector3.ZERO,99,[])==1,"new round may reuse event id")
	check(audio.get_child_count()==audio.MAX_VOICES,"fixed audio voice pool")
	check(audio.attenuation(Vector3.ZERO,Vector3(1,0,0),[])>audio.attenuation(Vector3.ZERO,Vector3(10,0,0),[]),"distance reduces level")
	var obstacle=[{"center":Vector3(3,1,3),"size":Vector3(1,3,1)}]
	check(audio.attenuation(Vector3(2,1,3),Vector3(4,1,3),obstacle)<audio.attenuation(Vector3(2,1,3),Vector3(4,1,3),[]),"obstacle occludes sound")
	# Real menu controls persist each category independently, including silence.
	MenuSettings.path_override="user://phase2-audio-test-%d.cfg" % OS.get_process_id()
	var menu:=DesktopMenu.new()
	root.add_child(menu)
	menu.press("settings")
	menu.press("settings_audio")
	check(menu.panel_name=="audio","category page opens")
	(menu.buttons.settings_movement_volume as HSlider).value=0.0
	(menu.buttons.settings_environment_volume as HSlider).value=0.25
	(menu.buttons.settings_combat_volume as HSlider).value=0.5
	var settings:=MenuSettings.load_saved()
	check(settings.movement_volume==0.0 and settings.environment_volume==0.25 and settings.combat_volume==0.5,"independent category settings persist")
	menu.press("audio_back")
	check(menu.panel_name=="settings","audio returns to settings")
	var view:=ArenaView.new()
	root.add_child(view)
	view.configure_audio(settings)
	check(view.spatial_audio.movement_volume==0.0 and view.spatial_audio.environment_volume==0.25,"saved categories reach live view")
	settings.combat_volume=0.0
	view.configure_audio(settings)
	view.fx.play_world("shot",Vector3.ZERO)
	var playing:=false
	for voice in view.fx._world_players: playing=playing or voice.playing
	check(not playing,"zero combat volume produces no audio voice")
	for voice in view.fx._ui_players: voice.stop()
	for voice in view.fx._world_players: voice.stop()
	view.free()
	if menu._player!=null: menu._player.stop()
	menu.free()
	DirAccess.remove_absolute(MenuSettings.file_path())
	MenuSettings.path_override=""
	for player in audio.get_children(): player.stop()
	audio.free()
	room.clear()
	print("SPATIAL_AUDIO_TEST_%s checks=%d failures=%d" % ["OK" if failures==0 else "FAILED",checks,failures])
	quit(0 if failures==0 else 1)
