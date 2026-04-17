// Sync FFI — WebSocket client and relay room management

// --- WebSocket ---

///|
pub fn ws_on_open(handle : Int, ws : @editor.JsWebSocket) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.ws_on_open(ws)
    None => ()
  }
}

///|
pub fn ws_on_message(handle : Int, data : Bytes) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.ws_on_message(data)
    None => ()
  }
}

///|
pub fn ws_on_close(handle : Int) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.ws_on_close()
    None => ()
  }
}

///|
pub fn ws_broadcast_edit(handle : Int) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.ws_broadcast_edit()
    None => ()
  }
}

///|
pub fn ws_broadcast_cursor(handle : Int) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.ws_broadcast_cursor()
    None => ()
  }
}

// --- Relay ---

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
/// Register a peer in the given room. Returns `true` on success, `false` if
/// the peer_id is empty or already connected — the caller (TS glue) should
/// close the duplicate transport.
pub fn relay_on_connect(
  room_id : String,
  peer_id : String,
  send_fn : (Bytes) -> Unit,
) -> Bool {
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
