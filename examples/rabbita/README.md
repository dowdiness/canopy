# Rabbita Projectional Editor Example

This directory is a Rabbita app scaffolded to follow the
[`moonbit-community/rabbita-template`](https://github.com/moonbit-community/rabbita-template)
layout:

- `moon.mod.json`
- `main/moon.pkg`
- `main/main.mbt`
- `index.html`
- `styles.css`
- `vite.config.js`
- `package.json`

The app is a frontend shell for the projectional editor architecture in this
repo. It is intentionally a UI-first prototype, not a fully wired editor yet.

## What is here

- `main/main.mbt` renders a Rabbita app with:
  - toolbar mode switching
  - a tree-first editor pane
  - a synchronized text pane
  - an inspector sidebar
- `app_sketch.mbt` keeps the larger AST-first integration sketch

## Getting started

From this directory:

```bash
moon add moonbit-community/rabbita
npm i
npm run dev
```

Then open the Vite URL in your browser.

## Notes

- This example is a separate MoonBit module under `examples/rabbita`.
- It is not wired into the root `dowdiness/crdt` module graph.
- The current UI demonstrates the intended Rabbita shape while the editor core
  is still converging on the `SyncEditor` facade described in
  `docs/design/03-unified-editor.md`.
