///|
/// Classify one atomic editor commit into domain terms: an Applied result is
/// a history-changing commit and advances both revision counters; an
/// Unchanged result is a history no-op and leaves them untouched. The
/// classification is independent of source equality — Applied advances
/// history whether or not the resulting Markdown source differs.
///
/// Pure: no editor, no DOM, no commands. The calling shell owns selection
/// extraction, preview demand, and the `@repository.history_trigger`
/// persistence decision.
fn classify_commit(
  model : DriverModel,
  result : @markdown.MarkdownCommitResult,
) -> (DriverModel, Bool) {
  match result {
    @markdown.Applied(document, _) =>
      (
        {
          ..model,
          document,
          source_revision: model.source_revision + 1,
          committed_change_count: model.committed_change_count + 1,
        },
        true,
      )
    @markdown.Unchanged(document) => ({ ..model, document, }, false)
  }
}
