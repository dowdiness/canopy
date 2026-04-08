---
summary: "Incremental parser optimization lessons — measure realistically, don't delete library code for one grammar, check config before architecture"
created: 2026-03-24
status: resolved
tags: [performance, incremental-parser, loom, lessons]
related: [loom/loom/src/core/reuse_cursor.mbt, loom/examples/lambda/src/cst_parser.mbt]
---

# Incremental Parser Optimization Lessons (2026-03-24)

## Key Findings

### Block reparse is the dominant win
- 13µs for lambda, 8µs for JSON — regardless of document size
- Was already working before any optimization
- Old trivial benchmarks (`let x = 0`) couldn't show this

### Per-node reuse requires three things
1. Grammar uses `ctx.node(kind, body)` not `mark/start_at/finish_node`
2. `reuse_size_threshold` must be low enough (default 64 bytes blocks small nodes)
3. `seek_node_at` must find the node (works for same-length edits, fails for insert/delete due to offset mismatch)

### Persistent OldTokenCache
- The O(n) `collect_old_tokens` walk was ~50µs per edit
- Fixed by persisting the flat token array across edits with delta-adjusted binary search
- `OldTokenCache::apply_edit` splices damaged range, accumulates offset delta
- `old_follow_token_lazy` adjusts search target by `pending_delta` for post-damage queries

### What NOT to do
- Don't delete trailing_context_matches — it's needed for context-dependent grammars
- Don't benchmark with trivial `let x = 0` — use realistic content with all grammar features
- Don't guess rejection causes — grep for the actual filter (`reuse_size_threshold` was the blocker, not seek navigation)

## Final Numbers (realistic benchmarks)

| Scenario | Before | After | 
|----------|--------|-------|
| Lambda 40 defs tail | 337µs (1.29x) | 274µs (1.01x) |
| Lambda 160 defs tail | 1.39ms (1.03x) | 1.20ms (0.90x) |
| Lambda block edit | 13µs | 13µs |
| JSON 100-member nested | — | 8.5µs (0.04x) |
| JSON 20-member flat | — | 82µs (2.06x — known tradeoff) |

## PRs
- event-graph-walker #9: Phase 2b FugueTree Array storage (merged)
- loom #49: persistent OldTokenCache + ctx.node() + benchmarks
