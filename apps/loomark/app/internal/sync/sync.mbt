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
pub(all) suberror CompletionError {
  StaleCompletion
} derive(Eq, Debug)

///|
pub struct State {
  priv session : Session
  priv lanes : Array[Lane]
  priv last_lookup_id : Int
  priv last_request_id : Int
} derive(Eq, Debug)

///|
pub fn State::State() -> State {
  {
    session: SessionUnavailable,
    lanes: [],
    last_lookup_id: 0,
    last_request_id: 0,
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
      if i == index { { ..lane, state, } } else { lane }
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
pub fn State::persist(
  self : Self,
  write : @source_repository.CheckpointWrite,
) -> (Self, Attempt?) {
  let checkpoint = write.checkpoint()
  let account = checkpoint.account()
  let document_id = checkpoint.document().id()
  match self.find_lane(account, document_id) {
    None => {
      let (self, attempt) = self.attempt(write)
      let lane = { account, document_id, state: Storing(attempt, None), }
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
) -> Self raise CompletionError {
  let (index, active, waiting) = self.active(request_id, checkpoint)
  let retained = match waiting {
    Some(next) => active.write.coalesce(next)
    None => active.write
  }
  self.replace_lane(index, RetryPending(retained))
}
