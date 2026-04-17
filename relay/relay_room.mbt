///|
struct RelayPeer {
  peer_id : String
  send_fn : (Bytes) -> Unit
}

///|
/// Room of connected peers. Peer IDs are assigned by the server-side glue
/// (e.g. `crypto.randomUUID()` in the CF Worker), but `RelayRoom` enforces
/// membership validity itself: duplicate or empty peer IDs are rejected at
/// `on_connect`, and messages from non-members are dropped by `on_message`.
pub struct RelayRoom {
  priv mut peers : Array[RelayPeer]
}

///|
pub fn RelayRoom::new() -> RelayRoom {
  { peers: [] }
}

///|
/// Register a peer. Returns `true` if accepted, `false` if rejected.
/// Rejected when the peer_id is empty or already present in the room.
/// On rejection the room is unchanged and no PeerJoined is broadcast —
/// callers (FFI glue) should close the duplicate transport.
pub fn RelayRoom::on_connect(
  self : RelayRoom,
  peer_id : String,
  send_fn : (Bytes) -> Unit,
) -> Bool {
  if peer_id == "" {
    return false
  }
  if self.has_peer(peer_id) {
    return false
  }
  let join_msg = encode_peer_joined(peer_id)
  self.broadcast(peer_id, join_msg)
  self.peers.push({ peer_id, send_fn })
  true
}

///|
fn RelayRoom::has_peer(self : RelayRoom, peer_id : String) -> Bool {
  for peer in self.peers {
    if peer.peer_id == peer_id {
      return true
    }
  }
  false
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
  // Drop messages from senders that are not members of the room —
  // defense-in-depth against ghost IDs that never completed on_connect.
  if !self.has_peer(sender) {
    return
  }
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
