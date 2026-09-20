CREATE TABLE loomark_document_with_preview (
  owner TEXT NOT NULL REFERENCES user(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision > 0),
  text TEXT,
  preview TEXT,
  deleted INTEGER NOT NULL CHECK (deleted IN (0, 1)),
  PRIMARY KEY (owner, id),
  CHECK (
    (deleted = 0 AND text IS NOT NULL AND preview IS NOT NULL) OR
    (deleted = 1 AND text IS NULL AND preview IS NULL)
  )
);

INSERT INTO loomark_document_with_preview (
  owner, id, revision, text, preview, deleted
)
SELECT owner, id, revision, text, substr(text, 1, 80), deleted
FROM loomark_document;

DROP TABLE loomark_document;
ALTER TABLE loomark_document_with_preview RENAME TO loomark_document;
