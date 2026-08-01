# Loomark application handoff

Status: staged handoff — application behavior is gated by adoption of merged Rabbita #142, Canopy #1045, and the Foundation through #1103. The canonical public Browser App/Session, teardown/remount claims, production adapters, and Waku cutover remain additionally gated by Rabbita #141. This is the sole implementation plan for the accepted #1060, #1062–#1067, and #1070 decisions; the pure core prototype is evidence only.

## Why

The current Waku Markdown feature owns behavior in TypeScript and a low-level global-handle FFI. Loomark replaces it with one standalone MoonBit module and one Browser App/Session seam. Before Rabbita exposes mount-specific teardown, a private single-mount development host may exercise the same application behavior in a disposable page/process. It may not claim reusable host ownership, disposal safety, or the public Session contract.

## Scope

In:

- editor/markdown typed atomic Canopy façade; loomark core, browser, private Rabbita view, one FFI root, hosts/adapters; generic dom-boundary selection/measurement.
- moon.work, build/release/CI artifact fan-out; later atomic Waku cutover.

Out:

- Public Browser Session, production adapters, or Waku work before their gates; npm/semver/publishing; raw DOM or JS public API; renderer/theming hooks; generic capability traits; legacy compatibility.
- New syntax/recovery semantics, rich inline editing, unsupported moves, Markdown diagnostic model, and React/Vue work during #1073–#1075.

## Current state and ownership

examples/web/src/features/markdown/browser/app.ts is migration evidence only: it owns mode, toolbar, Raw sync, BlockInput, Preview, focus, listeners, frames, handles, and cleanup. examples/web/src/shared/route-lifecycle/browser/imperative-session.ts remains Waku’s generic defensive snapshot/focus/idempotent-dispose seam and maps its dispose to the canonical unmount at cutover. ffi/markdown/markdown_ffi.mbt global handles/string commands/JSON ViewPatch path is replaced, never wrapped. ffi/jsx/session.mbt and ffi/jsx/apply_patches.mbt are only precedents for session-private ownership, atomic initial publication, structured errors, and JS exception quarantine.

    Loom parser / recovered CST / diagnostics / Markdown semantics
                                  ↓
    Canopy editor/markdown façade / projection / SourceMap / edit lowering
                                  ↓
                   dowdiness/loomark/core (pure reducer)
                             ↓                 ↓
         loomark/internal/rabbita      loomark/browser
                             \                 /
                        loomark/ffi (one JS link root)
                                  ↓
                  Vanilla → React/Vue/Waku adapters

| Boundary | Owns | Must not own |
| --- | --- | --- |
| Loom | parser, recovered CST, diagnostics, Markdown semantics | UI, DOM, host lifecycle |
| Canopy editor/markdown | document/projection access, source map, edit lowering, atomic source commit | browser state, callbacks, DOM |
| Loomark core | deterministic state, mode/toolbar/focus decisions, proposed transition | editor/source copy, DOM, Cmd/Sub, clock/random/framework state |
| Loomark browser | serialization, editor transaction, snapshots, tokens, effects/errors; canonical mount ownership only after #141 | Markdown renderer or provisional public lifecycle |
| private Rabbita | only mounted editor DOM, Raw/Block/Preview, Cmd/Sub/capability wiring; pre-#141 disposable mount adapter | Browser Session or framework |
| hosts | lifecycle/callback forwarding and token/snapshot carriage | Markdown logic or editor state |

Canopy never imports Loomark. The application transaction runs identically in the private development host and the later Browser Session: validate; pure-reduce; atomically commit canonical source through editor/markdown; install proposed state; emit ordered committed facts. Any editor failure discards proposal, preserves source/projection, emits no change, and reports its categorized error. Raw input and snapshot restore obey this same transaction.

## Physical layout and delivery paths

The provisional application/markdown and canopy-markdown-application names are superseded:

    editor/markdown/                         # dowdiness/canopy/editor/markdown
    loomark/
      moon.mod                               # name = "dowdiness/loomark"
      core/                                  # dowdiness/loomark/core
      browser/                               # dowdiness/loomark/browser
      internal/rabbita/                      # private
      internal/dev_host/                     # temporary private JS link root; #1103–#1075 only
      ffi/                                   # sole public JS link root; added by #1072
      adapters/react/                        # @dowdiness/loomark-react, unpublished
      adapters/vue/                          # @dowdiness/loomark-vue, unpublished
      examples/{vanilla,react,vue}/

Add only ./loomark to moon.work. Its manifest imports public Canopy façade, selected Rabbita identity, dowdiness/dom_boundary, dowdiness/js_ffi, and used Rabbita modules. Core imports neither Rabbita, DOM, JS FFI, framework, clock, nor host state. Before #1103, reconcile one selected Rabbita identity containing #142 with the existing CodeMirror, tabs, status, menu, and resizable module declarations. Before #1072, move that same identity to a release containing #141 without creating incompatible workspace versions. A submodule change follows the repository's upstream-PR/push-first stop rule.

The sole public generated runtime/declaration contract is:

    _build/js/release/build/dowdiness/loomark/ffi/ffi.js
    _build/js/release/build/dowdiness/loomark/ffi/ffi.d.ts
    _build/js/release/build/dowdiness/loomark/ffi/moonbit.d.ts

Add all three paths to scripts/build-js.sh, its Bash-3 fake-compiler fixture in scripts/test-pr-ready-bash32.sh, and the explicit build-js upload list in .github/workflows/ci.yml. All hosts consume this one runtime and generated types, never beside canopy/ffi/markdown/markdown.js. Later Waku cutover alone updates examples/web/moonbit-artifacts.mjs, examples/web/tsconfig.json, src/shared/browser/moonbit-client-probe.tsx, waku-tests/foundation.spec.ts, MODULE_MAP.md, Waku artifact verification, and bundle checks. scripts/package-release.sh later makes separate loomark-browser-version.tar.gz containing Loomark artifacts, manifest, README, and notices, not the legacy Markdown payload. Add a Node-24 loomark-hosts job to All Checks Passed; path filters include loomark, editor/markdown, dom-boundary, Rabbita pointer, build and CI files.

Before #141, `loomark/internal/dev_host` is the only temporary JS link root. It produces `_build/js/release/build/dowdiness/loomark/internal/dev_host/dev_host.js` solely for the disposable test page. It is never added to `scripts/build-js.sh`, CI artifact uploads, release payloads, host declarations, or production examples. #1103 adds `scripts/test-loomark-dev-host-e2e.sh`, which builds that package and runs the exact private Vanilla typecheck/browser commands below. It also adds a path-filtered `loomark-dev-host` Playwright job to All Checks Passed. #1072 deletes the private package, wrapper, and job while adding the public `loomark/ffi` artifact and `loomark-hosts` job; the two link roots never coexist in a candidate commit.

## Pre-#141 private development host

#1103 creates one package-private adapter, the temporary `loomark/internal/dev_host` link root, and one disposable Vanilla test page for application development. The adapter mounts exactly once into a fresh connected container. The browser page or test process owns lifetime termination; the container is never cleared, reused, remounted, or transferred. Tests create a fresh Playwright page and BrowserContext per isolated case. This bounded test-only lifetime is not a cleanup implementation and is not permitted in Waku, React, Vue, examples presented as production hosts, or the generated public declaration.

The development host may expose only test-driver operations needed to submit typed application events, inspect detached snapshots/errors, and assert rendered behavior. It exposes no `MarkdownApp`, `MarkdownSession`, `unmount`, raw Rabbita value, DOM handle, global handle registry, or success result implying cleanup. It uses the same pure reducer, editor transaction, event ordering, focus decisions, and private Rabbita view that the canonical Session will use. Fatal errors stop further driver operations but do not claim that Rabbita subscriptions or callbacks were released.

This is an internal seam, not a generic lifecycle trait. After Rabbita #141 is available, #1072 replaces the mount-once adapter's sole ownership site with the mount-specific `MountedApp` returned by Rabbita, delegates teardown to `MountedApp::unmount`, and exposes the generated contract below. The migration must leave Loomark core, editor/markdown commands, edit lowering, snapshots, application events, and rendered state unchanged. #1072 then adds disposal, repeated-unmount, host-reuse, fatal-cleanup, reentrancy, and remount tests before deleting the provisional adapter and its test-only entry point. No compatibility layer or dual DOM owner remains.

## Canonical Browser App/Session contract matrix

The generated declaration is the refined #1064 contract below. It is first exposed by #1072 after Rabbita #141; #1103 and #1073–#1075 may not publish a subset or provisional substitute. These names and shapes are exact; implementation tickets may not substitute a factory, optional error channel, removable error handler, raw handle, or different status vocabulary.

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

Focus tokens are opaque logical locators, not DOM/session identity. Their private versioned payload contains only a closed control kind, or supported block semantic kind plus exact Canopy source range. A compatible later session resolves exactly one rendered/focusable target; never selector/DOM id/raw JS/editor handle/source copy/neighbour fallback. Hosts may carry captured values but may not parse or synthesize them.

## Behavior-to-authority links

| Behavior | Current evidence / gap | Final authority |
| --- | --- | --- |
| SSR inert controls/runtime-load error | examples/web/waku-tests/markdown-route.spec.ts | Waku route |
| mode navigation/Raw-Block round trip | examples/web/tests/markdown-editor.spec.ts | private host + core, then Waku Playwright |
| caret/block fallback and snapshot/focus decisions | existing Markdown/Waku tests | private host + core, then Browser Session |
| route cleanup, teardown, remount, host reuse | existing Waku tests; unavailable through Rabbita today | #1072 Browser Session + Waku lifecycle |
| heading identity, markers, fences | lang/markdown/proj/proj_node_wbtest.mbt and editor suite | projection/editor + Waku scenario |
| UTF-16/non-BMP | editor text-diff, sync-editor, word-nav tests | editor + new browser caret/split |
| supported/rejected MoveBlock | lang/markdown/edits/compute_markdown_edit_wbtest.mbt | edit + approved Waku subset |
| IME final commit, version/errors/reentrancy | absent | #1076 core + Vanilla contract |
| mount ownership/full remount | absent | #1072 Vanilla contract; Waku cutover subset |
| selection/measurement/listener | lib/dom-boundary additions | boundary; Rabbita wiring only |
| React/Vue | absent | lifecycle tests plus real-binding smoke |

## Ordered graph

### Application behavior gates

1. #1068's canonical plan and tracker transaction merge; concrete native edges are verified before its temporary blocker is removed.
2. The selected Rabbita identity includes merged #142 `update_tagger`; direct `diff_subs` plus `every` and `on_resize` regressions stay green. The recorded 0.13.0 identity does not yet satisfy this gate.
3. Canopy #1045 lands with one accepted nested-heading policy and incremental-versus-fresh parity.
4. The Foundation completes through #1103.

Rabbita #141 is intentionally not an Application Train gate. It remains the native gate for the canonical public Browser App/Session, lifecycle claims, production adapters, and Waku cutover.

### Foundation

1. #1102 adds the opaque editor/markdown façade over existing companion/edit/projection/SyncEditor internals and creates the standalone Loomark module/core skeleton.
2. #1071 implements the accepted generic UTF-16 text-control selection and measurement capabilities in lib/dom-boundary with boundary tests.
3. #1103, after adopting a selected Rabbita identity containing #142, creates Loomark's private Rabbita application, read-only Preview, mount-once development adapter, temporary `internal/dev_host` link root, disposable Vanilla browser harness, shared `test-loomark-dev-host-e2e.sh` command, and `loomark-dev-host` CI job. It adds no public Browser App/Session declaration or lifecycle claim.

### Application Train

1. #1073: Raw and Preview editing through the shared application transaction and private development host; no Block editing or public Browser Session.
2. #1074 only after green committed #1073 and #1045: paragraphs and ATX/Setext headings, supported split/merge, accepted heading policy.
3. #1075 only after green committed #1074: ordered/unordered lists and fenced code. Defer unsupported moves/containers, rich inline, diagnostics UI, adapters, Waku.

Each ticket begins with behavioral matrix and first RED test, makes one logical commit, and reruns affected evidence after commit/amend/rebase, manifest/generated-interface change, or base movement.

### Canonical Session, adapters, and Waku

1. #1072 starts only after the #1068 transaction, green #1075, and Rabbita #141. It adopts one Rabbita identity containing both #141 and #142, replaces the private mount-once adapter as described above, deletes `internal/dev_host` and its wrapper/job, exposes the exact generated Browser App/Session contract, and adds declarations, artifact checks, the full Vanilla lifecycle/contract/browser suite, release payload, CI fan-out, and `loomark-hosts`.
2. After #1072 is green, #1076 and #1077 preserve composition/non-BMP and focus/selection/navigation behavior, including their teardown and post-unmount rows, through the canonical Session.
3. Also after #1072, #1078 and #1079 make thin React and Vue adapters: one empty connected host with Rabbita-exclusive descendants, unchanged generated types, callback update through `updateOptions`, one `unmount`, no initial-snapshot watcher/remount, and no Markdown behavior. React tests cover failed mount, callback replacement, refs, Strict Mode, and cleanup/reuse. Vue tests cover component/composable mount, emitted errors/events, reactive callbacks, exposed operations, and cleanup/reuse.
4. #1080, after #1076, #1077, and the explicit #834 prototype decision, atomically loads Loomark in Waku, maps dispose to `unmount`, migrates snapshot/focus carriage, removes TypeScript app, BlockInput, Preview/sentinels and live legacy FFI callers, and runs every Waku row. `GO`/`NARROW` implements only the accepted stabilization invariant; `NO-GO` adds no stabilization state. No dual route, feature flag, or mixed DOM ownership remains.

## Per-ticket requirements and Existing API First

Each ticket names package/file ownership, In/Out, behavioral matrix (syntax form, terminator where relevant, operation, lifecycle/ownership, success/error/event order, authority), first failing test, generated-artifact impact, exact native dependency identity, validation, and deferred cases. Browser tickets additionally specify host scope, reentrancy, the lifecycle guarantees they do and do not claim, and the error channel.

Before new APIs, search/report at least two candidates. Reuse lang/markdown/companion (new_markdown_editor, apply_markdown_edit, export_markdown_text), lang/markdown/edits/proj; SyncEditor/protocol.ViewPatch behind façade only; Loom typed values; Rabbita Cmd/Sub after-render/unload; lib/dom-boundary targets/errors/focus/subscription; ffi/jsx session/error patterns; concrete Option/Result, String/StringView, Array/ArrayView, Map/Set, and builders. Reject public raw SyncEditor, TreeEditorState, projection collections, generic traits, direct Rabbita App.mount lifecycle, and legacy FFI JSON/handles. New helpers only lower façade commands, construct pure transitions, or adapt typed browser/FFI codecs. Justify remaining imperative code.

## Validation

Targeted RED-to-green:

    NEW_MOON_MOD=0 moon check <affected-package-path>
    NEW_MOON_MOD=0 moon test -p <affected-package>

#1103 adds, and #1073–#1075 reuse, this exact pre-#141 validation entry point:

    ./scripts/test-loomark-dev-host-e2e.sh

The wrapper runs these commands in order and forwards optional Playwright selectors after `--` to the final command:

    NEW_MOON_MOD=0 moon build --target js --release loomark/internal/dev_host
    cd loomark/examples/vanilla && npm ci
    npm run typecheck:dev-host
    npm run test:dev-host

`typecheck:dev-host` is `tsc --noEmit -p tsconfig.dev-host.json`; `test:dev-host` is `playwright test --config=playwright.dev-host.config.ts`. Every isolated test creates a fresh BrowserContext/page and fresh connected mount container. The suite asserts that no case clears, reuses, remounts, or transfers that container and reports no teardown, remount, or host-reuse evidence. The `loomark-dev-host` CI job executes the same wrapper in the pinned Playwright environment and is required by All Checks Passed.

After #1072 deletes the private entry point and exposes the canonical Session, run the generated public build and full host suite:

    ./scripts/build-js.sh

After artifact exists, run:

    cd loomark/examples/vanilla && npm run typecheck && npm test
    cd examples/web && npm run typecheck
    cd examples/web && npm run test:boundaries
    cd examples/web && npm run test:foundation
    cd examples/web && npm run build:waku
    cd examples/web && npm run test:waku:e2e

On clean candidate HEAD: moon fmt, moon info, inspect generated mbti diff, moon check, moon test, then scripts/validate-pr-ready.sh with each affected target. Fetch origin/main first; repeat after base movement; end with scripts/validate-pr-ready.sh --verify-evidence.

## Acceptance criteria

- [ ] Loomark has this extraction-ready layout and Canopy never imports it.
- [ ] #1103 and #1073–#1075 deliver application behavior without a provisional public Session or production host.
- [ ] After #141, #1072 replaces the private mount-once adapter without editor/core behavior changes and makes the full #1064 contract observable through stated tests.
- [ ] One generated Loomark runtime/declaration contract serves all hosts.
- [ ] Foundation and #1073→#1074→#1075 stay serial; only canonical lifecycle and adoption work wait for #141.
- [ ] After the explicit #834 decision, Waku cutover is atomic, removes legacy ownership, passes Waku gates, and records rollback evidence.

## Rollback and deferred work

Rollback deploys the recorded prior complete artifact/commit and release command, never a flag, bundled legacy route, partial rollback, or mixed ownership. Old builds may reject new transient snapshot versions; canonical source remains recoverable and incompatible snapshots never mutate state.

Deferred until Rabbita #141: public Browser App/Session, disposal/remount/host reuse, React/Vue adapters, and Waku cutover. Otherwise deferred: npm/public-package release policy, detached/Shadow DOM mounting, public theming/renderers, unsupported moves/containers, rich inline editing, diagnostics presentation/model, broader Unicode work, and cross-version transient selection/focus/mode restoration.
