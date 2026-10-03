///|
/// The mutable EGW and native editor capabilities live in this example shell.
let states : Array[(@text.TextState, @undo.UndoManager)] = []

///|
fn create(actor : String, archive : String, version : String) -> String {
  try {
    let state = if archive == "" {
      @text.TextState::new(actor)
    } else {
      @text.TextState::restore_compact_direct_experimental(
        archive, actor, version,
      )
    }
    let handle = states.length()
    states.push((state, @undo.UndoManager::new(actor)))
    ({ "ok": true, "handle": handle.to_json() } : Json).stringify()
  } catch {
    error => failure(error)
  }
}

///|
fn failure(error : Error) -> String {
  let message = match error {
    @text.TextError::SyncFailed(reason) => reason.to_string()
    _ => error.to_string()
  }
  ({ "ok": false, "error": message.to_json() } : Json).stringify()
}

///|
fn inspect_state(handle : Int) -> String {
  try {
    let (state, undo) = states[handle]
    (
      {
        "ok": true,
        "text": state.text().to_json(),
        "version": state.version().to_json_string().to_json(),
        "count": state.causal_snapshot().op_count().to_json(),
        "pending": state.sync().pending_sync_count().to_json(),
        "canUndo": undo.can_undo().to_json(),
        "canRedo": undo.can_redo().to_json(),
      } : Json).stringify()
  } catch {
    error => failure(error)
  }
}

///|
fn replace(handle : Int, start : Int, end : Int, inserted : String) -> String {
  try {
    let (state, undo) = states[handle]
    undo.stop_capturing()
    state.replace_range_and_record(
      @text.Range::from_ints(start, end),
      inserted,
      undo,
      timestamp_ms=0,
    )
    undo.stop_capturing()
    inspect_state(handle)
  } catch {
    error => failure(error)
  }
}

///|
fn history(handle : Int, redo : Bool) -> String {
  try {
    let (state, undo) = states[handle]
    undo.stop_capturing()
    if redo {
      ignore(undo.redo(state))
    } else {
      ignore(undo.undo(state))
    }
    inspect_state(handle)
  } catch {
    error => failure(error)
  }
}

///|
fn delta(handle : Int, version : String) -> String {
  try {
    let message = states[handle].0
      .sync()
      .export_since(@text.Version::from_json_string(version))
    ({ "ok": true, "payload": message.to_json_string().to_json() } : Json).stringify()
  } catch {
    error => failure(error)
  }
}

///|
fn archive(handle : Int) -> String {
  (
    {
      "ok": true,
      "archive": states[handle].0.export_compact_experimental().to_json(),
    } : Json).stringify() catch {
    error => failure(error)
  }
}

///|
fn apply(handle : Int, payload : String) -> String {
  try {
    let state = states[handle].0
    let transition = state
      .sync()
      .apply_transition(@text.SyncMessage::from_json_string(payload))
    let effects : Array[Json] = []
    let availability = match transition.availability() {
      Exact(exact) => {
        for effect in exact {
          effects.push(
            match effect {
              Insert(pos, text) =>
                {
                  "kind": "insert",
                  "start": pos.value().to_json(),
                  "text": text.to_json(),
                }
              Delete(range) =>
                {
                  "kind": "delete",
                  "start": range.start().value().to_json(),
                  "end": range.end().value().to_json(),
                }
            },
          )
        }
        "exact"
      }
      SnapshotRequired => "snapshot"
      Unavailable => "unavailable"
    }
    let report = transition.finish()
    (
      {
        "ok": true,
        "availability": availability.to_json(),
        "effects": effects.to_json(),
        "before": transition.version_before().to_json_string().to_json(),
        "after": transition.version_after().to_json_string().to_json(),
        "pending": report.pending_operations().to_json(),
      } : Json).stringify()
  } catch {
    error => failure(error)
  }
}

///|
extern "js" fn expose(
  create : (String, String, String) -> String,
  inspect : (Int) -> String,
  replace : (Int, Int, Int, String) -> String,
  apply : (Int, String) -> String,
  delta : (Int, String) -> String,
  archive : (Int) -> String,
  history : (Int, Bool) -> String,
) =
  #| (create, inspect, replace, apply, delta, archive, history) => {
  #|   const wrap = f => (...a) => { const r=JSON.parse(f(...a)); if(!r.ok) throw Error(r.error); return r; };
  #|   globalThis.egw = Object.fromEntries(Object.entries({create,inspect,replace,apply,delta,archive,history}).map(([k,v])=>[k,wrap(v)]));
  #| }

///|
fn main {
  expose(create, inspect_state, replace, apply, delta, archive, history)
}
