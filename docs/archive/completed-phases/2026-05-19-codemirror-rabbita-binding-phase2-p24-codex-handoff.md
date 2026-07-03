# P2.4 Codex Handoff — Minimal example (`examples/codemirror_demo/`)

Companion to `2026-05-18-codemirror-rabbita-binding-phase2.md` (rev 3.7).
This document is the literal prompt to pass to Codex for the P2.4 PR —
the fifth binding-shipping PR after #296 (P2.0+P2.1), #297 (P2.2), and
#299 (P2.3).

The plan doc captures the *why* (decisions, sequencing, risks); this
doc captures the *what* (Codex's contract). Rev 3.7 is the source of
truth for the constrained P2.3 surface this demo is built on
(`Theme::custom` + `Keymap::from_raw` only; ecosystem factories
deferred). **Read rev 3.7 before this handoff.**

---

## Required reading (in order)

1. `docs/plans/2026-05-18-codemirror-rabbita-binding-phase2.md`
   §P2.4 (lines 417–454) — the canonical six-behavior verification
   list — and rev 3.7 in the revision-history block (lines 619–662)
   for the deferred-factories framing.
2. `lib/rabbita_codemirror/pkg.generated.mbti` — frozen public API
   the demo must consume. Twelve `pub fn` entries (`mount`, `unmount`,
   `set_doc`, `insert`, `replace`, `set_selection`, `set_theme`,
   `set_readonly`, `set_keymap`, `set_line_numbers`,
   `set_line_wrapping`, `listen`). Demo uses **four** of them
   (`mount`, `unmount`, `set_doc`, `set_readonly`) plus `listen`.
   Do NOT extend this surface.
3. `lib/rabbita_codemirror/addon/theme/pkg.generated.mbti` and
   `addon/keymap/pkg.generated.mbti` — the P2.3-shipped factories
   (`Theme::custom`, `Keymap::from_raw`) plus the P2.2 `to_extension`
   methods. Demo calls `Theme::custom(@js_ffi.js_extension_combine([]))`
   exactly once at mount to validate the factory end-to-end.
4. `lib/rabbita_codemirror/codemirror.mbt` (skim) — see how `mount`
   and `listen` are shaped (`init_doc~ = ""` default; `doc?`,
   `selection?`, `focus?` optional `Emit` taggers). The
   `build_listen_key` function at lines 258–266 is the contract the
   swap-tagger smoke exercises — keys encode only flag presence, not
   tagger identity.
5. `rabbita/examples/websocket/main/client.mbt` — **canonical
   end-to-end Rabbita consumer.** Mirror its top-level shape: `enum
   Msg`, `struct Model`, `fn update(emit, msg, model) -> (Cmd, Model)`,
   `fn subscriptions(emit, model) -> Sub`, `fn view(emit, model) ->
   Html`, `let initial_model`, `fn main { ... @rabbita.cell(...)
   ... @rabbita.new(app).mount("app") }`.
6. `rabbita/examples/websocket/{moon.mod.json, main/moon.pkg,
   README.md}` — the metadata shape to mirror. Note
   `supported_targets = "js"` and `"is-main": true` on the main
   package; `"preferred-target": "js"` on the module.
7. `rabbita/examples/SSR/{vite.config.js, package.json, index.html}` —
   the canonical Vite host for a rabbita app. Uses `@rabbita/vite`
   plugin. This is the shape the demo's `vite.config.ts` mirrors.
   **Do NOT mirror canopy's `examples/web/vite.config.ts`** — that
   uses a bespoke `vite-plugin-moonbit.ts` wired for namespaced FFI
   packages (`@moonbit/crdt-lambda`), which is the wrong shape for a
   single-module rabbita app.
8. `rabbita/skills/rabbita.md` — the consumer-side anti-pattern list.
   The demo is consumer-side; rules apply. Do not store
   Cmd/Msg/callbacks in Model. Keep callback bodies one-line
   (`x => send(DocChangedA(x))`).
9. `lib/rabbita_codemirror/moon.mod.json` — the path-dep shape (deps
   `moonbit-community/rabbita` → `../../rabbita/rabbita`). The demo's
   `moon.mod.json` mirrors this plus adds a path-dep on
   `dowdiness/rabbita_codemirror` → `../../lib/rabbita_codemirror`.

## Pre-resolved design decisions (read before implementing)

These four were resolved in the main-context dispatch prep and are
NOT open for Codex to re-decide. Codex's design-review pass (after
implementation) may flag concerns; do not change scope without an
explicit revision pass.

### Decision 1 — Six-behavior → public-API mapping

The §P2.4 spec lists six manual-smoke behaviors. Each maps to one
binding call. The demo exercises **four** Cmd-returning ops plus
`listen`:

| # | Behavior | Binding call | Symbol cite |
|---|---|---|---|
| 1 | Editor mounts | `@cm.mount(model.cm_id, host_id="cm-demo-host", init_doc=initial_text, initial_theme=Some(@theme.Theme::custom(@js_ffi.js_extension_combine([]))), on_mounted~=emit(Mounted), failed~=emit.map(MountFailed))` | `codemirror.mbt:321 mount` + `addon/theme/theme.mbt Theme::custom` + `js/pkg.generated.mbti js_extension_combine` |
| 2 | Typing fires `DocChanged` | `@cm.listen(model.cm_id, doc~=...)` in `subscriptions` | `codemirror.mbt:558 listen` |
| 3 | "Set doc" button | `@cm.set_doc(model.cm_id, "fresh text from the demo")` returned from `update` on `Msg::SetDocClicked` | `codemirror.mbt:402 set_doc` |
| 4 | "Toggle readonly" | `@cm.set_readonly(model.cm_id, !model.readonly)` returned from `update` on `Msg::ToggleReadonly` | `codemirror.mbt:486 set_readonly` |
| 5 | Unmount + re-mount | `@cm.unmount(model.cm_id)` on `Msg::UnmountClicked`; same `mount` call from #1 on `Msg::MountClicked` | `codemirror.mbt:386 unmount` + `codemirror.mbt:321 mount` |
| 6 | Swap tagger | See Decision 2 | (no new call; same `listen`) |

`set_theme`, `set_keymap`, `set_line_numbers`, `set_line_wrapping`,
`insert`, `replace`, `set_selection` are **not** in scope for P2.4.
Demo does not exercise them.

`@js_ffi.js_extension_combine` is `pub` and exported from
`dowdiness/rabbita_codemirror/js`. The demo's `main/moon.pkg`
imports it as `@js_ffi` alongside `dowdiness/rabbita_codemirror` as
`@cm` and `dowdiness/rabbita_codemirror/addon/theme` as `@theme`.

### Decision 2 — Swap-tagger msg-variant shape

The swap exercises rabbita's `update_tagger` rebind path — the
mechanism the P2.0 patch enables. The constraint is: **the
`@sub.custom_sub` key must stay constant across the swap**, only the
inner `Emit` tagger changes.

Shape:

```moonbit
enum Msg {
  Mounted
  MountFailed(String)
  DocChangedA(String)
  DocChangedB(String)
  SetDocClicked
  ToggleReadonly
  UnmountClicked
  MountClicked
  SwapTagger
}

struct Model {
  cm_id : String
  mounted : Bool
  readonly : Bool
  last_doc : String
  last_variant : String  // "A" or "B" — readout shows which
                         // variant most recently fired
  use_variant_b : Bool   // SwapTagger flips this
  status_log : Array[String]  // capped, like
                              // rabbita/examples/websocket's listen_log
}

fn subscriptions(emit : Emit[Msg], model : Model) -> Sub {
  guard model.mounted else { return @sub.none }
  let doc_tagger : Emit[String] = if model.use_variant_b {
    emit.map(t => DocChangedB(t))
  } else {
    emit.map(t => DocChangedA(t))
  }
  @cm.listen(model.cm_id, doc~=doc_tagger)
}
```

Both `DocChangedA(String)` and `DocChangedB(String)` carry the
same payload type. The `update` branch for each records
`last_variant: "A"` or `"B"` plus `last_doc: text`. The readout in
`view` shows `"\{model.last_variant}: \{model.last_doc}"`.

**Why this is the right shape**: `build_listen_key` (codemirror.mbt
lines 258–266) computes
`"codemirror.listen(id=\{id},doc=true,selection=false,focus=false)"`
in both branches — `has_doc` is `Some(_)` either way. The key is
byte-identical pre- and post-swap. Rabbita's patched `diff_subs`
sees the same key and calls `update_tagger` on the preserved sub.
`cm_sub_loader`'s `update_tagger` closure (lines 306–311) reads the
new `doc` field and assigns `doc_tagger = doc`. Next CM6 update,
the new `Emit` fires.

If after click-then-type the readout still shows `A:`, the rebind
broke. Triage either P2.0's framework patch or the binding's
`update_tagger` closure (lines 306–311). Both possibilities require
in-session diagnosis; do not ship the PR with the smoke failing.

The swap is NOT a re-subscribe. `subscriptions` does not return
`@sub.none` between renders. The `Bool` is toggled via
`SwapTagger`'s update branch; the same `listen` call is returned
both before and after.

### Decision 3 — Demo directory layout

Mirror `rabbita/examples/websocket/` (canonical fn-based-binding
consumer) with `rabbita/examples/SSR/`'s Vite host shape. Do NOT
introduce a `web/` subdir — rabbita examples have the Vite config
at the example root, and `@rabbita/vite` is path-resolution-sensitive
about this.

```
examples/codemirror_demo/
├── .gitignore                 # dist/, node_modules/, _build/, target/, .mooncakes/
├── README.md                  # six-behavior checklist (mirrors P2.4 §Verification)
├── moon.mod.json              # path-deps to rabbita + lib/rabbita_codemirror
├── index.html                 # <div id="app"></div>, <script src="/main.js" type=module>
├── package.json               # dev/build scripts; dep on @rabbita/vite
├── vite.config.ts             # defineConfig({ plugins: [rabbita()] })
├── tsconfig.json              # minimal — vite needs it; copy from rabbita/examples/SSR/ if present, else minimal
├── public/
│   └── styles.css             # minimal styling
└── main/
    ├── client.mbt             # full TEA app
    ├── moon.pkg               # imports @cm, @theme, @js_ffi, @rabbita, @html, @sub, @cmd
    └── pkg.generated.mbti     # regenerated by moon info
```

`moon.mod.json`:

```json
{
  "name": "example/codemirror_demo",
  "version": "0.1.0",
  "deps": {
    "moonbit-community/rabbita": { "path": "../../rabbita/rabbita" },
    "dowdiness/rabbita_codemirror": { "path": "../../lib/rabbita_codemirror" }
  },
  "readme": "README.md",
  "repository": "https://github.com/dowdiness/canopy",
  "license": "Apache-2.0",
  "keywords": [],
  "description": "Minimal Rabbita ↔ CodeMirror 6 binding demo",
  "preferred-target": "js"
}
```

`main/moon.pkg`:

```
import {
  "moonbit-community/rabbita",
  "moonbit-community/rabbita/cmd" @cmd,
  "moonbit-community/rabbita/sub" @sub,
  "moonbit-community/rabbita/html" @html,
  "dowdiness/rabbita_codemirror" @cm,
  "dowdiness/rabbita_codemirror/addon/theme" @theme,
  "dowdiness/rabbita_codemirror/js" @js_ffi,
}

supported_targets = "js"

options(
  "is-main": true,
)
```

The `addon/keymap` import is NOT included — demo does not exercise
`set_keymap`. Including it triggers a dead-import lint that future
maintenance burns time on.

The `@theme` and `@js_ffi` imports are mandatory: demo passes
`Some(@theme.Theme::custom(@js_ffi.js_extension_combine([])))` as
`initial_theme` to `mount`. This is the load-bearing rev-3.7
validation — if `Theme::custom(empty)` carries the demo end-to-end,
the deferred factories stay deferred until P2.5.

**`examples/codemirror_demo` is NOT a `moon.work` member.** Workspace
members are `lib/*` only (see `moon.work`: `./`, `./lib/text-change`,
`./lib/zipper`, `./lib/btree`, `./lib/moji`,
`./lib/rabbita_codemirror`). Demo lives outside the workspace, gets
exercised via `cd examples/codemirror_demo && moon ...`, and gets
added to CI as a matrix entry in `.github/workflows/ci.yml`'s
`test-examples` job (see Decision 4b).

### Decision 4 — Addon usage on mount

**Sub-decision 4a — Theme::custom is exercised on mount.** Per the
rev-3.7 framing, P2.4 must surface evidence that the
`Theme::custom(empty)` factory is sufficient for happy-path. The
mount call passes `initial_theme=Some(@theme.Theme::custom(@js_ffi.js_extension_combine([])))`.
If the editor renders with no visual style breakage (default CM6
styling), the deferred-factories decision stands.

If the demo surfaces a concrete need for dark theme (e.g., the
swap-tagger readout is unreadable on default styling because the
demo background is dark for design-context reasons), record that as
a P2.3.5 motivation in rev 3.8 — do NOT add the styling fix to
P2.4. Scope discipline.

**Sub-decision 4b — Other `set_*` ops are not exercised.**
`set_theme`, `set_keymap`, `set_line_numbers`, `set_line_wrapping`
are reachable via the public API but not in scope for the six §P2.4
behaviors. Omitting them keeps the demo's Msg/Model small and the
manual smoke fast. P2.5 (migrate `examples/ideal`) is the right
forcing function for those toggles.

**Sub-decision 4c — CI fan-out.** `.github/workflows/ci.yml`'s
`test-examples` matrix (lines 96–103) currently has three entries
(`ideal`, `block-editor`, `canvas`). Add a fourth:

```yaml
          - name: codemirror_demo
            path: examples/codemirror_demo
```

The matrix uses `scripts/run-moon-module.sh ci <path>` which runs
`moon check && moon test` per the script. Demo has no tests; `moon
test` on an empty test set passes trivially. The CI value is
catching compile breaks in the demo when the binding's public API
changes.

## Objective

Build a standalone Rabbita app at `examples/codemirror_demo/` that
exercises the binding's `mount`/`unmount`/`set_doc`/`set_readonly`/
`listen` surface, plus the P2.3 `Theme::custom` factory, against
the six manual-smoke behaviors in plan §P2.4. The demo is the
first end-to-end verification that:

- The binding's public API is consumable from a from-scratch
  rabbita app (no `examples/ideal` coupling).
- The P2.0 `diff_subs` patch + the binding's `update_tagger`
  closure together rebind taggers across renders without
  re-installing the subscription.
- `Theme::custom(empty)` is sufficient for happy-path mount.

## Scope

**Create:**

- `examples/codemirror_demo/moon.mod.json`
- `examples/codemirror_demo/main/client.mbt`
- `examples/codemirror_demo/main/moon.pkg`
- `examples/codemirror_demo/main/pkg.generated.mbti` (via `moon info`)
- `examples/codemirror_demo/index.html`
- `examples/codemirror_demo/package.json`
- `examples/codemirror_demo/vite.config.ts`
- `examples/codemirror_demo/tsconfig.json`
- `examples/codemirror_demo/public/styles.css`
- `examples/codemirror_demo/.gitignore`
- `examples/codemirror_demo/README.md`

**Modify:**

- `.github/workflows/ci.yml` — add the `codemirror_demo` matrix
  entry (per Decision 4c).

**Do NOT touch:**

- `lib/rabbita_codemirror/**` — binding is frozen post-P2.3.
- `rabbita/**` — vendored submodule.
- `moon.work` — demo is intentionally NOT a workspace member (see
  Decision 3).
- Other `examples/**` — P2.4 is the standalone demo. `examples/ideal`
  migration is P2.5.

## Public API consumed (citations)

Demo consumes these symbols. No others:

- `@cm.mount(id, host_id~, init_doc?, initial_theme?, on_mounted?,
  failed?)` — see `codemirror.mbt:321`.
- `@cm.unmount(id, failed?)` — `codemirror.mbt:386`.
- `@cm.set_doc(id, doc, failed?)` — `codemirror.mbt:402`.
- `@cm.set_readonly(id, enabled, failed?)` — `codemirror.mbt:486`.
- `@cm.listen(id, doc?, selection?, focus?)` —
  `codemirror.mbt:558`.
- `@theme.Theme::custom(@js_ffi.Extension)` —
  `addon/theme/theme.mbt:19`.
- `@js_ffi.js_extension_combine(Array[Extension])` —
  `js/pkg.generated.mbti:19`.
- Rabbita's standard surface (`@rabbita.cell`, `@rabbita.new`,
  `@rabbita.none`, `@rabbita.batch`, `@html.*`, `@sub.none`).

## Hard invariants

1. **No new public API on the binding.** `git diff
   lib/rabbita_codemirror/` is empty after Codex completes.
2. **No additions to `lib/rabbita_codemirror/js/pkg.generated.mbti`.**
   Grep clean.
3. **Demo imports only the symbols enumerated above.** Specifically:
   no `@cm.set_theme`, no `@cm.set_keymap`, no `@cm.set_line_numbers`,
   no `@cm.set_line_wrapping`, no `@cm.insert`, no `@cm.replace`, no
   `@cm.set_selection` in `main/client.mbt`. Grep:
   `grep -nE '@cm\.(set_theme|set_keymap|set_line_numbers|set_line_wrapping|insert|replace|set_selection)'
   examples/codemirror_demo/main/client.mbt` → empty.
4. **No `addon/keymap` import in `main/moon.pkg`.** Grep clean.
5. **Sub key constant across the swap.** The two branches of the
   `if model.use_variant_b` ternary in `subscriptions` produce
   `Emit[String]` values; only that varies. No other parameter of
   `@cm.listen` varies based on `use_variant_b`. Code review:
   verify visually.
6. **`Theme::custom(@js_ffi.js_extension_combine([]))` exactly
   once.** Constructed inline at the `mount` call site. No helper,
   no Model-stored Theme. Grep:
   `grep -c 'Theme::custom' examples/codemirror_demo/main/client.mbt`
   → exactly `1`.
7. **No `extern "js"`.** Demo is consumer-side; FFI lives in
   `lib/rabbita_codemirror/js/`. Grep clean.
8. **No escape-hatch APIs in consumer code.** Per
   `rabbita/skills/rabbita.md`: no `@cmd.custom_cmd`,
   `@sub.custom_sub`, `@cmd.effect`, `@cmd.attempt`, `@html.Attrs`,
   `@dom`. Grep clean across `main/client.mbt`.
9. **`#cfg(target="js")` on `main`** (matches `rabbita/examples/
   websocket/main/client.mbt` line 817). The rest of `client.mbt`
   does not need per-fn annotation because the module's
   `supported_targets = "js"` covers it.
10. **`is-main: true`** in `main/moon.pkg` (matches websocket).

## Tests

P2.4 adds **no MoonBit test files**. Verification is the manual
browser smoke (Decision 1 #6 table + plan §P2.4 verification list).
The `moon test` invocation in CI passes trivially on an empty test
set — its value is catching compile-time regressions in the demo
when the binding's API changes.

## Verification (independent re-run by Claude after Codex returns)

1. **Workspace root:** `moon check` clean. Report exit status +
   tail.
2. **Workspace root:** `moon test --target js` — report the
   **literal final-line summary** (e.g., `Total tests: N, passed:
   N, failed: 0`). Do not paraphrase. Rev 3 of the plan documents
   Codex's P2.0 paraphrasing a broken build as green.
3. **Demo:** `cd examples/codemirror_demo && moon check`. Clean.
4. **Demo:** `cd examples/codemirror_demo && moon test`. Literal
   final-line summary (expected: `Total tests: 0, passed: 0,
   failed: 0` or moonbit's equivalent for "no tests defined").
5. **Demo:** `cd examples/codemirror_demo && moon info && moon fmt`.
   Report any diff to `main/pkg.generated.mbti`.
6. **Demo:** `cd examples/codemirror_demo && moon build --target
   js --release`. Clean. Report any warnings.
7. **Demo Vite build:** `cd examples/codemirror_demo && npm install
   && npm run build`. Clean. Report any warnings. `dist/` produced.
8. **Grep checks (paste raw output):**
   - `grep -nE '@cm\.(set_theme|set_keymap|set_line_numbers|set_line_wrapping|insert|replace|set_selection)'
     examples/codemirror_demo/main/client.mbt` → empty.
   - `grep -n 'addon/keymap' examples/codemirror_demo/main/moon.pkg`
     → empty.
   - `grep -c 'Theme::custom' examples/codemirror_demo/main/client.mbt`
     → `1`.
   - `grep -rn 'extern "js"' examples/codemirror_demo/` → empty.
   - `grep -rnE '@cmd\.(custom_cmd|effect|attempt)|@sub\.custom_sub|@html\.Attrs|@dom\.'
     examples/codemirror_demo/main/client.mbt` → empty.
   - `git diff --stat lib/rabbita_codemirror/ rabbita/ moon.work` →
     empty.
9. **CI matrix entry:** `git diff .github/workflows/ci.yml` shows
   exactly one matrix entry added (Decision 4c shape).

## Artifacts contract

Return:

1. Files created/modified, with line counts.
2. Literal final-line `moon test` summary for both workspace root
   and `examples/codemirror_demo` (not paraphrased).
3. `moon check` exit status + tail (or "clean") for both.
4. `moon build --target js --release` output tail for
   `examples/codemirror_demo`.
5. `npm install && npm run build` final-line output for
   `examples/codemirror_demo`.
6. Full `main/pkg.generated.mbti` content (small, paste in full).
7. Full `main/client.mbt` content (paste in full — code review of
   the swap-tagger shape and the Theme::custom call site is the
   load-bearing pre-merge step).
8. `git diff .github/workflows/ci.yml` (just the added lines).
9. Raw output of all six grep checks.
10. Any deviation from this spec, with written justification
    — including formatter-driven shape rewrites.

## Owner

Codex implements; Claude (Opus) reviews:

- The Msg/Model shape matches Decision 2 verbatim (`DocChangedA`,
  `DocChangedB`, `use_variant_b`, `last_variant`).
- The `subscriptions` function returns the same `@cm.listen` call
  on both branches of the ternary, differing only in the
  `emit.map(...)` tagger (Decision 2 + Hard Invariant 5).
- The `Theme::custom(@js_ffi.js_extension_combine([]))` call is
  exactly at the `mount` site, not a helper (Hard Invariant 6).
- `main/moon.pkg` imports match Decision 3 verbatim (no
  `addon/keymap`).
- CI matrix entry matches Decision 4c shape.

Claude additionally runs the manual browser smoke (Playwright CLI,
WSL2; chrome MCP is blocked per global memory) against the six
behaviors. The swap-tagger step (#6) is the load-bearing
verification: type → see "A:" → click "Swap tagger" → type → must
see "B:". If after click-then-type the readout still shows "A:",
the rebind broke (either P2.0's framework patch regressed or
`cm_sub_loader`'s `update_tagger` closure at codemirror.mbt:306–311
is wrong). Triage both possibilities in-session; do not ship the
PR with the smoke failing.

## After dispatch

- Codex returns artifacts → Claude independently re-runs all eight
  verification checks above.
- Codex-review pass via `mcp__codex__codex` MCP: confirm the demo
  matches Decisions 1–4 and Hard Invariants 1–10, with particular
  attention to whether the swap-tagger shape (Decision 2) preserves
  the sub key invariant in `build_listen_key` (codemirror.mbt:258–266).
- Manual browser smoke per the six §P2.4 behaviors (Playwright
  CLI). On the swap-tagger step: triage if the readout fails to
  update. Record outcome in rev 3.8.
- Open PR with title `feat(rabbita_codemirror): P2.4 — minimal demo
  (examples/codemirror_demo)`. Body should call out:
  1. That `Theme::custom(empty)` carried the demo end-to-end
     (validating the rev-3.6/3.7 deferred-factories decision),
     **or** surface the concrete factory gap that warrants a P2.3.5
     mini-PR.
  2. The swap-tagger smoke result (pass/fail and any triage).
- After CI green: `/merge-pr <PR#>`.
- Update plan with rev 3.8 noting:
  - Any Codex deviations from this handoff.
  - The swap-tagger smoke outcome.
  - Whether the demo motivated a P2.3.5 (and if so, what factory
    surface).
- Next PR: P2.5 (migrate `examples/ideal` behind
  `VITE_CANOPY_USE_CM_BINDING=1`) per plan §P2.5.
