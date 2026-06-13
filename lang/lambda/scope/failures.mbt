///|
/// A witnessed unresolved reference — a free variable surfaced with the exact
/// reason it is free. `ScopeGraph` resolution returns `decl == None` only after
/// exhausting the lexical scope chain, so for today's lambda language a
/// `ReachableFailure` is genuinely *reachable*, not merely *possible* (research
/// note 2026-06-13 §4): both the failure and its witness are exact. Distinct
/// from `incr`'s `ReachableDerived` (cell liveness / GC-anchoring) despite the
/// shared word — see the note's naming-discipline aside (§5).
///
/// - `name`: the unresolved reference's identifier.
/// - `location`: the reference's source span when recorded; `None` when the
///   `SourceMap` holds no range for the node (nothing to draw). Diagnostic
///   consumers filter on `location is Some(_)`; impact-query consumers want the
///   whole set.
/// - `witness`: the scopes searched and found NOT to contain `name`
///   (`Resolution.visited_scopes`) — the dependency footprint of the negative
///   observation, shared (not copied) from the resolution.
pub(all) struct ReachableFailure {
  name : String
  location : @loomcore.Range?
  witness : Array[ScopeId]
} derive(Debug)

///|
fn ReachableFailure::ReachableFailure(
  name~ : String,
  location~ : @loomcore.Range?,
  witness~ : Array[ScopeId],
) -> ReachableFailure {
  { name, location, witness }
}

///|
/// Derived view over the scope graph: every unresolved (free) reference,
/// surfaced as a witnessed `ReachableFailure`. The failure predicate is
/// `resolution.decl is None`; the witness is `resolution.visited_scopes`; the
/// location is the reference node's recorded source span.
///
/// Total over the graph's refs: this is the failure SET that feeds both the
/// free-variable diagnostic (research note §6 Step 1, which it now sources) and
/// the future before/after impact diff (§6 Step 2 — that diff must key on
/// pipeline-independent semantic identity, never the graph-local `DeclId`/
/// `NodeId`).
pub fn failures(
  g : ScopeGraph,
  source_map : @core.SourceMap,
) -> Array[ReachableFailure] {
  [
    for r in g.refs if r.resolution.decl is None => {
      ReachableFailure(
        name=r.name,
        location=source_map.get_range(r.node_id),
        witness=r.resolution.visited_scopes,
      )
    }
  ]
}
