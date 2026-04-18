// Projection accessor methods for SyncEditor.

///|
/// Returns the cached ProjNode (converted from FlatProj once per invalidation).
/// Safe to call both inside and outside tracked context.
pub fn[T] SyncEditor::get_proj_node(self : SyncEditor[T]) -> @core.ProjNode[T]? {
  self.parser.runtime().read(self.cached_proj_node)
}

///|
/// Safe to call both inside and outside tracked context.
pub fn[T] SyncEditor::get_source_map(self : SyncEditor[T]) -> @core.SourceMap {
  self.parser.runtime().read(self.source_map_memo)
}

///|
/// Returns the full node registry (NodeId → ProjNode).
/// Safe to call both inside and outside tracked context.
pub fn[T] SyncEditor::get_registry(
  self : SyncEditor[T],
) -> Map[@core.NodeId, @core.ProjNode[T]] {
  self.parser.runtime().read(self.registry_memo)
}

///|
/// Returns the parsed AST tree (language-specific type T).
/// Always `Some(_)` — the Parser primes its AST cell in the constructor
/// and lex failures propagate as a language-specific sentinel (e.g.
/// `Term::Error("lex error: …")` for lambda via `on_lex_error`), not as
/// `None`. The `?` is kept so this API doesn't need to churn if we
/// later separate "never parsed" from "parse failed".
pub fn[T] SyncEditor::get_tree(self : SyncEditor[T]) -> T? {
  Some(self.parser.runtime().read(self.parser.ast()))
}

///|
pub fn[T] SyncEditor::get_node(
  self : SyncEditor[T],
  id : @core.NodeId,
) -> @core.ProjNode[T]? {
  self.parser.runtime().read(self.registry_memo).get(id)
}

///|
pub fn[T] SyncEditor::node_at_position(
  self : SyncEditor[T],
  position : Int,
) -> @core.NodeId? {
  self.parser.runtime().read(self.source_map_memo).innermost_node_at(position)
}

///|
pub fn[T] SyncEditor::get_node_range(
  self : SyncEditor[T],
  id : @core.NodeId,
) -> @loom_core.Range? {
  self.parser.runtime().read(self.source_map_memo).get_range(id)
}
