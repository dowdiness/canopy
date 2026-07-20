# Web module map

Implementation inventory for the current `examples/web` workspace. The source tree and Vite configuration are authoritative; this file records what exists today rather than prescribing a separate architecture.

## Active HTML surfaces

| Surface | HTML | Browser entry | Feature-owned source | Styles | Runtime and tests |
|---|---|---|---|---|---|
| Lambda | `index.html` | `src/entries/lambda.ts` | `features/lambda/browser/{mount,editor,ast-grep-runner}.ts` (uses shared decoration overlay) | Inline in `index.html` | Browser + generated MoonBit Lambda/Graphviz; `tests/lambda-editor.spec.ts` |
| JSON | `json.html` | `src/entries/json.ts` | `features/json/browser/{editor,mount}.ts` (uses shared decoration overlay) | Inline in `json.html` plus `src/json-editor.css` | Browser + generated MoonBit JSON; `tests/json-editor.spec.ts` |
| Markdown | `markdown.html` | `src/entries/markdown.ts` | `features/markdown/browser/{app,mount,sentinels}.ts` | Inline in `markdown.html` plus editor-adapter CSS | Browser + generated MoonBit Markdown; `tests/markdown-editor.spec.ts` |
| Memo | `memo.html` | `src/entries/memo.ts` | `features/memo/core/edit-actions.ts`, `features/memo/browser/{app,mount,view}.ts` | Inline in `memo.html` | Browser + generated MoonBit Lambda; `tests/memo-editor.spec.ts` |
| Posts | `posts.html` | `src/entries/posts.ts` | `features/posts/core/{posts,post-events,post-retrieval}.ts`, `features/posts/browser/{app,mount,post-events,post-store,view}.ts` | Inline in `posts.html` | Browser persistence shell around deterministic retrieval logic; `tests/post-app.spec.ts` |
| Resume/PKE | `resume.html` | `src/resume-app.tsx` | `resume-app.tsx`, `pi-resume-core.ts`, `pi-resume-chat-protocol.ts`, `components/ai-elements/*` | `src/resume.css` | Browser React + Vite chat relay; `tests/pi-resume.spec.ts` |
| GenUI | `genui.html` | `src/genui.js` | `genui.js`, `genui-data.ts`, feasibility flow/fixtures/schema/provider/recorded/spike modules, `src/fixtures/*` | Inline in `genui.html` plus `src/tailwind.css` | Browser + generated MoonBit JSX, deterministic feasibility code, and a server-only provider; `tests/genui.spec.ts`, feasibility suites, colocated Node tests, study scripts |
| GenUI Possibilities | `genui-possibilities.html` | `src/entries/genui-possibilities.js` | `features/genui-possibilities/core/journey-state.js`, `features/genui-possibilities/browser/mount.js` | `src/genui-possibilities.css` | Deterministic browser state; `tests/genui-possibilities.spec.ts`, `preview-tests/genui-preview.spec.ts` |

`spike-block-input.html` is an inactive investigation surface and is not part of the eight Vite inputs.

## Runtime and generated dependencies

- Browser code is TypeScript/TSX/JS bundled by Vite. React and the AI SDK are used by Resume/PKE; GenUI is plain browser JavaScript plus the generated JSX FFI.
- `vite-plugin-moonbit.ts` owns MoonBit builds, virtual-module loading, output watching, and HMR. It also currently owns the Lambda-only `/api/ast-grep` development relay.
- `vite-plugin-pi-resume-chat.ts` owns the local Resume/PKE provider relay. `vite-plugin-genui-feasibility.ts` owns the local GenUI study relay and imports the server-only `src/genui-feasibility-provider.js`. These Vite adapters are not browser entry dependencies.
- `signaling-server.js`, `signaling-worker.js`, `wrangler-signaling.toml`, and `wrangler.jsonc` are deployment/integration shells outside the eight browser entry graphs.

| Virtual module | Owning package/output | Browser owner |
|---|---|---|
| `@moonbit/crdt-lambda` | `_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.{js,d.ts}` | Lambda, Memo |
| `@moonbit/crdt-json` | `_build/js/release/build/dowdiness/canopy/ffi/json/json.{js,d.ts}` | JSON |
| `@moonbit/crdt-markdown` | `_build/js/release/build/dowdiness/canopy/ffi/markdown/markdown.{js,d.ts}` | Markdown |
| `@moonbit/crdt-jsx` | `_build/js/release/build/dowdiness/canopy/ffi/jsx/jsx.{js,d.ts}` | GenUI |
| `@moonbit/graphviz` | `_build/js/release/build/dowdiness/graphviz/browser/browser.{js,d.ts}` | Lambda |

`vite.config.ts` defines the runtime mappings, `tsconfig.json` maps generated declarations, `scripts/build-js.sh` checks the expected artifacts, and CI uploads/downloads the same paths. Treat these four locations as one artifact contract.

## Test and study ownership

- `playwright.config.ts` runs the default browser suites under `tests/`; `playwright.preview.config.ts` owns the production-preview GenUI check.
- `playwright.feasibility.config.ts` and `tests/genui-feasibility-live.spec.ts` own the live local-provider study path.
- `playwright.minimal-provider.config.ts` and `tests/genui-minimal-provider.spec.ts` own the bounded minimal-provider path.
- Deterministic GenUI tests are colocated as `src/genui-*.test.mjs`. Study orchestration tests are `scripts/*.test.mjs`; study evidence is retained under `studies/`.
- `tests/fixtures/pi-session-v3.jsonl` belongs to Resume/PKE import and relay tests.
- `spike-block-input.html`, `test-ast-bug.js`, and `test-ast-comprehensive.js` are not active Vite inputs or current test-runner inputs. Their removal or archival requires a separate reviewed slice.

## Current structural exceptions and debt

Most of the source tree is intentionally flat: feature ownership is inferred from filenames rather than represented by `src/entries`, `src/features`, and `src/shared` directories. Posts, Memo, JSON, and Markdown are pilot migrations to the target entry/feature layout. `shared/decoration-overlay.ts` is shared by Lambda and JSON. GenUI feasibility modules mix deterministic fixtures/flows with the server-only provider. Memo reuses the Lambda generated runtime. Styles are partly per-surface and partly global/adapter-owned. These are inventory facts, not exemptions from the boundary checker.

## Boundary vocabulary and allowed direction

The target vocabulary is:

- **entries**: one thin browser composition module per HTML surface;
- **features**: browser-owned modules for one application only;
- **shared**: reusable deterministic types, adapters, protocols, and core logic;
- **server**: Node/Vite/provider capabilities and relays.

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
