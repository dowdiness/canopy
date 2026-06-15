# Lambda CstFold modernization decision note (#623)

**Status:** accepted through #633; updated for #661 compatibility cleanup
**Date:** 2026-06-14  
**Issue:** <https://github.com/dowdiness/canopy/issues/623>

## Decision

Migrate Lambda incrementally toward the CstFold pattern at the **projection
construction** seam, but keep the Lambda-specific `ModuleProjection`
compatibility/reconciliation helpers and custom edit bridge for now.

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
    `lang/lambda/proj/module_projection.mbt` for legacy helpers/tests plus the
    internal root-module reconciliation hook; it is no longer editor-facing
    projection state.
  - Hand-written view-cast projection in `lang/lambda/proj/proj_node.mbt`.
  - `@core.build_projection_memos` via
    `lang/lambda/proj/projection_memo.mbt` for the editor-facing 3-memo stack
    (#633).
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
| Memo pipeline | `@core.build_projection_memos` 3-memo | `@core.build_projection_memos` via `lang/lambda/proj` (#633); legacy `ModuleProjection` no longer has an editor-facing memo | migrated in #633 |
| Edit bridge | `LanguageSpec::apply_edit` | `EditContext{registry,definition_index}` derived from the generic projection root + typed errors + patch trace + `Drop` via `move_node` | keep custom bridge |
| New-language guidance | copy Markdown | explicitly do not copy Lambda | leave docs accurate |

## Blockers to a full migration

1. **`ModuleProjection` remains a compatibility/reconciliation seam, not editor
   state.** Scope, semantic decorations, binding actions, and production edits
   now derive from the generic projection root plus `DefinitionIndex`. The
   remaining flat view is used internally to reconcile root-module binding IDs
   and by legacy tests being classified under #662.
2. **The `LanguageSpec` boundary deliberately excludes Lambda's edit bridge.**
   The S3 amendment records why: Lambda needs registry plus a definition index,
   returns `TreeEditError` plus the applied `SpanEdit` trace, and delegates
   `Drop` to `SyncEditor::move_node`.
3. **CstFold and current projection semantics are not byte-for-byte identical.**
   A probe comparing current projection kind with `syntax_node_to_term` showed:
   - `{ 1 }`: current projection `Int(1)`, CstFold term `Module([], Int(1))`.
   - `{ }`: current projection `Unit`, CstFold term `Error("empty block")`.
   - `(1)` and `fn f() { 1 }\nf` already agree.
   #629 decided to preserve current Canopy editor semantics and keep Loom's raw
   CstFold semantics intact. The compatibility boundary normalizes known
   no-definition block-expression structural patterns before parity-checking
   CstFold terms now or adopting them in later projection slices.
4. **Related issues remain adjacent, not substitutes.**
   - #129/#scope work centralized queries before #632/#661 removed the
     production `ModuleProjection` context requirement.
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
   - **must agree for valid representative sources**: ints, vars, parens,
     `fn` bindings, multi-param arrows, apps, binary expressions, `if`, holes,
     normal modules; or
   - **compatibility divergence**: block-expression empty/single-expression
     behavior remains raw-CstFold divergent but adapter-normalized to current
     editor semantics; or
   - **recovery divergence**: malformed/recovery CSTs whose current projection
     and CstFold error normalization intentionally differ.
3. Move one safe `Term` construction responsibility from
   `lang/lambda/proj/proj_node.mbt` to the existing CstFold API. Start with a
   local, private helper that obtains the folded `Term` for a syntax subtree and
   use it only on cases pinned by the parity tests. Start with leaf/value cases
   (`Int`, `Var`, `Hole`) before composite nodes whose `ProjNode.kind` must stay
   consistent with child kinds. Do not change `ModuleProjection` storage, public
   `.mbti` shape, source-map token roles, or the edit bridge in this slice.
4. For composite projection nodes, use CstFold only for the parent constructor
   shape. Do not recursively refold descendants that have already been projected
   into child `ProjNode`s; rebuild the parent kind from the shallow CstFold shape
   plus the existing child kinds.
5. Document any retained divergence in the test names/comments rather than
   silently normalizing it.

### Composite parent-shape rule

`@parser.syntax_node_to_term` is the full recursive fold: it computes every
child term in the syntax subtree. That is appropriate for leaf/value projection
and parity tests, but it is the wrong ownership boundary for composite
`ProjNode` construction because the projection builder has already produced child
`ProjNode`s with source spans, IDs, child order, source-map meaning, and edit
identity.

For one-CST-node/one-`ProjNode` composite cases, the safe migration pattern is:

1. Use Loom Lambda's per-node fold algebra to extract only the parent constructor
   shape with placeholder child terms.
2. Apply the Canopy compatibility normalization to that shallow shape.
3. Rebuild the parent `Term` with the already-projected child kinds via
   `@ast.rebuild_from` / `rebuild_kind`.
4. Allocate the branch through `ProjNode::branch` so projection metadata remains
   owned by Canopy.

This is a shallow fold / one-layer fold, not a visitor-specific pattern. In
recursion-scheme terms, it separates the parent constructor shape from recursive
child results: the parser/CstFold layer owns semantic constructor selection;
the projection layer owns identity, spans, and child `ProjNode`s. It also avoids
repeated suffix refolding for nested composite chains.

Do not apply this pattern blindly to shapes whose projection tree is synthetic
relative to the CST. `App` and `Bop` remain separate migration problems because
their CST forms are flat while the current projection shape is nested.

Likely touched files:

- `lang/lambda/proj/proj_node.mbt`
- `lang/lambda/proj/proj_node_wbtest.mbt` or a new
  `lang/lambda/proj/proj_node_cstfold_wbtest.mbt`
- `lang/lambda/proj/pkg.generated.mbti` only if `moon info` reveals an intended
  public API change; the preferred first slice should avoid one.

## Issue slicing

- #628 — add CstFold parity tests.
- #629 — decide the block-expression divergence (decided: compatibility adapter).
- #630 — replace safe leaf/value `Term` construction with CstFold.
- #642 — migrate safe composite `Term` construction through CstFold-compatible
  shallow parent shapes.
- #631 — extract a definition index from `ModuleProjection`.
- #632 — migrate scope/edit/semantic consumers off `ModuleProjection`.
- #633 — switch the projection memo stack to the generic 3-memo path.
- #634 — revisit the Lambda edit bridge after compatibility-surface cleanup.
- #635 — replace typed-`fn` source scanners with structured token metadata.

## Non-goals

- Do not migrate Lambda onto `LanguageSpec` in this issue slice.
- After #633/#661, keep remaining edit-bridge cleanup scoped to #634 instead of
  broadening compatibility-surface work into an edit redesign.
- Do not make #625's source scanner a reusable framework abstraction.
- Do not reopen binder identity or scope unification under #623 unless a concrete
  projection slice is blocked by them.

## Validation plan

From the worktree root:

```bash
NEW_MOON_MOD=0 moon check lang/lambda/proj
NEW_MOON_MOD=0 moon test lang/lambda/proj
NEW_MOON_MOD=0 moon test lang/lambda/edits
NEW_MOON_MOD=0 moon test lang/lambda/semantic
NEW_MOON_MOD=0 moon test lang/lambda/companion
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon info
git diff -- '*.mbti'
```

For docs-only follow-up edits, run the root doc check if it exists in the
current checkout. If it is still absent, run the available doc-link check:

```bash
if [ -x ./check-docs.sh ]; then
  bash ./check-docs.sh
else
  bash scripts/check-agent-doc-links.sh
fi
```
