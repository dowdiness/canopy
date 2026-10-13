///|
/// Used only while measuring an element in an active browser document.
pub extern "js" fn document_window(document : @dom.Document) -> @dom.Window =
  #| document => document.defaultView

///|
pub extern "js" fn document_fonts(document : @dom.Document) -> @dom.EventTarget =
  #| document => document.fonts

///|
pub extern "js" fn document_timeline_time(
  document : @dom.Document,
) -> @dom_js.Nullable[Double] =
  #| document => document.timeline.currentTime
