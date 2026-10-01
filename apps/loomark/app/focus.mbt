///|
/// Resolve the current node after rendering; never retain a node across the render.
fn focus_after_render(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=AfterRender, _ => {
    if @dom.document().get_element_by_id(id).to_option() is Some(element) {
      focus_element(element)
    }
  })
}

///|
/// Native focus remains an effect even when the resolved element is explicit.
fn focus_element(element : @dom.Element) -> Unit {
  guard !element.has_attribute("disabled") &&
    element.closest("[inert]") is None &&
    element.get_client_rects().length() > 0 else {
    return
  }
  if element.to_html_element() is Some(target) {
    target.focus_with_options(prevent_scroll=true)
  }
}
