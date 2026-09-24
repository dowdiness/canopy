///|
pub struct Attempt {
  priv id : Int
  priv write : @source_repository.ReplicaWrite
} derive(Eq, Debug)

///|
pub fn Attempt::write(self : Self) -> @source_repository.ReplicaWrite {
  self.write
}

///|
pub struct Retry {
  priv account : @source_repository.AccountId
  priv document_id : @source_repository.DocumentId
  priv failed_attempt : Int
} derive(Eq, Debug)

///|
pub(all) enum Status {
  Current
  Persisting
  Retryable(Retry, @source_repository.ReplicaFailure)
} derive(Eq, Debug)

///|
pub(all) enum Completion {
  Current(@source_repository.ReplicaWrite)
  Superseded(@source_repository.ReplicaWrite, Attempt)
  Retryable(
    @source_repository.ReplicaWrite,
    Retry,
    @source_repository.ReplicaFailure
  )
  Failed(@source_repository.ReplicaWrite, @source_repository.ReplicaFailure)
} derive(Eq, Debug)

///|
pub(all) suberror StaleAttempt {
  StaleAttempt
} derive(Eq, Debug)

///|
pub(all) suberror ExpiredRetry {
  ExpiredRetry
} derive(Eq, Debug)

///|
priv enum LaneState {
  Persisting(Attempt, @source_repository.ReplicaWrite?)
  Failed(
    Int,
    @source_repository.ReplicaWrite,
    @source_repository.ReplicaFailure
  )
} derive(Eq, Debug)

///|
priv struct Lane {
  account : @source_repository.AccountId
  document_id : @source_repository.DocumentId
  state : LaneState
} derive(Eq, Debug)

///|
pub struct State {
  priv lanes : Array[Lane]
  priv last_attempt_id : Int
} derive(Eq, Debug)

///|
pub fn State::State() -> State {
  { lanes: [], last_attempt_id: 0, }
}

///|
fn State::find(
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
  write : @source_repository.ReplicaWrite,
) -> (Self, Attempt) {
  let id = self.last_attempt_id + 1
  ({ ..self, last_attempt_id: id, }, { id, write, })
}

///|
fn State::replace(self : Self, index : Int, state : LaneState) -> Self {
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
fn State::remove(self : Self, index : Int) -> Self {
  let lanes = self.lanes.copy()
  lanes.remove(index) |> ignore
  { ..self, lanes, }
}

///|
/// Local edits branch from durable state after a failed write. The failed
/// candidate remains available only through its Retry capability.
pub fn State::editing_base(
  self : Self,
  durable : @source_repository.DocumentReplica,
) -> @source_repository.DocumentReplica {
  match self.find(durable.account(), durable.document_id()) {
    None => durable
    Some(index) =>
      match self.lanes[index].state {
        Persisting(_, Some(waiting)) => waiting.replica()
        Persisting(active, None) => active.write.replica()
        Failed(_, _, _) => durable
      }
  }
}

///|
/// Protocol outcomes apply to the newest candidate carrying their operation,
/// including a failed write. This preserves newer eligible text when an older
/// remote acknowledgment arrives later.
pub fn State::protocol_base(
  self : Self,
  durable : @source_repository.DocumentReplica,
) -> @source_repository.DocumentReplica {
  match self.find(durable.account(), durable.document_id()) {
    None => durable
    Some(index) =>
      match self.lanes[index].state {
        Persisting(_, Some(waiting)) => waiting.replica()
        Persisting(active, None) => active.write.replica()
        Failed(_, write, _) => write.replica()
      }
  }
}

///|
pub fn State::pending(
  self : Self,
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
) -> @source_repository.DocumentReplica? {
  match self.find(account, document_id) {
    None => None
    Some(index) =>
      Some(
        match self.lanes[index].state {
          Persisting(_, Some(waiting)) => waiting.replica()
          Persisting(active, None) => active.write.replica()
          Failed(_, write, _) => write.replica()
        },
      )
  }
}

///|
pub fn State::status(
  self : Self,
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
) -> Status {
  match self.find(account, document_id) {
    None => Current
    Some(index) =>
      match self.lanes[index].state {
        Persisting(_, _) => Status::Persisting
        Failed(failed_attempt, _, failure) =>
          Retryable({ account, document_id, failed_attempt, }, failure)
      }
  }
}

///|
pub fn State::submit(
  self : Self,
  write : @source_repository.ReplicaWrite,
) -> (Self, Attempt?) {
  let replica = write.replica()
  let account = replica.account()
  let document_id = replica.document_id()
  match self.find(account, document_id) {
    None => {
      let (self, attempt) = self.attempt(write)
      let lane : Lane = {
        account,
        document_id,
        state: Persisting(attempt, None),
      }
      ({ ..self, lanes: self.lanes + [lane], }, Some(attempt))
    }
    Some(index) =>
      match self.lanes[index].state {
        Persisting(active, waiting) => {
          let waiting = match waiting {
            Some(current) => current.coalesce(write)
            None => write
          }
          (self.replace(index, Persisting(active, Some(waiting))), None)
        }
        Failed(_, retained, _) => {
          let (self, attempt) = self.attempt(retained.coalesce(write))
          (self.replace(index, Persisting(attempt, None)), Some(attempt))
        }
      }
  }
}

///|
pub fn State::retry(
  self : Self,
  retry : Retry,
) -> (Self, Attempt) raise ExpiredRetry {
  guard self.find(retry.account, retry.document_id) is Some(index) &&
    self.lanes[index].state is Failed(failed_attempt, retained, _) &&
    failed_attempt == retry.failed_attempt else {
    raise ExpiredRetry
  }
  let (self, attempt) = self.attempt(retained)
  (self.replace(index, Persisting(attempt, None)), attempt)
}

///|
pub fn State::complete(
  self : Self,
  attempt : Attempt,
  result : Result[Unit, @source_repository.ReplicaFailure],
) -> (Self, Completion) raise StaleAttempt {
  let replica = attempt.write.replica()
  guard self.find(replica.account(), replica.document_id()) is Some(index) &&
    self.lanes[index].state is Persisting(active, waiting) &&
    active == attempt else {
    raise StaleAttempt
  }
  match result {
    Ok(_) =>
      match waiting {
        None => (self.remove(index), Current(active.write))
        Some(write) => {
          let (self, next) = self.attempt(write)
          (
            self.replace(index, Persisting(next, None)),
            Superseded(active.write, next),
          )
        }
      }
    Err(failure) => {
      if active.write is @source_repository.ReplicaWrite::PromoteSource(_) {
        return (self.remove(index), Failed(active.write, failure))
      }
      let retained = match waiting {
        Some(write) => active.write.coalesce(write)
        None => active.write
      }
      (
        self.replace(index, Failed(active.id, retained, failure)),
        Retryable(
          retained,
          {
            account: replica.account(),
            document_id: replica.document_id(),
            failed_attempt: active.id,
          },
          failure,
        ),
      )
    }
  }
}
