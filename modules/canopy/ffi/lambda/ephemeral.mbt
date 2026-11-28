// Ephemeral Presence API

///|
/// Encode all local ephemeral state as binary (for sending to peers)
pub fn ephemeral_encode_all(handle : Int32) -> Bytes {
  match lambda_registry.get(handle) {
    Some(h) => h.editor.encode_ephemeral_all()
    None => Bytes::make(0, b'\x00')
  }
}

///|
/// Apply remote ephemeral update (binary received from peer)
pub fn ephemeral_apply(handle : Int32, data : Bytes) -> Unit {
  match lambda_registry.get(handle) {
    Some(h) => h.editor.apply_ephemeral(data)
    None => ()
  }
}

///|
/// Set local presence (cursor position, name, color)
pub fn ephemeral_set_presence(
  handle : Int32,
  name : String,
  color : String,
) -> Unit {
  match lambda_registry.get(handle) {
    Some(h) => h.editor.set_local_presence(name, color)
    None => ()
  }
}

///|
/// Set local presence with selection range
pub fn ephemeral_set_presence_with_selection(
  handle : Int32,
  name : String,
  color : String,
  sel_start : Int32,
  sel_end : Int32,
) -> Unit {
  match lambda_registry.get(handle) {
    Some(h) =>
      h.editor.set_local_presence(
        name,
        color,
        selection=Some((sel_start, sel_end)),
      )
    None => ()
  }
}

///|
/// Delete local presence (call on beforeunload for graceful disconnect)
pub fn ephemeral_delete_presence(handle : Int32) -> Unit {
  match lambda_registry.get(handle) {
    Some(h) => h.editor.delete_local_presence()
    None => ()
  }
}

///|
/// Remove expired ephemeral entries (call on timer)
pub fn ephemeral_remove_outdated(handle : Int32) -> Unit {
  match lambda_registry.get(handle) {
    Some(h) => h.editor.remove_ephemeral_outdated()
    None => ()
  }
}

///|
/// Get adjusted peer cursors as JSON for rendering
/// Returns: [{"peer_id":"123","cursor":8,"name":"Alice","color":"#ff0000","selection":null}, ...]
pub fn ephemeral_get_peer_cursors_json(handle : Int32) -> String {
  match lambda_registry.get(handle) {
    Some(h) => {
      let cursors = h.editor.get_peer_cursors()
      let items : Array[String] = []
      for peer_id, cursor in cursors {
        let adj = if cursor.adjusted_cursor < 0 {
          0
        } else {
          cursor.adjusted_cursor
        }
        let sel = match cursor.selection {
          Some((s, e)) => "[" + s.to_string() + "," + e.to_string() + "]"
          None => "null"
        }
        let item = "{\"peer_id\":" +
          Json(peer_id).stringify() +
          ",\"cursor\":" +
          adj.to_string() +
          ",\"name\":" +
          Json(cursor.display_name).stringify() +
          ",\"color\":" +
          Json(cursor.color).stringify() +
          ",\"selection\":" +
          sel +
          "}"
        items.push(item)
      }
      "[" + items.join(",") + "]"
    }
    None => "[]"
  }
}
