# Design: Tree Editor Subtree Reuse And Elision

**Parent:** [2026-03-11 Rabbita Projection Editor Performance Recovery](./2026-03-11-rabbita-projection-editor-performance-plan.md)
**Related:** [Rabbita Projection Editor Performance Issues](../performance/RABBITA_PROJECTION_EDITOR_ISSUES.md)
**Status:** In Progress
**Date:** 2026-03-11

---

## Problem

Phase 5 has already removed two obvious sources of waste:

- the sidebar no longer rescans the full interactive tree every render
- `TreeEditorState::refresh(...)` now builds the tree and collects valid IDs in one pass

That is still not enough. A structural refresh currently allocates a fresh
`InteractiveTreeNode` value for every visible and hidden node in the projection
tree, even when:

- only one leaf changed
- large sibling subtrees are unchanged
- a subtree is collapsed and will not be rendered

The remaining cost is dominated by full interactive-tree reconstruction.

The current benchmark evidence makes that priority concrete:

- medium-tree Rabbita edits are still measured in the hundreds of milliseconds
  even after incremental text edits and deferred refresh
- the parser microbenchmarks are tiny in comparison
- the first large-tree deferred `TextInput` sample still did not complete within
  a `5+ minute` observation window in the release harness

So this design is no longer speculative cleanup. It is the main remaining
performance bottleneck after Phases 1-4.

## Goal

Reduce structural refresh cost by:

1. reusing unchanged `InteractiveTreeNode` subtrees when the underlying
   `ProjNode` subtree and UI flags are unchanged
2. eliding collapsed descendants so refresh does not allocate hidden
   interactive nodes unnecessarily
3. preserving existing semantics for selection, collapse/expand, drag/drop,
   delete cleanup, and stale-ID pruning

## Non-Goals

- No change to `ProjNode` reconciliation or node-ID rules
- No keyed child rendering via Rabbita `Map[String, Html]`
- No parser or CRDT changes in this design
- No attempt to make every tree operation O(1)

---

## Current Constraints

The current tree editor relies on several invariants:

- `ProjNode` is authoritative for structure and node identity
- `TreeEditorState` is UI state only
- `Collapse` and `Expand` are local UI operations and should remain immediate
- `Delete`, `DragOver`, `Drop`, and `SelectRange` currently inspect the loaded
  interactive tree to answer subtree questions
- Rabbita array children preserve sibling order; keyed children currently do not
  provide a safe ordered structure for this tree editor

The last two points are the main blockers for naive subtree elision.

If collapsed descendants are simply omitted from `InteractiveTreeNode.children`,
these existing operations become incorrect:

- `Delete` can fail to clear stale descendant selections or drag state
- `DragOver` / `Drop` can stop recognizing descendant relationships
- `SelectRange` can stop seeing nodes hidden under a collapsed branch
- local `Expand` has nothing to reveal unless another rebuild happens

So the design has to separate:

- the rendered interactive tree
- the indexes used for tree-editor operations

---

## Proposed Direction

## Split Tree State Into Render Tree Plus Structural Indexes

`TreeEditorState` should stop treating the interactive tree as the only data
structure for tree operations.

Add refresh-built indexes that describe the full projection tree even when some
interactive descendants are elided:

- `preorder_ids : Array[NodeId]`
- `preorder_range_by_root : Map[NodeId, (Int, Int)]`
  Meaning the inclusive preorder slice occupied by that subtree.
- `parent_by_child : Map[NodeId, NodeId]`
- `loaded_nodes : Map[NodeId, InteractiveTreeNode]`
  For fast node lookup in the currently materialized interactive tree.

These indexes are derived from the authoritative `ProjNode` refresh walk, not
from the rendered tree.

### Why this matters

With preorder subtree ranges:

- `SelectRange` can operate over `preorder_ids` directly
- subtree deletion cleanup can clear all descendant IDs without traversing loaded
  interactive children
- descendant checks for drag/drop can use parent links or preorder containment

That means collapsed descendants no longer have to stay materialized just to
support editor logic.

---

## Stage 1: Reuse Unchanged Interactive Subtrees

Before adding elision or index-backed operation rewrites, reduce rebuild churn
for expanded regions.

### Add an internal subtree stamp

During refresh, compute a cheap internal stamp per node from:

- `NodeId`
- `label`
- `text_range`
- `selected`
- `editing`
- `collapsed`
- `drop_target`
- ordered child `NodeId`s

This stamp does not need to be public API.

### Reuse rule

When refreshing node `N`:

1. recursively refresh child subtrees first
2. look up the previous `InteractiveTreeNode` for `N.id`
3. if the previous node's stamp matches and the refreshed child list is
   element-wise identical by node identity/order, return the previous node
4. otherwise allocate a new `InteractiveTreeNode`

This gives reuse for unchanged branches without changing external behavior.

### Expected win

- unrelated sibling branches stop being reallocated on every structural refresh
- render work can later benefit from stable subtree values even while Rabbita
  still diffs array children positionally
- this is the fastest plausible response to the benchmark result that medium
  trees are already far too slow, because it attacks expanded-tree rebuild cost
  directly without waiting for the more invasive elision/index work

---

## Stage 2: Add Structural Indexes

After reuse is in place, add the structural indexes needed to decouple tree
operations from fully loaded interactive descendants.

Add refresh-built indexes that describe the full projection tree:

- `preorder_ids : Array[NodeId]`
- `preorder_range_by_root : Map[NodeId, (Int, Int)]`
- `parent_by_child : Map[NodeId, NodeId]`
- `loaded_nodes : Map[NodeId, InteractiveTreeNode]`

This is the enabling step for safe elision.

## Stage 3: Port Tree Operations Onto Structural Indexes

These current helpers should stop depending on the loaded interactive subtree:

- `collect_subtree_ids`
- `is_descendant_of`
- `collect_nodes_in_range`

Replace them with index-backed logic:

- subtree IDs from `preorder_range_by_root`
- descendant checks from preorder containment or `parent_by_child`
- range selection from `preorder_ids`

This is the step that makes elision semantically safe.

### Example

If subtree root `r` has preorder span `(10, 18)`, then all descendants are:

```text
preorder_ids[10..18]
```

No interactive-child traversal is required.

## Stage 4: Elide Collapsed Descendants

Once the indexes and operation rewrites exist, collapsed nodes can stop
materializing full interactive descendants on refresh.

### Data model change

Replace unconditional `children : Array[InteractiveTreeNode]` with a loaded vs
elided representation.

One workable shape is:

```moonbit
enum InteractiveChildren {
  Loaded(Array[InteractiveTreeNode])
  Elided(descendant_count : Int)
}
```

`InteractiveTreeNode` would then hold:

```moonbit
children : InteractiveChildren
```

The tree view renders:

- `Loaded(children)` when expanded
- the collapsed marker when collapsed
- nothing recursive for `Elided(...)`

### Refresh behavior

When a node is collapsed during structural refresh:

- record its full subtree range in the structural indexes
- compute `descendant_count`
- do not allocate descendant `InteractiveTreeNode`s
- return `children = Elided(descendant_count)`

When a node is expanded during structural refresh:

- recurse normally and return `Loaded(children)`

### Important constraint

Local collapse after the subtree is already loaded should remain cheap and
immediate. That means `Collapse(node_id)` should usually just flip UI state on
the already-loaded node rather than immediately discarding its children.

The downgrade from `Loaded(...)` to `Elided(...)` should happen only on the next
structural refresh, not on the local collapse action itself.

---

## Stage 5: Add Projection-Only Hydration For Expanding Elided Nodes

Once collapsed descendants may be elided after refresh, `Expand` can no longer
assume the children are already materialized.

So `Expand` needs two modes:

- `Loaded -> Loaded`: local UI-only toggle, no rebuild
- `Elided -> Loaded`: projection-only subtree hydration from the current
  `ProjNode` + `SourceMap`, with no parser or CRDT work

This keeps the Phase 3 rule intact:

- expand does not trigger text or parser work
- but it may trigger a targeted tree-state rebuild for that branch if the branch
  was structurally elided on an earlier refresh

### Needed helper

Add a targeted builder such as:

```moonbit
fn TreeEditorState::hydrate_subtree(
  self,
  node_id : NodeId,
  proj : ProjNode,
  source_map : SourceMap,
) -> TreeEditorState
```

This should rebuild only the requested branch and patch it back into the loaded
interactive tree.

---

---

## Why Not Use Rabbita Keyed Children Here

The obvious UI idea is keyed subtree rendering, but Rabbita's keyed-children
path currently uses `Map[String, Html]`.

For this editor, sibling order is semantic, and a hash `Map` is not a safe
ordered collection. So keyed children are not part of this design unless
Rabbita grows an ordered keyed-child API.

The tree editor should therefore reduce work primarily by:

- reusing interactive subtree values
- skipping hidden subtree allocation
- keeping array child rendering in source order

---

## Implementation Plan

### Step 1. Add subtree-stamp-based reuse

Reuse unchanged expanded subtrees during refresh.

This is now the first implementation priority because the benchmark results say
medium expanded trees are already too slow, and reuse is the lowest-risk way to
cut refresh churn directly.

### Step 2. Add structural indexes to `TreeEditorState`

Add internal fields for preorder and parent/subtree indexes.

No render change yet.

### Step 3. Port helper operations to indexes

Make `Delete`, `DragOver` / `Drop`, and `SelectRange` use the new indexes.

At this point, elision becomes mechanically safe.

### Step 4. Introduce `InteractiveChildren`

Allow collapsed descendants to be represented as `Elided(...)`.

### Step 5. Add targeted expand hydration

Teach local `Expand` how to rehydrate an elided branch from the current
projection snapshot without touching parser or CRDT state.

---

## Testing Requirements

Add tests for:

- refresh reuses unchanged sibling branches after an unrelated leaf change
- `Delete` clears stale descendant UI state when the deleted subtree is elided
- `DragOver` still rejects dropping onto a descendant when the ancestor branch
  is collapsed/elided
- `SelectRange` still returns the correct preorder slice across elided regions
- local `Collapse` remains immediate for already-loaded branches
- `Expand` hydrates an elided subtree without changing text or parser state

The most important negative test is:

- collapsed subtree is elided after refresh
- expand it locally
- children appear correctly
- no parser/projection refresh is triggered beyond the targeted subtree hydrate

---

## Risks

### Index drift

If preorder or parent indexes stop matching the render tree, UI operations will
become subtly wrong. Refresh and targeted hydration must update both structures
together.

### Overcomplicating reuse stamps

The reuse stamp should stay local and pragmatic. If it becomes a second
projection system, the optimization will be harder to trust than the cost it is
trying to remove.

### Expand UX regression

If `Expand` on an elided node is not explicitly handled, the UI will appear
broken because the node toggles open with no children.

---

## Recommendation

Implement subtree reuse before index migration and collapsed-subtree elision.

Reuse is the lower-risk half:

- it preserves the current interactive-tree shape
- it already fits the current local expand/collapse behavior
- it should remove a meaningful amount of rebuild churn on large trees

The measured bottleneck now strengthens that ordering:

- parser work is not the dominant cost anymore
- medium-tree latency is still dominated by structural refresh work
- the large-tree path is still non-interactive

So the practical order is:

1. subtree reuse for unchanged expanded branches
2. structural indexes
3. operation migration to those indexes
4. collapsed-descendant elision
5. targeted expand hydration

That order keeps Phase 5 moving without breaking tree-editor semantics.
