// Active runtime types for projection editing.

///|
using @loomcore {type Range}

///|
/// Unique identifier for AST nodes (persistent across edits)
pub struct NodeId(Int) derive(Show, Eq, Hash, Compare)

///|
/// Construct a NodeId from a raw integer.
/// Used by cross-package JSON parsers that cannot directly construct NodeId.
pub fn NodeId::from_int(n : Int) -> NodeId {
  NodeId(n)
}

///|
/// Drop position for drag-and-drop operations
pub(all) enum DropPosition {
  /// Insert before the target
  Before
  /// Insert after the target
  After
  /// Insert as a child of the target
  Inside
} derive(Show, Eq)

///|
/// Hint for where to place the cursor after a structural edit.
/// MoveCursor(position~) uses post-edit coordinates — the bridge applies them directly.
pub(all) enum FocusHint {
  RestoreCursor
  MoveCursor(position~ : Int)
} derive(Show, Eq)
