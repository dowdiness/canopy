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

///|
test "shift_range: node starts inside deleted region — clamp to edit_start" {
  // Node: 5..15, Delete: 3..8 (delta=5, old_end=8)
  let result = shift_range(@loomcore.Range::new(5, 15), 3, 8, 5)
  // Start should clamp to 3, end shifts: 15 - 5 = 10
  inspect(result.start, content="3")
  inspect(result.end, content="10")
}

///|
test "shift_range: node entirely inside deleted region — collapse to point at edit_start" {
  // Node: 5..7, Delete: 3..10 (delta=7, old_end=10)
  let result = shift_range(@loomcore.Range::new(5, 7), 3, 10, 7)
  // Both start and end inside deletion → collapse to (3, 3)
  inspect(result.start, content="3")
  inspect(result.end, content="3")
}

///|
test "shift_range: node starts before deletion, ends inside — truncate at edit_start" {
  // Node: 1..6, Delete: 3..8 (delta=5, old_end=8)
  let result = shift_range(@loomcore.Range::new(1, 6), 3, 8, 5)
  // Start unchanged (before deletion), end truncated to edit_start
  inspect(result.start, content="1")
  inspect(result.end, content="3")
}

///|
test "shift_range: node starts before deletion, ends after — shrink by delta" {
  // Node: 1..20, Delete: 3..8 (delta=5, old_end=8)
  let result = shift_range(@loomcore.Range::new(1, 20), 3, 8, 5)
  // Start unchanged, end shifts: 20 - 5 = 15
  inspect(result.start, content="1")
  inspect(result.end, content="15")
}

///|
test "shift_range: range starts at edit_start, ends after deletion" {
  // Node: 3..10, Delete: 3..8 (delta=5, old_end=8)
  let result = shift_range(@loomcore.Range::new(3, 10), 3, 8, 5)
  // Start at boundary → clamp to edit_start (3), end shifts: 10 - 5 = 5
  inspect(result.start, content="3")
  inspect(result.end, content="5")
}

///|
test "shift_range: range ends exactly at old_end" {
  // Node: 1..8, Delete: 3..8 (delta=5, old_end=8)
  let result = shift_range(@loomcore.Range::new(1, 8), 3, 8, 5)
  // Start before deletion → unchanged, end at boundary → truncate to edit_start
  inspect(result.start, content="1")
  inspect(result.end, content="3")
}

///|
test "shift_range: range equals deletion exactly — collapse to point" {
  // Node: 3..8, Delete: 3..8 (delta=5, old_end=8)
  let result = shift_range(@loomcore.Range::new(3, 8), 3, 8, 5)
  inspect(result.start, content="3")
  inspect(result.end, content="3")
}

///|
test "shift_range: zero-width range inside deletion — collapse to edit_start" {
  // Node: 5..5, Delete: 3..8 (delta=5, old_end=8)
  let result = shift_range(@loomcore.Range::new(5, 5), 3, 8, 5)
  inspect(result.start, content="3")
  inspect(result.end, content="3")
}

///|
test "apply_edit: fully deleted token span collapses to point" {
  let sm = SourceMap::new()
  let nid = NodeId::from_int(1)
  sm.node_to_range[nid] = @loomcore.Range::new(0, 20)
  // Token span entirely inside the deletion
  sm.set_token_span(nid, "name", @loomcore.Range::new(4, 6))
  // Delete chars 3..10 (delta=7)
  sm.apply_edit(3, @loomcore.Range::new(3, 10))
  let spans = sm.get_all_token_spans(nid)
  inspect(spans.length(), content="1")
  // 4..6 entirely inside 3..10 → collapse to (3, 3)
  inspect(spans[0].1.start, content="3")
  inspect(spans[0].1.end, content="3")
}

///|
test "apply_edit: token spans shifted correctly after overlapping deletion" {
  let sm = SourceMap::new()
  let nid = NodeId::from_int(1)
  sm.node_to_range[nid] = @loomcore.Range::new(0, 20)
  // Token span inside the node, overlapping with deletion
  sm.set_token_span(nid, "param", @loomcore.Range::new(5, 10))
  // Delete chars 3..8 (delta=5)
  sm.apply_edit(3, @loomcore.Range::new(3, 8))
  // Token span 5..10 overlaps deletion 3..8:
  // start (5) inside deletion → clamp to 3, end (10) → shift to 5
  let spans = sm.get_all_token_spans(nid)
  inspect(spans.length(), content="1")
  inspect(spans[0].1.start, content="3")
  inspect(spans[0].1.end, content="5")
}
