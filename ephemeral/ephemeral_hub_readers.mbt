// Typed read methods for EphemeralHub

///|
pub fn EphemeralHub::get_cursor(
  self : EphemeralHub,
  peer_id : String,
) -> (Int, (Int, Int)?)? {
  let wire_id = to_wire_peer_id(peer_id)
  match self.stores[Cursor].get(wire_id) {
    Some(EphemeralValue::Map(map)) => {
      guard map.get("position") is Some(EphemeralValue::I64(n)) else {
        return None
      }
      let position = n.to_int()
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
      Some((position, selection))
    }
    _ => None
  }
}

///|
pub fn EphemeralHub::get_edit_mode(
  self : EphemeralHub,
  peer_id : String,
) -> EditModeState? {
  let wire_id = to_wire_peer_id(peer_id)
  match self.stores[EditMode].get(wire_id) {
    Some(value) => EditModeState::from_ephemeral(value)
    None => None
  }
}

///|
/// Returns all peers currently in edit mode.
/// Keys are wire peer IDs (numeric strings from to_wire_peer_id),
/// not original peer IDs. Use get_edit_mode(peer_id) for single-peer lookup.
pub fn EphemeralHub::get_all_editing(
  self : EphemeralHub,
) -> Map[String, EditModeState] {
  let result : Map[String, EditModeState] = {}
  for key, value in self.stores[EditMode].get_all_states() {
    if EditModeState::from_ephemeral(value) is Some(state) {
      result[key] = state
    }
  }
  result
}

///|
pub fn EphemeralHub::get_presence(
  self : EphemeralHub,
  peer_id : String,
) -> PeerPresence? {
  let wire_id = to_wire_peer_id(peer_id)
  match self.stores[Presence].get(wire_id) {
    Some(value) => PeerPresence::from_ephemeral(value)
    None => None
  }
}

///|
pub fn EphemeralHub::get_online_peers(
  self : EphemeralHub,
) -> Array[PeerPresence] {
  let result : Array[PeerPresence] = []
  for _key, value in self.stores[Presence].get_all_states() {
    if PeerPresence::from_ephemeral(value) is Some(presence) {
      result.push(presence)
    }
  }
  result
}
