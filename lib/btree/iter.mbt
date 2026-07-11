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
/// Lazy iterator: traverses leaves using cursor without allocating an array.
pub fn[T] BTree::iter(self : BTree[T]) -> Iter[T] {
  match self.root {
    None => Iter::empty()
    Some(root) => {
      let mut cursor : Cursor[T]? = Some(descend_leftmost(root, []))
      Iter::new(fn() {
        match cursor {
          None => None
          Some(cur) => {
            let elem = cur.leaf_elem
            cursor = cursor_next_leaf(cur)
            Some(elem)
          }
        }
      })
    }
  }
}
