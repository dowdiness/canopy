///|
fn preserve_recovery(
  older : CheckpointWrite,
  newer : CheckpointWrite,
) -> CheckpointWrite {
  match (older, newer) {
    (CheckpointAndRecovery(_, recovery), CheckpointOnly(checkpoint)) =>
      match checkpoint.phase {
        SyncPhase::Conflict(recovery_identity) if recovery_identity.id() ==
          recovery.id() => CheckpointAndRecovery(checkpoint, recovery)
        Ready | Sending(_) | RemoteUpdate(_) | Conflict(_) =>
          CheckpointOnly(checkpoint)
      }
    (_, newer) => newer
  }
}

///|
pub fn CheckpointWrite::coalesce(
  self : Self,
  newer : CheckpointWrite,
) -> CheckpointWrite {
  preserve_recovery(self, newer)
}
