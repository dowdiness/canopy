// TextLens: Bidirectional transformation between CanonicalModel and String
// Model ↔ Text (source code)

///|
/// Create a text lens for CanonicalModel ↔ String transformation
pub fn text_lens() -> Lens[CanonicalModel, String] {
  Lens::new(text_lens_get, text_lens_put)
}

///|
/// Create a text lens with diff capability
pub fn text_lens_with_diff() -> LensDiff[CanonicalModel, String, ProjectionEdit] {
  LensDiff::new(text_lens(), text_lens_diff)
}

///|
/// Get text from the canonical model (render AST to source code)
pub fn text_lens_get(model : CanonicalModel) -> Result[String, String] {
  match model.get_ast() {
    Some(ast) => Ok(@ast.print_term(ast.kind))
    None => Ok("")
  }
}

///|
/// Put text into the canonical model (parse text and reconcile with existing AST)
/// Returns the updated model (or error if parsing completely fails)
pub fn text_lens_put(
  model : CanonicalModel,
  text : String,
) -> Result[CanonicalModel, String] {
  // Parse the new text
  let (new_ast, _) = parse_to_proj_node(text)

  // Reconcile with existing AST to preserve node IDs where possible
  match model.get_ast() {
    Some(old_ast) => {
      let reconciled = reconcile_ast(old_ast, new_ast, model)
      model.set_ast(reconciled)
      Ok(model)
    }
    None => {
      model.set_ast(new_ast)
      Ok(model)
    }
  }
}

///|
/// Compute the difference between two text representations
pub fn text_lens_diff(
  old_text : String,
  new_text : String,
) -> Array[ProjectionEdit] {
  let edits : Array[ProjectionEdit] = []
  if old_text == new_text {
    return edits
  }

  // Find common prefix length
  let old_chars = old_text.to_array()
  let new_chars = new_text.to_array()
  let min_len = @cmp.minimum(old_chars.length(), new_chars.length())
  let mut prefix_len = 0
  while prefix_len < min_len && old_chars[prefix_len] == new_chars[prefix_len] {
    prefix_len = prefix_len + 1
  }

  // Find common suffix length (but don't overlap with prefix)
  let mut suffix_len = 0
  let old_remaining = old_chars.length() - prefix_len
  let new_remaining = new_chars.length() - prefix_len
  let max_suffix = @cmp.minimum(old_remaining, new_remaining)
  while suffix_len < max_suffix &&
        old_chars[old_chars.length() - 1 - suffix_len] ==
        new_chars[new_chars.length() - 1 - suffix_len] {
    suffix_len = suffix_len + 1
  }

  // Calculate the changed region
  let delete_start = prefix_len
  let delete_end = old_chars.length() - suffix_len
  let insert_start = prefix_len
  let insert_end = new_chars.length() - suffix_len

  // Generate edits for the changed region only
  // Insert first, then delete - this keeps positions valid during application
  if insert_end > insert_start {
    let inserted_text = new_chars[insert_start:insert_end]
      .iter()
      .fold(init=StringBuilder::new(), fn(sb, c) {
        sb.write_char(c)
        sb
      })
    edits.push(
      TextInsert(position=insert_start, text=inserted_text.to_string()),
    )
  }
  if delete_end > delete_start {
    // Adjust delete positions to account for the insert that happened first
    let insert_len = insert_end - insert_start
    edits.push(
      TextDelete(start=delete_start + insert_len, end=delete_end + insert_len),
    )
  }
  edits
}

///|
/// AST reconciliation: Preserve node IDs where possible when AST changes
/// This is crucial for maintaining cursor stability and projection sync
fn reconcile_ast(
  old : ProjNode,
  new : ProjNode,
  model : CanonicalModel,
) -> ProjNode {
  // If structurally identical (same kind), keep old node ID
  match (old.kind, new.kind) {
    // Same kinds - try to reconcile
    (Int(a), Int(b)) =>
      if a == b {
        old // Completely identical
      } else {
        // Value changed, keep old ID but update value
        ProjNode::new(new.kind, new.start, new.end, old.node_id, [])
      }
    (Var(a), Var(b)) =>
      if a == b {
        old
      } else {
        ProjNode::new(new.kind, new.start, new.end, old.node_id, [])
      }
    (Lam(param_old, _), Lam(param_new, _)) => {
      // Reconcile body (stored in children[0])
      let old_body = if old.children.length() > 0 {
        Some(old.children[0])
      } else {
        None
      }
      let new_body = if new.children.length() > 0 {
        Some(new.children[0])
      } else {
        None
      }
      let reconciled_body : Array[ProjNode] = match (old_body, new_body) {
        (Some(o), Some(n)) => [reconcile_ast(o, n, model)]
        (None, Some(n)) => [assign_fresh_ids(n, model)]
        (Some(_), None) => []
        (None, None) => []
      }
      let reconciled_body_kind = rebuild_kind(new.kind, reconciled_body)
      ProjNode::new(
        reconciled_body_kind,
        new.start,
        new.end,
        old.node_id,
        reconciled_body,
      )
    }
    (App(_, _), App(_, _)) => {
      // Reconcile both children
      let reconciled_children = reconcile_children(
        old.children,
        new.children,
        model,
      )
      ProjNode::new(
        rebuild_kind(new.kind, reconciled_children),
        new.start,
        new.end,
        old.node_id,
        reconciled_children,
      )
    }
    (Bop(_, _, _), Bop(_, _, _)) => {
      let reconciled_children = reconcile_children(
        old.children,
        new.children,
        model,
      )
      ProjNode::new(
        rebuild_kind(new.kind, reconciled_children),
        new.start,
        new.end,
        old.node_id,
        reconciled_children,
      )
    }
    (If(_, _, _), If(_, _, _)) => {
      let reconciled_children = reconcile_children(
        old.children,
        new.children,
        model,
      )
      ProjNode::new(
        rebuild_kind(new.kind, reconciled_children),
        new.start,
        new.end,
        old.node_id,
        reconciled_children,
      )
    }
    (Let(_, _, _), Let(_, _, _)) => {
      let reconciled_children = reconcile_children(
        old.children,
        new.children,
        model,
      )
      ProjNode::new(
        rebuild_kind(new.kind, reconciled_children),
        new.start,
        new.end,
        old.node_id,
        reconciled_children,
      )
    }
    // Different kinds - use new node with fresh ID
    _ => assign_fresh_ids(new, model)
  }
}

///|
/// Reconcile arrays of children using LCS (Longest Common Subsequence) matching.
/// LCS finds the best structural alignment between old and new children based on
/// their kind tags, preserving node IDs even when children are inserted, deleted,
/// or reordered.
fn reconcile_children(
  old_children : Array[ProjNode],
  new_children : Array[ProjNode],
  model : CanonicalModel,
) -> Array[ProjNode] {
  let old_len = old_children.length()
  let new_len = new_children.length()

  // Build LCS DP table
  // dp[i][j] = length of LCS of old_children[0..i] and new_children[0..j]
  let dp : Array[Array[Int]] = []
  for i = 0; i <= old_len; i = i + 1 {
    let row : Array[Int] = []
    for j = 0; j <= new_len; j = j + 1 {
      row.push(0)
    }
    dp.push(row)
  }
  for i = 1; i <= old_len; i = i + 1 {
    for j = 1; j <= new_len; j = j + 1 {
      if same_kind_tag(old_children[i - 1].kind, new_children[j - 1].kind) {
        dp[i][j] = dp[i - 1][j - 1] + 1
      } else {
        dp[i][j] = @cmp.maximum(dp[i - 1][j], dp[i][j - 1])
      }
    }
  }

  // Backtrack to find matched pairs
  // old_matched[i] = new index that old child i maps to (-1 if unmatched)
  // new_matched[j] = old index that new child j maps to (-1 if unmatched)
  let old_matched : Array[Int] = []
  let new_matched : Array[Int] = []
  for i = 0; i < old_len; i = i + 1 {
    old_matched.push(-1)
  }
  for j = 0; j < new_len; j = j + 1 {
    new_matched.push(-1)
  }
  let mut i = old_len
  let mut j = new_len
  while i > 0 && j > 0 {
    if same_kind_tag(old_children[i - 1].kind, new_children[j - 1].kind) {
      old_matched[i - 1] = j - 1
      new_matched[j - 1] = i - 1
      i = i - 1
      j = j - 1
    } else if dp[i - 1][j] >= dp[i][j - 1] {
      i = i - 1
    } else {
      j = j - 1
    }
  }

  // Build result array following new_children order
  let result : Array[ProjNode] = []
  for j = 0; j < new_len; j = j + 1 {
    if new_matched[j] >= 0 {
      // Matched with an old child - reconcile to preserve node IDs
      result.push(
        reconcile_ast(old_children[new_matched[j]], new_children[j], model),
      )
    } else {
      // Unmatched new child - assign fresh IDs
      result.push(assign_fresh_ids(new_children[j], model))
    }
  }

  // Unregister removed old children that weren't matched
  for i = 0; i < old_len; i = i + 1 {
    if old_matched[i] < 0 {
      unregister_node_tree_from_model(old_children[i], model)
    }
  }
  result
}

///|
/// Assign fresh node IDs to a tree
fn assign_fresh_ids(node : ProjNode, model : CanonicalModel) -> ProjNode {
  let new_id = model.new_node_id()
  let new_children : Array[ProjNode] = []
  for child in node.children {
    new_children.push(assign_fresh_ids(child, model))
  }
  ProjNode::new(node.kind, node.start, node.end, new_id.0, new_children)
}
