// Lambda projection memo builder.
// Uses the shared generic 3-memo projection pipeline: ProjNode, registry,
// and SourceMap. Lambda supplies a small root-module reconciliation hook so
// reordered `let` definitions keep their binding IDs without reviving the
// deleted flat projection memo stack.

///|
/// Build the 3-memo pipeline (proj, registry, source_map) for the Lambda
/// editor-facing projection.
pub fn build_lambda_projection_memos(
  parser : @loom.Parser[@ast.Term],
) -> (
  @incr.Derived[@core.ProjNode[@ast.Term]?],
  @incr.Derived[Map[@core.NodeId, @core.ProjNode[@ast.Term]]],
  @incr.Derived[@core.SourceMap],
) {
  @core.build_projection_memos(
    parser.runtime(),
    parser.syntax_tree(),
    to_proj_node,
    populate_token_spans,
    reconcile_node=reconcile_lambda_projection,
    label="lambda",
  )
}

///|
/// O(n) duplicate-safe key matching. For each new key, finds the corresponding
/// old index by consuming old entries in source order per key.
///
/// Existing APIs checked: `@core.reconcile` and `@core.assign_fresh_ids` own
/// identity preservation once a matching pair is known, but neither chooses a
/// domain key for top-level Lambda definition rows. `DefinitionIndex` exposes
/// module definitions by `ProjNode`, but it intentionally does not own
/// cross-version matching. This helper's responsibility is limited to
/// occurrence-stable name matching for Lambda's root-module reconcile hook.
fn[K : Eq + Hash] module_key_match(
  old_keys : Array[K],
  new_keys : Array[K],
) -> Array[Int?] {
  let old_by_key : Map[K, Array[Int]] = {}
  for i, key in old_keys {
    match old_by_key.get(key) {
      Some(indices) => indices.push(i)
      None => old_by_key[key] = [i]
    }
  }
  let cursors : Map[K, Int] = {}
  [
    for key in new_keys => {
      let cursor = cursors.get(key).unwrap_or(0)
      match old_by_key.get(key) {
        Some(indices) if cursor < indices.length() => {
          cursors[key] = cursor + 1
          Some(indices[cursor])
        }
        _ => None
      }
    }
  ]
}

///|
fn reconcile_module_child(
  old_children : Array[@core.ProjNode[@ast.Term]],
  new_child : @core.ProjNode[@ast.Term],
  matched_index : Int?,
  counter : Ref[Int],
) -> @core.ProjNode[@ast.Term] {
  match matched_index {
    Some(i) =>
      match old_children.get(i) {
        Some(old_child) => @core.reconcile(old_child, new_child, counter)
        None => @core.assign_fresh_ids(new_child, counter)
      }
    None => @core.assign_fresh_ids(new_child, counter)
  }
}

///|
/// Reconcile Lambda's root module with definition-name keys before falling
/// back to generic shape-based reconciliation. Generic sibling LCS is correct
/// for ordinary expression children, but top-level `LetDef` siblings all share
/// the same kind; matching those rows by source position would reassign binding
/// IDs when definitions are reordered.
fn reconcile_lambda_projection(
  old : @core.ProjNode[@ast.Term],
  new_ : @core.ProjNode[@ast.Term],
  counter : Ref[Int],
) -> @core.ProjNode[@ast.Term] {
  match (old.kind, new_.kind) {
    (Module(old_defs, _), Module(new_defs, _)) => {
      guard old.children.get(old_defs.length()) is Some(old_body) else {
        return @core.reconcile(old, new_, counter)
      }
      guard new_.children.get(new_defs.length()) is Some(new_body) else {
        return @core.reconcile(old, new_, counter)
      }
      let new_matched = module_key_match(
        old_defs.map(def => def.0),
        new_defs.map(def => def.0),
      )
      let children : Array[@core.ProjNode[@ast.Term]] = [
        for j in 0..<new_defs.length() => {
          reconcile_module_child(
            old.children,
            new_.children[j],
            new_matched[j],
            counter,
          )
        }
      ]
      children.push(@core.reconcile(old_body, new_body, counter))
      @core.ProjNode::new(
        new_.kind,
        new_.start,
        new_.end,
        old.node_id,
        children,
      )
    }
    _ => @core.reconcile(old, new_, counter)
  }
}
