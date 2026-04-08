///|
fn[T] BTreeNode::navigate(self : BTreeNode[T], pos : Int) -> FindResult[T]? {
  descend(self, pos, 0, prepare_noop, find_slot, false).map(fn(cursor) {
    { elem: cursor.leaf_elem, offset: cursor.offset }
  })
}
