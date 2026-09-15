class_name WebSocketServerTransport
extends RefCounted

static func listen(port: int, bind_address: String) -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_server(port, bind_address)
	if error != OK:
		return null
	return peer

