// WebSocket FFI — lambda editor ws client transport

///|
pub fn ws_on_open(handle : Int, ws : @editor.JsWebSocket) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.ws_on_open(ws)
    None => ()
  }
}

///|
pub fn ws_on_message(handle : Int, data : Bytes) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.ws_on_message(data)
    None => ()
  }
}

///|
pub fn ws_on_close(handle : Int) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.ws_on_close()
    None => ()
  }
}

///|
pub fn ws_broadcast_edit(handle : Int) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.ws_broadcast_edit()
    None => ()
  }
}

///|
pub fn ws_broadcast_cursor(handle : Int) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.ws_broadcast_cursor()
    None => ()
  }
}

// --- Watchdog & status FFI ---

///|
/// Called by the JS watchdog timer when it fires.
/// `request_id` is compared against the current recovery epoch —
/// stale firings (response already arrived) are silently ignored.
pub fn ws_on_watchdog_fire(handle : Int, request_id : Int) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.on_watchdog_fire(request_id)
    None => ()
  }
}

///|
/// Enable the watchdog for this editor handle.
/// After each SyncRequest the editor will call `js_schedule_watchdog`,
/// which schedules a setTimeout(() => ws_on_watchdog_fire(handle, request_id)).
/// Call once at editor construction time.
pub fn ws_enable_watchdog(handle : Int, timeout_ms : Int) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => {
      h.editor.set_watchdog_timeout(timeout_ms)
      h.editor.set_watchdog_scheduler(
        Some(fn(request_id, ms) { js_schedule_watchdog(handle, request_id, ms) }),
      )
    }
    None => ()
  }
}

///|
/// Register a JS callback that receives SyncStatus transitions.
/// The callback payload is a JSON string; the JS host `JSON.parse`s it
/// and reads the shape { tag, peer_id?, attempt?, reason? }:
///   {"tag":"disconnected"}
///   {"tag":"idle"}
///   {"tag":"recovering","peer_id":"<id>","attempt":<n>}
///   {"tag":"error","reason":"exhausted","peer_id":"<id>"}
///   {"tag":"error","reason":"target_left","peer_id":"<id>"}
/// JSON (vs. a delimited string) avoids ambiguity when peer_id contains
/// characters that would otherwise need escaping at the boundary.
/// Host JS wires delivery via `globalThis.__canopy_on_status_change`.
/// Fires one notification with the current status immediately on
/// registration so late-registering hosts can bootstrap — otherwise
/// a status that changed before registration would never be observed.
pub fn ws_set_status_callback(handle : Int) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => {
      h.editor.set_on_status_change(
        Some(fn(status) {
          js_notify_status_change(handle, encode_sync_status(status))
        }),
      )
      js_notify_status_change(
        handle,
        encode_sync_status(h.editor.get_sync_status()),
      )
    }
    None => ()
  }
}

///|
/// Serialize a SyncStatus to the JSON string documented on
/// ws_set_status_callback. JSON escaping is handled by the core
/// encoder, so peer_id values with special characters (':', '"', etc.)
/// round-trip cleanly.
fn encode_sync_status(status : @editor.SyncStatus) -> String {
  let j : Json = match status {
    Disconnected => Json::object({ "tag": Json::string("disconnected") })
    Idle => Json::object({ "tag": Json::string("idle") })
    Recovering(peer_id~, attempt~) =>
      Json::object({
        "tag": Json::string("recovering"),
        "peer_id": Json::string(peer_id),
        "attempt": Json::number(attempt.to_double()),
      })
    Error(reason~) =>
      match reason {
        Exhausted(peer_id~) =>
          Json::object({
            "tag": Json::string("error"),
            "reason": Json::string("exhausted"),
            "peer_id": Json::string(peer_id),
          })
        TargetLeft(peer_id~) =>
          Json::object({
            "tag": Json::string("error"),
            "reason": Json::string("target_left"),
            "peer_id": Json::string(peer_id),
          })
      }
  }
  j.stringify()
}

///|
/// Low-level JS bridge: schedule a watchdog timer.
/// The host JS owns timer delivery via `globalThis.__canopy_schedule_watchdog`.
/// A typical binding is:
///   globalThis.__canopy_schedule_watchdog = (handle, requestId, timeoutMs) =>
///     setTimeout(() => lambdaModule.ws_on_watchdog_fire(handle, requestId), timeoutMs);
/// where `lambdaModule` is the imported ESM namespace for the compiled
/// `ffi/lambda` package (named export `ws_on_watchdog_fire`). This
/// indirection avoids assuming an intra-module symbol resolution for the
/// setTimeout callback.
extern "js" fn js_schedule_watchdog(
  handle : Int,
  request_id : Int,
  timeout_ms : Int,
) -> Unit =
  #|(handle, requestId, timeoutMs) => {
  #|  if (typeof globalThis.__canopy_schedule_watchdog === "function") {
  #|    globalThis.__canopy_schedule_watchdog(handle, requestId, timeoutMs);
  #|  }
  #|}

///|
/// Low-level JS bridge: notify the JS side of a SyncStatus transition.
/// `encoded` is the tagged string produced by `encode_sync_status`.
extern "js" fn js_notify_status_change(handle : Int, encoded : String) -> Unit =
  #|(handle, encoded) => {
  #|  if (typeof globalThis.__canopy_on_status_change === "function") {
  #|    globalThis.__canopy_on_status_change(handle, encoded);
  #|  }
  #|}
