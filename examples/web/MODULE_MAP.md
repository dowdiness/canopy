# Web module map

Current implementation inventory for the `examples/web` Waku Worker. Source files and Waku configuration are authoritative; this file records what exists today.

## Route → feature ownership

| Canonical route | Waku page | Feature-owned route surface | Feature-owned browser mount | Styles | Runtime and tests |
|---|---|---|---|---|---|
| `/` | `src/pages/index.tsx` | Demo Hub in `src/shared/shell/` | N/A (React-only) | `src/shared/shell/` styles | Waku SSR; `waku-tests/hub.spec.ts` |
| `/ml` | `src/pages/ml.tsx` | `src/features/lambda/route/` | `src/features/lambda/browser/{ast-grep-runner,editor}.ts` | `src/features/lambda/browser/styles.css` | Generated MoonBit Lambda/Graphviz; `tests/lambda-editor.spec.ts`, `waku-tests/lambda-route.spec.ts` |
| `/json` | `src/pages/json.tsx` | `src/features/json/route/` | `src/features/json/browser/editor.ts` | `src/features/json/browser/styles.css` | Generated MoonBit JSON; `tests/json-editor.spec.ts`, `waku-tests/json-route.spec.ts` |
| `/markdown` | `src/pages/markdown.tsx` | `src/features/markdown/route/` | `src/features/markdown/browser/{app,sentinels}.ts` | `src/features/markdown/browser/styles.css` | Generated MoonBit Markdown; `tests/markdown-editor.spec.ts`, `waku-tests/markdown-route.spec.ts` |
| `/journey` | `src/pages/journey.tsx` | `src/features/genui-possibilities/route/` | `src/features/genui-possibilities/browser/mount.js` | `src/features/genui-possibilities/browser/styles.css` | Deterministic JS reducer; `tests/genui-possibilities.spec.ts`, `waku-tests/journey-route.spec.ts` |
| `/posts` | `src/pages/posts.tsx` | `src/features/posts/route/` | `src/features/posts/browser/{app,mount,post-events,post-store,view}.ts` | `src/features/posts/browser/styles.css` | Browser persistence over deterministic core; `tests/post-app.spec.ts`, `waku-tests/posts-route.spec.ts` |
| `/memo` | `src/pages/memo.tsx` | `src/features/memo/route/` | `src/features/memo/browser/{app,view}.ts` | `src/features/memo/browser/styles.css` | Generated MoonBit Lambda (shared specifier with `/ml`); `tests/memo-editor.spec.ts`, `waku-tests/memo-route.spec.ts` |
| `/resume` | `src/pages/resume.tsx` | `src/features/resume/route/resume-route.tsx` | `src/features/resume/browser/app.tsx` (native React) | `src/features/resume/browser/styles.css` | React 19 + local dev relay; `tests/pi-resume.spec.ts`, `waku-tests/resume-route.spec.ts` |
| `/genui` | `src/pages/genui.tsx` | `src/features/genui/route/` | `src/features/genui/browser/mount.js` | `src/features/genui/{browser,route}/styles.css` | Generated MoonBit JSX, deterministic feasibility core; `tests/genui.spec.ts`, `waku-tests/genui-route.spec.ts` |

## Compatibility aliases (permanent redirects)

Seven `.html` paths return 308 to their canonical route, preserving query/fragment:

| Alias | Redirects to |
|---|---|
| `/json.html` | `/json` |
| `/markdown.html` | `/markdown` |
| `/memo.html` | `/memo` |
| `/posts.html` | `/posts` |
| `/resume.html` | `/resume` |
| `/genui.html` | `/genui` |
| `/genui-possibilities.html` | `/journey` |

`/index.html` renders the same Hub as `/` without redirect.

## Retained inactive spike

`spike-block-input.html` is an inactive investigation surface at the workspace root. It is not a Waku route, not tested, and has no entry module. Its removal or archival requires a separate reviewed slice.

## Shared lifecycle and server contracts

### Route-lifecycle module

- `src/shared/route-lifecycle/core/reducer.ts` — pure `State + Event -> (State, Decision)` reducer.
- `src/shared/route-lifecycle/browser/` — React provider, imperative host, focus manager, imperative session, route render boundary, and common states.
- `scripts/waku-lifecycle-contract.test.mjs` — reducer/provider/focus/error/imperative-host contract tests.

### Waku server and Worker

- `waku.config.ts` — Waku configuration with official Cloudflare adapter, shared MoonBit artifact and Tailwind plugins, and serve-only local adapters (AST Grep, Resume chat, GenUI feasibility).
- `src/waku.server.tsx` — Waku server entry using `fsRouter` over `pages/**/*.{tsx,ts}`.
- `src/pages/_root.tsx` — root document; shared styles and long-lived route-lifecycle provider.
- `src/pages/_layout.tsx` — pass-through shared route layout.
- `src/pages/404.tsx` — accessible true 404.
- `src/pages/foundation.tsx` — foundation probe page.
- `server/waku/request-policy.ts` — deterministic request classifier for seven document/RSC redirects, exact canonical/RSC routes, and static assets.
- `server/waku/signaling-proxy.ts` — thin Hono shell forwarding to `ASSETS` or `SIGNALING`.
- `server/waku/observability.ts` — closed telemetry record; accepts only deployment version, route class, capability, status, and error category.
- `wrangler.jsonc` — canonical Waku Worker environments (preview and production).
- `wrangler.waku.jsonc` — compatibility symlink used by existing external Build/Deploy settings.

### Local development adapters (serve-only)

- `server/vite/ast-grep.ts` — Lambda-only `/api/ast-grep` development relay.
- `server/vite/resume-chat.ts` — local Resume chat provider relay.
- `server/vite/genui-feasibility.ts` — local GenUI study relay.
- `server/vite/moonbit.ts` — MoonBit build, virtual-module, and HMR plugin; reused by Waku's Vite integration.

These Vite adapters are not browser entry dependencies. Production Worker bundles exclude their endpoints, provider markers, and development hooks.

## Generated artifacts

| Virtual module | Owning package/output | Route owner(s) |
|---|---|---|
| `@moonbit/crdt-lambda` | `_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.{js,d.ts}` | `/ml`, `/memo` |
| `@moonbit/crdt-json` | `_build/js/release/build/dowdiness/canopy/ffi/json/json.{js,d.ts}` | `/json` |
| `@moonbit/crdt-markdown` | `_build/js/release/build/dowdiness/canopy/ffi/markdown/markdown.{js,d.ts}` | `/markdown` |
| `@moonbit/crdt-jsx` | `_build/js/release/build/dowdiness/canopy/ffi/jsx/jsx.{js,d.ts}` | `/genui` |
| `@moonbit/graphviz` | `_build/js/release/build/dowdiness/graphviz/browser/browser.{js,d.ts}` | `/ml` |

`moonbit-artifacts.mjs` centralizes the five generated module definitions. `waku.config.ts` consumes these definitions through `createMoonbitArtifactsPlugin` in `server/vite/moonbit.ts`. `tsconfig.json` maps generated declarations, `scripts/build-js.sh` checks the expected artifacts, and CI uploads/downloads the same paths. Treat these locations as one artifact contract.

## Test ownership

- `tests/` — existing per-demo Playwright suites; now run against canonical Waku routes.
- `waku-tests/` — route-memory, reload-reset, focus, disposal, and inert-SSR coverage per route.
- `preview-tests/` — production-preview GenUI recorded-replay and capability-absence checks.
- `playwright.waku.config.ts` — canonical route E2E suites.
- `playwright.waku-preview.config.ts` and `playwright.waku-preload.config.ts` — production preview suites.
- Deterministic GenUI tests colocated under `src/features/genui/core/*.test.mjs`; provider tests colocated under `server/genui/`. Study orchestration tests are `scripts/*.test.mjs`; study evidence retained under `studies/`.
- `scripts/waku-lifecycle-contract.test.mjs` — lifecycle reducer/provider/focus/error contract tests.
- `server/waku/request-policy.test.mjs` — request classifier tests.
- `scripts/smoke-waku-worker.sh` — built Worker/static-asset smoke under local workerd with multi-worker signaling.
- `tests/fixtures/pi-session-v3.jsonl` belongs to Resume import and relay tests.
- `spike-block-input.html`, `test-ast-bug.js`, and `test-ast-comprehensive.js` are not current test-runner inputs.

## Deployment compatibility

`npm run build:deploy:waku` is the Cloudflare Workers Builds production build alias. It initializes the pinned submodules, installs MoonBit dependencies, builds the generated JavaScript, and builds Waku. It is retained because Cloudflare Workers Builds external settings currently call this exact script name. The external deploy command still references `wrangler.waku.jsonc`; that compatibility symlink resolves to the canonical `wrangler.jsonc` so Waku and native deployment share one configuration source.

## Boundary vocabulary and allowed direction

The vocabulary is:

- **pages**: one Waku filesystem route per canonical demo;
- **features**: browser-owned, route, core, and protocol modules for one demo;
- **shared**: reusable deterministic types, adapters, protocols, route-lifecycle module, shell, and core logic;
- **server**: Waku Worker capabilities, local development adapters, and relays.

Allowed direction is `pages -> corresponding feature route surface -> feature browser -> shared`; server adapters may consume shared/core data but browser code must not consume server. Shared cannot consume features. A feature cannot consume another feature's internals. Declared `core/` and `protocol/` paths cannot import Node, Vite, React, or provider capabilities. The checker classifies Waku pages, feature route surfaces, Waku server modules, and client-only generated imports.

## Validation

```bash
cd examples/web
npm ci
npm run typecheck
npm run check:boundaries
npm run test:boundaries
npm run test:foundation
npm run build
npm run check:waku-bundles
npm run check:waku-types
npm run test:waku:e2e
npm run test:waku:preview
npm run test:waku:workerd
```

The repository-level JS build (`moon build --target js`, or `scripts/build-js.sh`) produces the generated dependencies before typecheck/build in CI.
