///|
fn set_updated_at(
  store : EphemeralStore,
  key : String,
  updated_at : UInt64,
) -> Unit {
  match store.states.get(key) {
    Some(record) =>
      store.states[key] = {
        value: record.value,
        clock: record.clock,
        updated_at,
      }
    None => ()
  }
}

///|
test "uvarint roundtrip" {
  let buf = @buffer.new()
  write_uvarint(buf, 0UL)
  write_uvarint(buf, 1UL)
  write_uvarint(buf, 127UL)
  write_uvarint(buf, 128UL)
  write_uvarint(buf, 300UL)
  write_uvarint(buf, 18446744073709551615UL)
  let reader = Reader::new(buf.to_bytes())
  inspect(read_uvarint(reader), content="0")
  inspect(read_uvarint(reader), content="1")
  inspect(read_uvarint(reader), content="127")
  inspect(read_uvarint(reader), content="128")
  inspect(read_uvarint(reader), content="300")
  inspect(read_uvarint(reader), content="18446744073709551615")
}

///|
test "ivarint roundtrip" {
  let buf = @buffer.new()
  write_ivarint(buf, 0L)
  write_ivarint(buf, 1L)
  write_ivarint(buf, -1L)
  write_ivarint(buf, 9223372036854775807L)
  write_ivarint(buf, -9223372036854775808L)
  let reader = Reader::new(buf.to_bytes())
  inspect(read_ivarint(reader), content="0")
  inspect(read_ivarint(reader), content="1")
  inspect(read_ivarint(reader), content="-1")
  inspect(read_ivarint(reader), content="9223372036854775807")
  inspect(read_ivarint(reader), content="-9223372036854775808")
}

///|
test "string roundtrip" {
  let buf = @buffer.new()
  write_string(buf, "hello")
  write_string(buf, "")
  write_string(buf, "日本語")
  let reader = Reader::new(buf.to_bytes())
  inspect(read_string(reader), content="hello")
  inspect(read_string(reader), content="")
  inspect(read_string(reader), content="日本語")
}

///|
test "LWW: higher clock wins" {
  let store = EphemeralStore::new(60000UL)
  store.set("1", EphemeralValue::I64(10L))
  let buf = @buffer.new()
  write_uvarint(buf, 1UL)
  write_uvarint(buf, 1UL)
  write_ivarint(buf, 5L)
  buf.write_byte(b'\x03')
  write_ivarint(buf, 99L)
  store.apply(buf.to_bytes())
  inspect(store.get("1"), content="Some(I64(99))")
}

///|
test "LWW: lower clock is discarded" {
  let store = EphemeralStore::new(60000UL)
  store.set("1", EphemeralValue::I64(1L))
  store.set("1", EphemeralValue::I64(2L))
  store.set("1", EphemeralValue::I64(3L))
  let buf = @buffer.new()
  write_uvarint(buf, 1UL)
  write_uvarint(buf, 1UL)
  write_ivarint(buf, 2L)
  buf.write_byte(b'\x03')
  write_ivarint(buf, 99L)
  store.apply(buf.to_bytes())
  inspect(store.get("1"), content="Some(I64(3))")
}

///|
test "remove_outdated_at removes expired entries" {
  let store = EphemeralStore::new(1000UL)
  store.set("1", EphemeralValue::I64(42L))
  store.set("2", EphemeralValue::I64(99L))
  set_updated_at(store, "1", 0UL)
  set_updated_at(store, "2", 1500UL)
  store.remove_outdated_at(2000UL)
  inspect(store.get("1"), content="None")
  inspect(store.get("2"), content="Some(I64(99))")
}

///|
test "remove_outdated_at triggers Timeout event" {
  let store = EphemeralStore::new(1000UL)
  store.set("1", EphemeralValue::I64(42L))
  set_updated_at(store, "1", 0UL)
  let events : Array[EphemeralStoreEvent] = []
  let _sub = store.subscribe(fn(event) {
    events.push(event)
    true
  })
  store.remove_outdated_at(5000UL)
  inspect(events.length(), content="1")
  inspect(events[0].by, content="Timeout")
  inspect(events[0].removed, content="[\"1\"]")
  inspect(events[0].added.length(), content="0")
  inspect(events[0].updated.length(), content="0")
}

///|
test "remove_outdated_at skips tombstones in removed list" {
  let store = EphemeralStore::new(1000UL)
  store.set("1", EphemeralValue::I64(42L))
  store.delete("1") // creates tombstone: value=None
  set_updated_at(store, "1", 0UL)
  let events : Array[EphemeralStoreEvent] = []
  let _sub = store.subscribe(fn(event) {
    events.push(event)
    true
  })
  store.remove_outdated_at(5000UL)
  inspect(events.length(), content="0")
  // The tombstone entry should be cleaned up from states
  inspect(store.states.get("1") is None, content="true")
}

///|
test "timeout_ms=0 disables expiry" {
  let store = EphemeralStore::new(0UL)
  store.set("1", EphemeralValue::I64(42L))
  set_updated_at(store, "1", 0UL)
  store.remove_outdated_at(999999999UL)
  inspect(store.get("1"), content="Some(I64(42))")
}

///|
test "remove_outdated_at expires old entries with explicit clock" {
  let store = EphemeralStore::new(1UL)
  store.set("1", EphemeralValue::I64(42L))
  set_updated_at(store, "1", 1UL)
  store.remove_outdated_at(100UL)
  inspect(store.get("1"), content="None")
}

///|
test "encode_entries and apply roundtrip" {
  let store = EphemeralStore::new(1000UL)
  store.set("1", EphemeralValue::I64(42L))
  store.set("2", EphemeralValue::I64(99L))
  set_updated_at(store, "1", 1UL)
  set_updated_at(store, "2", 5000UL)
  // Encode at a time where key "1" is expired but key "2" is not
  // encode_all uses now_ms() internally, so we backdate key "1" far enough
  // that even now_ms()=0 would expire it... but now_ms()=0 means
  // is_expired(1, 0, 1000) => 0 > 1 is false => not expired.
  // Instead, test via apply: encode from a store, apply to another, check keys.
  // Use a store where we control the data directly.
  let bytes = encode_entries([
    ("1", { value: Some(EphemeralValue::I64(42L)), clock: 1L, updated_at: 0UL }),
    ("2", { value: Some(EphemeralValue::I64(99L)), clock: 1L, updated_at: 0UL }),
  ])
  let store2 = EphemeralStore::new(1000UL)
  store2.apply(bytes)
  inspect(store2.get("1"), content="Some(I64(42))")
  inspect(store2.get("2"), content="Some(I64(99))")
}

///|
test "apply with higher clock refreshes record" {
  let store = EphemeralStore::new(60000UL)
  store.set("1", EphemeralValue::I64(10L))
  let old_clock = store.states.get("1").unwrap().clock
  let events : Array[EphemeralStoreEvent] = []
  let _sub = store.subscribe(fn(event) {
    events.push(event)
    true
  })
  // Remote sends same value but higher clock
  let remote = EphemeralStore::new(60000UL)
  remote.set("1", EphemeralValue::I64(10L))
  remote.set("1", EphemeralValue::I64(10L))
  store.apply(remote.encode_all())
  let record = store.states.get("1").unwrap()
  // No updated event since value is identical
  inspect(events.length(), content="0")
  // Clock should be updated to remote's clock (2)
  inspect(record.clock > old_clock, content="true")
}

///|
test "clock increments on each set" {
  let store = EphemeralStore::new(60000UL)
  store.set("1", EphemeralValue::I64(1L))
  let clock1 = store.states.get("1").unwrap().clock
  store.set("1", EphemeralValue::I64(2L))
  let clock2 = store.states.get("1").unwrap().clock
  store.set("1", EphemeralValue::I64(3L))
  let clock3 = store.states.get("1").unwrap().clock
  inspect(clock1, content="1")
  inspect(clock2, content="2")
  inspect(clock3, content="3")
}
