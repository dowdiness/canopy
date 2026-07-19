///|
priv enum ScenarioCheckpoint {
  GraphOperations
  RequestPersistence
  CompleteTranscript
} derive(Debug)

///|
impl @quickcheck.Arbitrary for ScenarioCheckpoint with fn arbitrary(_size, rs) {
  match rs.split().next_positive_int() % 3 {
    0 => GraphOperations
    1 => RequestPersistence
    _ => CompleteTranscript
  }
}

///|
impl @qc.Shrink for ScenarioCheckpoint with fn shrink(checkpoint) {
  match checkpoint {
    GraphOperations => [].iter()
    RequestPersistence => [GraphOperations].iter()
    CompleteTranscript => [RequestPersistence].iter()
  }
}

///|
priv enum ScenarioNodeRef {
  Existing(String)
  New(String)
} derive(Eq)

///|
fn ScenarioNodeRef::label(self : ScenarioNodeRef) -> String {
  match self {
    Existing(id) | New(id) => id
  }
}

///|
priv enum ScenarioPlacement {
  AtEnd
} derive(Eq)

///|
fn ScenarioPlacement::label(self : ScenarioPlacement) -> String {
  let AtEnd = self
  "end"
}

///|
priv enum ScenarioValue {
  Null
} derive(Eq)

///|
fn ScenarioValue::label(self : ScenarioValue) -> String {
  let Null = self
  "null"
}

///|
priv enum ScenarioOperation {
  InsertNode(
    handle~ : String,
    component~ : String,
    properties~ : Array[(String, ScenarioValue)],
    parent~ : ScenarioNodeRef,
    placement~ : ScenarioPlacement
  )
  MoveNode(
    node~ : ScenarioNodeRef,
    parent~ : ScenarioNodeRef,
    placement~ : ScenarioPlacement
  )
  SetProperty(node~ : ScenarioNodeRef, key~ : String, value~ : ScenarioValue)
  RemoveProperty(node~ : ScenarioNodeRef, key~ : String)
  RemoveNode(ScenarioNodeRef)
} derive(Eq)

///|
fn ScenarioOperation::label(self : ScenarioOperation) -> String {
  match self {
    InsertNode(handle~, component~, properties=_, parent~, placement~) =>
      "insert \{handle} \{component} at \{parent.label()} \{placement.label()}"
    MoveNode(node~, parent~, placement~) =>
      "move \{node.label()} into \{parent.label()} \{placement.label()}"
    SetProperty(node~, key~, value~) =>
      "set \{node.label()}.\{key} to \{value.label()}"
    RemoveProperty(node~, key~) => "remove \{node.label()}.\{key}"
    RemoveNode(node) => "remove \{node.label()}"
  }
}

///|
priv enum FakeShellEvent {
  OpenDocument
  EditDraft(bytes~ : Bytes, revision~ : Int, valid~ : Bool)
  SubmitAgentRequest(request_id~ : String, base_revision~ : Int)
  StoreCommit(request_id~ : String)
  LoseResponse(request_id~ : String)
  RetryRequest(request_id~ : String)
  DeliverSourceEffect(effect_id~ : String)
  CrashBeforeSourceOutcome(effect_id~ : String)
  RecoverDocument
  RedeliverSourceEffect(effect_id~ : String)
  StoreBlockedSourceOutcome(effect_id~ : String)
  DeliverRendererEffect(effect_id~ : String)
  RendererDeliveryFailed(effect_id~ : String)
  StoreRendererDirtyOutcome(effect_id~ : String)
  DeliverStaleRendererEffect(effect_id~ : String)
  RendererRebuildSucceeded(effect_id~ : String)
  CrashBeforeRendererOutcome(effect_id~ : String)
  RedeliverStaleRendererEffect(effect_id~ : String)
  StoreRebuiltRendererOutcome(effect_id~ : String)
  DeliverDuplicateRendererEffect(effect_id~ : String)
  StoreDuplicateRendererOutcome(effect_id~ : String)
} derive(Eq)

///|
fn FakeShellEvent::label(self : FakeShellEvent) -> String {
  match self {
    OpenDocument => "open document"
    EditDraft(..) => "edit draft to invalid bytes"
    SubmitAgentRequest(request_id~, ..) => "submit agent request \{request_id}"
    StoreCommit(request_id~) => "store commit \{request_id}"
    LoseResponse(request_id~) => "lose response \{request_id}"
    RetryRequest(request_id~) => "retry request \{request_id}"
    DeliverSourceEffect(effect_id~) => "deliver source effect \{effect_id}"
    CrashBeforeSourceOutcome(_) => "crash before source outcome"
    RecoverDocument => "recover document"
    RedeliverSourceEffect(effect_id~) => "redeliver source effect \{effect_id}"
    StoreBlockedSourceOutcome(_) => "store blocked source outcome"
    DeliverRendererEffect(effect_id~) => "deliver renderer effect \{effect_id}"
    RendererDeliveryFailed(effect_id~) => "renderer delivery \{effect_id} fails"
    StoreRendererDirtyOutcome(_) => "store renderer dirty outcome"
    DeliverStaleRendererEffect(effect_id~) =>
      "deliver stale renderer effect \{effect_id}"
    RendererRebuildSucceeded(_) => "renderer rebuild succeeds"
    CrashBeforeRendererOutcome(_) => "crash before renderer outcome"
    RedeliverStaleRendererEffect(effect_id~) =>
      "redeliver stale renderer effect \{effect_id}"
    StoreRebuiltRendererOutcome(_) => "store rebuilt renderer outcome"
    DeliverDuplicateRendererEffect(effect_id~) =>
      "deliver duplicate renderer effect \{effect_id}"
    StoreDuplicateRendererOutcome(_) => "store duplicate renderer outcome"
  }
}

///|
priv enum ScenarioObservation {
  DocumentOpened(
    draft_revision~ : Int,
    draft_bytes~ : Bytes,
    graph_digest~ : String,
    graph_revision~ : Int,
    schema_identity~ : String,
    schema_digest~ : String,
    renderer_baseline~ : Int,
    acknowledged_effect~ : String
  )
  DraftChanged(
    draft_revision~ : Int,
    draft_bytes~ : Bytes,
    valid~ : Bool,
    retained_graph_digest~ : String
  )
  CommitPlanned(
    request_id~ : String,
    graph_digest~ : String,
    inserted_node_ids~ : Array[String],
    source_effect_id~ : String,
    renderer_effect_id~ : String
  )
  CommitPersisted(
    request_id~ : String,
    graph_revision~ : Int,
    history_length~ : Int,
    outbox_length~ : Int
  )
  ResponseSuppressed(request_id~ : String)
  RecordedOutcomeReturned(
    request_id~ : String,
    graph_revision~ : Int,
    history_length~ : Int
  )
  PersistSourceBlocked(
    effect_id~ : String,
    reason~ : String,
    preserved_bytes~ : Bytes
  )
  CrashObserved(effect_id~ : String)
  Recovered(
    graph_revision~ : Int,
    pending_effects~ : Array[String],
    renderer_baseline~ : Int,
    renderer_dirty~ : Bool
  )
  SourceBlockedPersisted(effect_id~ : String, preserved_bytes~ : Bytes)
  RendererApplyRequested(effect_id~ : String, graph_revision~ : Int)
  PersistRendererDirty(
    effect_id~ : String,
    renderer_baseline~ : Int,
    graph_revision~ : Int
  )
  RendererDirtyPersisted(renderer_baseline~ : Int, graph_revision~ : Int)
  RebuildLatestRequested(
    delivered_effect_id~ : String,
    graph_digest~ : String,
    graph_revision~ : Int
  )
  PersistRendererRebuilt(
    delivered_effect_id~ : String,
    renderer_baseline~ : Int
  )
  RendererRebuiltPersisted(renderer_baseline~ : Int, renderer_dirty~ : Bool)
  PersistDuplicateRenderer(effect_id~ : String, renderer_baseline~ : Int)
  DuplicateRendererPersisted(renderer_baseline~ : Int, renderer_dirty~ : Bool)
} derive(Eq)

///|
priv struct ScenarioStep {
  event : FakeShellEvent
  expectations : Array[ScenarioObservation]
} derive(Eq)

///|
fn ScenarioStep::ScenarioStep(
  event~ : FakeShellEvent,
  expectations~ : Array[ScenarioObservation],
) -> ScenarioStep {
  { event, expectations }
}

///|
fn ScenarioStep::event(self : ScenarioStep) -> FakeShellEvent {
  self.event
}

///|
fn ScenarioStep::expectations(
  self : ScenarioStep,
) -> ArrayView[ScenarioObservation] {
  self.expectations.view()
}

///|
priv struct ScenarioFinalExpectation {
  graph_digest : String
  graph_revision : Int
  schema_identity : String
  schema_digest : String
  applied_history_length : Int
  terminal_request_count : Int
  inserted_node_ids : Array[String]
  draft_bytes : Bytes
  renderer_baseline : Int
  renderer_dirty : Bool
} derive(Eq)

///|
fn ScenarioFinalExpectation::ScenarioFinalExpectation(
  graph_digest~ : String,
  graph_revision~ : Int,
  schema_identity~ : String,
  schema_digest~ : String,
  applied_history_length~ : Int,
  terminal_request_count~ : Int,
  inserted_node_ids~ : Array[String],
  draft_bytes~ : Bytes,
  renderer_baseline~ : Int,
  renderer_dirty~ : Bool,
) -> ScenarioFinalExpectation {
  {
    graph_digest,
    graph_revision,
    schema_identity,
    schema_digest,
    applied_history_length,
    terminal_request_count,
    inserted_node_ids,
    draft_bytes,
    renderer_baseline,
    renderer_dirty,
  }
}

///|
priv struct FixedScenario {
  invalid_draft_bytes : Bytes
  request_batch : Array[ScenarioOperation]
  steps : Array[ScenarioStep]
  final_expectation : ScenarioFinalExpectation
}

///|
fn FixedScenario::FixedScenario(
  invalid_draft_bytes~ : Bytes,
  request_batch~ : Array[ScenarioOperation],
  steps~ : Array[ScenarioStep],
  final_expectation~ : ScenarioFinalExpectation,
) -> FixedScenario {
  { invalid_draft_bytes, request_batch, steps, final_expectation }
}

///|
fn FixedScenario::invalid_draft_bytes(self : FixedScenario) -> BytesView {
  self.invalid_draft_bytes.view()
}

///|
fn FixedScenario::request_batch(
  self : FixedScenario,
) -> ArrayView[ScenarioOperation] {
  self.request_batch.view()
}

///|
fn FixedScenario::steps(self : FixedScenario) -> ArrayView[ScenarioStep] {
  self.steps.view()
}

///|
fn FixedScenario::prefix(
  self : FixedScenario,
  checkpoint : ScenarioCheckpoint,
) -> ArrayView[ScenarioStep] {
  match checkpoint {
    GraphOperations => self.steps.view(end=3)
    RequestPersistence => self.steps.view(end=6)
    CompleteTranscript => self.steps.view()
  }
}

///|
fn FixedScenario::final_expectation(
  self : FixedScenario,
) -> ScenarioFinalExpectation {
  self.final_expectation
}

///|
fn fixed_request_batch() -> Array[ScenarioOperation] {
  [
    InsertNode(
      handle="h0",
      component="panel",
      properties=[],
      parent=Existing("root"),
      placement=AtEnd,
    ),
    InsertNode(
      handle="h1",
      component="text",
      properties=[],
      parent=Existing("root"),
      placement=AtEnd,
    ),
    SetProperty(node=New("h0"), key="note", value=Null),
    MoveNode(node=New("h1"), parent=New("h0"), placement=AtEnd),
    RemoveProperty(node=New("h0"), key="note"),
    RemoveNode(New("h1")),
  ]
}

///|
fn fixed_transcript_steps(invalid_draft_bytes : Bytes) -> Array[ScenarioStep] {
  [
    ScenarioStep(event=OpenDocument, expectations=[
      DocumentOpened(
        draft_revision=0,
        draft_bytes=b"valid",
        graph_digest="graph:G0",
        graph_revision=0,
        schema_identity="schema:ui-v1",
        schema_digest="schema-digest:ui-v1",
        renderer_baseline=0,
        acknowledged_effect="E-render-0",
      ),
    ]),
    ScenarioStep(
      event=EditDraft(bytes=invalid_draft_bytes, revision=1, valid=false),
      expectations=[
        DraftChanged(
          draft_revision=1,
          draft_bytes=invalid_draft_bytes,
          valid=false,
          retained_graph_digest="graph:G0",
        ),
      ],
    ),
    ScenarioStep(event=SubmitAgentRequest(request_id="Q", base_revision=0), expectations=[
      CommitPlanned(
        request_id="Q",
        graph_digest="graph:G1",
        inserted_node_ids=["node:Q:0", "node:Q:1"],
        source_effect_id="E-source-1",
        renderer_effect_id="E-render-1",
      ),
    ]),
    ScenarioStep(event=StoreCommit(request_id="Q"), expectations=[
      CommitPersisted(
        request_id="Q",
        graph_revision=1,
        history_length=1,
        outbox_length=2,
      ),
    ]),
    ScenarioStep(event=LoseResponse(request_id="Q"), expectations=[
      ResponseSuppressed(request_id="Q"),
    ]),
    ScenarioStep(event=RetryRequest(request_id="Q"), expectations=[
      RecordedOutcomeReturned(
        request_id="Q",
        graph_revision=1,
        history_length=1,
      ),
    ]),
    ScenarioStep(event=DeliverSourceEffect(effect_id="E-source-1"), expectations=[
      PersistSourceBlocked(
        effect_id="E-source-1",
        reason="RewriteConflict",
        preserved_bytes=invalid_draft_bytes,
      ),
    ]),
    ScenarioStep(event=CrashBeforeSourceOutcome(effect_id="E-source-1"), expectations=[
      CrashObserved(effect_id="E-source-1"),
    ]),
    ScenarioStep(event=RecoverDocument, expectations=[
      Recovered(
        graph_revision=1,
        pending_effects=["E-source-1", "E-render-1"],
        renderer_baseline=0,
        renderer_dirty=false,
      ),
    ]),
    ScenarioStep(event=RedeliverSourceEffect(effect_id="E-source-1"), expectations=[
      PersistSourceBlocked(
        effect_id="E-source-1",
        reason="RewriteConflict",
        preserved_bytes=invalid_draft_bytes,
      ),
    ]),
    ScenarioStep(event=StoreBlockedSourceOutcome(effect_id="E-source-1"), expectations=[
      SourceBlockedPersisted(
        effect_id="E-source-1",
        preserved_bytes=invalid_draft_bytes,
      ),
    ]),
    ScenarioStep(event=DeliverRendererEffect(effect_id="E-render-1"), expectations=[
      RendererApplyRequested(effect_id="E-render-1", graph_revision=1),
    ]),
    ScenarioStep(event=RendererDeliveryFailed(effect_id="E-render-1"), expectations=[
      PersistRendererDirty(
        effect_id="E-render-1",
        renderer_baseline=0,
        graph_revision=1,
      ),
    ]),
    ScenarioStep(event=StoreRendererDirtyOutcome(effect_id="E-render-1"), expectations=[
      RendererDirtyPersisted(renderer_baseline=0, graph_revision=1),
    ]),
    ScenarioStep(event=DeliverStaleRendererEffect(effect_id="E-render-0"), expectations=[
      RebuildLatestRequested(
        delivered_effect_id="E-render-0",
        graph_digest="graph:G1",
        graph_revision=1,
      ),
    ]),
    ScenarioStep(event=RendererRebuildSucceeded(effect_id="E-render-0"), expectations=[
      PersistRendererRebuilt(
        delivered_effect_id="E-render-0",
        renderer_baseline=1,
      ),
    ]),
    ScenarioStep(event=CrashBeforeRendererOutcome(effect_id="E-render-0"), expectations=[
      CrashObserved(effect_id="E-render-0"),
    ]),
    ScenarioStep(event=RecoverDocument, expectations=[
      Recovered(
        graph_revision=1,
        pending_effects=["E-render-0", "E-render-1"],
        renderer_baseline=0,
        renderer_dirty=true,
      ),
    ]),
    ScenarioStep(event=RedeliverStaleRendererEffect(effect_id="E-render-0"), expectations=[
      RebuildLatestRequested(
        delivered_effect_id="E-render-0",
        graph_digest="graph:G1",
        graph_revision=1,
      ),
    ]),
    ScenarioStep(event=RendererRebuildSucceeded(effect_id="E-render-0"), expectations=[
      PersistRendererRebuilt(
        delivered_effect_id="E-render-0",
        renderer_baseline=1,
      ),
    ]),
    ScenarioStep(event=StoreRebuiltRendererOutcome(effect_id="E-render-0"), expectations=[
      RendererRebuiltPersisted(renderer_baseline=1, renderer_dirty=false),
    ]),
    ScenarioStep(event=DeliverDuplicateRendererEffect(effect_id="E-render-1"), expectations=[
      PersistDuplicateRenderer(effect_id="E-render-1", renderer_baseline=1),
    ]),
    ScenarioStep(event=StoreDuplicateRendererOutcome(effect_id="E-render-1"), expectations=[
      DuplicateRendererPersisted(renderer_baseline=1, renderer_dirty=false),
    ]),
  ]
}

///|
fn fixed_scenario() -> FixedScenario {
  let invalid_draft_bytes = b"valid\n<unfinished"
  FixedScenario(
    invalid_draft_bytes~,
    request_batch=fixed_request_batch(),
    steps=fixed_transcript_steps(invalid_draft_bytes),
    final_expectation=ScenarioFinalExpectation(
      graph_digest="graph:G1",
      graph_revision=1,
      schema_identity="schema:ui-v1",
      schema_digest="schema-digest:ui-v1",
      applied_history_length=1,
      terminal_request_count=1,
      inserted_node_ids=["node:Q:0", "node:Q:1"],
      draft_bytes=invalid_draft_bytes,
      renderer_baseline=1,
      renderer_dirty=false,
    ),
  )
}
