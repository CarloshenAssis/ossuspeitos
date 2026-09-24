extends "res://tests/campaign_coordinator.gd"

## Fase 5, casos adversos em sessões reais (um caso por execução do servidor,
## `--adverse-case=NOME`). Reaproveita o motor de passos, os passos de coleta,
## tiro e recarga e os relatórios da campanha. Ações de processo (iniciar ou
## derrubar um cliente) ficam com o harness: o servidor imprime
## `ADVERSE_REQUEST action=... label=...` e observa o efeito pelo caminho real
## (conexão, recusa, desconexão).
##
## Casos:
##   ninth            8 jogadores em ACTIVE; um nono é recusado e ninguém muda.
##   join_ended       nome duplicado recusado; entrada em ACTIVE e em ENDED
##                    espera sem papel; os dois participam da rodada seguinte.
##   drop_moving      cliente derrubado (kill -9) no meio do movimento.
##   observed_leaves  o alvo que o espectador observa sai da partida.
##   leave_rejoin     sai e volta com o mesmo nome: peer novo, sem herança.
##   invalid_actions  ações inválidas e payloads malformados de vivo e morto.
##   phase4_delay     (rtt150j) eliminação com tiros pendentes e reinício com
##                    comandos em trânsito.

var case_name := ""
var refused: Array = []
var eliminated_at: Dictionary = {}
var counts_before: Dictionary = {}
var official_before: Dictionary = {}
var marks: Dictionary = {}

func _ready() -> void:
	super._ready()
	case_name = str(app.arguments.get("adverse-case", ""))

# --- Servidor ----------------------------------------------------------------

func observe_join_refused(peer_id: int, reason: String) -> void:
	refused.append({"peer": peer_id, "reason": reason, "msec": Time.get_ticks_msec()})

func observe_server_action(peer_id: int, action: String, sequence: Variant, result: Dictionary) -> void:
	super.observe_server_action(peer_id, action, sequence, result)
	if app.mode == "server" and not campaign_results.is_empty():
		campaign_results[-1]["msec"] = Time.get_ticks_msec()

func observe_server_shot(event: Dictionary) -> void:
	super.observe_server_shot(event)
	if app.mode == "server":
		campaign_shots[-1]["msec"] = Time.get_ticks_msec()

func observe_server_elimination(peer_id: int) -> void:
	if app.mode == "server":
		eliminated_at[peer_id] = Time.get_ticks_msec()
		marks["queue_at_elimination_%d" % peer_id] = (app.authoritative_world.states[peer_id]["queue"] as Array).size() \
			if app.authoritative_world.states.has(peer_id) else -1

func _request(action: String, label: String) -> void:
	print("ADVERSE_REQUEST action=%s label=%s" % [action, label])

func _label(peer_id: int) -> String:
	return str(app.lobby.label_for(peer_id))

func _peer_with_label(label: String) -> int:
	for peer_id in app.lobby.peer_ids():
		if _label(int(peer_id)) == label:
			return int(peer_id)
	return 0

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
	print("ADVERSE_ROUND_BEGIN case=%s round=%d round_id=%d participants=%d" % [case_name, round_number, app.round_authority.round_id, peers.size()])
	_add("round_start", {"check": _check_start})
	match "%s:%d" % [case_name, round_number]:
		"ninth:1": _plan_ninth()
		"join_ended:1": _plan_join_ended()
		"join_ended:2": _plan_join_ended_next()
		"drop_moving:1": _plan_drop_moving()
		"observed_leaves:1": _plan_observed_leaves()
		"leave_rejoin:1": _plan_leave_rejoin()
		"leave_rejoin:2": _plan_leave_rejoin_next()
		"invalid_actions:1": _plan_invalid_actions()
		"phase4_delay:1": _plan_phase4_delay()
		"phase4_delay:2": _plan_phase4_delay_next()
		_: _fail("unknown adverse case %s round %d" % [case_name, round_number])

func _check_start() -> String:
	var counts: Dictionary = app.round_authority.role_counts()
	if int(counts["assassin"]) != 1 or int(counts["detective"]) != 1 or int(counts["victim"]) != peers.size() - 2:
		return "role counts %s" % str(counts)
	for peer_id in peers:
		var id := int(peer_id)
		if not app.round_authority.is_participant(id) or not app.round_authority.is_alive(id): return "peer %d not an alive participant" % id
		if int(app.combat_authority.health.get(id, -1)) != 100: return "peer %d health" % id
		if not str(app.combat_authority.inventory.get_inventory(id).get("weapon_id", "")).is_empty(): return "peer %d kept a weapon" % id
		if round_number > 1 and previous_epochs.has(id) and int(app.authoritative_world.states[id]["epoch"]) <= int(previous_epochs[id]):
			return "peer %d epoch not advanced" % id
	return ""

## Estado relatado pelo próprio cliente (o que ele realmente recebeu).
func _ask(peer_id: int, kind: String) -> void:
	reports.erase(peer_id)
	adverse_state.rpc_id(peer_id, kind)

func _ask_all(kind: String) -> void:
	reports.clear()
	for peer_id in peers:
		_ask(int(peer_id), kind)

func _all_reported() -> bool:
	for peer_id in peers:
		if not reports.has(peer_id): return false
	return true

## Todos continuam recebendo snapshots atuais e nenhum viu campo privado.
func _check_clients_fresh() -> String:
	for peer_id in peers:
		var r: Dictionary = reports[peer_id]
		if app.server_tick - int(r["snapshot_tick"]) > 60: return "client %d stale snapshots (%d vs %d)" % [int(peer_id), int(r["snapshot_tick"]), app.server_tick]
		if int(r["violations"]) != 0: return "client %d saw private snapshot fields" % int(peer_id)
		if int(r["roster"]) != app.lobby.size(): return "client %d roster %d expected %d" % [int(peer_id), int(r["roster"]), app.lobby.size()]
	return ""

func _check_clients_roles() -> String:
	for peer_id in peers:
		var r: Dictionary = reports[peer_id]
		if int(r["role"]) != int(roles_by_round[round_number][int(peer_id)]): return "client %d does not hold its own role" % int(peer_id)
		if int(r["role_round"]) != int(round_ids[-1]): return "client %d role round %d" % [int(peer_id), int(r["role_round"])]
		if bool(r["eliminated"]) or bool(r["has_reveal"]) or not (r["targets"] as Array).is_empty(): return "client %d kept round state" % int(peer_id)
		if int(r["epoch"]) != int(app.authoritative_world.states[int(peer_id)]["epoch"]): return "client %d epoch %d vs %d" % [int(peer_id), int(r["epoch"]), int(app.authoritative_world.states[int(peer_id)]["epoch"])]
	return ""

func _add_round_end_generic(reason: String, team: int, has_next: bool) -> void:
	_add("round_result", {"done": func(): return app.round_authority.state == RoundState.ENDED, "check": func():
		if app.round_authority.winning_team != team or app.round_authority.winner_reason != reason:
			return "winner %d/%s expected %d/%s" % [app.round_authority.winning_team, app.round_authority.winner_reason, team, reason]
		print("ADVERSE_ROUND_RESULT case=%s round=%d team=%s reason=%s" % [case_name, round_number, Role.team_to_label(team), reason])
		for peer_id in peers:
			if app.authoritative_world.states.has(int(peer_id)):
				previous_epochs[int(peer_id)] = int(app.authoritative_world.states[int(peer_id)]["epoch"])
		return ""})
	if has_next:
		_add("next_round", {"done": func():
			return app.round_authority.state == RoundState.ACTIVE and app.combat_authority.active_round_id == app.round_authority.round_id \
				and app.round_authority.round_id > int(round_ids[-1])
		, "timeout": 40000, "check": func():
			peers = app.round_authority.participants.keys()
			peers.sort()
			_plan_round()
			return ""})

func _add_finish() -> void:
	_add("finish", {"run": func():
		print("ADVERSE_SERVER_OK case=%s rounds=%d lobby=%d profile=%s" % [case_name, round_number, app.lobby.size(), str(app.arguments.get("sync-profile", "local"))])
		stage = "SHUTDOWN"
		app._begin_server_shutdown(app.lobby.peer_ids())})

func _add_client_request(step_name: String, label: String, expected_reason: String) -> void:
	_add(step_name, {"run": func():
		refused.clear()
		_request("start_client", label)
	, "done": func(): return not refused.is_empty(), "timeout": 30000, "check": func():
		var entry: Dictionary = refused[0]
		if str(entry["reason"]) != expected_reason: return "refusal %s expected %s" % [entry["reason"], expected_reason]
		if app.lobby.has(int(entry["peer"])) or app.authoritative_world.states.has(int(entry["peer"])): return "refused peer kept server state"
		print("ADVERSE_JOIN_REFUSED case=%s label=%s reason=%s lobby=%d" % [case_name, label, entry["reason"], app.lobby.size()])
		return ""})

# --- ninth ---------------------------------------------------------------------

func _plan_ninth() -> void:
	_add_client_request("ninth_refused", "client-9", "room_unavailable")
	_add("room_unchanged", {"delay": 500, "check": func():
		if app.lobby.size() != 8 or app.round_authority.participants.size() != 8 or app.authoritative_world.states.size() != 8 \
				or app.combat_authority.health.size() != 8 or app.round_authority.state != RoundState.ACTIVE:
			return "room changed: lobby=%d participants=%d world=%d" % [app.lobby.size(), app.round_authority.participants.size(), app.authoritative_world.states.size()]
		for peer_id in peers:
			if not app.round_authority.is_alive(int(peer_id)): return "peer %d lost life" % int(peer_id)
		return ""})
	_add("others_unaffected", {"run": func(): _ask_all("after_ninth"), "done": _all_reported, "check": func():
		var error := _check_clients_fresh()
		if error.is_empty(): error = _check_clients_roles()
		if error.is_empty(): print("ADVERSE_OTHERS_UNAFFECTED case=ninth clients=%d" % peers.size())
		return error})
	# A sala continua jogável: coleta e tiro reais depois da recusa.
	_add("pickup_after", _pickup_step(victims[0], 1, "weapon_1"))
	_add("hit_after", _fire_step(victims[0], victims[1], 1, 66, true))
	_add_finish()

# --- join_ended ------------------------------------------------------------------

func _plan_join_ended() -> void:
	_add_client_request("duplicate_label_refused", _label(int(peers[0])), "room_unavailable")
	_add("duplicate_did_not_replace", {"check": func():
		if not app.lobby.has(int(peers[0])) or app.lobby.size() != 4: return "original session replaced"
		return ""})
	_add("late_in_active", _late_join_step("client-late-active", RoundState.ACTIVE))
	_add("pickup", _pickup_step(victims[0], 1, "weapon_1"))
	_add("assassin_down", _fire_step(victims[0], assassin, 3, 0, true))
	_add_round_end_generic(RoundRules.REASON_ASSASSIN_DOWN, Role.TEAM_INNOCENTS, false)
	_add("late_in_ended", _late_join_step("client-late-ended", RoundState.ENDED))
	_add("late_clients_waiting", {"run": func():
		reports.clear()
		_ask(int(marks["late_active"]), "late")
		_ask(int(marks["late_ended"]), "late")
	, "done": func(): return reports.has(int(marks["late_active"])) and reports.has(int(marks["late_ended"])), "check": func():
		for key in ["late_active", "late_ended"]:
			var r: Dictionary = reports[int(marks[key])]
			if int(r["role"]) != Role.NONE: return "%s received a role" % key
			if bool(r["eliminated"]) or not (r["targets"] as Array).is_empty(): return "%s got spectator state" % key
		if app.round_authority.state != RoundState.ENDED: return "round left ENDED before the check"
		print("ADVERSE_LATE_WAITING case=join_ended clients=2 state=ENDED")
		return ""})
	_add("next_round", {"done": func():
		return app.round_authority.state == RoundState.ACTIVE and app.round_authority.round_id > int(round_ids[-1])
	, "timeout": 40000, "check": func():
		peers = app.round_authority.participants.keys()
		peers.sort()
		if peers.size() != 6: return "next round has %d participants" % peers.size()
		for key in ["late_active", "late_ended"]:
			if not app.round_authority.is_participant(int(marks[key])): return "%s is not a participant" % key
		_plan_round()
		return ""})

func _plan_join_ended_next() -> void:
	_add("roles_delivered", {"run": func(): _ask_all("roles"), "delay": 500, "done": _all_reported, "check": func():
		var error := _check_clients_roles()
		if error.is_empty(): error = _check_clients_fresh()
		if error.is_empty(): print("ADVERSE_LATE_PARTICIPATES case=join_ended participants=%d" % peers.size())
		return error})
	_add_finish()

func _late_join_step(label: String, expected_state: int) -> Dictionary:
	var key := label.trim_prefix("client-").replace("-", "_")
	var lobby_before := [0]
	return {"run": func():
		lobby_before[0] = app.lobby.size()
		_request("start_client", label)
	, "done": func(): return _peer_with_label(label) != 0, "timeout": 30000, "check": func():
		var peer_id := _peer_with_label(label)
		marks[key] = peer_id
		peers.append(peer_id)
		if app.round_authority.state != expected_state: return "state %s expected %s" % [RoundState.to_label(app.round_authority.state), RoundState.to_label(expected_state)]
		if app.round_authority.is_participant(peer_id): return "late peer became a participant"
		if not app.round_authority.is_waiting_for_next_round(peer_id): return "late peer not waiting"
		if app.round_authority.get_role_for_peer(peer_id) != Role.NONE: return "late peer has a role"
		if int(app.authoritative_world.states[peer_id]["epoch"]) != 1: return "late peer epoch"
		if app.lobby.size() != int(lobby_before[0]) + 1: return "lobby size"
		print("ADVERSE_LATE_JOIN case=%s state=%s lobby=%d" % [case_name, RoundState.to_label(expected_state), app.lobby.size()])
		return ""}

# --- drop_moving -------------------------------------------------------------------

func _back_and_forth(ticks: int) -> Array:
	var script: Array = []
	for i in ticks:
		script.append({"move": Vector2(0, -1) if (i / 60) % 2 == 0 else Vector2(0, 1)})
	return script

func _still(ticks: int) -> Array:
	var script: Array = []
	for i in ticks: script.append({"move": Vector2.ZERO})
	return script

func _plan_drop_moving() -> void:
	var dropped := int(victims[0])
	_add("moving", {"run": func():
		marks["start"] = app.authoritative_world.states[dropped]["position"]
		_send_script(dropped, "SCRIPT", _back_and_forth(900))
	, "done": func():
		var state: Dictionary = app.authoritative_world.states[dropped]
		return (state["position"] as Vector3).distance_to(marks["start"]) > 0.5 and (state["velocity"] as Vector3).length() > 0.5
	, "check": func(): return ""})
	_add("drop_while_moving", {"run": func():
		marks["dropped_label"] = _label(dropped)
		print("ADVERSE_DROP_SPEED case=drop_moving speed=%.2f" % (app.authoritative_world.states[dropped]["velocity"] as Vector3).length())
		_request("kill_client", str(marks["dropped_label"]))
	, "done": func(): return not app.lobby.has(dropped), "timeout": 30000, "check": func():
		if app.authoritative_world.states.has(dropped) or app.combat_authority.health.has(dropped) \
				or app.combat_authority.inventory.inventories.has(dropped) or app.command_logs.has(dropped):
			return "dropped peer kept server state"
		if app.round_authority.state != RoundState.ACTIVE: return "round ended on a victim drop"
		if app.round_authority.is_alive(dropped): return "dropped peer still alive"
		peers.erase(dropped)
		expected_alive.erase(dropped)
		for peer_id in peers:
			if not app.round_authority.is_alive(int(peer_id)): return "peer %d lost life" % int(peer_id)
		print("ADVERSE_DROP_CLEANED case=drop_moving lobby=%d world=%d" % [app.lobby.size(), app.authoritative_world.states.size()])
		return ""})
	_add("others_keep_playing", {"run": func(): _ask_all("after_drop"), "delay": 800, "done": _all_reported, "check": _check_clients_fresh})
	_add("pickup", _pickup_step(victims[1], 1, "weapon_1"))
	_add("assassin_down", _fire_step(victims[1], assassin, 3, 0, true))
	_add_round_end_generic(RoundRules.REASON_ASSASSIN_DOWN, Role.TEAM_INNOCENTS, false)
	_add("reveal_to_remaining", {"run": func(): _ask_all("reveal"), "delay": 800, "done": _all_reported, "check": func():
		for peer_id in peers:
			var reveal: Dictionary = reports[peer_id]["reveal"]
			if (reveal.get("players", []) as Array).size() != 5: return "client %d reveal size" % int(peer_id)
		return ""})
	_add_finish()

# --- observed_leaves -----------------------------------------------------------------

func _plan_observed_leaves() -> void:
	var shooter := int(victims[0])
	var spectator := int(victims[1])
	_add("pickup", _pickup_step(shooter, 1, "weapon_1"))
	_add("eliminate_spectator", _fire_step(shooter, spectator, 3, 0, true))
	_add("choose_target", {"run": func():
		reports.clear()
		adverse_cycle_spectator.rpc_id(spectator, [assassin, shooter])
	, "delay": 500, "done": func(): return reports.has(spectator), "check": func():
		var r: Dictionary = reports[spectator]
		var target_peer := int(r["spectate_target"])
		if target_peer == 0 or target_peer in [assassin, shooter, spectator]: return "bad observed target %d" % target_peer
		var error := _check_spectator_report(spectator)
		marks["observed"] = target_peer
		print("ADVERSE_OBSERVING case=observed_leaves targets=%d" % (r["targets"] as Array).size())
		return error})
	_add("observed_leaves", {"run": func(): _request("kill_client", _label(int(marks["observed"])))
	, "done": func(): return not app.lobby.has(int(marks["observed"])), "timeout": 30000, "check": func():
		peers.erase(int(marks["observed"]))
		expected_alive[int(marks["observed"])] = false
		expected_alive.erase(int(marks["observed"]))
		if app.round_authority.state != RoundState.ACTIVE: return "round ended"
		return ""})
	_add("spectator_moved_on", {"run": func(): _ask(spectator, "after_leave"), "delay": 800, "done": func(): return reports.has(spectator), "check": func():
		var r: Dictionary = reports[spectator]
		var target_peer := int(r["spectate_target"])
		if target_peer == int(marks["observed"]): return "camera still on the player who left"
		if target_peer not in (r["targets"] as Array): return "camera target %d outside the allowed set" % target_peer
		var error := _check_spectator_report(spectator)
		if error.is_empty(): print("ADVERSE_OBSERVED_LEFT case=observed_leaves targets=%d camera_moved=true" % (r["targets"] as Array).size())
		return error})
	# Fase 6: quem saiu vivo não ganha corpo; o eliminado que sai deixa o corpo.
	_add("no_body_for_alive_leaver", {"check": func():
		for dto in app.body_registry.public_list():
			if int(dto["peer_id"]) == int(marks["observed"]): return "a player who left alive got a body"
		if app.body_registry.size() != 1: return "bodies %d" % app.body_registry.size()
		return ""})
	_add("eliminated_leaves", {"run": func(): _request("kill_client", _label(spectator))
	, "done": func(): return not app.lobby.has(spectator), "timeout": 30000, "check": func():
		peers.erase(spectator)
		expected_alive.erase(spectator)
		var kept: Array = app.body_registry.public_list().filter(func(d): return int(d["peer_id"]) == spectator)
		if kept.size() != 1: return "the body of the eliminated player vanished on disconnect"
		return ""})
	_add("body_kept_for_everyone", {"run": func(): _ask_all("bodies"), "delay": 600, "done": _all_reported, "check": func():
		for peer_id in peers:
			var seen: Array = reports[peer_id]["bodies"]
			if seen.size() != 1 or int(seen[0]["peer_id"]) != spectator: return "client %d bodies %s" % [int(peer_id), str(seen)]
		print("ADVERSE_BODY_KEPT_AFTER_DISCONNECT case=observed_leaves clients=%d" % peers.size())
		return ""})
	_add("assassin_down", _fire_step(shooter, assassin, 3, 0, true))
	_add_round_end_generic(RoundRules.REASON_ASSASSIN_DOWN, Role.TEAM_INNOCENTS, false)
	_add_finish()

func _check_spectator_report(peer_id: int) -> String:
	var got: Array = (reports[peer_id]["targets"] as Array).duplicate()
	got.sort()
	var expected: Array = []
	for other in peers:
		if int(other) != peer_id and app.lobby.has(int(other)) and bool(expected_alive.get(int(other), false)):
			expected.append(int(other))
	expected.sort()
	if got != expected: return "spectator targets %s expected %s" % [str(got), str(expected)]
	if not bool(reports[peer_id]["eliminated"]): return "client not spectating"
	return ""

# --- leave_rejoin --------------------------------------------------------------------

func _plan_leave_rejoin() -> void:
	var leaver := int(victims[0])
	marks["leaver"] = leaver
	marks["leaver_label"] = _label(leaver)
	_add("pickup_before_leave", _pickup_step(leaver, 1, "weapon_1"))
	_add("leave", {"run": func(): _request("kill_client", str(marks["leaver_label"]))
	, "done": func(): return not app.lobby.has(leaver), "timeout": 30000, "check": func():
		peers.erase(leaver)
		expected_alive.erase(leaver)
		return ""})
	_add("rejoin", {"run": func(): _request("start_client", str(marks["leaver_label"]))
	, "done": func(): return _peer_with_label(str(marks["leaver_label"])) != 0, "timeout": 30000, "check": func():
		var fresh := _peer_with_label(str(marks["leaver_label"]))
		marks["rejoined"] = fresh
		peers.append(fresh)
		if fresh == leaver: return "same peer id reused"
		if app.round_authority.is_participant(fresh) or app.round_authority.get_role_for_peer(fresh) != Role.NONE: return "rejoined peer inherited the round"
		if int(app.authoritative_world.states[fresh]["epoch"]) != 1 or int(app.authoritative_world.states[fresh]["last_received"]) != 0: return "rejoined peer inherited command state"
		if app.combat_authority.health.has(fresh) or not str(app.combat_authority.inventory.get_inventory(fresh).get("weapon_id", "")).is_empty(): return "rejoined peer inherited combat state"
		for table in [app.authoritative_world.states, app.combat_authority.health, app.combat_authority.inventory.inventories, app.command_logs]:
			if (table as Dictionary).has(leaver): return "old peer id still in a server table"
		print("ADVERSE_REJOINED case=leave_rejoin new_peer=true waiting=%s" % str(app.round_authority.is_waiting_for_next_round(fresh)))
		return ""})
	_add("rejoined_client_clean", {"run": func():
		reports.clear()
		_ask(int(marks["rejoined"]), "rejoined")
	, "delay": 500, "done": func(): return reports.has(int(marks["rejoined"])), "check": func():
		var r: Dictionary = reports[int(marks["rejoined"])]
		if int(r["role"]) != Role.NONE or bool(r["eliminated"]) or bool(r["has_reveal"]) or int(r["pending"]) > 90: return "rejoined client state %s" % str(r)
		return ""})
	_add("pickup", _pickup_step(victims[1], 2, "weapon_2"))
	_add("assassin_down", _fire_step(victims[1], assassin, 3, 0, true))
	_add_round_end_generic(RoundRules.REASON_ASSASSIN_DOWN, Role.TEAM_INNOCENTS, true)

func _plan_leave_rejoin_next() -> void:
	_add("rejoined_participates", {"run": func(): _ask_all("roles"), "delay": 500, "done": _all_reported, "check": func():
		if peers.size() != 5 or int(marks["rejoined"]) not in peers: return "rejoined peer not in the new round"
		var error := _check_clients_roles()
		if error.is_empty(): error = _check_clients_fresh()
		if error.is_empty(): print("ADVERSE_REJOIN_PARTICIPATES case=leave_rejoin participants=%d" % peers.size())
		return error})
	_add_finish()

# --- invalid_actions ----------------------------------------------------------------

const MALFORMED_EXPECTED := {"malformed": 4, "empty_batch": 1, "batch_too_large": 1, "invalid_sequence": 1,
	"malformed_action": 3, "sequence_jump": 1, "non_finite": 1, "move_magnitude": 1, "yaw_delta": 1}

func _snapshot_official(peer_id: int) -> Dictionary:
	return {"health": app.combat_authority.health.duplicate(), "inventory": app.combat_authority.inventory.get_inventory(peer_id).duplicate(),
		"alive": app.round_authority.alive.duplicate(), "ground": JSON.stringify(app.combat_authority.public_pickups()),
		"state": app.round_authority.state}

func _same_official(peer_id: int, label: String) -> String:
	var now := _snapshot_official(peer_id)
	for key in now:
		if str(now[key]) != str(official_before[key]): return "%s changed %s" % [label, key]
	var position: Vector3 = app.authoritative_world.states[peer_id]["position"]
	if not (is_finite(position.x) and is_finite(position.y) and is_finite(position.z)): return "%s position not finite" % label
	return ""

func _plan_invalid_actions() -> void:
	var alive_peer := int(victims[0])
	var dead_peer := int(victims[1])
	_add("alive_invalid_actions", {"run": func():
		official_before = _snapshot_official(alive_peer)
		campaign_results.clear()
		campaign_shots.clear()
		# Espaçadas além do limite de taxa de ações, para cada recusa ser a da
		# própria ação (sem arma, item inexistente, fora de alcance).
		var script: Array = []
		for action in [{"kind": "fire"}, {"kind": "reload"}, {"kind": "pickup", "pickup_id": "weapon_99"}, {"kind": "pickup", "pickup_id": "ammo_3"}]:
			action["id"] = _next_id(alive_peer, str(action["kind"]))
			script.append({"action": action})
			for gap in FIRE_GAP_TICKS: script.append({})
		_send_script(alive_peer, "SCRIPT", script)
	, "done": func(): return _results_for(alive_peer).size() >= 4, "check": func():
		for result in _results_for(alive_peer):
			if bool(result["accepted"]) or str(result["reason"]).is_empty() or str(result["reason"]) == "rate_limited": return "invalid action not refused by its own rule %s" % str(result)
		if not campaign_shots.is_empty(): return "invalid fire produced a shot"
		var error := _same_official(alive_peer, "alive invalid actions")
		if error.is_empty(): print("ADVERSE_INVALID_ACTIONS_REFUSED case=invalid_actions who=alive reasons=%s" % ",".join(PackedStringArray(_results_for(alive_peer).map(func(r): return str(r["reason"])))))
		return error})
	_add_malformed_step("alive_malformed", alive_peer)
	# Continua jogável: coleta e tiro reais depois do lixo.
	_add("pickup_after_malformed", _pickup_step(alive_peer, 1, "weapon_1"))
	_add("eliminate", _fire_step(alive_peer, dead_peer, 3, 0, true))
	_add("dead_actions", {"run": func():
		campaign_results.clear()
		sync_campaign_dead_probe.rpc_id(dead_peer)
	, "done": func(): return _results_for(dead_peer).size() >= 3, "check": func(): return _check_dead_blocked(dead_peer)})
	_add_malformed_step("dead_malformed", dead_peer)
	_add("no_leak", {"run": func(): _ask_all("privacy"), "done": _all_reported, "check": func():
		for peer_id in peers:
			var r: Dictionary = reports[peer_id]
			if int(r["violations"]) != 0: return "client %d saw private fields" % int(peer_id)
			if int(r["role"]) != int(roles_by_round[round_number][int(peer_id)]): return "client %d role changed" % int(peer_id)
		return ""})
	_add_finish()

func _add_malformed_step(step_name: String, peer_id: int) -> void:
	_add(step_name, {"run": func():
		official_before = _snapshot_official(peer_id)
		counts_before = app.authoritative_world.rejection_counts.duplicate()
		campaign_results.clear()
		campaign_shots.clear()
		reports.erase(peer_id)
		adverse_malformed.rpc_id(peer_id)
	, "done": func(): return reports.has(peer_id) and str(reports[peer_id].get("kind", "")) == "malformed_done", "delay": 0, "check": func():
		var dead: bool = not app.round_authority.is_alive(peer_id)
		var deltas := {}
		for key in MALFORMED_EXPECTED:
			deltas[key] = int(app.authoritative_world.rejection_counts.get(key, 0)) - int(counts_before.get(key, 0))
		for key in ["malformed", "empty_batch", "batch_too_large", "invalid_sequence", "malformed_action", "sequence_jump"]:
			if int(deltas[key]) < int(MALFORMED_EXPECTED[key]): return "%s refused %d times, expected %d" % [key, int(deltas[key]), int(MALFORMED_EXPECTED[key])]
		# Vivo: a simulação recusa valores fora do limite. Morto: a porta (vida)
		# recusa antes, com player_dead, sem olhar os valores.
		for key in ["non_finite", "move_magnitude", "yaw_delta"]:
			if not dead and int(deltas[key]) < int(MALFORMED_EXPECTED[key]): return "%s refused %d times" % [key, int(deltas[key])]
		if not campaign_shots.is_empty(): return "malformed packet produced a shot"
		for result in _results_for(peer_id):
			if bool(result["accepted"]): return "malformed action accepted"
		var error := _same_official(peer_id, step_name)
		if error.is_empty():
			print("ADVERSE_MALFORMED_REFUSED case=invalid_actions who=%s sent=%d deltas=%s" % ["dead" if dead else "alive", int(reports[peer_id]["sent"]), JSON.stringify(deltas)])
		return error})

# --- phase4_delay ---------------------------------------------------------------------

func _plan_phase4_delay() -> void:
	var doomed := int(victims[0])
	_add("pickup_doomed", _pickup_step(doomed, 1, "weapon_1"))
	_add("pickup_assassin", _pickup_step(assassin, 0, "weapon_0"))
	# O condenado dispara sem parar (uma tentativa a cada 4 ticks) para longe
	# de todos; o assassino o elimina no meio disso. Os comandos que estavam na
	# fila ou em trânsito precisam ser recusados, sem tiro póstumo.
	_add("eliminated_with_pending_fire", {"run": func():
		_scatter([doomed, assassin])
		app.authoritative_world.teleport(assassin, LANE_FROM, PI * 0.5, 0.0)
		app.authoritative_world.teleport(doomed, LANE_TO, PI * 0.5 + 1.2, 0.0)
		campaign_results.clear()
		campaign_shots.clear()
		eliminated_at.clear()
		var doomed_script: Array = []
		for i in 240:
			doomed_script.append({"action": {"kind": "fire", "id": _next_id(doomed, "fire")}} if i % 4 == 0 else {})
		var assassin_script: Array = []
		for shot in 3:
			for gap in 30: assassin_script.append({})
			assassin_script.append({"action": {"kind": "fire", "id": _next_id(assassin, "fire")}})
		get_tree().create_timer(1.0).timeout.connect(func():
			_send_script(doomed, "SCRIPT", doomed_script)
			_send_script(assassin, "SCRIPT", assassin_script))
	, "done": func(): return eliminated_at.has(doomed) and Time.get_ticks_msec() - int(eliminated_at[doomed]) > 2500, "timeout": 40000, "check": func():
		var death := int(eliminated_at[doomed])
		var accepted_before := 0
		var refused_after := 0
		for result in _results_for(doomed):
			if int(result.get("msec", 0)) > death:
				if bool(result["accepted"]): return "doomed action accepted after elimination"
				if str(result["reason"]) in ["player_dead", "stale_epoch"]: refused_after += 1
			elif bool(result["accepted"]):
				accepted_before += 1
		for event in campaign_shots:
			if int(event["shooter_peer_id"]) == doomed and int(event.get("msec", 0)) > death: return "posthumous shot"
			if int(event["shooter_peer_id"]) == doomed and bool(event["hit_player"]): return "doomed shot hit someone"
		if accepted_before < 1: return "doomed never fired before elimination"
		if refused_after < 1: return "no pending fire was refused after elimination"
		print("ADVERSE_PENDING_AFTER_ELIMINATION case=phase4_delay fired_before=%d refused_after=%d queue_at_elimination=%d" % [accepted_before, refused_after, int(marks.get("queue_at_elimination_%d" % doomed, -1))])
		expected_alive[doomed] = false
		return ""})
	_add("doomed_client_consistent", {"run": func(): _ask(doomed, "after_death"), "delay": 1500, "done": func(): return reports.has(doomed), "check": func():
		var r: Dictionary = reports[doomed]
		if not bool(r["eliminated"]): return "doomed client not spectating"
		if int(r["epoch"]) != int(app.authoritative_world.states[doomed]["epoch"]): return "doomed client epoch %d vs %d" % [int(r["epoch"]), int(app.authoritative_world.states[doomed]["epoch"])]
		return ""})
	_add("pickup_detective", _pickup_step(detective, 2, "weapon_2"))
	# Reinício com comandos em trânsito: uma vítima anda sem parar e o detetive
	# segue disparando depois do abate, atravessando ENDED e o início da
	# rodada seguinte.
	_add("assassin_down_with_traffic", {"run": func():
		_scatter([detective, assassin, int(victims[1])])
		app.authoritative_world.teleport(detective, LANE_FROM, PI * 0.5, 0.0)
		app.authoritative_world.teleport(assassin, LANE_TO)
		app.authoritative_world.teleport(int(victims[1]), Vector3(20.0, 1.0, 11.5), PI * 0.5, 0.0)
		campaign_results.clear()
		campaign_shots.clear()
		counts_before = app.authoritative_world.rejection_counts.duplicate()
		var detective_script: Array = []
		for i in 540:
			detective_script.append({"action": {"kind": "fire", "id": _next_id(detective, "fire")}} if i % 30 == 0 else {})
		get_tree().create_timer(1.0).timeout.connect(func():
			_send_script(int(victims[1]), "SCRIPT", _back_and_forth(540))
			_send_script(detective, "SCRIPT", detective_script))
	, "done": func(): return app.round_authority.state == RoundState.ENDED, "timeout": 40000, "check": func():
		marks["ended_msec"] = Time.get_ticks_msec()
		return ""})
	_add_round_end_generic(RoundRules.REASON_ASSASSIN_DOWN, Role.TEAM_INNOCENTS, true)

func _plan_phase4_delay_next() -> void:
	_add("old_traffic_refused", {"delay": 2000, "check": func():
		var ended := int(marks["ended_msec"])
		for event in campaign_shots:
			if int(event.get("msec", 0)) > ended: return "shot after the round ended"
		var gate := 0
		for result in campaign_results:
			if int(result.get("msec", 0)) > ended:
				if bool(result["accepted"]): return "old action accepted after the round ended (%s)" % str(result)
				gate += 1
		var stale := int(app.authoritative_world.rejection_counts.get("stale_epoch", 0)) - int(counts_before.get("stale_epoch", 0))
		var inactive := int(app.authoritative_world.rejection_counts.get("round_not_active", 0)) - int(counts_before.get("round_not_active", 0))
		if inactive < 1: return "no command refused while ENDED"
		if stale < 1: return "no old-epoch command refused in the new round"
		for peer_id in peers:
			if int(app.combat_authority.health.get(int(peer_id), -1)) != 100: return "new round health changed by old traffic"
		print("ADVERSE_RESET_WITH_TRAFFIC case=phase4_delay refused_actions=%d stale_epoch=%d round_not_active=%d" % [gate, stale, inactive])
		return ""})
	_add("clients_resynced", {"run": func(): _ask_all("resync"), "delay": 500, "done": _all_reported, "check": func():
		var error := _check_clients_roles()
		if error.is_empty(): error = _check_clients_fresh()
		return error})
	# Previsão sem herança: um roteiro novo termina sem erro contra o oficial.
	_add("fresh_prediction", {"run": func():
		reports.clear()
		_scatter([int(victims[0])])
		get_tree().create_timer(1.0).timeout.connect(func(): _send_script(int(victims[0]), "CAMPAIGN", _back_and_forth(120) + _still(40)))
	, "done": func(): return reports.has(int(victims[0])), "timeout": 30000, "check": func():
		var r: Dictionary = reports[int(victims[0])]
		var error := (r["position"] as Vector3).distance_to(app.authoritative_world.states[int(victims[0])]["position"])
		print("ADVERSE_FRESH_PREDICTION case=phase4_delay error=%.6f" % error)
		return "" if error <= 0.001 else "prediction differs from official by %.4f" % error})
	_add_finish()

# --- Cliente -----------------------------------------------------------------------

var snapshots_seen := 0

func observe_client_event(kind: String, payload: Variant = null) -> void:
	super.observe_client_event(kind, payload)
	if kind == "snapshot":
		snapshots_seen += 1

@rpc("authority", "call_remote", "reliable")
func adverse_state(kind: String) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	_send_adverse_report(kind, {})

func _send_adverse_report(kind: String, extra: Dictionary) -> void:
	var data := {"kind": kind, "eliminated": app.local_eliminated, "targets": app.local_spectator_targets.duplicate(),
		"spectate_target": app._spectator_target(), "role": app.local_role, "role_round": app.local_round_id,
		"has_reveal": not app.local_final_reveal.is_empty(), "reveal": app.local_final_reveal.duplicate(true),
		"snapshot_tick": app.last_snapshot_tick, "snapshots": snapshots_seen, "epoch": app.prediction.epoch,
		"pending": app.prediction.pending.size(), "roster": app.local_roster_peers.size(), "violations": snapshot_violations,
		"bodies": app.local_bodies.values().duplicate(true)}
	data.merge(extra, true)
	sync_report.rpc_id(1, "CAMPAIGN", data)

## Troca a câmera de espectador (como Q/E) até sair de `avoid`.
@rpc("authority", "call_remote", "reliable")
func adverse_cycle_spectator(avoid: Array) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	for i in app.local_spectator_targets.size():
		if app._spectator_target() not in avoid:
			break
		app._cycle_spectator(1)
	_send_adverse_report("cycled", {})

## Lixo pelo mesmo RPC dos comandos, um pacote a cada 100 ms (abaixo do limite
## de taxa). Pacotes estruturalmente válidos usam sequências novas.
@rpc("authority", "call_remote", "reliable")
func adverse_malformed() -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	var builders: Array = [
		func(_e, _s): return "garbage",
		func(_e, _s): return [],
		func(e, s): return [e, str(s), [[0, 0, 0, 0, []]]],
		func(e, s): return [e, s, [[0, 0, 0]]],
		func(e, s): return [e, s, []],
		func(e, s):
			var many: Array = []
			for i in NetSync.MAX_COMMANDS_PER_PACKET + 1: many.append([0, 0, 0, 0, []])
			return [e, s, many],
		func(e, _s): return [e, 0, [[0, 0, 0, 0, []]]],
		func(e, s): return [e, s, [["a", 0, 0, 0, []]]],
		func(e, s): return [e, s, [[0, 0, 0, 0, ["teleport", 1]]]],
		func(e, s): return [e, s, [[0, 0, 0, 0, ["fire", "1"]]]],
		func(e, s): return [e, s, [[0, 0, 0, 0, ["pickup", 1, "x".repeat(100)]]]],
		func(e, s): return [e, s + 100000, [[0, 0, 0, 0, []]]],
		func(e, s): return [e, s, [[NAN, 0.0, 0.0, 0.0, []]]],
		func(e, s): return [e, s, [[5.0, 0.0, 0.0, 0.0, ["fire", 777]]]],
		func(e, s): return [e, s, [[0.0, 0.0, 50.0, 0.0, []]]],
	]
	for builder in builders:
		await get_tree().create_timer(0.1).timeout
		if not app.client_connected:
			return
		var seq: int = app.prediction.next_seq
		app.prediction.next_seq += 1
		app.submit_commands.rpc_id(1, (builder as Callable).call(app.prediction.epoch, seq))
	await get_tree().create_timer(0.8).timeout
	_send_adverse_report("malformed_done", {"sent": builders.size()})
