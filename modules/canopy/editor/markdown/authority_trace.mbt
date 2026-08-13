/// Private Commit 1 characterization trace for the authority half of the
/// Markdown façade. Sequence is a monotonic observation ordinal; browser wall
/// time belongs to the application-level A–F trace.
priv struct MarkdownAuthorityTraceBuffer {
  sequence : FixedArray[Int]
  phase : FixedArray[Int]
  event_id : FixedArray[Int]
  mut count : Int
  mut next_sequence : Int
  mut next_event_id : Int
}

///|
const MARKDOWN_AUTHORITY_PHASE_A0 : Int = 1

///|
const MARKDOWN_AUTHORITY_PHASE_A1 : Int = 2

///|
let markdown_authority_trace : Ref[MarkdownAuthorityTraceBuffer?] = Ref(None)

/// Opt-in full-document export detector used only by characterization tests.
let markdown_full_export_count : Ref[Int?] = Ref(None)

///|
fn markdown_full_export_observed() -> Unit {
  match markdown_full_export_count.val {
    Some(count) => markdown_full_export_count.val = Some(count + 1)
    None => ()
  }
}

///|
#warnings("-unused_value")
fn markdown_full_export_detector_enable() -> Unit {
  markdown_full_export_count.val = Some(0)
}

///|
#warnings("-unused_value")
fn markdown_full_export_detector_disable() -> Unit {
  markdown_full_export_count.val = None
}

///|
#warnings("-unused_value")
fn markdown_full_export_detector_count() -> Int {
  markdown_full_export_count.val.unwrap_or(0)
}

///|
#warnings("-unused_value")
fn markdown_authority_trace_enable(capacity~ : Int) -> Unit {
  let capacity = capacity.clamp(min=0, max=65536)
  markdown_authority_trace.val = Some({
    sequence: FixedArray::make(capacity, 0),
    phase: FixedArray::make(capacity, 0),
    event_id: FixedArray::make(capacity, 0),
    count: 0,
    next_sequence: 1,
    next_event_id: 1,
  })
}

///|
#warnings("-unused_value")
fn markdown_authority_trace_disable() -> Unit {
  markdown_authority_trace.val = None
}

///|
fn markdown_authority_trace_begin() -> Int {
  match markdown_authority_trace.val {
    None => 0
    Some(trace) => {
      let event_id = trace.next_event_id
      trace.next_event_id += 1
      event_id
    }
  }
}

///|
fn markdown_authority_trace_record(event_id : Int, phase : Int) -> Unit {
  match markdown_authority_trace.val {
    None => ()
    Some(trace) => {
      guard trace.count < trace.sequence.length() else { return }
      let index = trace.count
      trace.sequence[index] = trace.next_sequence
      trace.phase[index] = phase
      trace.event_id[index] = event_id
      trace.next_sequence += 1
      trace.count += 1
    }
  }
}

///|
fn markdown_authority_trace_a0(event_id : Int) -> Unit {
  markdown_authority_trace_record(event_id, MARKDOWN_AUTHORITY_PHASE_A0)
}


///|
fn markdown_authority_trace_a1(event_id : Int) -> Unit {
  markdown_authority_trace_record(event_id, MARKDOWN_AUTHORITY_PHASE_A1)
}

///|
#warnings("-unused_value")
fn markdown_authority_trace_count() -> Int {
  match markdown_authority_trace.val {
    None => 0
    Some(trace) => trace.count
  }
}

///|
#warnings("-unused_value")
fn markdown_authority_trace_phase(index : Int) -> Int? {
  match markdown_authority_trace.val {
    None => None
    Some(trace) =>
      if index < 0 || index >= trace.count { None } else { Some(trace.phase[index]) }
  }
}

///|
#warnings("-unused_value")
fn markdown_authority_trace_event_id(index : Int) -> Int? {
  match markdown_authority_trace.val {
    None => None
    Some(trace) =>
      if index < 0 || index >= trace.count {
        None
      } else {
        Some(trace.event_id[index])
      }
  }
}
