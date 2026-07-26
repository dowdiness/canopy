# Web module map

Implementation inventory for the current `examples/web` workspace. The source tree and Vite configuration are authoritative; this file records what exists today rather than prescribing a separate architecture.

## Active HTML surfaces

| Surface | HTML | Browser entry | Feature-owned source | Styles | Runtime and tests |
|---|---|---|---|---|---|
| Lambda | `index.html` | `src/entries/lambda.ts` | `features/lambda/browser/{mount,editor,ast-grep-runner}.ts`, `features/lambda/route/{lambda-route,lambda-client}.tsx` (uses shared decoration overlay) | `features/lambda/browser/styles.css`, imported by Vite and Waku composition | Browser + generated MoonBit Lambda/Graphviz; `tests/lambda-editor.spec.ts`, `waku-tests/lambda-route.spec.ts` |
| JSON | `json.html` | `src/entries/json.ts` | `features/json/browser/{editor,mount}.ts` (uses shared decoration overlay) | `features/json/browser/styles.css`, imported by `mount.ts` | Browser + generated MoonBit JSON; `tests/json-editor.spec.ts` |
| Markdown | `markdown.html` | `src/entries/markdown.ts` | `features/markdown/browser/{app,mount,sentinels}.ts`; `features/markdown/route/{markdown-route,markdown-client}.tsx` | `features/markdown/browser/styles.css`, imported by Vite and Waku composition; adapter CSS remains adapter-owned | Browser + generated MoonBit Markdown; `tests/markdown-editor.spec.ts`, `waku-tests/markdown-route.spec.ts` |
| Memo | `memo.html` | `src/entries/memo.ts` | `features/memo/core/edit-actions.ts`, `features/memo/browser/{app,mount,view}.ts`, `features/memo/route/{memo-route,memo-client}.tsx` | `features/memo/browser/styles.css`, imported by Vite and development Waku composition | Development browser + generated MoonBit Lambda; production local-only state; `tests/memo-editor.spec.ts`, `waku-tests/memo-route.spec.ts` |
| Posts | `posts.html` | `src/entries/posts.ts` | `features/posts/core/{posts,post-events,post-retrieval}.ts`, `features/posts/browser/{app,mount,post-events,post-store,view}.ts` | `features/posts/browser/styles.css`, imported by `mount.ts` | Browser persistence shell around deterministic retrieval logic; `tests/post-app.spec.ts` |
| Resume/PKE | `resume.html` | `src/entries/resume.ts` | `features/resume/browser/app.tsx`, `features/resume/browser/components/*`, `features/resume/core/session.ts`, `features/resume/protocol/chat.ts` | `features/resume/browser/styles.css`, imported by `app.tsx` | Browser React + `server/vite/resume-chat.ts` local chat relay; `tests/pi-resume.spec.ts` |
| GenUI | `genui.html` | `src/entries/genui.js` | `features/genui/browser/mount.js`, deterministic `features/genui/core/*` (fixtures, schema, flow, recorded candidates, data, spikes), `server/genui/feasibility-provider.js`, and `server/vite/genui-feasibility.ts` | `features/genui/browser/styles.css`, imported by `mount.js`; `src/tailwind.css` remains the GenUI Tailwind input | Browser + generated MoonBit JSX, deterministic feasibility core, and a server-only study relay; `tests/genui.spec.ts`, feasibility suites, colocated core/server Node tests, study scripts |
| GenUI Possibilities | `genui-possibilities.html` | `src/entries/genui-possibilities.js` | `features/genui-possibilities/core/journey-state.js`, `features/genui-possibilities/browser/mount.js` | `features/genui-possibilities/browser/styles.css`, imported by `mount.js` | Deterministic browser state; `tests/genui-possibilities.spec.ts`, `preview-tests/genui-preview.spec.ts` |

`spike-block-input.html` is an inactive investigation surface and is not part of the eight Vite inputs.

## Runtime and generated dependencies

- Browser code is TypeScript/TSX/JS bundled by Vite. React and the AI SDK are used by Resume/PKE; GenUI is plain browser JavaScript plus the generated JSX FFI.
- `server/vite/ast-grep.ts` owns the Lambda-only `/api/ast-grep` development relay for Vite and Waku. Its serve-only plugin is absent from production, where Mini-ML returns no analysis matches without a request. `vite-plugin-moonbit.ts` owns MoonBit build, virtual-module, and HMR behavior only.
- `server/vite/resume-chat.ts` owns the local Resume/PKE provider relay and consumes the Resume protocol surface. `server/vite/genui-feasibility.ts` owns the local GenUI study relay and imports `server/genui/feasibility-provider.js`; it consumes only GenUI core fixtures and recorded candidates. These Vite adapters are not browser entry dependencies.
- `signaling-server.js`, `signaling-worker.js`, `wrangler-signaling.toml`, and `wrangler.jsonc` are deployment/integration shells outside the eight browser entry graphs.

| Virtual module | Owning package/output | Browser owner |
|---|---|---|
| `@moonbit/crdt-lambda` | `_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.{js,d.ts}` | Lambda, Memo |
| `@moonbit/crdt-json` | `_build/js/release/build/dowdiness/canopy/ffi/json/json.{js,d.ts}` | JSON |
| `@moonbit/crdt-markdown` | `_build/js/release/build/dowdiness/canopy/ffi/markdown/markdown.{js,d.ts}` | Markdown |
| `@moonbit/crdt-jsx` | `_build/js/release/build/dowdiness/canopy/ffi/jsx/jsx.{js,d.ts}` | GenUI |
| `@moonbit/graphviz` | `_build/js/release/build/dowdiness/graphviz/browser/browser.{js,d.ts}` | Lambda |

`moonbit-artifacts.mjs` centralizes the five generated module definitions and is the canonical source for import IDs and output paths. Both `vite.config.ts` and `waku.config.ts` consume these definitions through `createMoonbitArtifactsPlugin`. `tsconfig.json` maps generated declarations, `scripts/build-js.sh` checks the expected artifacts, and CI uploads/downloads the same paths. Treat these locations as one artifact contract.

## Test and study ownership

- `playwright.config.ts` runs the default browser suites under `tests/`; `playwright.preview.config.ts` owns the production-preview GenUI check.
- `playwright.feasibility.config.ts` and `tests/genui-feasibility-live.spec.ts` own the live local-provider study path.
- `playwright.minimal-provider.config.ts` and `tests/genui-minimal-provider.spec.ts` own the bounded minimal-provider path.
- Deterministic GenUI tests are colocated under `src/features/genui/core/*.test.mjs`; provider tests are colocated under `server/genui/`. Study orchestration tests are `scripts/*.test.mjs`; study evidence is retained under `studies/`.
- `tests/fixtures/pi-session-v3.jsonl` belongs to Resume/PKE import and relay tests.
- `spike-block-input.html`, `test-ast-bug.js`, and `test-ast-comprehensive.js` are not active Vite inputs or current test-runner inputs. Their removal or archival requires a separate reviewed slice.

## Current structural exceptions and debt

The active surfaces use the target `src/entries`, `src/features`, and `src/shared` ownership layout. `shared/decoration-overlay.ts` is shared by Lambda and JSON. GenUI keeps deterministic fixtures/flows/schema/recorded candidates in its core, browser DOM/effect code in its browser surface, and Node/provider/Vite capabilities under `server/`. Memo reuses the Lambda generated runtime without importing Lambda feature internals. Styles are partly per-surface and partly adapter-owned. These are inventory facts, not exemptions from the boundary checker.

## Waku migration (pre-production, #970–#976 Stages 0–7)

Vite remains the default build for all eight HTML surfaces. A parallel Waku 1.0.0-beta.8 + Wrangler 4.114.0 application has landed alongside it. Stage 2 added the Hub, route-lifecycle Module, shell, placeholder routes, and 404; Stages 3–7 migrate Journey, Posts, JSON, Markdown, Mini-ML, and Memo while retaining every old HTML entry.

### Stage 0–1 configuration and artifacts

- `waku.config.ts` — Waku configuration with the official Cloudflare adapter (`waku/adapters/cloudflare`) and the shared MoonBit artifact plugin.
- `src/waku.server.tsx` — Waku server entry using `fsRouter` over `pages/**/*.{tsx,ts}`.
- `src/pages/foundation.tsx` — foundation probe page (moved from `index.tsx`); renders only a `MoonbitClientProbe` (generated-artifact boundary check, not a migrated demo).
- `src/pages/_root.tsx` — Waku root document; Stage 2 also anchors shared styles and the long-lived route-lifecycle provider here.
- `moonbit-artifacts.mjs` — single source of truth for the five generated module records, consumed by both Vite and Waku build pipelines.
- `wrangler.jsonc` — unchanged existing Vite deployment shell.
- `wrangler.waku.jsonc` — isolated pre-production Waku preview and production Worker environments.

### Stage 2 — Hub, lifecycle Module, shell, and common states

- `src/pages/index.tsx` — Demo Hub. `/index.html` renders the same Hub without redirect (not a `308`).
- `src/pages/404.tsx` — accessible true 404 with `aria-labelledby`, `tabIndex={-1}`, semantic heading.
- `src/pages/{resume,genui}.tsx` — two canonical placeholder routes; each renders `DemoPlaceholder` from the shared shell.
- `src/pages/ml.tsx` — canonical Mini-ML route; composes its feature-owned controller through the shared imperative host.
- `src/pages/memo.tsx` — canonical Memo route; composes the local client editor in development and the explicit unavailable state in production.
- `src/pages/journey.tsx` — canonical Journey route; composes the feature-owned route surface through the shared imperative host.
- `src/pages/posts.tsx` — canonical Posts route; composes the feature-owned route surface through the shared imperative host.
- `src/pages/json.tsx` — canonical JSON route; composes the feature-owned editor controller through the shared imperative host.
- `src/pages/markdown.tsx` — canonical Markdown route; composes the feature-owned three-mode editor through the shared imperative host.
- `src/pages/_layout.tsx` — pass-through shared route layout; the provider stays at `_root.tsx` so its in-memory registry survives route render failures.
- `src/shared/catalog/demo-catalog.ts` — framework-independent catalog data (eight demos, three groups, canonical `DemoPath` routes).
- `src/shared/shell/` — `DemoHub` and `DemoPlaceholder` React components and shared shell styles.
- `src/shared/route-lifecycle/core/reducer.ts` — pure `State + Event -> (State, Decision)` reducer.
- `src/shared/route-lifecycle/browser/` — React provider, imperative host, focus manager, imperative session, route render boundary, and common states.
- `waku-tests/foundation.spec.ts` and `waku-tests/hub.spec.ts` — deterministic Waku page tests.
- `scripts/waku-lifecycle-contract.test.mjs` — reducer/provider/focus/error/imperative-host contract tests.

### Stage 3 — Journey Proposals

- `src/features/genui-possibilities/route/{journey-route,journey-client}.tsx` — server/client route seam that reuses the legacy HTML as canonical Journey markup, preserves content during RSC navigation, and routes the existing wordmark through the lifecycle provider.
- `src/features/genui-possibilities/browser/mount.js` — shared Vite/Waku mount; scopes DOM ownership to the supplied container and returns the defensive snapshot, stable response-focus, and idempotent disposal session.
- `tests/genui-possibilities.spec.ts` — unchanged Journey behavior and visual contract, now also run against Waku `/journey`.
- `waku-tests/journey-route.spec.ts` — route-memory, reload-reset, browser-traversal focus, and repeated timer/listener disposal coverage.

Stage 3 remains pre-production. Vite and `genui-possibilities.html` remain the defaults and are retained. No Journey compatibility redirect is active.

### Stage 4 — Posts

- `src/features/posts/route/{posts-route,posts-client}.tsx` — server/client route seam that reuses the legacy Posts markup at `/posts` and mounts the existing browser persistence shell inside the shared imperative host.
- `src/features/posts/browser/{app,mount,view}.ts` — shared Vite/Waku mount with an allowlisted route snapshot (draft, related mode, highlighted post ID), host-scoped DOM ownership, stable focus restoration, and idempotent listener/scheduled-focus cleanup.
- `tests/post-app.spec.ts` — existing Posts behavior and storage contract, now run against both legacy Vite `/posts.html` and Waku `/posts`.
- `waku-tests/posts-route.spec.ts` — same-document route-memory, full-reload storage boundary, focus restoration, and repeated listener/scheduled-focus disposal coverage.

Stage 4 remains pre-production. Vite and `posts.html` remain the defaults and are retained. No Posts compatibility redirect is active, and the existing `canopy.posts.v1` and `canopy.post-events.v1` schemas remain unchanged.

### Stage 5 — JSON editor

- `src/features/json/route/{json-route,json-client}.tsx` — server/client route seam that reuses the legacy JSON markup, loads the generated MoonBit runtime only in the client bundle, and mounts through the shared imperative host.
- `src/features/json/browser/{editor,mount}.ts` — root-scoped controller shared by Waku and Vite; snapshots source text only and owns the MoonBit handle, adapter, overlay, frames, listeners, focus, and global test hook until idempotent disposal.
- `tests/json-editor.spec.ts` — existing JSON behavior contract, now run against both legacy Vite `/json.html` and Waku `/json`.
- `waku-tests/json-route.spec.ts` — no-JavaScript inertness, route-memory/reload boundaries, reconstructed mode/collapse/edit-log state, focus restoration, and repeated resource-disposal coverage.

Stage 5 remains pre-production. Vite and `json.html` remain the defaults and are retained. No JSON compatibility redirect is active, and no MoonBit editor API or workflow changed.

### Stage 6 — Markdown editor

- `src/features/markdown/route/{markdown-route,markdown-client}.tsx` — server/client route seam that reuses the legacy Markdown markup, keeps the generated MoonBit runtime client-only, and mounts through the shared imperative host.
- `src/features/markdown/browser/{app,mount,sentinels}.ts` — root-scoped controller shared by Waku and Vite; snapshots document text only while rebuilding mode, active block, raw-dirty, and DOM-selection state after route return. It owns the MoonBit handle, `BlockInput`, `MarkdownPreview`, pending frame, listeners, and focus until idempotent disposal.
- `adapters/editor-adapter/block-input.ts` — explicitly owns and cancels its deferred `pointerup` listener and clears callbacks during disposal.
- `tests/markdown-editor.spec.ts` — existing Markdown mode, selection, edit, and preview contract, now run against both legacy Vite `/markdown.html` and Waku `/markdown`.
- `waku-tests/markdown-route.spec.ts` — no-JavaScript inertness, runtime-failure boundary, document-only route memory, rebuilt-mode focus fallback, reload reset, and repeated listener/frame disposal coverage.

Stage 6 remains pre-production. Vite and `markdown.html` remain the defaults and are retained. No Markdown compatibility redirect is active, and no Markdown model, toolbar, mode semantics, or MoonBit API changed.

### Stage 7 — Mini-ML and Memo

- `src/features/lambda/route/{lambda-route,lambda-client}.tsx` — server/client seam that reuses the legacy Mini-ML shell, loads Lambda and Graphviz from client-only dynamic imports, and mounts at `/ml` through the imperative host.
- `src/features/lambda/browser/{editor,mount}.ts` — root-scoped Vite/Waku controller that snapshots source text only and idempotently releases the MoonBit handle, `HTMLAdapter`, `DecorationOverlay`, listeners, animation frame, analysis timer, and request.
- `src/features/memo/route/{memo-route,memo-client}.tsx` — development route seam that shares the generated Lambda artifact specifier without a cross-feature import; production tree-shakes the client editor and renders a local-only state without credential/provider controls.
- `src/features/memo/browser/{app,mount,view}.ts` — root-scoped controller that snapshots draft, instruction, and completed proposal only; API key and request timing remain ephemeral, listeners are aborted, and late provider responses are invalidated after disposal.
- `tests/{lambda-editor,memo-editor}.spec.ts` — existing behavior and local-validation contracts, now run against both legacy Vite URLs and canonical Waku routes.
- `waku-tests/{lambda-route,memo-route}.spec.ts` — inert SSR shells, runtime failures, allowlisted route memory, focus, reload reset, and live-resource disposal coverage. The production bundle/Worker checks prove Mini-ML has no AST endpoint request and Memo has no credential surface.

Stage 7 remains pre-production. Vite `/`/`index.html` and `/memo.html` remain the defaults and are retained. No compatibility redirect, provider proxy, MoonBit API change, or production deployment is active.

Validation runs in parallel with the Vite pipeline:

- `npm run build:waku` — Waku production build from prebuilt MoonBit artifacts.
- `npm run check:waku-bundles` — asserts generated client/server bundle boundaries.
- `npm run test:waku:e2e` — Playwright suite under `playwright.waku.config.ts`.
- `npm run test:waku:workerd` — built Worker/static-asset smoke under local workerd.
- `npm run check:waku-types` — checks generated Waku Cloudflare binding types against the pinned config and build.
- `npx wrangler deploy --config wrangler.waku.jsonc --dry-run --env preview` — preview Waku Worker bundle dry-run.
- CI jobs `waku-build`, `waku-e2e`, and `waku-workerd` run alongside the existing Vite jobs until Stage 12 (Vite retirement).

Both development modes reuse the same coordinator, which starts one root MoonBit watcher rather than one watcher per virtual module. `npm run dev:dual` runs Vite and Waku side by side behind that single watcher. Generated modules stay client-only on the Waku side; the probe loads all five, JSON and Markdown load their own runtimes on demand, and Mini-ML/Memo share the Lambda artifact specifier without sharing feature internals.

## Boundary vocabulary and allowed direction

The target vocabulary is:

- **entries**: one thin browser composition module per HTML surface;
- **features**: browser-owned modules for one application only;
- **shared**: reusable deterministic types, adapters, protocols, and core logic;
- **server**: Node/Vite/provider capabilities and relays.

Style ownership is explicit: feature-only styles live under that feature's `browser/` directory and are imported by a browser module; stable multi-feature styles belong under `shared/browser/`; adapter styles remain imported from the adapter package. Inline HTML styles are migration debt unless a documented delivery or CSP constraint requires them.

Allowed direction is `entries -> corresponding feature -> shared`; server adapters may consume shared/core data but browser code must not consume server. Shared cannot consume features. A feature cannot consume another feature's internals. Declared `core/` and `protocol/` paths cannot import Node, Vite, React, or provider capabilities. The checker parses static imports with the TypeScript compiler and classifies the current flat tree explicitly; new target-shaped paths are checked by the same rules.

## Validation

```bash
npm ci
npm run check:boundaries
npm run test:boundaries
npm run typecheck   # generated MoonBit declarations must exist
npm run build
npm run preview
```

Playwright suites live in `tests/` and `preview-tests/`; deterministic unit/study tests are colocated under `src/` and `scripts/`. The repository-level JS build (`moon build --target js`, or `scripts/build-web.sh`) produces the generated dependencies before typecheck/build in CI.
