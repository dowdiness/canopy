///|
fn test_in_flight_token(coordinator : RawInputCoordinator) -> Int? {
  match coordinator.frontier.val.in_flight {
    Some(delivery) => Some(delivery.token)
    None => None
  }
}

///|
fn test_in_flight_source(coordinator : RawInputCoordinator) -> String? {
  match coordinator.frontier.val.in_flight {
    Some(delivery) => Some(delivery.source)
    None => None
  }
}

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
  assert_true(coordinator.frontier.val.pending is None)
  assert_true(test_in_flight_token(coordinator) is None)
}

///|
test "Raw coordinator does not schedule a pending store during live composition" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-composition-pending-rejection", "start",
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
  ignore(
    coordinator.capture_before_input(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(5, 5),
        input_type="insertText",
        is_composing=false,
      ),
    ),
  )
  ignore(
    coordinator.enqueue(
      "startX",
      @dom_boundary.TextSelection(6, 6, @dom_boundary.NoDirection),
      emit,
    ),
  )
  assert_true(coordinator.frontier.val.pending is None)
  assert_true(coordinator.frontier.val.composition is Some(_))
  assert_false(coordinator.scheduled.val)
}

///|
test "Raw coordinator rejects composition start behind active delivery without generation changes" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-composition-active-rejection", "start",
  )
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  ignore(
    coordinator.capture_before_input(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(5, 5),
        input_type="insertText",
        is_composing=false,
      ),
    ),
  )
  ignore(
    coordinator.enqueue(
      "startX",
      @dom_boundary.TextSelection(6, 6, @dom_boundary.NoDirection),
      emit,
    ),
  )
  guard coordinator.take_pending_delivery() is Some((0, _)) else {
    fail("the test input must become active")
  }
  let schedule_generation = coordinator.schedule_generation.val
  let capture_generation = coordinator.capture_generation.val
  assert_false(
    coordinator.begin_composition(
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=context.selection(5, 5),
        input_type="insertCompositionText",
        is_composing=false,
      ),
      "startX",
      @dom_boundary.TextSelection(6, 6, @dom_boundary.NoDirection),
    ),
  )
  assert_eq(coordinator.schedule_generation.val, schedule_generation)
  assert_eq(coordinator.capture_generation.val, capture_generation)
  assert_true(coordinator.frontier.val.in_flight is Some(_))
  assert_true(coordinator.frontier.val.composition is None)
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

  assert_true(coordinator.frontier.val.composition is None)
  assert_true(coordinator.frontier.val.pending is None)
  assert_eq(test_in_flight_token(coordinator), Some(0))
  assert_eq(test_in_flight_source(coordinator), Some("start漢字"))
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

  assert_true(coordinator.frontier.val.composition is None)
  assert_true(coordinator.frontier.val.pending is None)
  assert_true(test_in_flight_token(coordinator) is None)
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

  assert_true(coordinator.frontier.val.pending is None)
  assert_eq(test_in_flight_token(coordinator), Some(0))
  assert_eq(test_in_flight_source(coordinator), Some("start漢字"))
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
  assert_true(coordinator.frontier.val.in_flight is Some(_))
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

  guard coordinator.frontier.val.pending is Some(pending) else {
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

  assert_true(coordinator.frontier.val.composition is None)
  assert_eq(test_in_flight_source(coordinator), Some("abxyef"))
  assert_eq(test_in_flight_token(coordinator), Some(0))
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
  guard coordinator.frontier.val.composition is Some(started) else {
    fail("composition must promote the pending ordinary input")
  }
  assert_eq(started.source, "abxyef")
  assert_true(
    coordinator.update_composition(
      "abxy漢ef",
      @dom_boundary.TextSelection(5, 5, @dom_boundary.NoDirection),
    ),
  )

  guard coordinator.frontier.val.composition is Some(input) else {
    fail("composition must retain one complete final transaction")
  }
  assert_eq(input.before_input.selection.selection.anchor(), 4)
  assert_eq(input.before_input.selection.selection.head(), 2)
  assert_eq(input.source, "abxy漢ef")
  assert_eq(input.post_input_selection.start(), 5)
  assert_true(coordinator.frontier.val.pending is None)
}

///|
test "Raw coordinator does not guess an unpaired in-flight input" {
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  coordinator.reduce_frontier(
    RawInputEvent::BeginDelivery({ token: 1, source: "startX" }),
  )
  let deferred = coordinator.defer_native_input(
    "startXY",
    @dom_boundary.TextSelection(7, 7, @dom_boundary.NoDirection),
  )
  assert_false(deferred)
  assert_true(coordinator.frontier.val.deferred is None)
}

///|
test "Raw coordinator keeps an active delivery for unpaired input" {
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  coordinator.reduce_frontier(
    RawInputEvent::BeginDelivery({ token: 1, source: "startX" }),
  )
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  ignore(
    coordinator.enqueue(
      "startXY",
      @dom_boundary.TextSelection(7, 7, @dom_boundary.NoDirection),
      emit,
    ),
  )
  assert_eq(test_in_flight_token(coordinator), Some(1))
  assert_eq(test_in_flight_source(coordinator), Some("startX"))
}

///|
test "Raw coordinator keeps the first deferred selection and latest native value" {
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  coordinator.reduce_frontier(
    RawInputEvent::BeginDelivery({ token: 1, source: "xx" }),
  )
  coordinator.reduce_frontier(
    RawInputEvent::CaptureDeferredBeforeInput({
      base_source: "xx",
      input_type: "insertText",
      selection: @dom_boundary.TextSelection(1, 1, @dom_boundary.NoDirection),
    }),
  )
  assert_true(
    coordinator.defer_native_input(
      "xxx",
      @dom_boundary.TextSelection(2, 2, @dom_boundary.NoDirection),
    ),
  )
  coordinator.reduce_frontier(
    RawInputEvent::CaptureDeferredBeforeInput({
      base_source: "xx",
      input_type: "insertFromPaste",
      selection: @dom_boundary.TextSelection(2, 2, @dom_boundary.NoDirection),
    }),
  )
  assert_true(
    coordinator.defer_native_input(
      "xxyx",
      @dom_boundary.TextSelection(3, 3, @dom_boundary.NoDirection),
    ),
  )

  guard coordinator.frontier.val.deferred is Some(deferred) else {
    fail("paired native input must remain deferred")
  }
  assert_eq(deferred.input_type, "insertText")
  assert_eq(deferred.before_input_selection.start(), 1)
  assert_eq(deferred.before_input_selection.end(), 1)
  assert_eq(deferred.source, "xxyx")
  assert_eq(deferred.post_input_selection.start(), 3)
  assert_eq(deferred.input_count, 2)
}

///|
test "deferred Raw composition keeps the first ordinary input selection" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-deferred-composition-selection", "xx",
  )
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  coordinator.reduce_frontier(
    RawInputEvent::BeginDelivery({ token: 1, source: "xx" }),
  )
  coordinator.reduce_frontier(
    RawInputEvent::CaptureDeferredBeforeInput({
      base_source: "xx",
      input_type: "insertText",
      selection: @dom_boundary.TextSelection(1, 1, @dom_boundary.NoDirection),
    }),
  )
  assert_true(
    coordinator.defer_native_input(
      "xxx",
      @dom_boundary.TextSelection(2, 2, @dom_boundary.NoDirection),
    ),
  )
  assert_true(
    coordinator.begin_native_composition(
      context.model,
      "xxx",
      @dom_boundary.TextSelection(2, 2, @dom_boundary.NoDirection),
    ),
  )
  assert_true(
    coordinator.update_composition(
      "xxyx",
      @dom_boundary.TextSelection(3, 3, @dom_boundary.NoDirection),
    ),
  )

  guard coordinator.frontier.val.deferred_composition is Some(composition) else {
    fail("composition must replace the ordinary deferred frontier")
  }
  assert_true(coordinator.frontier.val.deferred is None)
  assert_eq(composition.before_input_selection.start(), 1)
  assert_eq(composition.before_input_selection.end(), 1)
  guard rebase_deferred_raw_input(context.model, composition)
    is Some(before_input) else {
    fail("deferred composition must rebase from the ordinary input selection")
  }
  let candidate = RawNativeInputCandidate::authorized(
    before_input~,
    source=composition.source,
    post_input_selection=composition.post_input_selection,
  )
  guard normalize_raw_input_candidate(context.model, candidate) is Some(request) else {
    fail("rebased deferred composition must normalize")
  }
  assert_eq(request.selection.selection.anchor(), 1)
  assert_eq(request.selection.selection.head(), 1)
  assert_eq(request.inserted, "xy")
}

///|
test "Raw coordinator clears a canceled deferred capture before rebase" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "coordinator-deferred-cancel", "startX",
  )
  let coordinator = RawInputCoordinator::RawInputCoordinator(None)
  coordinator.reduce_frontier(
    RawInputEvent::BeginDelivery({ token: 1, source: "startX" }),
  )
  coordinator.reduce_frontier(
    RawInputEvent::CaptureDeferredBeforeInput({
      base_source: "startX",
      input_type: "insertText",
      selection: @dom_boundary.TextSelection(6, 6, @dom_boundary.NoDirection),
    }),
  )
  coordinator.reduce_frontier(
    RawInputEvent::StoreDeferred({
      base_source: "startX",
      input_type: "insertText",
      before_input_selection: @dom_boundary.TextSelection(
        6,
        6,
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
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  ignore(coordinator.enqueue_deferred(context.model, emit))
  assert_true(coordinator.frontier.val.deferred_before_input is None)
  guard coordinator.frontier.val.pending is Some(pending) else {
    fail("deferred input must become pending after rebase")
  }
  assert_eq(pending.source, "startXY")
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
  guard coordinator.frontier.val.pending is Some(pending) else {
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
  assert_true(coordinator.frontier.val.pending is None)

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
  assert_true(coordinator.frontier.val.pending is None)
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
  assert_true(coordinator.frontier.val.pending is None)
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
  assert_true(coordinator.frontier.val.pending is None)
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

  assert_true(coordinator.frontier.val.composition is None)
  assert_true(coordinator.frontier.val.pending is None)
  assert_true(test_in_flight_token(coordinator) is None)
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
  guard coordinator.frontier.val.pending is Some(pending) else {
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
  guard coordinator.take_pending_delivery() is Some((0, _)) else {
    fail("pending input must become active before cancellation")
  }
  coordinator.cancel_pending()
  coordinator.expire_before_input(expiry_generation)
  assert_true(coordinator.unmatched_before_input.val is None)
  assert_true(coordinator.frontier.val.pending is None)
  assert_true(test_in_flight_token(coordinator) is None)
  assert_true(test_in_flight_source(coordinator) is None)
  assert_false(coordinator.scheduled.val)
}
