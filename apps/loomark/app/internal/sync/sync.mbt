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
pub struct RequestId(Int) derive(Eq, Debug)

///|
pub struct PlanId(Int) derive(Eq, Debug)

///|
pub struct DiscoveryId(Int) derive(Eq, Debug)

///|
pub struct EffectId(Int) derive(Eq, Debug)

///|
pub struct OpenIntent(Int) derive(Eq, Debug)

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
pub struct Attempt {
  request_id : RequestId
  write : @source_repository.CheckpointWrite
} derive(Eq, Debug)

///|
pub fn Attempt::request_id(self : Self) -> RequestId {
  self.request_id
}

///|
pub fn Attempt::write(self : Self) -> @source_repository.CheckpointWrite {
  self.write
}

///|
priv enum LaneState {
  Storing(Attempt, @source_repository.CheckpointWrite?)
  RetryPending(@source_repository.CheckpointWrite)
} derive(Eq, Debug)

///|
priv struct Lane {
  account : @source_repository.AccountId
  document_id : @source_repository.DocumentId
  state : LaneState
} derive(Eq, Debug)

///|
priv enum NetworkState {
  Planning(PlanId, Double)
  Delivering(EffectId, @source_repository.OperationId)
  ConflictPending(@source_repository.OperationId)
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
pub(all) suberror CompletionError {
  StaleCompletion
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
  priv lanes : Array[Lane]
  priv network : Array[Network]
  priv last_lookup_id : Int
  priv last_request_id : Int
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
    lanes: [],
    network: [],
    last_lookup_id: 0,
    last_request_id: 0,
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
fn checkpoint_covers(
  checkpoint : @source_repository.SyncCheckpoint,
  revision : @source_repository.SavedRevision,
) -> Bool {
  checkpoint.baseline_revision() >= revision.value()
}

///|
fn State::continue_open(
  self : Self,
  index : Int,
  revision : @source_repository.SavedRevision,
) -> (Self, Attempt?)? {
  match self.lanes[index].state {
    Storing(_, Some(waiting)) if checkpoint_covers(
        waiting.checkpoint(),
        revision,
      ) => Some((self, None))
    Storing(active, None) if checkpoint_covers(
        active.write.checkpoint(),
        revision,
      ) => Some((self, None))
    RetryPending(write) if checkpoint_covers(write.checkpoint(), revision) =>
      Some(self.persist(write))
    Storing(_, _) | RetryPending(_) => None
  }
}

///|
pub fn State::begin_open(
  self : Self,
  entry : @source_repository.RemoteEntry,
) -> (Self, Attempt?, Action?) {
  guard entry
    is @source_repository.RemoteEntry::Present(document_id, revision, _) &&
    self.session is Current(account, _) else {
    return (self, None, None)
  }
  let intent_value = self.last_open_intent + 1
  let intent = OpenIntent(intent_value)
  let self = self.cancel_open()
  let self = {
    ..self,
    open_target: Some({ intent, account, document_id, revision, }),
    last_open_intent: intent_value,
  }
  match self.find_lane(account, document_id) {
    Some(index) =>
      match self.continue_open(index, revision) {
        Some((self, attempt)) => return (self, attempt, None)
        None => ()
      }
    None => ()
  }
  let (self, effect) = self.effect()
  let read = RemoteRead::Open(intent, revision)
  let task : Network = {
    account,
    document_id,
    state: FetchingRemote(effect, read),
  }
  (
    { ..self, network: self.network + [task], },
    None,
    Some(GetRemote(effect, account, document_id, read)),
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
  durable : @source_repository.SyncCheckpoint?,
  remote : @source_repository.RemoteDocument,
) -> (Self, Attempt?) raise WorkError {
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
  let head = match self.find_lane(account, document_id) {
    Some(index) => Some(self.lane_head(index))
    None => durable
  }
  match head {
    Some(checkpoint) if checkpoint.account() == account &&
      checkpoint.document().id() == document_id =>
      match checkpoint.refresh(remote) {
        Some(write) => self.persist(write)
        None => (self, None)
      }
    Some(_) => raise StaleWork
    None =>
      self.persist(
        @source_repository.SyncCheckpoint::receive(account, document, actual).write(),
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
fn State::find_lane(
  self : Self,
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
) -> Int? {
  self.lanes
  .view()
  .search_by(lane => lane.account == account && lane.document_id == document_id)
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
/// Return the newest checkpoint in a document's causal write sequence. A
/// transition waiting behind storage is newer than the active write, and an
/// active write is newer than the last durable checkpoint.
fn State::head(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
) -> @source_repository.SyncCheckpoint {
  match self.find_lane(durable.account(), durable.document().id()) {
    None => durable
    Some(index) =>
      match self.lanes[index].state {
        Storing(_, Some(waiting)) => waiting.checkpoint()
        Storing(active, None) => active.write.checkpoint()
        RetryPending(retained) => retained.checkpoint()
      }
  }
}

///|
fn State::lane_head(
  self : Self,
  index : Int,
) -> @source_repository.SyncCheckpoint {
  match self.lanes[index].state {
    Storing(_, Some(waiting)) => waiting.checkpoint()
    Storing(active, None) => active.write.checkpoint()
    RetryPending(retained) => retained.checkpoint()
  }
}

///|
fn State::attempt(
  self : Self,
  write : @source_repository.CheckpointWrite,
) -> (Self, Attempt) {
  let request = self.last_request_id + 1
  (
    { ..self, last_request_id: request, },
    { request_id: RequestId(request), write, },
  )
}

///|
fn State::replace_lane(self : Self, index : Int, state : LaneState) -> Self {
  {
    ..self,
    lanes: self.lanes.mapi((i, lane) => {
      if i == index {
        { ..lane, state, }
      } else {
        lane
      }
    }),
  }
}

///|
fn State::remove_lane(self : Self, index : Int) -> Self {
  let lanes = self.lanes.copy()
  lanes.remove(index) |> ignore
  { ..self, lanes, }
}

///|
/// Accept one explicit persistence request. An active lane retains only its
/// newest successor; an explicit request restarts a failed lane.
fn State::persist(
  self : Self,
  write : @source_repository.CheckpointWrite,
) -> (Self, Attempt?) {
  let checkpoint = write.checkpoint()
  let account = checkpoint.account()
  let document_id = checkpoint.document().id()
  match self.find_lane(account, document_id) {
    None => {
      let (self, attempt) = self.attempt(write)
      let lane : Lane = { account, document_id, state: Storing(attempt, None), }
      ({ ..self, lanes: self.lanes + [lane], }, Some(attempt))
    }
    Some(index) =>
      match self.lanes[index].state {
        Storing(active, waiting) => {
          let waiting = match waiting {
            Some(current) => current.coalesce(write)
            None => write
          }
          (self.replace_lane(index, Storing(active, Some(waiting))), None)
        }
        RetryPending(retained) => {
          let (self, attempt) = self.attempt(retained.coalesce(write))
          (self.replace_lane(index, Storing(attempt, None)), Some(attempt))
        }
      }
  }
}

///|
/// Apply eligible local text to the newest checkpoint rather than branching
/// from the last durable value. Repeating the same save restarts a failed
/// writer but does not duplicate an active write.
pub fn State::save(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  text : String,
) -> (Self, Attempt?) {
  let head = self.head(durable)
  match head.edit(text) {
    @source_repository.EditPlan::Persist(write) => {
      let self = match
        self.find_network(durable.account(), durable.document().id()) {
        Some(index) if self.network[index].state is (Planning(_, _) | Blocked) =>
          self.remove_network(index)
        Some(index) if self.network[index].state is Recovering(_) &&
          !(write.checkpoint().directive()
          is @source_repository.SyncDirective::RecoveryRequired) =>
          self.remove_network(index)
        _ => self
      }
      let (self, attempt) = self.persist(write)
      (self, attempt)
    }
    @source_repository.EditPlan::Unchanged =>
      match self.find_lane(durable.account(), durable.document().id()) {
        Some(index) =>
          match self.lanes[index].state {
            RetryPending(retained) => {
              let (self, attempt) = self.persist(retained)
              (self, attempt)
            }
            Storing(_, _) => (self, None)
          }
        None => (self, None)
      }
  }
}

///|
fn State::fetch_newer(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
) -> (Self, Action?)? {
  let document_id = durable.document().id()
  guard self.remote_entry(document_id) is Some(entry) &&
    entry.revision().value() > durable.observed_revision() else {
    return None
  }
  let account = durable.account()
  let (self, effect) = self.effect()
  let read = RemoteRead::Revision(entry.revision())
  let task : Network = {
    account,
    document_id,
    state: FetchingRemote(effect, read),
  }
  Some(
    (
      { ..self, network: self.network + [task], },
      Some(Action::GetRemote(effect, account, document_id, read)),
    ),
  )
}

///|
/// Derive the next effect from durable checkpoint and catalog facts.
pub fn State::drive(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
) -> (Self, Action?) {
  let account = durable.account()
  let document_id = durable.document().id()
  guard self.session is Current(current, _) &&
    current == account &&
    self.find_lane(account, document_id) is None else {
    return (self, None)
  }
  match self.find_network(account, document_id) {
    Some(index) =>
      return match self.network[index].state {
        ConflictPending(operation_id) => {
          let (self, effect) = self.effect()
          let read = RemoteRead::Conflict(operation_id)
          (
            self.replace_network(index, FetchingRemote(effect, read)),
            Some(Action::GetRemote(effect, account, document_id, read)),
          )
        }
        Planning(_, _)
        | Delivering(_, _)
        | FetchingRemote(_, _)
        | Recovering(_)
        | Blocked => (self, None)
      }
    None => ()
  }
  let directive = durable.directive()
  match directive {
    Send(operation) => {
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
    Conflict(_, _) => (self, None)
    RecoveryRequired =>
      match self.fetch_newer(durable) {
        Some(next) => next
        None => {
          let (self, effect) = self.effect()
          let task : Network = {
            account,
            document_id,
            state: Recovering(effect),
          }
          (
            { ..self, network: self.network + [task], },
            Some(Action::CreateRecovery(effect, account, document_id)),
          )
        }
      }
    SaveRequired =>
      match self.fetch_newer(durable) {
        Some(next) => next
        None => {
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
      }
    Synchronized | UpdateAvailable(_) =>
      self.fetch_newer(durable).unwrap_or((self, None))
  }
}

///|
pub fn State::prepared(
  self : Self,
  id : PlanId,
  durable : @source_repository.SyncCheckpoint,
  operation_id : @source_repository.OperationId,
) -> (Self, Attempt?) raise WorkError {
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
  self.persist(draft.start(operation_id))
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
  durable : @source_repository.SyncCheckpoint,
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
  durable : @source_repository.SyncCheckpoint,
  effect : EffectId,
  operation_id : @source_repository.OperationId,
  revision : @source_repository.SavedRevision,
) -> (Self, Attempt?) raise WorkError {
  let index = self.delivery(durable, effect, operation_id)
  self.remove_network(index).acknowledge(durable, operation_id, revision) catch {
    _ => raise StaleWork
  }
}

///|
pub fn State::delivery_failed(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  effect : EffectId,
  operation_id : @source_repository.OperationId,
) -> Self raise WorkError {
  let index = self.delivery(durable, effect, operation_id)
  self.remove_network(index)
}

///|
pub fn State::revision_conflict(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  effect : EffectId,
  operation_id : @source_repository.OperationId,
) -> Self raise WorkError {
  let index = self.delivery(durable, effect, operation_id)
  self.replace_network(index, ConflictPending(operation_id))
}

///|
fn State::remote_fetch(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
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
  durable : @source_repository.SyncCheckpoint,
  effect : EffectId,
  read : RemoteRead,
) -> Self raise WorkError {
  let index = self.remote_fetch(durable, effect, read)
  match read {
    RemoteRead::Conflict(operation_id) =>
      self.replace_network(index, ConflictPending(operation_id))
    Revision(_) | Open(_, _) => self.remove_network(index)
  }
}

///|
fn State::reject_delivery(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  effect : EffectId,
  operation_id : @source_repository.OperationId,
  block : Bool,
) -> (Self, Attempt?) raise WorkError {
  let index = self.delivery(durable, effect, operation_id)
  let write = self.head(durable).reject_operation(operation_id) catch {
      _ => raise StaleWork
    }
  let self = if block {
    self.replace_network(index, Blocked)
  } else {
    self.remove_network(index)
  }
  self.persist(write)
}

///|
pub fn State::delivery_too_large(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  effect : EffectId,
  operation_id : @source_repository.OperationId,
) -> (Self, Attempt?) raise WorkError {
  let head = self.head(durable)
  guard head.directive() is @source_repository.SyncDirective::Send(operation) &&
    operation.operation_id() == operation_id else {
    raise StaleWork
  }
  let unchanged = match operation.content() {
    @source_repository.PendingContent::Save(text) =>
      head.document().text() == text
    Delete => true
  }
  self.reject_delivery(durable, effect, operation_id, unchanged)
}

///|
pub fn State::operation_rejected(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  effect : EffectId,
  operation_id : @source_repository.OperationId,
) -> (Self, Attempt?) raise WorkError {
  self.reject_delivery(durable, effect, operation_id, false)
}

///|
fn State::reconcile(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  read : RemoteRead,
  remote : @source_repository.RemoteDocument,
) -> @source_repository.ReconcilePlan raise WorkError {
  match read {
    RemoteRead::Conflict(operation_id) =>
      self.head(durable).reject_conflict(operation_id, remote) catch {
        _ => raise StaleWork
      }
    Revision(expected) => {
      guard remote.revision() >= expected.value() else { raise StaleWork }
      self.head(durable).reconcile(remote)
    }
    Open(_, _) => raise StaleWork
  }
}

///|
pub fn State::received(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  effect : EffectId,
  read : RemoteRead,
  remote : @source_repository.RemoteDocument,
) -> (Self, Attempt?) raise WorkError {
  let index = self.remote_fetch(durable, effect, read)
  let plan = self.reconcile(durable, read, remote)
  match plan {
    @source_repository.ReconcilePlan::Unchanged =>
      (self.remove_network(index), None)
    Persist(write) => {
      let (self, attempt) = self.remove_network(index).persist(write)
      (self, attempt)
    }
  }
}

///|
pub fn State::recover(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  effect : EffectId,
  recovery_id : @source_repository.DocumentId,
) -> (Self, Attempt?) raise WorkError {
  guard self.find_network(durable.account(), durable.document().id())
    is Some(index) &&
    self.network[index].state is Recovering(active) &&
    active == effect else {
    raise StaleWork
  }
  let write = self.head(durable).preserve(recovery_id) catch {
      _ => raise StaleWork
    }
  self.remove_network(index).persist(write)
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

///|
/// Apply a remote receipt to the same causal checkpoint head used by local
/// saves. The acknowledged request text advances the baseline while any newer
/// locally persisted text remains in the checkpoint.
pub fn State::acknowledge(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  operation_id : @source_repository.OperationId,
  revision : @source_repository.SavedRevision,
) -> (Self, Attempt?) raise @source_repository.ReceiptMismatch {
  let write = self.head(durable).acknowledge(operation_id, revision)
  self.persist(write)
}

///|
fn State::active(
  self : Self,
  request_id : RequestId,
  checkpoint : @source_repository.SyncCheckpoint,
) -> (Int, Attempt, @source_repository.CheckpointWrite?) raise CompletionError {
  guard self.find_lane(checkpoint.account(), checkpoint.document().id())
    is Some(index) &&
    self.lanes[index].state is Storing(active, waiting) &&
    active.request_id == request_id &&
    active.write.checkpoint() == checkpoint else {
    raise StaleCompletion
  }
  (index, active, waiting)
}

///|
pub fn State::stored(
  self : Self,
  request_id : RequestId,
  checkpoint : @source_repository.SyncCheckpoint,
) -> (Self, Attempt?) raise CompletionError {
  let (index, _, waiting) = self.active(request_id, checkpoint)
  match waiting {
    None => (self.remove_lane(index), None)
    Some(write) => {
      let (self, attempt) = self.attempt(write)
      (self.replace_lane(index, Storing(attempt, None)), Some(attempt))
    }
  }
}

///|
pub fn State::failed(
  self : Self,
  request_id : RequestId,
  checkpoint : @source_repository.SyncCheckpoint,
) -> (Self, @source_repository.SyncCheckpoint) raise CompletionError {
  let (index, active, waiting) = self.active(request_id, checkpoint)
  let retained = match waiting {
    Some(next) => active.write.coalesce(next)
    None => active.write
  }
  (self.replace_lane(index, RetryPending(retained)), retained.checkpoint())
}

///|
pub fn State::retry_metadata(
  self : Self,
  checkpoint : @source_repository.SyncCheckpoint,
) -> (Self, Attempt?) {
  match self.find_lane(checkpoint.account(), checkpoint.document().id()) {
    Some(index) =>
      match self.lanes[index].state {
        RetryPending(retained) if retained.checkpoint().document() ==
          checkpoint.document() => self.persist(retained)
        RetryPending(_) => (self, None)
        Storing(_, _) => (self, None)
      }
    None => (self, None)
  }
}
