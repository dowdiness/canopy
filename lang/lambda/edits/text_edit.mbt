///|
pub using @core {type SpanEdit}

///|
/// Shared context for all edit handlers. Constructed by the editor bridge
/// and passed through the middleware pipeline to per-file handler functions.
pub(all) struct EditContext[T] {
  source_text : String
  source_map : SourceMap
  registry : Map[NodeId, ProjNode[T]]
  flat_proj : FlatProj
}

///|
pub type EditResult = Result[(Array[SpanEdit], FocusHint)?, String]

///|
/// Translate a TreeEditOp into text span edits.
/// Passes through ValidateNodeExists middleware before core dispatch.
pub fn compute_text_edit(
  op : TreeEditOp,
  ctx : EditContext[@ast.Term],
) -> EditResult {
  ValidateNodeExists::{  }.apply(core_dispatch, op, ctx)
}

///|
/// Exhaustive router: delegates each TreeEditOp variant to its handler file.
fn core_dispatch(op : TreeEditOp, ctx : EditContext[@ast.Term]) -> EditResult {
  match op {
    Select(..)
    | SelectRange(..)
    | StartEdit(..)
    | CancelEdit
    | StartDrag(..)
    | DragOver(..)
    | Collapse(..)
    | Expand(..) => Ok(Some(([], RestoreCursor)))
    CommitEdit(node_id~, new_value~) => compute_commit(ctx, node_id, new_value)
    Delete(node_id~) => compute_delete(ctx, node_id)
    WrapInLambda(node_id~, var_name~) =>
      compute_wrap_lambda(ctx, node_id, var_name)
    WrapInApp(node_id~) => compute_wrap_app(ctx, node_id)
    InsertChild(parent~, index~, kind~) =>
      compute_insert_child(ctx, parent, index, kind)
    Unwrap(node_id~, keep_child_index~) =>
      compute_unwrap(ctx, node_id, keep_child_index)
    WrapInIf(node_id~) => compute_wrap_if(ctx, node_id)
    WrapInBop(node_id~, op~) => compute_wrap_bop(ctx, node_id, op)
    ChangeOperator(node_id~, new_op~) =>
      compute_change_operator(ctx, node_id, new_op)
    SwapChildren(node_id~) => compute_swap_children(ctx, node_id)
    DeleteBinding(binding_node_id~) =>
      compute_delete_binding(ctx, binding_node_id)
    DuplicateBinding(binding_node_id~) =>
      compute_duplicate_binding(ctx, binding_node_id)
    MoveBindingUp(binding_node_id~) =>
      compute_move_binding_up(ctx, binding_node_id)
    MoveBindingDown(binding_node_id~) =>
      compute_move_binding_down(ctx, binding_node_id)
    AddBinding(module_node_id~) => compute_add_binding(ctx, module_node_id)
    Drop(source~, target~, position~) =>
      compute_drop(ctx, source, target, position)
    ExtractToLet(node_id~, var_name~) =>
      compute_extract_to_let(ctx, node_id, var_name)
    InlineDefinition(node_id~) => compute_inline_definition(ctx, node_id)
    InlineAllUsages(binding_node_id~) =>
      compute_inline_all_usages(ctx, binding_node_id)
    Rename(node_id~, new_name~) => compute_rename(ctx, node_id, new_name)
  }
}
