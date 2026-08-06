///|
/// The only supported application archive schema version.
pub const LOOMARK_ARCHIVE_SCHEMA_VERSION : Int = 1

///|
/// An opaque logical identity for one Loomark document.
pub struct LoomarkDocumentId {
  priv value : String
} derive(Eq, Debug)

///|
pub(all) suberror LoomarkDocumentIdError {
  Empty
}

///|
/// Construct a non-empty logical document identity.
pub fn LoomarkDocumentId::from_string(
  value : String,
) -> LoomarkDocumentId raise LoomarkDocumentIdError {
  if value.is_empty() {
    raise LoomarkDocumentIdError::Empty
  }
  { value, }
}

///|
/// Return the validated identity for repository keying.
pub fn LoomarkDocumentId::value(self : Self) -> String {
  self.value
}

///|
/// The capture-side failures for an application-owned archive.
pub(all) suberror LoomarkArchiveCaptureError {
  HistoryUnavailable(detail~ : String)
}

///|
/// The decode-side failures for an application-owned archive.
pub(all) suberror LoomarkArchiveDecodeError {
  UnsupportedNewerVersion(version~ : String)
  MalformedEnvelope(detail~ : String)
  EmptyDocumentId
  CorruptHistory(detail~ : String)
  PortableTextHistoryMismatch
  InvalidValidationAgentId
}

///|
/// A versioned Loomark document archive with an opaque history payload.
pub struct LoomarkDocumentArchive {
  priv document_id : LoomarkDocumentId
  priv portable_markdown : String
  priv history : @markdown.MarkdownDocumentHistory
}

///|
pub fn LoomarkDocumentArchive::document_id(self : Self) -> LoomarkDocumentId {
  self.document_id
}

///|
pub fn LoomarkDocumentArchive::portable_markdown(self : Self) -> String {
  self.portable_markdown
}

///|
pub fn LoomarkDocumentArchive::history(
  self : Self,
) -> @markdown.MarkdownDocumentHistory {
  self.history
}

///|
/// Capture portable text and the complete opaque history from a valid editor.
///
/// The editor already owns the source/history invariant. Persisted input is
/// reopened and checked only at the decode boundary below.
pub fn LoomarkDocumentArchive::capture(
  document_id~ : LoomarkDocumentId,
  editor~ : @markdown.MarkdownEditor,
) -> LoomarkDocumentArchive raise LoomarkArchiveCaptureError {
  let portable_markdown = editor.portable_markdown()
  let history = editor.history_since() catch {
    _ =>
      raise LoomarkArchiveCaptureError::HistoryUnavailable(
        detail="history export failed",
      )
  }
  { document_id, portable_markdown, history }
}

///|
/// Encode the exact v1 envelope deterministically.
pub fn LoomarkDocumentArchive::to_json_string(self : Self) -> String {
  Json::object({
    "schema_version": Json::string(LOOMARK_ARCHIVE_SCHEMA_VERSION.to_string()),
    "document_id": Json::string(self.document_id.value()),
    "portable_markdown": Json::string(self.portable_markdown),
    "history": Json::string(self.history.to_json_string()),
    "extensions": Json::empty_object(),
  }).stringify()
}

///|
/// Decode and validate a v1 archive with a caller-owned fresh validation ID.
///
/// Field uniqueness follows core JSON's semantic-object `Map` behavior: a
/// duplicate member overwrites the earlier value. Canonical Loomark encoding
/// emits each field once, and strict validation below is over that semantic
/// object rather than lexical JSON member occurrences.
pub fn LoomarkDocumentArchive::from_json_string(
  json : String,
  validation_agent_id~ : String,
) -> LoomarkDocumentArchive raise LoomarkArchiveDecodeError {
  let value = @json.parse(json) catch {
    _ =>
      raise LoomarkArchiveDecodeError::MalformedEnvelope(detail="invalid JSON")
  }
  let fields = match value {
    Json::Object(fields) => fields
    _ =>
      raise LoomarkArchiveDecodeError::MalformedEnvelope(
        detail="archive must be a JSON object",
      )
  }
  let version = archive_schema_version(fields)
  if version != LOOMARK_ARCHIVE_SCHEMA_VERSION {
    raise LoomarkArchiveDecodeError::MalformedEnvelope(
      detail="unsupported archive schema version",
    )
  }
  validate_archive_fields(fields)
  let document_id = match fields.get("document_id") {
    Some(Json::String(value)) =>
      LoomarkDocumentId::from_string(value) catch {
        _ => raise LoomarkArchiveDecodeError::EmptyDocumentId
      }
    _ =>
      raise LoomarkArchiveDecodeError::MalformedEnvelope(
        detail="document_id must be a non-empty string",
      )
  }
  let portable_markdown = match fields.get("portable_markdown") {
    Some(Json::String(value)) => value
    _ =>
      raise LoomarkArchiveDecodeError::MalformedEnvelope(
        detail="portable_markdown must be a string",
      )
  }
  let history_json = match fields.get("history") {
    Some(Json::String(value)) => value
    _ =>
      raise LoomarkArchiveDecodeError::MalformedEnvelope(
        detail="history must be a string",
      )
  }
  let history = @markdown.MarkdownDocumentHistory::from_json_string(
    history_json,
  ) catch {
    _ =>
      raise LoomarkArchiveDecodeError::CorruptHistory(
        detail="history codec rejected payload",
      )
  }
  if validation_agent_id.is_empty() {
    raise LoomarkArchiveDecodeError::InvalidValidationAgentId
  }
  validate_decoded(portable_markdown, history, validation_agent_id)
  { document_id, portable_markdown, history }
}

///|
fn archive_schema_version(
  fields : Map[String, Json],
) -> Int raise LoomarkArchiveDecodeError {
  match fields.get("schema_version") {
    Some(Json::String(version)) =>
      if version == LOOMARK_ARCHIVE_SCHEMA_VERSION.to_string() {
        LOOMARK_ARCHIVE_SCHEMA_VERSION
      } else if !version.is_empty() &&
        !version.has_prefix("0") &&
        version.all(c => c.is_ascii_digit()) {
        raise LoomarkArchiveDecodeError::UnsupportedNewerVersion(version~)
      } else {
        raise LoomarkArchiveDecodeError::MalformedEnvelope(
          detail="schema_version must be the exact string \"1\"",
        )
      }
    _ =>
      raise LoomarkArchiveDecodeError::MalformedEnvelope(
        detail="schema_version must be a string",
      )
  }
}

///|
fn validate_archive_fields(
  fields : Map[String, Json],
) -> Unit raise LoomarkArchiveDecodeError {
  if fields.length() != 5 ||
    !fields.contains("schema_version") ||
    !fields.contains("document_id") ||
    !fields.contains("portable_markdown") ||
    !fields.contains("history") ||
    !fields.contains("extensions") {
    raise LoomarkArchiveDecodeError::MalformedEnvelope(
      detail="archive has missing or unknown top-level fields",
    )
  }
  match fields.get("extensions") {
    Some(Json::Object(extensions)) if extensions.is_empty() => ()
    _ =>
      raise LoomarkArchiveDecodeError::MalformedEnvelope(
        detail="extensions must be an empty object in schema version 1",
      )
  }
}

///|
fn validate_decoded(
  portable_markdown : String,
  history : @markdown.MarkdownDocumentHistory,
  validation_agent_id : String,
) -> Unit raise LoomarkArchiveDecodeError {
  let reopened = @markdown.MarkdownEditor::open(
    agent_id=validation_agent_id,
    history~,
  ) catch {
    @markdown.MarkdownArchiveError::InvalidAgentId =>
      raise LoomarkArchiveDecodeError::InvalidValidationAgentId
    _ =>
      raise LoomarkArchiveDecodeError::CorruptHistory(
        detail="history could not be reopened",
      )
  }
  if reopened.portable_markdown() != portable_markdown {
    raise LoomarkArchiveDecodeError::PortableTextHistoryMismatch
  }
}
