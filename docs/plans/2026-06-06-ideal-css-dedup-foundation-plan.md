# Ideal CSS De-dup Foundation + Tailwind v4 Spike Plan

## Scope and hard constraints
- Scope fence: `examples/ideal/` only.
- Preserve byte-stable class names and exact selector semantics used by current tests.
- Do not touch `leaf-editor.ts`, `text-nodeview.ts`, `cm-inline.ts` CSS injection architecture.
- No redesign of PR #530/#529 artifacts; only relocation + de-dup.
- Verification must use Playwright CLI (WSL2).
- Vite light-DOM stylesheet load (`/styles/editor.css`) must remain.

## 1) Audit & classify all relevant selectors (shadow-only / light-only / overlap)
- Read source anchors already identified:
  - `examples/ideal/web/styles/editor.css`
  - `examples/ideal/web/src/canopy-editor.ts` (constructor + `SHADOW_STYLES`)
  - `examples/ideal/main/view_actions.mbt`
  - `examples/ideal/main/view_outline.mbt` / `view_inspector.mbt` (for other potential overlap)
  - `examples/ideal/web/e2e/structural-editing.spec.ts`
  - `examples/ideal/web/src/canopy-editor.ts` constructor lines (~42–46 and ~248)
- Class provenance pass (script/grep), then tag by rendering surface:
  - `examples/ideal/main/**/*.mbt`: light-host authored view classes.
  - `examples/ideal/web/src/**/*.ts`: treat class writers in CM/PM nodeviews as shadow-rendered; treat `view_editor.mbt` and top-level non-shadow UI as light DOM.
- Practical commands:
  - `rg -o '\.(?:[A-Za-z_][A-Za-z0-9_-]*)(?:[-: .][^,{]*)*' examples/ideal/web/styles/editor.css`
  - `sed -n '248,620p' examples/ideal/web/src/canopy-editor.ts | rg '^\s*\.[A-Za-z.#:]'`
  - `rg -n 'class=\"|className\s*=\s*"|class: \"|\.class\(' examples/ideal/main examples/ideal/web/src`
  - `rg -n 'class\s*=\"action-overlay|action-label|name-prompt|peer-cursor|structure-|ProseMirror' examples/ideal/main examples/ideal/web/src`
- Produce a 3-bucket output artifact (local temp, non-committed):
  - `light-only`
  - `shadow-only`
  - `overlap` plus `overlap-dead-in-light` (no light-DOM consumer found)
- **Verification command**: produce the buckets as a markdown file or console dump and require every overlap selector to have one of the above buckets plus per-selector light-DOM usage proof.
- **Expected result**: overlap-set should contain action-overlay and name-prompt selectors; confirm if `overlap-dead-in-light` is non-empty.

## 2) Create dedicated shadow stylesheet file
- Create: `examples/ideal/web/styles/editor-shadow.css`.
- Move into it:
  - all `shadow-only` rules from `SHADOW_STYLES`.
  - all overlay-related overlap selectors currently in `SHADOW_STYLES` that are `overlap-dead-in-light`.
- Keep `:root` token definitions in `examples/ideal/web/styles/editor.css` only.
- Do not include non-overlay shadow-only rules if they are already covered by `editor.css` token semantics.
- **Verification command**:
  - `rg -n 'SHADOW_STYLES|ProseMirror|structure-|peer-cursor|action-overlay|name-prompt|:starting-style' examples/ideal/web/styles/editor-shadow.css`
- **Expected result**: selectors in shadow file are only the intended subset; `editor.css` still contains unchanged `:root` block.

## 3) Wire delivery via `?inline` + single shared `CSSStyleSheet` + fallback
- In `examples/ideal/web/src/canopy-editor.ts`:
  - import shadow css once with Vite inline import, e.g. `import shadowStyles from '../styles/editor-shadow.css?inline'`
  - replace `SHADOW_STYLES` constant usage.
  - instantiate one module-level `CSSStyleSheet`, `replaceSync(shadowStyles)` once (lazy or static singleton), and assign through `shadowRoot.adoptedStyleSheets`.
  - feature-detect fallback:
    - if `adoptedStyleSheets` available: append shared sheet to `this.shadowRoot.adoptedStyleSheets`
    - else: append `<style>` with `textContent = shadowStyles`.
- Ensure no duplicate append: only one shared stylesheet object for all components.
- Preserve existing light-DOM editor css link in `examples/ideal/web/index.html` unchanged (`/styles/editor.css`).
- Remove `SHADOW_STYLES` constant block from `canopy-editor.ts`.
- **Verification command (compilation breakpoint)**:
  - `cd examples/ideal/web && npm run build`
- **Expected result**: TS build passes; no `SHADOW_STYLES` reference remains.

## 4) Dead-CSS removal in light-DOM sheet
- In `examples/ideal/web/styles/editor.css`, delete overlap selectors validated as `overlap-dead-in-light`.
- Leave overlap selectors still used in light DOM untouched.
- Optionally keep temporary audit notes in file-local comments until cleanup commit.
- **Verification command**:
  - `rg -n '\.action-overlay-scrim|\.action-overlay-panel|\.action-overlay-list|\.action-overlay-item|\.action-group-label|\.action-mnemonic|\.action-label-text|\.name-prompt-(container|label|input|input-row|error)' examples/ideal/web/styles/editor.css`
- **Expected result**: only truly-used light-DOM selectors remain; dead overlap selectors are removed.

## 5) Tailwind v4 spike (overlay-only, on top of adopted-sheet path)
- Spike assets are throwaway:
  - `examples/ideal/web/styles/overlay-tailwind.css`
  - `examples/ideal/web/vite.config.ts` temporary plugin wiring (if absent)
- First, confirm status:
  - `cd examples/ideal/web && rg -n 'tailwind|@tailwindcss/vite|@source|@import "tailwindcss"' vite.config.ts src styles`
  - expected: no existing Tailwind v4 setup in `web` today.
- Spike stylesheet draft:
  - `@import "tailwindcss" source(none);`
  - `@source "../../main/**/*.mbt"`
  - fallback if `.mbt` not scanned: `@source "../../_build/js/release/build/main/**/*.js"` (or exact main js file)
  - add `@layer base { :host { ... } }` for minimal reset consistency
  - add only action-overlay utility classes used by `view_actions.mbt`
- Temporarily route shadow injection to spike stylesheet via one explicit temporary toggle (or local file swap) while executing the spike; keep production path unchanged unless spike passes.
- Adopted-sheet transport remains the same as Step 3 (no separate mechanism).
- PASS/FAIL gate:
  - PASS: scan picks up MBT action classes; overlay renders with computed styles via adopted stylesheet path; existing structural overlay test + new computed-style assertion pass.
  - FAIL: do not merge any Tailwind files; keep Step 3 as shipping baseline.

## 6) Tests
- Keep current e2e suite green.
- Add one Playwright computed-style assertion (single new assertion) against shadow-rendered overlay in:
  - `examples/ideal/web/e2e/structural-editing.spec.ts`
- Proposed pattern:
  - open Var action overlay.
  - resolve `const overlay = page.locator('canopy-editor').locator('.action-overlay-panel')`.
  - after visibility assert, read `getComputedStyle` for a property defined by shadow css (e.g. `backgroundColor`, `minWidth`, `zIndex`).
  - assert non-default value from the intended overlay style.
- **Verification command**:
  - `cd examples/ideal/web && npx playwright test e2e/structural-editing.spec.ts --reporter=line`
- **Expected result**: existing tests pass and the new computed-style assertion catches style regression in shadow transport.

## Resolutions to open questions (design-owner decisions)
1. **`.mbt` scanning in Tailwind v4.** Confirm the current v4 `@source` extractor behavior against docs via **Context7** at the start of Step 5 (not from memory). Empirically test `.mbt` scanning first; the `_build` JS `@source` is the committed fallback if `.mbt` is not picked up. This is a *spike question* — resolving it is the spike's purpose, not a blocker.
2. **Browser matrix for the fallback.** Target evergreen browsers (Chrome/Edge/Firefox, Safari 16.4+), where `adoptedStyleSheets` is native. The `<style>.textContent` fallback exists only as essentially-free insurance for Safari <16.4; no special test matrix is required.
3. **Spike dependency install.** Acceptable as a throwaway devDependency in `examples/ideal/web`. If the spike FAILS, the dep and all spike assets (`overlay-tailwind.css`, vite plugin wiring, the temporary injection toggle) are removed; none of it ships in the Step 1–4 foundation.

## Execution-risk note (human-judgment checkpoint)
The single highest-risk step is the **surface classification in Step 1** (which class renders in light DOM vs the shadow root). Misclassification silently regresses styling. Do **not** fully mechanize this: grep gives provenance, but the light-vs-shadow rendering surface of each class requires reading the view/nodeview that emits it. Treat the 3-bucket output as a reviewed artifact before any deletion in Step 4.
