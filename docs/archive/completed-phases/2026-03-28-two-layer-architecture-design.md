# Two-Layer Architecture for Term

**Date:** 2026-03-28
**Status:** Complete

## What We're Building

A Finally Tagless layer (`TermSym` trait + `replay` function) on top of the existing `Term` enum. This is the Two-Layer Architecture: the concrete enum stays for structural operations; the tagless trait provides an open set of interpretations that can be added without touching existing code.

Primary trigger: the `feat/egraph-lambda-evaluator` branch in `loom/` should implement `TermSym` rather than pattern-matching `Term`, so it lands without adding another exhaustive match site.

Secondary goal: establish the pattern for future language implementations (Markdown, block editor).

## Background: The Problem

`Term` has 10 variants and ~11 exhaustive match sites across the codebase. Adding a new variant (e.g., `LetRec`) currently requires touching all of them. Adding a new semantic pass (e.g., type checker, e-graph evaluator) requires writing another exhaustive match.

The `TermSym` trait solves the operation axis: new semantic passes implement `TermSym` without touching `Term`. The `replay` function localises the data axis: adding a new variant only requires updating `replay` — all existing `TermSym` implementations are untouched (the compiler enforces this via missing method errors).

## Approach: Co-locate in `ast` Package

`TermSym`, `replay`, and `Pretty` live in a new file `loom/examples/lambda/src/ast/sym.mbt`, in the same `@ast` package as `Term`. No new packages.

Downstream packages (e-graph evaluator, projection, future languages) import `@ast` and implement `TermSym` for their own interpretation types.

## Design

### `TermSym` Trait

Defined in `loom/examples/lambda/src/ast/sym.mbt`:

```moonbit
pub(open) trait TermSym {
  int_lit(Int) -> Self
  var(VarName) -> Self
  lam(VarName, Self) -> Self
  app(Self, Self) -> Self
  bop(Bop, Self, Self) -> Self
  if_then_else(Self, Self, Self) -> Self
  module(Array[(VarName, Self)], Self) -> Self
  unit() -> Self
  unbound(VarName) -> Self
  error_term(String) -> Self
}
```

Leaf constructors (`int_lit`, `var`, `unit`, `unbound`, `error_term`) take no `Self` input and are called as `T::method(args)`. Branch constructors (`lam`, `app`, etc.) receive `Self` inputs from recursive `replay` calls — no phantom receiver needed. Callers use type ascription: `(replay(term) : Pretty)`.

`pub(open)` is required so downstream packages (e-graph evaluator, future language impls) can implement the trait. A `pub` trait is closed — only the defining package can implement it.

### `Term : TermSym` Implementation

`Term` is the identity interpretation — constructing a `Term` via `TermSym` returns a `Term`:

```moonbit
impl TermSym for Term with int_lit(n) { Int(n) }
impl TermSym for Term with var(x) { Var(x) }
impl TermSym for Term with lam(x, body) { Lam(x, body) }
impl TermSym for Term with app(f, a) { App(f, a) }
impl TermSym for Term with bop(op, l, r) { Bop(op, l, r) }
impl TermSym for Term with if_then_else(c, t, e) { If(c, t, e) }
impl TermSym for Term with module(defs, body) { Module(defs, body) }
impl TermSym for Term with unit() { Unit }
impl TermSym for Term with unbound(x) { Unbound(x) }
impl TermSym for Term with error_term(msg) { Error(msg) }
```

### `replay` — The Hinge

The single function that bridges the two layers. This is the only exhaustive `Term` match that needs updating when a new variant is added:

```moonbit
pub fn[T : TermSym] replay(term : Term) -> T {
  match term {
    Int(n) => T::int_lit(n)
    Var(x) => T::var(x)
    Lam(x, body) => T::lam(x, replay(body))
    App(f, a) => T::app(replay(f), replay(a))
    Bop(op, l, r) => T::bop(op, replay(l), replay(r))
    If(c, t, e) => T::if_then_else(replay(c), replay(t), replay(e))
    Module(defs, body) =>
      T::module(defs.map(fn(d) { (d.0, replay(d.1)) }), replay(body))
    Unit => T::unit()
    Unbound(x) => T::unbound(x)
    Error(msg) => T::error_term(msg)
  }
}
```

### `Pretty` — Migrated `print_term`

`Pretty` is the first `TermSym` implementation and the migration path for `print_term`:

```moonbit
pub(all) struct Pretty { repr : String }  // pub(all) exposes the repr field

impl TermSym for Pretty with int_lit(n) { { repr: n.to_string() } }
impl TermSym for Pretty with var(x) { { repr: x } }
impl TermSym for Pretty with lam(x, body) { { repr: "(λ\{x}. \{body.repr})" } }
impl TermSym for Pretty with app(f, a) { { repr: "(\{f.repr} \{a.repr})" } }
impl TermSym for Pretty with bop(op, l, r) {
  let sym = match op { Plus => "+", Minus => "-" }
  { repr: "(\{l.repr} \{sym} \{r.repr})" }
}
impl TermSym for Pretty with if_then_else(c, t, e) {
  { repr: "if \{c.repr} then \{t.repr} else \{e.repr}" }
}
impl TermSym for Pretty with module(defs, body) {
  let parts = defs.map(fn(d) { "let \{d.0} = \{d.1.repr}" })
  parts.push(body.repr)
  { repr: parts.join("\n") }
}
impl TermSym for Pretty with unit() { { repr: "()" } }
impl TermSym for Pretty with unbound(x) { { repr: "<unbound: \{x}>" } }
impl TermSym for Pretty with error_term(msg) { { repr: "<error: \{msg}>" } }
```

`print_term` in `ast.mbt` becomes a one-liner wrapper — zero call-site changes:

```moonbit
pub fn print_term(term : Term) -> String {
  (replay(term) : Pretty).repr
}
```

### E-graph Evaluator Integration

The `feat/egraph-lambda-evaluator` branch implements `TermSym` for a local builder type, not `EGraph` directly. The existing e-graph API is mutable (`add(node) -> Id` over a private graph) — `Self` must be the builder result, not the graph itself. A wrapper type handles this:

```moonbit
// In the e-graph evaluator package — adapts mutable EGraph to TermSym
priv struct EGraphBuilder { graph: EGraph; root: Id }

impl TermSym for EGraphBuilder with lam(x, body) {
  let id = body.graph.add(ENode::Lam(x, body.root))
  { graph: body.graph, root: id }
}
// etc.

// Building from a Term:
let builder : EGraphBuilder = replay(term)
let graph = builder.graph
```

The orphan rule applies: if `EGraph` is defined in a foreign package, `EGraphBuilder` must be a local newtype wrapper (same pattern as `TermDotNode` in `dot_node.mbt`).

Benefits:
- No `Term` pattern matching in the e-graph package
- New variants are compile-enforced: missing `TermSym` method = compile error
- E-graph package stays decoupled from the concrete variant set

## What Changes

| File | Change |
|------|--------|
| `loom/examples/lambda/src/ast/sym.mbt` | **New.** `TermSym`, `Term : TermSym`, `replay`, `Pretty` |
| `loom/examples/lambda/src/ast/ast.mbt` | `print_term` body replaced with `(replay(term) : Pretty).repr` |
| E-graph evaluator (feature branch) | Replace `Term` match with `TermSym` impl |

## What Does Not Change

- `free_vars` — env-threading makes tagless encoding awkward; direct match stays
- `scope.mbt` — structural queries on specific variants; direct match stays
- `traits_term.mbt` — already the right pattern (operation-axis via `TreeNode`, `Renderable`)
- All edit handlers — generic over `T`, never match `Term` variants directly
- All call sites of `print_term` — wrapper preserves the existing API

## Testing

Existing `print_term` tests become free regression tests for `Pretty` and `replay`.

New tests in `sym_test.mbt`:

1. **Roundtrip:** `(replay(term) : Term) == term` for each variant
2. **Two interpretations:** same `Term` replayed as both `Pretty` and `Term`, verify both outputs
3. **All variants:** one test exercising every constructor through `replay`

E-graph evaluator tests on the feature branch serve as the integration test for `TermSym` in practice.

## Adding a New Variant Later

When `LetRec(VarName, Term, Term)` is added:

1. Add to `Term` enum — compiler flags all exhaustive matches
2. Add `let_rec(VarName, Self, Self) -> Self` to `TermSym` — compiler flags all `TermSym` impls
3. Update `replay` — one new arm
4. Update `Pretty` — one new impl
5. Update `free_vars` and scope functions in `projection/` — unavoidable
6. Update `resolve.mbt` — name resolution walks `Term` exhaustively
7. Update `dot_node.mbt` — DOT renderer has its own exhaustive `Term` match
8. Update `print_term` tests — unavoidable

Operations that stay untouched: `TreeNode`, `Renderable`, all edit handlers, e-graph evaluator (gets new method via compile error), future type checker.
