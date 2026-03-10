# Project TODO

Improvement proposals for the eg-walker CRDT Lambda Calculus Editor.

## Priority Legend

- **Impact:** High / Medium / Low
- **Effort:** High / Medium / Low
- **Status:** Not Started / In Progress / Done

---

## 1. CI/CD & Automation

**Impact:** High | **Effort:** Low-Medium | **Status:** ✅ Done

- [x] Add GitHub Actions workflow to run `moon test` for both modules on push/PR
- [x] Add `moon check` and `moon fmt --check` to CI pipeline
- [x] Add benchmark regression detection (store baselines, compare on PR)
- [x] Automate JS build verification (`moon build --target js`)
- [x] Add deployment workflow for GitHub Pages
- [x] Add release automation workflow
- [x] Add Dependabot configuration for dependency updates
- [x] Add Makefile for common development tasks
- [x] Add helper scripts (build-web.sh, test-all.sh, check-all.sh)
- [x] Add pre-commit hook installation script

---

## 2. Collaboration Features

**Impact:** High | **Effort:** High

- [ ] Complete WebSocket client integration (sync protocol designed, TypeScript API stub exists)
- [ ] Fix P2-1: Remote sync pollutes undo history — add `suppressUndoTracking` for remote changes (see `valtio/PLAN.md`)
- [ ] Fix P2-2: Position-based undo replays stale positions after concurrent edits — switch to snapshot-based undo (see `valtio/PLAN.md`)
- [ ] Add remote cursor/selection tracking

---

## 3. Incremental Parsing Optimization

**Impact:** Medium | **Effort:** Medium

- [ ] Implement selective cache invalidation by range instead of full reparse fallback (loom incremental engine)
- [x] Implement LCS matching for AST child reconciliation instead of positional matching (`projection/text_lens.mbt:219`)

---

## 4. Memory & Scalability

**Impact:** Medium | **Effort:** High

- [ ] Apply RLE memory optimization across full pipeline (estimated 50-80% reduction, Phase 2 TextSpan done)
- [ ] Implement lazy loading for 100k+ operation documents (load causal graph skeleton, hydrate on demand)
- [ ] Add B-tree indexing for FugueTree (O(n) → O(log n) random-access character lookup)

---

## 5. Testing Gaps

**Impact:** Medium | **Effort:** Low-Medium

- [ ] Add fuzz testing — random byte streams to parser, random operation sequences to CRDT
- [ ] Add E2E browser tests with Playwright (already a devDependency, no automated tests yet)
- [ ] Add error path tests — malformed sync messages, corrupted operation logs, network interruptions
- [ ] Add multi-agent stress tests in MoonBit — property-test N concurrent agents with random interleaving

---

## 6. Tree Edit Bridge Tech Debt

**Impact:** Medium | **Effort:** Medium-High

Known concerns from the `editor/tree_edit_bridge.mbt` roundtrip implementation (text CRDT approach per §5).

### Dual-state architecture (SyncEditor + CanonicalModel)

- [ ] **Encapsulate CanonicalModel inside SyncEditor** — `apply_tree_edit` takes both as separate arguments, leaking internal coupling to callers. Per §3, CanonicalModel should be retired; its useful parts (ProjNode reconciliation, node registry, source map) become derived state on SyncEditor with `Memo[ProjNode]`.
- [ ] **Double parse per tree edit** — `set_source` invalidates the reactive parser (lazy), then `text_lens_put` eagerly parses via `parse_to_proj_node`. Both are needed because SyncEditor and CanonicalModel maintain separate parse pipelines. Unifying them eliminates one full parse per edit.

### Diff logic triplication

- [ ] **Consolidate prefix/suffix diff** — The same longest-common-prefix/suffix algorithm exists in three places: `projection/text_lens.mbt` (`text_lens_diff`), `editor/sync_editor.mbt` (`set_text_and_record` inline), and `editor/text_diff.mbt` (`compute_edit`). Each returns a different type. Extract a shared diff core with adapters per return type.

### TextInput path efficiency

- [ ] **`set_text` is brute-force O(n)** — Deletes all chars one-by-one then re-inserts. `set_text_and_record` already has a diff-based approach but couples undo tracking. Extract the diff+apply core as a shared helper so `set_text` can use it too. Acceptable for lambda calculus (small expressions) but would matter for larger documents.

### CRDT API limitations

- [ ] **Char-by-char delete for range deletions** — `TextDoc` only exposes single-char `delete(Pos)`. Adding `delete_range` to `event-graph-walker/text` would eliminate char-by-char loops.
- [ ] **No undo tracking for tree edits** — `apply_tree_edit` uses `set_text` (bare `doc.insert`/`doc.delete`, no `_and_record` variants). Tree edits are not undoable via `SyncEditor.undo()`. Decide whether tree edits should integrate with UndoManager.

### Resolved: CRDT position ordering bug

- [x] **`apply_projection_edits` used insert-first ordering** — `text_lens_diff` produces edits with insert-before-delete and adjusted positions. FugueMax's position semantics require delete-first ordering; insert-first caused position drift producing corrupted text. **Fixed:** replaced with `set_text(new_text)` which uses proven delete-all + insert approach.

---

## 7. Code Cleanup

**Impact:** Low | **Effort:** Low

- [ ] Convert `abort()` calls in test files to proper assertions (`assert_true` / `inspect`) for better error messages

---

## 7. Developer Experience

**Impact:** Low-Medium | **Effort:** Low | **Status:** ✅ Done

- [x] Add top-level `Makefile` or `justfile` wrapping both-module test commands into a single invocation
- [x] Add pre-commit hook running `moon check && moon fmt --check`
- [x] Script the web build workflow (`moon build --target js && cp target/js/release/build/crdt.js web/public/`)

---

## Priority Ranking

| # | Proposal | Effort | Impact |
|---|----------|--------|--------|
| 1 | CI test automation | Low | High |
| 2 | Fix undo/redo (P2-1, P2-2) | Medium | High |
| 3 | Complete WebSocket collaboration | High | High |
| 4 | E2E browser tests | Low | Medium |
| 5 | Benchmark regression CI | Medium | Medium |
| 6 | Tree edit bridge tech debt | Medium-High | Medium |
| 7 | Incremental parsing TODOs | Medium | Medium |
| 8 | Single-command test runner | Low | Low-Med |
| 9 | Code cleanup | Low | Low |
| 10 | Memory optimization | High | Medium |
| 11 | Fuzz testing | Medium | Medium |
