///|
fn preserve_recovery(
  older : ReplicaWrite,
  newer : ReplicaWrite,
) -> ReplicaWrite {
  match (older, newer) {
    (StoreWithRecovery(_, recovery), Store(replica)) =>
      match replica.phase {
        ReplicaPhase::Conflict(recovery_identity) if recovery_identity.id() ==
          recovery.id() => StoreWithRecovery(replica, recovery)
        Ready | Sending(_) | Available(_) | Diverged(_) | Conflict(_) =>
          Store(replica)
      }
    (PromoteSource(_), Store(replica)) => PromoteSource(replica)
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
