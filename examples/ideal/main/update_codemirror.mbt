///|
fn handle_codemirror(
  emit : Emit[Msg],
  msg : Msg,
  model : Model,
) -> (Cmd, Model)? {
  let _ = emit
  match msg {
    CmMounted => {
      let new_model = { ..model, mounted: true }
      Some((sync_after_external_crdt_change(new_model), new_model))
    }
    CmDocChanged(text) => {
      model.editor.set_text_and_record(text, js_now_ms())
      let new_model = refresh({
        ..model,
        next_timestamp: model.next_timestamp + 1,
      })
      let actual_text = new_model.editor.get_text()
      let sync_cmd = if actual_text != text {
        @cm.set_doc(model.cm_id, actual_text)
      } else {
        none
      }
      let cmd = @rabbita.batch([
        sync_cmd,
        @rabbita.effect(fn() { js_after_local_text_edit() }),
      ])
      Some((cmd, new_model))
    }
    CmSelectionChanged(range) => {
      js_after_cm_selection_changed(range.from, range.to)
      Some((none, model))
    }
    CmFocusChanged(_) => Some((none, model))
    _ => None
  }
}
