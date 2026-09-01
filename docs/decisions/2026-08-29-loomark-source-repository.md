# Loomark persists authoritative Sources and derives its Catalog in memory

**Date:** 2026-08-29

**Status:** Accepted; amended by
[Loomark document deletion](2026-08-31-loomark-document-deletion.md) and
[#1305](https://github.com/dowdiness/canopy/issues/1305) for the Editing
Document convenience record.

**Issue:** [#1303](https://github.com/dowdiness/canopy/issues/1303)

**Related:**

- [Loomark document deletion](2026-08-31-loomark-document-deletion.md)
- [Resume the Editing Document](https://github.com/dowdiness/canopy/issues/1305)
- [Loomark separates current and saved text](2026-08-24-loomark-source-first-interactive-contract.md)
- [Loomark standard Rabbita Text app](../plans/2026-08-24-loomark-standard-rabbita-text-app.md)

## Context

Loomark needs stable identities and independently replaceable Saved text for
several Editing Documents. One malformed or unsupported record must not hide
other valid documents, and migration from the legacy `active` record must not
delete recoverable data when ownership is uncertain.

Document names are presentation derived from Canonical Markdown. Opening must
scan every Source to discover valid documents, isolate corruption, and preserve
unsupported schemas. That same scan can derive the complete Catalog. Persisting
an additional aggregate Catalog would not avoid Source scanning or Markdown
name derivation; it would add unrelated metadata rewrites, repair transactions,
cache-specific failures, and a crash window to every normal save.

## Decision

The `loomark` IndexedDB database remains at version `1` with object store
`documents`. Versioned keys inside that store define the repository:

- `source/v1/<document-id>` is one independently authoritative Source;
- `editing-document` is an optional Document ID string used only to choose the
  initial Editing Document after Source reconciliation;
- `active` is read only as the legacy migration source;
- every other key is preserved and reported as unknown or unsupported.

No Catalog record is persisted. A Source value contains `document_id`, `text`,
and Change order, and the key suffix must equal the payload identity. Opening
scans the complete store through Rabbita's IndexedDB cursor provider, decodes
each Source independently, derives the first usable ATX H1 name, sorts valid
Sources by newest Change order with a Document ID tie break, and returns a
deterministic in-memory Catalog. Only after that Snapshot is accepted does a
valid `editing-document` value select its exact Source. Missing, empty,
non-string, stale, or unknown values use the deterministic first Source without
repair or storage writes. Malformed values, identity mismatches, unsupported
schemas, unknown records, and unsupported key or value types remain stored and
cannot hide valid Sources.

An empty repository opens an ephemeral New document and writes no Source until
its first Document text change is accepted by Browser storage.

A valid legacy `active` value is moved with one atomic transaction containing a
Source put and legacy delete. If a valid target Source exists, that Source wins
and only `active` is deleted. A corrupt target preserves both records and is
reported as a migration collision. Mutation failure rolls back the target put
and preserves `active`.

A normal save commits only the accepted Source and applies its acknowledged
change to the latest immutable RepositorySnapshot after transaction completion.
New document creation reserves an identity without storage. Occupied keys
prevent overwrite of records observed by the Snapshot; concurrent-tab
coordination remains out of scope. Save completions are fenced by Document ID
and exact Source candidate before they update durability state.

Activating a saved Source separately replaces `editing-document` with its
Document ID. The write has no application state, queue, retry, or completion
message and makes no Source durability claim. Startup, ephemeral New document
activation, and the first save of a New document do not write the record.

The JS-only repository uses the browser's native JSON encoder for the fixed
`document_id`/`text` Source object. The strict MoonBit decoder remains the schema
and identity authority; serialized byte spelling is not a public or canonical
hash contract.

A normal save may parse only the previous Source's first terminated line to
derive an ephemeral prefix certificate. It reuses the current Catalog name only
when that prefix parses without diagnostics or CST error/incomplete metadata,
its first direct Document child is a line-terminated ATX H1 at offset zero, it
derives the same name, and it is exactly equal in the new Source. Name
derivation remains independent: recovered headings may still produce the same
Catalog name while receiving no certificate. Every uncertified case runs the
complete Markdown derivation and preserves its fail-closed behavior. No
certificate is retained or persisted, so it cannot become Source authority.

Repository issues describe currently observed conditions rather than an
append-only incident history. A name-derivation issue for a document disappears
after a later committed Source derives safely. Storage failures remain operation
results rather than permanent repository issues.

## Consequences

- Replacing one document performs one Source transaction and never rewrites
  unrelated Source or metadata records.
- Source discovery, corruption isolation, and Catalog derivation have one
  authority path.
- No missing, stale, malformed, or unwritable metadata record can hide a Source.
- The open path still pays the essential complete-scan and name-derivation cost.
- Suffix-only saves after a certified first-line title avoid redundant complete
  Markdown name derivation; changed, nested, missing, recovered, or EOF titles
  retain the full path.
- Fixed-schema Source encoding uses the deployment target's mature JSON escaping
  while strict decode and exact text round trips remain covered in MoonBit.
- The legacy record cannot shadow a successfully migrated Source indefinitely.
- A blocked migration may open a fresh baseline while preserving both collision
  records for later recovery.
- Text input continues to update only Browser-draft state; complete-source name
  derivation, serialization, and IndexedDB work begin at `SaveRequested`.
- The best-effort Editing Document record cannot become a second in-memory
  selection authority or a Source durability claim.
- RepositorySnapshots retain the exact observed `source/v1` keys, including
  malformed and unsupported records.
- A persisted discovery accelerator requires a separate measured decision and a
  validation protocol that cannot become document authority.

## Rejected alternatives

**One aggregate JSON value for all documents.** Rejected because one malformed
or failed replacement would affect every document and each save would rewrite
unrelated Sources.

**Persist an aggregate Catalog.** Rejected because opening still has to scan and
validate every Source and derive every name. The aggregate would add an O(number
of documents) metadata rewrite after each Source save without reducing the
measured open work.

**Persist per-document Catalog sidecars.** Rejected until a measured partial-list
or startup requirement exists. Sidecars would duplicate derived state and need
a freshness protocol before they could safely skip name derivation.

**Store Source and derived metadata in one normal-save transaction.** Rejected
because metadata failure must not roll back otherwise valid Saved text.

**Add hashes, generations, an object-store index, or another object store.**
Rejected because no measured product target requires a second validation or
schema-migration mechanism.

**Introduce a mutable repository actor or generic storage port.** Rejected
because the application reducer already owns per-document operation ordering and
completion fencing, while Rabbita owns the only production adapter, transaction
admission and lifecycle, and failure classification.

**Implement IndexedDB scanning in Canopy.** Rejected because Rabbita owns
connection lifecycle, cursor progression, transaction completion, abort
settlement, and DOMException classification.
