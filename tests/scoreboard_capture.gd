extends SceneTree

## Captura o placar (Tab) e a tela de fim de rodada numa janela real (xvfb).
## Uso: xvfb-run -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 \
##   --resolution 1280x720 --path . --script tests/scoreboard_capture.gd -- SAIDA_DIR

var out_dir := ""
var hud: RoundHud
var stage := 0
var wait := 0

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("SCOREBOARD_CAPTURE_ERROR precisa de janela (xvfb) e de SAIDA_DIR")
		quit(2)
		return
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("SCOREBOARD_CAPTURE_ERROR precisa de SAIDA_DIR")
		quit(2)
		return
	out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.07, 0.055, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	hud = RoundHud.new()
	root.add_child(hud)
	var roster := [
		{"peer_id": 7, "label": "Ana", "appearance": "knight", "connected": true, "participant": true, "alive": true, "kills": 3, "deaths": 0},
		{"peer_id": 8, "label": "Beto", "appearance": "soldier", "connected": true, "participant": true, "alive": false, "kills": 1, "deaths": 1},
		{"peer_id": 9, "label": "Caio", "appearance": "detective", "connected": true, "participant": true, "alive": true, "kills": 2, "deaths": 1},
		{"peer_id": 10, "label": "Dora", "appearance": "butler", "connected": true, "participant": true, "alive": true, "kills": 0, "deaths": 0},
	]
	hud.apply_roster(roster)
	hud.apply_pings({7: 24, 8: 41, 9: 18, 10: 63})
	hud.apply_round_state({
		"state": RoundState.ACTIVE, "round_id": 1, "connected": 4, "participants": 4, "alive": 3,
		"winning_team": Role.TEAM_NONE, "winner_reason": "", "min_players": 4, "max_players": 8,
		"countdown_msec": 0,
	}, Role.DETECTIVE, 1, 9)
	hud.apply_combat_state({"round_id": 1, "health": 80, "weapon_id": "common_pistol", "magazine": 6, "reserve": 18, "reloading": false})
	wait = 8

func _process(_delta: float) -> bool:
	if hud == null:
		return false
	if wait > 0:
		wait -= 1
		return false
	match stage:
		0:
			Input.action_press("scoreboard")
			wait = 6
			stage = 1
		1:
			_shot("scoreboard.png")
			Input.action_release("scoreboard")
			hud.apply_round_state({
				"state": RoundState.ENDED, "round_id": 1, "connected": 4, "participants": 4, "alive": 3,
				"winning_team": Role.TEAM_INNOCENTS, "winner_reason": RoundRules.REASON_ASSASSIN_DOWN,
				"min_players": 4, "max_players": 8, "countdown_msec": 0,
			}, Role.DETECTIVE, 1, 9)
			hud.apply_final_reveal({"round_id": 1, "players": [
				{"peer_id": 7, "role": "ASSASSIN"},
				{"peer_id": 8, "role": "VICTIM"},
				{"peer_id": 9, "role": "DETECTIVE"},
				{"peer_id": 10, "role": "VICTIM"},
			]})
			wait = 8
			stage = 2
		2:
			_shot("end-of-round.png")
			print("SCOREBOARD_CAPTURE_OK dir=%s" % out_dir)
			quit(0)
			return true
	return false

func _shot(name: String) -> void:
	await_viewport()
	var image := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name)
	var err := image.save_png(path)
	if err != OK:
		printerr("SCOREBOARD_CAPTURE_ERROR failed to write %s (%d)" % [path, err])
		quit(1)
		return
	print("SCOREBOARD_CAPTURE_SAVED %s %dx%d" % [path, image.get_width(), image.get_height()])

func await_viewport() -> void:
	RenderingServer.force_draw()
