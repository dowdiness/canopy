// Lambda projection memo builder.
// Uses the shared generic 3-memo projection pipeline: ProjNode, registry,
// and SourceMap. Lambda supplies a small root-module reconciliation hook so
// reordered `let` definitions keep their binding IDs without reviving the
// deleted flat projection memo stack.

///|
/// Convert a flat ordered list of structural-edit hints to the `NodeId`-keyed
/// map that `@core.reconcile_hinted` consumes.
///
/// Returns an empty map if any hint is `Opaque` (T2: degrade to LCS).
/// The caller is responsible for clearing the hint array after this call (T4).
fn build_hints_map(
  hints : Array[@core.IdentityTransform],
) -> Map[@core.NodeId, @core.IdentityTransform] {
  let result : Map[@core.NodeId, @core.IdentityTransform] = {}
  for hint in hints {
    match hint {
      @core.IdentityTransform::Opaque => return {}
      @core.IdentityTransform::Wrap(inner=id) => result[id] = hint
      @core.IdentityTransform::Unwrap(wrapper=id, ..) => result[id] = hint
      @core.IdentityTransform::Move(subtree=id) => result[id] = hint
      @core.IdentityTransform::Replace(old=id) => result[id] = hint
      @core.IdentityTransform::RenameLeaf(node=id) => result[id] = hint
      @core.IdentityTransform::InsertSubtree(parent=id, ..) => result[id] = hint
      @core.IdentityTransform::DeleteSubtree(node=id) => result[id] = hint
    }
  }
  result
}

///|
fn reconcile_module_child_hinted(
  old_children : Array[@core.ProjNode[@ast.Term]],
  new_child : @core.ProjNode[@ast.Term],
  matched_index : Int?,
  counter : Ref[Int],
  hints : Map[@core.NodeId, @core.IdentityTransform],
  trace_ref? : Ref[Array[@core.ReconcileTraceEvent]]? = None,
) -> @core.ProjNode[@ast.Term] {
  match matched_index {
    Some(i) =>
      match old_children.get(i) {
        Some(old_child) =>
          @core.reconcile_hinted(
            old_child,
            new_child,
            counter,
            hints,
            trace_ref~,
          )
        None => @core.assign_fresh_ids(new_child, counter)
      }
    None => @core.assign_fresh_ids(new_child, counter)
  }
}

///|
/// Variant of `reconcile_lambda_projection` that threads structural-edit hints
/// through to `@core.reconcile_hinted`. The hint map is keyed by prev-tree
/// `NodeId`; an empty map degrades to the same behaviour as `reconcile_lambda_projection`.
fn reconcile_lambda_projection_hinted(
  old : @core.ProjNode[@ast.Term],
  new_ : @core.ProjNode[@ast.Term],
  counter : Ref[Int],
  hints : Map[@core.NodeId, @core.IdentityTransform],
  trace_ref? : Ref[Array[@core.ReconcileTraceEvent]]? = None,
) -> @core.ProjNode[@ast.Term] {
  match (old.kind, new_.kind) {
    (Module(old_defs, _), Module(new_defs, _)) => {
      guard old.children.get(old_defs.length()) is Some(old_body) else {
        return @core.reconcile_hinted(old, new_, counter, hints, trace_ref~)
      }
      guard new_.children.get(new_defs.length()) is Some(new_body) else {
        return @core.reconcile_hinted(old, new_, counter, hints, trace_ref~)
      }
      let new_matched = module_key_match(
        old_defs.map(def => def.0),
        new_defs.map(def => def.0),
      )
      let children : Array[@core.ProjNode[@ast.Term]] = [
        for j in 0..<new_defs.length() => {
          reconcile_module_child_hinted(
            old.children,
            new_.children[j],
            new_matched[j],
            counter,
            hints,
            trace_ref~,
          )
        }
      ]
      children.push(
        @core.reconcile_hinted(old_body, new_body, counter, hints, trace_ref~),
      )
      @core.ProjNode(new_.kind, new_.start, new_.end, old.node_id, children)
    }
    _ => @core.reconcile_hinted(old, new_, counter, hints, trace_ref~)
  }
}

///|
/// Build the 3-memo pipeline (proj, registry, source_map) for the Lambda
/// editor-facing projection.
///
/// `identity_hints` is the shared `Ref` for the structural-edit hint channel,
/// typically created by `new_lambda_editor` and passed here and into
/// `SyncEditor::new_generic` as `identity_hints`. When provided, each reconcile
/// pass consumes+clears the pending hints (T4). When omitted, behaves identically
/// to passing no hints (falls back to `reconcile_lambda_projection`).
pub fn build_lambda_projection_memos(
  parser : @loom.Parser[@ast.Term],
  identity_hints? : Ref[Array[@core.IdentityTransform]],
  trace_ref? : Ref[Array[@core.ReconcileTraceEvent]]? = None,
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
    reconcile_node=fn(old, new_, counter, tr) {
      match identity_hints {
        None => reconcile_lambda_projection(old, new_, counter, trace_ref=tr)
        Some(hints_ref) => {
          let hints = build_hints_map(hints_ref.val)
          hints_ref.val = [] // T4: cleared exactly once per reparse
          reconcile_lambda_projection_hinted(
            old,
            new_,
            counter,
            hints,
            trace_ref=tr,
          )
        }
      }
    },
    trace_ref~,
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
  trace_ref? : Ref[Array[@core.ReconcileTraceEvent]]? = None,
) -> @core.ProjNode[@ast.Term] {
  match matched_index {
    Some(i) =>
      match old_children.get(i) {
        Some(old_child) =>
          @core.reconcile(old_child, new_child, counter, trace_ref~)
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
  trace_ref? : Ref[Array[@core.ReconcileTraceEvent]]? = None,
) -> @core.ProjNode[@ast.Term] {
  match (old.kind, new_.kind) {
    (Module(old_defs, _), Module(new_defs, _)) => {
      guard old.children.get(old_defs.length()) is Some(old_body) else {
        return @core.reconcile(old, new_, counter, trace_ref~)
      }
      guard new_.children.get(new_defs.length()) is Some(new_body) else {
        return @core.reconcile(old, new_, counter, trace_ref~)
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
            trace_ref~,
          )
        }
      ]
      children.push(@core.reconcile(old_body, new_body, counter, trace_ref~))
      @core.ProjNode(new_.kind, new_.start, new_.end, old.node_id, children)
    }
    _ => @core.reconcile(old, new_, counter, trace_ref~)
  }
}
