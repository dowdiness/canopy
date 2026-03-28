// Capability traits for parameterizing ProjNode over different AST types.

///|
/// Tree structure capability — provides structural access for reconciliation and traversal.
pub(open) trait TreeNode {
  children(Self) -> Array[Self]
  same_kind(Self, Self) -> Bool
}

///|
/// Rendering + text capability — provides display and serialization for projections.
pub(open) trait Renderable {
  kind_tag(Self) -> String
  label(Self) -> String
  placeholder(Self) -> String
  unparse(Self) -> String
}

///|
/// A language-specific structural edit action for UI discovery (context menus, palette).
/// Language packages export these as data; the UI renders them without knowing their semantics.
pub struct EditAction[T] {
  /// Display label for the action
  label : String
  /// Optional keyboard shortcut (e.g., "Ctrl+D")
  shortcut : String?
  /// Predicate: is this action applicable to the given node?
  applicable : (ProjNode[T], NodeId) -> Bool
  /// Compute replacement text given (source_text, span_start, span_end).
  /// Returns Ok(replacement) or Err(reason).
  compute_replacement : (String, Int, Int) -> Result[String, String]
}
