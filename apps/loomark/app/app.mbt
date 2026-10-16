///|
pub fn app() -> @rabbita.Val[@rabbita.Html] {
  let editor = @editor.MarkdownEditor::MarkdownEditor(EDITOR_TEXT_ID)
  let (notifications, toasts) = @rui.sonner_host(
    max_toasts=1,
    position="bottom-left",
    class="loomark-notifications",
  )
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
    update=(model, msg, emit) => {
      let before = error_messages(model)
      let (next, command) = update(model, msg, emit, editor)
      let commands = [command]
      let after = error_messages(next)
      if !before.is_empty() && after.is_empty() {
        commands.push(toasts.dismiss_all())
      }
      for message in after {
        if !before.contains(message) {
          commands.push(toasts.show(title=message, variant=ToastDestructive))
        }
      }
      (next, @cmd.batch(commands))
    },
    subscriptions=(current, emit) => {
      subscriptions(current, emit, viewport_subscription)
    },
  )
  view(model, emit, editor).map2(notifications, (editor, notifications) => {
    @html.fragment([editor, notifications])
  })
}
