// Relay room FFI — multi-peer relay room management

///|
let relay_rooms : Map[String, @relay.RelayRoom] = Map::default()

///|
fn get_or_create_room(room_id : String) -> @relay.RelayRoom {
  match relay_rooms.get(room_id) {
    Some(room) => room
    None => {
      let room = @relay.RelayRoom::new()
      relay_rooms[room_id] = room
      room
    }
  }
}

///|
/// Register a peer in the given room. Returns `true` on success, `false` if
/// the peer_id is empty or already connected — the caller (TS glue) should
/// close the duplicate transport.
///
/// If the call creates a new room and the peer is then rejected, the empty
/// room is removed so that clients cannot leak room entries by sending
/// repeated invalid connects to unique room IDs.
pub fn relay_on_connect(
  room_id : String,
  peer_id : String,
  send_fn : (Bytes) -> Unit,
) -> Bool {
  let room = get_or_create_room(room_id)
  let accepted = room.on_connect(peer_id, send_fn)
  if !accepted && room.peer_count() == 0 {
    relay_rooms.remove(room_id)
  }
  accepted
}

///|
pub fn relay_on_message(
  room_id : String,
  peer_id : String,
  data : Bytes,
) -> Unit {
  match relay_rooms.get(room_id) {
    Some(room) => room.on_message(peer_id, data)
    None => () // ignore messages for non-existent rooms
  }
}

///|
pub fn relay_on_disconnect(room_id : String, peer_id : String) -> Unit {
  match relay_rooms.get(room_id) {
    Some(room) => {
      room.on_disconnect(peer_id)
      if room.peer_count() == 0 {
        relay_rooms.remove(room_id)
      }
    }
    None => ()
  }
}
