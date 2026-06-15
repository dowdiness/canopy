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
/// the before/after impact diff (§6 Step 2 — `diff` below). The diff keys on
/// pipeline-independent semantic identity (name + source range), never on the
/// graph-local `DeclId`/`NodeId`.
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

///|
/// Pipeline-independent identity key for a `ReachableFailure`. Keyed on the
/// reference's source span and name, NOT on `DeclId`/`NodeId` (graph-local ids
/// that differ across rebuilds). Two failures at the same source position with
/// the same name are the same failure; a semantics-preserving rebuild over the
/// same source produces identical keys and an empty `diff`.
///
/// **Stability caveat:** keys are absolute positions in the source text.
/// When an edit only shifts an existing failure (e.g. inserting a binding
/// before it), the position changes and a naive `diff` would report the failure
/// as resolved-then-reintroduced. Call `remap_failures(before, edits)` before
/// `diff` to adjust `before` positions to post-edit coordinates, producing a
/// stable (non-spurious) diff.
///
/// `None` locations (SourceMap built without token spans) fall back to name
/// only — distinct free vars at different sites collapse to the same key.
/// Callers should ensure the SourceMap has populated token spans for
/// injective keys (the standard production path always does).
fn failure_key(f : ReachableFailure) -> String {
  match f.location {
    Some({ start, end }) => "\{start}:\{end}:\{f.name}"
    None => "?:\{f.name}"
  }
}

///|
/// Before/after diff of the `ReachableFailure` set for agent edit review.
/// `newly_reachable` — failures introduced by the edit (in `after`, not `before`).
/// `resolved` — failures the edit fixed (in `before`, not `after`).
/// An empty diff means the edit left the failure set unchanged.
pub(all) struct FailureDiff {
  newly_reachable : Array[ReachableFailure]
  resolved : Array[ReachableFailure]
} derive(Debug)

///|
fn FailureDiff::FailureDiff(
  newly_reachable~ : Array[ReachableFailure],
  resolved~ : Array[ReachableFailure],
) -> FailureDiff {
  { newly_reachable, resolved }
}

///|
/// Snapshot `failures()` before an agent's `UserIntent`/`GenericTreeOp` edit,
/// recompute after, and call `diff` to report what the edit introduced or fixed.
///
/// Keys on pipeline-independent semantic identity (name + source range), never
/// on `DeclId`/`NodeId`. A semantics-preserving rebuild over the same source
/// produces an **empty** diff (non-spurious). See research note §6 Step 2 and
/// issue #618.
pub fn diff(
  before : Array[ReachableFailure],
  after : Array[ReachableFailure],
) -> FailureDiff {
  let before_set = @immut/hashset.from_iter(before.iter().map(failure_key))
  let after_set = @immut/hashset.from_iter(after.iter().map(failure_key))
  FailureDiff(
    newly_reachable=[
      for f in after if !before_set.contains(failure_key(f)) => f
    ],
    resolved=[ for f in before if !after_set.contains(failure_key(f)) => f ],
  )
}

///|
/// Remap `failures` source positions from before-edit coordinates to
/// after-edit coordinates using `edits`. Call before `diff` to produce a
/// stable (non-spurious) diff when edits only shift existing failures without
/// introducing or fixing them.
///
/// `edits` must be sorted by `start` ascending and non-overlapping (the
/// ordering `compute_text_edit` guarantees). Failures with `location = None`
/// pass through unchanged; their key is already name-only and position-stable.
pub fn remap_failures(
  failures : Array[ReachableFailure],
  edits : Array[@core.SpanEdit],
) -> Array[ReachableFailure] {
  if edits.length() == 0 {
    return failures
  }
  failures.map(fn(f) {
    match f.location {
      None => f
      Some({ start, end }) =>
        ReachableFailure(
          name=f.name,
          location=Some({
            start: remap_pos(start, edits),
            end: remap_pos(end, edits),
          }),
          witness=f.witness,
        )
    }
  })
}

///|
/// Remap a single byte offset from before-edit to after-edit coordinates.
/// Edits must be sorted by `start` ascending, non-overlapping. Positions
/// inside a deleted range are mapped to the start of the replacement.
fn remap_pos(pos : Int, edits : Array[@core.SpanEdit]) -> Int {
  let final_shift = for edit in edits; shift = 0 {
    if pos < edit.start {
      break shift
    } else if pos < edit.start + edit.delete_len {
      return edit.start + shift
    } else {
      continue shift + edit.inserted.length() - edit.delete_len
    }
  } nobreak {
    shift
  }
  pos + final_shift
}
