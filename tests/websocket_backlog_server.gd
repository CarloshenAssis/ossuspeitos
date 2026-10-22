extends SceneTree
const PACKETS := 50
const PAYLOAD_BYTES := 3332
var peer := WebSocketMultiplayerPeer.new()
var client_id := 0
var sent := 0
var next_send := 0
var started := 0
var tail_sent := false
func _initialize() -> void:
 started=Time.get_ticks_msec()
 var port := OS.get_cmdline_user_args()[0].to_int()
 peer.peer_connected.connect(func(id: int): client_id=id)
 peer.peer_disconnected.connect(func(_id: int): print("WEBSOCKET_BACKLOG_SERVER_DONE sent=%d tail=%s"%[sent,tail_sent]);peer.close();quit(0))
 var error := peer.create_server(port,"127.0.0.1")
 if error!=OK: push_error("BACKLOG_SERVER_BIND_FAILED");quit(1);return
 print("WEBSOCKET_BACKLOG_SERVER_READY port=%d"%port)
func _process(_delta: float) -> bool:
 if Time.get_ticks_msec()-started>25000:
  push_error("BACKLOG_SERVER_TIMEOUT");peer.close();quit(1);return true
 peer.poll()
 while peer.get_available_packet_count()>0:
  var packet := peer.get_packet()
  if packet==PackedByteArray([1]):
   peer.set_target_peer(client_id)
   next_send=Time.get_ticks_msec()
 if next_send>0 and Time.get_ticks_msec()>=next_send and sent<PACKETS:
  var packet := PackedByteArray()
  packet.resize(PAYLOAD_BYTES)
  packet.encode_u32(0,sent)
  if peer.put_packet(packet)!=OK: push_error("BACKLOG_SERVER_SEND_FAILED");quit(1);return true
  sent+=1
  next_send+=50
 if sent==PACKETS and not tail_sent:
  var tail := PackedByteArray()
  tail.resize(8)
  tail.encode_u32(0,PACKETS)
  if peer.put_packet(tail)!=OK: push_error("BACKLOG_SERVER_TAIL_FAILED");quit(1);return true
  tail_sent=true
 return false
