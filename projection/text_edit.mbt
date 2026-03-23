///|
/// A text span replacement: replace source_text[start : start+delete_len] with inserted.
pub(all) struct SpanEdit {
  start : Int
  delete_len : Int
  inserted : String
} derive(Show, Eq)

///|
pub(all) struct EditContext {
  source_text : String
  source_map : SourceMap
  registry : Map[NodeId, ProjNode]
  flat_proj : FlatProj
}

///|
pub type EditResult = Result[(Array[SpanEdit], FocusHint)?, String]

///|
/// Translate a TreeEditOp into text span edits using the source map.
/// Wraps core_dispatch with middleware (currently: ValidateNodeExists).
pub fn compute_text_edit(op : TreeEditOp, ctx : EditContext) -> EditResult {
  let pipeline = wrap(ValidateNodeExists::{  }, core_dispatch)
  pipeline(op, ctx)
}

///|
/// Core dispatch: routes each TreeEditOp variant to its handler.
/// All TreeEditOp variants are handled — no fallback to the old path.
/// Returns Some([]) for no-op ops (Select, Collapse, etc.).
fn core_dispatch(op : TreeEditOp, ctx : EditContext) -> EditResult {
  match op {
    // No-op operations — these don't modify source text
    Select(..)
    | SelectRange(..)
    | StartEdit(..)
    | CancelEdit
    | StartDrag(..)
    | DragOver(..)
    | Collapse(..)
    | Expand(..) => Ok(Some(([], RestoreCursor)))
    // CommitEdit: replace node span with new user-provided text
    CommitEdit(node_id~, new_value~) => compute_commit(ctx, node_id, new_value)
    // Delete: replace node with placeholder, re-rendering parent for normalization.
    // Special case: if parent is error, remove entirely.
    Delete(node_id~) => compute_delete(ctx, node_id)
    // WrapInLambda: wrap node text in a lambda abstraction
    WrapInLambda(node_id~, var_name~) =>
      compute_wrap_lambda(ctx, node_id, var_name)
    // WrapInApp: wrap node text in an application
    WrapInApp(node_id~) => compute_wrap_app(ctx, node_id)
    // InsertChild: insert a new child at the given index
    InsertChild(parent~, index~, kind~) =>
      compute_insert_child(ctx, parent, index, kind)
    // Unwrap: replace a node with one of its children
    Unwrap(node_id~, keep_child_index~) =>
      compute_unwrap(ctx, node_id, keep_child_index)
    // WrapInIf: wrap a node in an if-then-else with placeholder condition
    WrapInIf(node_id~) => compute_wrap_if(ctx, node_id)
    // WrapInBop: wrap a node in a binary operation with placeholder right operand
    WrapInBop(node_id~, op~) => compute_wrap_bop(ctx, node_id, op)
    // ChangeOperator: change the operator of a Bop node
    ChangeOperator(node_id~, new_op~) =>
      compute_change_operator(ctx, node_id, new_op)
    // SwapChildren: swap left/right children of Bop, or then/else of If
    SwapChildren(node_id~) => compute_swap_children(ctx, node_id)
    // DeleteBinding: remove a let binding line from a Module
    DeleteBinding(binding_node_id~) =>
      compute_delete_binding(ctx, binding_node_id)
    // DuplicateBinding: copy a binding below with _copy suffix on name
    DuplicateBinding(binding_node_id~) =>
      compute_duplicate_binding(ctx, binding_node_id)
    // MoveBindingUp: swap a binding with its predecessor
    MoveBindingUp(binding_node_id~) =>
      compute_move_binding_up(ctx, binding_node_id)
    // MoveBindingDown: swap a binding with its successor
    MoveBindingDown(binding_node_id~) =>
      compute_move_binding_down(ctx, binding_node_id)
    // AddBinding: delegate to InsertChild for Module nodes
    AddBinding(module_node_id~) => compute_add_binding(ctx, module_node_id)
    // Drop: move a node from source to target position
    Drop(source~, target~, position~) =>
      compute_drop(ctx, source, target, position)
    // ExtractToLet: extract a sub-expression into a new let binding
    ExtractToLet(node_id~, var_name~) =>
      compute_extract_to_let(ctx, node_id, var_name)
    // InlineDefinition: inline a single Var usage of a module binding
    InlineDefinition(node_id~) => compute_inline_definition(ctx, node_id)
    // InlineAllUsages: replace all usages of a binding and remove the binding
    InlineAllUsages(binding_node_id~) =>
      compute_inline_all_usages(ctx, binding_node_id)
    // Rename: scope-aware renaming of variables and bindings
    Rename(node_id~, new_name~) => compute_rename(ctx, node_id, new_name)
  }
}
