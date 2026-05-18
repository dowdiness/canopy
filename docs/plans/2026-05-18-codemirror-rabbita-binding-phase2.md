# Phase 2 Plan — CodeMirror–Rabbita binding migration (rev 3)

Companion to `2026-05-18-codemirror-rabbita-binding-phase1-audit.md`. This is
**revision 3** after reading rabbita's own docs and bindings
(`rabbita/rabbita/websocket/`, `rabbita/rabbita/http/`, `rabbita/doc/*`,
`rabbita/rabbita/sub/design.md`, `rabbita/skills/rabbita.md`). The original
spec referenced `rabbita_xterm`'s `State/Action/Event/update/subscriptions/view`
shape; the rabbita ecosystem's own conventions are different and simpler. See
*Revision history* for the full diff.

## Confirmed decisions

| Item | Choice |
|---|---|
| Rabbita upgrade (blocker A) | **Done.** `examples/ideal` on `moonbit-community/rabbita 0.12.2`. |
| Binding location (blocker B) | **Done.** `lib/rabbita_codemirror/` workspace member. |
| Rabbita `diff_subs` patch (P2.0) | **Done.** Fork at `dowdiness/rabbita`, branch `patch/diff-subs-update-tagger` at `1cf3dab`, vendored via submodule + path dep in `examples/ideal/moon.mod.json`. |
| Q1 Doc ownership | **(b)** — but reinterpreted: the consumer's Model owns the doc (cached); the binding holds only the live CM6 view state. No binding-side `State.doc` field. |
| Q2 Action granularity | **(b)** Semantic: `set_doc` / `insert` / `replace` / `set_selection` as `Cmd`-returning functions. |
| Q3 Extension model | **(b)** Typed payload wrappers per family in `addon/`. Private `Compartment` per family lives inside the binding's internal `CmEntry`. `Compartment` never appears in any public `.mbti`. |
| Q4 Event surface | **(b)** Narrow: `listen(id, doc?, selection?, focus?) -> Sub`. |
| Q5 Language packages | In scope, deferred — `raw_extension(@js.Value) -> Extension` is the plug-in point. |
| Q6 Module pinning | Not pinning. `mount` carries a `source~ : String` default. |

## Architecture overview

```
+-----------------------------------------------------------------+
| examples/ideal/main (consumer)                                  |
|   - canopy CRDT (SyncEditor) is THE source of truth             |
|   - Model holds: cm_id : String, plus whatever the app caches   |
|   - consumes CmDocChanged(text) → applies to CRDT →             |
|     dispatches @cm.set_doc(cm_id, canonical) if it diverged     |
+-----------------------------------------------------------------+
                              ▲     │
                Sub events    │     │  Cmds (function-based API)
                              │     ▼
+-----------------------------------------------------------------+
| lib/rabbita_codemirror (public API)                             |
|   - pub fn mount/unmount/set_doc/insert/replace/set_selection   |
|     /set_theme/set_readonly/set_keymap/set_line_numbers         |
|     /set_line_wrapping → Cmd                                    |
|   - pub fn listen(id, doc?, selection?, focus?) → Sub           |
|   - priv let editors : Map[String, CmEntry]    (mutable, hidden)|
|   - priv struct CmEntry holds: view, theme_comp, readonly_comp, |
|     keymap_comp, line_numbers_comp, line_wrapping_comp          |
|   - priv suberror CmSubscription { CmListen(...) }              |
|   - priv fn cm_sub_loader using update_tagger pattern           |
|   - NO State / Action / Event public types                      |
|   - NO extern "js" declarations                                 |
+-----------------------------------------------------------------+
                              │     ▲
                              ▼     │
+-----------------------------------------------------------------+
| lib/rabbita_codemirror/js (FFI layer)                           |
|   - extern "js" only                                            |
|   - Opaque newtypes: CmView, CmState, Transaction, Compartment, |
|     Extension                                                   |
|   - async load_codemirror(source~ : String) -> @js.Promise      |
|   - pub fn raw_extension(@js.Value) -> Extension  (Q5 plug-in)  |
|   - js_dispatch wraps view.dispatch synchronously with the      |
|     applying ref-cell set/cleared in a JS try/finally           |
|   - js_add_update_listener consults the applying flag, skips    |
|     emission while it's true (Codex #2 fix; pure JS-side)       |
+-----------------------------------------------------------------+
                              ▲     │
                              │     ▼
                         @codemirror/* (ESM)
```

```
+-----------------------------------------------------------------+
| lib/rabbita_codemirror/addon/{theme,readonly,keymap,            |
|                               line_numbers,line_wrapping}/      |
|   - each defines its typed payload (Theme, Keymap, Bool, …)     |
|   - each exposes a Extension converter the root package uses    |
|     at mount time and on reconfigure                            |
|   - addons import only `js/`; root imports addons               |
|   - NO Compartment in any addon `.mbti`                         |
+-----------------------------------------------------------------+
```

### Why function-based (not State/Action/Event)

Every other binding in `rabbita/rabbita/*` (websocket, http, clipboard,
dialog) follows the function-based pattern. The skill explicitly forbids
storing Cmd/Msg/callbacks in the Model. The function-based API holds zero
Cmd/Msg/callbacks in the consumer's Model — the consumer's Model holds just
a `String` id. All state lives either in the consumer's existing structures
(CRDT, etc.) or in the binding's private `editors` registry.

The original spec described a State/Action/Event layer modeled on
`rabbita_xterm`; that pattern is at odds with rabbita's own current
conventions. We follow the conventions over the spec literal.

### Echo guard (Codex #2): JS-side, synchronous

The `applying` flag is a per-view mutable JS ref-cell. The FFI's
`js_dispatch(view, spec)` wraps the CM6 dispatch like:

```js
applying.value = true;
try { view.dispatch(spec) } finally { applying.value = false }
```

Since CM6's updateListener fires synchronously inside `view.dispatch`, the
listener observes `applying = true` and skips emission for programmatic
mutations. No TEA state involved.

### Doc-ownership (Codex #3): consumer owns canonical text

The binding holds **no** `doc : String` field. CM6's `state.doc` is the
live source-of-truth on the JS side; the consumer's Model is the
source-of-truth on the MoonBit side. The binding shuttles between them.
On `Event::DocChanged(text)`:

1. Sub fires with whatever text CM6 reports.
2. Consumer's `update` accepts (CRDT normalize) → produces canonical.
3. Consumer dispatches `@cm.set_doc(id, canonical)` *only if* canonical
   differs from what was reported.
4. Binding's `set_doc` is a no-op when the requested text equals current
   CM6 `state.doc.toString()` (cheap string compare via FFI).

No divergence window: there's nothing in the binding to diverge from.

### Compartment hiding (Codex #5): inside `CmEntry`

Compartments live as named fields on the private `CmEntry` struct. Each
addon (`addon/theme`, etc.) exposes only its typed payload type (`Theme`,
`Keymap`, `Bool`) and an `to_extension()` converter. The root package
imports each addon, creates a Compartment per family in `CmEntry` at
mount time, and calls `compartment.reconfigure` from the addon's
`set_X(id, value)` function. No addon ever sees the Compartment newtype.
Verified at PR-merge time by grepping each addon's `.mbti`.

### Codex blocker resolution (revised count)

| Codex finding | Status |
|---|---|
| #1 PR-local constraint checks | Still in §"Sequencing & PRs" |
| #1 `Disposable` should not import `@cmd` | `Disposable(() -> Unit)` — unchanged |
| #2 echo guard unsound as TEA state | **Resolved** — JS-side ref-cell |
| #3 binding/CRDT divergence window | **Resolved by construction** — no binding-side `doc` |
| #4 `update_tagger` not called | **Done in P2.0** — patched in fork |
| #5 Compartment cross-package reconfigure | **Resolved by construction** — Compartments in root's `CmEntry`, addons expose only payload types |
| #6 typing latency | Still a measurement risk; microbench in P2.5 |
| #7 Action vs Cmd type mismatch | **Resolved by construction** — every op returns `Cmd` directly |
| #8a structural Msg variants kept | Restated in P2.5 |
| #8b Mounted handwave | **Resolved** — `mount` takes `on_mounted? : Cmd` arg, no separate suberror constructor |
| #8c addon import cycle | **Resolved** — addons depend on `js/` only; root depends on addons + `js/`; no cycle |
| #8d `init()` missing doc | **Resolved** — no `init()`; `mount(id, host_id, init_doc~ = "", ...)` carries it |

Five of the seven Codex blockers dissolve under the function-based pattern
because the pattern simply doesn't have the structures that contained the
bugs.

## Work units

### P2.0 — Patch Rabbita `diff_subs`

**Status: DONE.** Vendored via submodule fork at `dowdiness/rabbita`,
branch `patch/diff-subs-update-tagger`, SHA `1cf3dab`.
`examples/ideal/moon.mod.json` switched to path dep. Workspace-root
`moon test` 979/979 and `examples/ideal` 23/23 green. wbtest written;
execution deferred to P2.2 (where the binding's own integration test
exercises the same path end-to-end via `@sub.custom_sub` + a re-rendered
tagger).

### P2.1 — FFI layer (`lib/rabbita_codemirror/js/`)

**Scope.** All `extern "js"` for CM6. No Rabbita imports.

**Deliverables.**
- Opaque newtypes: `CmModule`, `CmView`, `TransactionSpec`, `Compartment`,
  `Extension`. Each as `struct T(@js.Value)`. `CmModule` wraps the loaded
  CM6 ES module namespace; the consumer threads it explicitly to every op
  that needs to reach into the module (`js_create_view`,
  `js_compartment_new`). No global "current module" — see Codex #2
  resolution below.
- `pub fn cm_module_of(value : @js.Value) -> CmModule` — wraps the value
  resolved from `load_codemirror`'s Promise.
- `Disposable(() -> Unit)` with `pub fn dispose(self)`.
- `extern "js" fn load_codemirror(source? : String = "https://esm.sh/codemirror@6") -> @js.Promise`
  (MoonBit 0.9.2 rejects `async` on `extern`; the JS arrow is async,
  matching `rabbita/rabbita/dom/clipboard.mbt:42`). Module loads are
  memoized per `source` in `slot.modules`; rejected imports are evicted
  from the cache so a transient CDN failure does not poison every later
  call (Codex #1 resolution).
- FFI primitives mirroring CM6's API: `js_create_view(cm, host_id,
  init_doc, extension)`, `js_dispatch` (synchronous, wraps in
  applying-flag try/finally), `js_view_destroy`, `js_state_doc`,
  `js_state_selection_main`, `js_compartment_new(cm)`,
  `js_compartment_of`, `js_compartment_reconfigure`,
  `js_extension_combine`. `js_create_view` stashes the module on the
  returned view's JS object as `view._cmModule` so the listener installer
  can read it back without a global lookup.
- Per-view applying flag: JS-internal ref-cell keyed by
  `Symbol.for("dowdiness.rabbita_codemirror")`'s `WeakMap<view, cell>`.
  Set/cleared synchronously by `js_dispatch_raw`'s try/finally and
  consulted by the update listener's `isApplying()` closure. No
  MoonBit-side wrappers — the flag never crosses the FFI boundary.
- Listener installers returning `Disposable`:
  `js_add_update_listener(view, on_doc, on_selection, on_focus_change) -> Disposable`.
  Single underlying CM6 updateListener fires the three callbacks based on
  what changed in `ViewUpdate`. Each callback is `(@js.Value) -> Unit` for
  doc / SelRange-ish payload / Bool. Skips when `applying` is true. Reads
  `cm` from `view._cmModule`, so multiple views loaded from different
  sources cannot cross-contaminate (Codex #2 resolution).
- `pub fn raw_extension(@js.Value) -> Extension` — Q5 plug-in escape hatch.

**Verification.**
- `.mbti` grep: no `@cmd`/`@rabbita`/`@sub` imports.
- `moon check`, `moon info` clean.

**Owner.** Codex implements; Claude reviews newtype completeness and
synchronous-applying invariant.

### P2.2 — Public API + internal registry + sub loader (`lib/rabbita_codemirror/`)

**Scope.** The public function-based API. Mirror websocket binding's
shape exactly. Pure MoonBit, no `extern "js"`.

**Deliverables.**

```moonbit
// types
pub struct SelRange { from : Int, to : Int }

// internal
priv struct CmEntry {
  view : @js_ffi.CmView
  theme_comp : @js_ffi.Compartment
  readonly_comp : @js_ffi.Compartment
  keymap_comp : @js_ffi.Compartment
  line_numbers_comp : @js_ffi.Compartment
  line_wrapping_comp : @js_ffi.Compartment
  update_disposable : @js_ffi.Disposable
}
priv let editors : Map[String, CmEntry] = {}

// lifecycle
pub fn mount(
  id : String,
  host_id : String,
  init_doc~ : String = "",
  source~ : String = "https://esm.sh/codemirror@6",
  initial_theme~ : @theme.Theme? = None,
  initial_readonly~ : Bool = false,
  initial_keymap~ : @keymap.Keymap? = None,
  initial_line_numbers~ : Bool = true,
  initial_line_wrapping~ : Bool = false,
  on_mounted? : @cmd.Cmd,
  failed? : @cmd.Emit[String],
) -> @cmd.Cmd

pub fn unmount(id : String, failed? : ...) -> @cmd.Cmd

// edits (Q2=b)
pub fn set_doc(id : String, doc : String, failed? : ...) -> @cmd.Cmd
pub fn insert(id : String, pos : Int, text : String, failed? : ...) -> @cmd.Cmd
pub fn replace(id : String, from : Int, to : Int, text : String, failed? : ...) -> @cmd.Cmd
pub fn set_selection(id : String, range : SelRange, failed? : ...) -> @cmd.Cmd

// addon ops (Q3=b)
pub fn set_theme(id : String, theme : @theme.Theme, failed? : ...) -> @cmd.Cmd
pub fn set_readonly(id : String, enabled : Bool, failed? : ...) -> @cmd.Cmd
pub fn set_keymap(id : String, keymap : @keymap.Keymap, failed? : ...) -> @cmd.Cmd
pub fn set_line_numbers(id : String, enabled : Bool, failed? : ...) -> @cmd.Cmd
pub fn set_line_wrapping(id : String, enabled : Bool, failed? : ...) -> @cmd.Cmd

// subscription (Q4=b)
priv suberror CmSubscription {
  CmListen(
    id : String,
    doc~ : @cmd.Emit[String]?,
    selection~ : @cmd.Emit[SelRange]?,
    focus~ : @cmd.Emit[Bool]?,
  )
}
priv fn cm_sub_loader(payload : Error, scheduler : &@cmd.Scheduler) -> @sub.RunningSub?
pub fn listen(
  id : String,
  doc? : @cmd.Emit[String],
  selection? : @cmd.Emit[SelRange],
  focus? : @cmd.Emit[Bool],
) -> @sub.Sub
```

**Invariants.**
- `editors` is mutable (one of two acceptable mutable-state cases in the
  skill: array literals in view, and binding-internal registries).
- `mount(id, ...)` replaces the entry at the same id (websocket pattern;
  old entry's view destroyed, old sub's resources cleaned).
- `set_doc(id, x)` is a no-op when `x == js_state_doc(entry.view)`.
- `listen(id, ...)` returns `@sub.none` if no tagger provided (matches
  websocket's "no-op guard").
- `cm_sub_loader` follows `rabbita/rabbita/websocket/listen.mbt` line-for-
  line at the structural level: `let mut doc_tagger = doc`, capturing
  closures, `update_tagger` rebinding all three taggers. **Requires P2.0
  patch (done).**

**Verification.**
- Workspace `moon check` + `moon test` clean.
- Integration test in `lib/rabbita_codemirror/`: simulate a re-render with
  a swapped tagger; assert new tagger receives events. This is the
  practical verification of P2.0's patch — if this passes, both P2.0 and
  the listen-loader work.

**Owner.** Codex implements; Claude reviews tagger rebind closure
semantics specifically.

### P2.3 — Addon payload types (`lib/rabbita_codemirror/addon/*`)

**Scope.** Five addons. Each is its own subpackage. Each imports only
`js/`. Each exports its typed payload type + `to_extension` + (for the
Compartment plumbing) `to_compartment_extension(compartment)` that
returns `compartment.of(extension)` for mount-time wrapping.

**Deliverables per addon.**

```moonbit
// addon/theme/
pub struct Theme(@js_ffi.Extension)
pub fn dark() -> Theme
pub fn light() -> Theme
pub fn custom(...) -> Theme
pub fn to_extension(Theme) -> @js_ffi.Extension
```

Similar for `readonly`, `keymap`, `line_numbers`, `line_wrapping`. The
root package P2.2 wires each addon into a Compartment slot at mount time.

**Q5 plug-in.** Language packages (Lambda, Markdown, JSON) will plug in
via the FFI's `raw_extension(@js.Value)` — they construct a CM6
language extension on the JS side and wrap it. No addon required for
plug-in to work; addons are only needed when reconfiguration is needed.

**Verification.** Per-addon `.mbti` grep: `Compartment` absent. Each
addon's `.mbti` shows exactly the payload type + `to_extension` and
maybe one or two factory constructors.

**Owner.** Codex implements; Claude reviews `.mbti` purity.

### P2.4 — Minimal example (`examples/codemirror_demo/`)

**Scope.** Standalone Rabbita app exercising the binding in isolation.

**Deliverables.**
- Single-file Rabbita app with one editor:
  - `mount` on `with_init`
  - `set_doc` button
  - `set_readonly` toggle (proves Compartment-backed reconfigure)
  - readout updated via `listen(... doc=emit(DocChanged))`
  - `unmount` button + verification that the editor's DOM is gone
- `package.json`, `index.html`, Vite config under
  `examples/codemirror_demo/web/`.
- README enumerating the five behaviors the spec verification asks for.

**Verification.**
- `moon build --target js --release` clean.
- Manual smoke test in browser:
  1. Editor mounts.
  2. Typing fires `DocChanged`; readout updates.
  3. "Set doc" button calls `set_doc` and CM6 contents reset.
  4. "Toggle readonly" flips in place — cursor preserved, no remount.
  5. "Unmount" removes the editor; rerunning "Mount" recreates it.
- Microbenchmark (deferred to P2.5 but scaffold in this PR): tracks
  per-keystroke `DocChanged → emit` latency, vs today's direct
  `handle_text_intent` call in `examples/ideal`.

**Owner.** Codex implements; Claude does the manual browser smoke test.

### P2.5 — Migrate `examples/ideal` to the binding (behind feature flag)

**Scope.** Replace `canopy-editor.ts`'s text-mode CM6 ownership.
Structure mode (PM) untouched. Behind `VITE_CANOPY_USE_CM_BINDING=1`.

**Deliverables.**

`examples/ideal/main/model.mbt`:
- `Model` gains `cm_id : String` (constant value `"canopy-text-editor"` is fine; one editor per app).
- Remove `EditorTextChanged`, `EditorNodeSelected`, `EditorStructuralEdit`.
- Add `CmDocChanged(String)`, `CmSelectionChanged(SelRange)`, optionally
  `CmFocusChanged(Bool)`.
- Keep `StructuralEditRequested` (structure-mode adjacent, per Codex #8a).

`examples/ideal/main/main.mbt`:
- `init_model` no longer touches CM6 directly; the CRDT initializes from
  `let init_text = ...`. The binding mount happens via `with_init`.
- `main()` adds `with_init(@cm.mount(model.cm_id, host_id="canopy-text-editor", init_doc=editor.get_text(), ...))`.
- New `subscriptions` callback returning
  `@cm.listen(model.cm_id, doc=t => emit(CmDocChanged(t)), selection=s => emit(CmSelectionChanged(s)))`.
- `update` handlers:
  - `Undo / Redo / LoadExample / OutlineStructuralEdit / structural success`:
    after CRDT mutation, return `@cm.set_doc(model.cm_id, crdt.get_text())` as the Cmd.
  - `CmDocChanged(text)`: route through `handle_text_intent_checked` to
    the CRDT; if `crdt.get_text() != text`, return
    `@cm.set_doc(model.cm_id, crdt.get_text())` to canonicalize.
  - `CmSelectionChanged(_)`: drive peer-cursor broadcast (moved from JS).

`examples/ideal/main/view_editor.mbt`:
- Replace the seven hidden trigger buttons with
  `div(id="canopy-text-editor", nothing)`. The binding's lifecycle Cmd
  mounts CM6 into that div.

`examples/ideal/main/bridge_ffi.mbt`:
- Delete 13 CM6-related FFIs (audit Sections A and B). Keep perf,
  viewport, outline-DOM, overlay-focus FFIs (those aren't binding-related).

`examples/ideal/web/src/canopy-editor.ts`:
- Delete `mountTextMode`, `destroyCm`, `syncCmFromCrdt`, both
  `updateListener` blocks, Mod-z/Mod-Shift-z keymap.
- Reduce to a host that exposes `<div id="canopy-text-editor">` plus the
  structure-mode session.

`examples/ideal/web/src/main.ts:wireEditorEvents`:
- Delete text-mode listener registrations.
- Keep structural/outline/overlay wiring.

**Compilation break points.**
- **B1.** Deleting `EditorTextChanged` breaks the hidden trigger in
  `view_editor.mbt`. Fix: delete the trigger in the same commit.
- **B2.** Deleting `js_reconcile_editor_with_text` breaks five sites.
  Fix: each becomes `@cm.set_doc(model.cm_id, text)` directly as the Cmd.
- **B3.** Deleting `mountTextMode` breaks `canopy-editor.ts` attribute
  handler. Fix: handler becomes a no-op; binding mounts into the div.

**Feature flag.** `VITE_CANOPY_USE_CM_BINDING=1` for one PR cycle. Both
paths coexist until the flag flips default.

**Verification.**
- `cd examples/ideal && moon test` — 23/23.
- `cd examples/ideal/web && npm run build` clean.
- `cd examples/ideal/web && npm run test:e2e` — Playwright passes.
- Manual: type / undo / redo / text↔structure / load example / two
  browsers / peer cursors.
- Microbenchmark: per-keystroke `CmDocChanged → emit → update` latency
  vs today's direct path. If p50 regresses >5ms on large docs, add
  animation-frame batching in the loader before the flag flips.

**Owner.** Codex implements per-file edits in batched PRs; Claude runs
Playwright + decides flag flip.

### P2.6 — Final verification

Per spec checklist:
- [ ] `moon check`, `moon fmt --check`, `moon info` clean
      (workspace-root and `examples/ideal`).
- [ ] `grep -n 'extern "js"' lib/rabbita_codemirror/*.mbt lib/rabbita_codemirror/addon/*/*.mbt`
      empty.
- [ ] `grep -n 'priv suberror' lib/rabbita_codemirror/*.mbt` shows
      exactly one (`CmSubscription`).
- [ ] `grep -n '@sub.custom_sub' lib/rabbita_codemirror/*.mbt` shows
      exactly one (`listen`).
- [ ] `grep -n 'Compartment' lib/rabbita_codemirror/addon/*/pkg.generated.mbti`
      empty.
- [ ] `examples/codemirror_demo/` builds + smoke tests pass.
- [ ] `pkg.generated.mbti` diffs reviewed.
- [ ] Plans + Q&A committed under `docs/plans/`.

**Owner.** Claude runs verification; Codex fixes whatever fails.

## Delegation plan

Per user directive: **Claude (Opus) = command center; Codex = implementation
+ difficult thinking + design validation.**

| Activity | Owner |
|---|---|
| Plan revision, decision routing, PR sequencing | Claude |
| Approval calls, flag-flip decisions, verification command runs | Claude |
| Memory/feedback maintenance, doc index updates | Claude |
| FFI surface (`lib/rabbita_codemirror/js/`) | Codex |
| Public API + sub loader (`lib/rabbita_codemirror/`) | Codex |
| Addon payload types | Codex |
| `examples/codemirror_demo/` | Codex |
| `examples/ideal` migration edits | Codex |
| Microbenchmark interpretation | Codex |
| Debugging unexpected test failures | Codex |
| Codex MCP review of each PR before merge | Codex |

**Codex artifacts contract (tightened from rev 2).** Codex returns:
(a) files created/modified, (b) **terminal pass/fail counts from each
verification command**, (c) **the exact final-line summary line of each
`moon test` run** (e.g. "Total tests: N, passed: N, failed: 0"), (d) any
deviation from the spec'd design with written justification. Claude
verifies (b) and (c) by re-running spot checks independently.

Tightening reason: Codex's P2.0 report claimed "Total tests: 7, passed: 7,
failed: 0. [native]" but independent re-run showed the build fails before
tests run. Future delegations must include the literal last line of test
output.

## Out of scope (this iteration)

- Typed language wrappers (Q5 deferred; `raw_extension` is the plug-in).
- `@codemirror/*` version pinning (Q6; `source~` arg is overridable).
- `Compartment` as public API.
- Collaboration / CRDT / OT in the binding.
- Structure mode (PM) rewrite — Web Component keeps PM session intact.
- A multi-editor demo. The internal `editors` registry supports it, but
  the example shows one editor.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Echo loop via stale TEA state | JS-side ref-cell, synchronous around `view.dispatch`. |
| Binding/CRDT divergence | Resolved by construction: no binding-side doc. |
| Tagger staleness | P2.0 patch (done); end-to-end verified by P2.2 integration test. |
| Compartment leakage | Per-addon `.mbti` grep at P2.3 merge. |
| Typing latency regression | Microbench in P2.4/P2.5. p50 budget >5ms triggers animation-frame batching in the loader. |
| Multi-editor id collision in `editors` map | `mount(id, ...)` replaces on collision (matches websocket binding behavior). |
| Structure-mode Msg variants accidentally deleted | P2.5 explicitly enumerates kept-vs-deleted; `StructuralEditRequested` stays. |
| Sub key churn (re-installing instead of rebinding) | `listen`'s key string encodes `id` only — not the tagger identities. Stable across re-renders. |

## Sequencing & PRs

| PR | Contains | PR-local constraint check | Reviewer focus |
|---|---|---|---|
| #0 | P2.0 (done) + plan docs + lib skeleton | n/a (committed locally) | submodule pointer, vendoring boundary |
| #1 | P2.1 FFI layer | grep `js/` has no Rabbita imports | synchronous applying invariant, listener installer shape |
| #2 | P2.2 public API + sub loader + integration test | grep no `extern "js"` outside `js/`; `priv suberror` count = 1; `@sub.custom_sub` count = 1 | tagger rebind closure correctness, `set_doc` no-op invariant |
| #3 | P2.3 addons | per-addon `.mbti` no `Compartment` | addon isolation |
| #4 | P2.4 minimal example | five-behavior checklist | demo correctness, manual smoke |
| #5 | P2.5 ideal migration (behind flag) | E2E parity, microbenchmark | no perf regression, flag default = off |
| #6 | flag flip + P2.6 cleanup | full §P2.6 verification | spec verification block green |

Each PR ends on `moon check && moon fmt && moon info && moon test` clean
across workspace-root and `examples/ideal`.

---

## Revision history

**rev 3.2 (2026-05-18)** — Post-P2.1 PR feedback. Acted on two of Codex's
review comments on #296 by reworking the loader / view-creation FFI:
(a) `load_codemirror`'s JS body now evicts a `source` entry from the
memoization map if its `import()` Promise rejects, so a transient CDN
failure no longer poisons every later call (#1); (b) introduce a
`CmModule` opaque newtype + `cm_module_of` helper and pass it
explicitly to `js_create_view(cm, …)` and `js_compartment_new(cm)`. The
view stashes the module on itself as `view._cmModule`, which the
listener installer reads back. Eliminates the previous `slot.current`
mutable global, which couldn't safely support views from different
sources (#2). Also migrates `examples/ideal` off `@rabbita.Dispatch[Msg]`
and `@rabbita_cmd.raw_effect` (deprecated in the rabbita commit the
submodule points at) to `Emit[Msg]` and `custom_cmd` respectively —
CI was failing on the deprecation cascade.

**rev 3.1 (2026-05-18)** — Post-P2.1 alignment. Pruned three over-specified
items from §P2.1 deliverables once the shipped FFI revealed them as dead:
(a) `CmState` and `Transaction` newtypes (never appear in any function
signature in the shipped `js/` — `TransactionSpec` is the only
transaction-shaped type the API needs, and `CmState` reads happen JS-side
inside the extern bodies); (b) MoonBit-side `js_view_set_applying` /
`js_view_is_applying` wrappers (the applying flag is JS-internal —
`js_dispatch_raw`'s try/finally and the listener installer's local
`isApplying()` closure already provide synchronous read/write inside JS,
so MoonBit wrappers would just be dead crossings of the FFI boundary);
(c) `async` on `extern "js" fn load_codemirror` (MoonBit 0.9.2 parser
rejects it — the async lives in the JS arrow). Source-of-truth precedence:
the shipped code in `lib/rabbita_codemirror/js/codemirror.mbt` is canonical;
this paragraph documents the diff for future readers of rev 3.

**rev 3 (2026-05-18)** — Pivot to function-based API after reading rabbita's
own docs/examples. Removed the entire State/Action/Event managed layer
(was P2.2 in rev 2). The binding's public surface is now `fn(id, …) ->
Cmd` + one `listen → Sub`, matching `rabbita/rabbita/websocket/`'s pattern
1:1. Five of seven Codex blockers dissolve under the new shape because the
structures that contained the bugs (State, Action, dispatch_action helper,
Mounted message routing) no longer exist. Work units compress: rev 2's
P2.2 + P2.3 + P2.4 collapse into rev 3's P2.2 (one PR). Total binding work
is roughly two-thirds the size of rev 2.

**rev 2 (2026-05-18)** — Incorporated Codex plan review (5 blockers).
JS-side echo guard, no `applying` in State, `dispatch_action` helper for
Action[Msg]→Cmd routing, etc.

**rev 1 (2026-05-18)** — Initial plan based on Phase 1 audit and Q1–Q6
answers.
