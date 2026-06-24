# SDEG NodeId Side Table Sketch

**Status:** Internal design sketch. Not implemented behavior and not a public API.

This note extracts the Phase 0 Markdown heading spike into the smallest
side-table shape worth trying before adding a stable entity core or durable
`EntityId`.

**Phase 1 lifecycle note:** the active Phase 1 plan supersedes this sketch where
lifecycle naming differs. In particular, Phase 1 uses `Missing` for first
absence and reaches `Tombstoned` only after a retention threshold. The
`Tombstoned → Retired` transition is now implemented via a configurable
`retention_threshold` on the side table (issue #746); rows track
`consecutive_absences`, and `gc_eligible` is a predicate over `Retired` rows
(issue #745). Keep this sketch as prior evidence for same-node priority,
one-to-one assignment, and snapshot invariants, not as the final lifecycle
contract. See the [Retention threshold](#retention-threshold) section below.

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
  consecutive_absences : Int
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

The implemented five-state lifecycle (code is authoritative; this sketch's
earlier four-state version is superseded where they differ):

```text
new observation -> Live
Live + no match -> Missing
Live + unique match -> Live
Live/Tombstoned + multiple matches -> Ambiguous
Missing + no match -> Tombstoned
Missing + unique match -> Live
Tombstoned + unique match -> Live
Tombstoned + no match (below threshold) -> Tombstoned
Tombstoned + no match (threshold reached) -> Retired
Ambiguous + unique match -> Live
Ambiguous + no match -> Missing
Retired -> inert (no matching, no revival)
```

### Retention threshold

The side table carries a configurable `retention_threshold` field (set via
`from_observations(observations, retention_threshold=N)`).

| Threshold | Behavior |
|-----------|----------|
| `0` (default) | Preserves the old hardwired absence ladder. No `Tombstoned → Retired` transition ever fires; rows remain `Tombstoned` indefinitely. |
| `N > 0` | A `Tombstoned` row transitions to `Retired` when its `consecutive_absences` reaches `N`. Because the threshold check only fires on rows already in `Tombstoned` status (the `Missing → Tombstoned` transition has no threshold check), and `Tombstoned` is first reached at absence 2, the earliest possible retirement is absence 3. For `N ≤ 3`, retirement occurs at absence 3 (the first advance where the row is `Tombstoned` and the check evaluates). For `N > 3`, retirement occurs at absence `N`. |

Boundary behavior:

- **`N = 0`**: no retirement. The side table never produces `Retired` rows through normal lifecycle. `gc_eligible` returns `false` for every row.
- **`N = 1` or `N = 2`**: minimum retirement at absence 3. The row becomes `Tombstoned` at absence 2; the threshold check first evaluates at absence 3 (`new_absences=3 >= N`), so retirement fires at absence 3 — the same advance where it would for `N=3`.
- **`N ≥ 3`**: retirement at absence `N`. The standard ladder: `Missing` at 1, `Tombstoned` at 2, `Retired` at `N`.
- **`N < 0`**: negative thresholds never trigger retirement because the guard requires `retention_threshold > 0`. Behaves like `N = 0`.

`consecutive_absences` is reset to `0` whenever a row recovers to `Live` or
becomes `Ambiguous`. It increments by 1 on each advance where the row has no
matched candidates.

### Garbage collection predicate

`gc_eligible(row)` is a predicate, not a lifecycle state (issue #745). It
returns `true` when `row.status == Retired`. Today it is unconditional because
no pinning references (future edges) exist; when edges are added, the predicate
will also check that no pinning reference targets the row.

Retired rows are inert — they do not participate in matching and cannot become
`Live` again — but they remain in the row array. Physical removal (GC) is
future work.

### Recovery and `last_live`

`Missing`, `Tombstoned`, and `Ambiguous` rows retain their `last_live`
observation so a later unique match can recover them. Recovery resets
`consecutive_absences` to `0`. Once `Retired`, a row cannot recover — `last_live`
is frozen for diagnostic inspection only.

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
behavior, the retention threshold (`Tombstoned → Retired` transition), and
snapshot invariant tests. Shared heading observation helpers remain in
`lang/markdown/proj/sdeg_heading_spike_wbtest.mbt`.

Implemented since the initial sketch:

- **Retention threshold** (issue #746): configurable per side table via
  `from_observations(observations, retention_threshold=N)`. Default `0` preserves
  the old "keep tombstones forever" behavior. Positive values enable the
  `Tombstoned → Retired` transition when `consecutive_absences` reaches the
  threshold.
- **`gc_eligible` predicate** (issue #745): `Retired` rows are collectable.
  Physical row removal is not yet implemented.

Keep that implementation package-private or test-local. Promote a shared helper
only after another entity kind needs the same lifecycle semantics, and verify
`moon info` shows no accidental public API drift. No TypeScript-side integration
exists yet.

Related:

- [Stable Document Entity Graph](stable-document-entity-graph.md)
- [SDEG Phase 0 Markdown Heading Spike](../archive/2026-06-18-sdeg-phase0-markdown-heading-spike.md)
