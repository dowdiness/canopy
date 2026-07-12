///|
/// Identity allocated by one generative-UI lifecycle.
pub struct GenerativeUiGenerationId(Int) derive(Debug, Eq, Hash, Compare)

///|
pub fn GenerativeUiGenerationId::to_int(self : GenerativeUiGenerationId) -> Int {
  let GenerativeUiGenerationId(value) = self
  value
}

///|
/// Revision selected by the host as the base for one candidate generation.
///
/// This is intentionally separate from provider revisions and from the JSX
/// session's implementation details. An adapter may map it to either of
/// those at a later boundary.
pub struct GenerativeUiRevision(Int) derive(Debug, Eq, Hash, Compare)

///|
pub fn GenerativeUiRevision::new(value : Int) -> GenerativeUiRevision {
  GenerativeUiRevision(value)
}

///|
pub fn GenerativeUiRevision::to_int(self : GenerativeUiRevision) -> Int {
  let GenerativeUiRevision(value) = self
  value
}

///|
fn GenerativeUiRevision::next(
  self : GenerativeUiRevision,
) -> GenerativeUiRevision {
  GenerativeUiRevision(self.to_int() + 1)
}

///|
/// The kind of input carried by a generation envelope.
pub(all) enum GenerativeUiInputKind {
  Chunk
  Final
  Cancel
} derive(Debug, Eq)

///|
/// Provider-independent input envelope. Every event carries the generation
/// identity, selected base revision, and sequence number, including cancel.
pub struct GenerativeUiInput {
  priv generation_id : GenerativeUiGenerationId
  priv base_revision : GenerativeUiRevision
  priv sequence : Int
  priv payload : String
  priv kind : GenerativeUiInputKind
} derive(Debug, Eq)

///|
pub fn GenerativeUiInput::chunk(
  generation_id~ : GenerativeUiGenerationId,
  base_revision~ : GenerativeUiRevision,
  sequence~ : Int,
  payload~ : String,
) -> GenerativeUiInput {
  { generation_id, base_revision, sequence, payload, kind: Chunk }
}

///|
pub fn GenerativeUiInput::finalize(
  generation_id~ : GenerativeUiGenerationId,
  base_revision~ : GenerativeUiRevision,
  sequence~ : Int,
) -> GenerativeUiInput {
  { generation_id, base_revision, sequence, payload: "", kind: Final }
}

///|
pub fn GenerativeUiInput::cancel(
  generation_id~ : GenerativeUiGenerationId,
  base_revision~ : GenerativeUiRevision,
  sequence~ : Int,
) -> GenerativeUiInput {
  { generation_id, base_revision, sequence, payload: "", kind: Cancel }
}

///|
/// Lifecycle phase. Payload and diagnostics are available through the
/// lifecycle accessors so the phase itself remains easy to inspect.
pub(all) enum GenerativeUiPhase {
  Idle
  Receiving
  Validating
  DryRunning
  Applying
  Committed
  Rejected
  Cancelled
  Failed
} derive(Debug, Eq)

///|
/// Structured reasons for a candidate or input being rejected.
pub(all) enum GenerativeUiRejection {
  InvalidSequence(sequence~ : Int)
  SequenceGap(expected~ : Int, received~ : Int)
  ConflictingDuplicate(sequence~ : Int)
  UnexpectedFinalPayload
  BaseRevisionMismatch(
    expected~ : GenerativeUiRevision,
    received~ : GenerativeUiRevision
  )
  InvalidCandidate(message~ : String)
  DryRunFailed(message~ : String)
  ApplyFailed(message~ : String)
  ApplyRevisionMismatch(
    expected~ : GenerativeUiRevision,
    received~ : GenerativeUiRevision
  )
} derive(Debug, Eq)

///|
/// Why an event was ignored without changing the current lifecycle.
pub(all) enum GenerativeUiIgnoreReason {
  StaleGeneration
  TerminalState
  EventNotAcceptedInPhase
  CancellationTooLate
} derive(Debug, Eq)

///|
/// Observable result of one pure lifecycle transition.
pub(all) enum GenerativeUiTransition {
  Started(generation_id~ : GenerativeUiGenerationId)
  ChunkAccepted(sequence~ : Int)
  DuplicateChunk(sequence~ : Int)
  Finalized
  ValidationStarted
  DryRunStarted
  ApplyStarted
  Committed(revision~ : GenerativeUiRevision)
  Cancelled
  Rejected(reason~ : GenerativeUiRejection)
  Failed(reason~ : GenerativeUiRejection)
  Ignored(reason~ : GenerativeUiIgnoreReason)
} derive(Debug, Eq)

///|
/// Pure request/generation lifecycle state. It owns ordering and terminal
/// semantics, but no transport, parser, renderer, or DOM state.
pub struct GenerativeUiLifecycle {
  priv mut phase : GenerativeUiPhase
  priv mut next_generation_id : Int
  priv mut generation_id : GenerativeUiGenerationId?
  priv mut base_revision : GenerativeUiRevision?
  priv mut next_sequence : Int
  priv chunks : Array[String]
  priv mut rejection : GenerativeUiRejection?
  priv mut committed_revision : GenerativeUiRevision?
}

///|
pub fn GenerativeUiLifecycle::new() -> GenerativeUiLifecycle {
  {
    phase: Idle,
    next_generation_id: 1,
    generation_id: None,
    base_revision: None,
    next_sequence: 0,
    chunks: [],
    rejection: None,
    committed_revision: None,
  }
}

///|
pub fn GenerativeUiLifecycle::phase(
  self : GenerativeUiLifecycle,
) -> GenerativeUiPhase {
  self.phase
}

///|
pub fn GenerativeUiLifecycle::generation_id(
  self : GenerativeUiLifecycle,
) -> GenerativeUiGenerationId? {
  self.generation_id
}

///|
pub fn GenerativeUiLifecycle::base_revision(
  self : GenerativeUiLifecycle,
) -> GenerativeUiRevision? {
  self.base_revision
}

///|
pub fn GenerativeUiLifecycle::next_sequence(
  self : GenerativeUiLifecycle,
) -> Int {
  self.next_sequence
}

///|
pub fn GenerativeUiLifecycle::candidate_source(
  self : GenerativeUiLifecycle,
) -> String {
  self.chunks.join("")
}

///|
pub fn GenerativeUiLifecycle::rejection(
  self : GenerativeUiLifecycle,
) -> GenerativeUiRejection? {
  self.rejection
}

///|
pub fn GenerativeUiLifecycle::committed_revision(
  self : GenerativeUiLifecycle,
) -> GenerativeUiRevision? {
  self.committed_revision
}

///|
/// Start another generation without replacing the session-owned lifecycle.
/// The caller must provide the explicitly selected base revision. Keeping the
/// lifecycle preserves the generation counter, so late events from the prior
/// terminal generation remain distinguishable from the restart.
pub fn GenerativeUiLifecycle::restart(
  self : GenerativeUiLifecycle,
  base_revision : GenerativeUiRevision,
) -> GenerativeUiTransition {
  if !self.is_terminal() {
    return self.ignore_for_phase()
  }
  self.phase = Idle
  self.start(base_revision)
}

///|
/// Advance the lifecycle by one domain event. The method is deliberately
/// side-effect free beyond updating this in-memory state machine.
pub fn GenerativeUiLifecycle::dispatch(
  self : GenerativeUiLifecycle,
  event : GenerativeUiEvent,
) -> GenerativeUiTransition {
  match event {
    Start(base_revision~) => self.start(base_revision)
    Input(input) => self.accept_input(input)
    CandidateValid(generation_id~, current_revision~) =>
      self.accept_valid_candidate(generation_id, current_revision)
    CandidateInvalid(generation_id~, message~) =>
      self.reject_candidate(generation_id, message)
    DryRunSucceeded(generation_id~) => self.accept_dry_run(generation_id)
    DryRunFailed(generation_id~, message~) =>
      self.reject_dry_run(generation_id, message)
    ApplySucceeded(generation_id~, revision~) =>
      self.accept_apply(generation_id, revision)
    ApplyFailed(generation_id~, message~) =>
      self.fail_apply(generation_id, message)
  }
}

///|
pub(all) enum GenerativeUiEvent {
  Start(base_revision~ : GenerativeUiRevision)
  Input(GenerativeUiInput)
  CandidateValid(
    generation_id~ : GenerativeUiGenerationId,
    current_revision~ : GenerativeUiRevision
  )
  CandidateInvalid(generation_id~ : GenerativeUiGenerationId, message~ : String)
  DryRunSucceeded(generation_id~ : GenerativeUiGenerationId)
  DryRunFailed(generation_id~ : GenerativeUiGenerationId, message~ : String)
  ApplySucceeded(
    generation_id~ : GenerativeUiGenerationId,
    revision~ : GenerativeUiRevision
  )
  ApplyFailed(generation_id~ : GenerativeUiGenerationId, message~ : String)
} derive(Debug, Eq)

///|
fn GenerativeUiLifecycle::start(
  self : GenerativeUiLifecycle,
  base_revision : GenerativeUiRevision,
) -> GenerativeUiTransition {
  if self.phase != Idle {
    return self.ignore_for_phase()
  }
  let generation_id = GenerativeUiGenerationId(self.next_generation_id)
  self.next_generation_id += 1
  self.phase = Receiving
  self.generation_id = Some(generation_id)
  self.base_revision = Some(base_revision)
  self.next_sequence = 0
  self.chunks.clear()
  self.rejection = None
  self.committed_revision = None
  Started(generation_id~)
}

///|
fn GenerativeUiLifecycle::accept_input(
  self : GenerativeUiLifecycle,
  input : GenerativeUiInput,
) -> GenerativeUiTransition {
  if self.phase == Applying && input.kind == Cancel {
    return Ignored(reason=CancellationTooLate)
  }
  if self.phase == Committed ||
    self.phase == Rejected ||
    self.phase == Cancelled ||
    self.phase == Failed {
    return Ignored(reason=TerminalState)
  }
  match (self.generation_id, self.base_revision) {
    (Some(expected_generation), Some(expected_revision)) => {
      if input.generation_id != expected_generation ||
        input.base_revision != expected_revision {
        return Ignored(reason=StaleGeneration)
      }
      match input.kind {
        Cancel => self.cancel_generation()
        Chunk => self.accept_chunk(input.sequence, input.payload)
        Final => self.accept_final(input.sequence, input.payload)
      }
    }
    _ => Ignored(reason=EventNotAcceptedInPhase)
  }
}

///|
fn GenerativeUiLifecycle::accept_chunk(
  self : GenerativeUiLifecycle,
  sequence : Int,
  payload : String,
) -> GenerativeUiTransition {
  if self.phase != Receiving {
    return Ignored(reason=EventNotAcceptedInPhase)
  }
  if sequence < 0 {
    return self.reject(InvalidSequence(sequence~))
  }
  if sequence < self.next_sequence {
    match self.chunks.get(sequence) {
      Some(previous) if previous == payload => return DuplicateChunk(sequence~)
      _ => return self.reject(ConflictingDuplicate(sequence~))
    }
  }
  if sequence > self.next_sequence {
    return self.reject(
      SequenceGap(expected=self.next_sequence, received=sequence),
    )
  }
  self.chunks.push(payload)
  self.next_sequence += 1
  ChunkAccepted(sequence~)
}

///|
fn GenerativeUiLifecycle::accept_final(
  self : GenerativeUiLifecycle,
  sequence : Int,
  payload : String,
) -> GenerativeUiTransition {
  if self.phase != Receiving {
    return Ignored(reason=EventNotAcceptedInPhase)
  }
  if !payload.is_empty() {
    return self.reject(UnexpectedFinalPayload)
  }
  if sequence != self.next_sequence {
    return self.reject(
      SequenceGap(expected=self.next_sequence, received=sequence),
    )
  }
  self.phase = Validating
  Finalized
}

///|
fn GenerativeUiLifecycle::cancel_generation(
  self : GenerativeUiLifecycle,
) -> GenerativeUiTransition {
  if self.phase == Applying {
    return Ignored(reason=CancellationTooLate)
  }
  if self.phase != Receiving &&
    self.phase != Validating &&
    self.phase != DryRunning {
    return Ignored(reason=EventNotAcceptedInPhase)
  }
  self.phase = Cancelled
  Cancelled
}

///|
fn GenerativeUiLifecycle::accept_valid_candidate(
  self : GenerativeUiLifecycle,
  generation_id : GenerativeUiGenerationId,
  current_revision : GenerativeUiRevision,
) -> GenerativeUiTransition {
  if self.phase != Validating {
    return self.ignore_for_phase()
  }
  if !self.is_current_generation(generation_id) {
    return Ignored(reason=StaleGeneration)
  }
  let expected_revision = self.base_revision.unwrap()
  if current_revision != expected_revision {
    return self.reject(
      BaseRevisionMismatch(
        expected=expected_revision,
        received=current_revision,
      ),
    )
  }
  self.phase = DryRunning
  DryRunStarted
}

///|
fn GenerativeUiLifecycle::reject_candidate(
  self : GenerativeUiLifecycle,
  generation_id : GenerativeUiGenerationId,
  message : String,
) -> GenerativeUiTransition {
  if self.phase != Validating {
    return self.ignore_for_phase()
  }
  if !self.is_current_generation(generation_id) {
    return Ignored(reason=StaleGeneration)
  }
  self.reject(InvalidCandidate(message~))
}

///|
fn GenerativeUiLifecycle::accept_dry_run(
  self : GenerativeUiLifecycle,
  generation_id : GenerativeUiGenerationId,
) -> GenerativeUiTransition {
  if self.phase != DryRunning {
    return self.ignore_for_phase()
  }
  if !self.is_current_generation(generation_id) {
    return Ignored(reason=StaleGeneration)
  }
  self.phase = Applying
  ApplyStarted
}

///|
fn GenerativeUiLifecycle::reject_dry_run(
  self : GenerativeUiLifecycle,
  generation_id : GenerativeUiGenerationId,
  message : String,
) -> GenerativeUiTransition {
  if self.phase != DryRunning {
    return self.ignore_for_phase()
  }
  if !self.is_current_generation(generation_id) {
    return Ignored(reason=StaleGeneration)
  }
  self.reject(DryRunFailed(message~))
}

///|
fn GenerativeUiLifecycle::accept_apply(
  self : GenerativeUiLifecycle,
  generation_id : GenerativeUiGenerationId,
  committed_revision : GenerativeUiRevision,
) -> GenerativeUiTransition {
  if self.phase != Applying {
    return self.ignore_for_phase()
  }
  if !self.is_current_generation(generation_id) {
    return Ignored(reason=StaleGeneration)
  }
  let expected_revision = self.base_revision.unwrap().next()
  if committed_revision != expected_revision {
    return self.fail_apply_revision(expected_revision, committed_revision)
  }
  self.phase = Committed
  self.committed_revision = Some(committed_revision)
  Committed(revision=committed_revision)
}

///|
fn GenerativeUiLifecycle::fail_apply(
  self : GenerativeUiLifecycle,
  generation_id : GenerativeUiGenerationId,
  message : String,
) -> GenerativeUiTransition {
  if self.phase != Applying {
    return self.ignore_for_phase()
  }
  if !self.is_current_generation(generation_id) {
    return Ignored(reason=StaleGeneration)
  }
  self.rejection = Some(ApplyFailed(message~))
  self.phase = Failed
  Failed(reason=ApplyFailed(message~))
}

///|
fn GenerativeUiLifecycle::fail_apply_revision(
  self : GenerativeUiLifecycle,
  expected : GenerativeUiRevision,
  received : GenerativeUiRevision,
) -> GenerativeUiTransition {
  let reason = ApplyRevisionMismatch(expected~, received~)
  self.rejection = Some(reason)
  self.phase = Failed
  Failed(reason~)
}

///|
fn GenerativeUiLifecycle::reject(
  self : GenerativeUiLifecycle,
  reason : GenerativeUiRejection,
) -> GenerativeUiTransition {
  self.rejection = Some(reason)
  self.phase = Rejected
  Rejected(reason~)
}

///|
fn GenerativeUiLifecycle::ignore_for_phase(
  self : GenerativeUiLifecycle,
) -> GenerativeUiTransition {
  if self.phase == Committed ||
    self.phase == Rejected ||
    self.phase == Cancelled ||
    self.phase == Failed {
    Ignored(reason=TerminalState)
  } else {
    Ignored(reason=EventNotAcceptedInPhase)
  }
}

///|
fn GenerativeUiLifecycle::is_terminal(self : GenerativeUiLifecycle) -> Bool {
  self.phase == Committed ||
  self.phase == Rejected ||
  self.phase == Cancelled ||
  self.phase == Failed
}

///|
fn GenerativeUiLifecycle::is_current_generation(
  self : GenerativeUiLifecycle,
  generation_id : GenerativeUiGenerationId,
) -> Bool {
  self.generation_id == Some(generation_id)
}
