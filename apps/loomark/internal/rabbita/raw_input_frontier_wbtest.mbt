///|
test "Raw frontier reducer keeps deferred input ahead of the active delivery" {
  let state = RawInputFrontierState::initial()
  let active = reduce_raw_input_frontier(
    state,
    RawInputFrontierEvent::BeginDelivery({ token: 4, source: "startX" }),
  )
  let captured = reduce_raw_input_frontier(
    active,
    RawInputFrontierEvent::CaptureDeferredBeforeInput({
      base_source: "startX",
      input_type: "insertText",
    }),
  )
  let deferred = {
    base_source: "startX",
    input_type: "insertText",
    source: "startXY",
    post_input_selection: @dom_boundary.TextSelection(
      7,
      7,
      @dom_boundary.NoDirection,
    ),
    input_count: 1,
  }
  let next = reduce_raw_input_frontier(
    captured,
    RawInputFrontierEvent::StoreDeferred(deferred),
  )
  guard next.in_flight is Some(delivery) else {
    fail("storing deferred input must retain the active delivery")
  }
  assert_eq(delivery.token, 4)
  guard next.deferred is Some(input) else {
    fail("storing deferred input must retain its latest snapshot")
  }
  assert_eq(input.source, "startXY")
  assert_true(next.deferred_before_input is None)
}

///|
test "Raw frontier reducer keeps composition behind the active delivery" {
  let active = reduce_raw_input_frontier(
    RawInputFrontierState::initial(),
    RawInputFrontierEvent::BeginDelivery({ token: 4, source: "startX" }),
  )
  let composition = reduce_raw_input_frontier(
    active,
    RawInputFrontierEvent::BeginDeferredComposition({
      base_source: "startX",
      input_type: "insertCompositionText",
      source: "startX",
      post_input_selection: @dom_boundary.TextSelection(
        6,
        6,
        @dom_boundary.NoDirection,
      ),
      input_count: 0,
    }),
  )
  guard composition.deferred_composition is Some(input) else {
    fail("active composition must be retained behind the delivery")
  }
  assert_eq(input.source, "startX")
  let updated = reduce_raw_input_frontier(
    composition,
    RawInputFrontierEvent::UpdateDeferredComposition({
      ..input,
      source: "startX漢",
      post_input_selection: @dom_boundary.TextSelection(
        7,
        7,
        @dom_boundary.NoDirection,
      ),
      input_count: 1,
    }),
  )
  guard updated.deferred_composition is Some(latest) else {
    fail("composition updates must retain the deferred frontier")
  }
  assert_eq(latest.source, "startX漢")
  assert_true(updated.in_flight is Some(_))
  assert_true(updated.deferred is None)
}

///|
test "Raw frontier reducer rejects capture without an active delivery" {
  let state = RawInputFrontierState::initial()
  let next = reduce_raw_input_frontier(
    state,
    RawInputFrontierEvent::CaptureDeferredBeforeInput({
      base_source: "start",
      input_type: "insertText",
    }),
  )
  assert_true(next.deferred_before_input is None)
  assert_true(next.in_flight is None)
}

///|
test "Raw frontier reducer does not overwrite an active delivery" {
  let state = reduce_raw_input_frontier(
    RawInputFrontierState::initial(),
    RawInputFrontierEvent::BeginDelivery({ token: 4, source: "startX" }),
  )
  let next = reduce_raw_input_frontier(
    state,
    RawInputFrontierEvent::BeginDelivery({ token: 5, source: "startY" }),
  )
  guard next.in_flight is Some(delivery) else {
    fail("active delivery must remain present")
  }
  assert_eq(delivery.token, 4)
  assert_eq(delivery.source, "startX")
}

///|
test "Raw frontier reducer finishes only the matching delivery" {
  let state = reduce_raw_input_frontier(
    RawInputFrontierState::initial(),
    RawInputFrontierEvent::BeginDelivery({ token: 4, source: "startX" }),
  )
  let unchanged = reduce_raw_input_frontier(
    state,
    RawInputFrontierEvent::FinishDelivery(3),
  )
  assert_true(unchanged.in_flight is Some(_))
  let finished = reduce_raw_input_frontier(
    unchanged,
    RawInputFrontierEvent::FinishDelivery(4),
  )
  assert_true(finished.in_flight is None)
}

///|
test "Raw frontier reducer cancellation clears deferred and active state" {
  let state = reduce_raw_input_frontier(
    RawInputFrontierState::initial(),
    RawInputFrontierEvent::BeginDelivery({ token: 4, source: "startX" }),
  )
  let captured = reduce_raw_input_frontier(
    state,
    RawInputFrontierEvent::CaptureDeferredBeforeInput({
      base_source: "startX",
      input_type: "insertText",
    }),
  )
  let canceled = reduce_raw_input_frontier(
    captured,
    RawInputFrontierEvent::Cancel,
  )
  assert_true(canceled.in_flight is None)
  assert_true(canceled.deferred is None)
  assert_true(canceled.deferred_before_input is None)
}
