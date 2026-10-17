# Loomark Product Vocabulary & Behavior Contract

Loomark is a quiet, local-first browser Markdown text editor. This document is the canonical glossary describing its accepted product language, UI states, and behavioral invariants.

Before proposing UI changes, refactoring state machines, or adding features, ensure your changes comply with the terms and contracts defined here.

---

## Table of Contents

1. [Document Identity & Content](#1-document-identity--content)
2. [Editor Modes & Presentation](#2-editor-modes--presentation)
3. [Recent Documents & Navigation](#3-recent-documents--navigation)
4. [Storage, Durability & Autosave](#4-storage-durability--autosave)
5. [Multi-Device Synchronization & Conflict Recovery](#5-multi-device-synchronization--conflict-recovery)
6. [Document Operations (Import, Export, Deletion)](#6-document-operations-import-export-deletion)

---

## 1. Document Identity & Content

**Loomark document**:
The Markdown entity edited in Loomark. It has an identity and text.
_Avoid_: file, buffer, session

**New document**:
The temporary empty editor opened in the current Editor mode. It becomes a
Loomark document when the user first changes its text; leaving it untouched does
not add it to Recent documents.
More actions contains operations rather than routine saving explanations; the
untouched New document is never described as already saved.
The native Text area shows a "Start writing…" hint while the New document is
untouched. This is presentation, never Document text. A saved empty document
does not show the hint.
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

**Derived name**:
The in-app name derived from Document text. An empty string means that the
Loomark document has no name. A presentation may show `Unnamed document` as a
placeholder, but that placeholder is not the name. `Untitled` is reserved for
the Export filename fallback. The Document lead remains recognition content,
not a name.

**Plain content**:
A readable Document lead shown without the distinct form of a heading, task,
quote, code, or list. Its readable text remains while its source block receives
no other specialized presentation.
_Avoid_: ordinary content, paragraph

---

## 2. Editor Modes & Presentation

**Focus Mode**:
An explicit, page-local writing presentation, off on every launch or reload.
The icon-only toggle stays at the bottom-right of the available viewport and,
like the view controls, is hidden while an on-screen keyboard is detected and
the textarea has focus, so a mistaken detection cannot remove the only exit.
Toggling only switches the presentation; it never focuses the textarea, so it
cannot summon an on-screen keyboard. Its accessible label and tooltip name
`Focus Mode` or `Exit Focus Mode`, and its pressed state exposes whether it is on.
Entering hides Recent documents, the top toolbar, view controls, and routine
save feedback without changing the current Text, Preview, or Split mode.
Leaving restores the controls and sidebar visibility. Text, selection, and native
Undo history survive the transition. Escape exits, except during IME composition.
The toggle cannot change modes during composition or a blocking document action.
While the textarea has focus, surrounding writing groups fade; normal mode
never applies this dimming. Blurring the textarea restores full readability
without leaving Focus Mode. Autosave continues, and failure notices and
exceptional durability/sync actions remain available.
Routine controls fade out and back in over 180 ms, and the toggle icons
crossfade without moving. Controls become inert as soon as Focus Mode starts,
not after the fade. Reversing a transition retargets it rather than queuing
another animation. Reduced motion uses immediate switching. Sidebar and editor
pane layout changes remain immediate; text is not translated or scaled.

**Editor mode**:
The current way to edit, inspect, or combine views of the selected Document
text. A Document switch keeps the current mode, while reopening Loomark starts
in Text mode; modes never own a second text authority or a separate browser undo
history.
_Avoid_: layout, workspace

**Text mode**:
The editor mode that shows the textarea and hides Preview.
The writing area disables browser spellchecking so dictionary suggestions do not
mark document text with red underlines. Autocomplete and autocorrect remain off;
native IME composition is unchanged.
Outside Focus Mode, Text and Preview share the same edge fade and subtle blur
beneath the fixed top and bottom controls. Each bar owns its blurred background;
the editor has no separate decorative overlay. Document spacing stays inside the
scrollable content rather than an empty outer frame. Native scroll padding keeps
the current writing line clear of the controls and faded edges without changing
text, selection, composition, or Undo. Manual reading scrolls are not pulled back
to the caret. Compact Split retains a minimum usable writing pane when notices
reduce the available height.
The editor follows changes in the browser's available height, excluding pinch
magnification. It requests native content resizing where supported. The bottom
bar and its reserved space are removed when visual-viewport occlusion or a
window-size-adjusted height estimate indicates a keyboard. Panning alone does
not restore the bar.
No bottom overlay remains while the bar and Focus Mode toggle are hidden;
writing reserves bottom space only while a footer stays visible, such as
`Not saved`. The top toolbar (outside Focus Mode) and failure notices remain
available. Exceptional
durability/sync actions remain visible in Focus Mode even with a keyboard.
The bottom bar returns when the visible height recovers. Ordinary window-height
changes and hardware-keyboard focus alone do not hide it. Keyboard detection
under content resizing is best-effort, not a browser-provided visibility signal;
its limitations are described in [Mobile Viewport](docs/architecture.md#mobile-viewport).
Width or height changes keep the visible
textarea's active selection endpoint readable, including when a resize control
has focus, without replacing the textarea or changing text, selection, focus,
IME composition, or native Undo. Pinch zoom remains browser-owned and does not
cause the editor to reflow around the zoomed viewport. Keyboard and window height
changes still resize the editor while zoomed; a recovered height cannot leave
the previous keyboard-sized frame or an obsolete top offset in place.
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

**Character count**:
A quiet writing measure beside the Editor-mode control on wide screens. It
counts the Document text that Recent documents last settled on, so it may lag
typing by the same short pause. Every visible character counts, including
Markdown markers and punctuation; spaces and line breaks do not, and combining
marks, variation selectors, and joined emoji count with the character they
modify. It is absent for empty text and on compact screens, where save
attention owns the footer. It is presentation, not a save status.
_Avoid_: word count, statistics, progress

**Appearance**:
Loomark follows the system light or dark preference with the same warm paper
hue. Text uses a duospaced writing face with IBM Plex Sans JP for Japanese, and
Preview a reading serif with BIZ UDMincho; system fonts cover scripts they
lack. Japanese faces download only when Japanese text appears, or ahead of time
while idle for a Japanese-language browser or a Japanese document, and stay
cached by versioned file name. A face that arrives late replaces the system
font everywhere at once, and Writing focus re-measures. Printing from
Preview prints the reading page without controls. Appearance never changes
Document text, and Preview adds no quotation marks or code delimiters that the
text does not contain.
_Avoid_: theme, skin

**Japanese document**:
A Loomark document whose text contains kana and whose East Asian characters
outnumber its other words, judged from the same settled text as the Character
count. Its Text and Preview declare Japanese content for assistive technology
and Japanese typography: Preview keeps kana and kanji upright, marks emphasis
with emphasis dots, and widens line spacing. The interface language is
unchanged.
_Avoid_: locale, translation

---

## 3. Recent Documents & Navigation

**Recent documents**:
The place for choosing a Loomark document as one continuous, ungrouped list,
with the most recently changed first within the current page lifetime. A
Document text change immediately moves its document to the first position, even
before Autosave succeeds; reopening restores deterministic lexical Document ID
order; recency is never persisted.
It starts closed on every launch or reload, on both wide and narrow screens.
On wide screens it shifts the editor as it opens or closes. The sidebar spans the
viewport height. The same top-left icon opens and closes it at a fixed position;
there is no separate × control. One open-or-closed state continues across
breakpoint changes for the current page lifetime and is not persisted. New
document uses the existing square-pen icon in the top-right toolbar. On narrow
screens the sidebar fills the width and makes the editor inert until closed;
selecting a document there closes it. Each entry shows the Document lead using
its heading, task, quote,
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
may each occupy up to two visual lines. Both also have finite text budgets
independent of document size; visual clipping alone is not the limit. Omitted
content is not retained in the lead or exposed in full through an accessible
label or tooltip. Truncation preserves Unicode text boundaries and meaningful
structure within the budget, and remains distinguishable from Empty content.
The numeric budgets and the exact visible and accessible omission wording must
be finalized through browser comparison before the production extractor API is
accepted. Task checkboxes are read-only. An unsaved document has a small warning
mark with an accessible `Not saved` label rather than visible status text. A
document whose text is empty has no visible placeholder, while its selectable
entry retains an accessible `Empty document` label. When no saved documents
exist, the list shows `No documents yet` rather than unexplained blank space.
The selected document uses an explicit row highlight with a subtle tinted
background and no edge bar; exact visual values remain provisional. A selected cold
target shows a small loading indicator with an accessible `Loading document`
label while the current document remains visible. Merely opening a document does
not move it. While typing, an entry keeps its previous Document lead until a
lead
from the newer text replaces it after a short pause; a document entering Recent
documents for the first time uses its current text for its first lead.
_Avoid_: Document list, catalog, title list, file browser

**Document switch**:
Choosing another Loomark document without waiting for the current document to
finish saving. The current document remains visible until its IME input has
ended and the latest selected target is ready, then that target appears once
with a fresh browser undo history.
After activation, keyboard focus moves to the visible TextArea, or to the
selected Editor-mode control in Preview. Transient More actions content closes.
Closing More actions with Escape restores focus to its trigger.
_Avoid_: save-and-open, handoff

---

## 4. Storage, Durability & Autosave

**Saved text**:
The most recent Document text successfully written to browser storage. It may
be older than the current Document text.
Outside Focus Mode, the editor footer names local durability beside its status
icon: "Saving on this device", "Saved on this device", or "Not saved". Untouched New has no
success indicator. On compact screens, an attention action or message takes
priority over the caption; the icon retains the complete accessible name.
This is a browser-storage status, not a sync or publication confirmation.
_Avoid_: edit history, backup

**Unsaved document**:
A Loomark document whose latest text has not reached browser storage. Loomark
keeps it in memory and marks it in Recent documents. Failed saves show "Not saved"
in both normal and Focus Mode, without a duplicate toast or manual save-retry
button. Subsequent eligible edits retry saving; returning to the app alone does
not guarantee a retry. Current text remains available to Export without waiting
for a successful save. Loomark does not prompt when the browser tab closes.
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

**Recovery**:
The state shown for a Loomark document whose Browser storage record cannot be
opened safely. That document cannot become the Editing Document, but Loomark
preserves it as unavailable and opens another valid Loomark document or a New
document.
_Avoid_: automatic reset, save failure

---

## 5. Multi-Device Synchronization & Conflict Recovery

**Synced document**:
A Loomark document explicitly connected to the signed-in account. Its current
text is `Synced` only after that exact text has a remote durability
acknowledgment. Signing in does not turn existing local documents into Synced
documents; the person must choose `Sync` for each one.
_Avoid_: cloud file, shared document

**Update available**:
A newer remote revision retained beside an unchanged Editing Document. Loomark
does not apply it automatically. `Open update` is offered only while the action
still names the current account, Replica revision, and unedited working copy.
Opening it replaces the text once and starts a fresh native Undo history.
_Avoid_: live update, automatic merge

**Remote deletion**:
A server tombstone newer than the Editing Document's acknowledged revision.
Loomark keeps the current text visible until `Remove deleted document` is
chosen. The action expires if its account, revision, or working copy changes.
_Avoid_: local deletion, missing document

**Recovery document**:
A new local-only Loomark document created when local and remote text have both
diverged. It retains the local branch under a fresh identity while the original
identity follows the server branch. Creating it does not upload the recovery
text. If the conflicted document is being edited, its TextArea, IME composition,
selection, and native Undo continue under the recovery identity.
_Avoid_: merged document, conflict marker, backup

**Uncoordinated tabs**:
Separate browser tabs editing Loomark without shared operation ordering. A later
Browser storage write may overwrite Saved text or recreate a deleted document.
_Avoid_: synchronized tabs, collaborative sessions

---

## 6. Document Operations (Import, Export, Deletion)

**Import**:
Creating a new Loomark document from strictly decoded UTF-8 bytes. Loomark
consumes an initial UTF-8 BOM, normalizes CRLF and CR to LF, and preserves every
other decoded character. Empty files are valid. Filename, extension, and media
type do not affect admission or identity. Every import creates a new identity,
including repeated content, immediately becomes the Editing Document, and uses
the existing New-document autosave path, including retry on subsequent eligible
edits after a save failure. An accepted Import supersedes an
unfinished New action rather than adding a queue or pending-document owner.
_Avoid_: open file, replace, file sync

**Export**:
Downloading the current Document text exactly as shown, without waiting for
browser saving to finish. Its suggested filename is derived at download time
from the Document lead and is never a stored document name.
_Avoid_: backup, saved copy, publish

**Delete document**:
Permanently removing any one Loomark document without first opening it. Each
Recent documents entry exposes a direct icon-only trash button with a
target-specific accessible name and tooltip. With a hover-capable fine pointer
it appears while its entry is hovered or holds focus; touch screens always show
it with a 44px target, and keyboard focus always reveals it. Pointer or
keyboard activation opens Delete confirmation; there is no Actions, context, or overflow menu.
Deleting the Editing Document opens the most recently changed remainder, or a
New document when none remains; Loomark keeps no Trash.
_Avoid_: archive, trash, soft delete

**Delete confirmation**:
Approval to delete one saved or unsaved Loomark document, identified by the
bounded, duplicate-disambiguated label used for its Recent documents entry,
not a second rendering of the lead. An accepted delete request opens
confirmation and closes More actions without a separate IME-waiting state.
Cancellation restores focus to the requesting control and leaves
the document unchanged. Acceptance closes confirmation and supersedes the
target's pending Autosave without interrupting another document's Autosave.
See the [deletion decision](../../docs/decisions/2026-08-31-loomark-document-deletion.md)
for consent and persistence ordering.
_Avoid_: deletion warning, delete prompt

**Pending deletion**:
A confirmed Delete document awaiting Browser storage acknowledgment. A non-open
target shows its progress in Recent documents while editing continues; an open
target remains visible and permits neither editing nor Document switch.
Failure restores the target to retryable availability.
_Avoid_: loading document, optimistic deletion
