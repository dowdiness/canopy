// Typed write methods for EphemeralHub

///|
pub fn EphemeralHub::set_cursor(
  self : EphemeralHub,
  position : Int,
  selection? : (Int, Int)? = None,
) -> Unit {
  let map : Map[String, EphemeralValue] = {}
  map["position"] = EphemeralValue::I64(position.to_int64())
  if selection is Some((start, end)) {
    map["selection"] = EphemeralValue::List([
      EphemeralValue::I64(start.to_int64()),
      EphemeralValue::I64(end.to_int64()),
    ])
  }
  self.stores[Cursor].set(self.wire_peer_id, EphemeralValue::Map(map)) catch {
    _ => ()
  }
}

///|
pub fn EphemeralHub::set_edit_mode(
  self : EphemeralHub,
  node_id : String,
) -> Unit {
  let state : EditModeState = { node_id, }
  self.stores[EditMode].set(self.wire_peer_id, state.to_ephemeral()) catch {
    _ => ()
  }
}

///|
pub fn EphemeralHub::clear_edit_mode(self : EphemeralHub) -> Unit {
  self.stores[EditMode].delete(self.wire_peer_id) catch {
    _ => ()
  }
}

///|
pub fn EphemeralHub::set_drag(
  self : EphemeralHub,
  source_id : String,
  target? : (String, DragPosition)? = None,
) -> Unit {
  let state : DragState = { source_id, target }
  self.stores[Drag].set(self.wire_peer_id, state.to_ephemeral()) catch {
    _ => ()
  }
}

///|
pub fn EphemeralHub::clear_drag(self : EphemeralHub) -> Unit {
  self.stores[Drag].delete(self.wire_peer_id) catch {
    _ => ()
  }
}

///|
pub fn EphemeralHub::set_presence(
  self : EphemeralHub,
  display_name : String,
  color : String,
  status : PresenceStatus,
) -> Unit {
  let presence : PeerPresence = {
    peer_id: self.local_peer_id,
    display_name,
    color,
    status,
  }
  self.stores[Presence].set(self.wire_peer_id, presence.to_ephemeral()) catch {
    _ => ()
  }
}
