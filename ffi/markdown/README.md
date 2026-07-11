# ffi/markdown

JavaScript FFI boundary for the Markdown block editor. Exports a small set of functions keyed by integer handle for a `SyncEditor` instance configured for Markdown.

This package contains no logic — it delegates entirely to `editor`, `lang/markdown/edits`, and `lang/markdown/companion`.

## Public API

- `create_markdown_editor(source) -> Int` / `destroy_markdown_editor(handle)`
- `markdown_get_text(handle)` / `markdown_set_text(handle, text)`
- `markdown_export_text(handle) -> String` — export canonical Markdown (may differ from raw source)
- `markdown_apply_edit(handle, op_json, cursor, ...) -> String` — apply a structural edit and return patch JSON
- `markdown_compute_view_patches_json(handle) -> String`

## Consumers

No other MoonBit package imports `ffi/markdown`. Consumed by the Markdown block editor frontend in `examples/block-editor/`.

## Dependencies

- `dowdiness/canopy/editor`
- `dowdiness/canopy/core`
- `dowdiness/canopy/ffi/host` — shared handle/view-state registry and coordinator destroy gateway
- `dowdiness/canopy/lang/markdown/edits` + `lang/markdown/companion`
- `dowdiness/markdown` — Markdown AST type

## Stability

Unstable — route through `ffi/markdown`. The Markdown editor is the most actively developed editor and the exported surface changes frequently.
