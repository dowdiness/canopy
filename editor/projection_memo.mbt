// Projection Memo: Reactive derivation of FlatProj, ProjNode, registry, and source map
// from SyncEditor's incremental parser-backed signals.

///|
fn build_projection_memos(
  rt : @incr.Runtime,
  source_text : @incr.Signal[String],
  syntax_tree : @incr.Signal[@seam.SyntaxNode?],
  prev_flat_proj_ref : Ref[@proj.FlatProj?],
  prev_syntax_root_ref : Ref[@seam.SyntaxNode?],
  next_id_ref : Ref[Int],
) -> (
  @incr.Memo[@proj.FlatProj?],
  @incr.Memo[@proj.ProjNode?],
  @incr.Memo[Map[@proj.NodeId, @proj.ProjNode]],
  @incr.Memo[@proj.SourceMap],
) {
  let proj_memo : @incr.Memo[@proj.FlatProj?] = @incr.Memo::new(
    rt,
    fn() -> @proj.FlatProj? {
      if source_text.get() == "" {
        prev_flat_proj_ref.val = None
        prev_syntax_root_ref.val = None
        return None
      }
      let syntax_root = match syntax_tree.get() {
        Some(root) => root
        None => {
          prev_flat_proj_ref.val = None
          prev_syntax_root_ref.val = None
          return None
        }
      }
      let counter = Ref::new(next_id_ref.val)
      let result = match (prev_flat_proj_ref.val, prev_syntax_root_ref.val) {
        (Some(prev_fp), Some(prev_root)) =>
          // Incremental path: compare CST children via physical_equal
          @proj.to_flat_proj_incremental(
            syntax_root, prev_root, prev_fp, counter,
          )
        (Some(prev_fp), None) => {
          // No previous syntax root (e.g., after tree edit) — build fresh
          // and reconcile to preserve node IDs
          let new_fp = @proj.to_flat_proj(syntax_root, counter)
          @proj.reconcile_flat_proj(prev_fp, new_fp, counter)
        }
        _ => @proj.to_flat_proj(syntax_root, counter)
      }
      next_id_ref.val = counter.val
      prev_flat_proj_ref.val = Some(result)
      prev_syntax_root_ref.val = Some(syntax_root)
      Some(result)
    },
    label="proj_node",
  )

  // Single conversion FlatProj -> ProjNode, shared by registry + source_map + get_proj_node.
  // Counter write-back ensures Unit fallback IDs don't collide with future IDs.
  let cached_proj_node : @incr.Memo[@proj.ProjNode?] = @incr.Memo::new(
    rt,
    fn() -> @proj.ProjNode? {
      match proj_memo.get() {
        Some(fp) => {
          let counter = Ref::new(next_id_ref.val)
          let proj = fp.to_proj_node(counter)
          next_id_ref.val = counter.val
          Some(proj)
        }
        None => None
      }
    },
    label="cached_proj_node",
  )

  let registry_memo : @incr.Memo[Map[@proj.NodeId, @proj.ProjNode]] = @incr.Memo::new(
    rt,
    fn() -> Map[@proj.NodeId, @proj.ProjNode] {
      let registry : Map[@proj.NodeId, @proj.ProjNode] = {}
      match cached_proj_node.get() {
        Some(root) => register_node_tree(root, registry)
        None => ()
      }
      registry
    },
    label="proj_registry",
  )

  let source_map_memo : @incr.Memo[@proj.SourceMap] = @incr.Memo::new(
    rt,
    fn() -> @proj.SourceMap {
      match cached_proj_node.get() {
        Some(root) => @proj.SourceMap::from_ast(root)
        None => @proj.SourceMap::new()
      }
    },
    label="source_map",
  )

  (proj_memo, cached_proj_node, registry_memo, source_map_memo)
}

///|
fn register_node_tree(
  node : @proj.ProjNode,
  registry : Map[@proj.NodeId, @proj.ProjNode],
) -> Unit {
  registry[node.id()] = node
  for child in node.children {
    register_node_tree(child, registry)
  }
}

///|
pub fn SyncEditor::get_flat_proj(self : SyncEditor) -> @proj.FlatProj? {
  self.proj_memo.get()
}

///|
/// Returns the cached ProjNode (converted from FlatProj once per invalidation).
pub fn SyncEditor::get_proj_node(self : SyncEditor) -> @proj.ProjNode? {
  self.cached_proj_node.get()
}

///|
pub fn SyncEditor::get_source_map(self : SyncEditor) -> @proj.SourceMap {
  self.source_map_memo.get()
}

///|
pub fn SyncEditor::get_node(
  self : SyncEditor,
  id : @proj.NodeId,
) -> @proj.ProjNode? {
  self.registry_memo.get().get(id)
}

///|
pub fn SyncEditor::node_at_position(
  self : SyncEditor,
  position : Int,
) -> @proj.NodeId? {
  self.source_map_memo.get().innermost_node_at(position)
}

///|
pub fn SyncEditor::get_node_range(
  self : SyncEditor,
  id : @proj.NodeId,
) -> @loom_core.Range? {
  self.source_map_memo.get().get_range(id)
}
