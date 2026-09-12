# Loomark deletes documents through per-document persistence lanes

**Date:** 2026-08-31

**Status:** Accepted

**Issue:** [#1306](https://github.com/dowdiness/canopy/issues/1306)

**Partially supersedes:** [Loomark persists authoritative Sources and derives its Catalog in memory](2026-08-29-loomark-source-repository.md)

## Context

Loomark must permanently delete any valid document without first opening it,
without allowing an older Autosave to recreate it in the same tab, and without
blocking unrelated document editing. Deleting the open document also needs a
deterministic fallback.

The earlier repository returned a precomputed complete snapshot from each
write, assumed one write in flight, and created a persisted `# Untitled\n`
Source when no valid Source existed. Those choices could not represent
concurrent per-document persistence, page-local recent fallback, or an
ephemeral New document after deleting the final Source.

## Decision

Source records remain the independently authoritative Saved-document records,
and the Catalog remains a rebuildable in-memory view rather than a persisted
aggregate. A `source/v1` value contains only Document ID and exact Saved text.
Earlier three-field values are preserved as unsupported records rather than
guessed or migrated. Reload reconstructs `SavedDocuments` in lexical Document
ID order; no persisted recency metadata exists. During a page lifetime, an
accepted text change, Import, or promoted New moves that Document to the front.
Selection and save acknowledgment do not reorder it.

A repository with zero valid Sources is a normal `SavedDocuments` value. It does
not create a Source as a repair. The application opens an ephemeral New
document and reserves its identity without writing Browser storage. Deleting
the open document opens the first available Document in page-local recent order,
or a New document when none remains, while preserving the current Editor mode.

The Application Model owns pure per-document persistence lanes. Operations for
different Document IDs may proceed independently; operations for one Document
ID are ordered. A confirmed Delete waits for an already-running Autosave for the
same target to settle, regardless of save success, and then becomes the final
operation for that target. It prevents later same-tab Autosaves from being
issued.

Repository effects return acknowledged document changes such as a stored Source
or deleted Document ID, not a precomputed replacement `SavedDocuments` value.
The reducer applies each acknowledged change to the latest immutable
`SavedDocuments`, so completion order cannot erase an unrelated document's
acknowledged change.
Delete requests carry an identity separate from the editor `Activation`.
Unknown Document IDs fail before IndexedDB work.

Delete confirmation starts only after active IME composition ends and identifies
the target with the same content presentation as its Recent documents entry.
Saved and unsaved targets use the same confirmation. The row context menu uses
Rabbita `context_menu`; its overflow control uses `dropdown_menu`; both share one
actions view and emit the same target-specific message. Confirmation uses
Rabbita `alert_dialog` only to obtain consent and closes when accepted. Pending,
failure, and retry state live in the Application Model rather than in the
modal.

A non-open Pending deletion is shown on its Recent documents entry while the
open document remains editable. If the target is open, it remains visible but
cannot be edited or switched away from until the deletion settles. Failure
preserves the Source, `SavedDocuments`, text, Preview, selection, and
confirmation data needed for retry.

Rabbita `Store::delete` reports exactly one typed outcome after transaction
commit or failure. A successful completion applies the deletion to the latest
in-memory snapshot and removes the record; a failure preserves the Source and
restores the target to retryable availability. Loomark does not duplicate that
lifecycle with a watchdog, probe, or Unknown outcome. A reload performs a full
scan and reconstructs durable truth.

Uncoordinated browser tabs remain outside this guarantee. A later write from
another tab may recreate a document deleted in this tab. Malformed,
unsupported, and otherwise unavailable records are not Delete document targets
and remain preserved.

## Consequences

- Delete does not require Trash, a durable tombstone, a persisted Catalog, or a
  mutable repository actor.
- Empty repositories, New-document promotion, page-local recency, and
  acknowledged document changes are part of this contract.
- The Raw input task updates text and in-memory order only; serialization,
  IndexedDB, and list-content preparation remain outside it.
- Same-document persistence is serialized without serializing unrelated
  documents.
- A pending deletion blocks only its target; unrelated Documents remain
  editable and retain independent persistence lanes.
- Context-menu and overflow entry points reuse Rabbita's high-level components;
  Loomark does not add DOM or command escape hatches.

## Rejected alternatives

A persisted replacement Source for the final deletion was rejected because an
unedited New document is not yet a Loomark document. Global write
serialization was rejected because unrelated document saving and deletion are
independent. Aggregate-state completion was rejected because concurrent
acknowledgments can overwrite one another. Durable tombstones and tab locks were
rejected because cross-tab coordination remains out of scope. Keeping an alert
dialog open for the transaction lifetime was rejected because it would
unnecessarily block unrelated editing.
