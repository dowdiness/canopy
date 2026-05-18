# P2.2 Codex Handoff — Public API + registry + sub loader + theme/keymap scaffolds

Companion to `2026-05-18-codemirror-rabbita-binding-phase2.md` (rev 3.4).
This document is the literal prompt to pass to Codex for the P2.2 PR
(the third binding-shipping PR after #296's P2.0 + P2.1).

The reading list, signatures, invariants, and verification block below
are the source of truth for what P2.2 must deliver. The plan doc
captures the *why* (decisions, sequencing, risks); this doc captures
the *what* (Codex's contract).

---

## Required reading (in order)

1. `docs/plans/2026-05-18-codemirror-rabbita-binding-phase2.md` §P2.2
   (lines ~220–369). Read **rev 3.3** (no integration test) and **rev
   3.4** (addon scaffolds bundled) in the revision history block first
   — these are the corrections to the original spec.
2. `rabbita/rabbita/websocket/listen.mbt` — **canonical Sub-binding
   pattern**. Mirror its structure line-for-line: `priv suberror`,
   `let mut tagger`, `update_tagger`, `@sub.custom_sub` key encoding
   presence only.
3. `rabbita/rabbita/websocket/websocket.mbt` — **canonical Cmd-binding
   pattern**: `Map[String, Entry]` registry, `@cmd.custom_cmd(kind=
   Immediately, …)`, `report_failure` helper, lifecycle cleanup
   ordering, per-fn `#cfg(target="js")` annotation style.
4. `rabbita/rabbita/sub/design.md` — *why* `update_tagger` exists.
5. `rabbita/skills/rabbita.md` — consumer-vs-binding distinction. The
   binding is the escape-hatch shell.
6. `lib/rabbita_codemirror/js/pkg.generated.mbti` — frozen FFI surface
   from P2.1. Do **not** extend.
7. `lib/rabbita_codemirror/js/codemirror.mbt` (skim) — JS-side
   semantics relevant for matching invariants: `js_dispatch` is
   synchronous and toggles `applying`; `js_add_update_listener`
   filters events while `applying`; `load_codemirror` is memoized per
   source with reject-eviction; `js_create_view` stashes `_cmModule`
   on the view.

## Objective

Implement three things in this PR:

1. `lib/rabbita_codemirror/codemirror.mbt` — public function-based
   API + `priv` registry + `priv suberror` + `cm_sub_loader`.
   Consumers hold only a `String` id; all CodeMirror state lives in
   private `editors : Map[String, CmEntry]`.
2. `lib/rabbita_codemirror/addon/theme/` — `pub struct Theme(
   @js_ffi.Extension)` + `pub fn to_extension(self : Theme) ->
   @js_ffi.Extension`. Type-only scaffold — no factory constructors
   yet (those land in P2.3).
3. `lib/rabbita_codemirror/addon/keymap/` — symmetric: `Keymap`
   newtype + `to_extension`.

## Scope

**Modify:**
- `lib/rabbita_codemirror/codemirror.mbt` (currently docstring-only —
  populate)
- `lib/rabbita_codemirror/moon.pkg` (currently empty — populate; see
  §Package wiring)

**Create:**
- `lib/rabbita_codemirror/addon/theme/theme.mbt`
- `lib/rabbita_codemirror/addon/theme/moon.pkg`
- `lib/rabbita_codemirror/addon/keymap/keymap.mbt`
- `lib/rabbita_codemirror/addon/keymap/moon.pkg`
- `lib/rabbita_codemirror/codemirror_wbtest.mbt` (mandatory; see §Tests)
- All four `pkg.generated.mbti` files (regenerated via `moon info`)

**Do NOT touch:**
- `lib/rabbita_codemirror/js/**` — FFI is frozen post-P2.1.
- `rabbita/**` — vendored submodule; patched fork; no edits.
- `examples/**` — P2.5 territory.

## Package wiring

`lib/rabbita_codemirror/moon.pkg`:

```
import {
  "moonbit-community/rabbita/js" @js_value,
  "moonbit-community/rabbita/cmd" @cmd,
  "moonbit-community/rabbita/sub" @sub,
  "dowdiness/rabbita_codemirror/js" @js_ffi,
  "dowdiness/rabbita_codemirror/addon/theme" @theme,
  "dowdiness/rabbita_codemirror/addon/keymap" @keymap,
}

options(
  targets: { "*": [ "js" ] },
)
```

`lib/rabbita_codemirror/addon/theme/moon.pkg` (and `addon/keymap/`
identical with its own folder):

```
import {
  "dowdiness/rabbita_codemirror/js" @js_ffi,
}

options(
  targets: { "*": [ "js" ] },
)
```

**Every public function and top-level `let` in
`lib/rabbita_codemirror/codemirror.mbt` and the two addon files MUST
be annotated with `#cfg(target="js")`**, matching
`rabbita/rabbita/websocket/*.mbt`. The package-level `targets` in
`moon.pkg` is belt-and-suspenders; the per-declaration annotation is
the canonical form for binding code.

## Public API (exact signatures)

```moonbit
// types
pub struct SelRange { from : Int, to : Int }

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

pub fn unmount(id : String, failed? : @cmd.Emit[String]) -> @cmd.Cmd

// edits
pub fn set_doc(id : String, doc : String, failed? : @cmd.Emit[String]) -> @cmd.Cmd
pub fn insert(id : String, pos : Int, text : String, failed? : @cmd.Emit[String]) -> @cmd.Cmd
pub fn replace(id : String, from : Int, to : Int, text : String, failed? : @cmd.Emit[String]) -> @cmd.Cmd
pub fn set_selection(id : String, range : SelRange, failed? : @cmd.Emit[String]) -> @cmd.Cmd

// addon ops
pub fn set_theme(id : String, theme : @theme.Theme, failed? : @cmd.Emit[String]) -> @cmd.Cmd
pub fn set_readonly(id : String, enabled : Bool, failed? : @cmd.Emit[String]) -> @cmd.Cmd
pub fn set_keymap(id : String, keymap : @keymap.Keymap, failed? : @cmd.Emit[String]) -> @cmd.Cmd
pub fn set_line_numbers(id : String, enabled : Bool, failed? : @cmd.Emit[String]) -> @cmd.Cmd
pub fn set_line_wrapping(id : String, enabled : Bool, failed? : @cmd.Emit[String]) -> @cmd.Cmd

// subscription
pub fn listen(
  id : String,
  doc? : @cmd.Emit[String],
  selection? : @cmd.Emit[SelRange],
  focus? : @cmd.Emit[Bool],
) -> @sub.Sub
```

## Internal shape

```moonbit
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

priv suberror CmSubscription {
  CmListen(
    id : String,
    doc~ : @cmd.Emit[String]?,
    selection~ : @cmd.Emit[SelRange]?,
    focus~ : @cmd.Emit[Bool]?,
  )
}

priv fn cm_sub_loader(payload : Error, scheduler : &@cmd.Scheduler) -> @sub.RunningSub?
```

## Addon scaffolds (exact contents)

`lib/rabbita_codemirror/addon/theme/theme.mbt`:

```moonbit
///|
/// Typed wrapper for a CodeMirror theme extension. Factory
/// constructors (`dark()`, `light()`, `custom(...)`) land in P2.3;
/// this scaffold exists so the main package's `mount` /
/// `set_theme` signatures can reference `@theme.Theme` from the
/// first public release.

///|
pub struct Theme(@js_ffi.Extension)

///|
#cfg(target="js")
pub fn to_extension(self : Theme) -> @js_ffi.Extension {
  self.0
}
```

Symmetric for `addon/keymap/keymap.mbt` (with `Keymap` instead of
`Theme`).

## Hard invariants

1. **No `extern "js"` outside `js/`.** Grep clean.
2. **Exactly one `priv suberror` and exactly one `@sub.custom_sub`**
   in `lib/rabbita_codemirror/codemirror.mbt`.
3. **Sub key encodes `id` and presence-only.** Format:
   `"codemirror.listen(id=\{id},doc=\{has_doc},selection=\{has_selection},focus=\{has_focus})"`.
   Never include tagger identity, never the entry pointer.
   (Rationale: re-renders must rebind taggers via `update_tagger`, not
   re-install the sub. See `rabbita/skills/rabbita.md` "Sub key
   conventions".)
4. **`listen` returns `@sub.none` if no tagger provided.** No-op
   guard matching websocket binding.
5. **`cm_sub_loader` rebinds via `let mut`.** Three taggers
   (`doc_tagger`, `selection_tagger`, `focus_tagger`), each `let
   mut`. `update_tagger` guards `payload is CmListen(_, doc~,
   selection~, focus~)` and rebinds all three. This is the only
   reason P2.0's patch exists — capture by value defeats it.
6. **`mount(id, …)` replaces on collision.** Order: dispose old
   `update_disposable` → destroy old view → remove old entry →
   install new. Matches websocket's `connect` semantics.
7. **`set_doc(id, x)` is a no-op when `x ==
   js_state_doc(entry.view)`.** Echo prevention.
8. **All ops report missing-id via `failed?`.** Ops dispatched
   before `mount` completes (race in same frame) must report cleanly,
   not abort.
9. **`mount` uses `@cmd.custom_cmd(kind=Immediately, scheduler => {
   … })`** and `await`s `load_codemirror(source~).wait()` inside the
   scheduler closure. After successful view construction + compartment
   setup + listener install: schedule `on_mounted?` and any deferred
   state via `scheduler.add`.
10. **`load_codemirror.wait()` rejection MUST be caught.** Wrap the
    loader call in `try` / raise-catching; on rejection, call
    `report_failure(scheduler, failed, "codemirror module load failed:
    …")` and return. Do NOT abort. The FFI already evicts the cache
    entry; the binding only needs to surface the error to the
    consumer.
11. **`unmount` disposes in order:** `update_disposable.dispose()` →
    `js_view_destroy(view)` → `editors.remove(id)`.
12. **Addon scaffolds import only `js/`.** Each `addon/*/moon.pkg`
    has exactly one import (`@js_ffi`), no `@cmd` / `@sub` /
    `@js_value`.

## Tests

Per plan rev 3.3: **no in-binding integration test for
`update_tagger`.** End-to-end verification deferred to P2.4 browser
smoke (swap-tagger step).

**Required:** `lib/rabbita_codemirror/codemirror_wbtest.mbt` with at
least the following coverage.

Extract sub key construction as a private helper:

```moonbit
priv fn build_listen_key(
  id : String,
  has_doc : Bool,
  has_selection : Bool,
  has_focus : Bool,
) -> String {
  "codemirror.listen(id=\{id},doc=\{has_doc},selection=\{has_selection},focus=\{has_focus})"
}
```

Then `listen(…)` calls `build_listen_key(id, doc is Some(_),
selection is Some(_), focus is Some(_))`. This is the *one* refactor
permitted from the canonical websocket pattern, justified because (a)
it makes the presence-only invariant locally testable and (b) the
websocket binding's key construction is inlined as a single string
literal; refactoring is allowed when it enables testing the binding's
own correctness.

Tests in `codemirror_wbtest.mbt`:

1. **Format snapshot** — `inspect(build_listen_key("a", true, true,
   false), content="codemirror.listen(id=a,doc=true,selection=true,focus=false)")`.
   Locks the wire format so future edits to the key string trigger
   snapshot review.
2. **Determinism** — `inspect(build_listen_key("a", true, false,
   false) == build_listen_key("a", true, false, false),
   content="true")` (or equivalent).
3. **ID matters** — `inspect(build_listen_key("a", true, false,
   false) == build_listen_key("b", true, false, false),
   content="false")`.
4. **Presence flags matter** — at least two pairs with same id but
   different flag combinations producing different keys.

If `assert_not_eq` doesn't exist in MoonBit's test API (verify),
use `inspect` with bool content as shown above. Don't invent test
helpers.

Note: cannot test `listen(id)` with all-None taggers returning
`@sub.none` because `Sub` is opaque and has no `Eq` impl. The guard
semantics are covered by the grep check (`@sub.none` literal appears
in source) and code review.

## Verification (independent re-run by Claude)

1. `moon check` (workspace root) — clean.
2. `moon test --target js` (workspace root) — clean. Report the
   **literal final summary line** (e.g. `Total tests: N, passed: N,
   failed: 0`).
3. `moon info` — clean. Include `git diff
   lib/rabbita_codemirror/pkg.generated.mbti
   lib/rabbita_codemirror/addon/theme/pkg.generated.mbti
   lib/rabbita_codemirror/addon/keymap/pkg.generated.mbti` full
   output.
4. Grep checks (paste raw output):
   - `grep -rn 'extern "js"' lib/rabbita_codemirror/codemirror.mbt
     lib/rabbita_codemirror/addon/` → empty
   - `grep -c 'priv suberror' lib/rabbita_codemirror/codemirror.mbt`
     → 1
   - `grep -c '@sub.custom_sub'
     lib/rabbita_codemirror/codemirror.mbt` → 1
   - `grep -nE 'let mut [a-z_]*_tagger'
     lib/rabbita_codemirror/codemirror.mbt` → 3 lines
   - `grep -n 'update_tagger'
     lib/rabbita_codemirror/codemirror.mbt` → ≥1 line, inside
     `cm_sub_loader`
   - `grep -rn 'Compartment\|@cmd\|@sub\|@js_value'
     lib/rabbita_codemirror/addon/` → empty

## Artifacts contract

Return:

1. Files created/modified, with line counts.
2. Literal final-line `moon test` summary (not paraphrased — Codex's
   P2.0 report paraphrased the summary and the build was actually
   broken; tightened in plan rev 3 delegation block).
3. `moon check` exit status + tail (or "clean").
4. Full `git diff` of all four `.mbti` files.
5. Raw output of all six grep checks.
6. Any deviation from this spec, with written justification.

## Owner

Codex implements; Claude (Opus) reviews:

- Tagger rebind closure semantics (line-by-line vs
  `rabbita/rabbita/websocket/listen.mbt`)
- `set_doc` no-op invariant
- `mount` collision handling
- `load_codemirror` rejection path
- Sub key composition (presence-only, no tagger identities)

## After dispatch

- Codex returns artifacts → Claude independently re-runs the six
  grep checks, `moon check`, `moon test --target js`.
- Open the PR with the standard P2 sequencing format (`feat(
  rabbita_codemirror): P2.2 — …`).
- After CI green + Codex review (via `mcp__codex__codex` MCP) +
  manual code review of the rebind closure: `/merge-pr <PR#>`.
- Update plan doc with rev 3.5 noting any deviations Codex flagged
  during implementation, similar to rev 3.1.
- Next PR: P2.3 (addon factories) per plan §P2.3.
