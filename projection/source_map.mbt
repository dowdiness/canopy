// SourceMap: Bidirectional mapping between AST nodes and text positions
// Enables efficient lookup in both directions for projectional editing

///|
/// Maps between AST node IDs and their text positions
pub struct SourceMap {
  /// NodeId → Range mapping
  node_to_range : Map[NodeId, Range]
  /// Reverse index: position → candidate NodeIds (for point queries)
  /// Uses a simple array of (range, node_id) tuples sorted by start
  ranges : Array[(Range, NodeId)]
} derive(Show, Eq)

///|
/// Create an empty SourceMap
pub fn SourceMap::new() -> SourceMap {
  { node_to_range: {}, ranges: [] }
}

///|
/// Build a SourceMap from a ProjNode tree
pub fn SourceMap::from_ast(root : ProjNode) -> SourceMap {
  let map = SourceMap::new()
  map.build_from_node(root)
  map.rebuild_ranges()
  map
}

///|
/// Recursively build the map from an AST node
fn SourceMap::build_from_node(self : SourceMap, node : ProjNode) -> Unit {
  let node_id = NodeId(node.node_id)
  let range = Range::new(node.start, node.end)
  self.node_to_range[node_id] = range

  // Process children
  for child in node.children {
    self.build_from_node(child)
  }
}

///|
/// Rebuild the sorted ranges array for efficient position queries
fn SourceMap::rebuild_ranges(self : SourceMap) -> Unit {
  self.ranges.clear()
  for node_id, range in self.node_to_range {
    self.ranges.push((range, node_id))
  }
  // Sort by start position, then by end position (larger ranges first)
  self.ranges.sort_by(fn(a, b) {
    let (range_a, _) = a
    let (range_b, _) = b
    if range_a.start != range_b.start {
      range_a.start.compare(range_b.start)
    } else {
      // Larger ranges (higher end) come first for proper nesting
      range_b.end.compare(range_a.end)
    }
  })
}

///|
/// Get the text range for a node
pub fn SourceMap::get_range(self : SourceMap, node_id : NodeId) -> Range? {
  self.node_to_range.get(node_id)
}

///|
fn SourceMap::node_to_range_at_position(
  self : SourceMap,
  position : Int,
) -> Map[NodeId, Range] {
  self.ranges
  .iter()
  .fold(init=Map::new(), fn(acc, item) {
    if item.0.contains(position) {
      acc.set(item.1, item.0)
    }
    acc
  })
}

///|
/// Find all nodes that contain a given position
/// Returns nodes from outermost to innermost (parent to child)
pub fn SourceMap::nodes_at_position(
  self : SourceMap,
  position : Int,
) -> Array[NodeId] {
  self.node_to_range_at_position(position).keys().to_array()
}

///|
/// Find the innermost (smallest) node containing a position
pub fn SourceMap::innermost_node_at(
  self : SourceMap,
  position : Int,
) -> NodeId? {
  self
  .node_to_range_at_position(position)
  .iter()
  .fold(init=None, fn(acc, item) {
    if acc is None {
      Some(item)
    } else if acc is Some(map) {
      let m = map.1.minimum_by_length(item.1)
      if m == map.1 {
        acc
      } else {
        Some(item)
      }
    } else {
      acc
    }
  })
  .map(fn(x) { x.0 })
}

///|
/// Find nodes whose ranges overlap with a given range
pub fn SourceMap::nodes_in_range(
  self : SourceMap,
  range : Range,
) -> Array[NodeId] {
  self.node_to_range
  .iter()
  .fold(init=[], fn(acc, item) {
    if range.start < item.1.end && range.end > item.1.start {
      acc.push(item.0)
    }
    acc
  })
}

///|
/// Update positions after a text deletion
/// Shifts all positions after the deleted range backward
pub fn SourceMap::apply_edit(
  self : SourceMap,
  edit_start : Int,
  old_range : Range,
) -> Unit {
  let delta = old_range.length()

  // Update all ranges
  let updated : Map[NodeId, Range] = {}
  for node_id, node_range in self.node_to_range {
    let new_range = if node_range.end <= edit_start {
      // Before edit - unchanged
      node_range
    } else if node_range.start >= old_range.end {
      // After deleted range - shift backward by delta
      Range::new(node_range.start - delta, node_range.end - delta)
    } else {
      // Overlaps with edit - complex case
      // Adjust positions based on overlap
      let new_start = node_range.start
      let new_end = if node_range.end <= old_range.end {
        node_range.end
      } else {
        // End extends past deleted range - shift backward
        node_range.end - delta
      }
      Range::new(new_start, new_end)
    }
    updated[node_id] = new_range
  }

  // Replace the map
  self.node_to_range.clear()
  for k, v in updated {
    self.node_to_range[k] = v
  }
  self.rebuild_ranges()
}

///|
/// Clear and rebuild from a new AST
pub fn SourceMap::rebuild(self : SourceMap, root : ProjNode) -> Unit {
  self.node_to_range.clear()
  self.ranges.clear()
  self.build_from_node(root)
  self.rebuild_ranges()
}

///|
/// Get the number of mapped nodes
pub fn SourceMap::node_count(self : SourceMap) -> Int {
  self.node_to_range.length()
}
