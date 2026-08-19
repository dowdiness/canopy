///|
using @graph_model {type CanvasNode, type NodePosition, type WorkflowAction}

///|
using @spatial {type WorldPoint}

///|
const LAYOUT_QUANTUM : Double = 16.0

///|
pub(all) suberror LayoutError {
  InvalidRegionWidth(Double)
  InvalidGap(Double)
  NonFiniteGeometry
  ItemTooWide(item_width~ : Int, bin_width~ : Int)
  NoPlacement(width~ : Int, height~ : Int)
  CoordinateOverflow
} derive(Eq, Debug)

///|
pub struct LayoutPlan {
  positions : Array[NodePosition]
} derive(Eq, Debug)

///|
fn LayoutPlan::LayoutPlan(positions~ : Array[NodePosition]) -> LayoutPlan {
  { positions, }
}

///|
pub fn LayoutPlan::to_move_nodes(self : LayoutPlan) -> WorkflowAction {
  MoveNodes(self.positions)
}

///|
fn finite_number(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn quantize_length(value : Double) -> Int raise LayoutError {
  guard finite_number(value) else { raise NonFiniteGeometry }
  let scaled = (value * LAYOUT_QUANTUM).ceil()
  guard finite_number(scaled) && scaled <= @int.MAX_VALUE.to_double() else {
    raise CoordinateOverflow
  }
  let n = scaled.to_int()
  if n <= 0 {
    1
  } else {
    n
  }
}

///|
fn dequantize(offset : Int, origin : Double) -> Double {
  origin + offset.to_double() / LAYOUT_QUANTUM
}

///|
fn translate_pack_error(error : @pack.PackError) -> LayoutError {
  match error {
    ItemTooWide(item_width~, bin_width~) => ItemTooWide(item_width~, bin_width~)
    NoPlacement(width~, height~) => NoPlacement(width~, height~)
    CoordinateOverflow => CoordinateOverflow
    InvalidBinWidth(_) | InvalidMaxHeight(_) | InvalidSize(_) =>
      NonFiniteGeometry
  }
}

///|
fn selection_origin(
  nodes : ArrayView[CanvasNode],
) -> WorldPoint raise LayoutError {
  let first = nodes[0].position()
  let x = nodes.fold(init=first.x(), (acc, node) => acc.min(node.position().x()))
  let y = nodes.fold(init=first.y(), (acc, node) => acc.min(node.position().y()))
  WorldPoint::from_xy(x~, y~) catch {
    _ => raise NonFiniteGeometry
  }
}

///|
fn packed_size(node : CanvasNode, gap : Double) -> @pack.Size raise LayoutError {
  let width = quantize_length(node.size().width() + gap)
  let height = quantize_length(node.size().height() + gap)
  @pack.Size(width~, height~) catch {
    error => raise translate_pack_error(error)
  }
}

///|
/// Width that fits about two copies of the widest selected node after the same
/// quantization `arrange_with_skyline` uses. The packer stays width-agnostic.
pub fn compact_region_width(
  nodes : ArrayView[CanvasNode],
  gap~ : Double,
) -> Double raise LayoutError {
  guard !nodes.is_empty() else { raise InvalidRegionWidth(0.0) }
  guard finite_number(gap) && gap >= 0.0 else { raise InvalidGap(gap) }
  let widest = nodes.fold(init=1, (acc, node) => {
    acc.max(packed_size(node, gap).width)
  })
  guard widest <= @int.MAX_VALUE / 2 else { raise CoordinateOverflow }
  dequantize(widest * 2, 0.0)
}

///|
/// Pack `nodes` into a fixed-width strip with the Bottom-Left skyline heuristic.
///
/// Positions are relative to `origin`, or to the minimum X/Y of the selection
/// when `origin` is omitted. This function does not mutate canvas state.
pub fn arrange_with_skyline(
  nodes : ArrayView[CanvasNode],
  region_width~ : Double,
  gap? : Double = 0.0,
  origin? : WorldPoint,
) -> LayoutPlan raise LayoutError {
  guard finite_number(region_width) && region_width > 0.0 else {
    raise InvalidRegionWidth(region_width)
  }
  guard finite_number(gap) && gap >= 0.0 else { raise InvalidGap(gap) }
  if nodes.is_empty() {
    LayoutPlan(positions=[])
  } else {
    let origin = match origin {
      Some(point) => point
      None => selection_origin(nodes)
    }
    let bin_width = quantize_length(region_width)
    let packer = @pack.Packer(width=bin_width) catch {
      error => raise translate_pack_error(error)
    }
    let positions : Array[NodePosition] = []
    for node in nodes {
      let size = packed_size(node, gap)
      let placement = packer.place(size) catch {
        error => raise translate_pack_error(error)
      }
      let point = WorldPoint::from_xy(
        x=dequantize(placement.x, origin.x()),
        y=dequantize(placement.y, origin.y()),
      ) catch {
        _ => raise NonFiniteGeometry
      }
      positions.push(
        @spatial.ItemPosition::from_id_and_point(id=node.id, point~),
      )
    }
    LayoutPlan(positions~)
  }
}
