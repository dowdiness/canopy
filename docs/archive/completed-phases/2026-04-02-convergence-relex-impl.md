# Convergence-Based Incremental Re-lex Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Make mode-aware incremental edits O(edit_size + convergence_distance) instead of O(document_size), bringing incremental below batch parse.

**Measured baseline (2000-line doc):** Full parse 1.43ms, incremental 1.58ms (1.1x slower due to full retokenize). Target: incremental < 500µs.

**Architecture:** Store modes array in type-erased closures. On edit, re-lex from the mode at the damage start until the new mode matches the old mode (convergence). Splice replacement tokens into the existing buffer. Unchanged prefix/suffix tokens are reused.

**Scope:** `loom/loom/src/core/mode_lexer.mbt` and `loom/loom/src/core/token_buffer.mbt` only. No parser/grammar changes.

---

## Design

### How convergence works

After an edit, the stateless incremental path re-lexes a substring and splices in replacement tokens. The mode-aware path does the same, but must also check that the lex mode has stabilized:

1. Find damaged token range `[left, right)` (same binary search as stateless)
2. Get the mode stored at `left` from the captured modes array
3. Re-lex from `left`'s offset with that mode
4. After each token, if we've passed the edit region, check: does the current mode match the old mode at the corresponding old token index?
   - **Yes → converged.** Stop. Everything after this point is unchanged.
   - **No → mode changed.** Extend `right` by one token and continue re-lexing.
5. Splice replacement tokens + update modes array

For a paragraph edit (no mode change): convergence is immediate after the damaged region. Re-lex ~3 tokens.
For a code fence insertion: convergence at the closing fence. Re-lex the code block.
For an unclosed fence: convergence at EOF. Re-lex everything (same as full retokenize — unavoidable).

### Type-erased interface

`ModeRelexState[T]` gains two closures that hide M:

```moonbit
pub struct ModeRelexState[T] {
  /// Full tokenize (initial parse).
  tokenize : (String) -> (Array[TokenInfo[T]], Array[Int]) raise LexError
  /// Re-lex from offset with the mode at start_tok_idx.
  /// Continues until mode converges or EOF.
  /// Returns (replacement_tokens, converged_at_old_tok_idx).
  /// converged_at_old_tok_idx = old token index where modes matched, or
  /// old_token_count if reached EOF.
  relex_from : (String, Int, Int, Int) -> (Array[TokenInfo[T]], Int) raise LexError
  // params: (new_source, start_offset, start_tok_idx, old_token_count)
  /// Splice modes array after tokens are spliced.
  splice_modes : (Int, Int, Int) -> Unit
  // params: (start_idx, delete_count, insert_count)
}
```

The `relex_from` closure captures the `ModeLexer[T, M]` and `Ref[Array[M]]`. It:
1. Reads `modes_ref.val[start_tok_idx]` to get the starting mode
2. Calls `lexer.lex_step(source, pos, mode)` in a loop
3. Collects tokens until convergence: `new_mode == modes_ref.val[old_idx]`
4. Stores new modes in a temp array for `splice_modes` to apply

### TokenBuffer changes

`new_with_mode_relex` sets `incremental_relex_enabled: true` (was false). The `update` method's incremental path now checks for `mode_relex`:

```
// After finding [left_tok, right_tok) damage range:
match self.mode_relex {
  Some(state) => {
    let (replacement, converged_right) = state.relex_from(
      new_source, left_new_offset, left_tok_idx, old_len)
    // converged_right may be > right_tok_idx (mode propagated)
    // Use converged_right as the actual right boundary for splice
    state.splice_modes(left_tok_idx, converged_right - left_tok_idx, replacement.length())
    // ... splice tokens using converged_right instead of right_tok_idx
  }
  None => {
    // existing stateless tokenize_range_impl path
  }
}
```

---

## File Changes

| File | Change |
|------|--------|
| `core/mode_lexer.mbt` | Add `relex_from` + `splice_modes` to `ModeRelexState`. Restore `modes_ref` in `erase_mode_lexer`. Add `relex_with_convergence` helper. |
| `core/mode_lexer_wbtest.mbt` | Add convergence tests: no-mode-change edit, mode-change propagation, EOF convergence |
| `core/token_buffer.mbt` | Change `new_with_mode_relex` to `incremental_relex_enabled: true`. Add mode-aware branch in `update`'s incremental path. |
| `core/mode_relex_wbtest.mbt` | Update existing tests (they should still pass — same behavior, different path) |

---

## Tasks

### Task 1: Add relex_from and splice_modes to ModeRelexState

Restore `modes_ref` in `erase_mode_lexer`. Add the `relex_from` closure that re-lexes with convergence. Add `splice_modes` closure that updates the modes array.

Test: convergence unit tests with the mock 2-mode language.

### Task 2: Wire into TokenBuffer::update

Change `new_with_mode_relex` to set `incremental_relex_enabled: true`. Add the mode-aware branch in the incremental path that calls `relex_from` and uses the converged boundary for splicing.

Test: existing mode_relex_wbtest tests should still pass.

### Task 3: Benchmark verification

Run the scaled markdown benchmarks. Verify incremental is now faster than full parse at 50x and 100x scales.

### Task 4: Regression tests

Run lambda, JSON, and markdown full test suites. Verify no regressions.

---

## Acceptance Criteria

- [ ] Incremental edit on 2000-line document is faster than full parse
- [ ] Single-char paragraph edit converges within ~3 tokens (not full retokenize)
- [ ] Code fence insertion converges at closing fence
- [ ] All existing mode_relex_wbtest tests pass
- [ ] Lambda/JSON/Markdown test suites pass
- [ ] `moon check` 0 errors across loom module

## Validation

```bash
cd loom/loom && moon check && moon test
cd loom/examples/lambda && moon test
cd loom/examples/json && moon test
cd loom/examples/markdown && moon bench --release
```
