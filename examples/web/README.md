# Canopy web workspace

`examples/web` is a Vite workspace containing eight active browser applications:
Lambda (`index.html`), JSON, Markdown, Memo, Posts, Resume/PKE, GenUI, and GenUI Possibilities. Each HTML surface has its own entry module, while the applications share Canopy editor-adapter types and generated MoonBit JavaScript modules.

The implementation inventory, source clusters, runtime ownership, tests, Vite relays, generated artifacts, and current boundary debt are documented in [`MODULE_MAP.md`](./MODULE_MAP.md).

## Waku migration (in progress, #971)

A parallel Waku application is being built alongside the existing Vite workspace. Vite remains the default and production deploy path until final cutover. Stage 2 adds the Demo Hub, route-lifecycle Module (reducer, provider, focus manager, imperative host, error boundary), shared shell, eight canonical placeholder routes, and accessible 404. No demo behavior has been migrated; the previous foundation probe moved to `/foundation`, and no old HTML entry has been removed.

## Development

```bash
cd examples/web
npm ci
npm run dev:vite     # existing eight-surface application
npm run dev:waku     # pre-production Waku foundation
npm run dev:dual     # both servers with one shared root MoonBit watcher
```

`npm run dev` and `npm run build` remain Vite aliases until the final cutover. Both development modes reuse one root MoonBit build/watch coordinator; generated outputs remain namespaced under `_build/js/release/build/dowdiness/`.

```bash
npm run typecheck
npm run check:boundaries
npm run test:boundaries
npm run test:foundation
npm run build:vite
npm run build:waku
npm run check:waku-bundles
npm run test:waku:e2e
npm run test:waku:workerd
```

For the existing Pages deploy build, use `npm run build:deploy`; it installs MoonBit and builds the generated JavaScript before running Vite. The default `wrangler.jsonc` remains owned by that Vite deployment. The pre-production Waku foundation is isolated in `wrangler.waku.jsonc` and is not the production deploy path.

```bash
npm run check:waku-types
npx wrangler deploy --config wrangler.waku.jsonc --dry-run --env preview
```
