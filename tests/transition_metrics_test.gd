extends SceneTree

## Fase 10: medição das transições com relógio injetado (determinística).
## Classes, duração, marca substituída, cancelamento, erro, resumo, formato da
## linha (sem dado sensível) e ida e volta pelo parser do relatório.

var failures := 0
var checks := 0
var fake_now := 0

func _initialize() -> void:
	_test_disabled_is_silent()
	_test_begin_end_with_clock()
	_test_classes()
	_test_replace_cancel_error()
	_test_summary()
	_test_line_has_no_sensitive_fields()
	_test_query_key_allowed()
	if failures > 0:
		push_error("TRANSITION_METRICS_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return
	print("TRANSITION_METRICS_TEST_OK checks=%d" % checks)
	quit(0)

func _clock() -> int:
	return fake_now

func _metrics() -> TransitionMetrics:
	fake_now = 0
	return TransitionMetrics.new(true, _clock, "abc123")

func _test_disabled_is_silent() -> void:
	var off := TransitionMetrics.new(false, _clock)
	off.begin("room_join")
	_expect(not off.has("room_join"), "disabled metrics keep no marks")
	_expect(off.end("room_join") < 0.0 and off.record("server_tick", 5.0) < 0.0, "disabled metrics record nothing")
	_expect(off.records.is_empty(), "disabled metrics have no records")
	_expect(not TransitionMetrics.from_arguments({}).enabled, "off by default")
	_expect(TransitionMetrics.from_arguments({"transition-metrics": "true"}).enabled, "flag turns metrics on")

func _test_begin_end_with_clock() -> void:
	var m := _metrics()
	m.round_id = 3
	fake_now = 1_000_000
	m.begin("room_join")
	fake_now = 1_045_500
	var ms := m.end("room_join")
	_expect(is_equal_approx(ms, 45.5), "room_join measured with injected clock (%s)" % ms)
	_expect(m.records.size() == 1 and int(m.records[0]["round"]) == 3, "record carries round id")
	_expect(not m.has("room_join"), "mark consumed by end")
	_expect(m.end("room_join") < 0.0, "second end without begin records nothing")
	# Marca no futuro (fim previsto da contagem): atraso real depois do fim.
	m.begin("countdown_to_play", 2_000_000 + 10_000_000)
	fake_now = 12_120_000
	_expect(is_equal_approx(m.end("countdown_to_play"), 120.0), "countdown_to_play counts only the delay after the countdown")
	m.begin("countdown_to_play", 50_000_000)
	fake_now = 49_000_000
	_expect(m.end("countdown_to_play") == 0.0, "early arrival clamps to zero")

func _test_classes() -> void:
	_expect(TransitionMetrics.classify("countdown") == TransitionMetrics.CLASS_UX, "countdown is expected UX")
	_expect(TransitionMetrics.classify("results_to_lobby") == TransitionMetrics.CLASS_UX, "results screen is expected UX")
	_expect(TransitionMetrics.classify("room_join") == TransitionMetrics.CLASS_NETWORK, "join is network")
	_expect(TransitionMetrics.classify("server_tick") == TransitionMetrics.CLASS_SERVER, "tick is server")
	_expect(TransitionMetrics.classify("render_hitch") == TransitionMetrics.CLASS_RENDER, "hitch is render")
	_expect(TransitionMetrics.classify("whatever") == TransitionMetrics.CLASS_UNKNOWN, "unknown kind is undetermined")

func _test_replace_cancel_error() -> void:
	var m := _metrics()
	fake_now = 100_000
	m.begin("ready_ack")
	fake_now = 900_000
	m.begin("ready_ack")
	fake_now = 930_000
	_expect(is_equal_approx(m.end("ready_ack"), 30.0), "a new begin replaces the older attempt")
	m.begin("countdown")
	m.cancel("countdown")
	_expect(not m.has("countdown") and m.end("countdown") < 0.0, "cancel drops the mark")
	m.begin("room_join")
	fake_now = 1_130_000
	m.end("room_join", -1, "error")
	var last: Dictionary = m.records[-1]
	_expect(str(last["kind"]) == "error" and is_equal_approx(float(last["ms"]), 200.0), "refused request is recorded as error")

func _test_summary() -> void:
	var entries: Array = []
	for value in [10.0, 20.0, 30.0, 40.0, 1000.0]:
		entries.append({"kind": "room_join", "ms": value})
	entries.append({"kind": "countdown", "ms": 10005.0})
	var summary := TransitionMetrics.summarize(entries)
	var join: Dictionary = summary["room_join"]
	_expect(int(join["n"]) == 5 and float(join["min"]) == 10.0 and float(join["max"]) == 1000.0, "summary n/min/max")
	_expect(float(join["p50"]) == 30.0, "summary median")
	_expect(str(summary["countdown"]["class"]) == "ux", "summary keeps class")

func _test_line_has_no_sensitive_fields() -> void:
	var m := _metrics()
	m.round_id = 2
	var entry := {"kind": "room_create", "ms": 12.34, "class": "network", "round": 2}
	var text := TransitionMetrics.line(entry, m.session)
	_expect(text == "TRANSITION kind=room_create ms=12.3 class=network round=2 session=abc123", "line format: %s" % text)
	var keys := text.substr(11).split(" ")
	var names: Array = []
	for token in keys:
		names.append(token.split("=")[0])
	_expect(names == ["kind", "ms", "class", "round", "session"], "line has only kind/ms/class/round/session")
	var parsed := TransitionMetrics.parse_line("[client] " + text)
	_expect(str(parsed.get("kind", "")) == "room_create" and is_equal_approx(float(parsed["ms"]), 12.3) and int(parsed["round"]) == 2, "parser reads the line back")
	_expect(TransitionMetrics.parse_line("ROOM_ERROR id=x").is_empty(), "parser ignores other lines")
	var random_session := TransitionMetrics.new(true).session
	_expect(random_session.length() == 6 and random_session.is_valid_hex_number(), "session id is 6 random hex digits")

func _test_query_key_allowed() -> void:
	var values := NetworkConfig.web_query_arguments("?transition-metrics=true&online-url=ws://evil:1", "example.github.io")
	_expect(str(values.get("transition-metrics", "")) == "true", "web page can enable metrics")
	_expect(not values.has("online-url"), "web page still cannot redirect the server")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TRANSITION_METRICS_TEST_FAILED %s" % message)
