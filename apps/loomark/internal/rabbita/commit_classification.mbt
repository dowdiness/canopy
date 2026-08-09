///|
/// Classify one atomic commit by the explicit CRDT version frontier.
///
/// Source equality is consulted only after the frontier advances: a real
/// operation can preserve visible text while still counting as one accepted
/// commit. The function is pure; the shell owns editor and archive effects.
fn classify_commit(
  model : DriverModel,
  receipt : @markdown.MarkdownCommitReceipt,
) -> (DriverModel, Bool, Bool) {
  let document = match receipt.result() {
    @markdown.Applied(document, _) => document
    @markdown.Unchanged(document) => document
  }
  let accepted = receipt.after_version() != model.document_version
  if !accepted {
    return ({ ..model, document, }, false, false)
  }
  let changed = document.source() != model.document.source()
  (
    {
      ..model,
      document,
      document_version: receipt.after_version(),
      raw_selection: None,
      source_revision: if changed {
        model.source_revision + 1
      } else {
        model.source_revision
      },
      committed_change_count: model.committed_change_count + 1,
    },
    true,
    changed,
  )
}

///|
/// Advance counters when reconstruction cannot provide a usable snapshot but
/// the captured portable source/version still proves acceptance.
fn classify_recovered_source(
  model : DriverModel,
  source : String,
  version : @markdown.MarkdownDocumentVersion,
) -> DriverModel {
  let accepted = version != model.document_version
  if !accepted {
    return model
  }
  let changed = source != model.document.source()
  {
    ..model,
    document_version: version,
    raw_selection: None,
    source_revision: if changed {
      model.source_revision + 1
    } else {
      model.source_revision
    },
    committed_change_count: model.committed_change_count + 1,
  }
}

///|
/// Install the fresh snapshot after reopening a failed editor. The failed
/// editor itself is never queried for a snapshot.
fn classify_recovered_frontier(
  model : DriverModel,
  document : @markdown.MarkdownDocumentSnapshot,
  version : @markdown.MarkdownDocumentVersion,
) -> (DriverModel, Bool) {
  let accepted = version != model.document_version
  if !accepted {
    return ({ ..model, document, }, false)
  }
  let changed = document.source() != model.document.source()
  (
    {
      ..model,
      document,
      document_version: version,
      raw_selection: None,
      source_revision: if changed {
        model.source_revision + 1
      } else {
        model.source_revision
      },
      committed_change_count: model.committed_change_count + 1,
    },
    changed,
  )
}
