// Types for lambda edit operations.

///|
using @core {type NodeId}

///|
using @core {type ProjNode}

///|
using @core {type SourceMap}

///|
using @lambda_proj {
  type FlatProj,
  rebuild_kind,
  to_proj_node,
  parse_to_proj_node,
  populate_token_spans,
}

///|
using @loomcore {trait Renderable}

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
