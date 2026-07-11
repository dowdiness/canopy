///| Frozen wire-format fixtures for the presence-specific encoders.
///
/// These pin the EXACT byte output of `write_ephemeral_value` and
/// `encode_entries` so the on-the-wire presence format cannot change silently
/// (it is transmitted and persisted by CRDT sync). The `content=` snapshots
/// are frozen literals; the test compares freshly-encoded bytes against them
/// and never re-derives the reference by calling the code under refactor. The
/// generic primitive layouts (varint, string, f64, …) are pinned by the
/// fixtures in `lib/byte-codec`.

///|
test "wire fixture: ephemeral_value byte layout" {
  let inner_map : Map[String, EphemeralValue] = { "n": EphemeralValue::I64(7L) }
  let value = EphemeralValue::List([
    EphemeralValue::Null,
    EphemeralValue::Bool(true),
    EphemeralValue::String("ab"),
    EphemeralValue::Map(inner_map),
  ])
  let buf = Buffer()
  write_ephemeral_value(buf, value)
  inspect(
    buf.to_bytes(),
    content=(
      #|b"\x05\x04\x00\x01\x01\x04\x04a\x00b\x00\x06\x01\x02n\x00\x03\x0e"
    ),
  )
}

///|
test "wire fixture: encode_entries byte layout" {
  let entries : Array[(String, EphemeralRecord)] = [
    ("1", { value: Some(EphemeralValue::I64(42L)), clock: 3L, updated_at: 0UL }),
  ]
  inspect(
    encode_entries(entries),
    content=(
      #|b"\x01\x01\x06\x03T"
    ),
  )
}
