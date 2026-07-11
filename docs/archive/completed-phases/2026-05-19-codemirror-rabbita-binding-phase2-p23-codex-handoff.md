# P2.3 Codex Handoff — Addon factory constructors

Companion to `2026-05-18-codemirror-rabbita-binding-phase2.md` (rev 3.6).
This document is the literal prompt to pass to Codex for the P2.3 PR —
the fourth binding-shipping PR after #296 (P2.0 + P2.1) and #297 (P2.2).

The plan doc captures the *why* (decisions, sequencing, risks); this doc
captures the *what* (Codex's contract). The plan rev 3.6 entry — written
alongside this handoff — narrows P2.3 scope from the original §P2.3
deliverables list and explains the design tension that drove the
narrowing. **Read the rev 3.6 entry before this handoff.**

---

## Required reading (in order)

1. `docs/plans/2026-05-18-codemirror-rabbita-binding-phase2.md` §P2.3
   (lines 370–415) **and** rev 3.6 in the revision history block — rev
   3.6 is the source of truth for the narrowed scope, not the original
   §P2.3 prose.
2. `lib/rabbita_codemirror/addon/theme/theme.mbt` — P2.2 scaffold to
   augment. The `Theme(@js_ffi.Extension)` newtype + `to_extension`
   method are **frozen** — DO NOT change their shape or signature.
3. `lib/rabbita_codemirror/addon/keymap/keymap.mbt` — symmetric scaffold.
4. `lib/rabbita_codemirror/addon/theme/moon.pkg` and
   `addon/keymap/moon.pkg` — currently import only `@js_ffi`. P2.3 holds
   this invariant: no new imports.
5. `lib/rabbita_codemirror/js/pkg.generated.mbti` — frozen FFI surface
   since P2.1 (`#296`). P2.3 must NOT extend it. No new `extern "js"`
   declarations, no new `pub fn` re-exports in `js/`.
6. `lib/rabbita_codemirror/codemirror.mbt` (skim) — see how `mount` and
   `set_theme`/`set_keymap` already call `theme.to_extension()` and
   `keymap.to_extension()`. The factory constructors must produce
   `Theme` / `Keymap` instances whose internal Extension is a real
   CM6-acceptable value at the moment `to_extension()` is called.
7. `rabbita/rabbita/websocket/websocket.mbt` — the canonical
   `pub fn op(...) -> Cmd` pattern, in case any factory needs to go the
   `Cmd`-returning route. **Not used in the recommended scope below**;
   listed for reference if Codex's design review pushes back on the
   narrowing.

## Design tension (READ BEFORE IMPLEMENTING)

The plan's original §P2.3 lists these factory signatures:

```moonbit
pub fn dark() -> Theme
pub fn light() -> Theme
pub fn custom(extension : @js_ffi.Extension) -> Theme

pub fn default_keymap() -> Keymap
pub fn vim() -> Keymap
pub fn from_raw(extension : @js_ffi.Extension) -> Keymap
```

**Four of the six (`dark`, `light`, `default_keymap`, `vim`) require
synchronous access to the loaded CM6 module** to construct their
extensions:

- `Theme::dark()` ⇒ `cm.EditorView.theme(spec, {dark: true})` *or*
  `oneDark` from `@codemirror/theme-one-dark` (a separate ESM package
  not included in `esm.sh/codemirror@6`).
- `Theme::light()` ⇒ `cm.EditorView.theme({}, {dark: false})` *or*
  a no-op extension (CM6's default styling is light-ish).
- `Keymap::default_keymap()` ⇒ `cm.keymap.of(cm.defaultKeymap)` —
  needs the loaded `keymap` namespace and `defaultKeymap` array.
- `Keymap::vim()` ⇒ `@replit/codemirror-vim` — separate ESM package,
  not in `esm.sh/codemirror@6`.

**The constraint chain that makes them un-implementable in P2.3:**

1. The factory must return `Theme(@js_ffi.Extension)` with a *real*
   Extension inside (per the frozen newtype shape).
2. Constructing the Extension requires calling `cm.EditorView.theme(…)`
   or `cm.keymap.of(…)` — both need the loaded CM6 module's namespace.
3. The CM6 module is async-loaded inside `mount`'s scheduler closure
   (`load_codemirror(source).wait()`). No synchronous global handle is
   exposed.
4. The `addon/` packages can only import `@js_ffi` (P2.2 invariant) and
   the FFI is frozen (P2.1 constraint). There is no public sync
   primitive in `@js_ffi` that returns the loaded `CmModule`, and no
   `@js_value` access to walk `globalThis[Symbol.for(...)].modules`.

**Three resolution options** (selected in main-context narrowing — Codex
should design-review the choice in the post-implementation pass, not
re-decide it pre-implementation):

| Opt | Shape | Cost |
|-----|-------|------|
| **A (chosen)** | Ship only Extension-wrapping factories (`Theme::custom`, `Keymap::from_raw`). Defer ecosystem factories until P2.4+ when an FFI-extension or alt-shape design is approved. | ~10 LOC. Minimal P2.3. Consumers can't construct dark/vim until later. |
| B | Take `cm : @js_ffi.CmModule` parameter on each factory. Re-export `load_codemirror` from main package so consumers can resolve a module before constructing factories. | Re-exports module-loader to consumers; expands the consumer-facing surface; doesn't fit the function-based-API rabbita convention (consumer Model would need to plumb a CmModule through). |
| C | Factories return `@cmd.Cmd` that asynchronously load whatever extra ESM is needed and emit a `Theme`/`Keymap` to a tagger. Two-stage setup (load → use). | Changes plan signatures (factories return Cmd, not Theme directly); doesn't compose with `mount`'s synchronous `initial_theme` slot; more PRs to update. |

Option A is the lightest ship and preserves all future paths. Rev 3.6
records the choice; rev 3.7 (post-Codex) will record any deviations
Codex flags during the design-review pass.

## Q5-style decisions surfaced (for future phases — NOT P2.3 scope)

When the time comes to add `dark` / `default_keymap` / `vim` factories,
the following ESM mapping is the canonical reference (verified
2026-05-19 against esm.sh):

| Factory | Source module | Available in `esm.sh/codemirror@6`? |
|---------|---------------|-------------------------------------|
| `dark` (oneDark) | `https://esm.sh/@codemirror/theme-one-dark` | **No** — separate package. |
| `dark` (synthesized) | `cm.EditorView.theme({…}, {dark: true})` | Yes (`EditorView` is in the metapackage) but needs cm-module access. |
| `light` (synthesized) | `cm.EditorView.theme({}, {dark: false})` or empty Extension | Yes (synthesized) or trivially empty. |
| `default_keymap` | `cm.keymap.of(cm.defaultKeymap)` | Yes — both `keymap` and `defaultKeymap` ship in `esm.sh/codemirror@6`. Needs module access. |
| `vim` | `https://esm.sh/@replit/codemirror-vim` | **No** — separate package. |

The "needs module access" cases require an FFI extension (e.g., a
`theme_dark(cm : CmModule) -> Extension` helper inside
`lib/rabbita_codemirror/js/`) or a re-export of `load_codemirror`
through the public surface. Either path requires a written design-doc
revision (P2.4 or a P2.3.5 mini-PR), not a stealth FFI addition.

## Objective

Augment the existing P2.2 scaffolds with public factory constructors,
making the `Theme` and `Keymap` newtypes externally constructible from a
consumer-supplied `@js_ffi.Extension`. Without this, the newtypes are
opaque-but-uninstantiable from outside `lib/rabbita_codemirror/addon/*`
— consumers cannot pass an `initial_theme` to `mount` because there is
no public way to obtain a `Theme` value.

## Scope (narrowed per Option A)

**Modify:**

- `lib/rabbita_codemirror/addon/theme/theme.mbt` — add factory.
- `lib/rabbita_codemirror/addon/keymap/keymap.mbt` — add factory.
- `lib/rabbita_codemirror/addon/theme/pkg.generated.mbti` — regenerated.
- `lib/rabbita_codemirror/addon/keymap/pkg.generated.mbti` — regenerated.

**Create:** none.

**Do NOT touch:**

- `lib/rabbita_codemirror/js/**` — FFI is frozen post-P2.1.
- `lib/rabbita_codemirror/codemirror.mbt` — public API surface frozen
  post-P2.2 modulo the additive factories landing in `addon/*`.
- `lib/rabbita_codemirror/addon/*/moon.pkg` — imports stay limited to
  `@js_ffi`. No new imports (`@js_value`, `@cmd`, `@sub` etc.).
- `rabbita/**` — vendored submodule.
- `examples/**` — P2.4 territory.

## Public API (exact signatures)

`lib/rabbita_codemirror/addon/theme/theme.mbt` adds:

```moonbit
///|
/// Wrap a pre-built CodeMirror extension as a Theme. The Extension is
/// typically constructed by the consumer via
/// `@js_ffi.raw_extension(@js_value.Value)` after they've loaded the
/// CodeMirror module — or via `@js_ffi.js_extension_combine([])` for
/// "no theme" (CM6 default styling).
///
/// Named factories that bind to specific CM6 ecosystem extensions
/// (`dark`, `light`, `default_keymap`, `vim`) are deferred — see plan
/// rev 3.6 for the design tension and the Q5-style decision table.
#cfg(target="js")
pub fn Theme::custom(extension : @js_ffi.Extension) -> Theme {
  Theme(extension)
}
```

`lib/rabbita_codemirror/addon/keymap/keymap.mbt` adds (symmetric):

```moonbit
///|
/// Wrap a pre-built CodeMirror extension as a Keymap. See `Theme::custom`
/// for usage notes; the `default_keymap` and `vim` factories are
/// deferred per plan rev 3.6.
#cfg(target="js")
pub fn Keymap::from_raw(extension : @js_ffi.Extension) -> Keymap {
  Keymap(extension)
}
```

Factory naming notes:

- `Theme::custom` matches the original §P2.3 plan signature (`pub fn
  custom(extension) -> Theme`). Using the `Theme::custom` (qualified
  method) form for consistency with P2.2's `Theme::to_extension`
  shipped form (see rev 3.5: the MoonBit formatter rewrites
  free-function shapes to method form anyway).
- `Keymap::from_raw` matches the plan's `pub fn from_raw(extension) ->
  Keymap` exactly.

If the MoonBit formatter rewrites these into a different idiom (e.g.
plain `fn custom(extension) -> Theme` at module scope), accept the
formatter's output and note it in the artifact return. The `.mbti`
diff is the source of truth for the shipped public-API shape.

## Hard invariants

1. **No `extern "js"` outside `js/`.** Grep clean.
2. **`js/` directory untouched.** `git diff lib/rabbita_codemirror/js/`
   is empty.
3. **`Theme(@js_ffi.Extension)` struct shape unchanged.** Field count,
   visibility, derives — all identical to P2.2.
4. **`Theme::to_extension(self) -> @js_ffi.Extension` signature
   unchanged.** Same for `Keymap::to_extension`.
5. **Addon imports unchanged.** `lib/rabbita_codemirror/addon/{theme,
   keymap}/moon.pkg` continues to import only `dowdiness/rabbita_codemirror/js`.
   No new imports added — *especially* not `@js_value`, `@cmd`, `@sub`.
6. **No `Compartment` in any addon `.mbti`.** Same invariant as P2.2.
7. **`#cfg(target="js")` on every public factory.** Matches the per-fn
   annotation style P2.2 shipped (rev 3.5).
8. **Defer-flagged factories STAY DEFERRED.** Do not stub `dark()`,
   `light()`, `default_keymap()`, `vim()` even as `abort("TODO")` or
   `...`-placeholder bodies. They are out of P2.3 scope per rev 3.6.

## Tests

P2.3 adds **no new test files**. The shipped factories are one-line
Extension-wrappers — no testable behavior beyond "the constructor
exists and is callable." The `.mbti` diff is the artifact that proves
the API surface change.

If Codex wants to add a smoke test, it goes in `codemirror_wbtest.mbt`
(workspace whitebox tests already live there) and verifies only that
`Theme::custom(empty)` and `Keymap::from_raw(empty)` are callable
without panic — where `empty = @js_ffi.js_extension_combine([])`.
Acceptable but not required.

## Verification (independent re-run by Claude after Codex returns)

1. `moon check` (workspace root) — clean. Report exit status + tail.
2. `moon test --target js` (workspace root) — clean. **Report the
   literal final summary line** (e.g. `Total tests: N, passed: N,
   failed: 0`). Do not paraphrase. Rev 3 of the plan documents Codex's
   P2.0 having paraphrased a broken build as green.
3. `moon info` — clean. Include `git diff
   lib/rabbita_codemirror/addon/theme/pkg.generated.mbti
   lib/rabbita_codemirror/addon/keymap/pkg.generated.mbti` full output.
4. Grep checks (paste raw output):
   - `grep -rn 'extern "js"' lib/rabbita_codemirror/addon/` → empty.
   - `git diff --stat lib/rabbita_codemirror/js/` → empty.
   - `grep -rn '@js_value\|@cmd\|@sub\|@html\|Compartment'
     lib/rabbita_codemirror/addon/` → empty.
   - `grep -nE 'pub fn (Theme::custom|Keymap::from_raw)'
     lib/rabbita_codemirror/addon/` → exactly two lines (one each).
   - `grep -rn 'fn (dark|light|default_keymap|vim)\b'
     lib/rabbita_codemirror/addon/` → empty (defer invariant).

## Artifacts contract

Return:

1. Files modified, with line counts (expected: 2 source `.mbt` files
   + 2 regenerated `.mbti` files).
2. **Literal final-line `moon test` summary** (not paraphrased).
3. `moon check` exit status + tail (or "clean").
4. Full `git diff` of both `.mbti` files.
5. Raw output of all five grep checks.
6. Any deviation from this spec, with written justification — including
   formatter-driven shape rewrites (qualified vs. free-function form).

## Owner

Codex implements; Claude (Opus) reviews:

- Factory naming matches plan §P2.3 (`Theme::custom`, `Keymap::from_raw`).
- No deferred factories accidentally stubbed.
- FFI directory untouched.
- Addon import line unchanged.
- `.mbti` diff shows additive change only (new factory line; existing
  `Theme(@js.Extension)` + `to_extension` lines unchanged).

## After dispatch

- Codex returns artifacts → Claude independently re-runs the five grep
  checks, `moon check`, `moon test --target js`.
- Codex-review pass via `mcp__codex__codex` MCP: confirm the chosen
  Option A narrowing was correct (vs B/C alternatives), and confirm no
  hidden FFI extension.
- Open the PR with the standard P2 sequencing format
  (`feat(rabbita_codemirror): P2.3 — addon factory constructors`). Body
  should call out the deferral explicitly — readers may expect the
  plan's six factories.
- After CI green: `/merge-pr <PR#>`.
- Update plan doc with rev 3.7 noting any deviations Codex flagged.
- Next PR: P2.4 (minimal demo) per plan §P2.4. The demo MUST validate
  the deferred-factory decision by demonstrating an end-to-end mount
  flow either with `Theme::custom(@js_ffi.js_extension_combine([]))`
  (proving the narrow factory is sufficient for happy-path), or by
  surfacing a concrete gap that motivates a P2.3.5 FFI extension.
