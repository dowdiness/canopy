///|
priv struct DefinitionIndexEntry {
  init : ProjNode[@ast.Term]
  binding_id : NodeId
}

///|
fn DefinitionIndexEntry::from_let_def(
  let_def : ProjNode[@ast.Term],
) -> DefinitionIndexEntry {
  { init: let_def.children[0], binding_id: let_def.id() }
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
        for i, _ in defs if i + 1 < child_count &&
        root.children[i].kind is @ast.Term::LetDef(_, _) &&
        root.children[i].children.length() > 0 => {
          DefinitionIndexEntry::from_let_def(root.children[i])
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
/// Look up the binding handle for a module definition by its LetDef node id.
pub fn DefinitionIndex::binding_for_node(
  self : DefinitionIndex,
  node_id : NodeId,
) -> (NodeId, Int)? {
  self.entries
  .search_by(fn(entry) { entry.binding_id == node_id })
  .map(fn(i) { (self.entries[i].binding_id, i) })
}

///|
/// Return the number of preceding module definitions visible at `node_id`.
///
/// Nodes inside definition `i`'s initializer receive cutoff `i`; nodes outside
/// all initializers or missing from the source map receive the full definition
/// count.
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
