///|
pub(all) enum EditAction {
  Delete
  WrapLam(String)
  WrapApp
  WrapIf
  WrapBop(@ast.Bop)
  Unwrap(Int)
  SwapChildren
  ChangeOperator(@ast.Bop)
  CommitEdit(String)
} derive(Show)

///|
pub(all) enum Direction {
  Up
  Down
  Left
  Right
} derive(Show)

///|
pub(all) struct ActionRecord {
  action : EditAction
  cursor_before : @core.NodeId
  cursor_after : @core.NodeId
  role : PositionRole
} derive(Show)

///|
pub fn to_tree_edit_op(
  cursor : @core.NodeId,
  action : EditAction,
) -> @edits.TreeEditOp {
  match action {
    Delete => @edits.TreeEditOp::Delete(node_id=cursor)
    WrapLam(name) =>
      @edits.TreeEditOp::WrapInLambda(node_id=cursor, var_name=name)
    WrapApp => @edits.TreeEditOp::WrapInApp(node_id=cursor)
    WrapIf => @edits.TreeEditOp::WrapInIf(node_id=cursor)
    WrapBop(op) => @edits.TreeEditOp::WrapInBop(node_id=cursor, op~)
    Unwrap(idx) =>
      @edits.TreeEditOp::Unwrap(node_id=cursor, keep_child_index=idx)
    SwapChildren => @edits.TreeEditOp::SwapChildren(node_id=cursor)
    ChangeOperator(op) =>
      @edits.TreeEditOp::ChangeOperator(node_id=cursor, new_op=op)
    CommitEdit(text) =>
      @edits.TreeEditOp::CommitEdit(node_id=cursor, new_value=text)
  }
}
