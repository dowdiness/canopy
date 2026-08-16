///|
priv enum IncrCanvasWheelDeltaUnit {
  Pixel
  Line
  Page
}

///|
const INCR_CANVAS_WHEEL_PIXEL_UNIT_FACTOR : Double = 0.002

///|
const INCR_CANVAS_WHEEL_LINE_UNIT_FACTOR : Double = 0.05

///|
const INCR_CANVAS_WHEEL_PAGE_UNIT_FACTOR : Double = 1.0

///|
const INCR_CANVAS_WHEEL_PINCH_FACTOR : Double = 10.0

///|
fn incr_canvas_wheel_delta_unit(delta_mode : Int) -> IncrCanvasWheelDeltaUnit? {
  match delta_mode {
    0 => Some(Pixel)
    1 => Some(Line)
    2 => Some(Page)
    _ => None
  }
}

///|
fn incr_canvas_wheel_unit_factor(unit : IncrCanvasWheelDeltaUnit) -> Double {
  match unit {
    Pixel => INCR_CANVAS_WHEEL_PIXEL_UNIT_FACTOR
    Line => INCR_CANVAS_WHEEL_LINE_UNIT_FACTOR
    Page => INCR_CANVAS_WHEEL_PAGE_UNIT_FACTOR
  }
}

///|
fn incr_canvas_wheel_target_scale(
  current_scale : @spatial.Scale,
  delta_y : Double,
  delta_mode : Int,
  ctrl_key : Bool,
  mac_like : Bool,
) -> @spatial.Scale? {
  guard !delta_y.is_nan() && !delta_y.is_inf() && delta_y != 0.0 else {
    return None
  }
  let unit = match incr_canvas_wheel_delta_unit(delta_mode) {
    Some(unit) => unit
    None => return None
  }
  let pinch_factor = if ctrl_key && mac_like {
    INCR_CANVAS_WHEEL_PINCH_FACTOR
  } else {
    1.0
  }
  let exponent = -delta_y * incr_canvas_wheel_unit_factor(unit) * pinch_factor
  guard !exponent.is_nan() else { return None }
  // Finite extreme inputs may overflow the exponent or pow; their direction
  // still determines which host bound is the semantic target.
  let bounded = if exponent.is_inf() {
    if exponent > 0.0 {
      INCR_CANVAS_MAX_SCALE
    } else {
      INCR_CANVAS_MIN_SCALE
    }
  } else {
    let multiplier = @math.pow(2.0, exponent)
    guard !multiplier.is_nan() else { return None }
    let raw = current_scale.to_double() * multiplier
    if raw.is_inf() {
      if exponent > 0.0 {
        INCR_CANVAS_MAX_SCALE
      } else {
        INCR_CANVAS_MIN_SCALE
      }
    } else {
      guard !raw.is_nan() else { return None }
      raw.clamp(min=INCR_CANVAS_MIN_SCALE, max=INCR_CANVAS_MAX_SCALE)
    }
  }
  let scale = @spatial.Scale::from_double(value=bounded) catch {
    @spatial.ScaleError::NonFinite | @spatial.ScaleError::NonPositive =>
      return None
  }
  Some(scale)
}

///|
fn incr_canvas_update_viewport_scale_around(
  state : IncrCanvasState,
  absolute_scale : @spatial.Scale,
  anchor : @spatial.ScreenPoint,
) -> IncrCanvasState {
  guard state.active_pointer_id is None else { return state }
  guard state.viewport.scale() != absolute_scale else { return state }
  let viewport = state.viewport.with_scale_around(anchor~, absolute_scale~) catch {
    @spatial.CoordinateError::NonFinite => return state
  }
  if viewport == state.viewport {
    state
  } else {
    { ..state, viewport, }
  }
}

///|
fn incr_canvas_wheel(
  state : IncrCanvasState,
  delta_y : Double,
  delta_mode : Int,
  ctrl_key : Bool,
  x : Double,
  y : Double,
) -> IncrCanvasState {
  guard state.active_pointer_id is None else { return state }
  let anchor = match incr_canvas_screen_point(x, y) {
    Some(point) => point
    None => return state
  }
  let scale = match
    incr_canvas_wheel_target_scale(
      state.viewport.scale(),
      delta_y,
      delta_mode,
      ctrl_key,
      incr_canvas_is_mac_like(),
    ) {
    Some(scale) => scale
    None => return state
  }
  incr_canvas_update_viewport_scale_around(state, scale, anchor)
}

///|
#cfg(target="js")
extern "js" fn incr_canvas_is_mac_like() -> Bool = "() => /Mac|iPhone|iPad|iPod/.test(navigator.platform)"
