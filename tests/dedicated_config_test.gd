extends SceneTree

## Fase 8: configuração do servidor dedicado (`DedicatedConfig`), sem rede.
## Precedência de porta, validação, lista fechada de argumentos e commit.

var failures := 0
var checks := 0

func _initialize() -> void:
	_test_port_precedence()
	_test_invalid_ports()
	_test_bind()
	_test_refused_arguments()
	_test_status_interval()
	_test_commit()
	if failures > 0:
		push_error("DEDICATED_CONFIG_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return
	print("DEDICATED_CONFIG_TEST_OK checks=%d" % checks)
	quit(0)

func _test_port_precedence() -> void:
	var none := DedicatedConfig.resolve({"mode": "dedicated"}, {})
	_expect(none["ok"] and none["port"] == NetworkConfig.DEFAULT_PORT and none["port_source"] == "default", "no PORT uses the documented default")
	var env := DedicatedConfig.resolve({"mode": "dedicated"}, {"PORT": "8123"})
	_expect(env["ok"] and env["port"] == 8123 and env["port_source"] == "env", "PORT from the environment")
	var argument := DedicatedConfig.resolve({"mode": "dedicated", "port": "7001"}, {"PORT": "8123"})
	_expect(argument["ok"] and argument["port"] == 7001 and argument["port_source"] == "argument", "explicit --port wins over PORT")
	_expect(DedicatedConfig.resolve({}, {"PORT": "65535"})["port"] == 65535 and DedicatedConfig.resolve({}, {"PORT": "1"})["port"] == 1, "range limits accepted")

func _test_invalid_ports() -> void:
	for value in ["", " ", "abc", "0", "65536", "70000", "-1", "+80", "80.5", " 80", "80 ", "0x50", "999999"]:
		var result := DedicatedConfig.resolve({}, {"PORT": value})
		_expect(not result["ok"] and str(result["errors"][0]).begins_with("PORT inválida"), "PORT \"%s\" is a fatal error" % value)
	var bad_argument := DedicatedConfig.resolve({"port": "abc"}, {"PORT": "8080"})
	_expect(not bad_argument["ok"], "invalid --port never falls back to PORT")
	var empty_argument := DedicatedConfig.resolve({"port": ""}, {})
	_expect(not empty_argument["ok"], "empty --port is an error")

func _test_bind() -> void:
	_expect(DedicatedConfig.resolve({}, {})["bind"] == "0.0.0.0", "dedicated listens on all interfaces by default")
	_expect(DedicatedConfig.resolve({}, {"ARMED_MYSTERY_BIND": "127.0.0.1"})["bind"] == "127.0.0.1", "bind from the environment")
	_expect(DedicatedConfig.resolve({"bind": "::"}, {})["ok"], "IPv6 any accepted")
	_expect(not DedicatedConfig.resolve({}, {"ARMED_MYSTERY_BIND": "nao-e-ip"})["ok"], "invalid bind is an error")
	# O servidor do menu local continua em loopback.
	_expect(NetworkConfig.DEFAULT_BIND_ADDRESS == "127.0.0.1", "local server default stays on loopback")

func _test_refused_arguments() -> void:
	for key in ["combat-test", "campaign-test", "adverse-test", "sync-test", "spectator-reveal-test", "stop-after-clients",
			"stop-after-round-active", "expect-late-joins", "round-seed", "countdown-seconds", "round-end-delay-seconds",
			"hosted", "status-file", "test-protocol-version", "test-shutdown-after-msec", "test-net-profile", "expect-clients"]:
		var result := DedicatedConfig.resolve({"mode": "dedicated", key: "1"}, {"PORT": "9000"})
		_expect(not result["ok"] and key in result["refused"], "--%s refused in production" % key)
	var allowed := DedicatedConfig.resolve({"mode": "dedicated", "port": "9000", "bind": "0.0.0.0", "shutdown-file": "/tmp/x"}, {})
	_expect(allowed["ok"] and allowed["shutdown_file"] == "/tmp/x", "allowed arguments pass")

func _test_status_interval() -> void:
	_expect(DedicatedConfig.resolve({}, {})["status_interval_seconds"] == DedicatedConfig.STATUS_INTERVAL_SECONDS, "status line default")
	_expect(DedicatedConfig.resolve({}, {"ARMED_MYSTERY_STATUS_SECONDS": "0"})["status_interval_seconds"] == 0, "status line can be disabled")
	_expect(not DedicatedConfig.resolve({}, {"ARMED_MYSTERY_STATUS_SECONDS": "x"})["ok"], "invalid status interval is an error")

func _test_commit() -> void:
	_expect(DedicatedConfig.commit_from({}) == "unknown", "unknown commit without variables")
	_expect(DedicatedConfig.commit_from({"ARMED_MYSTERY_COMMIT": "", "RAILWAY_GIT_COMMIT_SHA": "d0beb8f5c55b36df7d674d55965a23b8d54ad69b"}) == "d0beb8f5c55b", "Railway SHA used when the image has none")
	_expect(DedicatedConfig.commit_from({"ARMED_MYSTERY_COMMIT": "c91d39c8dc6a66bd59cf98b700ad6d662cbbb501"}) == "c91d39c8dc6a", "image commit first")
	_expect(DedicatedConfig.commit_from({"ARMED_MYSTERY_COMMIT": "x; rm -rf"}) == "unknown", "garbage commit ignored")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("DEDICATED_CONFIG_TEST_FAILED %s" % message)
