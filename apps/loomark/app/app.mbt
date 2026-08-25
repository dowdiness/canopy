///|
pub fn app() -> @rabbita.Val[@rabbita.Html] {
  let text_area = @text_area.TextArea::TextArea("loomark-text")
  let (model, emit) = @rabbita.create_state_with_init(init=initial_state, update=(
    model,
    msg,
    emit,
  ) => update(model, msg, emit, text_area))
  model.view(model => view(model, emit, text_area))
}
