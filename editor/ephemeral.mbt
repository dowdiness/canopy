///|
pub(all) enum EphemeralValue {
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
pub(all) enum EphemeralEventTrigger {
  Local
  Import
  Timeout
} derive(Show, Eq)

///|
pub(all) struct EphemeralStoreEvent {
  by : EphemeralEventTrigger
  added : Array[String]
  updated : Array[String]
  removed : Array[String]
} derive(Show)

///|
pub fn EphemeralStoreEvent::by(
  self : EphemeralStoreEvent,
) -> EphemeralEventTrigger {
  self.by
}

///|
pub fn EphemeralStoreEvent::added(self : EphemeralStoreEvent) -> Array[String] {
  self.added
}

///|
pub fn EphemeralStoreEvent::updated(
  self : EphemeralStoreEvent,
) -> Array[String] {
  self.updated
}

///|
pub fn EphemeralStoreEvent::removed(
  self : EphemeralStoreEvent,
) -> Array[String] {
  self.removed
}

///|
struct EphemeralRecord {
  value : EphemeralValue?
  clock : Int64
  updated_at : UInt64
}

///|
struct EphemeralLocalEntry {
  id : Int
  callback : (Bytes) -> Bool
}

///|
struct EphemeralSubscriberEntry {
  id : Int
  callback : (EphemeralStoreEvent) -> Bool
}

///|
pub struct EphemeralSubscription {
  priv store : EphemeralStore
  priv id : Int
}

///|
pub struct EphemeralStore {
  priv timeout_ms : UInt64
  priv mut next_sub_id : Int
  priv mut states : Map[String, EphemeralRecord]
  priv mut local_subs : Array[EphemeralLocalEntry]
  priv mut subs : Array[EphemeralSubscriberEntry]
}

///|
pub fn EphemeralStore::new(timeout_ms : UInt64) -> EphemeralStore {
  { timeout_ms, next_sub_id: 1, states: Map::new(), local_subs: [], subs: [] }
}

///|
pub fn EphemeralStore::get(
  self : EphemeralStore,
  key : String,
) -> EphemeralValue? {
  match self.states.get(key) {
    Some(record) => record.value
    None => None
  }
}

///|
pub fn EphemeralStore::get_all_states(
  self : EphemeralStore,
) -> Map[String, EphemeralValue] {
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
pub fn EphemeralStore::set(
  self : EphemeralStore,
  key : String,
  value : EphemeralValue,
) -> Unit raise EphemeralError {
  if parse_peer_id(key) is None {
    raise EphemeralError::InvalidPeerKey(key~)
  }
  match value {
    EphemeralValue::Null => self.set_state(key, None)
    _ => self.set_state(key, Some(value))
  }
}

///|
pub fn EphemeralStore::delete(
  self : EphemeralStore,
  key : String,
) -> Unit raise EphemeralError {
  if parse_peer_id(key) is None {
    raise EphemeralError::InvalidPeerKey(key~)
  }
  self.set_state(key, None)
}

///|
fn EphemeralStore::set_state(
  self : EphemeralStore,
  key : String,
  value : EphemeralValue?,
) -> Unit {
  let now = now_ms()
  let old = self.states.get(key)
  let next_clock = match old {
    Some(record) => record.clock + 1L
    None => 1L
  }
  let record : EphemeralRecord = { value, clock: next_clock, updated_at: now }
  self.states[key] = record
  // Notify local subscribers with encoded bytes (skip encode if no subscribers)
  if self.local_subs.length() > 0 {
    self.local_subs = filter_local_subs(self.local_subs, self.encode(key))
  }
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
    let event : EphemeralStoreEvent = {
      by: EphemeralEventTrigger::Local,
      added,
      updated,
      removed,
    }
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
  callback : (Bytes) -> Bool,
) -> EphemeralSubscription {
  let id = self.alloc_sub_id()
  self.local_subs.push({ id, callback })
  { store: self, id }
}

///|
pub fn EphemeralStore::subscribe(
  self : EphemeralStore,
  callback : (EphemeralStoreEvent) -> Bool,
) -> EphemeralSubscription {
  let id = self.alloc_sub_id()
  self.subs.push({ id, callback })
  { store: self, id }
}

///|
fn EphemeralStore::alloc_sub_id(self : EphemeralStore) -> Int {
  let id = self.next_sub_id
  self.next_sub_id = if id == @int.MAX_VALUE { 1 } else { id + 1 }
  id
}

///|
fn EphemeralStore::unsubscribe(self : EphemeralStore, id : Int) -> Unit {
  self.local_subs = self.local_subs.filter(fn(e) { e.id != id })
  self.subs = self.subs.filter(fn(e) { e.id != id })
}

///|
fn filter_local_subs(
  entries : Array[EphemeralLocalEntry],
  bytes : Bytes,
) -> Array[EphemeralLocalEntry] {
  entries.filter(fn(entry) { (entry.callback)(bytes) })
}

///|
fn filter_ephemeral_subs(
  entries : Array[EphemeralSubscriberEntry],
  event : EphemeralStoreEvent,
) -> Array[EphemeralSubscriberEntry] {
  entries.filter(fn(entry) { (entry.callback)(event) })
}

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
    if !is_expired(record.updated_at, now, self.timeout_ms) {
      entries.push((key, record))
    }
  }
  encode_entries(entries)
}

///|
pub fn EphemeralStore::apply(
  self : EphemeralStore,
  data : Bytes,
) -> Unit raise EphemeralError {
  let entries = decode_entries(data)
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
        let incoming : EphemeralRecord = {
          value: record.value,
          clock: record.clock,
          updated_at: now,
        }
        self.states[key] = incoming
        match (existing.value, record.value) {
          (Some(old_value), Some(new_value)) =>
            if old_value != new_value {
              updated.push(key)
            }
          (Some(_), None) => removed.push(key)
          (None, Some(_)) => added.push(key)
          (None, None) => ()
        }
      }
      None => {
        let incoming : EphemeralRecord = {
          value: record.value,
          clock: record.clock,
          updated_at: now,
        }
        self.states[key] = incoming
        match record.value {
          Some(_) => added.push(key)
          None => ()
        }
      }
    }
  }
  if added.length() > 0 || updated.length() > 0 || removed.length() > 0 {
    let event : EphemeralStoreEvent = {
      by: EphemeralEventTrigger::Import,
      added,
      updated,
      removed,
    }
    self.subs = filter_ephemeral_subs(self.subs, event)
  }
}

///|
pub fn EphemeralStore::remove_outdated(self : EphemeralStore) -> Unit {
  self.remove_outdated_at(now_ms())
}

///|
fn EphemeralStore::remove_outdated_at(
  self : EphemeralStore,
  now : UInt64,
) -> Unit {
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
    let event : EphemeralStoreEvent = {
      by: EphemeralEventTrigger::Timeout,
      added: [],
      updated: [],
      removed,
    }
    self.subs = filter_ephemeral_subs(self.subs, event)
  }
}
