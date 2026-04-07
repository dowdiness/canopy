// Navigation, reconstruction, modification, and query operations for RoseZipper.
//
// All navigation returns Option — None at boundaries (root, leaf, first/last
// sibling). Every operation is persistent: the original zipper is unchanged,
// and old/new zippers share structure via @list.List cons cells.
//
// Vertical moves (go_down, go_up) are O(n) where n = number of children
// at the focused node (go_down) or siblings at the current level (go_up),
// because they split/merge the children array into sibling lists.
// Lateral moves (go_left, go_right) are O(1) — just list cons/uncons.

///|
pub fn[T] RoseZipper::go_down(
  self : RoseZipper[T],
  index? : Int = 0,
) -> RoseZipper[T]? {
  if index < 0 || index >= self.focus.children.length() {
    return None
  }
  let children = self.focus.children
  // Build left siblings in reverse order (nearest first) via cons — this
  // makes go_left O(1) and matches the reversed-list convention in RoseCtx.
  let mut left : @list.List[RoseNode[T]] = @list.List::default()
  for i in 0..<index {
    left = @list.cons(children[i], left)
  }
  let mut right : @list.List[RoseNode[T]] = @list.List::default()
  for i = children.length() - 1; i > index; i = i - 1 {
    right = @list.cons(children[i], right)
  }
  let ctx : RoseCtx[T] = { data: self.focus.data, left, right, index }
  Some({
    focus: children[index],
    path: @list.cons(ctx, self.path),
    depth: self.depth + 1,
  })
}

///|
pub fn[T] RoseZipper::go_up(self : RoseZipper[T]) -> RoseZipper[T]? {
  match self.path {
    Empty => None
    More(ctx, tail=rest) => {
      // Reconstruct children: left (reversed back to original order) + focus + right
      let children : Array[RoseNode[T]] = ctx.left.to_array()
      children.rev_in_place() // left was stored nearest-first; restore tree order
      children.push(self.focus)
      ctx.right.each(fn(n) { children.push(n) })
      let parent = RoseNode::new(data=ctx.data, children~)
      Some({ focus: parent, path: rest, depth: self.depth - 1 })
    }
  }
}

///|
pub fn[T] RoseZipper::go_left(self : RoseZipper[T]) -> RoseZipper[T]? {
  match self.path {
    More(ctx, tail=rest) =>
      match ctx.left {
        More(sibling, tail=left_rest) => {
          let new_right = @list.cons(self.focus, ctx.right)
          let new_ctx : RoseCtx[T] = {
            data: ctx.data,
            left: left_rest,
            right: new_right,
            index: ctx.index - 1,
          }
          Some({
            focus: sibling,
            path: @list.cons(new_ctx, rest),
            depth: self.depth,
          })
        }
        Empty => None
      }
    Empty => None
  }
}

///|
pub fn[T] RoseZipper::go_right(self : RoseZipper[T]) -> RoseZipper[T]? {
  match self.path {
    More(ctx, tail=rest) =>
      match ctx.right {
        More(sibling, tail=right_rest) => {
          let new_left = @list.cons(self.focus, ctx.left)
          let new_ctx : RoseCtx[T] = {
            data: ctx.data,
            left: new_left,
            right: right_rest,
            index: ctx.index + 1,
          }
          Some({
            focus: sibling,
            path: @list.cons(new_ctx, rest),
            depth: self.depth,
          })
        }
        Empty => None
      }
    Empty => None
  }
}

///|
pub fn[T] RoseZipper::to_tree(self : RoseZipper[T]) -> RoseNode[T] {
  let mut z = self
  while true {
    match z.go_up() {
      Some(parent) => z = parent
      None => break
    }
  }
  z.focus
}

///|
pub fn[T] RoseZipper::replace(
  self : RoseZipper[T],
  new_focus : RoseNode[T],
) -> RoseZipper[T] {
  { ..self, focus: new_focus }
}

///|
pub fn[T] RoseZipper::modify(
  self : RoseZipper[T],
  f : (RoseNode[T]) -> RoseNode[T],
) -> RoseZipper[T] {
  { ..self, focus: f(self.focus) }
}

///|
pub fn[T] RoseZipper::depth(self : RoseZipper[T]) -> Int {
  self.depth
}

///|
pub fn[T] RoseZipper::child_index(self : RoseZipper[T]) -> Int? {
  match self.path {
    More(ctx, ..) => Some(ctx.index)
    Empty => None
  }
}

///|
pub fn[T] RoseZipper::is_root(self : RoseZipper[T]) -> Bool {
  self.path is Empty
}

///|
pub fn[T] RoseZipper::is_leaf(self : RoseZipper[T]) -> Bool {
  self.focus.children.is_empty()
}

///|
pub fn[T] RoseZipper::num_children(self : RoseZipper[T]) -> Int {
  self.focus.children.length()
}

///|
pub fn[T] RoseZipper::to_path(self : RoseZipper[T]) -> Array[Int] {
  let indices : Array[Int] = []
  let mut p = self.path
  while true {
    match p {
      Empty => break
      More(ctx, tail=rest) => {
        indices.push(ctx.index)
        p = rest
      }
    }
  }
  indices.rev_in_place()
  indices
}

///|
pub fn[T] RoseZipper::focus_at(
  tree : RoseNode[T],
  path : Array[Int],
) -> RoseZipper[T]? {
  let mut z = RoseZipper::from_root(tree)
  for idx in path {
    match z.go_down(index=idx) {
      Some(z2) => z = z2
      None => return None
    }
  }
  Some(z)
}
