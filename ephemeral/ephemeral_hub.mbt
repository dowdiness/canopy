///|
pub(all) enum EphemeralNamespace {
  Cursor
  EditMode
  Drag
  Presence
} derive(Debug, Eq, Compare, Hash)

///|
pub impl Show for EphemeralNamespace with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

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
pub fn namespace_to_byte(ns : EphemeralNamespace) -> Byte {
  match ns {
    Cursor => b'\x01'
    EditMode => b'\x02'
    Drag => b'\x03'
    Presence => b'\x04'
  }
}

///|
pub fn namespace_from_byte(b : Byte) -> EphemeralNamespace? {
  match b {
    b'\x01' => Some(Cursor)
    b'\x02' => Some(EditMode)
    b'\x03' => Some(Drag)
    b'\x04' => Some(Presence)
    _ => None
  }
}

///|
pub fn all_namespaces() -> Array[EphemeralNamespace] {
  [Cursor, EditMode, Drag, Presence]
}

///|
pub struct EphemeralHub {
  local_peer_id : String
  wire_peer_id : String
  stores : Map[EphemeralNamespace, EphemeralStore]
}

///|
pub fn EphemeralHub::new(local_peer_id : String) -> EphemeralHub {
  let stores : Map[EphemeralNamespace, EphemeralStore] = {}
  for ns in all_namespaces() {
    stores[ns] = EphemeralStore::new(default_timeout(ns))
  }
  let wire_peer_id = to_wire_peer_id(local_peer_id)
  { local_peer_id, wire_peer_id, stores }
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
  for ns in all_namespaces() {
    let data = self.stores[ns].encode_all()
    if data.length() > 0 {
      entries.push((ns, data))
    }
  }
  let buf = Buffer()
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
  for _ in 0..<count {
    let ns_byte = reader.read_byte() catch { _ => break }
    let ns_data = read_len_bytes(reader) catch { _ => break }
    // Unknown namespace: skip entry data (reader already advanced past it)
    guard namespace_from_byte(ns_byte) is Some(ns) else { continue }
    self.apply(ns, ns_data)
  }
}

///|
pub fn EphemeralHub::remove_outdated(self : EphemeralHub) -> Unit {
  for ns in all_namespaces() {
    self.stores[ns].remove_outdated()
  }
}

///|
pub fn EphemeralHub::on_peer_leave(
  self : EphemeralHub,
  peer_id : String,
) -> Unit {
  let wire_id = to_wire_peer_id(peer_id)
  for ns in all_namespaces() {
    self.stores[ns].delete(wire_id) catch {
      _ => ()
    }
  }
}
