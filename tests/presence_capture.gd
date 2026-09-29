extends SceneTree

## Fase 11: capturas da apresentação real (ArenaView + HUD) numa janela
## (xvfb/OpenGL), alimentada só com dados no formato oficial: snapshot público
## (`armed`), evento público de disparo, estado privado próprio, corpo e
## estado da rodada. Uma cena por situação pedida — desarmado, coleta,
## armado, caminhada, disparo, impacto em parede, impacto em jogador,
## morte/corpo, espectador e reset — cada uma grava um PNG e confere o que dá
## para conferir sem olho humano: pistola visível só quando deve, mira oculta
## no espectador, boca da pistola e corpo fora das paredes, pistola dentro da
## tela quando o jogador está de frente.
## Precisa de janela real; não roda em --headless.
##
## Uso: xvfb-run -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 \
##   --resolution 1280x720 --path . --script tests/presence_capture.gd -- SAIDA_DIR

const LOCAL := 1
const REMOTE := 2
const SHOOTER := 3
const EYE := Vector3(12.0, 1.0, 16.2)
const REMOTE_AT := Vector3(12.0, 1.0, 12.8)
const SCENES := ["unarmed", "pickup", "armed", "walking", "firing", "impact_wall", "impact_player", "death_body", "spectator", "reset"]

var out_dir := ""
var arena: ArenaView
var hud: RoundHud
var failures := 0
var checks := 0
var _scene := -1
var _frame := 0
var _tick := 1000
var _remote := {"position": REMOTE_AT, "yaw": PI - 0.55, "pitch": 0.0, "armed": false, "epoch": 1}
var _shooter := {"position": Vector3(14.2, 1.0, 13.6), "yaw": PI * 0.5 + 0.35, "pitch": 0.0, "armed": true, "epoch": 1}
var _local_epoch := 1
var _images: Array = []
var _label := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		printerr("PRESENCE_CAPTURE_ERROR precisa de janela (xvfb) e de SAIDA_DIR")
		quit(2)
		return
	out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var size := DisplayServer.window_get_size()
	_label = "%dx%d" % [size.x, size.y]
	arena = ArenaView.new()
	arena.local_peer_id = LOCAL
	root.add_child(arena)
	hud = (load("res://client/round_hud.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	arena.set_appearance(REMOTE, "night")
	arena.set_appearance(SHOOTER, "ember")

func _snapshot() -> void:
	_tick += 1
	var states := [
		{"peer_id": LOCAL, "position": EYE, "velocity": Vector3.ZERO, "yaw": 0.0, "pitch": -0.06, "spawn_index": 0, "epoch": _local_epoch, "armed": false},
		{"peer_id": REMOTE, "position": _remote["position"], "velocity": Vector3.ZERO, "yaw": _remote["yaw"], "pitch": _remote["pitch"], "spawn_index": 1, "epoch": _remote["epoch"], "armed": _remote["armed"]},
		{"peer_id": SHOOTER, "position": _shooter["position"], "velocity": Vector3.ZERO, "yaw": _shooter["yaw"], "pitch": 0.0, "spawn_index": 2, "epoch": _shooter["epoch"], "armed": _shooter["armed"]},
	]
	var clean: Array = []
	for state in states:
		var sanitized := PublicCombatState.sanitize_player(state)
		_expect(not sanitized.is_empty(), "staged state passes the public allowlist")
		clean.append(sanitized)
	arena.apply_snapshot(clean, _tick)

func _process(_delta: float) -> bool:
	if arena == null:
		return false
	_snapshot()
	if _scene < 0:
		_scene = 0
		_frame = 0
		_round(RoundState.ACTIVE, 1)
		_own_combat(1, 100, "")
		arena.set_gameplay_visuals(true)
		_prepare(SCENES[0])
		return false
	_frame += 1
	_step(SCENES[_scene])
	if _frame >= _capture_frame(SCENES[_scene]):
		_capture(SCENES[_scene])
		_scene += 1
		_frame = 0
		if _scene >= SCENES.size():
			_finish()
			return true
		_prepare(SCENES[_scene])
	return false

func _capture_frame(scene: String) -> int:
	match scene:
		"firing", "impact_wall", "impact_player": return 29
		"death_body": return 60
		"walking": return 70
	return 40

func _prepare(scene: String) -> void:
	match scene:
		"unarmed":
			_remote["armed"] = false
		"pickup":
			# O item some (estado público) e a pistola aparece na mão (armed).
			var pickups := [{"pickup_id": "weapon_x", "type": "weapon", "position": Vector3(12.5, 0.4, 12.3), "available": true, "round_id": 1}]
			arena.apply_pickups(pickups)
		"armed":
			_remote["armed"] = true
			_own_combat(1, 100, "common_pistol")
		"walking":
			_remote["yaw"] = PI * 0.5
		"firing":
			_remote["yaw"] = PI - 0.3
			_remote["position"] = REMOTE_AT
		"spectator":
			hud.apply_roster([{"peer_id": LOCAL, "label": "Voce", "connected": true, "participant": true, "alive": false},
				{"peer_id": REMOTE, "label": "Night", "connected": true, "participant": true, "alive": true},
				{"peer_id": SHOOTER, "label": "Ember", "connected": true, "participant": true, "alive": true}])
			_own_combat(1, 0, "common_pistol")
			hud.apply_spectator_state(true, [REMOTE, SHOOTER], SHOOTER)
			arena.set_spectator_target(SHOOTER, true)
		"reset":
			arena.set_spectator_target(0, false)
			arena.clear_bodies()
			_round(RoundState.COUNTDOWN, 1)
			_remote = {"position": Vector3(10.5, 1.0, 12.5), "yaw": PI, "pitch": 0.0, "armed": false, "epoch": 2}
			_shooter = {"position": Vector3(13.8, 1.0, 12.2), "yaw": PI, "pitch": 0.0, "armed": false, "epoch": 2}
			_local_epoch = 2
			arena.set_player_alive(SHOOTER, true)
			arena.set_player_alive(REMOTE, true)
			hud.apply_roster([{"peer_id": LOCAL, "label": "Voce", "connected": true, "participant": true, "alive": true},
				{"peer_id": REMOTE, "label": "Night", "connected": true, "participant": true, "alive": true},
				{"peer_id": SHOOTER, "label": "Ember", "connected": true, "participant": true, "alive": true}])
			hud.apply_spectator_state(false, [], 0)
			_round(RoundState.ACTIVE, 2)
			_own_combat(2, 100, "")
			arena.set_gameplay_visuals(true)
			arena.apply_pickups([{"pickup_id": "weapon_x", "type": "weapon", "position": Vector3(12.5, 0.4, 12.3), "available": true, "round_id": 2}])

func _step(scene: String) -> void:
	match scene:
		"pickup":
			if _frame == 20:
				arena.apply_pickups([{"pickup_id": "weapon_x", "type": "weapon", "position": Vector3(12.5, 0.4, 12.3), "available": false, "round_id": 1}])
				_remote["armed"] = true
		"walking":
			var x := 10.6 + float(_frame) * 0.045
			_remote["position"] = Vector3(x, 1.0, 12.8)
		"firing":
			if _frame == 28:
				arena.show_shot(PublicCombatState.sanitize_shot({"round_id": 1, "shot_id": 1, "shooter_peer_id": REMOTE,
					"origin": REMOTE_AT + Vector3(0, 0.7, 0), "end": Vector3(13.5, 1.6, 17.9), "hit_player": false}))
		"impact_wall":
			if _frame == 28:
				arena.show_shot(PublicCombatState.sanitize_shot({"round_id": 1, "shot_id": 2, "shooter_peer_id": LOCAL,
					"origin": EYE + Vector3(0, 0.7, 0), "end": Vector3(9.9, 1.5, 11.4), "hit_player": false}))
		"impact_player":
			if _frame == 28:
				arena.show_shot(PublicCombatState.sanitize_shot({"round_id": 1, "shot_id": 3, "shooter_peer_id": SHOOTER,
					"origin": (_shooter["position"] as Vector3) + Vector3(0, 0.7, 0), "end": REMOTE_AT + Vector3(0, 0.35, 0.15), "hit_player": true}))
		"death_body":
			if _frame == 20:
				arena.show_elimination(REMOTE)
				arena.add_body({"body_id": 7, "round_id": 1, "peer_id": REMOTE, "position": REMOTE_AT, "yaw": PI - 0.3, "appearance": "night"}, true)

func _capture(scene: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join("presence_%s_%s.png" % [scene, _label])
	image.save_png(path)
	_images.append(image)
	print("PRESENCE_CAPTURE scene=%s file=%s" % [scene, path])
	var remote_armed := arena.held_weapon_visible(REMOTE)
	match scene:
		"unarmed":
			_expect(not remote_armed, "unarmed: no pistol in the hand")
			_expect(not arena.weapon_model.visible, "unarmed: no own pistol")
		"pickup", "armed", "walking", "firing":
			_expect(remote_armed, "%s: pistol in the hand" % scene)
			_check_pistol_placement(scene)
		"death_body":
			_expect(not remote_armed, "dead: no pistol")
			_expect(arena.bodies.has(7), "body shown")
			var body := arena.bodies[7] as Node3D
			_expect(not ArenaRules.overlaps_blocker(body.global_position, 0.05), "body not inside a wall")
		"spectator":
			_expect(not arena.crosshair.visible and not arena.weapon_model.visible, "spectator: no own crosshair or pistol")
		"reset":
			_expect(not remote_armed and not arena.held_weapon_visible(SHOOTER), "reset: nobody armed")
			_expect(arena.bodies.is_empty(), "reset: bodies cleared")
			_expect(hud._banner_panel.visible, "reset: new-round banner on screen")
	if scene == "armed":
		_expect(arena.weapon_model.visible and arena.crosshair.visible, "own pistol and crosshair when armed and alive")
		_check_viewmodel_clear_of_center()
	if scene == "firing":
		_expect(arena.fx.has_event("muzzle_flash") and arena.fx.has_event("tracer"), "firing: flash and tracer")
	if scene == "impact_wall":
		_expect(arena.fx.has_event("impact_wall"), "wall impact effect")
	if scene == "impact_player":
		_expect(arena.fx.has_event("impact_player"), "player impact effect")

func _check_pistol_placement(scene: String) -> void:
	var animator: CharacterAnimator = arena.animators.get(REMOTE)
	if animator == null:
		_expect(false, "%s: animator" % scene)
		return
	var muzzle := animator.muzzle_position()
	_expect(not ArenaRules.overlaps_blocker(muzzle, 0.02), "%s: muzzle not inside the map geometry (%s)" % [scene, str(muzzle)])
	var avatar := arena.avatars[REMOTE] as Node3D
	_expect(muzzle.distance_to(avatar.global_position) < 1.2, "%s: pistol stays with the body" % scene)
	var viewport := root.get_viewport().get_visible_rect()
	var on_screen := arena.camera.unproject_position(muzzle)
	_expect(viewport.has_point(on_screen) and not arena.camera.is_position_behind(muzzle), "%s: pistol on screen (%s)" % [scene, str(on_screen)])

## Pistola própria discreta: nenhum ponto dela perto do retículo (centro) e
## tudo na metade direita/inferior da tela.
func _check_viewmodel_clear_of_center() -> void:
	var viewport := root.get_viewport().get_visible_rect()
	var center := viewport.get_center()
	var clear := minf(viewport.size.x, viewport.size.y) * 0.14
	var nearest := INF
	var leftmost := INF
	var topmost := INF
	for mesh in arena.weapon_model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
		for corner in 8:
			var point := arena.camera.unproject_position(box.get_endpoint(corner))
			nearest = minf(nearest, point.distance_to(center))
			leftmost = minf(leftmost, point.x)
			topmost = minf(topmost, point.y)
	_expect(nearest > clear, "own pistol keeps the crosshair area clear (%.0f px > %.0f)" % [nearest, clear])
	_expect(leftmost > viewport.size.x * 0.5 and topmost > viewport.size.y * 0.5, "own pistol stays in the lower-right quarter (%.0f, %.0f)" % [leftmost, topmost])

func _round(state: int, round_id: int) -> void:
	var payload := {"state": state, "round_id": round_id, "countdown_msec": 3000, "connected": 3, "participants": 3,
		"alive": 3, "winning_team": Role.TEAM_NONE, "winner_reason": "", "min_players": 4, "max_players": 8}
	hud.apply_round_state(payload, Role.VICTIM if state == RoundState.ACTIVE else Role.NONE, round_id, LOCAL)
	arena.set_round(round_id if state == RoundState.ACTIVE else 0)

func _own_combat(round_id: int, health: int, weapon: String) -> void:
	var state := {"round_id": round_id, "health": health, "weapon_id": weapon, "magazine": 6 if not weapon.is_empty() else 0, "reserve": 0, "reloading": false}
	arena.apply_combat_state(state)
	hud.apply_combat_state(state)

func _finish() -> void:
	# Prancha com todas as cenas (2 colunas).
	var first: Image = _images[0]
	var w := first.get_width() / 2
	var h := first.get_height() / 2
	var sheet := Image.create(w * 2, h * int(ceil(_images.size() / 2.0)), false, first.get_format())
	for index in _images.size():
		var small: Image = (_images[index] as Image).duplicate()
		small.resize(w, h)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i((index % 2) * w, (index / 2) * h))
	sheet.save_png(out_dir.path_join("presence_sheet_%s.png" % _label))
	if failures > 0:
		push_error("PRESENCE_CAPTURE_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return
	print("PRESENCE_CAPTURE_OK checks=%d scenes=%d resolution=%s" % [checks, _images.size(), _label])
	quit(0)

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("PRESENCE_CAPTURE_FAILED %s" % message)
