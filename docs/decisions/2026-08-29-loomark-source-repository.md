# Loomark persists authoritative Sources and derives its Catalog in memory

**Date:** 2026-08-29

**Status:** Accepted; amended by
[Loomark document deletion](2026-08-31-loomark-document-deletion.md) and
[#1305](https://github.com/dowdiness/canopy/issues/1305) for the Editing
Document convenience record and
[#1307](https://github.com/dowdiness/canopy/issues/1307) for Derived name and
Markdown import/export.

**Issue:** [#1303](https://github.com/dowdiness/canopy/issues/1303)

**Related:**

- [Loomark document deletion](2026-08-31-loomark-document-deletion.md)
- [Resume the Editing Document](https://github.com/dowdiness/canopy/issues/1305)
- [Import / Export Markdown](https://github.com/dowdiness/canopy/issues/1307)
- [Loomark separates current and saved text](2026-08-24-loomark-source-first-interactive-contract.md)
- [Loomark standard Rabbita Text app](../plans/2026-08-24-loomark-standard-rabbita-text-app.md)

## Context

Loomark needs stable identities and independently replaceable Saved text for
several Editing Documents. One malformed or unsupported record must not hide
other valid documents, and the legacy `active` record must remain preserved
when its ownership is uncertain.

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
- legacy `active` and old record shapes are unsupported and remain preserved;
- every other key is preserved and reported as unknown or unsupported.

No Catalog record is persisted. A Source value contains exactly `document_id` and `text`, and the key suffix must equal the payload identity. Opening scans the complete store through Rabbita's IndexedDB provider, decodes each Source independently, derives a name from parsed text, sorts valid Documents lexically by ID, and returns a deterministic in-memory Catalog. Only after that `SavedDocuments` value is accepted does a
valid `editing-document` value select its exact Source. Missing, empty,
non-string, stale, or unknown values use the deterministic first Source without
repair or storage writes. Malformed values, identity mismatches, unsupported
schemas, unknown records, and unsupported key or value types remain stored and
cannot hide valid Sources.

An empty repository opens an ephemeral New document and writes no Source until
its first Document text change is accepted by Browser storage.

Import strictly decodes selected bytes as UTF-8, consumes an initial UTF-8 BOM,
normalizes CRLF and CR to LF, and preserves every other decoded character.
Filename, extension, and media type do not affect admission. Each accepted
Import receives a fresh Document ID, becomes the Editing Document, and enters
the existing New-origin save lane immediately rather than waiting for Autosave.
A storage failure retains the imported text as an Unsaved document and uses the
existing Retry action. An accepted Import supersedes an unfinished ephemeral New
action; Loomark does not queue either operation or bind file-read completion to
the prior Activation.

Legacy `active` values and old three-field records are not readable or migrated; they remain in IndexedDB and are reported as observed repository issues.

A normal save commits only the accepted Source and applies its acknowledged
change to the latest immutable SavedDocuments after transaction completion.
New document creation reserves an identity without storage. Occupied keys
prevent overwrite of records observed by `SavedDocuments`; concurrent-tab
coordination remains out of scope. Save completions are fenced by Document ID
and exact Source candidate before they update durability state.

Activating a saved Source separately replaces `editing-document` with its
Document ID. The write has no application state, queue, retry, or completion
message and makes no Source durability claim. Startup, ephemeral New document
activation, and the first save of a New document do not write the record.

The JS-only repository uses MoonBit core Json construction/stringification for
the fixed `document_id`/`text` Source object. The strict MoonBit decoder remains
the schema and identity authority; serialized byte spelling is not a public or
canonical hash contract.

Name derivation uses only parser-recognized Markdown structure. It flattens
readable heading, paragraph, quote, list, task, code, image-label, and supported
inline content, takes the first non-empty readable line, and skips structures
without readable text. It does not parse raw HTML, scan raw lines as a fallback,
or infer frontmatter when the Markdown parser has no frontmatter extension.

`SavedDocuments` derives its Catalog from accepted Document text. The
application may derive a temporary name from current unsaved text for Recent
documents presentation, but that projection is neither persisted nor another
Source authority.

Repository issues describe malformed, unsupported, or unknown records observed
by the latest complete scan rather than an append-only incident history.
Storage failures remain operation results rather than permanent repository
issues.

## Consequences

- Replacing one document performs one Source transaction and never rewrites
  unrelated Source or metadata records.
- Source discovery, corruption isolation, and Catalog derivation have one
  authority path.
- No missing, stale, malformed, or unwritable metadata record can hide a Source.
- The open path still pays the essential complete-scan and name-derivation cost.
- Fixed-schema Source encoding uses MoonBit core JSON escaping while strict
  decode and exact text round trips remain covered in MoonBit.
- Unsupported legacy records cannot shadow a valid two-field Source and remain
  preserved for explicit future recovery.
- Text input updates only page-local Document state; serialization and IndexedDB
  work begin when the Autosave lane emits a persistence decision.
- The best-effort Editing Document record cannot become a second in-memory
  selection authority or a Source durability claim.
- Import adds no second persistence path: accepted text uses the existing
  New-origin save, failure, and Retry behavior.
- SavedDocuments reconciliation observes the exact observed `source/v1` keys, including
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
