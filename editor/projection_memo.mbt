// Projection Memo: Reactive derivation of FlatProj, ProjNode, registry, and source map
// from SyncEditor's incremental parser-backed signals.
// @lambda_flat.VersionedFlatProj lives in @lambda_flat (lang/lambda/flat/) — imported here.

///|
/// Lambda-specific memo builder — wraps the lambda-specific FlatProj pipeline
/// and produces ProjNode[@ast.Term] memos for the SyncEditor constructor.
fn build_lambda_projection_memos(
  rt : @incr.Runtime,
  source_text : @incr.Signal[String],
  syntax_tree : @incr.Signal[@seam.SyntaxNode?],
  _parser : @loom.ImperativeParser[@ast.Term],
) -> (
  @incr.Memo[@lambda_flat.VersionedFlatProj],
  @incr.Memo[@proj.ProjNode[@ast.Term]?],
  @incr.Memo[Map[@proj.NodeId, @proj.ProjNode[@ast.Term]]],
  @incr.Memo[@proj.SourceMap],
) {
  let prev_flat_proj_ref : Ref[@proj.FlatProj?] = Ref::new(None)
  let prev_syntax_root_ref : Ref[@seam.SyntaxNode?] = Ref::new(None)
  let next_id_ref : Ref[Int] = Ref::new(0)
  // Change tracking side-channel: set by proj_memo, read by registry and source_map.
  // None = full rebuild needed (first parse, def count change, no prev root).
  // Some([]) = nothing changed. Some([2, 5]) = defs 2 and 5 changed. -1 = final_expr.
  let changed_def_indices_ref : Ref[Array[Int]?] = Ref::new(None)
  // Revision counter: bumped each time proj_memo recomputes. Downstream memos
  // track the last revision they processed. If they skipped revisions (lazy
  // access pattern), the delta in changed_def_indices_ref doesn't match their
  // prev state, so they must fall back to full rebuild.
  let proj_revision_ref : Ref[Int] = Ref::new(0)
  let proj_changed_at_ref : Ref[@incr.Revision] = Ref::new(
    @incr.Revision::initial(),
  )

  let proj_memo : @incr.Memo[@lambda_flat.VersionedFlatProj] = @incr.Memo::new_memo(
    rt,
    fn() -> @lambda_flat.VersionedFlatProj {
      if source_text.get() == "" {
        prev_flat_proj_ref.val = None
        prev_syntax_root_ref.val = None
        changed_def_indices_ref.val = None
        proj_changed_at_ref.val = proj_changed_at_ref.val.next()
        return @lambda_flat.VersionedFlatProj::{
          proj: None,
          changed_at: proj_changed_at_ref.val,
        }
      }
      let syntax_root = match syntax_tree.get() {
        Some(root) => root
        None => {
          prev_flat_proj_ref.val = None
          prev_syntax_root_ref.val = None
          changed_def_indices_ref.val = None
          proj_changed_at_ref.val = proj_changed_at_ref.val.next()
          return @lambda_flat.VersionedFlatProj::{
            proj: None,
            changed_at: proj_changed_at_ref.val,
          }
        }
      }
      let counter = Ref::new(next_id_ref.val)
      let result = match (prev_flat_proj_ref.val, prev_syntax_root_ref.val) {
        (Some(prev_fp), Some(prev_root)) => {
          let changed = Ref::new(([] : Array[Int]))
          let result = @proj.to_flat_proj_incremental(
            syntax_root,
            prev_root,
            prev_fp,
            counter,
            changed_indices=changed,
          )
          // Force full rebuild when structural shape changed:
          // - def count changed (indices not meaningful across different lengths)
          // - final_expr added or removed (patch path assumes stable child layout)
          // - expression-only document (no defs → ProjNode is not a Module,
          //   patch path's children[idx] logic doesn't apply)
          let final_expr_changed = match
            (prev_fp.final_expr, result.final_expr) {
            (Some(_), None) => true
            (None, Some(_)) => true
            _ => false
          }
          if result.defs.length() != prev_fp.defs.length() ||
            final_expr_changed ||
            result.defs.is_empty() {
            changed_def_indices_ref.val = None
          } else {
            // When there is no final_expr, to_proj_node_with_prev_module_id
            // synthesizes a fresh Unit body node (new node_id each time).
            // Always mark the body as changed so the patch path updates it.
            if result.final_expr is None && not(result.defs.is_empty()) {
              if not(changed.val.contains(-1)) {
                changed.val.push(-1)
              }
            }
            changed_def_indices_ref.val = Some(changed.val)
          }
          result
        }
        (Some(prev_fp), None) => {
          // No previous syntax root (e.g., after tree edit) — build fresh
          // and reconcile to preserve node IDs
          let new_fp = @proj.to_flat_proj(syntax_root, counter)
          changed_def_indices_ref.val = None
          @proj.reconcile_flat_proj(prev_fp, new_fp, counter)
        }
        _ => {
          changed_def_indices_ref.val = None
          @proj.to_flat_proj(syntax_root, counter)
        }
      }
      next_id_ref.val = counter.val
      prev_flat_proj_ref.val = Some(result)
      prev_syntax_root_ref.val = Some(syntax_root)
      proj_revision_ref.val = proj_revision_ref.val + 1
      // Advance changed_at only when content actually changed.
      // Some([]) = incremental, nothing changed → do not advance (backdate will fire).
      // Some([...]) or None = changes or full rebuild → advance.
      let has_changes = match changed_def_indices_ref.val {
        Some(indices) => not(indices.is_empty())
        None => true
      }
      if has_changes {
        proj_changed_at_ref.val = proj_changed_at_ref.val.next()
      }
      @lambda_flat.VersionedFlatProj::{
        proj: Some(result),
        changed_at: proj_changed_at_ref.val,
      }
    },
    label="proj_flat",
  )

  // Single conversion FlatProj -> ProjNode, shared by registry + source_map + get_proj_node.
  // Counter write-back ensures Unit fallback IDs don't collide with future IDs.
  // prev_module_id_ref holds the Module node_id from the most recent successful
  // conversion, so stable Module IDs survive incremental rebuilds.
  let prev_module_id_ref : Ref[Int?] = Ref::new(None)
  let cached_proj_node : @incr.Memo[@proj.ProjNode[@ast.Term]?] = @incr.Memo::new_no_backdate(
    rt,
    fn() -> @proj.ProjNode[@ast.Term]? {
      match proj_memo.get().proj {
        Some(fp) => {
          let counter = Ref::new(next_id_ref.val)
          let proj = fp.to_proj_node_with_prev_module_id(
            counter,
            prev_module_id_ref.val,
          )
          next_id_ref.val = counter.val
          // Remember the Module id (or the root id if no defs) for next rebuild
          prev_module_id_ref.val = Some(proj.node_id)
          Some(proj)
        }
        None =>
          // Keep prev_module_id_ref intact on transient projection misses
          // so stable Module IDs survive intermediate states.
          // Only the explicit empty-source paths in proj_memo clear it.
          None
      }
    },
    label="cached_proj_node",
  )

  let prev_registry_ref : Ref[Map[@proj.NodeId, @proj.ProjNode[@ast.Term]]?] = Ref::new(
    None,
  )
  let registry_prev_children_ref : Ref[Array[@proj.ProjNode[@ast.Term]]?] = Ref::new(
    None,
  )
  let registry_last_revision_ref : Ref[Int] = Ref::new(0)

  let registry_memo : @incr.Memo[Map[@proj.NodeId, @proj.ProjNode[@ast.Term]]] = @incr.Memo::new_no_backdate(
    rt,
    fn() -> Map[@proj.NodeId, @proj.ProjNode[@ast.Term]] {
      match cached_proj_node.get() {
        Some(root) => {
          // Detect revision skew: if this memo skipped revisions (wasn't
          // accessed on intermediate edits), the delta in changed_def_indices_ref
          // doesn't match our prev state. Fall back to full rebuild.
          let current_rev = proj_revision_ref.val
          let skipped = current_rev != registry_last_revision_ref.val + 1
          let registry = match
            (
              changed_def_indices_ref.val,
              prev_registry_ref.val,
              registry_prev_children_ref.val,
            ) {
            (Some(indices), Some(prev_reg), Some(prev_children)) if indices.length() >
              0 &&
              not(skipped) => {
              // Patch path: two-phase remove then add to avoid interleaving
              // issues when defs are reordered (a later remove could delete
              // an entry just added by an earlier iteration).
              // Phase 1: remove all old subtrees
              for idx in indices {
                if idx == -1 {
                  let last = prev_children.length() - 1
                  if last >= 0 {
                    unregister_subtree(prev_children[last], prev_reg)
                  }
                } else if idx >= 0 && idx < prev_children.length() {
                  unregister_subtree(prev_children[idx], prev_reg)
                }
              }
              // Phase 2: add all new subtrees
              for idx in indices {
                if idx == -1 {
                  let last = root.children.length() - 1
                  if last >= 0 {
                    register_node_tree(root.children[last], prev_reg)
                  }
                } else if idx >= 0 && idx < root.children.length() {
                  register_node_tree(root.children[idx], prev_reg)
                }
              }
              // Update the Module node itself (positions may have changed)
              prev_reg[root.id()] = root
              prev_reg
            }
            _ => {
              // Full rebuild
              let reg : Map[@proj.NodeId, @proj.ProjNode[@ast.Term]] = {}
              register_node_tree(root, reg)
              reg
            }
          }
          prev_registry_ref.val = Some(registry)
          registry_prev_children_ref.val = Some(root.children.copy())
          registry_last_revision_ref.val = current_rev
          registry
        }
        None => {
          prev_registry_ref.val = None
          registry_prev_children_ref.val = None
          registry_last_revision_ref.val = proj_revision_ref.val
          {}
        }
      }
    },
    label="proj_registry",
  )

  let prev_source_map_ref : Ref[@proj.SourceMap?] = Ref::new(None)
  let source_map_prev_children_ref : Ref[Array[@proj.ProjNode[@ast.Term]]?] = Ref::new(
    None,
  )
  let source_map_last_revision_ref : Ref[Int] = Ref::new(0)

  let source_map_memo : @incr.Memo[@proj.SourceMap] = @incr.Memo::new_no_backdate(
    rt,
    fn() -> @proj.SourceMap {
      match cached_proj_node.get() {
        Some(root) => {
          let current_rev = proj_revision_ref.val
          let skipped = current_rev != source_map_last_revision_ref.val + 1
          let sm = match
            (
              changed_def_indices_ref.val,
              prev_source_map_ref.val,
              source_map_prev_children_ref.val,
            ) {
            (Some(indices), Some(prev_sm), Some(prev_children)) if indices.length() >
              0 &&
              not(skipped) => {
              // Patch path: two-phase remove then add to avoid interleaving
              // issues when defs are reordered with ID-preserving reconciliation.
              // Phase 1: remove all old subtrees
              for idx in indices {
                if idx == -1 {
                  let last = prev_children.length() - 1
                  if last >= 0 {
                    prev_sm.remove_subtree(prev_children[last])
                  }
                } else if idx >= 0 && idx < prev_children.length() {
                  prev_sm.remove_subtree(prev_children[idx])
                }
              }
              // Phase 2: add all new subtrees
              for idx in indices {
                if idx == -1 {
                  let last = root.children.length() - 1
                  if last >= 0 {
                    prev_sm.patch_subtree(root.children[last])
                  }
                } else if idx >= 0 && idx < root.children.length() {
                  prev_sm.patch_subtree(root.children[idx])
                }
              }
              // Update Module node range
              prev_sm.node_to_range[root.id()] = @loom_core.Range::new(
                root.start,
                root.end,
              )
              prev_sm.rebuild_ranges()
              // Always repopulate ALL token spans from the SyntaxNode tree.
              // CstNode interning is position-independent, so reused defs may
              // have shifted offsets that only the SyntaxNode reflects correctly.
              match syntax_tree.get() {
                Some(syntax_root) =>
                  @proj.populate_token_spans(prev_sm, syntax_root, root)
                None => ()
              }
              prev_sm
            }
            _ => {
              // Full rebuild
              let new_sm = @proj.SourceMap::from_ast(root)
              match syntax_tree.get() {
                Some(syntax_root) =>
                  @proj.populate_token_spans(new_sm, syntax_root, root)
                None => ()
              }
              new_sm
            }
          }
          prev_source_map_ref.val = Some(sm)
          source_map_prev_children_ref.val = Some(root.children.copy())
          source_map_last_revision_ref.val = current_rev
          sm
        }
        None => {
          prev_source_map_ref.val = None
          source_map_prev_children_ref.val = None
          source_map_last_revision_ref.val = proj_revision_ref.val
          @proj.SourceMap::new()
        }
      }
    },
    label="source_map",
  )

  (proj_memo, cached_proj_node, registry_memo, source_map_memo)
}

///|
fn[T] register_node_tree(
  node : @proj.ProjNode[T],
  registry : Map[@proj.NodeId, @proj.ProjNode[T]],
) -> Unit {
  registry[node.id()] = node
  for child in node.children {
    register_node_tree(child, registry)
  }
}

///|
fn[T] unregister_subtree(
  node : @proj.ProjNode[T],
  registry : Map[@proj.NodeId, @proj.ProjNode[T]],
) -> Unit {
  registry.remove(node.id())
  for child in node.children {
    unregister_subtree(child, registry)
  }
}

///|
pub fn[T] SyncEditor::get_flat_proj(self : SyncEditor[T]) -> @proj.FlatProj? {
  self.proj_memo.get().proj
}

///|
/// Returns the cached ProjNode (converted from FlatProj once per invalidation).
pub fn[T] SyncEditor::get_proj_node(self : SyncEditor[T]) -> @proj.ProjNode[T]? {
  self.cached_proj_node.get()
}

///|
pub fn[T] SyncEditor::get_source_map(self : SyncEditor[T]) -> @proj.SourceMap {
  self.source_map_memo.get()
}

///|
pub fn[T] SyncEditor::get_node(
  self : SyncEditor[T],
  id : @proj.NodeId,
) -> @proj.ProjNode[T]? {
  self.registry_memo.get().get(id)
}

///|
pub fn[T] SyncEditor::node_at_position(
  self : SyncEditor[T],
  position : Int,
) -> @proj.NodeId? {
  self.source_map_memo.get().innermost_node_at(position)
}

///|
pub fn[T] SyncEditor::get_node_range(
  self : SyncEditor[T],
  id : @proj.NodeId,
) -> @loom_core.Range? {
  self.source_map_memo.get().get_range(id)
}
