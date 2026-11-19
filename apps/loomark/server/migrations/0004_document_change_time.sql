-- Every present document carries the client's Change time for its text, in
-- milliseconds since the epoch; a tombstone has none. Documents saved before
-- this migration get the epoch, which keeps their existing (Document ID)
-- order until they next change.
CREATE TABLE loomark_document_with_change_time (
  owner TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision > 0),
  text TEXT,
  preview TEXT,
  changed_at INTEGER,
  deleted INTEGER NOT NULL CHECK (deleted IN (0, 1)),
  PRIMARY KEY (owner, id),
  CHECK (
    (deleted = 0 AND text IS NOT NULL AND preview IS NOT NULL AND changed_at IS NOT NULL) OR
    (deleted = 1 AND text IS NULL AND preview IS NULL AND changed_at IS NULL)
  )
);

INSERT INTO loomark_document_with_change_time (
  owner, id, revision, text, preview, changed_at, deleted
)
SELECT owner, id, revision, text, preview, CASE deleted WHEN 0 THEN 0 END, deleted
FROM loomark_document;

DROP TABLE loomark_document;
ALTER TABLE loomark_document_with_change_time RENAME TO loomark_document;
