# Incremental Position Cache for Non-Sequential Inserts

**Date:** 2026-03-31
**PR:** https://github.com/dowdiness/event-graph-walker/pull/16
**Commit:** `976c652` on `fix/incremental-position-cache`

## Problem

Non-sequential inserts (clicking to a new cursor position then typing) invalidated the position cache and forced a full O(n) rebuild via `traverse_tree` + `OrderTree.from_array`. This was unnecessary — the cache is always valid at `insert()` entry.

## Fix

Remove defensive `invalidate_cache()` + `cache_valid = false` from cursor-miss and partial-cursor-hit paths in `Document::insert`. Use existing cache for lookups, let `OrderTree.insert_at` maintain it incrementally.

## Before (origin/main, no fix)

| Benchmark | Time |
|-----------|------|
| cache - sequential append (1000 chars) | 827µs |
| cache - alternating pos (1000 chars) | 87.86ms |
| cache - jump every 10 chars (1000 chars) | 115.95ms |
| cache - single non-seq insert on 1000-char doc | 1.47ms |
| cache - single non-seq insert on 5000-char doc | 4.99ms |

## After (with fix)

| Benchmark | Time |
|-----------|------|
| cache - sequential append (1000 chars) | 1.29ms |
| cache - alternating pos (1000 chars) | 2.33ms |
| cache - jump every 10 chars (1000 chars) | 1.59ms |
| cache - single non-seq insert on 1000-char doc | 4.79µs |
| cache - single non-seq insert on 5000-char doc | 4.69µs |

## Summary

| Benchmark | Before | After | Speedup |
|-----------|--------|-------|---------|
| Alternating positions (1000) | 87.86ms | 2.33ms | **37.7x** |
| Jump every 10 chars (1000) | 115.95ms | 1.59ms | **72.9x** |
| Single non-seq (1000-char) | 1.47ms | 4.79µs | **306x** |
| Single non-seq (5000-char) | 4.99ms | 4.69µs | **1064x** |

The 5000-char result (4.69µs) being nearly identical to 1000-char (4.79µs) confirms O(log n) scaling vs the previous O(n).

Sequential append is unchanged (1.29ms ≈ baseline insert cost at 1000 chars).

## Full text benchmark suite (after fix, no regressions)

| Benchmark | Time |
|-----------|------|
| text - insert append (100 chars) | 84.29µs |
| text - insert append (1000 chars) | 1.42ms |
| text - insert prepend (100 chars) | 126.11µs |
| text - delete (100 deletes from 100-char doc) | 215.18µs |
| text - text() (100-char doc) | 12.13µs |
| text - text() (1000-char doc) | 133.66µs |
| text - len() (1000-char doc) | 0.01µs |
| text - sync export_all (100 ops) | 0.09µs |
| text - sync export_all (1000 ops) | 0.08µs |
| text - sync export_since (50-op delta, 1000-op base) | 29.11µs |
| text - sync apply (50 remote ops) | 47.36µs |
| text - sync apply (500 remote ops) | 611.60µs |
| text - bidirectional sync (2 peers, 50 ops each) | 102.49µs |
| text - checkout (midpoint of 100-op doc) | 12.21µs |
| text - checkout (midpoint of 1000-op doc) | 149.94µs |
| text - undo record_insert (100 ops, 1 group) | 1.82µs |
| text - undo record_insert (100 ops, 100 groups) | 2.44µs |
| text - undo undo() (10-op group) | 25.59µs |
| text - undo undo() (50-op group) | 403.26µs |
| text - undo undo+redo roundtrip (10-op group) | 28.05µs |
| text - undo 10 undo+redo cycles (10-op group) | 261.70µs |

## Environment

- Platform: Linux 6.6.87.2-microsoft-standard-WSL2
- MoonBit: `moon bench --release` (native target)
- All benchmarks: `moon bench --package text --release`
