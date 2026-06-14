///|
priv struct DefinitionIndexEntry {
  name : String
  init : ProjNode[@ast.Term]
  binding_id : NodeId
}

///|
fn DefinitionIndexEntry::from_def(
  def : (String, ProjNode[@ast.Term], Int, NodeId),
) -> DefinitionIndexEntry {
  let (name, init, _start, binding_id) = def
  { name, init, binding_id }
}

///|
/// Index of module-level Lambda definitions.
///
/// `ModuleProjection` still owns the projection storage for this slice; this
/// derived index gives definition lookup and binding-id queries a named home
/// without exposing the underlying tuple layout to new consumers.
pub struct DefinitionIndex {
  priv entries : Array[DefinitionIndexEntry]
}

///|
fn DefinitionIndex::from_defs(
  defs : Array[(String, ProjNode[@ast.Term], Int, NodeId)],
) -> DefinitionIndex {
  { entries: defs.map(fn(def) { DefinitionIndexEntry::from_def(def) }) }
}

///|
/// Derive the definition-index view for this module projection.
pub fn ModuleProjection::definition_index(
  self : ModuleProjection,
) -> DefinitionIndex {
  DefinitionIndex::from_defs(self.defs)
}

///|
/// Number of indexed module definitions, preserving source order.
pub fn DefinitionIndex::length(self : DefinitionIndex) -> Int {
  self.entries.length()
}

///|
fn DefinitionIndex::names(self : DefinitionIndex) -> Array[String] {
  self.entries.map(fn(entry) { entry.name })
}

///|
/// Look up the binding handle for a module definition by either its LetDef node
/// id or its initializer node id.
pub fn DefinitionIndex::binding_for_node(
  self : DefinitionIndex,
  node_id : NodeId,
) -> (NodeId, Int)? {
  self.entries
  .search_by(fn(entry) {
    entry.binding_id == node_id || entry.init.id() == node_id
  })
  .map(fn(i) { (self.entries[i].binding_id, i) })
}

///|
/// Return the number of preceding module definitions visible at `node_id`.
///
/// Nodes inside definition `i`'s initializer receive cutoff `i`; nodes outside
/// all initializers receive the full definition count. Missing source ranges use
/// the full count, matching the legacy edit-scope fallback.
pub fn DefinitionIndex::cutoff_at_node(
  self : DefinitionIndex,
  source_map : SourceMap,
  node_id : NodeId,
) -> Int {
  guard source_map.get_range(node_id) is Some(r) else { return self.length() }
  self.entries
  .search_by(fn(entry) {
    source_map.get_range(entry.init.id()) is Some(dr) &&
    r.start >= dr.start &&
    r.start < dr.end
  })
  .unwrap_or(self.length())
}
