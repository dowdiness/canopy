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
/// Downloads BIZ UDMincho into the HTTP cache while the page is idle once a
/// Japanese document (marked `lang="ja"`) appears, since its Preview needs it.
/// `public/_headers` keeps the versioned file immutable. The path matches
/// styles/tailwind.css.
pub extern "js" fn warm_japanese_fonts() -> Unit =
  #| () => {
  #|   if (typeof fetch !== "function") return
  #|   const idle = callback => typeof requestIdleCallback === "function"
  #|     ? requestIdleCallback(callback, { timeout: 3000 })
  #|     : setTimeout(callback, 1500)
  #|   let warmed = false
  #|   const warm = () => {
  #|     if (warmed) return
  #|     warmed = true
  #|     fetch("./fonts/BIZUDMincho-Regular-1.06.woff2")
  #|       .then(response => response.arrayBuffer()).catch(() => {})
  #|   }
  #|   const japaneseDocument = () => document.querySelector('[lang="ja"]') !== null
  #|   idle(() => {
  #|     if (japaneseDocument()) warm()
  #|   })
  #|   const observer = new MutationObserver(() => {
  #|     if (!japaneseDocument()) return
  #|     observer.disconnect()
  #|     idle(warm)
  #|   })
  #|   observer.observe(document.documentElement, {
  #|     subtree: true,
  #|     attributes: true,
  #|     attributeFilter: ["lang"],
  #|   })
  #| }
