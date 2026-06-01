# BAND 2b — Canopy hot-path scaling cliffs: reproduce-or-reject (2026-06-01)

## Purpose

Evidence gate for canopy #443. The MoonDsp+Canopy vision report §7.6 claimed two
hot-path scaling cliffs in the per-keystroke projection pipeline:

1. `to_flat_proj_incremental` — an O(N) change-detection scan estimated at
   ~5 ms / ~60% of an ~8.5 ms 1000-def keystroke.
2. `core/reconcile.mbt` — LCS child matching, O(m×n) on wide sibling lists.

Per the project's microbenchmark-first rule these were **hypotheses**. This
document isolates each operation and reports the measured cost. **No
optimization code was written.** Follow-up fixes (if greenlit) stay separate.

## Method

Two isolated microbenchmark files, both `moon bench --release` (wasm-gc backend):

- `projection/flat_proj_incremental_benchmark_wbtest.mbt` — isolates
  `@lambda_proj.to_flat_proj_incremental` at 20/80/320/1000 defs across three
  scenarios.
- `projection/reconcile_lcs_benchmark_wbtest.mbt` — isolates `@core.reconcile`
  on wide Module sibling lists (the only realistic path that reaches the LCS DP
  on a wide list — see Cliff #2 scope note).

Each scenario carries a **positive-control test** that asserts it exercises the
intended code path (so timings aren't measuring a vacuous no-op). All four
controls pass: unchanged → 0 reuse-misses; tail → exactly 1; shifted → all 81;
reconcile → N+1 wide children at every benched size (21/81/321/1001).

Command: `NEW_MOON_MOD=0 moon bench --release --package dowdiness/canopy/projection`

## Staleness correction (read this first)

The 2026-04-06 "~5 ms / ~60%" figure for cliff #1 is **doubly stale** and must
not be cited as a measurement:

1. It was an **estimate by subtraction** — the analysis table header literally
   reads "Estimated cost"; the function was never benchmarked in isolation.
2. It described an O(N) scan checking **`physical_equal()` on CstNode pointers**.
   That algorithm no longer exists. `flat_proj.mbt:83-84` now compares
   `new_child.start() == old_child.start()` plus **structural**
   `cst_node() == cst_node()` equality (switched from `physical_equal` in commit
   `4875da6` / #396 when source-span CSTs dropped canonical physical identity;
   `b8b068b` was an earlier package-extraction refactor that still used
   `physical_equal`). `physical_equal` does
   not appear anywhere in `flat_proj.mbt` today.

So this gate establishes the **first** isolated measurement of the current
algorithm, not a re-validation.

## Results — Cliff #1: `to_flat_proj_incremental` (wasm-gc, release)

| Defs | unchanged (pure detection) | tail (1-line keystroke) | shifted (reuse fully blocked) |
|------|---------------------------:|------------------------:|------------------------------:|
| 20   |   6.22 µs |  14.70 µs |  17.78 µs |
| 80   |  38.53 µs |  76.94 µs |  71.47 µs |
| 320  | 417.61 µs | 604.34 µs | 345.09 µs |
| 1000 | **3.72 ms** | **4.50 ms** | **1.13 ms** |

- **unchanged** = old/new parsed from identical source: every structural
  comparison runs to completion and succeeds → pure change-*detection* cost.
- **tail** = only the last def's value changes (same width, no offset shift):
  N−1 reused, 1 rebuilt + reconciled — a realistic single-line keystroke.
- **shifted** = a leading space shifts every offset: the cheap `start()` check
  fails first (short-circuiting the structural compare), so reuse is fully
  blocked and every def is rebuilt — the worst case for change *propagation*.

### Findings (cliff #1)

1. **Reproduced — the function is a multi-millisecond cost at 1000 defs.** The
   realistic tail keystroke is **4.50 ms** and pure detection **3.72 ms**, the
   same order as the ~5 ms claim and ~44–53% of the 8.47 ms full-pipeline
   baseline. The qualitative claim "`to_flat_proj_incremental` dominates the
   1000-def keystroke" holds. (The gate's STOP-and-reprofile branch — for a
   result in the *microsecond* range — is **not** triggered.)

2. **Scaling is super-linear, not O(N).** unchanged: 80→320 = 4× defs → 10.8×
   time; 320→1000 = 3.1× defs → 8.9× time (≈O(N^1.7–2)). The stale doc's "O(N)
   scan" description is wrong for the current code. The detection cost grows
   faster than the def count — which undermines the whole point of an
   *incremental* scan at scale.

3. **The expensive path is detection (reuse-success), not rebuild.** The
   `unchanged`/`tail` cases (structural `cst_node() ==` runs to completion) are
   3–4× more expensive than `shifted` (1.13 ms), where the `start()` mismatch
   short-circuits the structural compare. So the cost lives in the structural
   CstNode equality of *successfully reused* defs.

4. **Below ~320 defs there is no cliff.** Realistic keystroke at 320 defs =
   604 µs, well within a 16 ms frame. The cliff is a >500-def concern, matching
   the 2026-04-06 "re-measure when documents exceed 500 definitions" trigger.

**Mechanism is a hypothesis, not yet proven.** The super-linear shape is
*consistent with* per-call `start()` / `cst_node()` costs that grow with a
node's position in the document (O(i) for the i-th def → O(N²) total over the
scan), plausibly tied to the source-span left-spine token walk (cf. #439). This
is **not** established by these benchmarks and must be confirmed (e.g. by
micro-timing `start()`/`cst_node()` at varying positions) before any fix is
designed. Do not edit code on the strength of this hypothesis.

## Results — Cliff #2: `@core.reconcile` LCS on wide siblings (wasm-gc, release)

| Defs (= N+1 wide children) | reconcile |
|------:|----------:|
| 20   |   7.20 µs |
| 80   |  69.80 µs |
| 320  |   1.00 ms |
| 1000 | **9.70 ms** |

### Findings (cliff #2)

1. **Reproduced and severe where reached.** Clean O(N²): 80→320 = 4× → 14×;
   320→1000 = 3.1× → 9.7×. At 1000 wide siblings the single `reconcile` call is
   **9.70 ms**. The unconditional (m+1)×(n+1) DP-table fill in
   `reconcile_children` (`core/reconcile.mbt:39-48`) is the cost; it does not
   short-circuit on identical input.

2. **CRITICAL scope note — the lambda keystroke hot path does NOT reach this.**
   `reconcile_flat_proj` routes the wide def list through `key_match`
   (hash-based, O(N), `flat_proj.mbt:134-166`) and only calls `@core.reconcile`
   per **individual init subtree** (narrow). The wide-sibling LCS is reached
   only when a parent with many direct children is reconciled *as a whole* —
   i.e. reconciling a Module node directly, or the JSON/flat-list projection
   path (arrays/objects with N elements). For the **lambda** editor this cliff
   is **already mitigated** and is not on the per-keystroke path. The
   "check existing mitigations" step (skill Step 3) is what surfaced this.

## Gate decision

- **Cliff #1 (`to_flat_proj_incremental`): REPRODUCED.** Multi-ms at 1000 defs
  (4.50 ms realistic), super-linear, dominated by structural CstNode equality on
  reused defs. Corrected vs the stale doc: it is **not** the O(N) `physical_equal`
  scan described — that algorithm is gone. Real cliff above ~500 defs.
- **Cliff #2 (LCS wide-sibling reconcile): REPRODUCED where reached (9.70 ms @
  1000), but NOT on the lambda keystroke path** — `key_match` routing already
  mitigates it there. It is a live concern for whole-node / JSON-array
  reconciliation only.

**This issue (#443) is an evidence gate and stops here. No optimization code.**
The two cliffs share only the conceptual "revision-stamp / skip-when-unchanged"
idea, not an implementation — any follow-up fixes are tracked as separate issues.

## Caveats / required follow-up before any optimization is greenlit

1. **Deployment target not yet measured.** These numbers are wasm-gc (matching
   the 2026-04-06 baseline for comparability). Canopy ships to the **web (JS)**;
   per the perf-investigation skill Step 6, a candidate fix's payoff must be
   measured on the JS backend (`moon build --target js` + Node harness) before
   it is greenlit. wasm-gc and JS can diverge.
2. **Cliff #1 mechanism unproven** (see hypothesis above) — confirm the
   per-position cost source before designing a fix.
3. These are 1000-def figures; if real-world documents stay under ~320 defs,
   neither cliff is worth optimizing (320-def keystroke = 604 µs).

## Artifacts

- `projection/flat_proj_incremental_benchmark_wbtest.mbt` (12 benches + 3 controls)
- `projection/reconcile_lcs_benchmark_wbtest.mbt` (4 benches + 1 control)

## Reproduce

```bash
NEW_MOON_MOD=0 moon bench --release --package dowdiness/canopy/projection
NEW_MOON_MOD=0 moon test --package dowdiness/canopy/projection -f "control:*"
```
