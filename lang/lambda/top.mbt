// Lambda language facade — unified entry point for lambda editor types.
//
// Only re-exports symbols that are actually consumed today (by editor/,
// ffi/lambda/, and examples/ideal). The previous version re-exported the full
// surface of the proj/edits/eval/flat/companion subpackages, but most of
// those re-exports had no callers — they were vestiges of an earlier wiring.
// Removed re-exports can be re-added when a new consumer needs them.
// Consumers that already import a subpackage directly do not need an
// aggregator re-export.

///|
pub using @lambda_edits {type TreeEditOp, type DropPosition}

///|
pub using @lambda_companion {
  type LambdaCompanion,
  new_lambda_editor,
  apply_lambda_tree_edit,
  get_lambda_ast,
  get_lambda_ast_pretty,
  get_lambda_resolution,
  get_lambda_dot_resolved,
  parse_tree_edit_op,
}

///|
pub using @lambda_eval {type EvalResult}
