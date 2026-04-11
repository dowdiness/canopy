// Projection accessor methods for SyncEditor.

///|
/// Returns the cached ProjNode (converted from FlatProj once per invalidation).
pub fn[T] SyncEditor::get_proj_node(self : SyncEditor[T]) -> @core.ProjNode[T]? {
  self.cached_proj_node.get()
}

///|
pub fn[T] SyncEditor::get_source_map(self : SyncEditor[T]) -> @core.SourceMap {
  self.source_map_memo.get()
}

///|
/// Returns the full node registry (NodeId → ProjNode).
pub fn[T] SyncEditor::get_registry(
  self : SyncEditor[T],
) -> Map[@core.NodeId, @core.ProjNode[T]] {
  self.registry_memo.get()
}

///|
/// Returns the parsed AST tree (language-specific type T).
pub fn[T] SyncEditor::get_tree(self : SyncEditor[T]) -> T? {
  self.parser.get_tree()
}

///|
pub fn[T] SyncEditor::get_node(
  self : SyncEditor[T],
  id : @core.NodeId,
) -> @core.ProjNode[T]? {
  self.registry_memo.get().get(id)
}

///|
pub fn[T] SyncEditor::node_at_position(
  self : SyncEditor[T],
  position : Int,
) -> @core.NodeId? {
  self.source_map_memo.get().innermost_node_at(position)
}

///|
pub fn[T] SyncEditor::get_node_range(
  self : SyncEditor[T],
  id : @core.NodeId,
) -> @loom_core.Range? {
  self.source_map_memo.get().get_range(id)
}
