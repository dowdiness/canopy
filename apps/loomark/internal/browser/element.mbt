///|
/// Missing native DOM accessor; resolve the supplied element's own document.
pub extern "js" fn element_document(element : @dom.Element) -> @dom.Document =
  #| element => element.ownerDocument

///|
/// A shadow root that page scripts and selectors cannot reach.
pub extern "js" fn attach_closed_shadow(element : @dom.Element) -> @dom.Node =
  #| element => element.attachShadow({ mode: "closed" })
