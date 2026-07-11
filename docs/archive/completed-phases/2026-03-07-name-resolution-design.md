# Lambda Calculus Name Resolution (Prototype)

**Date:** 2026-03-07
**Status:** Complete

## Overview

Complete boundary ③ of the incremental hylomorphism pipeline with a minimal semantic analysis: resolve every `Var(x)` in a `Term` as **bound** (with binder depth) or **free**. This is a throwaway prototype to demonstrate the full pipeline end-to-end.

## Types

```moonbit
// In loom/examples/lambda/src/
pub enum VarStatus {
  Bound(depth~: Int)   // bound by a λ or let, depth = distance to binder
  Free                 // not in any enclosing scope
}

pub struct Resolution {
  // keyed by pre-order traversal index (same as TermDotNode IDs)
  vars : Map[Int, VarStatus]
}
```

## Algorithm

Walk `Term` with an environment `Map[String, Int]` (name → current depth):
- `Lam(x, body)` → extend env with `x` at depth+1, recurse
- `Let(x, val, body)` → recurse into `val` (x not in scope), extend env with `x`, recurse into `body`
- `Var(x)` → lookup in env → record `Bound(depth)` or `Free`
- Others → recurse, incrementing the pre-order counter

~50 lines of MoonBit. One file: `resolve.mbt` + tests in `resolve_wbtest.mbt`.

## Visualization

Enrich `TermDotNode` to accept an optional `Resolution` and color nodes:
- Bound vars → green (`#6a9955`)
- Free vars → red (`#f44747`)

Add `term_to_dot_resolved(term, resolution) -> String` alongside existing `term_to_dot`.

## Integration

Add to `SyncEditor`:
```moonbit
pub fn get_resolution(self) -> Resolution {
  resolve(self.get_ast())
}
```

Expose via JS FFI for the web frontend.

## Files Changed

| File | Change |
|------|--------|
| `loom/examples/lambda/src/resolve.mbt` | **New** — `resolve()` + `VarStatus` + `Resolution` |
| `loom/examples/lambda/src/resolve_wbtest.mbt` | **New** — tests |
| `loom/examples/lambda/src/dot_node.mbt` | Add `term_to_dot_resolved()` with colors |
| `editor/sync_editor.mbt` | Add `get_resolution()` |
| `cmd/crdt.mbt` (JS FFI) | Expose `get_resolution_json()` |

## Out of Scope

- `@incr` memoization (just recompute each call)
- Type inference
- Shadowing warnings
- Arena-based node IDs (see `design-concerns.md`)

## Future

Once the prototype validates the pipeline, replace with a proper implementation:
- Arena-based node identity (see [Design Concerns](../design/design-concerns.md))
- `@incr` memoization for incremental recomputation
- Type inference and richer diagnostics
