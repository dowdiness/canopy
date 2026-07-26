# Canopy web workspace

`examples/web` is a Vite workspace containing eight active browser applications:
Lambda (`index.html`), JSON, Markdown, Memo, Posts, Resume/PKE, GenUI, and GenUI Possibilities. Each HTML surface has its own entry module, while the applications share Canopy editor-adapter types and generated MoonBit JavaScript modules.

The implementation inventory, source clusters, runtime ownership, tests, Vite relays, generated artifacts, and current boundary debt are documented in [`MODULE_MAP.md`](./MODULE_MAP.md).

## Waku migration (in progress, #975)

A parallel Waku application is being built alongside the existing Vite workspace. Vite remains the default and production deploy path until final cutover. Stages 0–2 provide the foundation, Demo Hub, route-lifecycle Module, shared shell, canonical routes, and accessible 404. Stages 3–6 migrate Journey Proposals, Posts, JSON, and Markdown to `/journey`, `/posts`, `/json`, and `/markdown`. JSON and Markdown snapshot source text only and rebuild their live MoonBit controller state after navigation; Markdown keeps its within-demo mode and selection behavior. All four use the imperative host and retain their legacy HTML entries; the other four canonical demo routes remain placeholders. No compatibility redirect, production deployment, or Vite removal is active.

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
(cd ../.. && moon build --target js)
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
