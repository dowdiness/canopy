///|
/// The client rectangles of the code units `start..end` in a text node.
pub extern "js" fn text_range_rects(
  text : @dom.Node,
  start : Int32,
  end : Int32,
) -> @dom.DOMRectList =
  #| (text, start, end) => {
  #|   const range = text.ownerDocument.createRange();
  #|   range.setStart(text, start);
  #|   range.setEnd(text, end);
  #|   return range.getClientRects();
  #| }

///|
pub extern "js" fn replace_text_data(
  text : @dom.Node,
  offset : Int32,
  count : Int32,
  data : String,
) -> Unit =
  #| (text, offset, count, data) => text.replaceData(offset, count, data)
