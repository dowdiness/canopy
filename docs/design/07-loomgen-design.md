# 07 — loomgen: Code Generation for Projectional Editor Languages

> **Status:** Design approved, implementation not started.
> **Date:** 2026-03-20

## Summary

`loomgen` is a code generator that reads annotated MoonBit `Token` and `Term` enums and emits the boilerplate needed to integrate a language with the loom/seam/projection pipeline. It follows the morm pattern: annotations on real MoonBit types → `.g.mbt` generated files.

**Problem:** Each new language for the projectional editor requires ~1,200 lines of mechanical code: SyntaxKind enum, view structs, token mappings, CST→Term conversion, Term printing, AST reconciliation, ProjNode conversion, and placeholder definitions. This is copy-paste-modify work that's error-prone and tedious.

**Solution:** Annotate the `Token` enum and `Term` enum with `#loom.*` annotations. The generator cross-references them to derive everything else. Declarative shortcuts handle common patterns (leaf extraction, template printing, child-based folding). Hand-written overrides handle the rest.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| DSL format | Annotated MoonBit types (D) | Reuses `moonbitlang/parser` like morm. Real types are source of truth. |
| Source of truth | Term enum (Approach 2) | Single source derives SyntaxKind, views, mappings. Minimal annotation surface. |
| Generation scope | Structural plumbing + optional declarative shortcuts (C) | Generate the mechanical parts, allow hand-written overrides for complex logic. |
| Override mechanism | Convention-first + annotation opt-out (C) | `fn fold_{Name}` discovered by convention; `#loom.manual_fold` as explicit signal. |
| Repository location | Standalone submodule (C) | Reusable across projects, like morm. |
| Non-code domains | Text always ground truth (A) | Keeps architecture unified with existing FugueMax CRDT. |

## Annotation Schema

### Token Enum

```moonbit
#loom.token
pub enum Token {
  #loom.keyword("fn")    // literal string(s)
  Lambda
  #loom.keyword("if")
  If
  #loom.keyword("then")
  Then
  #loom.keyword("else")
  Else
  #loom.keyword("let")
  Let
  #loom.keyword("in")
  In
  #loom.punct(".")
  Dot
  #loom.punct("(")
  LeftParen
  #loom.punct(")")
  RightParen
  #loom.punct("+")
  Plus
  #loom.punct("-")
  Minus
  #loom.punct("=")
  Eq
  #loom.ident                  // parametric: carries String
  Identifier(String)
  #loom.literal                // parametric: carries value
  Integer(Int)
  #loom.trivia                 // whitespace, skipped by parser
  Whitespace
  #loom.delimiter              // layout-sensitive, not trivia
  Newline
  #loom.error                  // error recovery token
  Error(String)
  #loom.eof
  EOF
}
```

**Derived from Token:**

- `SyntaxKind` token variants with naming convention:

| Annotation | Token name | Derived SyntaxKind |
|---|---|---|
| `#loom.keyword` | `If` | `IfKeyword` |
| `#loom.punct` | `Dot` | `DotToken` |
| `#loom.ident` | `Identifier` | `IdentToken` |
| `#loom.literal` | `Integer` | `IntToken` |
| `#loom.trivia` | `Whitespace` | `WhitespaceToken` |
| `#loom.delimiter` | `Newline` | `NewlineToken` |
| `#loom.error` | `Error` | `ErrorToken` |
| `#loom.eof` | `EOF` | `EofToken` |

- Override: `#loom.keyword("if", kind="IfKeyword")` if convention doesn't fit.
- `Token::Show`, `Token::IsTrivia`, `Token::IsEof`, `print_token`
- `syntax_kind_to_token_kind` mapping
- `cst_token_matches` function (keywords/punct compare by identity; `#loom.ident`/`#loom.literal` compare by value+text)

### Term Enum

```moonbit
#loom.term(root="SourceFile")
pub enum Term {
  // ─── Leaf nodes ───────────────────────────────────────────

  #loom.leaf(token="IntToken", extract="parse_int")
  Int(Int)

  #loom.leaf(token="IdentToken", kind="VarRef")
  Var(VarName)

  // ─── Compound nodes ──────────────────────────────────────

  #loom.node(
    kind="LambdaExpr",
    view_children=["body: child(0)"],
    view_tokens=["param: IdentToken"],
  )
  #loom.print("({param}) => {body}")
  #loom.placeholder("Lam(\"x\", Var(\"x\"))")
  Lam(VarName, Term)

  #loom.node(
    kind="AppExpr",
    view_children=["func: child(0)", "args: children_from(1)"],
  )
  #loom.fold("fold_left(App, recurse(func), args)")
  #loom.manual_print          // array-valued accessors are not interpolated in templates
  #loom.placeholder("App(Var(\"f\"), Var(\"x\"))")
  App(Term, Term)

  #loom.node(
    kind="BinaryExpr",
    view_children=["operands: children()", "lhs: child(0)", "rhs: child(1)"],
  )
  #loom.manual_fold
  #loom.manual_print
  #loom.placeholder("Bop(Plus, Int(0), Int(0))")
  Bop(Bop, Term, Term)

  #loom.node(
    kind="IfExpr",
    view_children=[
      "condition: child(0)",
      "then_branch: child(1)",
      "else_branch: child(2)",
    ],
  )
  #loom.print("if {condition} then {then_branch} else {else_branch}")
  #loom.placeholder("If(Int(0), Int(0), Int(0))")
  If(Term, Term, Term)

  // ─── Structural nodes ────────────────────────────────────

  #loom.transparent  // has a CST SyntaxKind/view; fold/proj unwrap to inner
  ParenExpr(Term)

  #loom.collector(
    collects="LetDef",
    let_view_tokens=["name: IdentToken"],
    let_view_children=["init: child(0)"],
    body="Expression",
  )
  #loom.manual_print
  Module(Array[(VarName, Term)], Term)

  // ─── Terminals ────────────────────────────────────────────

  #loom.unit
  Unit

  #loom.error_term
  Unbound(VarName)

  #loom.error_term
  Error(String)
}
```

### Operator Enum (optional)

```moonbit
#loom.operators
pub enum Bop {
  #loom.op_token("PlusToken")
  Plus
  #loom.op_token("MinusToken")
  Minus
}
```

Used to generate `BinaryExprView::ops()` — scans tokens and maps to operator variants.

### Embedded Mini-Language Grammar

Several annotations contain embedded expressions in string parameters. These are **not** arbitrary MoonBit code — they are a closed set of forms that the generator recognizes and expands into generated code.

#### `view_children` accessor syntax

Each entry is `"name: accessor"` where accessor is one of:

| Accessor | Meaning | Generated code |
|---|---|---|
| `child(n)` | nth node child (0-indexed) | `self.node.nth_child(n)` |
| `children_from(n)` | node children starting at index n | `self.node.children_from(n)` |
| `children()` | all node children | `self.node.children()` |

This is a **closed set**. New accessors require a generator update.

#### `view_tokens` accessor syntax

Each entry is `"name: TokenKind"` — extracts the text of the first token matching that SyntaxKind.

Generated code: `self.node.token_text(@syntax.TokenKind.to_raw())`

#### `#loom.print` template syntax

`{name}` interpolates a **scalar** view accessor result. Literal braces are written as `{{` and `}}`. The template is expanded to string concatenation in generated code. Each `{name}` must match a declared scalar accessor (from `child(n)`, `view_tokens`, or leaf `token`). Child accessors are recursively printed via `go(child)`.

Array-valued accessors (`children()` / `children_from(n)`) are available on the generated view, but they are **not** legal inside `#loom.print` templates. Use `#loom.manual_print` for list rendering.

#### `#loom.fold` expressions

A **closed set of fold combinators**, not arbitrary MoonBit:

| Combinator | Meaning | Example |
|---|---|---|
| `recurse(accessor)` | Recursively fold a child node | `recurse(body)` |
| `fold_left(Constructor, init, items_accessor)` | Left-fold an array-valued child accessor into a binary constructor; each item is recursively folded by the generator | `fold_left(App, recurse(func), args)` |

The generator pattern-matches these combinators and expands them into the appropriate loop/accumulation code. Accessor arguments are identifiers naming declared view accessors; arbitrary MoonBit method calls such as `args.map(...)` are not part of the DSL. Unrecognized expressions are a compile error. For anything more complex, use `#loom.manual_fold`.

#### `#loom.placeholder` expressions

Literal MoonBit Term constructor expressions, emitted verbatim into `placeholder_term_for_kind`. Must be valid Term enum constructors.

### Annotation Reference

| Annotation | On | Meaning |
|---|---|---|
| `#loom.term(root="X")` | enum | Marks AST type. `root` names the SourceFile syntax kind. |
| `#loom.leaf(token, extract?)` | variant | Leaf node. View extracts value from a single token. |
| `#loom.node(view_children, view_tokens?)` | variant | Compound node. `child(n)` = nth node child, `children_from(n)` = slice, `children()` = all. |
| `#loom.print("template")` | variant | Declarative print rule. `{name}` interpolates accessor results. |
| `#loom.fold("expr")` | variant | Declarative fold rule for non-trivial CST→Term conversion. |
| `#loom.placeholder("expr")` | variant | Default placeholder term for Delete/InsertChild. |
| `#loom.transparent` | variant | CST wrapper that still gets a SyntaxKind and view, but generated fold/projection unwrap to the inner term. |
| `#loom.collector(collects, let_view_*, body)` | variant | Root-level collector (e.g., SourceFile gathers LetDefs into Module). |
| `#loom.unit` | variant | Terminal value for empty/missing content. |
| `#loom.error_term` | variant | Error/semantic-error variant. No SyntaxKind/view generated, but reconciliation still matches by constructor tag to preserve node IDs. |
| `#loom.manual_fold` | variant | Skip generating `fold_node` case. Expects `fn fold_{ViewName}(node, recurse) -> Term`. The view struct is still generated if `#loom.node(...)` is present — `manual_fold` only skips the fold match arm, not the view. |
| `#loom.manual_print` | variant | Skip generating `print_term` case. Expects `fn print_{ViewName}(term) -> String`. |
| `#loom.manual_view` | variant | Skip generating the view struct entirely. The user provides a hand-written view. Implies `#loom.manual_fold`. |
| `#loom.operators` | enum | Marks an operator sub-enum. |
| `#loom.op_token("Kind")` | variant | Maps operator variant to a SyntaxKind token. |

### Derived SyntaxKind naming for Term variants

**There is no automatic naming convention.** Every Term variant requires an explicit `kind=` parameter to specify its SyntaxKind name, except for:

- `#loom.leaf` variants: default to `{VariantName}Literal` (e.g., `Int` → `IntLiteral`)
- `#loom.collector` root kind: specified by `#loom.term(root="SourceFile")`
- `#loom.transparent` variants: use the variant name directly (e.g., `ParenExpr`)
- `#loom.error_term` variants: no SyntaxKind generated

For compound nodes, you **must** provide `kind=`:

```moonbit
#loom.node(kind="LambdaExpr", ...)
Lam(VarName, Term)

#loom.node(kind="AppExpr", ...)
App(Term, Term)

#loom.node(kind="BinaryExpr", ...)
Bop(Bop, Term, Term)

#loom.node(kind="IfExpr", ...)
If(Term, Term, Term)
```

The view name is always `{kind}View` (e.g., `LambdaExpr` → `LambdaExprView`). Override with `view="CustomView"`.

**Full mapping for the lambda language:**

| Term variant | `kind=` | Derived View |
|---|---|---|
| `Int(Int)` | (default: `IntLiteral`) | `IntLiteralView` |
| `Var(VarName)` | `#loom.leaf(kind="VarRef")` | `VarRefView` |
| `Lam(VarName, Term)` | `kind="LambdaExpr"` | `LambdaExprView` |
| `App(Term, Term)` | `kind="AppExpr"` | `AppExprView` |
| `Bop(Bop, Term, Term)` | `kind="BinaryExpr"` | `BinaryExprView` |
| `If(Term, Term, Term)` | `kind="IfExpr"` | `IfExprView` |
| `Module(...)` | `root="SourceFile"` | (collector handling) |
| `ParenExpr(Term)` | (default: `ParenExpr`) | `ParenExprView` |

## Generated Output

| Generated file | Contents | ~Lines (lambda) |
|---|---|---|
| `syntax_kind.g.mbt` | `SyntaxKind` enum, `to_raw`/`from_raw`, `is_token`, `is_trivia`, `is_error` | ~130 |
| `token_impls.g.mbt` | `Show`, `IsTrivia`, `IsEof`, `print_token` for Token | ~60 |
| `views.g.mbt` | All view structs: `cast()`, `AstView` impl, typed accessors, `ToJson` | ~400 |
| `spec.g.mbt` | `syntax_kind_to_token_kind`, `cst_token_matches` (generated); `LanguageSpec` and `Grammar` are **not** generated — see note below | ~40 |
| `fold_node.g.mbt` | `fold_node` algebra (CST→Term), calling manual overrides where annotated | ~100 |
| `print_term.g.mbt` | `print_term` function, calling manual overrides where annotated | ~40 |
| `proj_helpers.g.mbt` | `same_kind_tag`, `rebuild_kind`, `placeholder_term_for_kind`, `assign_fresh_ids` | ~80 |
| `syntax_to_proj.g.mbt` | `syntax_to_proj_node`, `to_proj_node` (CST→ProjNode) | ~120 |
| `reconcile.g.mbt` | `reconcile_ast` with per-constructor matching, LCS child reconciliation | ~150 |

**Total: ~1,100 generated lines** for the lambda language.

**Note on `spec.g.mbt` scope:** Only `syntax_kind_to_token_kind` and `cst_token_matches` are generated — these are purely mechanical token↔SyntaxKind mappings. The `LanguageSpec` construction and `Grammar` object remain **hand-written** because they reference the hand-written `parse_root` function, `tokenize` function, `prefix_lexer`, and `on_lex_error` handler. These are deeply language-specific. A typical hand-written `spec.mbt` is ~30 lines and wires together the generated `cst_token_matches` with the hand-written parser entry point.

## Override Mechanism

### Convention-first discovery

For `#loom.manual_fold` on `Bop` (derived view name: `BinaryExpr`):

1. Scan `.mbt` files in the same package for `fn fold_BinaryExpr(node : @seam.SyntaxNode, recurse : (@seam.SyntaxNode) -> Term) -> Term`
2. If found: emit `@syntax.BinaryExpr => fold_BinaryExpr(node, recurse)` in the `fold_node` match
3. If not found: fail code generation with `error: Term::Bop has #loom.manual_fold but no fn fold_BinaryExpr found`

Same for `fn print_BinaryExpr(term : Term) -> String`.

### Annotation opt-out

`#loom.manual_fold` / `#loom.manual_print` are the explicit signal. The convention check is a convenience — the annotation is what matters for the generator's decision to skip that variant.

## Edge Cases

### LetDef — node kind without a Term variant

`#loom.collector(collects="LetDef", ...)` implicitly declares a `LetDef` syntax kind. The `let_view_tokens` and `let_view_children` parameters describe LetDefView's accessors.

#### Collector semantics in detail

The `#loom.collector` annotation generates:

1. **`LetDef` SyntaxKind** — added to the SyntaxKind enum automatically.
2. **`LetDefView`** — with accessors from `let_view_tokens` and `let_view_children`. E.g., `name() -> String` and `init() -> SyntaxNode?`.
3. **`fold_node` SourceFile case** — generated algorithm:
   - Iterate `root.children()`
   - If child kind is `LetDef`: cast to `LetDefView`, extract `(name, recurse(init))`, push to `defs` array
   - Otherwise: if no body yet, `body = recurse(child)`
   - If defs is empty: return body term
   - If defs is non-empty: return `Module(defs, body)`
4. **`syntax_to_proj_node` SourceFile case** — same iteration pattern, building ProjNode children from defs + body.
5. **`rebuild_kind` Module case** — reconstructs `Module(defs, body)` from reconciled children, preserving def names from the shape.

The `body="Expression"` parameter is a **semantic label** (not a SyntaxKind name). It means "take the first non-collected child as the body." The string value is used only in error messages (e.g., `"missing Expression"`).

The `Module` variant is **not** `#loom.manual_fold` by default — the collector fold is generated. Only `#loom.manual_print` is needed because printing Module involves newline-separated let bindings, which is hard to express as a template.

### ErrorNode and extra SyntaxKind variants

`ErrorNode` is always emitted. Additional extra kinds declared via `#loom.term(root="SourceFile", extra_kinds=["CustomKind"])`.

### Error terms and reconciliation

`#loom.error_term` variants do **not** get CST `SyntaxKind` variants or typed views, but they still participate in generated reconciliation:

- `same_kind_tag` includes `(Unbound(_), Unbound(_))`, `(Error(_), Error(_))`, etc.
- `reconcile_ast` emits leaf cases for them, preserving the old `node_id` when the constructor tag is unchanged.

This keeps semantic-error nodes stable across reparses, matching the rest of the projection identity model.

### Parametric token matching

- `#loom.ident` → `tok is Identifier(name) && name == text`
- `#loom.literal` on `Integer(Int)` → `tok is Integer(i) && text == i.to_string()`
- `#loom.literal` on `StringLit(String)` → `tok is StringLit(s) && s == text`

### Transparent nodes and span preservation

`#loom.transparent` emits unwrapping logic in `syntax_to_proj_node` that:
- Uses the **inner** node's `kind`, `node_id`, and `children` (for reconciliation identity stability)
- Uses the **outer** node's `start` and `end` spans (so parentheses are included in the position range)

This matches the existing hand-written behavior in `proj_node.mbt` lines 187-209.

### Multiple `#loom.literal` tokens

Each gets its own `SyntaxKind` token variant. Naming derives from the Token variant name.

### Generation idempotency

Running `loomgen` twice with the same `Term` enum **and** kind→raw registry produces
identical `.g.mbt` files, with stable ordering.

`to_raw` integers are **not** a fresh sequence assigned per run. loomgen reads a
persistent, append-only **kind→raw registry** as a second input: existing kinds keep
their assigned raw across any `Term`-enum edit, retired or deleted kinds keep their raw
as a tombstone (never reissued), and only newly introduced kinds receive a fresh raw
(the next unused integer). Regeneration is therefore **idempotent given the registry** —
editing the enum reshuffles nothing already assigned.

This is load-bearing, not cosmetic: seam bakes the raw int into CST structural identity
(the `CstNode` / `CstToken` content hash, which feeds `Eq` / `Hash` / interning /
reuse), so a naive sequential renumber on any enum edit would break node identity. The
registry's concrete form — a sidecar manifest, `#loom.kind(raw=N)` annotations on the
`Term` variants, or reading the prior generated output — is a loomgen implementation
choice; the contract is only that such a stable record exists and is honored. See
[decision: loomgen RawKind vs content-hash identity (L1-A)](../decisions/2026-06-23-loomgen-rawkind-content-hash-identity.md).

## Generator Architecture

### Repository structure

```
loomgen/                        # standalone submodule
├── moon.mod.json               # name: "dowdiness/loomgen"
├── moon.pkg                    # is-main: true, bin-target: native
├── main.mbt                    # CLI entry point, orchestration
├── parser.mbt                  # annotation extraction from AST
├── model.mbt                   # intermediate data structures
├── emit_syntax_kind.mbt        # SyntaxKind enum generator
├── emit_token_impls.mbt        # Token trait impls generator
├── emit_views.mbt              # View struct generator
├── emit_spec.mbt               # token mapping generator (cst_token_matches, syntax_kind_to_token_kind)
├── emit_fold.mbt               # fold_node generator
├── emit_print.mbt              # print_term generator
├── emit_proj.mbt               # proj_helpers + syntax_to_proj generator
├── emit_reconcile.mbt          # reconcile_ast generator
└── util.mbt                    # string helpers, indentation
```

### Dependencies

```json
{
  "name": "dowdiness/loomgen",
  "deps": {
    "moonbitlang/x": "0.4.40",
    "moonbitlang/parser": "0.1.16",
    "Yoorkin/ArgParser": "0.2.1"
  },
  "preferred-target": "native"
}
```

No dependency on loom or seam — the generator only emits source text that uses those libraries.

**Implementation note:** morm parses `Record` struct definitions via `TypeDesc::Record`. loomgen must parse `Variant` enum constructors via `TypeDesc::Variant` — accessing `ConstrDecl.attrs` for per-variant annotations. This is new ground (morm has never done this), so the annotation parsing code in `parser.mbt` will be written from scratch rather than adapted from morm. The `Attribute.parsed : Expr?` field provides structured access to annotation parameters and should be preferred over raw string parsing where possible.

### Pipeline

```
1. Parse CLI args (--pkg or --token/--term, -o output_dir)
2. Scan package for #loom.token enum → TokenSpec
3. Scan package for #loom.term enum → TermSpec
4. Scan package for #loom.operators enum → OperatorSpec?
5. Scan package for manual override functions → Array[ManualOverride]
6. Derive SyntaxKinds from TokenSpec + TermSpec
7. Derive ViewSpecs from TermSpec
8. Emit each .g.mbt file
9. Write files to output directory
```

### Error handling

| Error | Message |
|---|---|
| No `#loom.token` enum found | `error: no #loom.token enum found in package {path}` |
| No `#loom.term` enum found | `error: no #loom.term enum found in package {path}` |
| `#loom.leaf(token="FooToken")` references unknown token | `error: Term::Int references token "FooToken" but no token derives that SyntaxKind` |
| `#loom.manual_fold` but no override found | `error: Term::Bop has #loom.manual_fold but no fn fold_BinaryExpr found` |
| `#loom.manual_print` but no override found | `error: Term::Bop has #loom.manual_print but no fn print_BinaryExpr found` |
| Duplicate `#loom.token` enums | `error: multiple #loom.token enums found` |
| `#loom.print` template references unknown accessor | `error: Term::Lam print template references {unknown} but view has no such accessor` |

Warnings don't fail the build. Errors do.

## Integration with Existing Codebase

### Package boundary change

Language-specific generated code moves from `projection/` to the language package:

**Stays in `projection/` (language-agnostic):**
- `ProjNode`, `NodeId`, `DropPosition` — types
- `FlatProj`, `to_flat_proj`, `to_flat_proj_incremental` — generic flat projection
- `SourceMap` — bidirectional mapping
- `TreeEditorState`, `InteractiveTreeNode` — UI state
- `TreeEditOp`, `SpanEdit` — edit operation types
- `reconcile_children` — LCS algorithm (parameterized)

**Moves to language package (generated or hand-written per-language):**
- `same_kind_tag`, `rebuild_kind`, `reconcile_ast`, `syntax_to_proj_node`, `placeholder_term_for_kind`
- `compute_text_edit`, `insert_child_at`, and any `placeholder_text_for_kind`-style rendering helpers until the editor framework is fully parameterized over language rendering hooks

`reconcile_children` becomes generic — accepts `same_kind_tag` and `reconcile` as function parameters:

```moonbit
// projection/reconcile_ast.mbt — language-agnostic
pub fn reconcile_children(
  old_children : Array[ProjNode],
  new_children : Array[ProjNode],
  counter : Ref[Int],
  same_tag~ : (@ast.Term, @ast.Term) -> Bool,
  reconcile~ : (ProjNode, ProjNode, Ref[Int]) -> ProjNode,
) -> Array[ProjNode]
```

The generated `reconcile.g.mbt` in each language package provides the concrete `same_kind_tag` and `reconcile_ast` functions, passing them to `reconcile_children`:

```moonbit
// lambda/src/reconcile.g.mbt — generated, language-specific
pub fn reconcile_ast(old : ProjNode, new : ProjNode, counter : Ref[Int]) -> ProjNode {
  match (old.kind, new.kind) {
    (Lam(_, _), Lam(_, _)) => {
      let children = @projection.reconcile_children(
        old.children, new.children, counter,
        same_tag=same_kind_tag, reconcile=reconcile_ast,
      )
      ProjNode::new(rebuild_kind(new.kind, children), ...)
    }
    // ... other cases ...
  }
}
```

This is **not** the only package-boundary change. Parameterizing `reconcile_children` is the minimal framework edit, but the current `projection/text_edit.mbt` and `projection/tree_lens.mbt` code also depends on language-specific `print_term`, placeholder text, and `rebuild_kind` behavior. Those functions must either move beside the language package or be parameterized in a follow-up extraction.

### Generated code dependencies

| Generated file | Imports |
|---|---|
| `syntax_kind.g.mbt` | `@seam` (ToRawKind, FromRawKind, IsTrivia, IsError) |
| `views.g.mbt` | `@seam` (SyntaxNode, AstView), `@core` (strconv) |
| `spec.g.mbt` | `@core` (LanguageSpec, PrefixLexer), `@seam` (RawKind) |
| `fold_node.g.mbt` | `@seam` (SyntaxNode), local views, local ast |
| `print_term.g.mbt` | local ast |
| `proj_helpers.g.mbt` | `@projection` (ProjNode), local ast |
| `syntax_to_proj.g.mbt` | `@seam` (SyntaxNode), `@projection` (ProjNode), local views |
| `reconcile.g.mbt` | `@projection` (ProjNode, reconcile_children), local ast |

### Invocation

```bash
moon run loomgen -- --pkg loom/examples/lambda/src/ -o loom/examples/lambda/src/
moon fmt
moon check
```

`.g.mbt` files are committed to the repo (not gitignored).

### Migration effort for lambda

1. Add annotations to existing `token.mbt` and `ast.mbt`
2. Add `#loom.operators` to `Bop`
3. Extract manual overrides into `fold_binary_expr.mbt`, `print_binary_expr.mbt`, `print_module.mbt`
4. Run `loomgen`
5. Delete replaced hand-written files
6. Parameterize `reconcile_children` in `projection/`
7. Move or parameterize `compute_text_edit` / `insert_child_at` so `projection/` stops importing lambda-specific rendering behavior

### New language effort

| | Lambda today | Lambda with loomgen | New language with loomgen |
|---|---|---|---|
| Boilerplate | ~1,200 lines | ~50 lines annotations | ~70 lines annotations |
| Generated | 0 | ~1,130 lines | ~1,200-1,400 lines |
| Hand-crafted | ~1,700 lines | ~500 lines | ~500-600 lines |
