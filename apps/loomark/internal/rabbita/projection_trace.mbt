///|
/// Application-owned Commit 1 characterization trace for current synchronous
/// Loomark projection ownership. Storage is fixed-width and bounded; disabled
/// tracing has no buffer and never calls the injected clock.
priv struct ProjectionTraceBuffer {
  sequence : FixedArray[Int]
  timestamp : FixedArray[Int]
  event_id : FixedArray[Int]
  request_id : FixedArray[Int]
  group_work_id : FixedArray[Int]
  presentation_id : FixedArray[Int]
  group : FixedArray[Int]
  phase : FixedArray[Int]
  status : FixedArray[Int]
  request_disposition : FixedArray[Int]
  group_outcome : FixedArray[Int]
  reason : FixedArray[Int]
  terminal_work_ids : FixedArray[Int]
  terminal_outcomes : FixedArray[Int]
  work_ids : FixedArray[Int]
  work_event_ids : FixedArray[Int]
  work_request_ids : FixedArray[Int]
  work_groups : FixedArray[Int]
  work_adopted : FixedArray[Bool]
  clock : () -> Int
  mut count : Int
  mut terminal_count : Int
  mut work_count : Int
  mut dropped_count : Int
  mut overflowed : Bool
  mut id_exhausted : Bool
  mut contract_violated : Bool
  mut next_sequence : Int
  mut next_event_id : Int
  mut next_request_id : Int
  mut next_group_work_id : Int
  mut next_presentation_id : Int
  mut current_event_id : Int
  mut current_request_id : Int
}

///|
const PROJECTION_TRACE_PHASE_A0 : Int = 1

///|
const PROJECTION_TRACE_PHASE_C : Int = 2

///|
const PROJECTION_TRACE_PHASE_A1 : Int = 3

///|
const PROJECTION_TRACE_PHASE_B : Int = 4

///|
const PROJECTION_TRACE_PHASE_D : Int = 5

///|
const PROJECTION_TRACE_PHASE_E : Int = 6

///|
const PROJECTION_TRACE_PHASE_F : Int = 7

///|
const PROJECTION_TRACE_STATUS_RECORDED : Int = 1

///|
const PROJECTION_TRACE_STATUS_OMITTED : Int = 2

///|
const PROJECTION_TRACE_STATUS_REQUEST_FINAL : Int = 3

///|
const PROJECTION_TRACE_STATUS_GROUP_FINAL : Int = 4

///|
const PROJECTION_TRACE_STATUS_ADOPTION_ACCEPTED : Int = 5

///|
#warnings("-unused_value")
const PROJECTION_TRACE_STATUS_ADOPTION_REJECTED : Int = 6

///|

///|
#warnings("-unused_value")
const PROJECTION_TRACE_GROUP_BLOCK : Int = 2

///|
#warnings("-unused_value")
const PROJECTION_TRACE_GROUP_NONE : Int = 0

///|
#warnings("-unused_value")
const PROJECTION_TRACE_GROUP_PREVIEW : Int = 1

///|
#warnings("-unused_value")
const PROJECTION_TRACE_GROUP_DIAGNOSTICS : Int = 3

///|
#warnings("-unused_value")
const PROJECTION_TRACE_REQUEST_NONE : Int = 0

///|
#warnings("-unused_value")
const PROJECTION_TRACE_REQUEST_DISPATCHED : Int = 1

///|
#warnings("-unused_value")
const PROJECTION_TRACE_REQUEST_NO_DEMAND : Int = 2

///|
#warnings("-unused_value")
const PROJECTION_TRACE_REQUEST_FAILED : Int = 3

///|
#warnings("-unused_value")
const PROJECTION_TRACE_GROUP_OUTCOME_NONE : Int = 0

///|
#warnings("-unused_value")
const PROJECTION_TRACE_GROUP_OUTCOME_PRESENTED : Int = 1

///|
#warnings("-unused_value")
const PROJECTION_TRACE_GROUP_OUTCOME_ADOPTED_NOT_PRESENTED : Int = 2

///|
#warnings("-unused_value")
const PROJECTION_TRACE_GROUP_OUTCOME_REJECTED_AT_ADOPTION : Int = 3

///|
#warnings("-unused_value")
const PROJECTION_TRACE_GROUP_OUTCOME_SUPERSEDED_BEFORE_EXECUTION : Int = 4

///|
#warnings("-unused_value")
const PROJECTION_TRACE_GROUP_OUTCOME_SUPERSEDED_AFTER_EXECUTION : Int = 5

///|
#warnings("-unused_value")
const PROJECTION_TRACE_GROUP_OUTCOME_GENERATION_INVALIDATED : Int = 6

///|
#warnings("-unused_value")
const PROJECTION_TRACE_GROUP_OUTCOME_FAILED : Int = 7

///|
#warnings("-unused_value")
const PROJECTION_TRACE_GROUP_OUTCOME_DISPOSED : Int = 8

///|
#warnings("-unused_value")
const PROJECTION_TRACE_REASON_NONE : Int = 0

///|
#warnings("-unused_value")
const PROJECTION_TRACE_REASON_NOT_ACCEPTED : Int = 1

///|
#warnings("-unused_value")
const PROJECTION_TRACE_REASON_GENERATION_INVALIDATED : Int = 2

///|
#warnings("-unused_value")
const PROJECTION_TRACE_REASON_PRESENTATION_NOT_OBSERVED : Int = 3

///|
#warnings("-unused_value")
const PROJECTION_TRACE_REASON_FAILED : Int = 4

///|
#warnings("-unused_value")
const PROJECTION_TRACE_REASON_NO_DEMAND : Int = 5

///|
let projection_trace : Ref[ProjectionTraceBuffer?] = Ref(None)

///|
#warnings("-unused_value")
fn projection_trace_enable(capacity~ : Int, clock~ : () -> Int) -> Unit {
  let capacity = capacity.clamp(min=0, max=65536)
  projection_trace.val = Some({
    sequence: FixedArray::make(capacity, 0),
    timestamp: FixedArray::make(capacity, 0),
    event_id: FixedArray::make(capacity, 0),
    request_id: FixedArray::make(capacity, 0),
    group_work_id: FixedArray::make(capacity, 0),
    presentation_id: FixedArray::make(capacity, 0),
    group: FixedArray::make(capacity, 0),
    phase: FixedArray::make(capacity, 0),
    status: FixedArray::make(capacity, 0),
    request_disposition: FixedArray::make(capacity, 0),
    group_outcome: FixedArray::make(capacity, 0),
    reason: FixedArray::make(capacity, 0),
    terminal_work_ids: FixedArray::make(capacity, 0),
    terminal_outcomes: FixedArray::make(capacity, 0),
    work_ids: FixedArray::make(capacity, 0),
    work_event_ids: FixedArray::make(capacity, 0),
    work_request_ids: FixedArray::make(capacity, 0),
    work_groups: FixedArray::make(capacity, 0),
    work_adopted: FixedArray::make(capacity, false),
    clock,
    count: 0,
    terminal_count: 0,
    work_count: 0,
    dropped_count: 0,
    overflowed: false,
    id_exhausted: false,
    contract_violated: false,
    next_sequence: 1,
    next_event_id: 1,
    next_request_id: 1,
    next_group_work_id: 1,
    next_presentation_id: 1,
    current_event_id: 0,
    current_request_id: 0,
  })
}

///|
#warnings("-unused_value")
fn projection_trace_disable() -> Unit {
  projection_trace.val = None
}

///|
fn projection_trace_enabled() -> Bool {
  projection_trace.val is Some(_)
}

///|
/// Allocation fails closed before an Int counter can wrap or reuse zero.
fn projection_trace_take_id(trace : ProjectionTraceBuffer, kind : Int) -> Int {
  let next = match kind {
    1 => trace.next_event_id
    2 => trace.next_request_id
    3 => trace.next_group_work_id
    _ => trace.next_presentation_id
  }
  if next <= 0 || next == 2147483647 {
    trace.id_exhausted = true
    0
  } else {
    match kind {
      1 => trace.next_event_id += 1
      2 => trace.next_request_id += 1
      3 => trace.next_group_work_id += 1
      _ => trace.next_presentation_id += 1
    }
    next
  }
}

///|
#warnings("-unused_value")
fn projection_trace_test_exhaust_group_ids() -> Unit {
  match projection_trace.val {
    None => ()
    Some(trace) => trace.next_group_work_id = 2147483647
  }
}

///|
fn projection_trace_record(
  event_id : Int,
  request_id : Int,
  group_work_id : Int,
  presentation_id : Int,
  group : Int,
  phase : Int,
  status : Int,
  request_disposition : Int,
  group_outcome : Int,
  reason : Int,
) -> Unit {
  match projection_trace.val {
    None => ()
    Some(trace) => {
      if trace.count >= trace.sequence.length() {
        trace.overflowed = true
        trace.dropped_count += 1
        return
      }
      let index = trace.count
      trace.sequence[index] = trace.next_sequence
      trace.timestamp[index] = (trace.clock)()
      trace.event_id[index] = event_id
      trace.request_id[index] = request_id
      trace.group_work_id[index] = group_work_id
      trace.presentation_id[index] = presentation_id
      trace.group[index] = group
      trace.phase[index] = phase
      trace.status[index] = status
      trace.request_disposition[index] = request_disposition
      trace.group_outcome[index] = group_outcome
      trace.reason[index] = reason
      trace.next_sequence += 1
      trace.count += 1
    }
  }
}

///|
fn projection_trace_begin_authority_event() -> Int {
  match projection_trace.val {
    None => 0
    Some(trace) => {
      let event_id = projection_trace_take_id(trace, 1)
      trace.current_event_id = event_id
      event_id
    }
  }
}

///|
fn projection_trace_test_begin_request(event_id : Int) -> Int {
  match projection_trace.val {
    None => 0
    Some(trace) => {
      let request_id = projection_trace_take_id(trace, 2)
      trace.current_event_id = event_id
      trace.current_request_id = request_id
      request_id
    }
  }
}

///|
/// Backward-compatible private name used by the current transaction owner.
fn projection_trace_begin_request() -> Int {
  projection_trace_begin_authority_event()
}

///|
fn projection_trace_ensure_request(event_id : Int) -> Int {
  match projection_trace.val {
    None => 0
    Some(trace) =>
      if trace.current_request_id != 0 {
        trace.current_request_id
      } else {
        projection_trace_test_begin_request(event_id)
      }
  }
}

///|
fn projection_trace_test_begin_group(request_id : Int, group : Int) -> Int {
  match projection_trace.val {
    None => 0
    Some(trace) => {
      guard trace.work_count < trace.work_ids.length() else {
        trace.overflowed = true
        trace.dropped_count += 1
        return 0
      }
      let work_id = projection_trace_take_id(trace, 3)
      guard work_id != 0 else { return 0 }
      let index = trace.work_count
      trace.work_ids[index] = work_id
      trace.work_event_ids[index] = trace.current_event_id
      trace.work_request_ids[index] = request_id
      trace.work_groups[index] = group
      trace.work_count += 1
      trace.current_request_id = request_id
      work_id
    }
  }
}

///|
#warnings("-unused_value")
fn projection_trace_test_begin_presentation() -> Int {
  match projection_trace.val {
    None => 0
    Some(trace) => projection_trace_take_id(trace, 4)
  }
}

///|
fn projection_trace_test_progress(
  event_id~ : Int,
  request_id~ : Int,
  group_work_id~ : Int,
  presentation_id~ : Int,
  group~ : Int,
  phase~ : Int,
) -> Unit {
  projection_trace_record(
    event_id,
    request_id,
    group_work_id,
    presentation_id,
    group,
    phase,
    PROJECTION_TRACE_STATUS_RECORDED,
    PROJECTION_TRACE_REQUEST_NONE,
    PROJECTION_TRACE_GROUP_OUTCOME_NONE,
    PROJECTION_TRACE_REASON_NONE,
  )
}

///|
fn projection_trace_terminal_index(
  trace : ProjectionTraceBuffer,
  work_id : Int,
) -> Int {
  for index in 0..<trace.terminal_count {
    if trace.terminal_work_ids[index] == work_id {
      return index
    }
  }
  -1
}

///|
fn projection_trace_work_index(
  trace : ProjectionTraceBuffer,
  work_id : Int,
) -> Int {
  for index in 0..<trace.work_count {
    if trace.work_ids[index] == work_id {
      return index
    }
  }
  -1
}

///|
fn projection_trace_test_group_terminal(
  work_id : Int,
  outcome : Int,
  reason : Int,
) -> Unit {
  guard work_id != 0 else { return }
  match projection_trace.val {
    None => ()
    Some(trace) => {
      let terminal_index = projection_trace_terminal_index(trace, work_id)
      if terminal_index >= 0 {
        trace.contract_violated = true
        return
      }
      guard trace.terminal_count < trace.terminal_work_ids.length() else {
        trace.overflowed = true
        trace.dropped_count += 1
        return
      }
      let work_index = projection_trace_work_index(trace, work_id)
      if work_index < 0 {
        trace.contract_violated = true
        return
      }
      let phase = if outcome ==
        PROJECTION_TRACE_GROUP_OUTCOME_ADOPTED_NOT_PRESENTED {
        if !trace.work_adopted[work_index] {
          trace.contract_violated = true
          return
        }
        PROJECTION_TRACE_PHASE_F
      } else {
        0
      }
      trace.terminal_work_ids[trace.terminal_count] = work_id
      trace.terminal_outcomes[trace.terminal_count] = outcome
      trace.terminal_count += 1
      projection_trace_record(
        trace.work_event_ids[work_index],
        trace.work_request_ids[work_index],
        work_id,
        0,
        trace.work_groups[work_index],
        phase,
        PROJECTION_TRACE_STATUS_GROUP_FINAL,
        PROJECTION_TRACE_REQUEST_NONE,
        outcome,
        reason,
      )
    }
  }
}

///|
#warnings("-unused_value")
fn projection_trace_test_present(work_id : Int, presentation_id : Int) -> Unit {
  guard work_id != 0 && presentation_id != 0 else { return }
  match projection_trace.val {
    None => ()
    Some(trace) => {
      let terminal_index = projection_trace_terminal_index(trace, work_id)
      if terminal_index >= 0 {
        trace.contract_violated = true
        return
      }
      guard trace.terminal_count < trace.terminal_work_ids.length() else {
        trace.overflowed = true
        trace.dropped_count += 1
        return
      }
      let work_index = projection_trace_work_index(trace, work_id)
      if work_index < 0 || !trace.work_adopted[work_index] {
        trace.contract_violated = true
        return
      }
      trace.terminal_work_ids[trace.terminal_count] = work_id
      trace.terminal_outcomes[trace.terminal_count] = PROJECTION_TRACE_GROUP_OUTCOME_PRESENTED
      trace.terminal_count += 1
      projection_trace_record(
        trace.work_event_ids[work_index],
        trace.work_request_ids[work_index],
        work_id,
        presentation_id,
        trace.work_groups[work_index],
        PROJECTION_TRACE_PHASE_F,
        PROJECTION_TRACE_STATUS_GROUP_FINAL,
        PROJECTION_TRACE_REQUEST_NONE,
        PROJECTION_TRACE_GROUP_OUTCOME_PRESENTED,
        PROJECTION_TRACE_REASON_NONE,
      )
    }
  }
}

///|
#warnings("-unused_value")
fn projection_trace_request_is_final(
  trace : ProjectionTraceBuffer,
  request_id : Int,
) -> Bool {
  for index in 0..<trace.count {
    if trace.request_id[index] == request_id &&
      trace.status[index] == PROJECTION_TRACE_STATUS_REQUEST_FINAL {
      return true
    }
  }
  false
}

///|
#warnings("-unused_value")
fn projection_trace_request_dispatched(request_id : Int) -> Unit {
  guard request_id != 0 else { return }
  match projection_trace.val {
    None => ()
    Some(trace) => {
      guard !projection_trace_request_is_final(trace, request_id) else {
        return
      }
      projection_trace_record(
        trace.current_event_id,
        request_id,
        0,
        0,
        PROJECTION_TRACE_GROUP_NONE,
        0,
        PROJECTION_TRACE_STATUS_REQUEST_FINAL,
        PROJECTION_TRACE_REQUEST_DISPATCHED,
        PROJECTION_TRACE_GROUP_OUTCOME_NONE,
        PROJECTION_TRACE_REASON_NONE,
      )
    }
  }
}

///|
fn projection_trace_request_no_demand(request_id : Int) -> Unit {
  guard request_id != 0 else { return }
  match projection_trace.val {
    None => ()
    Some(trace) => {
      guard !projection_trace_request_is_final(trace, request_id) else {
        return
      }
      projection_trace_record(
        trace.current_event_id,
        request_id,
        0,
        0,
        PROJECTION_TRACE_GROUP_NONE,
        0,
        PROJECTION_TRACE_STATUS_REQUEST_FINAL,
        PROJECTION_TRACE_REQUEST_NO_DEMAND,
        PROJECTION_TRACE_GROUP_OUTCOME_NONE,
        PROJECTION_TRACE_REASON_NO_DEMAND,
      )
    }
  }
}

///|
fn projection_trace_clear_request(_request_or_event_id : Int) -> Unit {
  match projection_trace.val {
    None => ()
    Some(trace) => {
      trace.current_event_id = 0
      trace.current_request_id = 0
    }
  }
}

///|
/// Finalize an explicitly evaluated request that requires no consistency-group
/// work. A missing current request means the decision was not projection work.
fn projection_trace_current_request_no_demand() -> Unit {
  match projection_trace.val {
    None => ()
    Some(trace) => {
      guard trace.current_request_id != 0 else { return }
      guard !projection_trace_request_is_final(trace, trace.current_request_id) else {
        return
      }
      projection_trace_request_no_demand(trace.current_request_id)
      projection_trace_clear_request(trace.current_request_id)
    }
  }
}

///|
fn projection_trace_event_omitted(event_id : Int, reason : Int) -> Unit {
  projection_trace_record(
    event_id,
    0,
    0,
    0,
    PROJECTION_TRACE_GROUP_NONE,
    0,
    PROJECTION_TRACE_STATUS_OMITTED,
    PROJECTION_TRACE_REQUEST_NONE,
    PROJECTION_TRACE_GROUP_OUTCOME_NONE,
    reason,
  )
  projection_trace_clear_request(event_id)
}

///|
fn projection_trace_generation_invalidated() -> Unit {
  match projection_trace.val {
    None => ()
    Some(trace) => {
      let request_id = trace.current_request_id
      if request_id == 0 {
        guard trace.current_event_id != 0 else { return }
        projection_trace_event_omitted(
          trace.current_event_id,
          PROJECTION_TRACE_REASON_GENERATION_INVALIDATED,
        )
        return
      }
      let mut issued_work = false
      for index in 0..<trace.work_count {
        if trace.work_request_ids[index] == request_id {
          issued_work = true
          projection_trace_test_group_terminal(
            trace.work_ids[index],
            PROJECTION_TRACE_GROUP_OUTCOME_GENERATION_INVALIDATED,
            PROJECTION_TRACE_REASON_GENERATION_INVALIDATED,
          )
        }
      }
      if !issued_work {
        projection_trace_record(
          trace.current_event_id,
          request_id,
          0,
          0,
          PROJECTION_TRACE_GROUP_NONE,
          0,
          PROJECTION_TRACE_STATUS_REQUEST_FINAL,
          PROJECTION_TRACE_REQUEST_FAILED,
          PROJECTION_TRACE_GROUP_OUTCOME_NONE,
          PROJECTION_TRACE_REASON_GENERATION_INVALIDATED,
        )
      }
      projection_trace_clear_request(request_id)
    }
  }
}

///|
fn projection_trace_begin_demand_group(next_requested~ : Bool) -> Unit {
  guard next_requested else { return }
  match projection_trace.val {
    None => ()
    Some(trace) => {
      guard trace.current_request_id == 0 else { return }
      let request_id = projection_trace_test_begin_request(0)
      projection_trace_test_progress(
        event_id=0,
        request_id~,
        group_work_id=0,
        presentation_id=0,
        group=PROJECTION_TRACE_GROUP_PREVIEW,
        phase=PROJECTION_TRACE_PHASE_C,
      )
    }
  }
}

///|
#warnings("-unused_value")
fn projection_trace_test_authority_accepted(request_id : Int) -> Unit {
  match projection_trace.val {
    None => ()
    Some(trace) =>
      projection_trace_record(
        trace.current_event_id,
        request_id,
        0,
        0,
        PROJECTION_TRACE_GROUP_NONE,
        PROJECTION_TRACE_PHASE_A0,
        PROJECTION_TRACE_STATUS_RECORDED,
        PROJECTION_TRACE_REQUEST_NONE,
        PROJECTION_TRACE_GROUP_OUTCOME_NONE,
        PROJECTION_TRACE_REASON_NONE,
      )
  }
}

///|
fn projection_trace_observe_authority(
  event_id : Int,
  phase : @markdown.MarkdownProjectionObservationPhase,
) -> Unit {
  match phase {
    @markdown.MarkdownProjectionObservationPhase::AuthorityAccepted =>
      projection_trace_test_progress(
        event_id~,
        request_id=0,
        group_work_id=0,
        presentation_id=0,
        group=PROJECTION_TRACE_GROUP_NONE,
        phase=PROJECTION_TRACE_PHASE_A0,
      )
    @markdown.MarkdownProjectionObservationPhase::ProjectionMirrorSynchronized => {
      let request_id = projection_trace_ensure_request(event_id)
      projection_trace_test_progress(
        event_id~,
        request_id~,
        group_work_id=0,
        presentation_id=0,
        group=PROJECTION_TRACE_GROUP_NONE,
        phase=PROJECTION_TRACE_PHASE_C,
      )
    }
    @markdown.MarkdownProjectionObservationPhase::CausalEvidenceAvailable => {
      projection_trace_test_progress(
        event_id~,
        request_id=0,
        group_work_id=0,
        presentation_id=0,
        group=PROJECTION_TRACE_GROUP_NONE,
        phase=PROJECTION_TRACE_PHASE_A1,
      )
      match projection_trace.val {
        Some(trace) if trace.current_request_id != 0 =>
          projection_trace_test_progress(
            event_id~,
            request_id=trace.current_request_id,
            group_work_id=0,
            presentation_id=0,
            group=PROJECTION_TRACE_GROUP_NONE,
            phase=PROJECTION_TRACE_PHASE_B,
          )
        _ => ()
      }
    }
  }
}

///|
/// Record a fresh recovery session's Seed materialization and execution. The
/// recovered model has no Preview demand, so the request issues no group work.
fn projection_trace_recovery_seed_materialized() -> Unit {
  match projection_trace.val {
    None => ()
    Some(_) => {
      let request_id = projection_trace_test_begin_request(0)
      projection_trace_test_progress(
        event_id=0,
        request_id~,
        group_work_id=0,
        presentation_id=0,
        group=PROJECTION_TRACE_GROUP_NONE,
        phase=PROJECTION_TRACE_PHASE_B,
      )
      projection_trace_test_progress(
        event_id=0,
        request_id~,
        group_work_id=0,
        presentation_id=0,
        group=PROJECTION_TRACE_GROUP_NONE,
        phase=PROJECTION_TRACE_PHASE_C,
      )
      projection_trace_request_no_demand(request_id)
    }
  }
}

///|
/// Call only after the semantic document has materialized successfully.
fn projection_trace_semantic_attachment_read() -> Unit {
  match projection_trace.val {
    None => ()
    Some(trace) => {
      let request_id = if trace.current_request_id == 0 {
        projection_trace_test_begin_request(trace.current_event_id)
      } else {
        trace.current_request_id
      }
      let work_id = projection_trace_test_begin_group(
        request_id,
        PROJECTION_TRACE_GROUP_PREVIEW,
      )
      guard work_id != 0 else { return }
      projection_trace_request_dispatched(request_id)
      projection_trace_test_progress(
        event_id=trace.current_event_id,
        request_id~,
        group_work_id=work_id,
        presentation_id=0,
        group=PROJECTION_TRACE_GROUP_PREVIEW,
        phase=PROJECTION_TRACE_PHASE_D,
      )
    }
  }
}

///|
/// Record a complete committed Block artifact and its selection/resolver
/// evidence before the application adopts it.
fn projection_trace_block_materialized() -> Unit {
  match projection_trace.val {
    None => ()
    Some(trace) => {
      guard trace.current_request_id != 0 else { return }
      let work_id = projection_trace_test_begin_group(
        trace.current_request_id,
        PROJECTION_TRACE_GROUP_BLOCK,
      )
      guard work_id != 0 else { return }
      projection_trace_request_dispatched(trace.current_request_id)
      projection_trace_test_progress(
        event_id=trace.current_event_id,
        request_id=trace.current_request_id,
        group_work_id=work_id,
        presentation_id=0,
        group=PROJECTION_TRACE_GROUP_BLOCK,
        phase=PROJECTION_TRACE_PHASE_D,
      )
    }
  }
}

///|

///|
#warnings("-unused_value")
fn projection_trace_test_group_adopted(work_id : Int) -> Unit {
  guard work_id != 0 else { return }
  match projection_trace.val {
    None => ()
    Some(trace) => {
      let work_index = projection_trace_work_index(trace, work_id)
      if work_index < 0 ||
        projection_trace_terminal_index(trace, work_id) >= 0 ||
        trace.work_adopted[work_index] {
        trace.contract_violated = true
        return
      }
      projection_trace_record(
        trace.work_event_ids[work_index],
        trace.work_request_ids[work_index],
        work_id,
        0,
        trace.work_groups[work_index],
        PROJECTION_TRACE_PHASE_E,
        PROJECTION_TRACE_STATUS_ADOPTION_ACCEPTED,
        PROJECTION_TRACE_REQUEST_NONE,
        PROJECTION_TRACE_GROUP_OUTCOME_NONE,
        PROJECTION_TRACE_REASON_NONE,
      )
      trace.work_adopted[work_index] = true
    }
  }
}

///|
/// Publish the retained Preview payload under the accepted causal stamp without
/// claiming application adoption.
fn projection_trace_retained_preview_materialized() -> Unit {
  match projection_trace.val {
    None => ()
    Some(trace) => {
      guard trace.current_request_id != 0 else { return }
      let work_id = projection_trace_test_begin_group(
        trace.current_request_id,
        PROJECTION_TRACE_GROUP_PREVIEW,
      )
      guard work_id != 0 else { return }
      projection_trace_request_dispatched(trace.current_request_id)
      projection_trace_test_progress(
        event_id=trace.current_event_id,
        request_id=trace.current_request_id,
        group_work_id=work_id,
        presentation_id=0,
        group=PROJECTION_TRACE_GROUP_PREVIEW,
        phase=PROJECTION_TRACE_PHASE_D,
      )
    }
  }
}

///|
fn projection_trace_driver_model_adopted() -> Unit {
  match projection_trace.val {
    None => ()
    Some(trace) => {
      let request_id = trace.current_request_id
      for index in 0..<trace.work_count {
        if trace.work_request_ids[index] == request_id &&
          !trace.work_adopted[index] {
          projection_trace_test_group_adopted(trace.work_ids[index])
        }
      }
    }
  }
}

///|
/// Commit 1 cannot observe browser paint; retire adoption explicitly after the
/// detached publication side effect instead of fabricating Presented.
fn projection_trace_adopted_not_presented() -> Unit {
  match projection_trace.val {
    None => ()
    Some(trace) => {
      let request_id = trace.current_request_id
      for index in 0..<trace.work_count {
        if trace.work_request_ids[index] == request_id &&
          trace.work_adopted[index] {
          projection_trace_test_group_terminal(
            trace.work_ids[index],
            PROJECTION_TRACE_GROUP_OUTCOME_ADOPTED_NOT_PRESENTED,
            PROJECTION_TRACE_REASON_PRESENTATION_NOT_OBSERVED,
          )
        }
      }
      projection_trace_clear_request(request_id)
    }
  }
}

///|
#warnings("-unused_value")
fn projection_trace_count() -> Int {
  match projection_trace.val {
    None => 0
    Some(t) => t.count
  }
}

///|
#warnings("-unused_value")
fn projection_trace_overflowed() -> Bool {
  match projection_trace.val {
    None => false
    Some(t) => t.overflowed || t.id_exhausted
  }
}

///|
#warnings("-unused_value")
fn projection_trace_dropped_count() -> Int {
  match projection_trace.val {
    None => 0
    Some(t) => t.dropped_count
  }
}

///|
fn projection_trace_field(index : Int, field : Int) -> Int? {
  match projection_trace.val {
    None => None
    Some(trace) =>
      if index < 0 || index >= trace.count {
        None
      } else {
        Some(
          match field {
            1 => trace.event_id[index]
            2 => trace.request_id[index]
            3 => trace.group_work_id[index]
            4 => trace.presentation_id[index]
            5 => trace.group[index]
            6 => trace.phase[index]
            7 => trace.status[index]
            8 => trace.request_disposition[index]
            9 => trace.group_outcome[index]
            10 => trace.reason[index]
            _ => trace.timestamp[index]
          },
        )
      }
  }
}

///|
#warnings("-unused_value")
fn projection_trace_event_id(index : Int) -> Int? {
  projection_trace_field(index, 1)
}

///|
#warnings("-unused_value")
fn projection_trace_request_id(index : Int) -> Int? {
  projection_trace_field(index, 2)
}

///|
#warnings("-unused_value")
fn projection_trace_group_work_id(index : Int) -> Int? {
  projection_trace_field(index, 3)
}

///|
#warnings("-unused_value")
fn projection_trace_presentation_id(index : Int) -> Int? {
  projection_trace_field(index, 4)
}

///|
#warnings("-unused_value")
fn projection_trace_group(index : Int) -> Int? {
  projection_trace_field(index, 5)
}

///|
#warnings("-unused_value")
fn projection_trace_phase(index : Int) -> Int? {
  projection_trace_field(index, 6)
}

///|
#warnings("-unused_value")
fn projection_trace_status(index : Int) -> Int? {
  projection_trace_field(index, 7)
}

///|
#warnings("-unused_value")
fn projection_trace_request_disposition(index : Int) -> Int? {
  projection_trace_field(index, 8)
}

///|
#warnings("-unused_value")
fn projection_trace_group_outcome(index : Int) -> Int? {
  projection_trace_field(index, 9)
}

///|
#warnings("-unused_value")
fn projection_trace_reason(index : Int) -> Int? {
  projection_trace_field(index, 10)
}

///|
#warnings("-unused_value")
fn projection_trace_timestamp(index : Int) -> Int? {
  projection_trace_field(index, 11)
}

///|
#warnings("-unused_value")
fn projection_trace_terminal_count(work_id : Int) -> Int {
  match projection_trace.val {
    None => 0
    Some(trace) => {
      let mut count = 0
      for index in 0..<trace.count {
        if trace.group_work_id[index] == work_id &&
          trace.group_outcome[index] != PROJECTION_TRACE_GROUP_OUTCOME_NONE {
          count += 1
        }
      }
      count
    }
  }
}

///|
#warnings("-unused_value")
fn projection_trace_contract_violated() -> Bool {
  match projection_trace.val {
    None => false
    Some(trace) => trace.contract_violated
  }
}
