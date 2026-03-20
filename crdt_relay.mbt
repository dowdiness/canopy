// Relay exports

///|
let relay_rooms : Map[String, @relay.RelayRoom] = Map::new()

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
pub fn relay_on_connect(
  room_id : String,
  peer_id : String,
  send_fn : (Bytes) -> Unit,
) -> Unit {
  get_or_create_room(room_id).on_connect(peer_id, send_fn)
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
