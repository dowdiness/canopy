///|
/// Canonical data captured from an editor whose parser is no longer usable.
/// Every field is obtained from parser-independent façade/archive APIs.
priv struct RecoveryDocument {
  document_id : @archive.LoomarkDocumentId
  source : String
  version : @markdown.MarkdownDocumentVersion
  history : @markdown.MarkdownDocumentHistory
}

///|
fn capture_recovery_document(
  document_id : @archive.LoomarkDocumentId,
  editor : @markdown.MarkdownEditor,
) -> RecoveryDocument raise {
  let source = editor.portable_markdown()
  let version = editor.version()
  let history = editor.history_since()
  { document_id, source, version, history }
}

///|
/// Make exactly one fresh writer/parser pair from the captured complete
/// archive. The caller swaps the session only after this function succeeds.
fn reopen_recovery_document(
  recovery : RecoveryDocument,
  writer_prefix : String,
) -> (@markdown.MarkdownEditor, @md_markdown.MarkdownSemanticAttachment, String) raise {
  let writer_id = @archive_storage.fresh_id(writer_prefix)
  let reopened = @repository.reopen_local_history(
    recovery.history,
    document_id=recovery.document_id,
    agent_id=writer_id,
    policy=@repository.LocalRestorePolicy::trusted(),
  )
  (reopened.editor(), reopened.attachment(), writer_id)
}
