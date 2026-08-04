///|
pub(all) enum Edge {
  East
  South
  SouthEast
}

///|
pub(all) struct Constraints {
  min_w : Int
  max_w : Int
  min_h : Int
  max_h : Int
}

///|
struct Drag {
  edge : Edge
  origin_x : Int
  origin_y : Int
  base_w : Int
  base_h : Int
}

///|
pub struct Model {
  priv w : Int
  priv h : Int
  priv constraints : Constraints
  priv drag : Drag?
}

///|
pub(all) enum Msg {
  StartResize(edge~ : Edge, x~ : Int, y~ : Int)
  PointerMove(x~ : Int, y~ : Int)
  EndResize
  NudgeBy(dw~ : Int, dh~ : Int)
}

///|
fn Edge::resizes_width(self : Edge) -> Bool {
  match self {
    East | SouthEast => true
    South => false
  }
}

///|
fn Edge::resizes_height(self : Edge) -> Bool {
  match self {
    South | SouthEast => true
    East => false
  }
}
