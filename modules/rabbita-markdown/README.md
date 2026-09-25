# Rabbita Markdown building blocks

This module contains the browser textarea input adapter (`text_area`), the
incremental Markdown preview (`preview`), and their shared coordination
(`editor`). The host still owns the accepted document text: it applies each
`TextChange` to its document before calling `editor.accepted` with the resulting
text. Rejected edits must not be passed to `accepted`. Storage, sync, mode
controls, and split-pane layout remain with the host.

On acceptance, `editor.accepted` informs the textarea before notifying the
incremental preview; it normally leaves the browser textarea alone, but an
earlier rejection's pending after-render restoration then uses the latest
accepted text. `editor.activate` initializes the textarea on document switch,
and `editor.visibility_changed` manages preview demand on Text/Preview mode
boundaries. The host still handles rejected edits with `TextArea::initialize`
and fences old-document input notifications before accepting them.

The packages are currently building blocks for the workspace, not yet a
standalone embeddable editor or a stable external integration API. The
coordination package deliberately leaves the host's model, event dispatch, and
layout alone; it is not a finished all-in-one editor facade. For preview
rendering outside Loomark, load `styles/preview.css` alongside the compiled
application. It scopes its rules to `.rmd-preview`, needs no Tailwind or
Loomark stylesheet, and accepts optional `--rmd-*` CSS variables for colors
and fonts. Loomark continues to use its existing Tailwind styles via the
renderer’s legacy classes; those compatibility classes are not required by
the standalone stylesheet. The consumer owns the textarea, mode controls,
and split-pane layout.
