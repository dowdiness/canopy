///|
test "get_all_token_spans returns sorted pairs" {
  let sm = SourceMap::new()
  let nid = NodeId::from_int(1)
  sm.set_token_span(nid, "param", @loomcore.Range::new(5, 8))
  sm.set_token_span(nid, "name", @loomcore.Range::new(1, 3))
  let spans = sm.get_all_token_spans(nid)
  // Should be sorted by range start: name(1..3) before param(5..8)
  inspect(spans.length(), content="2")
  inspect(spans[0].0, content="name")
  inspect(spans[0].1.start, content="1")
  inspect(spans[1].0, content="param")
  inspect(spans[1].1.start, content="5")
}

///|
test "get_all_token_spans returns empty for unknown node" {
  let sm = SourceMap::new()
  let nid = NodeId::from_int(99)
  let spans = sm.get_all_token_spans(nid)
  inspect(spans.length(), content="0")
}

///|
test "apply_edit shifts token spans" {
  let sm = SourceMap::new()
  let nid = NodeId::from_int(1)
  sm.node_to_range[nid] = @loomcore.Range::new(0, 20)
  sm.set_token_span(nid, "param", @loomcore.Range::new(10, 13))
  // Delete 3 chars at positions 2..5 (before the token span)
  sm.apply_edit(2, @loomcore.Range::new(2, 5))
  let spans = sm.get_all_token_spans(nid)
  inspect(spans.length(), content="1")
  // param span should shift backward by 3: 10..13 → 7..10
  inspect(spans[0].1.start, content="7")
  inspect(spans[0].1.end, content="10")
}

///|
test "patch_subtree clears stale token spans" {
  let sm = SourceMap::new()
  let nid = NodeId::from_int(1)
  sm.node_to_range[nid] = @loomcore.Range::new(0, 10)
  sm.set_token_span(nid, "param", @loomcore.Range::new(2, 4))
  // Patch the node — should clear its token spans
  let node : ProjNode[Int] = ProjNode::new(42, 0, 12, 1, [])
  sm.patch_subtree(node)
  let spans = sm.get_all_token_spans(nid)
  inspect(spans.length(), content="0")
}
