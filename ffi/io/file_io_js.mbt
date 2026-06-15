// Browser file I/O transport (js target), via typed dependency injection.
//
// The host capability (open a picker / write a file) is a JS object injected
// once with `register_host`, mirroring how `transport_ws` receives a JS
// `JsWebSocket` and calls methods on it — no `globalThis` string lookups. The
// `handle` carried out by `request_open` is echoed back by the host to the
// language module's exported `on_file_opened(handle, content, ...)`, so this
// layer stays language-agnostic and a cancelled picker is a pure JS no-op.
//
// Text-only contract: `content` is a UTF-8 string. Binary files are out of
// scope. Error/cancel reporting is the host's concern and is surfaced to the
// app through the language module's inbound callbacks (see ffi/lambda).

///|
/// Opaque handle to the JS host object. Expected shape:
/// `{ save(content, name), open(handle) }`.
#external
pub type FileHost

///|
/// Process-wide host. `None` until the JS side injects one via `register_host`.
let host : Ref[FileHost?] = { val: None }

///|
/// Inject the JS host capability. Call once at startup, before any
/// `save_text` / `request_open`.
pub fn register_host(h : FileHost) -> Unit {
  host.val = Some(h)
}

///|
/// Ask the host to write `content` to a file named `suggested_name`.
/// No-op (the user's intent is silently dropped) if no host is registered.
pub fn save_text(content : String, suggested_name : String) -> Unit {
  match host.val {
    Some(h) => h.save(content, suggested_name)
    None => ()
  }
}

///|
/// Ask the host to open a file picker for editor `handle`. On success the host
/// calls the language module's exported `on_file_opened(handle, content, ...)`.
/// No-op if no host is registered.
pub fn request_open(handle : Int) -> Unit {
  match host.val {
    Some(h) => h.open(handle)
    None => ()
  }
}

///|
extern "js" fn FileHost::save(
  self : FileHost,
  content : String,
  name : String,
) -> Unit =
  #|(host, content, name) => {
  #|  host.save(content, name);
  #|}

///|
extern "js" fn FileHost::open(self : FileHost, handle : Int) -> Unit =
  #|(host, handle) => {
  #|  host.open(handle);
  #|}
