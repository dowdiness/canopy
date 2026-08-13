/// Application-owned Commit 1 characterization trace for current synchronous
/// Loomark projection ownership. Storage is fixed-width and bounded; disabled
/// tracing has no buffer and never calls the injected clock.
priv struct ProjectionTraceBuffer {
  sequence : FixedArray[Int]
  timestamp : FixedArray[Int]
  request_id : FixedArray[Int]
  group_work_id : FixedArray[Int]
  presentation_id : FixedArray[Int]
  phase : FixedArray[Int]
  status : FixedArray[Int]
  reason : FixedArray[Int]
  clock : () -> Int
  mut count : Int
  mut next_sequence : Int
  mut next_request_id : Int
  mut next_group_work_id : Int
  mut next_presentation_id : Int
  mut current_request_id : Int
  mut current_group_work_id : Int
  mut current_presentation_id : Int
}

///|
const PROJECTION_TRACE_PHASE_A0 : Int = 1

///|
const PROJECTION_TRACE_PHASE_C : Int = 2

///|
const PROJECTION_TRACE_PHASE_A1 : Int = 3

///|
const PROJECTION_TRACE_PHASE_D : Int = 4

///|
const PROJECTION_TRACE_PHASE_E : Int = 5

///|
const PROJECTION_TRACE_PHASE_F : Int = 6

///|
const PROJECTION_TRACE_STATUS_RECORDED : Int = 1

///|
const PROJECTION_TRACE_STATUS_OMITTED : Int = 2

///|
const PROJECTION_TRACE_REASON_NONE : Int = 0

///|
const PROJECTION_TRACE_REASON_NOT_ACCEPTED : Int = 1

///|
const PROJECTION_TRACE_REASON_GENERATION_INVALIDATED : Int = 2

///|
let projection_trace : Ref[ProjectionTraceBuffer?] = Ref(None)


///|
#warnings("-unused_value")
fn projection_trace_enable(
  capacity~ : Int,
  clock~ : () -> Int,
) -> Unit {
  let capacity = capacity.clamp(min=0, max=65536)
  projection_trace.val = Some({
    sequence: FixedArray::make(capacity, 0),
    timestamp: FixedArray::make(capacity, 0),
    request_id: FixedArray::make(capacity, 0),
    group_work_id: FixedArray::make(capacity, 0),
    presentation_id: FixedArray::make(capacity, 0),
    phase: FixedArray::make(capacity, 0),
    status: FixedArray::make(capacity, 0),
    reason: FixedArray::make(capacity, 0),
    clock,
    count: 0,
    next_sequence: 1,
    next_request_id: 1,
    next_group_work_id: 1,
    next_presentation_id: 1,
    current_request_id: 0,
    current_group_work_id: 0,
    current_presentation_id: 0,
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
fn projection_trace_begin_request() -> Int {
  match projection_trace.val {
    None => 0
    Some(trace) => {
      let request_id = trace.next_request_id
      let group_work_id = trace.next_group_work_id
      let presentation_id = trace.next_presentation_id
      trace.next_request_id += 1
      trace.next_group_work_id += 1
      trace.next_presentation_id += 1
      trace.current_request_id = request_id
      trace.current_group_work_id = group_work_id
      trace.current_presentation_id = presentation_id
      request_id
    }
  }
}

///|
fn projection_trace_clear_request(request_id : Int) -> Unit {
  match projection_trace.val {
    None => ()
    Some(trace) => {
      if trace.current_request_id == request_id {
        trace.current_request_id = 0
        trace.current_group_work_id = 0
        trace.current_presentation_id = 0
      }
    }
  }
}

///|
fn projection_trace_record(
  request_id : Int,
  phase : Int,
  status : Int,
  reason : Int,
) -> Unit {
  guard request_id != 0 else { return }
  match projection_trace.val {
    None => ()
    Some(trace) => {
      guard trace.count < trace.sequence.length() else { return }
      let index = trace.count
      trace.sequence[index] = trace.next_sequence
      trace.timestamp[index] = (trace.clock)()
      trace.request_id[index] = request_id
      trace.group_work_id[index] = trace.current_group_work_id
      trace.presentation_id[index] = trace.current_presentation_id
      trace.phase[index] = phase
      trace.status[index] = status
      trace.reason[index] = reason
      trace.next_sequence += 1
      trace.count += 1
    }
  }
}

///|
fn projection_trace_record_current(phase : Int) -> Unit {
  match projection_trace.val {
    None => ()
    Some(trace) =>
      projection_trace_record(
        trace.current_request_id,
        phase,
        PROJECTION_TRACE_STATUS_RECORDED,
        PROJECTION_TRACE_REASON_NONE,
      )
  }
}

///|
fn projection_trace_omit_request(request_id : Int, reason : Int) -> Unit {
  projection_trace_record(
    request_id,
    PROJECTION_TRACE_PHASE_A0,
    PROJECTION_TRACE_STATUS_OMITTED,
    reason,
  )
  projection_trace_clear_request(request_id)
}

///|
fn projection_trace_generation_invalidated() -> Unit {
  match projection_trace.val {
    None => ()
    Some(trace) => {
      let request_id = trace.current_request_id
      projection_trace_record(
        request_id,
        PROJECTION_TRACE_PHASE_F,
        PROJECTION_TRACE_STATUS_OMITTED,
        PROJECTION_TRACE_REASON_GENERATION_INVALIDATED,
      )
      projection_trace_clear_request(request_id)
    }
  }
}

///|
fn projection_trace_begin_demand_group(next_requested~ : Bool) -> Unit {
  guard next_requested else { return }
  let request_id = projection_trace_begin_request()
  projection_trace_record(
    request_id,
    PROJECTION_TRACE_PHASE_C,
    PROJECTION_TRACE_STATUS_RECORDED,
    PROJECTION_TRACE_REASON_NONE,
  )
}

///|
fn projection_trace_observe_authority(
  request_id : Int,
  phase : @editor.ProjectionObservationPhase,
) -> Unit {
  match phase {
    @editor.ProjectionObservationPhase::AuthorityAccepted =>
      projection_trace_record(
        request_id,
        PROJECTION_TRACE_PHASE_A0,
        PROJECTION_TRACE_STATUS_RECORDED,
        PROJECTION_TRACE_REASON_NONE,
      )
    @editor.ProjectionObservationPhase::ParserSynchronized =>
      projection_trace_record(
        request_id,
        PROJECTION_TRACE_PHASE_C,
        PROJECTION_TRACE_STATUS_RECORDED,
        PROJECTION_TRACE_REASON_NONE,
      )
    @editor.ProjectionObservationPhase::CausalEvidenceAvailable =>
      projection_trace_record(
        request_id,
        PROJECTION_TRACE_PHASE_A1,
        PROJECTION_TRACE_STATUS_RECORDED,
        PROJECTION_TRACE_REASON_NONE,
      )
  }
}

///|
fn projection_trace_semantic_attachment_read() -> Unit {
  projection_trace_record_current(PROJECTION_TRACE_PHASE_D)
}

///|
fn projection_trace_driver_model_adopted() -> Unit {
  projection_trace_record_current(PROJECTION_TRACE_PHASE_E)
}

///|
fn projection_trace_published() -> Unit {
  match projection_trace.val {
    None => ()
    Some(trace) => {
      let request_id = trace.current_request_id
      projection_trace_record_current(PROJECTION_TRACE_PHASE_F)
      projection_trace_clear_request(request_id)
    }
  }
}

///|
#warnings("-unused_value")
fn projection_trace_count() -> Int {
  match projection_trace.val {
    None => 0
    Some(trace) => trace.count
  }
}

///|
#warnings("-unused_value")
fn projection_trace_phase(index : Int) -> Int? {
  match projection_trace.val {
    None => None
    Some(trace) =>
      if index < 0 || index >= trace.count { None } else { Some(trace.phase[index]) }
  }
}

///|
#warnings("-unused_value")
fn projection_trace_request_id(index : Int) -> Int? {
  match projection_trace.val {
    None => None
    Some(trace) =>
      if index < 0 || index >= trace.count {
        None
      } else {
        Some(trace.request_id[index])
      }
  }
}

///|
#warnings("-unused_value")
fn projection_trace_group_work_id(index : Int) -> Int? {
  match projection_trace.val {
    None => None
    Some(trace) =>
      if index < 0 || index >= trace.count {
        None
      } else {
        Some(trace.group_work_id[index])
      }
  }
}

///|
#warnings("-unused_value")
fn projection_trace_presentation_id(index : Int) -> Int? {
  match projection_trace.val {
    None => None
    Some(trace) =>
      if index < 0 || index >= trace.count {
        None
      } else {
        Some(trace.presentation_id[index])
      }
  }
}

///|
#warnings("-unused_value")
fn projection_trace_status(index : Int) -> Int? {
  match projection_trace.val {
    None => None
    Some(trace) =>
      if index < 0 || index >= trace.count {
        None
      } else {
        Some(trace.status[index])
      }
  }
}

///|
#warnings("-unused_value")
fn projection_trace_reason(index : Int) -> Int? {
  match projection_trace.val {
    None => None
    Some(trace) =>
      if index < 0 || index >= trace.count {
        None
      } else {
        Some(trace.reason[index])
      }
  }
}

///|
#warnings("-unused_value")
fn projection_trace_timestamp(index : Int) -> Int? {
  match projection_trace.val {
    None => None
    Some(trace) =>
      if index < 0 || index >= trace.count {
        None
      } else {
        Some(trace.timestamp[index])
      }
  }
}
