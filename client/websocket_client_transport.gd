class_name WebSocketClientTransport
extends RefCounted

static func connect_to_url(url: String) -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_client(url)
	if error != OK:
		return null
	return peer

