# Visualizer

Shared graph visualization adapters for Canopy consumers.

This module keeps visualization outside `dowdiness/incr`. Consumers attach
driver-owned taps to public `incr` APIs, convert runtime snapshots into a small
renderer-neutral graph model, then render with the local `dowdiness/graphviz`
layout and SVG renderer. The Graphviz SVG renderer is backed by the local
`dowdiness/svg-dsl` module.

The first adapter is `IncrMemoEventTap`, which listens to
`Runtime::on_memo_event`, records compact memo recompute events, enriches known
cells through `Runtime::cell_info`, and renders the dependency graph. The tap
does not publish events back into the same runtime. `detach()` deactivates the
tap's own listener closure; a stale tap handle will not clear a newer tap that
replaced it on the same runtime.

Build custom graphs with `VisualGraph(id=...)`, `VisualNode(...)`,
`VisualEdge(...)`, `graph.add_node(...)`, and `graph.add_edge(...)`; render with
`graph.to_dot()` or `graph.to_svg()`.
