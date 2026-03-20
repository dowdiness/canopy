# Incremental Parser Optimization — Design

**Date:** 2026-03-21
**Status:** Draft
**Scope:** loom (parser framework) + seam (CST library)

---

## Problem

Loom's incremental parser is **2x slower than batch** for flat let-chains (80–320 siblings). The per-node reuse protocol (cursor seek, trailing context check, error span collection, position advance) costs more than reparsing cheap nodes.

**Current benchmarks (2026-03-21):**

| Benchmark | Incremental | Full reparse | Ratio |
|-----------|------------|-------------|-------|
| 80 lets — edit-only | 315 µs | 147 µs | 2.1x slower |
| 320 lets — edit-only | 1.37 ms | 623 µs | 2.2x slower |
| 80 lets — 50-edit session | 10.21 ms | 8.14 ms | 1.3x slower |
| 320 lets — 50-edit session | 43.49 ms | 34.57 ms | 1.3x slower |

**Root causes:**

1. `try_reuse()` is called for every grammar node — even 4-token `LetDef` nodes where reuse overhead exceeds reparse cost
2. Flat sibling lists require O(n) per-node reuse checks — no way to skip undamaged regions in bulk
3. No fast path for edits contained within a single reparseable block

## Approach

Evolve seam directly (no internal tree layer), design toward future decoupling. Three composable optimizations, preceded by a boundary enforcement phase.

**Design rule:** All optimizations go through `CstNode` + `SyntaxNode`. Consumers must use `SyntaxNode::children()` — never `CstNode.children` directly. This ensures internal tree changes (balanced groups) are invisible to consumers and enables future decoupling.

## Phase 0: Enforce SyntaxNode Boundary

**Goal:** Ensure no consumer outside loom/seam accesses `CstNode.children` directly.

**Current state:** Direct `CstNode.children` access outside loom/seam internals is limited to:
- `loom/examples/lambda/src/benchmarks/profiling_benchmark.mbt` — benchmark code iterating `cst.children`
- `loom/examples/lambda/src/cst_tree_test.mbt` — test code
- `loom/loom/src/viz/` — dot graph rendering

The projection layer already uses `ProjNode.children` (a local type) and `SyntaxNode::children()`. The consumer code (`term_convert.mbt`) correctly uses `node.children()` (the `SyntaxNode` method). The migration surface is smaller than initially expected — primarily benchmark and test code.

**Work:**
- Migrate benchmark and test files to use `SyntaxNode::children()` or `SyntaxNode::all_children()`
- Consider making `CstNode.children` private (pub(readonly) → private), exposing only through `SyntaxNode`
- Audit loom internal code (`viz/`, `cst_fold`) for access patterns that would need RepeatGroup-awareness

**Risk:** Low. Migration is mechanical and limited in scope.

**Validation:** `grep -r "\.children" --include="*.mbt"` outside loom/seam internals shows zero direct `CstNode.children` access.

## Phase 1: Size-Threshold Reuse Skip

**Goal:** Eliminate per-node reuse overhead for cheap nodes.

**Change:** In `ReuseCursor::try_reuse()`, if the candidate node's `text_len` is below a threshold (e.g., 64 bytes), return `None` immediately — skip the full reuse protocol and let the parser reparse it from scratch.

```
// In ReuseCursor::try_reuse():
// Early exit for small nodes — reparse is cheaper than reuse protocol
if node.text_len < REUSE_SIZE_THRESHOLD {
    return None
}
```

**Why this works:** Each `let x0 = 0\n` is ~12 bytes. The reuse protocol (seek + 6 condition checks + emit + advance) costs more than reparsing 4 tokens. Skipping reuse for small nodes eliminates the overhead where it can't pay off, while preserving reuse for large subtrees where it does.

**Threshold tuning:** Start with 64 bytes. Benchmark at 32, 64, 128 to find the crossover point. The threshold should be configurable via `LanguageSpec` for grammar-specific tuning.

**Expected impact:** Directly addresses the flat let-chain slowdown. With 80 LetDefs below threshold, the parser skips 79 reuse attempts and reparses them directly — similar cost to batch, with the single damaged LetDef also reparsed.

**Risk:** Low. Only affects which nodes are reused, not correctness. Worst case: threshold too high means we reparse nodes we could have reused (slightly slower for deep trees). Benchmark-driven tuning mitigates this.

**Validation:**
- `let-chain: 80 lets - edit-only` faster than full reparse
- `let-chain: 320 lets - edit-only` faster than full reparse
- All existing incremental parser tests pass

## Phase 2: Balanced Repeat Sequences

**Goal:** Reduce reuse checks from O(n) to O(log n) for repetition rules.

**Inspiration:** Lezer (CodeMirror 6) and tree-sitter both use balanced trees for `*`/`+` repetitions. Lezer's author confirmed that a bug preventing balanced repeat nodes "ruined the efficiency of incremental parses."

**Changes:**

### seam: Add RepeatGroup node kind

A `RepeatGroup` is a transparent grouping node used internally for tree balancing. It has a distinguished `RawKind` that seam knows to flatten.

```
// CstNode with kind == REPEAT_GROUP_KIND
// is transparent — SyntaxNode::children() flattens it
```

### seam: SyntaxNode flattens RepeatGroup

`SyntaxNode::children()` recursively unwraps `RepeatGroup` nodes, yielding their contents inline. Consumers see a flat sibling list — the balanced structure is invisible.

```
// Tree structure:
//         SourceFile
//        /          \
//   RepeatGroup    RepeatGroup
//    /     \        /     \
// LetDef LetDef  LetDef LetDef

// SyntaxNode::children() yields:
// LetDef, LetDef, LetDef, LetDef  (flat)
```

### loom: Build balanced trees for repetitions

When the parser processes a `*`/`+` grammar rule that produces >N children (e.g., N=8), automatically group them into a balanced binary tree of `RepeatGroup` nodes during `build_tree`.

The `Grammar` struct needs a way to mark repetition rules. Options:
- (a) Grammar author marks repeated node kinds explicitly via a field on `Grammar` or `LanguageSpec`
- (b) Loom detects during `build_tree` when a node has many children of the same kind
- (c) The `ctx.node()` combinator gains a `ctx.repeat()` variant

Option (a) is recommended. Option (b) is fragile — `build_tree` operates on a flat event stream without grammar knowledge, risking false positives (non-repetition nodes with many same-kind children, e.g., argument lists) and false negatives (repetitions with alternating kinds like `LetDef Newline LetDef Newline`). Option (c) is also viable but changes the grammar authoring API. Option (a) is explicit, reliable, and the field addition to `LanguageSpec` is minimal.

### loom: ReuseCursor reuses RepeatGroup subtrees

`try_reuse()` already works on any `CstNode` — it checks kind, damage overlap, and context. `RepeatGroup` nodes are CstNodes, so they're reusable as-is. A single undamaged `RepeatGroup` containing 40 LetDefs gets reused as one unit.

**Expected impact:** A tail edit in 320 LetDefs touches ~9 balanced spine nodes instead of 320 siblings. Combined with Phase 1 (skip reuse for small leaf nodes), the parser reuses large groups and reparses only the damaged leaf — O(log n) total work.

**Risk:** Medium-high. Balanced tree construction adds complexity to `build_tree`. `SyntaxNode` flattening must be applied to all methods that iterate `cst.children`, not just `children()` — including `all_children()`, `nth_child()`, `children_from()`, `nodes_and_tokens()`, `find_at()`, `token_at_offset()`, `tight_span()`, and the `ToJson` impl. Offset calculation bugs during flattening are a likely failure mode. Thorough testing required.

**Note:** The first parse after enabling balanced grouping will produce a structurally different tree (different hash) from the previous flat parse. This means no reuse from the pre-balanced tree — a one-time full reparse cost on transition. Acceptable but worth noting.

**Validation:**
- `SyntaxNode::children()` returns identical results for balanced and unbalanced trees
- Incremental reuse count at 320 lets shows O(log n) reused nodes, not O(n)
- All existing consumer tests pass without modification

## Phase 3: Block Reparse

**Goal:** Fast path for edits contained within a single reparseable node.

**Change:** Add an optional field to the `Grammar` struct (or `LanguageSpec`):

```
is_reparseable : (K) -> Bool  // default: fn(_) { false }
```

When an edit falls entirely within a node whose kind is reparseable, loom:

1. Extracts the byte range of that node from the old tree
2. Re-tokenizes only that range
3. Reparses the node in isolation using the grammar rule for that kind
4. Splices the new `CstNode` into the old tree, replacing the old subtree

No cursor setup, no per-node reuse checks, no trailing context matching.

**Grammar author's role:** Mark node kinds that can be parsed independently. For lambda calculus: `LetDef` is reparseable (self-contained), `Expression` may not be (context-dependent on `allow_newline_application`).

**Splice mechanism:** Since `CstNode` is immutable, splicing means constructing new spine nodes via path copying — O(depth) allocations. Each ancestor from the replaced node to the root gets a new `CstNode` with updated `children`, `text_len`, `hash`, and `token_count`.

**Isolated parse mechanics:** For the sub-range reparse:
1. Create a new `ParserContext` scoped to the byte range of the reparseable node
2. Re-tokenize only that range (the existing `TokenBuffer::update` handles this)
3. Parse using the grammar rule for the node kind — requires the grammar to provide a per-kind parse function (e.g., `parse_let_item` for `LetDef`)
4. Translate diagnostic byte offsets from local (sub-range) to global (document) positions
5. Construct new `CstNode` from the isolated parse result and splice into the spine

**Boundary handling:** Trivia (whitespace, newlines) at the edges of the reparseable block belongs to the block's parent, not the block itself. The reparse must use the same trivia boundaries as the original parse. This is ensured by using the old node's exact byte range (which already includes leading trivia as stored in `CstNode`).

**Expected impact:** Single-definition edits become O(definition_size), independent of document size. For a `let x = 0` → `let x = 1` edit in a 320-let file: reparse ~12 bytes instead of considering 320 siblings.

**Risk:** Medium-high. Requires grammar authors to correctly identify reparseable node kinds. Incorrect marking can produce invalid parses. The default (`fn(_) { false }`) is safe — block reparse is opt-in. Additionally, the grammar must provide per-kind parse entry points, which is a new API requirement for grammars that opt into block reparse.

**Validation:**
- Block reparse produces identical CST to full incremental reparse
- Property tests: random edits within reparseable nodes yield same tree
- Benchmark: single-def edit at 320 lets is O(1) relative to document size

## Composition

All three optimizations compose:

1. **Block reparse** fires first — if the edit is within a reparseable block, skip everything else
2. **Balanced trees** reduce the number of nodes the cursor must consider
3. **Size-threshold skip** eliminates reuse overhead on remaining small nodes

```
Edit arrives
    │
    ├── Within reparseable block? ──yes──→ Block reparse (Phase 3)
    │
    └── no
        │
        Full incremental parse with:
        ├── Balanced RepeatGroups (Phase 2): O(log n) spine nodes
        └── Size-threshold skip (Phase 1): small nodes reparsed, not reuse-checked
```

## Success Criteria

| Metric | Current | Target |
|--------|---------|--------|
| 80 lets — incremental single edit | 315 µs (2.1x slower than batch) | Faster than batch (< 147 µs) |
| 320 lets — incremental single edit | 1.37 ms (2.2x slower than batch) | Faster than batch (< 623 µs) |
| Consumer API changes | — | Zero |
| Existing test suite | — | All pass |

## Future: Decoupling Path

Phase 0 (enforce SyntaxNode boundary) is the prerequisite for future loom/seam decoupling. Once all consumers use `SyntaxNode::children()` and `CstNode.children` is private:

- `SyntaxNode`'s flattening logic becomes the natural abstraction boundary
- Loom could introduce an `InternalNode` behind `CstNode` without changing any consumer
- seam stays a clean, independent CST library usable without loom

This is not part of the current work — just a design choice preserved for the future.

## Implementation Order

1. **Phase 0** — SyntaxNode boundary enforcement (prerequisite)
2. **Phase 1** — Size-threshold skip (smallest change, immediate benchmark impact)
3. **Phase 2** — Balanced repeat sequences (structural change, biggest long-term impact)
4. **Phase 3** — Block reparse (opt-in fast path, grammar trait extension)

Each phase is independently valuable and can ship separately.

## References

- [Wagner — Practical Algorithms for Incremental Software Development Environments (1998)](https://www2.eecs.berkeley.edu/Pubs/TechRpts/1998/5885.html)
- [Lezer blog post — balanced subtrees from repetitions](https://marijnhaverbeke.nl/blog/lezer.html)
- [rust-analyzer — block-level reparsing](https://github.com/rust-lang/rust-analyzer/blob/master/crates/syntax/src/parsing/reparsing.rs)
- [Dubroy & Warth — Incremental Packrat Parsing (2017)](https://ohmjs.org/pubs/sle2017/incremental-packrat-parsing.pdf)
- `loom/docs/performance/incremental-overhead.md` — internal profiling analysis
- `docs/performance/2026-03-21-full-pipeline-benchmarks.md` — current benchmark baseline
