///|
pub fn app() -> @rabbita.Val[@rabbita.Html] {
  let editor = @editor.MarkdownEditor::MarkdownEditor(EDITOR_TEXT_ID)
  let initial_compact = compact_viewport(@browser.viewport_width())
  // Resolve stable browser handles once at the composition boundary.
  let window = @dom.window()
  let viewport_subscription = if window.get_visual_viewport() is Some(viewport) &&
    @dom.document().get_document_element() is Some(root) &&
    root.to_html_element() is Some(root) {
    @viewport.visual_viewport_subscription(window, viewport, root)
  } else {
    @sub.none
  }
  let (model, emit) = @rabbita.create_state_with_init(
    init=emit => initial_state(emit, initial_compact),
    update=(model, msg, emit) => update(model, msg, emit, editor),
    subscriptions=(current, emit) => {
      subscriptions(current, emit, viewport_subscription)
    },
  )
  view(model, emit, editor)
}
