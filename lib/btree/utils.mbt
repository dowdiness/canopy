///|
fn Array::sum(self : Array[Int]) -> Int {
  self.iter().fold(init=0, fn(acc, x) { acc + x })
}

///|
/// Cached span total: O(1) for both Leaf (stored span) and Internal (stored total).
pub fn[T] BTreeNode::total(self : BTreeNode[T]) -> Int {
  match self {
    Leaf(span~, ..) => span
    Internal(total~, ..) => total
  }
}

///|
fn[T] BTreeNode::is_full(self : BTreeNode[T], min_degree : Int) -> Bool {
  match self {
    Leaf(..) => false
    Internal(children~, ..) => children.length() >= 2 * min_degree
  }
}

///|
/// Slice positions are computed by the library — failure is an invariant violation.
fn[T : BTreeElem] must_slice(elem : T, start~ : Int, end~ : Int) -> T {
  @rle.Sliceable::slice(elem, start~, end~).unwrap()
}

///|
/// Prefix-sum search: walk cumulative counts to find which child slot
/// contains a given position. Returns (slot_index, remaining_offset).
///
/// `in_slot` determines boundary behavior:
/// - `fn(remaining, count) { remaining < count }` for reads/deletes (strict)
/// - `fn(remaining, count) { remaining <= count }` for inserts (inclusive)
fn[R] ArrayView::find_by_sum(
  self : ArrayView[Int],
  pos : Int,
  in_slot? : (Int, Int) -> Bool = fn(remaining, count) { remaining < count },
  f : (Int, Int) -> R?,
) -> R? {
  for view = self, remaining = pos, i = 0 {
    match (view, remaining, i) {
      ([], _, _) => break None
      ([count, ..], remaining, i) if in_slot(remaining, count) =>
        break f(i, remaining)
      ([count, .. rest], remaining, i) =>
        continue rest, remaining - count, i + 1
    }
  }
}
