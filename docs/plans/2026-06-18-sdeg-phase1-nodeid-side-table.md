# SDEG Phase 1 NodeId Side Table Design

## Why

The Phase 0 Markdown heading spike showed that Canopy's existing projection
identity pipeline is a good substrate for stable editing entities, but `NodeId`
itself is not semantic identity:

- heading rename, malformed inline recovery, and whitespace rewrites preserve
  `NodeId`;
- heading rename also preserves `NodeId` when routed through the real Markdown
  edit path (`MarkdownEditOp::CommitEdit` -> `apply_markdown_edit` ->
  `SyncEditor`);
- sibling reorder is position-stable rather than semantic-stable;
- committed delete/restore cannot recover a retired heading identity;
- `ProjectionIdentityTracker` / `realign_projection_items` does not cover those
  two gaps;
- heading level changes routed through the Markdown edit path currently freshen
  `NodeId`; preserving that case needs edit provenance hints or projection
  reconciliation, not a side-table-only guess;
- a test-only semantic matcher can detect simple reorder mismatches,
  delete/restore recovery candidates, and duplicate-heading ambiguity, but pure
  reorder cannot be recovered by a side-table-only matcher while same-node
  priority treats still-present `NodeId`s as exact matches.

This plan designs the next internal slice: a package-private Markdown heading
side table over `NodeId`, not a new public SDEG core.

## Scope

In:
- `lang/markdown/proj/` package-private heading identity helpers.
- White-box tests in `lang/markdown/proj/`.
- Existing `NodeId`, `ProjNode`, `SourceMap`, and token spans.
- Documentation updates to this plan and the archived Phase 0 result note if conclusions change.

Out:
- public `EntityId` or `sdeg-*` packages.
- CRDT / event-graph-walker anchor integration.
- reload-stable or peer-stable identity.
- frontend protocol changes.
- generic cross-language entity graph abstractions.
- production UI behavior changes until tests prove the model.

## Current State

The current spike file `lang/markdown/proj/sdeg_heading_spike_wbtest.mbt`
contains test-only observations and match evidence. It proves:

- `SourceMap` can provide UTF-16 heading anchors and marker/text token spans.
- `NodeId` is a usable current projection handle.
- semantic side-table matching over observations can classify:
  - unique semantic match;
  - ambiguous duplicate-heading match;
  - missing heading.

The companion edit-path test `lang/markdown/companion/sdeg_edit_path_wbtest.mbt`
proves that observations can be derived after `SyncEditor` applies a Markdown
edit; it also records heading level change as a fresh-`NodeId` limitation.

The missing piece for this phase is lifecycle: retaining old observations across
snapshots and mapping a stable session entity to its current `NodeId` when the
previous projection node is absent. Phase 1 should not weaken the matcher to
recover changes without evidence; it should keep ambiguous or
provenance-sensitive cases explicit. In particular, pure sibling reorder remains
out of scope for side-table-only recovery because Phase 0 showed the old
`NodeId`s are still present but attached by position. Reorder recovery is still
needed for the future block-based editor UI; the owner should be a language-owned
block move/reorder edit path that emits explicit move provenance, not the Phase 1
derived side table guessing around same-node priority.

## Desired State

A Markdown-internal side table can answer:

- Which session-local heading entity does this current `NodeId` represent?
- Which current `NodeId`, if any, represents this retained heading entity when
  the previous current node is absent?
- Was a heading preserved by `NodeId`, semantically reattached after absence,
  newly spawned, missing, ambiguous, or retired?
- What evidence justifies that decision?

The side table remains internal and session-local. It does not promise reload or
peer durability.

The table is a derived snapshot layer. It consumes the current projection and
source map after the normal edit/editor path has run; it must not mutate source
text, projection nodes, source maps, CRDT state, or undo history.

## Design

### Identity vocabulary

Use two names to avoid confusing projection identity with semantic identity:

- **Current node**: the current projection `NodeId` attached to a `ProjNode`.
- **Session entity ref**: a package-private stable ref for a heading entity,
  initially derived from the first `NodeId` that represented it.

A session entity ref may be represented as a private wrapper around `NodeId` in
implementation, but it must not be exposed as a public `EntityId`. Its contract
is only "stable within this editor session and this side table".

### Core records

Implementation can start with package-private types like these names. Exact
field names may change during implementation.

```moonbit
struct HeadingSignature {
  level : Int
  text : String
}

struct HeadingObservation {
  node_id : @core.NodeId
  signature : HeadingSignature
  range : @loomcore.Range
  marker : @loomcore.Range?
  text_span : @loomcore.Range?
  ordinal : Int
}

struct HeadingEntityRef {
  origin_node : @core.NodeId
}

enum HeadingEntityStatus {
  Live(current~ : @core.NodeId)
  Missing
  Tombstoned
  Ambiguous(candidates~ : Array[@core.NodeId])
  Retired
}

struct HeadingEntityRecord {
  entity : HeadingEntityRef
  status : HeadingEntityStatus
  last_observation : HeadingObservation
  last_seen_epoch : Int
}

enum HeadingMatchConfidence {
  High
  Medium
  Ambiguous
  Missing
}

struct HeadingMatchEvidence {
  same_signature : Bool
  range_overlaps : Bool
  ordinal_distance : Int
  candidate_count : Int
  node_id_preserved : Bool
  confidence : HeadingMatchConfidence
}
```

Keep these private until a second language needs the same pattern.

### Side-table shape

The internal table should maintain both directions:

```text
entity_ref -> HeadingEntityRecord
current_node_id -> entity_ref
```

The current-node index is rebuilt each update from live records. The entity
records retain missing/tombstoned observations for recovery.

### Carry-forward boundaries from Phase 0

- Same-node evidence has priority. If the projection `NodeId` survived, preserve
  that session entity before considering semantic recovery candidates.
- Semantic recovery is only for cases where the previous node is absent. It must
  be one-to-one and evidence-bearing; duplicate candidates stay ambiguous.
- Pure sibling reorder is not recoverable in this side-table-only phase: the old
  `NodeId`s remain present, so same-node priority wins and semantic recovery is
  not considered. Solving that requires explicit reorder/edit provenance or a
  projection reconciliation change that can override positional same-node
  evidence.
- Heading level change is not solved by dropping `level` from the signature or by
  guessing from text alone. If Phase 1 touches that case, record it as requiring
  edit provenance hints or projection reconciliation unless a stronger evidence
  source is added.
- Edit-path tests belong at the companion/editor boundary; side-table tests in
  `lang/markdown/proj/` should consume post-projection observations rather than
  create a parallel text mutation path.

### Matching pipeline

For each successful projection snapshot:

1. Extract current heading observations from `ProjNode` + `SourceMap`.
2. Match by preserved current `NodeId` first.
   - If an existing live record's current node still appears, keep that entity.
3. Match remaining current observations against retained records by semantic
   evidence.
   - Primary key: heading level + normalized heading text.
   - Tie-breakers: range overlap, ordinal distance, surrounding section context
     if available later.
4. Classify unmatched retained records.
   - `Live -> Missing` when absent for the first update.
   - `Missing -> Tombstoned` when still absent after the retention threshold.
   - `Tombstoned -> Retired` only after an explicit GC policy exists.
5. Classify unmatched current observations.
   - Spawn a new session entity unless the candidate set is ambiguous.
6. Rebuild the current-node index.

### Confidence rules for Phase 1

Start deliberately conservative:

- **High**: exactly one retained record and exactly one current observation share
  the same signature, or the current `NodeId` is preserved.
- **Ambiguous**: more than one retained or current observation shares the same
  signature.
- **Missing**: no current observation matches a retained record.
- **Medium**: reserve for future range/ordinal/context-assisted matches; do not
  rely on it in Phase 1 behavior.

This means duplicate headings remain ambiguous instead of being guessed.

### Lifecycle policy

Initial lifecycle should be observable and conservative:

```text
Live -> Missing      when no match exists in the current successful projection
Missing -> Live      when a unique semantic match returns
Missing -> Tombstoned after N successful epochs, where N is small/test-controlled
Tombstoned -> Live   when a unique semantic recovery match appears
Tombstoned -> Retired only in tests that explicitly exercise GC policy
Ambiguous -> Live    when ambiguity resolves uniquely
Ambiguous -> Missing if all candidates disappear
```

For Phase 1, the default retention can be "keep all tombstones during the test".
Do not introduce production GC until UI/undo/reload requirements are clearer.

### Expected behavior

- Rename: preserved by `NodeId`; signature changes on the same entity.
- Reorder: pure sibling reorder is recorded as position-stable, not
  semantic-stable, unless this phase also adds explicit reorder/edit provenance
  or a projection reconciliation fix.
- Delete: missing/tombstoned record retained for the deleted heading.
- Restore: unique semantic match recovers the retained entity with a new current
  `NodeId`.
- Duplicate headings: ambiguous; no semantic reattachment unless future evidence
  disambiguates.
- Edit-path rename: same as rename above; observations are derived after
  `SyncEditor` applies the Markdown edit.
- Heading level change through the edit path: source/projection observation
  updates, but current `NodeId` is fresh today. Phase 1 may record this as a
  limitation; it should not claim semantic recovery without edit provenance or a
  reconciliation fix.

## Steps

1. Start from the archived Phase 0 result note and
   `docs/design/sdeg-nodeid-side-table.md`; treat those as prior evidence for
   same-node priority and snapshot invariants. Where lifecycle names conflict,
   this Phase 1 plan supersedes the older sketch: first absence is `Missing`,
   and `Tombstoned` is reached only after the retention threshold.
2. Extract the test-only observation helpers into package-private helpers inside
   `lang/markdown/proj/`, still not public.
3. Add a package-private `HeadingEntityTable` with entity records and current-node
   index.
4. Implement update-from-observations for one successful projection snapshot.
5. Add tests for:
   - rename keeps one entity and updates its signature;
   - pure sibling reorder records the same-node-priority limitation instead of
     claiming semantic recovery;
   - delete marks the entity missing/tombstoned;
   - restore recovers the retained entity;
   - duplicates produce ambiguity rather than guessed identity;
   - heading level change remains an explicit fresh-`NodeId` limitation unless a
     provenance/reconciliation fix is included.
6. Keep all behavior test-local until the table is needed by a real consumer.
7. Summarize whether the table should graduate to a generic SDEG-internal
   abstraction or remain Markdown-owned.

## Acceptance Criteria

- [ ] No public `.mbti` surface changes.
- [ ] Heading observations are extracted from existing `ProjNode` + `SourceMap`.
- [ ] Pure sibling reorder is documented as a same-node-priority limitation, or
      fixed only with explicit reorder/provenance evidence.
- [ ] Side table marks delete as missing/tombstoned without deleting the record.
- [ ] Side table recovers a uniquely restored heading from retained observation.
- [ ] Duplicate headings are marked ambiguous.
- [ ] Tests document which evidence produced each decision.
- [ ] Heading level-change identity is either still documented as an upstream
      provenance/reconciliation limitation or fixed with explicit evidence.
- [ ] No CRDT, frontend protocol, or public SDEG package changes.

## Validation

```bash
NEW_MOON_MOD=0 moon check
NEW_MOON_MOD=0 moon test -p dowdiness/canopy/lang/markdown/proj
NEW_MOON_MOD=0 moon test
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon info
git diff -- '*.mbti'
```

The expected `.mbti` diff is empty. If `moon info` introduces unrelated trailing
blank-line churn in generated interfaces, revert those unrelated files before
committing.

## Risks

- A private wrapper around `NodeId` can become a de facto public `EntityId` if it
  escapes. Keep it package-private.
- Text+level matching is intentionally weak. It is useful for the first slice but
  must mark duplicates ambiguous.
- Retaining tombstones without GC can grow unbounded. Phase 1 should keep this
  test-local or editor-session-local until a retention policy is designed.
- Reorder behavior needs edit provenance or projection reconciliation before it
  can override same-node priority. Do not encode semantic reorder recovery as a
  side-table-only guarantee; track that separately in
  `docs/plans/2026-06-19-sdeg-reorder-provenance-investigation.md`.
- The side table should not mutate document state or bypass Markdown edit
  lowering.

## Notes

This design supports the current direction:

```text
current projection handle = NodeId
session semantic continuity = internal side table
future durable identity = only if reload/peer requirements demand it
```

If this phase succeeds, the next design question is how to expose side-table facts
to derived views through `incr` without making the table itself the document
source of truth.
