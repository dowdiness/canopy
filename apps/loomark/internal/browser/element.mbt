///|
/// Missing native DOM accessor; resolve the supplied element's own document.
pub extern "js" fn element_document(element : @dom.Element) -> @dom.Document =
  #| element => element.ownerDocument

///|
/// A shadow root that page scripts and selectors cannot reach.
pub extern "js" fn attach_closed_shadow(element : @dom.Element) -> @dom.Node =
  #| element => element.attachShadow({ mode: "closed" })

///|
/// Missing native observe option. A textarea whose padding grows with its
/// height keeps its content box, so watch the border box instead.
pub extern "js" fn observe_border_box(
  observer : @dom.ResizeObserver,
  element : @dom.Element,
) -> Unit =
  #| (observer, element) => observer.observe(element, { box: "border-box" })
