///|
/// All queries are scoped to the verified account supplied by the host.
pub async fn list(db : @d1.Database, owner : String, after : String?) -> Page {
  let rows = db
    .prepare(
      "SELECT id, revision, deleted FROM loomark_document WHERE owner = ? AND id > ? ORDER BY id LIMIT 101",
      [Text(owner), Text(after.unwrap_or(""))],
    )
    .all()
  let documents = rows[:rows.length().min(100)].map(decode_metadata)
  let next = if rows.length() > 100 { Some(documents[99].id) } else { None }
  { documents: documents[:], next, }
}

///|
pub async fn open(db : @d1.Database, owner : String, id : String) -> Document? {
  match
    db
    .prepare(
      "SELECT id, revision, text, deleted FROM loomark_document WHERE owner = ? AND id = ?",
      [Text(owner), Text(id)],
    )
    .first() {
    Some(row) => Some(decode_document(row))
    None => None
  }
}

///|
pub async fn commit(
  db : @d1.Database,
  owner : String,
  id : String,
  mutation : Mutation,
) -> CommitResult {
  let deleted = if mutation.text is None { 1.0 } else { 0.0 }
  let text_json = match mutation.text {
    Some(text) => text.to_json()
    None => Json::null()
  }
  let payload : Json = [
    id.to_json(),
    mutation.base_revision.to_json(),
    text_json,
  ]
  let hash = @crypto.sha256(payload.stringify())
  let next = mutation.base_revision + 1.0
  let text_parameter = match mutation.text {
    Some(text) => @d1.Value::Text(text)
    None => @d1.Value::Null
  }
  // D1, not a pre-read in application code, enforces the atomic CAS. Admission,
  // document write and receipt commit together; retries keep the original receipt.
  let results = db.batch([
    db.prepare(
      (
        #|INSERT INTO loomark_receipt (owner, operation_id, document_id, request_hash, revision)
        #|SELECT ?, ?, ?, ?, ?
        #|WHERE (? = 0 AND ? = 0 AND NOT EXISTS (
        #|  SELECT 1 FROM loomark_document WHERE owner = ? AND id = ?
        #|)) OR EXISTS (
        #|  SELECT 1 FROM loomark_document WHERE owner = ? AND id = ? AND revision = ? AND deleted = 0
        #|)
        #|ON CONFLICT (owner, operation_id) DO NOTHING
      ),
      [
        Text(owner),
        Text(mutation.operation_id),
        Text(id),
        Text(hash),
        Number(next),
        Number(mutation.base_revision),
        Number(deleted),
        Text(owner),
        Text(id),
        Text(owner),
        Text(id),
        Number(mutation.base_revision),
      ],
    ),
    db.prepare(
      (
        #|INSERT INTO loomark_document (owner, id, revision, text, deleted)
        #|SELECT ?, ?, ?, ?, ? FROM loomark_receipt
        #|WHERE owner = ? AND operation_id = ? AND request_hash = ?
        #|ON CONFLICT (owner, id) DO UPDATE SET
        #|  revision = excluded.revision, text = excluded.text, deleted = excluded.deleted
        #|WHERE loomark_document.revision = ? AND loomark_document.deleted = 0
      ),
      [
        Text(owner),
        Text(id),
        Number(next),
        text_parameter,
        Number(deleted),
        Text(owner),
        Text(mutation.operation_id),
        Text(hash),
        Number(mutation.base_revision),
      ],
    ),
    db.prepare(
      "SELECT request_hash, revision FROM loomark_receipt WHERE owner = ? AND operation_id = ?",
      [Text(owner), Text(mutation.operation_id)],
    ),
  ])
  match results[2][:] {
    [] => Conflict
    [
      {
        "request_hash": String(accepted_hash),
        "revision": Number(revision, ..),
        ..
      },
    ] if valid_revision(revision, saved=true) =>
      if accepted_hash == hash {
        Saved(revision~)
      } else {
        OperationReused
      }
    _ => raise InvalidStoredData
  }
}
