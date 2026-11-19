///|
const DATABASE_NAME : String = "loomark"

///|
const DATABASE_VERSION : Int = 2

///|
const STORE_NAME : String = "documents"

///|
/// Opens the database at `DATABASE_VERSION`, rewriting older data in the
/// upgrade transaction, and closes it again. Resolves `false` when the
/// database cannot be opened or the rewrite fails, which changes nothing.
fn upgrade_storage() -> @js_async.Promise[Bool] {
  ffi_upgrade_storage(DATABASE_NAME, DATABASE_VERSION, STORE_NAME, (
    old_version,
    key,
    value,
    replace,
  ) => {
    if upgrade_record(old_version, key, value) is Some(next) {
      replace(next)
    }
  })
}

///|
extern "js" fn ffi_upgrade_storage(
  name : String,
  version : Int,
  store_name : String,
  rewrite : (Int, String, String, (String) -> Unit) -> Unit,
) -> @js_async.Promise[Bool] =
  #| (name, version, storeName, rewrite) => new Promise(resolve => {
  #|   let open;
  #|   try { open = indexedDB.open(name, version); } catch { resolve(false); return; }
  #|   open.onupgradeneeded = event => {
  #|     const database = open.result;
  #|     const transaction = open.transaction;
  #|     if (!database.objectStoreNames.contains(storeName)) {
  #|       database.createObjectStore(storeName);
  #|       return;
  #|     }
  #|     const cursorRequest = transaction.objectStore(storeName).openCursor();
  #|     cursorRequest.onsuccess = () => {
  #|       const cursor = cursorRequest.result;
  #|       if (!cursor) return;
  #|       try {
  #|         if (typeof cursor.key === "string" && typeof cursor.value === "string") {
  #|           let next = null;
  #|           rewrite(event.oldVersion, cursor.key, cursor.value, value => { next = value; });
  #|           if (next !== null) cursor.update(next);
  #|         }
  #|         cursor.continue();
  #|       } catch {
  #|         transaction.abort();
  #|       }
  #|     };
  #|   };
  #|   open.onsuccess = () => { open.result.close(); resolve(true); };
  #|   open.onerror = () => resolve(false);
  #| })

///|
/// The one-off rewrite of browser storage written before Change time existed
/// (database version 1), run by `upgrade_storage` once per browser before
/// Loomark reads anything. Every saved document gets the epoch as its Change
/// time, so the existing order (by Document ID) is kept until each document
/// next changes. No other code knows the old format.
fn upgrade_record(old_version : Int, key : String, value : String) -> String? {
  guard old_version < 2 else { return None }
  if key.has_prefix(SOURCE_KEY_PREFIX) {
    upgrade_source(value)
  } else if key.has_prefix(REPLICA_KEY_PREFIX) {
    upgrade_replica(value)
  } else {
    None
  }
}

///|
/// Records that are not a version-1 shape are kept as they are; reading them
/// still reports them as unsupported.
fn upgrade_source(value : String) -> String? {
  let json = @json.parse(value) catch { _ => return None }
  guard json is Json::Object(fields) &&
    fields.length() == 2 &&
    fields.contains("document_id") &&
    fields.contains("text") else {
    return None
  }
  Some(at_epoch(json).stringify())
}

///|
fn upgrade_replica(encoded : String) -> String? {
  guard decode_header_length(encoded) is Some((length, start)) &&
    length <= encoded.length() - start else {
    return None
  }
  let header = @json.parse(encoded[start:start + length].to_owned()) catch {
    _ => return None
  }
  guard header is Json::Object(fields) && fields.get("state") is Some(state) else {
    return None
  }
  let upgraded = fields.copy()
  upgraded["state"] = upgrade_state(state)
  let header = Json::object(upgraded).stringify()
  Some(
    REPLICA_FRAME_PREFIX +
    header.length().to_string() +
    "\n" +
    header +
    encoded[start + length:].to_owned(),
  )
}

///|
/// Every place a Replica holds text gains the epoch beside it: the current
/// document, a present baseline or remote revision, and a pending save.
fn upgrade_state(state : Json) -> Json {
  guard state is Json::Object(fields) &&
    fields.get("kind") is Some(Json::String("live" | "deleting")) else {
    return state
  }
  let upgraded = fields.copy()
  upgraded["changed_at"] = 0
  if fields.get("baseline") is Some(baseline) && kind(baseline) == "present" {
    upgraded["baseline"] = at_epoch(baseline)
  }
  if fields.get("phase") is Some(Json::Object(phase)) {
    let next = phase.copy()
    if phase.get("remote") is Some(remote) && kind(remote) == "present" {
      next["remote"] = at_epoch(remote)
    }
    if phase.get("operation") is Some(operation) && kind(operation) == "save" {
      next["operation"] = at_epoch(operation)
    }
    upgraded["phase"] = Json::object(next)
  }
  Json::object(upgraded)
}

///|
fn kind(value : Json) -> String {
  match value {
    Json::Object(fields) =>
      match fields.get("kind") {
        Some(Json::String(kind)) => kind
        _ => ""
      }
    _ => ""
  }
}

///|
fn at_epoch(value : Json) -> Json {
  guard value is Json::Object(fields) else { return value }
  let upgraded = fields.copy()
  upgraded["changed_at"] = 0
  Json::object(upgraded)
}
