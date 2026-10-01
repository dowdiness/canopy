///|
/// Resolve the requested element only after rendering; DOM readiness belongs here.
fn focus_element(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=AfterRender, _ => {
    guard @dom.document().get_element_by_id(id).to_option() is Some(target) else {
      return
    }
    guard !target.has_attribute("disabled") &&
      target.closest("[inert]") is None &&
      target.get_client_rects().length() > 0 else {
      return
    }
    if target.to_html_element() is Some(element) {
      element.focus_with_options(prevent_scroll=true)
    }
  })
}
