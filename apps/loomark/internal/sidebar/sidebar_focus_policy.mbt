///|
/// Choose a focus position from plain facts; -1 means no candidate is active.
fn sidebar_focus_index(
  count : Int,
  active_index : Int,
  backwards : Bool,
) -> Int? {
  guard count > 0 else { return None }
  Some(
    if backwards {
      if active_index <= 0 {
        count - 1
      } else {
        active_index - 1
      }
    } else if active_index < 0 || active_index == count - 1 {
      0
    } else {
      active_index + 1
    },
  )
}
