# Incremental Parser: Fast Reuse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate leading-token, trailing-context, and old-token-flattening overhead from incremental parsing, making it 0.5-0.6x of batch speed at 320+ lets.

**Architecture:** Simplify `try_reuse` and `try_reuse_repeat_group` to keep only seek + damage-overlap check. Delete the O(n) `collect_old_tokens` walk and all trailing/leading validation code. Remove CstFold's cache-warming loop. All changes in `loom/loom/src/core/`.

**Tech Stack:** MoonBit, loom parser framework

**Spec:** `docs/plans/2026-03-23-incremental-parser-fast-reuse-design.md`

---

## File Structure

| File | Responsibility | Change |
|------|---------------|--------|
| `loom/loom/src/core/reuse_cursor.mbt` | ReuseCursor, try_reuse, old-token code | Simplify try_reuse/try_reuse_repeat_group, delete 6 functions + 2 structs |
| `loom/loom/src/core/cst_fold.mbt` | CstFold algebra runner | Remove cache-warming loop |
| `loom/loom/src/core/cst_fold_wbtest.mbt` | CstFold whitebox tests | Remove/update warm-cache test |
| `loom/loom/src/core/parser_wbtest.mbt` | Parser whitebox tests | Remove old_follow_token tests, update trailing-context test comments |

No new files. No changes to `factories.mbt`, `parser.mbt`, `recovery.mbt`, `token_buffer.mbt`, or grammar files.

---

### Task 1: Simplify `try_reuse` — remove leading/trailing checks

**Files:**
- Modify: `loom/loom/src/core/reuse_cursor.mbt:391-429`
- Modify: `loom/loom/src/core/parser_wbtest.mbt:1078-1091` (trailing-context regression test)
- Modify: `loom/loom/src/core/parser.mbt:527-530` (stale comments)

- [ ] **Step 1: Run all loom tests to establish baseline**

Run: `cd loom/loom && moon test`
Record total test count and ensure all pass.

- [ ] **Step 2: Simplify `try_reuse` method**

In `loom/loom/src/core/reuse_cursor.mbt`, replace the `try_reuse` method (lines 391-429). Remove the `leading_token_matches` and `trailing_context_matches` calls, keeping only seek + damage check:

Replace:
```moonbit
      if not(
          is_outside_damage(
            node_offset,
            node_end,
            self.damage_start,
            self.damage_end,
          ),
        ) {
        None
      } else if not(leading_token_matches(node, self, token_pos)) {
        None
      } else if not(trailing_context_matches(self, node_end)) {
        None
      } else {
        Some(node)
      }
```

With:
```moonbit
      if is_outside_damage(
          node_offset,
          node_end,
          self.damage_start,
          self.damage_end,
        ) {
        Some(node)
      } else {
        None
      }
```

Update the doc comment (lines 381-390): remove conditions 5 and 6, describe new 4-condition algorithm (globally disabled, byte_offset in damage, seek match, is_outside_damage).

- [ ] **Step 3: Update trailing-context regression test**

In `loom/loom/src/core/parser_wbtest.mbt`, find the test near line 1078-1091 that asserts `try_reuse` returns `None` because `trailing_context_matches` rejects it. Now that trailing context is no longer checked, this node WILL be reused (it's outside the damage zone with matching kind). Update the test:

Change:
```moonbit
  // Leading token matches (12), but follow token changed (34 -> 3), so reuse
  // must be rejected by trailing_context_matches.
  let result = cursor.try_reuse(test_kind_raw(KExpr), 0, 0)
  inspect(result is None, content="true")
```

To:
```moonbit
  // Node is outside damage zone — reused without trailing-context check.
  // (Trailing-context validation removed: damage-only check is sufficient
  // for context-free grammars like lambda.)
  let result = cursor.try_reuse(test_kind_raw(KExpr), 0, 0)
  inspect(result is Some(_), content="true")
```

- [ ] **Step 4: Update stale comments in `parser.mbt`**

In `loom/loom/src/core/parser.mbt`, update the comment at lines 527-530:

Change:
```moonbit
/// token_pos must skip past trivia first. leading_token_matches compares the
/// node's first *non-trivia* token against the token at token_pos in the new
/// stream. Passing a trivia index causes systematic false-negative reuse for
/// all whitespace-separated constructs (the common case).
```

To:
```moonbit
/// token_pos skips past trivia. Retained for API compatibility; the
/// ReuseCursor currently uses only seek + damage-overlap for reuse decisions.
```

- [ ] **Step 5: Run all tests**

Run: `cd loom/loom && moon test && cd ../examples/lambda && moon test`
Expected: All tests pass. The change is LESS strict (accepts nodes that trailing/leading would have rejected) — this is correct for context-free grammars where node production is independent of trailing context.

- [ ] **Step 6: Commit**

```bash
cd loom/loom && git add src/core/reuse_cursor.mbt src/core/parser_wbtest.mbt src/core/parser.mbt && git commit -m "perf(reuse): simplify try_reuse to seek + damage check, remove leading/trailing validation"
```

---

### Task 2: Simplify `try_reuse_repeat_group` — remove leading/trailing checks

**Files:**
- Modify: `loom/loom/src/core/reuse_cursor.mbt:441-520`

- [ ] **Step 1: Simplify `try_reuse_repeat_group` method**

In the RepeatGroup reuse function, find the block (around line 489-494):
```moonbit
              if leading_token_matches(child_node, self, token_pos) &&
                trailing_context_matches(self, child_end) {
                self.current_offset = child_offset
                return Some(child_node)
              }
```

Replace with:
```moonbit
              self.current_offset = child_offset
              return Some(child_node)
```

The node already passed `is_outside_damage` check (line 483-488). No further validation needed.

- [ ] **Step 2: Run all tests**

Run: `cd loom/loom && moon test && cd ../examples/lambda && moon test`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
cd loom/loom && git add src/core/reuse_cursor.mbt && git commit -m "perf(reuse): simplify try_reuse_repeat_group to damage-only check"
```

---

### Task 3: Delete old-token flattening code

**Files:**
- Modify: `loom/loom/src/core/reuse_cursor.mbt` — delete ~120 lines
- Modify: `loom/loom/src/core/parser_wbtest.mbt` — delete old_follow_token tests

After Tasks 1-2, `leading_token_matches`, `trailing_context_matches`, and `old_follow_token_lazy` are no longer called. Delete them and all supporting code.

- [ ] **Step 1: Delete the following from `reuse_cursor.mbt`**

Delete these functions/structs (in order of appearance in the file):
1. `OldToken` struct (lines 26-30)
2. `OldTokenCache` struct (lines 36-38)
3. `impl OffsetIndexed for Array[OldToken]` — both `length` and `offset_at` (lines 66-73)
4. `collect_old_tokens` function (lines 77-~130)
5. `leading_token_matches` function (lines 163-179)
6. `ensure_old_tokens` method (lines 185-204)
7. `old_follow_token_lazy` function (lines 209-~230)
8. `new_follow_token` function (lines ~235-~265)
9. `trailing_context_matches` function (lines ~270-~290)

Also remove the `cache` field from the `ReuseCursor` struct (line 52), and remove the `cache: OldTokenCache { tokens: None }` initialization from `ReuseCursor::new`.

**Intentionally retained fields:** `old_root`, `ws_raw`, `err_raw`, `incomplete_raw` remain on the struct even though they were primarily used by the deleted code. They are still used by `seek_node_at` (which navigates `old_root`) and may be used by future optimizations. Removing them is a separate cleanup.

- [ ] **Step 2: Delete old_follow_token AND new_follow_token tests from `parser_wbtest.mbt`**

Delete these five tests:
- `"new_follow_token: skips leading trivia"` (line 416)
- `"new_follow_token: returns None past end of tokens"` (line 434)
- `"old_follow_token_lazy: finds first non-trivia token at or after offset"` (line 452)
- `"old_follow_token_lazy: returns None past end of tree"` (line 473)
- `"old_follow_token_lazy: cache is shared across snapshots"` (line 490)

The trailing-context regression test comment was already updated in Task 1.

- [ ] **Step 3: Run `moon check` to verify no dangling references**

Run: `cd loom/loom && moon check`
Expected: No errors. If there are errors about missing functions, find and fix remaining callers.

- [ ] **Step 4: Run all tests**

Run: `cd loom/loom && moon test && cd ../examples/lambda && moon test`
Expected: All tests pass.

- [ ] **Step 5: Run `moon info && moon fmt`**

Run: `cd loom/loom && moon info && moon fmt`

- [ ] **Step 6: Commit**

```bash
cd loom/loom && git add src/core/reuse_cursor.mbt src/core/parser_wbtest.mbt src/core/pkg.generated.mbti && git commit -m "refactor(reuse): delete old-token flattening, leading/trailing validation code"
```

---

### Task 4: Remove CstFold cache-warming loop

**Files:**
- Modify: `loom/loom/src/core/cst_fold.mbt:80-86`
- Modify: `loom/loom/src/core/cst_fold_wbtest.mbt:82-100`

- [ ] **Step 1: Remove the cache-warming loop from `fold_node`**

In `loom/loom/src/core/cst_fold.mbt`, delete lines 80-86:
```moonbit
  // Verification: warm cache for unvisited node-children
  for child in node.children() {
    if not(visited.contains((child.start(), child.end()))) {
      self.stats.unvisited = self.stats.unvisited + 1
      let _ = self.fold_node(child)
    }
  }
```

- [ ] **Step 2: Update or remove the `FoldStats.unvisited` field**

The `unvisited` counter is now always 0. Either:
- Remove the field from `FoldStats` and all references, OR
- Keep it as always-0 for API compatibility

Choose the simpler option based on how many callers read `stats.unvisited`.

- [ ] **Step 3: Update whitebox test**

In `loom/loom/src/core/cst_fold_wbtest.mbt`, the test `"CstFold: unvisited children are cache-warmed"` (lines 83-100) asserts `stats.unvisited == 1`. This will now be 0. Either:
- Delete the test (the behavior no longer exists), OR
- Update the test to assert `stats.unvisited == 0` and rename to `"CstFold: unvisited children are not cache-warmed"`

- [ ] **Step 4: Run all tests**

Run: `cd loom/loom && moon test && cd ../examples/lambda && moon test`
Expected: All tests pass.

- [ ] **Step 5: Run `moon info && moon fmt`**

Run: `cd loom/loom && moon info && moon fmt`

- [ ] **Step 6: Commit**

```bash
cd loom/loom && git add src/core/cst_fold.mbt src/core/cst_fold_wbtest.mbt src/core/pkg.generated.mbti && git commit -m "perf(fold): remove cache-warming loop for unvisited children"
```

---

### Task 5: Benchmark and verify

**Files:**
- No file changes

- [ ] **Step 1: Run benchmarks**

Run: `cd loom/examples/lambda && moon bench --release 2>&1 | grep -E "profile:|incremental"`

Key benchmarks to record:
- `profile: 80 lets - full reparse`
- `profile: 80 lets - incremental (edit tail)`
- `profile: 80 lets - incremental (edit head)`
- `profile: 320 lets - full reparse`
- `profile: 320 lets - incremental (edit tail)`
- `profile: 320 lets - incremental (edit head)`

Compute incremental/batch ratio. Target: 0.3-0.7x.

- [ ] **Step 2: Run full test suite**

Run: `cd loom/loom && moon test && cd ../examples/lambda && moon test`
Expected: All tests pass.

- [ ] **Step 3: Run `moon check`**

Run: `cd loom/loom && moon check`
Expected: No errors.

- [ ] **Step 4: Verify `.mbti` interfaces**

Run: `cd loom/loom && git diff src/core/pkg.generated.mbti`
Expected: `OldToken`, `OldTokenCache` removed from interface. `try_reuse` / `try_reuse_repeat_group` signatures unchanged (token_pos param kept for API compatibility).

---

## Task Dependency Graph

```
Task 1 (simplify try_reuse) ──→ Task 2 (simplify repeat_group) ──→ Task 3 (delete dead code) ──→ Task 5 (benchmark)
                                                                                                      ↑
                                                                    Task 4 (remove cache warming) ────┘
```

Tasks 1-3 are sequential (each removes more code). Task 4 is independent but must complete before Task 5.
