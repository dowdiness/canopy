///|
pub(all) enum FlatProjItem {
  Def(String, ProjNode, Int, NodeId)
  Expr(ProjNode)
} derive(Show, Eq)

///|
pub struct FlatProj {
  items : Array[FlatProjItem]
} derive(Show, Eq)

///|
pub fn FlatProj::empty() -> FlatProj {
  { items: [] }
}

///|
/// Build a FlatProj from a SourceFile SyntaxNode.
/// Iterates LetDef and expression children and collects them as flat array entries.
/// Each init subtree is built via syntax_to_proj_node (unchanged).
pub fn to_flat_proj(root : @seam.SyntaxNode, counter : Ref[Int]) -> FlatProj {
  let items : Array[FlatProjItem] = []
  for child in root.children() {
    if @parser.LetDefView::cast(child) is Some(v) {
      let init = match v.init() {
        Some(n) => syntax_to_proj_node(n, counter)
        None =>
          error_node_for_syntax("missing let binding value", child, counter)
      }
      let id = NodeId(next_proj_node_id(counter))
      items.push(Def(v.name(), init, child.start(), id))
    } else {
      items.push(Expr(syntax_to_proj_node(child, counter)))
    }
  }
  { items, }
}

///|
/// Build a FlatProj incrementally by comparing old and new CST children.
///
/// For each child pair, compares underlying CstNodes. If unchanged
/// (physical_equal via NodeInterner), reuses the old FlatProj entry
/// directly — skipping both syntax_to_proj_node and reconcile_ast.
/// Only changed children are rebuilt and reconciled.
///
/// Cost: O(n) CstNode pointer comparisons + O(changed_subtree) rebuilds.
pub fn to_flat_proj_incremental(
  new_root : @seam.SyntaxNode,
  old_root : @seam.SyntaxNode,
  old_fp : FlatProj,
  counter : Ref[Int],
) -> FlatProj {
  // Extract children from old root, categorized
  let old_children : Array[@seam.SyntaxNode] = old_root.children()
  let new_children = new_root.children()
  // Parallel scan: compare new children against old children by index.
  // physical_equal checks pointer identity (same interned CstNode object).
  let items : Array[FlatProjItem] = []
  let mut any_changed = false
  for idx, new_child in new_children {
    if @parser.LetDefView::cast(new_child) is Some(v) {
      let mut reused = false
      if idx < old_children.length() && idx < old_fp.items.length() {
        let old_child = old_children[idx]
        if physical_equal(new_child.cst_node(), old_child.cst_node()) {
          // Same pointer — safe to reuse old entry with same positions
          items.push(old_fp.items[idx])
          reused = true
        }
      }
      if not(reused) {
        any_changed = true
        let init = match v.init() {
          Some(n) => syntax_to_proj_node(n, counter)
          None =>
            error_node_for_syntax(
              "missing let binding value", new_child, counter,
            )
        }
        let id = NodeId(next_proj_node_id(counter))
        items.push(Def(v.name(), init, new_child.start(), id))
      }
    } else {
      // Expression child
      let mut reused = false
      if idx < old_children.length() && idx < old_fp.items.length() {
        let old_child = old_children[idx]
        if physical_equal(new_child.cst_node(), old_child.cst_node()) {
          items.push(old_fp.items[idx])
          reused = true
        }
      }
      if not(reused) {
        any_changed = true
        items.push(Expr(syntax_to_proj_node(new_child, counter)))
      }
    }
  }
  // If number of items changed, that's also a change
  if old_fp.items.length() != items.length() {
    any_changed = true
  }
  let new_fp : FlatProj = { items, }
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
/// Generate keys for matching FlatProjItems.
/// Defs are keyed by name; Exprs by ordinal among expressions,
/// so identity is stable when Defs are inserted/removed around them.
fn item_keys(items : Array[FlatProjItem]) -> Array[String] {
  let keys : Array[String] = []
  let mut expr_ord = 0
  for i = 0; i < items.length(); i = i + 1 {
    match items[i] {
      Def(name, _, _, _) => keys.push("def:" + name)
      Expr(_) => {
        keys.push("expr:" + expr_ord.to_string())
        expr_ord += 1
      }
    }
  }
  keys
}

///|
/// Reconcile two FlatProjs, preserving node IDs where entries match.
/// O(n) hash-based matching on item keys; reconciles subtrees individually.
pub fn reconcile_flat_proj(
  old_fp : FlatProj,
  new_fp : FlatProj,
  counter : Ref[Int],
) -> FlatProj {
  let old_items = old_fp.items
  let new_items = new_fp.items
  let old_keys = item_keys(old_items)
  let new_keys = item_keys(new_items)
  let new_matched = key_match(old_keys, new_keys)

  // Build reconciled items
  let result_items : Array[FlatProjItem] = []
  for j = 0; j < new_items.length(); j = j + 1 {
    if new_matched[j] >= 0 {
      let old_item = old_items[new_matched[j]]
      match (old_item, new_items[j]) {
        (Def(_, old_init, _, old_id), Def(name, new_init, start, _)) => {
          let reconciled_init = reconcile_ast(old_init, new_init, counter)
          result_items.push(Def(name, reconciled_init, start, old_id))
        }
        (Expr(old_expr), Expr(new_expr)) => {
          let reconciled = reconcile_ast(old_expr, new_expr, counter)
          result_items.push(Expr(reconciled))
        }
        // Mismatched types shouldn't happen since keys would differ, but handle gracefully
        (_, new_item) => result_items.push(assign_fresh_item(new_item, counter))
      }
    } else {
      result_items.push(assign_fresh_item(new_items[j], counter))
    }
  }

  { items: result_items }
}

///|
/// Assign fresh IDs to a FlatProjItem.
fn assign_fresh_item(item : FlatProjItem, counter : Ref[Int]) -> FlatProjItem {
  match item {
    Def(name, init, start, _) => {
      let fresh_init = assign_fresh_ids(init, counter)
      let fresh_id = NodeId(next_proj_node_id(counter))
      Def(name, fresh_init, start, fresh_id)
    }
    Expr(expr) => Expr(assign_fresh_ids(expr, counter))
  }
}

///|
/// Reconstruct a Module ProjNode from FlatProj.
/// Uses stored NodeIds for the Module node. Counter only used for Unit fallback.
pub fn FlatProj::to_proj_node(self : FlatProj, counter : Ref[Int]) -> ProjNode {
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
) -> ProjNode {
  if self.items.is_empty() {
    return ProjNode::new(Unit, 0, 0, next_proj_node_id(counter), [])
  }
  // Check if there's only one Expr item with no Defs — return it directly
  if self.items.length() == 1 {
    match self.items[0] {
      Expr(expr) => return expr
      _ => ()
    }
  }
  let children : Array[ProjNode] = []
  let term_items : Array[@ast.ModuleItem] = []
  let mut start = 0
  let mut end = 0
  for i, item in self.items {
    match item {
      Def(name, init, def_start, _) => {
        children.push(init)
        term_items.push(@ast.ModuleItem::Def(name, init.kind))
        if i == 0 {
          start = def_start
        }
        end = init.end
      }
      Expr(expr) => {
        children.push(expr)
        term_items.push(@ast.ModuleItem::Expr(expr.kind))
        if i == 0 {
          start = expr.start
        }
        end = expr.end
      }
    }
  }
  let module_id = match prev_module_id {
    Some(id) => id
    None => next_proj_node_id(counter)
  }
  ProjNode::new(Module(term_items), start, end, module_id, children)
}

///|
/// Extract a FlatProj from a Module ProjNode.
/// Reads items from Module children and extracts the structure.
pub fn FlatProj::from_proj_node(root : ProjNode) -> FlatProj {
  match root.kind {
    Module(term_items) => {
      let items : Array[FlatProjItem] = []
      for i, item in term_items {
        if i < root.children.length() {
          let child = root.children[i]
          match item {
            @ast.ModuleItem::Def(name, _) =>
              items.push(Def(name, child, child.start, NodeId(child.node_id)))
            @ast.ModuleItem::Expr(_) => items.push(Expr(child))
          }
        }
      }
      { items, }
    }
    Unit => { items: [] }
    _ => { items: [Expr(root)] }
  }
}

///|
/// Print a FlatProj to text. Equivalent to @ast.print_term on the nested spine.
pub fn print_flat_proj(fp : FlatProj) -> String {
  let parts : Array[String] = []
  for item in fp.items {
    match item {
      Def(name, init, _, _) =>
        parts.push("let " + name + " = " + @ast.print_term(init.kind))
      Expr(expr) => parts.push(@ast.print_term(expr.kind))
    }
  }
  if parts.is_empty() {
    "()"
  } else {
    parts.join("\n")
  }
}
