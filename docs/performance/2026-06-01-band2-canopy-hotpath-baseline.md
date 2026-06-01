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

## JS-target measurement + mechanism confirmation (2026-06-01 addendum)

Caveat 1 (deployment target) and caveat 2 (cliff #1 mechanism unproven) above are
now resolved. Canopy ships to the **web (JS)**; the wasm-gc numbers needed a JS
cross-check before any fix could be greenlit, and the doc's mechanism claim was a
flagged hypothesis. Both were measured on the JS backend (`moon build --target js`,
Node v24 `performance.now()` harness — see Reproduce). **Still no optimization code.**

### Cliff #1 REPRODUCES on JS — V8 does not rescue it

JS is within ~10–15% of wasm-gc at every size; the cliff is essentially identical.

| Defs | unchanged JS / wasm | tail JS / wasm | shifted JS / wasm |
|------|--------------------:|---------------:|------------------:|
| 20   |    6.11 / 6.22 µs   |  14.1 / 14.7 µs |  15.9 / 17.8 µs   |
| 80   |   36.8 / 38.5 µs    |  64.7 / 76.9 µs |  66.5 / 71.5 µs   |
| 320  |    404 / 418 µs     |   515 / 604 µs  |   289 / 345 µs    |
| 1000 |  **3.61 / 3.72 ms** | **3.97 / 4.50 ms** | **1.03 / 1.13 ms** |

The realistic 1000-def tail keystroke is **3.97 ms on JS**. The gate's
microsecond STOP-branch is not triggered. Cliff #1 is a real JS-target concern.

### Mechanism CORRECTED — the doc's hypothesis was wrong twice over

The hypothesis above (lines 95–101) — "per-call `start()` / `cst_node()` cost
that grows with a node's position … tied to the source-span left-spine token
walk" — is **disproven**:

1. **`start()` and `cst_node()` are O(1) field reads** (`self.offset`,
   `self.cst` — `loom/seam/syntax_node.mbt:160-164, 525-533`). They cannot be
   the source of any super-linearity. The shifted case (which short-circuits at
   the `start()` field read, skipping the structural compare) confirms this: it
   scales near-**linearly** at the top (320→1000 = 3.1× time for 3.1× defs).

2. **The cost IS the structural `CstNode ==` of reused defs** (the doc's
   *attribution* was right; its *explanation* was not). Measured with the
   realistic access pattern — sweep `a[i].cst_node() == b[i].cst_node()` over all
   N **cold, independently-parsed** pairs once each:

   | N | ns / def-compare |
   |---|-----------------:|
   | 80 | 345 |
   | 320 | 1081 |
   | 1000 | 3422 |

   The full-sweep total at N=1000 (≈3.42 ms) ≈ the entire `unchanged` scan
   (3.61 ms): the structural compare is ~95% of the scan. (A naïve probe that
   compares the *same hot pair* 200 k× reports only ~65 ns — V8 caches it; that
   number is an artifact, not the in-situ cost.)

3. **The super-linearity is cache-bound, not algorithmic.** Each def's CST
   subtree is **flat and fixed-size = 9 nodes** at every position (probe 3:
   def 0/250/500/999 all = 9; root has 1001 flat children). So each deep compare
   does **O(1) work** (~9 node visits, no short-circuit since `physical_equal`
   fails across two parses and the hashes match). Yet per-def wall-clock grows
   ~linearly with N (345→3422 ns). The driver is **memory locality**:
   `a` and `b` come from two independent parses, so each compare chases pointers
   into two scattered heap regions whose combined working set outgrows cache as
   N rises → cache-miss rate per compare grows ~linearly → **O(N²) wall-clock
   from O(N) work**. Both GC'd backends (V8, wasm-gc) show it for the same
   pointer-chasing reason. (`children()` materialization is genuinely O(N):
   4.1 / 16.7 / 54.4 µs at 80/320/1000 — a real but minor ~1.5% slice.)

### Implication for any future fix (design NOT started)

`physical_equal` already collapses this exact compare to O(1) **during the
initial interned parse** (ADR `2026-03-14-physical-equal-interner.md`); it fails
on the incremental keystroke path only because new and old trees come from two
separate full parses that don't share interned identity. Two architecture-aligned
levers therefore exist, both targeting the confirmed cost (not the disproven one):

- **Extend cross-parse interning / subtree reuse** so unchanged def subtrees keep
  one identity across keystrokes → `physical_equal` fires → O(1)/def. Aligned
  with the existing `ReuseCursor` machinery; no correctness trade.
- **Compare cached `hash` only**, skipping the deep walk. O(1) field read per def,
  but the `CstNode::Eq` ADR (`cst_node.mbt:309-313`) *deliberately* does NOT
  trust hash alone (collision-safety). Trusting it trades that guarantee — a
  judgment call, not a free win.

A "skip-when-unchanged / revision-stamp" optimization is therefore **viable and
high-payoff** (it removes the cache-miss pointer chase that is ~95% of the cost),
but the deep-compare-avoidance must be designed against the collision-safety
invariant. **This remains an evidence gate; any such fix is a separate, greenlit
issue.**

## Artifacts

- `projection/flat_proj_incremental_benchmark_wbtest.mbt` (12 benches + 3 controls)
- `projection/reconcile_lcs_benchmark_wbtest.mbt` (4 benches + 1 control)
- JS-target harness: a throwaway `cmd/jsbench` main package (deleted after this
  measurement). Full source in the Reproduce section below — recreate to re-run.

## Reproduce

wasm-gc baseline + controls:

```bash
NEW_MOON_MOD=0 moon bench --release --package dowdiness/canopy/projection
NEW_MOON_MOD=0 moon test --package dowdiness/canopy/projection -f "control:*"
```

JS-target measurement (recreate the throwaway harness, then run on Node):

```bash
mkdir -p cmd/jsbench
cat > cmd/jsbench/moon.pkg <<'PKG'
import {
  "dowdiness/canopy/lang/lambda/proj" @lambda_proj,
  "dowdiness/lambda" @parser,
  "dowdiness/seam",
}

options(
  "is-main": true,
)
PKG
# cmd/jsbench/main.mbt — full source below, then:
NEW_MOON_MOD=0 moon run --target js --release ./cmd/jsbench
rm -rf cmd/jsbench   # throwaway; do not commit
```

<details><summary><code>cmd/jsbench/main.mbt</code> (JS evidence harness — full scan + 3 mechanism probes)</summary>

```moonbit
/// performance.now() — milliseconds, monotonic, sub-µs resolution. Node global.
extern "js" fn js_now_ms() -> Double =
  #| function() { return performance.now(); }

/// Verbatim copy of projection/tree_refresh_benchmark_wbtest.mbt's source
/// generator (a wbtest fn, not public) so the JS scenario is byte-identical.
fn bench_source(let_count : Int, tail_literal : String) -> String {
  let segments : Array[String] = []
  for i = 0; i < let_count - 1; i = i + 1 {
    segments.push("let x\{i} = \{i}")
  }
  segments.push("let x\{let_count - 1} = \{tail_literal}")
  segments.push("x\{let_count - 1}")
  segments.join("\n")
}

fn parse_syntax(text : String) -> @seam.SyntaxNode raise {
  let (cst, _) = @parser.parse_cst(text) catch { _ => fail("parse failed") }
  @seam.SyntaxNode::from_cst(cst)
}

/// Setup OUTSIDE the timed loop, time only to_flat_proj_incremental. Fresh
/// Ref(1000) per call, matching bench_fp_incr.
fn run_scenario(
  name : String, defs : Int, old_src : String, new_src : String, iters : Int,
) -> Unit raise {
  let old_root = parse_syntax(old_src)
  let old_fp = @lambda_proj.to_flat_proj(old_root, Ref(0))
  let new_root = parse_syntax(new_src)
  let mut sink = 0
  for _ in 0..<25 {
    let r = @lambda_proj.to_flat_proj_incremental(new_root, old_root, old_fp, Ref(1000))
    sink = sink + r.defs.length()
  }
  let t0 = js_now_ms()
  for _ in 0..<iters {
    let r = @lambda_proj.to_flat_proj_incremental(new_root, old_root, old_fp, Ref(1000))
    sink = sink + r.defs.length() // accumulate to defeat dead-code elimination
  }
  let us_per = (js_now_ms() - t0) * 1000.0 / iters.to_double()
  println("\{name} @ \{defs} defs: \{us_per} us/iter (sink=\{sink})")
}

/// PROBE 1 — structural CstNode== sweep over all N COLD pairs once (realistic).
/// Per-def cost growing with N ⇒ cache-driven super-linear compare.
fn probe_compare_cost() -> Unit raise {
  println("=== probe 1: structural CstNode== SWEEP (all N pairs once) ===")
  for n in [80, 320, 1000] {
    let a = parse_syntax(bench_source(n, "0")).children()
    let b = parse_syntax(bench_source(n, "0")).children()
    let reps = if n >= 1000 { 400 } else { 2000 }
    let mut acc = 0
    for _ in 0..<20 {
      for i in 0..<a.length() { if a[i].cst_node() == b[i].cst_node() { acc = acc + 1 } }
    }
    let t0 = js_now_ms()
    for _ in 0..<reps {
      for i in 0..<a.length() { if a[i].cst_node() == b[i].cst_node() { acc = acc + 1 } }
    }
    let total_us = (js_now_ms() - t0) * 1000.0 / reps.to_double()
    println("  N=\{n}: \{total_us} us/sweep (\{total_us * 1000.0 / n.to_double()} ns/def, acc=\{acc})")
  }
}

/// PROBE 2 — children() materialization scaling (the scan does it ×2/call).
fn probe_children_cost() -> Unit raise {
  println("=== probe 2: children() materialization scaling ===")
  for n in [80, 320, 1000] {
    let root = parse_syntax(bench_source(n, "0"))
    let iters = if n >= 1000 { 2000 } else { 8000 }
    let mut sink = 0
    for _ in 0..<50 { sink = sink + root.children().length() }
    let t0 = js_now_ms()
    for _ in 0..<iters { sink = sink + root.children().length() }
    println("  children() @ \{n}: \{(js_now_ms() - t0) * 1000.0 / iters.to_double()} us/call (sink=\{sink})")
  }
}

fn subtree_size(n : @seam.CstNode) -> Int {
  let mut total = 1
  for child in n.children {
    match child {
      @seam.CstElement::Node(c) => total = total + subtree_size(c)
      @seam.CstElement::Token(_) => total = total + 1
    }
  }
  total
}

/// PROBE 3 — flat (fixed subtree size ⇒ cache effect) vs nested (⇒ algorithmic O(N²)).
fn probe_subtree_shape() -> Unit raise {
  let kids = parse_syntax(bench_source(1000, "0")).children()
  println("=== probe 3: per-def CST subtree size (N=1000) ===")
  println("  #children at root = \{kids.length()}")
  for pos in [0, 250, 500, 999] {
    println("  def \{pos}: subtree_size = \{subtree_size(kids[pos].cst_node())}")
  }
}

fn main {
  try {
    probe_subtree_shape()
    probe_compare_cost()
    probe_children_cost()
    println("=== cliff #1 to_flat_proj_incremental — JS backend (Node) ===")
    let sizes = [(20, 5000), (80, 2000), (320, 500), (1000, 150)]
    for sz in sizes { let (n, it) = sz; run_scenario("unchanged", n, bench_source(n, "0"), bench_source(n, "0"), it) }
    for sz in sizes { let (n, it) = sz; run_scenario("tail     ", n, bench_source(n, "0"), bench_source(n, "1"), it) }
    for sz in sizes { let (n, it) = sz; let base = bench_source(n, "0"); run_scenario("shifted  ", n, base, " " + base, it) }
  } catch {
    e => println("ERROR: \{e}")
  }
}
```

</details>
