///|
/// Browser-clock timestamps for one deferred Raw transaction.
///
/// This is deliberately private to the driver: the measurements diagnose the
/// imperative shell without becoming part of the editor or application API.
priv struct RawInputPhaseTiming {
  token : Int
  input_count : Int
  input_received_at : Double
  debounce_fired_at : Double
  reducer_started_at : Double?
  reducer_finished_at : Double?
  editor_started_at : Double?
  editor_finished_at : Double?
  preview_started_at : Double?
  preview_finished_at : Double?
  publish_started_at : Double?
  publish_finished_at : Double?
  rendered_at : Double?
}

///|
/// Optional capability that enables Raw phase measurements for the private
/// development host without putting timing state on the standalone path.
priv struct RawInputTelemetry {
  pending_input_received_at : @ref.Ref[Double?]
  phase : @ref.Ref[RawInputPhaseTiming?]
  last_phase : @ref.Ref[RawInputPhaseTiming?]
}

///|
fn RawInputTelemetry::new() -> RawInputTelemetry {
  {
    pending_input_received_at: @ref.Ref(None),
    phase: @ref.Ref(None),
    last_phase: @ref.Ref(None),
  }
}

///|
/// Read the monotonic browser clock used by the phase probe.
fn raw_input_now_ms() -> Double {
  @dom.Window::get_performance(@dom.window()).now()
}

///|
fn raw_input_phase_duration(start : Double?, end : Double?) -> Json {
  match (start, end) {
    (Some(start), Some(end)) => (end - start).to_json()
    _ => Json::null()
  }
}

///|
/// Serialize durations rather than absolute timestamps so the dev-host
/// snapshot remains useful across browser contexts.
fn RawInputPhaseTiming::to_json(self : RawInputPhaseTiming) -> Json {
  Json::object({
    "token": self.token.to_json(),
    "input_count": self.input_count.to_json(),
    "input_to_debounce_ms": raw_input_phase_duration(
      Some(self.input_received_at),
      Some(self.debounce_fired_at),
    ),
    "debounce_to_reduce_ms": raw_input_phase_duration(
      Some(self.debounce_fired_at),
      self.reducer_started_at,
    ),
    "reduce_ms": raw_input_phase_duration(
      self.reducer_started_at,
      self.reducer_finished_at,
    ),
    "reduce_to_commit_ms": raw_input_phase_duration(
      self.reducer_finished_at,
      self.editor_started_at,
    ),
    "commit_ms": raw_input_phase_duration(
      self.editor_started_at,
      self.editor_finished_at,
    ),
    "preview_update_ms": raw_input_phase_duration(
      self.preview_started_at,
      self.preview_finished_at,
    ),
    "commit_to_publish_ms": raw_input_phase_duration(
      self.editor_finished_at,
      self.publish_started_at,
    ),
    "publish_ms": raw_input_phase_duration(
      self.publish_started_at,
      self.publish_finished_at,
    ),
    "publish_to_render_ms": raw_input_phase_duration(
      self.publish_finished_at,
      self.rendered_at,
    ),
    "input_to_render_ms": raw_input_phase_duration(
      Some(self.input_received_at),
      self.rendered_at,
    ),
  })
}
