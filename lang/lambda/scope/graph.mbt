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
/// not by interpreting `node_id` as a source range:
/// - lambda param: the `"param"` token span on the `Lam` node (`kind`'s `lam_id`).
/// - module def: the `"name"` token span on the first-class `LetDef` node,
///   with the module node's `"name:<def_index>"` span retained as a migration
///   fallback.
/// `node_id` is the declaration's structural identity; for module definitions it
/// now points at the real `LetDef` projection node. Consumers needing to locate
/// a binder should still use `binder_span`, never the full node range.
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
/// `module_node_id` is the root projection node that owns compatibility
/// module-def name token spans (`"name:<def_index>"` in the `SourceMap`). The
/// canonical module-def binder span lives on each `LetDef` node. For a
/// bare-expression program (no defs), this is the root expression node and the
/// name-span path is never exercised.
pub(all) struct ScopeGraph {
  scopes : Array[Scope]
  decls : Array[Decl]
  refs : Array[Ref]
  module_node_id : @core.NodeId
  // Per-node resolution inputs, retained from the builder so consumers can ask
  // hypothetical-position questions ("what would `name` resolve to AT this
  // node?", `resolve_name_at`). `node_cutoffs` keys each `ModuleDef`'s
  // sequential visibility per enclosing module scope; lambda scopes never appear
  // (they hold no `ModuleDef`). Every walked node has an entry in both.
  node_scope : Map[@core.NodeId, ScopeId]
  node_cutoffs : Map[@core.NodeId, Map[ScopeId, Int]]
} derive(Debug)
