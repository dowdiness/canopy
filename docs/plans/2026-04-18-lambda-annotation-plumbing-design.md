# Lambda Type-Annotation Plumbing (CST → TypedTerm)

**Status:** Design — ready for implementation plan
**Related TODO:** `docs/TODO.md` §23
**Predecessor PR:** #186 (shipped inline type diagnostics with empty annotation pipeline)

## Why

Today the lambda parser accepts `\x : Int. body` and emits a `TypeAnnot` CST node, but `term_convert.mbt` (CST → `@ast.Term`) drops it because `Term::Lam(VarName, Term)` has no slot for a type. `@typecheck.convert(Term) -> TypedTerm` therefore always emits `Lam(x, None, body)`, and `infer` reports "missing type annotation" on every unannotated lambda — including the five preset examples in `examples/web/index.html`, all of which fail typecheck.

Concrete surprise: a user who writes the documented syntax `\x : Int. x` still gets "missing type annotation". The annotation is silently discarded.

## Scope

In:
- `loom/examples/lambda/src/typecheck/convert.mbt` — new `convert_from_cst(SyntaxNode) -> TypedTerm`; retain existing `convert(Term)` for tests.
- `loom/examples/lambda/src/typecheck/typecheck_test.mbt` — unit tests for the new walker.
- `loom/examples/lambda/src/typecheck/moon.pkg` — add `dowdiness/seam` import.
- `ffi/canopy_lambda.mbt` — switch `typed_term_memo` to `parse_cst` + `convert_from_cst`.
- `ffi/moon.pkg` — `dowdiness/seam` import.
- `examples/web/index.html` — annotate the five preset examples.
- `examples/web/tests/lambda-editor.spec.ts` — strengthen assertions now that presets typecheck clean.

Out:
- Any change to `@ast.Term::Lam` shape.
- Bidirectional inference beyond what the existing typechecker `check`/`infer` already provides.
- `resolve`, `eval`, `sym`, pretty-printer — none of these care about type annotations.
- Polymorphism, type variables, or Hindley-Milner unification.

## Current State

- Tokens: `Colon` and `Arrow` exist in `loom/examples/lambda/src/token/token.mbt`.
- Parser: `cst_parser.mbt` has `parse_type`, `parse_atom_type`, `parse_type_annotation`; `LambdaExpr` and param-lists already accept `: Type`. Type grammar is right-associative: `Int -> Int -> Int` → `TypeArrow(Int, TypeArrow(Int, Int))` CST.
- AST: `@ast.Term::Lam(VarName, Term)` — no annotation slot. `term_convert.mbt` discards any `TypeAnnot` child of `LambdaExpr`.
- Typechecker: `TypedTerm::Lam(String, Type?, TypedTerm)` — slot exists. `infer` handles `Some(annot)` via normal arrow typing; `None` emits "missing type annotation". `check` can propagate a param type from an expected arrow to an unannotated lambda.
- Editor pipeline: `ffi/canopy_lambda.mbt` does `parse(text) → convert(Term) → build_typecheck_pipeline`. `TypedTerm.Lam` annotations are uniformly `None`.

## Desired State

- `\x : Int. x` parses to `TypedTerm::Lam("x", Some(TInt), Var("x"))`; typecheck emits zero diagnostics.
- `\x : Int -> Int. f` produces `Some(TArrow(TInt, TInt))`.
- `let f(x : Int, y : Int) = x + y` curries into `Lam("x", Some(TInt), Lam("y", Some(TInt), Bop(Plus, Var("x"), Var("y"))))`.
- `\x : . x` (malformed — parser emitted an ErrorNode inside `TypeAnnot`) → `Lam("x", Some(TError), ...)`, surfaced as "malformed type annotation" by the existing `infer` rules.
- Unannotated `\x. x` unchanged: still produces `Lam("x", None, ...)`, still emits "missing type annotation" in infer mode.
- The five web presets typecheck clean: Basics, Composition, Currying, Conditional, Pipeline.
- Existing `@typecheck.convert(Term)` still compiles and its existing tests still pass (it emits `None` annotations — that hasn't changed).

## Steps

**Loom side (PR against `loom/main`):**

1. Extend typecheck package to depend on `dowdiness/seam`.
2. Implement `convert_from_cst(SyntaxNode) -> TypedTerm`:
   - Recursive walker parallel to `syntax_node_to_term` in `loom/examples/lambda/src/term_convert.mbt`, using the same left-to-right `node.children()` traversal strategy so diagnostic order matches `infer(Module)` expectations.
   - **Do not use `LambdaExprView::body()`** — it returns `nth_child(0)`, which is the `TypeAnnot` node when an annotation is present, not the body. Walk `LambdaExpr` children explicitly: optional `TypeAnnot` comes first among interior nodes, then the body node.
   - **Do not use `LetDefView::params()`** — it returns bare names and loses per-parameter annotation pairing. Traverse the `ParamList` node's children directly, building `(name, annot?)` pairs by pairing each `IdentToken` with an optionally-following `TypeAnnot` child.
   - For `LambdaExpr`: extract optional `@syntax.TypeAnnot` child (wraps `ColonToken` + type node), build `Type` via `type_of_node` on the type child, emit `Lam(param, annot_opt, body)`.
   - For `LetDef` with `ParamList`: right-fold parameter `(name, annot?)` pairs into nested `Lam` nodes.
   - Unknown / `ErrorNode` → `TypedTerm::Error("...")` with a descriptive message. Missing-ident lambda, empty param list, or partially-recovered `LetDef` all produce `TypedTerm::Error`.
3. Implement private `type_of_node(SyntaxNode) -> Type`:
   - `@syntax.TypeInt` → `TInt`; `@syntax.TypeUnit` → `TUnit`.
   - `@syntax.TypeArrow` with two type children → `TArrow(type_of_node(lhs), type_of_node(rhs))`.
   - Parenthesized types: parser emits `LeftParenToken`, inner type, `RightParenToken` as siblings with no wrapper node — skip the paren tokens and recurse on the inner type node.
   - `@syntax.ErrorNode` anywhere in the subtree → `TError`.
4. Unit tests in `typecheck_test.mbt` — minimum coverage:
   - Annotated lambda: `\x : Int. x` clean.
   - Arrow annotation: `\f : Int -> Int. f 1` clean.
   - Right-associativity: `\f : Int -> Int -> Int. f 1 2` clean; `TArrow(Int, TArrow(Int, Int))`.
   - Let-def with param list: `let f(x : Int, y : Int) = x + y` clean.
   - Malformed annotation: `\x : . x` → one `malformed type annotation` diagnostic.
   - Unannotated lambda in let-binding: `let f = \x. x` still emits `missing type annotation` (regression guard).
   - **Error recovery**: `\` (missing ident) → `TypedTerm::Error`; `let f(,) = 1` (empty param) → `TypedTerm::Error`; multi-def input where one def is broken (`let a = 1 let b = let c = 3 c`) — confirms left-to-right def order is preserved across the broken def.
5. `moon info && moon fmt`; confirm `.mbti` changes are intentional. Open loom PR, Codex review, merge.

**Canopy side (PR against `main`, depends on loom merge):**

6. Bump `loom` submodule pointer to the merged commit.
7. `ffi/canopy_lambda.mbt`: replace `@lambda_lang.parse(text) → @typecheck.convert(term)` with `@lambda_lang.parse_cst(text) → @typecheck.convert_from_cst(@seam.SyntaxNode::from_cst(cst))`. Ignore the diagnostics array returned by `parse_cst` (parse errors continue to surface via `editor.get_errors()`).
8. `ffi/moon.pkg`: add `dowdiness/seam`.
9. `examples/web/index.html`: annotate preset `data-example` strings:
   - Basics: `let double = \x : Int. { x + x } let result = double 5 result`
   - Composition: `let inc = \n : Int. { n + 1 } let twice = \f : Int -> Int. \x : Int. { f (f x) } let result = twice inc 0 result`
   - Currying: `let add = \x : Int. \y : Int. { x + y } let add5 = add 5 let sum = add5 10 sum`
   - Conditional: `let choose = \x : Int. if x then { x + 1 } else { 42 } let a = choose 0 let b = choose 5 a + b`
   - Pipeline: `let compose = \f : Int -> Int. \g : Int -> Int. \x : Int. { f (g x) } let double = \x : Int. { x + x } let inc = \x : Int. { x + 1 } let f = compose inc double f 5`
10. `examples/web/tests/lambda-editor.spec.ts`:
    - Strengthen `example input parses successfully` → iterate all five presets (`Basics`, `Composition`, `Currying`, `Conditional`, `Pipeline`) and assert each shows `No errors`.
    - Add `annotated lambda typechecks clean` (`\x : Int. x`).
    - Keep `unannotated lambda produces typecheck error` with literal `\x. x`.
11. Run `moon test`, `moon build --target js`, `npx playwright test lambda-editor.spec.ts`. Open canopy PR, Codex review, merge.

## Testing

Beyond the unit and E2E tests listed above, the key regression guards:

- `moon test` in `loom/examples/lambda/` (currently 503 tests) must stay green. The existing `convert(Term)` function is not modified — old tests pass unchanged.
- `moon test` in canopy (currently 879 tests) stays green.
- The existing `get_diagnostics_json FFI: unbound variable` test (which prints the live JSON on `"x"`) must still produce `unbound variable: x` from the typecheck side.

## Risk

- **CST shapes under error recovery.** `parse_cst` can return partial trees on malformed input. If `convert_from_cst` encounters a `LambdaExpr` with no `IdentToken` child (because the parser inserted an error placeholder), emit `TypedTerm::Error("malformed lambda")`. Error paths in every View must be covered by tests.
- **Diagnostic order.** `ModuleTypeResult.all_diagnostics` is ordered by def traversal. The CST walk must visit `LetDef` nodes left-to-right, matching the current `Module` semantics.
- **`@seam` import in typecheck package.** The typecheck package currently imports `ast` and `incr/cells`; adding `seam` is new. No cyclic dep (seam is already a leaf dep of the rest of lambda).
- **Perf.** One extra CST walk per text change. ~O(n) in node count, negligible; the existing pipeline already walks the CST at least once for `syntax_node_to_term`.

## Non-Goals

- Teaching `infer` to propagate types across let-definitions (`let f = \x. x + 1; f 5` → infer f from usage). That's a separate follow-up (TODO §23 item 2) and would require a fixpoint pass or unification vars.
- Deleting `@typecheck.convert(Term)`. Leave it as the legacy AST path — loom tests exercise it directly from `Term`. Deprecation + removal is a follow-up, not a requirement here.
- Structured `def_name` in the diagnostic JSON (TODO §23 item 3). Orthogonal.

## Workflow

1. Loom PR first. Merge after Codex green-lights the design.
2. Canopy PR bumps submodule pointer + implements FFI and preset changes. Push loom first, then open canopy PR.
