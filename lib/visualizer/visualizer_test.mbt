///|
test "visual_graph_to_dot_formats_nodes_and_edges" {
  let graph = @visualizer.VisualGraph(id="sample")
  graph.add_node(@visualizer.VisualNode("a", label="A"))
  graph.add_node(
    @visualizer.VisualNode("b", label="B", status=@visualizer.Changed),
  )
  graph.add_edge(@visualizer.VisualEdge("a", "b", label="dep"))
  let dot = graph.to_dot()
  inspect(dot.contains("digraph sample"), content="true")
  inspect(dot.contains("a -> b"), content="true")
}

///|
test "visual_graph_to_svg_renders_svg" {
  let graph = @visualizer.VisualGraph(id="sample")
  graph.add_node(@visualizer.VisualNode("a", label="A"))
  graph.add_node(@visualizer.VisualNode("b", label="B"))
  graph.add_edge(@visualizer.VisualEdge("a", "b"))
  let svg = graph.to_svg()
  inspect(svg.contains("<svg"), content="true")
}

///|
test "incr_memo_event_tap_snapshots_runtime_graph" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 1, label="input")
  let memo = @incr.Derived(rt, () => sig.get() + 1, label="sum")
  let tap = @visualizer.RecomputeTap::attach(rt)
  inspect(memo.read_or_abort(), content="2")
  let snapshot = tap.snapshot()
  // Keep-last-per-cell: the memo's EnteringCompute + Completed collapse to a
  // single retained record for the one recomputed cell.
  inspect(snapshot.events.length(), content="1")
  inspect(snapshot.nodes.length() >= 2, content="true")
  inspect(snapshot.edges.length() >= 1, content="true")
  let graph = snapshot.to_visual_graph()
  inspect(graph.to_svg().contains("<svg"), content="true")
  tap.detach()
}

///|
test "incr_memo_event_tap_stale_detach_does_not_clear_newer_tap" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 1, label="input")
  let memo = @incr.Derived(rt, () => sig.get() + 1, label="sum")
  let older = @visualizer.RecomputeTap::attach(rt)
  let newer = @visualizer.RecomputeTap::attach(rt)
  inspect(memo.read_or_abort(), content="2")
  inspect(older.drain_events().length(), content="0")
  // One recomputed cell → one retained record (keep-last-per-cell).
  inspect(newer.drain_events().length(), content="1")
  older.detach()
  sig.set(2)
  inspect(memo.read_or_abort(), content="3")
  inspect(newer.drain_events().length(), content="1")
  newer.detach()
  sig.set(3)
  inspect(memo.read_or_abort(), content="4")
  inspect(newer.drain_events().length(), content="0")
}

///|
test "incr_memo_event_tap_buffer_is_bounded_per_cell" {
  let rt = @incr.Runtime()
  let sig = @incr.Signal(rt, 1, label="input")
  let memo = @incr.Derived(rt, () => sig.get() + 1, label="sum")
  let tap = @visualizer.RecomputeTap::attach(rt)
  // Drive several recomputes of the SAME memo without draining: each recompute
  // emits EnteringCompute + Completed, so the unbounded log would hold 6 events.
  inspect(memo.read_or_abort(), content="2")
  sig.set(2)
  inspect(memo.read_or_abort(), content="3")
  sig.set(3)
  inspect(memo.read_or_abort(), content="4")
  // Keep-last-per-cell bounds the buffer to one entry per distinct cell.
  let snapshot = tap.snapshot()
  inspect(snapshot.events.length(), content="1")
  tap.detach()
}
