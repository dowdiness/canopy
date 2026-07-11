# EphemeralStore Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a generic key-value ephemeral store for peer presence (cursors, selections, names) following the design in `docs/design/04-ephemeral-store.md`.

**Architecture:** Port Lomo's `awareness.mbt` LWW state machine and subscription plumbing, replacing `@types.LoroValue` with a self-contained `EphemeralValue` enum. Vendor ~100 lines of varint/length-prefixed binary encoding into the editor package (event-graph-walker has no encoding primitives). Add a cursor awareness derived view (`PeerCursorView`) on top of the store.

**Tech Stack:** MoonBit, `@buffer.T` for encoding, `extern "js"` for `now_ms()` FFI

**Reference:** Lomo source at https://github.com/Lampese/lomo/blob/main/awareness.mbt

---

## File Structure

| File | Responsibility |
|------|----------------|
| `editor/ephemeral.mbt` | `EphemeralValue`, `EphemeralRecord`, `EphemeralStore`, event types, subscriptions, LWW state machine |
| `editor/ephemeral_encoding.mbt` | Varint codec (`Reader`, `write_uvarint`, etc.), binary encode/decode for `EphemeralValue` entries |
| `editor/ephemeral_wbtest.mbt` | Whitebox tests (timeout via record backdating, internal state inspection) |
| `editor/ephemeral_test.mbt` | Blackbox tests (LWW, encode/decode roundtrip, events, subscriptions) |
| `editor/cursor_view.mbt` | `PeerCursorView`, `PeerCursor`, `adjust_position` — derived cursor layer |
| `editor/cursor_view_test.mbt` | Blackbox tests for cursor adjustment and derived view |

No changes to `editor/moon.pkg` — no new dependencies needed. `@buffer` is in MoonBit core.

---

## Task 1: Binary Encoding Utilities

**Files:**
- Create: `editor/ephemeral_encoding.mbt`
- Create: `editor/ephemeral_test.mbt`

### Step 1.1: Write the `Reader` type and varint codec

The encoding layer needs: uvarint (unsigned LEB128), ivarint (zigzag signed), length-prefixed strings/bytes, and a `Reader` cursor. These are internal to the editor package.

- [ ] **Write `editor/ephemeral_encoding.mbt`** with:

```moonbit
///|
priv struct Reader {
  data : Bytes
  mut pos : Int
}

///|
fn Reader::new(data : Bytes) -> Reader {
  { data, pos: 0 }
}

///|
fn Reader::read_byte(self : Reader) -> Byte!String {
  if self.pos >= self.data.length() {
    raise "unexpected end of input"
  }
  let b = self.data[self.pos]
  self.pos += 1
  b
}

///|
fn Reader::read_bytes(self : Reader, n : Int) -> Bytes!String {
  if self.pos + n > self.data.length() {
    raise "unexpected end of input"
  }
  let out = Bytes::new(n)
  out.blit(0, self.data, self.pos, n)
  self.pos += n
  out
}

///|
fn write_uvarint(buf : @buffer.T, value : UInt64) -> Unit {
  let mut v = value
  while v >= 0x80UL {
    buf.write_byte((v.to_byte().to_int().lor(0x80)).to_byte())
    v = v.lsr(7)
  }
  buf.write_byte(v.to_byte())
}

///|
fn read_uvarint(reader : Reader) -> UInt64!String {
  let mut result : UInt64 = 0
  let mut shift = 0
  for i = 0; i < 10; i = i + 1 {
    let b = reader.read_byte!()
    result = result.lor((b.to_int().land(0x7F)).to_uint64().lsl(shift))
    if b.to_int().land(0x80) == 0 {
      return result
    }
    shift += 7
  }
  raise "varint too long"
}

///|
fn write_ivarint(buf : @buffer.T, value : Int64) -> Unit {
  // zigzag encoding: (value << 1) ^ (value >> 63)
  let zigzag = (value.lsl(1)).lxor(value.asr(63)).to_uint64()
  write_uvarint(buf, zigzag)
}

///|
fn read_ivarint(reader : Reader) -> Int64!String {
  let zigzag = read_uvarint!(reader)
  // zigzag decoding: (zigzag >>> 1) ^ -(zigzag & 1)
  let signed = zigzag.lsr(1).to_int64().lxor(-(zigzag.land(1UL).to_int64()))
  signed
}

///|
fn write_string(buf : @buffer.T, s : String) -> Unit {
  let bytes = s.to_bytes()
  write_uvarint(buf, bytes.length().to_uint64())
  buf.write_bytes(bytes)
}

///|
fn read_string(reader : Reader) -> String!String {
  let len = read_uvarint!(reader).to_int()
  let bytes = reader.read_bytes!(len)
  bytes.to_unchecked_string()
}

///|
fn write_len_bytes(buf : @buffer.T, b : Bytes) -> Unit {
  write_uvarint(buf, b.length().to_uint64())
  buf.write_bytes(b)
}

///|
fn read_len_bytes(reader : Reader) -> Bytes!String {
  let len = read_uvarint!(reader).to_int()
  reader.read_bytes!(len)
}
```

- [ ] **Write initial test in `editor/ephemeral_test.mbt`:**

```moonbit
///|
test "uvarint roundtrip" {
  let buf = @buffer.new()
  write_uvarint(buf, 0UL)
  write_uvarint(buf, 1UL)
  write_uvarint(buf, 127UL)
  write_uvarint(buf, 128UL)
  write_uvarint(buf, 300UL)
  write_uvarint(buf, 18446744073709551615UL) // UInt64 max
  let reader = Reader::new(buf.to_bytes())
  inspect!(read_uvarint!(reader), content="0")
  inspect!(read_uvarint!(reader), content="1")
  inspect!(read_uvarint!(reader), content="127")
  inspect!(read_uvarint!(reader), content="128")
  inspect!(read_uvarint!(reader), content="300")
  inspect!(read_uvarint!(reader), content="18446744073709551615")
}

///|
test "ivarint roundtrip" {
  let buf = @buffer.new()
  write_ivarint(buf, 0L)
  write_ivarint(buf, 1L)
  write_ivarint(buf, -1L)
  write_ivarint(buf, 9223372036854775807L) // Int64 max
  write_ivarint(buf, -9223372036854775808L) // Int64 min
  let reader = Reader::new(buf.to_bytes())
  inspect!(read_ivarint!(reader), content="0")
  inspect!(read_ivarint!(reader), content="1")
  inspect!(read_ivarint!(reader), content="-1")
  inspect!(read_ivarint!(reader), content="9223372036854775807")
  inspect!(read_ivarint!(reader), content="-9223372036854775808")
}

///|
test "string roundtrip" {
  let buf = @buffer.new()
  write_string(buf, "hello")
  write_string(buf, "")
  write_string(buf, "日本語")
  let reader = Reader::new(buf.to_bytes())
  inspect!(read_string!(reader), content="hello")
  inspect!(read_string!(reader), content="")
  inspect!(read_string!(reader), content="日本語")
}
```

- [ ] **Run tests:** `moon test -p dowdiness/canopy/editor -f ephemeral_test.mbt`
- [ ] **Commit:** `feat(editor): add binary encoding utilities for ephemeral store`

---

## Task 2: EphemeralValue and Data Model

**Files:**
- Create: `editor/ephemeral.mbt`
- Modify: `editor/ephemeral_test.mbt`

### Step 2.1: Define the data model

- [ ] **Write `editor/ephemeral.mbt`** with types and the `now_ms` FFI:

```moonbit
///|
pub enum EphemeralValue {
  Null
  Bool(Bool)
  I64(Int64)
  F64(Double)
  String(String)
  Bytes(Bytes)
  List(Array[EphemeralValue])
  Map(Map[String, EphemeralValue])
} derive(Show, Eq)

///|
pub enum EphemeralEventTrigger {
  Local
  Import
  Timeout
} derive(Show, Eq)

///|
pub struct EphemeralStoreEvent {
  by : EphemeralEventTrigger
  added : Array[String]
  updated : Array[String]
  removed : Array[String]
} derive(Show)

///|
pub fn EphemeralStoreEvent::by(self : EphemeralStoreEvent) -> EphemeralEventTrigger {
  self.by
}

///|
pub fn EphemeralStoreEvent::added(self : EphemeralStoreEvent) -> Array[String] {
  self.added
}

///|
pub fn EphemeralStoreEvent::updated(self : EphemeralStoreEvent) -> Array[String] {
  self.updated
}

///|
pub fn EphemeralStoreEvent::removed(self : EphemeralStoreEvent) -> Array[String] {
  self.removed
}

///|
pub type LocalEphemeralCallback (Bytes) -> Bool

///|
pub type EphemeralSubscriber (EphemeralStoreEvent) -> Bool

///|
struct EphemeralRecord {
  value : EphemeralValue?
  clock : Int64
  updated_at : UInt64
}

///|
struct EphemeralLocalEntry {
  id : Int
  callback : LocalEphemeralCallback
}

///|
struct EphemeralSubscriberEntry {
  id : Int
  callback : EphemeralSubscriber
}

///|
pub struct EphemeralSubscription {
  store : EphemeralStore
  id : Int
}

///|
pub struct EphemeralStore {
  timeout_ms : UInt64
  mut next_sub_id : Int
  mut states : Map[String, EphemeralRecord]
  mut local_subs : Array[EphemeralLocalEntry]
  mut subs : Array[EphemeralSubscriberEntry]
}

///|
/// Wall-clock milliseconds. JS target uses performance.now() or Date.now().
/// Non-JS targets return 0 (tests use whitebox backdating for timeout tests).
fn now_ms() -> UInt64 {
  0UL
}
```

Note: The `now_ms()` FFI needs a JS-target variant. Create `editor/ephemeral_js.mbt` with:

```moonbit
///| target: js
extern "js" fn now_ms_js() -> Int =
  #|() => Date.now()
```

However, MoonBit's per-file conditional compilation may require a different approach. If the `///| target: js` annotation works, override `now_ms` to call `now_ms_js().to_uint64()`. If not, use a simple `0UL` default and set `updated_at` to `now_ms()` — tests work via whitebox backdating regardless. **Resolve this at implementation time by testing what compiles.**

- [ ] **Run:** `moon check` to verify the types compile
- [ ] **Commit:** `feat(editor): add EphemeralStore data model`

---

## Task 3: Core Store Operations

**Files:**
- Modify: `editor/ephemeral.mbt`
- Modify: `editor/ephemeral_test.mbt`

### Step 3.1: Constructor, get/set/delete, subscriptions

- [ ] **Add to `editor/ephemeral.mbt`:**

```moonbit
///|
pub fn EphemeralStore::new(timeout_ms : UInt64) -> EphemeralStore {
  {
    timeout_ms,
    next_sub_id: 1,
    states: Map::new(),
    local_subs: [],
    subs: [],
  }
}

///|
pub fn EphemeralStore::get(self : EphemeralStore, key : String) -> EphemeralValue? {
  match self.states.get(key) {
    Some(record) => record.value
    None => None
  }
}

///|
pub fn EphemeralStore::get_all_states(self : EphemeralStore) -> Map[String, EphemeralValue] {
  let out : Map[String, EphemeralValue] = {}
  for key, record in self.states {
    match record.value {
      Some(value) => out[key] = value
      None => ()
    }
  }
  out
}

///|
pub fn EphemeralStore::keys(self : EphemeralStore) -> Array[String] {
  let out : Array[String] = []
  for key, record in self.states {
    match record.value {
      Some(_) => out.push(key)
      None => ()
    }
  }
  out
}

///|
pub fn EphemeralStore::set(self : EphemeralStore, key : String, value : EphemeralValue) -> Unit {
  match value {
    EphemeralValue::Null => self.set_state(key, None)
    _ => self.set_state(key, Some(value))
  }
}

///|
pub fn EphemeralStore::delete(self : EphemeralStore, key : String) -> Unit {
  self.set_state(key, None)
}

///|
fn EphemeralStore::set_state(self : EphemeralStore, key : String, value : EphemeralValue?) -> Unit {
  let now = now_ms()
  let old = self.states.get(key)
  let next_clock = match old {
    Some(record) => record.clock + 1L
    None => 1L
  }
  let record = { value, clock: next_clock, updated_at: now }
  self.states[key] = record
  // Notify local subscribers with encoded bytes
  self.local_subs = filter_local_subs(self.local_subs, self.encode(key))
  // Build event
  let added : Array[String] = []
  let updated : Array[String] = []
  let removed : Array[String] = []
  match (old, value) {
    (Some(old_record), Some(_)) =>
      match old_record.value {
        Some(_) => updated.push(key)
        None => added.push(key)
      }
    (None, Some(_)) => added.push(key)
    (Some(old_record), None) =>
      match old_record.value {
        Some(_) => removed.push(key)
        None => ()
      }
    (None, None) => ()
  }
  if added.length() > 0 || updated.length() > 0 || removed.length() > 0 {
    let event = { by: EphemeralEventTrigger::Local, added, updated, removed }
    self.subs = filter_ephemeral_subs(self.subs, event)
  }
}

///|
pub fn EphemeralSubscription::unsubscribe(self : EphemeralSubscription) -> Unit {
  self.store.unsubscribe(self.id)
}

///|
pub fn EphemeralStore::subscribe_local_updates(
  self : EphemeralStore,
  callback : LocalEphemeralCallback,
) -> EphemeralSubscription {
  let id = self.alloc_sub_id()
  self.local_subs.push({ id, callback })
  { store: self, id }
}

///|
pub fn EphemeralStore::subscribe(
  self : EphemeralStore,
  callback : EphemeralSubscriber,
) -> EphemeralSubscription {
  let id = self.alloc_sub_id()
  self.subs.push({ id, callback })
  { store: self, id }
}

///|
fn EphemeralStore::alloc_sub_id(self : EphemeralStore) -> Int {
  let id = self.next_sub_id
  self.next_sub_id = id + 1
  id
}

///|
fn EphemeralStore::unsubscribe(self : EphemeralStore, id : Int) -> Unit {
  self.local_subs = self.local_subs.filter(fn(e) { e.id != id })
  self.subs = self.subs.filter(fn(e) { e.id != id })
}

///|
fn filter_local_subs(entries : Array[EphemeralLocalEntry], bytes : Bytes) -> Array[EphemeralLocalEntry] {
  entries.filter(fn(entry) { (entry.callback)(bytes) })
}

///|
fn filter_ephemeral_subs(entries : Array[EphemeralSubscriberEntry], event : EphemeralStoreEvent) -> Array[EphemeralSubscriberEntry] {
  entries.filter(fn(entry) { (entry.callback)(event) })
}
```

Note: `set_state` calls `self.encode(key)` which depends on Task 4. **Implement Task 4 before running tests for Task 3.** Alternatively, stub `encode` to return `b""` initially and fill in Task 4 next.

- [ ] **Run:** `moon check`

### Step 3.2: Write tests for core operations

- [ ] **Add to `editor/ephemeral_test.mbt`:**

```moonbit
///|
test "set and get" {
  let store = EphemeralStore::new(60000UL)
  store.set("1", EphemeralValue::I64(42L))
  inspect!(store.get("1"), content="Some(I64(42))")
  inspect!(store.get("2"), content="None")
}

///|
test "delete removes value" {
  let store = EphemeralStore::new(60000UL)
  store.set("1", EphemeralValue::I64(42L))
  store.delete("1")
  inspect!(store.get("1"), content="None")
}

///|
test "get_all_states excludes deleted" {
  let store = EphemeralStore::new(60000UL)
  store.set("1", EphemeralValue::I64(1L))
  store.set("2", EphemeralValue::I64(2L))
  store.delete("1")
  let states = store.get_all_states()
  inspect!(states.size(), content="1")
  inspect!(states.get("2"), content="Some(I64(2))")
}

///|
test "keys returns only non-deleted" {
  let store = EphemeralStore::new(60000UL)
  store.set("1", EphemeralValue::I64(1L))
  store.set("2", EphemeralValue::I64(2L))
  store.delete("1")
  inspect!(store.keys(), content="[2]")
}

///|
test "set Null acts as delete" {
  let store = EphemeralStore::new(60000UL)
  store.set("1", EphemeralValue::I64(42L))
  store.set("1", EphemeralValue::Null)
  inspect!(store.get("1"), content="None")
}

///|
test "subscribe receives Local events" {
  let store = EphemeralStore::new(60000UL)
  let events : Array[EphemeralStoreEvent] = []
  let _sub = store.subscribe(fn(event) {
    events.push(event)
    true
  })
  store.set("1", EphemeralValue::I64(42L))
  inspect!(events.length(), content="1")
  inspect!(events[0].by(), content="Local")
  inspect!(events[0].added(), content="[1]")
}

///|
test "subscribe auto-unsubscribe on false" {
  let store = EphemeralStore::new(60000UL)
  let call_count : Ref[Int] = Ref::new(0)
  let _sub = store.subscribe(fn(_event) {
    call_count.val = call_count.val + 1
    false // unsubscribe after first call
  })
  store.set("1", EphemeralValue::I64(1L))
  store.set("2", EphemeralValue::I64(2L))
  inspect!(call_count.val, content="1")
}

///|
test "unsubscribe stops events" {
  let store = EphemeralStore::new(60000UL)
  let call_count : Ref[Int] = Ref::new(0)
  let sub = store.subscribe(fn(_event) {
    call_count.val = call_count.val + 1
    true
  })
  store.set("1", EphemeralValue::I64(1L))
  sub.unsubscribe()
  store.set("2", EphemeralValue::I64(2L))
  inspect!(call_count.val, content="1")
}
```

- [ ] **Commit:** `feat(editor): add EphemeralStore core operations`

---

## Task 4: Binary Encode/Decode for Entries

**Files:**
- Modify: `editor/ephemeral_encoding.mbt`
- Modify: `editor/ephemeral.mbt` (add `encode`, `encode_all`, `apply`)
- Modify: `editor/ephemeral_test.mbt`

### Step 4.1: Value encoding tags and write/read functions

- [ ] **Add to `editor/ephemeral_encoding.mbt`:**

```moonbit
///|
let tag_null : Byte = b'\x00'

///|
let tag_bool : Byte = b'\x01'

///|
let tag_f64 : Byte = b'\x02'

///|
let tag_i64 : Byte = b'\x03'

///|
let tag_string : Byte = b'\x04'

///|
let tag_list : Byte = b'\x05'

///|
let tag_map : Byte = b'\x06'

///|
let tag_bytes : Byte = b'\x08'

///|
fn write_ephemeral_value(buf : @buffer.T, value : EphemeralValue) -> Unit {
  match value {
    EphemeralValue::Null => buf.write_byte(tag_null)
    EphemeralValue::Bool(v) => {
      buf.write_byte(tag_bool)
      buf.write_byte(if v { b'\x01' } else { b'\x00' })
    }
    EphemeralValue::F64(v) => {
      buf.write_byte(tag_f64)
      write_f64_le(buf, v)
    }
    EphemeralValue::I64(v) => {
      buf.write_byte(tag_i64)
      write_ivarint(buf, v)
    }
    EphemeralValue::String(v) => {
      buf.write_byte(tag_string)
      write_string(buf, v)
    }
    EphemeralValue::Bytes(v) => {
      buf.write_byte(tag_bytes)
      write_len_bytes(buf, v)
    }
    EphemeralValue::List(items) => {
      buf.write_byte(tag_list)
      write_uvarint(buf, items.length().to_uint64())
      for item in items {
        write_ephemeral_value(buf, item)
      }
    }
    EphemeralValue::Map(map) => {
      buf.write_byte(tag_map)
      write_uvarint(buf, map.size().to_uint64())
      for key, item in map {
        write_string(buf, key)
        write_ephemeral_value(buf, item)
      }
    }
  }
}

///|
fn read_ephemeral_value(reader : Reader) -> EphemeralValue!String {
  let tag = reader.read_byte!()
  if tag == tag_null {
    EphemeralValue::Null
  } else if tag == tag_bool {
    let raw = reader.read_byte!()
    if raw == b'\x00' {
      EphemeralValue::Bool(false)
    } else if raw == b'\x01' {
      EphemeralValue::Bool(true)
    } else {
      raise "invalid bool value"
    }
  } else if tag == tag_f64 {
    EphemeralValue::F64(read_f64_le!(reader))
  } else if tag == tag_i64 {
    EphemeralValue::I64(read_ivarint!(reader))
  } else if tag == tag_string {
    EphemeralValue::String(read_string!(reader))
  } else if tag == tag_bytes {
    EphemeralValue::Bytes(read_len_bytes!(reader))
  } else if tag == tag_list {
    let count = read_uvarint!(reader).to_int()
    let items : Array[EphemeralValue] = []
    for i = 0; i < count; i = i + 1 {
      items.push(read_ephemeral_value!(reader))
    }
    EphemeralValue::List(items)
  } else if tag == tag_map {
    let count = read_uvarint!(reader).to_int()
    let map : Map[String, EphemeralValue] = {}
    for i = 0; i < count; i = i + 1 {
      let key = read_string!(reader)
      let item = read_ephemeral_value!(reader)
      map[key] = item
    }
    EphemeralValue::Map(map)
  } else {
    raise "invalid ephemeral value tag"
  }
}

///|
fn write_f64_le(buf : @buffer.T, value : Double) -> Unit {
  let bits = value.reinterpret_as_uint64()
  for i = 0; i < 8; i = i + 1 {
    buf.write_byte(((bits.lsr(i * 8)).land(0xFFUL)).to_byte())
  }
}

///|
fn read_f64_le(reader : Reader) -> Double!String {
  let bytes = reader.read_bytes!(8)
  let mut bits : UInt64 = 0
  for i = 0; i < 8; i = i + 1 {
    bits = bits.lor(bytes[i].to_uint64().lsl(i * 8))
  }
  bits.reinterpret_as_double()
}

///|
fn parse_peer_id(key : String) -> UInt64? {
  try {
    Some(@strconv.parse_uint64!(key))
  } catch {
    _ => None
  }
}

///|
fn encode_entries(entries : Array[(String, EphemeralRecord)]) -> Bytes {
  let buf = @buffer.new()
  let filtered : Array[(UInt64, Int64, EphemeralValue)] = []
  for entry in entries {
    let (key, record) = entry
    let peer = match parse_peer_id(key) {
      Some(value) => value
      None => continue
    }
    let value = match record.value {
      Some(value) => value
      None => EphemeralValue::Null
    }
    filtered.push((peer, record.clock, value))
  }
  write_uvarint(buf, filtered.length().to_uint64())
  for entry in filtered {
    let (peer, clock, value) = entry
    write_uvarint(buf, peer)
    write_ivarint(buf, clock)
    write_ephemeral_value(buf, value)
  }
  buf.to_bytes()
}

///|
fn decode_entries(data : Bytes) -> Array[(String, EphemeralRecord)]!String {
  if data.length() == 0 {
    return []
  }
  let reader = Reader::new(data)
  let count = read_uvarint!(reader).to_int()
  let out : Array[(String, EphemeralRecord)] = []
  for i = 0; i < count; i = i + 1 {
    let peer = read_uvarint!(reader)
    let clock = read_ivarint!(reader)
    let value = read_ephemeral_value!(reader)
    let value_opt = match value {
      EphemeralValue::Null => None
      _ => Some(value)
    }
    out.push((peer.to_string(), { value: value_opt, clock, updated_at: 0UL }))
  }
  out
}
```

### Step 4.2: Add `encode`, `encode_all`, `apply`, `remove_outdated` to the store

- [ ] **Add to `editor/ephemeral.mbt`:**

```moonbit
///|
fn is_expired(updated_at : UInt64, now : UInt64, timeout_ms : UInt64) -> Bool {
  if timeout_ms == 0UL {
    return false
  }
  now > updated_at && now - updated_at > timeout_ms
}

///|
pub fn EphemeralStore::encode(self : EphemeralStore, key : String) -> Bytes {
  let now = now_ms()
  match self.states.get(key) {
    Some(record) =>
      if is_expired(record.updated_at, now, self.timeout_ms) {
        Bytes::new(0)
      } else {
        encode_entries([(key, record)])
      }
    None => Bytes::new(0)
  }
}

///|
pub fn EphemeralStore::encode_all(self : EphemeralStore) -> Bytes {
  let now = now_ms()
  let entries : Array[(String, EphemeralRecord)] = []
  for key, record in self.states {
    if not(is_expired(record.updated_at, now, self.timeout_ms)) {
      entries.push((key, record))
    }
  }
  encode_entries(entries)
}

///|
pub fn EphemeralStore::apply(self : EphemeralStore, data : Bytes) -> Unit!String {
  let entries = decode_entries!(data)
  if entries.length() == 0 {
    return
  }
  let now = now_ms()
  let added : Array[String] = []
  let updated : Array[String] = []
  let removed : Array[String] = []
  for entry in entries {
    let (key, record) = entry
    match self.states.get(key) {
      Some(existing) => {
        if existing.clock >= record.clock {
          continue
        }
        let incoming = { value: record.value, clock: record.clock, updated_at: now }
        self.states[key] = incoming
        match (existing.value, record.value) {
          (Some(_), Some(_)) => updated.push(key)
          (Some(_), None) => removed.push(key)
          (None, Some(_)) => added.push(key)
          (None, None) => ()
        }
      }
      None => {
        let incoming = { value: record.value, clock: record.clock, updated_at: now }
        self.states[key] = incoming
        match record.value {
          Some(_) => added.push(key)
          None => ()
        }
      }
    }
  }
  if added.length() > 0 || updated.length() > 0 || removed.length() > 0 {
    let event = { by: EphemeralEventTrigger::Import, added, updated, removed }
    self.subs = filter_ephemeral_subs(self.subs, event)
  }
}

///|
pub fn EphemeralStore::remove_outdated(self : EphemeralStore) -> Unit {
  let now = now_ms()
  let removed : Array[String] = []
  let next : Map[String, EphemeralRecord] = {}
  for key, record in self.states {
    if is_expired(record.updated_at, now, self.timeout_ms) {
      match record.value {
        Some(_) => removed.push(key)
        None => ()
      }
    } else {
      next[key] = record
    }
  }
  self.states = next
  if removed.length() > 0 {
    let event = { by: EphemeralEventTrigger::Timeout, added: [], updated: [], removed }
    self.subs = filter_ephemeral_subs(self.subs, event)
  }
}
```

### Step 4.3: Write encode/decode and LWW tests

- [ ] **Add to `editor/ephemeral_test.mbt`:**

```moonbit
///|
test "encode/decode roundtrip single entry" {
  let store = EphemeralStore::new(60000UL)
  store.set("123", EphemeralValue::Map({
    "cursor": EphemeralValue::I64(42L),
    "name": EphemeralValue::String("Alice"),
  }))
  let bytes = store.encode("123")
  let store2 = EphemeralStore::new(60000UL)
  store2.apply!(bytes)
  inspect!(store2.get("123") != None, content="true")
}

///|
test "encode/decode roundtrip all value types" {
  let store = EphemeralStore::new(60000UL)
  store.set("1", EphemeralValue::Bool(true))
  store.set("2", EphemeralValue::I64(-999L))
  store.set("3", EphemeralValue::F64(3.14))
  store.set("4", EphemeralValue::String("hello"))
  store.set("5", EphemeralValue::List([EphemeralValue::I64(1L), EphemeralValue::I64(2L)]))
  let bytes = store.encode_all()
  let store2 = EphemeralStore::new(60000UL)
  store2.apply!(bytes)
  inspect!(store2.get("1"), content="Some(Bool(true))")
  inspect!(store2.get("2"), content="Some(I64(-999))")
  inspect!(store2.get("4"), content="Some(String(hello))")
  inspect!(store2.keys().length(), content="5")
}

///|
test "LWW: higher clock wins" {
  let store = EphemeralStore::new(60000UL)
  // Peer A sets key "1" with clock 1
  store.set("1", EphemeralValue::I64(10L))
  // Simulate remote with clock 5 (higher)
  let buf = @buffer.new()
  write_uvarint(buf, 1UL) // count
  write_uvarint(buf, 1UL) // peer_id
  write_ivarint(buf, 5L)  // clock
  buf.write_byte(b'\x03') // tag_i64
  write_ivarint(buf, 99L) // value
  store.apply!(buf.to_bytes())
  inspect!(store.get("1"), content="Some(I64(99))")
}

///|
test "LWW: lower clock is discarded" {
  let store = EphemeralStore::new(60000UL)
  // Set key "1" multiple times to get clock=3
  store.set("1", EphemeralValue::I64(1L))
  store.set("1", EphemeralValue::I64(2L))
  store.set("1", EphemeralValue::I64(3L))
  // Simulate remote with clock 2 (lower)
  let buf = @buffer.new()
  write_uvarint(buf, 1UL)
  write_uvarint(buf, 1UL)
  write_ivarint(buf, 2L)
  buf.write_byte(b'\x03')
  write_ivarint(buf, 99L)
  store.apply!(buf.to_bytes())
  // Local value should be unchanged
  inspect!(store.get("1"), content="Some(I64(3))")
}

///|
test "apply triggers Import event" {
  let store = EphemeralStore::new(60000UL)
  let events : Array[EphemeralStoreEvent] = []
  let _sub = store.subscribe(fn(event) {
    events.push(event)
    true
  })
  // Build a remote message
  let remote = EphemeralStore::new(60000UL)
  remote.set("1", EphemeralValue::I64(42L))
  let bytes = remote.encode_all()
  store.apply!(bytes)
  inspect!(events.length(), content="1")
  inspect!(events[0].by(), content="Import")
  inspect!(events[0].added(), content="[1]")
}

///|
test "non-numeric keys are silently skipped in encoding" {
  let store = EphemeralStore::new(60000UL)
  // Directly set a non-numeric key (bypassing any future validation)
  store.set("alice", EphemeralValue::I64(42L))
  let bytes = store.encode("alice")
  // encode produces empty bytes for non-numeric keys
  inspect!(bytes.length(), content="0")
}
```

- [ ] **Run tests:** `moon test -p dowdiness/canopy/editor`
- [ ] **Run:** `moon info && moon fmt`
- [ ] **Commit:** `feat(editor): add EphemeralStore encode/decode and LWW`

---

## Task 5: Whitebox Timeout Tests

**Files:**
- Create: `editor/ephemeral_wbtest.mbt`

### Step 5.1: Write whitebox tests for timeout behavior

- [ ] **Write `editor/ephemeral_wbtest.mbt`:**

```moonbit
///|
test "remove_outdated removes expired entries" {
  let store = EphemeralStore::new(1000UL)
  store.set("1", EphemeralValue::I64(42L))
  store.set("2", EphemeralValue::I64(99L))
  // Backdate key "1" to trigger expiry
  match store.states.get("1") {
    Some(record) =>
      store.states["1"] = { value: record.value, clock: record.clock, updated_at: 0UL }
    None => ()
  }
  store.remove_outdated()
  inspect!(store.get("1"), content="None")
  inspect!(store.get("2") != None, content="true")
}

///|
test "remove_outdated triggers Timeout event" {
  let store = EphemeralStore::new(1000UL)
  store.set("1", EphemeralValue::I64(42L))
  // Backdate
  match store.states.get("1") {
    Some(record) =>
      store.states["1"] = { value: record.value, clock: record.clock, updated_at: 0UL }
    None => ()
  }
  let events : Array[EphemeralStoreEvent] = []
  let _sub = store.subscribe(fn(event) {
    events.push(event)
    true
  })
  store.remove_outdated()
  inspect!(events.length(), content="1")
  inspect!(events[0].by, content="Timeout")
  inspect!(events[0].removed, content="[1]")
}

///|
test "remove_outdated skips deleted entries in removed list" {
  let store = EphemeralStore::new(1000UL)
  store.set("1", EphemeralValue::I64(42L))
  store.delete("1") // value is now None (tombstone)
  // Backdate the tombstone
  match store.states.get("1") {
    Some(record) =>
      store.states["1"] = { value: record.value, clock: record.clock, updated_at: 0UL }
    None => ()
  }
  let events : Array[EphemeralStoreEvent] = []
  let _sub = store.subscribe(fn(event) {
    events.push(event)
    true
  })
  store.remove_outdated()
  // Tombstone expired but should NOT appear in removed (was already deleted)
  inspect!(events.length(), content="0")
}

///|
test "timeout_ms=0 disables expiry" {
  let store = EphemeralStore::new(0UL)
  store.set("1", EphemeralValue::I64(42L))
  // Backdate to ancient time
  match store.states.get("1") {
    Some(record) =>
      store.states["1"] = { value: record.value, clock: record.clock, updated_at: 0UL }
    None => ()
  }
  store.remove_outdated()
  // Should NOT be removed when timeout is 0
  inspect!(store.get("1"), content="Some(I64(42))")
}

///|
test "clock increments on each set" {
  let store = EphemeralStore::new(60000UL)
  store.set("1", EphemeralValue::I64(1L))
  inspect!(store.states["1"].clock, content="1")
  store.set("1", EphemeralValue::I64(2L))
  inspect!(store.states["1"].clock, content="2")
  store.set("1", EphemeralValue::I64(3L))
  inspect!(store.states["1"].clock, content="3")
}
```

- [ ] **Run tests:** `moon test -p dowdiness/canopy/editor`
- [ ] **Commit:** `test(editor): add whitebox tests for EphemeralStore timeout`

---

## Task 6: Cursor Awareness Layer

**Files:**
- Create: `editor/cursor_view.mbt`
- Create: `editor/cursor_view_test.mbt`

### Step 6.1: Write cursor adjustment tests first

- [ ] **Write `editor/cursor_view_test.mbt`:**

```moonbit
///|
test "adjust_position: before edit unchanged" {
  inspect!(adjust_position(3, 5, 0, 1), content="3")
}

///|
test "adjust_position: after insert shifts right" {
  inspect!(adjust_position(7, 3, 0, 1), content="8")
}

///|
test "adjust_position: inside deleted region moves to edit end" {
  inspect!(adjust_position(4, 3, 3, 0), content="3")
}

///|
test "adjust_position: after delete shifts left" {
  inspect!(adjust_position(7, 3, 2, 0), content="5")
}

///|
test "adjust_position: at edit boundary" {
  // pos == edit_start, insert
  inspect!(adjust_position(5, 5, 0, 3), content="5")
  // pos == edit_start + old_len (just past deleted range)
  inspect!(adjust_position(8, 5, 3, 0), content="5")
}

///|
test "PeerCursorView adjust_for_edit" {
  let view = PeerCursorView::new()
  view.set_cursor("peer1", 10, "Alice", "#ff0000")
  view.set_cursor("peer2", 3, "Bob", "#00ff00")
  // Insert 1 char at position 5
  view.adjust_for_edit(5, 0, 1)
  inspect!(view.get_cursor("peer1").unwrap().adjusted_cursor, content="11")
  inspect!(view.get_cursor("peer2").unwrap().adjusted_cursor, content="3")
}

///|
test "PeerCursorView apply_raw_update resets adjusted" {
  let view = PeerCursorView::new()
  view.set_cursor("peer1", 10, "Alice", "#ff0000")
  // Simulate local edit adjusting cursor
  view.adjust_for_edit(5, 0, 1)
  inspect!(view.get_cursor("peer1").unwrap().adjusted_cursor, content="11")
  // Peer sends new raw position
  view.set_cursor("peer1", 12, "Alice", "#ff0000")
  inspect!(view.get_cursor("peer1").unwrap().adjusted_cursor, content="12")
}

///|
test "PeerCursorView remove" {
  let view = PeerCursorView::new()
  view.set_cursor("peer1", 10, "Alice", "#ff0000")
  view.remove("peer1")
  inspect!(view.get_cursor("peer1"), content="None")
}
```

### Step 6.2: Implement cursor view

- [ ] **Write `editor/cursor_view.mbt`:**

```moonbit
///|
pub struct PeerCursor {
  mut raw_cursor : Int
  mut adjusted_cursor : Int
  mut display_name : String
  mut color : String
}

///|
pub struct PeerCursorView {
  cursors : Map[String, PeerCursor]
}

///|
pub fn PeerCursorView::new() -> PeerCursorView {
  { cursors: Map::new() }
}

///|
pub fn PeerCursorView::set_cursor(
  self : PeerCursorView,
  peer_id : String,
  cursor : Int,
  name : String,
  color : String,
) -> Unit {
  self.cursors[peer_id] = {
    raw_cursor: cursor,
    adjusted_cursor: cursor,
    display_name: name,
    color,
  }
}

///|
pub fn PeerCursorView::get_cursor(self : PeerCursorView, peer_id : String) -> PeerCursor? {
  self.cursors.get(peer_id)
}

///|
pub fn PeerCursorView::remove(self : PeerCursorView, peer_id : String) -> Unit {
  self.cursors.remove(peer_id)
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
      cursor.adjusted_cursor, edit_start, old_len, new_len,
    )
  }
}

///|
pub fn PeerCursorView::all_cursors(self : PeerCursorView) -> Map[String, PeerCursor] {
  self.cursors
}

///|
pub fn adjust_position(pos : Int, edit_start : Int, old_len : Int, new_len : Int) -> Int {
  if pos <= edit_start {
    pos
  } else if pos <= edit_start + old_len {
    edit_start + new_len
  } else {
    pos - old_len + new_len
  }
}
```

- [ ] **Run tests:** `moon test -p dowdiness/canopy/editor`
- [ ] **Run:** `moon info && moon fmt`
- [ ] **Commit:** `feat(editor): add PeerCursorView for cursor awareness`

---

## Task 7: Final Verification

### Step 7.1: Run all tests and format

- [ ] **Run:** `moon test` (full project)
- [ ] **Run:** `moon check`
- [ ] **Run:** `moon info && moon fmt`
- [ ] **Check:** `git diff *.mbti` to verify public API surface

### Step 7.2: Verify against design doc criteria

Cross-check the 12 verification criteria from `docs/design/04-ephemeral-store.md`:

1. LWW ordering — tested in "LWW: higher clock wins" + "LWW: lower clock is discarded"
2. Clock increment — tested in whitebox "clock increments on each set"
3. Timeout expiry — tested in whitebox "remove_outdated removes expired entries"
4. Encode/decode roundtrip — tested in "encode/decode roundtrip all value types"
5. Event correctness — tested in "subscribe receives Local events" + "apply triggers Import event" + "remove_outdated triggers Timeout event"
6. Subscription auto-unsubscribe — tested in "subscribe auto-unsubscribe on false"
7. Cursor adjustment — tested in cursor_view_test.mbt
8. Raw update resets adjustment — tested in "PeerCursorView apply_raw_update resets adjusted"
9. Initial sync — covered by encode_all + apply roundtrip test
10. Graceful disconnect — covered by "delete removes value" test
11. Heartbeat keeps alive — deferred (requires time-advancing test or integration test)
12. No CRDT contamination — architectural (ephemeral types are independent of TextDoc/OpLog)

- [ ] **Commit:** `chore(editor): finalize EphemeralStore implementation`
