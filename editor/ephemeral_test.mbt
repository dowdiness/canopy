///|
test "set and get" {
  let store = @editor.EphemeralStore::new(60000UL)
  store.set("1", @editor.EphemeralValue::I64(42L))
  inspect(store.get("1"), content="Some(I64(42))")
  inspect(store.get("2"), content="None")
}

///|
test "delete removes value" {
  let store = @editor.EphemeralStore::new(60000UL)
  store.set("1", @editor.EphemeralValue::I64(42L))
  store.delete("1")
  inspect(store.get("1"), content="None")
}

///|
test "get_all_states excludes deleted" {
  let store = @editor.EphemeralStore::new(60000UL)
  store.set("1", @editor.EphemeralValue::I64(1L))
  store.set("2", @editor.EphemeralValue::I64(2L))
  store.delete("1")
  let states = store.get_all_states()
  inspect(states.length(), content="1")
  inspect(states.get("2"), content="Some(I64(2))")
}

///|
test "keys returns only non-deleted" {
  let store = @editor.EphemeralStore::new(60000UL)
  store.set("1", @editor.EphemeralValue::I64(1L))
  store.set("2", @editor.EphemeralValue::I64(2L))
  store.delete("1")
  inspect(store.keys(), content="[\"2\"]")
}

///|
test "set Null acts as delete" {
  let store = @editor.EphemeralStore::new(60000UL)
  store.set("1", @editor.EphemeralValue::I64(42L))
  store.set("1", @editor.EphemeralValue::Null)
  inspect(store.get("1"), content="None")
}

///|
test "subscribe receives Local events" {
  let store = @editor.EphemeralStore::new(60000UL)
  let events : Array[@editor.EphemeralStoreEvent] = []
  let _sub = store.subscribe(fn(event) {
    events.push(event)
    true
  })
  store.set("1", @editor.EphemeralValue::I64(42L))
  inspect(events.length(), content="1")
  inspect(events[0].by(), content="Local")
  inspect(events[0].added(), content="[\"1\"]")
}

///|
test "subscribe auto-unsubscribe on false" {
  let store = @editor.EphemeralStore::new(60000UL)
  let call_count : Ref[Int] = Ref::new(0)
  let _sub = store.subscribe(fn(_event) {
    call_count.val = call_count.val + 1
    false
  })
  store.set("1", @editor.EphemeralValue::I64(1L))
  store.set("2", @editor.EphemeralValue::I64(2L))
  inspect(call_count.val, content="1")
}

///|
test "unsubscribe stops events" {
  let store = @editor.EphemeralStore::new(60000UL)
  let call_count : Ref[Int] = Ref::new(0)
  let sub = store.subscribe(fn(_event) {
    call_count.val = call_count.val + 1
    true
  })
  store.set("1", @editor.EphemeralValue::I64(1L))
  sub.unsubscribe()
  store.set("2", @editor.EphemeralValue::I64(2L))
  inspect(call_count.val, content="1")
}

///|
test "encode/decode roundtrip single entry" {
  let store = @editor.EphemeralStore::new(60000UL)
  store.set(
    "123",
    @editor.EphemeralValue::Map({
      "cursor": @editor.EphemeralValue::I64(42L),
      "name": @editor.EphemeralValue::String("Alice"),
    }),
  )
  let bytes = store.encode("123")
  let store2 = @editor.EphemeralStore::new(60000UL)
  store2.apply(bytes)
  inspect(store2.get("123") != None, content="true")
}

///|
test "encode/decode roundtrip all value types" {
  let store = @editor.EphemeralStore::new(60000UL)
  store.set("1", @editor.EphemeralValue::Bool(true))
  store.set("2", @editor.EphemeralValue::I64(-999L))
  store.set("3", @editor.EphemeralValue::F64(3.14))
  store.set("4", @editor.EphemeralValue::String("hello"))
  store.set(
    "5",
    @editor.EphemeralValue::List([
      @editor.EphemeralValue::I64(1L),
      @editor.EphemeralValue::I64(2L),
    ]),
  )
  store.set("6", @editor.EphemeralValue::Bytes(b"\x01\x02\x03"))
  let bytes = store.encode_all()
  let store2 = @editor.EphemeralStore::new(60000UL)
  store2.apply(bytes)
  inspect(store2.get("1"), content="Some(Bool(true))")
  inspect(store2.get("2"), content="Some(I64(-999))")
  inspect(store2.get("3"), content="Some(F64(3.14))")
  inspect(store2.get("4"), content="Some(String(\"hello\"))")
  inspect(store2.get("5"), content="Some(List([I64(1), I64(2)]))")
  inspect(store2.get("6"), content="Some(Bytes(b\"\\x01\\x02\\x03\"))")
  inspect(store2.keys().length(), content="6")
}

///|
test "apply triggers Import event" {
  let store = @editor.EphemeralStore::new(60000UL)
  let events : Array[@editor.EphemeralStoreEvent] = []
  let _sub = store.subscribe(fn(event) {
    events.push(event)
    true
  })
  let remote = @editor.EphemeralStore::new(60000UL)
  remote.set("1", @editor.EphemeralValue::I64(42L))
  let bytes = remote.encode_all()
  store.apply(bytes)
  inspect(events.length(), content="1")
  inspect(events[0].by(), content="Import")
  inspect(events[0].added(), content="[\"1\"]")
}

///|
test "non-numeric keys raise error on set" {
  let store = @editor.EphemeralStore::new(60000UL)
  let mut caught = false
  store.set("alice", @editor.EphemeralValue::I64(42L)) catch {
    _ => caught = true
  }
  inspect(caught, content="true")
}

///|
test "non-numeric keys raise error on delete" {
  let store = @editor.EphemeralStore::new(60000UL)
  let mut caught = false
  store.delete("bob") catch {
    _ => caught = true
  }
  inspect(caught, content="true")
}

///|
test "peer IDs must be canonical decimal strings" {
  let store = @editor.EphemeralStore::new(60000UL)
  let rejected : Array[Bool] = []
  for key in ["01", "0x10", "1_2"] {
    let mut caught = false
    store.set(key, @editor.EphemeralValue::I64(42L)) catch {
      _ => caught = true
    }
    rejected.push(caught)
  }
  store.set("0", @editor.EphemeralValue::I64(7L))
  inspect(rejected, content="[true, true, true]")
  inspect(store.get("0"), content="Some(I64(7))")
}

///|
test "subscribe_local_updates receives bytes and can apply to another store" {
  let store = @editor.EphemeralStore::new(60000UL)
  let received_bytes : Ref[Bytes] = Ref::new(Bytes::new(0))
  let _sub = store.subscribe_local_updates(fn(bytes) {
    received_bytes.val = bytes
    true
  })
  store.set("123", @editor.EphemeralValue::I64(42L))
  // Verify callback received non-empty bytes
  inspect(received_bytes.val.length() > 0, content="true")
  // Verify the bytes can be applied to another store
  let store2 = @editor.EphemeralStore::new(60000UL)
  store2.apply(received_bytes.val)
  inspect(store2.get("123"), content="Some(I64(42))")
}

///|
test "set triggers updated event on existing key" {
  let store = @editor.EphemeralStore::new(60000UL)
  let events : Array[@editor.EphemeralStoreEvent] = []
  let _sub = store.subscribe(fn(event) {
    events.push(event)
    true
  })
  store.set("1", @editor.EphemeralValue::I64(10L))
  store.set("1", @editor.EphemeralValue::I64(20L))
  inspect(events.length(), content="2")
  // First set should be "added"
  inspect(events[0].added(), content="[\"1\"]")
  inspect(events[0].updated(), content="[]")
  // Second set should be "updated"
  inspect(events[1].added(), content="[]")
  inspect(events[1].updated(), content="[\"1\"]")
}

///|
test "apply triggers updated event on existing key" {
  let store = @editor.EphemeralStore::new(60000UL)
  // Set initial value
  store.set("1", @editor.EphemeralValue::I64(10L))
  let events : Array[@editor.EphemeralStoreEvent] = []
  let _sub = store.subscribe(fn(event) {
    events.push(event)
    true
  })
  // Apply remote update with higher clock
  let remote = @editor.EphemeralStore::new(60000UL)
  remote.set("1", @editor.EphemeralValue::I64(10L))
  remote.set("1", @editor.EphemeralValue::I64(20L))
  let bytes = remote.encode_all()
  store.apply(bytes)
  inspect(events.length(), content="1")
  inspect(events[0].by(), content="Import")
  inspect(events[0].updated(), content="[\"1\"]")
  inspect(events[0].added(), content="[]")
}

///|
test "apply heartbeat with unchanged value refreshes state without updated event" {
  let store = @editor.EphemeralStore::new(60000UL)
  store.set(
    "1",
    @editor.EphemeralValue::Map({
      "cursor": @editor.EphemeralValue::I64(10L),
      "name": @editor.EphemeralValue::String("Alice"),
      "color": @editor.EphemeralValue::String("#ff0000"),
    }),
  )
  let events : Array[@editor.EphemeralStoreEvent] = []
  let _sub = store.subscribe(fn(event) {
    events.push(event)
    true
  })
  let remote = @editor.EphemeralStore::new(60000UL)
  remote.set(
    "1",
    @editor.EphemeralValue::Map({
      "cursor": @editor.EphemeralValue::I64(10L),
      "name": @editor.EphemeralValue::String("Alice"),
      "color": @editor.EphemeralValue::String("#ff0000"),
    }),
  )
  remote.set(
    "1",
    @editor.EphemeralValue::Map({
      "cursor": @editor.EphemeralValue::I64(10L),
      "name": @editor.EphemeralValue::String("Alice"),
      "color": @editor.EphemeralValue::String("#ff0000"),
    }),
  )
  store.apply(remote.encode_all())
  inspect(events.length(), content="0")
  inspect(store.get("1") != None, content="true")
}
