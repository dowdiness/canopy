# Plan A Handoff — Session 2026-07-02 (Session 2, updated)

## State: Steps 5-6 complete (9/10 quality), Step 7 partial, Step 8 pending

### Done
- **Step 5 (language_spec.mbt)**: COMPLETE. Closure types changed to `raise EditError`. The guard + `compute_edit` + `on_no_edit` all route through the typed error model — `apply_edit` wraps everything in a single `try/catch` with `EditError` → `Err(e.message())` at the boundary. All 70 lang/runtime tests pass.
- **Step 6 (JSON)**: COMPLETE. `compute_json_edit.mbt` fully converted. `json_companion.mbt` updated. All 70 JSON tests pass.
- **Quality fixes applied**: `moon fmt` run, stale doc comments updated, test name fixed, `ProjectionUnavailable` variant now used (was dead code before the guard refactor).

### In Progress
- **Step 7 (Markdown)**: Three sub-tasks:
  1. `compute_markdown_edit.mbt` — return types + error strings converted. 9 `Ok(Some((...)))` wrappers remain (need stripping). `compute_move_block(…)` call at line 25 still returns old `Result` type.
  2. `compute_move_block.mbt` — NOT TOUCHED.
  3. `compute_markdown_edit_wbtest.mbt` — HAS A TYPE CONFLICT. Test helper `compute_edit_result` declares `raise @loomcore.LexError` but `compute_markdown_edit` now raises `EditError`. Two raise types can't coexist in one function. Fix: catch `LexError` from `parse_to_proj_node`/`parse_cst` early and convert to `EditError::ParseFailed`, so the helper only raises `EditError`. Then convert all `Ok(Some(...))`/`Err(msg)` patterns to `Some(...)`/try-catch, same pattern as lambda wbtest.
  4. Companion + FFI not yet updated.

### Pending
- **Step 8 (Lambda wbtest)**: `text_edit_wbtest.mbt` — ~134 `Ok`/`Err` pattern mismatches. Subagent was rate-limited. Must be done inline.

### Key Learnings
1. **Catch syntax**: `catch { e => Err(e.message()) }` — bare `e` is typed as `EditError` from the try block's raise type.
2. **Don't delegate wbtest conversion**: Too tightly coupled. Do it inline.
3. **Strip Ok wrappers with regex, not sed**: `Ok(Some((...)))` has nested parens; sed/Perl -0pe corrupts them. Use the Python regex pattern that worked for JSON.
4. **Markdown wbtest has LexError collision**: `parse_to_proj_node` raises `LexError`, `compute_markdown_edit` raises `EditError`. Catch `LexError` early to keep the helper's raise type concrete.

### Remaining Work (Steps 7-8)

#### compute_markdown_edit.mbt — 9 Ok wrappers + compute_move_block call
```
Lines with Ok(:
  47, 94, 139, 167, 204, 247, 291, 377, 408
  
Line 25: compute_move_block(...) returns old Result type — needs compute_move_block.mbt converted first
```

#### compute_move_block.mbt
Full conversion. Error mappings in the handoff from session 1.

#### compute_markdown_edit_wbtest.mbt — LexError + EditError collision
Convert `compute_edit_result` and `apply_edit` helpers:
```moonbit
// BEFORE
fn compute_edit_result(…) -> Result[…, String] raise @loomcore.LexError {
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  …
  compute_markdown_edit(op, source, proj, source_map)  // now raises EditError
}

// AFTER: catch LexError early, unify on EditError
fn compute_edit_result(…) -> (Array[SpanEdit], FocusHint)? raise @core.EditError {
  let (proj, _) = @md_proj.parse_to_proj_node(source) catch {
    e => raise @core.EditError::ParseFailed(detail=e.to_string())
  }
  …
  compute_markdown_edit(op, source, proj, source_map)
}
```
Then convert all test patterns: `Ok(Some(...))` → `Some(...)`, `Err(msg)` → try/catch.

#### Markdown companion + FFI
Same pattern as JSON: add `@core` import, update `on_no_edit` closure.

#### text_edit_wbtest.mbt (Step 8)
~134 patterns. Conversion rules in session 1 handoff.

### Verifying Completion
```bash
cd lang/runtime && NEW_MOON_MOD=0 moon test   # 70/70 pass ✓
cd lang/json && NEW_MOON_MOD=0 moon test       # 70/70 pass ✓
cd lang/markdown && NEW_MOON_MOD=0 moon test   # target: all pass
cd lang/lambda/edits && NEW_MOON_MOD=0 moon check  # target: 0 errors
moon info && moon fmt && git diff *.mbti && update docs/TODO.md
```
