# Loomark

Loomark is a browser Markdown Text editor. This glossary describes its accepted
product language.

## Language

**Loomark document**:
The Markdown entity edited in Loomark. It has an identity and text.
_Avoid_: file, buffer, session

**New document**:
The temporary empty editor opened in the current Editor mode. It becomes a
Loomark document when the user first changes its text; leaving it untouched does
not add it to Recent documents.
_Avoid_: blank record, draft

**Editing Document**:
The Loomark document currently shown in the Editor and owning its TextArea and
Preview. A requested Document switch does not change the Editing Document until
the requested document is ready and activated.
_Avoid_: active document, open document, selected document

**Selection target**:
The Loomark document requested by a Document switch. It may differ temporarily
from the Editing Document while the requested document is being prepared.
_Avoid_: Editing Document, active document

**Document text**:
The current Markdown text. Text input updates it immediately.
_Avoid_: canonical source, draft text, surface, surface text

**Document lead**:
The first readable content, together with a structured description of subsequent
readable content, used to recognize a Loomark document without naming it.
Normally extracted from parser-recognized Markdown, it falls back to non-empty
source lines as Plain content rather than treating present text as empty.
_Avoid_: summary, title, document name, Preview

**Plain content**:
A readable Document lead shown without the distinct form of a heading, task,
quote, code, or list. Its readable text remains while its source block receives
no other specialized presentation.
_Avoid_: ordinary content, paragraph

**Recent documents**:
The place for choosing a Loomark document as one continuous, ungrouped list,
with the most recently changed first. A Document text change moves its document
first immediately, even before Autosave succeeds; reopening reflects only Saved
text and its saved change order.
On sufficiently wide screens it starts open as a fixed-width, collapsible pane
beside the editor; it is not resizable. On narrow screens it starts closed. An
18rem pane and 64rem breakpoint are prototype starting values, not accepted
dimensions. One open-or-closed state continues across breakpoint changes for the
current page lifetime and is not persisted. An icon-only editor-toolbar
control opens or closes Recent documents and carries an accessible label and
tooltip. The Recent documents action bar has no visible heading and owns a
right-aligned, text-only `New` action without a plus icon; the editor toolbar
does not duplicate the New action. On narrow screens it temporarily fills the
screen, provides a back-arrow control to close it without selection, and closes
after selection; selecting a document on a wide screen does not close the pane. Each entry shows the Document lead using its heading, task, quote,
code, list, or Plain content form. Every heading level uses the same form; lists
retain their bullets or numbering, and fenced and indented code use a restrained
background and monospaced text without syntax highlighting. The current parser
has no frontmatter extension, so YAML-like text is Plain content rather than
skipped metadata. An entry does not fetch or display an image thumbnail or
change time. When the first content is an image with alt text, the alt text
becomes Plain content without loading the image. Inline Markdown is flattened to
readable text, and links do not become separate actions. After the primary
content, subsequent readable content becomes one description that preserves
meaningful line breaks, indentation, list bullets or numbering, and code spacing
without retaining a Markdown block tree. The primary content and description
may each occupy up to two visual lines. Task checkboxes are read-only. An unsaved
document has a small warning mark with an accessible `Not saved` label rather
than visible status text. A document whose text is empty has
no visible placeholder, while its selectable entry retains an accessible `Empty
document` label. When no saved documents exist, the list shows `No documents
yet` rather than unexplained blank space. The selected document uses an explicit
row highlight with a
subtle background and slim edge accent; exact visual values remain provisional. A selected cold target
shows a small loading indicator with an accessible `Loading document` label
while the current document remains visible. Merely opening a document does not
move it. While typing, an entry keeps its previous Document lead until a lead
from the newer text replaces it after a short pause; a document entering Recent
documents for the first time uses its current text for its first lead.
_Avoid_: Document list, catalog, title list, file browser

**Document actions menu**:
The actions for one Recent documents entry, opened from its context-menu gesture,
keyboard command, or overflow control. Delete document is a destructive action
in this menu.
_Avoid_: row buttons, right-click-only menu

**Change order**:
An opaque comparable value assigned when Document text changes and saved with
that document. It orders Recent documents but is neither displayed nor treated
as a trustworthy wall-clock time across Uncoordinated tabs.
_Avoid_: modified date, timestamp, global sequence

**Document switch**:
Choosing another Loomark document without waiting for the current document to
finish saving. The current document remains visible until its IME input has
ended and the latest selected target is ready, then that target appears once
with a fresh browser undo history.
_Avoid_: save-and-open, handoff

**Editor mode**:
The current way to edit, inspect, or combine views of the selected Document
text. A Document switch keeps the current mode, while reopening Loomark starts
in Text mode; modes never own a second text authority or a separate browser undo
history.
_Avoid_: layout, workspace

**Text mode**:
The editor mode that shows the textarea and hides Preview.
_Avoid_: source mode, raw mode

**Preview**:
A read-only parse-derived view of Document text. It may lag behind Document text
and never determines editing or saving.
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
Creating at most one syntax Parser for the selected document after Preview or
Split is selected. A Document switch discards it; a target in Text mode does
not create another Parser. Returning to Text retains a healthy Parser and keeps
it current without producing hidden Preview output.
_Avoid_: warm-up, preloading

**Preview refresh**:
Reading one coherent syntax snapshot, lowering it directly to MarkdownIR, and
replacing Preview from the latest committed Document text while Preview or
Split is requested. After the Parser transition, lowering waits for a 24 ms
candidate-text quiet window so rapid changes normally produce one visible
update. Returning from Text requests one refresh when the retained Preview is
older than current Document text.
_Avoid_: projection refresh, render loop

**Stale Preview**:
The last successful Preview of the selected Loomark document retained after a
newer refresh fails. Loomark marks it as stale; it never becomes Document text
or carries over to another document.
_Avoid_: fallback document, recovered text

**Saved text**:
The most recent Document text successfully written to browser storage. It may
be older than the current Document text.
_Avoid_: edit history, backup

**Unsaved document**:
A Loomark document whose latest text has not reached browser storage. Loomark
keeps it in memory, marks it in Recent documents, and retries at the next edit
or return to the app without interrupting other work or prompting when the
browser tab closes.
_Avoid_: conflicted document, invalid document

**Browser storage**:
The IndexedDB records used for Loomark's ordinary automatic saving. Loomark asks
the browser to retain them after the first save, but browser storage remains
separate from explicit Markdown Import, Export, and backup.
_Avoid_: archive, backup, file storage

**Autosave**:
Saving the current Document text after input is quiet for 250 ms and IME
composition has ended.
_Avoid_: periodic backup, manual save

**Uncoordinated tabs**:
Separate browser tabs editing Loomark without shared operation ordering. A later
Browser storage write may overwrite Saved text or recreate a deleted document.
_Avoid_: synchronized tabs, collaborative sessions

**Import**:
Creating a new Loomark document from strictly decoded UTF-8 bytes. Loomark
consumes an initial UTF-8 BOM, normalizes CRLF and CR to LF, and preserves every
other decoded character. Empty files are valid. Filename, extension, and media
type do not affect admission or identity. Every import creates a new identity,
including repeated content, immediately becomes the Editing Document, and uses
the existing New-document save and Retry path. An accepted Import supersedes an
unfinished New action rather than adding a queue or pending-document owner.
_Avoid_: open file, replace, file sync

**Export**:
Downloading the current Document text exactly as shown, without waiting for
browser saving to finish. Its suggested filename is derived at download time
from the Document lead and is never a stored document name.
_Avoid_: backup, saved copy, publish

**Delete document**:
Permanently removing any one Loomark document without first opening it. Deleting
the open document opens the most recently changed remainder, or a New document
when none remains; Loomark keeps no Trash.
_Avoid_: archive, trash, soft delete

**Delete confirmation**:
Approval to delete one saved or unsaved Loomark document, identified with the
same content presentation used in Recent documents. It begins after any active
IME composition ends and closes when accepted, superseding the target's pending
Autosave without interrupting another document's Autosave.
_Avoid_: deletion warning, delete prompt

**Pending deletion**:
A confirmed Delete document awaiting Browser storage acknowledgment. A non-open
target shows its progress in Recent documents while editing continues; an open
target remains visible and permits neither editing nor Document switch.
_Avoid_: loading document, optimistic deletion

**Unknown deletion outcome**:
A Pending deletion whose Browser storage acknowledgment and follow-up check did
not arrive within bounded intervals. Loomark isolates that target from editing
and Autosave while other work continues; a late failure restores its availability
without changing the currently open document.
_Avoid_: delete failure, timed-out deletion

**Recovery**:
The state shown for a Loomark document whose Browser storage record cannot be
opened safely. That document cannot become the Editing Document, but Loomark
preserves it as unavailable and opens another valid Loomark document or a New
document.
_Avoid_: automatic reset, save failure
