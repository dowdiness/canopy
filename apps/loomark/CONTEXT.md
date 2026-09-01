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

**Document text**:
The current Markdown text. Text input updates it immediately.
_Avoid_: canonical source, draft text, surface, surface text

**Recent documents**:
The place for choosing a Loomark document as one continuous, ungrouped list,
with the most recently changed first. A Document text change moves its document
first immediately, even before Autosave succeeds; reopening reflects only Saved
text and its saved change order.
On sufficiently wide screens it starts open as a fixed-width, collapsible pane
beside the editor; it is not resizable. An 18rem pane and 64rem breakpoint are
prototype starting values, not accepted dimensions. Closing the pane lasts only
for the current page lifetime and is not persisted. An icon-only editor-toolbar
control opens or closes Recent documents and carries an accessible label and
tooltip. The Recent documents action bar has no visible heading and owns a
right-aligned, text-only `New` action without a plus icon; the editor toolbar
does not duplicate the New action. On narrow screens it temporarily fills the screen, provides a
back-arrow control to return without selection, and returns to the editor after
selection. Each entry shows the first content after optional leading
frontmatter, using its heading, task, quote, or ordinary text appearance; it
does not fetch or display an image thumbnail or change time. When the first
content is an image with alt text, the alt text becomes ordinary primary content
without loading the image. Inline Markdown is flattened to readable text; only
the heading, task, quote, or ordinary block appearance remains, and links do not
become separate actions. The primary content and following excerpt may each
occupy up to two visual lines. Task checkboxes are
read-only. An unsaved document has a small warning mark with an accessible `Not
saved` label rather than visible status text. A document whose text is empty has
no visible placeholder, while its selectable entry retains an accessible `Empty
document` label. When no saved documents exist, the list shows `No documents
yet` rather than unexplained blank space. The selected document uses an explicit
row highlight with a
subtle background and slim edge accent; exact visual values remain provisional. A selected cold target
shows a small loading indicator with an accessible `Loading document` label
while the current document remains visible. Merely opening a document does not
move it, and typing may update the entry after
a short pause.
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
not create another Parser.
_Avoid_: warm-up, preloading

**Preview refresh**:
Reading one coherent syntax snapshot, lowering it directly to MarkdownIR, and
replacing Preview from the latest committed Document text. After the Parser
transition, lowering waits for a 24 ms candidate-text quiet window so rapid
changes normally produce one visible update.
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
Creating a new Loomark document from supplied Markdown text with browser Text
mode's LF line endings. Every import creates a new identity, even when its
filename or content matches an existing document.
_Avoid_: open file, replace, file sync

**Export**:
Downloading the current Document text exactly as shown, without waiting for
browser saving to finish. Its suggested filename is derived at download time
from the first content and is never a stored document name.
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
opened safely. Loomark preserves it as unavailable without preventing valid
Loomark documents or a New document from opening.
_Avoid_: automatic reset, save failure
