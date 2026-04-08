---
summary: "Generic zipper library architecture — three layers (tree shapes, navigation algebra, annotation), concrete types for rose/binary/btree"
created: 2026-04-04
tags: [zipper, architecture, library-design, rose-tree, btree]
related: [core/proj_node.mbt, order-tree/src/walker_types.mbt, docs/TODO.md]
---

# Generic Zipper Library Architecture

## Three Layers

### Layer 1: Tree Shapes (the functor determines the context)

Each tree shape is a separate module. The derivative is computed once:

```
rose:    Node[T] = { data: T, children: Array[Node[T]] }
         Ctx[T]  = { data: T, left: Array[Node[T]], right: Array[Node[T]] }

binary:  Node[T] = Leaf | Branch(Node[T], T, Node[T])
         Ctx[T]  = WentLeft(T, Node[T]) | WentRight(Node[T], T)

btree:   Node[T] = Leaf(T, Int) | Internal(Array[Node[T]], Array[Int])
         Ctx[T]  = { children: Array[Node[T]], counts: Array[Int], idx: Int }
```

Each provides: `Zipper[T] = { focus: Node[T], path: List[Ctx[T]] }`

### Layer 2: Navigation Algebra (shared interface)

Every zipper supports:
- go_up, go_down(index), go_left, go_right
- to_root, focus, depth, child_index
- Persistent (stored in model, O(1) per move)

### Layer 3: Annotation — DROPPED from zipper library (2026-04-08)

Annotations are a tree-definition concern, not a zipper concern. Annotations should be
stored in tree nodes at construction time (like ProjNode's node_id, start, end fields),
not accumulated during navigation. See: Haskell Annotations library (`Ann x f a`),
Trees that Grow (Najd & Peyton Jones 2016), TS-that-grow (igrep).

MoonBit constraints that make a generic annotation trait impractical:
- Self-based traits can't parameterize over node data type `T`
- No type families, indexed access types, or associated types (needed for Trees that Grow)
- DepthCounter and PathRecorder are already built into RoseZipper

A principled tree-with-annotations library is a separate future project from the zipper.

## Consumers in Canopy

- ProjNode[T] = rose tree zipper (different T per language)
- OrderTree[T] = btree zipper (future Phase 2)
- Future languages (JSON, Markdown) = same rose tree zipper, different T

## Key Design Decisions

- ProjNode should BE a RoseNode (T = (NodeId, Term, Int, Int)) — zipper works directly
- No per-language zippers needed ��� `focus.kind : T` provides AST access
- Term-level zipper (lang/lambda/zipper/) superseded for navigation
- zipper-gen codegen plan superseded — uniform tree shapes have fixed derivatives

## What NOT to Include

- No codegen — derivative is fixed per tree shape
- No per-language zippers — annotation layer handles specifics
- No "zipper-aware" node types — nodes are plain data, zipper wraps them

## Phase 1 (Minimal)

Start with rose only (needed for compact view spec):

```
rose/
  node.mbt       -- RoseNode[T], RoseCtx[T], RoseZipper[T]
  navigate.mbt   -- go_up, go_down, go_left, go_right, to_root
  annotate.mbt   -- Annotator trait, push/pop wiring
```

Then btree when OrderTree refactors. Then binary when a consumer appears.
