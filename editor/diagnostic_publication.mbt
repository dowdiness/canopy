///|
/// Host-only identity for a diagnostic producer. It is intentionally distinct
/// from both source and display-channel identity.
priv struct DiagnosticProducerId(String) derive(Eq, Hash)

///|
#warnings("-unused_value")
fn DiagnosticProducerId::new(value : String) -> DiagnosticProducerId {
  DiagnosticProducerId(value)
}

///|
fn DiagnosticProducerId::to_string(self : DiagnosticProducerId) -> String {
  let DiagnosticProducerId(value) = self
  value
}

///|
priv struct DiagnosticSourceId(String) derive(Eq, Hash)

///|
#warnings("-unused_value")
fn DiagnosticSourceId::new(value : String) -> DiagnosticSourceId {
  DiagnosticSourceId(value)
}

///|
priv struct DiagnosticDependencyId(String) derive(Eq, Hash)

///|
#warnings("-unused_value")
fn DiagnosticDependencyId::new(value : String) -> DiagnosticDependencyId {
  DiagnosticDependencyId(value)
}

///|
priv struct DiagnosticConfigurationId(String) derive(Eq)

///|
#warnings("-unused_value")
fn DiagnosticConfigurationId::new(value : String) -> DiagnosticConfigurationId {
  DiagnosticConfigurationId(value)
}

///|
priv struct DiagnosticPublicationChannel {
  producer : DiagnosticProducerId
  name : String
} derive(Eq, Hash)

///|
#warnings("-unused_value")
fn DiagnosticPublicationChannel::new(
  producer : DiagnosticProducerId,
  name : String,
) -> DiagnosticPublicationChannel {
  { producer, name }
}

///|
fn DiagnosticPublicationChannel::compare(
  self : DiagnosticPublicationChannel,
  other : DiagnosticPublicationChannel,
) -> Int {
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
  revision : Int
}

///|
#warnings("-unused_value")
fn DiagnosticSourceRevision::new(
  source : DiagnosticSourceId,
  revision : Int,
) -> DiagnosticSourceRevision {
  { source, revision }
}

///|
priv struct DiagnosticDependencyRevision {
  dependency : DiagnosticDependencyId
  identity : String
}

///|
#warnings("-unused_value")
fn DiagnosticDependencyRevision::new(
  dependency : DiagnosticDependencyId,
  identity : String,
) -> DiagnosticDependencyRevision {
  { dependency, identity }
}

///|
/// Opaque host-issued capability. Producers only receive and return it.
priv struct DiagnosticPublicationTicket(Int) derive(Eq, Hash)

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
  generation : Int
  sources : Array[DiagnosticSourceRevision]
  dependencies : Array[DiagnosticDependencyRevision]
  configuration : DiagnosticConfigurationId
}

///|
/// Private functional-core state for publication provenance and accepted sets.
priv struct DiagnosticPublicationState {
  next_ticket : Int
  sources : Map[DiagnosticSourceId, Int]
  dependencies : Map[DiagnosticDependencyId, String]
  configuration : DiagnosticConfigurationId
  generations : Map[DiagnosticProducerId, Int]
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
    sources: Map::default(),
    dependencies: Map::default(),
    configuration,
    generations: Map::default(),
    active: Map::default(),
    requests: Map::default(),
    consumed: Set::default(),
    publications: Map::default(),
  }
}

///|
fn DiagnosticPublicationState::replace(
  self : DiagnosticPublicationState,
  next_ticket? : Int = self.next_ticket,
  sources? : Map[DiagnosticSourceId, Int] = self.sources,
  dependencies? : Map[DiagnosticDependencyId, String] = self.dependencies,
  configuration? : DiagnosticConfigurationId = self.configuration,
  generations? : Map[DiagnosticProducerId, Int] = self.generations,
  active? : Map[DiagnosticPublicationChannel, DiagnosticPublicationTicket] = self.active,
  requests? : Map[DiagnosticPublicationTicket, DiagnosticPublicationRequest] = self.requests,
  consumed? : Set[DiagnosticPublicationTicket] = self.consumed,
  publications? : Map[DiagnosticPublicationChannel, @loom_core.DiagnosticSet] = self.publications,
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
  revision : Int,
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
      consumed.add(ticket)
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
