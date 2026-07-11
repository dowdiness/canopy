# Design Concerns

Future considerations and open problems for the incremental hylomorphism pipeline.

---

## AST Node Identity

**Context:** The semantic analysis layer (boundary ③: AST → Typed AST) needs stable node identity to efficiently track dependencies via `@incr` memos. The choice of node identity scheme affects incremental recomputation performance.

**Current state:** `Term` has no built-in node IDs. `TermDotNode` assigns pre-order traversal indices for visualization, and `SyntaxNode` uses text spans `(start, end)` for CST-level identity.

**Approaches:**

| Approach | Used by | Pros | Cons |
|----------|---------|------|------|
| **Arena index** | rust-analyzer, Salsa | Fast lookup, cache-friendly, stable within a revision | Need the arena to resolve |
| **Text span** | loom's `SyntaxNode` | No extra storage, naturally unique | Positions shift on edit |
| **Path from root** | Some projectional editors | Stable under edits elsewhere | Expensive to compute, brittle on structural changes |
| **Content hash** (hash-consing) | Unison language | Identical subtrees share identity — perfect for incremental reuse | Expensive, alpha-equivalence is tricky |
| **Pre-order counter** | Simple visualizers | Trivial to implement | Unstable — any tree change renumbers everything |

**Recommendation:** Arena-based interning (what Salsa/rust-analyzer does). Each AST node gets an `InternId` that's stable across revisions when content hasn't changed. This maps cleanly to `@incr`'s `Memo` model: a `Memo` keyed by `InternId` only recomputes when that node actually changed, not when an unrelated edit shifted positions.

loom's `CstNode` is already position-independent and structurally shareable — the semantic layer should intern `Term` nodes into an arena and let `@incr` memos track dependencies by those interned IDs.

**Status:** Deferred. Prototypes may use pre-order traversal indices as a placeholder.
