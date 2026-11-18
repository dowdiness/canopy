///|
/// Add one non-negative span without allowing `Int` wraparound.
/// MoonBit core has no checked-add API, so this package keeps the range
/// decision in a small deterministic helper instead of widening then
/// truncating through `Int64`.
fn checked_span_add(total : Int32, span : Int32) -> Int32? {
  guard total >= 0 && span >= 0 else { return None }
  guard total <= @int.MAX_VALUE - span else { return None }
  Some(total + span)
}

///|
/// Convert an internal checked-add decision to the package's established
/// deterministic abort contract without changing any public error signature.
fn add_spans_or_abort(total : Int32, span : Int32) -> Int32 {
  match checked_span_add(total, span) {
    Some(result) => result
    None => abort("BTree: cumulative span must be in 0..=@int.MAX_VALUE")
  }
}

///|
/// Reuse core `ArrayView::fold` to validate and sum cached child spans.
fn ArrayView::checked_span_sum(self : ArrayView[Int32]) -> Int32? {
  self.fold(init=Some(0), fn(total, span) {
    match total {
      Some(acc) => checked_span_add(acc, span)
      None => None
    }
  })
}

///|
/// Sum cached child spans or reject an invalid cumulative range.
fn Array::sum(self : Array[Int32]) -> Int32 {
  match self[:].checked_span_sum() {
    Some(total) => total
    None => abort("BTree: cumulative span must be in 0..=@int.MAX_VALUE")
  }
}

///|
/// Compute the prospective tree total for a leaf-parent splice without
/// mutating either the current tree or its copy-on-write candidate path.
fn[T] checked_splice_total(
  tree_total : Int32,
  parent_counts : Array[Int32],
  splice : Splice[T],
) -> Int32? {
  guard splice.start_idx >= 0 &&
    splice.start_idx <= splice.end_idx &&
    splice.end_idx <= parent_counts.length() else {
    return None
  }
  let removed = parent_counts[splice.start_idx:splice.end_idx].checked_span_sum()
  let added = splice.new_leaves.fold(init=Some(0), fn(total, pair) {
    guard pair.1 > 0 else { return None }
    match total {
      Some(acc) => checked_span_add(acc, pair.1)
      None => None
    }
  })
  match (removed, added) {
    (Some(removed), Some(added)) if removed <= tree_total =>
      checked_span_add(tree_total - removed, added)
    _ => None
  }
}

///|
/// Largest minimum degree whose doubling remains within `Int`.
const MAX_SAFE_MIN_DEGREE : Int32 = @int.MAX_VALUE / 2

///|
fn clamp_min_degree(min_degree : Int32) -> Int32 {
  min_degree.clamp(min=2, max=MAX_SAFE_MIN_DEGREE)
}

///|
/// Reject invalid leaf spans before a constructor or splice mutates tree state.
fn[T] validate_positive_spans(
  items : Array[(T, Int32)],
  operation : String,
) -> Unit {
  guard items.all(pair => pair.1 > 0) else {
    abort("\{operation}: leaf spans must be positive")
  }
}

///|
/// Wrap an array of child nodes into an Internal node with computed counts/total.
fn[T] make_internal(children : Array[BTreeNode[T]]) -> BTreeNode[T] {
  let counts : Array[Int32] = children.map(fn(n) { n.total() })
  Internal(children~, counts~, total=counts.sum())
}

///|
/// Cached span total: O(1) for both Leaf (stored span) and Internal (stored total).
pub fn[T] BTreeNode::total(self : BTreeNode[T]) -> Int32 {
  match self {
    Leaf(span~, ..) => span
    Internal(total~, ..) => total
  }
}

///|
fn[T] BTreeNode::is_full(self : BTreeNode[T], min_degree : Int32) -> Bool {
  match self {
    Leaf(..) => false
    Internal(children~, ..) => children.length() >= 2 * min_degree
  }
}

///|
/// Slice positions are computed by the library — failure is an invariant violation.
fn[T : BTreeElem] must_slice(elem : T, start~ : Int32, end~ : Int32) -> T {
  @rle.Sliceable::slice(elem, start~, end~) catch {
    error => abort("must_slice: invariant violated: \{error}")
  }
}

///|
/// Prefix-sum search: walk cumulative counts to find which child slot
/// contains a given position. Returns (slot_index, remaining_offset).
///
/// `in_slot` determines boundary behavior:
/// - `fn(remaining, count) { remaining < count }` for reads/deletes (strict)
/// - `fn(remaining, count) { remaining <= count }` for inserts (inclusive)
fn[R] ArrayView::find_by_sum(
  self : ArrayView[Int32],
  pos : Int32,
  in_slot~ : (Int32, Int32) -> Bool = fn(remaining, count) { remaining < count },
  f : (Int32, Int32) -> R?,
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
