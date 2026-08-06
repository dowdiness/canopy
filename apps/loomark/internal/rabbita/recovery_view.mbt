///|
/// Categories shown when standalone recovery is blocked.
priv enum RecoveryCategory {
  StorageUnavailable
  StorageReadFailed
  EditorInitializationFailed
  UnsupportedArchive
  CorruptArchive
  ArchiveOverLimit
  IncompleteArchive
}

///|
/// Stable, non-editable recovery application for an unreadable local archive.
fn recovery_view(category : RecoveryCategory) -> @rabbita_runtime.Html {
  let (title, message, name) = match category {
    RecoveryCategory::StorageUnavailable =>
      (
        "Local document storage is unavailable", "The saved document was preserved, but local storage cannot be read.",
        "storage-unavailable",
      )
    RecoveryCategory::StorageReadFailed =>
      (
        "The saved document could not be read", "The saved document was preserved, but local storage returned an error.",
        "storage-read-failed",
      )
    RecoveryCategory::EditorInitializationFailed =>
      (
        "Loomark could not start the editor", "No document was replaced. Reload the page to try again.",
        "editor-initialization-failed",
      )
    RecoveryCategory::UnsupportedArchive =>
      (
        "This saved document cannot be opened", "The saved document uses an archive format this Loomark version does not support.",
        "unsupported-archive",
      )
    RecoveryCategory::CorruptArchive =>
      (
        "The saved document could not be opened safely", "The saved document was preserved because its archive is not valid.",
        "corrupt-archive",
      )
    RecoveryCategory::ArchiveOverLimit =>
      (
        "The saved document is too large to reopen", "The saved document was preserved because it exceeds the local restore policy.",
        "archive-over-limit",
      )
    RecoveryCategory::IncompleteArchive =>
      (
        "The saved document is incomplete", "The saved document was preserved because its history is incomplete.",
        "incomplete-archive",
      )
  }
  @html.div(
    id="loomark-recovery-root",
    attrs=@html.Attrs::build()
      .role("alert")
      .data_set("loomark-recovery-category", name),
    style=[
      "min-height:100vh;box-sizing:border-box;display:grid;place-items:center;padding:2rem;background:oklch(0.968 0.008 85);color:oklch(0.24 0.018 265)",
    ],
    @html.div(
      id="loomark-recovery-panel",
      attrs=@html.Attrs::build().data_set("loomark-recovery", "blocked"),
      style=[
        "width:min(100%,36rem);display:grid;gap:0.75rem;padding:2rem;border:1px solid oklch(0.86 0.012 85);border-radius:0.5rem;background:oklch(0.991 0.004 85)",
      ],
      [
        @html.h1(id="loomark-recovery-title", title),
        @html.p(id="loomark-recovery-message", message),
      ],
    ),
  )
}

///|
/// Build a static recovery app without an editor or storage command.
fn recovery_application(category : RecoveryCategory) -> @rabbita_runtime.App {
  @rabbita_runtime.new(() => {
    @rabbita_runtime.Val::constant(recovery_view(category))
  })
}
