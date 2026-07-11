# Performance: Alga + Event-Graph-Walker Flat Array Restructuring

**Date:** 2026-03-31
**Target:** wasm-gc, `--release` mode
**PRs:** dowdiness/alga#6, dowdiness/event-graph-walker#14, #15

## Summary

Restructured CausalGraph from immutable hashmaps to flat arrays with bidirectional edge storage (parents + children index). Added alga `DirectedGraph` trait. Applied gen-counter pattern for amortized O(1) visited-set reset.

## Event-Graph-Walker Benchmarks

| Benchmark | Before | After | Speedup |
|---|---|---|---|
| walker - linear 10 ops | 3.65 µs | 0.54 µs | 6.8x |
| walker - linear 100 ops | 66.1 µs | 4.31 µs | 15.3x |
| walker - linear 1000 ops | 1.21 ms | 41.4 µs | 29.2x |
| walker - large 10K ops | 25.6 ms | 445 µs | 57.5x |
| walker - linear 100K ops | 719.5 ms | 9.19 ms | 78.3x |
| walker - concurrent 100K (5 agents) | 772.1 ms | 30.0 ms | 25.7x |
| walker - concurrent 2×50 | 63.9 µs | 5.56 µs | 12.9x |
| walker - diamond 50 | 122 µs | 7.16 µs | 20.5x |
| walker - diff advance 10 | 26.4 µs | 2.66 µs | 11.0x |
| branch - checkout 10 | 6.97 µs | 3.62 µs | 1.9x |
| branch - checkout 100 | 88.1 µs | 25.4 µs | 3.4x |
| branch - checkout 1000 | 1.59 ms | 370 µs | 4.3x |
| text - checkout 100-op | 40.8 µs | 11.8 µs | 3.5x |
| text - checkout 1000-op | 696 µs | 152 µs | 4.6x |
| version_vector - from_frontier 100 | 14.2 µs | 3.92 µs | 3.6x |
| oplog - diff_and_collect 100K | 807.7 ms | 47.4 ms | 17.0x |

## Alga Benchmarks (Graph Library)

### DFS Reachable (1000-vertex chain)

| Variant | Time | vs Original |
|---|---|---|
| Original (Map visited + Map adjacency) | 94 µs | 1.0x |
| GenCounter visited | 34 µs | 2.7x |
| + Flat adjacency via trait | 23 µs | 4.1x |
| + Mark-and-reverse (no temp array) | 12 µs | 7.8x |
| + Direct iteration (no callback) | 6.7 µs | 14x |

### Graph Expression → AdjacencyMap

| Expression | Before (O(n²) merging) | After (direct collection) | Speedup |
|---|---|---|---|
| path(100) | 487 µs | 19 µs | 26x |
| path(1000) | 62 ms | 808 µs | 77x |
| clique(50) | 1.60 ms | 76 µs | 21x |
| star(1000) | 47 ms | 371 µs | 127x |

## Overhead Decomposition (DFS chain_1000)

| Source | Factor | Fix applied |
|---|---|---|
| Map visited set (O(log n) tree) | 2.7x | FixedArray + generation counter |
| Map adjacency (O(log n) tree) | 1.5x | DenseGraph (flat Array) |
| Per-vertex temp array in dfs_fold | 1.9x | Mark-and-reverse |
| Closure call_ref in for_each_successor | 1.8x | Direct iteration (DenseGraph methods) |

## Methodology

- All measurements: `moon bench --release`, mean of 10 iterations
- Before/after on same hardware, same session
- Correctness verified: 421 tests (event-graph-walker), 106 tests (alga)
- Full experiment report: `alga/EXPERIMENT_REPORT.md`
