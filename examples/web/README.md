# Canopy web workspace

`examples/web` is a Vite workspace containing eight active browser applications:
Lambda (`index.html`), JSON, Markdown, Memo, Posts, Resume/PKE, GenUI, and GenUI Possibilities. Each HTML surface has its own entry module, while the applications share Canopy editor-adapter types and generated MoonBit JavaScript modules.

The implementation inventory, source clusters, runtime ownership, tests, Vite relays, generated artifacts, and current boundary debt are documented in [`MODULE_MAP.md`](./MODULE_MAP.md).

## Waku deployment (#979)

The Waku application is the production deployment target. Cloudflare Workers
Builds deploys it to the `canopy-examples` Worker after every push to `main`.
The Vite workspace and legacy HTML entries remain available during the final
retirement stage, but GitHub Actions no longer deploys `examples/web` to Pages.

## Development

```bash
cd examples/web
npm ci
npm run dev:vite     # existing eight-surface application
npm run dev:waku     # Waku application
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
npm run test:waku:preview
npm run test:waku:workerd
```

`npm run build:deploy:waku` is the Cloudflare Workers Builds production build.
It initializes the pinned submodules, installs MoonBit dependencies, builds the
generated JavaScript, and then builds Waku. `npm run build:deploy` retains the
same setup with a final Vite build for local fallback validation. The production
Worker configuration is isolated in `wrangler.waku.jsonc`.

```bash
npm run check:waku-types
npx wrangler deploy --config wrangler.waku.jsonc --dry-run --env preview
npx wrangler check startup --config wrangler.waku.jsonc --env preview
npx wrangler deploy --config wrangler.waku.jsonc --dry-run --env production
npx wrangler check startup --config wrangler.waku.jsonc --env production
```

See [`CLOUDFLARE_DEPLOYMENT.md`](./CLOUDFLARE_DEPLOYMENT.md) for the native
Cloudflare Git build settings and rollback procedure.
