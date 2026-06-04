# Headless UI component library on rabbita × Tailwind — feasibility findings

**Status:** findings (source-verified) + design
**Date:** 2026-06-04
**Verified against:** vendored `rabbita/` submodule at **0.12.3** (upstream `moonbit-community/rabbita` main `e3865b2` + canopy's `diff_subs/update_tagger` patch, local branch `update-0.12.3-patched` `f6361f2`)
**PoC:** `examples/disclosure/` (browser-verified, see §4)

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
   owns all classes. This is the `asChild` substitute (fact e rules out cloneElement).
2. **Message lift = `Emit::map` / emit closures**, not `Html::map` (fact e). The
   doc's "selection 1" (Elm-style `Html.map`) is dead; "selection 3" (emit closure
   composition) is first-class. Nested components use `@rabbita.cell` + `Cell::view()`.
3. **`simple_cell` (Model-only `update`) fits side-effect-free primitives**; full
   `cell` (`(Cmd, Model)` update + `subscriptions`) is for primitives with effects
   (`rabbita:16,35`).
4. **Native `<dialog>` carries Dialog's hard parts.** rabbita's `@dialog` package is
   a thin binding over `HTMLDialogElement` (`dialog:9-13`, `dom:301-312`,
   `html:67`); focus-trap / Esc / light-dismiss are browser-native. The feared
   "Zag effects → custom subs" work mostly disappears.
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
sections onto native `<button>`/`<div>`; chevron driven **purely by
`aria-expanded`** in CSS (no extra markup). A small MoonBit test pins the TEA
`Toggle` update behavior.

Browser-verified headless (warren `dev`/`build` core-dump in this WSL2 env — broken
even on the known-good `examples/resizable`; bypassed via `moon build --target js`
+ static server + Playwright chromium). **10/10 assertions, 0 console errors:**
sections mount with correct initial state; `aria-controls` == panel `id`;
`role="region"` present; independent toggle on click; `Enter` toggles focused
trigger (native button a11y). Visual: on-brand, chevron rotates, panel shows/hides.

Validated learning: `hidden` attr gives correct a11y collapse but is instant — open
question is animation (CSS grid-rows / `data-state`), deferred.

## 5. rabbita 0.12.3 adoption status

`moon check` (full workspace) is **green** against 0.12.3 + patch after a single fix:

- **One breaking call site** from upstream PR #117 (void elements lose `children`):
  `examples/ideal/main/view_actions.mbt` — removed a trailing `[@html.text("")]`
  positional child from `@html.input(...)`. (Two more in
  `loom/incr/examples/typed_spreadsheet_rabbita_demo/view.mbt` — loom submodule,
  not a canopy workspace member; only matters if loom's examples are built.)
- `moon.mod` migration (0.12.3) resolves fine through path-deps; no canopy file
  auto-migrated.
- The `"version": "0.12.2"` pins in 6 `moon.mod.json` files are advisory (path-deps
  use the path) — bump to `0.12.3` for accuracy when adopting.

Remaining to actually adopt 0.12.3 in canopy (out of scope for this experiment):
push patch `f6361f2` to fork `dowdiness/rabbita` (PR), update canopy submodule
pointer (PR), bump the 6 version pins, fix the loom example sites.

## 6. Roadmap (phased; prose, not paste-ready)

- **P1 — Polish Disclosure**: expand/collapse animation via CSS `data-state` +
  grid-rows; keep `aria-expanded`/`hidden` as the source of truth.
- **P2 — Extract `lib/disclosure`** (`dowdiness/rabbita-disclosure`), mirroring
  `lib/resizable/src/resizable`: `Model`, `Msg`, `update`, `*_attrs`, `new`.
  Cell-ize only when composing stateful instances.
- **P3 — Dialog primitive** on native `<dialog>`: validate the "focus-trap/Esc is
  free" claim; settle controlled vs uncontrolled (config record: consumer `open` +
  `on_open_change`, or self-held in a `cell`).
- **P4 — Splitter primitive**: reuse `lib/resizable`'s document-`mouseup`
  `custom_sub` pattern; confirm it generalizes.
- **P5 — Design-system layer**: Tailwind `@utility` presets + CSS-var theme +
  `enum Variant → to_class()`. No variant logic in types.

## 7. Caveats

- All PoC artifacts under `/tmp/disc-preview/` are ephemeral (moon-built JS + host
  page); regenerate with `cd examples/disclosure && moon build --target js`.
- `asChild`'s DX (type-safe single-child prop merge) is genuinely unavailable;
  the `@html.Attrs` spread is the accepted substitute.
- Native SSR for the behavior layer is possible (pure Model/Msg/update is target-
  agnostic) but `@html`/`@dom` view code stays JS-only.
