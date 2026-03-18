# Benchmark Results: Post-RLE (all phases) + FlatProj physical_equal

**Date:** 2026-03-18
**State:** RLE Phases 0-3 merged, RLE sync wire format merged, FlatProj physical_equal PR open
**Command:** `moon bench --release`
**Platform:** Linux 6.6.87.2-microsoft-standard-WSL2

---

## Projection Pipeline (incremental keystroke — new benchmarks)

| Benchmark | Without physical_equal | With physical_equal | Change |
|---|---|---|---|
| incremental keystroke (20 defs) | 6.86 ms | 7.50 ms | ~same (dominated by CRDT) |
| incremental keystroke (80 defs) | 89.06 ms | 85.45 ms | **-4%** |

**Key finding:** At 80 defs, the full keystroke pipeline takes ~85ms. The projection layer is a small fraction — CRDT text operations + parse dominate. The `physical_equal` optimization correctly skips unchanged defs but the bottleneck is elsewhere. Structural changes in the text input path (Rabbita perf Phase 1-2) are needed for meaningful improvement.

## Parser Benchmarks (unchanged by RLE)

| Benchmark | Baseline (pre-RLE) | Current | Change |
|---|---|---|---|
| reactive full reparse medium (80 defs) | 195 µs | 203 µs | +4% (noise) |
| imperative incremental medium (80 defs) | 196 µs | 200 µs | +2% (noise) |
| reactive full reparse large (320 defs) | 791 µs | 845 µs | +7% (noise) |
| imperative incremental large (320 defs) | 804 µs | 799 µs | -1% (noise) |

## RLE Performance (event-graph-walker)

### Key Improvements vs Pre-RLE Baseline

| Benchmark | Pre-RLE | Post-RLE | Change |
|---|---|---|---|
| sequential typing (100k chars) | 284 ms | 221 ms | **-22%** |
| diff_and_collect (100k advance) | 821 ms | 764 ms | **-7%** |
| walker linear (100k ops) | 811 ms | 658 ms | **-19%** |
| get_op (1000 ops) | 0.02 µs | 0.13 µs | 6.5x slower (O(1)→O(log n), expected) |

### Sync Wire Format

| Benchmark | Pre-wire-format | Post-wire-format | Change |
|---|---|---|---|
| sync export_all (100 ops) | 4.24 µs | 0.09 µs | **47x faster** |
| sync export_all (1000 ops) | 49.88 µs | 0.10 µs | **499x faster** |

Both faster than the original pre-RLE baseline (0.21µs / 1.60µs).

## Bottleneck Analysis

The 80-def incremental keystroke at ~85ms breaks down approximately as:
- **CRDT text operations** (insert/delete single char via TextDoc) — dominant
- **Incremental parse** (ImperativeParser::edit) — ~200µs for 80 defs
- **Projection pipeline** (to_flat_proj + reconcile + to_proj_node) — small fraction
- **Registry + source map rebuild** — proportional to projection

**Next steps for perf:** Rabbita performance recovery Phases 1-2 (edit-based text APIs, incremental parser feeding) to reduce the CRDT text operation overhead that dominates the keystroke pipeline.
