# Markdown editor prototype

A save-free Rabbita consumer of `dowdiness/rabbita_markdown/editor.MarkdownEditor`.
It uses no direct `text_area` or `preview` imports or pane assembly. The example
owns the committed document string; only accepted `TextChange` values advance
the incremental preview.

Run from this directory with `warren dev` (or build with `warren build`).
The page renders two independent documents: Draft A starts in Text mode and
Draft B in Split. Switch each among Text, Preview, and Split; edits to one do
not change the other. The text is intentionally discarded on reload.

After installing the Loomark E2E dependencies, build with
`../../_build/tools/bin/warren build --browser-entry main --public-dir "$PWD/public"`
and run `node test.mjs` to check independent edits, preview, DOM selection, and
synthetic IME composition.

This is an integration experiment, **not** a stable external editor API. Each
instance supplies its own textarea DOM ID; the preview has no ID by default.
The example links the module's `styles/editor.css` and `styles/preview.css`
into `public/` for Warren to copy. Neither needs Loomark or Tailwind CSS;
the example's `styles.css` owns only the page, controls, and containing dimensions.
The preview renderer still emits legacy Loomark classes for the existing app.

Browser check: ordinary typing, select-all followed by typing, and a
programmatic `InputEvent` full replacement update the accepted text and preview
consistently. The browser automation command `fill` is different: it first
clears the textarea with a synthetic plain `Event("input")`, which Rabbita's
`on_input` handler does not accept as an `InputEvent`, then inserts new text
through native input events. Only the insertion reaches the app, so the
committed text and preview retain the old suffix while the DOM textarea does
not. Do not use `fill` as a native full-replacement test for this binding.
