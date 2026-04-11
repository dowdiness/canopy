///|
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
/// Descend for insert: splits full nodes during descent, uses inclusive slot
/// finding, allows leaf-end positions. Tree must be non-empty (use init_root
/// first). Aborts if pos is out of [0, span] or tree is empty.
/// The callback receives a LeafContext and returns a Splice describing
/// what to replace. The tree handles rebalancing and size tracking automatically.
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
      let cursor = match
        descend(
          root,
          pos,
          self.min_degree,
          prepare_split,
          find_slot_inclusive,
          true,
        ) {
        Some(c) => c
        None => abort("BTree::mutate_for_insert: descent failed")
      }
      let leaf_ctx = LeafContext::from_cursor(cursor)
      let splice = f(leaf_ctx)
      let propagated = propagate(cursor.path, splice, self.min_degree)
      self.apply_propagated(propagated, normalize_delete=false)
    }
  }
}

///|
/// Descend for delete: ensures min children during descent, uses strict slot
/// finding. Returns the callback's payload R, or None if pos is out of bounds
/// or tree is empty. The callback returns (splice, payload) where payload is
/// any caller-defined data (e.g., the deleted element).
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
        ) {
        None => None
        Some(cursor) => {
          let leaf_ctx = LeafContext::from_cursor(cursor)
          let (splice, payload) = f(leaf_ctx)
          let propagated = propagate(cursor.path, splice, self.min_degree)
          self.apply_propagated(propagated, normalize_delete=true)
          Some(payload)
        }
      }
    }
  }
}

///|
/// Delete all elements in the span range [start, end_).
/// Handles all cases: single-leaf splice, multi-child LCA splice,
/// underfull node repair, and post-splice boundary merging.
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
      // Skip root normalization here — we normalize after boundary merge
      self.apply_propagated(propagated, normalize_delete=false)
      guard self.root is Some(new_root) else { return }
      let (merged_root, boundary_merged) = normalize_boundary_merge(
        new_root,
        start,
        self.min_degree,
      )
      // Collapse unary root wrappers, fix underfull descendants, then
      // collapse again (fix_merged_chain may create new unary roots via merge).
      let final_root = match normalize_root_after_delete(merged_root) {
        None => None
        Some(collapsed) => {
          let fixed = fix_merged_chain(collapsed, self.min_degree)
          normalize_root_after_delete(fixed)
        }
      }
      self.root = final_root
      if boundary_merged {
        self.size = self.size - 1
      }
    }
  }
}

///|
fn[T] BTree::apply_propagated(
  self : BTree[T],
  propagated : PropagateResult[T],
  normalize_delete~ : Bool,
) -> Unit {
  match propagated.overflow {
    None =>
      if normalize_delete {
        self.root = normalize_root_after_delete(propagated.node)
      } else {
        self.root = Some(propagated.node)
      }
    Some(sibling) => {
      let left_total = propagated.node.total()
      let right_total = sibling.total()
      self.root = Some(
        Internal(
          children=[propagated.node, sibling],
          counts=[left_total, right_total],
          total=left_total + right_total,
        ),
      )
    }
  }
  self.size = self.size + propagated.leaf_delta
}

///|
/// Build a BTree bottom-up from a pre-sorted array of (element, span) pairs.
/// O(n) instead of O(n log n) repeated inserts.
/// Caller must ensure no adjacent items are mergeable (pre-merge if needed).
pub fn[T] BTree::from_sorted(
  items : Array[(T, Int)],
  min_degree? : Int = DEFAULT_MIN_DEGREE,
) -> BTree[T] {
  let min_degree = clamp_min_degree(min_degree)
  let max_degree = 2 * min_degree
  if items.is_empty() {
    return { root: None, min_degree, size: 0 }
  }
  let mut nodes : Array[BTreeNode[T]] = items.map(fn(pair) {
    Leaf(elem=pair.0, span=pair.1)
  })
  while nodes.length() > max_degree {
    let next : Array[BTreeNode[T]] = []
    let mut i = 0
    while i < nodes.length() {
      let remaining = nodes.length() - i
      // Redistribute when the leftover would violate min_degree
      let chunk_size = if remaining > max_degree &&
        remaining - max_degree < min_degree {
        remaining / 2
      } else if remaining <= max_degree {
        remaining
      } else {
        max_degree
      }
      let chunk : Array[BTreeNode[T]] = []
      for j in i..<(i + chunk_size) {
        chunk.push(nodes[j])
      }
      next.push(make_internal(chunk))
      i = i + chunk_size
    }
    nodes = next
  }
  let root = make_internal(nodes)
  { root: Some(root), min_degree, size: items.length() }
}

///|
/// Initialize root with a single leaf wrapped in an internal node.
pub fn[T] BTree::init_root(self : BTree[T], elem : T, span : Int) -> Unit {
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
/// View elements in span range [start, end). Slices at boundaries.
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
