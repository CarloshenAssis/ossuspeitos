extends "res://tests/sync_network_coordinator.gd"

## Fase 5, cenário principal: oito clientes reais, três rodadas seguidas na
## mesma sessão, sem reiniciar processos. Estende o coordenador de
## sincronização (roteiros de comandos, relatórios e conexões reais); não é
## uma segunda cópia do coordenador de combate.
##
## O servidor de teste conhece o estado oficial (papéis, vida, inventário) e
## calcula expectativas próprias (quem deve estar vivo, alvos do espectador,
## destinatários do reveal) sem usar os mesmos helpers que produzem o
## resultado. Os clientes relatam o que realmente receberam.
##
## Rodada 1 — inocentes vencem (assassino abatido):
##   rota por porta/corredor com outro jogador no caminho; coleta real de arma
##   e munição; tiro que acerta, tiro que erra, tiro obstruído; recarga; uma
##   vítima eliminada (ações bloqueadas, espectador privado); segunda vítima
##   (alvos atualizados); assassino abatido.
## Rodada 2 — assassino vence (todos os inocentes abatidos com tiros reais).
## Rodada 3 — inocentes vencem pelo detetive.
## Entre rodadas: reset oficial, callbacks antigos injetados, aparência
## mantida, estado do cliente limpo. Recursos amostrados a cada rodada.
##
## Setup determinístico isolado e documentado: reposicionamento (teleporte com
## época nova) e vida cheia de quem entra na faixa. Coleta, dano, munição,
## recarga, eliminação e vitória são sempre os reais.

const LANE_FROM := Vector3(12.0, 1.0, 15.5)
const LANE_TO := Vector3(9.0, 1.0, 15.5)
const WALL_FROM := Vector3(10.0, 1.0, 20.3)
const WALL_TO := Vector3(10.0, 1.0, 15.5)
const STEP_TIMEOUT_MSEC := 30000
const FIRE_GAP_TICKS := 30
const RELOAD_TICKS := 90

var steps: Array = []
var step_index := -1
var step_started_msec := 0
var step_ran := false
var round_number := 0
var round_ids: Array = []
var roles_by_round: Dictionary = {}
var expected_alive: Dictionary = {}
var first_appearances: Dictionary = {}
var action_ids: Dictionary = {}
var campaign_results: Array = []
var campaign_shots: Array = []
var private_by_peer: Dictionary = {}
var resources: Array = []
var victims: Array = []
var assassin := 0
var detective := 0
var shooter_peer := 0
var spectator_a := 0
var spectator_b := 0
var previous_epochs: Dictionary = {}

# --- Servidor ----------------------------------------------------------------

func _server_tick() -> void:
	if stage == "SHUTDOWN" or stage == "DONE":
		return
	if stage == "WAIT_ACTIVE":
		if app.round_authority.state != RoundState.ACTIVE or app.combat_authority.active_round_id <= 0:
			return
		peers = app.round_authority.participants.keys()
		if peers.size() != 8:
			return
		peers.sort()
		for peer_id in peers:
			first_appearances[int(peer_id)] = str(app.lobby.appearance_for(int(peer_id)))
		stage = "CAMPAIGN"
		_plan_round()
		_next_step()
		return
	if stage != "CAMPAIGN" or step_index < 0 or step_index >= steps.size():
		return
	var step: Dictionary = steps[step_index]
	if Time.get_ticks_msec() - step_started_msec > int(step.get("timeout", STEP_TIMEOUT_MSEC)):
		_fail("step=%s timeout round=%d alive=%s results=%s" % [step["name"], round_number, str(app.round_authority.alive), str(campaign_results.slice(-6))])
		return
	if Time.get_ticks_msec() - step_started_msec < int(step.get("delay", 0)):
		return
	if not step_ran:
		step_ran = true
		if step.has("run"):
			(step["run"] as Callable).call()
		return
	if step.has("done") and not bool((step["done"] as Callable).call()):
		return
	if step.has("check"):
		var error := str((step["check"] as Callable).call())
		if not error.is_empty():
			_fail("step=%s %s" % [step["name"], error])
			return
	print("CAMPAIGN_STEP_OK round=%d step=%s ms=%d" % [round_number, step["name"], Time.get_ticks_msec() - step_started_msec])
	_next_step()

func _next_step() -> void:
	step_index += 1
	step_started_msec = Time.get_ticks_msec()
	step_ran = false
	if step_index < steps.size():
		print("CAMPAIGN_STEP_START round=%d step=%s" % [round_number, steps[step_index]["name"]])

func _add(step_name: String, config: Dictionary) -> void:
	config["name"] = step_name
	steps.append(config)

## Monta os passos da próxima rodada (chamado com a rodada já ACTIVE).
func _plan_round() -> void:
	round_number += 1
	round_ids.append(int(app.round_authority.round_id))
	action_ids.clear()
	assassin = 0
	detective = 0
	victims.clear()
	var roles := {}
	for peer_id in peers:
		var role: int = app.round_authority.get_role_for_peer(int(peer_id))
		roles[int(peer_id)] = role
		if role == Role.ASSASSIN: assassin = int(peer_id)
		elif role == Role.DETECTIVE: detective = int(peer_id)
		else: victims.append(int(peer_id))
	roles_by_round[round_number] = roles
	expected_alive.clear()
	for peer_id in peers:
		expected_alive[int(peer_id)] = true
	print("CAMPAIGN_ROUND_BEGIN round=%d round_id=%d participants=%d" % [round_number, app.round_authority.round_id, peers.size()])
	_add("reset_invariants", {"check": _check_round_start})
	_add("client_state_clean", {"run": func(): _request_all_state("round_start"), "done": func(): return reports.size() == peers.size(), "check": _check_clients_clean})
	if round_number > 1:
		_add("stale_callbacks", {"run": _inject_stale_callbacks, "delay": 300, "done": func(): return reports.size() == peers.size(), "check": _check_stale_rejected})
	_add("resources", {"run": func(): _request_all_state("resources"), "done": func(): return reports.size() == peers.size(), "check": _record_resources})
	match round_number:
		1: _plan_round_one()
		2: _plan_round_two()
		3: _plan_round_three()

func _plan_round_one() -> void:
	shooter_peer = victims[0]
	spectator_a = victims[1]
	spectator_b = victims[2]
	# Rota: porta leste do Salão → corredor → Cozinha, com outro jogador parado
	# no corredor (não há colisão entre jogadores; a passagem é visual).
	_add("navigation", {"run": func():
		_scatter([shooter_peer, spectator_a])
		app.authoritative_world.teleport(shooter_peer, MOVE_START, -PI * 0.5, 0.0)
		app.authoritative_world.teleport(spectator_a, Vector3(20.0, 1.0, 11.5), PI * 0.5, 0.0)
		move_overlaps = 0
		move_zones.clear()
		reports.clear()
		get_tree().create_timer(1.0).timeout.connect(func(): _send_script(shooter_peer, "CAMPAIGN", _move_script()))
	, "done": func():
		_track_move(shooter_peer)
		return reports.has(shooter_peer)
	, "check": _check_navigation, "timeout": 40000})
	_add("pickup_weapon", _pickup_step(shooter_peer, 1, "weapon_1"))
	_add("pickup_ammo", _pickup_step(shooter_peer, 5, "ammo_1"))
	_add("hit", _fire_step(shooter_peer, spectator_a, 1, 66, true))
	_add("miss", _miss_step(shooter_peer, spectator_a))
	_add("obstructed", _wall_step(shooter_peer, spectator_a))
	_add("eliminate_first", _fire_step(shooter_peer, spectator_a, 2, 0, true))
	_add("spectator_first", {"run": func(): _request_state(spectator_a, "spectator"), "done": func(): return reports.has(spectator_a), "check": func(): return _check_spectator(spectator_a)})
	_add("dead_actions_blocked", {"run": func():
		campaign_results.clear()
		sync_campaign_dead_probe.rpc_id(spectator_a)
	, "done": func(): return _results_for(spectator_a).size() >= 3, "check": func(): return _check_dead_blocked(spectator_a)})
	_add("reload", _reload_step(shooter_peer))
	_add("eliminate_second", _fire_step(shooter_peer, spectator_b, 3, 0, true))
	_add("spectator_updated", {"run": func():
		reports.clear()
		_request_state(spectator_a, "spectator")
		_request_state(spectator_b, "spectator")
	, "delay": 400, "done": func(): return reports.has(spectator_a) and reports.has(spectator_b),
		"check": func():
			var first := _check_spectator(spectator_a)
			return first if not first.is_empty() else _check_spectator(spectator_b)})
	_add("assassin_down", _fire_step(shooter_peer, assassin, 3, 0, true))
	_add_round_end(RoundRules.REASON_ASSASSIN_DOWN, Role.TEAM_INNOCENTS)

func _plan_round_two() -> void:
	shooter_peer = assassin
	_add("pickup_weapon", _pickup_step(assassin, 0, "weapon_0"))
	for index in 3:
		_add("pickup_ammo_%d" % index, _pickup_step(assassin, 4 + index, "ammo_%d" % index))
	var innocents: Array = victims.duplicate()
	innocents.append(detective)
	var shots_fired := 0
	for target_peer in innocents:
		for hit in 3:
			if shots_fired > 0 and shots_fired % 6 == 0:
				_add("reload_%d" % shots_fired, _reload_step(assassin))
			shots_fired += 1
			var remaining := 100 - 34 * (hit + 1)
			_add("shot_%d" % shots_fired, _fire_step(assassin, target_peer, 1, maxi(0, remaining), true))
	_add_round_end(RoundRules.REASON_INNOCENTS_DOWN, Role.TEAM_ASSASSIN)

func _plan_round_three() -> void:
	shooter_peer = detective
	_add("pickup_weapon", _pickup_step(detective, 2, "weapon_2"))
	_add("assassin_down", _fire_step(detective, assassin, 3, 0, true))
	_add_round_end(RoundRules.REASON_ASSASSIN_DOWN, Role.TEAM_INNOCENTS)

func _add_round_end(reason: String, team: int) -> void:
	_add("round_result", {"done": func(): return app.round_authority.state == RoundState.ENDED, "check": func():
		if app.round_authority.winning_team != team or app.round_authority.winner_reason != reason:
			return "winner %d/%s expected %d/%s" % [app.round_authority.winning_team, app.round_authority.winner_reason, team, reason]
		print("CAMPAIGN_ROUND_RESULT round=%d team=%s reason=%s" % [round_number, Role.team_to_label(team), reason])
		# Épocas desta rodada, para provar que a próxima abre épocas novas e
		# para o comando velho injetado depois.
		for peer_id in peers:
			previous_epochs[int(peer_id)] = int(app.authoritative_world.states[int(peer_id)]["epoch"])
		return ""})
	_add("reveal_delivered", {"run": func(): _request_all_state("reveal"), "delay": 800, "done": func(): return reports.size() == peers.size(), "check": _check_reveal})
	if round_number < 3:
		_add("next_round", {"done": func():
			return app.round_authority.state == RoundState.ACTIVE and app.combat_authority.active_round_id == app.round_authority.round_id \
				and app.round_authority.round_id > int(round_ids[-1])
		, "check": func():
			_plan_round()
			return ""})
	else:
		_add("finish", {"run": func():
			print("CAMPAIGN_RESOURCES_SUMMARY %s" % JSON.stringify(resources))
			print("CAMPAIGN_SERVER_OK clients=%d rounds=%d profile=%s" % [peers.size(), round_number, str(app.arguments.get("sync-profile", "local"))])
			stage = "SHUTDOWN"
			app._begin_server_shutdown(app.lobby.peer_ids())})

# --- Passos reutilizáveis ----------------------------------------------------------

## Todos fora da faixa, cada um num spawn diferente (validados no mapa).
func _scatter(except: Array) -> void:
	var index := 0
	for peer_id in peers:
		if int(peer_id) in except:
			continue
		app.authoritative_world.teleport(int(peer_id), MovementRules.SPAWN_POINTS[index])
		index += 1

func _next_id(peer_id: int, kind: String) -> int:
	var key := "%d:%s" % [peer_id, kind]
	action_ids[key] = int(action_ids.get(key, 0)) + 1
	return int(action_ids[key])

func _results_for(peer_id: int) -> Array:
	return campaign_results.filter(func(r): return int(r["peer"]) == peer_id)

func _pickup_step(peer_id: int, pickup_index: int, pickup_id: String) -> Dictionary:
	var id_holder := [0]
	return {"run": func():
		_scatter([peer_id])
		app.authoritative_world.teleport(peer_id, ArenaRules.PICKUP_POSITIONS[pickup_index] + Vector3.UP * 0.75)
		campaign_results.clear()
		id_holder[0] = _next_id(peer_id, "pickup")
		get_tree().create_timer(1.0).timeout.connect(func():
			_send_script(peer_id, "SCRIPT", [{"action": {"kind": "pickup", "id": id_holder[0], "pickup_id": pickup_id}}]))
	, "done": func(): return _results_for(peer_id).size() >= 1, "check": func():
		var result: Dictionary = _results_for(peer_id)[0]
		if not bool(result["accepted"]):
			return "pickup %s refused: %s" % [pickup_id, result["reason"]]
		if bool(app.combat_authority.inventory.ground_items[pickup_id]["available"]):
			return "pickup %s still available" % pickup_id
		return ""}

## Atirador na faixa do Salão olhando para oeste; alvo a 3 m. Dispara `count`
## tiros reais e espera a vida oficial chegar a `expected_health`.
func _fire_step(shooter: int, target_peer: int, count: int, expected_health: int, expect_hits: bool) -> Dictionary:
	var before := {}
	return {"run": func():
		_scatter([shooter, target_peer])
		app.authoritative_world.teleport(shooter, LANE_FROM, PI * 0.5, 0.0)
		app.authoritative_world.teleport(target_peer, LANE_TO)
		before["magazine"] = int(app.combat_authority.inventory.get_inventory(shooter).get("magazine", 0))
		before["health"] = int(app.combat_authority.health.get(target_peer, 0))
		campaign_results.clear()
		campaign_shots.clear()
		var script: Array = []
		for shot in count:
			script.append({"action": {"kind": "fire", "id": _next_id(shooter, "fire")}})
			for gap in FIRE_GAP_TICKS: script.append({})
		get_tree().create_timer(1.0).timeout.connect(func(): _send_script(shooter, "SCRIPT", script))
	, "done": func(): return _results_for(shooter).size() >= count and campaign_shots.size() >= count, "check": func():
		for result in _results_for(shooter):
			if not bool(result["accepted"]):
				return "shot refused: %s" % result["reason"]
		for event in campaign_shots:
			if bool(event["hit_player"]) != expect_hits:
				return "hit flag %s expected %s" % [str(event["hit_player"]), str(expect_hits)]
		var last: Dictionary = campaign_shots[-1]
		var health := int((last["health_after"] as Dictionary).get(target_peer, -1))
		if health != expected_health:
			return "target health %d expected %d" % [health, expected_health]
		var magazine := int(last["magazine_after"])
		if magazine != int(before["magazine"]) - count:
			return "magazine %d expected %d" % [magazine, int(before["magazine"]) - count]
		if expected_health == 0:
			expected_alive[target_peer] = false
			if app.round_authority.is_alive(target_peer):
				return "target should be eliminated"
		for peer_id in expected_alive:
			if bool(expected_alive[peer_id]) != app.round_authority.is_alive(int(peer_id)) and app.round_authority.state == RoundState.ACTIVE:
				return "alive mismatch for %d" % int(peer_id)
		print("CAMPAIGN_SHOTS round=%d shooter_role_hidden target_health=%d->%d magazine=%d->%d" % [round_number, int(before["health"]), health, int(before["magazine"]), magazine])
		return ""}

func _miss_step(shooter: int, target_peer: int) -> Dictionary:
	var before := {}
	return {"run": func():
		app.authoritative_world.teleport(shooter, LANE_FROM, PI * 0.5 + 1.0, 0.0)
		app.authoritative_world.teleport(target_peer, LANE_TO)
		before["health"] = int(app.combat_authority.health.get(target_peer, 0))
		before["magazine"] = int(app.combat_authority.inventory.get_inventory(shooter).get("magazine", 0))
		campaign_results.clear()
		campaign_shots.clear()
		get_tree().create_timer(1.0).timeout.connect(func():
			_send_script(shooter, "SCRIPT", [{"action": {"kind": "fire", "id": _next_id(shooter, "fire")}}]))
	, "done": func(): return campaign_shots.size() >= 1, "check": func():
		if bool(campaign_shots[0]["hit_player"]): return "miss hit someone"
		if int(app.combat_authority.health[target_peer]) != int(before["health"]): return "miss changed health"
		if int(app.combat_authority.inventory.get_inventory(shooter)["magazine"]) != int(before["magazine"]) - 1: return "miss did not spend a round"
		return ""}

func _wall_step(shooter: int, target_peer: int) -> Dictionary:
	var before := {}
	return {"run": func():
		_scatter([shooter, target_peer])
		app.authoritative_world.teleport(shooter, WALL_FROM, 0.0, 0.0)
		app.authoritative_world.teleport(target_peer, WALL_TO)
		before["health"] = int(app.combat_authority.health.get(target_peer, 0))
		campaign_shots.clear()
		campaign_results.clear()
		get_tree().create_timer(1.0).timeout.connect(func():
			_send_script(shooter, "SCRIPT", [{"action": {"kind": "fire", "id": _next_id(shooter, "fire")}}]))
	, "done": func(): return campaign_shots.size() >= 1, "check": func():
		var event: Dictionary = campaign_shots[0]
		if bool(event["hit_player"]): return "shot went through the wall"
		if (event["end"] as Vector3).z < 16.0: return "shot end past the wall (%s)" % str(event["end"])
		if int(app.combat_authority.health[target_peer]) != int(before["health"]): return "wall shot changed health"
		return ""}

func _reload_step(peer_id: int) -> Dictionary:
	return {"run": func():
		campaign_results.clear()
		_send_script(peer_id, "SCRIPT", [{"action": {"kind": "reload", "id": _next_id(peer_id, "reload")}}])
	, "done": func():
		var held: Dictionary = app.combat_authority.inventory.get_inventory(peer_id)
		return _results_for(peer_id).size() >= 1 and not bool(held.get("reloading", true)) and int(held.get("magazine", 0)) > 0
	, "check": func():
		if not bool(_results_for(peer_id)[0]["accepted"]): return "reload refused: %s" % _results_for(peer_id)[0]["reason"]
		return ""}

func _track_move(peer_id: int) -> void:
	if app.authoritative_world.states.has(peer_id):
		var position: Vector3 = app.authoritative_world.states[peer_id]["position"]
		if ArenaRules.overlaps_blocker(position): move_overlaps += 1
		move_zones[str(ArenaRules.zone_at(position).get("id", ""))] = true

func _check_navigation() -> String:
	var official: Dictionary = app.authoritative_world.states[shooter_peer]
	var report: Dictionary = reports[shooter_peer]
	var error := (report["position"] as Vector3).distance_to(official["position"])
	print("CAMPAIGN_NAVIGATION zones=%s overlaps=%d prediction_error=%.6f corrections_large=%d" % [",".join(PackedStringArray(move_zones.keys())), move_overlaps, error, int(report["corrections_large"])])
	if move_overlaps > 0: return "official position inside geometry"
	if not (move_zones.has("corredor_salao_cozinha") and move_zones.has("cozinha")): return "route did not cross the door and corridor"
	if error > 0.001: return "prediction differs from official"
	return ""

# --- Checagens de rodada -----------------------------------------------------------

func _check_round_start() -> String:
	var counts: Dictionary = app.round_authority.role_counts()
	if int(counts["assassin"]) != 1 or int(counts["detective"]) != 1 or int(counts["victim"]) != 6:
		return "role counts %s" % str(counts)
	for peer_id in peers:
		var id := int(peer_id)
		if not app.round_authority.is_alive(id): return "peer %d not alive" % id
		if int(app.combat_authority.health.get(id, -1)) != 100: return "peer %d health" % id
		if not str(app.combat_authority.inventory.get_inventory(id).get("weapon_id", "")).is_empty(): return "peer %d kept a weapon" % id
		if str(app.lobby.appearance_for(id)) != str(first_appearances[id]): return "peer %d changed appearance" % id
		if not app.round_authority.get_spectator_state(id).is_empty(): return "peer %d has spectator state" % id
		if round_number > 1 and int(app.authoritative_world.states[id]["epoch"]) <= int(previous_epochs.get(id, 0)):
			return "peer %d epoch not advanced" % id
	if not app.round_authority.get_final_reveal().is_empty(): return "reveal not cleared"
	var pickups: Array = app.combat_authority.public_pickups()
	if pickups.size() != 8: return "pickups %d" % pickups.size()
	for entry in pickups:
		if not bool(entry["available"]): return "pickup %s unavailable" % entry["pickup_id"]
	return ""

func _request_all_state(kind: String) -> void:
	reports.clear()
	for peer_id in peers:
		_request_state(int(peer_id), kind)

func _request_state(peer_id: int, kind: String) -> void:
	reports.erase(peer_id)
	sync_campaign_state.rpc_id(peer_id, kind, round_number)

func _check_clients_clean() -> String:
	for peer_id in reports:
		var r: Dictionary = reports[peer_id]
		if bool(r["eliminated"]) or not (r["spectator_targets"] as Array).is_empty() or bool(r["has_reveal"]):
			return "client %d kept spectator/reveal state" % int(peer_id)
		if int(r["predicted_shots"]) != 0: return "client %d kept predicted shots" % int(peer_id)
		if int(r["role"]) != int(roles_by_round[round_number][int(peer_id)]):
			return "client %d does not hold its own role" % int(peer_id)
		if int(r["role_round"]) != int(round_ids[-1]): return "client %d role round %d" % [int(peer_id), int(r["role_round"])]
		if int(r["snapshot_violations"]) != 0: return "client %d saw private snapshot fields" % int(peer_id)
	return ""

## Callbacks da rodada anterior (controlados pelo harness): comando com época
## e id de tiro velhos, alvos de espectador e reveal com round_id antigo.
func _inject_stale_callbacks() -> void:
	var old_round := int(round_ids[-2])
	reports.clear()
	campaign_results.clear()
	campaign_shots.clear()
	for peer_id in peers:
		round_private_spectator_targets_stale(int(peer_id), old_round)
	sync_campaign_stale_packet.rpc_id(int(peers[0]), int(previous_epochs.get(int(peers[0]), 0)))
	get_tree().create_timer(0.6).timeout.connect(func(): _request_all_state("stale"))

func round_private_spectator_targets_stale(peer_id: int, old_round: int) -> void:
	app.round_private_spectator_targets.rpc_id(peer_id, {"round_id": old_round, "targets": peers.duplicate()})
	app.round_final_reveal.rpc_id(peer_id, {"round_id": old_round, "winner": "ASSASSIN", "reason": "stale", "players": []})

func _check_stale_rejected() -> String:
	if not campaign_shots.is_empty(): return "a stale packet produced a shot"
	var stale := _results_for(int(peers[0]))
	if stale.is_empty() or str(stale[0]["reason"]) != "stale_epoch": return "stale command not refused as stale_epoch (%s)" % str(stale)
	for peer_id in peers:
		if int(app.combat_authority.health[int(peer_id)]) != 100: return "stale packet changed health"
	for peer_id in reports:
		var r: Dictionary = reports[peer_id]
		if not (r["spectator_targets"] as Array).is_empty() or bool(r["has_reveal"]) or bool(r["eliminated"]):
			return "client %d accepted a stale callback" % int(peer_id)
	print("CAMPAIGN_STALE_CALLBACKS_REJECTED round=%d clients=%d" % [round_number, reports.size()])
	return ""

func _record_resources() -> String:
	var world: AuthoritativeWorld = app.authoritative_world
	var queued := 0
	for state in world.states.values(): queued += (state["queue"] as Array).size()
	var entry := {"round": round_number, "server_objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"server_nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "server_static_mem": OS.get_static_memory_usage(),
		"world_states": world.states.size(), "queued": queued, "health": app.combat_authority.health.size(),
		"inventories": app.combat_authority.inventory.inventories.size(), "ground": app.combat_authority.inventory.ground_items.size(),
		"lobby": app.lobby.size(), "command_logs": app.command_logs.size()}
	var clients := {}
	for peer_id in reports:
		clients[int(peer_id)] = reports[peer_id]["resources"]
	entry["clients"] = clients
	resources.append(entry)
	print("CAMPAIGN_RESOURCES round=%d server_objects=%d server_nodes=%d queued=%d world=%d lobby=%d" % [round_number,
		int(entry["server_objects"]), int(entry["server_nodes"]), queued, world.states.size(), app.lobby.size()])
	if world.states.size() != 8 or app.combat_authority.health.size() != 8 or app.combat_authority.inventory.ground_items.size() != 8:
		return "per-round collections not reset to 8"
	return ""

func _expected_targets(peer_id: int) -> Array:
	var result: Array = []
	for other in peers:
		if int(other) != peer_id and bool(expected_alive.get(int(other), false)):
			result.append(int(other))
	result.sort()
	return result

func _check_spectator(peer_id: int) -> String:
	var r: Dictionary = reports[peer_id]
	var got: Array = (r["spectator_targets"] as Array).duplicate()
	got.sort()
	var expected := _expected_targets(peer_id)
	print("CAMPAIGN_SPECTATOR round=%d peer=%d targets=%d expected=%d" % [round_number, peer_id, got.size(), expected.size()])
	if got != expected: return "spectator targets %s expected %s" % [str(got), str(expected)]
	if not bool(r["eliminated"]): return "client not in spectator mode"
	return ""

func _check_dead_blocked(peer_id: int) -> String:
	var kinds := {}
	for result in _results_for(peer_id):
		if bool(result["accepted"]) or str(result["reason"]) != "player_dead": return "dead action result %s" % str(result)
		kinds[result["action"]] = true
	if kinds.size() != 3: return "dead probe kinds %s" % str(kinds.keys())
	print("CAMPAIGN_DEAD_ACTIONS_BLOCKED round=%d peer=%d" % [round_number, peer_id])
	return ""

func _check_reveal() -> String:
	var roles: Dictionary = roles_by_round[round_number]
	for peer_id in peers:
		if not reports.has(peer_id): return "no reveal report from %d" % int(peer_id)
		var r: Dictionary = reports[peer_id]
		if int(r["reveal_count"]) != round_number: return "client %d reveal count %d" % [int(peer_id), int(r["reveal_count"])]
		var reveal: Dictionary = r["reveal"]
		if int(reveal.get("round_id", -1)) != int(round_ids[-1]): return "client %d reveal round" % int(peer_id)
		var players: Array = reveal.get("players", [])
		if players.size() != peers.size(): return "client %d reveal has %d players" % [int(peer_id), players.size()]
		for entry in players:
			var expected_label := Role.to_label(int(roles[int(entry["peer_id"])]))
			if str(entry["role"]) != expected_label: return "client %d reveal role mismatch" % int(peer_id)
		if int(r["reveal_state"]) != RoundState.ENDED: return "client %d received the reveal outside ENDED" % int(peer_id)
	print("CAMPAIGN_REVEAL_OK round=%d clients=%d" % [round_number, peers.size()])
	return ""

## Ganchos do NetworkApp.
func observe_server_action(peer_id: int, action: String, sequence: Variant, result: Dictionary) -> void:
	if app.mode == "server":
		campaign_results.append({"peer": peer_id, "action": action, "id": int(sequence) if typeof(sequence) == TYPE_INT else -1,
			"accepted": bool(result.get("accepted", false)), "reason": str(result.get("reason", ""))})

## Estado oficial no instante de cada tiro (o fim da rodada limpa o combate
## logo depois do último).
func observe_server_shot(event: Dictionary) -> void:
	if app.mode == "server":
		var entry := event.duplicate()
		entry["health_after"] = app.combat_authority.health.duplicate()
		var shooter := int(event.get("shooter_peer_id", 0))
		entry["magazine_after"] = int(app.combat_authority.inventory.get_inventory(shooter).get("magazine", -1))
		campaign_shots.append(entry)

# --- Cliente -----------------------------------------------------------------------

var reveal_receipts := 0
var reveal_state_at_receipt := -1
var last_spectator_targets: Array = []

func observe_client_event(kind: String, payload: Variant = null) -> void:
	super.observe_client_event(kind, payload)
	if kind == "spectator":
		last_spectator_targets = (payload as Array).duplicate()

func _client_tick() -> void:
	super._client_tick()
	if app.local_final_reveal.has("round_id") and int(app.local_final_reveal["round_id"]) != _last_reveal_round:
		_last_reveal_round = int(app.local_final_reveal["round_id"])
		reveal_receipts += 1
		reveal_state_at_receipt = int(app.local_round_public.get("state", -1))

var _last_reveal_round := 0

func _client_resources() -> Dictionary:
	var arena: ArenaView = app.arena_view
	var interp_samples := 0
	var avatars := 0
	if arena != null:
		interp_samples = int(arena.interpolator.stats()["samples"])
		avatars = arena.avatars.size()
	return {"objects": Performance.get_monitor(Performance.OBJECT_COUNT), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"static_mem": OS.get_static_memory_usage(), "pending": app.prediction.pending.size(), "outbox": app.outbox.size(),
		"interp_samples": interp_samples, "avatars": avatars, "net_stats_actions": app.net_stats._action_started.size()}

@rpc("authority", "call_remote", "reliable")
func sync_campaign_state(kind: String, _round_number: int) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	var reveal: Dictionary = app.local_final_reveal.duplicate(true)
	sync_report.rpc_id(1, stage_for_report(), {"kind": kind, "eliminated": app.local_eliminated,
		"spectator_targets": app.local_spectator_targets.duplicate(), "has_reveal": not reveal.is_empty(), "reveal": reveal,
		"reveal_count": reveal_receipts, "reveal_state": reveal_state_at_receipt, "role": app.local_role, "role_round": app.local_round_id,
		"predicted_shots": app.arena_view.predicted_shots.size() if app.arena_view != null else 0,
		"snapshot_violations": snapshot_violations, "resources": _client_resources()})

func stage_for_report() -> String:
	return "CAMPAIGN"

## Morto tentando andar, coletar, atirar e recarregar pelo fluxo de comandos.
@rpc("authority", "call_remote", "reliable")
func sync_campaign_dead_probe() -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	app.send_test_packet([{"kind": "pickup", "id": 90, "pickup_id": "weapon_3"}, {"kind": "fire", "id": 90}, {"kind": "reload", "id": 90}], Vector2.RIGHT)

## Comando velho: época da rodada anterior com um tiro.
@rpc("authority", "call_remote", "reliable")
func sync_campaign_stale_packet(old_epoch: int) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	var first_seq: int = app.prediction.next_seq
	app.prediction.next_seq += 1
	app.submit_commands.rpc_id(1, NetSync.encode_packet(old_epoch, first_seq, [NetSync.encode_command(Vector2.ZERO, 0.0, 0.0, ["fire", 1])]))
