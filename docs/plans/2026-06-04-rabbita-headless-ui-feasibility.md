# Headless UI component library on rabbita × Tailwind — feasibility findings

**Status:** findings (source-verified) + design
**Date:** 2026-06-04
**Verified against:** vendored `rabbita/` submodule at **0.12.4 + Canopy patch** (upstream tag `rabbita-v0.12.4` / commit `2dba2dc`, including `closedby` PR #118, plus canopy's `diff_subs/update_tagger` patch, published on `dowdiness/rabbita:update-0.12.4-patched` at `5f828eb`, also tagged `canopy-rabbita-v0.12.4-patched-2026-06-05` on the fork)
**PoC:** `examples/disclosure/` (browser-verified, see §4)
**Follow-up:** P3 native Dialog spike recorded in §5 (docs-only; no `lib/dialog` extraction)

**Original PR scope / done definition:** record the feasibility findings and land
the Disclosure PoC as an experiment. Do **not** extract a reusable
`lib/disclosure` or commit to an animation attribute contract. The follow-up
workspace adoption now points Canopy at the patched Rabbita 0.12.4 fork commit
listed above.

## Conclusion

**Buildable, and more feasible than first assumed.** A Zag/Radix-style headless
component library fits rabbita's TEA model cleanly via a two-layer split:

- **Behavior layer** = TEA `Model`/`Msg`/`update` + pure functions that return
  `@html.Attrs` (the `connect()` / `getTriggerProps()` equivalent). No styling.
- **Design-system layer** = Tailwind `@utility` presets + CSS variables + a thin
  MoonBit `enum Variant → to_class() -> String` helper. Lives in CSS, not types.

Canopy **already ships this exact pattern** in `lib/resizable` + `examples/resizable`
(`@resizable.Model::container_attrs()/handle_attrs()`). The PoC reproduces it for
Disclosure. Radix's `asChild` (React `cloneElement`) cannot be reproduced at the
type level (MoonBit traits: no type params / associated types / HKT), but its
*intent* — spread a behavior's attrs onto a consumer-chosen element — is fully
served by returning `@html.Attrs` and applying it via the element's `attrs?` param.
This is better understood as a prop-getter / render-prop-style lineage than as a
MoonBit clone of `asChild`.

## 1. Why

Question raised: can we build a headless (unstyled, accessible, composition-based)
UI primitive library on rabbita, with a Skeleton-style Tailwind token layer on top?
The original analysis flagged five rabbita API facts as **unverifiable** (source
not fetchable over the web). All five are now resolved from the vendored source.

## 2. The five resolved facts (with citations)

Paths are under `rabbita/rabbita/<pkg>/pkg.generated.mbti`.

| # | Question | Answer | Evidence |
|---|----------|--------|----------|
| a | Do `@html` elements take `attrs?` | **Yes** — every element has `attrs? : Attrs`; low-level `node(String, Attrs, C)` also exists | `html:69` (`div`), `html:153` (`node`) |
| b | Is `Attrs::class` public; ARIA surface? | **Yes**, and the full typed ARIA surface is public via the `Attrs::build()` builder | `html:333` (`build`), `:338` (`class`), `:270-322` (`aria_*`), `:412-442` (`on_*`) |
| c | `@dom.MouseEvent` accessors | Two tiers: raw via `IsMouseEvent` (`get_client_x/_y`, `get_offset_x/_y`, `get_button`…); cooked `@common.Mouse::client_pos()/offset_pos() -> Pos{x,y}` | `dom:780-802`, `common` (`Mouse`) |
| d | `@sub.on_mouse_up`? | **Absent** (observation confirmed). Present: `on_mouse_move`, `on_key_down/up`, `on_animation_frame`, `on_resize`, `on_scroll`, `on_url_*`, `on_visibility_change`, `every`. Document-level `mouseup` needs `custom_sub` | `sub:19-35`, `custom_sub` `sub:13` |
| e | `Html::map`/`Cmd::map`/`Sub::map`? | **None exist.** The only map is `Emit::map(Self[A], (B) -> A) -> Self[B]` — the message-lift primitive | grep `::map` → `cmd:40` only |

## 3. Architecture (validated)

```
Consumer app (TEA: own Model/Msg/update/view)
  └─ Design-system layer   Tailwind @utility presets + CSS vars + enum Variant→to_class()
       └─ Behavior layer   Model/Msg/update + *_attrs(state, emit) -> @html.Attrs
            └─ rabbita      @html / @cmd / @sub / @dom / @dialog
```

Key design decisions, each grounded in a verified fact:

1. **`Attrs::build()` chaining is the rabbita-native `getTriggerProps()`** — typed,
   ergonomic: `.aria_expanded(..).aria_controls(..).on_click(..)` (fact b). A
   primitive returns `@html.Attrs`; the consumer spreads it via `attrs=...` and
   owns all classes. This prop-getter shape serves the useful part of `asChild`
   without cloneElement (fact e rules out `Html.map`-style wrapping).
2. **Message lift = `Emit::map` / emit closures**, not `Html::map` (fact e). The
   doc's "selection 1" (Elm-style `Html.map`) is dead; "selection 3" (emit closure
   composition) is first-class. Nested components use `@rabbita.cell` + `Cell::view()`.
3. **`simple_cell` (Model-only `update`) fits side-effect-free primitives**; full
   `cell` (`(Cmd, Model)` update + `subscriptions`) is for primitives with effects
   (`rabbita:16,35`).
4. **Native `<dialog>` carries some Dialog hard parts, but not all.** rabbita's
   `@dialog` package is a thin binding over `HTMLDialogElement.show_modal()` /
   `close()` / `request_close()` (`rabbita/rabbita/dialog/dialog.mbt`,
   `dom:302-307`, `html:67`). That binding evidence proves the native dialog
   surface exists; it does **not** prove every expected dialog behavior is free.
   Modal inertness / focus trapping and Escape close should be validated in P3;
   light-dismiss is not assumed free and likely needs `closedby="any"` where
   supported or explicit click handling. So the feared "Zag effects → custom
   subs" work shrinks, but light-dismiss and focus-return details remain open.
5. **Splitter/drag** is the one real `custom_sub` case: `on_mouse_move` exists at
   document level (fact d) but document `mouseup` does not — mirror the canonical
   `rabbita/rabbita/websocket/listen.mbt` SubLoader (or an overlay with
   `Attrs::on_mouseup`). `lib/resizable` already does exactly this.

The design-system layer is MoonBit-independent: rabbita view emits `class="…"`
strings, so Skeleton's approach (preset = Tailwind `@utility`, theme = CSS vars +
`data-theme`) applies unchanged. Keep variants as `enum Variant → to_class()`, not
in the type system.

## 4. PoC result — Disclosure

`examples/disclosure/` (registered in `moon.work`). Headless logic inline in
`main/client.mbt`: `DisclosureModel` + `trigger_attrs`/`content_attrs` returning
`@html.Attrs`; consumer `Section` records pair copy with behavior state; view maps
sections onto native `<button>`/`<div>`; `content_id` is the stable panel id
referenced by `aria-controls`; chevron is driven **purely by `aria-expanded`** in
CSS (no extra markup). The example is intentionally a stack of independent
Disclosure widgets, not an Accordion, so panels are not exposed as `region`
landmarks. A small MoonBit test pins the TEA `Toggle` update behavior.

Browser-verified headless (warren `dev`/`build` core-dump in this WSL2 env — broken
even on the known-good `examples/resizable`; bypassed via `moon build --target js`
+ static server + Playwright chromium). **10/10 assertions, 0 console errors:**
sections mount with correct initial state; `aria-controls` == panel `id`;
independent toggle on click; `Enter` toggles focused trigger (native button a11y).
Visual: on-brand, chevron rotates, panel shows/hides.

Validated learning: `hidden` attr gives correct a11y collapse but is instant.
This experiment does **not** reserve a public `data-state` contract; decide that
when P1 polish or P2 extraction makes animation part of the primitive contract.

## 5. P3 result — native Dialog spike

A narrow throwaway spike (not landed as an example or library) was run after PR
#501 merged, starting from `origin/main` at `7f0888d` with the `rabbita`
submodule at `8381bef`. The harness rendered one native `<dialog>` and used
Playwright/Chromium to drive focus, Tab, Escape, page-control clicks, backdrop
clicks, and a `closedby="any"` injection. Injection was necessary for that spike
because the then-pinned Rabbita API could not emit `closedby`. Rabbita 0.12.4 now
exposes `Attrs::closedby` and `dialog(closedby?)`, so a rerun should use
`@html.dialog(closedby="any", ...)` instead of DOM injection.

Findings:

- `@dialog.show("dialog-spike", modal=true)` is Rabbita's command wrapper over
  native `showModal()`. In Chromium it opened a real modal top-layer dialog;
  the autofocus input was focused. Tab did not reach page controls (observed
  sequence: `dialog-input -> dialog-close -> BODY -> dialog-input`). Clicking a
  page button behind the modal kept the page-click counter at `0` and did not
  focus that page button.
- Escape emitted Rabbita `on_cancel`. Rabbita's `push_cancel` calls
  `prevent_default()`, so a dialog with `on_cancel` does not close automatically;
  the app must decide whether to close. The spike returned
  `@dialog.close(..., return_value="cancelled")` from `update`, then received
  `on_close` with the same return value.
- Chromium returned focus to the trigger (`#open-modal`) after Escape, explicit
  close-button close, and `closedby="any"` backdrop close.
- Backdrop click is `closedby`-dependent. Without `closedby`, backdrop click kept
  the dialog open and focused the dialog. With `closedby="any"`, Chromium
  light-dismissed and emitted `cancel` followed by `close` through the spike's
  explicit cancel-close path.
- Rabbita 0.12.4's `closedby` support is an attribute emission API only. MDN
  marks `HTMLDialogElement.closedBy` as non-Baseline, so consumers still need a
  fallback or an explicit browser-support decision; Rabbita does not claim a
  light-dismiss polyfill.

Implication: a future Dialog primitive can lean on native `showModal()` for the
Chromium modal/top-layer/inert/focus-return behavior observed here, but the
primitive must own cancel-close policy and must choose between limited-support
`closedby` and explicit backdrop handling for light-dismiss. Do not extract
`lib/dialog` until a real Canopy consumer exists.

## 6. rabbita 0.12.4 patched adoption status

`moon check` (full workspace) is **green** against 0.12.4 + patch. The single
compatibility fix introduced during the 0.12.3 upgrade remains sufficient for
0.12.4:

- **One breaking call site** from upstream PR #117 (void elements lose `children`):
  `examples/ideal/main/view_actions.mbt` — removed a trailing `[@html.text("")]`
  positional child from `@html.input(...)`. (Two more in
  `loom/incr/examples/typed_spreadsheet_rabbita_demo/view.mbt` — loom submodule,
  not a canopy workspace member; only matters if loom's examples are built.)
- `moon.mod` migration resolves fine through path-deps; no canopy file
  auto-migrated.
- Canopy's Rabbita path-dep pins now say `"version": "0.12.4"` for accuracy.

Canopy now points the `rabbita` gitlink at `5f828eb`, published on the configured
fork remote as `dowdiness/rabbita:update-0.12.4-patched` and pinned by the
separate fork tag `canopy-rabbita-v0.12.4-patched-2026-06-05`, so fresh clones
can resolve the submodule commit even if the review branch later moves. This is
a maintained-fork adoption, not an upstream-only release adoption: the
`diff_subs/update_tagger` patch remains fork-only unless it later lands in
`moonbit-community/rabbita`.

## 7. Roadmap (phased; prose, not paste-ready)

- **P1 — Polish Disclosure**: expand/collapse animation via CSS `data-state` +
  grid-rows; keep `aria-expanded`/`hidden` as the source of truth.
- **P2 — Extract `lib/disclosure`** (`dowdiness/rabbita-disclosure`), mirroring
  `lib/resizable/src/resizable`: `Model`, `Msg`, `update`, `*_attrs`, `new`.
  Cell-ize only when composing stateful instances.
- **P3 — Dialog primitive** on native `<dialog>`: spike complete (§5). Before
  extracting anything, wait for a real consumer and decide cancel-close policy,
  controlled vs uncontrolled shape (consumer `open` + `on_open_change`, or
  self-held in a `cell`), and light-dismiss strategy (`@html.dialog(closedby="any", ...)`
  where supported vs explicit backdrop handling).
- **P4 — Splitter primitive**: reuse `lib/resizable`'s document-`mouseup`
  `custom_sub` pattern; confirm it generalizes.
- **P5 — Design-system layer**: Tailwind `@utility` presets + CSS-var theme +
  `enum Variant → to_class()`. No variant logic in types.

## 8. Caveats

- All PoC artifacts under `/tmp/disc-preview/` are ephemeral (moon-built JS + host
  page); regenerate with `cd examples/disclosure && moon build --target js`.
- `asChild`'s DX (type-safe single-child prop merge) is genuinely unavailable;
  the `@html.Attrs` spread is the accepted substitute.
- Native SSR for the behavior layer is possible (pure Model/Msg/update is target-
  agnostic) but `@html`/`@dom` view code stays JS-only.
