///|
/// A world-space position paired with an item identity.
pub struct ItemPosition[Id] {
  id : Id
  point : WorldPoint
}

///|
/// Construct an item position.
pub fn[Id] ItemPosition::from_id_and_point(
  id~ : Id,
  point~ : WorldPoint,
) -> ItemPosition[Id] {
  { id, point }
}

///|
/// A drag gesture snapshot.
pub struct Drag[Id] {
  priv initial_positions : Array[ItemPosition[Id]]
  priv initial_pointer : WorldPoint
}

///|
/// Capture initial item positions and the pointer position at drag start.
pub fn[Id] Drag::start(
  positions~ : ReadOnlyArray[ItemPosition[Id]],
  pointer~ : WorldPoint,
) -> Drag[Id] {
  let snapshot : Array[ItemPosition[Id]] = [
    for item in positions => {
      ItemPosition::from_id_and_point(id=item.id, point=item.point)
    }
  ]
  { initial_positions: snapshot, initial_pointer: pointer }
}

///|
/// Translate an already-captured position view and map each result.
///
/// The view is borrowed only for this calculation; the returned array owns
/// the mapped values. This avoids copying a snapshot when an imperative shell
/// already stores one.
pub fn[A, B] map_drag_positions_at(
  positions~ : ArrayView[A],
  initial_pointer~ : WorldPoint,
  current_pointer~ : WorldPoint,
  to_point~ : (A) -> (Double, Double),
  map_result~ : (A, Double, Double) -> B,
) -> Array[B] {
  let delta_x = current_pointer.x - initial_pointer.x
  let delta_y = current_pointer.y - initial_pointer.y
  positions.map(item => {
    let (x, y) = to_point(item)
    map_result(item, x + delta_x, y + delta_y)
  })
}

///|
/// Compute item positions from the original snapshot at a new pointer point.
pub fn[Id] Drag::positions_at(
  self : Drag[Id],
  current_pointer : WorldPoint,
) -> Array[ItemPosition[Id]] {
  map_drag_positions_at(
    positions=self.initial_positions[:],
    initial_pointer=self.initial_pointer,
    current_pointer~,
    to_point=item => (item.point.x, item.point.y),
    map_result=(item, x, y) => {
      ItemPosition::from_id_and_point(
        id=item.id,
        point=WorldPoint::from_xy(x~, y~),
      )
    },
  )
}
