extends SceneTree

const NetworkAppScript = preload("res://shared/network_app.gd")

func _initialize() -> void:
	_expect(NetworkAppScript.resolve_start_mode({}, true, false, true) == "demo", "visual demo starts offline")
	_expect(NetworkAppScript.resolve_start_mode({"mode": "client"}, true, false, true) == "demo", "visual demo ignores online client mode")
	_expect(NetworkAppScript.resolve_start_mode({"mode": "server"}, true, false, true) == "demo", "visual demo ignores server mode")
	_expect(NetworkAppScript.resolve_start_mode({"mode": "client"}, false, false, true) == "client", "full client preset preserves client mode")
	_expect(NetworkAppScript.resolve_start_mode({}, false, true, false) == "menu", "desktop playtest keeps menu fallback")
	_expect(NetworkAppScript.resolve_start_mode({}, false, false, false).is_empty(), "headless build still requires a mode")
	print("VISUAL_DEMO_MODE_TEST_OK")
	quit(0)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error("VISUAL_DEMO_MODE_TEST_FAILED %s" % message)
		quit(1)
