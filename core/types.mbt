// Active runtime types for projection editing.

///|
/// Unique identifier for AST nodes (persistent across edits).
/// Construct via `NodeId::from_int(n)`.
pub struct NodeId(Int) derive(Debug, Eq, Hash, Compare)

///|
pub impl Show for NodeId with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub fn NodeId::from_int(n : Int) -> NodeId {
  NodeId(n)
}

///|
pub impl ToJson for NodeId with to_json(self) {
  let NodeId(n) = self
  n.to_json()
}

///|
/// A text span replacement computed by an edit handler.
pub(all) struct SpanEdit {
  start : Int
  delete_len : Int
  inserted : String
} derive(Debug, Eq)

///|
pub impl Show for SpanEdit with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Hint for where to place the cursor after a structural edit.
/// MoveCursor(position~) uses post-edit coordinates.
pub(all) enum FocusHint {
  RestoreCursor
  MoveCursor(position~ : Int)
} derive(Debug, Eq)

///|
pub impl Show for FocusHint with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Drop position for drag-and-drop and move operations.
pub(all) enum DropPosition {
  /// Insert before the target
  Before
  /// Insert after the target
  After
  /// Insert as a child of the target
  Inside
} derive(Debug, Eq)
