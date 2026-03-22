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
/// Send data to a specific peer by ID. Silent no-op if peer not found.
/// Public API — used by on_message routing and crdt_relay.mbt FFI.
pub fn RelayRoom::send_to(
  self : RelayRoom,
  peer_id : String,
  data : Bytes,
) -> Unit {
  for peer in self.peers {
    if peer.peer_id == peer_id {
      (peer.send_fn)(data)
      return
    }
  }
}

///|
pub fn RelayRoom::on_message(
  self : RelayRoom,
  sender : String,
  data : Bytes,
) -> Unit {
  // Safety: short or non-v2 frames broadcast unchanged
  if data.length() < 3 || data[0] != version {
    self.broadcast(sender, data)
    return
  }
  let msg_type = data[1]
  match msg_type {
    b'\x01' => {
      // CrdtOps -> wrap as RelayedCrdtOps (0x06) with sender ID, broadcast
      let wrapped = wrap_with_sender(sender, b'\x06', data, 3)
      self.broadcast(sender, wrapped)
    }
    b'\x03' | b'\x04' =>
      // SyncRequest/SyncResponse -> read target, wrap with sender, send_to target
      match read_relay_string(data, 3) {
        Some((target, after_target)) => {
          let wrapped = wrap_with_sender(sender, data[1], data, after_target)
          self.send_to(target, wrapped)
        }
        None => () // Malformed target_id — drop. Monitor at CF Worker layer if needed.
      }
    _ => self.broadcast(sender, data)
  }
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
