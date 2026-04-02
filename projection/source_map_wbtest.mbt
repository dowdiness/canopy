// Whitebox tests for SourceMap - Bug Fix: apply_edit position shifting
// These tests verify that positions shift backward correctly after deletions

///|
test "apply_edit shifts positions backward on delete" {
  // Create a source map with a node at position 5-10
  let source_map = SourceMap::new()
  let node_id = NodeId::from_int(1)
  source_map.node_to_range[node_id] = Range::new(5, 10)
  source_map.rebuild_ranges()

  // Delete 2 characters at position 0-2 (before the node)
  let deleted_range = Range::new(0, 2)
  source_map.apply_edit(0, deleted_range)

  // Node should now be at position 3-8 (shifted backward by 2)
  match source_map.get_range(node_id) {
    Some(range) => {
      inspect(range.start, content="3")
      inspect(range.end, content="8")
    }
    None => fail("Node not found after edit")
  }
}

///|
test "apply_edit leaves nodes before deletion unchanged" {
  let source_map = SourceMap::new()
  let node_id = NodeId::from_int(1)
  source_map.node_to_range[node_id] = Range::new(0, 3)
  source_map.rebuild_ranges()

  // Delete characters at position 5-7 (after the node)
  let deleted_range = Range::new(5, 7)
  source_map.apply_edit(5, deleted_range)

  // Node at 0-3 should be unchanged
  match source_map.get_range(node_id) {
    Some(range) => {
      inspect(range.start, content="0")
      inspect(range.end, content="3")
    }
    None => fail("Node not found after edit")
  }
}

///|
test "apply_edit handles overlapping deletion" {
  let source_map = SourceMap::new()
  let node_id = NodeId::from_int(1)
  // Node spans 3-10
  source_map.node_to_range[node_id] = Range::new(3, 10)
  source_map.rebuild_ranges()

  // Delete characters at position 5-7 (inside the node)
  let deleted_range = Range::new(5, 7)
  source_map.apply_edit(5, deleted_range)

  // Node start should be unchanged, end should shift backward
  match source_map.get_range(node_id) {
    Some(range) => {
      inspect(range.start, content="3")
      // End was 10, deletion of 2 chars (7-5=2) inside shifts end to 8
      inspect(range.end, content="8")
    }
    None => fail("Node not found after edit")
  }
}

///|
test "apply_edit multiple nodes" {
  let source_map = SourceMap::new()
  // Node A at 0-3 (before deletion)
  source_map.node_to_range[NodeId::from_int(1)] = Range::new(0, 3)
  // Node B at 5-8 (overlaps with deletion end)
  source_map.node_to_range[NodeId::from_int(2)] = Range::new(5, 8)
  // Node C at 10-15 (after deletion)
  source_map.node_to_range[NodeId::from_int(3)] = Range::new(10, 15)
  source_map.rebuild_ranges()

  // Delete characters at position 4-6
  let deleted_range = Range::new(4, 6)
  source_map.apply_edit(4, deleted_range)

  // Node A (0-3): unchanged (ends before edit_start)
  match source_map.get_range(NodeId::from_int(1)) {
    Some(range) => {
      inspect(range.start, content="0")
      inspect(range.end, content="3")
    }
    None => fail("Node A not found")
  }

  // Node B (5-8): overlaps deletion 4..6, start inside deletion → clamp to 4
  match source_map.get_range(NodeId::from_int(2)) {
    Some(range) => {
      inspect(range.start, content="4") // was 5, inside deletion → clamped to edit_start
      inspect(range.end, content="6") // 8 - 2 = 6
    }
    None => fail("Node B not found")
  }

  // Node C (10-15): after deletion, shifts backward by 2
  match source_map.get_range(NodeId::from_int(3)) {
    Some(range) => {
      inspect(range.start, content="8") // 10 - 2 = 8
      inspect(range.end, content="13") // 15 - 2 = 13
    }
    None => fail("Node C not found")
  }
}

///|
test "apply_edit with zero-length deletion does nothing" {
  let source_map = SourceMap::new()
  let node_id = NodeId::from_int(1)
  source_map.node_to_range[node_id] = Range::new(5, 10)
  source_map.rebuild_ranges()

  // Zero-length deletion at position 3
  let deleted_range = Range::new(3, 3)
  source_map.apply_edit(3, deleted_range)

  // Node should be unchanged
  match source_map.get_range(node_id) {
    Some(range) => {
      inspect(range.start, content="5")
      inspect(range.end, content="10")
    }
    None => fail("Node not found after edit")
  }
}

///|
test "SourceMap::remove_subtree removes node and children" {
  let parent = ProjNode::new(
    @ast.Term::App(@ast.Term::Var("f"), @ast.Term::Var("x")),
    0,
    5,
    1,
    [
      ProjNode::new(@ast.Term::Var("f"), 0, 1, 2, []),
      ProjNode::new(@ast.Term::Var("x"), 2, 5, 3, []),
    ],
  )
  let sm = SourceMap::from_ast(parent)
  inspect(sm.node_count(), content="3")

  sm.remove_subtree(parent)
  inspect(sm.node_count(), content="0")
}

///|
test "SourceMap::patch_subtree adds new node entries" {
  let sm = SourceMap::new()
  let node = ProjNode::new(
    @ast.Term::App(@ast.Term::Var("f"), @ast.Term::Var("x")),
    0,
    5,
    10,
    [
      ProjNode::new(@ast.Term::Var("f"), 0, 1, 11, []),
      ProjNode::new(@ast.Term::Var("x"), 2, 5, 12, []),
    ],
  )
  sm.patch_subtree(node)
  inspect(sm.node_count(), content="3")
  inspect(sm.get_range(NodeId::from_int(10)) is Some(_), content="true")
  inspect(sm.get_range(NodeId::from_int(11)) is Some(_), content="true")
}

///|
test "SourceMap::remove_subtree then patch_subtree replaces entries" {
  let old_child = ProjNode::new(@ast.Term::Int(1), 10, 11, 5, [])
  let old_root = ProjNode::new(
    @ast.Term::Module([("x", @ast.Term::Int(1))], @ast.Term::Int(1)),
    0,
    15,
    1,
    [old_child, ProjNode::new(@ast.Term::Int(1), 12, 15, 6, [])],
  )
  let sm = SourceMap::from_ast(old_root)
  inspect(sm.node_count(), content="3")

  sm.remove_subtree(old_child)
  inspect(sm.node_count(), content="2")

  let new_child = ProjNode::new(@ast.Term::Int(2), 10, 11, 7, [])
  sm.patch_subtree(new_child)
  sm.rebuild_ranges()
  inspect(sm.node_count(), content="3")

  inspect(sm.get_range(NodeId::from_int(5)), content="None")
  inspect(sm.get_range(NodeId::from_int(7)) is Some(_), content="true")
}
