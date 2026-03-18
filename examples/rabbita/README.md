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

The app is the current end-to-end example of the projectional editor
architecture in this repo. It is still a focused example app rather than the
final product UI, but the tree editor is wired through `SyncEditor` and the
projection packages rather than being a static mock.

## What is here

- `main/main.mbt` renders a Rabbita app with:
  - toolbar mode switching
  - a tree-first editor pane
  - a synchronized text pane
  - an inspector sidebar
- tree operations routed through `SyncEditor::apply_tree_edit(...)`
- collapsed-subtree elision plus targeted expand hydration
- index-backed tree selection, range selection, drag guards, and delete
- `perf_report/` for Rabbita-specific editor benchmarks

## Getting started

From this directory:

```bash
moon add moonbit-community/rabbita
bun install
bun run dev
```

Then open the Vite URL in your browser.

## Notes

- This example is a separate MoonBit module under `examples/rabbita`.
- It is not wired into the root `dowdiness/canopy` module graph.
- The current UI is built on the `SyncEditor` facade and `TreeEditorState`
  implementation in the root packages.
- It remains the most complete example of the projectional editor flow, but it
  is still intentionally narrower than the future multi-pane product design
  described in `docs/design/03-unified-editor.md`.

## Cloudflare Pages

`bun run build` now bootstraps the MoonBit CLI when it is missing, initializes
required git submodules, and runs `moon update` in CI-style environments before
invoking Vite. That is the correct build command for Cloudflare Pages.

The example pins `bun@1.2.15` in `package.json` to match the Bun version
reported by Cloudflare for this project.

If you prefer an explicit CI command, `bun run build:deploy` runs the same flow
with `CI=true`.

The scripts remain package-manager neutral, so `npm run build` still works
locally if you already have npm set up.

Recommended Cloudflare Pages settings for this example:

- Root directory: `examples/rabbita`
- Install command: `bun install`
- Build command: `bun run build`
- Build output directory: `dist`

The Wrangler files under `examples/web/` in this repo are for a different deployment
target and do not configure `examples/rabbita`.

If your Cloudflare project runs a deploy command such as `bunx wrangler deploy`,
this example now includes a local `wrangler.jsonc` that declares `dist` as the
static asset directory and enables SPA fallback routing.
