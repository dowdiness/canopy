# Core reconcile engine deepening — one engine behind three adapters

## GitHub Issue

Canonical issue: <https://github.com/dowdiness/canopy/issues/1196> — created
from the architecture review (candidate C1, reviewed by
`openai-codex/gpt-5.6-sol`). The issue and this plan link each other.

## Why

`modules/canopy/core/reconcile.mbt` (799 lines) hosts two sibling-matching
implementations — the hinted engine (`reconcile_children`, forward DP + end
backtracking) and the exact-key engine (`reconcile_children_exact`, suffix DP +
front reconstruction, weighted scoring) — that duplicate match ledgers,
result-realization loops, and trace emission. The public surface (three
`reconcile*` entries plus the `reconcile_node` callback on
`build_projection_memos` / `build_projection_memos_with_identity_hints`) is
stable and Tier 1; the problem is implementation-internal **locality**: matching
policy, realization, and tracing are interleaved twice, so a change to one
engine's semantics must be mirrored in the other by hand.

The two engines are not "the same algorithm with a different tie-break": they
differ in scoring (0/1 vs fingerprint-weighted), reconstruction orientation
(tail vs front), and hint machinery (exclusion + pair-count + singleton
pairing) that the exact-key path lacks. Counterexample: old `[L,B]` vs new
`[B,L]` — hinted drops the trailing `B` and matches `L→L`; a naive front mirror
would match `B→B`. See `reconcile_properties_wbtest.mbt` and the review notes
below.

## Scope

In:
- `modules/canopy/core/reconcile.mbt` (engine extraction, no public surface change)
- `modules/canopy/core/reconcile_properties_wbtest.mbt` (characterization pins, Phase 1)
- `modules/canopy/core/reconcile_trace_wbtest.mbt` (characterization pins, Phase 1)
- `modules/canopy/projection/reconcile_lcs_benchmark_wbtest.mbt` (benchmark split, Phase 2)

Out:
- **C3 — dead trace variants** (`ReconcileTraceEvent::Renamed/Freshened`,
  `StructuredChange::Renamed/Freshened`). Separate Tier 1 migration: the Ideal
  app pattern-matches them (`apps/ideal/main/view_bottom_patch.mbt`), so removal
  touches consumers. Tracked separately.
- Language-owned matchers (markdown `move_reconcile.mbt` prefix-LCS, lambda
  `projection_memo.mbt` O(n) domain-key matcher). They stay; absorbing them via
  a generic strategy callback would widen the interface.
- `build_projection_memos_with_identity_hints` / `IdentityHintConsumer` — the
  SPI-owned hint channel stays as-is.

## Pre-Extraction State

(As recorded before Phase 1–3; the phases below changed this state.)

- `modules/canopy/core/reconcile.mbt` — `reconcile` / `reconcile_hinted` /
  `reconcile_with_exact_key`; hinted engine at `reconcile_children` (DP table,
  end backtracking, tie prefers dropping old: `dp[i-1][j] >= dp[i][j-1]` →
  `i--`); exact-key engine at `reconcile_children_exact` (suffix table, front
  reconstruction, tie prefers skipping new: `suffix[oi][nj+1] == suffix[oi][nj]`
  → `nj++`; weighted `match_base_score` + fingerprint bonus).
- Positional fast path: equal-length, same-kind, hint-free sibling lists bypass
  the quadratic table entirely (`reconcile.mbt` ~106–126, ~141–165; pinned at
  `reconcile_properties_wbtest.mbt`).
- Trace order is observable and pinned: inner `Matched` before outer, `Deleted`
  after all matches (`reconcile_trace_wbtest.mbt`).
- Plain/hinted LCS identity selection on unequal duplicates was **not** pinned
  (implementation-defined; only exact-key prefix behavior was pinned, #892) —
  now pinned by the Phase 1 characterization tests (committed `f0841b29`).
- Benchmark `projection/reconcile_lcs_benchmark_wbtest.mbt` now has three
  workloads (positional fast path / forced LCS fallback / exact-key) with
  pre-extraction baselines in `docs/evidence/2026-08-08-core-reconcile-benchmark-baselines.json`;
  no timing thresholds (evidence, not a gate).

## Desired State

One private matching core in `reconcile.mbt` behind the three existing public
adapters. The core shares **match-plan realization and trace emission**;
matrix filling stays per-mode inside two private match-plan producers (prefix
fill + end backtracking vs weighted suffix fill + front reconstruction differ
materially — a shared matrix allocator would be a shallow module with little
leverage). Each mode keeps its policy-specific parts:

- **Default** — 0/1 scoring, tail-oriented reconstruction (today's hinted path
  with empty hints)
- **Hinted** — plus hint exclusion, pair counting, singleton pairing, wrap/unwrap
  recursion
- **ExactKey** — fingerprint-weighted scoring, front-oriented reconstruction

The three modes are a closed public set — the public surface offers no
hints+exact-key combination — but each mode may combine its own evidence with
positional LCS internally (see CONTEXT.md: reconciliation / identity evidence /
fresh identity). Public `.mbti` for core is unchanged — no new pub symbols, no
bound widening.

## Steps

### Phase 1 — Characterization tests (safety net, no engine change)

All tests below must pass on the current HEAD **before** any engine work. They
pin today's observable behavior through the public seam so the extraction
cannot silently change identity assignment, counter consumption, fresh-id
allocation order, or trace order. Where a test compares modes, compare all
observables: result tree, final counter value, and trace.

**A. `modules/canopy/core/reconcile_properties_wbtest.mbt` — LCS-fallback identity + counter pins**

1. `reconcile: LCS fallback on shorter duplicate list preserves suffix identity`
   — old `[L,L,L]` → new `[L,L]`: pin that old[1]/old[2] ids survive and old[0]
   is deleted (tail-oriented).
2. `reconcile: LCS fallback on longer duplicate list carries old ids onto the new suffix`
   — old `[L,L]` → new `[L,L,L]`: pin that the old ids land on `new[1]`/`new[2]`
   and `new[0]` is fresh (suffix-aligned carry, end-backtracking).
3. `reconcile: LCS fallback crossing tie drops the trailing old sibling`
   — old `[L,B]` → new `[B,L]`: pin that `B` is dropped (Deleted) and `L` keeps
   its id; new `B` is fresh. Both `L` and `B` childless so the fresh count is 1.
4. `reconcile: hinted mode with empty hints matches plain on fallback`
   — `reconcile_hinted(.., Map([]))` ≡ `reconcile` on cases 1–3, comparing tree,
   final counter, and trace (pins the shared path; empty hints bypass all hint
   machinery by design).
5. `reconcile: hinted non-empty fallback combines exclusion, LCS, and singleton pairing`
   — unequal-length fixture with non-empty hints: one ordinary LCS match, one
   excluded-and-hint-paired node, one fresh new node. Pin ids, counter, trace
   (the empty-hints test alone would not characterize the hinted engine).
6. `reconcile: fallback freshening consumes counter exactly for unmatched new nodes`
   — case 3 consumes exactly 1 (the new `B`); case 2 consumes exactly 1.
   (Subtree caveat: an unmatched sibling with descendants consumes one per
   node, post-order — covered by test 9.)
7. `reconcile: fully-matched fallback consumes no fresh ids`
   — old `[L,B,L]` → new `[L,L]`: unequal lengths force the LCS fallback; every
   new node is matched (old[0]→new[0], old[2]→new[1]), old[1] deleted, counter
   unchanged. (Equal-length same-kind lists take the positional fast path, so
   they cannot pin the fallback.)
8. `reconcile: exact-key freshening consumes counter exactly for unmatched new nodes`
   — old `[L,B]` → new `[B,L]` via `reconcile_with_exact_key`: the B↔B diagonal
   carries the fingerprint bonus (old "b" vs new "b" have equal payloads; the
   Leaf payloads differ), so exact-key matches old B → new B and **the new L is
   fresh** — exactly 1 consumed. (Plain reconcile drops the old B instead;
   see test 3. The exact-key path has no counter pin today.)
9. `reconcile: two fresh subtrees allocate ids in sibling order, post-order within`
   — two unmatched new subtrees (one with a child): assert the actual allocated
   ids — sibling order by new index, post-order inside each subtree (pins
   allocation order, not just counter deltas).

**B. `modules/canopy/core/reconcile_trace_wbtest.mbt` — fallback trace-order pins**

10. `LCS fallback emits inner Matched before outer Matched`
    — nested fallback: pin DFS emission order on a non-fast-path shape.
11. `LCS fallback emits all Deleted events after Matched events`
    — case 3 above: order pin (deletion-after-matches is already pinned on
    simple fallback shapes; this pins the crossing-tie shape).
12. `LCS fallback crossing tie emits one Inserted and one Deleted`
    — event-content pin for old `[L,B]` → new `[B,L]`.
13. `exact-key emits the same realization order as plain on the crossing tie`
    — old `[L,B]` → new `[B,L]` gives both diagonals equal weighted scores
    (same-kind base + equal fingerprint bonus), so the front reconstruction
    yields the same observable sequence as plain: one Inserted, one Matched,
    one Deleted. Pin the concrete sequence — not cross-mode equivalence in
    general.
13. `hinted pair emits Matched(old_index=-1) then Deleted for the consumed old node`
    — a successful post-LCS hint pair emits `Matched` with `old_index=-1`
    (`reconcile.mbt` ~267–289) while `old_matched` stays -1, so the Deleted
    loop later emits `Deleted` for the same old node. Pin the current sequence;
    "matching then reporting Deleted" is a known wart — correcting it is a
    separate behavior change, not part of this extraction.

### Phase 2 — Benchmark split (`projection/reconcile_lcs_benchmark_wbtest.mbt`) ✅ done

15. Pre-extraction release baselines recorded in
    `docs/evidence/2026-08-08-core-reconcile-benchmark-baselines.json`
    (fast path 219.82 µs @ 1000 defs; forced fallback 9.30 ms @ 1000 defs;
    exact-key 50.97 ms @ 1000 defs — single run, 10 iterations each;
    re-recorded after the fresh-id counter fix).
16. Positional fast-path workload renamed and kept (`bench_reconcile_fast_path`;
    bench tests "reconcile positional fast path (N defs)").
17. **Forced LCS fallback** workload added — same wide lists with an `Int`
    child spliced mid-list; control test proves the DP table is reached via an
    Inserted trace event (fast path would emit Matched for every child).
    **Exact-key** workload added — `reconcile_with_exact_key` with `kind_tag`
    as the key on the N-def shape.
    No timing thresholds are added (benchmark is BAND 2b evidence, not a gate);
    "no regression" is judged against the recorded baselines (order-of-magnitude
    check on the fast path only).

### Phase 3 — Engine extraction ✅ done (committed `594c1ef0`)

18. Extract the shared core. Today both engines already realize in the same
    order (ascending new index, recurse before outer `Matched`, deletions
    after) — share the realization + trace emission path first; matrix
    filling stays per-mode (prefix vs suffix filling differ; a configurable
    interface carrying direction, score, pairing, recursion, and tracing would
    be nearly as complex as the implementations). Concrete shape (reviewed by
    `openai-codex/gpt-5.6-sol`):
    1. private `MatchPlan { old_to_new, new_to_old }` ledger (both engines
       already produce identical ledger shapes),
    2. two deterministic private producers `plan_hinted_lcs` (exclusion and
       pair counts stay here; the `consumed` injection ledger is created by
       the realizer wrapper — consumption belongs to realization) and
       `plan_exact_lcs` (fingerprint
       maps stay in the exact adapter; both producer and matched-recursion
       callback capture them — the shared realizer must not expose them),
    3. one private **fallback realizer** taking a matched-recursion callback
       plus an optional hinted-unmatched callback; it owns ascending new-index
       order, fresh allocation, outer `Matched`/`Inserted`, and the final
       `Deleted` loop,
    4. the DP-table-free positional loop stays specialized (default/hinted
       only — the exact-key path must NOT gain a positional bypass; the
       exact-key bench is positionally identical and would silently measure
       the shortcut, so the plan keeps the shortcut default/hinted-only).
19. Keep per-mode policy: scoring function, reconstruction orientation
    (explicit ordering, **not** a single tie switch — the `[L,B]`/`[B,L]`
    counterexample forbids the naive mirror), old-node exclusion + post-LCS
    pairing (NOT "reservation" — global pre-LCS reservation is not current
    behavior; it is a known unimplemented fix, see `reconcile_hints_wbtest`
    "STILL VIOLATED" tests), wrap/unwrap recursion. The shared realizer must
    preserve the hint-pair `Matched(old_index=-1)` event followed by the
    `Deleted` for the same old node (test 14 pins this wart; emission order
    and fingerprint interner sharing for old+new maps must survive).
20. Preserve: positional fast path branch, empty-hints fast path, trace order,
    fresh-id post-order allocation order, exact-key weighted scoring.
21. Route the three public adapters (`reconcile`, `reconcile_hinted`,
    `reconcile_with_exact_key`) over the shared core without signature changes.

### Phase 4 — Validation ✅ done

22. ✅ `moon check`; tests green across core (175), projection (75), lang/*
    (649), editor + ffi (403) — 1302/1302 total.
23. ✅ `moon fmt && moon info`; `git diff *.mbti` — core `.mbti` shows **no
    diff** (no new pub symbols, no bound widening).
24. ✅ Benchmarks: all three workloads run post-extraction — no regression
    (fast path 219.8 → 203.2 µs @ 1000 defs; fallback 9.30 → 7.92 ms;
    exact-key 50.97 → 48.11 ms; recorded in the evidence JSON). Mutation
    re-probe with the Phase 1 mutations: 4 and 8 failures respectively.
25. ✅ `./scripts/validate-pr-ready.sh --target modules/canopy/core
    --target modules/canopy/projection` passed at HEAD `4b1b33a7`
    (validated-base `f55c5e33`). ADR recorded post-implementation:
    `docs/decisions/2026-08-08-core-reconcile-one-engine-behind-three-adapters.md`.

## Acceptance Criteria

- [x] All Phase 1 characterization tests pass on current HEAD (before Phase 3).
      Green run recorded at `f0841b29`: core 175/175 (js), projection 74/74 (js).
- [x] Phase 1 mutation probes: tie-break flip and Deleted-order change each
      fail a meaningful subset of the new + existing tests (11 failures across
      two probes) — the safety net is live. (Probe execution on
      `refactor/redesign-scratch`; re-probe after Phase 3 with the same two
      mutations.)
- [x] Phase 1 tests pass **unchanged** after Phase 3 (they are the safety
      net) — all 14 pass at `594c1ef0`.
- [x] Existing suites pass without semantic edits: 1302/1302 across core
      (175), projection (75), lang/* (649), editor + ffi (403).
- [x] `core` public interface unchanged: `.mbti` diff empty, no bound widening.
- [x] Positional fast path behavior unchanged; benchmarks show no observed
      increase in the recorded means (fast path 219.8 → 203.2 µs @ 1000 defs).
- [x] Fresh-id allocation order and hint-directed trace sequence pinned
      (tests 9 and 14) and passing unchanged.
- [x] Benchmark baselines recorded before extraction (Phase 2 step 15 →
      `docs/evidence/2026-08-08-core-reconcile-benchmark-baselines.json`).
- [x] CONTEXT.md framework terms (reconciliation / identity evidence / fresh
      identity) used in new code comments (final review pass adopted
      "identity-evidence-specific" for the producer wording).
- [x] ADR recorded in `docs/decisions/` after implementation
      (`2026-08-08-core-reconcile-one-engine-behind-three-adapters.md`).

## Validation

```bash
# In the canopy-redesign worktree
NEW_MOON_MOD=0 moon check
NEW_MOON_MOD=0 moon test --target js modules/canopy/core modules/canopy/projection \
  modules/canopy/lang/lambda modules/canopy/lang/markdown modules/canopy/lang/jsx modules/canopy/lang/json
NEW_MOON_MOD=0 moon fmt && NEW_MOON_MOD=0 moon info
git diff '*.mbti'   # must be empty for core
moon bench --release   # fast-path + forced-fallback + exact-key workloads
./scripts/validate-pr-ready.sh --target modules/canopy/core --target modules/canopy/projection   # repo gate
```

## Risks

- **Tie-break equivalence** — the reviewer's counterexample (old `[L,B]` vs new
  `[B,L]`) shows reconstruction orientation must be an explicit per-mode
  ordering, not a single tie switch. Phase 1 tests 3 and 12 pin this.
- **Observable side channels** — trace emission order and fresh-id post-order
  allocation are part of the observable behavior; tests 9–14 pin them.
- **Performance** — the shared core must keep the empty-hints and positional
  fast-path branches before any policy work; Phase 2 baselines watch this.
- **`.mbti` drift** — extraction must not add pub symbols or widen bounds;
  Phase 4 step 23 gates this.

## Notes

- Review input: `openai-codex/gpt-5.6-sol` review (temp agent
  `.pi/agents/sol-reviewer.md`). Corrections adopted: public inventory includes
  `build_projection_memos_with_identity_hints`; `#892` pins exact-key (not
  hinted) prefix behavior; `StructuredChange::Renamed/Freshened` are constructed
  by `to_structured_changes` and matched by apps/ideal (hence C3 is separate);
  the existing benchmark measures the positional fast path, not LCS.
- Phase 2 review (second `openai-codex/gpt-5.6-sol` pass) adopted: fresh-id
  counter must start above both parse trees' max ids (1000 collided at 1000
  defs → 5000); fallback control hardened to exact Inserted(parent, mid, 5000,
  "Int") + counter 5001; plan test-8 description corrected (exact-key freshens
  the new L, not B); Desired State no longer claims shared matrix fill;
  evidence JSON stores numeric mean/stddev with honest scope (ratios are
  aggregate observations, not phase attributions).
- Glossary: `CONTEXT.md` gained a `## Framework — projection editing` section
  (reconciliation / identity evidence / fresh identity) on branch
  `refactor/redesign-scratch`.
- Related: `docs/decisions/2026-06-11-library-api-boundary.md` (Tier 1,
  deprecation idiom — not needed here since the public surface is unchanged),
  `docs/decisions/2026-08-07-generic-language-spi-deepening.md` (opaque hint
  channel stays framework-owned), `docs/architecture/grove-and-structural-identity.md`.
