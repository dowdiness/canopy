///|
fn view_op_log(model : Model) -> Html {
  // When the bottom panel is collapsed, the whole <section> is CSS-hidden but
  // `view()` still re-runs on every model change. Skip the log iteration and
  // emit an empty container; vdom diff repopulates it when the panel reopens.
  if !model.workspace.bottom_visible {
    return @html.div(
      class="bottom-content",
      attrs=bottom_panel_attrs(OpLog),
      ([] : Array[Html]),
    )
  }
  let log = model.intent_log
  if log.is_empty() {
    @html.div(class="bottom-content", attrs=bottom_panel_attrs(OpLog), [
      @html.span(class="no-problems", [
        @html.text(
          "No structural edits yet — try the action overlay or drag.",
        ),
      ]),
    ])
  } else {
    // Most recent first; index labels reflect ordinal across the visible window.
    let n = log.length()
    let items : Array[Html] = Array::new(capacity=n)
    for i in 0..<n {
      let label = log[n - 1 - i]
      items.push(
        @html.div(class="op-log-row", [
          @html.span(class="op-log-index", [@html.text("\{n - i}.")]),
          @html.span(class="op-log-intent", [@html.text(label)]),
        ]),
      )
    }
    @html.div(
      class="bottom-content op-log",
      attrs=bottom_panel_attrs(OpLog),
      items,
    )
  }
}

///|
/// Format a single StructuredChange as human-readable text for the Patch panel.
/// Shows the kind tag and the actual source text at the affected position.
