# Markdown editor prototype

A save-free Rabbita consumer of `dowdiness/rabbita_markdown/text_area` and
`dowdiness/rabbita_markdown/preview`. The example owns the committed document
string; only accepted `TextChange` values advance the incremental preview.

Run from this directory with `warren dev` (or build with `warren build`).
The page renders two independent documents: Draft A starts in Text mode and
Draft B in Split. Switch each among Text, Preview, and Split; edits to one do
not change the other. The text is intentionally discarded on reload.

This is an integration experiment, **not** a reusable editor facade. Each
instance supplies its own textarea and optional preview DOM IDs; the preview
has no ID by default. The example links the module's `styles/preview.css`
into `public/` for Warren to copy. Its preview is styled without importing
Loomark or Tailwind CSS; the example's `styles.css` owns only the page,
controls, input, and split layout. The preview renderer still emits legacy
Loomark classes for the existing application until that styling is migrated.

Browser check: ordinary typing, select-all followed by typing, and a
programmatic `InputEvent` full replacement update the accepted text and preview
consistently. The browser automation command `fill` is different: it first
clears the textarea with a synthetic plain `Event("input")`, which Rabbita's
`on_input` handler does not accept as an `InputEvent`, then inserts new text
through native input events. Only the insertion reaches the app, so the
committed text and preview retain the old suffix while the DOM textarea does
not. Do not use `fill` as a native full-replacement test for this binding.
