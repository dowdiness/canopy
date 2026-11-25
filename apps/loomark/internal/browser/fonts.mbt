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

///|
/// Runs `callback` once `fonts`, the document's font face set, has no face
/// left loading.
extern "js" fn when_fonts_ready(
  fonts : @dom.EventTarget,
  callback : () -> Unit,
) -> Unit =
  #| (fonts, callback) => { fonts.ready.then(() => callback()) }

///|
priv suberror FontsLoaded {
  FontsLoaded(@dom.EventTarget, @cmd.Cmd)
}

///|
/// Call `loaded` whenever font faces finish loading, such as a late web font
/// or a face for characters not drawn before, until the returned function
/// stops it. `fonts` is the document's `FontFaceSet`. Faces are followed from
/// `loading` to `ready`, because WebKit never sends `loadingdone`.
pub fn on_fonts_loaded(
  fonts : @dom.EventTarget,
  loaded : () -> Unit,
) -> () -> Unit {
  let mut wait = Scheduled
  let listener : @dom.Listener = _ => {
    when_fonts_ready(fonts, () => if wait is Scheduled { loaded() })
  }
  fonts.add_event_listener("loading", listener)
  () => {
    wait = Released
    fonts.remove_event_listener("loading", listener)
  }
}

///|
/// Send `loaded` whenever font faces finish loading, as `on_fonts_loaded`
/// reports them, while the subscription is active.
pub fn fonts_loaded(fonts : @dom.EventTarget, loaded : @cmd.Cmd) -> @sub.Sub {
  @sub.custom_sub("browser.fonts_loaded", Local, FontsLoaded(fonts, loaded), (
    payload,
    scheduler,
  ) => {
    guard payload is FontsLoaded(fonts, tagger) else { return None }
    let mut tagger = tagger
    let stop = on_fonts_loaded(fonts, () => scheduler.queue_command(tagger))
    Some({
      unload: _ => stop(),
      update_tagger: payload => {
        if payload is FontsLoaded(_, next) {
          tagger = next
        }
      },
    })
  })
}
