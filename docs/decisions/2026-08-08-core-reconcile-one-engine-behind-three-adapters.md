# Core reconcile — one engine behind three adapters

**Date:** 2026-08-08

**Status:** Accepted (implementation: `refactor/redesign-scratch` commits
`f0841b29`…`594c1ef0`, issue #1196, plan
`docs/plans/2026-08-08-core-reconcile-engine-deepening.md`)

**Related:**

- [Library API boundary](2026-06-11-library-api-boundary.md) (core is Tier 1;
  the public reconcile surface is unchanged by this record)
- [Generic language SPI deepening](2026-08-07-generic-language-spi-deepening.md)
  (opaque, framework-owned identity-hint channel)
- [Grove and structural identity](../../docs/architecture/grove-and-structural-identity.md)
  (Level 1 edit-aware reconciliation)

**Reader:** Maintainers designing or reviewing projection reconciliation,
sibling matching, or node-identity behavior in Canopy core.

**Decision:** Reconcile the two sibling-matching implementations in
`modules/canopy/core/reconcile.mbt` into **one private matching engine behind
the three existing public adapters** (`reconcile`, `reconcile_hinted`,
`reconcile_with_exact_key`): a private `MatchPlan` ledger produced by two
mode-specific plan producers (`plan_hinted_lcs`, `plan_exact_lcs`) and
consumed by one shared fallback realizer (`realize_fallback`). The public
interface is unchanged; the three identity-evidence modes remain a closed
public set with no hints+exact-key composition.

**Keep until:** Permanently. Supersede only if a future identity-evidence
kind (e.g. a structural CRDT layer, Grove Level 2) needs a different
reconciliation shape.

**Disposition:** If a language needs hints AND exact keys together, extend the
closed set deliberately with semantics and tests — the current exclusion and
pairing machinery has known non-composition failures (see the "STILL
VIOLATED" tests in `reconcile_hints_wbtest.mbt`).

## Context

`reconcile.mbt` hosted two sibling-matching implementations that duplicated
match ledgers, result-realization loops, and trace emission:

- **Hinted engine** (`reconcile_children`): forward DP table, end
  backtracking, tie prefers dropping old children; old-node exclusion and
  post-LCS hint pairing for structural-edit hints.
- **Exact-key engine** (`reconcile_children_exact`): weighted suffix DP
  (fingerprint bonus), front reconstruction with earliest feasible diagonal,
  no hints.

The two are **not** "one algorithm with a different tie-break": scoring
(0/1 vs fingerprint-weighted), reconstruction orientation (tail vs front),
and the hint machinery all differ. Counterexample: old `[L,B]` vs new
`[B,L]` — the hinted path drops the trailing `B` and keeps `L`; a naive
front mirror would match `B→B`. A single tie switch therefore cannot unify
them.

The public surface is Tier 1 (library-API boundary): the three `reconcile*`
entries are the interface; the friction was implementation-internal
**locality** — a change to one engine's semantics had to be mirrored in the
other by hand.

## Decision

### Public surface (unchanged)

- `reconcile` / `reconcile_hinted` / `reconcile_with_exact_key` keep their
  signatures, trait bounds, and observable behavior. `.mbti` diff is empty.
- The three identity-evidence modes stay a **closed public set**: no
  hints+exact-key combination exists in the public surface. Each mode may
  combine its own evidence with positional LCS internally.

### Internal shape

1. **`MatchPlan { old_to_new, new_to_old }`** (private) — the match ledger
   both engines already produced in identical shape.
2. **`plan_hinted_lcs`** (private producer) — exclusion of hinted old
   children from LCS, the DP, and pair counts for post-LCS pairing all live
   here. The per-keystroke empty-hints branch skips all of it.
3. **`plan_exact_lcs`** (private producer) — weighted suffix DP + front
   reconstruction. Fingerprint maps stay in the exact adapter; both the
   producer and the matched-recursion callback capture them — the shared
   realizer does not expose them.
4. **`realize_fallback`** (shared realizer) — owns ascending new-index
   order, matched-child recursion before the outer `Matched`, fresh
   allocation for unmatched new children, and the final `Deleted` loop. It
   takes a matched-recursion callback plus an optional hint-pairing
   callback.
5. **Positional fast path** stays a specialized loop, **default/hinted only**.
   The exact-key path has NO positional shortcut — its weighted DP is
   observable behavior (the exact-key benchmark is positionally identical
   and would silently measure a shortcut).

### Preserved behavior (pinned by tests, not by convention)

- Trace emission order (inner `Matched` before outer, `Deleted` last) and
  the hint-pair wart: a successful post-LCS pair emits
  `Matched(old_index=-1)` and the same old node is later reported `Deleted`
  (characterization test 13 pins this).
- Fresh-id post-order allocation order within subtrees, sibling order
  across subtrees.
- Empty-hints equivalence: `reconcile_hinted(.., Map([]))` is observably
  identical to `reconcile`.
- Global pre-LCS hint **reservation** remains deliberately unimplemented
  (known "STILL VIOLATED" tests in `reconcile_hints_wbtest.mbt`); the
  extraction did not introduce it.

## Consequences

**Benefits:**

- Matching-policy decisions concentrate: plan producers are
  identity-evidence-specific, realization is written once.
- Trace emission and fresh allocation have one implementation, so a change
  cannot silently diverge between modes (the mutation re-probe caught the
  exact-key tests through the shared realizer).
- The three public adapters remain the test surface; characterization
  tests pass unchanged through the extraction.

**Trade-offs:**

- Two producers still fill their own DP matrices (prefix vs suffix
  filling differ materially). Sharing the allocator alone would be a
  shallow module with little leverage.
- The realizer's callback shape (matched recursion + optional
  unmatched-new) is a small internal seam; it is justified by two
  adapters (hinted and exact-key) — per seam discipline, not one
  hypothetical seam.

**Risks:**

- A future "hints AND exact-key" mode would need new reservation and
  scoring semantics — deliberately out of scope until a real consumer
  exists.
- Performance: the empty-hints and positional fast-path branches must
  precede any policy work. Benchmarks recorded pre- and post-extraction
  show no regression (fast path 219.8 → 203.2 µs @ 1000 defs).

## Validation evidence

- 14 characterization tests (Phase 1) pass unchanged before and after the
  extraction; full suites 1302/1302 (core, projection, lang/*, editor, ffi).
- Mutation re-probe with the same two mutations: tie-break flip → 4
  failures; Deleted-loop duplication → 8 failures (the shared realizer
  covers both modes; the exact-key realization-order test is newly
  caught).
- Benchmarks: `docs/evidence/2026-08-08-core-reconcile-benchmark-baselines.json`
  records pre/post numbers (no timing thresholds; BAND 2b evidence).
- Core `.mbti` diff empty: no new pub symbols, no trait-bound widening.

## Rejected alternatives

### One public options-record entry (`reconcile_with_options`)

Rejected (first review pass): a policy record would expose invalid
combinations (hints+exact-key) and, under the Tier 1 deprecation rule, the
public surface would grow for at least one release cycle while the three
names already communicate the three valid modes.

### One configurable strategy interface (direction, score, pairing, tracing)

Rejected: an interface carrying all policy dimensions would be nearly as
complex as the two implementations it replaces — a shallow module with no
locality gain.

### Shared matrix allocation/fill

Rejected: prefix fill + end backtracking and weighted suffix fill + front
reconstruction differ materially; the shared surface would be a one-line
allocator.

### Positional shortcut for the exact-key path

Rejected: it would change observable identity behavior (the exact-key
prefix-identity pins, #892) and silently invalidate the exact-key
benchmark workload.

### Absorbing the language-owned matchers (markdown move LCS, lambda
domain-key)

Rejected: out of scope. Absorbing them via a generic strategy callback
would widen the interface more than it deepens the module.

## References

- [Plan: core reconcile engine deepening](../plans/2026-08-08-core-reconcile-engine-deepening.md)
- [Issue #1196](https://github.com/dowdiness/canopy/issues/1196)
- [Library API boundary](2026-06-11-library-api-boundary.md)
- [Generic language SPI deepening](2026-08-07-generic-language-spi-deepening.md)
- [Grove and structural identity](../../docs/architecture/grove-and-structural-identity.md)
- Baseline evidence: `docs/evidence/2026-08-08-core-reconcile-benchmark-baselines.json`
