///|
#derive(Eq, Debug)
pub(all) suberror PackError {
  InvalidBinWidth(Int32)
  InvalidMaxHeight(Int32)
  InvalidSize(Int32, Int32)
  ItemTooWide(item_width~ : Int32, bin_width~ : Int32)
  NoPlacement(width~ : Int32, height~ : Int32)
  CoordinateOverflow
}

///|
#derive(Eq, Debug)
pub struct Size {
  width : Int32
  height : Int32
}

///|
pub fn Size::Size(width~ : Int32, height~ : Int32) -> Size raise PackError {
  guard width > 0 && height > 0 else { raise InvalidSize(width, height) }
  { width, height, }
}

///|
#derive(Eq, Debug)
pub struct Placement {
  x : Int32
  y : Int32
  width : Int32
  height : Int32
}

///|
fn Placement::Placement(
  x~ : Int32,
  y~ : Int32,
  width~ : Int32,
  height~ : Int32,
) -> Placement {
  { x, y, width, height, }
}

///|
/// Where `Packer::preview` would place a rectangle: its bottom-left corner and
/// the empty area between the skyline and its bottom edge.
#derive(Eq, Debug)
pub struct PlacementPreview {
  x : Int32
  y : Int32
  trapped_area : Int64
}

///|
fn PlacementPreview::PlacementPreview(
  x~ : Int32,
  y~ : Int32,
  trapped_area~ : Int64,
) -> PlacementPreview {
  { x, y, trapped_area, }
}

///|
#derive(Eq, Debug)
pub struct PackResult {
  placements : Array[Placement]
  height : Int32
}

///|
fn PackResult::PackResult(
  placements~ : Array[Placement],
  height~ : Int32,
) -> PackResult {
  { placements, height, }
}

///|
/// `Node(x, y)` is the height `y` over the half-open interval `[x, next.x)`.
#derive(Debug)
priv struct Node {
  x : Int32
  y : Int32
}

///|
fn Node::Node(x : Int32, y : Int32) -> Node {
  { x, y, }
}

///|
priv struct Candidate {
  x : Int32
  y : Int32
}

///|
fn Candidate::Candidate(x : Int32, y : Int32) -> Candidate {
  { x, y, }
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
fn checked_top(y : Int32, height : Int32) -> Int32 raise PackError {
  guard y <= @int.MAX_VALUE - height else { raise CoordinateOverflow }
  y + height
}

///|
pub extend PackError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PackError with Eq::{equal, not_equal}

///|
pub extend PackResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PackResult with Eq::{equal, not_equal}

///|
pub extend Placement with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Placement with Eq::{equal, not_equal}

///|
pub extend Size with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Size with Eq::{equal, not_equal}

///|
pub extend PlacementPreview with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PlacementPreview with Eq::{equal, not_equal}
