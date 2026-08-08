// PROTOTYPE — throwaway logic for the Markdown public API RC1.
//
// Question: can a mounted/unmounted writing-instance state machine make
// unmount idempotent without losing retryability, and can internal UTF-16
// edits be projected into a sentinel-free public coordinate space while
// preserving sequential transform application?

///|
struct HiddenRange {
  start : Int
  end : Int
} derive(Debug, Eq)

///|
struct PrototypeTransform {
  start : Int
  delete_len : Int
  inserted : String
  inserted_hidden : Array[HiddenRange]
} derive(Debug, Eq)

///|
struct PublicTransform {
  start : Int
  delete_len : Int
  inserted : String
} derive(Debug, Eq)

///|
struct CoordinateScenario {
  name : String
  internal_source : String
  hidden : Array[HiddenRange]
  edits : Array[PrototypeTransform]
}

///|
struct CoordinateModel {
  scenario_index : Int
  scenario_name : String
  internal_source : String
  hidden : Array[HiddenRange]
  public_source : String
  edits : Array[PrototypeTransform]
  applied_edits : Int
  last_internal : PrototypeTransform?
  last_public : PublicTransform?
  invariant_holds : Bool
}

///|
enum LifecycleState {
  DetachedSource
  Mounted(writer~ : String)
  DetachedHistory
} derive(Debug, Eq)

///|
struct LifecycleModel {
  state : LifecycleState
  source : String
  version : Int
  mount_generation : Int
  fail_next_unmount : Bool
  last_event : String
}

///|
struct PrototypeModel {
  lifecycle : LifecycleModel
  coordinates : CoordinateModel
  integration : IntegrationReport?
  notice : String
}

///|
enum PrototypeAction {
  NextScenario
  ApplyCoordinateEdit
  RecordIntegration(IntegrationReport)
  Mount
  Unmount
  ToggleUnmountFailure
  ApplyDocumentEdit
}

///|
fn project_source(source : String, hidden : Array[HiddenRange]) -> String {
  let ordered = hidden.copy()
  ordered.sort_by((a, b) => a.start.compare(b.start))
  let builder = StringBuilder()
  let mut position = 0
  for range in ordered {
    if range.start > position {
      builder.write_view(source[position:range.start])
    }
    position = position.max(range.end)
  }
  if position < source.length() {
    builder.write_view(source[position:])
  }
  builder.to_string()
}

///|
fn visible_offset(hidden : Array[HiddenRange], internal_offset : Int) -> Int {
  let hidden_before = hidden.fold(init=0, (total, range) => {
    if range.end <= internal_offset {
      total + range.end - range.start
    } else if range.start < internal_offset {
      total + internal_offset - range.start
    } else {
      total
    }
  })
  internal_offset - hidden_before
}

///|
fn apply_transform(source : String, transform : PublicTransform) -> String {
  let end = transform.start + transform.delete_len
  source[:transform.start].to_owned() +
  transform.inserted +
  source[end:].to_owned()
}

///|
fn map_transform(
  hidden : Array[HiddenRange],
  transform : PrototypeTransform,
) -> PublicTransform {
  let end = transform.start + transform.delete_len
  {
    start: visible_offset(hidden, transform.start),
    delete_len: visible_offset(hidden, end) -
    visible_offset(hidden, transform.start),
    inserted: project_source(transform.inserted, transform.inserted_hidden),
  }
}

///|
fn hidden_after_transform(
  hidden : Array[HiddenRange],
  transform : PrototypeTransform,
) -> Array[HiddenRange] {
  let deleted_end = transform.start + transform.delete_len
  let shift = transform.inserted.length() - transform.delete_len
  let next : Array[HiddenRange] = []
  for range in hidden {
    if range.end <= transform.start {
      next.push(range)
    } else if range.start >= deleted_end {
      next.push({ start: range.start + shift, end: range.end + shift })
    }
  }
  for range in transform.inserted_hidden {
    next.push({
      start: transform.start + range.start,
      end: transform.start + range.end,
    })
  }
  next.sort_by((a, b) => a.start.compare(b.start))
  next
}

///|
fn coordinate_scenarios() -> Array[CoordinateScenario] {
  [
    {
      name: "insert empty paragraph sentinel",
      internal_source: "A\nB",
      hidden: [],
      edits: [
        {
          start: 2,
          delete_len: 0,
          inserted: "\u200B\n",
          inserted_hidden: [{ start: 0, end: 1 }],
        },
      ],
    },
    {
      name: "CRLF around hidden sentinel",
      internal_source: "A\r\n\u200B\r\nB",
      hidden: [{ start: 3, end: 4 }],
      edits: [{ start: 6, delete_len: 1, inserted: "C", inserted_hidden: [] }],
    },
    {
      name: "non-BMP UTF-16 coordinates",
      internal_source: "😀\n\u200B\nB",
      hidden: [{ start: 3, end: 4 }],
      edits: [
        { start: 5, delete_len: 1, inserted: "🚀", inserted_hidden: [] },
      ],
    },
    {
      name: "sequential multi-transform projection",
      internal_source: "alpha\n\u200B\nomega",
      hidden: [{ start: 6, end: 7 }],
      edits: [
        { start: 8, delete_len: 5, inserted: "Ω", inserted_hidden: [] },
        { start: 0, delete_len: 5, inserted: "😀", inserted_hidden: [] },
        { start: 2, delete_len: 3, inserted: "\n", inserted_hidden: [] },
      ],
    },
  ]
}

///|
fn coordinate_model(scenario_index : Int) -> CoordinateModel {
  let scenarios = coordinate_scenarios()
  let index = scenario_index % scenarios.length()
  let scenario = scenarios[index]
  {
    scenario_index: index,
    scenario_name: scenario.name,
    internal_source: scenario.internal_source,
    hidden: scenario.hidden.copy(),
    public_source: project_source(scenario.internal_source, scenario.hidden),
    edits: scenario.edits,
    applied_edits: 0,
    last_internal: None,
    last_public: None,
    invariant_holds: true,
  }
}

///|
fn CoordinateModel::apply_next(self : CoordinateModel) -> CoordinateModel {
  guard self.edits.get(self.applied_edits) is Some(internal_transform) else {
    return self
  }
  let public_transform = map_transform(self.hidden, internal_transform)
  let next_public_from_transform = apply_transform(
    self.public_source,
    public_transform,
  )
  let next_internal = apply_transform(self.internal_source, {
    start: internal_transform.start,
    delete_len: internal_transform.delete_len,
    inserted: internal_transform.inserted,
  })
  let next_hidden = hidden_after_transform(self.hidden, internal_transform)
  let next_public_from_projection = project_source(next_internal, next_hidden)
  {
    ..self,
    internal_source: next_internal,
    hidden: next_hidden,
    public_source: next_public_from_projection,
    applied_edits: self.applied_edits + 1,
    last_internal: Some(internal_transform),
    last_public: Some(public_transform),
    invariant_holds: self.invariant_holds &&
    next_public_from_transform == next_public_from_projection,
  }
}

///|
fn initial_lifecycle() -> LifecycleModel {
  {
    state: DetachedSource,
    source: "# Prototype\n",
    version: 0,
    mount_generation: 0,
    fail_next_unmount: false,
    last_event: "created detached source",
  }
}

///|
fn LifecycleModel::mount(self : LifecycleModel) -> LifecycleModel {
  match self.state {
    Mounted(..) => { ..self, last_event: "mount ignored: already mounted" }
    DetachedSource | DetachedHistory => {
      let generation = self.mount_generation + 1
      let writer = "writer-\{generation}"
      {
        ..self,
        state: Mounted(writer~),
        mount_generation: generation,
        last_event: "mounted with a fresh writer identity",
      }
    }
  }
}

///|
fn LifecycleModel::unmount(self : LifecycleModel) -> LifecycleModel {
  match self.state {
    DetachedHistory =>
      { ..self, last_event: "unmount returned the cached detached document" }
    DetachedSource =>
      { ..self, last_event: "unmount ignored: document has never been mounted" }
    Mounted(..) if self.fail_next_unmount =>
      {
        ..self,
        fail_next_unmount: false,
        last_event: "history export failed; editor remains mounted",
      }
    Mounted(..) =>
      {
        ..self,
        state: DetachedHistory,
        last_event: "history captured; runtime unmounted",
      }
  }
}

///|
fn LifecycleModel::apply_edit(self : LifecycleModel) -> LifecycleModel {
  match self.state {
    Mounted(..) =>
      {
        ..self,
        source: self.source + "!",
        version: self.version + 1,
        last_event: "edit accepted and causal frontier advanced",
      }
    DetachedSource | DetachedHistory =>
      { ..self, last_event: "edit rejected: no mounted writing instance" }
  }
}

///|
fn initial_model() -> PrototypeModel {
  {
    lifecycle: initial_lifecycle(),
    coordinates: coordinate_model(0),
    integration: None,
    notice: "prototype ready",
  }
}

///|
fn reduce(model : PrototypeModel, action : PrototypeAction) -> PrototypeModel {
  match action {
    NextScenario =>
      {
        ..model,
        coordinates: coordinate_model(model.coordinates.scenario_index + 1),
        notice: "loaded next coordinate scenario",
      }
    ApplyCoordinateEdit => {
      let before = model.coordinates.applied_edits
      let coordinates = model.coordinates.apply_next()
      {
        ..model,
        coordinates,
        notice: if coordinates.applied_edits == before {
          "coordinate scenario has no remaining edits"
        } else {
          "mapped one internal edit into public coordinates"
        },
      }
    }
    RecordIntegration(integration) =>
      {
        ..model,
        integration: Some(integration),
        notice: if integration.passed {
          "real Markdown integration matrix passed"
        } else {
          "real Markdown integration matrix exposed a mismatch"
        },
      }
    Mount =>
      {
        ..model,
        lifecycle: model.lifecycle.mount(),
        notice: "mount transition requested",
      }
    Unmount =>
      {
        ..model,
        lifecycle: model.lifecycle.unmount(),
        notice: "unmount transition requested",
      }
    ToggleUnmountFailure =>
      {
        ..model,
        lifecycle: {
          ..model.lifecycle,
          fail_next_unmount: !model.lifecycle.fail_next_unmount,
          last_event: "toggled the next-unmount failure injection",
        },
        notice: "failure injection toggled",
      }
    ApplyDocumentEdit =>
      {
        ..model,
        lifecycle: model.lifecycle.apply_edit(),
        notice: "document edit requested",
      }
  }
}
