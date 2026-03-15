# Projection Layer Incremental Updates

**Date:** 2026-03-15
**Status:** Approved

## Problem

Every edit triggers four O(n) passes in the projection pipeline:

1. `to_proj_node()` — full syntax tree → ProjNode conversion with right-fold
2. `reconcile_ast()` — O(n*m) LCS matching to preserve node IDs
3. `register_node_tree()` — flat registry rebuild
4. `SourceMap::from_ast()` — position mapping rebuild

For 80 LetDefs, a single-character edit in one LetDef rebuilds all 80 ProjNodes, reconciles all 80, rebuilds the registry, and rebuilds the source map.

## Research findings

### LetDef CST nodes are NOT reused by the incremental parser

`parse_let_item` uses `ctx.start_at(mark, LetDef)` — the raw mark/start_at pattern, not `ctx.node(kind, body)` which is the reuse-aware combinator. Top-level LetDef nodes are always re-parsed from scratch on every incremental edit.

However, **`NodeInterner` deduplicates them**. Two structurally identical LetDefs (same tokens, same children) built in different parse runs are interned to the same canonical CstNode. So `physical_equal(old_letdef, new_letdef)` correctly returns `true` for unchanged LetDefs, even though they were re-parsed.

### Eliminating reconciliation breaks structural edits

For **content-only edits** (typing within a LetDef), positional matching works: each LetDef stays at the same index, `physical_equal` correctly identifies unchanged nodes.

For **structural edits** (inserting/deleting a LetDef), positional matching fails:

```
Before: [LetDef(a), LetDef(b), LetDef(c), Expr]
After:  [LetDef(a), LetDef(NEW), LetDef(b), LetDef(c), Expr]
```

Without LCS, positional matching assigns:
- Position 1: old LetDef(b)'s ID → new LetDef(NEW) — wrong
- Position 2: old LetDef(c)'s ID → new LetDef(b) — wrong

The LCS reconciler correctly aligns old LetDef(b) with new LetDef(b) despite the shift. Without it, every LetDef after an insertion gets the wrong ID, breaking cursor tracking, selection state, and `tree_edit_bridge`'s structural editing.

### Conclusion: keep reconciliation, make it fast via physical_equal

Feed the reconciler mostly-identical trees. When 79/80 ProjNode children are literally the same object, reconciliation is trivially fast — LCS on runs of equal elements degenerates to O(n) identity comparisons.

## Solution

Use `physical_equal` on CstNode children of SourceFile to detect unchanged LetDefs. Reuse old ProjNodes for unchanged LetDefs, only rebuild the changed one. Optimize the downstream pipeline to skip identical subtrees.

### Phase 1: `to_proj_node` incremental

**Current:** `to_proj_node(syntax_root, counter)` traverses ALL children, builds fresh ProjNodes for every LetDef, right-folds into nested Let terms.

**Change:** Accept an optional previous ProjNode tree. For each SourceFile child:
- Compare old and new CstNode via `physical_equal`
- If same: reuse the old ProjNode (and its ID, children, everything)
- If different: build a new ProjNode via `syntax_to_proj_node`
- Right-fold as before, but with reused ProjNodes for unchanged LetDefs

This makes `to_proj_node` O(n) pointer comparisons + O(changed_subtree) actual work, instead of O(total_nodes) tree traversal.

### Phase 2: `reconcile_ast` optimization

**Current:** `reconcile_children` builds an O(old*new) LCS DP table on every call.

**Change:** Before LCS, scan both children arrays for the first mismatch. If only one position differs (content edit), reconcile only that child — skip LCS entirely. If multiple positions differ (structural edit), fall back to LCS on the mismatched region only.

For content edits: O(n) scan + O(1) reconcile.
For structural edits: O(n) scan + O(k) LCS on k mismatched children.

### Phase 3: `register_node_tree` and `SourceMap` patch

**Current:** Both do O(n) full tree traversals on every edit.

**Change:** Keep full rebuilds for now. At O(n) with n=80, they take microseconds. Optimize only if profiling shows they matter.

## Data flow (after optimization)

```
Edit → incremental parse → new CstNode tree
                              ↓
to_proj_node(new_cst, prev_proj)
  ├─ For each SourceFile child:
  │   physical_equal(old_cst_child, new_cst_child)?
  │     → true:  reuse old ProjNode
  │     → false: build new ProjNode via syntax_to_proj_node
  ├─ Right-fold reused + new ProjNodes
  └─ Return mostly-reused ProjNode tree
                              ↓
reconcile_ast(prev_proj, new_proj)
  ├─ Scan children: physical_equal fast path
  ├─ Only reconcile changed positions
  └─ Return reconciled tree (mostly same IDs)
                              ↓
register_node_tree + SourceMap (full rebuild, fast)
```

## API changes

### `to_proj_node` (projection/proj_node.mbt)

Add optional parameter for previous parse state:

```moonbit
pub fn to_proj_node(
  root : @seam.SyntaxNode,
  counter : Ref[Int],
  prev_root? : @seam.SyntaxNode? = None,
  prev_proj? : ProjNode? = None,
) -> ProjNode
```

When `prev_root` and `prev_proj` are provided, use `physical_equal` on CstNode children to reuse ProjNodes.

### `reconcile_children` (projection/reconcile_ast.mbt)

Optimize to skip `physical_equal` matches:

```moonbit
fn reconcile_children(old, new, counter) -> Array[ProjNode] {
  // Fast path: scan for first mismatch
  // If all match: return old array
  // If one mismatch: reconcile only that child
  // If multiple: fall back to LCS on mismatched region
}
```

### `projection_memo.mbt` (editor/projection_memo.mbt)

Pass previous SyntaxNode and ProjNode to `to_proj_node`:

```moonbit
let new_proj = @proj.to_proj_node(
  syntax_root,
  counter,
  prev_root=prev_syntax_ref.val,
  prev_proj=prev_proj_ref.val,
)
```

## Expected outcome

- Content edits (common): O(n) pointer comparisons + O(1) actual work
- Structural edits (rare): O(n) pointer comparisons + O(k) reconciliation
- Registry/source map: unchanged (O(n), but fast at n=80)

## Non-goals

- Making registry/source map incremental (optimize later if needed)
- Changing the ProjNode data structure
- Changing the incr/Signal/Memo infrastructure
