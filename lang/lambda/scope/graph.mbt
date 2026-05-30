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
/// A declaration (binding site). `node_id` identifies the binder, but its
/// relationship to the projection tree differs by kind, and the module case is
/// a KNOWN divergence to reconcile (not a settled contract):
/// - lambda param: `node_id` IS the `Lam` projection node it occupies.
/// - module def: `node_id` is the FlatProj binder id (`defs[i].3`). On the
///   production `to_flat_proj` path this is a SYNTHETIC id occupying no registry
///   node — so it does NOT satisfy "the projection NodeId it occupies" the way
///   the lambda case does. Consumers needing a tree node for a module binder
///   must currently map through `def_index`, not `node_id`.
/// This gap (recorded by the `to_flat_proj` contract test in `lang/lambda/edits`)
/// should be revisited the first time a consumer reads a module `node_id` as an
/// output (e.g. go-to-definition); making module binder ids real tree nodes is
/// the path that restores the uniform invariant.
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
pub(all) struct ScopeGraph {
  scopes : Array[Scope]
  decls : Array[Decl]
  refs : Array[Ref]
} derive(Debug)
