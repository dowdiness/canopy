///|
fn finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn Constraints::is_valid(self : Constraints) -> Bool {
  finite(self.min_w) &&
  finite(self.max_w) &&
  finite(self.min_h) &&
  finite(self.max_h) &&
  self.min_w >= 1.0 &&
  self.min_w <= self.max_w &&
  self.min_h >= 1.0 &&
  self.min_h <= self.max_h
}

///|
fn clamp_size(
  w : Double,
  h : Double,
  constraints : Constraints,
) -> (Double, Double) {
  (
    w.clamp(min=constraints.min_w, max=constraints.max_w),
    h.clamp(min=constraints.min_h, max=constraints.max_h),
  )
}

///|
fn Model::with_clamped_size(self : Model, w : Double, h : Double) -> Model {
  guard finite(w) && finite(h) else { return self }
  let (w, h) = clamp_size(w, h, self.constraints)
  { ..self, w, h }
}

///|
fn Model::apply_drag(
  self : Model,
  drag : Drag,
  x : Double,
  y : Double,
) -> Model {
  let delta_x = x - drag.origin_x
  let delta_y = y - drag.origin_y
  let raw_w = if drag.edge.resizes_width() {
    drag.base_w + delta_x
  } else {
    drag.base_w
  }
  let raw_h = if drag.edge.resizes_height() {
    drag.base_h + delta_y
  } else {
    drag.base_h
  }
  self.with_clamped_size(raw_w, raw_h)
}

///|
/// Create a resizable model.
///
/// Preconditions: the initial size and all constraint values are finite, with
/// `1 <= min_w <= max_w` and `1 <= min_h <= max_h`. The initial size is
/// clamped into those bounds.
pub fn Model::new(
  w~ : Double,
  h~ : Double,
  constraints~ : Constraints,
) -> Model {
  guard constraints.is_valid() else {
    abort("resizable constraints must be finite and require 1 <= min <= max")
  }
  guard finite(w) && finite(h) else {
    abort("resizable initial size must be finite")
  }
  let (w, h) = clamp_size(w, h, constraints)
  { w, h, constraints, drag: None }
}

///|
pub fn Model::width(self : Model) -> Double {
  self.w
}

///|
pub fn Model::height(self : Model) -> Double {
  self.h
}

///|
pub fn Model::is_resizing(self : Model) -> Bool {
  self.drag is Some(_)
}

///|
/// Apply one resizable message to the model.
///
/// The update is pure and total. Mouse drags resize from the captured drag
/// origin; keyboard nudges apply directly to the current clamped size.
pub fn Model::update(self : Model, msg : Msg) -> Model {
  match msg {
    StartResize(edge~, x~, y~) => {
      let drag = {
        edge,
        origin_x: x,
        origin_y: y,
        base_w: self.w,
        base_h: self.h,
      }
      { ..self, drag: Some(drag) }
    }
    PointerMove(x~, y~) =>
      match self.drag {
        Some(drag) => self.apply_drag(drag, x, y)
        None => self
      }
    EndResize =>
      match self.drag {
        Some(_) => { ..self, drag: None }
        None => self
      }
    NudgeBy(dw~, dh~) => self.with_clamped_size(self.w + dw, self.h + dh)
  }
}
