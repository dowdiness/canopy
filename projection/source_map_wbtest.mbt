// Whitebox tests for SourceMap - Bug Fix: apply_edit position shifting
// These tests verify that positions shift backward correctly after deletions

///|
test "apply_edit shifts positions backward on delete" {
  // Create a source map with a node at position 5-10
  let source_map = SourceMap::new()
  let node_id = NodeId(1)
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
    None => abort("Node not found after edit")
  }
}

///|
test "apply_edit leaves nodes before deletion unchanged" {
  let source_map = SourceMap::new()
  let node_id = NodeId(1)
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
    None => abort("Node not found after edit")
  }
}

///|
test "apply_edit handles overlapping deletion" {
  let source_map = SourceMap::new()
  let node_id = NodeId(1)
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
    None => abort("Node not found after edit")
  }
}

///|
test "apply_edit multiple nodes" {
  let source_map = SourceMap::new()
  // Node A at 0-3 (before deletion)
  source_map.node_to_range[NodeId(1)] = Range::new(0, 3)
  // Node B at 5-8 (overlaps with deletion end)
  source_map.node_to_range[NodeId(2)] = Range::new(5, 8)
  // Node C at 10-15 (after deletion)
  source_map.node_to_range[NodeId(3)] = Range::new(10, 15)
  source_map.rebuild_ranges()

  // Delete characters at position 4-6
  let deleted_range = Range::new(4, 6)
  source_map.apply_edit(4, deleted_range)

  // Node A (0-3): unchanged (ends before edit_start)
  match source_map.get_range(NodeId(1)) {
    Some(range) => {
      inspect(range.start, content="0")
      inspect(range.end, content="3")
    }
    None => abort("Node A not found")
  }

  // Node B (5-8): overlaps, start unchanged, end shifts backward by 2
  match source_map.get_range(NodeId(2)) {
    Some(range) => {
      inspect(range.start, content="5")
      inspect(range.end, content="6") // 8 - 2 = 6
    }
    None => abort("Node B not found")
  }

  // Node C (10-15): after deletion, shifts backward by 2
  match source_map.get_range(NodeId(3)) {
    Some(range) => {
      inspect(range.start, content="8") // 10 - 2 = 8
      inspect(range.end, content="13") // 15 - 2 = 13
    }
    None => abort("Node C not found")
  }
}

///|
test "apply_edit with zero-length deletion does nothing" {
  let source_map = SourceMap::new()
  let node_id = NodeId(1)
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
    None => abort("Node not found after edit")
  }
}
