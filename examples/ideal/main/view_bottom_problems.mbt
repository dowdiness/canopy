///|
fn view_problems(model : Model) -> Html {
  guard model.workspace.bottom_visible else {
    return @html.div(
      class="bottom-content",
      attrs=bottom_panel_attrs(Problems),
      ([] : Array[Html]),
    )
  }
  let errors = model.editor.get_errors()
  if errors.is_empty() {
    @html.div(class="bottom-content", attrs=bottom_panel_attrs(Problems), [
      @html.span(class="no-problems", [@html.text("No problems found")]),
    ])
  } else {
    let items = errors.map(fn(err) {
      @html.div(class="problem-item", [
        @html.span(class="problem-text", [@html.text(err)]),
      ])
    })
    @html.div(
      class="bottom-content problems-list",
      attrs=bottom_panel_attrs(Problems),
      items,
    )
  }
}
