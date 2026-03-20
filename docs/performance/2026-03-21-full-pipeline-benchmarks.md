# Full Pipeline Benchmark Results

**Date:** 2026-03-21
**Branch:** `main` at `1a03826`
**Runner:** `moon bench --release` on WSL2 Linux 6.6.87.2
**Modules:** canopy (editor + projection), event-graph-walker, lambda parser

---

## Summary

The full keystroke pipeline is now **60fps-ready at 80 defs** (2.32ms, 15% of 16ms budget). The CRDT layer shows massive improvements over the 2026-03-18 baseline: TextDoc 1000-char append is 2400x faster (3.88s → 1.61ms), reflecting the cumulative effect of RLE phases 0-3 and Document-level caching optimizations.

---

## Projection Pipeline (end-to-end keystroke latency)

| Scenario | 2026-03-18 | Now | Speedup | % of 16ms budget |
|----------|-----------|-----|---------|-------------------|
| Incremental keystroke (20 defs) | 6.86 ms | **1.19 ms** | 5.7x | 7% |
| Incremental keystroke (80 defs) | 85.45 ms | **2.32 ms** | 37x | 15% |

### Parser (via editor benchmarks)

| Benchmark | Now |
|-----------|-----|
| Reactive full reparse medium (80 defs) | 261.65 µs |
| Imperative incremental medium (80 defs) | 235.89 µs |
| Reactive full reparse large (320 defs) | 997.67 µs |
| Imperative incremental large (320 defs) | 1.00 ms |

### Tree Refresh

| Scenario | Now |
|----------|-----|
| Unchanged (20 defs) | 5.03 µs |
| Unchanged (80 defs) | 17.16 µs |
| Unchanged (320 defs) | 74.18 µs |
| Unchanged (1000 defs) | 299.52 µs |
| 1 changed (20 defs) | 8.83 µs |
| 1 changed (80 defs) | 30.87 µs |
| 1 changed (320 defs) | 143.51 µs |
| 1 changed (1000 defs) | 561.84 µs |

---

## CRDT — TextDoc Operations

| Benchmark | 2026-03-18 | Now | Change |
|-----------|-----------|-----|--------|
| Insert append (100 chars) | 4.16 ms | **102.64 µs** | 40x faster |
| Insert append (1000 chars) | 3.88 s | **1.61 ms** | 2400x faster |
| Insert prepend (100 chars) | — | 1.29 ms | — |
| Delete (100 from 100-char doc) | 15.17 ms | **2.66 ms** | 5.7x faster |
| text() (100-char doc) | — | 20.25 µs | — |
| text() (1000-char doc) | 13.11 ms | **285.70 µs** | 46x faster |
| len() (1000-char doc) | 0.01 µs | 0.01 µs | same |

## CRDT — Sync Operations

| Benchmark | Now |
|-----------|-----|
| export_all (100 ops) | 0.13 µs |
| export_all (1000 ops) | 0.13 µs |
| export_since (50-op delta, 1000-op base) | 601.50 µs |
| apply (50 remote ops) | 119.32 µs |
| apply (500 remote ops) | 1.86 ms |
| Bidirectional sync (2 peers, 50 ops each) | 237.59 µs |

## CRDT — Undo Operations

| Benchmark | Now |
|-----------|-----|
| record_insert (100 ops, 1 group) | 2.23 µs |
| record_insert (100 ops, 100 groups) | 3.29 µs |
| undo() (10-op group) | 35.10 µs |
| undo() (50-op group) | 643.82 µs |
| undo+redo roundtrip (10-op group) | 41.59 µs |
| 10 undo+redo cycles (10-op group) | 388.31 µs |

## CRDT — OpLog

| Benchmark | Now |
|-----------|-----|
| Insert (100 ops) | 69.01 µs |
| Insert (1000 ops) | 915.17 µs |
| Insert and delete mix (100 ops) | 105.57 µs |
| apply_remote (50 ops) | 39.14 µs |
| get_op (1000 ops) | 0.21 µs |
| Sequential typing (500 chars) | 406.99 µs |
| Sequential typing (100k chars) | 335.72 ms |

## CRDT — Walker / Causal Graph

| Benchmark | Now |
|-----------|-----|
| Linear history (10 ops) | 4.50 µs |
| Linear history (100 ops) | 78.95 µs |
| Linear history (1000 ops) | 1.38 ms |
| Linear history (10k ops) | 32.31 ms |
| Linear history (100k ops) | 900.42 ms |
| Concurrent branches (2x50) | 77.46 µs |
| Concurrent branches (5x20) | 79.19 µs |
| Concurrent branches (100k ops, 5 agents) | 968.43 ms |
| Diamond pattern (50 diamonds) | 148.56 µs |

## CRDT — Branch

| Benchmark | Now |
|-----------|-----|
| Checkout (10 ops) | 7.25 µs |
| Checkout (100 ops) | 122.08 µs |
| Checkout (1000 ops) | 2.19 ms |
| Advance (10 new ops) | 38.57 µs |
| Advance (100 new ops) | 180.60 µs |
| Single advance (1 new op) | 27.38 µs |
| Realistic typing (50 chars) | 104.93 ms |
| to_text (100 chars) | 17.81 µs |
| to_text (1000 chars) | 259.29 µs |
| Concurrent merge scenario | 28.05 µs |

---

## Parser — Lambda Calculus

### Core Parse

| Benchmark | Now |
|-----------|-----|
| Full parse simple | 0.99 µs |
| Full parse lambda | 1.65 µs |
| Full parse complex | 8.27 µs |
| Tokenization | 0.36 µs |

### Incremental Parse

| Benchmark | Now |
|-----------|-----|
| Initial parse | 1.09 µs |
| Small edit | 3.95 µs |
| Multiple edits | 7.22 µs |
| Replacement | 4.55 µs |
| Typing simulation (single char) | 4.30 µs |
| Backspace simulation | 4.28 µs |

### Let-Chain Scaling

| Benchmark | Now |
|-----------|-----|
| 80 lets — initial parse | 189.69 µs |
| 80 lets — incremental single edit | 347.25 µs |
| 80 lets — full reparse | 146.89 µs |
| 320 lets — initial parse | 768.36 µs |
| 320 lets — incremental single edit | 1.53 ms |
| 320 lets — full reparse | 623.29 µs |
| 1000 terms — full reparse | 1.16 ms |
| 1000 terms — incremental single edit | 3.06 ms |

### Heavy Workloads

| Benchmark | Now |
|-----------|-----|
| Large document — initial parse | 74.77 µs |
| Wide arithmetic (100 terms) | 124.33 µs |
| Nested application (depth 50) | 95.82 µs |
| Typing session — 100 edits at end | 5.91 ms |
| Typing session — 100 edits in middle | 8.57 ms |
| Refactoring — 100 scattered replacements | 5.61 ms |

---

## 60fps Readiness

| Document Size | Keystroke Latency | % of 16ms Budget | Status |
|---------------|-------------------|-------------------|--------|
| Small (20 defs) | 1.19 ms | 7% | Ready |
| Medium (80 defs) | 2.32 ms | 15% | Ready |
| Large (320 defs) | ~5 ms (est.) | ~31% | Likely ready |
| Very large (1000 defs) | ~15 ms (est.) | ~94% | Borderline |

**Previous bottleneck (TextDoc CRDT) has been resolved.** The full pipeline — CRDT text edit, incremental parse, projection refresh, tree refresh — fits comfortably within the 16ms frame budget for typical documents.
