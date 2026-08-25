# Loomark application handoff

Status: delivered handoff baseline — the Foundation and private Application Train through #1075 and the semantic Preview slice #1145 are complete. #1162 superseded this plan's earlier public Browser App/Session-before-production assumption. #1176, merged as #1177, delivered standalone Loomark through `apps/loomark/main`; Warren is now canonical for development preview and release output. The public embeddable contract, teardown/remount claims, framework adapters, and Waku cutover remain future compatibility work gated by Rabbita #141 and #1072. This document retains the completed implementation history and deferred embedding contract; #1162 and its child issues define active product work.

## Why

The current Waku Markdown feature owns behavior in TypeScript and a low-level global-handle FFI. Loomark replaces it with one standalone MoonBit module and one page-owned Rabbita root for the page lifetime (#1162). The standalone executable package `apps/loomark/main` is the current production entry point, served by Warren for development and release builds. Before Rabbita exposes mount-specific teardown for embedding, no public JS lifecycle wrapper is required; the standalone page owns its mount for the page lifetime.

## Scope

In:

- editor/markdown typed atomic Canopy façade; Loomark core; the shared private Rabbita application; standalone `main` and public assets; the private diagnostic host; generic dom-boundary selection/measurement.
- Warren development/release/CI coverage for the standalone application; a future single public FFI root and host adapters under #1072; later atomic Waku cutover.

Out:

- Public embeddable Browser Session (the future `MarkdownApp`/`MarkdownSession` contract), disposal/remount/host reuse, React/Vue adapters, or Waku work before their gates; npm/semver/publishing; raw DOM or JS public API; renderer/theming hooks; generic capability traits; legacy compatibility. These remain deferred compatibility design for future embedding, not current production requirements.
- New syntax/recovery semantics, rich inline editing, unsupported moves, Markdown diagnostic model, and React/Vue work during #1073–#1075.

## Current state and ownership

apps/web/src/features/markdown/browser/app.ts is migration evidence only: it owns mode, toolbar, Raw sync, BlockInput, Preview, focus, listeners, frames, handles, and cleanup. apps/web/src/shared/route-lifecycle/browser/imperative-session.ts remains Waku's generic defensive snapshot/focus/idempotent-dispose seam and maps its dispose to the canonical unmount at cutover. ffi/markdown/markdown_ffi.mbt global handles/string commands/JSON ViewPatch path is replaced, never wrapped. ffi/jsx/session.mbt and ffi/jsx/apply_patches.mbt are only precedents for session-private ownership, atomic initial publication, structured errors, and JS exception quarantine.

    Loom parser / recovered CST / diagnostics / Markdown semantics
                                  ↓
    Canopy editor/markdown façade / projection / SourceMap / edit lowering
                                  ↓
                   dowdiness/loomark/core (pure reducer)
                                  ↓
                  apps/loomark/internal/rabbita
                         ↓                    ↓
         apps/loomark/main             internal/dev_host
         (Warren standalone)           (private diagnostics)

    Future embedding only (#1072):

    apps/loomark/browser → apps/loomark/ffi → React/Vue/Waku adapters

| Boundary | Owns | Must not own |
| --- | --- | --- |
| Loom | parser, recovered CST, diagnostics, Markdown semantics | UI, DOM, host lifecycle |
| Canopy editor/markdown | document/projection access, source map, edit lowering, atomic source commit | browser state, callbacks, DOM |
| Loomark core | deterministic state, mode/toolbar/focus decisions, proposed transition | editor/source copy, DOM, Cmd/Sub, clock/random/framework state |
| Loomark browser | serialization, snapshots, tokens, and future embedding adaptation | Markdown rendering or standalone mount ownership |
| private Rabbita application | mounted editor DOM, Raw editor, Block editor, Preview, Cmd/Sub/capability wiring; shared implementation for standalone `main` and private `dev_host` | public embeddable Session or framework lifecycle |
| standalone main | one page-owned mount plus Warren-served development and release output | embedding, teardown/remount, or host reuse (deferred to #1072) |
| hosts | lifecycle/callback forwarding and token/snapshot carriage | Markdown logic or editor state |

Canopy never imports Loomark. The application transaction runs identically in the standalone application and private development host, and a future Browser Session must preserve it: validate; pure-reduce; atomically commit canonical source through editor/markdown; install proposed state; emit ordered committed facts. Any editor failure discards the proposal, preserves source/projection, emits no change, and reports its categorized error. Raw input and snapshot restore obey this same transaction.

## Physical layout and delivery paths

The provisional application/markdown and canopy-markdown-application names are superseded:

    editor/markdown/                         # dowdiness/canopy/editor/markdown
    apps/loomark/
      moon.mod                               # name = "dowdiness/loomark"
      main/                                  # standalone executable entry point; #1176
      core/                                  # dowdiness/loomark/core
      browser/                               # dowdiness/loomark/browser
      internal/rabbita/                      # private; shared application driver
      internal/dev_host/                     # private test-only JS link root; #1103 diagnostic seam
      ffi/                                   # future embeddable JS link root; #1072 only
      public/                                # Warren static assets
      adapters/react/                        # @dowdiness/loomark-react, unpublished
      adapters/vue/                          # @dowdiness/loomark-vue, unpublished
      examples/{vanilla,react,vue}/

Add only ./apps/loomark to moon.work. Its manifest imports public Canopy façade, selected Rabbita identity, dowdiness/dom_boundary, dowdiness/js_ffi, and used Rabbita modules. Core imports neither Rabbita, DOM, JS FFI, framework, clock, nor host state. `apps/loomark/main` is the standalone executable package: it calls `@app.mount_standalone("app", "")` from a single `fn main`, is `pkgtype(kind: "executable")`, and depends on `dowdiness/loomark/internal/rabbita`. Warren serves it for development (`warren dev --direct`) and assembles static release output (`warren build`) into the ignored `apps/loomark/dist/` directory. Before #1103, reconcile one selected Rabbita identity containing #142 with the existing CodeMirror, tabs, status, menu, and resizable module declarations.

The future public generated runtime/declaration contract is (added by #1072 for embedding only):

    _build/js/release/build/dowdiness/loomark/ffi/ffi.js
    _build/js/release/build/dowdiness/loomark/ffi/ffi.d.ts
    _build/js/release/build/dowdiness/loomark/ffi/moonbit.d.ts

Add all three paths to scripts/build-js.sh, its Bash-3 fake-compiler fixture in scripts/test-pr-ready-bash32.sh, and the explicit build-js upload list in .github/workflows/ci.yml. All hosts consume this one runtime and generated types, never beside canopy/ffi/markdown/markdown.js. Later Waku cutover alone updates apps/web/moonbit-artifacts.mjs, apps/web/tsconfig.json, src/shared/browser/moonbit-client-probe.tsx, waku-tests/foundation.spec.ts, MODULE_MAP.md, Waku artifact verification, and bundle checks. scripts/package-release.sh later makes separate loomark-browser-version.tar.gz containing Loomark artifacts, manifest, README, and notices, not the legacy Markdown payload. Add a Node-24 loomark-hosts job to All Checks Passed; path filters include loomark, editor/markdown, dom-boundary, Rabbita pointer, build and CI files.

`apps/loomark/internal/dev_host` is the private test-only JS link root. It produces `_build/js/release/build/dowdiness/loomark/internal/dev_host/dev_host.js` solely for the disposable diagnostic test page. It is never added to `scripts/build-js.sh`, CI artifact uploads, release payloads, host declarations, or production examples. It provides unique diagnostic coverage (driver controls, test subscriptions, failure injection) that the standalone production page does not expose. #1103 adds `scripts/test-loomark-dev-host-e2e.sh`, which builds that package and runs the exact private Vanilla typecheck/browser commands below. It also adds a path-filtered `loomark-dev-host` Playwright job to All Checks Passed. #1072 deletes the private package, wrapper, and job while adding the public `apps/loomark/ffi` artifact and `loomark-hosts` job; the two link roots never coexist in a candidate commit. The standalone `apps/loomark/main` package remains the production entry point throughout.

## Pre-#141 private development host and standalone production

#1103 created one package-private adapter, the `apps/loomark/internal/dev_host` link root, and one disposable Vanilla test page for diagnostics. The adapter mounts exactly once into a fresh connected container. Its browser page or test process owns lifetime termination; the container is never cleared, reused, remounted, or transferred. Tests create a fresh Playwright page and BrowserContext per isolated case. This bounded test-only lifetime is not a cleanup implementation and is not permitted in Waku, React, Vue, examples presented as production hosts, or the generated public declaration.

The `apps/loomark/main` package added by #1176 is separate: it is the current production entry point, mounts one Rabbita root, and owns that root for the page lifetime. It neither depends on the private driver entry point nor claims reusable-host cleanup.

The development host may expose only test-driver operations needed to submit typed application events, inspect detached snapshots/errors, and assert rendered behavior. It exposes no `MarkdownApp`, `MarkdownSession`, `unmount`, raw Rabbita value, DOM handle, global handle registry, or success result implying cleanup. It uses the same pure reducer, editor transaction, event ordering, focus decisions, and private Rabbita view that the canonical Session will use. Fatal errors stop further driver operations but do not claim that Rabbita subscriptions or callbacks were released. The standalone production page does not expose these driver controls; production excludes them from the release bundle via `scripts/test-loomark-standalone-e2e.sh`.

The private host is an internal seam, not a generic lifecycle trait. After Rabbita #141 is available, #1072 may replace that diagnostic mount-once adapter with the mount-specific `MountedApp` returned by Rabbita, delegate teardown to `MountedApp::unmount`, and expose the generated embedding contract below. The standalone page-owned mount remains independently valid. The migration must leave Loomark core, editor/markdown commands, edit lowering, snapshots, application events, and rendered state unchanged. #1072 then adds disposal, repeated-unmount, host-reuse, fatal-cleanup, reentrancy, and remount tests before deleting any superseded private entry point. No compatibility layer or dual DOM owner remains. This embedding work does not gate standalone completion or daily-writing validation.

## Canonical Browser App/Session contract matrix (deferred embedding contract)

The generated declaration is the refined #1064 contract below. It is first exposed by #1072 after Rabbita #141 for embedding-only scenarios; #1103 and #1073–#1075 may not publish a subset or provisional substitute. Standalone Loomark does not require this contract. It applies only to future embedding in external hosts such as React, Vue, and Waku. These names and shapes are exact; implementation tickets may not substitute a factory, optional error channel, removable error handler, raw handle, or different status vocabulary.

```ts
export type MarkdownMode = "raw" | "block" | "preview";
export type MarkdownSnapshotV1 = Readonly<{
  version: 1;
  source: string;
  mode: MarkdownMode;
}>;

declare const markdownFocusTokenBrand: unique symbol;
export type MarkdownFocusToken = string & {
  readonly [markdownFocusTokenBrand]: true;
};

export type MarkdownErrorCode =
  | "invalid-host"
  | "host-already-mounted"
  | "invalid-options"
  | "unsupported-option"
  | "invalid-snapshot"
  | "unsupported-snapshot-version"
  | "disposed-session"
  | "editor-commit-failed"
  | "browser-effect-failed"
  | "callback-failed"
  | "internal-error";

export type MarkdownOperation =
  | "mount"
  | "restore-snapshot"
  | "update-options"
  | "editor-dispatch"
  | "browser-effect"
  | "event-callback";

export type MarkdownError = Readonly<{
  code: MarkdownErrorCode;
  operation: MarkdownOperation;
  message: string;
  fatal: boolean;
}>;
export type MarkdownResult<T> =
  | Readonly<{ ok: true; value: T }>
  | Readonly<{ ok: false; error: MarkdownError }>;
export type MarkdownDispatchStatus = "applied" | "unchanged" | "queued";
export type MarkdownEvent = Readonly<{
  type: "change";
  snapshot: MarkdownSnapshotV1;
}>;
export type MarkdownMountOptions = Readonly<{
  onError: (error: MarkdownError) => void;
  snapshot?: MarkdownSnapshotV1;
  onEvent?: (event: MarkdownEvent) => void;
}>;
export type MarkdownOptionsPatch = Readonly<{
  onError?: (error: MarkdownError) => void;
  onEvent?: ((event: MarkdownEvent) => void) | null;
}>;

export interface MarkdownSession {
  snapshot(): MarkdownSnapshotV1;
  restoreSnapshot(snapshot: MarkdownSnapshotV1): MarkdownResult<MarkdownDispatchStatus>;
  captureFocus(): MarkdownFocusToken | null;
  restoreFocus(token: MarkdownFocusToken): boolean;
  updateOptions(patch: MarkdownOptionsPatch): MarkdownResult<MarkdownDispatchStatus>;
  unmount(): MarkdownDispatchStatus;
}
export interface MarkdownApp {
  mount(host: HTMLElement, options: MarkdownMountOptions): MarkdownResult<MarkdownSession>;
}
export const markdownApp: MarkdownApp;
```

Snapshot v1 owns only source and mode. `MarkdownSession` has no public constructor or fields, and `markdownApp` is the sole generated application value.

Every mount requires callable non-removable onError and a connected light-DOM HTMLElement rooted in its Document. Detached hosts, Documents, selectors, non-elements, and ShadowRoot hosts return invalid-host atomically. No raw element, JS value, mutable collection, editor handle, projection, diagnostics, or DOM identity escapes.

| Operation/event | Success result | Failure result | Lifecycle/ownership and order | Callback reentrancy | Authoritative test seam |
| --- | --- | --- | --- | --- | --- |
| `markdownApp.mount(host, { onError })` | active session with default source/mode | `invalid-host`, `invalid-options`, internal mount error | validate before allocation; own host only after full success; no initial event | not applicable | Vanilla browser contract |
| `mount(host, { onError, snapshot })` | active session with source+mode installed | `invalid-snapshot`, `unsupported-snapshot-version`, editor/internal error | one atomic initial transaction; failed mount cleans partial resources; no initial event | not applicable | Vanilla contract + editor/application transaction tests |
| second mount on live host | none | `host-already-mounted` | existing owner and DOM unchanged | not applicable | Vanilla browser contract |
| `snapshot()` | detached, recursively frozen last-committed v1 value | none | read-only and available after unmount | reads current committed value | Vanilla contract |
| `restoreSnapshot(changed)` | idle `applied`, then one `change` | direct invalid snapshot/version/disposed/editor error | source+mode commit atomically; failure preserves source/state and emits nothing | valid call returns `queued`; later change or required `onError` | Vanilla + pure core/editor transaction tests |
| `restoreSnapshot(equal)` | idle `unchanged` | validation/lifecycle error | no editor replacement or event | valid call may return `queued`, then collapse to unchanged | Vanilla contract |
| user/editor transition | one ordered `change` after commit | `editor-commit-failed` through required `onError` | discard proposed state on failure | callback operations serialize FIFO | Vanilla + application tests |
| `captureFocus()` | opaque token or `null` | none | no ownership change | immediate read | Vanilla + Waku focus lifecycle |
| `restoreFocus(token)` | `true` only after focusing the exact target | `false`, focus unchanged | no event or state mutation | immediate against committed DOM | Vanilla + browser-capability tests |
| `updateOptions(patch)` | idle `applied` or `unchanged`; replace required `onError`, replace/clear `onEvent` | unsupported key, invalid callback, attempted `onError` removal, or disposed | no remount/event; omitted member unchanged | valid call returns `queued`; current callback set remains fixed | Vanilla contract |
| `onEvent(change)` | detached committed snapshot once | throw becomes non-fatal `callback-failed` delivered to required `onError` | after editor+application commit, in transition order | mutations queue until delivery ends | Vanilla contract |
| `onError(error)` | one structured queued/editor/effect/callback failure | handler throw restores invariants, then rethrows original host exception | fatal cleanup and ownership release happen before callback | accepted operations queue; fatal callback sees disposed | Vanilla + DOM-boundary effect tests |
| `unmount()` | idle `applied`; completed repeat `unchanged` | cleanup continues and reports one fatal `internal-error` after release | exactly-once teardown; host reusable before idle return; no event | request returns `queued`; pre-existing FIFO work runs, teardown completes before browser microtasks | Vanilla + Rabbita lifecycle tests |
| mutation/options after unmount request | none | `disposed-session` | reducer/editor/DOM untouched; no callbacks | immediate rejection | Vanilla contract |

Direct synchronous failures are MarkdownResult errors and not duplicated. Queued/editor/effect/onEvent-callback failures use required onError. onEvent throws never roll back a committed transition. onError throws restore queue/lifecycle invariants in finally and rethrow original host exception; no recursion or console-only fallback.

Callback calls validate arguments and lifecycle immediately. Invalid calls return their direct error; valid mutation and option calls return `queued` and run FIFO only after the current callback and full transaction. Queued replacement cannot change the callback being delivered. Callback unmount marks `unmount-requested` immediately and returns `queued`; later mutation/options return `disposed-session`; earlier queued work runs FIFO; exactly-once teardown finishes before browser microtasks. Host ownership persists during the callback and the first scheduled microtask may remount.

Focus tokens identify opaque logical locations independently of DOM or Session identity. Their private versioned payload contains only a closed control kind, or supported block semantic kind plus exact Canopy source range. A compatible later session resolves exactly one rendered/focusable target; never selector/DOM id/raw JS/editor handle/source copy/neighbour fallback. Hosts may carry captured values but may not parse or synthesize them.

## Behavior-to-authority links

| Behavior | Current evidence / gap | Final authority |
| --- | --- | --- |
| SSR inert controls/runtime-load error | apps/web/waku-tests/markdown-route.spec.ts | Waku route |
| mode navigation/Raw-Block round trip | apps/web/tests/markdown-editor.spec.ts | standalone browser + core |
| caret/block fallback and snapshot/focus decisions | existing Markdown/Waku tests | standalone browser + core; future Browser Session conformance |
| route cleanup, teardown, remount, host reuse | existing Waku tests; unavailable through Rabbita today | #1072 Browser Session + Waku lifecycle |
| heading identity, markers, fences | lang/markdown/proj/proj_node_wbtest.mbt and editor suite | projection/editor + standalone browser scenario |
| UTF-16/non-BMP | editor text-diff, sync-editor, word-nav tests | editor + standalone browser caret/split |
| supported/rejected MoveBlock | lang/markdown/edits/compute_markdown_edit_wbtest.mbt | edit + approved standalone subset |
| IME final commit, version/errors/reentrancy | absent | #1076 core + standalone browser contract |
| mount ownership/full remount | standalone page ownership covered; reusable host unavailable | #1072 Browser Session; Waku cutover subset |
| text value/selection/measurement/listener | modules/dom-boundary additions | boundary; Rabbita wiring only |
| React/Vue | absent | lifecycle tests plus real-binding smoke |

## Ordered graph

### Application behavior gates

1. #1068's canonical plan and tracker transaction merge; concrete native edges are verified before its temporary blocker is removed.
2. The selected Rabbita identity includes merged #142 `update_tagger`; direct `diff_subs` plus `every` and `on_resize` regressions stay green. The recorded 0.13.0 identity does not yet satisfy this gate.
3. Canopy #1045 lands with one accepted nested-heading policy and incremental-versus-fresh parity.
4. The Foundation completes through #1103. **Status: complete.**
5. #1176 delivers standalone Loomark through `apps/loomark/main`, served by Warren for development and release builds. **Status: complete; merged as #1177.**

Rabbita #141 is intentionally not an Application Train gate. It gates only the future embedding contract (public `MarkdownApp`/`MarkdownSession`), lifecycle claims, React/Vue adapters, and Waku cutover. The current standalone production page already ships without a public JS lifecycle wrapper.

### Foundation

1. #1102 adds the opaque editor/markdown façade over existing companion/edit/projection/SyncEditor internals and creates the standalone Loomark module/core skeleton.
2. #1071 implements the accepted generic UTF-16 text-control selection and measurement capabilities in modules/dom-boundary with boundary tests.
3. #1103, after adopting a selected Rabbita identity containing #142, creates Loomark's private Rabbita application, read-only Preview, mount-once development adapter, temporary `internal/dev_host` link root, disposable Vanilla browser harness, shared `test-loomark-dev-host-e2e.sh` command, and `loomark-dev-host` CI job. It adds no public Browser App/Session declaration or lifecycle claim.

### Application Train

1. #1073: Raw and Preview editing through the shared application transaction and private development host; no Block editing or public Browser Session.
2. #1074 only after green committed #1073 and #1045: paragraphs and ATX/Setext headings, supported split/merge, accepted heading policy.
3. #1075 only after green committed #1074: ordered/unordered lists and fenced code. Defer unsupported moves/containers, rich inline, diagnostics UI, adapters, Waku.

Each ticket begins with behavioral matrix and first RED test, makes one logical commit, and reruns affected evidence after commit/amend/rebase, manifest/generated-interface change, or base movement.

### Source-aware semantic Preview

Issue #1145 follows the completed private Application Train and does not wait for
Rabbita #141. It attaches one `MarkdownSemanticAttachment` to the exact parser
created for the private Loomark editor and retains it for the existing
page/process lifetime. Raw and Block keep the editable `Block` projection;
the document-level Preview consumer holds an owning `MarkdownIR` read model.
The consumer may be the full Preview mode or the fixed split Preview described
below. The ordinary headless
`MarkdownEditor` constructor remains attachment-free. `SyncEditor` privately
roots the three projection memos it already owns for the editor lifetime, so
attachment collection cannot sweep the editable projection graph without
adding a public disposal or reactive interface. The ownership decision is
recorded in
[Markdown semantic Preview ownership](../decisions/2026-08-04-markdown-semantic-preview-ownership.md).

| Boundary | Accepted transition | Semantic read | Required observation |
| --- | --- | --- | --- |
| Private mount | construct editor and attachment over one parser | none while initial mode is Raw | one attachment; ordinary constructor unchanged |
| no Preview consumer → at least one consumer | committed mode or split transition | once after transition acceptance | current complete MarkdownIR renders through typed Rabbita HTML |
| accepted source/block edit while a Preview consumer exists | editor commit succeeds | once after commit | Raw, Block, and Preview reflect the same canonical source |
| Preview no-op or rejected edit | no committed source change | none | prior owning Preview document and focus remain visible |
| Snapshot restore to Preview | source/mode transaction succeeds | once after acceptance | restored source and semantic document appear atomically |
| last Preview consumer disappears | committed mode or split transition | none; semantic model is cleared | editable source/projection behavior is unchanged |
| Prepend, position shift, exact reversal | commit succeeds in Preview | once per committed edit | attached result matches fresh one-shot MarkdownIR lowering |
| Malformed intermediate input | parser accepts recovered source | once per committed edit in Preview | `Raw`/`Recovered` are visible; no last-good substitution |
| Valid inline/block HTML | semantic render | no extra read | literal content is escaped text, never injected DOM markup |
| Repeated mode/split switches and mount rejection | accepted transition / rejected second mount | only zero-consumer → consumer reads | attachment count stays one; existing single-mount contract stays green |

The deterministic renderer exhaustively matches `MarkdownIRView`. It consumes
an already-owned document and performs no parser, attachment, DOM, clock,
subscription, or `document()` effect. Reading the attachment and installing the
owning document remain imperative-shell work at the committed boundaries above.

### Fixed split Preview M0

The first split-view increment is one editable Raw editor or Block editor beside one
read-only Preview pane. Both panes observe the same mount-owned editor, parser,
semantic attachment, canonical source, history, and accepted revision. Opening
or closing the split never constructs or disposes a document resource. Block
and Raw commits pass through their existing atomic editor boundary before the
Preview read model advances.

Split open state is private application state, while the divider ratio is local
ephemeral RUI state. Both are deliberately absent from `MarkdownSnapshotV1`,
focus tokens, and the future public Browser Session contract. Full Preview
temporarily replaces the split layout without discarding the private split
preference; returning to Raw or Block restores the two-pane view without
another semantic read.

Accepted Raw and Block input keeps each mounted textarea node stable across
renders. A rejected controlled edit also keeps that node: after rendering the
unchanged accepted model, the imperative shell restores the accepted value
through `dom-boundary` and reapplies any required focus/text cursor. Rejection
does not use a rendering epoch, keyed relocation, or remove/add remount to
repair a live DOM value that diverged from the accepted document.

The divider uses RUI's `resizable_panel_group_with_input`, which keeps pointer
capture, touch cancellation, keyboard nudges, clamped percentage sizes, and
separator ARIA values inside RUI while allowing the panels to observe Loomark's
incremental document model. Loomark owns only Pane composition and the pure
viewport-width decision in `internal/rabbita/split_view.mbt`. At 640 CSS pixels
and above the panes are side by side; below that breakpoint the same editor and
Preview stack vertically. Crossing the breakpoint preserves the live text
input node, focus, and text cursor. RUI supplies the one-pixel divider and its
wider invisible hit area on both axes.

Out of this increment are recursive Pane trees, a second editable Pane, layout
persistence, scroll/selection synchronization, and public lifecycle changes.
Warren is canonical for Loomark standalone development preview
(`warren dev --direct`) and release builds (`warren build`). It does not own
runtime Pane state or replace the private deterministic Vanilla/Playwright
diagnostic contract provided by `dev_host`. The standalone page is the current
production entry point, while `dev_host` provides additional driver controls
and failure-injection test seams.

### Canonical Session, adapters, and Waku (future embedding work)

1. #1076 and #1077 preserve composition/non-BMP and focus/selection/navigation behavior through the internal Session and standalone browser boundary. They do not wait for #1072. Their future teardown and post-unmount conformance rows remain deferred until an embeddable Session exists.
2. #1072 starts only after Rabbita #141. It adopts a compatible Rabbita identity, replaces any superseded private mount adapter, exposes the exact Browser App/Session contract for embedding only, and adds declarations, artifact checks, lifecycle tests, release payload, CI fan-out, and `loomark-hosts`. It must reuse the standalone application without changing standalone behavior.
3. After #1072, #1078 and #1079 make thin React and Vue adapters: one empty connected host with Rabbita-exclusive descendants, unchanged generated types, callback update through `updateOptions`, one `unmount`, no initial-snapshot watcher/remount, and no Markdown behavior. React tests cover failed mount, callback replacement, refs, Strict Mode, and cleanup/reuse. Vue tests cover component/composable mount, emitted errors/events, reactive callbacks, exposed operations, and cleanup/reuse.
4. #1080, after #1072, #1076, #1077, and the explicit #834 prototype decision, atomically loads Loomark in Waku, maps dispose to `unmount`, migrates snapshot/focus carriage, removes the TypeScript app, BlockInput, Preview/sentinels, and live legacy FFI callers, and runs every Waku row. `GO`/`NARROW` implements only the accepted stabilization invariant; `NO-GO` adds no stabilization state. No dual route, feature flag, or mixed DOM ownership remains.

## Per-ticket requirements and Existing API First

Each ticket names package/file ownership, In/Out, behavioral matrix (syntax form, terminator where relevant, operation, lifecycle/ownership, success/error/event order, authority), first failing test, generated-artifact impact, exact native dependency identity, validation, and deferred cases. Browser tickets additionally specify host scope, reentrancy, the lifecycle guarantees they do and do not claim, and the error channel.

Before new APIs, search/report at least two candidates. Reuse lang/markdown/companion (new_markdown_editor, apply_markdown_edit, export_markdown_text), lang/markdown/edits/proj; SyncEditor/protocol.ViewPatch behind façade only; Loom typed values; Rabbita Cmd/Sub after-render/unload; modules/dom-boundary targets/errors/focus/subscription; ffi/jsx session/error patterns; concrete Option/Result, String/StringView, Array/ArrayView, Map/Set, and builders. Reject public raw SyncEditor, TreeEditorState, projection collections, generic traits, direct Rabbita App.mount lifecycle, and legacy FFI JSON/handles. New helpers only lower façade commands, construct pure transitions, or adapt typed browser/FFI codecs. Justify remaining imperative code.

## Validation

Targeted RED-to-green:

    NEW_MOON_MOD=0 moon check <affected-package-path>
    NEW_MOON_MOD=0 moon test -p <affected-package>

#1103 adds, and #1073–#1075 reuse, this exact pre-#141 validation entry point for the private dev host:

    ./scripts/test-loomark-dev-host-e2e.sh

#1176 added standalone validation for the current production boundary:

    ./scripts/test-loomark-standalone-e2e.sh

This script validates Warren-based standalone development (`warren dev --direct`), release builds (`warren build`), and production Playwright tests. It ensures private dev host controls are excluded from the release bundle.

The wrapper runs these commands in order and forwards optional Playwright selectors after `--` to the final command:

    NEW_MOON_MOD=0 moon build --target js --release apps/loomark/internal/dev_host
    cd apps/loomark/examples/vanilla && npm ci
    npm run typecheck:dev-host
    npm run test:dev-host

`typecheck:dev-host` is `tsc --noEmit -p tsconfig.dev-host.json`; `test:dev-host` is `playwright test --config=playwright.dev-host.config.ts`. Every isolated test creates a fresh BrowserContext/page and fresh connected mount container. The suite asserts that no case clears, reuses, remounts, or transfers that container and reports no teardown, remount, or host-reuse evidence. The `loomark-dev-host` CI job executes the same wrapper in the pinned Playwright environment and is required by All Checks Passed.

After #1072 deletes the private entry point and exposes the canonical Session, run the generated public build and full host suite:

    ./scripts/build-js.sh

After artifact exists, run:

    cd apps/loomark/examples/vanilla && npm run typecheck && npm test
    cd apps/web && npm run typecheck
    cd apps/web && npm run test:boundaries
    cd apps/web && npm run test:foundation
    cd apps/web && npm run build:waku
    cd apps/web && npm run test:waku:e2e

On a clean candidate HEAD, run the focused validation above and inspect every generated `.mbti` diff. Fetch `origin/main`, sync if the base moved, then push normally so Lefthook validates affected packages. GitHub CI's `All Checks Passed` job remains the exact-commit merge gate.

## Acceptance criteria

- [x] #1176 delivers standalone Loomark as the production boundary via `apps/loomark/main`, served by Warren for development (`warren dev --direct`) and release builds (`warren build`).
- [ ] Loomark has this extraction-ready layout and Canopy never imports it.
- [x] #1103 and #1073–#1075 delivered application behavior through the private host without publishing a provisional Session.
- [ ] After #141, #1072 replaces any superseded private mount adapter without editor/core behavior changes and makes the full #1064 embedding contract observable through stated tests.
- [ ] One generated Loomark runtime/declaration contract serves all embedding hosts.
- [x] Foundation and #1073→#1074→#1075 stayed serial; only embedding lifecycle and adoption work wait for #141.
- [ ] After the explicit #834 decision, Waku cutover is atomic, removes legacy ownership, passes Waku gates, and records rollback evidence.

## Rollback and deferred work

Rollback deploys the recorded prior complete artifact/commit and release command, never a flag, bundled legacy route, partial rollback, or mixed ownership. Old builds may reject new transient snapshot versions; canonical source remains recoverable and incompatible snapshots never mutate state.

Deferred until Rabbita #141 (future embedding-only work): public embeddable Browser Session (`MarkdownApp`/`MarkdownSession`), disposal/remount/host reuse, React/Vue adapters, and Waku cutover. Standalone Loomark is already the current production boundary (#1176); these deferred items gate embedding in external hosts, not standalone completion or daily-writing validation. Otherwise deferred: npm/public-package release policy, detached/Shadow DOM mounting, public theming/renderers, unsupported moves/containers, rich inline editing, diagnostics presentation/model, broader Unicode work, and cross-version transient selection/focus/mode restoration.
