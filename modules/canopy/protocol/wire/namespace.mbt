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
