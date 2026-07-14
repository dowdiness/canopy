///|
fn render_graphviz_parse_error(position : Int, message : String) -> String {
  "<span class=\"problem-text\">Parse error at \{position}: \{@history_render.escape_html_string(message)}</span>"
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
    Err(e) => render_graphviz_parse_error(e.position, e.message)
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
/// Static color key for the IncrGraph tab. Unlike the History legend
/// (whose chips are per-agent and data-driven), the incr status palette is
/// fixed: the four `VisualNodeStatus` values map to fixed colors. Each
/// swatch sources its colors from `@visualizer.VisualNodeStatus::fill` /
/// `::stroke` — the same accessors the SVG renderer uses — so the key can't
/// drift from the rendered nodes.
///
/// Labels follow the status semantics in the visualizer event adapter
/// (`incr_tap.mbt` `record_status`): `Active` = a cell currently
/// recomputing, `Changed` = recompute produced a new value, `Failed` = the
/// recompute aborted, `Neutral` = resting (no recent event, or a recompute
/// that re-derived the prior value).
///
/// Emitted as a sibling of the `role="img"` SVG div (not inside it) so the
/// decoder stays list-readable for assistive tech, mirroring `legend_html`.
