# Lambda alpha-safe transformation boundary

**Date:** 2026-06-15
**Status:** Accepted
**Related:**
[Lambda edit bridge boundary](2026-06-15-lambda-edit-bridge-boundary.md) ·
[Identity and reuse mechanisms](2026-06-01-identity-and-reuse-mechanisms.md) ·
[`lang/lambda/scope` design](../superpowers/specs/2026-05-30-lambda-scope-graph-design.md) ·
loom ADR [Lambda rename consumer](../../loom/docs/decisions/2026-05-20-lambda-rename-consumer.md)

## Context

Lambda currently uses a named user-facing syntax tree. The concrete AST carries
binder names directly (`Var`, `Lam`, `Module`, `LetDef`), and the editor layer
keeps source locations through projection nodes, token spans, and `SourceMap`.
That representation is the right boundary for display, source edits, CRDT text
integration, and rename UI: users wrote names, and Canopy must preserve those
names unless an explicit edit changes them.

Binding-sensitive editor operations now have a better source of truth than raw
string matching: `lang/lambda/scope` builds a NodeId-keyed binding index with
`Decl`, `Ref`, and `Resolution` facts. Consumers can ask which declaration a
reference resolves to, which references point at a declaration, and where a
binder's source token lives. This fixed several root-relative and block-local
rename/inline mistakes without changing the public named AST.

The missing boundary is transformation. Operations such as beta reduction,
inline-by-substitution, extract/move with expression relocation, and future
lambda-aware optimization cannot safely operate by substituting directly into the
named `Term`: a free name in the replacement can be captured by a binder at the
use site, and alpha-equivalent programs still have many string-distinct shapes.
The current evaluator and type checker avoid this by using environments rather
than syntactic substitution, but future transformation passes need a capture-safe
intermediate representation.

## Decision

Keep named `Term` as Lambda's user-visible source/projection representation, and
introduce an alpha-safe internal representation for capture-sensitive
transformations.

The boundary is:

1. **Named source/projection remains the editor boundary.** `@ast.Term`,
   `ProjNode`, `SourceMap`, and token roles continue to model user-visible
   source. This ADR does not change the public shape of the named AST.
2. **`ScopeGraph` remains the binding-resolution source of truth.** Lowering
   from named/projection form to the alpha-safe core must use `lang/lambda/scope`
   facts rather than re-implementing name resolution from strings.
3. **Capture-sensitive transformations run only on the alpha-safe core.** Beta
   reduction, substitution, alpha-equivalence, alpha-stable hashing, and future
   lambda-aware optimizer rewrites must not substitute directly into named
   `Term` values.
4. **Reification is the only place that chooses fresh user-visible names.** When
   an internal transformation must return to source, reification uses
   deterministic freshening to avoid capture while preserving original name hints
   when possible.
5. **User rename and internal alpha-renaming stay separate.** Explicit rename is
   a source refactor: it should continue to use `ScopeGraph` references and
   binder spans, reject unsafe captures conservatively, and not silently rename
   unrelated binders. Automatic alpha-renaming is allowed only as part of a
   mechanical transformation preview or patch, such as beta reduction or future
   inline-by-substitution.

## Initial pilot

The first implementation target is a small beta-reduction pilot, not a broad
inline or optimizer migration.

The pilot should prove the smallest useful end-to-end path:

```text
named/projection term + ScopeGraph
  -> alpha-safe core
  -> capture-safe beta reduction
  -> deterministic reify for source/display
```

The canonical fixture is:

```text
((x) => (y) => x) y
```

A capture-avoiding beta step must produce a term equivalent to:

```text
(y1) => y
```

The exact fresh-name suffix is a policy choice, but it must be deterministic and
must satisfy the Lambda lexer. The pilot may live behind tests and does not need
to become a user-facing editor action in its first PR.

## Internal representation boundary

The alpha-safe core should distinguish binding identity from display names. A
binder carries an internal identity plus a name hint; a variable reference is
either bound to that identity or free by name. Source-derived binders should keep
an origin that can be related back to source when needed, but graph-local IDs
must not be treated as durable identities across rebuilds.

Useful identity lifetimes:

| Identity | Lifetime | Use |
|---|---|---|
| `ScopeId`, `DeclId`, `RefId` | One `ScopeGraph` build | Query indexing and resolution facts |
| `NodeId` + token role | Projection/editor lifetime | Source origin and edit locations |
| alpha `BinderId` | One lowered/constructed alpha term | Capture-safe substitution and alpha equality |
| generated binder id | One transformation/reify session | New binders introduced by transformations |

A source-derived alpha binder may remember the graph declaration that produced it
while lowering, but any state intended to survive a rebuild should retain a
source origin such as projection `NodeId`, role, and original hint instead of a
bare graph-local `DeclId`.

## Reification policies

There is no single correct "core to named" operation. Implementations should
separate at least these policies:

- **Display reify:** preserve readable hints and represent unresolved names in a
  diagnostic-friendly way.
- **Source reify:** produce named `Term`/text suitable for insertion into source;
  free names remain variables, and binders are deterministically freshened
  against the insertion context.
- **Canonical reify/keying:** ignore original hints where useful so
  alpha-equivalent terms get stable comparison/hash keys.

`Unbound(name)` needs an explicit policy because it is a current Lambda
`Term` variant, not just a display string. Lowering should treat it as an
unresolved/free reference by default. Display reify should preserve it as
`Unbound(name)` so diagnostics do not lose meaning. Source reify may normalize it
to `Var(name)` only when generating source text for insertion, and that policy
choice must be visible at the call site.

All policies must be total over incomplete editor terms: `Error`, `Hole`, and
`Unbound` should be preserved or deliberately mapped by the selected reify policy
rather than causing lowering or reification to abort.

## Existing APIs reused

- `lang/lambda/scope.build` builds the binding index used by lowering and source
  edit planning.
- `lang/lambda/scope.declaration` maps projection reference NodeIds to resolved
  declarations; lowering uses it to decide `Bound` versus `Free`.
- `lang/lambda/scope.references` remains the identity-based way to enumerate
  user-visible source references for explicit rename and future multi-edit
  patches.
- `lang/lambda/scope.binder_span` and `SourceMap` token spans remain the only
  accepted way to turn source binders into text edit ranges.
- The named `@ast.Term` / `TermSym` / pretty-printing layer remains the
  user-visible source and display representation.

APIs checked but not reused as the transformation core:

- The evaluator and type checker string environments are good for evaluation and
  checking, but they do not provide an alpha-safe syntactic substitution layer.
- `lang/lambda/edits/free_vars` remains useful for conservative editor guards,
  but free-name sets alone cannot identify which binder a reference denotes.
- The current egraph lambda examples use string payloads for lambda binders and
  variables; they are not a safe substrate for lambda rewrite rules that perform
  substitution.

## Non-goals

This ADR does not decide or require:

- extracting a generic `alpha` library in the first implementation;
- extracting a generic `scope-graph` library;
- changing the public named Lambda AST;
- changing explicit rename behavior;
- exposing beta reduction as a production editor action;
- migrating the evaluator, type checker, or egraph optimizer;
- designing imports, prelude lookup, recursive bindings, or mutual recursion;
- making `ScopeGraph` incremental.

Those remain future work. The first step is a Lambda-specific pilot with clear
seams so the dependency-free alpha core and scope graph core can later be split
out if a second language or optimizer needs them.

## Consequences

- Lambda gains a safe place for operations that need substitution without making
  the editor-facing AST unreadable or de Bruijn-indexed.
- `ScopeGraph` and alpha core stay separate: one resolves named source; the
  other performs capture-safe transformations.
- Inline/extract can continue to reject capture for now. A later PR may extend
  them to produce a multi-edit patch that includes deterministic alpha-renaming,
  but that should be a deliberate UX change with preview semantics.
- Generic library design is deferred until there are at least two real consumers.
  The pilot should still avoid unnecessary dependencies so extraction remains
  plausible.

## Validation strategy

The first implementation should add focused tests before any user-facing action:

- alpha-equivalence: `(x) => x` and `(y) => y` compare equal;
- lowering consistency: each bound alpha reference corresponds to the same
  declaration reported by `ScopeGraph`;
- beta capture avoidance: `((x) => (y) => x) y` reifies with the inner binder
  freshened;
- sequential module binding: a definition initializer only sees preceding module
  definitions;
- free names remain free through substitution and reification;
- `Unbound(name)` follows the selected reify policy: display reify preserves it,
  while source reify may deliberately normalize it to `Var(name)`;
- `Error` and `Hole` survive lowering/reification.

If the pilot touches MoonBit packages, run the affected package tests plus the
workspace checks required by `AGENTS.md`. A documentation-only ADR change is
validated with Markdown review and `git diff --check`.
