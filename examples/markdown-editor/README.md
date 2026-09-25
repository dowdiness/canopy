# Markdown editor prototype

A save-free Rabbita consumer of `dowdiness/rabbita_markdown/text_area` and
`dowdiness/rabbita_markdown/preview`. The example owns the committed document
string; only accepted `TextChange` values advance the incremental preview.

Run from this directory with `warren dev` (or build with `warren build`).
Switch among Text, Preview, and Split; edit in Text or Split and check the
preview. The text is intentionally discarded on reload.

This is an integration experiment, **not** a reusable editor facade. The
preview currently emits Loomark-specific classes and uses a fixed scroll DOM
ID. Local CSS makes the essential output legible, but the preview stylesheet
is not yet distributable or theme-independent. Do not place two instances on
the same page until the DOM IDs are made instance-specific.

Browser check: ordinary typing, select-all followed by typing, and a
programmatic `InputEvent` full replacement update the accepted text and preview
consistently. The browser automation command `fill` is different: it first
clears the textarea with a synthetic plain `Event("input")`, which Rabbita's
`on_input` handler does not accept as an `InputEvent`, then inserts new text
through native input events. Only the insertion reaches the app, so the
committed text and preview retain the old suffix while the DOM textarea does
not. Do not use `fill` as a native full-replacement test for this binding.
