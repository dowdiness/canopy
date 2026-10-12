///|
pub(all) struct Presentation {
  range : Range
  engaged : Bool
  reduced_motion : Bool
}

///|
pub enum Dimming {
  Unchanged
  Immediate(Range)
  Animated(Range)
}

///|
pub fn Presentation::dimming(
  self : Presentation,
  previous : Presentation?,
  geometry_changed~ : Bool,
) -> Dimming {
  let animate = match previous {
    None => false
    Some(previous) => {
      let engagement_changed = previous.engaged != self.engaged
      let range_changed = self.engaged &&
        (
          previous.range.start != self.range.start ||
          previous.range.end != self.range.end
        )
      if !geometry_changed &&
        !engagement_changed &&
        previous.reduced_motion == self.reduced_motion &&
        !range_changed {
        return Unchanged
      }
      !self.reduced_motion && (!geometry_changed || engagement_changed)
    }
  }
  let range = if self.engaged {
    self.range
  } else {
    { start: 0.0, end: @double.infinity, }
  }
  if animate {
    Animated(range)
  } else {
    Immediate(range)
  }
}
