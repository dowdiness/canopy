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
/// One remote-open lifecycle. The selected target and its active request can
/// never disagree because they are represented by the same value.
priv enum Opening {
  Idle
  Selected(OpenTarget)
  Fetching(OpenTarget, EffectId)
  Persisting(OpenTarget)
  Ready(OpenTarget)
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
  Planning(PlanId, @source_repository.OperationDraft)
  Delivering(EffectId, @source_repository.OperationId)
  RetryRemote(RemoteRead)
  FetchingRemote(EffectId, RemoteRead)
  Recovering(EffectId)
  Blocked(@source_repository.OperationDraft)
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
  Plan(@source_repository.OperationDraft)
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
  priv opening : Opening
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
    opening: Opening::Idle,
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
      opening: Opening::Idle,
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
fn State::retained_remote_entry(
  self : Self,
  document_id : @source_repository.DocumentId,
) -> @source_repository.RemoteEntry? {
  let entries = self.catalog.entries()
  entries
  .view()
  .search_by(entry => entry.document_id() == document_id)
  .map(index => entries[index])
}

///|
pub fn State::remote_entry(
  self : Self,
  document_id : @source_repository.DocumentId,
) -> @source_repository.RemoteEntry? {
  guard self.session is Current(account, _) &&
    self.catalog_account == Some(account) else {
    return None
  }
  self.retained_remote_entry(document_id)
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
      Some(index) if candidate.revision() == merged[index].revision() &&
        candidate is @source_repository.RemoteEntry::Deleted(_, _) &&
        merged[index] is @source_repository.RemoteEntry::Present(_, _, _) =>
        merged[index] = candidate
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
fn Opening::observe(
  self : Self,
  account : @source_repository.AccountId,
  entry : @source_repository.RemoteEntry,
) -> Opening {
  let target = match self {
    Idle => return self
    Selected(target)
    | Fetching(target, _)
    | Persisting(target)
    | Ready(target) => target
  }
  guard target.account == account &&
    target.document_id == entry.document_id() &&
    entry is @source_repository.RemoteEntry::Deleted(_, revision) &&
    revision.value() >= target.revision.value() else {
    return self
  }
  Idle
}

///|
fn opening_observe_catalog(
  opening : Opening,
  account : @source_repository.AccountId,
  fresh : Array[@source_repository.RemoteEntry],
  merged : Array[@source_repository.RemoteEntry],
) -> Opening {
  fresh.fold(init=opening, (opening, candidate) => {
    match
      merged
      .view()
      .search_by(entry => entry.document_id() == candidate.document_id()) {
      Some(index) => opening.observe(account, merged[index])
      None => opening
    }
  })
}

///|
fn remote_advances(
  current : @source_repository.RemoteEntry?,
  remote : @source_repository.RemoteDocument,
) -> Bool {
  match (current, remote) {
    (_, @source_repository.RemoteDocument::Missing) => false
    (None, Present(_, _) | Deleted(_)) => true
    (Some(entry), Present(revision, _)) =>
      revision.value() > entry.revision().value()
    (Some(entry), Deleted(revision)) =>
      revision.value() > entry.revision().value() ||
      (
        revision == entry.revision() &&
        entry is @source_repository.RemoteEntry::Present(_, _, _)
      )
  }
}

///|
fn State::observe_remote(
  self : Self,
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
  remote : @source_repository.RemoteDocument,
) -> Self {
  guard self.catalog_account == Some(account) &&
    remote_advances(self.retained_remote_entry(document_id), remote) &&
    remote.entry(document_id) is Some(entry) else {
    return self
  }
  let entries = merge_catalog(self.catalog.entries(), [entry])
  let catalog = match self.catalog {
    Catalog::Idle(_) => Catalog::Idle(entries)
    Loading(id, _) => Loading(id, entries)
  }
  {
    ..self,
    catalog,
    opening: opening_observe_catalog(self.opening, account, [entry], entries),
  }
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
  let (catalog, opening) = match entries {
    Some(fresh) => {
      let merged = merge_catalog(old, fresh)
      (
        Catalog::Idle(merged),
        opening_observe_catalog(self.opening, account, fresh, merged),
      )
    }
    None => (Catalog::Idle(old), self.opening)
  }
  ({ ..self, catalog, opening, }, true)
}

///|
fn State::effect(self : Self) -> (Self, EffectId) {
  let value = self.last_effect_id + 1
  ({ ..self, last_effect_id: value, }, EffectId(value))
}

///|
pub fn State::cancel_open(self : Self) -> Self {
  { ..self, opening: Opening::Idle, }
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
  document_id : @source_repository.DocumentId,
) -> Self {
  guard self.remote_entry(document_id)
    is Some(@source_repository.RemoteEntry::Present(_, revision, _)) &&
    self.session is Current(account, _) else {
    return self
  }
  let intent_value = self.last_open_intent + 1
  let intent = OpenIntent(intent_value)
  {
    ..self,
    opening: Selected({ intent, account, document_id, revision, }),
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
  let target = match self.opening {
    Selected(target) => target
    Persisting(target) => {
      guard replica
        .map(value => replica_covers(value, target.revision))
        .unwrap_or(false) else {
        return (self, None)
      }
      return ({ ..self, opening: Ready(target), }, None)
    }
    Idle | Fetching(_, _) | Ready(_) => return (self, None)
  }
  guard self.session is Current(current, _) && current == target.account else {
    return (self, None)
  }
  guard replica is None ||
    (
      replica is Some(candidate) &&
      candidate.account() == target.account &&
      candidate.document_id() == target.document_id
    ) else {
    return (self, None)
  }
  if replica
    .map(value => replica_covers(value, target.revision))
    .unwrap_or(false) {
    return ({ ..self, opening: Ready(target), }, None)
  }
  if self.find_network(target.account, target.document_id) is Some(_) {
    return (self, None)
  }
  let (self, effect) = self.effect()
  let read = RemoteRead::Open(target.intent, target.revision)
  (
    { ..self, opening: Fetching(target, effect), },
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
) -> (Self, @source_repository.OpenOutcome) raise WorkError {
  let target = { intent, account, document_id, revision: expected, }
  guard self.opening == Fetching(target, effect) else { raise StaleWork }
  guard self.session is Current(current, _) && current == account else {
    raise StaleWork
  }
  let self = self.observe_remote(account, document_id, remote)
  guard remote.revision() >= expected.value() else {
    return (
      { ..self, opening: Opening::Idle, },
      @source_repository.OpenOutcome::Unavailable,
    )
  }
  match replica {
    Some(replica) if replica.account() == account &&
      replica.document_id() == document_id => {
      let outcome = replica.open(remote) catch {
        _ => abort("Unmounted Replica must be openable")
      }
      let self = match outcome {
        @source_repository.OpenOutcome::PersistOnly(_) | Unavailable =>
          { ..self, opening: Opening::Idle, }
        Ready => { ..self, opening: Opening::Ready(target), }
        PersistAndOpen(_) => { ..self, opening: Persisting(target), }
      }
      (self, outcome)
    }
    Some(_) => raise StaleWork
    None => {
      guard remote is @source_repository.RemoteDocument::Present(actual, text) else {
        return (
          { ..self, opening: Opening::Idle, },
          @source_repository.OpenOutcome::Unavailable,
        )
      }
      let document = @source_repository.Document::create(document_id, text)
      (
        { ..self, opening: Persisting(target), },
        @source_repository.OpenOutcome::PersistAndOpen(
          @source_repository.DocumentReplica::receive(account, document, actual).store(),
        ),
      )
    }
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
  let target = { intent, account, document_id, revision: expected, }
  guard self.opening == Fetching(target, effect) else { raise StaleWork }
  { ..self, opening: Opening::Idle, }
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
  match self.opening {
    Selected(target)
    | Fetching(target, _)
    | Persisting(target)
    | Ready(target) =>
      Some((target.intent, target.account, target.document_id, target.revision))
    Idle => None
  }
}

///|
pub fn State::ready_open(
  self : Self,
) -> (
  OpenIntent,
  @source_repository.AccountId,
  @source_repository.DocumentId,
  @source_repository.SavedRevision,
)? {
  match self.opening {
    Ready(target) =>
      Some((target.intent, target.account, target.document_id, target.revision))
    Idle | Selected(_) | Fetching(_, _) | Persisting(_) => None
  }
}

///|
pub fn State::complete_open(self : Self, intent : OpenIntent) -> Self {
  match self.opening {
    Ready(target) if target.intent == intent =>
      { ..self, opening: Opening::Idle, }
    Idle | Selected(_) | Fetching(_, _) | Persisting(_) | Ready(_) => self
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
    NetworkRetry(_, _) | Deliver(_) | Fetch(_) | Recover | Plan(_) =>
      Retryable({ replica, })
  }
}

///|
fn State::newer_revision(
  self : Self,
  replica : @source_repository.DocumentReplica,
) -> @source_repository.SavedRevision? {
  match self.remote_entry(replica.document_id()) {
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
  let document_id = replica.document_id()
  guard self.session is Current(current, _) && current == account else {
    return NoWork
  }
  match self.find_network(account, document_id) {
    Some(index) =>
      return match self.network[index].state {
        RetryRemote(read) => NetworkRetry(index, read)
        Blocked(_) => NetworkBlocked
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
    CreateOperation(draft) =>
      match draft.content() {
        @source_repository.PendingContent::Save(_) =>
          match self.newer_revision(replica) {
            Some(revision) => Fetch(revision)
            None => Plan(draft)
          }
        Delete => Plan(draft)
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
fn NetworkState::accepts(
  self : Self,
  replica : @source_repository.DocumentReplica,
) -> Bool {
  match self {
    Planning(_, draft) =>
      replica.directive() ==
      @source_repository.ReplicaDirective::CreateOperation(draft)
    Delivering(_, operation_id) =>
      replica.directive()
      is @source_repository.ReplicaDirective::Send(operation) &&
      operation.operation_id() == operation_id
    RetryRemote(Conflict(operation_id))
    | FetchingRemote(_, Conflict(operation_id)) =>
      replica.directive()
      is @source_repository.ReplicaDirective::Send(operation) &&
      operation.operation_id() == operation_id
    RetryRemote(Revision(_)) | FetchingRemote(_, Revision(_)) =>
      replica.document() is Some(_)
    RetryRemote(Open(_, _)) | FetchingRemote(_, Open(_, _)) => false
    Recovering(_) =>
      replica.directive()
      is @source_repository.ReplicaDirective::RecoveryRequired
    Blocked(blocked) =>
      replica.directive() ==
      @source_repository.ReplicaDirective::CreateOperation(blocked)
  }
}

///|
fn State::retain_compatible_network(
  self : Self,
  replica : @source_repository.DocumentReplica,
) -> Self {
  match self.find_network(replica.account(), replica.document_id()) {
    Some(index) if !self.network[index].state.accepts(replica) =>
      self.remove_network(index)
    Some(_) | None => self
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
      let self = self.retain_compatible_network(write.replica())
      (self, Some(write))
    }
    @source_repository.EditPlan::Unchanged
    | @source_repository.EditPlan::Unavailable => (self, None)
  }
}

///|
/// Persist deletion intent from the newest Replica head. Any working-copy text
/// not yet eligible for Autosave is included before deletion closes editing.
pub fn State::delete(
  self : Self,
  replica : @source_repository.DocumentReplica,
  text : String,
) -> (Self, @source_repository.ReplicaWrite) {
  let replica = match replica.edit(text) {
    @source_repository.EditPlan::Persist(write) => write.replica()
    Unchanged => replica
    Unavailable => abort("deletion requested without a live replica")
  }
  let write = replica.request_deletion() catch {
    _ => abort("live replica rejected deletion")
  }
  let self = self.retain_compatible_network(write.replica())
  (self, write)
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
  let document_id = durable.document_id()
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
    Plan(draft) => {
      let value = self.last_plan_id + 1
      let id = PlanId(value)
      let task : Network = { account, document_id, state: Planning(id, draft), }
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
  guard self.find_network(durable.account(), durable.document_id())
    is Some(index) &&
    self.network[index].state is Planning(active, draft) &&
    active == id &&
    durable.directive() ==
    @source_repository.ReplicaDirective::CreateOperation(draft) else {
    raise StaleWork
  }
  let self = self.remove_network(index)
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
  guard self.find_network(durable.account(), durable.document_id())
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
  guard self.find_network(durable.account(), durable.document_id())
    is Some(index) &&
    self.network[index].state.accepts(durable) &&
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
    guard write.replica().directive()
      is @source_repository.ReplicaDirective::CreateOperation(draft) &&
      draft.content() is @source_repository.PendingContent::Save(_) else {
      raise StaleWork
    }
    self.replace_network(index, Blocked(draft))
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
  let unchanged = match (durable.is_deleting(), operation.content()) {
    (false, @source_repository.PendingContent::Save(text)) =>
      durable
      .document()
      .map(document => document.text() == text)
      .unwrap_or(false)
    (true, Save(_)) | (_, Delete) => false
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
  let self = self.observe_remote(
    durable.account(),
    durable.document_id(),
    remote,
  )
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
  guard self.find_network(durable.account(), durable.document_id())
    is Some(index) &&
    self.network[index].state.accepts(durable) &&
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
