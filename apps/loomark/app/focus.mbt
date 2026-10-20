///|
/// Where focus belongs once the editor has rendered.
priv enum FocusTarget {
  /// The current mode's element: the textarea, or the Preview tab.
  CurrentMode
  /// Focus Mode makes the Preview tab inert; its toggle stands in.
  FocusModeToggle
  /// An inert editor cannot hold focus, so Recent documents receives it.
  RecentDocuments
}

///|
fn editor_focus_target(
  mode : EditorMode,
  editor_inert~ : Bool,
  mode_element_inert~ : Bool,
) -> FocusTarget {
  if editor_inert {
    RecentDocuments
  } else if mode == Preview && mode_element_inert {
    FocusModeToggle
  } else {
    CurrentMode
  }
}

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
    let document = @dom.document()
    let mode_element = document
      .get_element_by_id(editor_focus_id(mode))
      .to_option()
    let target = editor_focus_target(
      mode,
      editor_inert=editor_is_inert(document),
      mode_element_inert=mode_element is Some(element) && is_inert(element),
    )
    match target {
      CurrentMode => if mode_element is Some(element) { focus_element(element) }
      FocusModeToggle =>
        if document.get_element_by_id("loomark-focus-toggle").to_option()
          is Some(toggle) {
          focus_element(toggle)
        }
      RecentDocuments => scheduler.queue_command(focus_recent_documents())
    }
  })
}

///|
/// Leave focus where it is unless the editor holding it has become inert.
fn retain_editor_focus_after_render() -> @cmd.Cmd {
  @cmd.custom_cmd(kind=AfterRender, scheduler => {
    if editor_is_inert(@dom.document()) {
      scheduler.queue_command(focus_recent_documents())
    }
  })
}

///|
fn focus_recent_documents() -> @cmd.Cmd {
  @sidebar.sidebar_focus("loomark-document-sidebar")
}

///|
fn editor_is_inert(document : @dom.Document) -> Bool {
  document.get_element_by_id("loomark-editor").to_option() is Some(editor) &&
  is_inert(editor)
}

///|
fn is_inert(element : @dom.Element) -> Bool {
  element.closest("[inert]") is Some(_)
}

///|
/// Native focus remains an effect even when the resolved element is explicit.
fn focus_element(element : @dom.Element) -> Unit {
  guard !element.has_attribute("disabled") &&
    !is_inert(element) &&
    element.get_client_rects().length() > 0 &&
    element.to_html_element() is Some(target) else {
    return
  }
  target.focus_with_options(prevent_scroll=true)
}

///|
/// An Example is read from its beginning, unlike writing that resumes at its end.
fn caret_at_start_after_render() -> @cmd.Cmd {
  @cmd.custom_cmd(kind=AfterRender, _ => {
    if editor_text_area() is Some(area) {
      area.set_selection_range(0, 0)
      area.as_element().set_scroll_top(0)
    }
  })
}
