# Lambda alpha-safe beta-reduction pilot

**Status:** Draft
**Date:** 2026-06-15
**Decision:** [Lambda alpha-safe transformation boundary](../decisions/2026-06-15-lambda-alpha-safe-core-boundary.md)

## Why

Lambda's editor-facing `Term` is intentionally named and source-oriented. That is
right for projection, rename UI, CRDT text integration, and diagnostics, but it
is the wrong substrate for syntactic substitution: substituting directly into
`Var(String)` / `Lam(String, ...)` can capture free variables.

The accepted alpha-safe boundary ADR chooses a small beta-reduction pilot as the
first implementation target. The pilot should prove the core transformation
path without changing user-facing edit behavior:

```text
ProjNode + ScopeGraph -> alpha-safe core -> beta step -> deterministic reify
```

The canonical fixture is:

```text
((x) => (y) => x) y
```

A capture-avoiding beta step must reify to a term equivalent to:

```text
(y1) => y
```

## Scope

In:

- `lang/lambda/alpha/` — new Lambda-specific alpha-safe core package for the
  pilot.
- `lang/lambda/alpha/moon.pkg` — imports for `@ast.Term`, `@core.ProjNode`, and
  `@scope.ScopeGraph`.
- `lang/lambda/alpha/types.mbt` — alpha-safe term, binder, reference, free-name
  origin, and reify policy types.
- `lang/lambda/alpha/lower.mbt` — lowering from `ProjNode[@ast.Term]` plus
  `ScopeGraph` into alpha core.
- `lang/lambda/alpha/subst.mbt` — capture-safe substitution and root beta step
  over alpha core.
- `lang/lambda/alpha/reify.mbt` — deterministic reify back to named `@ast.Term`.
- `lang/lambda/alpha/alpha_eq.mbt` — alpha-equivalence helper for tests and
  future hash/keying work.
- `lang/lambda/alpha/*_wbtest.mbt` — focused whitebox tests for the pilot.

Out:

- No production editor action for beta reduction.
- No changes to explicit rename behavior.
- No migration of inline/extract in this slice.
- No evaluator/typechecker/egraph migration.
- No generic alpha library extraction yet.
- No generic ScopeGraph extraction or incremental ScopeGraph redesign.
- No import, prelude, recursive binding, or mutual-recursion semantics.

## Current State

- `loom/examples/lambda/src/ast/ast.mbt` defines the named `Term` variants used
  by parser, projection, editor display, evaluator, and type checker.
- `lang/lambda/scope` builds a NodeId-keyed `ScopeGraph` and exposes:
  - `build(registry, source_map)`
  - `declaration(graph, ref_node)`
  - `declaration_for_name_at(graph, node, name)`
  - `references(graph, decl.id)`
  - `binder_span(graph, decl, source_map)`
- `lang/lambda/edits/text_edit_rename.mbt` already uses `ScopeGraph` identities
  for source rename and should remain a source-edit refactor, not an automatic
  alpha-renaming action.
- `lang/lambda/edits/free_vars.mbt` computes free name sets and remains useful
  for conservative edit guards, but it does not identify binders.
- `lang/lambda/proj` can produce a `ProjNode[@ast.Term]`; tests can use
  `@core.collect_registry`, `@core.SourceMap::from_ast`, and `@scope.build` to
  build the graph needed for lowering.
- Current evaluator/typechecker string environments avoid syntactic substitution
  and are not the pilot target.

## Existing API First

Reuse:

- `@scope.build` as the binding-resolution source for lowering.
- `@scope.declaration` to lower `Var` / `Unbound` projection nodes to
  `Bound(binder)` or `Free(name)`.
- `@core.collect_registry` and `@core.SourceMap::from_ast` in tests to build a
  `ScopeGraph` from a projected root without introducing new projection plumbing.
- `@ast.Term` constructors and `@ast.print_term` only at the named
  boundary/reify tests.

Checked but not used as the alpha transformation substrate:

- `@lambda_eval.Env` and `TypeEnv`: environment-based evaluation/checking, not
  syntactic substitution.
- `lang/lambda/edits/free_vars`: name-set based, insufficient for binder
  identity.
- Existing egraph lambda string payloads: not alpha-safe for beta/substitution
  rewrites.

New helper responsibility boundary:

- `lang/lambda/alpha` owns only alpha-safe transformation for Lambda terms. It
  may depend on current Lambda projection/scope packages for lowering, but it
  must not apply source edits or become a UI action bridge.

## Desired State

The pilot produces a small, tested alpha-safe transformation layer:

- Lowering maps source-resolved references to internal binder identity.
- Free names and `Unbound` retain enough origin information for reify policy to
  distinguish display from source insertion.
- A root beta step substitutes by binder identity, not by string name.
- Reify freshens binders deterministically to avoid capturing free names.
- The canonical beta fixture reifies without capture.
- `Error` and `Hole` survive lowering/reification.

## Proposed Types

Keep the first slice small and concrete. Avoid premature generic library API.
Use `pub(all)` only where tests or later packages genuinely need structural
inspection; otherwise prefer constructors/accessors.

Conceptual shape:

```moonbit
pub(all) struct BinderId(Int) derive(Eq, Hash, Debug)

pub(all) enum BinderOrigin {
  SourceDecl(node_id~ : @core.NodeId, hint~ : String)
  Generated(Int)
}

pub(all) struct Binder {
  id : BinderId
  hint : String
  origin : BinderOrigin
}

pub(all) enum FreeOrigin {
  SourceVar
  SourceUnbound
  GeneratedFree
}

pub(all) struct FreeName {
  name : String
  origin : FreeOrigin
}

pub(all) enum AlphaRef {
  Bound(BinderId)
  Free(FreeName)
}

pub(all) enum AlphaTerm {
  Int(Int)
  Unit
  Var(AlphaRef)
  Lam(Binder, AlphaTerm)
  App(AlphaTerm, AlphaTerm)
  Bop(@ast.Bop, AlphaTerm, AlphaTerm)
  If(AlphaTerm, AlphaTerm, AlphaTerm)
  LetDef(Binder, AlphaTerm)
  Module(Array[(Binder, AlphaTerm)], AlphaTerm)
  Error(String)
  Hole(Int)
}
```

Notes:

- `FreeOrigin` exists because the ADR requires explicit `Unbound` policy.
- `SourceDecl` should not store graph-local `DeclId` as durable identity. Use
  source/projection origin such as `NodeId` and hint.
- `LetDef` may be useful as a structural mirror for `Term::LetDef`, even if most
  transformations operate on `Module` definitions.

## Steps

1. Add `lang/lambda/alpha/moon.pkg`.
   - Production imports: `dowdiness/canopy/core`,
     `dowdiness/canopy/lang/lambda/scope`, `dowdiness/lambda/ast`, and small
     core packages needed by the alpha implementation.
   - Test-only imports under `for "wbtest"`: `dowdiness/canopy/lang/lambda/proj`
     and `dowdiness/lambda`, mirroring the existing scope tests. Parse/project
     helpers belong in tests, not production dependencies.
   - Do not add dependencies on editor/companion/FFI packages.

2. Add `types.mbt`.
   - Define the pilot types above or a smaller equivalent that still preserves
     binder identity, hints, free-origin policy, `Error`, and `Hole`.
   - Add named constructors if public struct fields are not `pub(all)`.

3. Add lowering from projection.
   - Public entry point: `lower(root, graph) -> AlphaTerm` or
     `lower_root(root, graph) -> AlphaTerm`.
   - Traverse `ProjNode[@ast.Term]` so every `Var` / `Unbound` node has a
     `NodeId` available.
   - For each binder (`Lam`, `LetDef` in `Module`), create one `BinderId` and a
     map from the corresponding source declaration to binder id.
   - For each `Var` / `Unbound`, call `@scope.declaration(graph, node.id())`:
     - resolved -> `Var(Bound(binder_id))`
     - unresolved `Var` -> `Var(Free({ name, origin: SourceVar }))`
     - unresolved `Unbound` -> `Var(Free({ name, origin: SourceUnbound }))`
   - Preserve `Error` and `Hole`.
   - Do not re-implement sequential module visibility; trust the `ScopeGraph`
     resolution result.

4. Add alpha-equivalence.
   - Ignore binder hints and source origins.
   - Compare binders by correspondence rather than raw names.
   - Tests must show `(x) => x` and `(y) => y` are alpha-equivalent.

5. Add capture-safe substitution and beta step.
   - `substitute(term, binder_id, replacement)` replaces only
     `Var(Bound(binder_id))`.
   - It must not inspect names to decide binding.
   - First beta API can be root-only:
     `beta_reduce_root(term) -> AlphaTerm?`, reducing `App(Lam(binder, body), arg)`.
   - No normalization/evaluation loop is required.

6. Add deterministic reify.
   - Support at least `Display` and `Source` policies.
   - Compute free names of a binder body before choosing the binder's output
     name so reify can avoid capturing free references.
   - Fresh name policy: try `hint`, then `hint1`, `hint2`, ... using a fallback
     such as `x` for empty or invalid hints.
   - `Display` policy preserves `SourceUnbound` as `@ast.Term::Unbound(name)`.
   - `Source` policy may map `SourceUnbound` to `@ast.Term::Var(name)` only at
     this explicit call site.

7. Add focused tests.
   - Direct alpha-core tests for alpha-equivalence, substitution, freshening,
     and `Error`/`Hole` preservation.
   - Projection-lowering tests that parse/project source, build `ScopeGraph`,
     lower, and assert bound/free classification matches the graph.
   - Beta fixture test for `((x) => (y) => x) y` reifying to a capture-free term
     equivalent to `(y1) => y`.
   - Sequential module test: in newline-separated source
     `let x = 1\nlet x = x\nx`, the second initializer's `x` binds to the
     first definition and the body's `x` binds to the second definition.

8. Keep the pilot unexposed.
   - Do not add a `TreeEditOp` variant.
   - Do not update JS FFI.
   - Do not change companion/editor behavior.

9. Run validation and inspect generated interfaces.
   - Run `moon check` and `moon test` from the root workspace.
   - If the new package affects generated interfaces, run `moon fmt && moon info`
     and inspect `.mbti` diffs for accidental API widening.

## Acceptance Criteria

- [ ] New `lang/lambda/alpha` package exists and is not imported by production
      editor/FFI paths.
- [ ] Lowering uses `ScopeGraph` for reference resolution rather than string-only
      lexical lookup.
- [ ] `alpha_eq((x) => x, (y) => y)` is true in tests.
- [ ] Root beta reduction substitutes by `BinderId` and does not capture free
      names.
- [ ] The canonical beta fixture reifies with a freshened inner binder.
- [ ] `Unbound`, `Error`, and `Hole` policies are covered by tests.
- [ ] Sequential module scoping is covered by a lowering test.
- [ ] No user-facing edit action or FFI surface changes in this slice.

## Validation

From the repository root:

```bash
moon check
moon test
moon fmt && moon info
```

Then inspect public interface changes:

```bash
git diff -- '*.mbti'
```

If only `lang/lambda/alpha` is added, the `.mbti` diff should expose only the
new intentional package API. No TypeScript, Playwright, or JS rebuild is required
unless a later slice wires beta reduction into the web/FFI surface.

## Risks

- **Binder origin confusion:** `DeclId` is graph-local; storing it as durable
  alpha identity would make cached alpha terms invalid across rebuilds. Use
  source/projection origin for anything that leaves one lowering run.
- **Reify capture bug:** choosing a binder name without considering free names in
  its body recreates the exact bug this pilot is meant to avoid.
- **Over-generic first slice:** trying to design a reusable alpha library before
  one Lambda pilot lands may freeze the wrong API. Keep the first package
  Lambda-specific but dependency-conscious.
- **Unbound normalization ambiguity:** display and source reify intentionally
  differ; tests must pin both policies.
- **MoonBit API widening:** `pub(all)` is convenient for tests but becomes public
  API. Prefer constructors/accessors unless structural inspection is needed.

## Notes

- This plan intentionally follows the two-layer architecture from the MoonBit
  expression-problem guidance: named `Term` remains the concrete user/source
  layer, while alpha core is a second concrete structure for transformation.
- A later generic extraction should split dependency-free alpha utilities from
  Lambda's `ScopeGraph`/`ProjNode` adapter only after there is a second consumer
  or a real optimizer/egraph migration.
