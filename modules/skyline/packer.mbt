///|
pub struct Packer {
  priv width : Int
  priv max_height : Int?
  priv mut skyline : Array[Node]
  priv mut used_height : Int
} derive(Debug)

///|
pub fn Packer::Packer(
  width~ : Int,
  max_height? : Int,
) -> Packer raise PackError {
  guard width > 0 else { raise InvalidBinWidth(width) }
  match max_height {
    Some(limit) if limit <= 0 => raise InvalidMaxHeight(limit)
    _ => ()
  }
  { width, max_height, skyline: [Node(0, 0), Node(width, 0)], used_height: 0 }
}

///|
pub fn Packer::height(self : Packer) -> Int {
  self.used_height
}

///|
fn Packer::validate_size(self : Packer, size : Size) -> Unit raise PackError {
  guard size.width <= self.width else {
    raise ItemTooWide(item_width=size.width, bin_width=self.width)
  }
}

///|
fn Packer::height_at(self : Packer, x : Int) -> Int {
  if x == self.width {
    0
  } else {
    self.skyline
    .windows(2)
    .iter()
    .find_first(window => window[0].x <= x && x < window[1].x)
    .map(window => window[0].y)
    .unwrap_or(0)
  }
}

///|
fn Packer::height_over(self : Packer, left : Int, right : Int) -> Int {
  self.skyline
  .windows(2)
  .iter()
  .filter(window => {
    let node = window[0]
    let segment_right = window[1].x
    segment_right > left && node.x < right
  })
  .map(window => window[0].y)
  .fold(init=0, Int::max)
}

///|
fn Packer::candidate_at(self : Packer, size : Size, x : Int) -> Candidate? {
  guard x >= 0 && x <= self.width - size.width else { None }
  let y = self.height_over(x, x + size.width)
  match self.max_height {
    Some(limit) if size.height > limit => None
    Some(limit) if y > limit - size.height => None
    _ => Some(Candidate(x, y))
  }
}

///|
fn Packer::find_candidate(self : Packer, size : Size) -> Candidate? {
  self.skyline[:self.skyline.length() - 1].fold(init=None, (best, node) => {
    match self.candidate_at(size, node.x) {
      Some(candidate) => choose_candidate(best, candidate)
      None => best
    }
  })
}

///|
fn Packer::find_constrained_candidate(
  self : Packer,
  size : Size,
  allowed_x : ArrayView[Int],
) -> Candidate? {
  allowed_x.fold(init=None, (best, x) => {
    match self.candidate_at(size, x) {
      Some(candidate) => choose_candidate(best, candidate)
      None => best
    }
  })
}

///|
fn Packer::commit(
  self : Packer,
  size : Size,
  candidate : Candidate,
) -> Placement raise PackError {
  let left = candidate.x
  let right = left + size.width
  let top = checked_top(candidate.y, size.height)
  let old_right_height = self.height_at(right)
  let next : Array[Node] = []
  self.skyline
  .iter()
  .each(node => if node.x < left { push_normalized(next, node, false) })
  push_normalized(next, Node(left, top), false)
  if right < self.width {
    push_normalized(next, Node(right, old_right_height), false)
  }
  self.skyline
  .iter()
  .each(node => {
    if node.x > right && node.x < self.width {
      push_normalized(next, node, false)
    }
  })
  push_normalized(next, Node(self.width, 0), true)
  self.skyline = next
  self.used_height = self.used_height.max(top)
  Placement(x=left, y=candidate.y, width=size.width, height=size.height)
}

///|
pub fn Packer::place(self : Packer, size : Size) -> Placement raise PackError {
  self.validate_size(size)
  guard self.find_candidate(size) is Some(candidate) else {
    raise NoPlacement(width=size.width, height=size.height)
  }
  self.commit(size, candidate)
}

///|
/// Place a rectangle only at one of the supplied X coordinates.
///
/// The candidate array is only observed; probing does not mutate the skyline.
pub fn Packer::place_constrained(
  self : Packer,
  size : Size,
  allowed_x : ArrayView[Int],
) -> Placement raise PackError {
  self.validate_size(size)
  guard self.find_constrained_candidate(size, allowed_x) is Some(candidate) else {
    raise NoPlacement(width=size.width, height=size.height)
  }
  self.commit(size, candidate)
}

///|
/// Pack rectangles without changing their order.
///
/// The returned placements have the same indices as the input sizes.
pub fn pack_in_order(
  sizes : ArrayView[Size],
  bin_width~ : Int,
) -> PackResult raise PackError {
  let packer = Packer(width=bin_width)
  let placements : Array[Placement] = []
  for size in sizes {
    placements.push(packer.place(size))
  }
  PackResult(placements~, height=packer.height())
}
