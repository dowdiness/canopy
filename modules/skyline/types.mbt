///|
pub(all) suberror PackError {
  InvalidBinWidth(Int)
  InvalidMaxHeight(Int)
  InvalidSize(Int, Int)
  ItemTooWide(item_width~ : Int, bin_width~ : Int)
  NoPlacement(width~ : Int, height~ : Int)
  CoordinateOverflow
} derive(Eq, Debug)

///|
pub struct Size {
  width : Int
  height : Int
} derive(Eq, Debug)

///|
pub fn Size::Size(width~ : Int, height~ : Int) -> Size raise PackError {
  guard width > 0 && height > 0 else { raise InvalidSize(width, height) }
  { width, height }
}

///|
pub struct Placement {
  x : Int
  y : Int
  width : Int
  height : Int
} derive(Eq, Debug)

///|
fn Placement::Placement(
  x~ : Int,
  y~ : Int,
  width~ : Int,
  height~ : Int,
) -> Placement {
  { x, y, width, height }
}

///|
pub struct PackResult {
  placements : Array[Placement]
  height : Int
} derive(Eq, Debug)

///|
fn PackResult::PackResult(
  placements~ : Array[Placement],
  height~ : Int,
) -> PackResult {
  { placements, height }
}

///|
/// `Node(x, y)` is the height `y` over the half-open interval `[x, next.x)`.
priv struct Node {
  x : Int
  y : Int
} derive(Debug)

///|
fn Node::Node(x : Int, y : Int) -> Node {
  { x, y }
}

///|
priv struct Candidate {
  x : Int
  y : Int
}

///|
fn Candidate::Candidate(x : Int, y : Int) -> Candidate {
  { x, y }
}

///|
fn choose_candidate(best : Candidate?, candidate : Candidate) -> Candidate? {
  match best {
    None => Some(candidate)
    Some(current) =>
      if candidate.y < current.y ||
        (candidate.y == current.y && candidate.x < current.x) {
        Some(candidate)
      } else {
        Some(current)
      }
  }
}

///|
fn push_normalized(
  nodes : Array[Node],
  node : Node,
  is_sentinel : Bool,
) -> Unit {
  if nodes.length() == 0 {
    nodes.push(node)
  } else if is_sentinel || nodes[nodes.length() - 1].y != node.y {
    nodes.push(node)
  }
}

///|
fn checked_top(y : Int, height : Int) -> Int raise PackError {
  guard y <= @int.MAX_VALUE - height else { raise CoordinateOverflow }
  y + height
}
