# Pipeline Decomposition Benchmarks (2026-04-06)

## Purpose

Isolate per-component costs in the projection pipeline to ground claims from
the incremental architecture evaluation. Specifically: is `rebuild_ranges()`
expensive? Is `innermost_node_at()` expensive? Where does per-keystroke time
actually go?

## Method

Three benchmark sets, all `moon bench --release`:

1. **Isolated source_map operations** — synthetic ProjNode trees (flat, N leaf
   children), measuring `rebuild_ranges()`, `innermost_node_at()`, `from_ast()`,
   and `patch 1 leaf + rebuild_ranges()` in isolation.

2. **Pipeline decomposition** — real SyncEditor with Lambda grammar. Compare
   full pipeline (proj_node + source_map) vs proj_node-only (no source_map
   access) to measure source_map overhead by subtraction.

3. **Existing pipeline benchmarks** — incremental keystroke and whitespace
   keystroke at 20–1000 defs for overall baseline.

## Results

### Full Pipeline (keystroke = parse + project + source_map)

| Defs | Full pipeline | Whitespace (backdate) |
|------|--------------|----------------------|
| 20   | 507 µs       | 550 µs               |
| 80   | 635 µs       | 630 µs               |
| 320  | 2.06 ms      | 2.03 ms              |
| 500  | 3.66 ms      | 3.41 ms              |
| 1000 | 8.47 ms      | 8.03 ms              |

### Pipeline Without Source_Map

| Defs | Proj_node only | Full pipeline | Source_map overhead | % of total |
|------|---------------|--------------|-------------------|------------|
| 20   | 532 µs        | 507 µs       | noise             | ~0%        |
| 80   | 622 µs        | 635 µs       | ~13 µs            | ~2%        |
| 320  | 1.93 ms       | 2.06 ms      | ~130 µs           | ~6%        |
| 1000 | 6.93 ms       | 8.47 ms      | ~1.54 ms          | ~18%       |

### Isolated Source_Map Operations

| Nodes | rebuild_ranges | innermost_node_at | from_ast (full) | patch 1 + rebuild |
|-------|---------------|-------------------|-----------------|-------------------|
| 20    | 0.40 µs       | 0.18 µs           | 1.79 µs         | 0.57 µs           |
| 80    | 1.79 µs       | 0.34 µs           | 5.65 µs         | 1.75 µs           |
| 320   | 6.89 µs       | 1.04 µs           | 24.4 µs         | 6.80 µs           |
| 1000  | 25.5 µs       | 3.33 µs           | 84.7 µs         | 21.6 µs           |
| 3000  | 72.3 µs       | 10.5 µs           | 266 µs          | 69.4 µs           |

### Parser Only (for reference)

| Defs | Reactive (full reparse) | Imperative (incremental) |
|------|------------------------|-------------------------|
| 80   | 277 µs                 | 91 µs                   |
| 320  | 1.22 ms                | 362 µs                  |

## Analysis

### Where time goes at 1000 defs (~8.5 ms total)

| Component | Estimated cost | % of total |
|-----------|---------------|------------|
| `to_flat_proj_incremental` (O(N) def scan) | ~5 ms | ~60% |
| Reconcile + ProjNode conversion | ~1.5 ms | ~18% |
| Source_map (rebuild + populate_token_spans) | ~1.5 ms | ~18% |
| Parser (incremental) | ~360 µs | ~4% |
| `rebuild_ranges()` alone | ~25 µs | 0.3% |
| `innermost_node_at()` alone | ~3.3 µs | 0.04% |

### Key Findings

1. **`rebuild_ranges()` is cheap.** 25 µs at 1000 nodes. The O(N log N) sort
   has a tiny constant. Not worth optimizing.

2. **`innermost_node_at()` is cheap.** 3.3 µs at 1000 nodes. The O(N) linear
   scan is fast because N is small and the loop body is trivial.

3. **Source_map overhead is modest.** 18% at 1000 defs, 6% at 320, negligible
   at 80. Most of this is `populate_token_spans()` walking the full tree, not
   `rebuild_ranges()`.

4. **`to_flat_proj_incremental` dominates.** The O(N) scan of all definitions
   checking `physical_equal()` on CstNode pointers accounts for ~60% of
   per-keystroke cost at 1000 defs. This is change *detection*, not change
   *propagation*.

5. **Pipeline fits within frame budget at realistic sizes.** At 320 defs,
   2.06 ms total — well within a 16 ms frame. At 1000 defs, 8.5 ms is tight
   but workable with rAF batching.

### Claims Investigated and Dismissed

- `rebuild_ranges()` as a bottleneck — 0.3% of pipeline. Not a problem.
- `innermost_node_at()` needing binary search — 3.3 µs. Not worth the change.
- Source_map as a major cost — only at extreme scale (1000+ defs).

## Historical Comparison

### Incremental keystroke (full pipeline) over time

| Defs | 2026-03-18 | 2026-03-21 | 2026-03-22 | 2026-03-28 | 2026-04-06 |
|------|-----------|-----------|-----------|-----------|-----------|
| 20   | 6.86 ms   | 1.19 ms   | 1.05 ms   | ~715 µs   | **507 µs** |
| 80   | 85.45 ms  | 2.32 ms   | 1.53 ms   | ~941 µs   | **635 µs** |
| 320  | —         | —         | 6.71 ms   | ~3.2 ms   | **2.06 ms** |
| 500  | —         | —         | overflow  | ~5.0 ms   | **3.66 ms** |
| 1000 | —         | —         | overflow  | ~11.0 ms  | **8.47 ms** |

Total speedup (2026-03-18 → 2026-04-06): **13.5x at 20 defs, 135x at 80 defs.**

### Parser only (incremental)

| Defs | 2026-03-21 | 2026-03-28 | 2026-04-06 |
|------|-----------|-----------|-----------|
| 80   | 236 µs    | ~103 µs   | 91 µs     |
| 320  | 1.00 ms   | ~401 µs   | 362 µs    |

### What caused each improvement

**2026-03-18 → 2026-03-21 (5.7x–37x):** CRDT layer rewrite. RLE phases 0-3
and Document-level caching. TextDoc 1000-char append: 3.88s → 1.61ms (2400x).
The CRDT dominated everything else.

**2026-03-21 → 2026-03-22 (~1.1x):** Incremental SourceMap/Registry patching.
Modest gains because CRDT still dominated at these sizes.

**2026-03-22 → 2026-03-28 (~1.5x–2x):** Alga flat-array restructuring
(29-78x walker speedup) and incremental position cache fix (306-1064x for
non-sequential inserts). CRDT per-character cost dropped dramatically.
500+ def benchmarks became possible (stack overflow fixed).

**2026-03-28 → 2026-04-06 (~1.3x):** Smaller gains, likely from MoonBit
compiler improvements and minor code changes. Larger documents see less
relative improvement, suggesting fixed-cost reduction in CRDT overhead.

### Bottleneck shift

The 2026-03-22 analysis noted: "CRDT text edit dominates — at 320 defs,
FugueMax insert/delete is the biggest cost (~5ms)."

This is no longer true. By 2026-04-06, CRDT cost is invisible in the profile.
The bottleneck has shifted from the CRDT layer to the projection pipeline —
specifically `to_flat_proj_incremental`'s O(N) definition scan.

This is a classic optimization pattern: fixing the biggest cost reveals the
next layer as the new bottleneck. Three weeks of CRDT optimization (2400x
for text append, 306x for non-sequential inserts) moved the wall from "barely
60fps at 80 defs" to "comfortably 60fps at 320 defs."

### Frame budget over time (% of 16 ms at 80 defs)

- 2026-03-18: 85.45 ms → **534%** (unusable)
- 2026-03-21: 2.32 ms → **15%** (60fps-ready)
- 2026-03-28: 0.94 ms → **6%** (comfortable)
- 2026-04-06: 0.64 ms → **4%** (ample headroom)

## Future Measurement Triggers

- When documents routinely exceed 500 definitions, re-measure FlatProj scan.
- When adding Markdown with large documents, measure `populate_token_spans`
  specifically (Markdown has more token span roles than Lambda).
- When adding type checking or semantic analysis, measure the new memo's cost
  relative to the pipeline baseline.
- When CRDT or parser libraries are updated, re-run this benchmark suite
  to detect regressions or further improvements.
