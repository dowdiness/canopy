///|
pub(all) enum AccountResult {
  SignedOut
  Resolved(@source_repository.AccountId, String)
  AccountUnavailable
}

///|
pub enum AccountSelection {
  NoAccountSelected
  AccountSelected(@source_repository.AccountId)
} derive(Eq, Debug)

///|
pub enum Session {
  Resolving(Int)
  NoAccount
  Current(@source_repository.AccountId, String)
  SessionUnavailable
} derive(Eq, Debug)

///|
pub struct PlanId(Int) derive(Eq, Debug)

///|
pub struct DiscoveryId(Int) derive(Eq, Debug)

///|
pub struct EffectId(Int) derive(Eq, Debug)

///|
pub struct OpenIntent(Int) derive(Eq, Debug)

///|
pub struct Retry {
  priv replica : @source_repository.DocumentReplica
} derive(Eq, Debug)

///|
pub fn Retry::replica(self : Self) -> @source_repository.DocumentReplica {
  self.replica
}

///|
pub enum Progress {
  Inactive
  Working
  Retryable(Retry)
  Blocked
} derive(Eq, Debug)

///|
priv struct OpenTarget {
  intent : OpenIntent
  account : @source_repository.AccountId
  document_id : @source_repository.DocumentId
  revision : @source_repository.SavedRevision
} derive(Eq, Debug)

///|
pub(all) enum RemoteRead {
  Conflict(@source_repository.OperationId)
  Revision(@source_repository.SavedRevision)
  Open(OpenIntent, @source_repository.SavedRevision)
} derive(Eq, Debug)

///|
priv enum Catalog {
  Idle(Array[@source_repository.RemoteEntry])
  Loading(DiscoveryId, Array[@source_repository.RemoteEntry])
} derive(Eq, Debug)

///|
priv enum NetworkState {
  Planning(PlanId, Double)
  Delivering(EffectId, @source_repository.OperationId)
  RetryRemote(RemoteRead)
  FetchingRemote(EffectId, RemoteRead)
  Recovering(EffectId)
  Blocked
} derive(Eq, Debug)

///|
priv struct Network {
  account : @source_repository.AccountId
  document_id : @source_repository.DocumentId
  state : NetworkState
} derive(Eq, Debug)

///|
priv enum Next {
  NoWork
  NetworkRunning
  NetworkRetry(Int, RemoteRead)
  NetworkBlocked
  Deliver(@source_repository.PendingOperation)
  Fetch(@source_repository.SavedRevision)
  Recover
  Plan
}

///|
pub(all) enum Action {
  CreateOperation(
    PlanId,
    @source_repository.AccountId,
    @source_repository.DocumentId
  )
  Deliver(
    EffectId,
    @source_repository.AccountId,
    @source_repository.DocumentId,
    @source_repository.PendingOperation
  )
  GetRemote(
    EffectId,
    @source_repository.AccountId,
    @source_repository.DocumentId,
    RemoteRead
  )
  CreateRecovery(
    EffectId,
    @source_repository.AccountId,
    @source_repository.DocumentId
  )
} derive(Eq, Debug)

///|
pub(all) suberror WorkError {
  StaleWork
} derive(Eq, Debug)

///|
pub struct State {
  priv session : Session
  priv catalog_account : @source_repository.AccountId?
  priv catalog : Catalog
  priv open_target : OpenTarget?
  priv network : Array[Network]
  priv last_lookup_id : Int
  priv last_plan_id : Int
  priv last_discovery_id : Int
  priv last_effect_id : Int
  priv last_open_intent : Int
} derive(Eq, Debug)

///|
pub fn State::State() -> State {
  {
    session: SessionUnavailable,
    catalog_account: None,
    catalog: Idle([]),
    open_target: None,
    network: [],
    last_lookup_id: 0,
    last_plan_id: 0,
    last_discovery_id: 0,
    last_effect_id: 0,
    last_open_intent: 0,
  }
}

///|
pub fn State::session(self : Self) -> Session {
  self.session
}

///|
pub fn State::begin_lookup(self : Self) -> (Self, Int) {
  let request_id = self.last_lookup_id + 1
  (
    {
      ..self,
      session: Resolving(request_id),
      open_target: None,
      last_lookup_id: request_id,
    },
    request_id,
  )
}

///|
pub fn State::resolved(
  self : Self,
  request_id : Int,
  result : AccountResult,
) -> (Self, AccountSelection?) {
  guard self.session == Resolving(request_id) else { return (self, None) }
  let session = match result {
    SignedOut => NoAccount
    AccountUnavailable => SessionUnavailable
    Resolved(id, name) => Current(id, name)
  }
  let account = match result {
    Resolved(id, _) => Some(AccountSelection::AccountSelected(id))
    SignedOut => Some(AccountSelection::NoAccountSelected)
    AccountUnavailable => None
  }
  let (catalog_account, catalog) = match result {
    Resolved(id, _) if self.catalog_account == Some(id) =>
      (self.catalog_account, self.catalog)
    Resolved(id, _) => (Some(id), Idle([]))
    SignedOut => (None, Idle([]))
    AccountUnavailable => (self.catalog_account, self.catalog)
  }
  ({ ..self, session, catalog_account, catalog, }, account)
}

///|
fn Catalog::entries(self : Self) -> Array[@source_repository.RemoteEntry] {
  match self {
    Idle(entries) | Loading(_, entries) => entries
  }
}

///|
pub fn State::catalog(self : Self) -> Array[@source_repository.RemoteEntry] {
  match (self.session, self.catalog_account) {
    (Current(account, _), Some(owner)) if account == owner =>
      self.catalog.entries()
    _ => []
  }
}

///|
pub fn State::remote_entry(
  self : Self,
  document_id : @source_repository.DocumentId,
) -> @source_repository.RemoteEntry? {
  self
  .catalog()
  .view()
  .search_by(entry => entry.document_id() == document_id)
  .map(index => self.catalog()[index])
}

///|
pub fn State::begin_discovery(self : Self) -> (Self, DiscoveryId?) {
  guard self.session is Current(account, _) &&
    self.catalog_account == Some(account) else {
    return (self, None)
  }
  let value = self.last_discovery_id + 1
  let id = DiscoveryId(value)
  (
    {
      ..self,
      catalog: Loading(id, self.catalog.entries()),
      last_discovery_id: value,
    },
    Some(id),
  )
}

///|
fn merge_catalog(
  old : Array[@source_repository.RemoteEntry],
  fresh : Array[@source_repository.RemoteEntry],
) -> Array[@source_repository.RemoteEntry] {
  let merged = old.copy()
  for candidate in fresh {
    match
      merged
      .view()
      .search_by(entry => entry.document_id() == candidate.document_id()) {
      Some(index) if candidate.revision().value() >
        merged[index].revision().value() => merged[index] = candidate
      Some(_) => ()
      None => merged.push(candidate)
    }
  }
  merged.sort_by((left, right) => {
    left.document_id().value().lexical_compare(right.document_id().value())
  })
  merged
}

///|
pub fn State::discovered(
  self : Self,
  account : @source_repository.AccountId,
  id : DiscoveryId,
  entries : Array[@source_repository.RemoteEntry]?,
) -> (Self, Bool) {
  guard self.session is Current(current, _) &&
    current == account &&
    self.catalog_account == Some(account) &&
    self.catalog is Loading(active, old) &&
    active == id else {
    return (self, false)
  }
  let catalog = match entries {
    Some(fresh) => Idle(merge_catalog(old, fresh))
    None => Idle(old)
  }
  ({ ..self, catalog, }, true)
}

///|
fn State::effect(self : Self) -> (Self, EffectId) {
  let value = self.last_effect_id + 1
  ({ ..self, last_effect_id: value, }, EffectId(value))
}

///|
pub fn State::cancel_open(self : Self) -> Self {
  {
    ..self,
    open_target: None,
    network: self.network.filter(task => {
      !(task.state is FetchingRemote(_, RemoteRead::Open(_, _)))
    }),
  }
}

///|
fn replica_covers(
  replica : @source_repository.DocumentReplica,
  revision : @source_repository.SavedRevision,
) -> Bool {
  replica.baseline_revision() >= revision.value()
}

///|
pub fn State::select_open(
  self : Self,
  entry : @source_repository.RemoteEntry,
) -> Self {
  guard entry
    is @source_repository.RemoteEntry::Present(document_id, revision, _) &&
    self.session is Current(account, _) else {
    return self
  }
  let intent_value = self.last_open_intent + 1
  let intent = OpenIntent(intent_value)
  let self = self.cancel_open()
  {
    ..self,
    open_target: Some({ intent, account, document_id, revision, }),
    last_open_intent: intent_value,
  }
}

///|
/// Start a selected remote read only after Replication has admitted it against
/// the document's persistence lane.
pub fn State::advance_open(
  self : Self,
  replica : @source_repository.DocumentReplica?,
) -> (Self, Action?) {
  guard self.open_target is Some(target) &&
    self.session is Current(current, _) &&
    current == target.account else {
    return (self, None)
  }
  guard replica is None ||
    (
      replica is Some(candidate) &&
      candidate.account() == target.account &&
      candidate.document().id() == target.document_id
    ) else {
    return (self, None)
  }
  if replica
    .map(value => replica_covers(value, target.revision))
    .unwrap_or(false) ||
    self.find_network(target.account, target.document_id) is Some(_) {
    return (self, None)
  }
  let (self, effect) = self.effect()
  let read = RemoteRead::Open(target.intent, target.revision)
  let task : Network = {
    account: target.account,
    document_id: target.document_id,
    state: FetchingRemote(effect, read),
  }
  (
    { ..self, network: self.network + [task], },
    Some(GetRemote(effect, target.account, target.document_id, read)),
  )
}

///|
pub fn State::opened(
  self : Self,
  effect : EffectId,
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
  intent : OpenIntent,
  expected : @source_repository.SavedRevision,
  replica : @source_repository.DocumentReplica?,
  remote : @source_repository.RemoteDocument,
) -> (Self, @source_repository.ReplicaWrite?) raise WorkError {
  guard self.find_network(account, document_id) is Some(index) &&
    self.network[index].state
    is FetchingRemote(
      active,
      RemoteRead::Open(expected_intent, expected_revision)
    ) &&
    active == effect &&
    expected_intent == intent &&
    expected_revision == expected else {
    raise StaleWork
  }
  let self = self.remove_network(index)
  guard self.open_target ==
    Some({ intent, account, document_id, revision: expected, }) &&
    self.session is Current(current, _) &&
    current == account &&
    remote is @source_repository.RemoteDocument::Present(actual, text) &&
    actual.value() >= expected.value() else {
    return (self, None)
  }
  let document = @source_repository.Document::create(document_id, text)
  match replica {
    Some(replica) if replica.account() == account &&
      replica.document().id() == document_id => (self, replica.refresh(remote))
    Some(_) => raise StaleWork
    None =>
      (
        self,
        Some(
          @source_repository.DocumentReplica::receive(account, document, actual).store(),
        ),
      )
  }
}

///|
pub fn State::open_failed(
  self : Self,
  effect : EffectId,
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
  intent : OpenIntent,
  expected : @source_repository.SavedRevision,
) -> Self raise WorkError {
  guard self.find_network(account, document_id) is Some(index) &&
    self.network[index].state
    is FetchingRemote(active, RemoteRead::Open(active_intent, active_revision)) &&
    active == effect &&
    active_intent == intent &&
    active_revision == expected else {
    raise StaleWork
  }
  let self = self.remove_network(index)
  if self.open_target ==
    Some({ intent, account, document_id, revision: expected, }) {
    { ..self, open_target: None, }
  } else {
    self
  }
}

///|
pub fn State::pending_open(
  self : Self,
) -> (
  OpenIntent,
  @source_repository.AccountId,
  @source_repository.DocumentId,
  @source_repository.SavedRevision,
)? {
  self.open_target.map(target => {
    (target.intent, target.account, target.document_id, target.revision)
  })
}

///|
pub fn State::activated(self : Self, intent : OpenIntent) -> Self {
  match self.open_target {
    Some(target) if target.intent == intent => { ..self, open_target: None, }
    Some(_) | None => self
  }
}

///|
fn State::find_network(
  self : Self,
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
) -> Int? {
  self.network
  .view()
  .search_by(task => task.account == account && task.document_id == document_id)
}

///|
pub fn State::progress(
  self : Self,
  replica : @source_repository.DocumentReplica,
) -> Progress {
  match self.next(replica) {
    NoWork => Inactive
    NetworkBlocked => Blocked
    NetworkRunning => Working
    NetworkRetry(_, _) | Deliver(_) | Fetch(_) | Recover | Plan =>
      Retryable({ replica, })
  }
}

///|
fn State::newer_revision(
  self : Self,
  replica : @source_repository.DocumentReplica,
) -> @source_repository.SavedRevision? {
  match self.remote_entry(replica.document().id()) {
    Some(entry) if entry.revision().value() > replica.observed_revision() =>
      Some(entry.revision())
    Some(_) | None => None
  }
}

///|
fn State::next(
  self : Self,
  replica : @source_repository.DocumentReplica,
) -> Next {
  let account = replica.account()
  let document_id = replica.document().id()
  guard self.session is Current(current, _) && current == account else {
    return NoWork
  }
  match self.find_network(account, document_id) {
    Some(index) =>
      return match self.network[index].state {
        RetryRemote(read) => NetworkRetry(index, read)
        Blocked => NetworkBlocked
        Planning(_, _)
        | Delivering(_, _)
        | FetchingRemote(_, _)
        | Recovering(_) => NetworkRunning
      }
    None => ()
  }
  match replica.directive() {
    Send(operation) => Deliver(operation)
    RecoveryRequired =>
      match self.newer_revision(replica) {
        Some(revision) => Fetch(revision)
        None => Recover
      }
    SaveRequired =>
      match self.newer_revision(replica) {
        Some(revision) => Fetch(revision)
        None => Plan
      }
    Synchronized | UpdateAvailable(_) =>
      match self.newer_revision(replica) {
        Some(revision) => Fetch(revision)
        None => NoWork
      }
  }
}

///|
fn State::remove_network(self : Self, index : Int) -> Self {
  let network = self.network.copy()
  network.remove(index) |> ignore
  { ..self, network, }
}

///|
fn State::replace_network(
  self : Self,
  index : Int,
  state : NetworkState,
) -> Self {
  {
    ..self,
    network: self.network.mapi((i, task) => {
      if i == index {
        { ..task, state, }
      } else {
        task
      }
    }),
  }
}

///|
/// Apply eligible local text to the newest replica rather than branching
/// from the last durable value.
pub fn State::save(
  self : Self,
  replica : @source_repository.DocumentReplica,
  text : String,
) -> (Self, @source_repository.ReplicaWrite?) {
  match replica.edit(text) {
    @source_repository.EditPlan::Persist(write) => {
      let self = match
        self.find_network(replica.account(), replica.document().id()) {
        Some(index) if self.network[index].state is (Planning(_, _) | Blocked) =>
          self.remove_network(index)
        Some(index) if self.network[index].state is Recovering(_) &&
          !(write.replica().directive()
          is @source_repository.ReplicaDirective::RecoveryRequired) =>
          self.remove_network(index)
        _ => self
      }
      (self, Some(write))
    }
    @source_repository.EditPlan::Unchanged => (self, None)
  }
}

///|
/// Derive the next effect from durable replica and catalog facts.
pub fn State::advance(
  self : Self,
  durable : @source_repository.DocumentReplica,
) -> (Self, Action?) {
  let (self, open) = self.advance_open(Some(durable))
  guard open is None else { return (self, open) }
  let account = durable.account()
  let document_id = durable.document().id()
  match self.next(durable) {
    NetworkRetry(index, read) => {
      let (self, effect) = self.effect()
      (
        self.replace_network(index, FetchingRemote(effect, read)),
        Some(Action::GetRemote(effect, account, document_id, read)),
      )
    }
    Deliver(operation) => {
      let (self, effect) = self.effect()
      let task : Network = {
        account,
        document_id,
        state: Delivering(effect, operation.operation_id()),
      }
      (
        { ..self, network: self.network + [task], },
        Some(Action::Deliver(effect, account, document_id, operation)),
      )
    }
    Fetch(revision) => {
      let (self, effect) = self.effect()
      let read = RemoteRead::Revision(revision)
      let task : Network = {
        account,
        document_id,
        state: FetchingRemote(effect, read),
      }
      (
        { ..self, network: self.network + [task], },
        Some(Action::GetRemote(effect, account, document_id, read)),
      )
    }
    Recover => {
      let (self, effect) = self.effect()
      let task : Network = { account, document_id, state: Recovering(effect), }
      (
        { ..self, network: self.network + [task], },
        Some(Action::CreateRecovery(effect, account, document_id)),
      )
    }
    Plan => {
      let value = self.last_plan_id + 1
      let id = PlanId(value)
      let task : Network = {
        account,
        document_id,
        state: Planning(id, durable.generation()),
      }
      (
        { ..self, network: self.network + [task], last_plan_id: value, },
        Some(Action::CreateOperation(id, account, document_id)),
      )
    }
    NoWork | NetworkRunning | NetworkBlocked => (self, None)
  }
}

///|
pub fn State::prepared(
  self : Self,
  id : PlanId,
  durable : @source_repository.DocumentReplica,
  operation_id : @source_repository.OperationId,
) -> (Self, @source_repository.ReplicaWrite?) raise WorkError {
  guard self.find_network(durable.account(), durable.document().id())
    is Some(index) &&
    self.network[index].state is Planning(active, generation) &&
    active == id &&
    generation == durable.generation() else {
    raise StaleWork
  }
  let self = self.remove_network(index)
  guard durable.plan_save() is @source_repository.OperationPlan::Start(draft) else {
    raise StaleWork
  }
  (self, Some(draft.start(operation_id)))
}

///|
pub fn State::planning_failed(
  self : Self,
  id : PlanId,
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
) -> Self {
  match self.find_network(account, document_id) {
    Some(index) if self.network[index].state is Planning(active, _) &&
      active == id => self.remove_network(index)
    _ => self
  }
}

///|
fn State::delivery(
  self : Self,
  durable : @source_repository.DocumentReplica,
  effect : EffectId,
  operation_id : @source_repository.OperationId,
) -> Int raise WorkError {
  guard self.find_network(durable.account(), durable.document().id())
    is Some(index) &&
    self.network[index].state is Delivering(active_effect, active_operation) &&
    active_effect == effect &&
    active_operation == operation_id else {
    raise StaleWork
  }
  index
}

///|
pub fn State::acknowledged(
  self : Self,
  durable : @source_repository.DocumentReplica,
  effect : EffectId,
  operation_id : @source_repository.OperationId,
  revision : @source_repository.SavedRevision,
) -> (Self, @source_repository.ReplicaWrite?) raise WorkError {
  let index = self.delivery(durable, effect, operation_id)
  let write = durable.acknowledge(operation_id, revision) catch {
    _ => raise StaleWork
  }
  (self.remove_network(index), Some(write))
}

///|
pub fn State::delivery_failed(
  self : Self,
  durable : @source_repository.DocumentReplica,
  effect : EffectId,
  operation_id : @source_repository.OperationId,
) -> Self raise WorkError {
  let index = self.delivery(durable, effect, operation_id)
  self.remove_network(index)
}

///|
pub fn State::revision_conflict(
  self : Self,
  durable : @source_repository.DocumentReplica,
  effect : EffectId,
  operation_id : @source_repository.OperationId,
) -> Self raise WorkError {
  let index = self.delivery(durable, effect, operation_id)
  self.replace_network(index, RetryRemote(Conflict(operation_id)))
}

///|
fn State::remote_fetch(
  self : Self,
  durable : @source_repository.DocumentReplica,
  effect : EffectId,
  read : RemoteRead,
) -> Int raise WorkError {
  guard self.find_network(durable.account(), durable.document().id())
    is Some(index) &&
    self.network[index].state is FetchingRemote(active_effect, active_read) &&
    active_effect == effect &&
    active_read == read else {
    raise StaleWork
  }
  index
}

///|
pub fn State::remote_failed(
  self : Self,
  durable : @source_repository.DocumentReplica,
  effect : EffectId,
  read : RemoteRead,
) -> Self raise WorkError {
  let index = self.remote_fetch(durable, effect, read)
  match read {
    Conflict(_) | Revision(_) => self.replace_network(index, RetryRemote(read))
    Open(_, _) => self.remove_network(index)
  }
}

///|
fn State::reject_delivery(
  self : Self,
  durable : @source_repository.DocumentReplica,
  effect : EffectId,
  operation_id : @source_repository.OperationId,
  block : Bool,
) -> (Self, @source_repository.ReplicaWrite?) raise WorkError {
  let index = self.delivery(durable, effect, operation_id)
  let write = durable.reject_operation(operation_id) catch {
    _ => raise StaleWork
  }
  let self = if block {
    self.replace_network(index, Blocked)
  } else {
    self.remove_network(index)
  }
  (self, Some(write))
}

///|
pub fn State::delivery_too_large(
  self : Self,
  durable : @source_repository.DocumentReplica,
  effect : EffectId,
  operation_id : @source_repository.OperationId,
) -> (Self, @source_repository.ReplicaWrite?) raise WorkError {
  guard durable.directive()
    is @source_repository.ReplicaDirective::Send(operation) &&
    operation.operation_id() == operation_id else {
    raise StaleWork
  }
  let unchanged = match operation.content() {
    @source_repository.PendingContent::Save(text) =>
      durable.document().text() == text
    Delete => true
  }
  self.reject_delivery(durable, effect, operation_id, unchanged)
}

///|
pub fn State::operation_rejected(
  self : Self,
  durable : @source_repository.DocumentReplica,
  effect : EffectId,
  operation_id : @source_repository.OperationId,
) -> (Self, @source_repository.ReplicaWrite?) raise WorkError {
  self.reject_delivery(durable, effect, operation_id, false)
}

///|
fn reconcile(
  durable : @source_repository.DocumentReplica,
  read : RemoteRead,
  remote : @source_repository.RemoteDocument,
) -> @source_repository.ReconcilePlan raise WorkError {
  match read {
    RemoteRead::Conflict(operation_id) =>
      durable.reject_conflict(operation_id, remote) catch {
        _ => raise StaleWork
      }
    Revision(expected) => {
      guard remote.revision() >= expected.value() else { raise StaleWork }
      durable.reconcile(remote)
    }
    Open(_, _) => raise StaleWork
  }
}

///|
pub fn State::received(
  self : Self,
  durable : @source_repository.DocumentReplica,
  effect : EffectId,
  read : RemoteRead,
  remote : @source_repository.RemoteDocument,
) -> (Self, @source_repository.ReplicaWrite?) raise WorkError {
  let index = self.remote_fetch(durable, effect, read)
  let plan = reconcile(durable, read, remote)
  match plan {
    @source_repository.ReconcilePlan::Unchanged =>
      (self.remove_network(index), None)
    Persist(write) => (self.remove_network(index), Some(write))
  }
}

///|
pub fn State::recover(
  self : Self,
  durable : @source_repository.DocumentReplica,
  effect : EffectId,
  recovery_id : @source_repository.DocumentId,
) -> (Self, @source_repository.ReplicaWrite?) raise WorkError {
  guard self.find_network(durable.account(), durable.document().id())
    is Some(index) &&
    self.network[index].state is Recovering(active) &&
    active == effect else {
    raise StaleWork
  }
  let write = durable.fork(recovery_id) catch { _ => raise StaleWork }
  (self.remove_network(index), Some(write))
}

///|
pub fn State::recovery_failed(
  self : Self,
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
  effect : EffectId,
) -> Self {
  match self.find_network(account, document_id) {
    Some(index) if self.network[index].state is Recovering(active) &&
      active == effect => self.remove_network(index)
    _ => self
  }
}
