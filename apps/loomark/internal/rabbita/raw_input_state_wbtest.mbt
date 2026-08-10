///|
fn raw_state_test_input(source : String) -> PendingRawInput {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-state-reducer-test", "start",
  )
  {
    before_input: RawBeforeInputCandidate::RawBeforeInputCandidate(
      selection=context.selection(5, 5),
      input_type="insertText",
      is_composing=false,
    ),
    source,
    post_input_selection: @dom_boundary.TextSelection(
      5,
      5,
      @dom_boundary.NoDirection,
    ),
    input_count: 1,
  }
}

///|
test "Raw state reducer delivers pending input atomically" {
  let input = raw_state_test_input("startX")
  let (stored, _) = reduce_raw_input(
    RawInputState::initial(),
    RawInputEvent::StorePending(input),
  )
  let (active, decision) = reduce_raw_input(
    stored,
    RawInputEvent::BeginPendingDelivery(7),
  )
  guard decision is RawInputDecision::Deliver(token, delivered) else {
    fail("pending delivery must produce an explicit delivery decision")
  }
  assert_eq(token, 7)
  assert_eq(delivered.source, "startX")
  assert_true(active.pending is None)
  guard active.in_flight is Some(delivery) else {
    fail("pending delivery must become the active frontier")
  }
  assert_eq(delivery.token, 7)
  assert_eq(delivery.source, "startX")
}

///|
test "Raw state reducer keeps pending input behind an active frontier" {
  let active = {
    let (state, _) = reduce_raw_input(
      RawInputState::initial(),
      RawInputEvent::BeginDelivery({ token: 3, source: "start" }),
    )
    state
  }
  let (next, decision) = reduce_raw_input(
    active,
    RawInputEvent::StorePending(raw_state_test_input("startX")),
  )
  guard next.pending is Some(input) else {
    fail("pending input must wait behind the active frontier")
  }
  assert_eq(input.source, "startX")
  assert_true(next.in_flight is Some(_))
  assert_true(decision is RawInputDecision::StoredPending)
}

///|
test "Raw state reducer retains pending input when deferred composition starts" {
  let (active, _) = reduce_raw_input(
    RawInputState::initial(),
    RawInputEvent::BeginDelivery({ token: 3, source: "start" }),
  )
  let (with_pending, _) = reduce_raw_input(
    active,
    RawInputEvent::StorePending(raw_state_test_input("startX")),
  )
  let (next, _) = reduce_raw_input(
    with_pending,
    RawInputEvent::BeginDeferredComposition({
      base_source: "start",
      input_type: "insertCompositionText",
      before_input_selection: @dom_boundary.TextSelection(
        5,
        5,
        @dom_boundary.NoDirection,
      ),
      source: "start",
      post_input_selection: @dom_boundary.TextSelection(
        5,
        5,
        @dom_boundary.NoDirection,
      ),
      input_count: 0,
    }),
  )
  guard next.pending is Some(pending) else {
    fail("deferred composition must not discard a pending ordinary input")
  }
  assert_eq(pending.source, "startX")
  assert_true(next.deferred_composition is Some(_))
}

///|
test "Raw state reducer retains pending input when ordinary input is deferred" {
  let (active, _) = reduce_raw_input(
    RawInputState::initial(),
    RawInputEvent::BeginDelivery({ token: 3, source: "start" }),
  )
  let (with_pending, _) = reduce_raw_input(
    active,
    RawInputEvent::StorePending(raw_state_test_input("startX")),
  )
  let (captured, _) = reduce_raw_input(
    with_pending,
    RawInputEvent::CaptureDeferredBeforeInput({
      base_source: "start",
      input_type: "insertText",
      selection: @dom_boundary.TextSelection(5, 5, @dom_boundary.NoDirection),
    }),
  )
  let (next, _) = reduce_raw_input(
    captured,
    RawInputEvent::StoreDeferred({
      base_source: "start",
      input_type: "insertText",
      before_input_selection: @dom_boundary.TextSelection(
        5,
        5,
        @dom_boundary.NoDirection,
      ),
      source: "startXY",
      post_input_selection: @dom_boundary.TextSelection(
        7,
        7,
        @dom_boundary.NoDirection,
      ),
      input_count: 1,
    }),
  )
  assert_true(next.pending is Some(_))
  assert_true(next.deferred is Some(_))
}

///|
test "Raw state reducer keeps pending input through deferred composition no-op" {
  let (active, _) = reduce_raw_input(
    RawInputState::initial(),
    RawInputEvent::BeginDelivery({ token: 3, source: "start" }),
  )
  let (with_pending, _) = reduce_raw_input(
    active,
    RawInputEvent::StorePending(raw_state_test_input("startX")),
  )
  let (deferred, _) = reduce_raw_input(
    with_pending,
    RawInputEvent::BeginDeferredComposition({
      base_source: "start",
      input_type: "insertCompositionText",
      before_input_selection: @dom_boundary.TextSelection(
        5,
        5,
        @dom_boundary.NoDirection,
      ),
      source: "start",
      post_input_selection: @dom_boundary.TextSelection(
        5,
        5,
        @dom_boundary.NoDirection,
      ),
      input_count: 0,
    }),
  )
  let (finished, _) = reduce_raw_input(
    deferred,
    RawInputEvent::MarkDeferredCompositionFinished,
  )
  let (cleared_composition, _) = reduce_raw_input(
    finished,
    RawInputEvent::ClearDeferredComposition,
  )
  let (next, _) = reduce_raw_input(
    cleared_composition,
    RawInputEvent::ClearDeferredCompositionFinished,
  )
  guard next.pending is Some(pending) else {
    fail("a deferred composition no-op must retain ordinary pending input")
  }
  assert_eq(pending.source, "startX")
  assert_false(next.deferred_composition_finished)
}

///|
test "Raw state reducer clears completion marker after follow-up delivery" {
  let (active, _) = reduce_raw_input(
    RawInputState::initial(),
    RawInputEvent::BeginDelivery({ token: 3, source: "start" }),
  )
  let (deferred, _) = reduce_raw_input(
    active,
    RawInputEvent::BeginDeferredComposition({
      base_source: "start",
      input_type: "insertCompositionText",
      before_input_selection: @dom_boundary.TextSelection(
        5,
        5,
        @dom_boundary.NoDirection,
      ),
      source: "start漢",
      post_input_selection: @dom_boundary.TextSelection(
        6,
        6,
        @dom_boundary.NoDirection,
      ),
      input_count: 1,
    }),
  )
  let (finished, _) = reduce_raw_input(
    deferred,
    RawInputEvent::MarkDeferredCompositionFinished,
  )
  let (after_original, _) = reduce_raw_input(
    finished,
    RawInputEvent::FinishDelivery(3),
  )
  assert_true(after_original.deferred_composition_finished)
  let (cleared, _) = reduce_raw_input(
    after_original,
    RawInputEvent::ClearDeferredComposition,
  )
  let (stored, decision) = reduce_raw_input(
    cleared,
    RawInputEvent::StorePending(raw_state_test_input("start漢")),
  )
  assert_true(decision is RawInputDecision::StoredPending)
  let (follow_up, delivery_decision) = reduce_raw_input(
    stored,
    RawInputEvent::BeginPendingDelivery(4),
  )
  assert_true(delivery_decision is RawInputDecision::Deliver(_, _))
  let (done, _) = reduce_raw_input(follow_up, RawInputEvent::FinishDelivery(4))
  assert_false(done.deferred_composition_finished)
}

///|
test "Raw state reducer discards only the matching active delivery" {
  let (active, _) = reduce_raw_input(
    RawInputState::initial(),
    RawInputEvent::BeginDelivery({ token: 3, source: "start" }),
  )
  let (with_pending, _) = reduce_raw_input(
    active,
    RawInputEvent::StorePending(raw_state_test_input("startX")),
  )
  let (unchanged, _) = reduce_raw_input(
    with_pending,
    RawInputEvent::DiscardDelivery(2),
  )
  assert_true(unchanged.in_flight is Some(_))
  assert_true(unchanged.pending is Some(_))
  let (discarded, _) = reduce_raw_input(
    unchanged,
    RawInputEvent::DiscardDelivery(3),
  )
  assert_true(discarded.in_flight is None)
  assert_true(discarded.pending is None)
}

///|
test "Raw state reducer rejects pending input during live composition" {
  let (composing, _) = reduce_raw_input(
    RawInputState::initial(),
    RawInputEvent::BeginComposition(raw_state_test_input("start")),
  )
  let (next, decision) = reduce_raw_input(
    composing,
    RawInputEvent::StorePending(raw_state_test_input("startX")),
  )
  assert_true(next.pending is None)
  assert_true(next.composition is Some(_))
  assert_true(decision is RawInputDecision::Noop)
}

///|
test "Raw state reducer promotes pending input into composition" {
  let pending = raw_state_test_input("startX")
  let (stored, _) = reduce_raw_input(
    RawInputState::initial(),
    RawInputEvent::StorePending(pending),
  )
  let composition_input = raw_state_test_input("startX")
  let (composing, _) = reduce_raw_input(
    stored,
    RawInputEvent::BeginComposition(composition_input),
  )
  assert_true(composing.pending is None)
  guard composing.composition is Some(input) else {
    fail("composition must own the promoted input")
  }
  assert_eq(input.source, "startX")
  let (updated, _) = reduce_raw_input(
    composing,
    RawInputEvent::UpdateComposition({ ..input, source: "start漢" }),
  )
  guard updated.composition is Some(latest) else {
    fail("composition update must retain the live composition")
  }
  assert_eq(latest.source, "start漢")
}

///|
test "Raw state reducer rejects composition start behind every deferred frontier" {
  let input = raw_state_test_input("start漢")
  let (active, _) = reduce_raw_input(
    RawInputState::initial(),
    RawInputEvent::BeginDelivery({ token: 5, source: "start" }),
  )
  let (active_unchanged, active_decision) = reduce_raw_input(
    active,
    RawInputEvent::BeginComposition(input),
  )
  assert_true(active_unchanged.in_flight is Some(_))
  assert_true(active_unchanged.composition is None)
  assert_true(active_decision is RawInputDecision::Noop)

  let (captured, _) = reduce_raw_input(
    active,
    RawInputEvent::CaptureDeferredBeforeInput({
      base_source: "start",
      input_type: "insertText",
      selection: @dom_boundary.TextSelection(5, 5, @dom_boundary.NoDirection),
    }),
  )
  let (captured_unchanged, captured_decision) = reduce_raw_input(
    captured,
    RawInputEvent::BeginComposition(input),
  )
  assert_true(captured_unchanged.deferred_before_input is Some(_))
  assert_true(captured_unchanged.composition is None)
  assert_true(captured_decision is RawInputDecision::Noop)

  let (deferred, _) = reduce_raw_input(
    captured,
    RawInputEvent::StoreDeferred({
      base_source: "start",
      input_type: "insertText",
      before_input_selection: @dom_boundary.TextSelection(
        5,
        5,
        @dom_boundary.NoDirection,
      ),
      source: "startX",
      post_input_selection: @dom_boundary.TextSelection(
        6,
        6,
        @dom_boundary.NoDirection,
      ),
      input_count: 1,
    }),
  )
  let (deferred_unchanged, deferred_decision) = reduce_raw_input(
    deferred,
    RawInputEvent::BeginComposition(input),
  )
  assert_true(deferred_unchanged.deferred is Some(_))
  assert_true(deferred_unchanged.composition is None)
  assert_true(deferred_decision is RawInputDecision::Noop)

  let (deferred_composition, _) = reduce_raw_input(
    active,
    RawInputEvent::BeginDeferredComposition({
      base_source: "start",
      input_type: "insertCompositionText",
      before_input_selection: @dom_boundary.TextSelection(
        5,
        5,
        @dom_boundary.NoDirection,
      ),
      source: "start漢",
      post_input_selection: @dom_boundary.TextSelection(
        6,
        6,
        @dom_boundary.NoDirection,
      ),
      input_count: 1,
    }),
  )
  let (deferred_composition_unchanged, deferred_composition_decision) = reduce_raw_input(
    deferred_composition,
    RawInputEvent::BeginComposition(input),
  )
  assert_true(deferred_composition_unchanged.deferred_composition is Some(_))
  assert_true(deferred_composition_unchanged.composition is None)
  assert_true(deferred_composition_decision is RawInputDecision::Noop)
}

///|
test "Raw state reducer tracks deferred composition completion" {
  let (active, _) = reduce_raw_input(
    RawInputState::initial(),
    RawInputEvent::BeginDelivery({ token: 4, source: "start" }),
  )
  let (deferred, _) = reduce_raw_input(
    active,
    RawInputEvent::BeginDeferredComposition({
      base_source: "start",
      input_type: "insertCompositionText",
      before_input_selection: @dom_boundary.TextSelection(
        5,
        5,
        @dom_boundary.NoDirection,
      ),
      source: "start",
      post_input_selection: @dom_boundary.TextSelection(
        5,
        5,
        @dom_boundary.NoDirection,
      ),
      input_count: 0,
    }),
  )
  let (finished, _) = reduce_raw_input(
    deferred,
    RawInputEvent::MarkDeferredCompositionFinished,
  )
  assert_true(finished.deferred_composition_finished)
  let (cleared, _) = reduce_raw_input(
    finished,
    RawInputEvent::ClearDeferredCompositionFinished,
  )
  assert_false(cleared.deferred_composition_finished)
}

///|
test "Raw state reducer keeps the completion marker on duplicate deferred begin" {
  let (active, _) = reduce_raw_input(
    RawInputState::initial(),
    RawInputEvent::BeginDelivery({ token: 4, source: "start" }),
  )
  let (deferred, _) = reduce_raw_input(
    active,
    RawInputEvent::BeginDeferredComposition({
      base_source: "start",
      input_type: "insertCompositionText",
      before_input_selection: @dom_boundary.TextSelection(
        5,
        5,
        @dom_boundary.NoDirection,
      ),
      source: "start漢",
      post_input_selection: @dom_boundary.TextSelection(
        6,
        6,
        @dom_boundary.NoDirection,
      ),
      input_count: 1,
    }),
  )
  let (finished, _) = reduce_raw_input(
    deferred,
    RawInputEvent::MarkDeferredCompositionFinished,
  )
  let (unchanged, decision) = reduce_raw_input(
    finished,
    RawInputEvent::BeginDeferredComposition({
      base_source: "start",
      input_type: "insertCompositionText",
      before_input_selection: @dom_boundary.TextSelection(
        5,
        5,
        @dom_boundary.NoDirection,
      ),
      source: "start別",
      post_input_selection: @dom_boundary.TextSelection(
        6,
        6,
        @dom_boundary.NoDirection,
      ),
      input_count: 1,
    }),
  )
  assert_true(unchanged.deferred_composition_finished)
  assert_true(unchanged.deferred_composition is Some(_))
  assert_true(decision is RawInputDecision::Noop)
}

///|
test "Raw state reducer ignores mismatched delivery completion" {
  let (active, _) = reduce_raw_input(
    RawInputState::initial(),
    RawInputEvent::BeginDelivery({ token: 4, source: "start" }),
  )
  let (unchanged, decision) = reduce_raw_input(
    active,
    RawInputEvent::FinishDelivery(5),
  )
  assert_true(unchanged.in_flight is Some(_))
  assert_true(decision is RawInputDecision::Noop)
}

///|
test "Raw state reducer cancellation clears every semantic frontier" {
  let (active, _) = reduce_raw_input(
    RawInputState::initial(),
    RawInputEvent::BeginDelivery({ token: 4, source: "start" }),
  )
  let (deferred, _) = reduce_raw_input(
    active,
    RawInputEvent::BeginDeferredComposition({
      base_source: "start",
      input_type: "insertCompositionText",
      before_input_selection: @dom_boundary.TextSelection(
        5,
        5,
        @dom_boundary.NoDirection,
      ),
      source: "start漢",
      post_input_selection: @dom_boundary.TextSelection(
        6,
        6,
        @dom_boundary.NoDirection,
      ),
      input_count: 1,
    }),
  )
  let (finished, _) = reduce_raw_input(
    deferred,
    RawInputEvent::MarkDeferredCompositionFinished,
  )
  let (canceled, _) = reduce_raw_input(finished, RawInputEvent::Cancel)
  assert_true(canceled.pending is None)
  assert_true(canceled.composition is None)
  assert_true(canceled.deferred_before_input is None)
  assert_true(canceled.deferred is None)
  assert_true(canceled.deferred_composition is None)
  assert_true(canceled.in_flight is None)
  assert_false(canceled.deferred_composition_finished)
}
