# Core reconcile engine deepening — one engine behind three adapters

## GitHub Issue

Canonical issue: **none yet** — created from an architecture review
(`improve-codebase-architecture`, candidate C1, reviewed by `openai-codex/gpt-5.6-sol`).
File a canonical issue and link this plan before implementation.

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

## Current State

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
- Plain/hinted LCS identity selection on unequal duplicates is **not** pinned
  (`reconcile_properties_wbtest.mbt` marks plain/hinted selection
  implementation-defined; only exact-key prefix behavior is pinned, #892).
- Benchmark `projection/reconcile_lcs_benchmark_wbtest.mbt` measures the
  positional fast path only, with no timing threshold (evidence, not a gate).

## Desired State

One private matching core in `reconcile.mbt` behind the three existing public
adapters. The core shares matrix allocation/fill, match-plan realization, and
trace emission; each mode keeps its policy-specific parts:

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
   — old `[L,B]` → new `[B,L]` via `reconcile_with_exact_key`: pin that the new
   `B` is fresh and consumes exactly 1 (the exact-key path has no counter pin
   today).
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
14. `hinted pair emits Matched(old_index=-1) then Deleted for the consumed old node`
    — a successful post-LCS hint pair emits `Matched` with `old_index=-1`
    (`reconcile.mbt` ~267–289) while `old_matched` stays -1, so the Deleted
    loop later emits `Deleted` for the same old node. Pin the current sequence;
    "matching then reporting Deleted" is a known wart — correcting it is a
    separate behavior change, not part of this extraction.

### Phase 2 — Benchmark split (`projection/reconcile_lcs_benchmark_wbtest.mbt`)

15. Record pre-extraction release baselines for all three workloads (fast path,
    forced fallback, exact-key) before any engine change.
16. Keep the positional fast-path workload (rename to make its scope explicit).
17. Add a **forced LCS fallback** workload — wide sibling list, equal length,
    with one kind mismatch mid-list (verify the setup actually reaches the DP
    table, e.g. with a control test). Add an **exact-key** workload —
    `reconcile_with_exact_key` on the N-def module shape.
    No timing thresholds are added (benchmark is BAND 2b evidence, not a gate);
    "no regression" is judged against the recorded baselines.

### Phase 3 — Engine extraction (after Phase 1 is green)

18. Extract the shared core. Today both engines already realize in the same
    order (ascending new index, recurse before outer `Matched`, deletions
    after) — share the realization + trace emission path first; share matrix
    allocation/fill only where the two fill directions genuinely coincide
    (prefix vs suffix filling differ; a configurable interface carrying
    direction, score, pairing, recursion, and tracing would be nearly as
    complex as the implementations — prefer two private match-plan producers
    plus one shared realization module).
19. Keep per-mode policy: scoring function, reconstruction orientation
    (explicit ordering, **not** a single tie switch — the `[L,B]`/`[B,L]`
    counterexample forbids the naive mirror), old-node exclusion + post-LCS
    pairing (NOT "reservation" — global pre-LCS reservation is not current
    behavior; it is a known unimplemented fix, see `reconcile_hints_wbtest`
    "STILL VIOLATED" tests), wrap/unwrap recursion.
20. Preserve: positional fast path branch, empty-hints fast path, trace order,
    fresh-id post-order allocation order, exact-key weighted scoring.
21. Route the three public adapters (`reconcile`, `reconcile_hinted`,
    `reconcile_with_exact_key`) over the shared core without signature changes.

### Phase 4 — Validation

22. `moon check` in the worktree; `moon test` for `core`, `projection`,
    `lang/{lambda,markdown,jsx,json}`.
23. `moon fmt && moon info`; `git diff *.mbti` — core `.mbti` must show **no
    diff** (no new pub symbols, no bound widening).
24. Benchmarks: all three workloads run; fast path within recorded baseline.
25. Run `./scripts/validate-pr-ready.sh --target <package-path>` per affected
    MoonBit package (repo policy), then record the ADR post-implementation
    (`docs/decisions/`) — "one engine behind three adapters", linking this
    plan and the glossary terms.

## Acceptance Criteria

- [ ] All Phase 1 characterization tests pass on current HEAD (before Phase 3).
- [ ] Phase 1 tests pass **unchanged** after Phase 3 (they are the safety net).
- [ ] Existing suites (`reconcile_hints_wbtest`, `reconcile_properties_wbtest`,
      `reconcile_trace_wbtest`, projection, all `lang/*`) pass without semantic
      edits.
- [ ] `core` public interface unchanged: `.mbti` diff empty, no bound widening.
- [ ] Positional fast path behavior and benchmark unchanged.
- [ ] Fresh-id allocation order and hint-directed trace sequence pinned
      (tests 9 and 14).
- [ ] Benchmark baselines recorded before extraction (Phase 2 step 15).
- [ ] CONTEXT.md framework terms (reconciliation / identity evidence / fresh
      identity) used in new code comments.
- [ ] ADR recorded in `docs/decisions/` after implementation.

## Validation

```bash
# In the canopy-redesign worktree
NEW_MOON_MOD=0 moon check
NEW_MOON_MOD=0 moon test --target js modules/canopy/core modules/canopy/projection \
  modules/canopy/lang/lambda modules/canopy/lang/markdown modules/canopy/lang/jsx modules/canopy/lang/json
NEW_MOON_MOD=0 moon fmt && NEW_MOON_MOD=0 moon info
git diff '*.mbti'   # must be empty for core
moon bench --release   # fast-path + forced-fallback + exact-key workloads
./scripts/validate-pr-ready.sh --target dowdiness/canopy/core   # repo gate
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
- Glossary: `CONTEXT.md` gained a `## Framework — projection editing` section
  (reconciliation / identity evidence / fresh identity) on branch
  `refactor/redesign-scratch`.
- Related: `docs/decisions/2026-06-11-library-api-boundary.md` (Tier 1,
  deprecation idiom — not needed here since the public surface is unchanged),
  `docs/decisions/2026-08-07-generic-language-spi-deepening.md` (opaque hint
  channel stays framework-owned), `docs/architecture/grove-and-structural-identity.md`.
