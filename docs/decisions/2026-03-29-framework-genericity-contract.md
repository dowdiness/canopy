# ADR: Framework Genericity Contract (TestExpr Proof)

**Date:** 2026-03-29
**Status:** Accepted

## tl;dr

- Context: `framework/core/` contains language-agnostic projection nodes, source maps, and reconciliation. Language-specific builders and editors live in other packages. After extraction (Phases 1–4), a grep confirms zero `@ast` imports — but static analysis doesn't prove runtime correctness.
- Decision: Add proof tests using a non-lambda `TestExpr` AST type in `framework/core/test_expr_wbtest.mbt`.
- Rationale: The project plans JSON and Markdown editors sharing `framework/core/`. The tests guard the core primitives against hidden coupling to lambda's `@ast.Term`.
- Consequences: These tests catch regressions in `framework/core/` genericity. They do not cover higher layers (`projection/`, `editor/`).

## Problem

After the framework extraction, `framework/core/` has zero `@ast` imports — verified by grep. But "no imports" doesn't prove "no implicit assumptions." The reconciliation algorithm, source map builder, and other generic functions could contain logic that only works correctly for ASTs shaped like lambda's `Term`.

We need a stronger guarantee before building additional language editors on this foundation.

## Decision

Add 7 whitebox tests that instantiate `framework/core/` primitives with a deliberately different AST type:

```moonbit
priv enum TestExpr {
  Leaf(String)
  Branch(String, Array[TestExpr])
}
```

This type has different structure than `@ast.Term` (variable-arity children, no parametric fields like `VarName`). The tests exercise:

| Test | What it verifies |
|---|---|
| ProjNode construction | `ProjNode::new` and field access work with any T |
| SourceMap::from_ast | Source map builds correctly for non-lambda trees |
| reconcile (preserve IDs) | Uses `TreeNode::same_kind`, not Term-specific patterns |
| reconcile (fresh IDs) | Kind mismatch detection is generic |
| assign_fresh_ids | Post-order renumbering works for arbitrary trees |
| get_node_in_tree | Node lookup is generic |
| ToJson | `ToJson for ProjNode[T]` compiles with any `T : ToJson` |

**Scope:** These tests cover `framework/core/` primitives only. They do not exercise `projection/` (TreeEditorState, tree refresh), `editor/` (SyncEditor, CRDT sync, undo), or language-specific builders. Those layers are generic by type parameter but are not tested with `TestExpr` here.

**Limitations:** The tests do not cover `reconcile_children` with multi-child LCS matching, `SourceMap` query/update methods, token spans, or `SourceMap` JSON serialization. The zero-import guarantee is enforced separately by grep (or a CI check), not by these tests.

## Why now

The project's near-term roadmap includes:

1. **JSON editor** — loom already has a JSON grammar (`loom/examples/json/`). Building a JSON projectional editor by hand validates the framework with a real second language.
2. **Markdown editor** — for the block-based document editor.
3. **loomgen** — code generator for per-language boilerplate. Will be built after the JSON editor provides a second real example.

All three depend on `framework/core/` being generic. The TestExpr proof guards this property.

## When these tests fail

Run: `moon test -p dowdiness/canopy/framework/core -f test_expr_wbtest.mbt`

| Failing test | Look at |
|---|---|
| ProjNode, assign_fresh_ids, get_node_in_tree | `framework/core/proj_node.mbt` |
| SourceMap::from_ast | `framework/core/source_map.mbt` |
| reconcile (preserve/fresh IDs) | `framework/core/reconcile.mbt` |
| ToJson | `framework/core/proj_node_json.mbt` |

The fix should be in `framework/core/`, not in `lang/lambda/`. If the test broke because someone added `@ast`-specific logic to a generic function, make the function generic again. Do not delete the tests.

## What you build per language

`framework/core/` provides reconciliation, source mapping, and node identity. Per language, you still need:

1. A loom `Grammar` (parser)
2. A `syntax_to_proj_node` builder (CST → ProjNode)
3. `TreeNode + Renderable` trait implementations
4. Text edit handlers (structural edits as text changes)

Higher layers (`SyncEditor[T]`, `TreeEditorState[T]`, `EphemeralHub`) are generic by type parameter and expected to work with any language — but that is not yet tested by these proof tests.
