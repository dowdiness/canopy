---
summary: "Generic tree library architecture — rose zipper (immutable, navigation API) vs B-tree (mutable, tree API with cursor internal)"
created: 2026-04-04
updated: 2026-04-08
tags: [zipper, btree, architecture, library-design, rose-tree]
related: [core/proj_node.mbt, order-tree/src/walker_types.mbt, docs/TODO.md]
---

# Generic Tree Library Architecture

## Key Insight: Different Tree Shapes -> Different Abstraction Levels

The derivative of a type (McBride 2001) gives the context/zipper shape for any tree. But whether
the **zipper** or the **tree** is the right API depends on the tree's purpose:

- **Rose tree** -> zipper is the API. The tree type is trivial (data + children). The interesting
  part is persistent navigation. Users hold zippers across keystrokes, keep multiple cursors.
  -> `lib/zipper/` exposes `RoseZipper[T]` (immutable, persistent)

- **B-tree** -> the tree is the API. The interesting part is balanced mutations (split, merge,
  rebalance) with counted access. Cursors are ephemeral (create, use, discard per operation).
  -> `lib/btree/` exposes `BTree[T]` (mutable, cursor internal)

A shared "navigation algebra" trait across both is not practical -- the APIs are too different
(persistent go_up/go_down vs ephemeral descend-and-mutate). The shared concept is theoretical
(both decompose tree into focus + context), not a code-level interface.

### Why mutable zippers resist generalization

Immutable zippers separate navigation from mutation (one universal API: go_up/down/left/right).
Mutable B-tree cursors entangle them: descent prepares for the specific mutation (proactive
splitting for insert, proactive rebalancing for delete). Balancing invariants are tree-shape-specific
(B-tree degree vs AVL height vs RB coloring). This is why a generic "mutable zipper" interface
doesn't work -- but a generic B-tree library (hiding the cursor) works fine.

## Consumers in Canopy

- ProjNode[T] = rose tree zipper (different T per language)
- OrderTree[T] = generic B-tree (cursor internal, Phase 2)
- Future languages (JSON, Markdown) = same rose tree zipper, different T

## Key Design Decisions

- ProjNode should BE a RoseNode (T = (NodeId, Term, Int, Int)) -- zipper works directly
- No per-language zippers needed -- `focus.kind : T` provides AST access
- Term-level zipper (lang/lambda/zipper/) superseded for navigation
- zipper-gen codegen plan superseded -- uniform tree shapes have fixed derivatives
- Annotation trait dropped -- tree-definition concern, separate future project
- B-tree zipper renamed to B-tree library -- cursor is internal, tree is the API

## Phase Plan

- Phase 1: Rose tree zipper (`lib/zipper/`) -- Done (PR #130)
- Phase 2: Generic B-tree library (`lib/btree/`) -- extract from OrderTree
- Future: Binary tree zipper, finger tree -- when consumers appear
