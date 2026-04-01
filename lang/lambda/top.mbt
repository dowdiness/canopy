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
  type SpanEdit,
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
pub using @lambda_flat {type VersionedFlatProj}

///|
pub using @lambda_zipper {
  type Zipper,
  type Direction,
  type EditAction,
  type ActionRecord,
  type HoleInfo,
  type HoleRegistry,
  type PositionRole,
  type TermCtx,
  available_actions,
  depth,
  find_proj_node_for_focus,
  focus_at,
  from_root,
  go_down,
  go_left,
  go_right,
  go_up,
  navigate,
  path_indices_to_node,
  position_role,
  to_path_indices,
  to_root,
  to_tree_edit_op,
  zipper_from_node_id,
}
