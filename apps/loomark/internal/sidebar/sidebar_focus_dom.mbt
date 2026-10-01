// DOM focus shell extracted from the copied RUI Sidebar; see PROVENANCE and LICENSE.
// Element discovery, browser events, and deferred native focus remain here.

///|
#cfg(target="js")
fn sidebar_document_elements(selector : String) -> Array[@dom.Element] {
  let elements : Array[@dom.Element] = []
  if !ui_has_document() {
    return elements
  }
  let nodes = @dom.document().query_selector_all(selector)
  for index in 0..<nodes.get_length().to_int() {
    if nodes.item(index.to_double()).to_option() is Some(node) &&
      node.to_element() is Some(element) {
      elements.push(element)
    }
  }
  elements
}

///|
#cfg(target="js")
fn sidebar_element_is_visible(element : @dom.Element) -> Bool {
  if element.get_client_rects().length() == 0 ||
    element.closest("[inert]") is Some(_) ||
    !ui_element_is_enabled(element) {
    return false
  }
  if ui_has_window() {
    let style = @dom.window().get_computed_style(element)
    style.get_property_value("display") != "none" &&
    style.get_property_value("visibility") != "hidden"
  } else {
    true
  }
}

///|
#cfg(target="js")
fn sidebar_focusable_elements(root : @dom.Element) -> Array[@dom.Element] {
  root
  .query_selector_all(SidebarFocusableSelector)
  .iter()
  .filter(sidebar_element_is_visible)
  .collect()
}

///|
#cfg(target="js")
fn sidebar_focus_edge(root : @dom.Element, last : Bool) -> Unit {
  let items = sidebar_focusable_elements(root)
  let target = match sidebar_focus_index(items.length(), -1, last) {
    Some(index) => items[index]
    None => root
  }
  ui_focus_element_without_scroll(target)
  if target.is_same_node(root.as_node()) && ui_has_window() {
    ignore(
      @dom.window().request_animation_frame(_ => {
        if !root.get_is_connected() ||
          root.get_attribute("data-mobile-state").unwrap_or("") != "open" ||
          !ui_has_document() {
          return
        }
        let document = @dom.document()
        guard document.get_active_element() is Some(active) &&
          active.is_same_node(root.as_node()) else {
          return
        }
        let refreshed = sidebar_focusable_elements(root)
        if sidebar_focus_index(refreshed.length(), -1, last) is Some(index) {
          ui_focus_element_without_scroll(refreshed[index])
        }
      }),
    )
  }
}

///|
#cfg(target="js")
fn sidebar_trap_focus(event : @dom.KeyboardEvent) -> Bool {
  if event.key() != "Tab" ||
    event.alt_key() ||
    event.ctrl_key() ||
    event.meta_key() {
    return false
  }
  guard event.current_target().to_option() is Some(current) &&
    current.to_element() is Some(root) else {
    return false
  }
  if root.get_attribute("aria-hidden").unwrap_or("") == "true" {
    return false
  }
  let items = sidebar_focusable_elements(root)
  if items.length() == 0 {
    ui_focus_element_without_scroll(root)
    return true
  }
  let active = if ui_has_document() {
    @dom.document().get_active_element()
  } else {
    None
  }
  let mut active_index = -1
  if active is Some(active) {
    for index, item in items {
      if item.is_same_node(active.as_node()) {
        active_index = index
      }
    }
  }
  if sidebar_focus_index(items.length(), active_index, event.shift_key())
    is Some(index) {
    ui_focus_element_without_scroll(items[index])
  }
  true
}
