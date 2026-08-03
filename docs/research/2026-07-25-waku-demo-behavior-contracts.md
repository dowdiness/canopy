# Waku demo behavior contracts

**Date:** 2026-07-25

**Issue:** [#953 — Inventory behavioral acceptance contracts for all eight demos](https://github.com/dowdiness/canopy/issues/953)

This document records the behavior preserved by the `apps/web` Waku
migration. It is an inventory of the current checkout, not a route design or an
implementation plan. Canonical URLs, route-memory behavior, and error recovery
are implemented by the Waku route and lifecycle surfaces linked below.

## Scope

The inventory covers the eight demos listed in the current
[module map](../../apps/web/MODULE_MAP.md). It records visible
workflows, runtime dependencies, state lifetime, accessibility behavior,
existing verification, development-only capabilities, migration gates, and
verified gaps. It does not cover the inactive `spike-block-input.html` surface
or historical files under `docs/archive`.

## Summary

| Demo | Canonical route and page | Primary job | Runtime boundary | Persistence | Development/production split | Principal test |
| --- | --- | --- | --- | --- | --- | --- |
| Lambda | `/ml` ([page](../../apps/web/src/pages/ml.tsx), [map](../../apps/web/MODULE_MAP.md)) | Edit Mini-ML and inspect AST, formatted structure, and diagnostics | Generated Lambda and Graphviz JavaScript virtual modules; local AST Grep adapter | Page memory | AST Grep returns no matches outside development; visible collaboration controls are not bound by the current route surface | [Lambda Playwright](../../apps/web/tests/lambda-editor.spec.ts#L1-L163) |
| JSON | `/json` ([page](../../apps/web/src/pages/json.tsx), [map](../../apps/web/MODULE_MAP.md)) | Edit JSON as text or a structural tree and inspect edits | Generated JSON JavaScript virtual module and editor adapter | Page memory | No custom server adapter | [JSON Playwright](../../apps/web/tests/json-editor.spec.ts#L1-L291) |
| Markdown | `/markdown` ([page](../../apps/web/src/pages/markdown.tsx), [map](../../apps/web/MODULE_MAP.md)) | Edit one Markdown document in block, raw, and preview modes | Generated Markdown JavaScript virtual module and editor adapter | Page memory | No custom server adapter | [Markdown Playwright](../../apps/web/tests/markdown-editor.spec.ts#L1-L375) |
| Memo | `/memo` ([page](../../apps/web/src/pages/memo.tsx), [map](../../apps/web/MODULE_MAP.md)) | Preview and accept or reject typo corrections and structured edits | Generated Lambda JavaScript virtual module; browser-to-Google credential flow | Page memory | Explicitly local-only; production renders unavailable state | [Memo Playwright](../../apps/web/tests/memo-editor.spec.ts#L1-L26) |
| Posts | `/posts` ([page](../../apps/web/src/pages/posts.tsx), [map](../../apps/web/MODULE_MAP.md)) | Save local posts and retrieve related earlier posts | Browser persistence shell around deterministic TypeScript core | `localStorage` | Same browser implementation in both modes | [Posts Playwright](../../apps/web/tests/post-app.spec.ts#L1-L243) |
| Resume/PKE | `/resume` ([page](../../apps/web/src/pages/resume.tsx), [map](../../apps/web/MODULE_MAP.md)) | Inspect a session through synchronized timeline, conversation, and evidence; optionally chat with attached context | React 19 browser app and local dev chat relay | Page memory; imported file is not stored | DeepSeek/fake relay is local; production reports unavailable | [Resume Playwright](../../apps/web/tests/pi-resume.spec.ts#L1-L1159) |
| GenUI | `/genui` ([page](../../apps/web/src/pages/genui.tsx), [map](../../apps/web/MODULE_MAP.md)) | Stream JSX, inspect projection/diagnostics, and replay bounded feasibility candidates | Generated JSX JavaScript virtual module; optional local study relay | Page memory | Preview keeps recorded replay and excludes the development test hook and local study endpoint | [GenUI Playwright](../../apps/web/tests/genui.spec.ts#L1-L1403) |
| Journey | `/journey` ([page](../../apps/web/src/pages/journey.tsx), [map](../../apps/web/MODULE_MAP.md)) | Compare journey responses, preview a change, apply it, and undo it | Deterministic JavaScript reducer with a DOM shell | Page memory | No custom server adapter | [Journey Playwright](../../apps/web/tests/genui-possibilities.spec.ts#L1-L442) |

## Lambda calculus editor

### User-visible contract

The page offers five source presets, a plaintext contenteditable editor, an AST
visualization, formatted structure, and diagnostics
([route](../../apps/web/src/pages/ml.tsx)). Typing or selecting a preset
updates the generated model and all three outputs
([editor](../../apps/web/src/features/lambda/browser/editor.ts#L34-L81),
[tests](../../apps/web/tests/lambda-editor.spec.ts#L48-L163)).

### Runtime and browser dependencies

The browser imports `@moonbit/crdt-lambda`, `@moonbit/graphviz`, the HTML editor
adapter, and the shared decoration overlay
([editor](../../apps/web/src/features/lambda/browser/editor.ts#L3-L8)). AST
Grep analysis crosses the `/api/ast-grep` boundary through a cancellable browser
request ([runner](../../apps/web/src/features/lambda/browser/ast-grep-runner.ts#L1-L37)).

### State and lifetime

Each mount creates a fresh agent ID and editor handle. The returned imperative
session snapshots source text, restores editor focus, and releases listeners,
frames, requests, adapters, overlays, and the MoonBit handle on disposal; it
creates no browser storage path
([editor](../../apps/web/src/features/lambda/browser/editor.ts#L13-L73),
[session return](../../apps/web/src/features/lambda/browser/editor.ts#L216-L229)).

### Accessibility and focus

Presets are native buttons and the editor is a focusable plaintext contenteditable
([route](../../apps/web/src/pages/ml.tsx)). Existing browser tests verify
that the editor is visible and focusable, but do not assert screen-reader
semantics ([tests](../../apps/web/tests/lambda-editor.spec.ts#L44-L52)).

### Existing verification

The Playwright suite covers page errors, presets, AST rendering, formatted
output, clean and failing type checks, parse-error suppression, the AST Grep
HTTP method/empty-input contract, and current/stale structural-match list and
jump behavior
([tests](../../apps/web/tests/lambda-editor.spec.ts),
[route tests](../../apps/web/waku-tests/lambda-route.spec.ts)).

### Development/production split

The server adapter is `apply: 'serve'`
([adapter](../../apps/web/server/vite/ast-grep.ts#L13-L20)), and the browser
runner returns an empty match list when `import.meta.env.DEV` is false
([runner](../../apps/web/src/features/lambda/browser/ast-grep-runner.ts#L16-L21)).
The collaboration panel exists in the route-owned shell. The current Lambda
mount binds the editor, preset buttons, and structural-match result list.
Signaling files remain separate integration shells outside the browser graph
([route](../../apps/web/src/pages/ml.tsx),
[client mount](../../apps/web/src/features/lambda/route/lambda-client.tsx#L20-L53),
[map](../../apps/web/MODULE_MAP.md)).

### Migration acceptance gates

Preserve source editing, AST/format/diagnostic updates, preset behavior, and the
AST Grep development contract. Production must retain the current no-analysis
fallback rather than attempting the local endpoint
([runner](../../apps/web/src/features/lambda/browser/ast-grep-runner.ts#L16-L21),
[tests](../../apps/web/tests/lambda-editor.spec.ts#L29-L43)).

### Known gaps

The visible Network Collaboration controls have no event binding in the current
Lambda route surface, and the Lambda feature suite does not exercise the shared
signaling handshake
([editor bindings](../../apps/web/src/features/lambda/browser/editor.ts#L188-L204),
[Lambda suite](../../apps/web/tests/lambda-editor.spec.ts#L1-L163)).

## JSON editor

### User-visible contract

The page provides presets, raw text editing, formatting, a structured tree,
structural actions, and an edit log
([route](../../apps/web/src/pages/json.tsx),
[editor](../../apps/web/src/features/json/browser/editor.ts#L196-L451)).

### Runtime and browser dependencies

The browser imports `@moonbit/crdt-json`, the HTML adapter, adapter view types,
and the shared decoration overlay
([editor](../../apps/web/src/features/json/browser/editor.ts#L1-L4)). No
server adapter belongs to this surface ([map](../../apps/web/MODULE_MAP.md)).

### State and lifetime

A per-load agent ID creates the JSON handle. Structured collapse state remains
in a `Set` during the mounted session, and `beforeunload` destroys the adapter
and handle ([editor](../../apps/web/src/features/json/browser/editor.ts#L17-L38),
[cleanup](../../apps/web/src/features/json/browser/editor.ts#L525-L546)).

### Accessibility and focus

Container toggles expose `role="button"` and `tabindex="0"` and respond to Enter
or Space. The edit-log disclosure uses the same keyboard contract
([tree](../../apps/web/src/features/json/browser/editor.ts#L196-L220),
[log](../../apps/web/src/features/json/browser/editor.ts#L506-L524)).

### Existing verification

Playwright covers raw parse errors, text-to-structure updates, add/delete/type
operations, collapse persistence, semantic role spans, decorations, and format
behavior ([tests](../../apps/web/tests/json-editor.spec.ts#L29-L291)).

### Development/production split

The current surface has no custom server adapter; its generated JavaScript
module and browser code are shared by development and production builds
([map](../../apps/web/MODULE_MAP.md)).

### Migration acceptance gates

Preserve lossless switching between raw and structured views, structural edit
operations, collapse state while mounted, role-span decorations, formatting,
and cleanup. Tests may keep `window.getJsonRoleSpans` or receive an equivalent
observable seam ([editor](../../apps/web/src/features/json/browser/editor.ts#L55-L61),
[tests](../../apps/web/tests/json-editor.spec.ts#L137-L269)).

### Known gaps

The current Playwright suite does not assert rendered edit-log entries or
`beforeunload` cleanup ([tests](../../apps/web/tests/json-editor.spec.ts#L1-L291)).

## Markdown editor

### User-visible contract

One document can be edited in Block or Raw mode and read in Preview mode. The
block toolbar changes headings, toggles list items, and deletes blocks
([route](../../apps/web/src/pages/markdown.tsx),
[app](../../apps/web/src/features/markdown/browser/app.ts#L180-L279)).

### Runtime and browser dependencies

The browser imports `@moonbit/crdt-markdown`, `BlockInput`, `MarkdownPreview`,
and adapter protocol types
([app](../../apps/web/src/features/markdown/browser/app.ts#L1-L9)). There is
no custom server adapter for this surface
([map](../../apps/web/MODULE_MAP.md)).

### State and lifetime

The mounted shell owns the Markdown handle, current mode, active node, raw-mode
dirty flag, and saved `BlockSelection`. Switching modes stores and restores the
BlockInput selection; `beforeunload` destroys both adapters and the handle
([state](../../apps/web/src/features/markdown/browser/app.ts#L22-L35),
[modes](../../apps/web/src/features/markdown/browser/app.ts#L182-L231),
[cleanup](../../apps/web/src/features/markdown/browser/app.ts#L327-L335)).

### Accessibility and focus

Mode controls and toolbar actions are native buttons. Block mode supports
Ctrl+1–6, Ctrl+0, and Ctrl+Shift+L; switching to Raw focuses the textarea, and
returning to Block attempts to restore the saved selection
([modes](../../apps/web/src/features/markdown/browser/app.ts#L182-L231),
[shortcuts](../../apps/web/src/features/markdown/browser/app.ts#L281-L310)).

### Existing verification

Playwright covers lossless mode changes, selection restoration, block identity,
list markers, insertion/deletion/navigation, code-block whitespace, and semantic
preview output ([tests](../../apps/web/tests/markdown-editor.spec.ts#L29-L375)).

### Development/production split

The current surface has no custom server capability; the same browser modules
run in both builds ([map](../../apps/web/MODULE_MAP.md)).

### Migration acceptance gates

Within a mounted editor, preserve text, block identity, active selection/focus,
raw dirty-state semantics, and preview meaning across mode changes. Cross-route
retention remains a separate #952 decision
([modes](../../apps/web/src/features/markdown/browser/app.ts#L182-L231),
[tests](../../apps/web/tests/markdown-editor.spec.ts#L45-L137)).

### Known gaps

The current Playwright suite does not exercise the documented Ctrl-based block
shortcuts or `beforeunload` cleanup
([tests](../../apps/web/tests/markdown-editor.spec.ts#L1-L375)).

## Memo editor

### User-visible contract

The page accepts text, a Gemini API key, and an edit instruction. It can request
typo correction or structured edits, then show original/corrected panes with
Accept and Reject actions ([route](../../apps/web/src/pages/memo.tsx)).

### Runtime and browser dependencies

The browser imports the generated Lambda module and calls its
`canopy_llm_fix_typos` and `canopy_llm_edit` functions
([app](../../apps/web/src/features/memo/browser/app.ts#L1-L8)). The HTML
states that the key is sent directly from the browser to Google
([route](../../apps/web/src/pages/memo.tsx)).

### State and lifetime

The key, pending corrected text, request timestamp, input, and instruction stay
in page memory. The app enforces a 5-second request interval and a 5,000-character
input limit ([app](../../apps/web/src/features/memo/browser/app.ts#L10-L48)).

### Accessibility and focus

Inputs, textarea, and actions are native controls. Missing key/text/instruction
validation reports status, and a missing instruction returns focus to that input
([app](../../apps/web/src/features/memo/browser/app.ts#L16-L39),
[edit path](../../apps/web/src/features/memo/browser/app.ts#L96-L108)).

### Existing verification

The browser suite verifies page startup and local validation for missing key,
text, and instruction ([tests](../../apps/web/tests/memo-editor.spec.ts#L1-L26)).

### Development/production split

The page explicitly identifies itself as local-only, warns against public
deployment, and requires a server-side proxy for production use
([route](../../apps/web/src/pages/memo.tsx)).

### Migration acceptance gates

Keep the local-only warning and browser validation. Do not expose the current
credential flow from a production route unless a separately approved server
boundary replaces it ([route](../../apps/web/src/pages/memo.tsx),
[tests](../../apps/web/tests/memo-editor.spec.ts#L8-L26)).

### Known gaps

The current browser suite does not call the provider or cover rate limiting,
length limiting, diff rendering, Accept, or Reject
([tests](../../apps/web/tests/memo-editor.spec.ts#L1-L26)).

## Posts

### User-visible contract

A person can write and post local text, use Ctrl/Cmd+Enter to submit, use Ask
without posting, inspect related earlier posts, and fall back to a newest-first
timeline ([route](../../apps/web/src/pages/posts.tsx),
[tests](../../apps/web/tests/post-app.spec.ts#L12-L243)).

### Runtime and browser dependencies

The browser shell composes deterministic post/event/retrieval core modules with
DOM and `localStorage` adapters. It has no generated MoonBit or custom server
dependency ([mount](../../apps/web/src/features/posts/browser/mount.ts#L1-L13),
[map](../../apps/web/MODULE_MAP.md)).

### State and lifetime

Posts persist as JSON under `canopy.posts.v1`; creation and related-open events
persist under `canopy.post-events.v1`. Both stores validate parsed entries and
return newest-first data
([post store](../../apps/web/src/features/posts/browser/post-store.ts#L1-L42),
[event store](../../apps/web/src/features/posts/browser/post-events.ts#L1-L71)).

### Accessibility and focus

The status row is polite live text, the related panel and timeline use labelled
sections/lists, and keyboard submit is documented with `kbd` labels
([route](../../apps/web/src/pages/posts.tsx)). The implementation moves focus
to the matching timeline item when a related post opens
([view](../../apps/web/src/features/posts/browser/view.ts#L110-L151)).

### Existing verification

Playwright covers reload persistence, keyboard submission, order, related-post
retrieval, Ask isolation, engagement reranking, highlighting, and persisted
event shape ([tests](../../apps/web/tests/post-app.spec.ts#L12-L243)).

### Development/production split

The feature is browser-only in both modes
([map](../../apps/web/MODULE_MAP.md)).

### Migration acceptance gates

Preserve both storage keys and their validated JSON shapes, newest-first order,
keyboard submission, Ask-without-posting behavior, retrieval results, and
related-open focus. Migration must not clear existing local data
([stores](../../apps/web/src/features/posts/browser/post-store.ts#L5-L42),
[events](../../apps/web/src/features/posts/browser/post-events.ts#L13-L71),
[tests](../../apps/web/tests/post-app.spec.ts#L12-L243)).

### Known gaps

No additional source-backed gap is recorded.

## Resume/PKE

### User-visible contract

The React workbench loads an example session or an imported JSONL file, selects
a path, synchronizes Timeline, Conversation, and Evidence, and offers an
independent chat whose history/source context is attached explicitly
([tests](../../apps/web/tests/pi-resume.spec.ts#L19-L190),
[app](../../apps/web/src/features/resume/browser/app.tsx#L1500-L1645)).

### Runtime and browser dependencies

The app uses React 19, `@ai-sdk/react`, and the AI SDK
([package](../../apps/web/package.json#L15-L25),
[imports](../../apps/web/src/features/resume/browser/app.tsx#L1-L17)). Chat
uses the `/api/pi-resume-chat` transport supplied by a local Vite adapter
([app](../../apps/web/src/features/resume/browser/app.tsx#L602-L612),
[adapter](../../apps/web/server/vite/resume-chat.ts#L48-L62)).

### State and lifetime

Imported session, path selection, and chat state live in React state for the
current tab. Tests verify no local storage, session storage, or IndexedDB is
created by the workflow ([state](../../apps/web/src/features/resume/browser/app.tsx#L60-L120),
[tests](../../apps/web/tests/pi-resume.spec.ts#L135-L150)).

### Accessibility and focus

The recorded conversation is a listbox. Options expose selected/current state,
and Arrow keys plus Home move focus while keeping the evidence selection in sync
([tests](../../apps/web/tests/pi-resume.spec.ts#L117-L153)). Mobile tests
preserve access through pane tabs rather than removing a view
([tests](../../apps/web/tests/pi-resume.spec.ts#L871-L946)).

### Existing verification

The Playwright suite covers import/recovery, synchronized inspection, explicit
chat context, request previews, stop/continue, relay failures, protocol errors,
mobile/desktop layout, and storage absence
([tests](../../apps/web/tests/pi-resume.spec.ts#L19-L1159)).

### Development/production split

The chat adapter is `apply: 'serve'`; it supports a configured DeepSeek key or a
fake local mode and reports unavailable status otherwise
([adapter](../../apps/web/server/vite/resume-chat.ts#L48-L84),
[status](../../apps/web/server/vite/resume-chat.ts#L132-L151)). The current
repository has no production-preview contract for this relay.

### Migration acceptance gates

Preserve deterministic session normalization/projection, file import and Forget
recovery, synchronized source identity/focus, explicit per-turn chat context,
outbound request preview, and zero browser persistence
([core](../../apps/web/src/features/resume/core/session.ts#L709-L903),
[protocol](../../apps/web/src/features/resume/protocol/chat.ts#L260-L446),
[tests](../../apps/web/tests/pi-resume.spec.ts#L19-L339)).

### Known gaps

Post-merge production acceptance (2026-07-28) verified that Resume renders the
intentional production-unavailable chat state while session inspection remains
fully available. A server-side production chat proxy remains out of scope for
this migration.

## GenUI

### User-visible contract

The page accepts JSX presets/input, streams a rendered preview, exposes
projection and diagnostic views, replays bounded feasibility candidates, and
provides a JSON/CSV order explorer
([route](../../apps/web/src/pages/genui.tsx),
[stream test](../../apps/web/tests/genui.spec.ts#L1104-L1159),
[data tests](../../apps/web/tests/genui.spec.ts#L331-L535)).

### Runtime and browser dependencies

The browser uses the generated `@moonbit/crdt-jsx` JavaScript virtual module and
Tailwind input. The local feasibility adapter consumes deterministic core
fixtures/candidates and a server-only provider
([map](../../apps/web/MODULE_MAP.md),
[adapter](../../apps/web/server/vite/genui-feasibility.ts#L1-L25)).

### State and lifetime

JSX editor/session handles, stream state, selected feasibility case, committed
revision, and data-explorer filter/selection remain in page memory
([mount](../../apps/web/src/features/genui/browser/mount.js#L34-L75),
[feasibility state](../../apps/web/src/features/genui/browser/mount.js#L216-L240)).

### Accessibility and focus

Order rows expose selected state and support Enter/Space; data-source buttons
expose pressed state
([mount](../../apps/web/src/features/genui/browser/mount.js#L125-L188),
[tests](../../apps/web/tests/genui.spec.ts#L489-L535)).

### Existing verification

Browser tests cover streaming/projection, recorded candidate commit/replay,
invalid/stale rejection, DOM-apply recovery, data filtering/selection, and async
driver cancellation/restart. Colocated core/provider tests cover deterministic
flow and provider boundaries
([browser tests](../../apps/web/tests/genui.spec.ts#L331-L1403),
[test ownership](../../apps/web/MODULE_MAP.md)).

### Development/production split

The live provider is enabled only with `GENUI_FEASIBILITY_LIVE=1` and is served
through a serve-only adapter in Waku's Vite integration
([adapter](../../apps/web/server/vite/genui-feasibility.ts#L94-L127)). The
live-study browser API is guarded by `import.meta.env.DEV`
([mount](../../apps/web/src/features/genui/browser/mount.js#L367-L393)). The
production-preview suite verifies recorded replay remains while the local
`/api/genui-feasibility` route and development source marker are absent
([preview](../../apps/web/preview-tests/genui-preview.spec.ts#L7-L52)).

### Migration acceptance gates

Preserve generated-module loading, incremental streaming, session cleanup,
projection/diagnostic output, deterministic recorded replay and output hash,
rejection without state corruption, and data-explorer selection across filters
([stream](../../apps/web/tests/genui.spec.ts#L1104-L1159),
[feasibility](../../apps/web/tests/genui.spec.ts#L341-L484),
[data](../../apps/web/tests/genui.spec.ts#L489-L535)).

### Known gaps

The current browser suite does not exercise the streaming controls through a
screen-reader-specific assertion
([tests](../../apps/web/tests/genui.spec.ts#L1104-L1159)).

## GenUI Possibilities / Journey

### User-visible contract

The workspace presents a disruption, persistent itinerary, comparable response
options, a non-mutating preview, explicit Apply, revision status, and Undo
([route](../../apps/web/src/pages/journey.tsx),
[tests](../../apps/web/tests/genui-possibilities.spec.ts#L151-L275)).

### Runtime and browser dependencies

A deterministic `transitionJourney` reducer owns select/apply/undo decisions;
the browser module renders state and wires effects. No custom server adapter or
generated MoonBit module belongs to this surface
([reducer](../../apps/web/src/features/genui-possibilities/core/journey-state.js#L1-L67),
[map](../../apps/web/MODULE_MAP.md)).

### State and lifetime

Selection, applied response, plan, previous plan, and revision remain in memory.
Reloading creates the initial state again
([reducer](../../apps/web/src/features/genui-possibilities/core/journey-state.js#L1-L67),
[mount](../../apps/web/src/features/genui-possibilities/browser/mount.js#L34-L55)).

### Accessibility and focus

The page has a skip link, labelled regions, a response radiogroup, polite preview
and toast feedback, and roving Arrow/Home/End keyboard focus
([route](../../apps/web/src/pages/journey.tsx),
[keyboard tests](../../apps/web/tests/genui-possibilities.spec.ts#L155-L205)).

### Existing verification

Reducer tests cover state transitions and protected content. Playwright covers
preview-before-apply, revision/undo, focus, stable nodes, responsive parity,
reduced motion, and forced colors
([reducer tests](../../apps/web/src/features/genui-possibilities/core/journey-state.test.mjs#L1-L80),
[browser tests](../../apps/web/tests/genui-possibilities.spec.ts#L151-L442)).

### Development/production split

The current surface is browser-only in both modes
([map](../../apps/web/MODULE_MAP.md)).

### Migration acceptance gates

Preserve selection without mutation, explicit Apply, monotonic revision, Undo as
a new transition, protected itinerary content, focus/selection stability,
responsive information parity, reduced motion, and forced-colors meaning
([reducer tests](../../apps/web/src/features/genui-possibilities/core/journey-state.test.mjs#L1-L80),
[browser tests](../../apps/web/tests/genui-possibilities.spec.ts#L151-L442)).

### Known gaps

State restores across same-document route traversal and intentionally resets on
full reload
([route tests](../../apps/web/waku-tests/journey-route.spec.ts#L1-L35)).

## Cross-demo invariants

1. Preserve all nine canonical routes and seven permanent compatibility redirects.
   The seven legacy demo aliases return 308; `/index.html` renders the Hub without redirect
   ([route table](../../apps/web/MODULE_MAP.md)).
2. Preserve the five public MoonBit virtual import IDs, generated JavaScript
   artifact paths, declaration mappings, and dependency-optimizer exclusions
   ([Waku config](../../apps/web/waku.config.ts#L1-L30),
   [map](../../apps/web/MODULE_MAP.md)).
3. Keep imperative editor/session ownership inside client-side feature shells.
   Waku pages remain thin, browser code does not import server adapters, and
   local adapters consume only permitted core/protocol surfaces
   ([map](../../apps/web/MODULE_MAP.md)).
4. Do not clear or silently rewrite Posts data under `canopy.posts.v1` or
   `canopy.post-events.v1`; other demo route memory follows the explicit
   traversal-restore and full-reload-reset lifecycle contracts
   ([post store](../../apps/web/src/features/posts/browser/post-store.ts#L5-L42),
   [event store](../../apps/web/src/features/posts/browser/post-events.ts#L13-L71),
   [route test ownership](../../apps/web/MODULE_MAP.md#test-ownership)).
5. Preserve equivalent pointer, keyboard, screen-reader, responsive, and
   reduced-motion evidence where current tests assert it, especially Markdown
   selection restoration, Resume synchronized focus, GenUI row selection, and
   Journey decision parity
   ([Markdown](../../apps/web/tests/markdown-editor.spec.ts#L45-L137),
   [Resume](../../apps/web/tests/pi-resume.spec.ts#L117-L153),
   [GenUI](../../apps/web/tests/genui.spec.ts#L489-L535),
   [Journey](../../apps/web/tests/genui-possibilities.spec.ts#L151-L442)).
6. Retain each capability's current environment split: AST Grep is development
   only, Resume chat is a local relay exposed through Waku's Vite integration,
   and GenUI preview excludes the live study relay while retaining recorded replay
   ([AST Grep](../../apps/web/src/features/lambda/browser/ast-grep-runner.ts#L16-L21),
   [Resume](../../apps/web/server/vite/resume-chat.ts#L48-L84),
   [GenUI](../../apps/web/preview-tests/genui-preview.spec.ts#L7-L52)).

## Source register

- [Active-surface and runtime inventory](../../apps/web/MODULE_MAP.md)
- [Waku configuration](../../apps/web/waku.config.ts#L1-L30)
- [Waku route pages](../../apps/web/src/pages/)
- [Feature packages](../../apps/web/src/features/)
- [Local development adapters](../../apps/web/server/vite/)
- [Default browser suites](../../apps/web/tests/)
- [Production-preview suite](../../apps/web/preview-tests/genui-preview.spec.ts#L1-L52)
