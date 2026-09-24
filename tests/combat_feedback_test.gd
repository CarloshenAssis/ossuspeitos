extends SceneTree

## Cada efeito de combate nasce do evento oficial certo, e só dele: coleta
## aceita x recusada, disparo com e sem acerto, confirmação privada de acerto,
## recarga pelo estado oficial, dano recebido, eliminação pública e nova rodada.
## Também confere que nada visual mexe na mira, que nada tem colisão e que os
## sons são gerados no próprio jogo (sem arquivo externo).

const LOCAL := 1
const REMOTE := 2
const OTHER := 3

var failures := 0
var checks := 0
var _arena: ArenaView
var _frame := 0

func _initialize() -> void:
	_arena = ArenaView.new()
	_arena.local_peer_id = LOCAL
	root.add_child(_arena)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_arena.apply_snapshot(_states(0.0))
	_arena.set_gameplay_visuals(true)
	_test_feedback_model()
	_test_pickup_accepted_and_rejected()
	_test_shots_with_and_without_hit()
	_test_reload_follows_official_state()
	_test_damage_and_elimination()
	_test_new_round_starts_clean()
	_test_sounds_are_generated_in_game()
	if failures > 0:
		push_error("COMBAT_FEEDBACK_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return true
	print("COMBAT_FEEDBACK_TEST_OK checks=%d" % checks)
	quit(0)
	return true

func _test_feedback_model() -> void:
	var unarmed := _combat(1, 100, "", 0, 0, false)
	var armed := _combat(1, 100, "common_pistol", 6, 0, false)
	_expect(ArenaView.combat_feedback(unarmed, armed) == ["pickup_ok"], "official weapon pickup")
	_expect(ArenaView.combat_feedback(armed, _combat(1, 100, "common_pistol", 6, 6, false)) == ["pickup_ok"], "official ammo pickup")
	_expect(ArenaView.combat_feedback(armed, _combat(1, 100, "common_pistol", 5, 0, false)).is_empty(), "a shot is not a pickup")
	_expect(ArenaView.combat_feedback(_combat(1, 100, "common_pistol", 0, 6, false), _combat(1, 100, "common_pistol", 0, 6, true)) == ["reload_start"], "official reload start")
	_expect(ArenaView.combat_feedback(_combat(1, 100, "common_pistol", 0, 6, true), _combat(1, 100, "common_pistol", 6, 0, false)) == ["reload_end"], "official reload end (reserve moving into the magazine is not a pickup)")
	_expect(ArenaView.combat_feedback(armed, _combat(1, 66, "common_pistol", 6, 0, false)) == ["hurt"], "official damage")
	_expect(ArenaView.combat_feedback(armed, _combat(1, 0, "common_pistol", 6, 0, false)) == ["hurt"], "lethal damage hurts, nothing else")
	_expect(ArenaView.combat_feedback({}, armed).is_empty(), "first state is not news")
	_expect(ArenaView.combat_feedback(unarmed, _combat(2, 100, "common_pistol", 6, 0, false)).is_empty(), "nothing across rounds")
	_expect(ArenaView.combat_feedback(_combat(1, 32, "", 0, 0, false), _combat(2, 100, "", 0, 0, false)).is_empty(), "respawn health is not damage")

func _test_pickup_accepted_and_rejected() -> void:
	_arena.apply_combat_state(_combat(1, 100, "", 0, 0, false))
	_arena.fx.events.clear()
	# Recusa oficial: som de "não", nenhum sucesso, pickup continua no chão.
	_arena.apply_pickups(_pickups([]))
	_arena.show_rejection("pickup", "inventory_full")
	_arena.show_rejection("pickup", "out_of_range")
	_expect(_arena.fx.count_event("pickup_deny") == 2 and not _arena.fx.has_event("pickup_ok"), "rejected pickups sound denied, never successful")
	_expect(not _arena.fx.has_event("pickup_vanish") and (_arena.pickup_nodes["p0"] as Node3D).visible, "a rejected pickup stays on the floor")
	_arena.show_rejection("fire", "fire_rate")
	_arena.show_rejection("fire", "direction_yaw_divergence")
	_expect(_arena.fx.count_event("pickup_deny") == 2 and not _arena.fx.has_event("dry_fire"), "silent reasons make no sound")
	# Aceita: o pickup some (público) e só então o estado privado arma o jogador.
	_arena.fx.events.clear()
	_arena.apply_pickups(_pickups(["p0"]))
	_expect(_arena.fx.has_event("pickup_vanish") and not _arena.fx.has_event("pickup_ok"), "public vanish alone is not the local success")
	_arena.apply_combat_state(_combat(1, 100, "common_pistol", 6, 0, false))
	_expect(_arena.fx.count_event("pickup_ok") == 1, "official private state confirms the pickup")
	_arena.apply_pickups(_pickups(["p0"]))
	_expect(_arena.fx.count_event("pickup_vanish") == 1, "no second ring for an already collected pickup")

func _test_shots_with_and_without_hit() -> void:
	_arena.fx.events.clear()
	var aim_before := _arena.camera_direction()
	# Próprio disparo que não acertou ninguém: som e recuo, impacto na parede,
	# e nenhuma confirmação de dano.
	_arena.show_shot(_shot(LOCAL, false))
	_expect(_arena.fx.has_event("shot") and _arena.fx.has_event("impact_wall"), "own miss: shot sound and wall impact")
	_expect(not _arena.fx.has_event("hit") and not _arena.fx.has_event("impact_player"), "own miss: no damage confirmation")
	_expect(_arena._muzzle_flash.visible, "own shot: brief muzzle flash on the held pistol")
	_expect(_arena.camera_direction().distance_to(aim_before) < 0.0001, "recoil never moves the aim")
	# Acerto: confirmação privada separada do evento público.
	_arena.fx.events.clear()
	_arena.show_shot(_shot(LOCAL, true))
	_expect(_arena.fx.has_event("impact_player") and not _arena.fx.has_event("hit"), "public hit_player alone is not the private confirmation")
	_arena.show_hit_marker()
	_expect(_arena.fx.count_event("hit") == 1, "combat_hit_confirmed plays the hit sound")
	# Disparo de outro jogador: clarão e som posicionados na origem pública.
	_arena.fx.events.clear()
	var remote := _shot(REMOTE, false)
	_arena.show_shot(remote)
	_expect(_arena.fx.has_event("muzzle_flash") and _arena.fx.has_event("shot@world") and not _arena.fx.has_event("shot"), "remote shot: world flash and positional sound")
	_expect(_event_position("shot@world").is_equal_approx(remote["origin"]), "remote shot sound at the official origin")
	_expect(_flash_energy_ok(), "muzzle light stays dim")
	# Tiro alheio que termina em você: nada de mancha na frente da câmera.
	_arena.fx.events.clear()
	var into_me := _shot(REMOTE, true)
	into_me["end"] = _arena.camera_origin() + Vector3(0, 0, -0.3)
	_arena.show_shot(into_me)
	_expect(_arena.fx.has_event("shot@world") and not _arena.fx.has_event("impact_player"), "no impact blob right on the own camera")

func _test_reload_follows_official_state() -> void:
	_arena.apply_combat_state(_combat(1, 100, "common_pistol", 0, 6, false))
	_arena.fx.events.clear()
	_arena.show_rejection("fire", "empty_magazine")
	_expect(_arena.fx.has_event("dry_fire") and not _arena.fx.has_event("shot"), "empty magazine: dry click, no shot")
	_arena.apply_combat_state(_combat(1, 100, "common_pistol", 0, 6, true))
	_expect(_arena.fx.has_event("reload_start") and _arena._reload_pose, "official reloading lowers the pistol")
	_arena.apply_combat_state(_combat(1, 100, "common_pistol", 0, 6, true))
	_expect(_arena.fx.count_event("reload_start") == 1, "the same official state does not repeat the sound")
	_arena.apply_combat_state(_combat(1, 100, "common_pistol", 6, 0, false))
	_expect(_arena.fx.has_event("reload_end") and not _arena._reload_pose, "official reload end raises the pistol")
	_expect(not _arena.fx.has_event("pickup_ok"), "reload is never mistaken for a pickup")

func _test_damage_and_elimination() -> void:
	_arena.fx.events.clear()
	var aim_before := _arena.camera_direction()
	var origin_before := _arena.camera_origin()
	_arena.apply_combat_state(_combat(1, 66, "common_pistol", 6, 0, false))
	_expect(_arena.fx.count_event("hurt") == 1, "official damage plays hurt")
	_expect(_arena.camera_direction().distance_to(aim_before) < 0.0001 and _arena.camera_origin().distance_to(origin_before) < 0.0001, "damage kick never changes the aim")
	# Eliminação de outro jogador: fumaça neutra no corpo, sem cor de papel.
	_arena.fx.events.clear()
	var body := (_arena.avatars[REMOTE] as Node3D).global_position
	_arena.show_elimination(REMOTE)
	_expect(_arena.fx.has_event("elimination") and _event_position("elimination").is_equal_approx(body), "public elimination at the body")
	_expect(not (_arena.avatars[REMOTE] as Node3D).visible, "eliminated body disappears")
	# Sincronizar o roster não repete efeito de eliminação.
	_arena.fx.events.clear()
	_arena.apply_roster_alive([{"peer_id": REMOTE, "alive": false}])
	_expect(not _arena.fx.has_event("elimination"), "roster sync is not an elimination")
	for node in _arena.fx.get_children():
		_expect(not (node is CollisionObject3D), "effect %s has no collision" % node.name)

func _test_new_round_starts_clean() -> void:
	_arena.apply_combat_state(_combat(1, 100, "common_pistol", 0, 6, true))
	_arena.fx.impact(Vector3(1, 1, 1), false)
	_arena.fx.events.clear()
	# Como o cliente faz em WAITING/COUNTDOWN: estado de combate limpo.
	_arena.apply_combat_state({})
	await_frames()
	_expect(_visual_effect_count() == 0, "clearing the combat state removes lingering effects")
	_expect(not _arena._reload_pose, "no reload pose carries into the next round")
	_arena.apply_combat_state(_combat(2, 100, "", 0, 0, false))
	_expect(_arena.fx.events.is_empty(), "the first state of the new round plays nothing")

func _test_sounds_are_generated_in_game() -> void:
	for sound_name in SfxBank.NAMES:
		var stream := SfxBank.stream(sound_name)
		_expect(stream != null and stream.data.size() > 0 and stream.resource_path.is_empty(), "sound %s is synthesised in memory" % sound_name)
		_expect(stream != null and stream.get_length() <= 0.5, "sound %s is short" % sound_name)

func await_frames() -> void:
	# `queue_free` só conclui no fim do quadro; aqui basta ignorar o que já saiu.
	for child in _arena.fx.get_children():
		if child.is_queued_for_deletion():
			_arena.fx.remove_child(child)

func _visual_effect_count() -> int:
	var total := 0
	for child in _arena.fx.get_children():
		if not (child is AudioStreamPlayer or child is AudioStreamPlayer3D):
			total += 1
	return total

func _flash_energy_ok() -> bool:
	for light in _arena.fx.find_children("*", "OmniLight3D", true, false):
		if (light as OmniLight3D).light_energy > 1.0:
			return false
	return CombatFx.FLASH_SECONDS <= 0.1

func _event_position(kind: String) -> Vector3:
	for entry in _arena.fx.events:
		if str(entry["kind"]) == kind:
			return entry["position"]
	return Vector3.INF

func _shot(shooter: int, hit_player: bool) -> Dictionary:
	return {"round_id": 1, "shooter_peer_id": shooter, "origin": Vector3(0, 1.7, 0) if shooter == LOCAL else Vector3(3, 1.7, 3),
		"end": Vector3(0, 1.7, -8), "hit_player": hit_player}

func _states(yaw: float) -> Array:
	return [
		{"peer_id": LOCAL, "position": Vector3(0, 1, 0), "yaw": yaw, "velocity": Vector3.ZERO, "spawn_index": 0},
		{"peer_id": REMOTE, "position": Vector3(3, 1, 3), "yaw": 0.0, "velocity": Vector3.ZERO, "spawn_index": 1},
		{"peer_id": OTHER, "position": Vector3(-3, 1, 3), "yaw": 0.0, "velocity": Vector3.ZERO, "spawn_index": 2},
	]

func _pickups(taken: Array) -> Array:
	var result: Array = []
	for index in ArenaRules.PICKUP_POSITIONS.size():
		var pickup_id := "p%d" % index
		result.append({"pickup_id": pickup_id, "type": "weapon" if index < 4 else "ammo",
			"position": ArenaRules.PICKUP_POSITIONS[index], "available": not taken.has(pickup_id), "round_id": 1})
	return result

func _combat(round_id: int, health: int, weapon: String, magazine: int, reserve: int, reloading: bool) -> Dictionary:
	return {"round_id": round_id, "health": health, "weapon_id": weapon, "magazine": magazine, "reserve": reserve, "reloading": reloading}

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("COMBAT_FEEDBACK_CHECK_FAILED %s" % description)
