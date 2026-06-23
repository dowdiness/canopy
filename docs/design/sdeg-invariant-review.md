# SDEG Invariant & Semantics Review

**Status:** Review / analysis snapshot (not a spec, not implemented behavior).
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
- `docs/plans/2026-06-18-sdeg-phase1-nodeid-side-table.md` — the active Phase 1 plan
- `docs/plans/2026-06-19-sdeg-reorder-provenance-investigation.md` — reorder conclusion
- `docs/archive/2026-06-18-sdeg-phase0-markdown-heading-spike.md` — Phase 0 results
- `docs/archive/2026-06-20-markdown-block-move-provenance-spike.md` — move provenance
- `docs/decisions/2026-06-01-identity-and-reuse-mechanisms.md` — identity layering
- `docs/decisions/2026-06-13-range-span-unit-boundaries.md` — anchor units
- `lang/markdown/proj/sdeg_heading_side_table.mbt` — **the implemented core**
- `*_wbtest.mbt` companions — the only executable invariant evidence today

**Verdict.** The design separates *facts*, *hypotheses*, *relations*, and
*lifecycle* well at the prose level — "identity is a hypothesis with evidence"
is exactly the right framing. But it has **one structural confusion** that
propagates into every other section, and **a set of invariants that are named as
goals without being stated as invariants** (so they are unenforced and, in
several cases, contradicted by the code that already exists). The strongest
output of this review is therefore the *missing* invariants, not new features.

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
identity survived." Phase 0/the reorder doc then quietly contradict this for
reorder. Stated precisely: **a surviving `NodeId` proves projection-*handle*
continuity, not semantic continuity** — the reorder diagnostic
(`lang/markdown/proj/sdeg_heading_spike_wbtest.mbt:351`) records both prior
NodeIds surviving the swap, re-attached by position. The fact (positional
`NodeId` continuity) is solid; the hypothesis (semantic continuity) is what
same-node priority silently assumes. **Every
structural invariant in the sketch can hold while this hypothesis is false** —
that is the central gap (see G1).

Secondary structural problem: the **three live documents disagree on the
lifecycle**, and the **implementation disagrees with both** in places. The main
design doc names six states and explicitly defers the transition table; the
sketch implements four (no `Missing`, no GC); Phase 1 implements five with a
retention threshold; the code implements five with the threshold hardwired to a
2-absence ladder and **no reachable `Retired` state and no GC state at all**.
A future implementer can faithfully follow any one source and be incompatible
with the others.

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
- **U:** `retired` and `garbage-collectable` have **no entry condition** anywhere
  testable; the code never produces them (G4). *Post-#745:* `garbage-collectable`
  is now a predicate (no entry condition needed); `retired`'s entry stays deferred
  (G3/#746).
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
· *Scope:* per snapshot. · *Preserved by:* seeding from a unique `NodeId` +
fresh-row filter (`side_table_has_stable_id`). · *Allowed violations:* none.
· *Failure symptoms:* two rows alias; current-node index overwrites; lost
entities. · *Existing evidence:* snapshot-invariant test "stable_id unique"
(`sdeg_heading_side_table_wbtest.mbt`); enforced in `advance`. · *Missing
evidence:* property test over random observation streams (uniqueness across many
advances), not just single snapshots.

**I2 — stable_id immutability / session-locality.**
A `stable_id` never changes for the life of an entity; it is meaningful only
within one editor session + one table.
· *Scope:* session. · *Preserved by:* `stable_id` set at birth from origin
`NodeId`, never reassigned. · *Allowed violations:* none in-session; *undefined*
across reload/peer (correctly out of scope). · *Failure symptoms:* a serialized
`stable_id` silently rebinds after reload. · *Existing evidence:* `priv` wrapper
keeps it internal (impl). · *Missing evidence:* a guard/test that `stable_id`
cannot be serialized or leak into a public `.mbti` (the Phase 1 risk note flags
this socially, not structurally) — see G10.

**I3 — same-node priority.**
If the origin `NodeId` is still present, the entity is kept on it *before* any
semantic recovery candidate is considered.
· *Scope:* per advance. · *Preserved by:*
`heading_side_table_match_with_same_node_priority` +
`current_without_ids(semantic_current)`. · *Allowed violations:* only when an
explicit move-provenance reconciler overrides it (block-move spike); never
side-table-only. · *Failure symptoms:* a present node gets stolen by a semantic
duplicate; flicker. · *Existing evidence:* test "same-node priority wins over a
duplicate retained row's semantic claim." · *Missing evidence:* none for the
positive case; the *negative* case (when same-node priority is wrong — reorder)
has no corrective invariant (see I5/G1).

**I4 — one-to-one current-anchor** (also structural).
No two `Live` rows share a `current_id`.
· *Scope:* per snapshot. · *Preserved by:* claim-count demotion to `Ambiguous` +
fresh-row exclusion. · *Allowed violations:* none. · *Failure symptoms:* two
entities both claim one node → double-counted outline/diagnostics. · *Existing
evidence:* snapshot-invariant test "no two Live rows share current_id." ·
*Missing evidence:* a test that an adversarial matcher returning two `Exact`s for
one node still cannot violate it (the impl path for same-node rows bypasses the
claim graph — G5).

**I5 — (MISSING) `NodeId` continuity is positional, not semantic.**
Same-node evidence proves *position-stable* continuity; it does **not** prove the
entity means the same thing. Should be stated as an explicit non-guarantee.
· *Scope:* always. · *Preserved by:* nothing — it is a *limit*, currently
implicit. · *Allowed violations:* this is the violated property under reorder.
· *Failure symptoms:* silent semantic misattribution (old-A row now labels
content-B), with *all* other invariants green. · *Existing evidence:* the reorder
diagnostic tests record the *fact* (NodeIds swap attachment) but assert it as
"expected limitation," not as a named invariant. · *Missing evidence:* an
invariant + test asserting "no consumer may treat a `Live` row's meaning as
stable across edits that can reorder siblings without move provenance" (G1).

### Structural invariants

> Evidence note: S1–S4 and I1/I4 are **not** individually-named tests; they are
> asserted collectively by a shared white-box predicate
> `heading_side_table_invariants_hold` exercised across scenarios
> (`sdeg_heading_side_table_wbtest.mbt:141`, called from rename/restore/reorder/
> delete cases at `:187`,`:292`,`:317`,`:340`,`:361`,`:396`–`:431`); the
> current-node index is checked by `heading_side_table_index_valid` (`:127`).
> "Existing evidence" lines below name that shared predicate, not per-invariant
> tests.

**S1 — Live ⟺ current_id = Some.** · *Scope:* snapshot. · *Preserved by:*
`row_from_match` constructs `Live` only with `Some(current_obs.id)`. · *Allowed
violations:* none. · *Failure:* a `Live` row with no node (dangling). · *Existing
evidence:* snapshot-invariant test. · *Missing:* none material.

**S2 — non-Live ⟹ current_id = None.** (`Missing`/`Tombstoned`/`Ambiguous`/
`Retired`.) · *Preserved by:* `row_from_match` sets `current_id: None` on every
non-Live arm. · *Allowed violations:* none. · *Failure:* stale anchor on a
tombstoned row. · *Existing evidence:* snapshot-invariant test. · *Missing:*
test that `Ambiguous` keeps candidates but `current_id = None` simultaneously.

**S3 — live current_id ∈ current projection.**
Every `Live` row's `current_id` refers to an observation in the *current*
snapshot. · *Preserved by:* `row_from_match` re-resolves via
`find_heading_by_id(current, id)` and downgrades to `Tombstoned` if absent. ·
*Allowed violations:* none. · *Failure:* anchor points at a vanished node. ·
*Existing evidence:* the shared invariant predicate (see note). · *Missing
evidence:* a *future generic* matcher-contract test — the current impl hardcodes
matching (`heading_side_table_match`) and derives candidates only from current
observations, defensively tombstoning absent ids
(`sdeg_heading_side_table.mbt:201`,`:326`), so the gap is latent in the *designed*
pluggable matcher (G9), not a hole in today's code.

**S4 — Ambiguous ⟹ candidates nonempty.** · *Preserved by:* `Ambiguous` arm
sets `candidates: ids` (the multi/conflicting branch). · *Allowed violations:*
none. · *Failure:* an ambiguous row with nothing to resolve to. · *Existing
evidence:* invariant test. · *Missing:* none material.

**S5 — no duplicate representation.**
A node listed as an `Ambiguous` candidate is not also emitted as a fresh `Live`
row in the same snapshot. · *Preserved by:* `fresh_rows` filter via
`side_table_mentions_current_id` (checks both `current_id` and `candidates`). ·
*Allowed violations:* none. · *Failure:* one node both spawns a new entity and is
a pending candidate → eventual double identity. · *Existing evidence:* invariant
test "candidate ids not emitted as fresh Live rows." · *Missing:* test of the
ordering dependency (fresh rows computed against already-advanced `next_rows`).

**S6 — Retired is inert.**
`Retired` rows never match and never become `Live` again. · *Preserved by:*
`row_active` filter excludes them; `advance`/`row_from_match` pass them through
with `current_id: None`. · *Allowed violations:* none. · *Failure:* a retired
entity resurrects, colliding with a fresh one. · *Existing evidence:* impl
filters; "retired-row behavior" test (sketch references it). · *Missing:* there
is **no transition INTO `Retired`** in the code, so the only tested behavior is
of a row *constructed* retired — the entry path is untested because it does not
exist (G4).

**S7 — tree relation is borrowed.**
SDEG owns no entity-to-entity tree; structure comes from projection children. ·
*Scope:* whole design. · *Preserved by:* the side table stores no parent/child
edges. · *Allowed violations:* none until a decision gate adds graph relations.
· *Failure:* SDEG accidentally becomes a parallel tree (a stated non-goal). ·
*Existing evidence:* impl has no edge storage. · *Missing:* none (absence is the
invariant); but "same/nearby section context" evidence (sketch) would *introduce*
a containment relation — currently unbuilt (G6).

**S8 — current_index is a materialized view of live rows only.**
The `NodeId → StableRowId` index contains exactly the `Live` rows (cardinality =
live-row count); a lookup returns the live row's `stable_id`. · *Scope:*
snapshot. · *Preserved by:* `heading_current_index` rebuilds it each advance from
`(HeadingLive, Some(id))` rows only (`sdeg_heading_side_table.mbt:105`). ·
*Allowed violations:* none. · *Failure symptoms:* a stale/over-full index
resolves a node to a dead entity. · *Existing evidence:*
`heading_side_table_index_valid` (`sdeg_heading_side_table_wbtest.mbt:127`). ·
*Missing evidence:* none material.

### Semantic invariants

**Sem1 — never guess; duplicates stay Ambiguous.**
Semantic recovery must be one-to-one and evidence-bearing; a non-unique semantic
match degrades to `Ambiguous`, not a guess. · *Scope:* per advance. · *Preserved
by:* `heading_side_table_match` `semantic_count` branches (`==1` Probable, `>1`
Ambiguous). · *Allowed violations:* none side-table-only. · *Failure:* a restore
attaches to the wrong duplicate. · *Existing evidence:* tests "duplicates produce
ambiguity," "restore recovers unique." · *Missing:* a test where two retained
rows + one current observation compete (retained-side ambiguity, not just
current-side).

**Sem2 — (IMPLIED) semantic keys are not unique.**
The key (level + text) may collide; the matcher must treat collision as
ambiguity, never as identity. · *Scope:* always. · *Preserved by:* Sem1. ·
*Allowed violations:* none. · *Failure:* two genuinely different headings merged.
· *Existing evidence:* duplicate-heading tests. · *Missing:* this is never
*stated* as an invariant; it is only emergent from the duplicate handling.

**Sem3 — (MISSING) identity should track meaning, not position.**
The semantic counterpart to I5. No invariant asserts that an entity's *meaning*
is preserved; only that a node binding exists. · *Failure:* reorder. · *Existing
evidence:* none (the design accepts the violation as a limitation). · *Missing:*
the entire invariant, plus a corrective mechanism (move provenance) gated behind
a future block-edit path (G1).

**Sem4 — (MISSING) normalization contract for keys.**
"normalized heading text" is specified in the sketch/Phase 0 but the impl uses
*raw* `obs.text` equality. · *Scope:* matcher. · *Preserved by:* nothing
defined. · *Failure:* `# A ` vs `# A`, `# *A*` vs `# A`, NFC vs NFD, case — two
implementers normalize differently → divergent ambiguity/recovery. · *Existing
evidence:* none (raw equality only). · *Missing:* an explicit normalization spec
(note: repo already has the `moji` Unicode library — candidate owner) (G6).

**Sem5 — (IMPLIED) every match outcome records candidate cardinality.**
Same-node birth/match, missing, ambiguous, and restore each push an evidence
record incl. `HeadingCandidateCount(_)` (`sdeg_heading_side_table.mbt:100`,`:214`,
`:236`,`:243`), making each decision explainable — the operational form of
"identity is a hypothesis with evidence." · *Scope:* per row. · *Preserved by:*
the evidence array populated on every `row_from_match` arm. · *Allowed
violations:* none intended. · *Failure symptoms:* an unexplained status change.
· *Existing evidence:* evidence fields populated on every arm. · *Missing
evidence:* an invariant test that *asserts* non-empty evidence on every row —
currently incidental, not enforced.

### Lifecycle invariants

**L1 — absence ladder.**
First absence → `Missing`; continued absence → `Tombstoned`. · *Scope:* per
advance. · *Preserved by:* `row_from_match` empty-ids arm
(`Missing|Tombstoned => Tombstoned; _ => Missing`). · *Allowed violations:*
none. · *Failure:* immediate tombstoning loses one-frame-flicker recovery. ·
*Existing evidence:* test "first absence is Missing; repeated absence becomes
Tombstoned." · *Missing:* the **threshold is hardwired to N=2 absences** in code,
while Phase 1 says "N small/test-controlled" and the sketch says first-absence →
`Tombstoned` (N=1). No epoch counter (`last_seen_epoch` is in the Phase 1 *record
sketch* but absent from the implemented `HeadingSideTableRow`). The configurable-N
invariant is untestable because the counter does not exist (G3).

**L2 — recovery retention.**
`Missing`/`Tombstoned`/`Ambiguous` rows retain `last_live` observation so a later
unique match can recover them. · *Scope:* session. · *Preserved by:* `..row`
spread keeps `last_live`. · *Allowed violations:* after `Retired`/GC (undefined).
· *Failure:* premature discard → unrecoverable restore. · *Existing evidence:*
restore test. · *Missing:* a bound — retention is "whole session," i.e.
*unbounded* (a stated risk), with no GC test (G4).
*Additional invariant (L2a):* `last_live` is updated **only** on an accepted
`Live` match (`sdeg_heading_side_table.mbt:328`) and carried unchanged through
`missing`/`tombstoned`/`ambiguous` via row spread (`:316`,`:346`,`:308`) — so the
recovery substrate never drifts while an entity is absent.

**L3 — Retired is terminal.** · *Preserved by:* S6. · *Existing evidence:* inert
behavior. · *Missing:* **entry condition** — undefined and unreachable (G4).

**L4 — garbage-collectable is a property, not a state.**
The design lists it as a lifecycle state; sketch/Phase 1 treat GC as policy. ·
*Existing evidence:* none — no representation anywhere. · *Missing:* a decision
on whether GC is a state or a predicate over `Retired` rows, and the safety
condition (depends on the open "who may reference non-live entities" question)
(G4/G13). · *Decided (#745):* predicate over `Retired`; safety precondition = no
pinning reference (see *Decision: reference policy for non-live entities*).

**L5 — (DECIDED #745) reference rules for non-live entities.**
Whether `Missing`/`Tombstoned`/`Ambiguous`/`Retired` entities may be referenced
by edges, selections, undo, diagnostics, or debug tooling was **explicitly
undecided** in the design. · *Failure:* undo points at a GC'd entity; a selection
survives a tombstone inconsistently. · *Existing evidence:* none. · *Decided
(#745):* the *kind* of reference governs, not the consumer — resolving references
(selection/diagnostics/debug) may name any non-live entity and never block GC;
only pinning references (future edges) extend retention; undo is egw-owned and
never references SDEG entities. This unblocks L4 (GC safety). See *Decision:
reference policy for non-live entities*.

### Synchronization invariants

**Y1 — side table is derived, never source of truth.**
`advance` must not mutate source text, projection nodes, source maps, CRDT state,
or undo. · *Scope:* always. · *Preserved by:* **construction** — `advance` takes
only `Array[HeadingObservation]` (value copies of ids/ranges) and returns a new
table; it holds no handle to mutate document state. · *Allowed violations:* none.
· *Failure:* metadata write masquerades as an edit; collaboration/undo desync. ·
*Existing evidence:* the function signature (type-level); invariant test "the
side table never mutates source/projection/source-map/CRDT." · *Missing:* a test
that a *downstream consumer* treating the table as authoritative is prevented —
unenforceable from inside SDEG (a documentation/contract gap, G12).

**Y2 — metadata update ≠ document edit.** · *Preserved by:* Y1 + the edit-path
ordering. · *Existing evidence:* edit-path tests run advance *after* `SyncEditor`.
· *Missing:* structural enforcement that advance is never on the edit path.

**Y3 — post-reconciliation ordering.**
advance consumes observations only after parse + projection reconciliation. ·
*Preserved by:* convention (the pipeline diagram). · *Existing evidence:*
companion edit-path test derives observations after `SyncEditor`. · *Missing:*
the **"successful projection snapshot" precondition is unencoded** — advance has
no validity flag, so a failed/partial parse can be fed in and misfire the
lifecycle (G11).

**Y4 — (DEFERRED/UNTESTABLE) reload + peer stability.**
Out of scope by design; no durable anchor, deterministic key, or persistent
store. · *Existing evidence:* none possible. · *Missing:* all of it — correctly
deferred, but means three of five named stability scopes have *zero* evidence.

**Y5 — anchors carry explicit units.**
All anchors are UTF-16 code-unit `@loomcore.Range`. · *Preserved by:* convention
(`@loomcore.Range` is unit-blind). · *Existing evidence:* the range/span decision
doc; impl uses `@loomcore.Range` consistently. · *Missing:* a unit-bearing
wrapper at the boundary, and a test/guard against mixing item-space / PM-tree
ranges — the adapter boundary for CRDT anchors is the live risk (G7).

---

## Operation Preservation Matrix

Derived from the design + the spikes + the code (not assumed). "Evidence
required" = the evidence the matcher needs to make the right call.

| Operation | May change | Must be preserved | Evidence required | Failure mode |
|---|---|---|---|---|
| **rename** (`# A`→`# A2`) | signature (level+text), source range, token spans, recorded evidence | `stable_id`, current `NodeId` (same-node), `Live`, one-to-one anchor | `HeadingSameNodeId` (NodeId survives the edit path) | if `NodeId` were freshened, rename ≡ delete+spawn → identity lost. *Holds today* (Phase 0 + edit-path rename test). |
| **reorder** (`# A\n# B`→`# B\n# A`) | ordinal/position; which `ProjNode` each `NodeId` attaches to | (today) *nothing semantic* — explicitly "position-stable, not semantic-stable" | would need explicit **move provenance** (`IdentityTransform::Move`); side-table-only has none | **silent semantic misattribution** — all structural invariants green, meaning wrong (I5/Sem3). Corrected only by the future block-move path. |
| **duplicate** (`# A\n# A`) | confidence → `Ambiguous`; candidate set | distinct `stable_id` per distinct `NodeId` while both present; one-to-one (I4) | `HeadingSameSemanticKey` collision + `CandidateCount>1` | guessing → two rows on one node, or restore to wrong twin. *Avoided* by staying `Ambiguous` (duplicate test). Spurious collision if normalization is loose (Sem4). |
| **delete** (`# A` removed) | status `Live→Missing→Tombstoned`; `current_id→None` | `stable_id`; `last_live` (recovery substrate) | `CandidateCount(0)` | **`Missing` conflates delete with malformed absence** (G2); committed delete also drops the projection baseline (Phase 0), so SDEG's retained `last_live` is the *only* recovery path. |
| **restore** (deleted heading re-typed) | a new current `NodeId` (in the tested path); status →`Live` | original `stable_id` recovered iff a *unique semantic candidate* exists while the prior node is absent (freshness not required) | `HeadingSameSemanticKey` + unique candidate | duplicate text → stays `Ambiguous` (no guess); different normalization → spawns fresh (not recovered); only works before `Retired`/GC. |
| **malformed input recovery** | transient `Missing`, then re-`Live` | `stable_id` across the bad window; ideally `NodeId` via `ProjectionIdentityTracker` | NodeId survival (delegated to loom) or semantic recovery | premature `Tombstoned` if absent > ladder; **indistinguishable from delete** (G2); SDEG inherits the tracker's limits (G8). |
| **large paste** | many fresh `NodeId`s + fresh rows; possible mass ambiguity | rows whose `NodeId`s survive (untouched headings) | same-node for survivors; fresh for pasted | region-replacing paste freshens `NodeId`s → looks like delete-all+spawn-all; pasted duplicate text mis-resolves; **matching is O(rows×obs)** (nested filters) — scaling not stated as an invariant. |
| **format-like rewrite** (whitespace/formatter) | source ranges, token spans (shift) | `stable_id`, `NodeId`, `Live`, signature (text unchanged) | same-node + same-key + overlapping-range | low risk; if formatter alters text normalization, key changes but same-node priority still preserves identity. *Holds today* (Phase 0). |
| **projection regeneration** | full observation set + current-node index rebuilt | rows across regeneration | whatever `NodeId`s/keys survive regeneration | wholesale `NodeId` refresh (non-incremental rebuild) → mass semantic recovery; uniques recovered, duplicates → `Ambiguous`. **Bounded entirely by projection-identity stability** (G8). |
| **reparse** (single) | token spans, ranges | `NodeId` via incremental reparse + tracker | same-node | parser reuse (`ReuseCursor`) is *structural, not identity* (identity/reuse decision) — reparse-stability is **not** a parser guarantee, only a projection-tracker one layered above (G8). "Stable across a single reparse" is the minimal named scope. |

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
- *Retention:* whole session (unbounded).
- *Open:* **cannot distinguish "deleted" from "malformed-transient"** (G2);
  threshold to `Tombstoned` hardwired (G3); does **not exist** in the sketch
  (sketch jumps straight to `Tombstoned`).

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
- *Exit:* → `Live` (unique recovery); stays `Tombstoned` while absent.
- *Allowed references:* `current_id = None`; retains `last_live`.
- *Retention:* whole session; **no GC** (a stated risk).
- *Open:* in the sketch, `Tombstoned` is the *first* absence state (no `Missing`);
  no transition to `Retired` exists in code.

**retired**
- *Entry:* **undefined / unreachable** — the design says "after retention expiry"
  / "only in tests that exercise GC"; the code has **no transition into it**.
- *Exit:* none (terminal).
- *Allowed references:* `current_id = None` (S6); per #745, resolving references
  (selection/diagnostics/debug) may name it but resolve to nothing — debug can
  still inspect its frozen `last_live` — and a pinning reference would block GC.
- *Retention:* it *is* the retention boundary, but the boundary is unspecified.
- *Open:* entry condition only (G4); the reference rule is decided (#745).

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
  reference (G4 GC-half / G13 / L4 / L5). Threshold for the `retired` *entry* still
  deferred (G3/#746).

### Derived transition table

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
| **tombstoned** | ✓ unique recovery | ✗ | (impl) multiple recovery candidates | (impl) stays absent | **(design-only, unreachable — entry pending retention threshold N, #746)** |
| **retired** | ✗ (S6) | ✗ | ✗ | ✗ | (impl) inert self |

**Conflicts surfaced by the table:**
1. `Missing` column is empty in the sketch's model (sketch has no `Missing`).
2. `ambiguous → tombstoned` is the sketch's rule; code routes `ambiguous →
   missing`. Direct contradiction.
3. `gc` is no longer a state — per the #745 decision it is a predicate over
   `retired` (column removed; see *Decision: reference policy for non-live
   entities*). `retired` remains `(design-only)`: its entry transition is unbuilt,
   pending the retention threshold (#746). Of the original six names the lifecycle
   is now **five states + one predicate**, and `retired` is the sole
   reachable-in-design but unbuilt state.
4. The `live → tombstoned` direct edge in the sketch ("Live + no match →
   Tombstoned") does not exist in code (code inserts `Missing` first).

### Decision: reference policy for non-live entities (#745)

Resolves **G13 / L5** and the garbage-collection half of **G4 / L4**. Decided
2026-06-23 by brainstorm; the principle-level statement lives in
`stable-document-entity-graph.md` (Lifecycle model), the code-grounded mechanics
here. The retention threshold N and the `retired` *entry* transition are out of
scope (G3, tracked in #746); `missing`'s delete-vs-malformed overload is out of
scope (G2, tracked in #748).

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
unconditionally now; the predicate's *form* reserves the future edge case (a
`retired` row targeted by a live edge is **not** collectable). This decision fixes
only the GC *safety precondition* — the precondition that GC safety, undo
correctness, and bounded retention (L2/L5) all require; the threshold that drives a
row *into* `retired` is deferred (G3/#746).

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
borrowed tree**. Relations 1–3 + 5 express "index + anchor + confidence"
directly; relation 4 is forced by the no-guessing ethic. Any *additional* entity-
to-entity relation (containment / section context / cross-references) is **outside
the minimal core** and is exactly what Decision Gate #3 ("graph relations beyond
the projection tree") would add — confirming the design's own gate placement. The
"same/nearby section context" evidence floated in the sketch is the first thing
that would push relation 6 (containment) into the core; it is currently unbuilt.

---

## Design Gaps

Ordered by severity. Each is a place where behavior depends on an **unstated
invariant** or where a future implementation could diverge incompatibly. Missing
*invariants*, not missing features.

**G1 — No invariant captures semantic correctness of identity (the central gap).**
Every snapshot invariant is structural (uniqueness, Some/None, no-shared-node).
None asserts that a `Live` row *means* what its `last_live` says. Reorder
satisfies all invariants while being semantically wrong. *Needed:* an explicit
invariant pair — I5 ("same-node = positional, not semantic") + Sem3 ("identity
should track meaning; not guaranteed across reorder without move provenance") —
plus a stated consumer contract that meaning is unstable across sibling reorder.
Incompatible-interpretation risk: a consumer (outline, AI context) treats a
`Live` row's heading text as a stable handle and silently relabels.

**G2 — `Missing` conflates "deleted" and "transiently unparseable."**
Both produce zero candidates → `Missing` → `Tombstoned`, on the same ladder, with
no distinguishing signal. The named "stable across malformed intermediate input"
scope cannot be honored because the table cannot tell a malformed parse from a
real deletion. *Needed:* either an edit-provenance signal ("this advance follows
a delete") or a parse-validity signal feeding `advance`, plus an invariant that
malformed-transient absence must not advance the tombstone ladder. *Evidence
note:* the wbtests cover delete/restore and edit-path cases but **not** transient
malformed absence distinct from delete (`stable-document-entity-graph.md:181`
requests the scope; no test exercises it) — so the invariant is currently
unevidenced as well as unstated.

**G3 — Retention threshold N is unspecified in the contract and hardwired in
code.** Phase 1 says "N small/test-controlled"; the sketch implies N=1; the code
hardwires a 2-absence ladder with **no epoch counter** (`last_seen_epoch` is in
the Phase 1 record sketch but not in the implemented row). The configurable-N
invariant is untestable because the state needed to test it does not exist.
*Needed:* decide whether N is a real, counted parameter; if yes, add the epoch
field and a test; if no, delete `last_seen_epoch` from the docs.

**G4 — `retired` entry and `garbage-collectable` are undefined and unreachable.**
Two of six named lifecycle states have no entry transition in code; `gc` has no
representation at all. A future implementer must invent the policy from scratch,
and the design only says "after an explicit GC policy exists." *Needed:* either
remove these from the *lifecycle state* list (and call GC a predicate/policy), or
specify entry conditions. This is blocked on G13. *Partly resolved (#745):*
`garbage-collectable` is now a predicate over `Retired` (removed from the state
list) with a fixed safety precondition (no pinning reference); the `retired`
*entry* transition remains undefined, pending the retention threshold (G3/#746).

**G5 — "Global one-to-one assignment" is stated as an invariant but implemented as
same-node reservation + local candidate-claim counting, not a global solver.** The
sketch (step 4, `docs/design/sdeg-nodeid-side-table.md:156`) promises a global
one-to-one assignment; the code precomputes all active matches, then resolves each
row using a *local* `candidate_claim_count` (`sdeg_heading_side_table.mbt:259`),
with same-node rows reserved up front and matched against full `current` while
other rows match `semantic_current` (`:288`,`:363`) — so same-node rows never
enter the claim graph at all. It is **not** order-dependent greedy, but it is also
not a maximum/global assignment. Cases where a globally-unique assignment exists
but local counting demotes to `Ambiguous` (or the reverse) are unaddressed and
untested. *Needed:* either weaken the stated invariant to "same-node reservation +
local conflict detection" or implement + test the global property.

**G6 — Semantic-key normalization is undefined.**
Sketch/Phase 0 say "normalized heading text"; the code uses raw `obs.text`
equality. Case, trailing whitespace, inline markup (`# *A*`), and Unicode
normalization (NFC/NFD, graphemes/emoji) are all unspecified. Two implementers
diverge on ambiguity/recovery. *Needed:* an explicit normalization contract (the
repo's `moji` Unicode library is the natural owner). Also: "editing target" /
"stable editing entity" is never defined at the model level — the grain of
identity is entirely language-defined and unbounded.

**G7 — Anchor units are enforced by convention, not type.**
`@loomcore.Range` is unit-blind; the "name the unit" rule is documentation. A
wrong-unit (item-space / PM-tree) range compiles. The CRDT-anchor adapter
mentioned as future work is exactly where Canopy has historically mixed units
(PR #555). *Needed:* a unit-bearing wrapper at the entity-anchor boundary before
the adapter lands, and an invariant that anchors of different units never compare.

**G8 — No invariant bounds SDEG correctness by projection-identity stability.**
SDEG's same-node evidence is only as good as the `NodeId` layer, which the
identity/reuse decision doc shows is itself layered and deliberately limited
(`ReuseCursor` is structural-not-identity; `ProjectionIdentityTracker` is
windowed and loses committed deletes). The design says "grow out of projection
identity" but never states the *boundary invariant*: **SDEG guarantees ⊆
projection-identity guarantees.** Without it, the five-scope list reads as SDEG
promises when several are delegated. *Needed:* state the boundary; attribute each
stability scope to its owning layer.

**G9 — The matcher contract is unstated (latent until the matcher is made
pluggable).** The design makes the matcher language-owned and pluggable (sketch
`match_entity` signature + API sketch), with the core trusting its `confidence` +
candidate ids to maintain S3/S4/I4. The *current* impl hardcodes matching
(`heading_side_table_match`) and derives candidates only from current
observations, so the hole is not yet live — but the moment the matcher is
extracted per the design, a buggy/adversarial matcher (two `Exact`s on one node; a
candidate id not in `current`) could violate core invariants. The code is *partly*
defensive (re-checks `find_heading_by_id`; demotes), but the *required* guarantees
on a matcher are never written. *Needed:* a written matcher contract +
defensive-contract tests *before* the matcher becomes pluggable. "Closed core
states, open evidence" protects the state enum from extension, not the invariants
from a bad matcher.

**G10 — `stable_id` is seeded from a session-local `NodeId` with only a social
guard against escape.** The Phase 1 risk note ("a private wrapper around `NodeId`
can become a de facto public `EntityId` if it escapes") is the only protection. A
consumer serializing a `stable_id` silently breaks on reload/peer. *Needed:* an
invariant/guard that `stable_id` is non-serializable and absent from any public
`.mbti` (the white-box `priv` keeps it internal *today*, but nothing prevents a
later `pub` accessor).

**G11 — "Successful projection snapshot" is an unencoded precondition of
`advance`.** The signature takes raw observations with no validity flag; nothing
stops a caller wiring `advance` into the `incr` runtime from calling it on a
failed/partial parse, misfiring the lifecycle (compounds G2). *Needed:* encode
the precondition (a validity-tagged input or a separate "parse failed → hold"
path) and an invariant that `advance` runs only on reconciled, successful
projections.

**G12 — "Never source of truth" is structural for writes but only conventional
for reads.** `advance` cannot mutate document state (no handles) — good. But
nothing stops a *consumer* from reading the table mid-edit or treating it as
authoritative, which is the actual "becomes source of truth" failure. *Needed:* a
consumer-facing contract (read only post-reconciliation, never feed back into the
edit path) — unenforceable from inside SDEG, so it must be a documented invariant
on consumers.

**G13 — (RESOLVED #745) The reference policy for non-live entities was undecided,
and it gated GC, undo, and selection correctness.** The design explicitly left
open "whether non-live entities may be referenced by edges, diagnostics,
selections, undo, or debug tooling." This was the highest-leverage *undecided*
invariant: you could not define `garbage-collectable` safety (G4) without it,
guarantee undo points at a live target, or bound retention (L2/L5) — it was the
precondition for half the lifecycle invariants above. *Resolved (#745):* decided
via the resolving-vs-pinning discriminator — see *Decision: reference policy for
non-live entities* (and L5).

**G14 — `advance` assumes a well-formed prior snapshot; there is no validation
boundary.** `advance` preserves invariants for tables *it* produced, but nothing
validates an externally- or hand-constructed prior `rows` array — the white-box
tests can build invalid rows directly (`sdeg_heading_side_table_wbtest.mbt:413`).
The moment the type is anything but strictly internal, a malformed prior table
silently breaks S1–S8. This is distinct from G11 (which concerns the *observation*
input, not the prior table). *Needed:* either keep construction strictly private
(current posture) **as a stated invariant**, or add a validating constructor.

---

## Related

- [Stable Document Entity Graph](stable-document-entity-graph.md) — the design direction reviewed here
- [SDEG NodeId Side Table Sketch](sdeg-nodeid-side-table.md) — the API/algorithm sketch
- [Identity and reuse mechanisms](../decisions/2026-06-01-identity-and-reuse-mechanisms.md)
- [Range/span unit boundaries](../decisions/2026-06-13-range-span-unit-boundaries.md)
