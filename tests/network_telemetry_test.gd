extends SceneTree

var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var world := AuthoritativeWorld.new()
	world.add_player(1)
	world.set_telemetry_enabled(true)
	var other := AuthoritativeWorld.new()
	other.add_player(1)
	other.set_telemetry_enabled(true)
	var action := NetSync.encode_command(Vector2.ZERO, 0.0, 0.0, ["fire", 1])
	var packet := NetSync.encode_packet(1, 1, [action])
	world.receive_commands(1, packet, 0)
	world.receive_commands(1, packet, 20)
	world.bump_epoch(1)
	var fired := [0]
	world.step(func(_id): return "", func(_id, _action, _seq): fired[0] += 1, func(_id, _seq, _action, _why): pass)
	check(fired[0] == 0, "old epoch and duplicate never execute action")
	check(world.ack_for(1).keys() == ["seq", "epoch", "yaw_tokens", "pitch_tokens"], "ACK schema unchanged")
	check(world.snapshot()[0].keys() == ["peer_id", "position", "velocity", "yaw", "pitch", "spawn_index", "epoch"], "public schema unchanged")
	var before := world.telemetry_snapshot()
	world.receive_commands(1, {"secret": "ignored"}, 40)
	check(world.telemetry_snapshot().payload_samples == before.payload_samples, "malformed is never serialized")
	for index in 700:
		world.receive_commands(1, NetSync.encode_packet(1, index * 8 + 2, [action, action, action, action, action, action, action, action]), 100 + index * 20)
	check(world.states[1].queue.size() <= 32 and world.states[1].budget <= 12, "flood respects authority limits")
	var stats := world.telemetry_snapshot()
	check(stats.queue_high_water == 32 and stats.payload_samples.size() == 128, "bounded samples and observed high water")
	check(stats.duplicates == 1 and stats.queued >= 33, "actual accepted and duplicate counts")
	stats.payload_samples.clear()
	check(world.telemetry_snapshot().payload_samples.size() == 128, "snapshot returns copy")
	check(other.telemetry_snapshot().queued == 0, "rooms independent")
	for index in 100:
		world._count("hostile_%d" % index)
	check(world.rejection_counts.size() <= AuthoritativeWorld.REJECTION_CATEGORIES.size(), "fixed rejection keys")
	check(world.telemetry_snapshot().keys() == ["validated_packets", "variant_payload_bytes", "payload_samples", "queued", "duplicates", "queue_high_water"], "telemetry exact size-only schema")
	world._count("other", AuthoritativeWorld.TELEMETRY_COUNTER_MAX)
	world._count("other", 1)
	check(world.rejection_counts.other == AuthoritativeWorld.TELEMETRY_COUNTER_MAX, "counter saturation")
	world.add_player(2)
	var peer_two_before: Dictionary = world.ack_for(2)
	var size_before: int = world.telemetry_snapshot().validated_packets
	world.receive_commands(2, NetSync.encode_packet(1, 1, [NetSync.encode_command(Vector2.ZERO, 0.0, 0.0, ["pickup", 1, "x".repeat(65)])]), 0)
	check(world.telemetry_snapshot().validated_packets == size_before and world.ack_for(2) == peer_two_before, "oversized action rejected before measurement or resolution")
	for index in 40:
		world.receive_commands(2, packet, 0)
	check(world.rejection_counts.get("packet_rate", 0) > 0, "live packet flood rate rejected")
	check(world.states[2].queue.size() == 1 and world.states[2].last_received == 1, "duplicates and rate flood cannot amplify queue")
	check(world.states[1].queue.size() == 32, "other peer queue unaffected")
	world.remove_player(2)
	world.add_player(2)
	check(world.states[2].queue.is_empty() and world.ack_for(2).seq == 0, "reconnect resets per-peer queue and ACK")
	world.clear()
	check(world.telemetry_snapshot().queued == 0 and world.rejection_counts.is_empty(), "clear resets measurements")
	world.set_telemetry_enabled(false)
	world.add_player(1)
	world.receive_commands(1, packet, 0)
	check(world.telemetry_snapshot().payload_samples.is_empty(), "disabled has no serialization samples")
	print("NETWORK_TELEMETRY_TEST_OK" if failures == 0 else "NETWORK_TELEMETRY_TEST_FAILED")
	quit(0 if failures == 0 else 1)
