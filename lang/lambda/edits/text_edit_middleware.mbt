///|
/// Middleware wraps core dispatch with cross-cutting concerns.
/// Each middleware receives `next` (the inner handler) and can
/// short-circuit or delegate — SuperOOP's `super` pattern.
priv trait EditMiddleware {
  fn apply(
    Self,
    (TreeEditOp, EditContext[@ast.Term]) -> EditResult raise EditError,
    TreeEditOp,
    EditContext[@ast.Term],
  ) -> EditResult raise EditError
}

///|
/// Rejects structural ops whose primary node ID is missing from the registry.
/// No-op ops (Select, Collapse, etc.) bypass validation.
priv struct ValidateNodeExists {}

///|
impl EditMiddleware for ValidateNodeExists with fn apply(_self, next, op, ctx) {
  match extract_primary_node_id(op) {
    Some(id) =>
      if ctx.registry.contains(id) {
        next(op, ctx)
      } else {
        raise NodeNotFound(action="Validate", node_id=id)
      }
    None => next(op, ctx)
  }
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

///|
/// Fold constants at edit time: when a CommitEdit targets a Bop node
/// with both Int children (e.g. `1 + 2`), replace the entire expression
/// with the folded result (e.g. `3`). Only fires on CommitEdit — structural
/// ops (SwapChildren, Unwrap, ChangeOperator, etc.) delegate to core_dispatch
/// unchanged.
priv struct FoldConstants {}

///|
impl EditMiddleware for FoldConstants with fn apply(_self, next, op, ctx) {
  match try_fold_constant(op, ctx) {
    Some(result) => result
    None => next(op, ctx)
  }
}

///|
/// Attempt to fold Bop(Plus, Int(a), Int(b)) → Int(a + b)
/// or Bop(Minus, Int(a), Int(b)) → Int(a - b).
/// Only triggers on CommitEdit (user replacing text at the Bop node).
fn try_fold_constant(
  op : TreeEditOp,
  ctx : EditContext[@ast.Term],
) -> EditResult? {
  let node_id = match op {
    CommitEdit(node_id~, ..) => node_id
    _ => return None
  }
  let node = match ctx.registry.get(node_id) {
    Some(n) => n
    None => return None
  }
  match node.kind {
    @ast.Term::Bop(op_kind, @ast.Term::Int(a), @ast.Term::Int(b)) => {
      let folded = match op_kind {
        @ast.Bop::Plus => a + b
        @ast.Bop::Minus => a - b
      }
      let range = match ctx.source_map.get_range(node_id) {
        Some(r) => r
        None => return None
      }
      let fold_text = folded.to_string()
      Some(
        Some(
          (
            [
              {
                start: range.start,
                delete_len: range.end - range.start,
                inserted: fold_text,
              },
            ],
            RestoreCursor,
          ),
        ),
      )
    }
    _ => None
  }
}
