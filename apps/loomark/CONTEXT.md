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
