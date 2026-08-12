///|
/// A world-space position paired with an item identity.
pub struct ItemPosition[Id] {
  id : Id
  point : WorldPoint
} derive(Eq, Debug)

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
} derive(Eq, Debug)

///|
/// Capture initial item positions and the pointer position at drag start.
pub fn[Id] Drag::start(
  positions~ : ReadOnlyArray[ItemPosition[Id]],
  pointer~ : WorldPoint,
) -> Drag[Id] raise DragStartError {
  guard pointer.is_finite() else { raise DragStartError::InvalidPointer }
  let snapshot : Array[ItemPosition[Id]] = [
    for item in positions => {
      guard item.point.is_finite() else {
        raise DragStartError::InvalidPosition
      }
      ItemPosition::from_id_and_point(id=item.id, point=item.point)
    }
  ]
  { initial_positions: snapshot, initial_pointer: pointer }
}

///|
/// Compute item positions from the original snapshot at a pointer point.
pub fn[Id] Drag::positions_at(
  self : Drag[Id],
  current_pointer : WorldPoint,
) -> Array[ItemPosition[Id]] raise DragError {
  guard current_pointer.is_finite() else { raise DragError::InvalidPointer }
  let delta_x = current_pointer.x - self.initial_pointer.x
  let delta_y = current_pointer.y - self.initial_pointer.y
  let positions = self.initial_positions.map(item => {
    let point = WorldPoint::from_xy(
      x=item.point.x + delta_x,
      y=item.point.y + delta_y,
    )
    guard point.is_finite() else { raise DragError::PositionOverflow }
    ItemPosition::from_id_and_point(id=item.id, point~)
  })
  positions
}

///|
/// Return the identities captured at drag start, in snapshot order.
pub fn[Id] Drag::initial_ids(self : Drag[Id]) -> Array[Id] {
  self.initial_positions.map(item => item.id)
}
