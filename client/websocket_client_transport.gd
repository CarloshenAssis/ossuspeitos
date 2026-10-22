class_name WebSocketClientTransport
extends RefCounted

## Bounded headroom for Web main-thread/render stalls: 6 seconds at the
## measured eight-player snapshot load (3332 bytes * 20 Hz = 399840 bytes),
## plus reliable control traffic. Godot's default 65535 bytes loses frames
## in the browser while JS receives messages before the client can poll.
## Servers/outbound/packet-count limits and authoritative DTOs are unchanged.
const INBOUND_BUFFER_BYTES := 512 * 1024 - 1

static func connect_to_url(url: String) -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = INBOUND_BUFFER_BYTES
	var error := peer.create_client(url)
	if error != OK:
		return null
	return peer

