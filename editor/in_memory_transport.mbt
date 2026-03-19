///|
pub struct InMemoryRoom {
  peers : Map[String, Array[(Bytes) -> Unit]]
}

///|
pub fn InMemoryRoom::new() -> InMemoryRoom {
  { peers: Map::new() }
}

///|
fn InMemoryRoom::broadcast(
  self : InMemoryRoom,
  sender : String,
  data : Bytes,
) -> Unit {
  for peer_id, handlers in self.peers {
    if peer_id != sender {
      for handler in handlers {
        handler(data)
      }
    }
  }
}

///|
fn InMemoryRoom::register(self : InMemoryRoom, peer_id : String) -> Unit {
  match self.peers.get(peer_id) {
    Some(_) => ()
    None => self.peers[peer_id] = []
  }
}

///|
fn InMemoryRoom::unregister(self : InMemoryRoom, peer_id : String) -> Unit {
  self.peers.remove(peer_id)
}

///|
pub struct InMemoryTransport {
  peer_id : String
  room : InMemoryRoom
}

///|
pub fn InMemoryTransport::new(
  peer_id : String,
  room : InMemoryRoom,
) -> InMemoryTransport {
  room.register(peer_id)
  { peer_id, room }
}

///|
pub impl SyncTransport for InMemoryTransport with send(self, data) {
  self.room.broadcast(self.peer_id, data)
}

///|
pub impl SyncTransport for InMemoryTransport with on_receive(self, handler) {
  match self.room.peers.get(self.peer_id) {
    Some(handlers) => handlers.push(handler)
    None => ()
  }
}

///|
pub impl SyncTransport for InMemoryTransport with close(self) {
  self.room.unregister(self.peer_id)
}
