# lang/lambda

Thin facade for the lambda-calculus editor language. Re-exports the handful of
symbols that consumers (`editor/` tests and `ffi/lambda/`) call through this
path, sourced from the currently-imported subpackages `edits`, `eval`, and
`companion`. The projection subpackage (`proj`) is not re-exported here;
consumers that need it import the subpackage directly.

The facade was originally much larger; in 2026-05 it was trimmed to the symbols
with live callers. Consumers that need more reach should import subpackages
directly (see `examples/ideal/main/moon.pkg`).

## Public API

Re-exported from `lang/lambda/edits`:

- type `TreeEditOp`
- type `DropPosition` (canonical origin is `@core`; `lang/lambda/edits`
  re-re-exports it, so consumers see it through either path)

Re-exported from `lang/lambda/companion`:

- type `LambdaCompanion`
- `new_lambda_editor(agent_id, capture_timeout_ms?, parent_runtime?) -> (SyncEditor[Term], LambdaCompanion)`
- `apply_lambda_tree_edit(editor, companion, op, timestamp_ms)`
- `get_lambda_ast`, `get_lambda_ast_pretty`, `get_lambda_resolution`,
  `get_lambda_dot_resolved`
- `parse_tree_edit_op`

Re-exported from `lang/lambda/eval`:

- type `EvalResult`

## Consumers

- `ffi/lambda/` — JS FFI surface; calls `new_lambda_editor`,
  `apply_lambda_tree_edit`, `parse_tree_edit_op`, and the AST/pretty accessors.
- `editor/` (blackbox tests only) — uses `@lambda.get_lambda_ast` and related
  accessors to drive integration tests.
- `examples/ideal/main/` — additionally uses `LambdaCompanion`, `EvalResult`,
  `DropPosition`, `TreeEditOp`; imports `lang/lambda/edits` directly for the
  rest.

## Dependencies

`lang/lambda/edits`, `lang/lambda/eval`, `lang/lambda/companion`. The `proj`
subpackage is not re-exported here; consumers that need it should import it
directly.

## Stability

Experimental. Lambda is a legacy stress case for editor features, not the
template for adding a new language; use Markdown for that. The facade surface
evolves as features are wired up, and re-exports are added when new consumers
need them.

## Notes

There is no top-level logic in this package. Earlier revisions included a
`reconcile_ast.mbt` file re-exporting `@core.reconcile`, which had no callers
and was removed. Lambda's editor-facing projection memos now live in
`lang/lambda/proj` via `build_lambda_projection_memos`, a thin wrapper around
`@core.build_projection_memos`. Lambda's edit bridge intentionally remains
outside `LanguageSpec`; see
`docs/decisions/2026-06-15-lambda-edit-bridge-boundary.md`.
