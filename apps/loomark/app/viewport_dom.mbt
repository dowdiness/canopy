///|
/// Missing Rabbita DOM accessors only. No lookup, layout policy, scheduling,
/// or application state belongs in this FFI file.
extern "js" fn element_document(element : @dom.Element) -> @dom.Document =
  #| element => element.ownerDocument

///|
/// Used only while measuring an element in an active browser document.
extern "js" fn document_window(document : @dom.Document) -> @dom.Window =
  #| document => document.defaultView

///|
/// Preserve native CSS numeric conversion, including NaN for nonnumeric values.
extern "js" fn css_pixels(
  style : @dom.CSSStyleDeclaration,
  property : String,
) -> Double =
  #| (style, property) => parseFloat(style.getPropertyValue(property))

///|
extern "js" fn window_outer_height(window : @dom.Window) -> Double =
  #| window => window.outerHeight

///|
extern "js" fn visual_viewport_scale(viewport : @dom.VisualViewport) -> Double =
  #| viewport => viewport.scale
