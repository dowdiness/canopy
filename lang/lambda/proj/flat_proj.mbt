// Lambda-specific FlatProj: flat representation of Module with per-def tracking.
// Moved from projection/flat_proj.mbt to separate language code from framework.

///|
pub struct FlatProj {
  defs : Array[(String, ProjNode[@ast.Term], Int, NodeId)] // (name, init, start, id)
  final_expr : ProjNode[@ast.Term]?
} derive(Show, Eq)

///|
pub fn FlatProj::empty() -> FlatProj {
  { defs: [], final_expr: None }
}

///|
/// Build a FlatProj from a SourceFile SyntaxNode.
/// Iterates LetDef children and collects them as flat array entries.
/// Each init subtree is built via syntax_to_proj_node (unchanged).
pub fn to_flat_proj(root : @seam.SyntaxNode, counter : Ref[Int]) -> FlatProj {
  let defs : Array[(String, ProjNode[@ast.Term], Int, NodeId)] = []
  let mut final_proj : ProjNode[@ast.Term]? = None
  for child in root.children() {
    if @parser.LetDefView::cast(child) is Some(v) {
      let init = match v.init() {
        Some(n) => syntax_to_proj_node(n, counter)
        None =>
          error_node_for_syntax("missing let binding value", child, counter)
      }
      let id = NodeId::from_int(@core.next_proj_node_id(counter))
      defs.push((v.name(), init, child.start(), id))
    } else if final_proj is None {
      final_proj = Some(syntax_to_proj_node(child, counter))
    }
  }
  { defs, final_expr: final_proj }
}

///|
/// Build a FlatProj incrementally by comparing old and new CST children.
///
/// For each child pair, compares underlying CstNodes. If unchanged
/// (physical_equal via NodeInterner), reuses the old FlatProj entry
/// directly — skipping both syntax_to_proj_node and reconcile.
/// Only changed children are rebuilt and reconciled.
///
/// Cost: O(n) CstNode pointer comparisons + O(changed_subtree) rebuilds.
pub fn to_flat_proj_incremental(
  new_root : @seam.SyntaxNode,
  old_root : @seam.SyntaxNode,
  old_fp : FlatProj,
  counter : Ref[Int],
  changed_indices? : Ref[Array[Int]] = Ref::new([]),
) -> FlatProj {
  // Extract LetDef children from old and new roots
  let new_children = new_root.children()
  let old_let_children : Array[@seam.SyntaxNode] = []
  let mut old_final_child : @seam.SyntaxNode? = None
  for child in old_root.children() {
    if @parser.LetDefView::cast(child) is Some(_) {
      old_let_children.push(child)
    } else if old_final_child is None {
      old_final_child = Some(child)
    }
  }
  // Parallel scan: compare new LetDefs against old LetDefs by index.
  // physical_equal checks pointer identity (same interned CstNode object).
  // When content and position are both unchanged, the parser returns
  // the exact same object, making physical_equal true.
  let defs : Array[(String, ProjNode[@ast.Term], Int, NodeId)] = []
  let mut final_proj : ProjNode[@ast.Term]? = None
  let mut old_def_idx = 0
  let mut any_changed = false
  for new_child in new_children {
    if @parser.LetDefView::cast(new_child) is Some(v) {
      let mut reused = false
      if old_def_idx < old_let_children.length() &&
        old_def_idx < old_fp.defs.length() {
        let old_child = old_let_children[old_def_idx]
        if physical_equal(new_child.cst_node(), old_child.cst_node()) {
          // Same pointer — safe to reuse old entry with same positions
          let old_entry = old_fp.defs[old_def_idx]
          defs.push((old_entry.0, old_entry.1, old_entry.2, old_entry.3))
          reused = true
        }
        old_def_idx = old_def_idx + 1
      }
      if not(reused) {
        any_changed = true
        changed_indices.val.push(defs.length())
        let init = match v.init() {
          Some(n) => syntax_to_proj_node(n, counter)
          None =>
            error_node_for_syntax(
              "missing let binding value", new_child, counter,
            )
        }
        let id = NodeId::from_int(@core.next_proj_node_id(counter))
        defs.push((v.name(), init, new_child.start(), id))
      }
    } else if final_proj is None {
      match old_final_child {
        Some(old_fc) if physical_equal(new_child.cst_node(), old_fc.cst_node()) =>
          final_proj = old_fp.final_expr
        _ => {
          any_changed = true
          changed_indices.val.push(-1)
          final_proj = Some(syntax_to_proj_node(new_child, counter))
        }
      }
    }
  }
  // If number of defs changed, that's also a change
  if old_fp.defs.length() != defs.length() {
    any_changed = true
  }
  let new_fp : FlatProj = { defs, final_expr: final_proj }
  if any_changed {
    reconcile_flat_proj(old_fp, new_fp, counter)
  } else {
    new_fp
  }
}

///|
/// O(n) hash-based key matching. For each new key, finds the corresponding
/// old index by consuming old entries in order per key.
/// Handles duplicate keys correctly via per-key cursors.
fn[K : Eq + Hash] key_match(
  old_keys : Array[K],
  new_keys : Array[K],
) -> Array[Int] {
  // Build: key -> ordered list of old indices
  let old_by_key : Map[K, Array[Int]] = {}
  for i = 0; i < old_keys.length(); i = i + 1 {
    match old_by_key.get(old_keys[i]) {
      Some(indices) => indices.push(i)
      None => old_by_key[old_keys[i]] = [i]
    }
  }
  // Consume in order per key
  let cursors : Map[K, Int] = {}
  let matched : Array[Int] = []
  for key in new_keys {
    let cursor = match cursors.get(key) {
      Some(c) => c
      None => 0
    }
    match old_by_key.get(key) {
      Some(indices) =>
        if cursor < indices.length() {
          matched.push(indices[cursor])
          cursors[key] = cursor + 1
        } else {
          matched.push(-1)
        }
      None => matched.push(-1)
    }
  }
  matched
}

///|
/// Reconcile two FlatProjs, preserving node IDs where entries match.
/// O(n) hash-based matching on def names; reconciles init subtrees individually.
pub fn reconcile_flat_proj(
  old_fp : FlatProj,
  new_fp : FlatProj,
  counter : Ref[Int],
) -> FlatProj {
  let old_defs = old_fp.defs
  let new_defs = new_fp.defs
  let old_names = old_defs.map(d => d.0)
  let new_names = new_defs.map(d => d.0)
  let new_matched = key_match(old_names, new_names)

  // Build reconciled defs
  let result_defs : Array[(String, ProjNode[@ast.Term], Int, NodeId)] = []
  for j = 0; j < new_defs.length(); j = j + 1 {
    let new_entry = new_defs[j]
    let name = new_entry.0
    let new_init = new_entry.1
    let start = new_entry.2
    if new_matched[j] >= 0 {
      let old_entry = old_defs[new_matched[j]]
      let reconciled_init = @core.reconcile(old_entry.1, new_init, counter)
      result_defs.push((name, reconciled_init, start, old_entry.3))
    } else {
      let fresh_init = @core.assign_fresh_ids(new_init, counter)
      let fresh_id = NodeId::from_int(@core.next_proj_node_id(counter))
      result_defs.push((name, fresh_init, start, fresh_id))
    }
  }

  // Reconcile final_expr
  let final_expr = match (old_fp.final_expr, new_fp.final_expr) {
    (Some(old_fe), Some(new_fe)) =>
      Some(@core.reconcile(old_fe, new_fe, counter))
    (None, Some(new_fe)) => Some(@core.assign_fresh_ids(new_fe, counter))
    (Some(_), None) => None
    (None, None) => None
  }

  { defs: result_defs, final_expr }
}

///|
/// Reconstruct a Module ProjNode from FlatProj.
/// Uses stored NodeIds for the Module node. Counter only used for Unit fallback.
pub fn FlatProj::to_proj_node(
  self : FlatProj,
  counter : Ref[Int],
) -> ProjNode[@ast.Term] {
  self.to_proj_node_with_prev_module_id(counter, None)
}

///|
/// Reconstruct a Module ProjNode from FlatProj, optionally reusing a previous
/// Module node_id for stability across rebuilds.
///
/// When `prev_module_id` is `Some(id)`, the Module node reuses that id instead
/// of allocating a fresh one from the counter. This ensures the root Module
/// node_id is stable across incremental rebuilds when the content hasn't
/// changed structurally — which is required for ProseMirror document identity.
pub fn FlatProj::to_proj_node_with_prev_module_id(
  self : FlatProj,
  counter : Ref[Int],
  prev_module_id : Int?,
) -> ProjNode[@ast.Term] {
  let body = match self.final_expr {
    Some(expr) => expr
    None => {
      // Use last def's end position so the synthetic Unit node doesn't
      // interfere with SourceMap position queries at offset 0.
      let end_pos = if self.defs.length() > 0 {
        self.defs[self.defs.length() - 1].1.end
      } else {
        0
      }
      ProjNode::new(Unit, end_pos, end_pos, @core.next_proj_node_id(counter), [])
    }
  }
  if self.defs.is_empty() {
    return body
  }
  let children : Array[ProjNode[@ast.Term]] = self.defs.map(d => d.1)
  children.push(body)
  let term_defs : Array[(@ast.VarName, @ast.Term)] = self.defs.map(d => {
    (d.0, d.1.kind)
  })
  let start = self.defs[0].2
  let module_id = match prev_module_id {
    Some(id) => id
    None => @core.next_proj_node_id(counter)
  }
  ProjNode::new(
    Module(term_defs, body.kind),
    start,
    body.end,
    module_id,
    children,
  )
}

///|
/// Extract a FlatProj from a Module ProjNode.
/// Reads def entries from Module children and extracts the body.
pub fn FlatProj::from_proj_node(root : ProjNode[@ast.Term]) -> FlatProj {
  match root.kind {
    Module(term_defs, _) => {
      let defs : Array[(String, ProjNode[@ast.Term], Int, NodeId)] = []
      for i = 0; i < term_defs.length(); i = i + 1 {
        if i < root.children.length() - 1 {
          let init_child = root.children[i]
          defs.push(
            (
              term_defs[i].0,
              init_child,
              init_child.start,
              NodeId::from_int(init_child.node_id),
            ),
          )
        }
      }
      let body_child = root.children[root.children.length() - 1]
      let final_expr = match body_child.kind {
        Unit => None
        _ => Some(body_child)
      }
      { defs, final_expr }
    }
    Unit => { defs: [], final_expr: None }
    _ => { defs: [], final_expr: Some(root) }
  }
}

///|
/// Print a FlatProj to text. Equivalent to @ast.print_term on the nested spine.
pub fn print_flat_proj(fp : FlatProj) -> String {
  let parts : Array[String] = []
  for def in fp.defs {
    let (name, init, _, _) = def
    parts.push("let " + name + " = " + @ast.print_term(init.kind))
  }
  match fp.final_expr {
    Some(expr) => parts.push(@ast.print_term(expr.kind))
    None => parts.push("()")
  }
  parts.join("\n")
}
