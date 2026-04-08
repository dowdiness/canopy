///|
pub fn[T] BTree::new(min_degree? : Int = DEFAULT_MIN_DEGREE) -> BTree[T] {
  let min_degree = if min_degree < 2 { 2 } else { min_degree }
  { root: None, min_degree, size: 0 }
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
/// Initialize root with a single leaf wrapped in an internal node.
pub fn[T] BTree::init_root(self : BTree[T], elem : T, span : Int) -> Unit {
  let leaf = Leaf(elem~, span~)
  self.root = Some(Internal(children=[leaf], counts=[span], total=span))
  self.size = 1
}

///|
/// A B-tree root with one internal child is a useless extra level —
/// collapsing it maintains minimal height. A root with zero children
/// means the tree is empty.
pub fn[T] normalize_root_after_delete(root : BTreeNode[T]) -> BTreeNode[T]? {
  match root {
    Internal(children~, ..) if children.is_empty() => None
    Internal(children~, ..) if children.length() == 1 =>
      if children[0] is Internal(..) {
        Some(children[0])
      } else {
        Some(root)
      }
    Internal(..) => Some(root)
    Leaf(..) => abort("normalize_root_after_delete: root should be internal")
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
