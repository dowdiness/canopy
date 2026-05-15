# lang/lambda

Thin facade for the lambda-calculus editor language. Re-exports the handful of types and functions that consumers (`editor/` tests and `ffi/lambda/`) actually call through this path, sourced from the five subpackages `proj`, `edits`, `eval`, `flat`, `companion`.

The facade was originally much larger; in 2026-05 it was trimmed to the symbols with live callers. Consumers that need more reach into the subpackages directly (see `examples/ideal/main/moon.pkg`).

## Public API

Re-exported from `lang/lambda/edits`:
- type `TreeEditOp`
- type `DropPosition` (canonical origin is `@core`; `lang/lambda/edits` re-re-exports it, so consumers see it through either path)

Re-exported from `lang/lambda/companion`:
- type `LambdaCompanion`
- `new_lambda_editor(source) -> (SyncEditor[Term], LambdaCompanion)`
- `apply_lambda_tree_edit(editor, companion, op, cursor)`
- `get_lambda_ast`, `get_lambda_ast_pretty`, `get_lambda_resolution`, `get_lambda_dot_resolved`
- `parse_tree_edit_op`

Re-exported from `lang/lambda/eval`:
- type `EvalResult`

## Consumers

- `ffi/lambda/` — JS FFI surface; calls `new_lambda_editor`, `apply_lambda_tree_edit`, `parse_tree_edit_op`, and the AST/pretty accessors.
- `editor/` (blackbox tests only) — uses `@lambda.get_lambda_ast` and related accessors to drive integration tests.
- `examples/ideal/main/` — additionally uses `LambdaCompanion`, `EvalResult`, `DropPosition`, `TreeEditOp`; imports `lang/lambda/edits` directly for the rest.

## Dependencies

`lang/lambda/edits`, `lang/lambda/eval`, `lang/lambda/companion`. The `proj` and `flat` subpackages exist but are not re-exported here; consumers that need them (none today) should import them directly.

## Stability

Experimental — the lambda language is the reference implementation for new editor features. The facade surface evolves as features are wired up; expect re-exports to be added as new consumers appear.

## Notes

There is no top-level logic in this package. Earlier revisions included a `reconcile_ast.mbt` file re-exporting `@core.reconcile`, which had no callers and was removed. The reference for incremental projection over the lambda AST lives in `lang/lambda/flat` (`VersionedFlatProj`, `build_lambda_projection_memos`); import that subpackage directly if needed.
