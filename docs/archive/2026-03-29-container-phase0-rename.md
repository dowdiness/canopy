# Container Phase 0: Type Renames — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename `TextDoc` → `TextState`, `TreeDoc` → `TreeState`, `TreeDocError` → `TreeError` to clear naming space for the container's `Document` type.

**Architecture:** Mechanical find-and-replace across event-graph-walker (submodule) and canopy (main module). Each rename is done, tested, and committed independently. `.mbti` files are regenerated with `moon info`.

**Tech Stack:** MoonBit, event-graph-walker submodule, canopy main module, block-editor example

**Design reference:** `docs/plans/2026-03-29-container-design.md` § Naming Changes

---

## File Map

### Rename 1: TextDoc → TextState

| File | Package | Type of change |
|------|---------|---------------|
| `event-graph-walker/text/text_doc.mbt` | text | Definition + all methods |
| `event-graph-walker/text/sync.mbt` | text | SyncSession references |
| `event-graph-walker/text/undo_helpers.mbt` | text | Helper function parameters |
| `event-graph-walker/text/undoable_impl.mbt` | text | Trait impl |
| `event-graph-walker/text/text_test.mbt` | text | Test constructor calls |
| `event-graph-walker/text/text_properties_test.mbt` | text | Test constructor calls |
| `event-graph-walker/text/text_convergence_fuzz_test.mbt` | text | Test constructor calls |
| `event-graph-walker/text/text_benchmark.mbt` | text | Benchmark constructor calls |
| `event-graph-walker/text/debug_convergence_test.mbt` | text | Test constructor calls |
| `event-graph-walker/undo/undo_manager_test.mbt` | undo | Test references to TextDoc |
| `event-graph-walker/undo/undoable.mbt` | undo | Trait bound references |
| `editor/sync_editor.mbt` | canopy/editor | Field type + usage |
| `editor/editor.mbt` | canopy/editor | Field type + usage |
| `examples/block-editor/main/block_doc.mbt` | block-editor | Field type in texts Map value |
| `loom/examples/lambda/src/crdt_egw_test.mbt` | lambda | Test constructor calls |

### Rename 2: TreeDoc → TreeState

| File | Package | Type of change |
|------|---------|---------------|
| `event-graph-walker/tree/tree_doc.mbt` | tree | Definition + all methods |
| `event-graph-walker/tree/errors.mbt` | tree | Error name definition |
| `event-graph-walker/tree/tree_doc_test.mbt` | tree | Test constructor calls |
| `examples/block-editor/main/block_doc.mbt` | block-editor | Field type + raise signatures |
| `examples/block-editor/main/block_import.mbt` | block-editor | Raise signatures |

### Rename 3: TreeDocError → TreeError

Same files as Rename 2 — done together since they're in the same package.

---

### Task 1: Rename TextDoc → TextState in event-graph-walker

**Files:**
- Modify: `event-graph-walker/text/text_doc.mbt`
- Modify: `event-graph-walker/text/sync.mbt`
- Modify: `event-graph-walker/text/undo_helpers.mbt`
- Modify: `event-graph-walker/text/undoable_impl.mbt`
- Modify: `event-graph-walker/text/text_test.mbt`
- Modify: `event-graph-walker/text/text_properties_test.mbt`
- Modify: `event-graph-walker/text/text_convergence_fuzz_test.mbt`
- Modify: `event-graph-walker/text/text_benchmark.mbt`
- Modify: `event-graph-walker/text/debug_convergence_test.mbt`
- Modify: `event-graph-walker/undo/undo_manager_test.mbt`
- Modify: `event-graph-walker/undo/undoable.mbt`

- [ ] **Step 1: Find all TextDoc references in event-graph-walker**

```bash
cd event-graph-walker
grep -rn "TextDoc" --include="*.mbt" text/ undo/
```

Verify the reference count before and after to ensure nothing is missed.

- [ ] **Step 2: Replace TextDoc with TextState in all .mbt files**

In each file listed above, replace every occurrence of `TextDoc` with `TextState`. This is a literal text replacement — `TextDoc` appears only as a type name, not in comments or strings that should be preserved.

Key replacements:
- `pub fn TextDoc::` → `pub fn TextState::`
- `self : TextDoc` → `self : TextState`
- `-> TextDoc` → `-> TextState`
- `TextDoc::new(` → `TextState::new(`

- [ ] **Step 3: Run moon check**

```bash
cd event-graph-walker && moon check
```

Expected: 0 errors. If there are errors, a reference was missed — find and fix it.

- [ ] **Step 4: Run moon test**

```bash
cd event-graph-walker && moon test
```

Expected: All tests pass (same count as before the rename).

- [ ] **Step 5: Regenerate interfaces and format**

```bash
cd event-graph-walker && moon info && moon fmt
```

- [ ] **Step 6: Commit in submodule**

```bash
cd event-graph-walker
git add text/ undo/
git commit -m "rename: TextDoc → TextState

Clears the naming space for the container's Document type.
The text CRDT's mutable state is a TextState, not a Document."
```

---

### Task 2: Rename TreeDoc → TreeState and TreeDocError → TreeError in event-graph-walker

**Files:**
- Modify: `event-graph-walker/tree/tree_doc.mbt`
- Modify: `event-graph-walker/tree/errors.mbt`
- Modify: `event-graph-walker/tree/tree_doc_test.mbt`

- [ ] **Step 1: Find all TreeDoc and TreeDocError references**

```bash
cd event-graph-walker
grep -rn "TreeDoc\|TreeDocError" --include="*.mbt" tree/
```

- [ ] **Step 2: Replace TreeDocError with TreeError first (more specific, avoids partial match)**

In `tree/errors.mbt`: `pub(all) suberror TreeDocError` → `pub(all) suberror TreeError`

In `tree/tree_doc.mbt`: every `raise TreeDocError` → `raise TreeError`, every `TreeDocError` → `TreeError`

- [ ] **Step 3: Replace TreeDoc with TreeState**

In `tree/tree_doc.mbt`:
- `pub struct TreeDoc` → `pub struct TreeState`
- `pub fn TreeDoc::` → `pub fn TreeState::`
- `fn TreeDoc::` → `fn TreeState::`
- `self : TreeDoc` → `self : TreeState`
- `-> TreeDoc` → `-> TreeState`

In `tree/tree_doc_test.mbt`:
- `@tree.TreeDoc::new(` → `@tree.TreeState::new(`

- [ ] **Step 4: Run moon check**

```bash
cd event-graph-walker && moon check
```

Expected: 0 errors.

- [ ] **Step 5: Run moon test**

```bash
cd event-graph-walker && moon test
```

Expected: All tests pass.

- [ ] **Step 6: Regenerate interfaces and format**

```bash
cd event-graph-walker && moon info && moon fmt
```

- [ ] **Step 7: Commit in submodule**

```bash
cd event-graph-walker
git add tree/
git commit -m "rename: TreeDoc → TreeState, TreeDocError → TreeError

Clears the naming space for the container's Document type.
The tree CRDT's mutable state is a TreeState, not a Document."
```

---

### Task 3: Update canopy consumers

**Files:**
- Modify: `editor/sync_editor.mbt`
- Modify: `editor/editor.mbt`
- Modify: Any other `editor/*.mbt` files referencing `TextDoc`
- Modify: `examples/block-editor/main/block_doc.mbt`
- Modify: `examples/block-editor/main/block_import.mbt`
- Modify: `loom/examples/lambda/src/crdt_egw_test.mbt`

- [ ] **Step 1: Find all TextDoc, TreeDoc, TreeDocError references in canopy**

```bash
grep -rn "TextDoc\|TreeDoc\|TreeDocError" --include="*.mbt" editor/ examples/ crdt*.mbt lang/ loom/
```

- [ ] **Step 2: Replace all references**

- `@text.TextDoc` → `@text.TextState`
- `TextDoc` → `TextState` (in files that import the text package)
- `@tree.TreeDoc` → `@tree.TreeState`
- `TreeDoc` → `TreeState`
- `@tree.TreeDocError` → `@tree.TreeError`
- `TreeDocError` → `TreeError`

- [ ] **Step 3: Update submodule pointer**

```bash
git add event-graph-walker
```

- [ ] **Step 4: Run moon check on canopy**

```bash
moon check
```

Expected: 0 errors.

- [ ] **Step 5: Run moon test on canopy**

```bash
moon test
```

Expected: All tests pass.

- [ ] **Step 6: Run moon check on block-editor**

```bash
cd examples/block-editor && moon check
```

Expected: 0 errors (only the pre-existing `id_eq` unused warning).

- [ ] **Step 7: Run moon test on block-editor**

```bash
cd examples/block-editor && moon test
```

Expected: All 44 tests pass.

- [ ] **Step 8: Regenerate interfaces and format**

```bash
moon info && moon fmt
cd examples/block-editor && moon info && moon fmt
```

- [ ] **Step 9: Commit**

```bash
git add editor/ examples/ loom/ crdt*.mbt lang/
git commit -m "rename: update canopy consumers for TextState, TreeState, TreeError

Follows event-graph-walker rename of TextDoc → TextState,
TreeDoc → TreeState, TreeDocError → TreeError."
```

---

### Task 4: Verify full test suite

- [ ] **Step 1: Run all test suites**

```bash
cd event-graph-walker && moon test
cd ../loom/loom && moon test
cd ../../examples/block-editor && moon test
cd ../.. && moon test
```

Expected: All pass with the same counts as before the rename.

- [ ] **Step 2: Verify no stale references remain**

```bash
grep -rn "TextDoc\|TreeDoc\|TreeDocError" --include="*.mbt" event-graph-walker/ editor/ examples/ crdt*.mbt lang/ loom/
```

Expected: Zero matches (except possibly in comments or strings that don't need updating — verify each).

- [ ] **Step 3: Push submodule**

```bash
cd event-graph-walker && git push origin HEAD:main
```

- [ ] **Step 4: Push canopy**

```bash
cd .. && git push origin main
```
