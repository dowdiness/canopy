///|
#warnings("-unused_value-struct_never_constructed-unused_field")
priv struct ProjectionAdapterLimits {
  max_advance_count : Int
  max_encoded_bytes : Int
  max_source_effect_bytes : Int
}

///|
priv struct ProjectionStamp {
  generation : Int
  sequence : Int
  source_revision : Int
  causal_version : String
  block_intent : Int
} derive(Eq, Debug)

///|
#warnings("-unused_value")
priv struct ProjectionDemand {
  block : Bool
  preview : Bool
  diagnostics : Bool
} derive(Eq, Debug)

///|
#warnings("-unused_value-unused_constructor")
priv enum ProjectionSourceEffect {
  ReplaceProjectionSource(String)
  ProjectionSourceUnchanged
} derive(Eq, Debug)

///|
priv enum ProjectionConsistencyGroup {
  Block
  Preview
  Diagnostics
} derive(Eq, Hash, Debug)

///|
priv enum NormalizedBlockKind {
  NormalizedParagraph
  NormalizedHeading(Int)
  NormalizedUnorderedListItem
  NormalizedOrderedListItem(Int, String)
  NormalizedCodeBlock(String)
} derive(Eq, Debug)

///|
priv struct NormalizedBlock {
  key : String
  kind : NormalizedBlockKind
  source_range : (Int, Int)
  text_range : (Int, Int)
  marker_range : (Int, Int)?
  fence_open_range : (Int, Int)?
  fence_close_range : (Int, Int)?
  text : String
} derive(Eq, Debug)

///|
priv struct NormalizedRoleSpan {
  start : Int
  end : Int
  role : String
} derive(Eq, Debug)

///|
priv struct NormalizedResolverEvidence {
  key : String
  source_start : Int
  source_end : Int
} derive(Eq, Debug)

///|
priv struct NormalizedBlockProjection {
  source : String
  blocks : Array[NormalizedBlock]
  node_keys : Array[String]
  roles : Array[NormalizedRoleSpan]
  resolver_evidence : Array[NormalizedResolverEvidence]
} derive(Eq, Debug)

///|
priv struct NormalizedMarkdownNode {
  kind : String
  start : Int
  end : Int
  text : String?
  detail : String
  flags : Int
  children : Array[NormalizedMarkdownNode]
} derive(Eq, Debug)

///|
priv struct NormalizedDiagnosticLabel {
  source : String
  start : Int
  end : Int
  style : String
  message : String?
} derive(Eq, Debug)

///|
priv struct NormalizedDiagnostic {
  origin : String
  severity : String
  message : String
  code : String?
  labels : Array[NormalizedDiagnosticLabel]
  notes : Array[String]
} derive(Eq, Debug)

///|
priv struct NormalizedPreviewProjection {
  source : String
  markdown_ir : NormalizedMarkdownNode
  html : String
} derive(Eq, Debug)

///|
#warnings("-unused_constructor")
priv enum ProjectionArtifact {
  BlockArtifact(NormalizedBlockProjection)
  PreviewArtifact(NormalizedPreviewProjection)
  DiagnosticsArtifact(Array[NormalizedDiagnostic])
} derive(Eq, Debug)

///|
#warnings("-unused_value-struct_never_constructed-unused_field")
priv struct ProjectionWorkResult {
  work_id : Int
  stamp : ProjectionStamp
  group : ProjectionConsistencyGroup
  artifact : ProjectionArtifact
} derive(Eq, Debug)

///|
#warnings("-unused_constructor")
priv enum ProjectionExecutionFailure {
  ProjectionExecutionFailed(String)
  ProjectionExecutorDisposed
  ProjectionExecutorTimeout
  ProjectionDecodeFailed(String)
}

///|
#warnings("-unused_value")
priv enum ProjectionCommandRejection {
  InvalidInitialStamp
  NonContiguousSequence
  InvalidGeneration
  InvalidSourceRevision
  DuplicateCausalVersion
  StaleBlockIntent
  SeedCaptureMismatch
  CounterExhausted
  AdapterDisposed
  DemandStampMismatch
} derive(Eq, Debug)

///|
#warnings("-unused_value")
priv enum ProjectionCallbackRejection {
  UnknownOrTerminalWork
  CallbackStampMismatch
  CallbackGroupMismatch
  PresentationIdInvalid
} derive(Eq, Debug)

///|
#warnings("-unused_value")
priv enum ProjectionRequestDisposition {
  Dispatched
  Queued
  NoDemand
  SeedCaptureRequested
} derive(Eq, Debug)

///|
#warnings("-unused_value-unused_constructor")
priv enum ProjectionRetirementReason {
  DemandRemoved
  PresentationNotObserved
  AdapterDisposedBeforePresentation
} derive(Eq, Debug)

///|
#warnings("-unused_value")
priv enum ProjectionTerminalOutcome {
  Presented(Int)
  AdoptedNotPresented(ProjectionRetirementReason)
  RejectedAtAdoption
  SupersededBeforeExecution
  SupersededAfterExecution
  GenerationInvalidated
  Failed
  Disposed
} derive(Eq, Debug)

///|
#warnings("-unused_constructor")
priv enum ProjectionAdapterInput {
  Seed(ProjectionStamp, String, ProjectionDemand)
  Advance(ProjectionStamp, ProjectionSourceEffect, ProjectionDemand)
  SeedCaptured(ProjectionStamp, String, ProjectionDemand)
  Demand(ProjectionStamp, ProjectionDemand)
  DispatchNextAdvance
  GroupMaterialized(ProjectionWorkResult)
  GroupFailed(
    work_id~ : Int,
    stamp~ : ProjectionStamp,
    group~ : ProjectionConsistencyGroup,
    failure~ : ProjectionExecutionFailure
  )
  GroupsPresented(presentation_id~ : Int, work_ids~ : Array[Int])
  DisposeProjectionAdapter
}

///|
#warnings("-unused_constructor-unused_field")
priv enum ProjectionEffect {
  QueueAdvance(ProjectionStamp)
  CaptureLatestSeed(stamp~ : ProjectionStamp)
  StartGroupWork(
    work_id~ : Int,
    stamp~ : ProjectionStamp,
    group~ : ProjectionConsistencyGroup,
    source~ : String
  )
  CancelObsoleteWork(work_id~ : Int, group~ : ProjectionConsistencyGroup)
  AdoptArtifact(
    work_id~ : Int,
    stamp~ : ProjectionStamp,
    group~ : ProjectionConsistencyGroup,
    artifact~ : ProjectionArtifact
  )
  PresentArtifact(
    presentation_id~ : Int,
    work_id~ : Int,
    group~ : ProjectionConsistencyGroup
  )
  RecordRequestDisposition(ProjectionRequestDisposition)
  RecordTerminalOutcome(
    work_id~ : Int,
    group~ : ProjectionConsistencyGroup,
    outcome~ : ProjectionTerminalOutcome
  )
  RejectCommand(ProjectionCommandRejection)
  RejectCallback(ProjectionCallbackRejection)
  ReportGroupFailure(
    work_id~ : Int,
    group~ : ProjectionConsistencyGroup,
    failure~ : ProjectionExecutionFailure
  )
}

///|
priv struct QueuedProjectionAdvance {
  stamp : ProjectionStamp
  effect : ProjectionSourceEffect
  demand : ProjectionDemand
  encoded_bytes : Int
  source_effect_bytes : Int
}

///|
priv struct PendingSeedCapture {
  allocated : ProjectionStamp
  source_revision : Int
  causal_version : String
  block_intent : Int
  demand : ProjectionDemand
}

///|
priv struct PendingProjectionWork {
  work_id : Int
  stamp : ProjectionStamp
  group : ProjectionConsistencyGroup
}

///|
#warnings("-unused_field")
priv struct AdoptedProjectionWork {
  work_id : Int
  stamp : ProjectionStamp
  group : ProjectionConsistencyGroup
  artifact : ProjectionArtifact
}

///|
priv struct ProjectionGroupState {
  pending : PendingProjectionWork?
  adopted : AdoptedProjectionWork?
  retained : ProjectionArtifact?
}

///|
fn empty_projection_group_state() -> ProjectionGroupState {
  { pending: None, adopted: None, retained: None }
}

///|
#warnings("-unused_value")
priv struct ProjectionAdapter {
  limits : ProjectionAdapterLimits
  last_sequence : Int
  current_stamp : ProjectionStamp?
  current_source : String?
  demand : ProjectionDemand
  queue : Array[QueuedProjectionAdvance]
  queued_encoded : Int
  queued_source_effect : Int
  pending_seed : PendingSeedCapture?
  next_work_id : Int
  block_state : ProjectionGroupState
  preview_state : ProjectionGroupState
  diagnostics_state : ProjectionGroupState
  disposed : Bool
}

///|
#warnings("-unused_value")
fn ProjectionAdapter::ProjectionAdapter(
  limits : ProjectionAdapterLimits,
) -> ProjectionAdapter {
  {
    limits,
    last_sequence: 0,
    current_stamp: None,
    current_source: None,
    demand: { block: false, preview: false, diagnostics: false },
    queue: [],
    queued_encoded: 0,
    queued_source_effect: 0,
    pending_seed: None,
    next_work_id: 1,
    block_state: empty_projection_group_state(),
    preview_state: empty_projection_group_state(),
    diagnostics_state: empty_projection_group_state(),
    disposed: false,
  }
}

///|
#warnings("-unused_value")
fn ProjectionAdapter::generation(self : Self) -> Int {
  match self.current_stamp {
    Some(stamp) => stamp.generation
    None => 0
  }
}

///|
#warnings("-unused_value")
fn ProjectionAdapter::sequence(self : Self) -> Int {
  self.last_sequence
}

///|
#warnings("-unused_value")
fn ProjectionAdapter::source_revision(self : Self) -> Int {
  match self.current_stamp {
    Some(stamp) => stamp.source_revision
    None => 0
  }
}

///|
#warnings("-unused_value")
fn ProjectionAdapter::current_source(self : Self) -> String? {
  self.current_source
}

///|
#warnings("-unused_value")
fn ProjectionAdapter::queued_advance_count(self : Self) -> Int {
  self.queue.length()
}

///|
#warnings("-unused_value")
fn ProjectionAdapter::queued_encoded_bytes(self : Self) -> Int {
  self.queued_encoded
}

///|
#warnings("-unused_value")
fn ProjectionAdapter::queued_source_effect_bytes(self : Self) -> Int {
  self.queued_source_effect
}

///|
#warnings("-unused_value")
fn ProjectionAdapter::pending_seed_stamp(self : Self) -> ProjectionStamp? {
  self.pending_seed.map(capture => capture.allocated)
}

///|
#warnings("-unused_value")
fn ProjectionAdapter::pending_seed_source_revision(self : Self) -> Int? {
  self.pending_seed.map(capture => capture.source_revision)
}

///|
fn ProjectionDemand::for_group(
  self : Self,
  group : ProjectionConsistencyGroup,
) -> Bool {
  match group {
    Block => self.block
    Preview => self.preview
    Diagnostics => self.diagnostics
  }
}

///|
fn ProjectionAdapter::group_state(
  self : Self,
  group : ProjectionConsistencyGroup,
) -> ProjectionGroupState {
  match group {
    Block => self.block_state
    Preview => self.preview_state
    Diagnostics => self.diagnostics_state
  }
}

///|
fn ProjectionAdapter::with_group_state(
  self : Self,
  group : ProjectionConsistencyGroup,
  state : ProjectionGroupState,
) -> Self {
  match group {
    Block => { ..self, block_state: state }
    Preview => { ..self, preview_state: state }
    Diagnostics => { ..self, diagnostics_state: state }
  }
}

///|
#warnings("-unused_value")
fn ProjectionAdapter::has_pending_group(
  self : Self,
  group : ProjectionConsistencyGroup,
) -> Bool {
  self.group_state(group).pending is Some(_)
}

///|
fn projection_groups() -> Array[ProjectionConsistencyGroup] {
  [Block, Preview, Diagnostics]
}

///|
fn checked_next(value : Int) -> Int? {
  if value < 0 || value == 2147483647 {
    None
  } else {
    Some(value + 1)
  }
}

///|
fn projection_source_effect_json(effect : ProjectionSourceEffect) -> Json {
  match effect {
    ReplaceProjectionSource(source) =>
      Json::object({
        "kind": Json::string("replace-source"),
        "source": Json::string(source),
      })
    ProjectionSourceUnchanged =>
      Json::object({ "kind": Json::string("source-unchanged") })
  }
}

///|
fn source_effect_bytes(effect : ProjectionSourceEffect) -> Int {
  @utf8.encode(projection_source_effect_json(effect).stringify()).length()
}

///|
fn advance_encoded_bytes(
  stamp : ProjectionStamp,
  effect : ProjectionSourceEffect,
) -> Int {
  let encoded = Json::object({
    "generation": Json::number(stamp.generation.to_double()),
    "sequence": Json::number(stamp.sequence.to_double()),
    "source_revision": Json::number(stamp.source_revision.to_double()),
    "causal_version": Json::string(stamp.causal_version),
    "block_intent": Json::number(stamp.block_intent.to_double()),
    "source_effect": projection_source_effect_json(effect),
  }).stringify()
  @utf8.encode(encoded).length()
}

///|
fn drop_first_advance(
  queue : Array[QueuedProjectionAdvance],
) -> Array[QueuedProjectionAdvance] {
  let rest : Array[QueuedProjectionAdvance] = []
  for index = 1; index < queue.length(); index = index + 1 {
    rest.push(queue[index])
  }
  rest
}

///|
fn ProjectionAdapter::admission_stamp(self : Self) -> ProjectionStamp? {
  if self.queue.is_empty() {
    self.current_stamp
  } else {
    Some(self.queue[self.queue.length() - 1].stamp)
  }
}

///|
fn ProjectionAdapter::retire_group(
  self : Self,
  group : ProjectionConsistencyGroup,
  pending_outcome : ProjectionTerminalOutcome,
  adopted_outcome : ProjectionTerminalOutcome,
  cancel : Bool,
  effects : Array[ProjectionEffect],
) -> Self {
  let state = self.group_state(group)
  match state.pending {
    Some(work) => {
      if cancel {
        effects.push(CancelObsoleteWork(work_id=work.work_id, group~))
      }
      effects.push(
        RecordTerminalOutcome(
          work_id=work.work_id,
          group~,
          outcome=pending_outcome,
        ),
      )
    }
    None => ()
  }
  match state.adopted {
    Some(work) =>
      effects.push(
        RecordTerminalOutcome(
          work_id=work.work_id,
          group~,
          outcome=adopted_outcome,
        ),
      )
    None => ()
  }
  self.with_group_state(group, empty_projection_group_state())
}

///|
fn ProjectionAdapter::retire_all_groups(
  self : Self,
  outcome : ProjectionTerminalOutcome,
  effects : Array[ProjectionEffect],
) -> Self {
  let mut next = self
  for group in projection_groups() {
    next = next.retire_group(group, outcome, outcome, true, effects)
  }
  next
}

///|
fn ProjectionAdapter::start_demanded_groups(
  self : Self,
  stamp : ProjectionStamp,
  source : String,
  demand : ProjectionDemand,
  reuse : Map[ProjectionConsistencyGroup, ProjectionArtifact]?,
  effects : Array[ProjectionEffect],
) -> Self {
  let mut next = self
  let mut issued = false
  let demanded_count = projection_groups().fold(init=0, (count, group) => {
    if demand.for_group(group) {
      count + 1
    } else {
      count
    }
  })
  guard next.next_work_id > 0 &&
    demanded_count <= 2147483647 - next.next_work_id else {
    effects.push(RejectCommand(CounterExhausted))
    return self
  }
  for group in projection_groups() {
    guard demand.for_group(group) else { continue }
    issued = true
    let work_id = next.next_work_id
    next = { ..next, next_work_id: work_id + 1 }
    let reused = reuse.bind(values => values.get(group))
    match reused {
      Some(artifact) => {
        effects.push(AdoptArtifact(work_id~, stamp~, group~, artifact~))
        next = next.with_group_state(group, {
          pending: None,
          adopted: Some({ work_id, stamp, group, artifact }),
          retained: None,
        })
      }
      None => {
        effects.push(StartGroupWork(work_id~, stamp~, group~, source~))
        next = next.with_group_state(group, {
          pending: Some({ work_id, stamp, group }),
          adopted: None,
          retained: None,
        })
      }
    }
  }
  if !issued {
    effects.push(RecordRequestDisposition(NoDemand))
  }
  next
}

///|
fn ProjectionAdapter::adopted_artifacts(
  self : Self,
) -> Map[ProjectionConsistencyGroup, ProjectionArtifact] {
  let artifacts : Map[ProjectionConsistencyGroup, ProjectionArtifact] = Map([])
  for group in projection_groups() {
    let state = self.group_state(group)
    match state.adopted {
      Some(work) => artifacts[group] = work.artifact
      None =>
        match state.retained {
          Some(artifact) => artifacts[group] = artifact
          None => ()
        }
    }
  }
  artifacts
}

///|
fn ProjectionAdapter::install_seed(
  self : Self,
  stamp : ProjectionStamp,
  source : String,
  demand : ProjectionDemand,
  effects : Array[ProjectionEffect],
) -> Self {
  let next = self.retire_all_groups(GenerationInvalidated, effects)
  let next = {
    ..next,
    last_sequence: stamp.sequence,
    current_stamp: Some(stamp),
    current_source: Some(source),
    demand,
    queue: [],
    queued_encoded: 0,
    queued_source_effect: 0,
    pending_seed: None,
  }
  effects.push(RecordRequestDisposition(Dispatched))
  next.start_demanded_groups(stamp, source, demand, None, effects)
}

///|
fn ProjectionAdapter::request_seed_capture(
  self : Self,
  latest : ProjectionStamp,
  demand : ProjectionDemand,
  effects : Array[ProjectionEffect],
) -> Self {
  match self.pending_seed {
    Some(capture) => {
      let pending_seed = Some({
        ..capture,
        source_revision: latest.source_revision,
        causal_version: latest.causal_version,
        block_intent: latest.block_intent,
        demand,
      })
      {
        ..self,
        queue: [],
        queued_encoded: 0,
        queued_source_effect: 0,
        pending_seed,
      }
    }
    None => {
      guard checked_next(self.last_sequence) is Some(sequence) else {
        effects.push(RejectCommand(CounterExhausted))
        return self
      }
      let current_generation = match self.current_stamp {
        Some(stamp) => stamp.generation
        None => 0
      }
      guard checked_next(current_generation) is Some(generation) else {
        effects.push(RejectCommand(CounterExhausted))
        return self
      }
      let allocated = {
        generation,
        sequence,
        source_revision: latest.source_revision,
        causal_version: latest.causal_version,
        block_intent: latest.block_intent,
      }
      effects.push(CaptureLatestSeed(stamp=allocated))
      effects.push(RecordRequestDisposition(SeedCaptureRequested))
      {
        ..self,
        queue: [],
        queued_encoded: 0,
        queued_source_effect: 0,
        pending_seed: Some({
          allocated,
          source_revision: latest.source_revision,
          causal_version: latest.causal_version,
          block_intent: latest.block_intent,
          demand,
        }),
      }
    }
  }
}

///|
fn ProjectionAdapter::reduce_seed(
  self : Self,
  stamp : ProjectionStamp,
  source : String,
  demand : ProjectionDemand,
  effects : Array[ProjectionEffect],
) -> Self {
  guard checked_next(self.last_sequence) is Some(expected_sequence) else {
    effects.push(RejectCommand(CounterExhausted))
    return self
  }
  let valid_generation = match self.current_stamp {
    None => stamp.generation > 0
    Some(current) =>
      match checked_next(current.generation) {
        Some(value) => stamp.generation == value
        None => {
          effects.push(RejectCommand(CounterExhausted))
          return self
        }
      }
  }
  guard stamp.sequence == expected_sequence else {
    effects.push(RejectCommand(NonContiguousSequence))
    return self
  }
  guard valid_generation && stamp.source_revision >= 0 else {
    effects.push(RejectCommand(InvalidInitialStamp))
    return self
  }
  self.install_seed(stamp, source, demand, effects)
}

///|
fn ProjectionAdapter::reduce_advance(
  self : Self,
  stamp : ProjectionStamp,
  effect : ProjectionSourceEffect,
  demand : ProjectionDemand,
  effects : Array[ProjectionEffect],
) -> Self {
  match self.pending_seed {
    Some(_) => return self.request_seed_capture(stamp, demand, effects)
    None => ()
  }
  guard self.admission_stamp() is Some(current) else {
    effects.push(RejectCommand(InvalidInitialStamp))
    return self
  }
  guard stamp.generation == current.generation else {
    effects.push(RejectCommand(InvalidGeneration))
    return self
  }
  guard checked_next(self.last_sequence) is Some(expected_sequence) else {
    effects.push(RejectCommand(CounterExhausted))
    return self
  }
  if stamp.sequence != expected_sequence {
    return self.request_seed_capture(stamp, demand, effects)
  }
  guard stamp.causal_version != current.causal_version else {
    effects.push(RejectCommand(DuplicateCausalVersion))
    return self
  }
  guard stamp.block_intent >= current.block_intent else {
    effects.push(RejectCommand(StaleBlockIntent))
    return self
  }
  let valid_source_revision = match effect {
    ProjectionSourceUnchanged =>
      stamp.source_revision == current.source_revision
    ReplaceProjectionSource(_) =>
      stamp.source_revision > current.source_revision
  }
  guard valid_source_revision else {
    effects.push(RejectCommand(InvalidSourceRevision))
    return self
  }
  let encoded_bytes = advance_encoded_bytes(stamp, effect)
  let effect_bytes = source_effect_bytes(effect)
  let exceeds = self.queue.length() + 1 > self.limits.max_advance_count ||
    self.queued_encoded + encoded_bytes > self.limits.max_encoded_bytes ||
    self.queued_source_effect + effect_bytes >
    self.limits.max_source_effect_bytes
  if exceeds {
    return self.request_seed_capture(stamp, demand, effects)
  }
  let queue = self.queue.copy()
  queue.push({
    stamp,
    effect,
    demand,
    encoded_bytes,
    source_effect_bytes: effect_bytes,
  })
  effects.push(QueueAdvance(stamp))
  effects.push(RecordRequestDisposition(Queued))
  {
    ..self,
    last_sequence: stamp.sequence,
    queue,
    queued_encoded: self.queued_encoded + encoded_bytes,
    queued_source_effect: self.queued_source_effect + effect_bytes,
  }
}

///|
fn ProjectionAdapter::dispatch_next(
  self : Self,
  effects : Array[ProjectionEffect],
) -> Self {
  guard !self.queue.is_empty() else { return self }
  let advance = self.queue[0]
  let queue = drop_first_advance(self.queue)
  let source = match advance.effect {
    ReplaceProjectionSource(source) => source
    ProjectionSourceUnchanged => self.current_source.unwrap_or("")
  }
  let reused = if advance.effect is ProjectionSourceUnchanged {
    Some(self.adopted_artifacts())
  } else {
    None
  }
  let mut next = {
    ..self,
    queue,
    queued_encoded: self.queued_encoded - advance.encoded_bytes,
    queued_source_effect: self.queued_source_effect -
    advance.source_effect_bytes,
    current_stamp: Some(advance.stamp),
    current_source: Some(source),
    demand: advance.demand,
  }
  for group in projection_groups() {
    next = next.retire_group(
      group,
      SupersededBeforeExecution,
      SupersededAfterExecution,
      true,
      effects,
    )
  }
  effects.push(RecordRequestDisposition(Dispatched))
  next.start_demanded_groups(
    advance.stamp,
    source,
    advance.demand,
    reused,
    effects,
  )
}

///|
fn ProjectionAdapter::reduce_demand(
  self : Self,
  stamp : ProjectionStamp,
  demand : ProjectionDemand,
  effects : Array[ProjectionEffect],
) -> Self {
  let expected = match self.pending_seed {
    Some(capture) =>
      Some({
        ..capture.allocated,
        source_revision: capture.source_revision,
        causal_version: capture.causal_version,
        block_intent: capture.block_intent,
      })
    None => self.current_stamp
  }
  guard expected == Some(stamp) else {
    effects.push(RejectCommand(DemandStampMismatch))
    return self
  }
  if self.demand == demand {
    return self
  }
  let mut next = { ..self, demand, }
  let source = next.current_source.unwrap_or("")
  for group in projection_groups() {
    let was = self.demand.for_group(group)
    let now = demand.for_group(group)
    if was && !now {
      next = next.retire_group(
        group,
        SupersededBeforeExecution,
        AdoptedNotPresented(DemandRemoved),
        true,
        effects,
      )
    } else if !was && now && self.pending_seed is None {
      let single : ProjectionDemand = match group {
        Block => { block: true, preview: false, diagnostics: false }
        Preview => { block: false, preview: true, diagnostics: false }
        Diagnostics => { block: false, preview: false, diagnostics: true }
      }
      next = next.start_demanded_groups(stamp, source, single, None, effects)
    }
  }
  next
}

///|
fn ProjectionAdapter::reduce_materialized(
  self : Self,
  result : ProjectionWorkResult,
  effects : Array[ProjectionEffect],
) -> Self {
  let state = self.group_state(result.group)
  guard state.pending is Some(pending) else {
    effects.push(RejectCallback(UnknownOrTerminalWork))
    return self
  }
  guard pending.work_id == result.work_id else {
    effects.push(RejectCallback(UnknownOrTerminalWork))
    return self
  }
  guard pending.group == result.group else {
    effects.push(RejectCallback(CallbackGroupMismatch))
    return self
  }
  guard pending.stamp == result.stamp &&
    self.current_stamp == Some(result.stamp) else {
    effects.push(
      RecordTerminalOutcome(
        work_id=result.work_id,
        group=result.group,
        outcome=RejectedAtAdoption,
      ),
    )
    effects.push(RejectCallback(CallbackStampMismatch))
    return self.with_group_state(result.group, empty_projection_group_state())
  }
  guard self.demand.for_group(result.group) else {
    effects.push(
      RecordTerminalOutcome(
        work_id=result.work_id,
        group=result.group,
        outcome=RejectedAtAdoption,
      ),
    )
    return self.with_group_state(result.group, empty_projection_group_state())
  }
  effects.push(
    AdoptArtifact(
      work_id=result.work_id,
      stamp=result.stamp,
      group=result.group,
      artifact=result.artifact,
    ),
  )
  self.with_group_state(result.group, {
    pending: None,
    adopted: Some({
      work_id: result.work_id,
      stamp: result.stamp,
      group: result.group,
      artifact: result.artifact,
    }),
    retained: state.retained,
  })
}

///|
fn ProjectionAdapter::reduce_failed(
  self : Self,
  work_id : Int,
  stamp : ProjectionStamp,
  group : ProjectionConsistencyGroup,
  failure : ProjectionExecutionFailure,
  effects : Array[ProjectionEffect],
) -> Self {
  let state = self.group_state(group)
  guard state.pending is Some(pending) &&
    pending.work_id == work_id &&
    pending.stamp == stamp else {
    effects.push(RejectCallback(UnknownOrTerminalWork))
    return self
  }
  effects.push(ReportGroupFailure(work_id~, group~, failure~))
  effects.push(RecordTerminalOutcome(work_id~, group~, outcome=Failed))
  self.with_group_state(group, empty_projection_group_state())
}

///|
fn ProjectionAdapter::reduce_presented(
  self : Self,
  presentation_id : Int,
  work_ids : Array[Int],
  effects : Array[ProjectionEffect],
) -> Self {
  guard presentation_id > 0 else {
    effects.push(RejectCallback(PresentationIdInvalid))
    return self
  }
  let mut next = self
  for work_id in work_ids {
    let mut found = false
    for group in projection_groups() {
      let state = next.group_state(group)
      match state.adopted {
        Some(adopted) if adopted.work_id == work_id => {
          found = true
          effects.push(PresentArtifact(presentation_id~, work_id~, group~))
          effects.push(
            RecordTerminalOutcome(
              work_id~,
              group~,
              outcome=Presented(presentation_id),
            ),
          )
          next = next.with_group_state(group, {
            pending: None,
            adopted: None,
            retained: Some(adopted.artifact),
          })
        }
        _ => ()
      }
    }
    if !found {
      effects.push(RejectCallback(UnknownOrTerminalWork))
    }
  }
  next
}

///|
#warnings("-unused_value")
fn ProjectionAdapter::reduce(
  self : Self,
  input : ProjectionAdapterInput,
) -> (Self, Array[ProjectionEffect]) {
  let effects : Array[ProjectionEffect] = []
  if self.disposed {
    match input {
      GroupMaterialized(_) | GroupFailed(..) | GroupsPresented(..) =>
        effects.push(RejectCallback(UnknownOrTerminalWork))
      _ => effects.push(RejectCommand(AdapterDisposed))
    }
    return (self, effects)
  }
  let next = match input {
    Seed(stamp, source, demand) =>
      self.reduce_seed(stamp, source, demand, effects)
    Advance(stamp, effect, demand) =>
      self.reduce_advance(stamp, effect, demand, effects)
    SeedCaptured(stamp, source, demand) => {
      guard self.pending_seed is Some(capture) else {
        effects.push(RejectCommand(SeedCaptureMismatch))
        self
      }
      let expected = {
        ..capture.allocated,
        source_revision: capture.source_revision,
        causal_version: capture.causal_version,
        block_intent: capture.block_intent,
      }
      if stamp != expected || demand != capture.demand {
        effects.push(RejectCommand(SeedCaptureMismatch))
        self
      } else {
        self.install_seed(stamp, source, demand, effects)
      }
    }
    Demand(stamp, demand) => self.reduce_demand(stamp, demand, effects)
    DispatchNextAdvance => self.dispatch_next(effects)
    GroupMaterialized(result) => self.reduce_materialized(result, effects)
    GroupFailed(work_id~, stamp~, group~, failure~) =>
      self.reduce_failed(work_id, stamp, group, failure, effects)
    GroupsPresented(presentation_id~, work_ids~) =>
      self.reduce_presented(presentation_id, work_ids, effects)
    DisposeProjectionAdapter => {
      let next = self.retire_all_groups(Disposed, effects)
      {
        ..next,
        queue: [],
        queued_encoded: 0,
        queued_source_effect: 0,
        pending_seed: None,
        disposed: true,
      }
    }
  }
  (next, effects)
}

///|
#warnings("-unused_value")
priv struct NormalizedProjectionObservables {
  block : NormalizedBlockProjection
  preview : NormalizedPreviewProjection
  diagnostics : Array[NormalizedDiagnostic]
} derive(Eq, Debug)

///|
fn normalize_block_kind(
  kind : @markdown.MarkdownBlockKind,
) -> NormalizedBlockKind {
  match kind {
    @markdown.Paragraph => NormalizedParagraph
    @markdown.Heading(level~) => NormalizedHeading(level)
    @markdown.UnorderedListItem => NormalizedUnorderedListItem
    @markdown.OrderedListItem(start~, delimiter~) =>
      NormalizedOrderedListItem(start, delimiter)
    @markdown.CodeBlock(info~) => NormalizedCodeBlock(info)
  }
}

///|
fn normalize_markdown_role(role : @md_markdown.MarkdownRole) -> String {
  match role {
    @md_markdown.HeadingMarker => "heading-marker"
    @md_markdown.HeadingText => "heading-text"
    @md_markdown.ListMarker => "list-marker"
    @md_markdown.ListContent => "list-content"
    @md_markdown.CodeFenceDelimiter => "code-fence-delimiter"
    @md_markdown.CodeFenceContent => "code-fence-content"
    @md_markdown.InlineCodeDelimiter => "inline-code-delimiter"
    @md_markdown.InlineCodeContent => "inline-code-content"
    @md_markdown.EmphasisDelimiter => "emphasis-delimiter"
    @md_markdown.EmphasisContent => "emphasis-content"
    @md_markdown.LinkText => "link-text"
    @md_markdown.LinkDestination => "link-destination"
    @md_markdown.Punctuation => "punctuation"
    @md_markdown.Error => "error"
  }
}

///|
fn normalize_markdown_node(
  node : @md_markdown.MarkdownIR,
) -> NormalizedMarkdownNode {
  let origin = node.origin()
  {
    kind: node.kind_tag(),
    start: origin.start(),
    end: origin.end(),
    text: node.text_value(),
    detail: "",
    flags: (if node.is_raw() { 1 } else { 0 }) +
    (if node.is_recovered() { 2 } else { 0 }) +
    (if node.is_unsupported() { 4 } else { 0 }),
    children: node.children().map(normalize_markdown_node),
  }
}

///|
fn normalize_diagnostic_severity(
  severity : @diagnostic.DiagnosticSeverity,
) -> String {
  match severity {
    @diagnostic.Error => "error"
    @diagnostic.Warning => "warning"
    @diagnostic.Info => "info"
    @diagnostic.Hint => "hint"
  }
}

///|
fn normalize_label_style(style : @diagnostic.LabelStyle) -> String {
  match style {
    @diagnostic.Primary => "primary"
    @diagnostic.Secondary => "secondary"
  }
}

///|
fn normalize_diagnostic(
  diagnostic : @diagnostic.Diagnostic,
) -> NormalizedDiagnostic {
  {
    origin: diagnostic.origin().name(),
    severity: normalize_diagnostic_severity(diagnostic.severity()),
    message: diagnostic.message(),
    code: diagnostic.code().map(code => code.value()),
    labels: diagnostic
    .labels()
    .map(label => {
      let span = label.span()
      let range = span.range()
      {
        source: span.source_id().value(),
        start: range.start().value(),
        end: range.end().value(),
        style: normalize_label_style(label.style()),
        message: label.message(),
      }
    }),
    notes: diagnostic.notes(),
  }
}

///|
fn normalized_projection_node_key(
  raw_node_keys : Array[String],
  raw_key : String,
  fallback_index : Int,
) -> String {
  for index, candidate in raw_node_keys {
    if candidate == raw_key {
      return "node-" + index.to_string()
    }
  }
  "unresolved-" + fallback_index.to_string()
}

///|
fn normalized_projection_observables(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
) -> NormalizedProjectionObservables raise {
  let snapshot = editor.snapshot()
  let source = snapshot.source()
  let raw_node_keys : Array[String] = []
  let node_keys : Array[String] = []
  let mut node_index = 0
  for node in snapshot.projection().node_ids() {
    raw_node_keys.push(node.key())
    node_keys.push("node-" + node_index.to_string())
    node_index += 1
  }
  let blocks : Array[NormalizedBlock] = []
  let mut block_index = 0
  for block in snapshot.blocks() {
    blocks.push({
      key: normalized_projection_node_key(
        raw_node_keys,
        block.key(),
        block_index,
      ),
      kind: normalize_block_kind(block.kind()),
      source_range: block.source_range(),
      text_range: block.text_range(),
      marker_range: block.marker_range(),
      fence_open_range: block.fence_open_range(),
      fence_close_range: block.fence_close_range(),
      text: block.text(),
    })
    block_index += 1
  }
  let parser = @loom.new_parser(
    @loom.SourceId("projection-observable"),
    source,
    @md_markdown.markdown_grammar,
  )
  let parser_snapshot = parser.snapshot().read_or_abort()
  let roles = @md_markdown.project_markdown_roles(parser_snapshot.syntax).map(role => {
    start: role.start(),
    end: role.end(),
    role: normalize_markdown_role(role.role()),
  })
  let resolver_evidence = blocks.map(block => {
    key: block.key,
    source_start: block.source_range.0,
    source_end: block.source_range.1,
  })
  let document = attachment.document()
  {
    block: { source, blocks, node_keys, roles, resolver_evidence },
    preview: {
      source,
      markdown_ir: normalize_markdown_node(document),
      html: @md_markdown.experimental_markdown_ir_to_commonmark_html(document),
    },
    diagnostics: document.diagnostics().map(normalize_diagnostic),
  }
}

///|
fn normalized_protocol_observables(
  artifacts : Map[ProjectionConsistencyGroup, ProjectionArtifact],
) -> NormalizedProjectionObservables raise Failure {
  match
    (artifacts.get(Block), artifacts.get(Preview), artifacts.get(Diagnostics)) {
    (
      Some(BlockArtifact(block)),
      Some(PreviewArtifact(preview)),
      Some(DiagnosticsArtifact(diagnostics)),
    ) => { block, preview, diagnostics }
    _ => raise Failure::Failure("incomplete projection protocol artifacts")
  }
}

///|
#warnings("-unused_value")
priv struct ProjectionSession {
  editor : @markdown.MarkdownEditor
  attachment : @md_markdown.MarkdownSemanticAttachment
  mut adapter : ProjectionAdapter
  mut source : String
  mut sequence : Int
  mut causal_counter : Int
  mut generation : Int
  mut source_revision : Int
  mut block_intent : Int
  mut presentation_id : Int
  mut demand : ProjectionDemand
  mut disposed : Bool
}

///|
fn projection_all_demand() -> ProjectionDemand {
  { block: true, preview: true, diagnostics: true }
}

///|
fn ProjectionSession::ProjectionSession(
  agent_id~ : String,
  source~ : String,
  generation? : Int = 1,
  demand? : ProjectionDemand = projection_all_demand(),
) -> ProjectionSession raise {
  let (editor, attachment) = @markdown.MarkdownEditor::with_semantic_attachment(
    agent_id~,
    source~,
  )
  let session = {
    editor,
    attachment,
    adapter: ProjectionAdapter::ProjectionAdapter({
      max_advance_count: 64,
      max_encoded_bytes: 1048576,
      max_source_effect_bytes: 1048576,
    }),
    source,
    sequence: 1,
    causal_counter: 1,
    generation,
    source_revision: 1,
    block_intent: 1,
    presentation_id: 1,
    demand,
    disposed: false,
  }
  let stamp = session.stamp()
  let (adapter, effects) = session.adapter.reduce(Seed(stamp, source, demand))
  session.adapter = adapter
  session.execute_effects(effects)
  session
}

///|
fn ProjectionSession::stamp(self : Self) -> ProjectionStamp {
  {
    generation: self.generation,
    sequence: self.sequence,
    source_revision: self.source_revision,
    causal_version: "projection-session-" + self.causal_counter.to_string(),
    block_intent: self.block_intent,
  }
}

///|
fn projection_effects_adopt_work(
  effects : Array[ProjectionEffect],
  expected_work_id : Int,
) -> Bool {
  effects.any(effect => {
    match effect {
      AdoptArtifact(work_id~, ..) => work_id == expected_work_id
      _ => false
    }
  })
}

///|
fn ProjectionSession::execute_effects(
  self : Self,
  effects : Array[ProjectionEffect],
) -> Unit raise {
  let adopted_work_ids : Array[Int] = []
  let materialized_effects : Array[ProjectionEffect] = []
  let needs_materialization = effects.any(effect => {
    match effect {
      StartGroupWork(work_id~, ..) =>
        !projection_effects_adopt_work(effects, work_id)
      _ => false
    }
  })
  let observables = if needs_materialization {
    Some(normalized_projection_observables(self.editor, self.attachment))
  } else {
    None
  }
  for effect in effects {
    match effect {
      StartGroupWork(work_id~, stamp~, group~, ..) =>
        if !projection_effects_adopt_work(effects, work_id) {
          let values = observables.unwrap()
          let artifact = match group {
            Block => BlockArtifact(values.block)
            Preview => PreviewArtifact(values.preview)
            Diagnostics => DiagnosticsArtifact(values.diagnostics)
          }
          let result : ProjectionWorkResult = {
            work_id,
            stamp,
            group,
            artifact,
          }
          let (adapter, next) = self.adapter.reduce(GroupMaterialized(result))
          self.adapter = adapter
          for next_effect in next {
            materialized_effects.push(next_effect)
          }
        }
      AdoptArtifact(work_id~, ..) => adopted_work_ids.push(work_id)
      QueueAdvance(_) => {
        let (adapter, next) = self.adapter.reduce(DispatchNextAdvance)
        self.adapter = adapter
        self.execute_effects(next)
      }
      CaptureLatestSeed(stamp~) => {
        let (adapter, next) = self.adapter.reduce(
          SeedCaptured(stamp, self.source, self.demand),
        )
        self.adapter = adapter
        self.generation = stamp.generation
        self.sequence = stamp.sequence
        self.source_revision = stamp.source_revision
        self.block_intent = stamp.block_intent
        self.execute_effects(next)
      }
      _ => ()
    }
  }
  if !materialized_effects.is_empty() {
    self.execute_effects(materialized_effects)
  }
  if !adopted_work_ids.is_empty() {
    let presentation_id = self.presentation_id
    self.presentation_id += 1
    let (adapter, next) = self.adapter.reduce(
      GroupsPresented(presentation_id~, work_ids=adopted_work_ids),
    )
    self.adapter = adapter
    self.execute_effects(next)
  }
}

///|
#warnings("-unused_value")
fn ProjectionSession::demand(
  self : Self,
  demand : ProjectionDemand,
) -> Unit raise {
  guard !self.disposed else {
    raise Failure::Failure("projection session disposed")
  }
  let (adapter, effects) = self.adapter.reduce(Demand(self.stamp(), demand))
  self.adapter = adapter
  self.demand = demand
  self.execute_effects(effects)
}

///|
fn ProjectionSession::preview_document(
  self : Self,
) -> @md_markdown.MarkdownIR? raise {
  guard !self.disposed else {
    raise Failure::Failure("projection session disposed")
  }
  let state = self.adapter.group_state(Preview)
  guard state.adopted is Some(_) || state.retained is Some(_) else {
    return None
  }
  Some(self.attachment.document())
}

///|
#warnings("-unused_value")
fn ProjectionSession::advance(
  self : Self,
  effect : ProjectionSourceEffect,
) -> Unit raise {
  guard !self.disposed else {
    raise Failure::Failure("projection session disposed")
  }
  match effect {
    ProjectionSourceUnchanged => ()
    ReplaceProjectionSource(source) => {
      let result = self.editor.commit(
        @markdown.MarkdownEditRequest::ReplaceSource(source),
      )
      match result {
        Ok(_) => ()
        Err(error) => raise error
      }
      self.source = source
      self.source_revision += 1
      self.block_intent += 1
    }
  }
  self.sequence += 1
  self.causal_counter += 1
  let (adapter, effects) = self.adapter.reduce(
    Advance(self.stamp(), effect, self.demand),
  )
  self.adapter = adapter
  self.execute_effects(effects)
}

///|
fn ProjectionSession::normalized_observables(
  self : Self,
) -> NormalizedProjectionObservables raise {
  guard !self.disposed else {
    raise Failure::Failure("projection session disposed")
  }
  normalized_projection_observables(self.editor, self.attachment)
}

///|
#warnings("-unused_value")
fn ProjectionSession::normalized_protocol_observables(
  self : Self,
) -> NormalizedProjectionObservables raise {
  guard !self.disposed else {
    raise Failure::Failure("projection session disposed")
  }
  normalized_protocol_observables(self.adapter.adopted_artifacts())
}

///|
fn ProjectionSession::dispose(self : Self) -> Unit {
  if !self.disposed {
    let (adapter, _) = self.adapter.reduce(DisposeProjectionAdapter)
    self.adapter = adapter
    self.attachment.dispose()
    self.disposed = true
  }
}

///|
#warnings("-unused_value")
fn fresh_projection_observables(
  source : String,
  agent_id~ : String,
) -> NormalizedProjectionObservables raise {
  let session = ProjectionSession::ProjectionSession(agent_id~, source~)
  defer session.dispose()
  session.normalized_observables()
}
