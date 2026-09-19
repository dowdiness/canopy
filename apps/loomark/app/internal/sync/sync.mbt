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
  Delivering(@source_repository.OperationId)
  ConflictPending(@source_repository.OperationId)
  FetchingRemote(@source_repository.OperationId)
  Recovering(@source_repository.OperationId, @source_repository.RemoteDocument)
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
    @source_repository.DocumentId,
  )
  Deliver(
    @source_repository.AccountId,
    @source_repository.DocumentId,
    @source_repository.PendingOperation,
  )
  FetchRemote(
    @source_repository.AccountId,
    @source_repository.DocumentId,
    @source_repository.OperationId,
  )
} derive(Eq, Debug)

///|
pub(all) enum ConflictAction {
  Persisting(Attempt?)
  CreateRecovery
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
  priv lanes : Array[Lane]
  priv network : Array[Network]
  priv last_lookup_id : Int
  priv last_request_id : Int
  priv last_plan_id : Int
} derive(Eq, Debug)

///|
pub fn State::State() -> State {
  {
    session: SessionUnavailable,
    lanes: [],
    network: [],
    last_lookup_id: 0,
    last_request_id: 0,
    last_plan_id: 0,
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
    { ..self, session: Resolving(request_id), last_lookup_id: request_id, },
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
  ({ ..self, session, }, account)
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
      if i == index { { ..task, state, } } else { task }
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
      let lane : Lane = {
        account,
        document_id,
        state: Storing(attempt, None),
      }
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
  let self = match self.find_network(durable.account(), durable.document().id()) {
    Some(index) if self.network[index].state is (Planning(_, _) | Blocked) =>
      self.remove_network(index)
    _ => self
  }
  let head = self.head(durable)
  match head.edit(text) {
    Some(write) => self.persist(write)
    None =>
      match self.find_lane(durable.account(), durable.document().id()) {
        Some(index) =>
          match self.lanes[index].state {
            RetryPending(retained) => self.persist(retained)
            Storing(_, _) => (self, None)
          }
        None => (self, None)
      }
  }
}

///|
/// Schedule only work whose prerequisite checkpoint is already durable.
pub fn State::schedule(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
) -> (Self, Action?) {
  let account = durable.account()
  let document_id = durable.document().id()
  guard self.find_lane(account, document_id) is None else {
    return (self, None)
  }
  match self.find_network(account, document_id) {
    Some(index) =>
      return match self.network[index].state {
        ConflictPending(operation_id) =>
          (
            self.replace_network(index, FetchingRemote(operation_id)),
            Some(Action::FetchRemote(account, document_id, operation_id)),
          )
        Planning(_, _) | Delivering(_) | FetchingRemote(_) | Recovering(_, _) | Blocked =>
          (self, None)
      }
    None => ()
  }
  match durable.directive() {
    @source_repository.SyncDirective::SaveRequired => {
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
    Send(operation) => {
      let task : Network = {
        account,
        document_id,
        state: Delivering(operation.operation_id()),
      }
      (
        { ..self, network: self.network + [task], },
        Some(Action::Deliver(account, document_id, operation)),
      )
    }
    Synchronized | UpdateAvailable(_) | Conflict(_, _) => (self, None)
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
    self.network[index].state is Planning(active, generation) && active == id &&
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
    Some(index) if self.network[index].state is Planning(active, _) && active == id =>
      self.remove_network(index)
    _ => self
  }
}

///|
fn State::delivery(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  operation_id : @source_repository.OperationId,
) -> Int raise WorkError {
  guard self.find_network(durable.account(), durable.document().id())
    is Some(index) &&
    self.network[index].state is Delivering(active) && active == operation_id else {
    raise StaleWork
  }
  index
}

///|
pub fn State::acknowledged(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  operation_id : @source_repository.OperationId,
  revision : @source_repository.SavedRevision,
) -> (Self, Attempt?) raise WorkError {
  let index = self.delivery(durable, operation_id)
  self.remove_network(index).acknowledge(durable, operation_id, revision) catch {
    _ => raise StaleWork
  }
}

///|
pub fn State::delivery_failed(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  operation_id : @source_repository.OperationId,
) -> Self raise WorkError {
  let index = self.delivery(durable, operation_id)
  self.remove_network(index)
}

///|
pub fn State::revision_conflict(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  operation_id : @source_repository.OperationId,
) -> Self raise WorkError {
  let index = self.delivery(durable, operation_id)
  self.replace_network(index, ConflictPending(operation_id))
}

///|
fn State::remote_fetch(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  operation_id : @source_repository.OperationId,
) -> Int raise WorkError {
  guard self.find_network(durable.account(), durable.document().id())
    is Some(index) &&
    self.network[index].state is FetchingRemote(active) &&
    active == operation_id else {
    raise StaleWork
  }
  index
}

///|
pub fn State::remote_failed(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  operation_id : @source_repository.OperationId,
) -> Self raise WorkError {
  let index = self.remote_fetch(durable, operation_id)
  self.replace_network(index, ConflictPending(operation_id))
}

///|
fn State::reject_delivery(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  operation_id : @source_repository.OperationId,
  block : Bool,
) -> (Self, Attempt?) raise WorkError {
  let index = self.delivery(durable, operation_id)
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
  operation_id : @source_repository.OperationId,
) -> (Self, Attempt?) raise WorkError {
  let head = self.head(durable)
  guard head.directive() is @source_repository.SyncDirective::Send(operation) &&
    operation.operation_id() == operation_id else {
    raise StaleWork
  }
  let unchanged = match operation.content() {
    @source_repository.PendingContent::Save(text) => head.document().text() == text
    Delete => true
  }
  self.reject_delivery(durable, operation_id, unchanged)
}

///|
pub fn State::operation_rejected(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  operation_id : @source_repository.OperationId,
) -> (Self, Attempt?) raise WorkError {
  self.reject_delivery(durable, operation_id, false)
}

///|
pub fn State::rejected(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  operation_id : @source_repository.OperationId,
  remote : @source_repository.RemoteDocument,
) -> (Self, ConflictAction) raise WorkError {
  let index = self.remote_fetch(durable, operation_id)
  let plan = self.head(durable).reject_conflict(operation_id, remote) catch {
    _ => raise StaleWork
  }
  match plan {
    @source_repository.ReconcilePlan::Unchanged =>
      (self.remove_network(index), ConflictAction::Persisting(None))
    Persist(write) => {
      let (self, attempt) = self.remove_network(index).persist(write)
      (self, ConflictAction::Persisting(attempt))
    }
    ConflictDetected(_) =>
      (
        self.replace_network(index, Recovering(operation_id, remote)),
        ConflictAction::CreateRecovery,
      )
  }
}

///|
pub fn State::recover(
  self : Self,
  durable : @source_repository.SyncCheckpoint,
  operation_id : @source_repository.OperationId,
  recovery_id : @source_repository.DocumentId,
) -> (Self, Attempt?) raise WorkError {
  guard self.find_network(durable.account(), durable.document().id())
    is Some(index) &&
    self.network[index].state is Recovering(active, remote) &&
    active == operation_id else {
    raise StaleWork
  }
  let plan = self.head(durable).reject_conflict(operation_id, remote) catch {
    _ => raise StaleWork
  }
  guard plan is @source_repository.ReconcilePlan::ConflictDetected(draft) else {
    raise StaleWork
  }
  let write = draft.preserve(recovery_id) catch { _ => raise StaleWork }
  self.remove_network(index).persist(write)
}

///|
pub fn State::recovery_failed(
  self : Self,
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
  operation_id : @source_repository.OperationId,
) -> Self {
  match self.find_network(account, document_id) {
    Some(index) if self.network[index].state
      is Recovering(active, _) && active == operation_id =>
      self.remove_network(index)
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
