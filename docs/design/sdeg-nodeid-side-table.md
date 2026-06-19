# SDEG NodeId Side Table Sketch

**Status:** Internal design sketch. Not implemented behavior and not a public API.

This note extracts the Phase 0 Markdown heading spike into the smallest
side-table shape worth trying before adding a stable entity core or durable
`EntityId`.

## Intent

Use existing projection `NodeId`s as session-local identity seeds, then keep a
side table that maps each stable row to the current projection node when the
entity is live.

The side table is derived state. It must not become the document source of truth
or bypass language-owned edit lowering.

## First scope

- Entity kind: Markdown headings.
- Stability: editor session only.
- Anchors: existing `SourceMap` UTF-16 ranges and token spans.
- Storage: immutable snapshots or package-private helpers.
- API: internal/test-local until a second consumer proves reuse.

Out of scope: public `sdeg-*` packages, reload/peer-stable IDs, CRDT persistence,
a graph store, or replacing projection reconciliation.

## Closed core states, open evidence

Keep control-flow state closed. Lifecycle transitions are invariants, so callers
should be able to exhaustively reason about them.

```moonbit
enum EntityStatus {
  Live
  Tombstoned
  Ambiguous
  Retired
}

enum MatchConfidence {
  Exact
  Probable
  Ambiguous
  Missing
}
```

Use extensible enums only for extension points whose unknown cases can be safely
ignored or displayed generically. Matching evidence is the right first use:

```moonbit
pub(all) extenum EntityEvidence {
  SameNodeId(NodeId)
  SameSemanticKey(String)
  OverlappingSourceRange(Range, Range)
  CandidateCount(Int)
}
```

A language package can add its own evidence without changing the shared shape:

```moonbit
pub(all) extenum @sdeg.EntityEvidence += {
  SameHeadingLevel(Int)
  SameHeadingText(String)
  SameHeadingSection(String)
}
```

Consumers must include a wildcard branch when matching evidence, because another
package may add constructors later. Do not use `extenum` for lifecycle state or
other values the core transition algorithm must fully understand.

## Data shape

Use a private wrapper for the stable row key so it is not confused with a current
projection node. The wrapped value can still be seeded from the original
`NodeId`.

```moonbit
struct StableRowId(NodeId)

struct EntityObservation[Kind] {
  node_id : NodeId
  kind : Kind
  semantic_key : String
  source_range : Range
  token_spans : Array[(String, Range)]
}

struct MatchCandidate {
  node_id : NodeId
  evidence : Array[EntityEvidence]
}

struct MatchResult {
  confidence : MatchConfidence
  candidates : Array[MatchCandidate]
  evidence : Array[EntityEvidence]
}

struct EntityRow[Kind] {
  stable_id : StableRowId
  current_id : NodeId?
  status : EntityStatus
  last_live : EntityObservation[Kind]
  candidates : Array[NodeId]
  evidence : Array[EntityEvidence]
}

struct EntitySnapshot[Kind] {
  rows : Array[EntityRow[Kind]]
}
```

For Markdown headings, `semantic_key` starts as level plus normalized heading
text. Other languages may need parent context, declaration role, scope path, or
nearby-sibling evidence.

## Matcher contract

The matcher should be evidence-bearing, not boolean. A boolean `same_entity`
throws away the information SDEG needs to explain identity decisions.

```moonbit
fn[Kind] match_entity(
  previous : EntityObservation[Kind],
  current : Array[EntityObservation[Kind]],
) -> MatchResult
```

The matcher is language-owned. The side-table algorithm only interprets the
closed `MatchConfidence` and candidate ids; it stores evidence for diagnostics,
debug UI, and later confidence tuning.

A preserved projection `NodeId` is an `Exact` candidate and should be considered
before semantic-key candidates. Without edit provenance, a same-node match is the
only evidence that the row's original session-local identity survived; a
semantic singleton elsewhere is only a recovery candidate when the original node
is absent.

## Advance rule

Given the previous `EntitySnapshot` and current observations:

1. Exclude `Retired` rows from matching.
2. Match each remaining prior row's `last_live` against current observations.
3. Build a candidate graph from `StableRowId` to candidate current `NodeId`s.
4. Resolve live matches as a global one-to-one assignment, not as independent row
   decisions.
5. A row becomes `Live` only when it has one assigned current node and no other
   active row claims that node.
6. A row becomes `Tombstoned` when it has no candidates.
7. A row becomes `Ambiguous` when it has multiple candidates, when its only
   candidate is also claimed by another active row, or when the assignment cannot
   choose a unique row/node pair without guessing.
8. Add a current observation as a fresh `Live` row only if it is neither assigned
   to a live row nor listed as an ambiguous candidate for an existing row.

The one-to-one assignment rule is required even when individual matchers return
`Exact` or `Probable`: two old rows must never both become live at the same
current projection node. On conflict, prefer `Ambiguous` with stored candidate
ids and evidence over a plausible but unprovable match.

Step 8 prevents duplicate representation: an ambiguous candidate must not also
become a fresh live row until the ambiguity is resolved or the old row is
retired.

## Lifecycle

```text
new observation -> Live
Live + unique match -> Live
Live + no match -> Tombstoned
Tombstoned + unique match -> Live
Live/Tombstoned + multiple matches -> Ambiguous
Ambiguous + unique match -> Live
Ambiguous + no match -> Tombstoned
Tombstoned/Ambiguous + retention expiry -> Retired
Retired -> no longer participates in matching
```

Initial retention policy: keep tombstoned and ambiguous rows for the editor
session. Add bounded retention or garbage collection only after a consumer needs
it. Once `Retired`, a row is diagnostic history, not a recovery candidate.

## Snapshot invariants

Every produced snapshot must satisfy these invariants:

- `stable_id` is unique across all rows.
- `Live` rows have `current_id = Some(_)`.
- `Tombstoned`, `Ambiguous`, and `Retired` rows have `current_id = None`.
- No two `Live` rows share the same `current_id`.
- `Ambiguous` rows have one or more candidate ids.
- Candidate ids recorded on `Ambiguous` rows are not emitted as fresh `Live` rows
  in the same snapshot.
- `Retired` rows do not participate in matching and cannot become `Live` again.
- Every live `current_id` refers to an observation in the current projection
  snapshot.
- The side table never mutates source text, projection nodes, source maps, or CRDT
  state.

These invariants should become package-local tests before any helper leaves the
white-box spike.

## API sketch

```moonbit
fn[Kind] EntitySnapshot::from_observations(
  observations : Array[EntityObservation[Kind]],
) -> EntitySnapshot[Kind]

fn[Kind] EntitySnapshot::advance(
  self : EntitySnapshot[Kind],
  observations : Array[EntityObservation[Kind]],
  match_entity : (
    EntityObservation[Kind],
    Array[EntityObservation[Kind]],
  ) -> MatchResult,
) -> EntitySnapshot[Kind]

fn[Kind] EntitySnapshot::row_for_stable_id(
  self : EntitySnapshot[Kind],
  stable_id : StableRowId,
) -> EntityRow[Kind]?

fn[Kind] EntitySnapshot::row_for_current_id(
  self : EntitySnapshot[Kind],
  current_id : NodeId,
) -> EntityRow[Kind]?
```

Return a new snapshot instead of mutating in place so the shape can later sit
behind an `incr` derived value.

## Evidence to retain

Rows should explain identity outcomes with: stable row key, current node when
live, status, last live source range, token spans, semantic key, candidate ids,
confidence, and evidence. Do not expose byte offsets; source anchors remain
`SourceMap` UTF-16 ranges.

Good initial evidence for Markdown headings:

- same projection `NodeId`;
- same heading level;
- same normalized heading text;
- overlapping source range;
- same or nearby section context;
- candidate count.

## Decision gate

Stay with this side-table shape while identity is session-local and matching is
language-owned. Revisit a distinct stable entity core only when a real consumer
needs reload/peer stability, projection-independent graph relations,
language-independent evidence storage beyond an extensible enum, or durable CRDT
anchors in matching.

## Next slice

The Markdown white-box spike now mirrors this sketch in
`lang/markdown/proj/sdeg_heading_side_table_wbtest.mbt`: it has a stable-row
wrapper, an evidence-bearing matcher, same-node match priority, global
one-to-one conflict handling, ambiguous candidate retention, retired-row
behavior, and snapshot invariant tests. Shared heading observation helpers remain
in `lang/markdown/proj/sdeg_heading_spike_wbtest.mbt`.

Keep that implementation package-private or test-local. Promote a shared helper
only after another entity kind needs the same lifecycle semantics, and verify
`moon info` shows no accidental public API drift.

Related:

- [Stable Document Entity Graph](stable-document-entity-graph.md)
- [SDEG Phase 0 Markdown Heading Spike](../plans/2026-06-18-sdeg-phase0-markdown-heading-spike.md)
