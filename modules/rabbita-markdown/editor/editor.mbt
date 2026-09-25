///|
/// Activate a document's input and preview together. The host still owns the
/// accepted text and decides whether the preview is visible.
pub fn activate(
  area : @text_area.TextArea,
  engine : @preview.PreviewEngine,
  generation : Int,
  text : String,
  preview_visible : Bool,
  emit : @rabbita.Emit[@preview.Event],
) -> (@preview.State, @rabbita.Cmd) {
  let input = @preview.Input(generation, text)
  let (preview, activated) = engine.activate(input)
  let (preview, requested) = if preview_visible {
    engine.request(preview, input, emit)
  } else {
    (preview, @cmd.none)
  }
  (preview, @cmd.batch([area.initialize(text), activated, requested]))
}

///|
/// Call only after the host has accepted the change and supplied its new text.
/// In particular, a rejected edit must never reach the incremental parser.
pub fn accepted(
  area : @text_area.TextArea,
  engine : @preview.PreviewEngine,
  preview : @preview.State,
  generation : Int,
  text : String,
  change : @text_change.TextChange,
  emit : @rabbita.Emit[@preview.Event],
) -> (@preview.State, @rabbita.Cmd) {
  area.accepted(text)
  engine.document_changed(
    preview,
    @preview.Input(generation, text),
    change,
    emit,
  )
}

///|
/// Keep a healthy parser while switching between visible preview modes;
/// request it only on entry and suspend it only on exit.
pub fn visibility_changed(
  engine : @preview.PreviewEngine,
  preview : @preview.State,
  generation : Int,
  text : String,
  was_visible : Bool,
  is_visible : Bool,
  emit : @rabbita.Emit[@preview.Event],
) -> (@preview.State, @rabbita.Cmd) {
  let input = @preview.Input(generation, text)
  if !was_visible && is_visible {
    engine.request(preview, input, emit)
  } else if was_visible && !is_visible {
    engine.suspend(preview, input)
  } else {
    (preview, @cmd.none)
  }
}
