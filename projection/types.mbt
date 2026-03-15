// Active runtime types for projection editing.

///|
using @loomcore {type Range}

///|
/// Unique identifier for AST nodes (persistent across edits)
pub struct NodeId(Int) derive(Show, Eq, Hash, Compare)

///|
/// Drop position for drag-and-drop operations
pub enum DropPosition {
  /// Insert before the target
  Before
  /// Insert after the target
  After
  /// Insert as a child of the target
  Inside
} derive(Show, Eq)
