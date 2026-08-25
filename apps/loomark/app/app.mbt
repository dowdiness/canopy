///|
pub fn app() -> @rabbita.Val[@rabbita.Html] {
  let (model, emit) = @rabbita.create_state_with_init(
    init=initial_state,
    update~,
  )
  model.view(model => view(model, emit))
}
