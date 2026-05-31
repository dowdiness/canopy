///|
/// Graph-local compact indices. NOT persistent identity — `@core.NodeId`
/// carries persistent identity; these index into the graph's own arrays.
pub(all) struct ScopeId(Int) derive(Debug, Eq, Hash, Compare)

///|
pub(all) struct DeclId(Int) derive(Debug, Eq, Hash, Compare)

///|
pub(all) struct RefId(Int) derive(Debug, Eq, Hash, Compare)

///|
/// The kind of binding site a declaration represents. The one lambda-specific
/// type here (see design spec). A future loom lift makes `Decl` generic over
/// this (`Decl[K]`).
pub(all) enum DeclKind {
  LamParam(lam_id~ : @core.NodeId)
  ModuleDef(def_index~ : Int)
} derive(Debug, Eq)

///|
/// A lexical scope. `parent` is the enclosing scope (None for the root).
pub(all) struct Scope {
  id : ScopeId
  parent : ScopeId?
  decl_ids : Array[DeclId]
  ref_ids : Array[RefId]
} derive(Debug)

///|
/// A declaration (binding site). A binder's LOCATION is its source span,
/// recovered uniformly via `binder_span` (which reads `SourceMap` token spans),
/// not via `node_id`:
/// - lambda param: the `"param"` token span on the `Lam` node (`kind`'s `lam_id`).
/// - module def: the `"name:<def_index>"` token span on the module node
///   (`ScopeGraph::module_node_id`).
/// `node_id` is retained only as an internal dedup/identity handle. It is NOT a
/// reliable tree-node pointer for module defs (on the production `to_flat_proj`
/// path it is a synthetic id occupying no registry node), so consumers needing
/// to locate a binder MUST use `binder_span`, never `node_id`.
pub(all) struct Decl {
  id : DeclId
  node_id : @core.NodeId
  name : String
  scope : ScopeId
  kind : DeclKind
} derive(Debug, Eq)

///|
/// A reference (use site), keyed by NodeId, with its resolution result.
pub(all) struct Ref {
  id : RefId
  node_id : @core.NodeId
  name : String
  scope : ScopeId
  resolution : Resolution
} derive(Debug)

///|
/// Resolution outcome for a reference.
/// `decl: None` is a NEGATIVE OBSERVATION (unresolved / free).
/// `visited_scopes` records scopes checked and found NOT to contain the
/// name — populated in v1 as a by-product of the resolution walk, read only
/// by a future incremental layer (see design spec).
pub(all) struct Resolution {
  decl : DeclId?
  visited_scopes : Array[ScopeId]
} derive(Debug)

///|
/// The binding index for one lambda module.
/// `module_node_id` is the root projection node that owns the module-def name
/// token spans (`"name:<def_index>"` in the `SourceMap`); `binder_span` reads
/// them through it. For a bare-expression program (no defs) it is the root
/// expression node and the name-span path is never exercised.
pub(all) struct ScopeGraph {
  scopes : Array[Scope]
  decls : Array[Decl]
  refs : Array[Ref]
  module_node_id : @core.NodeId
} derive(Debug)
