# Loomark multi-document v1 release contract

**Status:** Proposed for the first multi-document release. This is a deliberately
small, temporary v1 contract, not permanent Loomark architecture. Revisit each
choice after the v1 product is complete and measured rather than extending this
plan by assumption.

**Issues:** [#1300](https://github.com/dowdiness/canopy/issues/1300),
[#1303](https://github.com/dowdiness/canopy/issues/1303),
[#1304](https://github.com/dowdiness/canopy/issues/1304),
[#1305](https://github.com/dowdiness/canopy/issues/1305),
[#1306](https://github.com/dowdiness/canopy/issues/1306),
[#1307](https://github.com/dowdiness/canopy/issues/1307),
[#1308](https://github.com/dowdiness/canopy/issues/1308), and
[#1347](https://github.com/dowdiness/canopy/issues/1347)

## Goal

Ship a complete multi-document Loomark that feels like a quick-note app and does
not require users to name, file, tag, or otherwise organize their writing. Keep
Document text as the Markdown authority and keep browser storage, parsing, and
list preparation outside the ordinary Text input task.

## V1 product contract

### Saving boundary

- IndexedDB is V1's ordinary automatic persistence. Users do not select or
  manage a backing file while editing.
- Markdown files participate only through explicit one-time Import and Export.
  V1 does not retain a file handle or synchronize later changes with a file.
- After the first successful document save, V1 requests persistent storage once.
  A denied request does not block editing or trigger repeated requests, and an
  accepted request is never described as backup.

### IndexedDB shape

- Each document is one structured IndexedDB record containing its identity,
  Document text, most-recent-change value, and the bounded information needed to
  display its first content in Recent documents.
- Document text and list information are replaced together. V1 does not keep a
  separate catalog, manifest, Header record, or Source record.
- The Recent documents view reads a browser-maintained index without
  materializing every Document text. Opening a document reads that document's
  complete record.
- One malformed document record is preserved and shown as unavailable without
  blocking valid documents. V1 does not hide, delete, repair, or replace it.
- The latest selected DocumentId is small session data outside document records.
  Reopening Loomark loads that document in Text mode. If it no longer exists,
  Loomark selects the most recently changed remaining document; if none exists,
  it shows an unstored New document. A malformed selected document is reported
  rather than silently replaced by another document.
- Export writes only Document text; IndexedDB list and session fields never enter
  the Markdown file.

### Create and identify

- A Loomark document has an identity and Document text, not an independently
  editable title.
- A New document opens as an empty editor and is not added to browser storage or
  Recent documents until the user first changes its text.
- Once created, a document remains a document even if its text is later emptied.
  Its Recent documents entry has no visible placeholder text, but the selectable
  entry retains an accessible `Empty document` label.
- Equal text does not imply equal identity.

### Recent documents

- Recent documents is one continuous list ordered by most recent text change.
  It has no Today, Yesterday, or older grouping. When it contains no saved
  documents, it shows `No documents yet` rather than unexplained blank space.
  Merely opening a document does not move it.
- On sufficiently wide screens it starts open as a fixed-width, collapsible pane
  beside the editor. The prototype starts with an 18rem pane and 64rem
  breakpoint, but both dimensions remain provisional until compared in the
  production browser. The pane is not resizable; V1 does not add a second drag
  divider beside Split's existing divider. A manual close lasts for the current
  page lifetime and is not persisted, so the pane starts open again after
  reopening or reloading Loomark. An icon-only editor-toolbar control opens or
  closes Recent documents and has an accessible label and tooltip. The Recent
  documents action bar has no visible heading. It contains a right-aligned,
  text-only `New` action without a plus icon, which is not duplicated in the
  editor toolbar. On narrow screens Recent documents
  temporarily fills the screen, provides a back-arrow control to return without
  selection, and returns to the editor after a document is selected. Both
  placements use the same entries and selection behavior.
- Each entry shows the first content after optional leading frontmatter and
  keeps a useful distinction between a heading, task, quote, and ordinary text.
  Inline Markdown is flattened to readable text; bold, inline code, and links do
  not add nested formatting or actions inside a selectable entry. V1 adds Task
  checkbox display to the shared Markdown interpretation so Preview and Recent
  documents agree; checkboxes in Recent documents are read-only.
- Each entry allows up to two visual lines for its primary content and two for a
  following excerpt. This contextual density takes priority over maximizing the
  number of visible entries because V1 has no independent title.
- The selected document has an explicit row highlight using a subtle background
  and slim edge accent. Exact colors and dimensions remain provisional until
  browser comparison.
- Entries do not display change times or fetch or display image thumbnails. If
  the first content is an image with alt text, its alt text is shown as ordinary
  primary content without loading the image. Timestamp presentation, image
  thumbnail extraction, loading, caching, and thumbnail layout are outside V1.
- List preparation does not run in the ordinary Text input task. The active
  entry may update after the existing 250 ms input-quiet interval and does not
  wait for browser saving to succeed.
- V1 does not include full-text search, folders, tags, manual ordering, or an
  independently managed title. Search is a post-v1 product capability, not a
  requirement for completing this release.

### Switch documents

- Selecting another document never waits for the current document to finish
  saving.
- Pointer or touch down may begin the selected document's read before activation.
  V1 performs no startup-wide, recent-document, idle, or hover prefetch. Add
  hover prefetch only if production measurements show that pointer-down loading
  misses the accepted interaction target.
- If an unopened target is not ready, the current document remains visible and
  editor focus does not accept text for the target. The target entry shows a
  small loading indicator with an accessible `Loading document` label and no
  added visible status text. When the latest selected target is ready, it
  appears once. An older read completion never changes the visible document.
- The current Text, Preview, or Split mode remains selected across a Document
  switch. V1 does not store a mode per document, and reopening Loomark still
  starts in Text mode.
- A mode change preserves the current textarea and native undo history. A
  document switch starts a fresh browser-native undo history; V1 does not
  preserve undo across documents and does not add shadow history.
- If IME composition is active, the browser finishes or cancels it in the
  current document before the prepared target replaces that document.
- V1 owns at most one syntax Parser, for the selected document. A Document
  switch discards it instead of caching Parsers or rendered Preview by
  DocumentId. A Text-mode target creates no Parser; a Preview/Split target starts
  Preview preparation only after its source is visible.
- In Split mode, the target's Text becomes editable as soon as its source is
  ready; only its Preview remains in preparation. In Preview mode, the target
  shows its own preparation state. A completed Preview from the previous
  document is never shown as the target's Preview.

### Save failures

- Saving continues independently for each document after it becomes inactive.
- A document whose latest text has not reached browser storage remains in memory
  and has a small warning mark in Recent documents. The mark has an accessible
  `Not saved` label and tooltip but no visible status text. The document is not
  evicted merely because another document is active.
- A save failure does not switch documents, block other editing, or force the
  user back to the affected document.
- Loomark retries at the next edit to that document, when the user returns to
  the app, or when the failure display is activated. V1 does not run an
  unbounded timer retry loop.
- Closing the browser tab does not show an additional unsaved-changes prompt.
  Memory-only changes may therefore be lost when the tab closes.
- #1347 remains separate: bounding the crash-loss window during continuous
  typing is not part of document switching.

### Pre-release browser storage

- The current single-document IndexedDB shape is unreleased development data,
  not a supported earlier product version.
- V1 starts with its own empty storage shape. It does not inspect, migrate, or
  fall back to the development record.
- Do not add compatibility or recovery branches for an unobserved migration
  failure. Investigate a demonstrated failure before adding a workaround.
- Recovery still applies to malformed data written in the supported v1 shape;
  it is not a pre-v1 compatibility mechanism.

### Multiple browser tabs

- V1 does not coordinate editing between browser tabs and does not acquire an
  exclusive editor lock.
- Two tabs may edit the same document. The last browser-storage write to finish
  wins and may overwrite changes saved by the other tab without a warning.
- Multi-tab conflict detection, locking, and synchronization are post-v1 work.

### Import, export, and delete

- Import preserves the supplied Markdown content and always creates a new
  identity, even when filename or content matches an existing document. Browser
  Text mode normalizes imported line endings to LF; V1 does not retain original
  CRLF/CR metadata, track the source file, or synchronize it.
- Export downloads the current Document text exactly as shown, without waiting
  for browser saving to complete. A save failure does not prevent export. The
  suggested download filename is derived from the first content at export time,
  falls back to `loomark-document.md`, and is not stored as a document name.
- Delete requires confirmation and then permanently removes the document. V1
  has no Trash, soft deletion, or deletion Undo.
- Delete wins over an older pending save. A late save completion must not make a
  deleted document reappear.
- Deleting the active document opens the most recently changed remaining
  document. If none remains, Loomark shows an unstored New document.

## Deliberately deferred

The following are not rejected permanently. They are excluded so that v1 can be
finished and measured:

- full-text search and a search index;
- multi-tab conflict detection, locking, or synchronization;
- hover, idle, recent-document, or startup source prefetch;
- a generalized priority queue or adaptive cache policy;
- cross-document undo, iframe-isolated editors, or editor-owned history;
- Trash, timed delete Undo, or recovery of deleted documents;
- filename synchronization, duplicate detection, or content-addressed storage;
- persisted folders, tags, pins, manual ordering, or other organization systems;
- Workers, OPFS, SQLite, chunked source records, or Blob-based source storage.

## Reassessment after v1

Do not turn a deferred capability into a v1 prerequisite. After release, use
production evidence to answer these questions independently:

1. Do cold document reads miss the switching target often enough to justify
   hover or bounded background prefetch?
2. Do realistic document counts make the recent list insufficient and justify
   full-text search?
3. Does losing undo at a document switch cause enough real harm to reconsider
   browser-owned history?
4. Do save failures or accidental deletion justify stronger close protection,
   Trash, or deletion Undo?
5. Do document count, source size, or memory measurements require cache eviction
   or a different physical storage layout?

Any replacement policy should supersede the relevant v1 section explicitly;
this plan must not be cited as a permanent product constraint.
