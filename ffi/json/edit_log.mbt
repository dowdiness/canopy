// Edit log for tracking applied structural edits on JSON documents.
// Bounded ring buffer stored on JsonHandle, exposed via FFI.

///|
/// A single edit log entry — captures the operation JSON, timestamp, and result.
priv struct JsonEditLogEntry {
  op : Json // parsed from the caller's op_json — reuses existing parse work
  ts : Int
  ok : Bool
  error : String?
}

///|
/// Maximum number of edit log entries to retain. A bounded ring buffer
/// prevents unbounded memory growth under heavy editing.
const MAX_EDIT_LOG_SIZE = 100

///|
/// Get the edit log for a JSON editor as a JSON array string.
/// Each entry: {"op": {...}, "ts": <int>, "ok": <bool>}
/// The `error` key is omitted when None.
pub fn json_get_edit_log(handle : Int) -> String {
  match json_registry.get(handle) {
    Some(h) => {
      let entries : Array[Json] = []
      for entry in h.edit_log.iter() {
        entries.push(entry.to_json())
      }
      Json::array(entries).stringify()
    }
    None => "[]"
  }
}

///|
fn JsonEditLogEntry::to_json(self : JsonEditLogEntry) -> Json {
  let m : Map[String, Json] = {}
  m["op"] = self.op
  m["ts"] = Json::number(self.ts.to_double())
  m["ok"] = self.ok.to_json()
  match self.error {
    Some(e) => m["error"] = Json::string(e)
    None => ()
  }
  Json::object(m)
}
