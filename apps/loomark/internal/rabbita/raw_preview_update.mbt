///|
/// Feature update adapter. The pure model transition decides adoption or
/// recovery; this shell executes the resulting Runtime command.
fn update_raw_preview_msg(
  msg : RawPreviewMsg,
  model : DriverModel,
  raw_input_coordinator : RawInputCoordinator,
  runtime : RawPreviewRuntime?,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, @cmd.Cmd) {
  match (runtime, msg) {
    (None, _) => (model, @rabbita_runtime.none)
    (Some(runtime), ProjectionCompleted(request_id, expected, raw, source)) => {
      let (claimed, result, next_command) = runtime.complete(
        request_id, expected, raw, source, emit,
      )
      guard claimed && result is Some(result) else {
        return (model, next_command)
      }
      let current_source = raw_input_coordinator
        .fast_source_value()
        .unwrap_or(model.document.source())
      let demanded = preview_requested(model)
      let speculative = demanded && current_source != model.document.source()
      let (raw_preview, decision) = update_raw_preview(
        result,
        model.raw_preview,
        current_source~,
        demanded~,
        speculative~,
      )
      match decision {
        Rejected => (model, next_command)
        Stopped => {
          runtime.stop()
          ({ ..model, raw_preview, }, @rabbita_runtime.none)
        }
        Recover(source) =>
          ({ ..model, raw_preview, }, runtime.recover(source, emit))
        Adopted => {
          let projection_error = model.error_code == Some("projection-failed") ||
            model.error_code == Some("projection-pending")
          (
            {
              ..model,
              semantic_document: None,
              raw_preview,
              semantic_read_count: model.semantic_read_count + 1,
              error: if projection_error {
                None
              } else {
                model.error
              },
              error_code: if projection_error {
                None
              } else {
                model.error_code
              },
              error_operation: if projection_error {
                None
              } else {
                model.error_operation
              },
            },
            next_command,
          )
        }
      }
    }
  }
}
