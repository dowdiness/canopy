// Property-based tests for source_map.mbt using @qc (quickcheck).
// These test structural invariants: node coverage, range consistency,
// sorted-ranges ordering, and token span containment.

///|
/// Property 1: Every node in a ProjNode tree has a range in the SourceMap.
/// SourceMap::from_ast should produce an entry for every node in the tree.
fn prop_from_ast_covers_all_nodes(expr : TestExpr) -> Bool {
  let counter = Ref::new(0)
  let root = to_proj_node(expr, counter)
  let sm = SourceMap::from_ast(root)
  let ids = collect_ids(root)
  if sm.node_count() != ids.length() {
    return false
  }
  for id in ids {
    if sm.get_range(NodeId::from_int(id)) is None {
      return false
    }
  }
  true
}

///|
test "property: from_ast covers all nodes" {
  @qc.quick_check_fn(prop_from_ast_covers_all_nodes)
}

///|
/// Property 2: The sorted ranges array has the same length as node_to_range.
/// After from_ast, ranges should contain exactly one entry per node.
fn prop_ranges_length_matches_node_count(expr : TestExpr) -> Bool {
  let counter = Ref::new(0)
  let root = to_proj_node(expr, counter)
  let sm = SourceMap::from_ast(root)
  sm.ranges.length() == sm.node_count()
}

///|
test "property: ranges array length matches node count" {
  @qc.quick_check_fn(prop_ranges_length_matches_node_count)
}

///|
/// Property 3: The ranges array is sorted by start position (ascending),
/// with ties broken by end position (descending — larger ranges first).
/// Uses realistic nested ranges so sorting is non-trivially exercised.
fn prop_ranges_sorted(expr : TestExpr) -> Bool {
  let counter = Ref::new(0)
  let offset = Ref::new(0)
  let root = to_proj_node_with_ranges(expr, counter, offset)
  let sm = SourceMap::from_ast(root)
  for i = 1; i < sm.ranges.length(); i = i + 1 {
    let (prev_range, _) = sm.ranges[i - 1]
    let (curr_range, _) = sm.ranges[i]
    if prev_range.start > curr_range.start {
      return false
    }
    if prev_range.start == curr_range.start && prev_range.end < curr_range.end {
      return false
    }
  }
  true
}

///|
test "property: ranges array is correctly sorted" {
  @qc.quick_check_fn(prop_ranges_sorted)
}

///|
/// Property 4: rebuild() then from_ast() produce the same SourceMap content.
/// Rebuilding from the same tree should yield identical node_to_range entries.
fn prop_rebuild_matches_from_ast(expr : TestExpr) -> Bool {
  let counter = Ref::new(0)
  let root = to_proj_node(expr, counter)
  let sm1 = SourceMap::from_ast(root)
  let sm2 = SourceMap::new()
  sm2.rebuild(root)
  if sm1.node_count() != sm2.node_count() {
    return false
  }
  let ids = collect_ids(root)
  for id in ids {
    let nid = NodeId::from_int(id)
    let r1 = sm1.get_range(nid)
    let r2 = sm2.get_range(nid)
    if r1 != r2 {
      return false
    }
  }
  true
}

///|
test "property: rebuild matches from_ast" {
  @qc.quick_check_fn(prop_rebuild_matches_from_ast)
}

///|
/// Convert a TestExpr into a ProjNode with non-trivial, nested ranges.
/// Parent range encloses children: parent=[start, start+total_width).
/// This produces valid nesting so position queries are meaningful.
fn to_proj_node_with_ranges(
  expr : TestExpr,
  counter : Ref[Int],
  offset : Ref[Int],
) -> ProjNode[TestExpr] {
  match expr {
    Leaf(s) => {
      let start = offset.val
      let end = start + s.length().max(1)
      offset.val = end
      let id = next_proj_node_id(counter)
      ProjNode::new(expr, start, end, id, [])
    }
    Branch(_, cs) => {
      let start = offset.val
      let children : Array[ProjNode[TestExpr]] = []
      for c in cs {
        children.push(to_proj_node_with_ranges(c, counter, offset))
      }
      let end = offset.val.max(start + 1)
      offset.val = end
      let id = next_proj_node_id(counter)
      ProjNode::new(expr, start, end, id, children)
    }
  }
}

///|
/// Property 5: Parent ranges enclose child ranges in the SourceMap.
/// For every node with children, the parent's range should contain
/// each child's range.
fn prop_parent_encloses_children(expr : TestExpr) -> Bool {
  let counter = Ref::new(0)
  let offset = Ref::new(0)
  let root = to_proj_node_with_ranges(expr, counter, offset)
  let sm = SourceMap::from_ast(root)
  check_enclosure(root, sm)
}

///|
fn check_enclosure(node : ProjNode[TestExpr], sm : SourceMap) -> Bool {
  let parent_range = match sm.get_range(node.id()) {
    Some(r) => r
    None => return false
  }
  for child in node.children {
    let child_range = match sm.get_range(child.id()) {
      Some(r) => r
      None => return false
    }
    if child_range.start < parent_range.start ||
      child_range.end > parent_range.end {
      return false
    }
    if !check_enclosure(child, sm) {
      return false
    }
  }
  true
}

///|
test "property: parent ranges enclose child ranges" {
  @qc.quick_check_fn(prop_parent_encloses_children)
}

///|
/// Property 6: innermost_node_at returns the node with the smallest
/// containing range among all nodes that contain the query position.
/// Probes multiple positions across the root range for better coverage.
fn prop_innermost_node_has_minimal_range(expr : TestExpr) -> Bool {
  let counter = Ref::new(0)
  let offset = Ref::new(0)
  let root = to_proj_node_with_ranges(expr, counter, offset)
  let sm = SourceMap::from_ast(root)
  let root_range = match sm.get_range(root.id()) {
    Some(r) => r
    None => return true
  }
  // Probe at start, midpoint, and end-1 of the root range
  let positions = [
    root_range.start,
    (root_range.start + root_range.end) / 2,
    (root_range.end - 1).max(root_range.start),
  ]
  for pos in positions {
    match sm.innermost_node_at(pos) {
      None => return false // should find at least the root
      Some(nid) => {
        let innermost_range = match sm.get_range(nid) {
          Some(r) => r
          None => return false
        }
        // Must contain the position
        if !innermost_range.contains(pos) {
          return false
        }
        // Verify minimality: no other node has a strictly smaller
        // containing range
        let innermost_len = innermost_range.end - innermost_range.start
        let all_containing = sm.nodes_at_position(pos)
        for other_nid in all_containing {
          match sm.get_range(other_nid) {
            Some(other_range) => {
              let other_len = other_range.end - other_range.start
              if other_len < innermost_len {
                return false
              }
            }
            None => ()
          }
        }
      }
    }
  }
  true
}

///|
test "property: innermost_node_at returns minimal containing node" {
  @qc.quick_check_fn(prop_innermost_node_has_minimal_range)
}

///|
/// Property 7: rebuild() clears token spans.
/// Set token spans on the SourceMap, then rebuild from the same tree.
/// All token spans should be gone after rebuild (as documented in
/// source_map.mbt — "clears token_spans").
fn prop_rebuild_clears_token_spans(expr : TestExpr) -> Bool {
  let counter = Ref::new(0)
  let offset = Ref::new(0)
  let root = to_proj_node_with_ranges(expr, counter, offset)
  let sm = SourceMap::from_ast(root)
  // Set a token span on the root node
  let node_range = match sm.get_range(root.id()) {
    Some(r) => r
    None => return true
  }
  if node_range.start >= node_range.end {
    return true
  }
  let span = @loomcore.Range::new(
    node_range.start,
    (node_range.start + node_range.end) / 2 + 1,
  )
  sm.set_token_span(root.id(), "test_role", span)
  // Verify it was set
  if sm.get_token_span(root.id(), "test_role") is None {
    return false
  }
  // Rebuild from the same tree
  sm.rebuild(root)
  // Token spans should be cleared
  sm.get_token_span(root.id(), "test_role") is None
}

///|
test "property: rebuild clears token spans" {
  @qc.quick_check_fn(prop_rebuild_clears_token_spans)
}
