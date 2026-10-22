extends SceneTree

## A retained inner peer must not retain a dropped test wrapper. Reverting the
## weak forwarders to lambdas capturing self fails release and late-signal checks.
const DelayPeer = preload("res://tests/net_delay_peer.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("NET_DELAY_LIFECYCLE_ASSERT " + label)

func _initialize() -> void:
	for profile in DelayPeer.PROFILES:
		_test_lifecycle(str(profile))
	if failures == 0:
		print("NET_DELAY_LIFECYCLE_TEST_OK checks=%d" % checks)
	else:
		printerr("NET_DELAY_LIFECYCLE_TEST_FAILED failures=%d checks=%d" % [failures, checks])
	quit(0 if failures == 0 else 1)

func _test_lifecycle(profile: String) -> void:
	var inner := WebSocketMultiplayerPeer.new()
	var wrapper: MultiplayerPeer = DelayPeer.new(inner, profile, 8)
	var observed: Array = []
	wrapper.peer_connected.connect(func(peer: int): observed.append(["connected", peer]))
	wrapper.peer_disconnected.connect(func(peer: int): observed.append(["disconnected", peer]))
	inner.peer_connected.emit(17)
	inner.peer_disconnected.emit(17)
	check(observed == [["connected",17],["disconnected",17]], profile + " forwards each live signal once")
	var settings: Dictionary = DelayPeer.PROFILES[profile]
	check(float(wrapper.get("up_ms")) == float(settings.up), profile + " keeps upstream delay")
	check(float(wrapper.get("down_ms")) == float(settings.down), profile + " keeps downstream delay")
	check(float(wrapper.get("jitter_ms")) == float(settings.jitter), profile + " keeps jitter")
	var reference: WeakRef = weakref(wrapper)
	wrapper = null
	check(reference.get_ref() == null, profile + " dropped wrapper is released while inner stays alive")
	inner.peer_connected.emit(23)
	inner.peer_disconnected.emit(23)
	check(observed == [["connected",17],["disconnected",17]], profile + " late inner signals do not call a freed wrapper")
	# Keep the RED run clean too: old forwarding lambdas form the very cycle
	# under test, so explicitly disconnect them only after asserting release.
	_disconnect_inner(inner)
	inner.close()

static func _disconnect_inner(inner: MultiplayerPeer) -> void:
	for signal_name in ["peer_connected", "peer_disconnected"]:
		for connection in inner.get_signal_connection_list(signal_name):
			inner.disconnect(signal_name, connection.callable)
