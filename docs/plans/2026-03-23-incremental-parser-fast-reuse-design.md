# Incremental Parser: Fast Reuse via Damage-Only Validation

**Date:** 2026-03-23
**Status:** Design
**Submodule:** loom/loom

## Problem

Incremental parsing is 1.2-1.25x slower than full reparse at all scales:

| Scale | Full reparse | Incremental | Overhead |
|-------|-------------|-------------|----------|
| 80 lets | 111 µs | 132 µs | 1.19x |
| 320 lets | 486 µs | 608 µs | 1.25x |

Profiling shows the overhead comes from per-node validation in `try_reuse`: each of 320 top-level nodes runs 4 checks (damage overlap, seek in old tree, leading-token match, trailing-context match). Additionally, `collect_old_tokens` does an O(n) walk of the entire old CST to build a flat token array for trailing-context binary search.

**Target:** Incremental should be 0.3-0.7x of batch at 320+ lets.

## Key Insight

Nodes outside the edit damage zone are provably identical in content and context:

- **Source text unchanged** outside the damage zone (by definition of the edit)
- **Tokenization unchanged** outside the damage zone (lambda lexer is context-free)
- **CST stores relative sizes**, not absolute positions — reusing a node at a shifted position is valid

Therefore: leading-token and trailing-context checks are redundant for nodes outside the damage zone. The only check needed is damage overlap.

**Precondition:** This optimization requires that node production in the grammar is independent of trailing context. This holds for the lambda grammar (LetDef, expressions, etc. are self-contained). Grammars with significant indentation or automatic semicolon insertion would need trailing-context checks preserved. Consider adding a `trailing_context_required: Bool` flag on the ReuseCursor for grammar-level opt-in.

## Design

### Change 1: `reuse_cursor.mbt` — Damage-only `try_reuse`

Keep the existing `seek_node_at` mechanism (O(depth), handles arbitrary grammar call patterns including nested `ctx.node()` and `mark()/wrap_at()`). Remove the leading-token and trailing-context validation.

**New `try_reuse` algorithm:**

```
try_reuse(expected_kind, byte_offset, token_pos):
  // 1. Early exit: if grammar is in the damage zone, can't reuse
  if self.reuse_globally_disabled ||
    (byte_offset >= self.damage_start && byte_offset < self.damage_end):
    return None

  // 2. Seek matching node in old tree (existing O(depth) mechanism)
  let (old_node, node_offset) = self.seek_node_at(byte_offset, expected_kind)?

  // 3. Size threshold check (existing, small nodes not worth reusing)
  if self.reuse_size_threshold > 0 && old_node.text_len < self.reuse_size_threshold:
    return None

  // 4. Damage overlap check — preserve existing is_outside_damage semantics
  //    CRITICAL: left-adjacent (node_end == damage_start) is EXCLUDED from reuse
  //    because trailing context at the boundary may have changed.
  let node_end = node_offset + old_node.text_len
  if not(is_outside_damage(node_offset, node_end, self.damage_start, self.damage_end)):
    return None

  // 5. Reuse — no leading/trailing checks
  return Some(old_node)
```

**`is_outside_damage` is preserved as-is** (line 153-160 of current code):
```moonbit
fn is_outside_damage(node_start, node_end, damage_start, damage_end) -> Bool {
  node_end < damage_start || node_start >= damage_end
}
```
Left-adjacent nodes (`node_end == damage_start`) are correctly rejected. Right-adjacent nodes (`node_start == damage_end`) are correctly accepted.

**Post-damage reuse limitation:** For insert/delete edits (delta != 0), `seek_node_at` looks up nodes by old absolute offsets. Post-damage nodes in the old tree have offsets that don't match the grammar's new-source offsets. The current seek mechanism cannot find them after a non-zero delta. This means **post-damage reuse only works for same-length replacements**. Insert/delete edits only reuse pre-damage nodes. This is a known limitation — addressing it requires coordinate remapping in `seek_node_at`, which is deferred as a future optimization.

**Delete:**
- `OldTokenCache` struct
- `collect_old_tokens()` — the O(n) old-tree walk
- `ensure_old_tokens()` — lazy materialization
- `old_follow_token_lazy()` — binary search in flat array
- `trailing_context_matches()` — trailing context validation
- `leading_token_matches()` — leading token validation

**Update `try_reuse_repeat_group`:** This function (`reuse_cursor.mbt:441`) also uses `leading_token_matches` and `trailing_context_matches`. Apply the same damage-only check: keep seek and `is_outside_damage`, remove leading/trailing validation.

### Change 2: `cst_fold.mbt` — Remove cache-warming loop

Delete the cache-warming loop in `fold_node` that walks unvisited children (`cst_fold.mbt:70-87`):

```moonbit
// DELETE THIS BLOCK in fold_node:
for child in node.children() {
  if not(visited.contains(...)) {
    self.stats.unvisited = self.stats.unvisited + 1
    let _ = self.fold_node(child)
  }
}
```

**Why safe:** The fold cache is keyed by CST node hash. Reused nodes produce identical hashes, so cached fold results are valid. The cache is unbounded over the fold's lifetime (no eviction). Removing cache warming means fewer prewarmed entries for future folds, but this is acceptable — cache misses simply recurse normally.

**Required cleanup:** `FoldStats.unvisited` becomes meaningless. Update or remove the whitebox test at `cst_fold_wbtest.mbt:83-99` that asserts on `unvisited` counts.

### Change 3: `factories.mbt` — No new damage field needed

The existing `damage_start`/`damage_end` fields on ReuseCursor already use `edit.start`/`edit.old_end()` (old-source coordinates). The grammar's `byte_offset` comes from the new token stream. For the early-exit check (step 1), we use the same `damage_start..damage_end` range — this is conservative but correct:

- For same-length edits: old and new damage ranges are identical
- For inserts: `damage_end` (old) < `damage_end_new` — the early-exit check is slightly too narrow, but `is_outside_damage` in step 4 catches any nodes that overlap the old damage
- For deletes: `damage_end` (old) > `damage_end_new` — the early-exit is slightly too broad, which is safe (rejects more, never accepts incorrectly)

No new field is needed. The current coordinate convention is sufficient.

### No change to `token_buffer.mbt`

Lambda uses `PrefixLexer` with `incremental_relex_enabled: false`, so `TokenBuffer::update` does a full re-tokenize. The current implementation builds the new token array incrementally with push-based construction — it is already efficient for this path. No change needed. Incremental re-lexing optimization is out of scope (would require `incremental_relex_enabled: true` in the lambda grammar config).

## Correctness Argument

| Scenario | Reuse decision | Why correct |
|----------|---------------|-------------|
| Node before damage | Reuse (seek + damage check) | Source, tokens, subtree all identical |
| Node left-adjacent to damage | Reject (`node_end == damage_start` → `is_outside_damage` returns false) | Trailing context may have changed |
| Node overlaps damage | Reject (damage check) | Source changed in this region |
| Node after damage (same-length edit) | Reuse (seek finds it at same offset) | Source identical, offset unchanged |
| Node after damage (insert/delete) | Not found by seek (offset mismatch) → grammar reparses | Conservative but correct |
| New node (insertion) | Grammar in damage zone → early exit | Grammar parses fresh |
| Deleted node | Old node in old-damage zone → rejected | Seek may find it but damage check rejects |

**Grammar independence precondition:** Node production in the lambda grammar does not depend on trailing context. LetDef, expressions, and atoms are self-contained parsing rules. This must be verified if the optimization is applied to other grammars.

## Performance Expectations

At 320 lets, single-char **same-length replacement** (e.g., `1` → `2`):

| Component | Before | After |
|-----------|--------|-------|
| Old-token flattening | ~40-50 µs (O(n) walk) | 0 (deleted) |
| Trailing-context per node | ~160 µs (320 × O(log n)) | 0 (deleted) |
| Leading-token per node | ~30 µs (320 × O(depth)) | 0 (deleted) |
| Seek per node | ~100 µs (320 × O(depth)) | ~100 µs (unchanged) |
| Damage check per node | ~3 µs (320 × O(1)) | ~3 µs (unchanged) |
| Tokenize (full re-lex) | ~92 µs | ~92 µs (unchanged) |
| Tree build (ReuseNode) | ~41 µs | ~41 µs (unchanged) |
| CstFold cache warming | ~varies | 0 (removed) |
| 1 fresh reparse | ~10 µs | ~10 µs |
| **Total** | **~608 µs** | **~250-300 µs** |

**Expected ratio (same-length edit):** 0.5-0.6x of batch (486 µs). Meets target.

**Insert/delete edits:** Post-damage nodes are not reused (seek can't find them). Only pre-damage nodes are reused. For an edit in let #160 of 320: ~160 nodes reused, ~160 reparsed. Expected ~0.7-0.8x of batch. Still faster than current 1.25x.

**Further optimization potential:** Adding coordinate remapping to `seek_node_at` would enable post-damage reuse for insert/delete edits, bringing them to parity with same-length performance.

## Files Affected

Changes in `loom/loom/src/core/`:
- `reuse_cursor.mbt` — Simplify try_reuse and try_reuse_repeat_group, delete OldTokenCache + 6 functions
- `cst_fold.mbt` — Remove cache-warming loop, update FoldStats

Changes in `loom/loom/src/`:
- `factories.mbt` — No new field, but verify damage range passing is correct

Test files requiring updates:
- `loom/loom/src/core/cst_fold_wbtest.mbt` — Update/remove warm-cache test (lines 83-99)
- `loom/loom/src/core/parser_wbtest.mbt` — May need updates if tests assert on leading/trailing check behavior
- `loom/examples/lambda/src/cst_parser.mbt` — Calls `ReuseCursor::new` in whitebox helper

No changes to:
- `token_buffer.mbt` — already efficient
- `parser.mbt` / `recovery.mbt` — try_reuse signature unchanged (token_pos param becomes unused but kept for API compatibility)

## Testing

- All existing parser tests must pass (correctness preserved)
- All incremental-vs-batch differential tests must pass
- The existing adjacent-insert regression test (`imperative_parser_test.mbt:644-655`) must still pass — it relies on left-adjacent damage exclusion which is preserved
- Benchmark comparison: before vs after at 80, 320 lets
- Verify `Checkpoint`/`restore` still works correctly
- Verify `next_sibling_has_error` still works correctly

## Risks

1. **Grammar-dependent correctness:** Dropping trailing-context checks is only safe for context-independent grammars. The lambda grammar qualifies. Consider a `trailing_context_required: Bool` flag for grammar-level opt-in.

2. **Left-adjacent boundary:** The `is_outside_damage` function correctly rejects left-adjacent nodes. If this function is modified, the adjacent-insert regression test catches it. Do not change `is_outside_damage`.

3. **Post-damage reuse loss for insert/delete:** This is a known limitation accepted in this design. Performance for insert/delete edits is still better than current (eliminating old-token + leading/trailing overhead for pre-damage nodes) but not as good as same-length edits.

## Non-Goals

- Sequential cursor advancement (replacing seek_node_at) — not feasible with current grammar patterns
- Token buffer changes — already efficient; lambda uses full re-lex anyway
- Coordinate remapping for post-damage seek — future optimization
- Block-level reuse — future optimization
