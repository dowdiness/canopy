# Incremental SourceMap & Registry (2026-03-22)

## Summary

Made `registry_memo` and `source_map_memo` patch-aware: when only a few defs change, they update changed subtrees instead of rebuilding from scratch. This reduces the projection pipeline from O(all_nodes) to O(changed_subtree) per keystroke.

## Benchmark Results

Full projection pipeline (CRDT text edit + incremental parse + FlatProj + ProjNode + Registry + SourceMap), single-char edit at tail def:

### Before vs After

| Document size | Baseline (full rebuild) | Optimized (patch) | Speedup |
|---|---|---|---|
| 20 defs | 1.09ms | 1.05ms | 1.04x |
| 80 defs | 1.76ms | 1.53ms | **1.15x** (13% faster) |
| 320 defs | 7.58ms | 6.71ms | **1.13x** (11% faster) |

### Analysis

Gains are modest at these sizes because:
- **CRDT text edit dominates** — at 320 defs, FugueMax insert/delete is the biggest cost (~5ms), not the projection pipeline
- **`rebuild_ranges()` still runs O(n log n)** — the sorted ranges array is fully rebuilt after patching
- **Parser is already fast** — incremental parse + CST pointer reuse was already O(changed)

The optimization eliminates ~870µs of tree-walk overhead at 320 defs. At larger document sizes (once the CRDT stack overflow is fixed), gains would scale proportionally since registry/source_map walk costs are O(n).

Note: 500-def benchmark hits a pre-existing FugueTree stack overflow (CRDT limitation, not projection-related).

## What Changed

### Change set propagation

`to_flat_proj_incremental` now tracks which def indices failed the `physical_equal` CST pointer check via a `changed_indices~` parameter. This information flows through a `Ref[Array[Int]?]` side-channel to downstream memos.

### Registry patching

When `changed_def_indices_ref` contains specific indices:
- `unregister_subtree(old_child)` removes stale NodeId entries
- `register_node_tree(new_child)` adds new entries
- Module node updated for position changes

When `changed_def_indices_ref` is `None` (def count change, first parse, structural reorder): full rebuild as before.

### SourceMap patching

Same pattern as registry:
- `remove_subtree(old_child)` removes old ranges and token_spans
- `patch_subtree(new_child)` adds new ranges
- `rebuild_ranges()` re-sorts the position index (still O(n log n))
- `populate_token_spans` refreshes all token spans from the SyntaxNode tree (O(n) — required because CstNode interning is position-independent, so reused defs may have shifted offsets)

### Execution-order independence

Each downstream memo manages its own `prev_children_ref` snapshot, so `registry_memo` and `source_map_memo` can be evaluated in any order.

## Remaining Bottleneck

`SourceMap::rebuild_ranges()` still runs O(n log n) on every keystroke (re-sorts the full ranges array after patching). At 320 defs this is ~1000 entries. An interval tree or incremental sorted insert could eliminate this, but it's not the dominant cost yet.

## Files Changed

- `projection/flat_proj.mbt` — `changed_indices~` parameter
- `projection/source_map.mbt` — `remove_subtree`, `patch_subtree`, `rebuild_ranges` (pub), `populate_token_spans_for_indices`
- `editor/projection_memo.mbt` — patch-aware `registry_memo` and `source_map_memo`
