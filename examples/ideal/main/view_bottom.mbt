///|
/// Render a DOT string to SVG using the MoonBit graphviz pipeline.
fn render_dot_to_svg(dot : String) -> String {
  if dot == "" || dot == "digraph { }" {
    return "<span class=\"no-problems\">No graph data</span>"
  }
  match @gv_parser.parse_dot(dot) {
    Ok(graph) => {
      let layout = @gv_layout.compute_layout_with_config(
        graph,
        @gv_layout.LayoutConfig::compact(),
      )
      @gv_svg.render_svg_with_config(layout, @gv_svg.SvgConfig::dark_theme())
    }
    Err(e) =>
      "<span class=\"problem-text\">Parse error at \{e.position}: \{e.message}</span>"
  }
}

///|
/// Create a command that renders the Graphviz SVG into the container.
/// Must run after the DOM element exists (use as AfterRender or after flush).
fn graphviz_render_cmd(model : Model) -> @rabbita.Cmd {
  if model.bottom_tab != Graphviz || !model.workspace.bottom_visible {
    return @rabbita.none
  }
  let dot = @lambda.get_lambda_dot_resolved(model.editor)
  let svg = render_dot_to_svg(dot)
  // AfterRender ensures the container div exists in the DOM before setting innerHTML.
  @rabbita_cmd.raw_effect(
    fn(_) { js_set_inner_html("canopy-graphviz-container", svg) },
    kind=@rabbita_cmd.after_render,
  )
}

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
      @html.div(
        class="bottom-content graphviz-content",
        attrs=@html.Attrs::build().id("canopy-graphviz-container"),
        [@html.text("")],
      )
  }
  @html.fragment([view_bottom_tabs(dispatch, model), content])
}
