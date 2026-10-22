extends Node
const Transport = preload("res://client/websocket_client_transport.gd")
const PACKETS := 50
const PAYLOAD_BYTES := 3332
const STALL_MSEC := 3200
var peer: WebSocketMultiplayerPeer
var start := 0
var resume_at := 0
var drain_at := 0
var received: Dictionary = {}
var tail_received := false
var complete := false
func _ready() -> void:
 start=Time.get_ticks_msec()
 peer=Transport.connect_to_url(str(ProjectSettings.get_setting("test/backlog_url")))
 if peer==null: _finish("connect_error")
func _process(_delta: float) -> void:
 if complete: return
 var now := Time.get_ticks_msec()
 if now-start>15000: _finish("timeout");return
 if resume_at==0:
  peer.poll()
  if peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED:
   peer.set_target_peer(1)
   peer.put_packet(PackedByteArray([1]))
   resume_at=now+STALL_MSEC
   print("WEBSOCKET_BACKLOG_STALL milliseconds=%d inbound=%d"%[STALL_MSEC,peer.inbound_buffer_size])
  return
 if now<resume_at: return
 if drain_at==0: drain_at=now
 peer.poll()
 while peer.get_available_packet_count()>0:
  var packet := peer.get_packet()
  if packet.size()==8 and packet.decode_u32(0)==PACKETS:
   tail_received=true
  elif packet.size()==PAYLOAD_BYTES:
   received[packet.decode_u32(0)]=true
  else:
   _finish("unexpected_payload_%d"%packet.size());return
 if now-drain_at>=1200: _finish("")
func _finish(reason: String) -> void:
 if complete: return
 complete=true
 var ok := reason.is_empty() and received.size()==PACKETS and tail_received
 print("WEBSOCKET_BACKLOG_RESULT received=%d expected=%d reliable_tail=%s inbound=%d reason=%s"%[received.size(),PACKETS,tail_received,peer.inbound_buffer_size if peer!=null else -1,reason])
 print("WEBSOCKET_BACKLOG_TEST_%s"%("OK" if ok else "FAILED"))
 if peer!=null: peer.close()
