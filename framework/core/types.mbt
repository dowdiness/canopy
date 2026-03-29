// Active runtime types for projection editing.

///|
/// Unique identifier for AST nodes (persistent across edits).
/// Construct via `NodeId::from_int(n)`.
pub struct NodeId(Int) derive(Show, Eq, Hash, Compare)

///|
pub fn NodeId::from_int(n : Int) -> NodeId {
  NodeId(n)
}

///|
/// A text span replacement computed by an edit handler.
pub(all) struct SpanEdit {
  start : Int
  delete_len : Int
  inserted : String
} derive(Show, Eq)

///|
/// Hint for where to place the cursor after a structural edit.
/// MoveCursor(position~) uses post-edit coordinates.
pub(all) enum FocusHint {
  RestoreCursor
  MoveCursor(position~ : Int)
} derive(Show, Eq)
