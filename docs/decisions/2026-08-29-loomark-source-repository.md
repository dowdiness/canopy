# Loomark persists authoritative Sources and rebuilds its Catalog

**Date:** 2026-08-29

**Status:** Accepted

**Issue:** [#1303](https://github.com/dowdiness/canopy/issues/1303)

**Related:**

- [Loomark separates current and saved text](2026-08-24-loomark-source-first-interactive-contract.md)
- [Loomark standard Rabbita Text app](../plans/2026-08-24-loomark-standard-rabbita-text-app.md)

## Context

Loomark originally persisted one document under the IndexedDB key `active`.
That shape could restore one editor, but it could not discover several documents,
isolate corruption to one document, or replace one document independently. A
single aggregate value would retain the same failure domain and make each save
rewrite unrelated documents.

Document names are presentation data derived from Canonical Markdown. Treating
a persisted name index as document authority would let stale or corrupt cache
state hide valid saved text. Migration also has to preserve the existing
`active` value if its target is uncertain or a transaction aborts.

## Decision

The existing `loomark` database remains at version `1` with object store
`documents`. Versioned keys inside that store define the repository:

- `source/v1/<document-id>` is one independently authoritative Source;
- `catalog/v1` is a rebuildable cache of Document IDs and derived names;
- `active` is read only as the legacy migration source.

A Source value retains exactly the fields `document_id` and `text`. The key
suffix must equal the payload identity. Opening scans the complete store through
Rabbita's IndexedDB cursor provider, decodes each Source independently, derives
the first usable ATX H1 name, sorts by Document ID, and compares the result with
the persisted Catalog. Unsupported schemas, unknown records, malformed values,
and identity mismatches are preserved and reported without hiding valid
Sources.

Missing, stale, or malformed Catalog state is replaced in a separate
transaction. Catalog write failure is non-fatal because the complete scan can
rebuild it later. The current single-editor application selects the first valid
Document ID lexically.

An empty repository creates a UUID-backed Source whose exact text is
`# Untitled\n`. Loomark does not use a fallback identity source.

A valid legacy `active` value is moved with one atomic transaction containing a
Source put and legacy delete. If a valid target Source exists, that Source wins
and only `active` is deleted. A corrupt target preserves both records and is
reported as a migration collision. Mutation failure rolls back the target put
and preserves `active`.

A normal save derives the next Catalog outside the Raw input task, commits the
Source first, and then writes the Catalog separately. Source transaction
completion establishes durability. Catalog failure does not roll back or
misreport the committed Source. Save completions are fenced by Document ID and
source candidate before they update application state.

## Consequences

- Each document can be replaced and validated without rewriting unrelated
  Sources.
- Catalog membership and names cannot become a second document authority.
- Corruption has record-level scope when at least one valid Source remains.
- Crashes between Source and Catalog transactions may leave stale cache state;
  the next open repairs it.
- The legacy record cannot shadow a successfully migrated Source indefinitely.
- A blocked migration may open a fresh baseline while preserving both collision
  records for later recovery.
- Text input continues to update only browser-draft state; scanning, Markdown
  name derivation, serialization, and IndexedDB work begin at `SaveRequested`.
- Persistent active-document selection remains deferred to #1305.

## Rejected alternatives

**One aggregate JSON value for all documents.** Rejected because one malformed
or failed replacement would affect every document and each save would rewrite
unrelated Sources.

**Treat the Catalog as authority.** Rejected because stale or malformed cache
state could hide valid Sources.

**Store Source and Catalog in one normal save transaction.** Rejected because a
cache quota or write failure would roll back otherwise durable text.

**Add an object store or increment the database version.** Rejected because the
existing string store and versioned key namespace provide the required
isolation without schema upgrade risk.

**Implement IndexedDB scanning in Canopy.** Rejected because Rabbita already
owns connection lifecycle, transaction completion, failure classification, and
FIFO command ordering.
