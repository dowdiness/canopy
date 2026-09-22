///|
fn preserve_recovery(
  older : ReplicaWrite,
  newer : ReplicaWrite,
) -> ReplicaWrite {
  match (older, newer) {
    (Fork(_, recovery), Store(replica)) =>
      if replica.recovery_document_id() == Some(recovery.id()) {
        Fork(replica, recovery)
      } else {
        Store(replica)
      }
    (PromoteSource(_), Store(replica)) => PromoteSource(replica)
    (_, Remove(replica)) => Remove(replica)
    (_, newer) => newer
  }
}

///|
pub fn ReplicaWrite::coalesce(
  self : Self,
  newer : ReplicaWrite,
) -> ReplicaWrite {
  preserve_recovery(self, newer)
}
