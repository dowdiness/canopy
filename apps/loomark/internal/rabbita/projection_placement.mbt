///|
/// Private measurement selector. Browser production and malformed query values
/// remain synchronous; non-browser test runtimes retain the Worker trace contract.
#warnings("-unused_value")
priv enum ProjectionPlacement {
  ProjectionWorker
  ProjectionInProcess
  ProjectionSynchronous
} derive(Eq, Debug)

///|
#warnings("-unused_value")
fn projection_placement_from_query(value : String?) -> ProjectionPlacement {
  match value {
    Some("worker") => ProjectionWorker
    Some("in-process") => ProjectionInProcess
    _ => ProjectionSynchronous
  }
}

///|
#warnings("-unused_value")
fn projection_benchmark_enabled_from_query(value : String?) -> Bool {
  value == Some("1")
}

///|
/// Disable persistence only inside the explicitly enabled private benchmark.
fn archive_persistence_enabled_from_query(
  benchmark_enabled : Bool,
  value : String?,
) -> Bool {
  !(benchmark_enabled && value == Some("0"))
}

///|
/// Enable fixed-width persistence tracing only for an exact private opt-in.
fn persistence_trace_enabled_from_query(
  benchmark_enabled : Bool,
  value : String?,
) -> Bool {
  benchmark_enabled && value == Some("1")
}

///|
/// PROTOTYPE: replace full-history persistence only under an exact private
/// benchmark opt-in. Production and malformed values retain v1 behavior.
fn local_text_prototype_enabled_from_query(
  benchmark_enabled : Bool,
  value : String?,
) -> Bool {
  benchmark_enabled && value == Some("1")
}

///|
/// PROTOTYPE: publish browser-owned causal-ready marks only for the private
/// four-clock experiment.
fn four_clock_prototype_enabled_from_query(
  benchmark_enabled : Bool,
  value : String?,
) -> Bool {
  benchmark_enabled && value == Some("1")
}

///|
#warnings("-unused_value")
fn ProjectionPlacement::name(self : ProjectionPlacement) -> String {
  match self {
    ProjectionWorker => "worker"
    ProjectionInProcess => "in-process"
    ProjectionSynchronous => "synchronous"
  }
}

///|
extern "js" fn projection_placement_query_value() -> String =
  #| () => globalThis.location == null
  #|   ? "worker"
  #|   : new URLSearchParams(globalThis.location.search).get("projection-placement") ?? ""

///|
extern "js" fn projection_benchmark_query_value() -> String =
  #| () => new URLSearchParams(globalThis.location?.search ?? "")
  #|   .get("projection-benchmark") ?? ""

///|
extern "js" fn archive_persistence_query_value() -> String =
  #| () => new URLSearchParams(globalThis.location?.search ?? "")
  #|   .get("archive-persistence") ?? ""

///|
extern "js" fn persistence_trace_query_value() -> String =
  #| () => new URLSearchParams(globalThis.location?.search ?? "")
  #|   .get("persistence-trace") ?? ""

///|
extern "js" fn local_text_prototype_query_value() -> String =
  #| () => new URLSearchParams(globalThis.location?.search ?? "")
  #|   .get("local-text-prototype") ?? ""

///|
extern "js" fn four_clock_prototype_query_value() -> String =
  #| () => new URLSearchParams(globalThis.location?.search ?? "")
  #|   .get("four-clock-prototype") ?? ""

///|
extern "js" fn publish_causal_ready_prototype_mark() -> Unit =
  #| () => {
  #|   const root = document.documentElement;
  #|   const previous = Number(root.dataset.loomarkCausalReadySequence ?? "0");
  #|   root.dataset.loomarkCausalReadySequence = (previous + 1).toString();
  #|   root.dataset.loomarkCausalReadyMs = performance.now().toString();
  #| }

///|
#warnings("-unused_value")
fn current_projection_placement() -> ProjectionPlacement {
  projection_placement_from_query(Some(projection_placement_query_value()))
}

///|
let selected_projection_placement : ProjectionPlacement = current_projection_placement()

///|
#warnings("-unused_value")
let projection_benchmark_enabled : Bool = projection_benchmark_enabled_from_query(
  Some(projection_benchmark_query_value()),
)

///|
let archive_persistence_enabled : Bool = archive_persistence_enabled_from_query(
  projection_benchmark_enabled,
  Some(archive_persistence_query_value()),
)

///|
let persistence_trace_enabled : Bool = persistence_trace_enabled_from_query(
  projection_benchmark_enabled,
  Some(persistence_trace_query_value()),
)

///|
let local_text_prototype_enabled : Bool = local_text_prototype_enabled_from_query(
  projection_benchmark_enabled,
  Some(local_text_prototype_query_value()),
)

///|
let four_clock_prototype_enabled : Bool = four_clock_prototype_enabled_from_query(
  projection_benchmark_enabled,
  Some(four_clock_prototype_query_value()),
)

///|
fn mark_causal_ready_for_prototype() -> Unit {
  if four_clock_prototype_enabled {
    publish_causal_ready_prototype_mark()
  }
}
