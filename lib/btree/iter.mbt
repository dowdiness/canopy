///|
pub fn[T] BTreeNode::each(self : BTreeNode[T], f : (T) -> Unit) -> Unit {
  match self {
    Leaf(elem~, ..) => f(elem)
    Internal(children~, ..) => children.each(fn(child) { child.each(f) })
  }
}

///|
pub fn[T] BTree::each(self : BTree[T], f : (T) -> Unit) -> Unit {
  match self.root {
    Some(node) => node.each(f)
    _ => ()
  }
}

///|
pub fn[T] BTree::to_array(self : BTree[T]) -> Array[T] {
  let result : Array[T] = []
  self.each(fn(elem) { result.push(elem) })
  result
}

///|
/// Eager iterator: materializes to_array() first. For streaming traversal
/// without allocation, use each() or BTreeNode::each_slice_in_range().
pub fn[T] BTree::iter(self : BTree[T]) -> Iter[T] {
  let arr = self.to_array()
  let mut i = 0
  Iter::new(fn() {
    if i < arr.length() {
      let elem = arr[i]
      i = i + 1
      Some(elem)
    } else {
      None
    }
  })
}
