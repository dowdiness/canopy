// Rose tree zipper library — types and constructors.
//
// A zipper (Huet 1997) turns an immutable tree inside-out around a focus
// point, enabling efficient local navigation without mutating the original tree.
// Lateral moves (go_left, go_right) are O(1); vertical moves (go_down, go_up)
// are O(n) where n is the number of children at the relevant node.
//
//   RoseNode[T]   — the tree itself: data of type T with ordered children.
//   RoseCtx[T]    — one-hole context: the "derivative" of RoseNode (McBride 2001).
//                   Stores the parent's data plus left and right sibling lists
//                   so the parent can be reconstructed when navigating up.
//   RoseZipper[T] — a position within a tree: the focused subtree plus a
//                   stack of contexts from focus to root.
//
// The context type is uniform in T — the same zipper shape works regardless
// of what data the nodes carry. No per-language codegen is needed.

///|
pub(all) struct RoseNode[T] {
  data : T
  children : Array[RoseNode[T]]
} derive(Debug, Eq)

///|
pub impl[T : Debug] Show for RoseNode[T] with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub fn[T] RoseNode::new(
  data~ : T,
  children? : Array[RoseNode[T]] = [],
) -> RoseNode[T] {
  { data, children }
}

///|
/// One-hole context for a rose tree node. Stores everything needed to
/// reconstruct the parent: its data, the siblings to the left and right
/// of the focused child, and the child's index.
///
/// `left` is stored in reverse order (nearest sibling first) so that
/// go_left/go_right are O(1) list cons/uncons operations.
pub(all) struct RoseCtx[T] {
  data : T
  left : @list.List[RoseNode[T]]
  right : @list.List[RoseNode[T]]
  index : Int
} derive(Debug, Eq)

///|
pub impl[T : Debug] Show for RoseCtx[T] with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// A focused position within a rose tree. `focus` is the current subtree,
/// `path` is the stack of contexts from focus to root (innermost first).
/// `depth` is cached (invariant: depth == path.length()) for O(1) queries.
pub(all) struct RoseZipper[T] {
  focus : RoseNode[T]
  path : @list.List[RoseCtx[T]]
  depth : Int
} derive(Debug, Eq)

///|
pub impl[T : Debug] Show for RoseZipper[T] with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub fn[T] RoseZipper::from_root(tree : RoseNode[T]) -> RoseZipper[T] {
  { focus: tree, path: @list.List::default(), depth: 0 }
}
