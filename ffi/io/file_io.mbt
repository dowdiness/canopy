// Browser file I/O transport, expressed entirely through `@js` — no bespoke
// `extern "js"` per host method.
//
// The host is a plain JS object `{ save(content, name), open(handle) }`
// injected once via `register_host`. `save_text` / `request_open` invoke its
// methods; with no host registered they no-op. The `handle` carried by
// `request_open` is echoed back by the host to the language module's exported
// `on_file_opened`, so this layer stays language-agnostic and a cancelled
// picker needs no bookkeeping.
//
// Text-only contract: `content` is a UTF-8 string; binary files are out of
// scope. Error/cancel reporting is the host's concern, surfaced to the app
// through the language module's inbound callbacks (see ffi/lambda).

///|
/// Process-wide host. `None` until the JS side injects one via `register_host`.
let host : Ref[@js.Any?] = { val: None }

///|
/// Inject the JS host capability: `{ save(content, name), open(handle) }`.
/// Call once at startup, before any `save_text` / `request_open`.
pub fn register_host(h : @js.Any) -> Unit {
  host.val = Some(h)
}

///|
/// Ask the host to write `content` to a file named `suggested_name`.
/// No-op (the intent is silently dropped) if no host is registered.
pub fn save_text(content : String, suggested_name : String) -> Unit {
  match host.val {
    Some(h) =>
      h.call("save", [@js.any(content), @js.any(suggested_name)]) |> ignore
    None => ()
  }
}

///|
/// Ask the host to open a file picker for editor `handle`. On success the host
/// calls the language module's exported `on_file_opened(handle, content, ...)`.
/// No-op if no host is registered.
pub fn request_open(handle : Int) -> Unit {
  match host.val {
    Some(h) => h.call("open", [@js.any(handle)]) |> ignore
    None => ()
  }
}
