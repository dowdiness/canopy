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
/// Coalesce native textarea events into one delayed, tokenized Raw transaction.
/// Custom-driver RawInput events bypass this coordinator and remain token-less.
priv struct RawInputCoordinator {
  unmatched_before_input : @ref.Ref[RawBeforeInputCandidate?]
  pending_before_input : @ref.Ref[RawBeforeInputCandidate?]
  pending_source : @ref.Ref[String?]
  pending_selection : @ref.Ref[@dom_boundary.TextSelection?]
  pending_count : @ref.Ref[Int]
  scheduled : @ref.Ref[Bool]
  schedule_generation : @ref.Ref[Int]
  capture_generation : @ref.Ref[Int]
  next_token : @ref.Ref[Int]
  in_flight_token : @ref.Ref[Int?]
  in_flight_source : @ref.Ref[String?]
  suppress_unmatched_repair : @ref.Ref[Bool]
  telemetry : RawInputTelemetry?
}

///|
fn RawInputCoordinator::RawInputCoordinator(
  telemetry : RawInputTelemetry?,
) -> RawInputCoordinator {
  {
    unmatched_before_input: @ref.Ref(None),
    pending_before_input: @ref.Ref(None),
    pending_source: @ref.Ref(None),
    pending_selection: @ref.Ref(None),
    pending_count: @ref.Ref(0),
    scheduled: @ref.Ref(false),
    schedule_generation: @ref.Ref(0),
    capture_generation: @ref.Ref(0),
    next_token: @ref.Ref(0),
    in_flight_token: @ref.Ref(None),
    in_flight_source: @ref.Ref(None),
    suppress_unmatched_repair: @ref.Ref(false),
    telemetry,
  }
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
  match self.pending_source.val {
    Some(source) => source
    None =>
      match self.in_flight_source.val {
        Some(source) => source
        None => committed_source
      }
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
  }
}

///|
/// Capture beforeinput while the DOM still exposes the pre-edit selection.
fn RawInputCoordinator::capture_native_before_input(
  self : RawInputCoordinator,
  model : DriverModel,
  event : @dom.InputEvent,
) -> @cmd.Cmd {
  if raw_input_event_is_composing(event) {
    self.cancel_pending()
    return @rabbita_runtime.none
  }
  match self.pending_before_input.val {
    Some(first) => return self.capture_before_input(first)
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
fn RawInputCoordinator::flush(
  self : RawInputCoordinator,
  scheduler : &@cmd.Scheduler,
  emit : @cmd.Emit[DriverEvent],
) -> Unit {
  self.scheduled.val = false
  match
    (
      self.pending_before_input.val,
      self.pending_source.val,
      self.pending_selection.val,
    ) {
    (Some(before_input), Some(source), Some(post_input_selection)) => {
      self.pending_before_input.val = None
      self.pending_source.val = None
      self.pending_selection.val = None
      let input_count = self.pending_count.val
      self.pending_count.val = 0
      let token = self.next_token.val
      self.next_token.val = token + 1
      self.in_flight_token.val = Some(token)
      self.in_flight_source.val = Some(source)
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
            token,
            input_count,
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
      scheduler.add(
        emit(
          Editing(
            RawNativeInput(
              token~,
              candidate=RawNativeInputCandidate::RawNativeInputCandidate(
                before_input~,
                source~,
                post_input_selection~,
              ),
            ),
          ),
        ),
      )
    }
    _ => self.cancel_pending()
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
  self.cancel_pending()
  self.suppress_unmatched_repair.val = true
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
fn RawInputCoordinator::enqueue(
  self : RawInputCoordinator,
  source : String,
  post_input_selection : @dom_boundary.TextSelection,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  self.capture_generation.val += 1
  let before_input = match self.unmatched_before_input.val {
    Some(before_input) => before_input
    None => {
      self.cancel_pending()
      return @rabbita_runtime.none
    }
  }
  self.unmatched_before_input.val = None
  guard !before_input.is_composing else {
    self.cancel_pending()
    return @rabbita_runtime.none
  }
  match self.pending_before_input.val {
    Some(first) if first.selection.document_id !=
      before_input.selection.document_id ||
      first.selection.version != before_input.selection.version => {
      self.cancel_pending()
      return @rabbita_runtime.none
    }
    None => self.pending_before_input.val = Some(before_input)
    Some(_) => ()
  }
  if self.pending_count.val == 0 {
    match self.telemetry {
      Some(telemetry) =>
        telemetry.pending_input_received_at.val = Some(raw_input_now_ms())
      None => ()
    }
  }
  self.pending_count.val += 1
  self.pending_source.val = Some(raw_textarea_value(source))
  self.pending_selection.val = Some(post_input_selection)
  self.schedule(emit)
}

///|
/// Finish a normalized native transaction after its resulting render. The
/// phase remains available for the outer publish and is copied to last_phase.
fn RawInputCoordinator::finish(
  self : RawInputCoordinator,
  token : Int,
  latest_model : @ref.Ref[DriverModel?],
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  guard self.in_flight_token.val == Some(token) else {
    return @rabbita_runtime.none
  }
  self.in_flight_token.val = None
  self.in_flight_source.val = None
  after_render(
    scheduler => {
      ignore(scheduler)
      self.mark_rendered(token)
      match latest_model.val {
        Some(model) => publish(model, Some(self), None)
        None => ()
      }
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
  if self.in_flight_token.val == Some(token) {
    self.in_flight_token.val = None
    self.in_flight_source.val = None
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
  self.pending_before_input.val = None
  self.pending_source.val = None
  self.pending_selection.val = None
  self.pending_count.val = 0
  match self.telemetry {
    Some(telemetry) => {
      telemetry.pending_input_received_at.val = None
      telemetry.phase.val = None
    }
    None => ()
  }
  self.in_flight_token.val = None
  self.in_flight_source.val = None
  self.suppress_unmatched_repair.val = false
}

///|
fn RawInputCoordinator::is_active(
  self : RawInputCoordinator,
  token : Int,
) -> Bool {
  self.in_flight_token.val == Some(token)
}

///|
fn RawInputCoordinator::cancel(self : RawInputCoordinator, token : Int) -> Unit {
  if self.in_flight_token.val == Some(token) {
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
