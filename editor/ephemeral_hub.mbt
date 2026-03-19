///|
pub(all) enum EphemeralNamespace {
  Cursor
  EditMode
  Drag
  Presence
} derive(Show, Eq, Compare, Hash)

///|
fn default_timeout(ns : EphemeralNamespace) -> UInt64 {
  match ns {
    Cursor => 30_000UL
    EditMode => 60_000UL
    Drag => 5_000UL
    Presence => 120_000UL
  }
}

///|
fn namespace_to_byte(ns : EphemeralNamespace) -> Byte {
  match ns {
    Cursor => b'\x01'
    EditMode => b'\x02'
    Drag => b'\x03'
    Presence => b'\x04'
  }
}

///|
fn namespace_from_byte(b : Byte) -> EphemeralNamespace? {
  match b {
    b'\x01' => Some(Cursor)
    b'\x02' => Some(EditMode)
    b'\x03' => Some(Drag)
    b'\x04' => Some(Presence)
    _ => None
  }
}

///|
let all_namespaces : Array[EphemeralNamespace] = [
  Cursor,
  EditMode,
  Drag,
  Presence,
]

///|
pub struct EphemeralHub {
  local_peer_id : String
  wire_peer_id : String
  stores : Map[EphemeralNamespace, EphemeralStore]
}

///|
pub fn EphemeralHub::new(local_peer_id : String) -> EphemeralHub {
  let stores : Map[EphemeralNamespace, EphemeralStore] = {}
  for ns in all_namespaces {
    stores[ns] = EphemeralStore::new(default_timeout(ns))
  }
  let wire_peer_id = to_wire_peer_id(local_peer_id)
  { local_peer_id, wire_peer_id, stores }
}

// --- Typed write methods ---

///|
pub fn EphemeralHub::set_cursor(
  self : EphemeralHub,
  position : Int,
  selection? : (Int, Int)? = None,
) -> Unit {
  let map : Map[String, EphemeralValue] = {}
  map["position"] = EphemeralValue::I64(position.to_int64())
  match selection {
    Some((start, end)) =>
      map["selection"] = EphemeralValue::List([
        EphemeralValue::I64(start.to_int64()),
        EphemeralValue::I64(end.to_int64()),
      ])
    None => ()
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

// --- Typed read methods ---

///|
pub fn EphemeralHub::get_cursor(
  self : EphemeralHub,
  peer_id : String,
) -> (Int, (Int, Int)?)? {
  let wire_id = to_wire_peer_id(peer_id)
  match self.stores[Cursor].get(wire_id) {
    Some(EphemeralValue::Map(map)) => {
      let position = match map.get("position") {
        Some(EphemeralValue::I64(n)) => n.to_int()
        _ => return None
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
    match EditModeState::from_ephemeral(value) {
      Some(state) => result[key] = state
      None => ()
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
    match PeerPresence::from_ephemeral(value) {
      Some(presence) => result.push(presence)
      None => ()
    }
  }
  result
}

// --- Sync and lifecycle ---

///|
pub fn EphemeralHub::get_store(
  self : EphemeralHub,
  ns : EphemeralNamespace,
) -> EphemeralStore {
  self.stores[ns]
}

///|
pub fn EphemeralHub::encode(
  self : EphemeralHub,
  ns : EphemeralNamespace,
) -> Bytes {
  self.stores[ns].encode_all()
}

///|
pub fn EphemeralHub::encode_all(self : EphemeralHub) -> Bytes {
  let entries : Array[(EphemeralNamespace, Bytes)] = []
  for ns in all_namespaces {
    let data = self.stores[ns].encode_all()
    if data.length() > 0 {
      entries.push((ns, data))
    }
  }
  let buf = @buffer.new()
  write_uvarint(buf, entries.length().to_uint64())
  for entry in entries {
    let (ns, data) = entry
    buf.write_byte(namespace_to_byte(ns))
    write_len_bytes(buf, data)
  }
  buf.to_bytes()
}

///|
pub fn EphemeralHub::apply(
  self : EphemeralHub,
  ns : EphemeralNamespace,
  data : Bytes,
) -> Unit {
  self.stores[ns].apply(data) catch {
    _ => ()
  }
}

///|
pub fn EphemeralHub::apply_all(self : EphemeralHub, data : Bytes) -> Unit {
  if data.length() == 0 {
    return
  }
  let reader = Reader::new(data)
  let count = safe_uvarint_to_int(read_uvarint(reader)) catch { _ => return }
  for _i = 0; _i < count; _i = _i + 1 {
    let ns_byte = reader.read_byte() catch { _ => break }
    let ns_data = read_len_bytes(reader) catch { _ => break }
    // Unknown namespace: skip entry data (reader already advanced past it)
    let ns = match namespace_from_byte(ns_byte) {
      Some(ns) => ns
      None => continue
    }
    self.apply(ns, ns_data)
  }
}

///|
pub fn EphemeralHub::remove_outdated(self : EphemeralHub) -> Unit {
  for ns in all_namespaces {
    self.stores[ns].remove_outdated()
  }
}

///|
pub fn EphemeralHub::on_peer_leave(
  self : EphemeralHub,
  peer_id : String,
) -> Unit {
  let wire_id = to_wire_peer_id(peer_id)
  for ns in all_namespaces {
    self.stores[ns].delete(wire_id) catch {
      _ => ()
    }
  }
}
