# Canopy web workspace

`examples/web` is a Vite workspace containing eight active browser applications:
Lambda (`index.html`), JSON, Markdown, Memo, Posts, Resume/PKE, GenUI, and GenUI Possibilities. Each HTML surface has its own entry module, while the applications share Canopy editor-adapter types and generated MoonBit JavaScript modules.

The implementation inventory, source clusters, runtime ownership, tests, Vite relays, generated artifacts, and current boundary debt are documented in [`MODULE_MAP.md`](./MODULE_MAP.md).

## Development

```bash
cd examples/web
npm ci
npm run dev
```

The Vite configuration relays MoonBit modules from the repository build output and rebuilds them during development when needed. Build artifacts are namespaced under `_build/js/release/build/dowdiness/`.

```bash
npm run typecheck
npm run check:boundaries
npm run test:boundaries
npm run build
npm run preview
```

For a deploy build, use `npm run build:deploy`; it installs MoonBit and builds the generated JavaScript before running Vite.
