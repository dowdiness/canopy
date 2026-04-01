// SourceMap: Bidirectional mapping between AST nodes and text positions
// Enables efficient lookup in both directions for projectional editing

///|
using @loomcore {type Range}

///|
/// Maps between AST node IDs and their text positions
pub struct SourceMap {
  /// NodeId → Range mapping
  node_to_range : Map[NodeId, Range]
  /// Reverse index: position → candidate NodeIds (for point queries)
  /// Uses a simple array of (range, node_id) tuples sorted by start
  ranges : Array[(Range, NodeId)]
  /// Token-level spans within nodes (e.g., param name in lambda, binding name in let).
  /// Outer key = NodeId of containing node, inner key = token role name, value = Range.
  token_spans : Map[NodeId, Map[String, Range]]
} derive(Show, Eq)

///|
/// Create an empty SourceMap
pub fn SourceMap::new() -> SourceMap {
  { node_to_range: {}, ranges: [], token_spans: {} }
}

///|
/// Build a SourceMap from a ProjNode tree
pub fn[T] SourceMap::from_ast(root : ProjNode[T]) -> SourceMap {
  let map = SourceMap::new()
  map.build_from_node(root)
  map.rebuild_ranges()
  map
}

///|
/// Recursively build the map from an AST node
fn[T] SourceMap::build_from_node(self : SourceMap, node : ProjNode[T]) -> Unit {
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
pub fn SourceMap::rebuild_ranges(self : SourceMap) -> Unit {
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
/// Remove all entries for a ProjNode subtree from the source map.
/// Does NOT rebuild the sorted ranges array — call rebuild_ranges() after
/// all patches are done.
pub fn[T] SourceMap::remove_subtree(
  self : SourceMap,
  node : ProjNode[T],
) -> Unit {
  let node_id = NodeId::from_int(node.node_id)
  self.node_to_range.remove(node_id)
  self.token_spans.remove(node_id)
  for child in node.children {
    self.remove_subtree(child)
  }
}

///|
/// Add entries for a ProjNode subtree to the source map.
/// Clears any stale token_spans for patched nodes — call
/// populate_token_spans() afterward to repopulate them.
/// Does NOT rebuild the sorted ranges array — call rebuild_ranges() after
/// all patches are done.
pub fn[T] SourceMap::patch_subtree(
  self : SourceMap,
  node : ProjNode[T],
) -> Unit {
  let node_id = NodeId::from_int(node.node_id)
  self.node_to_range[node_id] = Range::new(node.start, node.end)
  self.token_spans.remove(node_id)
  for child in node.children {
    self.patch_subtree(child)
  }
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
/// Shift a range by `delta` using the same deletion semantics as node ranges.
fn shift_range(
  r : Range,
  edit_start : Int,
  old_end : Int,
  delta : Int,
) -> Range {
  if r.end <= edit_start {
    r
  } else if r.start >= old_end {
    Range::new(r.start - delta, r.end - delta)
  } else {
    let new_end = if r.end <= old_end { r.end } else { r.end - delta }
    Range::new(r.start, new_end)
  }
}

///|
/// Update positions after a text deletion.
/// Shifts all node ranges and token spans after the deleted range backward.
pub fn SourceMap::apply_edit(
  self : SourceMap,
  edit_start : Int,
  old_range : Range,
) -> Unit {
  let delta = old_range.length()
  let old_end = old_range.end

  // Update node ranges
  let updated : Map[NodeId, Range] = {}
  for node_id, node_range in self.node_to_range {
    updated[node_id] = shift_range(node_range, edit_start, old_end, delta)
  }
  self.node_to_range.clear()
  for k, v in updated {
    self.node_to_range[k] = v
  }

  // Shift token spans by the same delta
  for _node_id, roles in self.token_spans {
    let shifted : Array[(String, Range)] = []
    for role, span in roles {
      shifted.push((role, shift_range(span, edit_start, old_end, delta)))
    }
    for pair in shifted {
      roles[pair.0] = pair.1
    }
  }

  self.rebuild_ranges()
}

///|
/// Clear and rebuild from a new AST.
/// Note: this clears token_spans. Call populate_token_spans() afterward
/// if token-level spans are needed.
pub fn[T] SourceMap::rebuild(self : SourceMap, root : ProjNode[T]) -> Unit {
  self.node_to_range.clear()
  self.ranges.clear()
  self.token_spans.clear()
  self.build_from_node(root)
  self.rebuild_ranges()
}

///|
/// Get the number of mapped nodes
pub fn SourceMap::node_count(self : SourceMap) -> Int {
  self.node_to_range.length()
}

///|
/// Set a token-level span for a specific role within a node.
/// For example, set_token_span(lambda_id, "param", Range::new(2, 3))
/// records that the param name occupies characters 2..3.
pub fn SourceMap::set_token_span(
  self : SourceMap,
  node_id : NodeId,
  role : String,
  range : Range,
) -> Unit {
  match self.token_spans.get(node_id) {
    Some(roles) => roles[role] = range
    None => {
      let roles : Map[String, Range] = {}
      roles[role] = range
      self.token_spans[node_id] = roles
    }
  }
}

///|
/// Get the token-level span for a specific role within a node.
/// Returns None if no token span is recorded for that node/role.
pub fn SourceMap::get_token_span(
  self : SourceMap,
  node_id : NodeId,
  role : String,
) -> Range? {
  match self.token_spans.get(node_id) {
    Some(roles) => roles.get(role)
    None => None
  }
}

///|
/// Get all token-level spans for a node as (role, range) pairs sorted by
/// range start position. Returns an empty array if no spans are recorded.
pub fn SourceMap::get_all_token_spans(
  self : SourceMap,
  node_id : NodeId,
) -> Array[(String, Range)] {
  match self.token_spans.get(node_id) {
    Some(roles) => {
      let pairs : Array[(String, Range)] = []
      for role, range in roles {
        pairs.push((role, range))
      }
      pairs.sort_by(fn(a, b) { a.1.start.compare(b.1.start) })
      pairs
    }
    None => []
  }
}
