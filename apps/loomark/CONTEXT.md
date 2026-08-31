# Loomark

Loomark is a browser Markdown Text editor. This glossary describes only the
current product.

## Language

**Loomark document**:
The Markdown entity edited in Loomark. It has an identity and text.
_Avoid_: file, buffer, session

**Document text**:
The current Markdown text. Text input updates it immediately.
_Avoid_: canonical source, draft text, surface, surface text

**Editor mode**:
A user-selected way to edit, inspect, or combine views of one Document text. A
mode never owns a second text authority.
_Avoid_: layout, workspace

**Text mode**:
The editor mode that shows the textarea and hides Preview.
_Avoid_: source mode, raw mode

**Preview**:
A read-only parse-derived view of Document text. It may lag behind Document text
and never determines editing or saving. Loomark explicitly enables GFM task-list
semantics here; task checkboxes display Document text state and remain disabled.
Ordinary unresolved reference candidates render as text. Genuine raw/recovered
regions render escaped author source without parser labels or inline diagnostics.
_Avoid_: rendered document, accepted text

**Preview mode**:
The editor mode that shows Preview while preserving the hidden textarea and its
browser-owned editing state.
_Avoid_: reading mode

**Split mode**:
The editor mode that shows the textarea and the same Preview together with a
resizable divider.
_Avoid_: dual editor, two-pane editor

**Preview preparation**:
Creating one long-lived syntax Parser after Preview or Split is selected for
the first time. Preparation is skipped when a document remains in Text mode.
_Avoid_: warm-up, preloading

**Preview refresh**:
Reading one coherent syntax snapshot, lowering its captured source directly to
MarkdownIR without reconstructing the document from CST tokens, and replacing
Preview from the latest committed Document text. After the Parser transition,
lowering waits for a 24 ms candidate-text quiet window so rapid changes normally
produce one visible update.
_Avoid_: projection refresh, render loop

**Stale Preview**:
The last successful Preview retained after a newer refresh fails. Loomark marks
it as stale; it never becomes Document text.
_Avoid_: fallback document, recovered text

**Saved text**:
The most recent Document text successfully written to browser storage. It may
be older than the current Document text.
_Avoid_: edit history, backup

**Source repository**:
The IndexedDB-backed collection of independently authoritative Source records.
Opening scans and reconciles the collection, then derives its in-memory Catalog.
_Avoid_: archive, aggregate document record, alternate storage

**Source record**:
One versioned `source/v1/<document-id>` record containing a Document ID and its
exact Saved text.
_Avoid_: catalog entry, session, backup

**Catalog**:
The deterministic in-memory view of Document IDs and names derived from valid
Source records. It is rebuilt on open and advances only after Source commit.
_Avoid_: persisted metadata, document authority, index of truth

**Autosave**:
Saving the current Document text after 250 ms of quiet or after one
non-restarting 2,000 ms maximum-wait timer becomes processable. Checkpoint epoch
identifies the dirty interval; quiet revision identifies its latest committed
edit even when text returns to an earlier value. IME composition defers
persistence until its committed result. A hidden page makes pending text
eligible as a best effort. Exact return to acknowledged text requires no write,
including after a failed attempt.
_Avoid_: periodic backup, manual save, termination guarantee

**Recovery**:
The state shown when the Source repository cannot produce a usable snapshot
because storage access, migration, identity creation, or authoritative Source
writing failed. Record-level corruption is isolated when another valid Source
can open.
_Avoid_: automatic reset, catalog repair, save failure
