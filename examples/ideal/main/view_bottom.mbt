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
/// Canonical bottom-tab order: the single source of truth for tab ordering,
/// labels, the tab ↔ index mapping, and the tab count. The headless `@tabs`
/// behavior is parameterized by index, so this list — not the behavior — owns
/// which `BottomTab` each tablist position is.
let bottom_tab_defs : Array[(BottomTab, String)] = [
  (Problems, "Problems"),
  (OpLog, "Op Log"),
  (Patch, "Patch"),
  (History, "History"),
  (CrdtState, "CRDT State"),
  (Graphviz, "Graphviz"),
  (IncrGraph, "Incr Graph"),
]

///|
/// Ordinal of a tab within `bottom_tab_defs`. Deriving the index from the defs
/// list (rather than a hard-coded `match`) keeps tab *order* single-sourced, so
/// reordering the tablist can't desync the index. A `BottomTab` absent from the
/// list is a defect, not a fallback case: aliasing it to `0` would silently give
/// it the Problems tab's id / focus / `SelectBottomTab` target, so we abort
/// loudly instead. Unreachable today — every variant is listed.
fn bottom_tab_index(tab : BottomTab) -> Int {
  match bottom_tab_defs.search_by(pair => pair.0 == tab) {
    Some(index) => index
    None => abort("BottomTab variant missing from bottom_tab_defs")
  }
}

///|
/// Headless tablist behavior for the bottom panel, with `selected` taken from
/// the durable `model.bottom_tab`. Rebuilt per use: selection lives in the
/// model, not in the behavior (no second source of truth).
fn bottom_tabs_behavior(selected : BottomTab) -> @tabs.Model {
  @tabs.Model::new(
    id="canopy-bottom-tabs",
    tab_count=bottom_tab_defs.length(),
    selected=bottom_tab_index(selected),
  )
}

///|
/// Focus the selected tab's button after the next render. Roving tabindex makes
/// inactive tabs unreachable via Tab; without this, arrow-key navigation would
/// leave focus stranded on the previous (now `tabindex="-1"`) button.
/// Click-driven switches are no-ops because the browser already focuses the
/// clicked button.
fn bottom_tab_focus_cmd(tab : BottomTab) -> @rabbita.Cmd {
  bottom_tabs_behavior(tab).focus_cmd()
}

///|
/// Stable slug per tab — used for the tabpanel container id (see
/// `bottom_tab_panel_id`).
fn bottom_tab_slug(tab : BottomTab) -> String {
  match tab {
    Problems => "problems"
    OpLog => "oplog"
    Patch => "patch"
    History => "history"
    CrdtState => "crdt"
    Graphviz => "graphviz"
    IncrGraph => "incr"
  }
}

///|
fn view_bottom_tabs(dispatch : Emit[Msg], model : Model) -> Html {
  let behavior = bottom_tabs_behavior(model.bottom_tab)
  let style = @ui.underline_tab_style()
  let triggers = bottom_tab_defs.mapi(fn(i, pair) {
    let (tab, label) = pair
    @ui.tab_trigger_view(
      behavior,
      i,
      { id: bottom_tab_slug(tab), label },
      panel_id=bottom_tab_panel_id(tab),
      model.bottom_tab == tab,
      j => dispatch(SelectBottomTab(bottom_tab_defs[j].0)),
      style.tab_class,
    )
  })
  @ui.tablist_view(
    label="Bottom panel sections",
    class=style.container_class,
    triggers,
  )
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
/// Build the standard tabpanel attrs for a bottom-panel container — id,
/// role, aria-labelledby pointing back at the tab button, and
/// `tabindex="0"` so Tab from the tablist enters the panel even when no
/// descendant is focusable (Problems / OpLog / CRDT State / SVG-only
/// History/Graphviz). APG: a tabpanel with no focusable content must be
/// in the tab sequence itself.
fn bottom_panel_attrs(tab : BottomTab) -> @html.Attrs {
  // `panel_attrs` reads only the behavior's id prefix and the explicit index, so
  // the Model's `selected` is irrelevant here — `bottom_panel_attrs` is called
  // for whichever panel renders, not necessarily the selected one.
  bottom_tabs_behavior(tab).panel_attrs(
    bottom_tab_index(tab),
    panel_id=bottom_tab_panel_id(tab),
  )
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
fn view_bottom_content(dispatch : Emit[Msg], model : Model) -> Html {
  let content : Html = match model.bottom_tab {
    Problems => view_problems(model)
    OpLog => view_op_log(model)
    Patch => view_patch_log(model)
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

///|
fn render_history_html(model : Model) -> String {
  let snap = model.editor.causal_snapshot()
  let me = model.editor.get_peer_id()
  let key = render_cache_key(model.editor.identity(), snap)
  if cache_hit(history_cache, key) {
    history_cache.html
  } else {
    let h = match @history_render.render_history(snap, me) {
      @history_render.Empty =>
        "<span class=\"history-empty\">No history yet. Edits will appear here as you type.</span>"
      @history_render.TooLarge(n) =>
        "<span class=\"history-empty\">Too many edits to render (\{n}). This view shows histories up to \{@history_render.MAX_OPS} ops.</span>"
      @history_render.Dot(dot) => {
        // Screen-reader label for the SVG. Legend stays outside the
        // role="img" subtree so its agent decoder remains list-readable.
        let svg_label = "Causal history graph: \{snap.op_count()} edits"
        @history_render.legend_html(snap, me) +
        "<div class=\"history-graph\" role=\"img\" aria-label=\"" +
        @history_render.escape_html_string(svg_label) +
        "\">" +
        render_dot_to_svg(dot) +
        "</div>"
      }
    }
    cache_store(history_cache, key, h)
    h
  }
}
