# Rabbita Markdown building blocks

This module contains the browser textarea input adapter (`text_area`) and the
incremental Markdown preview (`preview`) extracted from Loomark. Loomark still
owns the accepted document text and connects the two: it applies each
`TextChange` to its document before notifying the preview. Storage, sync, mode
controls, and split-pane layout remain in Loomark.

The packages are currently building blocks for the workspace, not yet a
standalone embeddable editor or a stable external integration API. Preview
styles still depend on Loomark's stylesheet; a self-contained editor UI and
its CSS are separate follow-up work.
