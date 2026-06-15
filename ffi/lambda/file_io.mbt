// File load/save FFI — bridges the language-agnostic `@io` transport to this
// editor's existing text I/O. Outbound goes through the injected `@io.FileHost`
// (typed DI, mirroring how `ws.mbt` calls methods on an injected JsWebSocket);
// inbound delivery is handle-routed exactly like `ws_on_message`.

///|
/// Inject the JS host that performs the actual picker/write. Call once at
/// startup: `lambdaModule.register_file_host({ save, open })`.
pub fn register_file_host(host : @io.FileHost) -> Unit {
  @io.register_host(host)
}

///|
/// Open a file picker and load the chosen file's text into editor `handle`.
/// Asynchronous — returns immediately; the host reads the file and calls
/// `on_file_opened` below. A cancelled picker is a no-op.
pub fn load_file(handle : Int) -> Unit {
  @io.request_open(handle)
}

///|
/// Host callback: replace editor `handle`'s document with loaded file
/// `content`, recording the change so the load is undoable (same path as
/// `LoadExample` / CodeMirror edits in the app). `timestamp_ms` orders the
/// undo entry. A miss on `handle` (editor already destroyed) drops the content.
pub fn on_file_opened(
  handle : Int,
  content : String,
  timestamp_ms : Int,
) -> Unit {
  set_text_and_record(handle, content, timestamp_ms)
}

///|
/// Save editor `handle`'s current text to a file named `suggested_name`.
pub fn save_file(handle : Int, suggested_name : String) -> Unit {
  @io.save_text(get_text(handle), suggested_name)
}
