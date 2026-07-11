///|
test "set and get" {
  let store = @ephemeral.EphemeralStore::new(60000UL)
  store.set("1", @ephemeral.EphemeralValue::I64(42L))
  @debug.debug_inspect(store.get("1"), content="Some(I64(42))")
  @debug.debug_inspect(store.get("2"), content="None")
}

///|
test "delete removes value" {
  let store = @ephemeral.EphemeralStore::new(60000UL)
  store.set("1", @ephemeral.EphemeralValue::I64(42L))
  store.delete("1")
  @debug.debug_inspect(store.get("1"), content="None")
}

///|
test "get_all_states excludes deleted" {
  let store = @ephemeral.EphemeralStore::new(60000UL)
  store.set("1", @ephemeral.EphemeralValue::I64(1L))
  store.set("2", @ephemeral.EphemeralValue::I64(2L))
  store.delete("1")
  let states = store.get_all_states()
  inspect(states.length(), content="1")
  @debug.debug_inspect(states.get("2"), content="Some(I64(2))")
}

///|
test "keys returns only non-deleted" {
  let store = @ephemeral.EphemeralStore::new(60000UL)
  store.set("1", @ephemeral.EphemeralValue::I64(1L))
  store.set("2", @ephemeral.EphemeralValue::I64(2L))
  store.delete("1")
  @debug.debug_inspect(store.keys(), content="[\"2\"]")
}

///|
test "set Null acts as delete" {
  let store = @ephemeral.EphemeralStore::new(60000UL)
  store.set("1", @ephemeral.EphemeralValue::I64(42L))
  store.set("1", @ephemeral.EphemeralValue::Null)
  @debug.debug_inspect(store.get("1"), content="None")
}

///|
test "subscribe receives Local events" {
  let store = @ephemeral.EphemeralStore::new(60000UL)
  let events : Array[@ephemeral.EphemeralStoreEvent] = []
  let _sub = store.subscribe(fn(event) {
    events.push(event)
    true
  })
  store.set("1", @ephemeral.EphemeralValue::I64(42L))
  inspect(events.length(), content="1")
  inspect(events[0].by(), content="Local")
  @debug.debug_inspect(events[0].added(), content="[\"1\"]")
}

///|
test "subscribe auto-unsubscribe on false" {
  let store = @ephemeral.EphemeralStore::new(60000UL)
  let call_count : Ref[Int] = Ref(0)
  let _sub = store.subscribe(fn(_event) {
    call_count.val = call_count.val + 1
    false
  })
  store.set("1", @ephemeral.EphemeralValue::I64(1L))
  store.set("2", @ephemeral.EphemeralValue::I64(2L))
  inspect(call_count.val, content="1")
}

///|
test "unsubscribe stops events" {
  let store = @ephemeral.EphemeralStore::new(60000UL)
  let call_count : Ref[Int] = Ref(0)
  let sub = store.subscribe(fn(_event) {
    call_count.val = call_count.val + 1
    true
  })
  store.set("1", @ephemeral.EphemeralValue::I64(1L))
  sub.unsubscribe()
  store.set("2", @ephemeral.EphemeralValue::I64(2L))
  inspect(call_count.val, content="1")
}

///|
test "encode/decode roundtrip single entry" {
  let store = @ephemeral.EphemeralStore::new(60000UL)
  store.set(
    "123",
    @ephemeral.EphemeralValue::Map({
      "cursor": @ephemeral.EphemeralValue::I64(42L),
      "name": @ephemeral.EphemeralValue::String("Alice"),
    }),
  )
  let bytes = store.encode("123")
  let store2 = @ephemeral.EphemeralStore::new(60000UL)
  store2.apply(bytes)
  inspect(store2.get("123") != None, content="true")
}

///|
test "encode/decode roundtrip all value types" {
  let store = @ephemeral.EphemeralStore::new(60000UL)
  store.set("1", @ephemeral.EphemeralValue::Bool(true))
  store.set("2", @ephemeral.EphemeralValue::I64(-999L))
  store.set("3", @ephemeral.EphemeralValue::F64(3.14))
  store.set("4", @ephemeral.EphemeralValue::String("hello"))
  store.set(
    "5",
    @ephemeral.EphemeralValue::List([
      @ephemeral.EphemeralValue::I64(1L),
      @ephemeral.EphemeralValue::I64(2L),
    ]),
  )
  store.set("6", @ephemeral.EphemeralValue::Bytes(b"\x01\x02\x03"))
  let bytes = store.encode_all()
  let store2 = @ephemeral.EphemeralStore::new(60000UL)
  store2.apply(bytes)
  @debug.debug_inspect(store2.get("1"), content="Some(Bool(true))")
  @debug.debug_inspect(store2.get("2"), content="Some(I64(-999))")
  @debug.debug_inspect(store2.get("3"), content="Some(F64(3.14))")
  @debug.debug_inspect(store2.get("4"), content="Some(String(\"hello\"))")
  @debug.debug_inspect(store2.get("5"), content="Some(List([I64(1), I64(2)]))")
  @debug.debug_inspect(
    store2.get("6"),
    content=(
      #|Some(Bytes(<Bytes: [0x01, 0x02, 0x03]>))
    ),
  )
  inspect(store2.keys().length(), content="6")
}

///|
test "apply triggers Import event" {
  let store = @ephemeral.EphemeralStore::new(60000UL)
  let events : Array[@ephemeral.EphemeralStoreEvent] = []
  let _sub = store.subscribe(fn(event) {
    events.push(event)
    true
  })
  let remote = @ephemeral.EphemeralStore::new(60000UL)
  remote.set("1", @ephemeral.EphemeralValue::I64(42L))
  let bytes = remote.encode_all()
  store.apply(bytes)
  inspect(events.length(), content="1")
  inspect(events[0].by(), content="Import")
  @debug.debug_inspect(events[0].added(), content="[\"1\"]")
}

///|
test "non-numeric keys raise error on set" {
  let store = @ephemeral.EphemeralStore::new(60000UL)
  let mut caught = false
  store.set("alice", @ephemeral.EphemeralValue::I64(42L)) catch {
    _ => caught = true
  }
  inspect(caught, content="true")
}

///|
test "non-numeric keys raise error on delete" {
  let store = @ephemeral.EphemeralStore::new(60000UL)
  let mut caught = false
  store.delete("bob") catch {
    _ => caught = true
  }
  inspect(caught, content="true")
}

///|
test "peer IDs must be canonical decimal strings" {
  let store = @ephemeral.EphemeralStore::new(60000UL)
  let rejected : Array[Bool] = []
  for key in ["01", "0x10", "1_2"] {
    let mut caught = false
    store.set(key, @ephemeral.EphemeralValue::I64(42L)) catch {
      _ => caught = true
    }
    rejected.push(caught)
  }
  store.set("0", @ephemeral.EphemeralValue::I64(7L))
  @debug.debug_inspect(rejected, content="[true, true, true]")
  @debug.debug_inspect(store.get("0"), content="Some(I64(7))")
}

///|
test "subscribe_local_updates receives bytes and can apply to another store" {
  let store = @ephemeral.EphemeralStore::new(60000UL)
  let received_bytes : Ref[Bytes] = Ref(Bytes::new(0))
  let _sub = store.subscribe_local_updates(fn(bytes) {
    received_bytes.val = bytes
    true
  })
  store.set("123", @ephemeral.EphemeralValue::I64(42L))
  // Verify callback received non-empty bytes
  inspect(received_bytes.val.length() > 0, content="true")
  // Verify the bytes can be applied to another store
  let store2 = @ephemeral.EphemeralStore::new(60000UL)
  store2.apply(received_bytes.val)
  @debug.debug_inspect(store2.get("123"), content="Some(I64(42))")
}

///|
test "set triggers updated event on existing key" {
  let store = @ephemeral.EphemeralStore::new(60000UL)
  let events : Array[@ephemeral.EphemeralStoreEvent] = []
  let _sub = store.subscribe(fn(event) {
    events.push(event)
    true
  })
  store.set("1", @ephemeral.EphemeralValue::I64(10L))
  store.set("1", @ephemeral.EphemeralValue::I64(20L))
  inspect(events.length(), content="2")
  // First set should be "added"
  @debug.debug_inspect(events[0].added(), content="[\"1\"]")
  @debug.debug_inspect(events[0].updated(), content="[]")
  // Second set should be "updated"
  @debug.debug_inspect(events[1].added(), content="[]")
  @debug.debug_inspect(events[1].updated(), content="[\"1\"]")
}

///|
test "apply triggers updated event on existing key" {
  let store = @ephemeral.EphemeralStore::new(60000UL)
  // Set initial value
  store.set("1", @ephemeral.EphemeralValue::I64(10L))
  let events : Array[@ephemeral.EphemeralStoreEvent] = []
  let _sub = store.subscribe(fn(event) {
    events.push(event)
    true
  })
  // Apply remote update with higher clock
  let remote = @ephemeral.EphemeralStore::new(60000UL)
  remote.set("1", @ephemeral.EphemeralValue::I64(10L))
  remote.set("1", @ephemeral.EphemeralValue::I64(20L))
  let bytes = remote.encode_all()
  store.apply(bytes)
  inspect(events.length(), content="1")
  inspect(events[0].by(), content="Import")
  @debug.debug_inspect(events[0].updated(), content="[\"1\"]")
  @debug.debug_inspect(events[0].added(), content="[]")
}

///|
test "apply heartbeat with unchanged value refreshes state without updated event" {
  let store = @ephemeral.EphemeralStore::new(60000UL)
  store.set(
    "1",
    @ephemeral.EphemeralValue::Map({
      "cursor": @ephemeral.EphemeralValue::I64(10L),
      "name": @ephemeral.EphemeralValue::String("Alice"),
      "color": @ephemeral.EphemeralValue::String("#ff0000"),
    }),
  )
  let events : Array[@ephemeral.EphemeralStoreEvent] = []
  let _sub = store.subscribe(fn(event) {
    events.push(event)
    true
  })
  let remote = @ephemeral.EphemeralStore::new(60000UL)
  remote.set(
    "1",
    @ephemeral.EphemeralValue::Map({
      "cursor": @ephemeral.EphemeralValue::I64(10L),
      "name": @ephemeral.EphemeralValue::String("Alice"),
      "color": @ephemeral.EphemeralValue::String("#ff0000"),
    }),
  )
  remote.set(
    "1",
    @ephemeral.EphemeralValue::Map({
      "cursor": @ephemeral.EphemeralValue::I64(10L),
      "name": @ephemeral.EphemeralValue::String("Alice"),
      "color": @ephemeral.EphemeralValue::String("#ff0000"),
    }),
  )
  store.apply(remote.encode_all())
  inspect(events.length(), content="0")
  inspect(store.get("1") != None, content="true")
}
