///|
pub(all) enum Edge {
  East
  South
  SouthEast
}

///|
pub(all) struct Constraints {
  min_w : Double
  max_w : Double
  min_h : Double
  max_h : Double
}

///|
struct Drag {
  edge : Edge
  origin_x : Double
  origin_y : Double
  base_w : Double
  base_h : Double
}

///|
pub struct Model {
  priv w : Double
  priv h : Double
  priv constraints : Constraints
  priv drag : Drag?
}

///|
pub(all) enum Msg {
  StartResize(edge~ : Edge, x~ : Double, y~ : Double)
  PointerMove(x~ : Double, y~ : Double)
  EndResize
  NudgeBy(dw~ : Double, dh~ : Double)
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
