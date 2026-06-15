// Non-js stub. Browser file I/O is host-driven and has no equivalent here, so
// these no-op and keep native/wasm builds linking. The public surface matches
// `file_io_js.mbt` exactly (same as transport_ws's JsWebSocket native stub) so
// callers compile on every target.

///|
pub struct FileHost(Int)

///|
pub fn register_host(_h : FileHost) -> Unit {

}

///|
pub fn save_text(_content : String, _suggested_name : String) -> Unit {

}

///|
pub fn request_open(_handle : Int) -> Unit {

}
