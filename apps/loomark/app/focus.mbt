///|
/// Run after rendering so activation has mounted and initialized its textarea.
/// Preview keeps keyboard users at the selected mode control instead.
fn focus_editor() -> Unit {
  guard @dom.document().get_element_by_id("loomark-root").to_option()
    is Some(root) else {
    return
  }
  guard root.query_selector("textarea") is Some(editor) else { return }
  guard !editor.has_attribute("disabled") && editor.closest("[inert]") is None else {
    return
  }
  let target = if editor.get_client_rects().length() > 0 {
    Some(editor)
  } else {
    root.query_selector("[role=\"tab\"][aria-selected=\"true\"]")
  }
  if target is Some(element) && element.to_html_element() is Some(element) {
    element.focus_with_options(prevent_scroll=true)
  }
}

///|
fn focus_more_actions() -> Unit {
  if @dom.document().get_element_by_id("loomark-more-actions").to_option()
    is Some(element) &&
    element.to_html_element() is Some(element) {
    element.focus_with_options(prevent_scroll=true)
  }
}

///|
fn focus_delete_action(lifecycle_key : String) -> Unit {
  guard @dom.document()
    .get_element_by_id("loomark-delete-" + lifecycle_key)
    .to_option()
    is Some(target) else {
    return
  }
  if target.get_client_rects().length() > 0 &&
    target.closest("[inert]") is None &&
    target.to_html_element() is Some(element) {
    element.focus_with_options(prevent_scroll=true)
  }
}
