///|
priv trait EditMiddleware {
  apply(Self, (TreeEditOp, EditContext) -> EditResult, TreeEditOp, EditContext) -> EditResult
}

///|
fn[M : EditMiddleware] wrap(
  middleware : M,
  inner : (TreeEditOp, EditContext) -> EditResult,
) -> (TreeEditOp, EditContext) -> EditResult {
  fn(op, ctx) { middleware.apply(inner, op, ctx) }
}

///|
priv struct ValidateNodeExists {}

///|
impl EditMiddleware for ValidateNodeExists with apply(_self, next, op, ctx) {
  match extract_primary_node_id(op) {
    Some(id) =>
      if ctx.registry.contains(id) {
        next(op, ctx)
      } else {
        Err("Node not found: " + id.to_string())
      }
    None => next(op, ctx)
  }
}

///|
fn extract_primary_node_id(op : TreeEditOp) -> NodeId? {
  match op {
    // No-ops: unconditional in core router, skip validation
    Select(_)
    | SelectRange(..)
    | StartEdit(_)
    | CancelEdit
    | StartDrag(_)
    | DragOver(..)
    | Collapse(_)
    | Expand(_) => None
    // Structural ops that require node lookup
    Delete(node_id~)
    | WrapInLambda(node_id~, ..)
    | WrapInApp(node_id~)
    | WrapInIf(node_id~)
    | WrapInBop(node_id~, ..)
    | Unwrap(node_id~, ..)
    | SwapChildren(node_id~)
    | ChangeOperator(node_id~, ..)
    | CommitEdit(node_id~, ..)
    | ExtractToLet(node_id~, ..)
    | InlineDefinition(node_id~)
    | Rename(node_id~, ..) => Some(node_id)
    Drop(source~, ..) => Some(source)
    InsertChild(parent~, ..) => Some(parent)
    DeleteBinding(binding_node_id~)
    | DuplicateBinding(binding_node_id~)
    | MoveBindingUp(binding_node_id~)
    | MoveBindingDown(binding_node_id~)
    | InlineAllUsages(binding_node_id~) => Some(binding_node_id)
    AddBinding(module_node_id~) => Some(module_node_id)
  }
}
