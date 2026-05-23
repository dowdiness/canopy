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
  let tap = @visualizer.IncrMemoEventTap::attach(rt)
  inspect(memo.read_or_abort(), content="2")
  let snapshot = tap.snapshot()
  inspect(snapshot.events.length(), content="2")
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
  let older = @visualizer.IncrMemoEventTap::attach(rt)
  let newer = @visualizer.IncrMemoEventTap::attach(rt)
  inspect(memo.read_or_abort(), content="2")
  inspect(older.drain_events().length(), content="0")
  inspect(newer.drain_events().length(), content="2")
  older.detach()
  sig.set(2)
  inspect(memo.read_or_abort(), content="3")
  inspect(newer.drain_events().length(), content="2")
  newer.detach()
  sig.set(3)
  inspect(memo.read_or_abort(), content="4")
  inspect(newer.drain_events().length(), content="0")
}
