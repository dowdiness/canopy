///|
/// Browser wheel units exposed by `WheelEvent::deltaMode`.
priv enum CanvasWheelDeltaUnit {
  Pixel
  Line
  Page
}

///|
const CANVAS_WHEEL_PIXEL_UNIT_FACTOR : Double = 0.002

///|
const CANVAS_WHEEL_LINE_UNIT_FACTOR : Double = 0.05

///|
const CANVAS_WHEEL_PAGE_UNIT_FACTOR : Double = 1.0

///|
const CANVAS_WHEEL_PINCH_FACTOR : Double = 10.0

///|
fn canvas_wheel_delta_unit(delta_mode : Int) -> CanvasWheelDeltaUnit? {
  match delta_mode {
    0 => Some(Pixel)
    1 => Some(Line)
    2 => Some(Page)
    _ => None
  }
}

///|
fn canvas_wheel_unit_factor(unit : CanvasWheelDeltaUnit) -> Double {
  match unit {
    Pixel => CANVAS_WHEEL_PIXEL_UNIT_FACTOR
    Line => CANVAS_WHEEL_LINE_UNIT_FACTOR
    Page => CANVAS_WHEEL_PAGE_UNIT_FACTOR
  }
}

///|
/// Convert one raw wheel delta into the absolute target scale used by the
/// semantic viewport reducer. A `None` result means the event is not an
/// admissible camera change.
fn canvas_wheel_target_scale(
  current_scale : @spatial.Scale,
  delta_y : Double,
  delta_mode : Int,
  ctrl_key : Bool,
  mac_like : Bool,
  min_scale~ : Double,
  max_scale~ : Double,
) -> @spatial.Scale? {
  guard !delta_y.is_nan() && !delta_y.is_inf() && delta_y != 0.0 else {
    return None
  }
  let unit = match canvas_wheel_delta_unit(delta_mode) {
    Some(unit) => unit
    None => return None
  }
  let pinch_factor = if ctrl_key && mac_like {
    CANVAS_WHEEL_PINCH_FACTOR
  } else {
    1.0
  }
  let exponent = -delta_y * canvas_wheel_unit_factor(unit) * pinch_factor
  guard !exponent.is_nan() else { return None }
  // Finite extreme inputs may overflow the exponent or pow; their direction
  // still determines which host bound is the semantic target.
  let bounded = if exponent.is_inf() {
    if exponent > 0.0 {
      max_scale
    } else {
      min_scale
    }
  } else {
    let multiplier = @math.pow(2.0, exponent)
    guard !multiplier.is_nan() else { return None }
    let raw = current_scale.to_double() * multiplier
    if raw.is_inf() {
      if exponent > 0.0 {
        max_scale
      } else {
        min_scale
      }
    } else {
      guard !raw.is_nan() else { return None }
      raw.clamp(min=min_scale, max=max_scale)
    }
  }
  let scale = @spatial.Scale::from_double(value=bounded) catch {
    @spatial.ScaleError::NonFinite | @spatial.ScaleError::NonPositive =>
      return None
  }
  Some(scale)
}
