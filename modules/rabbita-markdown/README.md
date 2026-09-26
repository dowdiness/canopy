# Rabbita Markdown building blocks

This module contains the browser textarea input adapter (`text_area`), the
incremental Markdown preview (`preview`), and their shared coordination
(`editor`). The host still owns the accepted document text: it applies each
`TextChange` to its document before calling `editor.accepted` with the resulting
text. Rejected edits must not be passed to `accepted`. Storage, sync, mode
controls, and split-pane layout remain with the host.

On acceptance, `editor.accepted` informs the textarea before notifying the
incremental preview; it normally leaves the browser textarea alone. A rejected
edit restores the existing textarea before the next input task, while
`editor.activate` initializes a newly mounted textarea after render on document
switch. Pending initialization uses the latest accepted text.
`editor.visibility_changed` manages preview demand on Text/Preview mode
boundaries. The component offers the same operations as `MarkdownEditor` methods.
The host still rejects edits and fences old-document input notifications.

`editor.MarkdownEditor` provides a combined textarea and preview view with
Text/Preview/Split modes, plus opaque state and completion events. The two-editor
example and ownership-race proof use it without assembling either pane. The
`on_change` callback supplies an opaque `InputEdit`; call `editor.admit(input)`
once before applying its returned `TextChange` to host-owned text. Rejection or
activation invalidates previously queued inputs, including full-value fallback
edits; normal acceptance leaves later inputs in the same batch valid. Restore
the accepted text if the returned change cannot be applied. The host still owns
accepted text, its acceptance policy, document generation, selected mode,
event dispatch, and the surrounding layout. A host with its own pane layout can
render `input_view` and `preview_view` inside its panels while keeping the same
`MarkdownEditor` instance, state, and lifecycle. Loomark exercises this path
with its RUI resizable panels; the examples use the default `view`. This is a
workspace prototype, not yet a stable external integration API.

For use outside Loomark, load `styles/editor.css` and `styles/preview.css`
alongside the compiled application. Both scope their rules to the editor and
preview, need no Tailwind or Loomark stylesheet, and accept optional `--rmd-*`
CSS variables for colors and fonts. Loomark continues to use its existing
Tailwind styles via the renderer's legacy classes. The host owns mode controls
and the editor's containing dimensions.
