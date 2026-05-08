///|
/// Render-cache for the bottom-panel SVG tabs. The view-update loop
/// re-issues `bottom_render_cmd` on every Model change; without a cache,
/// every keystroke would re-walk the snapshot, re-emit DOT, re-parse,
/// re-layout, and re-render the SVG — work proportional to N ops and
/// dominated by Sugiyama layout (O(V·E)).
///
/// Cache keys on `(op_count, frontier_hash, agent)`. The snapshot is a
/// live alias over egw's Document, so cache key extraction is O(|frontier|).
/// `html` is cached too, so a tab switch that remounts the container still
/// gets innerHTML written cheaply on the next render — only the heavy
/// pipeline is skipped.
///
/// Module-local mutable state is acceptable here: the cmd is the only
/// writer, the update loop sequences calls, and after_render writes are
/// synchronous.
priv struct RenderCache {
  mut op_count : Int
  mut frontier_hash : Int
  mut agent : String
  mut html : String
  mut valid : Bool
}

///|
let history_cache : RenderCache = {
  op_count: 0,
  frontier_hash: 0,
  agent: "",
  html: "",
  valid: false,
}

///|
let graphviz_cache : RenderCache = {
  op_count: 0,
  frontier_hash: 0,
  agent: "",
  html: "",
  valid: false,
}

///|
/// Snapshot identity hash for cache lookup. Frontier is small (1-3 LVs in
/// practice); the multiply-by-31 fold collides only on adversarial inputs
/// that callers don't construct.
fn render_cache_key(
  snap : @history.CausalSnapshot,
  agent : String,
) -> (Int, Int, String) {
  let mut h = 0
  for lv in snap.frontier() {
    h = h * 31 + lv
  }
  (snap.op_count(), h, agent)
}

///|
fn cache_hit(cache : RenderCache, key : (Int, Int, String)) -> Bool {
  cache.valid &&
  cache.op_count == key.0 &&
  cache.frontier_hash == key.1 &&
  cache.agent == key.2
}

///|
fn cache_store(
  cache : RenderCache,
  key : (Int, Int, String),
  html : String,
) -> Unit {
  cache.op_count = key.0
  cache.frontier_hash = key.1
  cache.agent = key.2
  cache.html = html
  cache.valid = true
}

///|
/// Render a DOT string to SVG using the MoonBit graphviz pipeline.
///
/// `LayoutConfig::compact()` produces 50×28 user-unit nodes; the
/// upstream `SvgConfig::dark_theme()` ships `font_size: 14`, which at
/// the default Arial metric (~0.55 em advance) needs >50 units for
/// labels of ~7 chars. The History tab's `"You (57 ops)"` and
/// `"Peer-9d49#7"` overflow visually. Halve the font (14 → 9) so
/// 12-character labels fit inside the rect at the panel's downscaled
/// size. Both tabs share this renderer; the Graphviz tab has shorter
/// labels and only benefits from the change.
let bottom_tab_svg_config : @gv_svg.SvgConfig = {
  ..@gv_svg.SvgConfig::dark_theme(),
  font_size: 9.0,
}

///|
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
      @gv_svg.render_svg_with_config(layout, bottom_tab_svg_config)
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
  let snap = model.editor.causal_snapshot()
  let key = render_cache_key(snap, model.editor.get_peer_id())
  // Cache the wrapped HTML, not the bare SVG — the role="img" wrapper is
  // a constant cost we want to pay once. Mirrors the History tab so screen
  // readers see the same shape on either panel.
  let html = if cache_hit(graphviz_cache, key) {
    graphviz_cache.html
  } else {
    let dot = @lambda.get_lambda_dot_resolved(model.editor)
    let svg = render_dot_to_svg(dot)
    let wrapped = "<div role=\"img\" aria-label=\"Resolved lambda expression graph\">" +
      svg +
      "</div>"
    cache_store(graphviz_cache, key, wrapped)
    wrapped
  }
  // AfterRender ensures the container div exists in the DOM before setting innerHTML.
  // We always write — cache hit only skips the upstream resolve+layout cost.
  @rabbita_cmd.raw_effect(
    fn(_) { js_set_inner_html("canopy-graphviz-container", html) },
    kind=@rabbita_cmd.after_render,
  )
}

///|
/// Render the causal-graph history view (legend + SVG) into the History
/// tab's container. Mirrors `graphviz_render_cmd` — guarded on tab and
/// visibility.
fn history_render_cmd(model : Model) -> @rabbita.Cmd {
  if model.bottom_tab != History || !model.workspace.bottom_visible {
    return @rabbita.none
  }
  let snap = model.editor.causal_snapshot()
  let me = model.editor.get_peer_id()
  let key = render_cache_key(snap, me)
  let html = if cache_hit(history_cache, key) {
    history_cache.html
  } else {
    let h = match render_history(snap, me) {
      Empty =>
        "<span class=\"history-empty\">No history yet. Edits will appear here as you type.</span>"
      TooLarge(n) =>
        "<span class=\"history-empty\">Too many edits to render (\{n}). This view shows histories up to \{MAX_OPS} ops.</span>"
      Dot(dot) => {
        // Screen-reader label for the SVG. Legend stays outside the
        // role="img" subtree so its agent decoder remains list-readable.
        let svg_label = "Causal history graph: \{snap.op_count()} edits"
        legend_html(snap, me) +
        "<div class=\"history-graph\" role=\"img\" aria-label=\"" +
        escape_html_string(svg_label) +
        "\">" +
        render_dot_to_svg(dot) +
        "</div>"
      }
    }
    cache_store(history_cache, key, h)
    h
  }
  @rabbita_cmd.raw_effect(
    fn(_) { js_set_inner_html("canopy-history-container", html) },
    kind=@rabbita_cmd.after_render,
  )
}

///|
/// Run the appropriate bottom-panel render command for the active tab.
/// Each per-tab cmd self-guards on tab + visibility, so this just batches.
fn bottom_render_cmd(model : Model) -> @rabbita.Cmd {
  @rabbita.batch([graphviz_render_cmd(model), history_render_cmd(model)])
}

///|
/// Stable slug per tab — used for both the tab button id and the tabpanel
/// id, so `aria-controls` ↔ `aria-labelledby` round-trips cleanly.
fn bottom_tab_slug(tab : BottomTab) -> String {
  match tab {
    Problems => "problems"
    OpLog => "oplog"
    History => "history"
    CrdtState => "crdt"
    Graphviz => "graphviz"
  }
}

///|
fn bottom_tab_button_id(tab : BottomTab) -> String {
  "canopy-bottom-tab-" + bottom_tab_slug(tab)
}

///|
/// Panel container id. History and Graphviz keep their existing
/// `canopy-{name}-container` ids because the render cmds write innerHTML
/// to those exact element ids; the others get a uniform slug.
fn bottom_tab_panel_id(tab : BottomTab) -> String {
  match tab {
    History => "canopy-history-container"
    Graphviz => "canopy-graphviz-container"
    _ => "canopy-bottom-panel-" + bottom_tab_slug(tab)
  }
}

///|
fn view_bottom_tabs(dispatch : Dispatch[Msg], model : Model) -> Html {
  let tabs : Array[(BottomTab, String)] = [
    (Problems, "Problems"),
    (OpLog, "Op Log"),
    (History, "History"),
    (CrdtState, "CRDT State"),
    (Graphviz, "Graphviz"),
  ]
  @html.div(
    class="bottom-tabs",
    attrs=@html.Attrs::build()
      .role("tablist")
      .aria_label("Bottom panel sections"),
    tabs.map(fn(pair) {
      let (tab, label) = pair
      let active = model.bottom_tab == tab
      let class_name = if active { "tab active" } else { "tab" }
      let attrs = @html.Attrs::build()
        .id(bottom_tab_button_id(tab))
        .role("tab")
        .aria_selected(if active { "true" } else { "false" })
        .aria_controls(bottom_tab_panel_id(tab))
      @html.button(
        class=class_name,
        on_click=dispatch(SelectBottomTab(tab)),
        attrs~,
        [@html.text(label)],
      )
    }),
  )
}

///|
/// Build the standard tabpanel attrs for a bottom-panel container — id,
/// role, and aria-labelledby pointing back at the tab button.
fn bottom_panel_attrs(tab : BottomTab) -> @html.Attrs {
  @html.Attrs::build()
  .id(bottom_tab_panel_id(tab))
  .role("tabpanel")
  .aria_labelledby(bottom_tab_button_id(tab))
}

///|
fn view_problems(model : Model) -> Html {
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

///|
fn view_bottom_content(dispatch : Dispatch[Msg], model : Model) -> Html {
  let content : Html = match model.bottom_tab {
    Problems => view_problems(model)
    OpLog =>
      @html.div(class="bottom-content", attrs=bottom_panel_attrs(OpLog), [
        @html.span(class="no-problems", [@html.text("Op log coming soon")]),
      ])
    CrdtState =>
      @html.div(
        class="bottom-content crdt-state",
        attrs=bottom_panel_attrs(CrdtState),
        [
          @html.div(class="state-row", [
            @html.span(class="state-label", [@html.text("Agent")]),
            @html.span(class="state-value", [
              @html.text(model.editor.get_peer_id()),
            ]),
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
        ],
      )
    History =>
      @html.div(
        class="bottom-content history-content",
        attrs=bottom_panel_attrs(History),
        [@html.text("")],
      )
    Graphviz =>
      @html.div(
        class="bottom-content graphviz-content",
        attrs=bottom_panel_attrs(Graphviz),
        [@html.text("")],
      )
  }
  @html.fragment([view_bottom_tabs(dispatch, model), content])
}
