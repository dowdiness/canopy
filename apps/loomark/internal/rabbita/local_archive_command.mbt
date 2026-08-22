///|
/// Build the sole one-shot command for an immutable local archive write.
///
/// Keeping this adapter seam shared by bootstrap, normal commits, retries, and
/// pending promotion makes completion correlation and persistence tracing
/// consistent across every write path.
fn local_archive_write_command(
  pending : @repository.LocalArchivePendingWrite?,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  match pending {
    Some(pending) => {
      projection_trace_persistence_phase(PROJECTION_TRACE_PHASE_H7)
      @archive_storage.replace(pending, completed=completion => {
        emit(Archive(completion))
      })
    }
    None => @rabbita_runtime.none
  }
}
