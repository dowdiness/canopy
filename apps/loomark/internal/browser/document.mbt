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

///|
/// Viewport height of the middle of the characters between two offsets of a
/// laid-out text node. Their box spans the glyphs, not the whole line.
pub extern "js" fn document_text_middle(
  document : @dom.Document,
  text : @dom.Node,
  start : Int,
  end : Int,
) -> Double =
  #| (document, text, start, end) => {
  #|   const range = document.createRange();
  #|   range.setStart(text, start);
  #|   range.setEnd(text, end);
  #|   const rect = range.getBoundingClientRect();
  #|   return rect.top + rect.height / 2;
  #| }
