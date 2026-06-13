# Lambda CstFold modernization decision note (#623)

**Status:** proposed first slice  
**Date:** 2026-06-14  
**Issue:** <https://github.com/dowdiness/canopy/issues/623>

## Decision

Migrate Lambda incrementally toward the CstFold pattern at the **projection
construction** seam, but keep the Lambda-specific `ModuleProjection` memo layer
and custom edit bridge for now.

Markdown remains the reference integration for new languages. Lambda stays a
legacy stress case, not a reference demo. The immediate modernization goal is to
remove duplicated Lambda AST construction where it is safe, while explicitly
containing the remaining exceptions.

## Verified context

- `docs/development/ADDING_A_LANGUAGE.md` names Markdown as the CstFold/3-memo
  reference and warns not to copy Lambda.
- Markdown uses:
  - `@loomcore.CstFold::new(@markdown.markdown_fold_node)` in
    `lang/markdown/proj/proj_node.mbt`.
  - `@core.build_projection_memos` for the 3-memo `(proj, registry,
    source_map)` pipeline.
  - `@lang_runtime.LanguageSpec` for editor construction and edit application.
- Lambda still uses:
  - `ModuleProjection { defs, final_expr }` in
    `lang/lambda/proj/module_projection.mbt`.
  - Hand-written view-cast projection in `lang/lambda/proj/proj_node.mbt`.
  - A custom 4-output memo stack in `lang/lambda/flat/projection_memo.mbt`.
  - A custom `apply_lambda_tree_edit` bridge in
    `lang/lambda/companion/lambda_editor.mbt`.
- Loom Lambda already exports the existing CstFold API:
  `@parser.lambda_fold_node` and `@parser.syntax_node_to_term`.
- #620 shipped MoonBit-style Lambda syntax; #625/#622 only fixed the narrower
  typed-`fn` binding rewrite preservation. The #625 source scanner is a bounded
  compatibility layer, not a framework pattern.

## Comparison

| Responsibility | Markdown/reference | Lambda/current | Decision for #623 |
|---|---|---|---|
| CST -> AST value | `CstFold` + language fold node | duplicated hand-built `Term` construction in Canopy | migrate first |
| AST/projection tree shape | small AST/syntax parallel walk | bespoke synthetic `Lam`, `App`, `Bop`, `LetDef`, `Module` shapes | preserve initially |
| Memo pipeline | `@core.build_projection_memos` 3-memo | `VersionedModuleProjection` + proj + registry + source_map | keep legacy boundary |
| Edit bridge | `LanguageSpec::apply_edit` | `EditContext{registry,module_projection}` + typed errors + patch trace + `Drop` via `move_node` | keep custom bridge |
| New-language guidance | copy Markdown | explicitly do not copy Lambda | leave docs accurate |

## Blockers to a full migration

1. **`ModuleProjection` is still semantic/editor state.** Scope, semantic
   decorations, binding actions, and many edit tests consume the flat def view
   and its LetDef ids. Removing it requires a separate identity/scope design,
   not just swapping memo helpers.
2. **The `LanguageSpec` boundary deliberately excludes Lambda's edit bridge.**
   The S3 amendment records why: Lambda needs registry + module-projection
   context, returns `TreeEditError` plus the applied `SpanEdit` trace, and
   delegates `Drop` to `SyncEditor::move_node`.
3. **CstFold and current projection semantics are not byte-for-byte identical.**
   A probe comparing current projection kind with `syntax_node_to_term` showed:
   - `{ 1 }`: current projection `Int(1)`, CstFold term `Module([], Int(1))`.
   - `{ }`: current projection `Unit`, CstFold term `Error("empty block")`.
   - `(1)` and `fn f() { 1 }\nf` already agree.
   These differences need an explicit compatibility decision before replacing
   the root builder wholesale.
4. **Related issues remain adjacent, not substitutes.**
   - #129/#scope work centralized queries but did not remove the
     `ModuleProjection` context requirement.
   - #567/`ProjectionIdentityTracker` is relevant for future binder identity,
     but it does not replace Lambda's current projection-diff mechanism.
   - #389 may improve projection API ergonomics later; it is not a current
     blocker with a concrete in-tree migration path.

## First slice

Goal: make Loom's Lambda CstFold the checked semantic source for Lambda
projection without changing editor behavior.

1. Add projection parity tests in `lang/lambda/proj/proj_node_wbtest.mbt` (or a
   new focused wbtest) that compare:
   - `parse_to_proj_node(source).kind`
   - `@parser.syntax_node_to_term(@seam.SyntaxNode::from_cst(cst))`
   for representative sources.
2. Classify each source as either:
   - **must agree now**: ints, vars, parens, `fn` bindings, multi-param arrows,
     apps, binary expressions, `if`, holes, normal modules; or
   - **legacy divergence**: block-expression empty/single-expression behavior,
     until a compatibility decision is made.
3. Move one safe `Term` construction responsibility from
   `lang/lambda/proj/proj_node.mbt` to the existing CstFold API. Start with a
   local, private helper that obtains the folded `Term` for a syntax subtree and
   use it only on cases pinned by the parity tests. Do not change
   `ModuleProjection` storage, public `.mbti` shape, source-map token roles, or
   the edit bridge in this slice.
4. Document any retained divergence in the test names/comments rather than
   silently normalizing it.

Likely touched files:

- `lang/lambda/proj/proj_node.mbt`
- `lang/lambda/proj/proj_node_wbtest.mbt` or a new
  `lang/lambda/proj/proj_node_cstfold_wbtest.mbt`
- `lang/lambda/proj/pkg.generated.mbti` only if `moon info` reveals an intended
  public API change; the preferred first slice should avoid one.

## Non-goals

- Do not migrate Lambda onto `LanguageSpec` in this issue slice.
- Do not replace `build_lambda_projection_memos` with
  `@core.build_projection_memos` until `ModuleProjection` consumers have a new
  home.
- Do not make #625's source scanner a reusable framework abstraction.
- Do not reopen binder identity or scope unification under #623 unless a concrete
  projection slice is blocked by them.

## Validation plan

From the worktree root:

```bash
NEW_MOON_MOD=0 moon check lang/lambda/proj
NEW_MOON_MOD=0 moon test lang/lambda/proj
NEW_MOON_MOD=0 moon test lang/lambda/edits
NEW_MOON_MOD=0 moon test lang/lambda/companion
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon info
git diff -- '*.mbti'
```

For docs-only follow-up edits in this checkout, the root `check-docs.sh`
script is absent as of `b11b29f`; run the available doc-link check instead:

```bash
bash scripts/check-agent-doc-links.sh
```
