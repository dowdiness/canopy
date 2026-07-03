///|
pub using @core {type SpanEdit}

///|
/// Shared context for all edit handlers. Constructed by the editor bridge
/// and passed through the middleware pipeline to per-file handler functions.
pub(all) struct EditContext[T] {
  source_text : String
  source_map : SourceMap
  registry : Map[NodeId, ProjNode[T]]
  definition_index : DefinitionIndex
}

///|
pub type EditResult = (Array[SpanEdit], FocusHint)?

///|
/// Raises NodeNotInSourceMap if the source map lacks a range,
/// or NodeNotInRegistry if the registry lacks the node.
fn[T] EditContext::resolve(
  self : EditContext[T],
  node_id : NodeId,
) -> (ProjNode[T], @loomcore.Range) raise EditError {
  guard self.source_map.get_range(node_id) is Some(range) else {
    raise NodeNotInSourceMap(action="Resolve", node_id~)
  }
  guard self.registry.get(node_id) is Some(node) else {
    raise NodeNotInRegistry(action="Resolve", node_id~)
  }
  (node, range)
}

///|
/// Translate a TreeEditOp into text span edits.
/// Passes through FoldConstants and ValidateNodeExists middleware before
/// core dispatch. FoldConstants runs outermost so foldable patterns are
/// caught before validation.
pub fn compute_text_edit(
  op : TreeEditOp,
  ctx : EditContext[@ast.Term],
) -> EditResult raise EditError {
  FoldConstants::{  }.apply(
    fn(op_arg, ctx_arg) raise EditError {
      ValidateNodeExists::{  }.apply(core_dispatch, op_arg, ctx_arg)
    },
    op,
    ctx,
  )
}

///|
/// Exhaustive router: delegates each TreeEditOp variant to its handler file.
fn core_dispatch(
  op : TreeEditOp,
  ctx : EditContext[@ast.Term],
) -> EditResult raise EditError {
  match op {
    Select(..)
    | SelectRange(..)
    | StartEdit(..)
    | CancelEdit
    | StartDrag(..)
    | DragOver(..)
    | Collapse(..)
    | Expand(..) => Some(([], RestoreCursor))
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
