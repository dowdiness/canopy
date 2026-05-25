///|
/// Small incr-backed core for store-wide revision and dependency snapshots.
struct CognitionReactive {
  revision : @incr.Input[Revision]
  dependency_tick : @incr.Input[Int]
  dependency_edges_watch : @incr.Watch[Array[Dependency]]
}

///|
fn CognitionReactive::CognitionReactive(
  dependencies : Map[CognitionKey, Array[CognitionKey]],
) -> CognitionReactive {
  let runtime = @incr.Runtime::new()
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
  { revision, dependency_tick, dependency_edges_watch }
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
