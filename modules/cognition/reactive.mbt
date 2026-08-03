///|
/// Small incr-backed core for store-wide revision and dependency snapshots.
struct CognitionReactive {
  revision : @incr.Input[Revision]
  dependency_tick : @incr.Input[Int]
  dependency_edges_watch : @incr.Watch[Array[Dependency]]
  provider_planning : ProviderPlanningGraph
}

///|
fn CognitionReactive::CognitionReactive(
  dependencies : Map[CognitionKey, Array[CognitionKey]],
) -> CognitionReactive {
  let runtime = @incr.Runtime()
  let revision = @incr.Input(runtime, Revision(0), label="cognition_revision")
  let dependency_tick = @incr.Input(
    runtime,
    0,
    label="cognition_dependency_tick",
  )
  let dependency_edges_cell = @incr.Derived::Derived(
    runtime,
    fn() {
      let _ = dependency_tick.get()
      dependency_edges_from(dependencies)
    },
    label="cognition_dependency_edges",
  )
  let dependency_edges_watch = dependency_edges_cell.watch()
  let provider_planning = ProviderPlanningGraph::ProviderPlanningGraph(runtime)
  provider_planning.set_fake_time_ms(0)
  { revision, dependency_tick, dependency_edges_watch, provider_planning }
}

///|
fn CognitionReactive::bump_revision(self : CognitionReactive) -> Revision {
  let next = Revision(self.revision.peek().to_int() + 1)
  self.revision.set(next)
  next
}

///|
fn CognitionReactive::current_revision(self : CognitionReactive) -> Revision {
  self.revision.peek()
}

///|
fn CognitionReactive::bump_dependency_revision(
  self : CognitionReactive,
) -> Unit {
  self.dependency_tick.set(self.dependency_tick.peek() + 1)
}

///|
fn CognitionReactive::dependency_edges(
  self : CognitionReactive,
) -> Array[Dependency] {
  self.dependency_edges_watch.read_or_abort().copy()
}

///|
fn CognitionReactive::plan_provider_request(
  self : CognitionReactive,
  target~ : CognitionKey,
  options~ : ProviderOptionProvenance,
  context~ : Array[ContextItem],
  source_revisions~ : Array[ProviderSourceSnapshot],
  dependencies~ : Array[CognitionKey],
) -> ProviderRequestDescriptor {
  let request = self.provider_planning.plan_request(
    target~,
    options~,
    context~,
    source_revisions~,
    dependencies~,
  )
  self.prime_provider_boundary()
  request
}

///|
fn CognitionReactive::clear_provider_events(self : CognitionReactive) -> Unit {
  self.provider_planning.clear_events()
  self.prime_provider_boundary()
}

///|
fn CognitionReactive::record_provider_cancellation(
  self : CognitionReactive,
  request : ProviderRequestDescriptor,
) -> Unit {
  self.provider_planning.record_cancellation(request)
  self.prime_provider_boundary()
}

///|
/// Internal provider-driver test hook; keep private until a real driver API exists.
#warnings("-unused_value")
fn CognitionReactive::acknowledge_provider_cancellation(
  self : CognitionReactive,
  request_id : ProviderRequestId,
) -> Unit {
  self.provider_planning.acknowledge_cancellation(request_id)
  self.prime_provider_boundary()
}

///|
/// Internal provider-driver test hook; keep private until a real driver API exists.
#warnings("-unused_value")
fn CognitionReactive::acknowledge_provider_start(
  self : CognitionReactive,
  request_id : ProviderRequestId,
) -> Unit {
  self.provider_planning.acknowledge_start(request_id)
  self.prime_provider_boundary()
}

///|
fn CognitionReactive::record_provider_completion(
  self : CognitionReactive,
  request : ProviderRequestDescriptor,
  completion : ProviderResultDescriptor,
) -> Unit {
  self.provider_planning.record_completion(request, completion)
  self.prime_provider_boundary()
}

///|
fn CognitionReactive::provider_dependency_fingerprint(
  self : CognitionReactive,
) -> ProviderDependencyFingerprint? {
  self.provider_planning.dependency_fingerprint()
}

///|
fn CognitionReactive::provider_status(
  self : CognitionReactive,
) -> ProviderStatusDescriptor? {
  self.provider_planning.status()
}

///|
fn CognitionReactive::provider_retry_classification(
  self : CognitionReactive,
) -> ProviderRetryClassification? {
  self.provider_planning.retry_classification()
}

///|
fn CognitionReactive::provider_next_driver_action(
  self : CognitionReactive,
) -> ProviderDriverAction {
  self.provider_planning.next_driver_action()
}

///|
#warnings("-unused_value")
fn CognitionReactive::provider_next_driver_action_at(
  self : CognitionReactive,
  now_ms : Int,
) -> ProviderDriverAction {
  self.provider_planning.next_driver_action_at(now_ms)
}

///|
fn CognitionReactive::prime_provider_boundary(self : CognitionReactive) -> Unit {
  let _ = self.provider_dependency_fingerprint()
  let _ = self.provider_status()
  let _ = self.provider_retry_classification()
  let _ = self.provider_next_driver_action()
}

///|
fn dependency_edges_from(
  dependencies : Map[CognitionKey, Array[CognitionKey]],
) -> Array[Dependency] {
  let edges : Array[Dependency] = []
  for from, inputs in dependencies {
    for input in inputs {
      edges.push({ from, input })
    }
  }
  edges.sort_by(fn(a, b) {
    let by_from = a.from.compare(b.from)
    if by_from != 0 {
      by_from
    } else {
      a.input.compare(b.input)
    }
  })
  edges
}
