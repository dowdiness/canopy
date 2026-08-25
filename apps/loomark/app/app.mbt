///|
pub fn app() -> @rabbita.Val[@rabbita.Html] {
  let preview_engine = @preview.PreviewEngine::new()
  let (model, emit) = @rabbita.create_state_with_init(init=initial_state, update=(
    model,
    msg,
    emit,
  ) => {
    update(model, msg, emit, input_text => {
      preview_engine.prepare(
        input_text,
        result=emit.map(result => PreviewPrepared(input_text, result)),
      )
    })
  })
  model.view(model => view(model, emit))
}
