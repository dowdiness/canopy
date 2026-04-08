---
summary: "Why ProjNode zipper supersedes Term-level zipper and zipper-gen — analysis of what's truly needed at each level"
created: 2026-04-04
tags: [zipper, architecture-decision, projnode, term-zipper]
related: [lang/lambda/zipper/, core/proj_node.mbt, docs/archive/2026-03-28-ast-zipper-design.md]
---

# Supersession Analysis: ProjNode Zipper vs Term Zipper vs Zipper-Gen

## What Supersedes What

```
ProjNode rose tree zipper
  supersedes → Term-level zipper (lang/lambda/zipper/)
  supersedes → zipper-gen codegen plan (TODO.md §11, old)
```

## Why Term-Level Zipper Is Superseded

The Term zipper (TermCtx with 11 hand-written variants) was the natural Huet zipper for lambda calculus. But ProjNode[T] carries `kind: T` at every node.

Every feature attributed to the Term zipper works through ProjNode:

| Feature | Term zipper | ProjNode zipper |
|---------|-------------|-----------------|
| Navigation | go_up/down/left/right on Term | Same ops on ProjNode (uniform children) |
| NodeId access | Bridge: DFS → path → move → DFS back | Direct: focus.id() |
| available_actions | match z.focus { Lam(..) => ... } | match focus.kind { Lam(..) => ... } |
| PositionRole | match z.path { CtxAppFunc(..) => ... } | match (ctx.parent_kind, ctx.index) |
| Scope at cursor | Not supported (separate resolve_binder call) | ScopeProvider trait, maintained incrementally |
| plug / to_root | Reconstruct Term from context | go_up puts focus back in children array |
| Performance | O(n) per move (transient, rebuilt each time) | O(1) per move (persistent) |

## The "Infrastructure Not Yet Used" Concern

The Term zipper was built 2026-03-28 as infrastructure for deferred features:
- Structural undo (EditAction inversion)
- Collaborative structural editing (Grove-style conflict resolution)
- Refactoring (ExtractToLet, Inline, Rename)
- Type-aware hole filling

**Key finding:** None of these fundamentally require a Term-level zipper. They need:
1. Language-specific action types (EditAction enum — just data, not zipper)
2. Language-specific validity checks (pattern match on `focus.kind : T`)
3. Language-specific position roles (derive from `ctx.parent_kind + ctx.index`)
4. `plug` for tree reconstruction — but Canopy is text-first (edits go through CRDT, not direct AST mutation)

## Why Zipper-Gen Is Superseded

zipper-gen was planned to generate TermCtx variants automatically from AST definitions. But:

1. ProjNode is a rose tree — ONE context type for ALL languages
2. OrderTree is a B-tree — ONE context type for ALL payloads
3. Languages that don't need complex structural editing (JSON, Markdown) need no Term zipper at all
4. For languages that do (Lambda), ProjNode's `kind: T` provides the same AST access

## Proof in the Codebase

OrderTree already has a generic zipper (`Cursor[T]` + `PathFrame[T]`) that works without codegen. Same principle as ProjNode. Two independent confirmations of the theory.

## What's Preserved

- EditAction, TreeEditOp, PositionRole — these are language-specific DATA, not zipper operations
- Scope resolution (resolve_binder, find_usages) — consumed by the annotation layer
- The "NodeId is the cursor" principle — still true, now with direct access via focus.id()
