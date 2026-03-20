///|
fn view_bottom_tabs(dispatch : Dispatch[Msg], model : Model) -> Html {
  let tabs : Array[(BottomTab, String)] = [
    (Problems, "Problems"),
    (OpLog, "Op Log"),
    (CrdtState, "CRDT State"),
    (Graphviz, "Graphviz"),
  ]
  @html.div(
    class="bottom-tabs",
    tabs.map(fn(pair) {
      let (tab, label) = pair
      let class_name = if model.bottom_tab == tab {
        "tab active"
      } else {
        "tab"
      }
      @html.button(class=class_name, on_click=dispatch(SelectBottomTab(tab)), [
        @html.text(label),
      ])
    }),
  )
}

///|
fn view_problems(model : Model) -> Html {
  let errors = model.editor.get_errors()
  if errors.is_empty() {
    @html.div(class="bottom-content", [
      @html.span(class="no-problems", [@html.text("No problems found")]),
    ])
  } else {
    let items = errors.map(fn(err) {
      @html.div(class="problem-item", [
        @html.span(class="problem-text", [@html.text(err)]),
      ])
    })
    @html.div(class="bottom-content problems-list", items)
  }
}

///|
fn view_bottom_content(dispatch : Dispatch[Msg], model : Model) -> Html {
  let content : Html = match model.bottom_tab {
    Problems => view_problems(model)
    OpLog =>
      @html.div(class="bottom-content", [
        @html.span(class="no-problems", [@html.text("No operations recorded")]),
      ])
    CrdtState =>
      @html.div(class="bottom-content crdt-state", [
        @html.div(class="state-row", [
          @html.span(class="state-label", [@html.text("Agent")]),
          @html.span(class="state-value", [@html.text("local")]),
        ]),
        @html.div(class="state-row", [
          @html.span(class="state-label", [@html.text("Timestamp")]),
          @html.span(class="state-value", [
            @html.text(model.next_timestamp.to_string()),
          ]),
        ]),
        @html.div(class="state-row", [
          @html.span(class="state-label", [@html.text("Text length")]),
          @html.span(class="state-value", [
            @html.text(model.editor.get_text().length().to_string()),
          ]),
        ]),
      ])
    Graphviz =>
      @html.div(class="bottom-content graphviz-content", [
        @html.pre(class="graphviz-dot-source", [
          @html.text(model.editor.get_dot_resolved()),
        ]),
      ])
  }
  @html.fragment([view_bottom_tabs(dispatch, model), content])
}
