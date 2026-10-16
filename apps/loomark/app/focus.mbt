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
/// Resolve the presentation after rendering, including recovery-driven activation.
fn focus_editor_after_render(mode : EditorMode) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=AfterRender, scheduler => {
    if @dom.document().get_element_by_id("loomark-editor").to_option()
      is Some(editor) &&
      editor.closest("[inert]") is Some(_) {
      scheduler.queue_command(
        @sidebar.sidebar_focus("loomark-document-sidebar"),
      )
      return
    }
    let id = editor_focus_id(mode)
    if @dom.document().get_element_by_id(id).to_option() is Some(element) {
      if mode == Preview && element.closest("[inert]") is Some(_) {
        if @dom.document().get_element_by_id("loomark-focus-toggle").to_option()
          is Some(toggle) {
          focus_element(toggle)
        }
      } else {
        focus_element(element)
      }
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
