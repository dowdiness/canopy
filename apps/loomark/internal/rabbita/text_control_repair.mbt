///|
/// Map one live offset from a rejected contiguous edit back into the accepted
/// text's UTF-16 coordinates.
fn rejected_text_offset(
  accepted_source : String,
  rejected_source : String,
  offset : Int,
) -> Int {
  let change = @text_change.compute_text_change(
    accepted_source, rejected_source,
  )
  let inserted_len = change.inserted.length()
  let inserted_end = change.start + inserted_len
  let mapped = if offset <= change.start {
    offset
  } else if offset >= inserted_end {
    offset - inserted_len + change.delete_len
  } else {
    change.start
  }
  mapped.clamp(min=0, max=accepted_source.length())
}

///|
/// Map a live selection from one rejected contiguous edit back into the
/// accepted source's UTF-16 coordinates.
fn rejected_text_selection(
  accepted_source : String,
  rejected_source : String,
  selection : @dom_boundary.TextSelection,
) -> @dom_boundary.TextSelection {
  let accepted_value = raw_textarea_value(accepted_source)
  let start = rejected_text_offset(
    accepted_value,
    rejected_source,
    selection.start(),
  )
  let end = rejected_text_offset(
    accepted_value,
    rejected_source,
    selection.end(),
  ).clamp(min=start, max=accepted_value.length())
  @dom_boundary.TextSelection(start, end, selection.direction())
}

///|
/// The delay groups rapid native input events into one editor transaction.
const RAW_INPUT_DEBOUNCE_MS : Int = 50

///|
/// One complete pending batch. Keeping its base, latest browser state, and
/// count together prevents partially populated coordinator states.
priv struct PendingRawInput {
  before_input : RawBeforeInputCandidate
  source : String
  post_input_selection : @dom_boundary.TextSelection
  input_count : Int
}

///|
/// Coalesce native textarea events into one delayed, tokenized Raw transaction.
/// Custom-driver RawInput events bypass this coordinator and remain token-less.
priv struct RawInputCoordinator {
  frontier : @ref.Ref[RawInputState]
  unmatched_before_input : @ref.Ref[RawBeforeInputCandidate?]
  scheduled : @ref.Ref[Bool]
  schedule_generation : @ref.Ref[Int]
  capture_generation : @ref.Ref[Int]
  next_token : @ref.Ref[Int]
  suppress_unmatched_repair : @ref.Ref[Bool]
  composition_final_source : @ref.Ref[String?]
  render_barrier_armed : @ref.Ref[Bool]
  render_barrier_waiting : @ref.Ref[Bool]
  render_barrier_token : @ref.Ref[Int?]
  render_barrier_latest_model : @ref.Ref[@ref.Ref[DriverModel?]?]
  render_barrier_emit : @ref.Ref[@cmd.Emit[DriverEvent]?]
  telemetry : RawInputTelemetry?
}

///|
fn RawInputCoordinator::RawInputCoordinator(
  telemetry : RawInputTelemetry?,
) -> RawInputCoordinator {
  {
    frontier: @ref.Ref(RawInputState::initial()),
    unmatched_before_input: @ref.Ref(None),
    scheduled: @ref.Ref(false),
    schedule_generation: @ref.Ref(0),
    capture_generation: @ref.Ref(0),
    next_token: @ref.Ref(0),
    suppress_unmatched_repair: @ref.Ref(false),
    composition_final_source: @ref.Ref(None),
    render_barrier_armed: @ref.Ref(false),
    render_barrier_waiting: @ref.Ref(false),
    render_barrier_token: @ref.Ref(None),
    render_barrier_latest_model: @ref.Ref(None),
    render_barrier_emit: @ref.Ref(None),
    telemetry,
  }
}

///|
fn RawInputCoordinator::reduce_frontier_with_decision(
  self : RawInputCoordinator,
  event : RawInputEvent,
) -> RawInputDecision {
  let (state, decision) = reduce_raw_input(self.frontier.val, event)
  self.frontier.val = state
  decision
}

///|
fn RawInputCoordinator::reduce_frontier(
  self : RawInputCoordinator,
  event : RawInputEvent,
) -> Unit {
  ignore(self.reduce_frontier_with_decision(event))
}

///|
/// Apply one phase update only while its deferred transaction is still the
/// current measurement. Stale callbacks must not mutate a newer transaction.
fn RawInputCoordinator::update_phase(
  self : RawInputCoordinator,
  token : Int,
  update : (RawInputPhaseTiming) -> RawInputPhaseTiming,
) -> Unit {
  match self.telemetry {
    Some(telemetry) =>
      match telemetry.phase.val {
        Some(phase) if phase.token == token =>
          telemetry.phase.val = Some(update(phase))
        _ => ()
      }
    None => ()
  }
}

///|
fn RawInputCoordinator::mark_reducer_started(
  self : RawInputCoordinator,
  token : Int,
) -> Unit {
  self.update_phase(token, phase => {
    ..phase,
    reducer_started_at: Some(raw_input_now_ms()),
  })
}

///|
fn RawInputCoordinator::mark_reducer_finished(
  self : RawInputCoordinator,
  token : Int,
) -> Unit {
  self.update_phase(token, phase => {
    ..phase,
    reducer_finished_at: Some(raw_input_now_ms()),
  })
}

///|
fn RawInputCoordinator::mark_editor_started(
  self : RawInputCoordinator,
  token : Int,
) -> Unit {
  self.update_phase(token, phase => {
    ..phase,
    editor_started_at: Some(raw_input_now_ms()),
  })
}

///|
fn RawInputCoordinator::mark_editor_finished(
  self : RawInputCoordinator,
  token : Int,
) -> Unit {
  self.update_phase(token, phase => {
    ..phase,
    editor_finished_at: Some(raw_input_now_ms()),
  })
}

///|
fn RawInputCoordinator::mark_preview_started(
  self : RawInputCoordinator,
  token : Int,
) -> Unit {
  self.update_phase(token, phase => {
    ..phase,
    preview_started_at: Some(raw_input_now_ms()),
  })
}

///|
fn RawInputCoordinator::mark_preview_finished(
  self : RawInputCoordinator,
  token : Int,
) -> Unit {
  self.update_phase(token, phase => {
    ..phase,
    preview_finished_at: Some(raw_input_now_ms()),
  })
}

///|
fn RawInputCoordinator::mark_publish_started(
  self : RawInputCoordinator,
  token : Int,
) -> Unit {
  self.update_phase(token, phase => {
    ..phase,
    publish_started_at: Some(raw_input_now_ms()),
  })
}

///|
fn RawInputCoordinator::mark_publish_finished(
  self : RawInputCoordinator,
  token : Int,
) -> Unit {
  self.update_phase(token, phase => {
    ..phase,
    publish_finished_at: Some(raw_input_now_ms()),
  })
}

///|
fn RawInputCoordinator::mark_rendered(
  self : RawInputCoordinator,
  token : Int,
) -> Unit {
  self.update_phase(token, phase => {
    ..phase,
    rendered_at: Some(raw_input_now_ms()),
  })
  match self.telemetry {
    Some(telemetry) =>
      match telemetry.phase.val {
        Some(phase) if phase.token == token =>
          telemetry.last_phase.val = Some(phase)
        _ => ()
      }
    None => ()
  }
}

///|
/// Expose only the latest phase with a completed publish. A pending input or
/// canceled transaction must not hide the last useful measurement.
fn RawInputCoordinator::phase_json(self : RawInputCoordinator) -> Json? {
  match self.telemetry {
    Some(telemetry) => {
      let phase = match telemetry.phase.val {
        Some(phase) if phase.publish_finished_at is Some(_) => Some(phase)
        _ => telemetry.last_phase.val
      }
      match phase {
        Some(phase) => Some(phase.to_json())
        None => None
      }
    }
    None => None
  }
}

///|
fn RawInputCoordinator::epoch(self : RawInputCoordinator) -> Int {
  self.capture_generation.val
}

///|
fn RawInputCoordinator::display_source(
  self : RawInputCoordinator,
  committed_source : String,
) -> String {
  match self.frontier.val.composition {
    Some(input) => input.source
    None =>
      match self.frontier.val.pending {
        Some(pending) => pending.source
        None =>
          match self.frontier.val.deferred_composition {
            Some(composition) => composition.source
            None =>
              match self.frontier.val.deferred {
                Some(deferred) => deferred.source
                None =>
                  match self.frontier.val.in_flight {
                    Some(delivery) => delivery.source
                    None => committed_source
                  }
              }
          }
      }
  }
}

///|
/// Begin browser ownership from the exact accepted Raw selection. A pending
/// ordinary batch keeps its earlier beforeinput base and becomes part of the
/// final composition transaction.
fn RawInputCoordinator::begin_composition(
  self : RawInputCoordinator,
  before_input : RawBeforeInputCandidate,
  source : String,
  selection : @dom_boundary.TextSelection,
) -> Bool {
  guard !self.has_active_delivery() &&
    self.frontier.val.deferred_before_input is None &&
    self.frontier.val.deferred is None &&
    self.frontier.val.deferred_composition is None else {
    return false
  }
  let input = match self.frontier.val.pending {
    Some(pending) if pending.before_input.selection.document_id ==
      before_input.selection.document_id &&
      pending.before_input.selection.version == before_input.selection.version =>
      { ..pending, post_input_selection: selection }
    _ =>
      {
        before_input,
        source: raw_textarea_value(source),
        post_input_selection: selection,
        input_count: 0,
      }
  }
  self.schedule_generation.val += 1
  self.capture_generation.val += 1
  self.scheduled.val = false
  self.unmatched_before_input.val = None
  self.suppress_unmatched_repair.val = false
  self.reduce_frontier(RawInputEvent::BeginComposition(input))
  self.composition_final_source.val = None
  true
}

///|
/// Keep the latest browser-owned text and caret without exposing it as a
/// committable pending Raw input.
fn RawInputCoordinator::begin_native_composition(
  self : RawInputCoordinator,
  model : DriverModel,
  source : String,
  selection : @dom_boundary.TextSelection,
) -> Bool {
  if self.has_active_delivery() {
    let frontier = self.frontier.val
    let (base_source, frontier_source, before_input_selection) = match
      frontier.deferred {
      Some(deferred) =>
        (deferred.base_source, deferred.source, deferred.before_input_selection)
      None =>
        match frontier.in_flight {
          Some(delivery) => (delivery.source, delivery.source, selection)
          None => (model.document.source(), model.document.source(), selection)
        }
    }
    self.reduce_frontier(
      RawInputEvent::BeginDeferredComposition({
        base_source,
        input_type: "insertCompositionText",
        before_input_selection,
        source: raw_textarea_value(frontier_source),
        post_input_selection: selection,
        input_count: 0,
      }),
    )
    return true
  }
  let before_input = match self.frontier.val.pending {
    Some(pending) if pending.before_input.selection.document_id ==
      model.document_id &&
      pending.before_input.selection.version == model.document_version =>
      pending.before_input
    _ => {
      let versioned = versioned_raw_selection_from_dom(model, selection) catch {
        _ => return false
      }
      RawBeforeInputCandidate::RawBeforeInputCandidate(
        selection=versioned,
        input_type="insertCompositionText",
        is_composing=false,
      )
    }
  }
  self.begin_composition(before_input, source, selection)
}

///|
fn RawInputCoordinator::update_composition(
  self : RawInputCoordinator,
  source : String,
  selection : @dom_boundary.TextSelection,
) -> Bool {
  match self.frontier.val.composition {
    Some(input) => {
      self.reduce_frontier(
        RawInputEvent::UpdateComposition({
          ..input,
          source: raw_textarea_value(source),
          post_input_selection: selection,
          input_count: input.input_count + 1,
        }),
      )
      true
    }
    None =>
      match self.frontier.val.deferred_composition {
        Some(input) => {
          self.reduce_frontier(
            RawInputEvent::UpdateDeferredComposition({
              ..input,
              source: raw_textarea_value(source),
              post_input_selection: selection,
              input_count: input.input_count + 1,
            }),
          )
          true
        }
        None => false
      }
  }
}

///|
/// Resolve composition at its browser boundary. A net no-op never reaches the
/// editor; a changed final value becomes one immediate native transaction so a
/// following blur or mode click cannot cancel accepted IME text.
fn RawInputCoordinator::finish_composition(
  self : RawInputCoordinator,
  accepted_source : String,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  match self.frontier.val.deferred_composition {
    Some(input) => {
      if input.source == raw_textarea_value(input.base_source) {
        self.reduce_frontier(RawInputEvent::ClearDeferredComposition)
        self.reduce_frontier(RawInputEvent::ClearDeferredCompositionFinished)
      } else {
        self.reduce_frontier(RawInputEvent::MarkDeferredCompositionFinished)
      }
      return @rabbita_runtime.none
    }
    None => ()
  }
  guard self.frontier.val.composition is Some(input) else {
    return @rabbita_runtime.none
  }
  self.reduce_frontier(RawInputEvent::ClearComposition)
  if input.source == raw_textarea_value(accepted_source) {
    match self.telemetry {
      Some(telemetry) => telemetry.pending_input_received_at.val = None
      None => ()
    }
    return @rabbita_runtime.none
  }
  self.reduce_frontier(RawInputEvent::StorePending(input))
  self.composition_final_source.val = Some(input.source)
  let expiry_command = self.capture_before_input(input.before_input)
  match self.take_pending_delivery() {
    Some((token, candidate)) =>
      @cmd.batch([
        emit(Editing(RawNativeInput(token~, candidate~))),
        expiry_command,
      ])
    None => expiry_command
  }
}

///|
#cfg(target="js")
fn raw_input_event_is_composing(event : @dom.InputEvent) -> Bool {
  event.is_composing()
}

///|
#cfg(not(target="js"))
fn raw_input_event_is_composing(event : @dom.InputEvent) -> Bool {
  ignore(event)
  false
}

///|
#cfg(target="js")
fn raw_input_event_type(event : @dom.InputEvent) -> String {
  event.input_type()
}

///|
#cfg(not(target="js"))
fn raw_input_event_type(event : @dom.InputEvent) -> String {
  ignore(event)
  ""
}

///|
/// Store a candidate synchronously and expire only this unmatched capture.
fn RawInputCoordinator::capture_before_input(
  self : RawInputCoordinator,
  candidate : RawBeforeInputCandidate,
) -> @cmd.Cmd {
  self.capture_generation.val += 1
  let generation = self.capture_generation.val
  self.unmatched_before_input.val = Some(candidate)
  @cmd.delay(
    @cmd.custom_cmd(scheduler => {
      ignore(scheduler)
      self.expire_before_input(generation)
    }),
    0,
  )
}

///|
fn RawInputCoordinator::expire_before_input(
  self : RawInputCoordinator,
  generation : Int,
) -> Unit {
  if self.capture_generation.val == generation {
    self.unmatched_before_input.val = None
    self.composition_final_source.val = None
  }
}

///|
/// Keep a native input separate while the DOM is ahead of the committed model.
fn RawInputCoordinator::capture_deferred_before_input(
  self : RawInputCoordinator,
  model : DriverModel,
  event : @dom.InputEvent,
) -> @cmd.Cmd {
  let selection = match read_raw_selection() {
    Some(selection) => selection
    None => {
      self.capture_generation.val += 1
      self.reduce_frontier(RawInputEvent::ClearDeferredCapture)
      return @rabbita_runtime.none
    }
  }
  let base_source = match self.frontier.val.deferred {
    Some(deferred) => deferred.base_source
    None =>
      match self.frontier.val.in_flight {
        Some(delivery) => delivery.source
        None => model.document.source()
      }
  }
  self.capture_generation.val += 1
  self.reduce_frontier(
    RawInputEvent::CaptureDeferredBeforeInput({
      base_source,
      input_type: raw_input_event_type(event),
      selection,
    }),
  )
  @rabbita_runtime.none
}

///|
/// Capture beforeinput while the DOM still exposes the pre-edit selection.
fn RawInputCoordinator::capture_native_before_input(
  self : RawInputCoordinator,
  model : DriverModel,
  event : @dom.InputEvent,
) -> @cmd.Cmd {
  if raw_input_event_is_composing(event) {
    if self.frontier.val.composition is None &&
      self.frontier.val.deferred_composition is None &&
      !self.has_active_delivery() {
      self.cancel_pending()
    }
    return @rabbita_runtime.none
  }
  if self.frontier.val.deferred_composition is Some(_) {
    return @rabbita_runtime.none
  }
  if self.frontier.val.in_flight is Some(_) ||
    self.frontier.val.deferred is Some(_) {
    return self.capture_deferred_before_input(model, event)
  }
  match self.frontier.val.pending {
    Some(pending) => return self.capture_before_input(pending.before_input)
    None => ()
  }
  let selection = match read_raw_selection() {
    Some(selection) => selection
    None => {
      self.cancel_pending()
      return @rabbita_runtime.none
    }
  }
  let selection = versioned_raw_selection_from_dom(model, selection) catch {
    _ => {
      self.cancel_pending()
      return @rabbita_runtime.none
    }
  }
  self.capture_before_input(
    RawBeforeInputCandidate::RawBeforeInputCandidate(
      selection~,
      input_type=raw_input_event_type(event),
      is_composing=false,
    ),
  )
}

///|
fn RawInputCoordinator::schedule(
  self : RawInputCoordinator,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  self.schedule_generation.val += 1
  let generation = self.schedule_generation.val
  self.scheduled.val = true
  @cmd.delay(
    @cmd.custom_cmd(scheduler => {
      if self.schedule_generation.val == generation {
        self.flush(scheduler, emit)
      }
    }),
    RAW_INPUT_DEBOUNCE_MS,
  )
}

///|
fn read_raw_selection() -> @dom_boundary.TextSelection? {
  try @dom_boundary.read_text_selection_id("loomark-input") catch {
    _ => None
  } noraise {
    selection => Some(selection)
  }
}

///|
fn RawInputCoordinator::take_pending_delivery(
  self : RawInputCoordinator,
) -> (Int, RawNativeInputCandidate)? {
  guard self.frontier.val.in_flight is None else { return None }
  guard self.frontier.val.pending is Some(_) else { return None }
  let token = self.next_token.val
  match
    self.reduce_frontier_with_decision(
      RawInputEvent::BeginPendingDelivery(token),
    ) {
    RawInputDecision::Deliver(delivery_token, pending) => {
      self.next_token.val = token + 1
      match self.telemetry {
        Some(telemetry) => {
          let now = raw_input_now_ms()
          let input_received_at = match
            telemetry.pending_input_received_at.val {
            Some(at) => at
            None => now
          }
          telemetry.pending_input_received_at.val = None
          telemetry.phase.val = Some({
            token: delivery_token,
            input_count: pending.input_count,
            input_received_at,
            debounce_fired_at: now,
            reducer_started_at: None,
            reducer_finished_at: None,
            editor_started_at: None,
            editor_finished_at: None,
            preview_started_at: None,
            preview_finished_at: None,
            publish_started_at: None,
            publish_finished_at: None,
            rendered_at: None,
          })
        }
        None => ()
      }
      Some(
        (
          delivery_token,
          RawNativeInputCandidate::authorized(
            before_input=pending.before_input,
            source=pending.source,
            post_input_selection=pending.post_input_selection,
          ),
        ),
      )
    }
    RawInputDecision::Noop | RawInputDecision::StoredPending => None
  }
}

///|
/// A debounce callback may race an active delivery. Preserve the existing
/// shell policy: a blocked pending callback cancels the pending transaction;
/// browser input that must survive the race is captured through the deferred
/// frontier and rebased after render.
fn RawInputCoordinator::flush(
  self : RawInputCoordinator,
  scheduler : &@cmd.Scheduler,
  emit : @cmd.Emit[DriverEvent],
) -> Unit {
  self.scheduled.val = false
  match self.take_pending_delivery() {
    Some((token, candidate)) =>
      scheduler.add(emit(Editing(RawNativeInput(token~, candidate~))))
    None => self.cancel_pending()
  }
}

///|
fn RawInputCoordinator::has_captured_before_input(
  self : RawInputCoordinator,
) -> Bool {
  self.unmatched_before_input.val is Some(_)
}

///|
fn RawInputCoordinator::suppress_composing_input_repair(
  self : RawInputCoordinator,
) -> Unit {
  if self.frontier.val.composition is None &&
    self.frontier.val.deferred_composition is None {
    if !self.has_active_delivery() {
      self.cancel_pending()
    }
    self.suppress_unmatched_repair.val = true
  }
}

///|
fn RawInputCoordinator::take_unmatched_input_repair(
  self : RawInputCoordinator,
) -> Bool {
  let repair = !self.suppress_unmatched_repair.val
  self.suppress_unmatched_repair.val = false
  repair
}

///|
/// Store the latest native value without attempting to interpret it against a
/// committed document that is older than the value visible in the textarea.
fn RawInputCoordinator::defer_native_input(
  self : RawInputCoordinator,
  source : String,
  post_input_selection : @dom_boundary.TextSelection,
) -> Bool {
  let frontier = self.frontier.val
  let capture = match frontier.deferred_before_input {
    Some(capture) => capture
    None => return false
  }
  let existing = frontier.deferred
  let (base_source, input_type, before_input_selection, input_count) = match
    existing {
    Some(deferred) =>
      (
        deferred.base_source,
        deferred.input_type,
        deferred.before_input_selection,
        deferred.input_count + 1,
      )
    None => (capture.base_source, capture.input_type, capture.selection, 1)
  }
  self.capture_generation.val += 1
  self.unmatched_before_input.val = None
  let source = raw_textarea_value(source)
  self.reduce_frontier(
    RawInputEvent::StoreDeferred({
      base_source,
      input_type,
      before_input_selection,
      source,
      post_input_selection,
      input_count,
    }),
  )
  true
}

///|
fn RawInputCoordinator::enqueue(
  self : RawInputCoordinator,
  source : String,
  post_input_selection : @dom_boundary.TextSelection,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  self.capture_generation.val += 1
  let source = raw_textarea_value(source)
  match self.composition_final_source.val {
    Some(final_source) => {
      self.composition_final_source.val = None
      if final_source == source {
        self.unmatched_before_input.val = None
        return @rabbita_runtime.none
      }
    }
    None => ()
  }
  let before_input = match self.unmatched_before_input.val {
    Some(before_input) => before_input
    None => {
      if self.has_active_delivery() {
        return @rabbita_runtime.none
      }
      self.cancel_pending()
      return @rabbita_runtime.none
    }
  }
  self.unmatched_before_input.val = None
  guard !before_input.is_composing else {
    self.cancel_pending()
    return @rabbita_runtime.none
  }
  let pending = match self.frontier.val.pending {
    Some(pending) if pending.before_input.selection.document_id !=
      before_input.selection.document_id ||
      pending.before_input.selection.version != before_input.selection.version => {
      self.cancel_pending()
      return @rabbita_runtime.none
    }
    Some(pending) =>
      {
        ..pending,
        source,
        post_input_selection,
        input_count: pending.input_count + 1,
      }
    None => {
      match self.telemetry {
        Some(telemetry) =>
          telemetry.pending_input_received_at.val = Some(raw_input_now_ms())
        None => ()
      }
      { before_input, source, post_input_selection, input_count: 1 }
    }
  }
  match
    self.reduce_frontier_with_decision(RawInputEvent::StorePending(pending)) {
    RawInputDecision::StoredPending => self.schedule(emit)
    RawInputDecision::Noop | RawInputDecision::Deliver(_, _) =>
      @rabbita_runtime.none
  }
}

///|
/// Rebase the latest native value after the preceding transaction has rendered.
fn RawInputCoordinator::enqueue_deferred(
  self : RawInputCoordinator,
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  let deferred = match self.frontier.val.deferred {
    Some(deferred) => deferred
    None => return @rabbita_runtime.none
  }
  self.reduce_frontier(RawInputEvent::ClearDeferred)
  guard raw_textarea_value(model.document.source()) ==
    raw_textarea_value(deferred.base_source) else {
    return @rabbita_runtime.none
  }
  let before_input = match rebase_deferred_raw_input(model, deferred) {
    Some(before_input) => before_input
    None => return @rabbita_runtime.none
  }
  self.capture_generation.val += 1
  self.unmatched_before_input.val = Some(before_input)
  let command = self.enqueue(
    deferred.source,
    deferred.post_input_selection,
    emit,
  )
  match self.frontier.val.pending {
    Some(pending) =>
      self.reduce_frontier(
        RawInputEvent::StorePending({
          ..pending,
          input_count: deferred.input_count,
        }),
      )
    None => ()
  }
  command
}

///|
fn RawInputCoordinator::enqueue_deferred_composition(
  self : RawInputCoordinator,
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  let deferred = match self.frontier.val.deferred_composition {
    Some(deferred) => deferred
    None => {
      self.reduce_frontier(RawInputEvent::ClearDeferredCompositionFinished)
      return @rabbita_runtime.none
    }
  }
  self.reduce_frontier(RawInputEvent::ClearDeferredComposition)
  guard raw_textarea_value(model.document.source()) ==
    raw_textarea_value(deferred.base_source) else {
    self.reduce_frontier(RawInputEvent::ClearDeferredCompositionFinished)
    return @rabbita_runtime.none
  }
  let before_input = match rebase_deferred_raw_input(model, deferred) {
    Some(before_input) => before_input
    None => {
      self.reduce_frontier(RawInputEvent::ClearDeferredCompositionFinished)
      return @rabbita_runtime.none
    }
  }
  self.capture_generation.val += 1
  self.unmatched_before_input.val = None
  self.reduce_frontier(
    RawInputEvent::StorePending({
      before_input,
      source: deferred.source,
      post_input_selection: deferred.post_input_selection,
      input_count: deferred.input_count,
    }),
  )
  match self.take_pending_delivery() {
    Some((token, candidate)) =>
      emit(Editing(RawNativeInput(token~, candidate~)))
    None => @rabbita_runtime.none
  }
}

///|
fn RawInputCoordinator::finalize_deferred_composition(
  self : RawInputCoordinator,
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  guard self.frontier.val.deferred_composition_finished else {
    return @rabbita_runtime.none
  }
  guard !self.has_active_delivery() else { return @rabbita_runtime.none }
  self.enqueue_deferred_composition(model, emit)
}

///|
fn RawInputCoordinator::discard_deferred(self : RawInputCoordinator) -> Unit {
  self.reduce_frontier(RawInputEvent::ClearDeferred)
  self.reduce_frontier(RawInputEvent::ClearDeferredComposition)
  self.reduce_frontier(RawInputEvent::ClearDeferredCompositionFinished)
}

///|
fn RawInputCoordinator::arm_render_barrier(self : RawInputCoordinator) -> Unit {
  self.render_barrier_armed.val = true
  self.render_barrier_waiting.val = false
  self.render_barrier_token.val = None
  self.render_barrier_latest_model.val = None
  self.render_barrier_emit.val = None
}

///|
fn RawInputCoordinator::render_barrier_armed(
  self : RawInputCoordinator,
) -> Bool {
  self.render_barrier_armed.val
}

///|
fn RawInputCoordinator::render_barrier_waiting(
  self : RawInputCoordinator,
) -> Bool {
  self.render_barrier_waiting.val
}

///|
fn RawInputCoordinator::release_render_barrier(
  self : RawInputCoordinator,
) -> @cmd.Cmd {
  self.render_barrier_armed.val = false
  guard self.render_barrier_waiting.val else { return @rabbita_runtime.none }
  self.render_barrier_waiting.val = false
  let token = self.render_barrier_token.val
  let latest_model = self.render_barrier_latest_model.val
  let emit = self.render_barrier_emit.val
  self.render_barrier_token.val = None
  self.render_barrier_latest_model.val = None
  self.render_barrier_emit.val = None
  match (token, latest_model, emit) {
    (Some(token), Some(latest_model), Some(emit)) =>
      @cmd.custom_cmd(scheduler => {
        self.complete_after_render(token, latest_model, emit, scheduler)
      })
    _ => @rabbita_runtime.none
  }
}

///|
fn RawInputCoordinator::complete_after_render(
  self : RawInputCoordinator,
  token : Int,
  latest_model : @ref.Ref[DriverModel?],
  emit : @cmd.Emit[DriverEvent],
  scheduler : &@cmd.Scheduler,
) -> Unit {
  guard self.is_active(token) else { return }
  self.render_barrier_waiting.val = false
  self.render_barrier_token.val = None
  self.render_barrier_latest_model.val = None
  self.render_barrier_emit.val = None
  self.mark_rendered(token)
  let has_deferred = self.frontier.val.deferred is Some(_)
  let has_deferred_composition = self.frontier.val.deferred_composition
    is Some(_) &&
    self.frontier.val.deferred_composition_finished
  self.reduce_frontier(RawInputEvent::ClearDeferredCapture)
  match latest_model.val {
    Some(model) => {
      publish(model, Some(self), None)
      self.reduce_frontier(RawInputEvent::FinishDelivery(token))
      if has_deferred_composition {
        scheduler.add(self.enqueue_deferred_composition(model, emit))
      } else if has_deferred {
        scheduler.add(self.enqueue_deferred(model, emit))
      }
    }
    None => {
      self.discard_deferred()
      self.reduce_frontier(RawInputEvent::ClearDeferredComposition)
      self.reduce_frontier(RawInputEvent::FinishDelivery(token))
    }
  }
}

///|
/// Finish a normalized native transaction after its resulting render. Keep the
/// token and source active until AfterRender so a native input that arrives
/// before the controlled DOM repaint can be deferred against this frontier.
fn RawInputCoordinator::finish(
  self : RawInputCoordinator,
  token : Int,
  latest_model : @ref.Ref[DriverModel?],
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  guard self.is_active(token) else { return @rabbita_runtime.none }
  after_render(
    scheduler => {
      guard self.is_active(token) else { return }
      if self.render_barrier_armed.val {
        self.render_barrier_waiting.val = true
        self.render_barrier_token.val = Some(token)
        self.render_barrier_latest_model.val = Some(latest_model)
        self.render_barrier_emit.val = Some(emit)
        match latest_model.val {
          Some(model) => publish(model, Some(self), None)
          None => ()
        }
        return
      }
      self.complete_after_render(token, latest_model, emit, scheduler)
    },
    emit,
  )
}

///|
/// Discard a native transaction that could not be normalized or was canceled.
fn RawInputCoordinator::discard(
  self : RawInputCoordinator,
  token : Int,
) -> Unit {
  if self.is_active(token) {
    self.reduce_frontier(RawInputEvent::DiscardDelivery(token))
    self.render_barrier_armed.val = false
    self.render_barrier_waiting.val = false
    self.render_barrier_token.val = None
    self.render_barrier_latest_model.val = None
    self.render_barrier_emit.val = None
    match self.telemetry {
      Some(telemetry) => telemetry.phase.val = None
      None => ()
    }
  }
}

///|
/// Drop native input that is superseded by an external canonical-source
/// operation. Generations invalidate already-created timers and captures.
fn RawInputCoordinator::cancel_pending(self : RawInputCoordinator) -> Unit {
  self.schedule_generation.val += 1
  self.capture_generation.val += 1
  self.scheduled.val = false
  self.unmatched_before_input.val = None
  match self.telemetry {
    Some(telemetry) => {
      telemetry.pending_input_received_at.val = None
      telemetry.phase.val = None
    }
    None => ()
  }
  self.reduce_frontier(RawInputEvent::Cancel)
  self.suppress_unmatched_repair.val = false
  self.composition_final_source.val = None
  self.render_barrier_armed.val = false
  self.render_barrier_waiting.val = false
  self.render_barrier_token.val = None
  self.render_barrier_latest_model.val = None
  self.render_barrier_emit.val = None
}

///|
fn RawInputCoordinator::has_active_delivery(self : RawInputCoordinator) -> Bool {
  self.frontier.val.in_flight is Some(_)
}

///|
fn RawInputCoordinator::has_deferred_composition(
  self : RawInputCoordinator,
) -> Bool {
  self.frontier.val.deferred_composition is Some(_)
}

///|
/// A mode transition must not cancel an IME snapshot that is waiting behind
/// an already active native delivery.
fn RawInputCoordinator::cancel_pending_for_navigation(
  self : RawInputCoordinator,
) -> Unit {
  if self.frontier.val.deferred_composition_finished ||
    (self.has_active_delivery() && self.has_deferred_composition()) {
    return
  }
  self.cancel_pending()
}

///|
/// An accepted native caret is still current only when no newer browser
/// frontier is waiting to be committed or composing.
fn RawInputCoordinator::native_selection_frontier_is_current(
  self : RawInputCoordinator,
  committed_source : String,
) -> Bool {
  self.frontier.val.pending is None &&
  self.frontier.val.composition is None &&
  self.frontier.val.deferred_before_input is None &&
  self.frontier.val.deferred is None &&
  self.frontier.val.deferred_composition is None &&
  raw_textarea_value(self.display_source(committed_source)) ==
  raw_textarea_value(committed_source)
}

///|
fn RawInputCoordinator::is_active(
  self : RawInputCoordinator,
  token : Int,
) -> Bool {
  match self.frontier.val.in_flight {
    Some(delivery) => delivery.token == token
    None => false
  }
}

///|
fn RawInputCoordinator::cancel(self : RawInputCoordinator, token : Int) -> Unit {
  if self.is_active(token) {
    self.cancel_pending()
  }
}

///|
/// Capture the DOM text cursor before the controlled textarea is rendered again.
fn block_input_command(
  block : @markdown.MarkdownBlockSnapshot,
  input_id : String,
  text : String,
  document_id : @archive.LoomarkDocumentId,
  expected_version : @markdown.MarkdownDocumentVersion,
  coordinator : BlockInputCoordinator,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    let selection = @dom_boundary.read_text_selection_id(input_id) catch {
      _ => return
    }
    scheduler.add(
      coordinator.enqueue(
        PendingBlockInput::PendingBlockInput(
          document_id~,
          expected_version~,
          node_id=block.node_id(),
          input_id~,
          text~,
          selection~,
        ),
        emit,
      ),
    )
  })
}
