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
Creating one long-lived syntax Parser after Preview or Split is selected for
the first time. Preparation is skipped when a document remains in Text mode.
_Avoid_: warm-up, preloading

**Preview refresh**:
Reading one coherent syntax snapshot, lowering it directly to MarkdownIR, and
replacing Preview from the latest committed Document text. Refresh is delayed
by 32 ms after input so rapid changes normally produce one visible update.
_Avoid_: projection refresh, render loop

**Stale Preview**:
The last successful Preview retained after a newer refresh fails. Loomark marks
it as stale; it never becomes Document text.
_Avoid_: fallback document, recovered text

**Saved text**:
The most recent Document text successfully written to browser storage. It may
be older than the current Document text.
_Avoid_: edit history, backup

**Browser storage**:
The IndexedDB record containing one document identity and its Saved text.
_Avoid_: archive, repository, alternate storage

**Autosave**:
Saving the current Document text after input is quiet for 250 ms and IME
composition has ended.
_Avoid_: periodic backup, manual save

**Recovery**:
The state shown when the browser-storage record cannot be opened safely. Loomark
preserves the stored value and does not open an editor or replace the value.
_Avoid_: automatic reset, save failure
