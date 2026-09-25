# Rabbita Markdown building blocks

This module contains the browser textarea input adapter (`text_area`) and the
incremental Markdown preview (`preview`) extracted from Loomark. Loomark still
owns the accepted document text and connects the two: it applies each
`TextChange` to its document before notifying the preview. Storage, sync, mode
controls, and split-pane layout remain in Loomark.

The packages are currently building blocks for the workspace, not yet a
standalone embeddable editor or a stable external integration API. For preview
rendering outside Loomark, load `styles/preview.css` alongside the compiled
application. It scopes its rules to `.rmd-preview`, needs no Tailwind or
Loomark stylesheet, and accepts optional `--rmd-*` CSS variables for colors
and fonts. Loomark continues to use its existing Tailwind styles via the
renderer’s legacy classes; those compatibility classes are not required by
the standalone stylesheet. The consumer owns the textarea, mode controls,
and split-pane layout.
