// Projection Memo: Reactive derivation of ProjNode, registry, and source map
// from SyncEditor's incremental parser-backed signals.

///|
fn build_projection_memos(
  rt : @incr.Runtime,
  source_text : @incr.Signal[String],
  syntax_tree : @incr.Signal[@seam.SyntaxNode?],
  prev_proj_ref : Ref[@proj.ProjNode?],
  next_id_ref : Ref[Int],
) -> (
  @incr.Memo[@proj.ProjNode?],
  @incr.Memo[Map[@proj.NodeId, @proj.ProjNode]],
  @incr.Memo[@proj.SourceMap],
) {
  let proj_memo : @incr.Memo[@proj.ProjNode?] = @incr.Memo::new(
    rt,
    fn() -> @proj.ProjNode? {
      if source_text.get() == "" {
        prev_proj_ref.val = None
        return None
      }
      let syntax_root = match syntax_tree.get() {
        Some(root) => root
        None => {
          prev_proj_ref.val = None
          return None
        }
      }
      let expr_root = @proj.unwrap_expression_root(syntax_root)
      let counter = Ref::new(next_id_ref.val)
      let new_proj = @proj.syntax_to_proj_node(expr_root, counter)
      let reconciled = match prev_proj_ref.val {
        None => new_proj
        Some(prev) => @proj.reconcile_ast(prev, new_proj, counter)
      }
      next_id_ref.val = counter.val
      prev_proj_ref.val = Some(reconciled)
      Some(reconciled)
    },
    label="proj_node",
  )

  let registry_memo : @incr.Memo[Map[@proj.NodeId, @proj.ProjNode]] = @incr.Memo::new(
    rt,
    fn() -> Map[@proj.NodeId, @proj.ProjNode] {
      let registry : Map[@proj.NodeId, @proj.ProjNode] = {}
      match proj_memo.get() {
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
      match proj_memo.get() {
        Some(root) => @proj.SourceMap::from_ast(root)
        None => @proj.SourceMap::new()
      }
    },
    label="source_map",
  )

  (proj_memo, registry_memo, source_map_memo)
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
pub fn SyncEditor::get_proj_node(self : SyncEditor) -> @proj.ProjNode? {
  self.proj_memo.get()
}

///|
pub fn SyncEditor::get_source_map(self : SyncEditor) -> @proj.SourceMap {
  self.source_map_memo.get()
}

///|
fn SyncEditor::seed_proj_node(
  self : SyncEditor,
  proj : @proj.ProjNode?,
) -> Unit {
  self.prev_proj_node.val = proj
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
