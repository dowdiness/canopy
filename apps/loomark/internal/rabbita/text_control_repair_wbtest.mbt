///|
test "rejected insertion maps a non-BMP UTF-16 text cursor back to accepted source" {
  let selection = rejected_text_selection(
    "A😀B",
    "A😀XB",
    @dom_boundary.TextSelection(4, 4, @dom_boundary.NoDirection),
  )
  inspect(selection.start(), content="3")
  inspect(selection.end(), content="3")
}

///|
test "rejected replacement maps a range around the accepted span" {
  let selection = rejected_text_selection(
    "abcdef",
    "abXef",
    @dom_boundary.TextSelection(2, 3, @dom_boundary.Backward),
  )
  inspect(selection.start(), content="2")
  inspect(selection.end(), content="4")
  guard selection.direction() is @dom_boundary.Backward else {
    fail("expected selection direction to be preserved")
  }
}

///|
test "rejected Raw repair maps canonical CRLF to textarea LF offsets" {
  let selection = rejected_text_selection(
    "a\r\nb",
    "a\nbx",
    @dom_boundary.TextSelection(4, 4, @dom_boundary.NoDirection),
  )
  assert_eq(selection.start(), 3)
  assert_eq(selection.end(), 3)
}

///|
test "rejected Raw repair maps canonical lone CR to textarea LF offsets" {
  let selection = rejected_text_selection(
    "a\rb",
    "a\nbx",
    @dom_boundary.TextSelection(4, 4, @dom_boundary.NoDirection),
  )
  assert_eq(selection.start(), 3)
  assert_eq(selection.end(), 3)
}

///|
test "Raw coordinator without telemetry keeps phase snapshots empty" {
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  guard coordinator.phase_json() is None else {
    fail("standalone Raw coordinator must not expose phase telemetry")
  }
}

///|
test "Raw coordinator suppresses only the matching composition repair" {
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  coordinator.suppress_composing_input_repair()
  assert_false(coordinator.take_unmatched_input_repair())
  assert_true(coordinator.take_unmatched_input_repair())
}

///|
test "Raw composition keeps intermediate DOM state out of pending input" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-composition-intermediate", "start",
  )
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  let before_input = RawBeforeInputCandidate::RawBeforeInputCandidate(
    selection=context.selection(5, 5),
    input_type="insertCompositionText",
    is_composing=false,
  )

  assert_true(
    coordinator.begin_composition(
      before_input,
      "start",
      @dom_boundary.TextSelection(5, 5, @dom_boundary.NoDirection),
    ),
  )
  assert_true(
    coordinator.update_composition(
      "startか",
      @dom_boundary.TextSelection(6, 6, @dom_boundary.NoDirection),
    ),
  )

  assert_eq(coordinator.display_source("start"), "startか")
  assert_true(coordinator.pending.val is None)
  assert_true(coordinator.in_flight_token.val is None)
}

///|
test "Raw composition end releases one immediate final transaction" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-composition-final", "start",
  )
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  assert_true(
    coordinator.begin_composition(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(5, 5),
        input_type="insertCompositionText",
        is_composing=false,
      ),
      "start",
      @dom_boundary.TextSelection(5, 5, @dom_boundary.NoDirection),
    ),
  )
  assert_true(
    coordinator.update_composition(
      "start漢字",
      @dom_boundary.TextSelection(7, 7, @dom_boundary.NoDirection),
    ),
  )

  ignore(coordinator.finish_composition("start", emit))

  assert_true(coordinator.composition.val is None)
  assert_true(coordinator.pending.val is None)
  assert_eq(coordinator.in_flight_token.val, Some(0))
  assert_eq(coordinator.in_flight_source.val, Some("start漢字"))
}

///|
test "Canceled Raw composition never becomes an editor transaction" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-composition-cancel", "start",
  )
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  assert_true(
    coordinator.begin_composition(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(5, 5),
        input_type="insertCompositionText",
        is_composing=false,
      ),
      "start",
      @dom_boundary.TextSelection(5, 5, @dom_boundary.NoDirection),
    ),
  )
  assert_true(
    coordinator.update_composition(
      "start",
      @dom_boundary.TextSelection(5, 5, @dom_boundary.NoDirection),
    ),
  )

  ignore(coordinator.finish_composition("start", emit))

  assert_true(coordinator.composition.val is None)
  assert_true(coordinator.pending.val is None)
  assert_true(coordinator.in_flight_token.val is None)
  assert_true(coordinator.unmatched_before_input.val is None)
}

///|
test "Raw composition ignores one same-value final input while delivery is active" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-composition-duplicate-final", "start",
  )
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  assert_true(
    coordinator.begin_composition(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(5, 5),
        input_type="insertCompositionText",
        is_composing=false,
      ),
      "start",
      @dom_boundary.TextSelection(5, 5, @dom_boundary.NoDirection),
    ),
  )
  assert_true(
    coordinator.update_composition(
      "start漢字",
      @dom_boundary.TextSelection(7, 7, @dom_boundary.NoDirection),
    ),
  )
  ignore(coordinator.finish_composition("start", emit))
  coordinator.unmatched_before_input.val = None

  ignore(
    coordinator.enqueue(
      "start漢字",
      @dom_boundary.TextSelection(7, 7, @dom_boundary.NoDirection),
      emit,
    ),
  )

  assert_true(coordinator.pending.val is None)
  assert_eq(coordinator.in_flight_token.val, Some(0))
  assert_eq(coordinator.in_flight_source.val, Some("start漢字"))
}

///|
test "Raw input keeps latest same-value text after a different pending value" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-latest-same-as-active", "x",
  )
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  let capture = () => {
    coordinator.capture_before_input(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(1, 1),
        input_type="insertText",
        is_composing=false,
      ),
    )
  }
  ignore(capture())
  ignore(
    coordinator.enqueue(
      "A",
      @dom_boundary.TextSelection(1, 1, @dom_boundary.NoDirection),
      emit,
    ),
  )
  guard coordinator.take_pending_delivery() is Some((0, _)) else {
    fail("first value must become active")
  }
  ignore(capture())
  ignore(
    coordinator.enqueue(
      "B",
      @dom_boundary.TextSelection(1, 1, @dom_boundary.NoDirection),
      emit,
    ),
  )
  ignore(capture())
  ignore(
    coordinator.enqueue(
      "A",
      @dom_boundary.TextSelection(1, 1, @dom_boundary.NoDirection),
      emit,
    ),
  )

  guard coordinator.pending.val is Some(pending) else {
    fail("latest value must remain pending")
  }
  assert_eq(pending.source, "A")
}

///|
test "Raw composition releases promoted input without a composition input" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-composition-no-input", "abcdef",
  )
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  ignore(
    coordinator.capture_before_input(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(4, 2),
        input_type="insertText",
        is_composing=false,
      ),
    ),
  )
  ignore(
    coordinator.enqueue(
      "abxyef",
      @dom_boundary.TextSelection(4, 4, @dom_boundary.NoDirection),
      emit,
    ),
  )
  assert_true(
    coordinator.begin_composition(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(4, 4),
        input_type="insertCompositionText",
        is_composing=false,
      ),
      "abcdef",
      @dom_boundary.TextSelection(4, 4, @dom_boundary.NoDirection),
    ),
  )

  ignore(coordinator.finish_composition("abcdef", emit))

  assert_true(coordinator.composition.val is None)
  assert_eq(coordinator.in_flight_source.val, Some("abxyef"))
  assert_eq(coordinator.in_flight_token.val, Some(0))
}

///|
test "Raw composition keeps a pending ordinary input as its transaction base" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-composition-pending-base", "abcdef",
  )
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  ignore(
    coordinator.capture_before_input(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(4, 2),
        input_type="insertText",
        is_composing=false,
      ),
    ),
  )
  ignore(
    coordinator.enqueue(
      "abxyef",
      @dom_boundary.TextSelection(4, 4, @dom_boundary.NoDirection),
      emit,
    ),
  )
  assert_true(
    coordinator.begin_composition(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(4, 4),
        input_type="insertCompositionText",
        is_composing=false,
      ),
      "abcdef",
      @dom_boundary.TextSelection(4, 4, @dom_boundary.NoDirection),
    ),
  )
  guard coordinator.composition.val is Some(started) else {
    fail("composition must promote the pending ordinary input")
  }
  assert_eq(started.source, "abxyef")
  assert_true(
    coordinator.update_composition(
      "abxy漢ef",
      @dom_boundary.TextSelection(5, 5, @dom_boundary.NoDirection),
    ),
  )

  guard coordinator.composition.val is Some(input) else {
    fail("composition must retain one complete final transaction")
  }
  assert_eq(input.before_input.selection.selection.anchor(), 4)
  assert_eq(input.before_input.selection.selection.head(), 2)
  assert_eq(input.source, "abxy漢ef")
  assert_eq(input.post_input_selection.start(), 5)
  assert_true(coordinator.pending.val is None)
}

///|
test "Raw coordinator keeps the first backward base and latest collapsed caret" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "coordinator-pairing", "abcdef",
  )
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  ignore(
    coordinator.capture_before_input(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(4, 2),
        input_type="insertText",
        is_composing=false,
      ),
    ),
  )
  ignore(
    coordinator.enqueue(
      "abxyef",
      @dom_boundary.TextSelection(4, 4, @dom_boundary.NoDirection),
      emit,
    ),
  )
  ignore(
    coordinator.capture_before_input(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(4, 4),
        input_type="insertText",
        is_composing=false,
      ),
    ),
  )
  ignore(
    coordinator.enqueue(
      "abxyZef",
      @dom_boundary.TextSelection(5, 5, @dom_boundary.NoDirection),
      emit,
    ),
  )
  guard coordinator.pending.val is Some(pending) else {
    fail("first capture must remain the batch base")
  }
  assert_eq(pending.before_input.selection.selection.anchor(), 4)
  assert_eq(pending.before_input.selection.selection.head(), 2)
  assert_eq(pending.source, "abxyZef")
  assert_eq(pending.post_input_selection.start(), 5)
  assert_eq(pending.input_count, 2)
}

///|
test "Raw coordinator discards a batch on version or document mismatch" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "coordinator-frontier-mismatch", "abc",
  )
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  let capture = selection => {
    RawBeforeInputCandidate::RawBeforeInputCandidate(
      selection~,
      input_type="insertText",
      is_composing=false,
    )
  }
  ignore(coordinator.capture_before_input(capture(context.selection(1, 1))))
  ignore(
    coordinator.enqueue(
      "aXbc",
      @dom_boundary.TextSelection(2, 2, @dom_boundary.NoDirection),
      emit,
    ),
  )
  let (advanced_model, _) = context.commit(
    context.model,
    context.selection(0, 0),
    "q",
  )
  let advanced = {
    ..context.selection(1, 1),
    version: advanced_model.document_version,
  }
  ignore(coordinator.capture_before_input(capture(advanced)))
  ignore(
    coordinator.enqueue(
      "aXYbc",
      @dom_boundary.TextSelection(3, 3, @dom_boundary.NoDirection),
      emit,
    ),
  )
  assert_true(coordinator.pending.val is None)

  ignore(coordinator.capture_before_input(capture(context.selection(1, 1))))
  ignore(
    coordinator.enqueue(
      "aXbc",
      @dom_boundary.TextSelection(2, 2, @dom_boundary.NoDirection),
      emit,
    ),
  )
  let other = RawSelectionTestContext::RawSelectionTestContext(
    "coordinator-other-document", "abc",
  )
  ignore(coordinator.capture_before_input(capture(other.selection(1, 1))))
  ignore(
    coordinator.enqueue(
      "aXYbc",
      @dom_boundary.TextSelection(3, 3, @dom_boundary.NoDirection),
      emit,
    ),
  )
  assert_true(coordinator.pending.val is None)
}

///|
test "Raw coordinator input without capture discards a pending batch" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "coordinator-no-capture", "abc",
  )
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  ignore(
    coordinator.capture_before_input(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(1, 1),
        input_type="insertText",
        is_composing=false,
      ),
    ),
  )
  ignore(
    coordinator.enqueue(
      "aXbc",
      @dom_boundary.TextSelection(2, 2, @dom_boundary.NoDirection),
      emit,
    ),
  )
  ignore(
    coordinator.enqueue(
      "aXYbc",
      @dom_boundary.TextSelection(3, 3, @dom_boundary.NoDirection),
      emit,
    ),
  )
  assert_true(coordinator.pending.val is None)
}

///|
test "Raw coordinator discards a composition-intermediate capture" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "coordinator-composition", "abc",
  )
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  ignore(
    coordinator.capture_before_input(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(1, 1),
        input_type="insertCompositionText",
        is_composing=true,
      ),
    ),
  )
  ignore(
    coordinator.enqueue(
      "aXbc",
      @dom_boundary.TextSelection(2, 2, @dom_boundary.NoDirection),
      emit,
    ),
  )
  assert_true(coordinator.unmatched_before_input.val is None)
  assert_true(coordinator.pending.val is None)
}

///|
test "Raw input cancellation clears live composition" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-composition-cancel-pending", "start",
  )
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  assert_true(
    coordinator.begin_composition(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(5, 5),
        input_type="insertCompositionText",
        is_composing=false,
      ),
      "start",
      @dom_boundary.TextSelection(5, 5, @dom_boundary.NoDirection),
    ),
  )
  assert_true(
    coordinator.update_composition(
      "start漢",
      @dom_boundary.TextSelection(6, 6, @dom_boundary.NoDirection),
    ),
  )
  assert_eq(coordinator.display_source("start"), "start漢")

  coordinator.cancel_pending()

  assert_true(coordinator.composition.val is None)
  assert_true(coordinator.pending.val is None)
  assert_true(coordinator.in_flight_token.val is None)
  assert_eq(coordinator.display_source("start"), "start")
}

///|
test "Raw coordinator capture expiry clears only an unmatched capture" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "coordinator-expiry", "abc",
  )
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  ignore(
    coordinator.capture_before_input(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(1, 1),
        input_type="insertText",
        is_composing=false,
      ),
    ),
  )
  ignore(
    coordinator.enqueue(
      "aXbc",
      @dom_boundary.TextSelection(2, 2, @dom_boundary.NoDirection),
      emit,
    ),
  )
  ignore(
    coordinator.capture_before_input(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(2, 2),
        input_type="insertText",
        is_composing=false,
      ),
    ),
  )
  let generation = coordinator.capture_generation.val
  coordinator.expire_before_input(generation)
  assert_true(coordinator.unmatched_before_input.val is None)
  guard coordinator.pending.val is Some(pending) else {
    fail("capture expiry must preserve the pending batch")
  }
  assert_eq(pending.source, "aXbc")
  assert_eq(pending.input_count, 1)
}

///|
test "Raw coordinator cancel clears all state and invalidates capture expiry" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "coordinator-cancel", "abc",
  )
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  ignore(
    coordinator.capture_before_input(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(1, 1),
        input_type="insertText",
        is_composing=false,
      ),
    ),
  )
  ignore(
    coordinator.enqueue(
      "aXbc",
      @dom_boundary.TextSelection(2, 2, @dom_boundary.NoDirection),
      emit,
    ),
  )
  ignore(
    coordinator.capture_before_input(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(2, 2),
        input_type="insertText",
        is_composing=false,
      ),
    ),
  )
  let expiry_generation = coordinator.capture_generation.val
  coordinator.in_flight_token.val = Some(7)
  coordinator.in_flight_source.val = Some("in-flight")
  coordinator.cancel_pending()
  coordinator.expire_before_input(expiry_generation)
  assert_true(coordinator.unmatched_before_input.val is None)
  assert_true(coordinator.pending.val is None)
  assert_true(coordinator.in_flight_token.val is None)
  assert_true(coordinator.in_flight_source.val is None)
  assert_false(coordinator.scheduled.val)
}
