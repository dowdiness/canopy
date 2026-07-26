# Waku demo behavior contracts

**Date:** 2026-07-25

**Issue:** [#953 — Inventory behavioral acceptance contracts for all eight demos](https://github.com/dowdiness/canopy/issues/953)

This document records the behavior that the `examples/web` Waku migration must
preserve. It is an inventory of the current checkout, not a route design or an
implementation plan. Canonical Waku URLs, cross-route state retention, and route
error behavior remain decisions for issue #952.

## Scope

The inventory covers the eight active HTML surfaces listed in the current
[module map](../../examples/web/MODULE_MAP.md#L5-L16). It records visible
workflows, runtime dependencies, state lifetime, accessibility behavior,
existing verification, development-only capabilities, migration gates, and
verified gaps. It does not cover the inactive `spike-block-input.html` surface
or historical files under `docs/archive`.

## Summary

| Demo | Current URL and source | Primary job | Runtime boundary | Persistence | Development/production split | Principal test |
| --- | --- | --- | --- | --- | --- | --- |
| Lambda | `/`, `/index.html` ([HTML](../../examples/web/index.html#L1-L5), [map](../../examples/web/MODULE_MAP.md#L7)) | Edit Mini-ML and inspect AST, formatted structure, and diagnostics | Generated Lambda and Graphviz JavaScript virtual modules; local AST Grep adapter | Page memory | AST Grep returns no matches outside development; visible collaboration controls are not bound by the current entry graph | [Lambda Playwright](../../examples/web/tests/lambda-editor.spec.ts#L1-L163) |
| JSON | `/json.html` ([HTML](../../examples/web/json.html#L1-L8), [map](../../examples/web/MODULE_MAP.md#L8)) | Edit JSON as text or a structural tree and inspect edits | Generated JSON JavaScript virtual module and editor adapter | Page memory | No custom server adapter | [JSON Playwright](../../examples/web/tests/json-editor.spec.ts#L1-L291) |
| Markdown | `/markdown.html` ([HTML](../../examples/web/markdown.html#L1-L9), [map](../../examples/web/MODULE_MAP.md#L9)) | Edit one Markdown document in block, raw, and preview modes | Generated Markdown JavaScript virtual module and editor adapter | Page memory | No custom server adapter | [Markdown Playwright](../../examples/web/tests/markdown-editor.spec.ts#L1-L375) |
| Memo | `/memo.html` ([HTML](../../examples/web/memo.html#L1-L16), [map](../../examples/web/MODULE_MAP.md#L10)) | Preview and accept or reject typo corrections and structured edits | Generated Lambda JavaScript virtual module; browser-to-Google credential flow | Page memory | Explicitly local-only; current page must not be deployed publicly | [Memo Playwright](../../examples/web/tests/memo-editor.spec.ts#L1-L26) |
| Posts | `/posts.html` ([HTML](../../examples/web/posts.html#L1-L14), [map](../../examples/web/MODULE_MAP.md#L11)) | Save local posts and retrieve related earlier posts | Browser persistence shell around deterministic TypeScript core | `localStorage` | Same browser implementation in both modes | [Posts Playwright](../../examples/web/tests/post-app.spec.ts#L1-L243) |
| Resume/PKE | `/resume.html` ([HTML](../../examples/web/resume.html#L1-L14), [map](../../examples/web/MODULE_MAP.md#L12)) | Inspect a session through synchronized timeline, conversation, and evidence; optionally chat with attached context | React 19 browser app and local Vite chat relay | Page memory; imported file is not stored | DeepSeek/fake relay is local; production behavior is unverified | [Resume Playwright](../../examples/web/tests/pi-resume.spec.ts#L1-L1159) |
| GenUI | `/genui.html` ([HTML](../../examples/web/genui.html#L1-L15), [map](../../examples/web/MODULE_MAP.md#L13)) | Stream JSX, inspect projection/diagnostics, and replay bounded feasibility candidates | Generated JSX JavaScript virtual module; optional local study relay | Page memory | Preview keeps recorded replay and excludes the development test hook and local study endpoint | [GenUI Playwright](../../examples/web/tests/genui.spec.ts#L1-L1403) |
| Journey | `/genui-possibilities.html` ([HTML](../../examples/web/genui-possibilities.html#L1-L12), [map](../../examples/web/MODULE_MAP.md#L14)) | Compare journey responses, preview a change, apply it, and undo it | Deterministic JavaScript reducer with a DOM shell | Page memory | No custom server adapter | [Journey Playwright](../../examples/web/tests/genui-possibilities.spec.ts#L1-L442) |

## Lambda calculus editor

### User-visible contract

The page offers five source presets, a plaintext contenteditable editor, an AST
visualization, formatted structure, and diagnostics
([HTML](../../examples/web/index.html#L70-L117)). Typing or selecting a preset
updates the generated model and all three outputs
([editor](../../examples/web/src/features/lambda/browser/editor.ts#L34-L81),
[tests](../../examples/web/tests/lambda-editor.spec.ts#L48-L163)).

### Runtime and browser dependencies

The browser imports `@moonbit/crdt-lambda`, `@moonbit/graphviz`, the HTML editor
adapter, and the shared decoration overlay
([editor](../../examples/web/src/features/lambda/browser/editor.ts#L3-L8)). AST
Grep analysis crosses the `/api/ast-grep` boundary through a cancellable browser
request ([runner](../../examples/web/src/features/lambda/browser/ast-grep-runner.ts#L1-L37)).

### State and lifetime

Each mount creates a fresh agent ID and editor handle
([mount](../../examples/web/src/features/lambda/browser/mount.ts#L5-L19),
[editor](../../examples/web/src/features/lambda/browser/editor.ts#L9-L12)). The
current controller exposes text read/write operations but no disposal or browser
storage path ([editor](../../examples/web/src/features/lambda/browser/editor.ts#L138-L151)).

### Accessibility and focus

Presets are native buttons and the editor is a focusable plaintext contenteditable
([HTML](../../examples/web/index.html#L70-L104)). Existing browser tests verify
that the editor is visible and focusable, but do not assert screen-reader
semantics ([tests](../../examples/web/tests/lambda-editor.spec.ts#L44-L52)).

### Existing verification

The Playwright suite covers page errors, presets, AST rendering, formatted
output, clean and failing type checks, parse-error suppression, and the AST
Grep HTTP method/empty-input contract
([tests](../../examples/web/tests/lambda-editor.spec.ts#L29-L163)).

### Development/production split

The server adapter is `apply: 'serve'`
([adapter](../../examples/web/server/vite/ast-grep.ts#L13-L20)), and the browser
runner returns an empty match list when `import.meta.env.DEV` is false
([runner](../../examples/web/src/features/lambda/browser/ast-grep-runner.ts#L16-L21)).
The collaboration panel exists in HTML, but the current Lambda mount binds only
the editor and preset buttons. Signaling files remain separate integration
shells outside the browser graph
([HTML](../../examples/web/index.html#L14-L30),
[mount](../../examples/web/src/features/lambda/browser/mount.ts#L5-L19),
[map](../../examples/web/MODULE_MAP.md#L18-L23)).

### Migration acceptance gates

Preserve source editing, AST/format/diagnostic updates, preset behavior, and the
AST Grep development contract. Production must retain the current no-analysis
fallback rather than attempting the local endpoint
([runner](../../examples/web/src/features/lambda/browser/ast-grep-runner.ts#L16-L21),
[tests](../../examples/web/tests/lambda-editor.spec.ts#L29-L43)).

### Known gaps

The visible Network Collaboration controls have no event binding in the current
Lambda entry graph, and no browser test exercises a signaling handshake
([mount](../../examples/web/src/features/lambda/browser/mount.ts#L5-L19),
[Lambda suite](../../examples/web/tests/lambda-editor.spec.ts#L1-L163)).

## JSON editor

### User-visible contract

The page provides presets, raw text editing, formatting, a structured tree,
structural actions, and an edit log
([HTML](../../examples/web/json.html#L10-L59),
[editor](../../examples/web/src/features/json/browser/editor.ts#L196-L451)).

### Runtime and browser dependencies

The browser imports `@moonbit/crdt-json`, the HTML adapter, adapter view types,
and the shared decoration overlay
([editor](../../examples/web/src/features/json/browser/editor.ts#L1-L4)). No
server adapter belongs to this surface ([map](../../examples/web/MODULE_MAP.md#L7-L22)).

### State and lifetime

A per-load agent ID creates the JSON handle. Structured collapse state remains
in a `Set` during the mounted session, and `beforeunload` destroys the adapter
and handle ([editor](../../examples/web/src/features/json/browser/editor.ts#L17-L38),
[cleanup](../../examples/web/src/features/json/browser/editor.ts#L525-L546)).

### Accessibility and focus

Container toggles expose `role="button"` and `tabindex="0"` and respond to Enter
or Space. The edit-log disclosure uses the same keyboard contract
([tree](../../examples/web/src/features/json/browser/editor.ts#L196-L220),
[log](../../examples/web/src/features/json/browser/editor.ts#L506-L524)).

### Existing verification

Playwright covers raw parse errors, text-to-structure updates, add/delete/type
operations, collapse persistence, semantic role spans, decorations, and format
behavior ([tests](../../examples/web/tests/json-editor.spec.ts#L29-L291)).

### Development/production split

The current surface has no custom server adapter; its generated JavaScript
module and browser code are shared by development and production builds
([map](../../examples/web/MODULE_MAP.md#L7-L22)).

### Migration acceptance gates

Preserve lossless switching between raw and structured views, structural edit
operations, collapse state while mounted, role-span decorations, formatting,
and cleanup. Tests may keep `window.getJsonRoleSpans` or receive an equivalent
observable seam ([editor](../../examples/web/src/features/json/browser/editor.ts#L55-L61),
[tests](../../examples/web/tests/json-editor.spec.ts#L137-L269)).

### Known gaps

The current Playwright suite does not assert rendered edit-log entries or
`beforeunload` cleanup ([tests](../../examples/web/tests/json-editor.spec.ts#L1-L291)).

## Markdown editor

### User-visible contract

One document can be edited in Block or Raw mode and read in Preview mode. The
block toolbar changes headings, toggles list items, and deletes blocks
([HTML](../../examples/web/markdown.html#L10-L63),
[app](../../examples/web/src/features/markdown/browser/app.ts#L180-L279)).

### Runtime and browser dependencies

The browser imports `@moonbit/crdt-markdown`, `BlockInput`, `MarkdownPreview`,
and adapter protocol types
([app](../../examples/web/src/features/markdown/browser/app.ts#L1-L9)). There is
no custom server adapter for this surface
([map](../../examples/web/MODULE_MAP.md#L9-L22)).

### State and lifetime

The mounted shell owns the Markdown handle, current mode, active node, raw-mode
dirty flag, and saved `BlockSelection`. Switching modes stores and restores the
BlockInput selection; `beforeunload` destroys both adapters and the handle
([state](../../examples/web/src/features/markdown/browser/app.ts#L22-L35),
[modes](../../examples/web/src/features/markdown/browser/app.ts#L182-L231),
[cleanup](../../examples/web/src/features/markdown/browser/app.ts#L327-L335)).

### Accessibility and focus

Mode controls and toolbar actions are native buttons. Block mode supports
Ctrl+1–6, Ctrl+0, and Ctrl+Shift+L; switching to Raw focuses the textarea, and
returning to Block attempts to restore the saved selection
([modes](../../examples/web/src/features/markdown/browser/app.ts#L182-L231),
[shortcuts](../../examples/web/src/features/markdown/browser/app.ts#L281-L310)).

### Existing verification

Playwright covers lossless mode changes, selection restoration, block identity,
list markers, insertion/deletion/navigation, code-block whitespace, and semantic
preview output ([tests](../../examples/web/tests/markdown-editor.spec.ts#L29-L375)).

### Development/production split

The current surface has no custom server capability; the same browser modules
run in both builds ([map](../../examples/web/MODULE_MAP.md#L9-L22)).

### Migration acceptance gates

Within a mounted editor, preserve text, block identity, active selection/focus,
raw dirty-state semantics, and preview meaning across mode changes. Cross-route
retention remains a separate #952 decision
([modes](../../examples/web/src/features/markdown/browser/app.ts#L182-L231),
[tests](../../examples/web/tests/markdown-editor.spec.ts#L45-L137)).

### Known gaps

The current Playwright suite does not exercise the documented Ctrl-based block
shortcuts or `beforeunload` cleanup
([tests](../../examples/web/tests/markdown-editor.spec.ts#L1-L375)).

## Memo editor

### User-visible contract

The page accepts text, a Gemini API key, and an edit instruction. It can request
typo correction or structured edits, then show original/corrected panes with
Accept and Reject actions ([HTML](../../examples/web/memo.html#L9-L52)).

### Runtime and browser dependencies

The browser imports the generated Lambda module and calls its
`canopy_llm_fix_typos` and `canopy_llm_edit` functions
([app](../../examples/web/src/features/memo/browser/app.ts#L1-L8)). The HTML
states that the key is sent directly from the browser to Google
([HTML](../../examples/web/memo.html#L9-L14)).

### State and lifetime

The key, pending corrected text, request timestamp, input, and instruction stay
in page memory. The app enforces a 5-second request interval and a 5,000-character
input limit ([app](../../examples/web/src/features/memo/browser/app.ts#L10-L48)).

### Accessibility and focus

Inputs, textarea, and actions are native controls. Missing key/text/instruction
validation reports status, and a missing instruction returns focus to that input
([app](../../examples/web/src/features/memo/browser/app.ts#L16-L39),
[edit path](../../examples/web/src/features/memo/browser/app.ts#L96-L108)).

### Existing verification

The browser suite verifies page startup and local validation for missing key,
text, and instruction ([tests](../../examples/web/tests/memo-editor.spec.ts#L1-L26)).

### Development/production split

The page explicitly identifies itself as local-only, warns against public
deployment, and requires a server-side proxy for production use
([HTML](../../examples/web/memo.html#L9-L14)).

### Migration acceptance gates

Keep the local-only warning and browser validation. Do not expose the current
credential flow from a production route unless a separately approved server
boundary replaces it ([HTML](../../examples/web/memo.html#L9-L18),
[tests](../../examples/web/tests/memo-editor.spec.ts#L8-L26)).

### Known gaps

The current browser suite does not call the provider or cover rate limiting,
length limiting, diff rendering, Accept, or Reject
([tests](../../examples/web/tests/memo-editor.spec.ts#L1-L26)).

## Posts

### User-visible contract

A person can write and post local text, use Ctrl/Cmd+Enter to submit, use Ask
without posting, inspect related earlier posts, and fall back to a newest-first
timeline ([HTML](../../examples/web/posts.html#L10-L60),
[tests](../../examples/web/tests/post-app.spec.ts#L12-L243)).

### Runtime and browser dependencies

The browser shell composes deterministic post/event/retrieval core modules with
DOM and `localStorage` adapters. It has no generated MoonBit or custom server
dependency ([mount](../../examples/web/src/features/posts/browser/mount.ts#L1-L13),
[map](../../examples/web/MODULE_MAP.md#L11-L22)).

### State and lifetime

Posts persist as JSON under `canopy.posts.v1`; creation and related-open events
persist under `canopy.post-events.v1`. Both stores validate parsed entries and
return newest-first data
([post store](../../examples/web/src/features/posts/browser/post-store.ts#L1-L42),
[event store](../../examples/web/src/features/posts/browser/post-events.ts#L1-L71)).

### Accessibility and focus

The status row is polite live text, the related panel and timeline use labelled
sections/lists, and keyboard submit is documented with `kbd` labels
([HTML](../../examples/web/posts.html#L17-L60)). The implementation moves focus
to the matching timeline item when a related post opens
([view](../../examples/web/src/features/posts/browser/view.ts#L110-L151)).

### Existing verification

Playwright covers reload persistence, keyboard submission, order, related-post
retrieval, Ask isolation, engagement reranking, highlighting, and persisted
event shape ([tests](../../examples/web/tests/post-app.spec.ts#L12-L243)).

### Development/production split

The feature is browser-only in both modes
([map](../../examples/web/MODULE_MAP.md#L11-L22)).

### Migration acceptance gates

Preserve both storage keys and their validated JSON shapes, newest-first order,
keyboard submission, Ask-without-posting behavior, retrieval results, and
related-open focus. Migration must not clear existing local data
([stores](../../examples/web/src/features/posts/browser/post-store.ts#L5-L42),
[events](../../examples/web/src/features/posts/browser/post-events.ts#L13-L71),
[tests](../../examples/web/tests/post-app.spec.ts#L12-L243)).

### Known gaps

No additional source-backed gap is recorded.

## Resume/PKE

### User-visible contract

The React workbench loads an example session or an imported JSONL file, selects
a path, synchronizes Timeline, Conversation, and Evidence, and offers an
independent chat whose history/source context is attached explicitly
([tests](../../examples/web/tests/pi-resume.spec.ts#L19-L190),
[app](../../examples/web/src/features/resume/browser/app.tsx#L1500-L1645)).

### Runtime and browser dependencies

The app uses React 19, `@ai-sdk/react`, and the AI SDK
([package](../../examples/web/package.json#L15-L25),
[imports](../../examples/web/src/features/resume/browser/app.tsx#L1-L17)). Chat
uses the `/api/pi-resume-chat` transport supplied by a local Vite adapter
([app](../../examples/web/src/features/resume/browser/app.tsx#L602-L612),
[adapter](../../examples/web/server/vite/resume-chat.ts#L48-L62)).

### State and lifetime

Imported session, path selection, and chat state live in React state for the
current tab. Tests verify no local storage, session storage, or IndexedDB is
created by the workflow ([state](../../examples/web/src/features/resume/browser/app.tsx#L60-L120),
[tests](../../examples/web/tests/pi-resume.spec.ts#L135-L150)).

### Accessibility and focus

The recorded conversation is a listbox. Options expose selected/current state,
and Arrow keys plus Home move focus while keeping the evidence selection in sync
([tests](../../examples/web/tests/pi-resume.spec.ts#L117-L153)). Mobile tests
preserve access through pane tabs rather than removing a view
([tests](../../examples/web/tests/pi-resume.spec.ts#L871-L946)).

### Existing verification

The Playwright suite covers import/recovery, synchronized inspection, explicit
chat context, request previews, stop/continue, relay failures, protocol errors,
mobile/desktop layout, and storage absence
([tests](../../examples/web/tests/pi-resume.spec.ts#L19-L1159)).

### Development/production split

The chat adapter is `apply: 'serve'`; it supports a configured DeepSeek key or a
fake local mode and reports unavailable status otherwise
([adapter](../../examples/web/server/vite/resume-chat.ts#L48-L84),
[status](../../examples/web/server/vite/resume-chat.ts#L132-L151)). The current
repository has no production-preview contract for this relay.

### Migration acceptance gates

Preserve deterministic session normalization/projection, file import and Forget
recovery, synchronized source identity/focus, explicit per-turn chat context,
outbound request preview, and zero browser persistence
([core](../../examples/web/src/features/resume/core/session.ts#L709-L903),
[protocol](../../examples/web/src/features/resume/protocol/chat.ts#L260-L446),
[tests](../../examples/web/tests/pi-resume.spec.ts#L19-L339)).

### Known gaps

Production chat availability is unverified by the current preview suites
([map](../../examples/web/MODULE_MAP.md#L18-L23)).

## GenUI

### User-visible contract

The page accepts JSX presets/input, streams a rendered preview, exposes
projection and diagnostic views, replays bounded feasibility candidates, and
provides a JSON/CSV order explorer
([HTML](../../examples/web/genui.html#L11-L207),
[stream test](../../examples/web/tests/genui.spec.ts#L1104-L1159),
[data tests](../../examples/web/tests/genui.spec.ts#L331-L535)).

### Runtime and browser dependencies

The browser uses the generated `@moonbit/crdt-jsx` JavaScript virtual module and
Tailwind input. The local feasibility adapter consumes deterministic core
fixtures/candidates and a server-only provider
([map](../../examples/web/MODULE_MAP.md#L13-L22),
[adapter](../../examples/web/server/vite/genui-feasibility.ts#L1-L25)).

### State and lifetime

JSX editor/session handles, stream state, selected feasibility case, committed
revision, and data-explorer filter/selection remain in page memory
([mount](../../examples/web/src/features/genui/browser/mount.js#L34-L75),
[feasibility state](../../examples/web/src/features/genui/browser/mount.js#L216-L240)).

### Accessibility and focus

Order rows expose selected state and support Enter/Space; data-source buttons
expose pressed state
([mount](../../examples/web/src/features/genui/browser/mount.js#L125-L188),
[tests](../../examples/web/tests/genui.spec.ts#L489-L535)).

### Existing verification

Browser tests cover streaming/projection, recorded candidate commit/replay,
invalid/stale rejection, DOM-apply recovery, data filtering/selection, and async
driver cancellation/restart. Colocated core/provider tests cover deterministic
flow and provider boundaries
([browser tests](../../examples/web/tests/genui.spec.ts#L331-L1403),
[test ownership](../../examples/web/MODULE_MAP.md#L42-L48)).

### Development/production split

The live provider is enabled only with `GENUI_FEASIBILITY_LIVE=1` and is served
through a Vite-only adapter
([adapter](../../examples/web/server/vite/genui-feasibility.ts#L94-L127)). The
live-study browser API is guarded by `import.meta.env.DEV`
([mount](../../examples/web/src/features/genui/browser/mount.js#L367-L393)). The
production-preview suite verifies recorded replay remains while the local
`/api/genui-feasibility` route and development source marker are absent
([preview](../../examples/web/preview-tests/genui-preview.spec.ts#L7-L52)).

### Migration acceptance gates

Preserve generated-module loading, incremental streaming, session cleanup,
projection/diagnostic output, deterministic recorded replay and output hash,
rejection without state corruption, and data-explorer selection across filters
([stream](../../examples/web/tests/genui.spec.ts#L1104-L1159),
[feasibility](../../examples/web/tests/genui.spec.ts#L341-L484),
[data](../../examples/web/tests/genui.spec.ts#L489-L535)).

### Known gaps

The current browser suite does not exercise the streaming controls through a
screen-reader-specific assertion
([tests](../../examples/web/tests/genui.spec.ts#L1104-L1159)).

## GenUI Possibilities / Journey

### User-visible contract

The workspace presents a disruption, persistent itinerary, comparable response
options, a non-mutating preview, explicit Apply, revision status, and Undo
([HTML](../../examples/web/genui-possibilities.html#L10-L104),
[tests](../../examples/web/tests/genui-possibilities.spec.ts#L151-L275)).

### Runtime and browser dependencies

A deterministic `transitionJourney` reducer owns select/apply/undo decisions;
the browser module renders state and wires effects. No custom server adapter or
generated MoonBit module belongs to this surface
([reducer](../../examples/web/src/features/genui-possibilities/core/journey-state.js#L1-L67),
[map](../../examples/web/MODULE_MAP.md#L14-L22)).

### State and lifetime

Selection, applied response, plan, previous plan, and revision remain in memory.
Reloading creates the initial state again
([reducer](../../examples/web/src/features/genui-possibilities/core/journey-state.js#L1-L67),
[mount](../../examples/web/src/features/genui-possibilities/browser/mount.js#L34-L55)).

### Accessibility and focus

The page has a skip link, labelled regions, a response radiogroup, polite preview
and toast feedback, and roving Arrow/Home/End keyboard focus
([HTML](../../examples/web/genui-possibilities.html#L10-L104),
[keyboard tests](../../examples/web/tests/genui-possibilities.spec.ts#L155-L205)).

### Existing verification

Reducer tests cover state transitions and protected content. Playwright covers
preview-before-apply, revision/undo, focus, stable nodes, responsive parity,
reduced motion, and forced colors
([reducer tests](../../examples/web/src/features/genui-possibilities/core/journey-state.test.mjs#L1-L80),
[browser tests](../../examples/web/tests/genui-possibilities.spec.ts#L151-L442)).

### Development/production split

The current surface is browser-only in both modes
([map](../../examples/web/MODULE_MAP.md#L14-L22)).

### Migration acceptance gates

Preserve selection without mutation, explicit Apply, monotonic revision, Undo as
a new transition, protected itinerary content, focus/selection stability,
responsive information parity, reduced motion, and forced-colors meaning
([reducer tests](../../examples/web/src/features/genui-possibilities/core/journey-state.test.mjs#L1-L80),
[browser tests](../../examples/web/tests/genui-possibilities.spec.ts#L151-L442)).

### Known gaps

State intentionally does not persist across reloads; whether a routed app should
retain it is a #952 decision
([reducer](../../examples/web/src/features/genui-possibilities/core/journey-state.js#L1-L67)).

## Cross-demo invariants

1. Preserve all eight current compatibility URLs until issue #952 explicitly
   selects canonical routes and redirects. The Vite build currently names all
   eight HTML inputs ([config](../../examples/web/vite.config.ts#L55-L69)).
2. Preserve the five public MoonBit virtual import IDs, generated JavaScript
   artifact paths, declaration mappings, and dependency-optimizer exclusions
   ([config](../../examples/web/vite.config.ts#L18-L46),
   [map](../../examples/web/MODULE_MAP.md#L24-L40)).
3. Keep imperative editor/session ownership inside client-side feature shells.
   Entries remain thin, browser code does not import server adapters, and local
   adapters consume only permitted core/protocol surfaces
   ([map](../../examples/web/MODULE_MAP.md#L50-L71)).
4. Do not clear or silently rewrite Posts data under `canopy.posts.v1` or
   `canopy.post-events.v1`; all other current demo state is page-scoped unless
   issue #952 chooses a new lifetime
   ([post store](../../examples/web/src/features/posts/browser/post-store.ts#L5-L42),
   [event store](../../examples/web/src/features/posts/browser/post-events.ts#L13-L71)).
5. Preserve equivalent pointer, keyboard, screen-reader, responsive, and
   reduced-motion evidence where current tests assert it, especially Markdown
   selection restoration, Resume synchronized focus, GenUI row selection, and
   Journey decision parity
   ([Markdown](../../examples/web/tests/markdown-editor.spec.ts#L45-L137),
   [Resume](../../examples/web/tests/pi-resume.spec.ts#L117-L153),
   [GenUI](../../examples/web/tests/genui.spec.ts#L489-L535),
   [Journey](../../examples/web/tests/genui-possibilities.spec.ts#L151-L442)).
6. Retain each capability's current environment split: AST Grep is development
   only, Resume chat is a local Vite relay with no production contract, and
   GenUI preview excludes the live study relay while retaining recorded replay
   ([AST Grep](../../examples/web/src/features/lambda/browser/ast-grep-runner.ts#L16-L21),
   [Resume](../../examples/web/server/vite/resume-chat.ts#L48-L84),
   [GenUI](../../examples/web/preview-tests/genui-preview.spec.ts#L7-L52)).

## Source register

- [Active-surface and runtime inventory](../../examples/web/MODULE_MAP.md#L1-L74)
- [Vite entry and generated-module configuration](../../examples/web/vite.config.ts#L1-L74)
- [Browser entries](../../examples/web/src/entries/)
- [Feature packages](../../examples/web/src/features/)
- [Local Vite adapters](../../examples/web/server/vite/)
- [Default browser suites](../../examples/web/tests/)
- [Production-preview suite](../../examples/web/preview-tests/genui-preview.spec.ts#L1-L52)
