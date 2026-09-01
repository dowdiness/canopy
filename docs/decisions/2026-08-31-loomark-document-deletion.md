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

The existing repository returns a precomputed complete
`RepositorySnapshot` from each write, assumes one write in flight, orders the
Catalog lexically by Document ID, and creates a persisted `# Untitled\n` Source
when no valid Source exists. Those choices cannot represent concurrent
per-document persistence, most-recently-changed fallback, or an ephemeral New
document after deleting the final Source.

## Decision

Source records remain the independently authoritative Saved-document records,
and the Catalog remains a rebuildable in-memory view rather than a persisted
aggregate. Before the first multi-document release, `source/v1` is redefined to
contain Document ID, exact Saved text, and an opaque Change order. Earlier
development-only two-field values are preserved as unsupported records rather
than guessed or migrated. Change order is issued when Document text changes,
using browser time with a per-tab monotonic floor seeded above the loaded
maximum; ties are broken deterministically by Document ID. It orders Recent
documents but is neither displayed nor treated as a trustworthy cross-tab
clock.

A repository with zero valid Sources is a normal `RepositorySnapshot`. It does
not create a Source as a repair. The application opens an ephemeral New
document, reserves its identity without writing Browser storage, and promotes it
to a Loomark document on its first text change. Deleting the open document opens
the most recently changed remaining document, or a New document when none
remains, while preserving the current Editor mode.

The Application Model owns pure per-document persistence lanes. Operations for
different Document IDs may proceed independently; operations for one Document
ID are ordered. A confirmed Delete waits for an already-running Autosave for the
same target to settle, regardless of save success, and then becomes the final
operation for that target. It prevents later same-tab Autosaves from being
issued.

Repository effects return acknowledged document changes such as a stored Source
or deleted Document ID, not a precomputed replacement Snapshot.
The reducer applies each acknowledged change to the latest immutable Snapshot,
so completion order cannot erase an unrelated document's acknowledged change.
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
preserves the Source, Snapshot, text, Preview, selection, and confirmation data
needed for retry.

A missing acknowledgment triggers an automatic Browser storage check after a
bounded interval; elapsed time alone proves neither success nor failure. If the
check also fails to settle within a bounded interval, the target enters Unknown
deletion outcome. Loomark isolates that target from editing and Autosave, opens
the most recently changed remaining document or a New document, and lets other
work continue. A late failure restores the target's availability without
changing the currently open document; a later success or full scan resolves
durable truth.

Uncoordinated browser tabs remain outside this guarantee. A later write from
another tab may recreate a document deleted in this tab. Malformed,
unsupported, and otherwise unavailable records are not Delete document targets
and remain preserved.

## Consequences

- Delete does not require Trash, a durable tombstone, a persisted Catalog, or a
  mutable repository actor.
- Empty repositories, New-document promotion, Change order, and acknowledged
  document changes must land before Delete document can satisfy this contract.
- The Raw input task updates text and in-memory order only; serialization,
  IndexedDB, and list-content preparation remain outside it.
- Same-document persistence is serialized without serializing unrelated
  documents.
- Pending storage cannot make the entire application permanently unusable;
  uncertain targets are isolated without inventing a success or failure.
- Context-menu and overflow entry points reuse Rabbita's high-level components;
  Loomark does not add DOM or command escape hatches.

## Rejected alternatives

A persisted replacement Source for the final deletion was rejected because an
unedited New document is not yet a Loomark document. Global write
serialization was rejected because unrelated document saving and deletion are
independent. Full-Snapshot completion was rejected because concurrent
acknowledgments can overwrite one another. Durable tombstones and tab locks were
rejected because cross-tab coordination remains out of scope. Keeping an alert
dialog open for the transaction lifetime was rejected because it blocks
unrelated editing and can make a lost callback appear to freeze the app.
