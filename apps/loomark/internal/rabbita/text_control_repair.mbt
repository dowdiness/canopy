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
  let start = rejected_text_offset(
    accepted_source,
    rejected_source,
    selection.start(),
  )
  let end = rejected_text_offset(
    accepted_source,
    rejected_source,
    selection.end(),
  ).clamp(min=start, max=accepted_source.length())
  @dom_boundary.TextSelection(start, end, selection.direction())
}

///|
/// The delay groups rapid native input events into one editor transaction.
const RAW_INPUT_DEBOUNCE_MS : Int = 50

///|
/// Keep the latest native Raw value while one deferred commit is in flight.
/// The browser can continue updating the textarea without queuing stale
/// canonical-source commits behind an expensive editor transaction.
///
/// The token and one-shot retry preserve the existing rejected-edit behavior:
/// if the transaction fails, the latest native value gets one more chance
/// instead of being lost by coalescing.
priv struct RawInputCoordinator {
  pending_source : @ref.Ref[String?]
  pending_count : @ref.Ref[Int]
  scheduled : @ref.Ref[Bool]
  schedule_generation : @ref.Ref[Int]
  retry_budget : @ref.Ref[Int]
  repair_pending : @ref.Ref[Bool]
  retry_selection : @ref.Ref[@dom_boundary.TextSelection?]
  input_epoch : @ref.Ref[Int]
  next_token : @ref.Ref[Int]
  in_flight_token : @ref.Ref[Int?]
  in_flight_count : @ref.Ref[Int?]
  telemetry : RawInputTelemetry?
}

///|
fn RawInputCoordinator::RawInputCoordinator(
  telemetry : RawInputTelemetry?,
) -> RawInputCoordinator {
  {
    pending_source: @ref.Ref(None),
    pending_count: @ref.Ref(0),
    scheduled: @ref.Ref(false),
    schedule_generation: @ref.Ref(0),
    retry_budget: @ref.Ref(0),
    repair_pending: @ref.Ref(false),
    retry_selection: @ref.Ref(None),
    input_epoch: @ref.Ref(0),
    next_token: @ref.Ref(0),
    in_flight_token: @ref.Ref(None),
    in_flight_count: @ref.Ref(None),
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
  self.input_epoch.val
}

///|
fn RawInputCoordinator::display_source(
  self : RawInputCoordinator,
  committed_source : String,
) -> String {
  match self.pending_source.val {
    Some(source) => source
    None => committed_source
  }
}

///|
fn RawInputCoordinator::schedule(
  self : RawInputCoordinator,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  guard !self.scheduled.val else { return @rabbita_runtime.none }
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
/// Move the trailing edge when a newer native value arrives.
fn RawInputCoordinator::reschedule(
  self : RawInputCoordinator,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  self.schedule_generation.val += 1
  self.scheduled.val = false
  self.schedule(emit)
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
  match self.pending_source.val {
    None => ()
    Some(source) => {
      self.pending_source.val = None
      let input_count = self.pending_count.val
      self.pending_count.val = 0
      let token = self.next_token.val
      self.next_token.val = token + 1
      match self.telemetry {
        Some(telemetry) => {
          let debounce_fired_at = raw_input_now_ms()
          let input_received_at = match
            telemetry.pending_input_received_at.val {
            Some(at) => at
            None => debounce_fired_at
          }
          telemetry.pending_input_received_at.val = None
          telemetry.phase.val = Some({
            token,
            input_count,
            input_received_at,
            debounce_fired_at,
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
      self.in_flight_token.val = Some(token)
      self.in_flight_count.val = Some(input_count)
      let selection = match self.retry_selection.val {
        Some(selection) => {
          self.retry_selection.val = None
          Some(selection)
        }
        None => read_raw_selection()
      }
      scheduler.add(emit(Editing(RawInput(source, selection, Some(token)))))
    }
  }
}

///|
fn RawInputCoordinator::enqueue(
  self : RawInputCoordinator,
  source : String,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  self.input_epoch.val += 1
  match self.telemetry {
    Some(telemetry) =>
      telemetry.pending_input_received_at.val = Some(raw_input_now_ms())
    None => ()
  }
  match self.pending_source.val {
    None => self.pending_count.val = 1
    Some(_) => self.pending_count.val += 1
  }
  self.pending_source.val = Some(source)
  self.retry_selection.val = None
  self.retry_budget.val = 1
  self.reschedule(emit)
}

///|
/// Complete a deferred transaction and retry one rejected native value.
fn RawInputCoordinator::complete(
  self : RawInputCoordinator,
  token : Int,
  source : String,
  selection : @dom_boundary.TextSelection?,
  accepted : Bool,
  repair_check : () -> Bool,
  after_render_publish : () -> Unit,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  guard self.in_flight_token.val == Some(token) else {
    return @rabbita_runtime.none
  }
  self.in_flight_token.val = None
  let input_count = self.in_flight_count.val
  self.in_flight_count.val = None
  let can_retry = match input_count {
    Some(count) => count > 1
    None => false
  }
  if accepted {
    let needs_repair = self.repair_pending.val &&
      self.pending_source.val is None
    self.retry_budget.val = 0
    self.repair_pending.val = false
    let repair_epoch = self.input_epoch.val
    let command = match self.pending_source.val {
      Some(_) => self.schedule(emit)
      None => @rabbita_runtime.none
    }
    let render_measurement = after_render(
      scheduler => {
        ignore(scheduler)
        self.mark_rendered(token)
        after_render_publish()
      },
      emit,
    )
    if needs_repair {
      @cmd.batch([
        command,
        render_measurement,
        after_render(
          scheduler => {
            ignore(scheduler)
            if self.input_epoch.val != repair_epoch || !repair_check() {
              return
            }
            @dom_boundary.write_text_value_id("loomark-input", source)
            match selection {
              Some(selection) =>
                @dom_boundary.write_text_selection_id(
                  "loomark-input", selection,
                )
              None => ()
            }
          },
          emit,
        ),
      ])
    } else {
      @cmd.batch([command, render_measurement])
    }
  } else if self.retry_budget.val > 0 && can_retry {
    self.input_epoch.val += 1
    self.retry_budget.val -= 1
    self.repair_pending.val = true
    self.retry_selection.val = selection
    if self.pending_source.val is None {
      self.pending_count.val = 1
      self.pending_source.val = Some(source)
    }
    self.schedule(emit)
  } else {
    self.pending_source.val = None
    self.repair_pending.val = false
    self.retry_selection.val = None
    @rabbita_runtime.none
  }
}

///|
/// Drop native input that is superseded by an external canonical-source
/// operation. The generation invalidates the already-created timer without
/// requiring timer cancellation support from the command layer.
fn RawInputCoordinator::cancel_pending(self : RawInputCoordinator) -> Unit {
  self.input_epoch.val += 1
  self.schedule_generation.val += 1
  self.scheduled.val = false
  self.pending_source.val = None
  self.pending_count.val = 0
  match self.telemetry {
    Some(telemetry) => {
      telemetry.pending_input_received_at.val = None
      telemetry.phase.val = None
    }
    None => ()
  }
  self.retry_budget.val = 0
  self.repair_pending.val = false
  self.retry_selection.val = None
  self.in_flight_token.val = None
  self.in_flight_count.val = None
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
    self.input_epoch.val += 1
    self.in_flight_token.val = None
    self.in_flight_count.val = None
    match self.telemetry {
      Some(telemetry) => telemetry.phase.val = None
      None => ()
    }
    self.repair_pending.val = false
    self.retry_selection.val = None
  }
}

///|
/// Defer Raw input handling and retain only the latest native value.
fn raw_input_command(
  source : String,
  coordinator : RawInputCoordinator,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  coordinator.enqueue(source, emit)
}

///|
/// Capture the DOM text cursor before the controlled textarea is rendered again.
fn block_input_command(
  block : @markdown.MarkdownBlockSnapshot,
  input_id : String,
  text : String,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    let selection = @dom_boundary.read_text_selection_id(input_id) catch {
      error => {
        scheduler.add(emit(Navigation(EffectFailed(error.message()))))
        return
      }
    }
    scheduler.add(
      emit(
        Editing(
          BlockInput(
            node_id=block.node_id(),
            input_id~,
            text~,
            selection_offset=selection.end(),
          ),
        ),
      ),
    )
  })
}
