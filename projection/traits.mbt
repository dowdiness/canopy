// Capability traits for parameterizing ProjNode over different AST types.

///|
/// Tree structure capability — provides structural access for reconciliation and traversal.
pub trait TreeNode {
  children(Self) -> Array[Self]
  same_kind(Self, Self) -> Bool
}

///|
/// Rendering + text capability — provides display and serialization for projections.
pub trait Renderable {
  kind_tag(Self) -> String
  label(Self) -> String
  placeholder(Self) -> String
  unparse(Self) -> String
}
