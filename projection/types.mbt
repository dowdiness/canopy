// Re-export types from framework/core and lang/lambda/edits for backward compatibility.

///|
using @loomcore {type Range}

///|
pub using @core {type NodeId}

///|
// Re-export lambda edit types so editor/ can use @proj.TreeEditOp etc.
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
