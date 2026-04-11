// Lambda language facade — unified entry point for lambda editor types.

///|
pub using @lambda_proj {
  type FlatProj,
  syntax_to_proj_node,
  to_proj_node,
  parse_to_proj_node,
  rebuild_kind,
  to_flat_proj,
  to_flat_proj_incremental,
  reconcile_flat_proj,
  print_flat_proj,
  populate_token_spans,
}

///|
pub using @lambda_edits {
  type TreeEditOp,
  type EditContext,
  type EditResult,
  type FocusHint,
  type DropPosition,
  type ActionGroup,
  type Action,
  type NodeContext,
  type BindingSite,
  compute_text_edit,
  get_actions_for_node,
  resolve_binder,
  find_usages,
  find_binding_for_init,
  collect_lam_env,
  free_vars,
}

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
pub using @lambda_flat {type VersionedFlatProj, build_lambda_projection_memos}

///|
pub using @lambda_eval {
  type EvalResult,
  eval_term,
  build_eval_memo,
  inject_eval_annotations,
}
