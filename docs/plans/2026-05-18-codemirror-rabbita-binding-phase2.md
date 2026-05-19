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
`moon test` 979/979 and `examples/ideal` 23/23 green. The patch ships
with its own whitebox test (`rabbita/tea_wbtest.mbt`) verifying
`diff_subs` calls `update_tagger` on preserved keys. End-to-end
verification at the binding level happens in P2.4's browser smoke
(swap-tagger step) since the binding cannot replicate the framework
test (see rev 3.3 in revision history).

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

### P2.2 — Public API + internal registry + sub loader (`lib/rabbita_codemirror/`) + typed-addon scaffolds

**Scope.** The public function-based API plus the typed-extension
scaffolds for the two addons that appear in the public API: `theme`
and `keymap`. Mirror websocket binding's shape exactly. Pure MoonBit
in `lib/rabbita_codemirror/` itself (no `extern "js"`); the typed
addons live in `lib/rabbita_codemirror/addon/theme/` and
`lib/rabbita_codemirror/addon/keymap/`, each importing only `js/`.

**Why typed addons here, not deferred to P2.3.** `mount`'s public
signature references `@theme.Theme` and `@keymap.Keymap`. Defining
those types in P2.2 keeps the API contract concrete from the first
public release rather than going through a stub→real type change.
P2.3 expands the addons by adding factory constructors (`Theme::dark()`,
etc.) and adds the typed Bool addons (`readonly`, `line_numbers`,
`line_wrapping`) if they end up needing typed plug-in surfaces beyond
the inline Bool params on `mount`/`set_*`. The scaffold-now-factories-
later split keeps each PR's review scope small (P2.2 is the registry
+ sub loader; the addon code in P2.2 is only 5-10 lines per addon and
trivially correctness-checked alongside its consumer).

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

**Addon scaffolds (in `lib/rabbita_codemirror/addon/theme/` and
`lib/rabbita_codemirror/addon/keymap/`):**

```moonbit
// addon/theme/theme.mbt
pub struct Theme(@js_ffi.Extension)
pub fn to_extension(self : Theme) -> @js_ffi.Extension { self.0 }
// No factories here — added in P2.3.

// addon/keymap/keymap.mbt
pub struct Keymap(@js_ffi.Extension)
pub fn to_extension(self : Keymap) -> @js_ffi.Extension { self.0 }
```

Construction in P2.2 happens externally: consumers (and the P2.4 demo)
build a `Theme` by wrapping an `@js_ffi.Extension` they got from
`@js_ffi.raw_extension(value)`. P2.3 adds `Theme::dark()`,
`Theme::light()`, `Theme::custom(...)`, and similar for `Keymap`.

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
- Addon scaffolds import **only** `lib/rabbita_codemirror/js/` —
  not `@cmd`, not `@sub`, not the main package. Each addon `.mbti`
  shows exactly: the newtype, `to_extension`, and no `Compartment`
  reference.

**Verification.**
- Workspace `moon check` + `moon test` clean.
- Grep-level structural mirror of `rabbita/rabbita/websocket/listen.mbt`:
  - `grep -c 'priv suberror' lib/rabbita_codemirror/codemirror.mbt` → 1
  - `grep -c '@sub.custom_sub' lib/rabbita_codemirror/codemirror.mbt` → 1
  - `grep -n 'let mut.*_tagger' lib/rabbita_codemirror/codemirror.mbt` → 3 lines (doc/selection/focus)
  - `grep -n 'update_tagger' lib/rabbita_codemirror/codemirror.mbt` → at least one occurrence inside `cm_sub_loader`
  - `grep -rn 'Compartment\|@cmd\|@sub' lib/rabbita_codemirror/addon/` → empty (addons only import `js/`)
- Claude code-reviews `cm_sub_loader` line-by-line against
  `rabbita/rabbita/websocket/listen.mbt` to confirm the rebind shape
  matches.
- **End-to-end verification of `update_tagger` deferred to P2.4** (see
  §P2.4 smoke step "swap tagger across re-render").

Why no integration test at this layer: an in-package test would have to
either (a) call `diff_subs` directly — but `diff_subs` is package-private
to `moonbit-community/rabbita` and not exposed via `@sub`, or
(b) call `cm_sub_loader` directly — but the loader body invokes
`js_add_update_listener` which requires a real `CmView` and DOM. The
P2.0 patch's own whitebox test (`rabbita/tea_wbtest.mbt`) already
verifies the `diff_subs` mechanism at the framework level; this
binding's job is to mirror the canonical pattern, and the mirror is
verified by structural grep + code review + browser smoke (§P2.4).

**Owner.** Codex implements; Claude reviews tagger rebind closure
semantics specifically.

### P2.3 — Addon factories + typed extensions (`lib/rabbita_codemirror/addon/*`)

**Scope.** Build on the scaffolds landed in P2.2:

1. Add factory constructors to the existing `addon/theme/` and
   `addon/keymap/` subpackages (`Theme::dark()`, `Theme::light()`,
   `Theme::custom(...)`, plus keymap equivalents).
2. **Re-evaluate** whether the three Bool-toggle addons (`readonly`,
   `line_numbers`, `line_wrapping`) need their own typed subpackages.
   Default position: **no** — they're consumed as `Bool` params in the
   main package's `mount`/`set_*` signatures, and the main package's
   implementation constructs the appropriate `@js_ffi.Extension`
   internally. Add subpackages only if a typed-extension surface is
   needed (e.g. composing with other addons, language-package plug-in
   that wants to override the default keymap behavior).

This is the Codex finding: the original "five addons, all symmetric"
framing overstated symmetry. Theme/keymap are typed extension wrappers
(part of the core public contract — every nontrivial editor sets them).
The other three are flag-shaped. Codex's framing: see `rev 3.4` history.

**Deliverables.**

```moonbit
// addon/theme/theme.mbt — augmented from P2.2 scaffold
pub fn dark() -> Theme
pub fn light() -> Theme
pub fn custom(extension : @js_ffi.Extension) -> Theme
// to_extension already shipped in P2.2

// addon/keymap/keymap.mbt — augmented from P2.2 scaffold
pub fn default_keymap() -> Keymap
pub fn vim() -> Keymap   // if reachable via the CM6 ecosystem
pub fn from_raw(extension : @js_ffi.Extension) -> Keymap
```

**Q5 plug-in.** Language packages (Lambda, Markdown, JSON) plug in via
the FFI's `raw_extension(@js.Value)` — they construct a CM6 language
extension on the JS side and wrap it. No addon required for plug-in;
addons are only needed when reconfiguration via Compartment is needed.

**Verification.** Per-addon `.mbti` grep: `Compartment` absent. Each
addon's `.mbti` shows the payload type + `to_extension` (shipped P2.2)
+ the new factory constructors.

**Owner.** Codex implements; Claude reviews `.mbti` purity.

### P2.4 — Minimal example (`examples/codemirror_demo/`)

**Scope.** Standalone Rabbita app exercising the binding in isolation.

**Deliverables.**
- Single-file Rabbita app with one editor:
  - `mount` on `with_init`
  - `set_doc` button
  - `set_readonly` toggle (proves Compartment-backed reconfigure)
  - readout updated via `listen(... doc=emit(DocChanged))`
  - "swap tagger" button: toggles between `DocChangedA(String)` and
    `DocChangedB(String)` as the variant the listen sub emits — the
    sub key stays constant so rabbita's `diff_subs` rebinds via
    `update_tagger` rather than re-installing the sub
  - `unmount` button + verification that the editor's DOM is gone
- `package.json`, `index.html`, Vite config under
  `examples/codemirror_demo/web/`.
- README enumerating the six behaviors the spec verification asks for.

**Verification.**
- `moon build --target js --release` clean.
- Manual smoke test in browser:
  1. Editor mounts.
  2. Typing fires `DocChanged`; readout updates.
  3. "Set doc" button calls `set_doc` and CM6 contents reset.
  4. "Toggle readonly" flips in place — cursor preserved, no remount.
  5. "Unmount" removes the editor; rerunning "Mount" recreates it.
  6. **Swap tagger across re-render** (verifies P2.0 + binding
     end-to-end). Demo exposes a "swap tagger" button that toggles which
     of two `DocChanged` variants the `listen` subscription dispatches.
     After clicking: type → readout shows the *new* variant's payload,
     not the old one. If this fails, either P2.0's patch regressed or
     the binding's `update_tagger` rebind is broken.
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
| Tagger staleness | P2.0 patch (done), framework-verified by `rabbita/tea_wbtest.mbt`; binding-level structural mirror checked at P2.2; end-to-end checked at P2.4 swap-tagger smoke step. |
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
| #2 | P2.2 public API + sub loader + theme/keymap scaffolds | grep no `extern "js"` outside `js/`; `priv suberror` count = 1; `@sub.custom_sub` count = 1; `let mut.*_tagger` count = 3; `Compartment`/`@cmd`/`@sub` absent under `addon/` | tagger rebind closure correctness vs websocket reference, `set_doc` no-op invariant, mount-replace semantics, addon `.mbti` purity |
| #3 | P2.3 addon factories + Bool addon decision | per-addon `.mbti` no `Compartment`; factory constructors land on theme/keymap | addon isolation, Bool-toggle subpackage necessity |
| #4 | P2.4 minimal example | six-behavior checklist (incl. swap-tagger) | demo correctness, manual smoke, P2.0 + binding end-to-end |
| #5 | P2.5 ideal migration (behind flag) | E2E parity, microbenchmark | no perf regression, flag default = off |
| #6 | flag flip + P2.6 cleanup | full §P2.6 verification | spec verification block green |

Each PR ends on `moon check && moon fmt && moon info && moon test` clean
across workspace-root and `examples/ideal`.

---

## Revision history

**rev 3.8 (2026-05-19)** — Post-P2.4 demo + P2.1.5 FFI fix. Codex
implemented `examples/codemirror_demo/` per the handoff
(`2026-05-19-codemirror-rabbita-binding-phase2-p24-codex-handoff.md`),
all six §P2.4 behaviors verified end-to-end including the
load-bearing swap-tagger step. Three Codex implementation
deviations + one Codex-review nit + one **P2.1.5 FFI bug**
surfaced by the live smoke (the whole purpose of P2.4 as the
binding's first end-to-end consumer).

**Codex implementation deviations (all justified):**
(a) `Model.read_only` instead of `readonly` — `readonly` is a
MoonBit reserved token and won't parse as a field name.
(b) `@cm.mount(model.cm_id, "cm-demo-host", ...)` with positional
`host_id` — the frozen `pkg.generated.mbti` declares
`pub fn mount(String, String, ...)` (two positional `String`
args, no `host_id~` label). The handoff doc's labelled-call
example was wrong; Codex's positional form matches the actual
binding signature.
(c) `cell_with_emit(...)..with_init(mount_cmd(emit, initial_model)).mount("app")`
with `#warnings("-alert_unstable")` instead of websocket's
`cell(...).mount("app")`. Reason: the demo auto-mounts the
editor at boot (§P2.4 behavior #1), which needs a `Cmd`
referencing `emit`, which only `cell_with_emit` exposes
ergonomically. Matches the `with_init` pattern in
`rabbita/examples/shiki_editor/main/client.mbt` (the canonical
editor-binding analog per the rabbita-skill table).

**Codex-review nit (fixed before browser smoke):**
The original `mount_cmd` did not pass `initial_readonly`, so
after toggling readonly → unmount → remount, the editor came
back editable while `model.read_only` was still `true`. Added
`initial_readonly=model.read_only,` to the `@cm.mount` call site
in `mount_cmd` so remount preserves readonly state.

**P2.1.5 FFI namespace-synthesis fix (bundled in this PR).**
Browser smoke's behavior #1 failed with `pageerror:
cm.Compartment is not a constructor`. Root cause:
`https://esm.sh/codemirror@6` (the binding's previous default
`source~`) is the CM6 *metapackage*, which re-exports only
`default` (the `basicSetup` bundle); it does NOT re-export
`Compartment`, `EditorView`, `EditorState`, `StateEffect`. The
FFI bodies in `lib/rabbita_codemirror/js/codemirror.mbt`
reference `cm.Compartment` (line 194), `cm.EditorView`,
`cm.EditorState` (lines 97, 99, 280), `cm.StateEffect` (line
280). The bug had never surfaced because the binding's first
end-to-end consumer is P2.4 (`examples/ideal` still owns CM6
directly via `canopy-editor.ts`; that migration is P2.5).
**Fix:** `load_codemirror` now `Promise.all`-loads
`@codemirror/state@6`, `@codemirror/view@6`,
`@codemirror/commands@6` from the `source~` base URL and merges
their namespaces with `{ ...state, ...view, ...commands }`. The
`source~` semantics change from "CM6 metapackage URL" to "CDN
base URL"; default flips from `"https://esm.sh/codemirror@6"`
to `"https://esm.sh"` on both `mount`'s default and
`load_codemirror`'s default. `CmModule`'s public API stays
identical — consumers see the same merged-namespace shape via
`cm.X` access in any future binding extensions (e.g. when the
deferred ecosystem factories `dark`/`vim`/`default_keymap` get
implemented, they can now reach `cm.EditorView.theme(...)` and
`cm.keymap.of(cm.defaultKeymap)` synchronously — though those
factories remain deferred until a forcing function demands
them; `Theme::custom(empty)` carried this demo end-to-end as
the rev-3.7 default position predicted).

**§P2.1 update.** Plan §P2.1's `load_codemirror` signature line
(default `"https://esm.sh/codemirror@6"`) is historical — the
actual shipped (post-P2.1.5) default is `"https://esm.sh"` and
the body is multi-load + merge. Future P2-doc readers should
treat §P2.1 as the original spec and this rev 3.8 entry as the
authoritative current state.

**Swap-tagger smoke result.** PASS. Pre-swap typing → readout
`"A: ... beforeswap"`. After clicking "Swap tagger" and typing
` afterswap`, readout flipped to `"B: ... beforeswap afterswap"`.
End-to-end confirms (a) P2.0's `diff_subs` patch correctly
preserves same-keyed subs across renders, (b) the binding's
`cm_sub_loader` `update_tagger` closure (codemirror.mbt:306–311)
correctly rebinds the doc tagger. The triage branches the
handoff anticipated (P2.0 regression vs binding closure bug)
were both ruled out by the green smoke.

**Demo footprint.** 12 files added under
`examples/codemirror_demo/` (10 source + `dist/` and
`node_modules/` gitignored). One CI matrix entry added to
`.github/workflows/ci.yml`. Workspace tests stay at 1155
passed / 0 failed; demo `moon test` is 0/0 by design (no tests
defined — runtime smoke is the only validation).

**Deferred work for P2.5.** Migrate `examples/ideal` behind
`VITE_CANOPY_USE_CM_BINDING=1` per plan §P2.5. The
multi-load-now-works property may unblock the deferred
ecosystem factories (`dark`/`vim`/`default_keymap`) at low
cost since `cm.EditorView` and `cm.keymap.of` are now reachable
from within `addon/` packages via `@js_ffi.raw_extension` — but
the actual forcing function (whether the ideal editor needs
them post-migration) doesn't yet exist. Default position from
rev 3.7 stands: stay deferred until P2.5 surfaces concrete
need.

**rev 3.7 (2026-05-19)** — Post-P2.3 ship (PR #299, squash SHA
`2b0dd11`). Codex implemented the rev-3.6 narrowed scope verbatim:
`Theme::custom(extension : @js_ffi.Extension) -> Theme` and
`Keymap::from_raw(extension : @js_ffi.Extension) -> Keymap`, both
`#cfg(target="js")`, both formatter-canonicalized into the qualified
method shape (matching the P2.2 precedent in rev 3.5). No API-shape
deviation versus the handoff doc. Three implementation-session notes
worth recording:
(a) **Doc-comment scrub for the grep invariant.** The handoff's
`Theme::custom` doc-comment example referenced the consumer
constructing via `@js_ffi.raw_extension(@js_value.Value)` — that
literal `@js_value` token would have tripped the hard grep invariant
that scans for `@js_value\|@cmd\|@sub\|@html\|Compartment` under
`lib/rabbita_codemirror/addon/`. Codex restated as "the consumer …
after they've loaded the CodeMirror module" — accurate but less
specific. The Codex review session noted this as a correct-for-now
trade-off; a future docs cleanup could narrow the grep to
code/imports (excluding doc comments) and restore the more precise
wording.
(b) **Stale scaffold-comment refresh.** Codex updated the obsolete
P2.2-era top-of-file prose ("factory constructors `dark()`,
`light()`, `custom(...)` land in P2.3") on both addon files to
reflect that ecosystem factories are deferred. Not called for in
the handoff; Codex acted on initiative — appropriate.
(c) **Stale `#warnings("-unused_constructor")` removal.** Codex
review caught that the P2.2-era warning suppressions on the `Theme`
and `Keymap` structs are now stale because the new factory bodies
invoke the positional constructors. Removed before opening the PR.
Parallel to the rev-3.5 cleanup of stale `#warnings("-deprecated_syntax")`
on the same files.
Minor handoff-doc bug for future use: the §"Verification" grep
example `grep -nE '...' lib/rabbita_codemirror/addon/` is missing
`-r`, so GNU grep complains "Is a directory." Codex ran the intended
source-only form (`addon/*/*.mbt`) and reported the substituted
command. Update if reused for P2.4+.
**Deferred factories status.** `Theme::dark` / `Theme::light` /
`Keymap::default_keymap` / `Keymap::vim` remain unimplemented. Either
a P2.3.5 mini-PR unfreezing the FFI narrowly (`theme_dark(cm) ->
Extension` helpers) OR bundling into P2.4 demo design (let the demo
surface concrete evidence about which factories the swap-tagger
smoke step actually needs). Default position: let P2.4 drive — if
`Theme::custom(@js_ffi.js_extension_combine([]))` carries the demo
end-to-end, the deferred factories stay deferred until P2.5 migration
of `examples/ideal` proves they're needed.

**rev 3.6 (2026-05-19)** — Pre-P2.3 dispatch. Narrowing the original
§P2.3 deliverables list from six factories (`dark`, `light`, `custom`,
`default_keymap`, `vim`, `from_raw`) to two (`Theme::custom`,
`Keymap::from_raw`). The four deferred factories all require
synchronous access to the loaded CM6 module to construct their
extensions, which collides with three P2.1/P2.2 invariants stacked
together: (a) FFI in `lib/rabbita_codemirror/js/` is frozen, (b) the
`Theme(@js_ffi.Extension)` newtype shape and `to_extension(self) ->
Extension` signature are frozen, (c) `addon/*` packages can import
only `@js_ffi` — not `@js_value`, so they cannot reach
`globalThis[Symbol.for(...)].modules` to look up a pre-loaded module
synchronously. Three resolution options surfaced: (A) ship only the
trivial Extension-wrapping factories and defer the ecosystem ones,
(B) take a `CmModule` parameter and re-export `load_codemirror`,
(C) factories return `@cmd.Cmd` and resolve to `Theme`/`Keymap` via a
tagger. Adopted (A): preserves all future paths at ~10 LOC, doesn't
commit to a particular ecosystem-factory shape, and lets the P2.4
demo surface concrete evidence about whether dark/default_keymap are
needed before flag-day. The Q5-style ESM-mapping table for the
deferred factories is recorded in
`docs/plans/2026-05-19-codemirror-rabbita-binding-phase2-p23-codex-handoff.md`.
Plan §P2.3 prose remains the original aspirational target; the handoff
doc is the actual P2.3 spec. Rev 3.7 (post-Codex) will record any
deviations Codex's design-review pass surfaces.

**rev 3.5 (2026-05-19)** — Post-P2.2 ship (PR #297). Codex implemented
the spec verbatim; three notable deviations + one pre-PR cleanup landed
versus rev 3.4's handoff doc:
(a) `lib/rabbita_codemirror/moon.pkg` carries `supported_targets = "js"`
**in addition to** the `options(targets: { "*": [ "js" ] })` the handoff
specified — required because `moonbit-community/rabbita/cmd` declares
`supported_targets`, and MoonBit raises a package-target warning unless
the consumer matches the form. Per-fn `#cfg(target="js")` annotations
remain canonical for binding code; `supported_targets` is package-level
belt-and-suspenders to silence the compatibility warning.
(b) The MoonBit formatter rewrote `addon/{theme,keymap}` `to_extension`
from free-function form (`fn to_extension(self : T)`) to qualified
method form (`fn T::to_extension(self : T)`). Semantically identical
callable surface (`theme.to_extension()` either way); the `.mbti`
records the method form. No follow-up needed — Codex's pre-PR review
confirmed the qualified form is the idiomatic post-deprecation shape.
(c) `priv suberror CmListen` uses a positional `String` as its first
field rather than the named `id : String` in the handoff doc — Codex's
implementer flagged this as a MoonBit constraint on suberror payloads.
The Codex reviewer pass corrected the framing: the canonical
`rabbita/rabbita/websocket/listen.mbt` *also* uses a positional first
field, so the original handoff's `id : String` was the deviation, not
Codex's implementation. Future bindings should mirror the websocket
positional-first form. The pattern still matches by position in
`cm_sub_loader` and `update_tagger`.
**Cleanup before PR:** removed two stale `#warnings("-deprecated_syntax")`
annotations Codex left on `addon/{theme,keymap}/*.mbt`'s
`to_extension` — Codex's review pass diagnosed them as referring to the
*old* free-function `fn to_extension(self : T)` form that the formatter
had already replaced, so the suppressions were no-ops. Removed; build
still clean.
**Other findings from Codex review (all PASS):** the double-dispose
path on `update_disposable` after a sub-unload + later `unmount` is
safe (the JS disposable closures guard with a `disposed` flag in
`js/codemirror.mbt:283-290`); the listen-before-mount race recovers on
the next re-render because the loader returns `None` and Rabbita re-fires
on the next `diff_subs` pass; and the `Local` argument to
`@sub.custom_sub` is the correct per-instance semantics for a binding
that owns per-editor state.

**rev 3.4 (2026-05-18)** — Pre-P2.2 dispatch, addon sequencing. The
prior plan sequenced P2.2 (main API) → P2.3 (all five addon subpackages),
but P2.2's `mount` and `set_theme`/`set_keymap` signatures already
reference `@theme.Theme` / `@keymap.Keymap` — types defined in
not-yet-created subpackages. Three options surfaced: (a) reorder
P2.3-first, (b) bundle scaffolds in P2.2, (c) drop typed params from
P2.2 and add them additively in P2.3. Codex (high-effort design
opinion) favored **(b)**, flagging an under-weighted consideration:
making the main package import `addon/theme` and `addon/keymap`
elevates those addons to *core public contract*, not optional add-ons
— this is fine for theme/keymap (every nontrivial editor sets them),
which justifies their early inclusion. Adopted (b): P2.2 bundles the
type-only scaffolds (`Theme(@js_ffi.Extension)` + `to_extension`, same
for `Keymap`); P2.3 adds factory constructors (`Theme::dark()`, etc.)
and re-evaluates whether `readonly`/`line_numbers`/`line_wrapping`
need typed subpackages at all (default: no — they're consumed as
`Bool` on `mount`/`set_*` signatures; subpackages added only if a
typed-extension surface emerges as needed for plug-in composition).

**rev 3.3 (2026-05-18)** — Pre-P2.2 dispatch. Removed the
"integration test in `lib/rabbita_codemirror/`" line from §P2.2
verification after a reachability audit of `rabbita/rabbita/sub/`:
(a) `diff_subs` is package-private to `moonbit-community/rabbita` and
not exported via `@sub`, so the test pattern from the P2.0 patch's own
`rabbita/tea_wbtest.mbt` cannot be replicated downstream; (b) calling
`cm_sub_loader` directly hits `js_add_update_listener` which requires
a real `CmView` and DOM, so even whitebox-internal-to-binding is
infeasible without deviating from the canonical websocket-binding
shape. Replaced the integration test with structural grep + manual
code-review-against-websocket-reference. End-to-end verification of
`update_tagger` now lives in §P2.4's manual smoke as a sixth step
("swap tagger across re-render"): if the new tagger fires after a
sub-key-preserving payload swap, P2.0 + binding both work in browser.
The P2.0 patch's own whitebox test already verifies `diff_subs`'s
mechanism at the framework level — the binding doesn't need to
re-verify it.

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
