///|
pub(all) struct PeerCursor {
  mut raw_cursor : Int
  mut adjusted_cursor : Int
  mut display_name : String
  mut color : String
  mut selection : (Int, Int)?
} derive(Show)

///|
pub struct PeerCursorView {
  cursors : Map[String, PeerCursor]
  wire_keys : Map[String, String]
}

///|
pub fn PeerCursorView::new() -> PeerCursorView {
  { cursors: Map::new(), wire_keys: Map::new() }
}

///|
pub fn PeerCursorView::set_cursor(
  self : PeerCursorView,
  peer_id : String,
  cursor : Int,
  name : String,
  color : String,
  selection? : (Int, Int)? = None,
) -> Unit {
  self.cursors[peer_id] = {
    raw_cursor: cursor,
    adjusted_cursor: cursor,
    display_name: name,
    color,
    selection,
  }
}

///|
pub fn PeerCursorView::get_cursor(
  self : PeerCursorView,
  peer_id : String,
) -> PeerCursor? {
  self.cursors.get(peer_id)
}

///|
pub fn PeerCursorView::remove(self : PeerCursorView, peer_id : String) -> Unit {
  match self.wire_keys.get(peer_id) {
    Some(logical_peer_id) => {
      self.wire_keys.remove(peer_id)
      self.cursors.remove(logical_peer_id)
    }
    None => self.cursors.remove(peer_id)
  }
}

///|
pub fn PeerCursorView::adjust_for_edit(
  self : PeerCursorView,
  edit_start : Int,
  old_len : Int,
  new_len : Int,
) -> Unit {
  for _peer_id, cursor in self.cursors {
    cursor.adjusted_cursor = adjust_position(
      cursor.adjusted_cursor,
      edit_start,
      old_len,
      new_len,
    )
    match cursor.selection {
      Some((sel_start, sel_end)) =>
        cursor.selection = Some(
          (
            adjust_position(sel_start, edit_start, old_len, new_len),
            adjust_position(sel_end, edit_start, old_len, new_len),
          ),
        )
      None => ()
    }
  }
}

///|
pub fn PeerCursorView::all_cursors(
  self : PeerCursorView,
) -> Map[String, PeerCursor] {
  self.cursors
}

///|
pub fn PeerCursorView::apply_raw_update(
  self : PeerCursorView,
  peer_id : String,
  value : EphemeralValue,
) -> Unit {
  match value {
    EphemeralValue::Map(map) => {
      let logical_peer_id = match map.get("peer_id") {
        Some(EphemeralValue::String(s)) => s
        _ => peer_id
      }
      let cursor = match map.get("cursor") {
        Some(EphemeralValue::I64(n)) => n.to_int()
        _ => 0
      }
      let name = match map.get("name") {
        Some(EphemeralValue::String(s)) => s
        _ => ""
      }
      let color = match map.get("color") {
        Some(EphemeralValue::String(s)) => s
        _ => ""
      }
      let selection = match map.get("selection") {
        Some(EphemeralValue::List(arr)) =>
          if arr.length() == 2 {
            match (arr[0], arr[1]) {
              (EphemeralValue::I64(a), EphemeralValue::I64(b)) =>
                Some((a.to_int(), b.to_int()))
              _ => None
            }
          } else {
            None
          }
        _ => None
      }
      match self.wire_keys.get(peer_id) {
        Some(old_peer_id) =>
          if old_peer_id != logical_peer_id {
            self.cursors.remove(old_peer_id)
          }
        None => ()
      }
      self.wire_keys[peer_id] = logical_peer_id
      self.set_cursor(logical_peer_id, cursor, name, color, selection~)
    }
    _ => () // Non-Map values are ignored
  }
}

///|
pub fn PeerCursorView::from_store(
  store : EphemeralStore,
  local_peer : String,
) -> PeerCursorView {
  let view = PeerCursorView::new()
  for key, value in store.get_all_states() {
    if key != local_peer {
      view.apply_raw_update(key, value)
    }
  }
  view
}

///|
pub fn adjust_position(
  pos : Int,
  edit_start : Int,
  old_len : Int,
  new_len : Int,
) -> Int {
  if pos <= edit_start {
    pos
  } else if pos <= edit_start + old_len {
    edit_start + new_len
  } else {
    pos - old_len + new_len
  }
}
