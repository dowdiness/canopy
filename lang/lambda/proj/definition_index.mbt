///|
priv struct DefinitionIndexEntry {
  init : ProjNode[@ast.Term]
  binding_id : NodeId
}

///|
fn DefinitionIndexEntry::from_binding(
  child : ProjNode[@ast.Term],
) -> DefinitionIndexEntry {
  match child.kind {
    @ast.Term::LetDef(_, _) if child.children.length() > 0 =>
      { init: child.children[0], binding_id: child.id() }
    _ => { init: child, binding_id: child.id() }
  }
}

///|
/// Index of module-level Lambda definitions derived from the current
/// `ProjNode` root.
pub struct DefinitionIndex {
  priv entries : Array[DefinitionIndexEntry]
}

///|
/// Derive a definition-index view directly from the current projection tree.
pub fn DefinitionIndex::from_proj_node(
  root : ProjNode[@ast.Term],
) -> DefinitionIndex {
  match root.kind {
    @ast.Term::Module(defs, _) => {
      let child_count = root.children.length()
      let entries : Array[DefinitionIndexEntry] = [
        for i, _ in defs if i + 1 < child_count => {
          DefinitionIndexEntry::from_binding(root.children[i])
        }
      ]
      { entries, }
    }
    _ => { entries: [] }
  }
}

///|
/// Number of indexed module definitions, preserving source order.
pub fn DefinitionIndex::length(self : DefinitionIndex) -> Int {
  self.entries.length()
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
