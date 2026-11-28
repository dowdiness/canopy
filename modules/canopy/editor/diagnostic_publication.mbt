///|
/// Host-only identity for a diagnostic producer. It is intentionally distinct
/// from both source and display-channel identity.
#derive(Eq, Hash, @debug.Debug)
pub struct DiagnosticProducerId {
  priv value : String
}

///|
pub fn DiagnosticProducerId::DiagnosticProducerId(
  value : String,
) -> DiagnosticProducerId {
  { value, }
}

///|
pub fn DiagnosticProducerId::to_string(self : DiagnosticProducerId) -> String {
  self.value
}

///|
#derive(Eq, Hash)
priv struct DiagnosticSourceId(String)

///|
#warnings("-unused_value")
fn DiagnosticSourceId::new(value : String) -> DiagnosticSourceId {
  DiagnosticSourceId(value)
}

///|
#derive(Eq, Hash, @debug.Debug)
pub struct DiagnosticDependencyId {
  priv value : String
}

///|
pub fn DiagnosticDependencyId::DiagnosticDependencyId(
  value : String,
) -> DiagnosticDependencyId {
  { value, }
}

///|
pub fn DiagnosticDependencyId::to_string(
  self : DiagnosticDependencyId,
) -> String {
  self.value
}

///|
#derive(Eq, @debug.Debug)
pub struct DiagnosticConfigurationId {
  priv value : String
}

///|
pub fn DiagnosticConfigurationId::DiagnosticConfigurationId(
  value : String,
) -> DiagnosticConfigurationId {
  { value, }
}

///|
pub fn DiagnosticConfigurationId::to_string(
  self : DiagnosticConfigurationId,
) -> String {
  self.value
}

///|
#derive(Eq, @debug.Debug)
pub struct DiagnosticProducerGeneration {
  priv value : Int32
}

///|
pub fn DiagnosticProducerGeneration::DiagnosticProducerGeneration(
  value : Int32,
) -> DiagnosticProducerGeneration {
  { value, }
}

///|
pub fn DiagnosticProducerGeneration::to_int(
  self : DiagnosticProducerGeneration,
) -> Int32 {
  self.value
}

///|
#derive(Eq, Hash)
priv struct DiagnosticPublicationChannel {
  producer : DiagnosticProducerId
  name : String
}

///|
#warnings("-unused_value")
fn DiagnosticPublicationChannel::new(
  producer : DiagnosticProducerId,
  name : String,
) -> DiagnosticPublicationChannel {
  { producer, name, }
}

///|
fn DiagnosticPublicationChannel::compare(
  self : DiagnosticPublicationChannel,
  other : DiagnosticPublicationChannel,
) -> Int32 {
  let producer_order = self.producer
    .to_string()
    .compare(other.producer.to_string())
  if producer_order == 0 {
    self.name.compare(other.name)
  } else {
    producer_order
  }
}

///|
priv struct DiagnosticSourceRevision {
  source : DiagnosticSourceId
  revision : Int32
}

///|
#warnings("-unused_value")
fn DiagnosticSourceRevision::new(
  source : DiagnosticSourceId,
  revision : Int32,
) -> DiagnosticSourceRevision {
  { source, revision, }
}

///|
#derive(Eq, @debug.Debug)
pub struct DiagnosticDependencyRevision {
  priv dependency : DiagnosticDependencyId
  priv identity : String
}

///|
pub fn DiagnosticDependencyRevision::DiagnosticDependencyRevision(
  dependency : DiagnosticDependencyId,
  identity : String,
) -> DiagnosticDependencyRevision {
  { dependency, identity, }
}

///|
pub fn DiagnosticDependencyRevision::dependency(
  self : DiagnosticDependencyRevision,
) -> DiagnosticDependencyId {
  self.dependency
}

///|
pub fn DiagnosticDependencyRevision::identity(
  self : DiagnosticDependencyRevision,
) -> String {
  self.identity
}

///|
/// Opaque host-issued capability. Producers only receive and return it.
#derive(Eq, Hash)
priv struct DiagnosticPublicationTicket(Int32)

///|
#warnings("-unused_constructor")
priv enum DiagnosticPublicationDecision {
  Accepted
  Rejected
}

///|
/// Commands are data from the functional core; the shell owns execution.
#warnings("-unused_constructor")
priv enum DiagnosticPublicationCommand {
  Start(DiagnosticPublicationTicket)
  Cancel(DiagnosticPublicationTicket)
}

///|
priv struct DiagnosticPublicationRequest {
  channel : DiagnosticPublicationChannel
  generation : Int32
  sources : Array[DiagnosticSourceRevision]
  dependencies : Array[DiagnosticDependencyRevision]
  configuration : DiagnosticConfigurationId
}

///|
/// Private functional-core state for publication provenance and accepted sets.
priv struct DiagnosticPublicationState {
  next_ticket : Int32
  sources : Map[DiagnosticSourceId, Int32]
  dependencies : Map[DiagnosticDependencyId, String]
  configuration : DiagnosticConfigurationId
  generations : Map[DiagnosticProducerId, Int32]
  active : Map[DiagnosticPublicationChannel, DiagnosticPublicationTicket]
  requests : Map[DiagnosticPublicationTicket, DiagnosticPublicationRequest]
  consumed : Set[DiagnosticPublicationTicket]
  publications : Map[DiagnosticPublicationChannel, @loom_core.DiagnosticSet]
}

///|
#warnings("-unused_value")
fn DiagnosticPublicationState::new(
  configuration : DiagnosticConfigurationId,
) -> DiagnosticPublicationState {
  {
    next_ticket: 0,
    sources: Default::default(),
    dependencies: Default::default(),
    configuration,
    generations: Default::default(),
    active: Default::default(),
    requests: Default::default(),
    consumed: Default::default(),
    publications: Default::default(),
  }
}

///|
fn DiagnosticPublicationState::replace(
  self : DiagnosticPublicationState,
  next_ticket~ : Int32 = self.next_ticket,
  sources~ : Map[DiagnosticSourceId, Int32] = self.sources,
  dependencies~ : Map[DiagnosticDependencyId, String] = self.dependencies,
  configuration~ : DiagnosticConfigurationId = self.configuration,
  generations~ : Map[DiagnosticProducerId, Int32] = self.generations,
  active~ : Map[DiagnosticPublicationChannel, DiagnosticPublicationTicket] = self.active,
  requests~ : Map[DiagnosticPublicationTicket, DiagnosticPublicationRequest] = self.requests,
  consumed~ : Set[DiagnosticPublicationTicket] = self.consumed,
  publications~ : Map[DiagnosticPublicationChannel, @loom_core.DiagnosticSet] = self.publications,
) -> DiagnosticPublicationState {
  {
    next_ticket,
    sources,
    dependencies,
    configuration,
    generations,
    active,
    requests,
    consumed,
    publications,
  }
}

///|
/// The shell supplies its current monotonic source revision through this event.
#warnings("-unused_value")
fn DiagnosticPublicationState::set_source_revision(
  self : DiagnosticPublicationState,
  source : DiagnosticSourceId,
  revision : Int32,
) -> DiagnosticPublicationState {
  let sources = self.sources.copy()
  sources.set(source, revision)
  self.replace(sources~)
}

///|
#warnings("-unused_value")
fn DiagnosticPublicationState::set_dependency_identity(
  self : DiagnosticPublicationState,
  dependency : DiagnosticDependencyId,
  identity : String,
) -> DiagnosticPublicationState {
  let dependencies = self.dependencies.copy()
  dependencies.set(dependency, identity)
  self.replace(dependencies~)
}

///|
#warnings("-unused_value")
fn DiagnosticPublicationState::set_configuration(
  self : DiagnosticPublicationState,
  configuration : DiagnosticConfigurationId,
) -> DiagnosticPublicationState {
  self.replace(configuration~)
}

///|
/// Restart invalidates every older request for this producer by generation.
#warnings("-unused_value")
fn DiagnosticPublicationState::restart_producer(
  self : DiagnosticPublicationState,
  producer : DiagnosticProducerId,
) -> (DiagnosticPublicationState, Array[DiagnosticPublicationCommand]) {
  let generations = self.generations.copy()
  generations.set(producer, generations.get(producer).unwrap_or(0) + 1)
  let active = self.active.copy()
  let affected = self.active
    .to_array()
    .filter(entry => entry.0.producer == producer)
  affected.sort_by((left, right) => left.0.compare(right.0))
  let commands = affected.map(entry => {
    active.remove(entry.0)
    DiagnosticPublicationCommand::Cancel(entry.1)
  })
  (self.replace(generations~, active~), commands)
}

///|
/// Issue a ticket from an already coherent host snapshot. Starting/cancelling
/// work is deferred to the imperative shell through returned commands.
#warnings("-unused_value")
fn DiagnosticPublicationState::issue(
  self : DiagnosticPublicationState,
  channel : DiagnosticPublicationChannel,
  sources : Array[DiagnosticSourceRevision],
  dependencies : Array[DiagnosticDependencyRevision],
) -> (
  DiagnosticPublicationState,
  DiagnosticPublicationTicket,
  Array[DiagnosticPublicationCommand],
) {
  let ticket = DiagnosticPublicationTicket(self.next_ticket)
  let request = {
    channel,
    generation: self.generations.get(channel.producer).unwrap_or(0),
    sources: sources.copy(),
    dependencies: dependencies.copy(),
    configuration: self.configuration,
  }
  let active = self.active.copy()
  let commands = match active.get(channel) {
    Some(previous) => [DiagnosticPublicationCommand::Cancel(previous)]
    None => []
  }
  active.set(channel, ticket)
  let requests = self.requests.copy()
  requests.set(ticket, request)
  let next = self.replace(next_ticket=self.next_ticket + 1, active~, requests~)
  commands.push(DiagnosticPublicationCommand::Start(ticket))
  (next, ticket, commands)
}

///|
#warnings("-unused_value")
fn DiagnosticPublicationState::cancel(
  self : DiagnosticPublicationState,
  ticket : DiagnosticPublicationTicket,
) -> (DiagnosticPublicationState, Array[DiagnosticPublicationCommand]) {
  match self.requests.get(ticket) {
    Some(request) if self.active.get(request.channel) == Some(ticket) => {
      let active = self.active.copy()
      active.remove(request.channel)
      (self.replace(active~), [DiagnosticPublicationCommand::Cancel(ticket)])
    }
    _ => (self, [])
  }
}

///|
fn DiagnosticPublicationState::request_is_current(
  self : DiagnosticPublicationState,
  ticket : DiagnosticPublicationTicket,
  request : DiagnosticPublicationRequest,
) -> Bool {
  self.active.get(request.channel) == Some(ticket) &&
  !self.consumed.contains(ticket) &&
  self.generations.get(request.channel.producer).unwrap_or(0) ==
  request.generation &&
  self.configuration == request.configuration &&
  request.sources.all(snapshot => {
    self.sources.get(snapshot.source) == Some(snapshot.revision)
  }) &&
  request.dependencies.all(snapshot => {
    self.dependencies.get(snapshot.dependency) == Some(snapshot.identity)
  })
}

///|
/// Single deterministic completion decision. Rejection has no published-state
/// effect; acceptance copies and atomically replaces exactly one channel.
#warnings("-unused_value")
fn DiagnosticPublicationState::complete(
  self : DiagnosticPublicationState,
  ticket : DiagnosticPublicationTicket,
  diagnostics : @loom_core.DiagnosticSet,
) -> (DiagnosticPublicationState, DiagnosticPublicationDecision) {
  match self.requests.get(ticket) {
    Some(request) if self.request_is_current(ticket, request) => {
      let active = self.active.copy()
      active.remove(request.channel)
      let consumed = self.consumed.copy()
      consumed.insert(ticket)
      let publications = self.publications.copy()
      publications.set(request.channel, diagnostics.copy())
      (
        self.replace(active~, consumed~, publications~),
        DiagnosticPublicationDecision::Accepted,
      )
    }
    _ => (self, DiagnosticPublicationDecision::Rejected)
  }
}

///|
/// Assemble a fresh diagnostic set: parser first, then stable producer/channel
/// order. Local sorting mutates only a newly returned array.
#warnings("-unused_value")
fn DiagnosticPublicationState::display(
  self : DiagnosticPublicationState,
  parser_channel : DiagnosticPublicationChannel,
) -> @loom_core.DiagnosticSet {
  let merged = match self.publications.get(parser_channel) {
    Some(parser) => parser.copy()
    None => @loom_core.DiagnosticSet::empty()
  }
  let others = self.publications
    .to_array()
    .filter(entry => entry.0 != parser_channel)
  others.sort_by((left, right) => left.0.compare(right.0))
  others.each(entry => merged.add_all(entry.1))
  merged
}

///|
pub extend DiagnosticConfigurationId with @moonbitlang/core/debug.Debug::{
  to_repr,
}

///|
pub extend DiagnosticConfigurationId with Eq::{equal, not_equal}

///|
pub extend DiagnosticDependencyId with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DiagnosticDependencyId with Eq::{equal, not_equal}

///|
pub extend DiagnosticDependencyId with Hash::{hash, hash_combine}

///|
pub extend DiagnosticDependencyRevision with @moonbitlang/core/debug.Debug::{
  to_repr,
}

///|
pub extend DiagnosticDependencyRevision with Eq::{equal, not_equal}

///|
pub extend DiagnosticProducerGeneration with @moonbitlang/core/debug.Debug::{
  to_repr,
}

///|
pub extend DiagnosticProducerGeneration with Eq::{equal, not_equal}

///|
pub extend DiagnosticProducerId with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DiagnosticProducerId with Eq::{equal, not_equal}

///|
pub extend DiagnosticProducerId with Hash::{hash, hash_combine}
