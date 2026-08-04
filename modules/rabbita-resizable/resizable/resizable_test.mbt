///|
fn test_constraints() -> Constraints {
  { min_w: 50, max_w: 300, min_h: 40, max_h: 220 }
}

///|
fn test_model() -> Model {
  Model::new(w=120, h=90, constraints=test_constraints())
}

///|
fn apply_messages(model : Model, messages : Array[Msg]) -> Model {
  for msg in messages; current = model {
    continue current.update(msg)
  } nobreak {
    current
  }
}

///|
fn assert_in_bounds(model : Model, constraints : Constraints) -> Unit raise {
  assert_true(model.width() >= constraints.min_w)
  assert_true(model.width() <= constraints.max_w)
  assert_true(model.height() >= constraints.min_h)
  assert_true(model.height() <= constraints.max_h)
}

///|
fn assert_same_public_state(left : Model, right : Model) -> Unit raise {
  assert_eq(left.width(), right.width())
  assert_eq(left.height(), right.height())
  assert_eq(left.is_resizing(), right.is_resizing())
}

///|
fn sample_coord(seed : Int) -> Int {
  seed % 701 - 350
}

///|
fn non_negative(seed : Int) -> Int {
  if seed < 0 {
    -(seed + 1)
  } else {
    seed
  }
}

///|
fn sample_msg(seed : Int) -> Msg {
  let value = non_negative(seed)
  let x = sample_coord(value)
  let y = sample_coord(value / 701)
  match value % 8 {
    0 => StartResize(edge=East, x~, y~)
    1 => StartResize(edge=South, x~, y~)
    2 => StartResize(edge=SouthEast, x~, y~)
    3 => PointerMove(x~, y~)
    4 => EndResize
    5 => NudgeBy(dw=x, dh=0)
    6 => NudgeBy(dw=0, dh=y)
    _ => NudgeBy(dw=x, dh=y)
  }
}

///|
test "Model::new clamps initial size" {
  let constraints = test_constraints()
  let model = Model::new(w=10, h=1000, constraints~)
  assert_eq(model.width(), constraints.min_w)
  assert_eq(model.height(), constraints.max_h)
  assert_in_bounds(model, constraints)
}

///|
test "quickcheck sample sequences preserve clamp invariant" {
  let constraints = test_constraints()
  let samples : Array[Array[Int]] = @quickcheck.samples(32)
  for sample in samples {
    let model = apply_messages(
      Model::new(w=120, h=90, constraints~),
      sample.map(sample_msg),
    )
    assert_in_bounds(model, constraints)
  }
}

///|
test "clamp invariant after representative message sequences" {
  let constraints = test_constraints()
  let sequences : Array[Array[Msg]] = [
    [],
    [NudgeBy(dw=1000, dh=1000)],
    [NudgeBy(dw=-1000, dh=-1000)],
    [StartResize(edge=East, x=0, y=0), PointerMove(x=1000, y=0)],
    [StartResize(edge=East, x=0, y=0), PointerMove(x=-1000, y=0)],
    [StartResize(edge=South, x=0, y=0), PointerMove(x=0, y=1000)],
    [StartResize(edge=South, x=0, y=0), PointerMove(x=0, y=-1000)],
    [
      StartResize(edge=SouthEast, x=10, y=10),
      PointerMove(x=1000, y=-1000),
      EndResize,
      NudgeBy(dw=-1000, dh=1000),
    ],
    [
      PointerMove(x=99, y=99),
      EndResize,
      StartResize(edge=SouthEast, x=0, y=0),
      PointerMove(x=25, y=35),
      EndResize,
      EndResize,
    ],
  ]
  for seq in sequences {
    let model = apply_messages(Model::new(w=120, h=90, constraints~), seq)
    assert_in_bounds(model, constraints)
  }
}

///|
test "EndResize clears drag and is idempotent" {
  let dragging = test_model().update(StartResize(edge=East, x=10, y=20))
  assert_true(dragging.is_resizing())
  let once = dragging.update(EndResize)
  let twice = once.update(EndResize)
  assert_true(!once.is_resizing())
  assert_same_public_state(once, twice)
}

///|
test "StartResize followed by same-point PointerMove leaves size unchanged" {
  let model = test_model()
  let moved = model
    .update(StartResize(edge=SouthEast, x=42, y=71))
    .update(PointerMove(x=42, y=71))
  assert_eq(moved.width(), model.width())
  assert_eq(moved.height(), model.height())
  assert_true(moved.is_resizing())
}

///|
test "PointerMove with no active drag is identity" {
  let model = test_model()
  let moved = model.update(PointerMove(x=900, y=900))
  assert_same_public_state(model, moved)
}

///|
test "East drag width change equals delta within bounds" {
  let model = test_model()
  let moved = model
    .update(StartResize(edge=East, x=10, y=5))
    .update(PointerMove(x=45, y=105))
  assert_eq(moved.width(), model.width() + 35)
  assert_eq(moved.height(), model.height())
}
