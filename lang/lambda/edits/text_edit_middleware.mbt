///|
/// Middleware wraps core dispatch with cross-cutting concerns.
/// Each middleware receives `next` (the inner handler) and can
/// short-circuit or delegate — SuperOOP's `super` pattern.
priv trait EditMiddleware {
  fn apply(
    Self,
    (TreeEditOp, EditContext[@ast.Term]) -> EditResult,
    TreeEditOp,
    EditContext[@ast.Term],
  ) -> EditResult
}

///|
/// Rejects structural ops whose primary node ID is missing from the registry.
/// No-op ops (Select, Collapse, etc.) bypass validation.
priv struct ValidateNodeExists {}

///|
impl EditMiddleware for ValidateNodeExists with fn apply(_self, next, op, ctx) {
  match extract_primary_node_id(op) {
    Some(id) =>
      if ctx.registry.contains(id) ||
        (
          op_accepts_binding_id(op) &&
          flat_proj_contains_binding_id(ctx.flat_proj, id)
        ) {
        next(op, ctx)
      } else {
        Err("Node not found: " + id.to_string())
      }
    None => next(op, ctx)
  }
}

///|
fn op_accepts_binding_id(op : TreeEditOp) -> Bool {
  match op {
    Rename(..)
    | DeleteBinding(..)
    | DuplicateBinding(..)
    | MoveBindingUp(..)
    | MoveBindingDown(..)
    | InlineAllUsages(..) => true
    _ => false
  }
}

///|
fn flat_proj_contains_binding_id(
  flat_proj : FlatProj,
  node_id : NodeId,
) -> Bool {
  flat_proj.defs.iter().any(fn(def) { def.3 == node_id })
}

///|
/// Returns the primary target node for ops that require registry lookup.
/// Returns None for no-ops so they bypass validation.
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
