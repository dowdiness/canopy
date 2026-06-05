# #505 — Migrate Ideal bottom tabs to a reusable headless Tabs behavior

**Status:** completed in PR #517 · **Date:** 2026-06-05 · **Issue:** #505
**Precedent:** `lib/menu` (the already-merged headless primitive; mirror it).
**Design owner:** Opus · **Plan authoring:** Codex ("Opus orchestrates, Codex plans").

## Goal

Extract the WAI-ARIA tablist keyboard/ARIA behavior currently inlined in
`examples/ideal/main/view_bottom.mbt` (`view_bottom_tabs`, `bottom_panel_attrs`,
and the id/slug/focus helpers) into a reusable headless package `lib/tabs`
(module `dowdiness/rabbita-tabs`, package `dowdiness/rabbita-tabs/tabs`), and
make the Ideal editor consume it. Behavior-preserving for the user.

## Converged design (the WHAT)

**Responsibility split.**
- Library owns the tab-**button** id scheme: `tab_button_id(i) = id + "-tab-" + i`
  (mirrors menu's `item_id`). Verified safe: nothing references the old slug
  button ids.
- Consumer owns **panel** ids and passes them in — mandatory because
  History/Graphviz/IncrGraph keep legacy ids `canopy-{name}-container` that
  render cmds write `innerHTML` to and E2E specs locate. Must be preserved.
- Behavior is **derived/stateless**: durable selection stays in the consumer's
  `model.bottom_tab : BottomTab`. The library `Model` is a per-render snapshot
  built from `(id, tab_count, selected)`. No stored `@tabs.Model`, no
  `Msg`/`update` (unlike menu, whose focus state is ephemeral/consumer-external).
- **Automatic activation** (selection follows focus): arrow/Home/End immediately
  select+focus the target tab — exactly today's behavior. Horizontal only:
  ArrowLeft/Right wrap, Home/End jump; ArrowUp/Down intentionally unhandled
  (APG reserves them for scroll).

**Public API (`lib/tabs/src/tabs`).**
- `Model::new(id~, tab_count~, selected~)` — clamp `tab_count >= 0`, `selected`
  into `[0, tab_count-1]`; `tab_count==0` deterministic + safe across all getters.
- `Model::nav_target(self, key) -> Int?` — pure keyboard core (the unit-tested
  surface). None for unhandled keys and for `tab_count==0` (no mod-by-zero).
- `Model::tab_button_id(self, index) -> String`.
- `Model::tablist_attrs(self, label~) -> @html.Attrs` — role=tablist, aria-label.
- `Model::tab_attrs(self, index, panel_id~, dispatch : (Int) -> @cmd.Cmd)` —
  id, role=tab, aria-selected, roving tabindex, aria-controls **only when
  selected**; on_click → dispatch(index); on_keydown → nav_target → prevent_default
  + dispatch(target) else none. `#cfg(target="js")` / non-js split like menu.
- `Model::panel_attrs(self, index, panel_id~)` — id=panel_id, role=tabpanel,
  aria-labelledby=tab_button_id(index), tabindex=0.
- `Model::focus_cmd(self)` — focus selected tab button after_render; #cfg split.

The `dispatch : (Int) -> @cmd.Cmd` callback keeps the library domain-agnostic;
the consumer maps index→`BottomTab`.

## Steps (Codex-authored)

1. Create `lib/tabs` skeleton mirroring `lib/menu` (moon.mod.json, src/tabs/moon.pkg,
   types.mbt, attrs.mbt, tabs_wbtest.mbt, README.md). Check + test.
2. `Model::new` + `nav_target` + `tab_button_id` in types.mbt. Define `tab_count==0`.
3. `tablist_attrs`/`tab_attrs`/`panel_attrs`/`focus_cmd` in attrs.mbt (js/non-js split,
   reuse menu's `focus_element_by_id` extern shape).
4. `tabs_wbtest.mbt`: nav_target (arrows/Home/End/wrap/unhandled/empty), `new`
   clamping, `tab_button_id` format, aria-controls-only-when-selected.
5. `NEW_MOON_MOD=0 moon info && moon fmt`; review `pkg.generated.mbti` diff = minimal.
6. Register `./lib/tabs` in `moon.work`. Workspace check.
7. Import `dowdiness/rabbita-tabs/tabs` in `examples/ideal/main/moon.pkg` (as `@tabs`).
8. Migrate `view_bottom_tabs`: rename local `tabs` → `tab_defs`; build one
   `@tabs.Model::new(id="canopy-bottom-tabs", tab_count=…, selected=…)`; replace
   per-button attrs with `@tabs.tab_attrs(i, panel_id=bottom_tab_panel_id(tab),
   dispatch=fn(j) => dispatch(SelectBottomTab(tab_defs[j].0)))`; keep class strings + labels.
9. Replace `bottom_panel_attrs` body with `@tabs.panel_attrs(index, panel_id=…)`;
   keep `bottom_tab_panel_id` (legacy-id exceptions) and `bottom_tab_slug`.
   Remove now-unused `bottom_tab_button_id`.
10. Rewire `SelectBottomTab` focus: `bottom_tab_focus_cmd` builds the `@tabs.Model`
    for the selected tab and returns `focus_cmd()`. No new model field.
11. `moon info && moon fmt` for ideal/main; review .mbti diff (imports only).
12. New E2E `examples/ideal/web/e2e/bottom-tabs-keyboard.spec.ts`: focus a tab,
    ArrowRight/Left/Home/End move selection+focus & aria-selected; ArrowUp/Down do not.
13. Workspace `moon test` + ideal `moon test` + tab E2E specs (build recipe below).
14. Sanity: legacy container ids intact; role/name selectors still pass.

## Verification

- Per-edit: `NEW_MOON_MOD=0 moon check` (package dir, then consumer).
- `NEW_MOON_MOD=0 moon info && moon fmt`; `git diff *.mbti` minimal.
- `NEW_MOON_MOD=0 moon test` (lib/tabs + workspace + ideal).
- E2E (WSL2 recipe — warren dev/build may core-dump): build JS via
  `examples/ideal/web` → `npm run prebuild:moonbit` (= `MOON_WORK=off moon build
  --target js --release`), serve, then `npx playwright test e2e/editor-features.spec.ts
  e2e/history.spec.ts e2e/incr-graph.spec.ts e2e/bottom-tabs-keyboard.spec.ts`.

## Non-goals

No vertical tabs, no manual-activation mode, no panel-content/SVG-cache changes,
no bottom-panel UI redesign, no public-API growth beyond in-package callers.
