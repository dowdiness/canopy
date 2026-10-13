///|
/// Missing native DOM accessor; resolve the supplied element's own document.
pub extern "js" fn element_document(element : @dom.Element) -> @dom.Document =
  #| element => element.ownerDocument
