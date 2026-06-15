# Identity and reuse mechanisms across the parse → projection pipeline

**Date:** 2026-06-01
**Status:** Accepted (decision record; see "Source of truth on drift" below)
**Related:** [#449](https://github.com/dowdiness/canopy/issues/449) ·
[BAND 2b hot-path baseline](../performance/2026-06-01-band2-canopy-hotpath-baseline.md) ·
loom ADR [`2026-03-14-physical-equal-interner`](../../loom/docs/decisions/2026-03-14-physical-equal-interner.md) ·
[Responsibility Map](../architecture/responsibility-map.md)

> 2026-06-14 update: #633 removed mechanism #3 from Lambda's editor-facing
> projection memo stack. This ADR remains useful historical context for the
> legacy `ModuleProjection` helper/tests, but it is no longer the current editor
> data-flow description.

## Why this record exists

The #449 investigation (the BAND 2b Cliff #1 fix) surfaced a recurring confusion:
the per-keystroke pipeline appears to have "an incremental-reuse thing," but there
are in fact **three distinct mechanisms at three different layers**, each solving a
different problem and owned by a different package. Because they all carry words
like *reuse* / *incremental* / *identity*, they read as one — which made the cliff
fix look like "just wiring up existing machinery" (a refactor) when it is not.

This record fixes the responsibility map for these three mechanisms, documents the
deliberate design tension that makes the cliff exist, and records why the cliff fix
is an **optimization with a real design tradeoff**, not a clarity refactor. Read it
before re-opening #449 as a refactor.

## The three mechanisms as of 2026-06-01

| # | Mechanism | Layer / package | Question it answers | Identity basis | Persistence |
|---|-----------|-----------------|---------------------|----------------|-------------|
| 1 | `ReuseCursor` | `loom/core` (`reuse_cursor.mbt`) | "During *this* reparse, can I splice an old CST subtree instead of re-lexing/re-parsing it?" | damage-overlap + leading/trailing token context | reconstructed **per parse** from old tree + `Edit`; only `OldTokenCache` survives (token table, *not* node identity) |
| 2 | `ProjectionIdentityTracker` / `ProjectionIdentityBaseline` | `loom/core` (`projection_identity.mbt`) | "Which semantic leaves keep their stable `NodeId` across an edit?" | **source offset + key** (prefix/suffix windows around the edit) | last-good baseline retained across malformed intermediate input |
| 3 | historical `to_module_projection_incremental` + Lambda-specific `build_lambda_projection_memos` | pre-#633: `lang/lambda/proj` + `lang/lambda/flat`; post-#633 legacy helper/tests only | "Which top-level defs are structurally unchanged, so I can reuse their `ModuleProjection` entry / `ProjNode` / source-map subtree?" | `start()` + **structural** `cst_node() ==` | prev `ModuleProjection` + prev root retained in `Ref`s inside the memo |

Loom's own `CLAUDE.md` states #1's contract explicitly: *"`ReuseCursor` … is
structural reuse, **not stable parser-owned token/subtree identity**."* That single
sentence is why #1 cannot be reused as #3: it does not expose a trustworthy "this
exact subtree is identical to before" signal.

## Historical Lambda data flow per keystroke (as of 2026-06-01)

1. `editor/sync_editor_parser.mbt` → `parser.apply_edit(edit, new_source)` — loom's
   `ImperativeParser` does an **incremental reparse**, using mechanism **#1** to
   splice reusable subtrees.
2. `parser.syntax_tree()` (an `@incr.Derived`) publishes the new `SyntaxNode` root.
3. The pre-#633 Lambda-specific projection memo read that root and compared it
   against the **previous keystroke's** root (retained in `prev_syntax_root_ref`)
   via mechanism **#3** (`to_module_projection_incremental`).
4. #3 emits `changed_indices`, which drives the two-phase registry patch, the
   source-map patch, and revision-skew fallback in the same memo file.

At that point the editor **did** use incremental reparse — yet #3 still paid a
structural `cst_node() ==` per def. The next section is why that historical
cliff was not a free refactor.

## The deliberate tension that creates the cliff

Mechanism #3 cannot use pointer identity (`physical_equal`) even though the reused
subtree came from an incremental reparse, because of a **deliberate** earlier
decision:

- The loom ADR [`2026-03-14-physical-equal-interner`](../../loom/docs/decisions/2026-03-14-physical-equal-interner.md)
  made `physical_equal` collapse structural compares to O(1) **during the initial
  interned parse** (position-independent interned `CstNode`s).
- **#396 (`4875da6`) intentionally dropped canonical physical identity** so CSTs
  could carry **source spans** — required for the scope-graph / `SourceMap` work
  (`lang/lambda/scope`, #396–#405). The code documents this in two places:
  - `module_projection.mbt`: *"Source-span CSTs no longer guarantee canonical physical
    identity across parses, so equality must use the stable structural CstNode
    contract."*
  - `projection_memo.mbt`: *"CstNode interning is position-independent, so reused
    defs may have shifted offsets that only the SyntaxNode reflects correctly."*

A def that shifted by one column (because an earlier def changed length) is
structurally identical but has different source spans → `physical_equal` fails →
#3 falls back to the deep structural compare. The BAND 2b measurement showed that
compare is **~95% of the per-keystroke scan at 1000 defs** (3.97 ms tail on JS),
super-linear from cache-miss pointer-chasing across two independently-derived
heaps. See the [BAND 2b baseline](../performance/2026-06-01-band2-canopy-hotpath-baseline.md)
for the full numbers and mechanism confirmation.

## Decision: the cliff fix is an optimization, not a refactor — and it is parked

The proposed fix (extend cross-parse subtree interning so `physical_equal` fires
on the incremental path) was evaluated as a possible clarity/architecture refactor.
It is not:

1. **It unifies none of the three mechanisms.** It would be a fourth identity
   concept (pointer identity on the projection-diff path), sitting *in front of* #3's
   structural compare, which must remain as the collision-safe fallback
   (`CstNode::Eq` deliberately distrusts hash alone — `cst_node.mbt`). Net **more**
   machinery, not less.
2. **It partly reverses #396.** Restoring position-independent interned identity for
   unchanged subtrees re-introduces a property that #396 dropped on purpose, and it
   must now *coexist* with the source-span requirement rather than replace it. That
   is a genuine design tradeoff deserving its own ADR — not cleanup.
3. **The surrounding pipeline is already well-factored.** #3 is the single
   change-determination source feeding the registry/source-map patch paths; making
   it O(1) speeds the foundation but simplifies no layer above it.

**Therefore #449 is parked** (see the baseline doc's park section). The scale
precondition is also absent: the largest *real* Canopy document is ~4 top-level
defs (lambda) / 7 elements (JSON), vs the ~500-def cliff onset. Even at scale, the
fix is a tradeoff against the source-span contract, not a free refactor.

### The one legitimate future-refactor seam

"What changed" is currently determined **twice**: once at parse time (mechanism #1's
reuse decision) and again at projection time (mechanism #3's structural compare). A
principled unification would have the parser *propagate* a trustworthy subtree-identity
signal downstream so #3 skips the compare. But #1 deliberately exposes no such signal
today, so building that bridge is substantial new design — essentially the cliff fix
in a different guise (propagate parse-time identity to the projection layer), not a
free rename. If that bridge is ever built, it supersedes both this tension and #449.

## Source of truth on drift

Code and generated `.mbti` files are authoritative. This record names specific
types/files **as of 2026-06-01** to fix the mechanism map; if a name here disagrees
with the code, the code wins and this record should be updated. The *judgment*
(three separate mechanisms; cliff fix is a tradeoff, not a refactor) is the durable
content.
