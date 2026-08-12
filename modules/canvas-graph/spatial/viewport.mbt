///|
/// A viewport maps world coordinates into canvas-local screen coordinates.
pub struct Viewport {
  priv origin : ScreenPoint
  priv scale : Double
} derive(Eq, Debug)

///|
fn finite_number(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn valid_scale(scale : Double) -> Bool {
  finite_number(scale) && scale > 0.0
}

///|
fn viewport_json_number_field(
  fields : Map[String, Json],
  path : @json.JsonPath,
  key : String,
) -> Double raise @json.JsonDecodeError {
  match fields.get(key) {
    Some(Json::Number(number, ..)) => {
      guard finite_number(number) else {
        raise @json.JsonDecodeError(
          (path.add_key(key), "Viewport: '\\{key}' must be finite"),
        )
      }
      number
    }
    _ =>
      raise @json.JsonDecodeError(
        (path.add_key(key), "Viewport: '\\{key}' must be a number"),
      )
  }
}

///|
/// Construct a viewport when the scale has already been validated.
///
/// This constructor aborts for invalid input. Use `try_from_scale` when the scale
/// comes from an untrusted boundary.
pub fn Viewport::validated(origin~ : ScreenPoint, scale~ : Double) -> Viewport {
  guard valid_scale(scale) else {
    abort("viewport scale must be finite and positive")
  }
  { origin, scale }
}

///|
/// Construct a viewport from untrusted input without aborting.
pub fn Viewport::try_from_scale(
  origin~ : ScreenPoint,
  scale~ : Double,
) -> Viewport? {
  if valid_scale(scale) {
    Some({ origin, scale })
  } else {
    None
  }
}

///|
/// Return the screen-space origin of the world coordinate system.
pub fn Viewport::screen_origin(self : Viewport) -> ScreenPoint {
  self.origin
}

///|
pub impl ToJson for Viewport with fn to_json(self) {
  let origin = self.screen_origin()
  let fields : Map[String, Json] = Map([])
  fields["x"] = origin.x.to_json()
  fields["y"] = origin.y.to_json()
  fields["scale"] = self.scale.to_json()
  Json::object(fields)
}

///|
pub impl @json.FromJson for Viewport with fn from_json(json, path) {
  let fields = match json {
    Json::Object(fields) => fields
    _ => raise @json.JsonDecodeError((path, "Viewport: expected JSON object"))
  }
  let origin = ScreenPoint::from_xy(
    x=viewport_json_number_field(fields, path, "x"),
    y=viewport_json_number_field(fields, path, "y"),
  )
  let scale = viewport_json_number_field(fields, path, "scale")
  match Viewport::try_from_scale(origin~, scale~) {
    Some(viewport) => viewport
    None =>
      raise @json.JsonDecodeError(
        (path.add_key("scale"), "Viewport: 'scale' must be finite and positive"),
      )
  }
}

///|
/// Return the viewport's absolute scale.
pub fn Viewport::scale(self : Viewport) -> Double {
  self.scale
}

///|
/// Convert a canvas-local screen point into world coordinates.
pub fn Viewport::screen_to_world(
  self : Viewport,
  screen : ScreenPoint,
) -> WorldPoint {
  WorldPoint::from_xy(
    x=(screen.x - self.origin.x) / self.scale,
    y=(screen.y - self.origin.y) / self.scale,
  )
}

///|
/// Convert a world point into canvas-local screen coordinates.
pub fn Viewport::world_to_screen(
  self : Viewport,
  world : WorldPoint,
) -> ScreenPoint {
  ScreenPoint::from_xy(
    x=self.origin.x + world.x * self.scale,
    y=self.origin.y + world.y * self.scale,
  )
}

///|
/// Return a viewport with an absolute scale while keeping `anchor` fixed.
///
/// This method aborts for invalid input. Use `try_with_scale_around` when the
/// scale comes from an untrusted boundary.
pub fn Viewport::with_scale_around(
  self : Viewport,
  anchor~ : ScreenPoint,
  absolute_scale~ : Double,
) -> Viewport {
  match self.try_with_scale_around(anchor~, absolute_scale~) {
    Some(viewport) => viewport
    None => abort("viewport scale must be finite and positive")
  }
}

///|
/// Change scale around an anchor without aborting on invalid input.
pub fn Viewport::try_with_scale_around(
  self : Viewport,
  anchor~ : ScreenPoint,
  absolute_scale~ : Double,
) -> Viewport? {
  if !valid_scale(absolute_scale) {
    None
  } else {
    let world_anchor = self.screen_to_world(anchor)
    let origin = ScreenPoint::from_xy(
      x=anchor.x - world_anchor.x * absolute_scale,
      y=anchor.y - world_anchor.y * absolute_scale,
    )
    Some({ origin, scale: absolute_scale })
  }
}
