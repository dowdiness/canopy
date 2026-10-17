///|
/// Downloads the Japanese faces into the HTTP cache while the page is idle.
///
/// Warming lets IBM Plex Sans JP arrive before Japanese text does, so the
/// writing area rarely swaps faces while someone writes. `document.fonts.load`
/// would also start the face's display timeline, so the warm-up only fills the
/// cache, where `public/_headers` keeps the versioned files immutable. Plex is
/// warmed for Japanese-language browsers or
/// a Japanese document (marked `lang="ja"`); BIZ UDMincho only for a Japanese
/// document, whose Preview needs it. Paths match styles/tailwind.css.
pub extern "js" fn warm_japanese_fonts() -> Unit =
  #| () => {
  #|   if (typeof fetch !== "function") return
  #|   const idle = callback => typeof requestIdleCallback === "function"
  #|     ? requestIdleCallback(callback, { timeout: 3000 })
  #|     : setTimeout(callback, 1500)
  #|   const warmed = new Set()
  #|   const warm = path => {
  #|     if (warmed.has(path)) return
  #|     warmed.add(path)
  #|     fetch(path).then(response => response.arrayBuffer()).catch(() => {})
  #|   }
  #|   const warmFor = japaneseDocument => {
  #|     warm("./fonts/IBMPlexSansJP-Regular-1.004.woff2")
  #|     if (japaneseDocument) warm("./fonts/BIZUDMincho-Regular-1.06.woff2")
  #|   }
  #|   const japaneseDocument = () => document.querySelector('[lang="ja"]') !== null
  #|   const languages = navigator.languages || [navigator.language]
  #|   idle(() => {
  #|     if (japaneseDocument()) warmFor(true)
  #|     else if (languages.some(language => /^ja(-|$)/i.test(language))) warmFor(false)
  #|   })
  #|   const observer = new MutationObserver(() => {
  #|     if (!japaneseDocument()) return
  #|     observer.disconnect()
  #|     idle(() => warmFor(true))
  #|   })
  #|   observer.observe(document.documentElement, {
  #|     subtree: true,
  #|     attributes: true,
  #|     attributeFilter: ["lang"],
  #|   })
  #| }
