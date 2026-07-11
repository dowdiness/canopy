# Container Phase 1: Document with Tree Ops — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create `container/` package in event-graph-walker with a `Document` struct that provides tree ops by composing internal packages directly, then switch the block editor to use it.

**Architecture:** Document composes CausalGraph + MovableTree + TreeOpLog + FractionalIndex directly (not through TreeState). Block editor switches from `@tree.TreeState` to `@container.Document`.

**Tech Stack:** MoonBit, event-graph-walker submodule (internal packages), canopy block-editor example

**Design reference:** `docs/plans/2026-03-29-container-design.md`

**Source reference:** `event-graph-walker/tree/tree_doc.mbt` — Document replicates TreeState's tree logic. This duplication is explicitly temporary — a follow-up before Phase 2 will extract shared tree logic into an internal package that both TreeState and Document consume, eliminating the fork.

**Deferred to Phase 2:** Op enum, Lv type alias, LogEntry struct — these are dead code until Phase 2 actually wires the unified oplog. move_node_after — no current consumer, YAGNI.

---

## File Map

### New files (event-graph-walker/container/)

| File | Responsibility |
|------|---------------|
| `container/moon.pkg` | Package manifest (DSL format), imports movable_tree, causal_graph, fractional_index, core |
| `container/errors.mbt` | `DocumentError` suberror |
| `container/document.mbt` | `Document` struct, all tree mutation/query methods, PropertyKey, comparison/dedup helpers, re-exports (TreeNodeId, root_id, etc.) |
| `container/document_test.mbt` | Tests (25 from tree_doc_test.mbt adapted + any new) |

### Modified files

| File | Change |
|------|--------|
| `examples/block-editor/main/moon.pkg` | Replace `@tree` import with `@container` import |
| `examples/block-editor/main/block_doc.mbt` | `@tree.TreeState` → `@container.Document`, `@tree.TreeError` → `@container.DocumentError` |
| `examples/block-editor/main/block_import.mbt` | Error type in signatures |
| `examples/block-editor/main/block_init.mbt` | Node ID helper references |
| `examples/block-editor/main/block_init_wbtest.mbt` | Node ID helper references |

Note: `examples/block-editor/moon.mod.json` does NOT need changes — it already depends on `dowdiness/event-graph-walker` which includes the `container/` package.

---

### Task 1: Create container/ package skeleton

**Files:**
- Create: `event-graph-walker/container/moon.pkg`
- Create: `event-graph-walker/container/errors.mbt`

- [ ] **Step 1: Create moon.pkg (DSL format, matching tree/moon.pkg pattern)**

```
import {
  "dowdiness/event-graph-walker/internal/movable_tree" @mt,
  "dowdiness/event-graph-walker/internal/fractional_index" @fi,
  "dowdiness/event-graph-walker/internal/causal_graph" @cg,
  "dowdiness/event-graph-walker/internal/core",
}

import {
  "moonbitlang/core/quickcheck",
} for "test"
```

- [ ] **Step 2: Create errors.mbt**

```moonbit
///| Document error types

///|
pub(all) suberror DocumentError {
  /// replica_id must be non-empty
  EmptyReplicaId
  /// Target node does not exist locally
  TargetNotFound
  /// Parent node does not exist locally or is not alive
  ParentNotFound
  /// Move would create a cycle in the tree
  CycleDetected
  /// Internal invariant violation
  Internal(detail~ : String)
}
```

- [ ] **Step 3: Run moon check**

```bash
cd event-graph-walker && moon check
```

Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
cd event-graph-walker
git add container/
git commit -m "feat(container): add package skeleton with DocumentError"
```

---

### Task 2: Implement Document struct with tree ops

**Files:**
- Create: `event-graph-walker/container/document.mbt`

The Document struct replicates TreeState's tree logic. Read `event-graph-walker/tree/tree_doc.mbt` in full and copy its entire content into `container/document.mbt` with these changes:

**Type/name substitutions:**
- `pub struct TreeState` → `pub struct Document`
- Every `TreeState::` → `Document::`
- Every `self : TreeState` → `self : Document`
- Every `-> TreeState` → `-> Document`
- Every `raise TreeError` → `raise DocumentError`
- Every `raise EmptyReplicaId/TargetNotFound/ParentNotFound/CycleDetected/Internal(` — same variant names, they resolve to DocumentError's variants

**What to copy:**
- `PropertyKey` struct (private, no conflict with tree/'s copy)
- `compare_ops`, `compare_property_ops`, `op_key`, `encode_field` helper functions (private, no conflict)
- `Document` struct with all fields (same as TreeState's fields)
- `Document::new` constructor
- All private helpers: `alloc_id`, `next_timestamp`, `record_op`, `reapply_properties`, `apply_property_op`, `apply_move_op`, `observe_remote_op`, `is_local_parent_valid`, `position_after_last_child`, `position_after_sibling`
- All public methods: `create_node`, `create_node_after`, `move_node`, `delete_node`, `children`, `is_alive`, `set_property`, `get_property`, `export_ops`, `apply_remote_op`

**What NOT to copy (already in this package or deferred):**
- `pub using @mt { type TreeNodeId }` — add to document.mbt as a re-export
- `pub let root_id` / `pub let trash_id` — add to document.mbt
- `tree_node_id_key`, `tree_node_id_eq`, `tree_node_id_new`, `tree_node_id_agent`, `tree_node_id_counter` — add to document.mbt
- `move_node_after` — deferred, no consumer yet

- [ ] **Step 1: Create document.mbt with all content**

Copy tree_doc.mbt with substitutions. Add re-exports (TreeNodeId, root_id, trash_id, node ID helpers) at the top.

- [ ] **Step 2: Run moon check**

```bash
cd event-graph-walker && moon check
```

Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
cd event-graph-walker
git add container/document.mbt
git commit -m "feat(container): implement Document struct with tree ops"
```

---

### Task 3: Write tests for Document

**Files:**
- Create: `event-graph-walker/container/document_test.mbt`

Copy `tree/tree_doc_test.mbt` (25 tests) and adapt:
- `@tree.TreeState::new(` → `@container.Document::new(`
- `@tree.root_id` → `@container.root_id`
- `@mt.TreeNodeId` stays the same (imported via the test's own moon.pkg imports)
- `@fi.FractionalIndex` stays the same
- The `op_timestamp` helper function at the top of tree_doc_test.mbt should also be copied

- [ ] **Step 1: Create document_test.mbt with all 25 tests adapted**

- [ ] **Step 2: Run container tests**

```bash
cd event-graph-walker && moon test -p container
```

Expected: 25 tests pass.

- [ ] **Step 3: Run full test suite**

```bash
cd event-graph-walker && moon test
```

Expected: All pass (existing + new container tests).

- [ ] **Step 4: Format and update interfaces**

```bash
cd event-graph-walker && moon info && moon fmt
```

- [ ] **Step 5: Commit**

```bash
cd event-graph-walker
git add container/
git commit -m "test(container): add 25 Document tests (adapted from TreeState)"
```

---

### Task 4: Switch block editor to @container.Document

**Files:**
- Modify: `examples/block-editor/main/moon.pkg`
- Modify: `examples/block-editor/main/block_doc.mbt`
- Modify: `examples/block-editor/main/block_import.mbt`
- Modify: `examples/block-editor/main/block_init.mbt`
- Modify: `examples/block-editor/main/block_init_wbtest.mbt`

- [ ] **Step 1: Update moon.pkg imports**

In `examples/block-editor/main/moon.pkg`, replace the `@tree` import with `@container`:

```
import {
  "dowdiness/event-graph-walker/container" @container,
  "dowdiness/event-graph-walker/text" @text,
}
```

Note: `@tree` is removed entirely. The block editor now gets TreeNodeId, root_id, etc. from `@container`.

- [ ] **Step 2: Replace all @tree references in block_doc.mbt**

- `@tree.TreeState` → `@container.Document`
- `@tree.TreeError` → `@container.DocumentError`
- `@tree.TreeNodeId` → `@container.TreeNodeId`
- `@tree.root_id` → `@container.root_id`
- `@tree.tree_node_id_key(` → `@container.tree_node_id_key(`
- `@tree.tree_node_id_eq(` → `@container.tree_node_id_eq(`

- [ ] **Step 3: Replace @tree references in block_import.mbt**

- `@tree.TreeError` → `@container.DocumentError`

- [ ] **Step 4: Replace @tree references in block_init.mbt**

- `@tree.tree_node_id_new(` → `@container.tree_node_id_new(`
- `@tree.root_id` → `@container.root_id`

- [ ] **Step 5: Replace @tree references in block_init_wbtest.mbt**

- `@tree.tree_node_id_agent(` → `@container.tree_node_id_agent(`
- `@tree.tree_node_id_counter(` → `@container.tree_node_id_counter(`

- [ ] **Step 6: Run moon check**

```bash
cd examples/block-editor && moon check
```

Expected: 0 errors (only pre-existing id_eq unused warning).

- [ ] **Step 7: Run moon test**

```bash
cd examples/block-editor && moon test
```

Expected: All 44 tests pass.

- [ ] **Step 8: Format and update interfaces**

```bash
cd examples/block-editor && moon info && moon fmt
```

- [ ] **Step 9: Commit (canopy repo)**

```bash
git add event-graph-walker examples/block-editor/
git commit -m "feat(block-editor): switch from TreeState to container Document

Block editor now uses @container.Document instead of @tree.TreeState.
This is Container Phase 1 — the foundation for unified tree+text ops."
```

---

### Task 5: Verify and finalize

- [ ] **Step 1: Run all test suites**

```bash
cd event-graph-walker && moon test
cd .. && moon test
cd examples/block-editor && moon test
```

Expected: All pass.

- [ ] **Step 2: Verify no stale @tree references in block-editor**

```bash
grep -rn "@tree\." examples/block-editor/main/*.mbt
```

Expected: Zero matches.

- [ ] **Step 3: Ask user about submodule push**

Before pushing event-graph-walker, ask: "Can I push the container/ changes to event-graph-walker main, or should I create a PR on the submodule repo?"
