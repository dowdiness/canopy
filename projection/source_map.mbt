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
  let node_id = NodeId(node.node_id)
  self.node_to_range.remove(node_id)
  self.token_spans.remove(node_id)
  for child in node.children {
    self.remove_subtree(child)
  }
}

///|
/// Add entries for a ProjNode subtree to the source map.
/// Does NOT rebuild the sorted ranges array — call rebuild_ranges() after
/// all patches are done.
pub fn[T] SourceMap::patch_subtree(
  self : SourceMap,
  node : ProjNode[T],
) -> Unit {
  let node_id = NodeId(node.node_id)
  self.node_to_range[node_id] = Range::new(node.start, node.end)
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
/// Populate token-level spans by walking a SyntaxNode tree in parallel
/// with a ProjNode tree. Extracts param name spans from LambdaExpr nodes
/// and binding name spans from LetDef nodes.
///
/// Must be called after from_ast() with the corresponding syntax tree.
pub fn SourceMap::populate_token_spans(
  self : SourceMap,
  syntax_root : @seam.SyntaxNode,
  proj_root : ProjNode[@ast.Term],
) -> Unit {
  self.collect_token_spans_source_file(syntax_root, proj_root)
}

///|
/// Walk a SourceFile syntax node and its corresponding Module ProjNode.
/// Handles LetDef children at the top level and delegates expression
/// children to collect_token_spans_expr.
fn SourceMap::collect_token_spans_source_file(
  self : SourceMap,
  syntax_root : @seam.SyntaxNode,
  proj_root : ProjNode[@ast.Term],
) -> Unit {
  // For a Module ProjNode, children are: [init_0, init_1, ..., body]
  // The syntax_root has LetDef children and optionally a final expression child.
  match proj_root.kind {
    Module(defs, _) => {
      let syntax_children = syntax_root.children()
      let mut def_idx = 0
      let mut expr_seen = false
      for syn_child in syntax_children {
        if @parser.LetDefView::cast(syn_child) is Some(v) {
          if def_idx < defs.length() && def_idx < proj_root.children.length() {
            // The ProjNode child at def_idx is the init expression, but
            // the LetDef's name token belongs to the LetDef itself.
            // We need a NodeId for the LetDef. In the current FlatProj model,
            // LetDef nodes don't have their own ProjNode — the Module node
            // owns the defs array. So we store the name span on the Module
            // node with a role like "name:0", "name:1", etc.
            let ident_token = syn_child.find_token(@syntax.IdentToken.to_raw())
            match ident_token {
              Some(tok) => {
                // Use index-based key for stability across renames
                let role = "name:" + def_idx.to_string()
                self.set_token_span(
                  proj_root.id(),
                  role,
                  Range::new(tok.start(), tok.end()),
                )
              }
              None => ()
            }
            // Recurse into the init expression
            match v.init() {
              Some(init_syn) =>
                self.collect_token_spans_expr(
                  init_syn,
                  proj_root.children[def_idx],
                )
              None => ()
            }
          }
          def_idx = def_idx + 1
        } else if not(expr_seen) {
          expr_seen = true
          // This is the final expression — last child of Module ProjNode
          let body_idx = proj_root.children.length() - 1
          if body_idx >= 0 {
            self.collect_token_spans_expr(
              syn_child,
              proj_root.children[body_idx],
            )
          }
        }
      }
    }
    _ => {
      // Not a Module — the ProjNode is a single expression.
      // The syntax_root is a SourceFile; find the first non-LetDef child.
      let syntax_children = syntax_root.children()
      for syn_child in syntax_children {
        if @parser.LetDefView::cast(syn_child) is None {
          self.collect_token_spans_expr(syn_child, proj_root)
          break
        }
      }
    }
  }
}

///|
/// Walk an expression-level syntax node alongside its ProjNode counterpart.
/// Extracts token spans for lambda params and recurses into children.
fn SourceMap::collect_token_spans_expr(
  self : SourceMap,
  syntax_node : @seam.SyntaxNode,
  proj_node : ProjNode[@ast.Term],
) -> Unit {
  if @parser.LambdaExprView::cast(syntax_node) is Some(v) {
    // Extract param token span
    let ident_token = syntax_node.find_token(@syntax.IdentToken.to_raw())
    match ident_token {
      Some(tok) =>
        self.set_token_span(
          proj_node.id(),
          "param",
          Range::new(tok.start(), tok.end()),
        )
      None => ()
    }
    // Recurse into body
    match v.body() {
      Some(body_syn) =>
        if proj_node.children.length() > 0 {
          self.collect_token_spans_expr(body_syn, proj_node.children[0])
        }
      None => ()
    }
  } else if @parser.AppExprView::cast(syntax_node) is Some(v) {
    // AppExpr is flattened: syntax has [func, arg1, arg2, ...]
    // ProjNode is nested: App(App(func, arg1), arg2)
    // We need to walk the nested ProjNode tree matching the flat syntax.
    match v.func() {
      Some(func_syn) => {
        let args = v.args()
        if args.length() == 0 {
          // Single func, no args — just recurse
          self.collect_token_spans_expr(func_syn, proj_node)
        } else {
          // Navigate to the innermost App (leftmost) which contains func
          let mut current_proj = proj_node
          // Walk down left children to find the innermost
          let depth = args.length()
          let proj_chain : Array[ProjNode[@ast.Term]] = []
          proj_chain.push(current_proj)
          for i = 0; i < depth - 1; i = i + 1 {
            if current_proj.children.length() >= 1 {
              current_proj = current_proj.children[0]
              proj_chain.push(current_proj)
            }
          }
          // Now proj_chain[-1] is the innermost App(func, arg1)
          let innermost = proj_chain[proj_chain.length() - 1]
          if innermost.children.length() >= 2 {
            self.collect_token_spans_expr(func_syn, innermost.children[0])
            self.collect_token_spans_expr(args[0], innermost.children[1])
          }
          // Walk back up: proj_chain[i]'s right child = args[chain_len - 1 - i]
          for i = proj_chain.length() - 2; i >= 0; i = i - 1 {
            let parent = proj_chain[i]
            let arg_idx = proj_chain.length() - 1 - i
            if arg_idx < args.length() && parent.children.length() >= 2 {
              self.collect_token_spans_expr(args[arg_idx], parent.children[1])
            }
          }
        }
      }
      None => ()
    }
  } else if @parser.BinaryExprView::cast(syntax_node) is Some(v) {
    // BinaryExpr operands are flat in CST, nested in ProjNode
    let operands = v.operands()
    if operands.length() <= 1 {
      if operands.length() == 1 {
        self.collect_token_spans_expr(operands[0], proj_node)
      }
    } else {
      // Navigate nested Bop tree: Bop(Bop(a, b), c) for a + b + c
      let mut current_proj = proj_node
      let depth = operands.length() - 1
      let proj_chain : Array[ProjNode[@ast.Term]] = []
      proj_chain.push(current_proj)
      for i = 0; i < depth - 1; i = i + 1 {
        if current_proj.children.length() >= 1 {
          current_proj = current_proj.children[0]
          proj_chain.push(current_proj)
        }
      }
      // Innermost: Bop(operands[0], operands[1])
      let innermost = proj_chain[proj_chain.length() - 1]
      if innermost.children.length() >= 2 {
        self.collect_token_spans_expr(operands[0], innermost.children[0])
        self.collect_token_spans_expr(operands[1], innermost.children[1])
      }
      // BinaryExpr innermost eats operands[0] and operands[1],
      // so back-walk starts from operands[2]: op_idx = chain.length() - i
      for i = proj_chain.length() - 2; i >= 0; i = i - 1 {
        let parent = proj_chain[i]
        let op_idx = proj_chain.length() - i
        if op_idx < operands.length() && parent.children.length() >= 2 {
          self.collect_token_spans_expr(operands[op_idx], parent.children[1])
        }
      }
    }
  } else if @parser.IfExprView::cast(syntax_node) is Some(v) {
    match v.condition() {
      Some(cond) =>
        if proj_node.children.length() > 0 {
          self.collect_token_spans_expr(cond, proj_node.children[0])
        }
      None => ()
    }
    match v.then_branch() {
      Some(then_) =>
        if proj_node.children.length() > 1 {
          self.collect_token_spans_expr(then_, proj_node.children[1])
        }
      None => ()
    }
    match v.else_branch() {
      Some(else_) =>
        if proj_node.children.length() > 2 {
          self.collect_token_spans_expr(else_, proj_node.children[2])
        }
      None => ()
    }
  } else if @parser.ParenExprView::cast(syntax_node) is Some(v) {
    // ParenExpr unwraps: ProjNode reuses inner's node_id and children
    match v.inner() {
      Some(inner) => self.collect_token_spans_expr(inner, proj_node)
      None => ()
    }
  }
  // IntLiteral, VarRef: leaf nodes, no token spans to extract
}
