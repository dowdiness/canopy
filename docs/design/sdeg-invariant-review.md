# SDEG invariant and semantics review

**Status:** Review / analysis snapshot rather than a spec or implemented behavior.
**Reviewed against:** `aa3d475` — `file:line` citations are as-of this commit;
code and generated `.mbti` are authoritative on drift.
**Decisions recorded:** #745 — reference policy for non-live entities (resolves
G13/L5 and the GC half of G4/L4); see *Lifecycle Analysis → Decision: reference
policy for non-live entities*.

## Context

Review target: the **Stable Document Entity Graph (SDEG)** design, primarily
`docs/design/stable-document-entity-graph.md`, read against the rest of the SDEG
corpus so claims are grounded in what is actually built and tested rather than in
prose alone.

Sources read:

- `docs/design/stable-document-entity-graph.md` — the design direction (review target)
- `docs/design/sdeg-nodeid-side-table.md` — the API/algorithm sketch
- `docs/archive/2026-06-18-sdeg-phase1-nodeid-side-table.md` — completed Phase 1 plan
- `docs/archive/2026-06-19-sdeg-reorder-provenance-investigation.md` — reorder conclusion
- `docs/archive/2026-06-18-sdeg-phase0-markdown-heading-spike.md` — Phase 0 results
- `docs/archive/2026-06-20-markdown-block-move-provenance-spike.md` — move provenance
- `docs/decisions/2026-06-01-identity-and-reuse-mechanisms.md` — identity layering
- `docs/decisions/2026-06-13-range-span-unit-boundaries.md` — anchor units
- `lang/markdown/proj/sdeg_heading_side_table.mbt` — **the implemented core**
- `*_wbtest.mbt` companions — the only executable invariant evidence today

**Verdict.** The design separates *facts*, *hypotheses*, *relations*, and
*lifecycle* well at the prose level — "identity is a hypothesis with evidence"
is exactly the right framing.

It has **one structural confusion** that propagates into every other section. It
also has **a set of invariants that are named as goals without being stated as
invariants**, so they are unenforced and sometimes contradicted by existing code.
The strongest output of this review is therefore the *missing* invariants rather
than new features.

---

## Core finding (read this first)

**The design conflates two different claims under the word "identity preserved":**

1. *Fact* — "the projection `NodeId` from the previous snapshot is still present
   in the current snapshot." This is decidable from the current document state
   (set membership over current observations). It is what the implementation's
   `find_heading_by_id` / same-node priority actually tests.
2. *Hypothesis* — "therefore this stable entity still corresponds to the same
   editing target / meaning." This is **not** decidable, and the design's own
   reorder investigation proves it is sometimes **false**: after `# A\n# B` →
   `# B\n# A`, previous-A's `NodeId` is positionally re-attached to current B.

The sketch states the hypothesis *as if it were the strong evidence*: "a
same-node match is the only evidence that the row's original session-local
identity survived." Phase 0/the reorder doc then contradict this for reorder.

Stated precisely: **a surviving `NodeId` proves projection-*handle* continuity,
rather than semantic continuity**; the reorder diagnostic
(`lang/markdown/proj/sdeg_heading_spike_wbtest.mbt:351`) records both prior
NodeIds surviving the swap, re-attached by position.

The fact is solid; same-node priority silently assumes the semantic hypothesis.
**Every structural invariant in the sketch can hold while this hypothesis is
false** — that is the central gap (see G1).

Secondary structural problem: the **three live documents disagree on the
lifecycle**, and the **implementation disagrees with both** in places.

The main design doc names six states and explicitly defers the transition table.
The sketch implements four states, with no `Missing` and no GC. Phase 1
implements five with a retention threshold.

The code now implements five with a configurable consecutive-absence threshold
for `Tombstoned → Retired`, while GC remains a predicate rather than a state. A
future implementer can faithfully follow any one source and be incompatible with
the others.

---

## Per-section analysis (main design doc)

For each section: (F)act vs current state, (H)ypothesis/matching decision,
(R)elations, (I)mplied-but-unstated invariant, (U)ntestable invariant,
(A)mbiguity, (L)ifecycle under-specification.

### Thesis / target model (layered stack)
- **F:** text/CRDT is source of truth; CST is parsed facts; entity layer is "a
  thin, evidence-bearing index over editing targets."
- **H:** "how confidently they correspond to targets from a previous state" — the
  entire correspondence-to-previous-state is hypothesis, correctly labelled.
- **R:** stack is a *layering* relation (each layer derived from the one above);
  the entity layer borrows the tree relation from projection, owns no tree itself.
- **I (unstated):** *SDEG guarantees ⊆ projection-identity guarantees* — the
  index cannot be more stable than the `NodeId` layer it indexes. Never stated;
  the identity/reuse decision doc shows the projection layer is itself
  deliberately limited (G8).
- **U:** "thin" and "index" are aspirational, not testable.
- **A:** "editing target" is never defined — heading? block? declaration? The
  unit of identity is left to the language adapter, so the whole model's grain
  is language-defined (intentional, but unbounded — G6 on the heading case).
- **L:** none here.

### Current stance (side-table over projection identity)
- **F:** projection identity, source maps, edit lowering exist (true; see
  identity/reuse decision doc).
- **H:** "projection identity provides session-local entity identity" — treated
  as fact, but is a *hypothesis equating projection identity with entity
  identity*. This is the core finding in another guise.
- **R:** entity → projection `NodeId` (anchor); entity → side-table status /
  evidence / anchors (owned). Tree relation is *borrowed*, explicitly.
- **I (unstated):** the side table must be a *pure function of* (prior snapshot,
  current observations) — i.e. deterministic and free of hidden state. The impl
  is pure-by-signature; never named as a contract.
- **U:** "satisfy the required stability scope" — no scope is measurable until
  one is named (next section names five but commits to one).
- **A:** "session-local" is the committed scope but `stable_id`'s seed *is* a
  `NodeId`, which is itself session-local and non-deterministic — fine for now,
  a serialization trap later (G10).
- **L:** none.

### Source of truth (edit path ordering)
- **F:** the canonical edit path (intent → language edit calc → patch → CRDT →
  parse → projection reconciliation → side table → views).
- **H:** none.
- **R:** a strict *happens-before / dataflow* relation; the side table is the
  penultimate consumer, derived views the last.
- **I (unstated, important):** **(Y3) advance must consume only
  post-reconciliation observations**, and **(Y2) a side-table update is not a
  document edit.** Stated in prose; nothing structurally prevents a consumer
  reading the table mid-edit or feeding pre-reconciliation observations (G11,
  G12).
- **U:** "updating entity metadata alone must not count as editing" — testable
  only as "advance has no write handles" (true by construction), but the broader
  "never becomes source of truth" depends on *consumer discipline*, which is
  untestable from inside SDEG.
- **A:** "successful" projection snapshot is implied but not defined here (G11).
- **L:** none directly, but this ordering is what makes `Missing` mean
  "absent after a successful reconciliation," which collides with malformed
  input (see Lifecycle / G2).

### Identity is a hypothesis
- **F:** the *evidence* values (range continuity, same role, semantic key, edit
  provenance, retained projection identity, language hints) are facts when
  present.
- **H:** the identity *conclusion* drawn from that evidence — explicitly framed
  as hypothesis. This section is the design's best moment.
- **R:** entity → evidence[] (the "justified by" relation). Note: *confidence is
  transient* — it lives on the per-advance `HeadingSideTableMatch`
  (`sdeg_heading_side_table.mbt:59`), **not** stored on the row (`:67`); only
  evidence + status persist.
- **I (unstated):** **evidence must be retained even when it does not yet drive
  behavior** (stated as intent). And: *confidence is monotone in evidence* — more
  corroborating evidence never lowers confidence. Never stated; the impl's ad-hoc
  `Exact/Probable/Ambiguous/Missing` ladder is not proven monotone.
- **U:** "record when identity is ambiguous or low confidence" is testable
  (and tested); "explainable" is not.
- **A:** evidence kinds are an open `extenum` — by design — so two languages can
  produce non-comparable evidence sets; the *core* only trusts the closed
  `confidence` + candidate ids. Good separation, but the **matcher contract is
  unstated** (what a matcher must guarantee for core invariants to hold — G9).
- **L:** none.

### Stability scopes
- **F:** five scopes named (single reparse / malformed intermediate / session /
  reload / peer); committed scope = session-local.
- **H:** which scope a given `EntityId` satisfies is a *claim about the future*
  the API must not over-promise.
- **R:** scopes form a *strength lattice* (reparse ⊂ malformed ⊂ session ⊂ reload
  ⊂ peer) — naming them as an explicit lattice would expose which cells are
  delegated vs owned.
- **I (unstated):** **reparse-stability and malformed-stability are delegated to
  loom's `ProjectionIdentityTracker`, not owned by SDEG** — the Phase 0 spike
  proves SDEG inherits exactly that layer's limits (no better on reorder, loses
  committed deletes). The scope list reads as SDEG promises; they are projection
  promises (G8).
- **U:** reload-stable and peer-stable are **untestable today** — no durable
  anchor, deterministic key, or persistent store exists. Correctly deferred, but
  that means three of five scopes have *no* possible evidence yet.
- **A:** "stable across malformed intermediate input" vs the `Missing` lifecycle:
  malformed input and deletion both produce absent observations (G2).
- **L:** the malformed scope is what `Missing` is *meant* to serve, but the
  mechanism cannot distinguish it from delete.

### Anchors and units
- **F:** Canopy has multiple integer coordinate spaces (source-code-unit, parser
  span, CRDT item, frontend tree). Anchors today are `@loomcore.Range` (UTF-16).
- **H:** none.
- **R:** entity → anchor (range + token spans) in a *named* coordinate space.
- **I (unstated, enforced only by convention):** **(Y5) every anchor carries an
  explicit unit.** The rule "must not expose raw position integers without naming
  the unit" is real, but `@loomcore.Range` is a *unit-blind* type (per the
  range/span decision doc it is plain ints with a documented—not type-enforced—
  unit). Passing an item-space or PM-tree range compiles. The invariant is
  *documented*, not *type-level* (G7).
- **U:** unit-correctness is untestable at the type system today; only review
  catches a wrong-unit anchor.
- **A:** "CRDT operation anchors can be added later through an adapter" — the
  adapter boundary is exactly where unit confusion historically bit Canopy
  (cursor PM vs doc offsets, PR #555). Unguarded.
- **L:** none.

### Relationship to event-graph-walker
- **F:** egw owns causal history, CRDT semantics, sync, undo.
- **H:** *which* entities deserve durable CRDT identity is a per-product judgment
  ("treat syntax-derived entities as extracted and reconciled unless a product
  case proves otherwise").
- **R:** a *composition* relation (SDEG composes with egw, must not duplicate it);
  and a future *durable-anchor* relation (entity → CRDT item) explicitly deferred.
- **I (unstated):** **no SDEG state may be authoritative over any egw state** —
  a stronger form of Y1 crossing the CRDT boundary. Implied, not stated.
- **U:** peer-sync invariants — untestable (no peer path).
- **A:** the boundary "syntax-derived vs structurally-edited" object is a
  judgment with no decision procedure; two implementers will draw it differently.
- **L:** durable-identity entities would need a *different* lifecycle (they can't
  be garbage-collected like extracted ones); the lifecycle model does not
  distinguish extracted from durable entities.

### Relationship to the incremental runtime
- **F:** labels/outlines/diagnostics/projections/summaries/AI-context are derived.
- **H:** none.
- **R:** entity facts → derived views (through `incr`), a derivation relation.
- **I (unstated):** **the side table stores facts+evidence and must not own cache
  invalidation** (stated); and the table must be *snapshot-immutable* so it can
  later sit behind an `incr` derived value (stated as preference). Immutability
  should be an invariant, not a preference.
- **U:** "avoid a mutable entity store that later has to be wrapped reactively" —
  a design smell test, not testable.
- **A:** "change summaries" are mentioned but never specified — what a change
  summary contains, and whether it is itself a fact or a diff, is open.
- **L:** none.

### Language boundary
- **F:** core is language-agnostic; extraction + edit lowering are language-owned.
- **H:** the five adapter answers (which nodes are entities, which anchors, which
  keys, how intent lowers, how to report evidence) are *all* per-language design
  hypotheses.
- **R:** core ↔ adapter contract; matcher is language-owned, core interprets only
  closed `confidence` + candidate ids.
- **I (unstated, important):** **the matcher contract** — to preserve S3/S4 the
  matcher must only return candidate ids that exist in the current observation
  set, and must not return a unique `Exact` for two distinct rows at one node.
  The impl is *partly* defensive (re-checks `find_heading_by_id`, demotes to
  `Tombstoned`/`Ambiguous`) but the contract is never written (G9).
- **U:** adapter quality ("good keys") is untestable generically.
- **A:** "which projection nodes count as stable editing entities" is the
  undefined "editing target" again.
- **L:** none.

### Lifecycle model
- **F:** none — this section is forward-looking.
- **H:** the entire lifecycle is "diagnostic until behavior is proven."
- **R:** status as an attribute relation entity → state; candidate relation
  entity → node[] for `ambiguous`.
- **I (unstated):** *retention policy is part of the lifecycle contract* — stated
  as a to-do ("define a transition table and retention policy") but the live
  sketch + Phase 1 + code already encode three different ones.
- **U:** `garbage-collectable` has no state entry condition because it is now a
  predicate over `Retired` (post-#745). `retired` now has a testable entry
  condition: a `Tombstoned` row retires once its consecutive-absence count reaches
  the side table's positive retention threshold (G3/#746).
- **A:** the six-state list here vs four (sketch) vs five (Phase 1/code).
- **L:** **this was the most under-specified section in the design.** It lists six
  states, defers the transition table, and the open question "whether non-live
  entities may be referenced by edges, diagnostics, selections, undo, or debug
  tooling" was the single most consequential undecided invariant (it gates GC
  safety, undo correctness, and reference integrity — G4/G13). *Now decided
  (#745):* see *Lifecycle Analysis → Decision: reference policy for non-live
  entities* (resolving-vs-pinning; GC is a predicate, not a sixth state).

### Phase 0 spike / Decision gates / Non-goals
- **F:** the spike scope and the concrete decision gates (five conditions that
  would justify a distinct core). Non-goals are crisp.
- **H:** "success means the existing pipeline preserves identity well enough" —
  "well enough" is a judgment, not a measured threshold.
- **R:** none new.
- **I (unstated):** the decision gates are *disjunctive* (any one triggers a
  core) but there is no invariant that the side-table approach must *fail
  explainably* before a gate is honored — the doc says "produces explainable
  failures," which should be an invariant (every non-`Live`/non-`Exact` outcome
  carries evidence). The impl does attach evidence to every row, so this is
  testable and largely met.
- **U:** "well enough for common heading edits" — no defined corpus.
- **A:** "common heading edits" undefined.
- **L:** none.

---

## Invariant Inventory

Grouped by category. Each: **Description · Scope · Preserved by · Allowed
violations · Failure symptoms · Existing evidence · Missing evidence.**
"Evidence" = tests/code that would confirm or deny the invariant.

### Identity invariants

**I1 — stable_id uniqueness.**
Every row has a `stable_id` distinct from all others.

*Scope:* per snapshot.

*Preserved by:* seeding from a unique `NodeId` +
the table's historical `used_stable_ids` reservation.

*Allowed violations:* none.

*Failure symptoms:* two rows alias; current-node index overwrites; lost
entities.

*Existing evidence:* snapshot-invariant test "stable_id unique"
(`sdeg_heading_side_table_wbtest.mbt`); enforced in `advance`.

*Missing
evidence:* property test over random observation streams (uniqueness across many
advances), not just single snapshots.

**I2 — stable_id immutability / session-locality.**
A `stable_id` never changes for the life of an entity; it is meaningful only
within one editor session + one table.

*Scope:* session.

*Preserved by:* `stable_id` set at birth from origin
`NodeId`, never reassigned.

*Allowed violations:* none in-session; *undefined*
across reload/peer (correctly out of scope).

*Failure symptoms:* a serialized
`stable_id` silently rebinds after reload.

*Existing evidence:* `priv` wrapper
keeps it internal (impl).

*Missing evidence:* a guard/test that `stable_id`
cannot be serialized or leak into a public `.mbti` (the Phase 1 risk note flags
this socially, not structurally) — see G10.

**I3 — same-node priority.**
If the origin `NodeId` is still present, the entity is kept on it *before* any
semantic recovery candidate is considered.

*Scope:* per advance.

*Preserved by:*
`heading_side_table_match_with_same_node_priority` +
`current_without_ids(semantic_current)`.

*Allowed violations:* only when an
explicit move-provenance reconciler overrides it (block-move spike); never
side-table-only.

*Failure symptoms:* a present node gets stolen by a semantic
duplicate; flicker.

*Existing evidence:* test "same-node priority wins over a
duplicate retained row's semantic claim."

*Missing evidence:* none for the
positive case; the *negative* case (when same-node priority is wrong — reorder)
has no corrective invariant (see I5/G1).

**I4 — one-to-one current-anchor** (also structural).
No two `Live` rows share a `current_id`.

*Scope:* per snapshot.

*Preserved by:* claim-count demotion to `Ambiguous` +
fresh-row exclusion.

*Allowed violations:* none.

*Failure symptoms:* two
entities both claim one node → double-counted outline/diagnostics.

*Existing
evidence:* snapshot-invariant test "no two Live rows share current_id." ·
*Missing evidence:* a test that an adversarial matcher returning two `Exact`s for
one node still cannot violate it (the impl path for same-node rows bypasses the
claim graph — G5).

**I5 — (MISSING) `NodeId` continuity is positional, not semantic.**
Same-node evidence proves *position-stable* continuity; it does **not** prove the
entity means the same thing. Should be stated as an explicit non-guarantee.

*Scope:* always.

*Preserved by:* nothing — it is a *limit*, currently
implicit.

*Allowed violations:* this is the violated property under reorder.

*Failure symptoms:* silent semantic misattribution (old-A row now labels
content-B), with *all* other invariants green.

*Existing evidence:* the reorder
diagnostic tests record the *fact* (NodeIds swap attachment) but assert it as
"expected limitation," not as a named invariant.

*Missing evidence:* an
invariant + test asserting "no consumer may treat a `Live` row's meaning as
stable across edits that can reorder siblings without move provenance" (G1).

### Structural invariants

> Evidence note: S1–S4 and I1/I4 are **not** individually-named tests. They are
> asserted collectively by a shared white-box predicate,
> `heading_side_table_invariants_hold`.
>
> The predicate is exercised across rename, restore, reorder, and delete cases in
> `sdeg_heading_side_table_wbtest.mbt` (`:141`, called from `:187`,`:292`,`:317`,
> `:340`,`:361`,`:396`–`:431`). The current-node index is checked by
> `heading_side_table_index_valid` (`:127`).
>
> "Existing evidence" lines below name that shared predicate rather than
> per-invariant tests.

**S1 — Live ⟺ current_id = Some.**

*Scope:* snapshot.

*Preserved by:*
`row_from_match` constructs `Live` only with `Some(current_obs.id)`.

*Allowed
violations:* none.

*Failure:* a `Live` row with no node (dangling).

*Existing
evidence:* snapshot-invariant test.

*Missing:* none material.

**S2 — non-Live ⟹ current_id = None.** (`Missing`/`Tombstoned`/`Ambiguous`/
`Retired`.)

*Preserved by:* `row_from_match` sets `current_id: None` on every
non-Live arm.

*Allowed violations:* none.

*Failure:* stale anchor on a
tombstoned row.

*Existing evidence:* snapshot-invariant test.

*Missing:*
test that `Ambiguous` keeps candidates but `current_id = None` simultaneously.

**S3 — live current_id ∈ current projection.**
Every `Live` row's `current_id` refers to an observation in the *current*
snapshot.

*Preserved by:* `row_from_match` re-resolves via
`find_heading_by_id(current, id)` and downgrades to `Tombstoned` if absent. ·
*Allowed violations:* none.

*Failure:* anchor points at a vanished node. ·
*Existing evidence:* the shared invariant predicate (see note).

*Missing
evidence:* a *future generic* matcher-contract test — the current impl hardcodes
matching (`heading_side_table_match`) and derives candidates only from current
observations, defensively tombstoning absent ids
(`sdeg_heading_side_table.mbt:201`,`:326`), so the gap is latent in the *designed*
pluggable matcher (G9), not a hole in today's code.

**S4 — Ambiguous ⟹ candidates nonempty.**

*Preserved by:* `Ambiguous` arm
sets `candidates: ids` (the multi/conflicting branch).

*Allowed violations:*
none.

*Failure:* an ambiguous row with nothing to resolve to.

*Existing
evidence:* invariant test.

*Missing:* none material.

**S5 — no duplicate representation.**
A node listed as an `Ambiguous` candidate is not also emitted as a fresh `Live`
row in the same snapshot.

*Preserved by:* `fresh_rows` filter via the
`heading_mentioned_current_ids` set (checks both `current_id` and `candidates`). ·
*Allowed violations:* none.

*Failure:* one node both spawns a new entity and is
a pending candidate → eventual double identity.

*Existing evidence:* invariant
test "candidate ids not emitted as fresh Live rows."

*Missing:* test of the
ordering dependency (fresh rows computed against already-advanced `next_rows`).

**S6 — Retired is inert.**
`Retired` rows never match and never become `Live` again.

*Preserved by:*
`row_active` filter excludes them; `advance`/`row_from_match` pass them through
with `current_id: None`.

*Allowed violations:* none.

*Failure:* a retired
entity resurrects, colliding with a fresh one.

*Existing evidence:* impl
filters; "retired-row behavior" test; retention-threshold test exercises the
`Tombstoned → Retired` entry path; GC tests remove retired rows while preserving
historical stable-id reservations.

*Missing:* production GC still needs a live
pinning-reference set.

**S7 — tree relation is borrowed.**
SDEG owns no entity-to-entity tree; structure comes from projection children. ·
*Scope:* whole design.

*Preserved by:* the side table stores no parent/child
edges.

*Allowed violations:* none until a decision gate adds graph relations.

*Failure:* SDEG accidentally becomes a parallel tree (a stated non-goal). ·
*Existing evidence:* impl has no edge storage.

*Missing:* none (absence is the
invariant); but "same/nearby section context" evidence (sketch) would *introduce*
a containment relation — currently unbuilt (G6).

**S8 — current_index is a materialized view of live rows only.**
The `NodeId → StableRowId` index contains exactly the `Live` rows (cardinality =
live-row count); a lookup returns the live row's `stable_id`.

*Scope:*
snapshot.

*Preserved by:* `heading_current_index` rebuilds it each advance from
`(HeadingLive, Some(id))` rows only (`sdeg_heading_side_table.mbt:105`). ·
*Allowed violations:* none.

*Failure symptoms:* a stale/over-full index
resolves a node to a dead entity.

*Existing evidence:*
`heading_side_table_index_valid` (`sdeg_heading_side_table_wbtest.mbt:127`). ·
*Missing evidence:* none material.

### Semantic invariants

**Sem1 — never guess; duplicates stay Ambiguous.**
Semantic recovery must be one-to-one and evidence-bearing; a non-unique semantic
match degrades to `Ambiguous`, not a guess.

*Scope:* per advance.

*Preserved
by:* `heading_side_table_match` `semantic_count` branches (`==1` Probable, `>1`
Ambiguous).

*Allowed violations:* none side-table-only.

*Failure:* a restore
attaches to the wrong duplicate.

*Existing evidence:* tests "duplicates produce
ambiguity," "restore recovers unique."

*Missing:* a test where two retained
rows + one current observation compete (retained-side ambiguity, not just
current-side).

**Sem2 — (IMPLIED) semantic keys are not unique.**
The key (level + text) may collide; the matcher must treat collision as
ambiguity, never as identity.

*Scope:* always.

*Preserved by:* Sem1. ·
*Allowed violations:* none.

*Failure:* two genuinely different headings merged.

*Existing evidence:* duplicate-heading tests.

*Missing:* this is never
*stated* as an invariant; it is only emergent from the duplicate handling.

**Sem3 — (MISSING) identity should track meaning rather than position.**
The semantic counterpart to I5. No invariant asserts that an entity's *meaning*
is preserved; only that a node binding exists.

*Failure:* reorder.

*Existing
evidence:* none (the design accepts the violation as a limitation).

*Missing:*
the entire invariant, plus a corrective mechanism (move provenance) gated behind
a future block-edit path (G1).

**Sem4 — (MISSING) normalization contract for keys.**
"normalized heading text" is specified in the sketch/Phase 0 but the impl uses
*raw* `obs.text` equality.

*Scope:* matcher.

*Preserved by:* nothing
defined.

*Failure:* `# A ` vs `# A`, `# *A*` vs `# A`, NFC vs NFD, case — two
implementers normalize differently → divergent ambiguity/recovery.

*Existing
evidence:* none (raw equality only).

*Missing:* an explicit normalization spec
(note: repo already has the `moji` Unicode library — candidate owner) (G6).

**Sem5 — (IMPLIED) every match outcome records candidate cardinality.**
Same-node birth/match, missing, ambiguous, and restore each push an evidence
record incl. `HeadingCandidateCount(_)` (`sdeg_heading_side_table.mbt:100`,`:214`,
`:236`,`:243`), making each decision explainable — the operational form of
"identity is a hypothesis with evidence."

*Scope:* per row.

*Preserved by:*
the evidence array populated on every `row_from_match` arm.

*Allowed
violations:* none intended.

*Failure symptoms:* an unexplained status change.

*Existing evidence:* evidence fields populated on every arm.

*Missing
evidence:* an invariant test that *asserts* non-empty evidence on every row —
currently incidental, not enforced.

### Lifecycle invariants

**L1 — absence ladder.**
First absence → `Missing`; continued absence → `Tombstoned`; when the table has a
positive retention threshold, a `Tombstoned` row retires once its
`consecutive_absences` reaches that threshold, with thresholds below `3` still
retiring on the third valid absence because the second valid absence remains an
observable `Tombstoned` frame.

*Scope:* per advance. ·
*Preserved by:* `row_from_match` empty-ids arm.

*Allowed violations:* none. ·
*Failure:* immediate tombstoning loses one-frame-flicker recovery, or unbounded
retention ignores an explicit threshold.

*Existing evidence:* tests for first
absence, repeated absence, below-threshold retention, and threshold retirement. ·
*Missing:* the sketch still differs by making first absence `Tombstoned` (N=1).

**L2 — recovery retention.**
`Missing`/`Tombstoned`/`Ambiguous` rows retain `last_live` observation so a later
unique match can recover them.

*Scope:* session.

*Preserved by:* `..row`
spread keeps `last_live`.

*Allowed violations:* after `Retired`/GC (undefined).

*Failure:* premature discard → unrecoverable restore.

*Existing evidence:*
restore test; GC reservation test shows physical row removal does not make a
collected `stable_id` reusable.

*Missing:* a production retention bound tied to
pinning references.
*Additional invariant (L2a):* `last_live` is updated **only** on an accepted
`Live` match (`sdeg_heading_side_table.mbt:328`) and carried unchanged through
`missing`/`tombstoned`/`ambiguous` via row spread (`:316`,`:346`,`:308`) — so the
recovery substrate never drifts while an entity is absent.

**L3 — Retired is terminal.**

*Preserved by:* S6.

*Existing evidence:* inert
behavior, threshold-entry behavior, and row-removal/GC tests that keep retired
stable ids reserved after physical removal.

*Missing:* production pinning-set
integration.

**L4 — garbage-collectable is a property, not a state.**
The design lists it as a lifecycle state; sketch/Phase 1 treat GC as policy. ·
*Existing evidence:* `gc_eligible` is a predicate over `Retired`; `collect_garbage`
physically removes retired rows while preserving historical stable-id reservations.

*Missing:* production computation of the live pinning-reference set.

*Decided
(#745):* predicate over `Retired`; safety precondition = no pinning reference (see
*Decision: reference policy for non-live entities*). The `Retired` entry transition
is now implemented via the retention threshold (#746).

**L5 — (DECIDED #745) reference rules for non-live entities.**
Whether `Missing`/`Tombstoned`/`Ambiguous`/`Retired` entities may be referenced
by edges, selections, undo, diagnostics, or debug tooling was **explicitly
undecided** in the design.

*Failure:* undo points at a GC'd entity; a selection
survives a tombstone inconsistently.

*Existing evidence:* none.

*Decided (#745):* the *kind* of reference governs, not the consumer.

Resolving references (selection/diagnostics/debug) may name any non-live entity
and never block GC. Only pinning references (future edges) extend retention.
Undo is egw-owned and never references SDEG entities.

This unblocks L4 (GC safety). See *Decision: reference policy for non-live
entities*.

### Synchronization invariants

**Y1 — side table is derived, never source of truth.**
`advance` must not mutate source text, projection nodes, source maps, CRDT state,
or undo.

*Scope:* always.

*Preserved by:* **construction** — `advance` takes
only `Array[HeadingObservation]` (value copies of ids/ranges) and returns a new
table; it holds no handle to mutate document state.

*Allowed violations:* none.

*Failure:* metadata write masquerades as an edit; collaboration/undo desync. ·
*Existing evidence:* the function signature (type-level); invariant test "the
side table never mutates source/projection/source-map/CRDT."

*Missing:* a test
that a *downstream consumer* treating the table as authoritative is prevented —
unenforceable from inside SDEG (a documentation/contract gap, G12).

**Y2 — metadata update ≠ document edit.**

*Preserved by:* Y1 + the edit-path
ordering.

*Existing evidence:* edit-path tests run advance *after* `SyncEditor`.

*Missing:* structural enforcement that advance is never on the edit path.

**Y3 — post-reconciliation ordering.**
advance consumes observations only after parse + projection reconciliation. ·
*Preserved by:* convention (the pipeline diagram) plus the side-table
validity-tag hold path.

*Existing evidence:* companion edit-path test derives
observations after `SyncEditor`; #748/#767 wbtests cover invalid snapshots
through the production source-map memo path. The Markdown heading side-table
memo derives validity from parser diagnostics plus recovered projection `Error`
nodes before calling `advance`.

**Y4 — (DEFERRED/UNTESTABLE) reload + peer stability.**
Out of scope by design; no durable anchor, deterministic key, or persistent
store.

*Existing evidence:* none possible.

*Missing:* all of it — correctly
deferred, but means three of five named stability scopes have *zero* evidence.

**Y5 — anchors carry explicit units.**
All anchors are UTF-16 code-unit `@loomcore.Range`.

*Preserved by:* convention
(`@loomcore.Range` is unit-blind).

*Existing evidence:* the range/span decision doc records the unit rule, and the
implementation uses `@loomcore.Range` consistently.

*Missing:* a unit-bearing
wrapper at the boundary, and a test/guard against mixing item-space / PM-tree
ranges — the adapter boundary for CRDT anchors is the live risk (G7).

---

## Operation Preservation Matrix

Derived from the design + the spikes + the code (not assumed). "Evidence
required" = the evidence the matcher needs to make the right call.

| Operation | May change | Must be preserved | Evidence required | Failure mode |
|---|---|---|---|---|
| **rename** (`# A`→`# A2`) | signature (level+text), source range, token spans, recorded evidence | `stable_id`, current `NodeId` (same-node), `Live`, one-to-one anchor | `HeadingSameNodeId` (NodeId survives the edit path) | if `NodeId` were freshened, rename ≡ delete+spawn → identity lost. *Holds today* (Phase 0 + edit-path rename test). |
| **reorder** (`# A\n# B`→`# B\n# A`) | ordinal/position; which `ProjNode` each `NodeId` attaches to | (today) *nothing semantic* — explicitly "position-stable, not semantic-stable" | would need explicit **move provenance** (`IdentityTransform::Move`); side-table-only has none | **silent semantic misattribution** — all structural invariants green, meaning wrong (I5/Sem3). Corrected by the explicit block-move path for root siblings (#723) and same-list items (#731); cross-container / list-container moves stay rejected — see *Decision: Markdown move-provenance scope* (#724). |
| **duplicate** (`# A\n# A`) | confidence → `Ambiguous`; candidate set | distinct `stable_id` per distinct `NodeId` while both present; one-to-one (I4) | `HeadingSameSemanticKey` collision + `CandidateCount>1` | guessing → two rows on one node, or restore to wrong twin. *Avoided* by staying `Ambiguous` (duplicate test). Spurious collision if normalization is loose (Sem4). |
| **delete** (`# A` removed) | status `Live→Missing→Tombstoned`; `current_id→None` | `stable_id`; `last_live` (recovery substrate) | `CandidateCount(0)` from a valid snapshot | committed delete also drops the projection baseline (Phase 0), so SDEG's retained `last_live` is the *only* recovery path; delete evidence must come from a valid snapshot. |
| **restore** (deleted heading re-typed) | a new current `NodeId` (in the tested path); status →`Live` | original `stable_id` recovered iff a *unique semantic candidate* exists while the prior node is absent (freshness not required) | `HeadingSameSemanticKey` + unique candidate | duplicate text → stays `Ambiguous` (no guess); different normalization → spawns fresh (not recovered); only works before `Retired`/GC. |
| **malformed input recovery** | invalid snapshots mark `Live`/`Ambiguous` rows unavailable (`Missing`, no current anchor/candidates) until a valid snapshot returns | `stable_id`, `last_live`, and `consecutive_absences` across the bad window; ideally `NodeId` via `ProjectionIdentityTracker` | production `HeadingSnapshotInvalid` signal derived from parser diagnostics plus projection `Error` nodes, plus later NodeId survival (delegated to loom) or semantic recovery | invalid snapshots clear current anchors/candidates but do not increment absence counters or advance `Missing→Tombstoned→Retired`; #767 wires this through the Markdown source-map memo path. |
| **large paste** | many fresh `NodeId`s + fresh rows; possible mass ambiguity | rows whose `NodeId`s survive (untouched headings) | same-node for survivors; fresh for pasted | region-replacing paste freshens `NodeId`s → looks like delete-all+spawn-all; pasted duplicate text mis-resolves; **matching is O(rows×obs)** (nested filters) — scaling not stated as an invariant. |
| **format-like rewrite** (whitespace/formatter) | source ranges, token spans (shift) | `stable_id`, `NodeId`, `Live`, signature (text unchanged) | same-node + same-key + overlapping-range | low risk; if formatter alters text normalization, key changes but same-node priority still preserves identity. *Holds today* (Phase 0). |
| **projection regeneration** | full observation set + current-node index rebuilt | rows across regeneration | whatever `NodeId`s/keys survive regeneration | wholesale `NodeId` refresh (non-incremental rebuild) → mass semantic recovery; uniques recovered, duplicates → `Ambiguous`. **Bounded entirely by projection-identity stability** (G8). |
| **reparse** (single) | token spans, ranges | `NodeId` via incremental reparse + tracker | same-node | parser reuse (`ReuseCursor`) is *structural, not identity* (identity/reuse decision) — reparse-stability is **not** a parser guarantee, only a projection-tracker one layered above (G8). "Stable across a single reparse" is the minimal named scope. |

---

## Decision: Markdown move-provenance scope (#724)

Resolves the corrective-mechanism *reach* for **reorder** (Operation Preservation
Matrix) and the implemented half of **G1**: explicit move provenance now
preserves identity across the *safe* moves and **documents a proof-backed reason**
for the moves it keeps rejecting (issue #724, AC#3, second clause).

Decided 2026-06-23; code is source of truth
(`lang/markdown/edits/compute_move_block.mbt`,
`lang/markdown/proj/move_reconcile.mbt`).

`MarkdownEditOp::MoveBlock(source, target, position)` carries an explicit
`IdentityTransform::Move(subtree=id)` so a moved block keeps its `NodeId` and its
SDEG row instead of being read as delete-at-old + spawn-at-new.

The identity-preserving reconciler is `reconcile_markdown_children_hinted`. At
each container level it excludes the move source from the LCS match
(`is_move_source` over that level's `old_children`), then pairs it to a **unique
exact-payload sibling among that same container's new children**
(`markdown_move_pair` + `markdown_move_pair_counts`, requiring a pair count of 1).

**Shipped — identity preserved.**

| Move | Provenance path | Coverage |
|---|---|---|
| root-level sibling block (heading/paragraph/code), unique payload | #723, `compute_root_move_source` | `compute_markdown_edit_wbtest.mbt` `move_block: *` |
| same-list item reorder (ordered/unordered), unique payload | #731, `compute_list_item_move_source` | same file, `move_block: *list item*` incl. renumbering, `.`/`)` delimiters, start-value, separators |

**Rejected — proof-backed (the sibling-level reconciler structurally cannot
preserve identity here).**

1. **Cross-container moves** — list item → root, root block → into a list, or an
   item → a *different* list. Gate: `compute_move_block.mbt:45-55` (the
   `is_markdown_list_item` arms at `:46-50` give the targeted blocker messages).
   The `Move` hint is keyed by the subtree's `NodeId` and is consulted only at the
   container level where that id is a *direct child*. A relocated node leaves
   container A and surfaces as an *unmatched new child* of container B, but
   `markdown_move_pair` only searches the **current** container's `old_children` —
   so the move-source exclusion in A and the orphan in B never meet. The output is
   rebuilt from `new_children` only: the relocated content surfaces as an unmatched
   new child of B and is given a fresh id by `assign_fresh_ids`, while the source
   node is simply dropped from A's reconciled children. The moved block therefore
   does not inherit the source's `NodeId`, and identity is lost. This is an *architectural
   limit of the sibling-level pairing reconciler*, **not an impossibility**:
   preserving identity across a container boundary needs the ancestor-aware
   container reconciliation #724 itself names as unbuilt — the same work Decision
   Gate #3 (graph relations beyond the projection tree) would add.

2. **List-container source** — moving a whole `UnorderedList` / `OrderedList`.
   Gate: `compute_move_block.mbt:62-64`. Containers match by *kind only*:
   `markdown_child_match` falls through to `@loomcore.TreeNode::same_kind` for any
   `is_block_container` node, never by payload. A moved list among ≥2 same-kind
   sibling lists therefore yields a pair count > 1 (or a spurious match against the
   wrong list) and cannot be *uniquely* paired, so identity attribution would be a
   guess — which the no-guessing ethic (S4/S5) forbids. The item-level ambiguity
   rule does not transfer: it needs an exact payload, which the explicit list
   payloads (#730) deliberately do not carry at the container level.

3. **Loose lists** — blank-line-separated items. Gate:
   `reject_loose_list_separators`. Source-text lowering re-emits items with
   single-`\n` separators (`compute_list_item_move_source`); applying it to a loose
   list would silently reflow loose → tight, a semantic change to the surrounding
   list rather than a move, so the move is rejected instead of performed lossily.

**Why this closes #724.** The acceptance criteria are met *without* widening
cross-container legality:

| Acceptance criterion | Satisfier |
|---|---|
| distinguish ordered vs unordered without `SourceMap` side channels | #730 (explicit list payloads) |
| still reject every list-container source variant | gates above (`:62-64`), regression-tested (#726) |
| sibling moves with identity preservation **or** a proof-backed rejection | #731 (sibling) + this decision (cross-container) |
| tests: `- B` before `- A`, ordered moves, ordered/unordered + duplicate ambiguity, marker renumbering, synthesized separators | #731 (`compute_markdown_edit_wbtest.mbt`) |
| #723 root-move tests + #726 blocker regressions still pass | green on `main` |

The remaining cross-container / list-container legality and loose-list separator
preservation are tracked as narrow follow-ups under the drag-drop-foundation item
in `docs/TODO.md` (§10), not under a still-open #724.

---

## Lifecycle Analysis

Authority: **code is source of truth** (`sdeg_heading_side_table.mbt`). Where
the three design docs disagree, the code wins and the conflict is flagged.

### Per-state

**live**
- *Entry:* fresh observation with no matching/candidate row; OR an active row with
  a same-node match; OR a unique `Exact`/`Probable` (claim-count 1) semantic match
  from `Missing`/`Tombstoned`/`Ambiguous`.
- *Exit:* → `Missing` (no candidates); → `Ambiguous` (multiple/conflicting).
- *Allowed references:* `current_id = Some`, in current projection (S1, S3).
- *Retention:* n/a (current).
- *Open:* none.

**missing**
- *Entry:* `Live`/`Ambiguous` row with zero candidates this advance.
- *Exit:* → `Live` (unique recovery); → `Tombstoned` (still absent next advance).
- *Allowed references:* `current_id = None`; retains `last_live`.
- *Retention:* whole session unless a positive table retention threshold later
  retires the row after it has become `Tombstoned`.
- *Resolved for Markdown headings:* invalid snapshots can mark current anchors
  unavailable without advancing the tombstone ladder. PR #767 derives the
  validity signal from parser diagnostics plus projection `Error` nodes and
  passes it through the production source-map memo path before `advance`.
  `Missing` does **not exist** in the sketch (sketch jumps straight to
  `Tombstoned`).

**ambiguous**
- *Entry:* active row with >1 candidate, or whose sole candidate is contested, or
  whose assignment cannot be made unique without guessing.
- *Exit:* → `Live` (resolves uniquely); → `Missing` (all candidates vanish).
- *Allowed references:* `current_id = None`; `candidates` nonempty (S4); those
  candidates may not also be fresh `Live` rows (S5).
- *Retention:* whole session.
- *Open:* `Ambiguous`+no-match → `Missing` (code/Phase 1) vs `Tombstoned`
  (sketch). The "global one-to-one assignment" that *defines* ambiguity is stated
  but only locally approximated (G5).

**tombstoned**
- *Entry:* `Missing`/`Tombstoned` row absent again (the 2nd consecutive absence).
- *Exit:* → `Live` (unique recovery); stays `Tombstoned` while absent below the
  retention threshold; → `Retired` once `consecutive_absences >= retention_threshold`
  and the threshold is positive.
- *Allowed references:* `current_id = None`; retains `last_live`.
- *Retention:* whole session by default (`retention_threshold = 0`); bounded by a
  configured positive threshold.
- *Open:* in the sketch, `Tombstoned` is the *first* absence state (no `Missing`).

**retired**
- *Entry:* `Tombstoned` row absent on an advance where the table has a positive
  retention threshold and the row's `consecutive_absences` reaches that threshold.
- *Exit:* none (terminal).
- *Allowed references:* `current_id = None` (S6); per #745, resolving references
  (selection/diagnostics/debug) may name it but resolve to nothing — debug can
  still inspect its frozen `last_live` — and a pinning reference would block GC.
- *Retention:* it *is* the retention boundary; the threshold is configured per
  table, with `0` meaning "never retire".
- *Open:* production row-removal/GC must still be gated by the live pinning set;
  the test-local `collect_garbage` path preserves historical stable-id reservations.

**garbage-collectable** — *resolved to a predicate, not a state (#745).*
- *Entry:* **no representation** as a state — and, per #745, none is needed: it is
  a predicate over `Retired` (see *Decision: reference policy for non-live
  entities*).
- *Exit:* n/a.
- *Allowed references:* a `Retired` row is collectable when **no pinning
  reference** targets it; resolving references (selection/diagnostics/debug) never
  block GC (L5 decided).
- *Retention:* the predicate `gc_eligible` *is* the "safe to discard" test —
  unconditional today (no pinning refs), edge-gated in future.
- *Resolved:* state-vs-predicate → predicate; safety precondition → no pinning
  reference (G4 GC-half / G13 / L4 / L5). The `retired` entry threshold is now
  implemented as a side-table setting (G3/#746).

### Derived transition table

The table below describes valid/successful projection snapshots. Invalid
snapshots use the side-table hold path: no initial or fresh rows are created,
`Live`/`Ambiguous` rows become `Missing` with current anchors cleared,
`Missing`/`Tombstoned`/`Retired` stay in place, `last_live` is preserved, and
`consecutive_absences` does not change.

`✓` implemented & tested · `(impl)` in code, not directly tested ·
`(design-only)` named in a doc but **not** in code · `✗` impossible today.

`garbage-collectable` has **no column**: per the #745 decision it is a predicate
over `retired`, not a state (see *Decision: reference policy for non-live
entities*).

| From → To | live | missing | ambiguous | tombstoned | retired |
|---|---|---|---|---|---|
| *(none)* → | ✓ new observation | — | — | — | — |
| **live** | ✓ same-node / unique match | ✓ no candidates | ✓ multiple/contested | ✗ (must pass through missing) | ✗ |
| **missing** | ✓ unique recovery | ✗ never stays `missing` — continued absence → `tombstoned` (`sdeg_heading_side_table.mbt:311`) | (impl) multiple recovery candidates | ✓ absent again | (design-only) |
| **ambiguous** | ✓ resolves unique | ✓ all candidates vanish | (impl) still multiple | ✗ (goes to missing first) | (design-only) |
| **tombstoned** | ✓ unique recovery | ✗ | (impl) multiple recovery candidates | (impl) stays absent below threshold | ✓ retention threshold reached |
| **retired** | ✗ (S6) | ✗ | ✗ | ✗ | (impl) inert self |

**Conflicts surfaced by the table:**
1. `Missing` column is empty in the sketch's model (sketch has no `Missing`).
2. `ambiguous → tombstoned` is the sketch's rule; code routes `ambiguous →
   missing`. Direct contradiction.
3. `gc` is no longer a state — per the #745 decision it is a predicate over
   `retired` (column removed; see *Decision: reference policy for non-live
   entities*). `retired` now has an implemented threshold entry transition
   (#746), so the lifecycle is **five states + one predicate**.
4. The `live → tombstoned` direct edge in the sketch ("Live + no match →
   Tombstoned") does not exist in code (code inserts `Missing` first).

### Decision: reference policy for non-live entities (#745)

Resolves **G13 / L5** and the garbage-collection half of **G4 / L4**. Decided
2026-06-23 by brainstorm; the principle-level statement lives in
`stable-document-entity-graph.md` (Lifecycle model), and this document holds the
code-grounded mechanics.

The retention threshold N and the `retired` *entry* transition are now
implemented in the side table (#746). `missing`'s delete-vs-malformed overload is
resolved for Markdown headings by the production validity signal (#748/#767).

**Discriminator: the *kind* of reference, not the consumer.**

- *Resolving reference* — read-time, transient, non-owning; re-evaluated every
  `advance`; never extends retention. May name any non-live entity.
- *Pinning reference* — durable, owning, retention-extending. The only kind that
  can keep a non-live entity from being collected.

**Per consumer class.**

| Consumer | Reference kind | May reference non-live? | Resolves to |
|---|---|---|---|
| edges / relations | pinning (Decision Gate #3; unbuilt) | yes — the only pinning class | the entity; **pins it against GC** |
| selection | resolving | yes | per the per-state resolution below (live → node; missing/tombstoned/retired → nothing; ambiguous → candidate set) |
| diagnostics | resolving (re-derived per snapshot) | yes | per the per-state resolution below (incl. `last_live` for display; ambiguous → candidate set) |
| debug tooling | resolving, read-all, inert | yes, incl. `retired` | full row: status + evidence + `last_live` |
| undo | none — egw-owned, operates on CRDT items | no reference to SDEG entities | — |

Undo is owned by event-graph-walker (egw owns causal history / undo); it never
references SDEG entities, so it is out of scope by the layering boundary (no SDEG
state authoritative over egw — the stronger form of Y1). A future *semantic* undo
that named an entity directly would be a pinning reference under the edge rule.

**Per-state resolution (the "what does it resolve to" rule).**

| State | Resolves to |
|---|---|
| `live` | current `NodeId` (S1, S3) |
| `missing` | nothing; `last_live` retained for display (L2/L2a) |
| `tombstoned` | nothing; `last_live` retained for display |
| `ambiguous` | the **candidate set** — consumers handle multiplicity, never a single node (S4) |
| `retired` | nothing; inert and not resolvable (S6). Retains frozen `last_live` in storage (the `HeadingRetired` arm spreads `..row`, clearing only `current_id`/`candidates`), so debug tooling can still inspect it. |

**`garbage-collectable` is a predicate, not a state** (confirms L4). Over a
`retired` row:

> `gc_eligible(row) := row.status == Retired && no live pinning reference targets it`

No pinning references exist today (no edge layer), so `retired ⟹ gc_eligible`
unconditionally now. The predicate's *form* reserves the future edge case: a
`retired` row targeted by a live edge is **not** collectable.

This decision fixes only the GC *safety precondition*. GC safety, undo
correctness, and bounded retention (L2/L5) all require that precondition. The
threshold that drives a row *into* `retired` is governed by the side table's
retention threshold (#746).

---

## Minimal Relational Core

Ignoring implementation, the **minimal set of relations** needed to express the
stated goals ("which editing targets exist now, where anchored, how confidently
they correspond to previous targets"):

**1. identity-seed: `StableRowId → origin NodeId`** (total, immutable)
- *Why:* gives each entity a session-local identity distinct from its current
  projection node.
- *Invariants depending on it:* I1 (uniqueness), I2 (immutability/session-scope).
- *Lifecycle:* set at birth, never changes; survives every state incl. `Retired`.

**2. current-anchor: `StableRowId ⇀ current NodeId` + range/spans** (partial)
- *Why:* "where is this entity *now*" — the index's primary job.
- *Invariants:* S1 (Live⟺Some), S2 (non-Live⟹None), S3 (∈ current), I4/Y5.
- *Lifecycle:* defined only in `live`; `None` in every other state.
- *Note:* the inverse `current NodeId → StableRowId` (the impl's `current_index`)
  is a **materialized view of this relation**, not a primitive — rebuilt each
  advance. Not part of the minimal core.

**3. last-observation: `StableRowId → HeadingObservation`** (total)
- *Why:* the retained facts (range, semantic key from level+text, token spans)
  that make semantic *recovery* possible; also the diagnostic record. (`ordinal`
  appears in the Phase 1 *sketch* but **not** in the implemented
  `HeadingObservation`, `sdeg_heading_side_table.mbt:5`; `confidence` is likewise
  transient, not a stored relation.)
- *Invariants:* L2 (retention enables recovery), Sem1/Sem4 (keys come from here).
- *Lifecycle:* live-updated while `live`; frozen on entering `missing`; carried
  through `tombstoned`; becomes immutable history at `retired`.

**4. candidate: `StableRowId → Set[NodeId]`** (partial)
- *Why:* represent *ambiguity without guessing* — the design's core ethic. Must be
  first-class (not derivable) because ambiguous candidates both (a) block fresh
  spawns (S5) and (b) are the resolution set for later advances.
- *Invariants:* S4 (Ambiguous⟹nonempty), S5 (not spawned fresh).
- *Lifecycle:* meaningful only in `ambiguous`; empty elsewhere.

**5. evidence: `StableRowId → Set[Evidence]`** (total, open codomain)
- *Why:* "identity is a hypothesis *with evidence*" — every decision must be
  explainable; this is the relation that makes failures diagnosable.
- *Invariants:* the (unstated) "explainable failure" invariant; confidence derives
  from it.
- *Lifecycle:* all states except `retired` (where it is frozen history).

**Borrowed (not SDEG-owned): projection-child: `NodeId → Set[NodeId]`**
- *Why:* the *only* tree/structural relation; the design deliberately reuses the
  projection tree (S7) rather than owning one.
- *Invariants:* none SDEG-owned; SDEG must not duplicate it (non-goal).
- *Lifecycle:* lives entirely in the projection layer; SDEG reads it transiently.

**Conclusion:** the goals as written need **five SDEG-owned relations + one
borrowed tree**. Relations 1–3 + 5 express "index + anchor + confidence" directly.
Relation 4 is forced by the no-guessing ethic.

Any *additional* entity-to-entity relation, such as containment, section context,
or cross-references, is **outside the minimal core**.

That is exactly what Decision Gate #3 ("graph relations beyond the projection
tree") would add, which confirms the design's own gate placement. The
"same/nearby section context" evidence floated in the sketch is the first thing
that would push relation 6 (containment) into the core; it is currently unbuilt.

---

## Design Gaps

Ordered by severity. Each is a place where behavior depends on an **unstated
invariant** or where a future implementation could diverge incompatibly. Missing
*invariants*, not missing features.

**G1 — No invariant captures semantic correctness of identity (the central gap).**
Every snapshot invariant is structural: uniqueness, Some/None, and no-shared-node.
None asserts that a `Live` row *means* what its `last_live` says. Reorder
satisfies all invariants while being semantically wrong.

*Needed:* an explicit invariant pair:

- I5: "same-node = positional, not semantic";
- Sem3: "identity should track meaning; not guaranteed across reorder without
  move provenance".

The design also needs a stated consumer contract that meaning is unstable across
sibling reorder. Otherwise a consumer such as outline or AI context can treat a
`Live` row's heading text as a stable handle and silently relabel it.

**G2 — `Missing` conflates "deleted" and "transiently unparseable."**
*Resolved for Markdown heading side tables (#748/#764/#767):* the constructor and
`advance` require an explicit snapshot-validity tag.

Invalid snapshots create no initial rows, create no fresh rows, clear stale
current anchors, preserve `last_live`, and do not change `consecutive_absences` or
advance `Missing→Tombstoned→Retired`. Valid snapshots retain the existing delete
ladder.

The production Markdown source-map memo now attaches the private heading
side-table memo and derives validity from parser diagnostics plus recovered
projection `Error` nodes before calling `advance`, so valid deletes and malformed
transient absences take different paths end to end.

**G3 — Retention threshold N was unspecified in the contract and hardwired in
code.**
*Resolved in code (#746):* the side table carries `retention_threshold` (`0`
means never retire), and rows track `consecutive_absences`.

A `Tombstoned` row becomes `Retired` when the threshold is positive and the
counter reaches it. Because the first valid absence is always observable as
`Missing` and the second as `Tombstoned`, thresholds `1` and `2` effectively
retire on the third valid absence.

*Remaining doc drift:* the sketch still implies N=1, while the implemented
ladder keeps first absence as `Missing`.

**G4 — `retired` entry and `garbage-collectable` were undefined and unreachable.**
*Resolved in two parts:* `garbage-collectable` is now a predicate over `Retired`
(#745), and `Retired` has an implemented `Tombstoned → Retired` threshold entry
(#746).

`collect_garbage` removes retired rows while preserving historical stable-id
reservations, so a later fresh row cannot reuse a collected entity's id.

*Remaining work:* production GC must honor the no-pinning-reference precondition.

**G5 — "Global one-to-one assignment" is stated as an invariant but implemented as
same-node reservation + local candidate-claim counting, not a global solver.** The
sketch (step 4, `docs/design/sdeg-nodeid-side-table.md:156`) promises a global
one-to-one assignment.

The code precomputes all active matches, then resolves each row using a *local*
`candidate_claim_count` (`sdeg_heading_side_table.mbt:259`). Same-node rows are
reserved up front and matched against full `current`.

Other rows match `semantic_current` (`:288`,`:363`), so same-node rows never
enter the claim graph. It is **not** order-dependent greedy, but it is also not a
maximum/global assignment.

Cases where a globally-unique assignment exists but local counting demotes to
`Ambiguous` (or the reverse) are unaddressed and untested.

*Needed:* either weaken the stated invariant to "same-node reservation +
local conflict detection" or implement + test the global property.

**G6 — Semantic-key normalization is undefined.**
Sketch/Phase 0 say "normalized heading text"; the code uses raw `obs.text`
equality. Case, trailing whitespace, inline markup (`# *A*`), and Unicode
normalization (NFC/NFD, graphemes/emoji) are all unspecified.

Two implementers can diverge on ambiguity/recovery, so the design needs an
explicit normalization contract. The repo's `moji` Unicode library is the natural
owner.

Also: "editing target" / "stable editing entity" is never defined at the model
level — the grain of identity is entirely language-defined and unbounded.

**G7 — Anchor units are enforced by convention, not type.**
`@loomcore.Range` is unit-blind; the "name the unit" rule is documentation. A
wrong-unit range, such as item-space or PM-tree, compiles.

The CRDT-anchor adapter mentioned as future work is exactly where Canopy has
historically mixed units (PR #555).

*Needed:* a unit-bearing wrapper at the entity-anchor boundary before the adapter
lands, and an invariant that anchors of different units never compare.

**G8 — No invariant bounds SDEG correctness by projection-identity stability.**
SDEG's same-node evidence is only as good as the `NodeId` layer. The identity/reuse
decision doc shows that layer is itself layered and deliberately limited:
`ReuseCursor` is structural-not-identity, and `ProjectionIdentityTracker` is
windowed and loses committed deletes.

The design says "grow out of projection identity" but never states the *boundary
invariant*: **SDEG guarantees ⊆ projection-identity guarantees.** Without it, the
five-scope list reads as SDEG promises when several are delegated.

*Needed:* state the boundary; attribute each
stability scope to its owning layer.

**G9 — The matcher contract is unstated (latent until the matcher is made
pluggable).** The design makes the matcher language-owned and pluggable (sketch
`match_entity` signature + API sketch), with the core trusting its `confidence` +
candidate ids to maintain S3/S4/I4.

The *current* impl hardcodes matching (`heading_side_table_match`) and derives
candidates only from current observations, so the hole is not yet live. The
moment the matcher is extracted per the design, a buggy/adversarial matcher could
violate core invariants by returning two `Exact`s on one node or a candidate id
that is not in `current`.

The code is *partly* defensive: it re-checks `find_heading_by_id` and demotes bad
candidates. The *required* guarantees on a matcher are still unwritten.

*Needed:* a written matcher contract +
defensive-contract tests *before* the matcher becomes pluggable. "Closed core
states, open evidence" protects the state enum from extension, not the invariants
from a bad matcher.

**G10 — `stable_id` is seeded from a session-local `NodeId` with only a social
guard against escape.** The Phase 1 risk note ("a private wrapper around `NodeId`
can become a de facto public `EntityId` if it escapes") is the only protection. A
consumer serializing a `stable_id` silently breaks on reload/peer.

*Needed:* an
invariant/guard that `stable_id` is non-serializable and absent from any public
`.mbti` (the white-box `priv` keeps it internal *today*, but nothing prevents a
later `pub` accessor).

**G11 — "Successful projection snapshot" is an unencoded precondition of
`advance`.**
*Resolved for Markdown heading side tables (#748/#764/#767):* `from_observations`
and `advance` encode the precondition with a required snapshot-validity tag.

`HeadingSnapshotInvalid` selects the "parse failed → hold" path;
`HeadingSnapshotValid` retains the successful-snapshot behavior. The production
source-map memo now supplies that tag from parser diagnostics plus recovered
projection `Error` nodes before advancing the private side-table memo.

**G12 — "Never source of truth" is structural for writes but only conventional
for reads.** `advance` cannot mutate document state (no handles) — good. But
nothing stops a *consumer* from reading the table mid-edit or treating it as
authoritative, which is the actual "becomes source of truth" failure.

*Needed:* a
consumer-facing contract (read only post-reconciliation, never feed back into the
edit path) — unenforceable from inside SDEG, so it must be a documented invariant
on consumers.

**G13 — (RESOLVED #745) The reference policy for non-live entities was undecided,
and it gated GC, undo, and selection correctness.** The design explicitly left
open "whether non-live entities may be referenced by edges, diagnostics,
selections, undo, or debug tooling."

This was the most consequential *undecided* invariant. Without it, the design
could not define `garbage-collectable` safety (G4), guarantee undo points at a
live target, or bound retention (L2/L5). It was the precondition for half the
lifecycle invariants above.

*Resolved (#745):* decided
via the resolving-vs-pinning discriminator — see *Decision: reference policy for
non-live entities* (and L5).

**G14 — `advance` assumes a well-formed prior snapshot; there is no validation
boundary.** `advance` preserves invariants for tables *it* produced, but nothing
validates an externally- or hand-constructed prior `rows` array — the white-box
tests can build invalid rows directly. This is distinct from G11 (which concerns
the *observation* input, not the prior table).

*Current boundary:* the side-table
types and constructors remain package-private (`priv`), so malformed prior rows
are possible only in same-package white-box tests. If the type ever becomes
public, add a validating constructor before exposing direct construction.

---

## Related

- [Stable Document Entity Graph](stable-document-entity-graph.md) — the design direction reviewed here
- [SDEG NodeId Side Table Sketch](sdeg-nodeid-side-table.md) — the API/algorithm sketch
- [Identity and reuse mechanisms](../decisions/2026-06-01-identity-and-reuse-mechanisms.md)
- [Range/span unit boundaries](../decisions/2026-06-13-range-span-unit-boundaries.md)
