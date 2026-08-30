///|
/// DOM helpers retained from the copied RUI Sidebar implementation.
fn ui_has_global(name : String) -> Bool {
  let value : @js.Value = @js.globalThis.get_with_string(name)
  !value.is_undefined() && !value.is_null()
}

///|
fn ui_has_window() -> Bool {
  ui_has_global("window")
}

///|
fn ui_has_document() -> Bool {
  ui_has_global("document")
}

///|
fn ui_element_contains_target(
  root : @dom.Element,
  target : @dom.EventTarget,
) -> Bool {
  if target.to_node() is Some(node) {
    root.contains(node)
  } else {
    false
  }
}

///|
fn ui_focus_element_without_scroll(element : @dom.Element) -> Unit {
  if element.to_html_element() is Some(html_element) {
    html_element.focus_with_options(prevent_scroll=true)
  }
}

///|
fn ui_element_is_enabled(element : @dom.Element) -> Bool {
  !element.has_attribute("disabled") &&
  element.get_attribute("aria-disabled").unwrap_or("") != "true"
}
