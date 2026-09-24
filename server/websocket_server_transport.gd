class_name WebSocketServerTransport
extends RefCounted

static func listen(port: int, bind_address: String) -> WebSocketMultiplayerPeer:
	return open(port, bind_address)["peer"]

## Como `listen`, mas também devolve o código de erro do bind (porta ocupada,
## endereço inválido), para o servidor dedicado registrar a causa.
static func open(port: int, bind_address: String) -> Dictionary:
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_server(port, bind_address)
	if error != OK:
		return {"peer": null, "error": error}
	return {"peer": peer, "error": OK}
