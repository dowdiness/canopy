///|
/// Private measurement selector. Production and every malformed value remain on
/// the dedicated Worker placement.
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
  #| () => new URLSearchParams(globalThis.location?.search ?? "")
  #|   .get("projection-placement") ?? ""

///|
extern "js" fn projection_benchmark_query_value() -> String =
  #| () => new URLSearchParams(globalThis.location?.search ?? "")
  #|   .get("projection-benchmark") ?? ""

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
