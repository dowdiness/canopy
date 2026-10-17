///|
/// The document's `FontFaceSet`.
#external
pub type FontFaceSet

///|
pub extern "js" fn document_font_faces(document : @dom.Document) -> FontFaceSet =
  #| document => document.fonts

///|
/// Loads the faces that `font` needs for `text`; text without characters in
/// their unicode ranges loads nothing.
pub extern "js" fn load_font_faces(
  faces : FontFaceSet,
  font : String,
  text : String,
) -> Unit =
  #| (faces, font, text) => { faces.load(font, text).catch(() => {}) }

///|
/// Whether the browser asks pages to reduce data use (Save-Data).
pub extern "js" fn save_data_requested(window : @dom.Window) -> Bool =
  #| window => window.navigator.connection?.saveData === true

///|
/// Runs `callback` once the page is idle, or after `timeout_ms` at the latest.
pub extern "js" fn request_idle(
  window : @dom.Window,
  timeout_ms : Int,
  callback : () -> Unit,
) -> Unit =
  #| (window, timeout, callback) => {
  #|   if (typeof window.requestIdleCallback === "function") {
  #|     window.requestIdleCallback(() => callback(), { timeout })
  #|   } else {
  #|     window.setTimeout(() => callback(), 0)
  #|   }
  #| }

///|
/// Runs `callback` once the faces that are loading have arrived.
pub extern "js" fn when_font_faces_ready(
  faces : FontFaceSet,
  callback : () -> Unit,
) -> Unit =
  #| (faces, callback) => { faces.ready.then(() => callback()) }
