///|
/// Render-cache for the bottom-panel SVG tabs. The view function runs
/// on every Model change; without a cache, every keystroke would
/// re-walk the snapshot, re-emit DOT, re-parse, re-layout, and re-render
/// the SVG — work proportional to N ops and dominated by Sugiyama
/// layout (O(V·E)).
///
/// Cache keys on `(editor_identity, op_count, frontier_hash)`. Identity
/// distinguishes separately-constructed `SyncEditor`s in the same process
/// — the existing flow has one editor per page, but keying on identity
/// closes the stale-hit path if a future flow swaps editors. Snapshot is
/// a live alias over egw's Document, so key extraction is O(|frontier|).
/// `html` is cached too, so a tab switch that remounts the container
/// still gets innerHTML written cheaply on the next render — only the
/// heavy pipeline is skipped.
///
/// Module-local mutable state is acceptable here: the cmd is the only
/// writer, the update loop sequences calls, and after_render writes are
/// synchronous.
priv struct RenderCache {
  mut identity : Int
  mut op_count : Int
  mut frontier_hash : Int
  mut html : String
  mut valid : Bool
}

///|
let history_cache : RenderCache = {
  identity: -1,
  op_count: 0,
  frontier_hash: 0,
  html: "",
  valid: false,
}

///|
let graphviz_cache : RenderCache = {
  identity: -1,
  op_count: 0,
  frontier_hash: 0,
  html: "",
  valid: false,
}

///|
let incr_graph_cache : RenderCache = {
  identity: -1,
  op_count: 0,
  frontier_hash: 0,
  html: "",
  valid: false,
}

///|
/// Snapshot identity hash for cache lookup. Frontier is small (1-3 LVs in
/// practice); the multiply-by-31 fold collides only on adversarial inputs
/// that callers don't construct.
fn render_cache_key(
  identity : Int,
  snap : @history.CausalSnapshot,
) -> (Int, Int, Int) {
  let mut h = 0
  for lv in snap.frontier() {
    h = h * 31 + lv
  }
  (identity, snap.op_count(), h)
}

///|
fn cache_hit(cache : RenderCache, key : (Int, Int, Int)) -> Bool {
  cache.valid &&
  cache.identity == key.0 &&
  cache.op_count == key.1 &&
  cache.frontier_hash == key.2
}

///|
fn cache_store(
  cache : RenderCache,
  key : (Int, Int, Int),
  html : String,
) -> Unit {
  cache.identity = key.0
  cache.op_count = key.1
  cache.frontier_hash = key.2
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
/// Render the Graphviz tab's HTML (cached). Consumed by
/// `view_bottom_content` via `Attrs::inner_html` so the raw SVG lives
/// inside rabbita's vdom rather than being painted in via a side-effect.
/// Mounting through vdom is what keeps tab-switching consistent: when
/// the user moves to another tab, rabbita's diff sees the panel element
/// transition from `<section>` (SVG panels) to `<div>` (everything
/// else), removes the old subtree wholesale, and rebuilds — so stale
/// SVG can't leak past the diff and block sibling click handlers.
fn render_graphviz_html(model : Model) -> String {
  let snap = model.editor.causal_snapshot()
  let key = render_cache_key(model.editor.identity(), snap)
  if cache_hit(graphviz_cache, key) {
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
}

///|
/// Render the IncrGraph tab's HTML (cached). Keyed on the same triple as
/// the Graphviz tab: the incr dependency graph only changes when text
/// edits advance `op_count`, so cache hits skip the snapshot copy + DOT
/// pipeline. On cache miss we also `drain_events()` on the tap — the
/// snapshot we just took already captured a copy of the events for
/// status coloring, so draining bounds `tap.events` growth to one
/// inter-text-edit gap.
fn render_incr_graph_html(model : Model) -> String {
  let snap = model.editor.causal_snapshot()
  let key = render_cache_key(model.editor.identity(), snap)
  if cache_hit(incr_graph_cache, key) {
    incr_graph_cache.html
  } else {
    let snapshot = model.incr_tap.snapshot()
    let _ = model.incr_tap.drain_events()
    let html = if snapshot.nodes.is_empty() {
      "<span class=\"no-problems\">No incr cells observed yet</span>"
    } else {
      let svg = snapshot
        .to_visual_graph()
        .to_svg_with_config(bottom_tab_svg_config)
      "<div role=\"img\" aria-label=\"Incr runtime dependency graph\">" +
      svg +
      "</div>"
    }
    cache_store(incr_graph_cache, key, html)
    html
  }
}

///|
/// Render the causal-graph History tab's HTML (legend + SVG, cached).
/// See `render_graphviz_html` for the vdom-mount rationale.
fn render_history_html(model : Model) -> String {
  let snap = model.editor.causal_snapshot()
  let me = model.editor.get_peer_id()
  let key = render_cache_key(model.editor.identity(), snap)
  if cache_hit(history_cache, key) {
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
}

///|
/// Focus the active tab's button after the next render. Roving tabindex
/// makes inactive tabs unreachable via Tab; without this, arrow-key
/// navigation would leave focus stranded on the previous (now
/// `tabindex="-1"`) button. Click-driven switches are no-ops because the
/// browser already focuses the clicked button.
fn bottom_tab_focus_cmd(tab : BottomTab) -> @rabbita.Cmd {
  focus_id_after_render(bottom_tab_button_id(tab))
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
    IncrGraph => "incr"
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
    IncrGraph => "canopy-incr-container"
    _ => "canopy-bottom-panel-" + bottom_tab_slug(tab)
  }
}

///|
fn view_bottom_tabs(dispatch : Emit[Msg], model : Model) -> Html {
  let tabs : Array[(BottomTab, String)] = [
    (Problems, "Problems"),
    (OpLog, "Op Log"),
    (History, "History"),
    (CrdtState, "CRDT State"),
    (Graphviz, "Graphviz"),
    (IncrGraph, "Incr Graph"),
  ]
  // Build buttons with WAI-ARIA tabs keyboard support: arrow keys
  // navigate, Home/End jump to ends, and roving tabindex keeps the focus
  // budget at one (active tab is tabindex=0; others are -1, so the page
  // Tab key skips over inactive tabs).
  let n = tabs.length()
  let first_tab = tabs[0].0
  let last_tab = tabs[n - 1].0
  let buttons : Array[Html] = []
  for i in 0..<n {
    let (tab, label) = tabs[i]
    let prev_tab = tabs[(i + n - 1) % n].0
    let next_tab = tabs[(i + 1) % n].0
    let active = model.bottom_tab == tab
    let class_name = if active { "tab active" } else { "tab" }
    // `aria-controls` is set only on the active tab — the other panels
    // aren't mounted (`view_bottom_content` matches on `bottom_tab` and
    // returns one), so cross-referencing missing IDs would mislead AT.
    // The `aria-labelledby` on the active panel still ties it back to
    // its tab button.
    let mut attrs = @html.Attrs::build()
      .id(bottom_tab_button_id(tab))
      .role("tab")
      .aria_selected(if active { "true" } else { "false" })
      .tabindex(if active { 0 } else { -1 })
      .on_keydown(fn(ev) {
        // Horizontal tablist: APG reserves ArrowUp/Down for normal scroll;
        // only ArrowLeft/Right + Home/End move between tabs. Cancel the
        // browser default for handled keys — Home/End and arrow keys
        // otherwise scroll the page or scroll containers, so without
        // prevent_default the viewport jumps while focus moves between
        // tabs.
        let target_tab = match ev.key() {
          "ArrowLeft" => Some(prev_tab)
          "ArrowRight" => Some(next_tab)
          "Home" => Some(first_tab)
          "End" => Some(last_tab)
          _ => None
        }
        match target_tab {
          Some(t) => {
            ev.prevent_default()
            dispatch(SelectBottomTab(t))
          }
          None => @rabbita.none
        }
      })
    if active {
      attrs = attrs.aria_controls(bottom_tab_panel_id(tab))
    }
    buttons.push(
      @html.button(
        class=class_name,
        on_click=dispatch(SelectBottomTab(tab)),
        attrs~,
        [@html.text(label)],
      ),
    )
  }
  @html.div(
    class="bottom-tabs",
    attrs=@html.Attrs::build()
      .role("tablist")
      .aria_label("Bottom panel sections"),
    buttons,
  )
}

///|
/// Build the standard tabpanel attrs for a bottom-panel container — id,
/// role, aria-labelledby pointing back at the tab button, and
/// `tabindex="0"` so Tab from the tablist enters the panel even when no
/// descendant is focusable (Problems / OpLog / CRDT State / SVG-only
/// History/Graphviz). APG: a tabpanel with no focusable content must be
/// in the tab sequence itself.
fn bottom_panel_attrs(tab : BottomTab) -> @html.Attrs {
  @html.Attrs::build()
  .id(bottom_tab_panel_id(tab))
  .role("tabpanel")
  .aria_labelledby(bottom_tab_button_id(tab))
  .tabindex(0)
}

///|
/// Render the History panel — wraps the cached HTML via `inner_html`.
/// `<section>` (instead of `<div>`) is intentional: when the user
/// switches to a non-SVG tab (Problems/OpLog/CrdtState — all `<div>`),
/// the tag mismatch makes rabbita's diff issue a full remove + insert
/// rather than patching in place. In-place patching would leave the
/// raw SVG sitting under the new tab's children, because rabbita's
/// `remove_property("innerHTML")` is a `delete element.innerHTML` which
/// is a no-op for prototype accessors.
/// The `inner_html` call is XSS-vulnerable in general; the input here
/// is built from our own SVG renderer + `escape_html_string` for the
/// aria-label, never user-supplied text.
#warnings("-alert_xss_vulnerable")
fn view_history_panel(model : Model) -> Html {
  // When the bottom panel is collapsed, the entire <section> is CSS-hidden
  // but `view()` still runs on every model change. Skip the DOT/SVG layout
  // pipeline (cache key changes on every edit) and emit empty innerHTML;
  // the cache stays valid for the next open.
  let html = if model.workspace.bottom_visible {
    render_history_html(model)
  } else {
    ""
  }
  @html.section(
    class="bottom-content history-content",
    attrs=bottom_panel_attrs(History).inner_html(html),
    ([] : Array[Html]),
  )
}

///|
/// Render the Graphviz panel. See `view_history_panel` for why this is
/// a `<section>` with `inner_html` rather than a `<div>` with vdom
/// children, and for the `bottom_visible` gate.
#warnings("-alert_xss_vulnerable")
fn view_graphviz_panel(model : Model) -> Html {
  let html = if model.workspace.bottom_visible {
    render_graphviz_html(model)
  } else {
    ""
  }
  @html.section(
    class="bottom-content graphviz-content",
    attrs=bottom_panel_attrs(Graphviz).inner_html(html),
    ([] : Array[Html]),
  )
}

///|
/// Render the IncrGraph panel. See `view_history_panel` for the
/// `<section>` + `inner_html` rationale and the `bottom_visible` gate.
#warnings("-alert_xss_vulnerable")
fn view_incr_graph_panel(model : Model) -> Html {
  let html = if model.workspace.bottom_visible {
    render_incr_graph_html(model)
  } else {
    ""
  }
  @html.section(
    class="bottom-content incr-graph-content",
    attrs=bottom_panel_attrs(IncrGraph).inner_html(html),
    ([] : Array[Html]),
  )
}

///|
fn view_op_log(model : Model) -> Html {
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
fn view_bottom_content(dispatch : Emit[Msg], model : Model) -> Html {
  let content : Html = match model.bottom_tab {
    Problems => view_problems(model)
    OpLog => view_op_log(model)
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
    History => view_history_panel(model)
    Graphviz => view_graphviz_panel(model)
    IncrGraph => view_incr_graph_panel(model)
  }
  @html.fragment([view_bottom_tabs(dispatch, model), content])
}
