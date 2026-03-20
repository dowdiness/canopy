///|
struct RelayPeer {
  peer_id : String
  send_fn : (Bytes) -> Unit
}

///|
/// Room of connected peers. Peer IDs are trusted (assigned by the server-side
/// TypeScript glue, e.g. crypto.randomUUID() in CF Worker). No duplicate-ID
/// or membership validation — callers must ensure IDs are unique.
pub struct RelayRoom {
  priv mut peers : Array[RelayPeer]
}

///|
pub fn RelayRoom::new() -> RelayRoom {
  { peers: [] }
}

///|
pub fn RelayRoom::on_connect(
  self : RelayRoom,
  peer_id : String,
  send_fn : (Bytes) -> Unit,
) -> Unit {
  let join_msg = encode_peer_joined(peer_id)
  self.broadcast(peer_id, join_msg)
  self.peers.push({ peer_id, send_fn })
}

///|
pub fn RelayRoom::on_message(
  self : RelayRoom,
  sender : String,
  data : Bytes,
) -> Unit {
  self.broadcast(sender, data)
}

///|
pub fn RelayRoom::on_disconnect(self : RelayRoom, peer_id : String) -> Unit {
  self.peers = self.peers.filter(fn(p) { p.peer_id != peer_id })
  let leave_msg = encode_peer_left(peer_id)
  self.broadcast(peer_id, leave_msg)
}

///|
pub fn RelayRoom::peer_count(self : RelayRoom) -> Int {
  self.peers.length()
}

///|
fn RelayRoom::broadcast(
  self : RelayRoom,
  exclude : String,
  data : Bytes,
) -> Unit {
  for peer in self.peers {
    if peer.peer_id != exclude {
      (peer.send_fn)(data)
    }
  }
}
