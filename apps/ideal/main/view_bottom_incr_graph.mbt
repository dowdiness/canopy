///|
fn incr_legend_html() -> String {
  let entries : Array[(@visualizer.VisualNodeStatus, String)] = [
    (Neutral, "Idle"),
    (Active, "Recomputing"),
    (Changed, "Changed"),
    (Failed, "Failed"),
  ]
  let buf = StringBuilder::new()
  buf.write_string(
    "<div class=\"incr-legend\" role=\"list\" aria-label=\"Incr graph status color legend\">",
  )
  for entry in entries {
    let (status, label) = entry
    // Swatch is decorative (aria-hidden) — it duplicates the SVG fill; the
    // text label carries the meaning for assistive tech.
    buf.write_string(
      "<span class=\"incr-legend-item\" role=\"listitem\"><span class=\"incr-legend-swatch\" aria-hidden=\"true\" style=\"background:",
    )
    buf.write_string(status.fill())
    buf.write_string(";border-color:")
    buf.write_string(status.stroke())
    buf.write_string("\"></span>")
    buf.write_string(label)
    buf.write_string("</span>")
  }
  buf.write_string("</div>")
  buf.to_string()
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
      incr_legend_html() +
      "<div class=\"incr-graph\" role=\"img\" aria-label=\"Incr runtime dependency graph\">" +
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
