# Lazy & Incremental Tree Refresh — Benchmark Results

**Date:** 2026-03-20
**Branch:** `feature/lazy-tree-refresh` (PR #42)
**Baseline:** `main` at `098d59d`
**Benchmark:** `projection/tree_refresh_benchmark.mbt`
**Runner:** `moon bench --release` on WSL2 Linux 6.6.87.2

---

## Summary

Phase 1 (lazy structural indexes) + Phase 2 (subtree skip) yield **3-4x speedup** for unchanged projections and **2-2.6x speedup** when 1 def changes, scaling with tree size.

---

## Results

### Unchanged projection (common case during rapid typing)

| Tree size | Before | After | Speedup |
|-----------|--------|-------|---------|
| 20 defs | 15.27 µs | 4.62 µs | **3.3x** |
| 80 defs | 62.43 µs | 17.75 µs | **3.5x** |
| 320 defs | 286.62 µs | 72.39 µs | **4.0x** |
| 1000 defs | 1.18 ms | 279.38 µs | **4.2x** |

### 1 def changed out of N (single-character edit)

| Tree size | Before | After | Speedup |
|-----------|--------|-------|---------|
| 20 defs | 15.55 µs | 8.28 µs | **1.9x** |
| 80 defs | 64.18 µs | 32.55 µs | **2.0x** |
| 320 defs | 298.14 µs | 131.76 µs | **2.3x** |
| 1000 defs | 1.24 ms | 469.25 µs | **2.6x** |

---

## What changed

**Before (main):** `TreeEditorState::refresh()` performs 4 O(n) passes every time:
1. `build_loaded_node_index(self.tree)` — rebuild Map from old tree
2. `refresh_node_with_reuse_impl` — walk ProjNode tree, build new tree + preorder_ids + parent_by_child + preorder_range_by_root
3. `valid_ids` → HashSet conversion
4. Stale UI pruning via HashSet intersection

**After (feature):** `refresh()` performs 1 pass with subtree skip:
1. `refresh_node_minimal` — walk ProjNode tree, use `self.loaded_nodes` directly as previous. `can_skip_subtree` skips unchanged subtrees entirely (carry over loaded_nodes). No structural indexes built. Stale pruning via O(1) `loaded_nodes.get` checks.

**Why speedup scales with tree size:** More defs = more unchanged subtrees to skip. The subtree skip avoids stamp construction, InteractiveTreeNode allocation, and UI state lookups for every node in a reused subtree.

---

## Methodology

Each benchmark alternates between two states:
- **Unchanged:** refresh with the same ProjNode (simulates deferred refresh after coalesced keystrokes)
- **1 changed:** refresh with a reconciled ProjNode where the last def's value changed from `0` to `1` (simulates single-character edit)

Tree sizes: 20, 80, 320, 1000 let-definitions. Each def is `let xN = N` with a final expression `xN`. Total nodes per tree ≈ 3 × defs (Module + def name + init value).

Run with `moon bench --release -p dowdiness/canopy/projection -f tree_refresh_benchmark.mbt`.
