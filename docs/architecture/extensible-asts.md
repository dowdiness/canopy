# Extensible ASTs in MoonBit

This document records the analysis from 2026-04-08 exploring the tree-decoration problem — whether MoonBit can support extensible AST infrastructure analogous to Haskell's Trees that Grow — and what practical strategy Canopy adopts instead.

## The problem: decorating trees with phase-specific data

Compilers and editors process ASTs through multiple phases, each adding information:

1. **Parsing** produces bare syntax nodes
2. **Name resolution** decorates variables with their binding sites
3. **Type inference** decorates expressions with inferred types
4. **Evaluation** decorates definitions with their computed values

The challenge: how do you define the tree type *once* but allow different phases to attach different data to each node — without duplicating the entire tree definition per phase?

This is the **Tree-Decoration Problem** (Najd & Peyton Jones 2017).

## Three known solutions (and why they don't work in MoonBit)

### 1. Trees that Grow (Haskell — type families)

The TTG approach parameterizes each constructor with an **extension descriptor** `xi` and uses **type families** to map `(xi, constructor)` to the extension type:

```haskell
data Exp_X xi = Lit_X  (X_Lit xi)  Integer
              | Var_X  (X_Var xi)  Var
              | App_X  (X_App xi)  (Exp_X xi) (Exp_X xi)
              | Abs_X  (X_Abs xi)  Var        (Exp_X xi)
              | Exp_X  (X_Exp xi)              -- new constructors

type family X_Lit xi
type family X_App xi
-- ...

-- Undecorated (parsing output): all extensions = Void
data UD
type instance X_Lit UD = Void
type instance X_App UD = Void

-- Type-checked: App gains a Typ field
data TC
type instance X_App TC = Typ
```

**Why this can't work in MoonBit:** No type families, no associated types, no type-level functions. No mechanism to map `(phase, constructor) -> extension_type`.

### 2. Haskell Annotations Library (functor transformer)

```haskell
data Ann x f a = Ann x (f a)
type AnnFix x f = Fix (Ann x f)  -- fully annotated tree

rootAnn    :: AnnFix x f -> x
mkAnnFix   :: x -> f (AnnFix x f) -> AnnFix x f
unannotate :: Functor f => AnnFix x f -> Fix f
```

Pairs annotation `x` with functor `f` at every recursive level.

**Why this can't work in MoonBit:** Requires HKT. `Ann x f a` is parameterized over a *functor* `f`. MoonBit's Self-based traits can't abstract over "a type constructor that takes one argument."

### 3. TS-that-Grow (TypeScript — indexed access types)

```typescript
interface ExtendExpression {
  Literal: object;
  Variable: object;
}

type Literal<Extend extends ExtendExpression> = {
  type: "Literal"; value: number;
} & Extend["Literal"];  // indexed access = type family application
```

**Why this can't work in MoonBit:** No indexed access types, no intersection types, no structural subtyping.

### What all three share

All three compute `extension_type = f(phase, constructor)` at the type level. MoonBit lacks all three mechanisms — a fundamental limitation rather than a gap that clever encoding can bridge.

## What the type system constraint really means

Three specific things MoonBit cannot express:

| Constraint | What it means | Impact |
|---|---|---|
| **A. Per-phase tree types** | `Exp[Parsed]` vs `Exp[TypeChecked]` with different fields | Can't statically distinguish phases |
| **B. Annotation presence** | Compile error if accessing `.type` on an untyped tree | Lookups always return `Option` |
| **C. Per-constructor extensions** | `App` carries `Typ`, `Lit` doesn't | Annotations keyed by NodeId, not by constructor |

These constraints exist in MoonBit's current type system (as of 2026-04). MoonBit is actively evolving — type families or associated types could be added in the future. But as of now, no amount of refactoring or code generation adds type-level phase/constructor indexing.

## Why this may not matter for Canopy

Canopy's actual annotation inventory:

| Annotation | Which nodes? | Per-constructor? |
|---|---|---|
| Source positions (start, end) | ALL nodes | No — uniform |
| Node registry | ALL nodes | No — uniform |
| Source map ranges | ALL nodes | No — uniform |
| Token spans | ALL nodes | No — uniform |
| Eval results | Top-level defs only | Subset, but not per-constructor |

None of Canopy's current annotations are per-constructor. They're either "all nodes" or "a filtered subset." TTG's per-constructor extensions solve GHC's problem (97 types, 321 constructors, different fields per phase per constructor). Canopy has 11 Term variants and 7 JsonValue variants.

**The type system constraint is real but is not currently a practical problem.**

If Canopy later adds a type checker (type annotations per expression node) or a linter (warnings per specific construct), the pattern remains `Map[NodeId, T]` with `Option` lookups. The runtime cost of `None` for nodes without annotations is negligible. Revisit if evidence shows otherwise.

## The expression problem framing

The tree-decoration problem is one face of the **expression problem** — extensibility in two dimensions:

- **New operations** (add an evaluator, type checker, linter without modifying the AST definition)
- **New data** (add annotation fields per phase without modifying operations)

Tagless final solves the "new operations" direction. TTG/Annotations solve the "new data" direction. MoonBit can do the first but not the second at the type level.

## Canopy's practical strategy

### Layer 1: Tagless Final Algebra (Lambda only — recommended pattern)

The Lambda language uses the Finally Tagless pattern (Kiselyov's "Symantics"):

```moonbit
// loom/examples/lambda/src/ast/sym.mbt
pub(open) trait TermSym {
  int_lit(Int) -> Self
  variable(VarName) -> Self
  lam(VarName, Self) -> Self
  app(Self, Self) -> Self
  bop(Bop, Self, Self) -> Self
  if_then_else(Self, Self, Self) -> Self
  mod(Array[(VarName, Self)], Self) -> Self
  unit() -> Self
  unbound(VarName) -> Self
  error_term(String) -> Self
  hole(Int) -> Self
}
```

- `TermSym` is the algebra
- `impl TermSym for Term` is the identity interpretation (constructs the enum)
- `impl TermSym for Pretty` and `PrettyLayout` are pretty-printer interpretations
- `replay : fn[T : TermSym](Term) -> T` is the fold (concrete Term to any interpretation)
- `pub(open)` allows downstream packages to add new interpretations

**Current scope:** Only Lambda has this pattern. JSON and Markdown define their ASTs as plain enums without a `Sym` trait. Tagless final is the *recommended* approach for new languages; it is not yet universal across the codebase. Codegen (Layer 4) would make it the default by generating the `Sym` trait from any enum definition.

This handles **extensible operations** — the "new operations" direction of the expression problem. Adding an evaluator, type checker, or linter means implementing `TermSym` for a new type.

**Note:** Loom's `Grammar` struct also takes a `fold_node: (SyntaxNode, (SyntaxNode) -> Ast) -> Ast` callback — a fold over the CST that produces the AST. Every language has this (`lambda_fold_node`, `json_fold_node`, `markdown_fold_node`). This is a *different* fold from `replay`: `fold_node` goes CST→AST (parsing), while `replay` goes AST→interpretation (semantics). Both are per-language; only `replay` is part of the tagless final pattern.

### Layer 2: Side Tables with Typed Maps (current approach)

Annotations are stored in `Map[NodeId, V]` structures, each with a specific value type:

- `Map[NodeId, ProjNode[T]]` — node registry
- `SourceMap` (contains `Map[NodeId, Range]`) — position annotations
- `Array[EvalResult]` — evaluation results (indexed by definition)

Each map is typed — you can't accidentally put a `Range` where an `EvalResult` goes. The lack of per-constructor granularity means lookups return `Option`, but the annotation *type* is always known.

### Layer 3: Incremental Memos (computation scheduling)

`@incr.Memo` handles **when** to recompute annotations rather than what they contain. Each memo declares dependencies and recomputes only when inputs change. The projection memo uses `changed_def_indices_ref` to patch only changed subtrees, achieving O(changed) recomputation.

This is orthogonal to annotation structure — an optimisation layer rather than an architectural one.

### Layer 4: Code Generation (planned — boilerplate reduction)

The practical pain point is **mechanical boilerplate** when adding or modifying language definitions. Currently, adding a variant to Lambda's `Term` requires hand-updating 7 locations across two repos:

| Location | Repo | What it does | Mechanical? |
|---|---|---|---|
| `sym.mbt` — `TermSym` trait | loom | Add algebra method | Yes |
| `sym.mbt` — `impl TermSym for Term` | loom | Identity interpretation | Yes |
| `sym.mbt` — `replay` | loom | Fold case | Yes |
| `proj_traits.mbt` — `TreeNode::children` | loom | Child extraction | Yes |
| `proj_traits.mbt` — `TreeNode::same_kind` | loom | Variant comparison | Yes |
| `proj_traits.mbt` — `Renderable::kind_tag` | loom | Variant name string | Yes |
| `proj_node.mbt` — `rebuild_kind` | canopy | Inverse of children | Yes |

All seven are mechanical functions of the enum definition, written by hand and kept in sync manually. Miss one, get a silent bug. The cross-repo split (loom submodule vs canopy) adds friction.

**Planned codegen** (morm-style `pre-build` using `@moonbitlang/parser`):

- **Generate from enum definition:** `TermSym` trait, `replay` fold, identity impl, `children_of`, `rebuild_from`, `same_kind`, `kind_tag`
- **Leave hand-written:** `label`, `placeholder`, `unparse`, evaluation, pretty-printing, `fold_node` (CST→AST) — anything with semantic choices
- **Output:** `.g.mbt` files alongside source, visible in diffs, no hidden metaprogramming

**Prerequisite refactoring:** Consolidate all structural knowledge about Term's recursive shape into `sym.mbt` — move `rebuild_kind` from `lang/lambda/proj/proj_node.mbt` into loom's `sym.mbt` as `rebuild_from`, add `children_of` next to `replay`. This makes `sym.mbt` the single file that codegen would replace, and eliminates the cross-repo sync problem for mechanical code.

## What this strategy does and does not solve

### Solved (practical problems)

- **Boilerplate when adding variants/languages** — codegen generates mechanical impls
- **Sync bugs between children/rebuild_kind/replay** — single source of truth
- **Extensible operations** — tagless final (`TermSym`) already handles this
- **Typed annotation storage** — `Map[NodeId, V]` with specific `V` per annotation kind
- **Incremental recomputation** — `@incr.Memo` with dirty tracking

### Not solved (type system constraints)

- **Per-phase tree types** — still one `ProjNode[Term]` for all phases
- **Annotation presence guarantees** — still `map.get(id) -> Option`
- **Per-constructor extensions** — still same annotation type for all constructors

These remain unsolved because MoonBit's type system cannot express them. They are acknowledged limitations rather than problems requiring a solution at Canopy's current scale.

## Phased execution plan

1. **Now — Refactor:** Consolidate `sym.mbt` as single source of structural truth. Move `rebuild_kind` next to `replay` and `children_of`. Split `proj_traits.mbt` into mechanical (future codegen target) and semantic (always hand-written).

2. **Next — Codegen prototype:** When adding the Markdown language, build a minimal codegen tool that generates `TermSym`, `replay`, identity impl, and mechanical `TreeNode`/`Renderable` impls from the enum definition. Follow morm's pattern: `pre-build` in `moon.pkg`, `@moonbitlang/parser` for AST reading, `.g.mbt` output.

3. **Later — Annotation-aware fold:** If annotation computation becomes repetitive across languages, extend `replay` to a `replay_proj` that works on `ProjNode[Term]` and records per-node results into `Map[NodeId, T]`. This bridges a structural gap: `replay` matches on `Term` variants directly (`App(f, a)` and recurses into `f`, `a`), but `ProjNode` stores children in a flat array (`node.children[0]`, `node.children[1]`). The fold must map between the variant's recursive fields and the children array — the same knowledge encoded in `children_of` and `rebuild_from`. This turns any `TermSym` interpretation into an annotation-producing fold.

4. **If needed — Trait-bounded context:** If the number of annotation kinds grows beyond what's manageable as explicit parameters (10+ annotations, 4+ languages), introduce annotation capability traits (`HasSourceMap`, `HasEvalResults`) for compile-time checking. Premature now.

## References

- Najd, S. & Peyton Jones, S. (2017). ["Trees that Grow."](https://www.microsoft.com/en-us/research/publication/trees-that-grow/) *J. of Universal Computer Science*, vol. 23, no. 1, pp. 42-62.
- van Steenbergen, M. [Haskell Annotations library](https://hackage.haskell.org/package/Annotations). `Ann x f a = Ann x (f a)` functor transformer.
- igrep. ["Trees that Grow in TypeScript"](https://dev.to/igrep/flexiblly-extend-nested-structures-trees-that-grow-in-typescript-4347). Indexed access types as type family substitute.
- oboard. [morm](https://github.com/oboard/morm). MoonBit ORM — code generation pattern via `pre-build` and `@moonbitlang/parser`.
- Canopy source: `loom/examples/lambda/src/ast/sym.mbt` (TermSym algebra + replay fold), `core/proj_node.mbt` (ProjNode), `lang/lambda/flat/projection_memo.mbt` (incremental memos), `lang/lambda/eval/eval_memo.mbt` (eval annotations).
