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
- Audit loom internal code (`viz/`, `cst_fold`, `tree_diff`) and `SyntaxNode::cst_node()` usage for access patterns that would need RepeatGroup-awareness in Phase 2

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

When the parser processes a repeated region that produces >N children (e.g., N=8), automatically group them into a balanced binary tree of `RepeatGroup` nodes.

**Key challenge:** `build_tree` only sees a flat `ParseEvent` stream — it has no grammar-level knowledge of which children form a repetition. Marking "repeated node kinds" on `LanguageSpec` is insufficient because the same kind can appear in non-repetition contexts (e.g., `AppExpr` is a flat n-ary node, `BinaryExpr` mixes operand nodes with operator tokens). The design must identify repetition *sites*, not just repeated kinds.

Options:
- (a) **Repetition-region events** — add `StartRepeat`/`FinishRepeat` events to `ParseEvent`. The parser emits these around repeated child runs, and `build_tree` groups children within these markers into balanced `RepeatGroup` nodes. This is explicit and handles mixed child/token layouts correctly.
- (b) Grammar author marks repeated node kinds on `LanguageSpec` — fragile, can't distinguish repetition sites from non-repetition uses of the same kind.
- (c) **`ctx.repeat()` combinator** — a grammar-level API that emits the repetition-region events internally. Clean grammar authoring but changes the API.

Option (a) is recommended, optionally paired with (c) as syntactic sugar. The event stream is the right layer to encode repetition boundaries because `build_tree` already consumes events. Option (b) is rejected — `build_tree` lacks the context to infer repetition sites from kind information alone.

**Raw-CST compatibility:** `SyntaxNode::cst_node()` still exposes the raw `CstNode`, and `tree_diff` walks raw `CstNode.children` directly. Consumers using these raw APIs will observe `RepeatGroup` nodes. Phase 0 should include auditing `cst_node()` usage and `tree_diff` for RepeatGroup-awareness. The "zero consumer API changes" claim applies to `SyntaxNode`-based consumers only; raw-CST consumers may need updates.

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
2. Re-tokenize only that range — requires a new public subrange tokenization API. The existing `TokenBuffer::update` is a whole-buffer mutation API; the private `tokenize_range_impl` helper exists but is not exposed. Phase 3 needs a first-class "tokenize this byte range" entrypoint.
3. Parse using a per-kind parse function — requires the grammar to provide per-kind entry points (e.g., `parse_let_item` for `LetDef`). Today only `spec.parse_root` exists as a public parse entrypoint. A new `Grammar` field like `parse_kind : (K, ParserContext) -> Unit` is needed.
4. Translate diagnostic byte offsets from local (sub-range) to global (document) positions
5. Construct new `CstNode` from the isolated parse result and splice into the spine

**Boundary handling:** Trivia ownership at block edges is grammar-specific, not a general CST property. In the lambda grammar, `LetDef` starts before the `let` keyword (so same-line leading spaces are inside the node), but delimiter newlines are emitted by the parent `SourceFile` loop after `parse_let_item` returns. The block reparse contract must specify:
- Which trivia belongs to the block vs the parent
- Whether the block's byte range includes or excludes boundary trivia
- How the isolated parse context handles trivia at the start/end of the range

This requires an explicit trivia-ownership contract per reparseable kind, making block reparse grammar-specific by nature.

**Expected impact:** Single-definition edits become O(definition_size), independent of document size. For a `let x = 0` → `let x = 1` edit in a 320-let file: reparse ~12 bytes instead of considering 320 siblings.

**Risk:** High. Requires grammar authors to correctly identify reparseable node kinds, provide per-kind parse entry points, and define trivia-ownership contracts. Incorrect marking can produce invalid parses. The default (`fn(_) { false }`) is safe — block reparse is opt-in. Multiple new APIs needed (subrange tokenization, per-kind parsing) before this phase is implementable.

**Recommendation:** Defer Phase 3 until after Phase 2 proves out. Phase 1 + Phase 2 already address the flat-list case that motivated this design. Phase 3 requires new parser and lexer APIs that should be designed after the balanced-tree architecture is stable.

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

### Performance targets

| Metric | Current | Target |
|--------|---------|--------|
| 80 lets — incremental single edit | 315 µs (2.1x slower than batch) | Within 1.2x of batch (~175 µs) |
| 320 lets — incremental single edit | 1.37 ms (2.2x slower than batch) | Within 1.2x of batch (~750 µs) |
| 80 lets — 50-edit session | 10.21 ms (1.3x slower) | Within 1.1x of batch (~9 ms) |
| 320 lets — 50-edit session | 43.49 ms (1.3x slower) | Within 1.1x of batch (~38 ms) |
| Deep tree (20 nested lets) — single edit | baseline TBD | No regression from Phase 1 threshold |

Note: targets are benchmark thresholds, not hard gates. Exact crossover depends on hardware and compiler version.

### Observability

- `reuse_count` per incremental parse — track how many nodes are reused vs reparsed to distinguish Phase 1 and Phase 2 effects
- `try_reuse_calls` / `try_reuse_hits` from `PerfStats` — verify Phase 1 reduces call count, Phase 2 increases hit rate

### Correctness

- All existing incremental parser tests pass
- CST equality: incremental parse produces identical `CstNode` structure as full reparse (modulo `RepeatGroup` transparency)
- Diagnostic equality: incremental parse produces identical diagnostics (offsets, messages) as full reparse
- `SyntaxNode`-based consumer API: zero changes required

## Future: Decoupling Path

Phase 0 (enforce SyntaxNode boundary) is the prerequisite for future loom/seam decoupling. Once all consumers use `SyntaxNode::children()` and `CstNode.children` is private:

- `SyntaxNode`'s flattening logic becomes the natural abstraction boundary
- Loom could introduce an `InternalNode` behind `CstNode` without changing any consumer
- seam stays a clean, independent CST library usable without loom

This is not part of the current work — just a design choice preserved for the future.

## Implementation Order

1. **Phase 0** — SyntaxNode boundary enforcement (prerequisite for Phase 2)
2. **Phase 1** — Size-threshold skip (smallest change, immediate benchmark impact)
3. **Phase 2** — Balanced repeat sequences with repetition-region events (structural change, biggest long-term impact)
4. **Phase 3** — Block reparse (deferred — requires new parser/lexer APIs, design after Phase 2 stabilizes)

Phases 0–2 are independently valuable and can ship separately. Phase 3 is deferred pending Phase 2 results and API design for subrange tokenization and per-kind parsing.

## References

- [Wagner — Practical Algorithms for Incremental Software Development Environments (1998)](https://www2.eecs.berkeley.edu/Pubs/TechRpts/1998/5885.html)
- [Lezer blog post — balanced subtrees from repetitions](https://marijnhaverbeke.nl/blog/lezer.html)
- [rust-analyzer — block-level reparsing](https://github.com/rust-lang/rust-analyzer/blob/master/crates/syntax/src/parsing/reparsing.rs)
- [Dubroy & Warth — Incremental Packrat Parsing (2017)](https://ohmjs.org/pubs/sle2017/incremental-packrat-parsing.pdf)
- `loom/docs/performance/incremental-overhead.md` — internal profiling analysis
- `docs/performance/2026-03-21-full-pipeline-benchmarks.md` — current benchmark baseline
