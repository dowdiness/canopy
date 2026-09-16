CREATE TABLE loomark_document (
  owner TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision > 0),
  text TEXT,
  deleted INTEGER NOT NULL CHECK (deleted IN (0, 1)),
  PRIMARY KEY (owner, id),
  CHECK ((deleted = 0 AND text IS NOT NULL) OR (deleted = 1 AND text IS NULL))
);

-- Receipts contain only a request fingerprint, never retained document text.
CREATE TABLE loomark_receipt (
  owner TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  operation_id TEXT NOT NULL,
  document_id TEXT NOT NULL,
  request_hash TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision > 0),
  PRIMARY KEY (owner, operation_id)
);
