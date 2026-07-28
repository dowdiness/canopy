# Unified Waku Web Migration

**Status:** completed

**Map:** [#947](https://github.com/dowdiness/canopy/issues/947)

**Decisions:** [#948](https://github.com/dowdiness/canopy/issues/948), [#949](https://github.com/dowdiness/canopy/issues/949), [#950](https://github.com/dowdiness/canopy/issues/950), [#951](https://github.com/dowdiness/canopy/issues/951), [#952](https://github.com/dowdiness/canopy/issues/952), [#953](https://github.com/dowdiness/canopy/issues/953), [#954](https://github.com/dowdiness/canopy/issues/954), [#955](https://github.com/dowdiness/canopy/issues/955), [#956](https://github.com/dowdiness/canopy/issues/956), [#957](https://github.com/dowdiness/canopy/issues/957)

**Behavior baseline:** [`c82368c5`](https://github.com/dowdiness/canopy/commit/c82368c5)

## Completion Evidence

- **PR:** [#997](https://github.com/dowdiness/canopy/pull/997) squash-merged at 2026-07-28T16:00:20Z.
- **Merge commit:** `e47aee68677b91cd433b0a0d5253ced715cac62c`.
- **CI:** repository `All Checks Passed` passed on the final PR head; CodeRabbit's final rerun was pass with reason `Review rate limited`, after its five earlier actionable findings were fixed and local/CI validation reran.
- **Deployment:** native Cloudflare Workers Builds produced Worker version `37b75d02-124a-468f-abc4-75d673eb5ac5`, deployment `9453ae99-b0a8-47d9-8976-00fa320a06e1` at 2026-07-28T16:02:06Z, 100% traffic. Previous rollback version: `8fc4338a-b425-430b-a05b-8b91f1b85679`.
- **Production acceptance:** all nine canonical routes plus `/index.html` returned 200; seven document aliases and their RSC aliases returned 308 with query preservation; unknown route returned 404; Memo production-unavailable boundary, Resume production-chat-unavailable boundary, GenUI recorded replay and production hook exclusion, Waku history/focus, Signaling WebSocket, and error-only live tail all passed. No error invocation appeared for the new version.

## Why

`examples/web` originally built eight independent HTML inputs with Vite. The
migration replaced those inputs with one routed Waku application without
losing the verified demo workflows, the five generated MoonBit JavaScript
contracts, the local-development capability split, existing Posts data, or the
ability to fall back to the prior deployment.

The route decision in #952 adds a stronger requirement than changing URLs:
navigation must behave as a reversible context switch. User work may survive a
same-document route change, but every live editor, adapter, request, timer, and
DOM listener must still be released when its route leaves.

This document is the single implementation specification for that migration.
Issues track execution status and link here rather than duplicating this detail.

## Scope

### In

- Convert the eight active surfaces listed in `examples/web/MODULE_MAP.md` to
  Waku filesystem routes under `examples/web/src/pages/`.
- Server-render the Demo Hub, document shell, route metadata, compatibility
  behavior, and error pages.
- Keep editor- and DOM-dependent implementations below client boundaries.
- Preserve the five public virtual import IDs and generated artifact paths from
  `examples/web/vite.config.ts`, `examples/web/vite-plugin-moonbit.ts`, and
  `scripts/build-js.sh`.
- Introduce one shared route-lifecycle Module for same-document snapshots,
  disposal decisions, focus restoration, and route-level errors.
- Keep the Waku Worker and Signaling Worker independently deployable and connect
  them through a Cloudflare service binding.
- Run Vite and Waku validation in parallel until production cutover is proven.
- Add staging, observability, deployment, and rollback gates for the Waku
  Worker.

### Out

- Changes to MoonBit source, generated MoonBit interfaces, or the five public
  virtual import IDs.
- Signaling protocol, room, Durable Object, or WebSocket lifecycle redesign.
- Production enablement of AST Grep, Resume chat, live GenUI feasibility, or the
  current Memo browser credential flow.
- Deep redesign of any demo workflow.
- A persistent demo directory, sidebar, or showcase shell around every route.
- Persistence of new demo data in `localStorage`, `sessionStorage`, IndexedDB,
  cookies, or `history.state`.
- The inactive `spike-block-input.html` surface and the throwaway Hub prototype.

## Baseline State (2026-07-25, `c82368c5`)

- `examples/web/vite.config.ts` names the eight active HTML inputs.
- `examples/web/src/entries/` contains one thin browser entry per surface.
- `examples/web/src/features/` owns each demo's browser, core, and protocol
  implementation; `examples/web/src/shared/decoration-overlay.ts` is the only
  current shared browser module.
- `examples/web/server/vite/` owns the development-only AST Grep, Resume chat,
  and GenUI feasibility adapters.
- `examples/web/vite.config.ts` composes React, Tailwind, all three local
  adapters, and `moonbitPlugin` with the five virtual-module records.
- `scripts/build-js.sh` produces and checks the five generated JavaScript and
  declaration outputs before the web build.
- `examples/web/scripts/check-boundaries.mjs` enforces the current
  `entries -> corresponding feature -> shared` direction and keeps browser,
  core/protocol, and server capabilities separated.
- `.github/workflows/ci.yml` builds MoonBit JavaScript, builds and typechecks the
  web example, runs boundary checks, and runs the Playwright suite.
- `.github/workflows/deploy-cloudflare.yml` deployed `examples/web/dist`
  to the `canopy-lambda-editor` Cloudflare Pages project on pushes to `main`
  (superseded by the Waku Worker deployment in Stage 12).
- `examples/web/wrangler-signaling.toml` deploys the separate
  `crdt-signaling-server` Worker and its `SIGNALING_ROOM` Durable Object.

The behavior inventory at `c82368c5` is the acceptance source for each demo.
Code wins if that document and the implementation disagree.

## Desired State

### Routes

| Surface | Canonical route | Compatibility behavior |
| --- | --- | --- |
| Demo Hub | `/` | `/index.html` renders the same Hub without redirect |
| Mini-ML | `/ml` | the former root meaning is intentionally replaced by the Hub |
| JSON | `/json` | `/json.html` returns `308` to `/json` |
| Markdown | `/markdown` | `/markdown.html` returns `308` to `/markdown` |
| Memo | `/memo` | `/memo.html` returns `308` to `/memo` |
| Posts | `/posts` | `/posts.html` returns `308` to `/posts` |
| Resume | `/resume` | `/resume.html` returns `308` to `/resume` |
| GenUI | `/genui` | `/genui.html` returns `308` to `/genui` |
| Journey | `/journey` | `/genui-possibilities.html` returns `308` to `/journey` |

Query strings and fragments survive compatibility redirects. An alias never
creates a second demo snapshot or an extra usable Back stop.

### Target source shape

The exact filenames may move during implementation only when the same ownership
and boundary tests remain enforceable.

```text
examples/web/
  src/
    pages/
      _root.tsx
      _layout.tsx
      index.tsx
      index.html.tsx
      ml.tsx
      json.tsx
      markdown.tsx
      memo.tsx
      posts.tsx
      resume.tsx
      genui.tsx
      journey.tsx
      404.tsx
    shared/
      catalog/
      route-lifecycle/
        core/
        browser/
      shell/
    features/<feature>/
      route/
      browser/
      core/ or protocol/ where already present
    waku.server.tsx
    waku.client.tsx                 # only if the default client entry cannot host the provider
  server/
    vite/                           # retained while local adapters still use Vite
    waku/
      signaling-proxy.ts
  waku.config.ts
  wrangler.waku.jsonc
```

`src/pages/index.tsx` and `src/pages/index.html.tsx` reuse the same Hub module.
The catalog remains framework-independent data outside the React renderer.
The root layout supplies document structure, shared styles, lifecycle context,
and error/focus infrastructure; it does not add a persistent navigation system
rejected by #951.

### Dependency direction

1. A Waku page is an entry module. It may import its corresponding feature
   route surface and `shared`, but not feature browser internals directly.
2. A feature route surface may import its own `browser`, `core`, and `protocol`
   modules plus `shared`.
3. `shared` imports no feature module.
4. Feature `core` and `protocol` modules import no React, DOM, Vite, Node, AI
   provider, or Cloudflare capability.
5. Waku server modules may import `shared` and explicit feature `core` or
   `protocol` surfaces, never feature browser modules.
6. The five `@moonbit/*` imports occur only below a `'use client'` boundary.
7. `examples/web/scripts/check-boundaries.mjs` and its tests are extended to
   recognize Waku pages, feature route surfaces, Waku server modules, and
   client-only generated imports. They remain the executable ownership map.

## Decision: Capability Allocation (#954)

| Capability | Owner | Contract |
| --- | --- | --- |
| RSC, SSR, Hub, layouts, route metadata, 404 | Waku Worker | Official `waku/adapters/cloudflare` entry; Worker-compatible code only |
| Static application assets | Waku Worker static-assets binding | Publish Waku `dist/public`; do not copy MoonBit artifacts into `public` |
| Compatibility routes | Waku request/router layer | `/index.html` is a real page; seven other aliases return `308` for document and client navigation |
| Route-level server failures | Waku Worker | Correct non-success status; accessible production-safe fallback without stack or payload disclosure |
| Demo DOM, editors, file import, generated MoonBit modules | Client feature route surfaces | Loaded only below `'use client'`; each route owns its live resources |
| Posts data | Posts browser adapters | Preserve `canopy.posts.v1` and `canopy.post-events.v1` exactly |
| Same-document route snapshots | Shared route-lifecycle Module plus feature snapshot adapters | Memory only, one latest snapshot per canonical demo, opaque outside its feature |
| Signaling protocol, room state, WebSocket endpoint | Separate Signaling Worker and `SignalingRoom` Durable Object | Existing behavior and independent deployment remain unchanged |
| Same-origin signaling ingress | Waku Worker | Forward the original WebSocket upgrade request through the `SIGNALING` service binding; do not terminate or reinterpret the protocol in Waku |
| AST Grep | Local-development adapter | Production client performs no request and keeps the existing empty-match fallback |
| Resume chat | Local-development adapter | Production inspection remains usable and chat reports unavailable; no production provider secret or server function is added |
| GenUI live feasibility | Local-development adapter | Production retains recorded replay and excludes the local endpoint and development hook |
| Memo provider credential flow | Local client route only | Production renders an explicit unavailable/local-only state and does not expose the API-key form or provider call |

The Waku Worker gains no provider secret in this migration. Cloudflare-generated
binding types, not a handwritten `Env` interface, describe the `SIGNALING` service
binding.

## Decision: Route-Lifecycle Module (#955)

### Interface and seam

The shared Module owns lifecycle policy, not demo state. Its interface is kept
small:

- a pure reducer receives `State + Event` and returns `State + Decision`;
- an imperative React provider executes decisions against Waku navigation,
  browser history, focus, and mounted route adapters;
- snapshots are opaque, defensively owned values keyed by canonical demo ID;
- the snapshot registry is never exposed as a mutable collection.

The reducer decides when to save or forget a snapshot, dispose a mounted
surface, mount a destination from its latest snapshot, restore a focus token,
focus a new route heading, or announce a navigation error. It performs no DOM,
history, network, storage, clock, or controller operation.

Seven imperative demos use one real adapter seam. A mounted imperative session
provides only:

- `snapshot()` — returns the feature-owned, sanitized serializable snapshot;
- `restoreFocus(token)` — attempts a feature-owned stable focus target;
- `dispose()` — idempotently cancels and releases every live resource.

The shared host supplies the mount container and restored snapshot. It does not
mirror active editor internals into React state. Resume is already React-owned;
it uses the route snapshot provider directly instead of pretending to be an
imperative adapter.

Waku remains the sole router and history authority. The lifecycle Module must
integrate with the pinned Waku route lifecycle; it must not add a second URL
matcher, intercept modified clicks, or emulate Waku navigation. The foundation
slice must prove the available Waku route-event/unmount hooks before the shared
Module is finalized.

### Per-demo route contract

| Demo | Same-document snapshot | Never snapshot | Live resources disposed on exit | Pop focus target | Production error/availability |
| --- | --- | --- | --- | --- | --- |
| Mini-ML | source text | agent ID, handle, AST output, diagnostics cache | MoonBit handle, adapters, overlay, animation frame, AST timer/request | plaintext editor when its stable token exists | AST Grep returns no matches without requesting the local endpoint |
| JSON | source text | agent ID, handle, structure mode, collapsed-node set, edit-log cache, DOM selection | MoonBit handle, adapter, overlay, frames, global test hook/listeners | JSON editor or existing stable structural control | normal local browser behavior |
| Markdown | document text | handle, active mode/node, raw-dirty flag, DOM selection | MoonBit handle, BlockInput, preview adapter, frames/listeners | existing stable pane/control; heading fallback if the mode was rebuilt | normal local browser behavior |
| Memo | draft text, instruction, completed proposed edit | API key, request timestamp, pending request, provider response in flight | listeners and pending provider request | memo or instruction field represented by the token | explicit local-only/unavailable production page; no credential flow |
| Posts | unsubmitted draft, related mode, highlighted post ID | duplicate copies of posts/events | DOM listeners and scheduled focus work | draft or related timeline item | existing storage/status behavior; no new persisted schema |
| Resume | normalized loaded session, selected path/source, completed chat history | pending request, AbortController, DOM/file handles | React effects, frames, pending status/chat requests | stored listbox/source/control token | inspection works; chat reports unavailable |
| GenUI | JSX source, selected recorded case, committed revision, explorer filter/selection | generated handles, pending stream/provider task, development hook state | MoonBit/session handles, stream driver, frames/listeners | source editor or selected order control | recorded replay remains; live study endpoint/hook absent |
| Journey | defensive copy of reducer state | timers, DOM nodes | listeners and toast timer | selected response or route heading | normal deterministic browser behavior |

A full reload, tab close, or new tab clears these snapshots. Posts reloads its
existing two stores. `Forget` immediately removes Resume's snapshot. Browser
history is navigation history, not content undo: two history entries for one
demo restore the same latest route snapshot.

### History, focus, and errors

- A normal Waku navigation pushes one entry; Back/Forward never creates another.
- A new route scrolls to a valid fragment or otherwise to the top, then focuses
  a programmatically focusable `h1`.
- Back/Forward restores the history entry's scroll position and stable focus
  token with `preventScroll`; a missing token falls back to the route heading.
- Resume source fragments retain their existing replace-style behavior.
- Inline parse, type, validation, and provider statuses remain inside each demo
  and do not steal focus.
- A pre-commit RSC/navigation failure leaves the source route and snapshot
  visible, writes no history entry, announces an alert, and offers Retry plus an
  ordinary-link fallback.
- A post-commit render or mount failure keeps the destination URL and displays a
  route-local Retry/Back-to-demos error. Retry first disposes partial resources
  and then remounts from the retained snapshot.
- Unknown routes return an actual HTTP 404 with a static accessible page.

## Decision: Migration Sequence and Gates (#956)

The old Vite application remains runnable and tested through Stage 12. Each
feature keeps its old HTML URL until its canonical Waku route passes its gate.
A compatibility redirect is enabled only after its destination has parity.
The root is the special case: through Stage 6, the deployed/default Vite `/`
and `/index.html` continue to serve Mini-ML while only the pre-production Waku
runtime serves the Hub there. Do not switch the default command or production
hostname to the Waku root until `/ml` passes the Stage 7 Mini-ML gate.

### Stage 0 — Baseline and dual-run harness

- Land or otherwise make the #953 behavior inventory available to implementers.
- Pin the current Vite suites as the unchanged compatibility baseline.
- Add distinct `dev:vite`, `build:vite`, `dev:waku`, and `build:waku` commands;
  do not repurpose `dev` or `build` yet.
- Define one root MoonBit build/watch coordinator shared by both development
  modes; never start one watcher per virtual module.

**Gate:** the unchanged Vite build, boundary tests, and Playwright suite pass;
one generated-artifact build can serve both modes.

### Stage 1 — Waku foundation and generated artifacts

- Add the pinned Waku/Cloudflare dependencies and official Cloudflare adapter.
- Add `waku.config.ts`, Waku server entry, Worker static-assets output, and
  preview/production environments in an explicit `wrangler.waku.jsonc`. Keep
  the existing Vite deployment's default `wrangler.jsonc` unchanged until
  production cutover.
- Reuse the existing five public virtual IDs and output paths in Waku's Vite
  environments, including optimizer exclusions and full browser reload after a
  successful output write.
- Generate Cloudflare binding types and extend boundary classification before
  adding feature routes.
- Prove which pinned Waku lifecycle events support pre/post navigation, scroll,
  focus, error, and unmount integration. Record the result in tests rather than
  introducing a custom router.

**Gate:** Waku build and Waku-configured `wrangler deploy --dry-run` succeed
from prebuilt MoonBit artifacts; a client-only probe imports each of the five
virtual modules; server/RSC bundles contain none of them; Vite remains green.

### Stage 2 — Hub, lifecycle Module, and common states

- Move the accepted catalog out of the throwaway prototype into the shared pure
  catalog module and update all links to canonical routes.
- Add the root document, restrained shared shell, pre-production Waku `/`,
  nonredirecting `/index.html`, and `/404` pages. The parallel Vite runtime keeps
  serving Mini-ML at its root during this stage.
- Implement and deterministically test the route-lifecycle reducer, React
  provider, imperative host, focus manager, and route-level error states.
- Add placeholder client routes only where needed to exercise navigation; do
  not remove any old HTML entry.

**Gate:** SSR contains the full Hub catalog; `/` and `/index.html` have equivalent
content without redirect; 404 status is correct; reducer tests cover save,
dispose, forget, push, pop, focus fallback, and both failure phases; Hub browser
checks pass at desktop and mobile widths.

### Stage 3 — Journey

Migrate the pure reducer/DOM-shell demo first to prove route snapshot and focus
behavior without generated modules or server capabilities.

**Gate:** the existing Journey reducer and Playwright contracts pass at
`/journey`; route-away/return restores reducer state; reload resets it; disposal
leaves no toast timer/listener; the Vite URL still passes.

### Stage 4 — Posts

Migrate Posts to prove the persistence exception independently of route memory.

**Gate:** `/posts` preserves both existing storage keys and shapes, newest-first
order, Ask behavior, related-item focus, and unsubmitted same-document draft;
route reload preserves stored posts/events but clears only route-memory state;
old Vite tests remain green.

### Stage 5 — JSON representative imperative editor

Use the accepted #950 React/controller seam as the template. Refactor global DOM
and unload ownership into an idempotent mounted controller without changing
MoonBit or editor behavior.

**Gate:** the existing JSON suite passes at `/json`; text survives route
unmount/remount and clears on reload; structure/collapse internals rebuild;
focus request succeeds; repeated Strict Mode and navigation cycles leave one
handle/adapter/overlay and no stale hook or page error; Vite remains green.

### Stage 6 — Markdown

Apply the proven imperative host to Markdown while preserving its richer
within-demo selection and mode contract.

**Gate:** the existing Markdown suite passes at `/markdown`; route return restores
the document; within-demo mode changes still restore selection; disposal
releases both adapters and the handle; Vite remains green.

### Stage 7 — Mini-ML and Memo

Migrate Mini-ML first, then reuse its generated Lambda artifact loading for
Memo. Keep separate feature-owned snapshot schemas and commits.

**Gate:** `/ml` preserves presets, AST/format/diagnostic updates, and production
no-analysis behavior; `/memo` preserves local validation in development and
renders the explicit unavailable production state without an API-key control;
both routes dispose requests/handles and restore only allowed snapshots; Vite
remains green.

### Stage 8 — Resume

Keep the native React state machine and protocol/core seams. Add route snapshot
ownership without converting Resume to the imperative adapter.

**Gate:** the existing Resume suite passes at `/resume`; import, Forget,
synchronized timeline/conversation/evidence, listbox focus, request preview,
stop/continue, and zero browser persistence remain intact; route return restores
completed state; pending work cancels; production chat visibly reports
unavailable; Vite remains green.

### Stage 9 — GenUI

Migrate GenUI after the imperative and native React patterns are proven. Keep
recorded replay and live-study paths separate.

**Gate:** the existing deterministic, browser, and preview suites pass at
`/genui`; stream/session cleanup survives repeated route cycles; invalid and
stale candidates do not corrupt committed state; production contains recorded
replay but no live endpoint or development hook; Vite remains green.

### Stage 10 — Cloudflare staging and signaling seam

- Add the `SIGNALING` service binding to the Waku Worker environments.
- Forward the original same-origin WebSocket upgrade request to the separately
  deployed Signaling Worker without importing its Durable Object class.
- Deploy a non-production Waku Worker version and run real workerd/Cloudflare
  route, static asset, RSC, 404, error, and WebSocket handshake checks.
- Enable structured logs/traces without demo content, imported sessions,
  request payloads, API keys, or chat text.

**Gate:** every canonical route passes direct-load and client-navigation smoke;
the seven aliases preserve query/fragment and return `308`; `/index.html` does
not redirect; the signaling handshake succeeds through the service binding;
Worker startup and binding type checks pass; no provider secret is configured.

### Stage 11 — Production cutover

**Resolution (2026-07-28):** Cutover used native Cloudflare Workers Builds from
`main` and moved the resulting Worker version directly to 100% traffic. The
repository did not add a GitHub deployment controller, protected environment,
or gradual traffic split.

- Require the repository-owned `All Checks Passed` aggregate before merging the
  production candidate.
- Let the external Cloudflare configuration build and deploy the merged `main`
  commit.
- Verify canonical routes, aliases, 404, availability states, static assets,
  RSC navigation, state/focus restoration, and signaling on the production
  hostname.
- Retain the previous stable Worker version for immediate rollback. The Pages
  deployment remains available only through the acceptance window and is
  retired in Stage 12.

**Gate:** all production smoke checks pass and the observation window contains
no release-attributable uncaught Worker error, canonical-route 5xx, asset/RSC
mismatch, or failed signaling handshake.

### Stage 12 — Vite retirement

**Status (2026-07-28):** Complete. Waku is the default dev/build/preview path;
legacy Vite HTML inputs, `src/entries/`, and dual-build scripts are removed.
`wrangler.jsonc` owns the Worker configuration; `wrangler.waku.jsonc` and
`build:deploy:waku` remain as compatibility aliases for Cloudflare Workers
Builds external settings. Final repository CI passed and post-merge production
verification on Cloudflare succeeded (see Completion Evidence above). No
remaining gate.

- Make Waku the default development/build path.
- Remove old HTML inputs, Vite multi-page configuration, throwaway Hub files,
  and local adapter wiring only after equivalent Waku development adapters or
  explicit fallbacks are proven.
- Preserve deterministic feature core/protocol tests and update module/deploy
  documentation.

**Gate:** a clean checkout passes the final CI matrix using Waku, no active test
or documentation link depends on an old HTML file except compatibility tests,
and rollback instructions identify the previous stable Waku Worker version.

## Decision: CI, Deployment, and Rollback (#957)

### Required CI during migration

1. `build-js` remains the only producer of generated MoonBit JavaScript. Waku
   build and browser jobs download and fail-closed verify that artifact.
2. Keep separate Vite build/E2E and Waku build/E2E jobs until Stage 12. Do not
   hide one behind a script that silently selects a runtime.
3. Waku build runs TypeScript typecheck, boundary check/tests, lifecycle/core
   unit tests, production build, generated binding check, deploy dry run, and
   client/server bundle-boundary assertions.
4. Waku browser jobs run the existing per-demo suites against canonical routes
   plus dedicated route-contract tests for aliases, history, state, focus,
   disposal, errors, 404, and production availability.
5. A workerd job exercises the built Worker locally. Production acceptance
   exercises the real service binding and WebSocket handshake after the native
   Cloudflare deployment.
6. Add all required Waku jobs to `All Checks Passed`; path-filtered skips are
   accepted only through the existing aggregate policy.

### Deployment contract

**Stage 12 resolution (2026-07-28):** Production deployment remains native to
Cloudflare Workers Builds. This supersedes the earlier proposal for a GitHub
Actions deployment controller, protected-environment approval, and staged
traffic split.

- The `web` row is removed from the push-triggered Pages matrix; other examples
  retain their existing deployment types.
- A successful push to `main` triggers the external Cloudflare Workers Build
  configuration. It runs `npm run build:deploy:waku`, then deploys
  `wrangler.waku.jsonc` to 100% traffic. The config path is a compatibility
  symlink to the canonical `wrangler.jsonc`.
- Production no longer uses `wrangler pages deploy` for `examples/web`; it uses
  the Waku Worker `wrangler deploy` workflow and `dist/public` assets.
- GitHub Actions validates Waku build, browser, bundle-boundary, startup, and
  workerd behavior but does not own production deployment.
- Preview and production use distinct Worker names/environments and service
  bindings. The target Signaling Worker must already exist in the same account.
- `wrangler types --check` guards binding drift. `wrangler deploy --dry-run`
  guards bundling/configuration. `wrangler check startup` analyzes the emitted
  multipart Worker bundle but is not the sole release gate.
- Worker observability is enabled. Structured records include deployment
  version, route class, capability, status, and error category; they exclude
  user-authored content and secrets.

### Rollback contract

- Record the new and previous stable Waku Worker version IDs in deployment
  output before traffic moves.
- Roll back immediately on any deterministic production smoke failure. During
  the acceptance window, roll back on a verified release-attributable uncaught
  Worker exception, canonical-route 5xx, asset/RSC version mismatch, or failed
  signaling proxy handshake.
- Waku rollback uses the previous Worker version and its versioned assets.
  Stage 12 removes the legacy Pages deployment, so it is no longer a fallback.
- Never roll back the Signaling Worker automatically with the Waku Worker. Its
  version and Durable Object state are independent; change it only through its
  own tested deployment procedure.
- Rollback does not rewrite or clear Posts storage and introduces no server-side
  data migration to reverse.

## Implementation Work Packages

The migration is split into ten child implementation issues. Their bodies
contain scope, dependencies, exit criteria, and validation links; they do not
copy the whole plan.

1. **[#970 — Establish the dual Vite/Waku foundation and MoonBit artifact contract](https://github.com/dowdiness/canopy/issues/970)**
   - Scope: Stage 0–1 configuration, scripts, boundary rules, generated binding
     types, lifecycle-hook probe, and parallel CI skeleton.
   - Exit: Stage 1 gate; no feature behavior migration.

2. **[#971 — Build the Waku Hub, route-lifecycle Module, and common route states](https://github.com/dowdiness/canopy/issues/971)**
   - Depends on 1. Scope: Stage 2, route table, catalog, shell, reducer/provider,
     imperative host, 404, focus/error contract tests.
   - Exit: Stage 2 gate; no old HTML removal.

3. **[#972 — Migrate Journey to `/journey`](https://github.com/dowdiness/canopy/issues/972)**
   - Depends on 2. Scope and exit: Stage 3.

4. **[#973 — Migrate Posts to `/posts` without storage drift](https://github.com/dowdiness/canopy/issues/973)**
   - Depends on 2. Scope and exit: Stage 4.

5. **[#974 — Migrate JSON to `/json` as the imperative lifecycle reference](https://github.com/dowdiness/canopy/issues/974)**
   - Depends on 2. Scope and exit: Stage 5.

6. **[#975 — Migrate Markdown to `/markdown`](https://github.com/dowdiness/canopy/issues/975)**
   - Depends on 5. Scope and exit: Stage 6.

7. **[#976 — Migrate Mini-ML and Memo with their production capability split](https://github.com/dowdiness/canopy/issues/976)**
   - Depends on 5. Use separate commits for Mini-ML and Memo. Scope and exit:
     Stage 7.

8. **[#977 — Migrate Resume to `/resume` with native React snapshot ownership](https://github.com/dowdiness/canopy/issues/977)**
   - Depends on 2. Scope and exit: Stage 8.

9. **[#978 — Migrate GenUI to `/genui` and preserve recorded production replay](https://github.com/dowdiness/canopy/issues/978)**
   - Depends on 5. Scope and exit: Stage 9.

10. **[#979 — Deploy the Waku Worker, verify signaling, cut over, and retire Vite](https://github.com/dowdiness/canopy/issues/979)**
    - Depends on 3–9. Scope: Stage 10–12, all seven redirects, production
      acceptance, observability, native Cloudflare deployment, rollback, and
      final cleanup.
    - Exit: Stage 12 gate.

## Acceptance Criteria

- [x] `/` and `/index.html` server-render equivalent data-driven Hub content and
      `/index.html` does not redirect.
- [x] All eight canonical demo routes pass their inherited behavior contract.
- [x] All seven active legacy HTML URLs return `308`, preserve query/fragment,
      and lead to the correct canonical route without an extra usable Back stop.
- [x] Waku owns navigation; modified clicks and new-tab behavior remain native.
- [x] Same-document snapshots restore exactly the allowed per-demo fields and
      clear on reload/new tab, except Posts' two unchanged stores.
- [x] Every route exit disposes its live resources idempotently; repeated
      Strict Mode/navigation cycles leak no handle, adapter, overlay, request,
      timer, listener, React root, or development hook.
- [x] Push, pop, fragment, fallback, and route-error focus behavior matches #952.
- [x] Unknown routes return HTTP 404; pre-commit and post-commit failures retain
      the correct URL/state and provide accessible recovery.
- [x] Production exposes no Memo credential flow, AST Grep request, Resume
      provider call, GenUI live endpoint, provider secret, stack, or user content
      in errors/logs.
- [x] The five virtual IDs and artifact paths remain unchanged, are absent from
      server/RSC bundles, and trigger output-driven full reload in development.
- [x] The separate Signaling Worker remains independently deployable and a real
      same-origin handshake passes through the service binding.
- [x] Vite remains green until cutover; the final Waku CI jobs join
      `All Checks Passed` before Vite is retired.
- [x] Production deployment records version IDs, passes production smoke gates,
      and has a verified previous-Worker-version rollback procedure.

## Validation

Run the commands relevant to each slice; do not claim a gate from a narrower
command.

### Repository root

```bash
./scripts/build-js.sh
moon check
moon test
git diff -- '*.mbti'
```

`*.mbti` output must not change because this plan does not authorize MoonBit
source changes. If a later implementation unexpectedly changes MoonBit source,
run `moon fmt && moon info` before inspecting the interface diff.

### `examples/web`

```bash
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

### Waku Worker from `examples/web`

```bash
npx wrangler types --config wrangler.waku.jsonc --check
npx wrangler deploy --config wrangler.waku.jsonc --dry-run --env preview \
  --outfile "${TMPDIR:-/tmp}/canopy-waku-preview.bundle"
npx wrangler check startup \
  --worker "${TMPDIR:-/tmp}/canopy-waku-preview.bundle"
npx wrangler deploy --config wrangler.waku.jsonc --dry-run --env production \
  --outfile "${TMPDIR:-/tmp}/canopy-waku-production.bundle"
npx wrangler check startup \
  --worker "${TMPDIR:-/tmp}/canopy-waku-production.bundle"
```

The workerd/staging harness added by Work Package 1 supplies the exact automated
smoke command; it must cover canonical routes, compatibility routes, RSC client
navigation, 404, both error phases, state/focus restoration, production
availability, assets, and the service-bound WebSocket handshake.

### Final repository gate

```bash
moon check
moon test
```

Then require the raw repository-owned `All Checks Passed` status before any
production deployment or merge.

## Existing API and Reuse Check

### Reuse

- `moonbitPlugin` in `examples/web/vite-plugin-moonbit.ts`, its five module
  records and optimizer exclusions in `examples/web/vite.config.ts`, and the
  output checks in `scripts/build-js.sh` are the source-verified artifact
  contract. Adapt their composition to Waku; do not duplicate IDs or paths.
- `examples/web/scripts/check-boundaries.mjs` and
  `check-boundaries.test.mjs` are the source-verified ownership checker and test
  seam. Extend rather than replace them.
- The accepted catalog types/data on `prototype/waku-demo-hub` are the source
  for the production pure catalog; do not preserve prototype delivery code.
- `transitionJourney`, Posts core/store adapters, Resume reducer/core/protocol,
  GenUI deterministic core/recorded candidates, and Memo edit-action core remain
  feature-owned and are reused through current interfaces.
- Waku `Link`, filesystem routing, 404 support, and official Cloudflare adapter
  remain the navigation/server interfaces; do not add another router.
- Cloudflare service bindings, generated Wrangler types, Worker versions, static
  assets, observability, and rollback remain platform interfaces; do not call
  the Cloudflare REST API from the Worker.

### Check before adding definitions

- Inspect `adapters/editor-adapter/types.ts`, HTML adapter, BlockInput, and
  MarkdownPreview disposal/ownership interfaces before naming any new generic
  disposable type.
- Inspect the pinned Waku router/client lifecycle and error interfaces before
  naming provider hooks or depending on unstable events.
- Confirm `@moonbit/crdt-jsx` declaration loading in the Waku client environment;
  the current GenUI caller is JavaScript, so the absence of a TypeScript `paths`
  entry alone is not evidence of a defect.
- No new MoonBit helper, type, loop, or data transformation is planned. If that
  changes, perform the repository's Existing API First checks against project
  APIs and concrete MoonBit core candidates (`Map`, `Set`, `String`/views,
  `Option`/`Result`, `Array`, and `Iter`) before implementation.

## Risks

- **Waku lifecycle API drift:** route events used by the lifecycle provider may
  be unstable. Pin versions and prove the seam in Work Package 1; do not hide a
  second router behind a compatibility wrapper.
- **Global DOM ownership:** current demos query `document` and some clean up only
  on `beforeunload`. Container scoping and idempotent disposal must land one
  feature at a time, with JSON as the reference.
- **State over-retention:** feature snapshot adapters can accidentally retain
  API keys, imported content after Forget, pending requests, or mutable internal
  collections. Keep schemas feature-owned, explicit, defensive, and tested.
- **Client/server leakage:** generated MoonBit modules or browser adapters in an
  RSC import graph would break the Worker or enlarge its server bundle. Make
  this a boundary and bundle assertion, not a convention only.
- **Development capability drift:** Waku's Vite integration may not run the
  current `configureServer` adapters unchanged. Preserve Vite until each local
  replacement and production fallback has explicit tests.
- **Static asset/version skew:** the native 100% Worker deployment must keep
  code, RSC payloads, and hashed assets in one complete build. Verify the
  deployed version and retain immediate rollback.
- **Signaling coupling:** the Waku proxy must forward the original upgrade and
  must not become a second signaling implementation. Validate with a real
  service-bound handshake.
- **Deployment race:** native Cloudflare deployment starts from a merged `main`
  push independently of repository CI. Require the repository aggregate before
  merge, verify the deployed commit/version afterward, and roll back on failed
  production acceptance.

## Documentation Updates During Execution

- Update `examples/web/MODULE_MAP.md` after each ownership or route stage.
- Update `examples/web/CLOUDFLARE_DEPLOYMENT.md` and
  `QUICKSTART_CLOUDFLARE.md` when the Worker/service-binding workflow is real.
- Add one brief `docs/TODO.md` entry linking this plan while implementation is
  active; do not copy execution detail there.
- Archive this plan only after Stage 12 is complete and validated.

## Post-Cutover Follow-Up: React Ownership Assessment (Non-Gating)

This section is not a migration stage, not a Stage 12 exit criterion, and does
not authorize any rewrite of the current Journey, JSON, Markdown, Mini-ML, Memo,
Posts, Resume, or GenUI implementations. It records the agreed approach for
future per-demo React ownership evaluation after the Waku cutover is complete
and Vite is retired. Reactification must not block or delay Waku cutover or
Vite retirement.

### Principles

- React ownership is assessed per demo, never mandated wholesale across all
  demos in one effort.
- Each candidate is tracked in a separate issue and delivered in a separate PR
  after cutover.
- Journey is the first candidate: it already has a pure reducer and
  presentation-only DOM, and proved the imperative lifecycle seam in Stage 3.
- For each candidate, use React as a thin imperative shell around the existing
  functional core. The reducer remains the domain source of truth; React renders
  its returned state and dispatches events into it.
- Do not mirror into React state: editor or runtime handles, generated MoonBit
  state, DOM selection, IME composition state, in-flight requests or streams,
  provider sessions, or any other live imperative resource. These remain behind
  the imperative adapter.
- JSON, Markdown, Mini-ML, and GenUI editor/runtime internals remain behind
  imperative adapters unless separate evidence in a follow-up issue justifies a
  different ownership seam for a specific demo. Memo and Posts are assessed
  only where their browser DOM is presentation-only and React would not
  duplicate provider or persistence ownership. Resume remains React-owned
  through its existing native route snapshot seam.

### Preservation Requirements

Every React ownership change must preserve:

- Existing reducer semantics and determinism.
- The verified demo workflow and visual design.
- Focus, selection, and node identity contracts.
- Legacy behavior contracts that remain relevant for the demo.
- Idempotent lifecycle cleanup on unmount, navigation, and route exit.

### Candidate Entry Criteria

A demo is eligible for React ownership assessment only when all of the
following hold:

- The demo already exposes a pure deterministic transition (`State + Event →
  State`, optionally with returned decisions) or can be factored into one
  without changing verified behavior.
- Route state is serializable and already captured by the route-lifecycle
  snapshot.
- The DOM surface is presentation-only — it renders reducer output and
  dispatches user events, without owning live editor, runtime, or provider
  handles in React state.

### Candidate Validation and Exit Criteria

Each React ownership PR must demonstrate:

- All existing behavior contracts (Playwright suites, reducer unit tests,
  boundary checks) still pass unchanged.
- Route snapshot save and restore works through the new React shell.
- Full page reload clears all transient state as before; no React-managed
  cache survives reload.
- Focus restoration (route heading and per-demo stable token) works after
  navigation to and from the route.
- Unmount, Strict Mode double-mount, and repeated navigation cycles dispose
  all live resources: no leaked handle, adapter, overlay, request, timer,
  listener, or React root.
- There is exactly one render implementation — React does not duplicate the
  imperative adapter's rendering logic. If the imperative adapter is still
  needed for a portion of the DOM, React delegates to it rather than
  re-rendering it.

### Scope Boundaries

This follow-up does not:

- Change any Stage 3 exit criterion or the Journey implementation in this plan.
- Add gating requirements to any stage in the migration sequence.
- Authorize changes to the five public virtual import IDs, generated MoonBit
  JavaScript, or the route-lifecycle Module interface.
- Redesign the signaling, storage, or provider capability contracts.
