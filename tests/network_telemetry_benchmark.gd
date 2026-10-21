extends SceneTree

## In-process four-peer command workload. This measures instrumentation CPU,
## not WebSocket framing or TCP bandwidth. Same packets with telemetry off/on.
func _initialize() -> void:
	for batch in [2, 8]:
		for enabled in [false, true]:
			var world := AuthoritativeWorld.new()
			world.set_telemetry_enabled(enabled)
			for peer in range(1, 5): world.add_player(peer)
			var commands: Array = []
			for index in batch: commands.append(NetSync.encode_command(Vector2.ZERO, 0.0, 0.0, []))
			var started := Time.get_ticks_usec()
			for tick in 2400:
				if tick % batch == 0:
					for peer in range(1, 5): world.receive_commands(peer, NetSync.encode_packet(1, tick + 1, commands), tick * 17)
				world.step(func(_id): return "", func(_id, _action, _seq): pass, func(_id, _seq, _action, _reason): pass)
			print("TELEMETRY_BENCH peers=4 ticks=2400 batch=%d enabled=%s elapsed_usec=%d stats=%s" % [batch, enabled, Time.get_ticks_usec() - started, JSON.stringify(world.telemetry_snapshot())])
	quit()
