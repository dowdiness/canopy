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
pub struct DiscoveryId(Int) derive(Eq, Debug)

///|
pub struct OperationAttempt {
  priv id : Int
  priv account : @source_repository.AccountId
  priv document_id : @source_repository.DocumentId
} derive(Eq, Debug)

///|
pub fn OperationAttempt::account(self : Self) -> @source_repository.AccountId {
  self.account
}

///|
pub fn OperationAttempt::document_id(
  self : Self,
) -> @source_repository.DocumentId {
  self.document_id
}

///|
pub struct DeliveryAttempt {
  priv id : Int
  priv account : @source_repository.AccountId
  priv document_id : @source_repository.DocumentId
  priv operation_id : @source_repository.OperationId
} derive(Eq, Debug)

///|
pub fn DeliveryAttempt::account(self : Self) -> @source_repository.AccountId {
  self.account
}

///|
pub fn DeliveryAttempt::document_id(
  self : Self,
) -> @source_repository.DocumentId {
  self.document_id
}

///|
priv enum ReplicaRead {
  ResolveConflict(@source_repository.OperationId)
  Refresh(@source_repository.SavedRevision)
} derive(Eq, Debug)

///|
pub struct ReadAttempt {
  priv id : Int
  priv account : @source_repository.AccountId
  priv document_id : @source_repository.DocumentId
  priv read : ReplicaRead
} derive(Eq, Debug)

///|
pub fn ReadAttempt::account(self : Self) -> @source_repository.AccountId {
  self.account
}

///|
pub fn ReadAttempt::document_id(self : Self) -> @source_repository.DocumentId {
  self.document_id
}

///|
pub struct RecoveryAttempt {
  priv id : Int
  priv account : @source_repository.AccountId
  priv document_id : @source_repository.DocumentId
} derive(Eq, Debug)

///|
pub fn RecoveryAttempt::account(self : Self) -> @source_repository.AccountId {
  self.account
}

///|
pub fn RecoveryAttempt::document_id(
  self : Self,
) -> @source_repository.DocumentId {
  self.document_id
}

///|
pub struct SelectionIntent(Int) derive(Eq, Debug)

///|
pub struct Retry {
  priv account : @source_repository.AccountId
  priv document_id : @source_repository.DocumentId
  priv failed_attempt : Int
} derive(Eq, Debug)

///|
pub fn Retry::account(self : Self) -> @source_repository.AccountId {
  self.account
}

///|
pub fn Retry::document_id(self : Self) -> @source_repository.DocumentId {
  self.document_id
}

///|
pub enum Activity {
  Idle
  Working
  Retryable(Retry)
  Blocked
} derive(Eq, Debug)

///|
pub(all) enum Observation {
  Unknown
  Observed
  Unavailable
} derive(Eq, Debug)

///|
priv struct Selection {
  intent : SelectionIntent
  account : @source_repository.AccountId
  document_id : @source_repository.DocumentId
} derive(Eq, Debug)

///|
pub struct OpenAttempt {
  priv id : Int
  priv selection : Selection
} derive(Eq, Debug)

///|
pub fn OpenAttempt::account(self : Self) -> @source_repository.AccountId {
  self.selection.account
}

///|
pub fn OpenAttempt::document_id(self : Self) -> @source_repository.DocumentId {
  self.selection.document_id
}

///|
pub struct SelectionRetry {
  priv failed : OpenAttempt
} derive(Eq, Debug)

///|
pub fn SelectionRetry::account(self : Self) -> @source_repository.AccountId {
  self.failed.account()
}

///|
pub fn SelectionRetry::document_id(
  self : Self,
) -> @source_repository.DocumentId {
  self.failed.document_id()
}

///|
pub enum SelectionActivity {
  Idle
  Working
  Retryable(SelectionRetry)
} derive(Eq, Debug)

///|
pub(all) enum SelectionStep {
  Wait
  Fetch(OpenAttempt)
  Persist(@source_repository.ReplicaWrite)
} derive(Eq, Debug)

///|
/// A selection is a demand for an openable durable Replica. Only a remote-only
/// document owns a separate fetch lifecycle here; existing Replicas continue
/// through their ordinary network lane.
priv enum Opening {
  Idle
  Selected(Selection)
  Fetching(OpenAttempt)
  Failed(OpenAttempt)
  Persisting(Selection)
  Ready(Selection)
} derive(Eq, Debug)

///|
priv enum Work {
  Prepare(OperationAttempt, @source_repository.OperationDraft)
  Deliver(DeliveryAttempt)
  Read(ReadAttempt)
  Recover(RecoveryAttempt)
} derive(Eq, Debug)

///|
priv struct AccountCatalog {
  account : @source_repository.AccountId
  entries : Array[@source_repository.RemoteEntry]
  observation : Observation
  discovery : DiscoveryId?
} derive(Eq, Debug)

///|
fn AccountCatalog::AccountCatalog(
  account : @source_repository.AccountId,
) -> AccountCatalog {
  { account, entries: [], observation: Unknown, discovery: None, }
}

///|
priv enum Catalog {
  Unbound
  Bound(AccountCatalog)
} derive(Eq, Debug)

///|
fn Catalog::account(self : Self) -> @source_repository.AccountId? {
  match self {
    Unbound => None
    Bound(catalog) => Some(catalog.account)
  }
}

///|
priv enum NetworkState {
  Running(Work)
  RetryPending(Work)
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
  Restart(Int)
  NetworkBlocked
  Deliver(@source_repository.PendingOperation)
  Fetch(@source_repository.SavedRevision)
  Recover
  Plan(@source_repository.OperationDraft)
}

///|
pub(all) enum Action {
  CreateOperation(OperationAttempt)
  Deliver(DeliveryAttempt, @source_repository.PendingOperation)
  GetRemote(ReadAttempt)
  OpenRemote(OpenAttempt)
  CreateRecovery(RecoveryAttempt)
} derive(Eq, Debug)

///|
pub(all) suberror WorkError {
  StaleWork
} derive(Eq, Debug)

///|
pub struct State {
  priv session : Session
  priv catalog : Catalog
  priv opening : Opening
  priv network : Array[Network]
  priv last_lookup_id : Int
  priv last_discovery_id : Int
  priv last_attempt_id : Int
  priv last_selection_intent : Int
} derive(Eq, Debug)

///|
pub fn State::State() -> State {
  {
    session: SessionUnavailable,
    catalog: Catalog::Unbound,
    opening: Opening::Idle,
    network: [],
    last_lookup_id: 0,
    last_discovery_id: 0,
    last_attempt_id: 0,
    last_selection_intent: 0,
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
  let catalog = match result {
    Resolved(id, _) if self.catalog.account() == Some(id) => self.catalog
    Resolved(id, _) => Catalog::Bound(AccountCatalog(id))
    SignedOut => Catalog::Unbound
    AccountUnavailable => self.catalog
  }
  ({ ..self, session, catalog, }, account)
}

///|
pub fn State::observation(self : Self) -> Observation {
  match self.catalog {
    Bound(catalog) => catalog.observation
    Unbound => Observation::Unknown
  }
}

///|
pub fn State::discovering(self : Self) -> Bool {
  match self.catalog {
    Bound({ discovery: Some(_), .. }) => true
    Bound({ discovery: None, .. }) | Unbound => false
  }
}

///|
pub fn State::catalog(self : Self) -> Array[@source_repository.RemoteEntry] {
  match (self.session, self.catalog) {
    (Current(account, _), Bound(catalog)) if account == catalog.account =>
      catalog.entries
    _ => []
  }
}

///|
fn State::retained_remote_entry(
  self : Self,
  document_id : @source_repository.DocumentId,
) -> @source_repository.RemoteEntry? {
  guard self.catalog is Bound(catalog) else { return None }
  let entries = catalog.entries
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
    self.catalog.account() == Some(account) else {
    return None
  }
  self.retained_remote_entry(document_id)
}

///|
pub fn State::remote_head(
  self : Self,
  document_id : @source_repository.DocumentId,
) -> @source_repository.RemoteHead? {
  self.remote_entry(document_id).map(entry => entry.head())
}

///|
pub fn State::begin_discovery(self : Self) -> (Self, DiscoveryId?) {
  guard self.session is Current(account, _) &&
    self.catalog is Bound(catalog) &&
    catalog.account == account else {
    return (self, None)
  }
  let value = self.last_discovery_id + 1
  let id = DiscoveryId(value)
  (
    {
      ..self,
      catalog: Bound({ ..catalog, discovery: Some(id), }),
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
  let selection = match self {
    Idle => return self
    Selected(selection) | Persisting(selection) | Ready(selection) => selection
    Fetching(attempt) | Failed(attempt) => attempt.selection
  }
  guard selection.account == account &&
    selection.document_id == entry.document_id() else {
    return self
  }
  match entry {
    @source_repository.RemoteEntry::Deleted(_, _) => Idle
    Present(_, _, _) =>
      match self {
        Ready(_) => Selected(selection)
        Idle | Selected(_) | Fetching(_) | Failed(_) | Persisting(_) => self
      }
  }
}

///|
fn opening_observe_catalog(
  opening : Opening,
  account : @source_repository.AccountId,
  old : Array[@source_repository.RemoteEntry],
  fresh : Array[@source_repository.RemoteEntry],
  merged : Array[@source_repository.RemoteEntry],
) -> Opening {
  fresh.fold(init=opening, (opening, candidate) => {
    match
      merged
      .view()
      .search_by(entry => entry.document_id() == candidate.document_id()) {
      Some(index) => {
        let retained = merged[index]
        let previous = old
          .view()
          .search_by(entry => entry.document_id() == candidate.document_id())
          .map(previous => old[previous])
        if previous == Some(retained) {
          opening
        } else {
          opening.observe(account, retained)
        }
      }
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
  guard self.catalog is Bound(catalog) &&
    catalog.account == account &&
    remote_advances(self.retained_remote_entry(document_id), remote) &&
    remote.entry(document_id) is Some(entry) else {
    return self
  }
  let entries = merge_catalog(catalog.entries, [entry])
  {
    ..self,
    catalog: Bound({ ..catalog, entries, }),
    opening: opening_observe_catalog(
      self.opening,
      account,
      catalog.entries,
      [entry],
      entries,
    ),
  }
}

///|
pub fn State::discovered(
  self : Self,
  account : @source_repository.AccountId,
  id : DiscoveryId,
  entries : Array[@source_repository.RemoteEntry]?,
) -> (Self, Bool) {
  guard self.catalog is Bound(catalog) &&
    catalog.account == account &&
    catalog.discovery == Some(id) else {
    return (self, false)
  }
  let (observation, catalog_entries, opening) = match entries {
    Some(fresh) => {
      let merged = merge_catalog(catalog.entries, fresh)
      (
        Observation::Observed,
        merged,
        opening_observe_catalog(
          self.opening,
          account,
          catalog.entries,
          fresh,
          merged,
        ),
      )
    }
    None => (Observation::Unavailable, catalog.entries, self.opening)
  }
  (
    {
      ..self,
      catalog: Bound({
        ..catalog,
        entries: catalog_entries,
        observation,
        discovery: None,
      }),
      opening,
    },
    true,
  )
}

///|
fn State::attempt_id(self : Self) -> (Self, Int) {
  let value = self.last_attempt_id + 1
  ({ ..self, last_attempt_id: value, }, value)
}

///|
pub fn State::cancel_selection(self : Self) -> Self {
  { ..self, opening: Opening::Idle, }
}

///|
pub fn State::selection_activity(self : Self) -> SelectionActivity {
  match self.opening {
    Idle | Ready(_) => SelectionActivity::Idle
    Selected(_) | Fetching(_) | Persisting(_) => Working
    Failed(attempt) => Retryable({ failed: attempt, })
  }
}

///|
fn State::selected_revision(
  self : Self,
  selection : Selection,
) -> @source_repository.SavedRevision? {
  guard self.session is Current(account, _) &&
    account == selection.account &&
    self.remote_entry(selection.document_id)
    is Some(@source_repository.RemoteEntry::Present(_, revision, _)) else {
    return None
  }
  Some(revision)
}

///|
pub fn State::select(
  self : Self,
  document_id : @source_repository.DocumentId,
) -> Self {
  guard self.remote_entry(document_id)
    is Some(@source_repository.RemoteEntry::Present(_, _, _)) &&
    self.session is Current(account, _) else {
    return self
  }
  let intent_value = self.last_selection_intent + 1
  {
    ..self,
    opening: Selected({
      intent: SelectionIntent(intent_value),
      account,
      document_id,
    }),
    last_selection_intent: intent_value,
  }
}

///|
/// Derive one selection step from the current catalog and authoritative
/// Replica. Existing Replicas never start a second selection-specific GET.
pub fn State::advance_selection(
  self : Self,
  replica : @source_repository.DocumentReplica?,
) -> (Self, SelectionStep) {
  let selection = match self.opening {
    Selected(selection) | Persisting(selection) => selection
    Fetching(attempt) | Failed(attempt) if replica is Some(candidate) &&
      candidate.account() == attempt.selection.account &&
      candidate.document_id() == attempt.selection.document_id =>
      attempt.selection
    Idle | Fetching(_) | Failed(_) | Ready(_) => return (self, Wait)
  }
  guard self.selected_revision(selection) is Some(required) else {
    return ({ ..self, opening: Opening::Idle, }, Wait)
  }
  match replica {
    Some(replica) if replica.account() == selection.account &&
      replica.document_id() == selection.document_id =>
      match replica.open(required) {
        @source_repository.OpenStep::Ready =>
          ({ ..self, opening: Ready(selection), }, Wait)
        Persist(write) =>
          ({ ..self, opening: Persisting(selection), }, Persist(write))
        AwaitSync => ({ ..self, opening: Selected(selection), }, Wait)
        Unavailable => ({ ..self, opening: Opening::Idle, }, Wait)
      }
    Some(_) => ({ ..self, opening: Opening::Idle, }, Wait)
    None => {
      let (self, id) = self.attempt_id()
      let attempt : OpenAttempt = { id, selection, }
      ({ ..self, opening: Fetching(attempt), }, Fetch(attempt))
    }
  }
}

///|
pub fn State::opened(
  self : Self,
  attempt : OpenAttempt,
  remote : @source_repository.RemoteDocument,
) -> (Self, @source_repository.ReplicaWrite?) raise WorkError {
  let selection = attempt.selection
  guard self.opening == Fetching(attempt) else { raise StaleWork }
  guard self.selected_revision(selection) is Some(required) else {
    raise StaleWork
  }
  guard remote.revision() >= required.value() else {
    return ({ ..self, opening: Failed(attempt), }, None)
  }
  let self = self.observe_remote(
    selection.account,
    selection.document_id,
    remote,
  )
  match remote {
    @source_repository.RemoteDocument::Present(revision, text) => {
      let document = @source_repository.Document::create(
        selection.document_id,
        text,
      )
      let write = @source_repository.DocumentReplica::receive(
        selection.account,
        document,
        revision,
      ).store()
      ({ ..self, opening: Persisting(selection), }, Some(write))
    }
    Missing | Deleted(_) => ({ ..self, opening: Opening::Idle, }, None)
  }
}

///|
pub fn State::open_failed(
  self : Self,
  attempt : OpenAttempt,
) -> Self raise WorkError {
  guard self.opening == Fetching(attempt) else { raise StaleWork }
  { ..self, opening: Opening::Failed(attempt), }
}

///|
pub fn State::retry_selection(
  self : Self,
  retry : SelectionRetry,
) -> (Self, Action) raise WorkError {
  let failed = retry.failed
  let selection = failed.selection
  guard self.opening == Failed(failed) &&
    self.session is Current(account, _) &&
    account == selection.account &&
    self.selected_revision(selection) is Some(_) else {
    raise StaleWork
  }
  let (self, id) = self.attempt_id()
  let attempt : OpenAttempt = { id, selection, }
  ({ ..self, opening: Fetching(attempt), }, OpenRemote(attempt))
}

///|
pub fn State::selection(
  self : Self,
) -> (
  SelectionIntent,
  @source_repository.AccountId,
  @source_repository.DocumentId,
)? {
  match self.opening {
    Selected(selection) | Persisting(selection) | Ready(selection) =>
      Some((selection.intent, selection.account, selection.document_id))
    Fetching(attempt) | Failed(attempt) => {
      let selection = attempt.selection
      Some((selection.intent, selection.account, selection.document_id))
    }
    Idle => None
  }
}

///|
pub fn State::ready_selection(
  self : Self,
) -> (
  SelectionIntent,
  @source_repository.AccountId,
  @source_repository.DocumentId,
)? {
  match self.opening {
    Ready(selection) =>
      Some((selection.intent, selection.account, selection.document_id))
    Idle | Selected(_) | Fetching(_) | Failed(_) | Persisting(_) => None
  }
}

///|
pub fn State::complete_selection(
  self : Self,
  intent : SelectionIntent,
) -> Self raise WorkError {
  match self.opening {
    Ready(target) if target.intent == intent =>
      { ..self, opening: Opening::Idle, }
    Idle | Selected(_) | Fetching(_) | Failed(_) | Persisting(_) | Ready(_) =>
      raise StaleWork
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
pub fn State::activity(
  self : Self,
  replica : @source_repository.DocumentReplica,
) -> Activity {
  let account = replica.account()
  let document_id = replica.document_id()
  match self.find_network(account, document_id) {
    None => Idle
    Some(index) => {
      let task = self.network[index]
      guard task.state.accepts(replica) else { return Idle }
      match task.state {
        RetryPending(work) =>
          Retryable({
            account: task.account,
            document_id: task.document_id,
            failed_attempt: work.attempt_id(),
          })
        Blocked(_) => Blocked
        Running(_) => Working
      }
    }
  }
}

///|
/// Consume exactly the retry projected from the current network task. The
/// durable Replica is supplied by the aggregate after authoritative lookup.
pub fn State::retry(
  self : Self,
  durable : @source_repository.DocumentReplica,
  retry : Retry,
) -> (Self, Action) raise WorkError {
  guard durable.account() == retry.account &&
    durable.document_id() == retry.document_id &&
    self.session is Current(current, _) &&
    current == retry.account &&
    self.find_network(retry.account, retry.document_id) is Some(index) else {
    raise StaleWork
  }
  let task = self.network[index]
  guard task.state is RetryPending(work) &&
    work.attempt_id() == retry.failed_attempt &&
    work.accepts(durable) else {
    raise StaleWork
  }
  self.restart(index, work, durable)
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
        RetryPending(work) if work.accepts(replica) => Restart(index)
        RetryPending(_) => NoWork
        Blocked(_) => NetworkBlocked
        Running(_) => NetworkRunning
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
fn Work::attempt_id(self : Self) -> Int {
  match self {
    Prepare(attempt, _) => attempt.id
    Deliver(attempt) => attempt.id
    Read(attempt) => attempt.id
    Recover(attempt) => attempt.id
  }
}

///|
fn Work::accepts(
  self : Self,
  replica : @source_repository.DocumentReplica,
) -> Bool {
  match self {
    Prepare(_, draft) =>
      replica.directive() ==
      @source_repository.ReplicaDirective::CreateOperation(draft)
    Deliver(attempt) =>
      replica.directive()
      is @source_repository.ReplicaDirective::Send(operation) &&
      operation.operation_id() == attempt.operation_id
    Read({ read: ResolveConflict(operation_id), .. }) =>
      replica.directive()
      is @source_repository.ReplicaDirective::Send(operation) &&
      operation.operation_id() == operation_id
    Read({ read: Refresh(required), .. }) =>
      replica.document() is Some(_) &&
      replica.observed_revision() < required.value()
    Recover(_) =>
      replica.directive()
      is @source_repository.ReplicaDirective::RecoveryRequired
  }
}

///|
fn NetworkState::accepts(
  self : Self,
  replica : @source_repository.DocumentReplica,
) -> Bool {
  match self {
    Running(work) | RetryPending(work) => work.accepts(replica)
    Blocked(blocked) =>
      replica.directive() ==
      @source_repository.ReplicaDirective::CreateOperation(blocked)
  }
}

///|
fn Work::renew(self : Self, id : Int) -> Work {
  match self {
    Prepare(attempt, draft) =>
      Prepare(
        { id, account: attempt.account, document_id: attempt.document_id, },
        draft,
      )
    Deliver(attempt) =>
      Deliver({
        id,
        account: attempt.account,
        document_id: attempt.document_id,
        operation_id: attempt.operation_id,
      })
    Read(attempt) =>
      Read({
        id,
        account: attempt.account,
        document_id: attempt.document_id,
        read: attempt.read,
      })
    Recover(attempt) =>
      Recover({
        id,
        account: attempt.account,
        document_id: attempt.document_id,
      })
  }
}

///|
fn Work::action(
  self : Self,
  durable : @source_repository.DocumentReplica,
) -> Action raise WorkError {
  guard self.accepts(durable) else { raise StaleWork }
  match self {
    Prepare(attempt, _) => Action::CreateOperation(attempt)
    Deliver(attempt) => {
      guard durable.directive()
        is @source_repository.ReplicaDirective::Send(operation) else {
        raise StaleWork
      }
      Action::Deliver(attempt, operation)
    }
    Read(attempt) => Action::GetRemote(attempt)
    Recover(attempt) => Action::CreateRecovery(attempt)
  }
}

///|
fn State::restart(
  self : Self,
  index : Int,
  failed : Work,
  durable : @source_repository.DocumentReplica,
) -> (Self, Action) raise WorkError {
  guard self.network[index].state == RetryPending(failed) &&
    failed.accepts(durable) else {
    raise StaleWork
  }
  let (self, id) = self.attempt_id()
  let running = match (failed, self.newer_revision(durable)) {
    (Read(attempt), Some(current)) if attempt.read is Refresh(previous) =>
      Read({
        ..attempt,
        id,
        read: Refresh(
          if current.value() > previous.value() {
            current
          } else {
            previous
          },
        ),
      })
    _ => failed.renew(id)
  }
  let action = running.action(durable)
  (self.replace_network(index, Running(running)), action)
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
  let self = self.retain_compatible_network(durable)
  let account = durable.account()
  let document_id = durable.document_id()
  match self.next(durable) {
    Restart(index) => {
      guard self.network[index].state is RetryPending(work) else {
        abort("restart requires failed work")
      }
      let (self, action) = self.restart(index, work, durable) catch {
        _ => abort("compatible failed work must restart")
      }
      (self, Some(action))
    }
    Deliver(operation) => {
      let (self, id) = self.attempt_id()
      let attempt : DeliveryAttempt = {
        id,
        account,
        document_id,
        operation_id: operation.operation_id(),
      }
      let task : Network = {
        account,
        document_id,
        state: Running(Work::Deliver(attempt)),
      }
      (
        { ..self, network: self.network + [task], },
        Some(Action::Deliver(attempt, operation)),
      )
    }
    Fetch(revision) => {
      let (self, id) = self.attempt_id()
      let attempt : ReadAttempt = {
        id,
        account,
        document_id,
        read: ReplicaRead::Refresh(revision),
      }
      let task : Network = {
        account,
        document_id,
        state: Running(Work::Read(attempt)),
      }
      (
        { ..self, network: self.network + [task], },
        Some(Action::GetRemote(attempt)),
      )
    }
    Recover => {
      let (self, id) = self.attempt_id()
      let attempt : RecoveryAttempt = { id, account, document_id, }
      let task : Network = {
        account,
        document_id,
        state: Running(Work::Recover(attempt)),
      }
      (
        { ..self, network: self.network + [task], },
        Some(Action::CreateRecovery(attempt)),
      )
    }
    Plan(draft) => {
      let (self, id) = self.attempt_id()
      let attempt : OperationAttempt = { id, account, document_id, }
      let task : Network = {
        account,
        document_id,
        state: Running(Work::Prepare(attempt, draft)),
      }
      (
        { ..self, network: self.network + [task], },
        Some(Action::CreateOperation(attempt)),
      )
    }
    NoWork | NetworkRunning | NetworkBlocked => (self, None)
  }
}

///|
pub fn State::prepared(
  self : Self,
  attempt : OperationAttempt,
  durable : @source_repository.DocumentReplica,
  operation_id : @source_repository.OperationId,
) -> (Self, @source_repository.ReplicaWrite?) raise WorkError {
  guard self.find_network(durable.account(), durable.document_id())
    is Some(index) &&
    self.network[index].state is Running(Prepare(active, draft)) &&
    active == attempt &&
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
  attempt : OperationAttempt,
) -> Self raise WorkError {
  guard self.find_network(attempt.account, attempt.document_id) is Some(index) &&
    self.network[index].state is Running(work) &&
    work is Prepare(active, _) &&
    active == attempt else {
    raise StaleWork
  }
  self.replace_network(index, RetryPending(work))
}

///|
fn State::delivery(
  self : Self,
  durable : @source_repository.DocumentReplica,
  attempt : DeliveryAttempt,
) -> Int raise WorkError {
  guard self.find_network(durable.account(), durable.document_id())
    is Some(index) &&
    self.network[index].state is Running(Deliver(active)) &&
    active == attempt else {
    raise StaleWork
  }
  index
}

///|
pub fn State::acknowledged(
  self : Self,
  durable : @source_repository.DocumentReplica,
  attempt : DeliveryAttempt,
  revision : @source_repository.SavedRevision,
) -> (Self, @source_repository.ReplicaWrite?) raise WorkError {
  let index = self.delivery(durable, attempt)
  let write = durable.acknowledge(attempt.operation_id, revision) catch {
    _ => raise StaleWork
  }
  (self.remove_network(index), Some(write))
}

///|
pub fn State::delivery_failed(
  self : Self,
  durable : @source_repository.DocumentReplica,
  attempt : DeliveryAttempt,
) -> Self raise WorkError {
  let index = self.delivery(durable, attempt)
  self.replace_network(index, RetryPending(Work::Deliver(attempt)))
}

///|
pub fn State::revision_conflict(
  self : Self,
  durable : @source_repository.DocumentReplica,
  attempt : DeliveryAttempt,
) -> Self raise WorkError {
  let index = self.delivery(durable, attempt)
  let read : ReadAttempt = {
    id: attempt.id,
    account: attempt.account,
    document_id: attempt.document_id,
    read: ReplicaRead::ResolveConflict(attempt.operation_id),
  }
  self.replace_network(index, RetryPending(Work::Read(read)))
}

///|
fn State::remote_fetch(
  self : Self,
  durable : @source_repository.DocumentReplica,
  attempt : ReadAttempt,
) -> Int raise WorkError {
  guard self.find_network(durable.account(), durable.document_id())
    is Some(index) &&
    self.network[index].state.accepts(durable) &&
    self.network[index].state is Running(Read(active)) &&
    active == attempt else {
    raise StaleWork
  }
  index
}

///|
pub fn State::remote_failed(
  self : Self,
  durable : @source_repository.DocumentReplica,
  attempt : ReadAttempt,
) -> Self raise WorkError {
  let index = self.remote_fetch(durable, attempt)
  self.replace_network(index, RetryPending(Work::Read(attempt)))
}

///|
fn State::reject_delivery(
  self : Self,
  durable : @source_repository.DocumentReplica,
  attempt : DeliveryAttempt,
  block : Bool,
) -> (Self, @source_repository.ReplicaWrite?) raise WorkError {
  let index = self.delivery(durable, attempt)
  let write = durable.reject_operation(attempt.operation_id) catch {
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
  attempt : DeliveryAttempt,
) -> (Self, @source_repository.ReplicaWrite?) raise WorkError {
  guard durable.directive()
    is @source_repository.ReplicaDirective::Send(operation) &&
    operation.operation_id() == attempt.operation_id else {
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
  self.reject_delivery(durable, attempt, unchanged)
}

///|
pub fn State::operation_rejected(
  self : Self,
  durable : @source_repository.DocumentReplica,
  attempt : DeliveryAttempt,
) -> (Self, @source_repository.ReplicaWrite?) raise WorkError {
  self.reject_delivery(durable, attempt, false)
}

///|
fn reconcile(
  durable : @source_repository.DocumentReplica,
  read : ReplicaRead,
  remote : @source_repository.RemoteDocument,
) -> @source_repository.ReconcilePlan raise WorkError {
  match read {
    ReplicaRead::ResolveConflict(operation_id) =>
      durable.reject_conflict(operation_id, remote) catch {
        _ => raise StaleWork
      }
    Refresh(expected) => {
      guard remote.revision() >= expected.value() else { raise StaleWork }
      durable.reconcile(remote)
    }
  }
}

///|
pub fn State::received(
  self : Self,
  durable : @source_repository.DocumentReplica,
  attempt : ReadAttempt,
  remote : @source_repository.RemoteDocument,
) -> (Self, @source_repository.ReplicaWrite?) raise WorkError {
  let index = self.remote_fetch(durable, attempt)
  let self = self.observe_remote(
    durable.account(),
    durable.document_id(),
    remote,
  )
  let plan = reconcile(durable, attempt.read, remote)
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
  attempt : RecoveryAttempt,
  recovery_id : @source_repository.DocumentId,
) -> (Self, @source_repository.ReplicaWrite?) raise WorkError {
  guard self.find_network(durable.account(), durable.document_id())
    is Some(index) &&
    self.network[index].state.accepts(durable) &&
    self.network[index].state is Running(Recover(active)) &&
    active == attempt else {
    raise StaleWork
  }
  let write = durable.fork(recovery_id) catch { _ => raise StaleWork }
  (self.remove_network(index), Some(write))
}

///|
pub fn State::recovery_failed(
  self : Self,
  attempt : RecoveryAttempt,
) -> Self raise WorkError {
  guard self.find_network(attempt.account, attempt.document_id) is Some(index) &&
    self.network[index].state is Running(Recover(active)) &&
    active == attempt else {
    raise StaleWork
  }
  self.replace_network(index, RetryPending(Work::Recover(attempt)))
}
