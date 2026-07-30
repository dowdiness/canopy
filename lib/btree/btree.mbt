///|
/// Create an empty tree. `min_degree` is normalized to the inclusive interval
/// `[2, @int.MAX_VALUE / 2]`.
pub fn[T] BTree::new(min_degree? : Int = DEFAULT_MIN_DEGREE) -> BTree[T] {
  { root: None, min_degree: clamp_min_degree(min_degree), size: 0 }
}

///|
pub fn[T] BTree::size(self : BTree[T]) -> Int {
  self.size
}

///|
pub fn[T] BTree::span(self : BTree[T]) -> Int {
  match self.root {
    Some(node) => node.total()
    _ => 0
  }
}

///|
pub fn[T] BTree::is_empty(self : BTree[T]) -> Bool {
  self.root is None
}

///|
pub fn[T] BTree::get_at(self : BTree[T], pos : Int) -> T? {
  guard pos >= 0 else { return None }
  self.find(pos).map(fn(r) { r.elem })
}

///|
pub fn[T] BTree::find(self : BTree[T], pos : Int) -> FindResult[T]? {
  guard pos >= 0 else { return None }
  match self.root {
    Some(node) => node.navigate(pos)
    _ => None
  }
}

///|
/// Mutate a non-empty tree at a span position in the inclusive interval
/// `[0, span()]`; use `init_root` for the first element. An empty tree or a
/// position outside that interval aborts.
///
/// The callback receives a `LeafContext` snapshot and returns a `Splice`
/// description. The tree applies it, rebalances, and updates size. Every span
/// in the returned splice must be positive. A prospective cumulative span
/// above `@int.MAX_VALUE` aborts before the copy-on-write candidate is published.
pub fn[T] BTree::mutate_for_insert(
  self : BTree[T],
  pos : Int,
  f : (LeafContext[T]) -> Splice[T],
) -> Unit {
  // Empty tree must be initialized via init_root before mutating.
  // Silent no-op would lose the insert with no signal.
  match self.root {
    None =>
      abort("BTree::mutate_for_insert: tree is empty, use init_root first")
    Some(root) => {
      // Bounds check before descend — prepare_split may mutate the tree, so
      // reject invalid positions before any structural preparation begins.
      guard pos >= 0 && pos <= root.total() else {
        abort("BTree::mutate_for_insert: position out of bounds")
      }
      let cursor = match
        descend(
          root,
          pos,
          self.min_degree,
          prepare_split,
          find_slot_inclusive,
          true,
          copy_on_write=true,
        ) {
        Some(c) => c
        None => abort("BTree::mutate_for_insert: descent failed")
      }
      let leaf_ctx = LeafContext::from_cursor(cursor)
      let splice = f(leaf_ctx)
      validate_positive_spans(splice.new_leaves, "BTree splice")
      let leaf_parent = cursor.path[cursor.path.length() - 1]
      guard checked_splice_total(root.total(), leaf_parent.counts, splice)
        is Some(_) else {
        abort("BTree: cumulative span must be in 0..=@int.MAX_VALUE")
      }
      let propagated = propagate(cursor.path, splice, self.min_degree)
      self.apply_propagated(propagated, normalize_delete=true)
    }
  }
}

///|
/// Mutate the leaf containing span position `pos`, where
/// `0 <= pos < span()`. Returns the callback's payload, or `None` without
/// calling the callback when the tree is empty or `pos` is out of bounds.
/// Every span in the returned splice must be positive. A prospective cumulative
/// span above `@int.MAX_VALUE` aborts without publishing the candidate tree.
pub fn[T, R] BTree::mutate_for_delete(
  self : BTree[T],
  pos : Int,
  f : (LeafContext[T]) -> (Splice[T], R),
) -> R? {
  match self.root {
    None => None
    Some(root) => {
      // Bounds check before descend — prepare_ensure_min mutates the tree,
      // so we must not descend with an out-of-range position.
      guard pos >= 0 && pos < root.total() else { return None }
      match
        descend(
          root,
          pos,
          self.min_degree,
          prepare_ensure_min,
          find_slot,
          false,
          copy_on_write=true,
        ) {
        None => None
        Some(cursor) => {
          let leaf_ctx = LeafContext::from_cursor(cursor)
          let (splice, payload) = f(leaf_ctx)
          validate_positive_spans(splice.new_leaves, "BTree splice")
          let leaf_parent = cursor.path[cursor.path.length() - 1]
          guard checked_splice_total(root.total(), leaf_parent.counts, splice)
            is Some(_) else {
            abort("BTree: cumulative span must be in 0..=@int.MAX_VALUE")
          }
          let propagated = propagate(cursor.path, splice, self.min_degree)
          self.apply_propagated(propagated, normalize_delete=true)
          Some(payload)
        }
      }
    }
  }
}

///|
/// Merge the canonical closure at logical span boundary `pos`. This is a no-op
/// for an empty tree, an outer boundary, a position inside a leaf, or stable
/// non-mergeable neighbors. For `m` merged boundaries, runs in
/// `O((m + 1) log n)` time for a fixed minimum degree.
pub fn[T : @rle.Spanning + @rle.Mergeable] BTree::normalize_boundary_at(
  self : BTree[T],
  pos : Int,
) -> Unit {
  guard self.root is Some(root) else { return }
  let (next_root, leaf_delta) = normalize_boundary_chain(
    root,
    pos,
    self.min_degree,
  )
  guard leaf_delta != 0 else { return }
  let next_size = self.size + leaf_delta
  self.root = Some(next_root)
  self.size = next_size
}

///|
/// Delete the half-open span range `[start, end_)`, clamping an oversized end
/// to `span()`. This is a no-op for an empty tree, a negative start, an empty
/// or reversed range, or `start >= span()`. Splice, boundary merge, and repair
/// complete on an unpublished copy-on-write candidate before one final update.
pub fn[T : BTreeElem] BTree::delete_range(
  self : BTree[T],
  start : Int,
  end_ : Int,
) -> Unit {
  guard self.root is Some(root) else { return }
  let total = root.total()
  guard start >= 0 && start < end_ && start < total else { return }
  let clamped_end = if end_ > total { total } else { end_ }
  match plan_delete_range(root, start, clamped_end, self.min_degree) {
    None => ()
    Some(splice) => {
      let propagated = propagate_node_splice(splice, self.min_degree)
      // Keep every range-delete phase on an unpublished candidate. A late
      // boundary-merge or repair rejection must leave the original tree intact.
      let (final_root, boundary_leaf_delta) = match
        propagated.root_candidate(self.min_degree, normalize_delete=false) {
        None => (None, 0)
        Some(new_root) => {
          let (merged_root, boundary_leaf_delta) = normalize_boundary_chain(
            new_root,
            start,
            self.min_degree,
          )
          // Collapse unary root wrappers, fix underfull descendants, then
          // collapse again (fix_merged_chain may create new unary roots).
          let final_root = match normalize_root_after_delete(merged_root) {
            None => None
            Some(collapsed) => {
              let fixed = fix_merged_chain(collapsed, self.min_degree)
              normalize_root_after_delete(fixed)
            }
          }
          (final_root, boundary_leaf_delta)
        }
      }
      let final_size = self.size + propagated.leaf_delta + boundary_leaf_delta
      self.root = final_root
      self.size = final_size
    }
  }
}

///|
fn[T] PropagateResult::root_candidate(
  self : PropagateResult[T],
  min_degree : Int,
  normalize_delete~ : Bool,
) -> BTreeNode[T]? {
  guard !self.segment.is_empty() else { return None }
  let mut segment = self.segment
  while segment.length() > 1 {
    segment = pack_level(segment, min_degree)
  }
  let root = segment[0]
  if normalize_delete {
    normalize_root_after_delete(root)
  } else {
    Some(root)
  }
}

///|
fn[T] BTree::apply_propagated(
  self : BTree[T],
  propagated : PropagateResult[T],
  normalize_delete~ : Bool,
) -> Unit {
  let next_root = propagated.root_candidate(self.min_degree, normalize_delete~)
  let next_size = self.size + propagated.leaf_delta
  self.root = next_root
  self.size = next_size
}

///|
/// Build a `BTree` bottom-up in input order from pre-sorted `(element, span)`
/// pairs. `min_degree` is normalized to `[2, @int.MAX_VALUE / 2]`.
///
/// Every span must be positive and the cumulative total must be at most
/// `@int.MAX_VALUE`, or construction aborts before publishing a tree. The caller
/// must pre-merge adjacent mergeable elements when its canonicalization policy
/// requires that invariant. Runs in O(n), rather than O(n log n) inserts.
pub fn[T] BTree::from_sorted(
  items : Array[(T, Int)],
  min_degree? : Int = DEFAULT_MIN_DEGREE,
) -> BTree[T] {
  validate_positive_spans(items, "BTree::from_sorted")
  let min_degree = clamp_min_degree(min_degree)
  let max_degree = 2 * min_degree
  if items.is_empty() {
    return { root: None, min_degree, size: 0 }
  }
  let mut nodes : Array[BTreeNode[T]] = items.map(fn(pair) {
    Leaf(elem=pair.0, span=pair.1)
  })
  while nodes.length() > max_degree {
    nodes = pack_level(nodes, min_degree)
  }
  let root = make_internal(nodes)
  { root: Some(root), min_degree, size: items.length() }
}

///|
/// Initialize an empty tree with a single root element. `span` must be positive;
/// a non-positive span or an already initialized tree aborts.
pub fn[T] BTree::init_root(self : BTree[T], elem : T, span : Int) -> Unit {
  guard span > 0 else { abort("BTree::init_root: leaf span must be positive") }
  guard self.is_empty() else {
    abort("BTree::init_root: tree is already initialized")
  }
  let leaf = Leaf(elem~, span~)
  self.root = Some(Internal(children=[leaf], counts=[span], total=span))
  self.size = 1
}

///|
/// A B-tree root with one internal child is a useless extra level —
/// collapsing it maintains minimal height. A root with zero children
/// means the tree is empty. Iterative: collapses all unary internal
/// chains (can occur after boundary merge + propagation).
fn[T] normalize_root_after_delete(root : BTreeNode[T]) -> BTreeNode[T]? {
  let mut current = root
  for ;; {
    match current {
      Internal(children~, ..) if children is [] => return None
      Internal(children~, ..) if children is [child] =>
        if child is Internal(..) {
          current = child
          continue
        } else {
          return Some(current)
        }
      Internal(..) => return Some(current)
      Leaf(..) => abort("normalize_root_after_delete: root should be internal")
    }
  }
}

///|
/// Return elements in the half-open span range `[start, end)`, slicing boundary
/// elements. A negative start clamps to zero; an omitted or oversized end
/// clamps to `span()`. An empty or reversed range, a negative end, or a start at
/// or beyond `span()` returns an empty array.
pub fn[T : BTreeElem] BTree::view(
  self : BTree[T],
  start? : Int = 0,
  end? : Int,
) -> Array[T] {
  let total = self.span()
  let start = if start < 0 { 0 } else { start }
  let end = match end {
    Some(e) => if e > total { total } else { e }
    None => total
  }
  let result : Array[T] = []
  guard start < end && start < total else { return result }
  match self.root {
    Some(root) => {
      root.each_slice_in_range(start, end, fn(elem) { result.push(elem) })
      result
    }
    _ => result
  }
}
