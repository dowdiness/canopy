// TreeNode and Renderable stay here (orphan rule).

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
