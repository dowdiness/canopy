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
fn DefinitionIndexEntry::from_binding(
  name : String,
  child : ProjNode[@ast.Term],
) -> DefinitionIndexEntry {
  match child.kind {
    @ast.Term::LetDef(_, _) if child.children.length() > 0 =>
      { name, init: child.children[0], binding_id: child.id() }
    _ => { name, init: child, binding_id: child.id() }
  }
}

///|
/// Index of module-level Lambda definitions.
///
/// Production edit paths derive this from the current `ProjNode` root. The
/// `ModuleProjection` adapter below exists for the legacy compatibility layer
/// and root-module reconciliation, but new consumers should use
/// `DefinitionIndex::from_proj_node`.
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
/// Derive a definition-index view directly from the current projection tree.
pub fn DefinitionIndex::from_proj_node(
  root : ProjNode[@ast.Term],
) -> DefinitionIndex {
  match root.kind {
    @ast.Term::Module(defs, _) => {
      let entries : Array[DefinitionIndexEntry] = []
      let child_count = root.children.length()
      for i, def in defs {
        if i + 1 < child_count {
          entries.push(
            DefinitionIndexEntry::from_binding(def.0, root.children[i]),
          )
        }
      }
      { entries, }
    }
    _ => { entries: [] }
  }
}

///|
/// Legacy compatibility adapter: derive the definition-index view for this
/// module projection. New production callers should use
/// `DefinitionIndex::from_proj_node`.
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
