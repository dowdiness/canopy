# Ideal Tailwind v4 Migration

## Why

Ideal should migrate to Tailwind v4 as a deliberate design-system move, not as a
shadow-CSS de-dup fix. PR #532 already solved shadow stylesheet duplication via
`editor-shadow.css` + `adoptedStyleSheets`; the Tailwind value is now:

- stronger design-token enforcement through a Tailwind theme layer,
- easier maintenance by colocating low-level visual choices with the MoonBit
  views that render them,
- a shared vocabulary for future Ideal UI work.

GitHub issue: <https://github.com/dowdiness/canopy/issues/533>

Status: PR #534 shipped the first light-DOM slice (action overlay/name prompt).
Future slices must follow the Ideal Tailwind style-management conventions in
[docs/development/ideal-tailwind-style-management.md](../development/ideal-tailwind-style-management.md).

## Scope

In:
- `examples/ideal/web/package.json`
- `examples/ideal/web/package-lock.json`
- `examples/ideal/web/vite.config.ts`
- `examples/ideal/web/index.html` or `examples/ideal/web/styles/editor.css`
  depending on the documented Tailwind v4/Vite entrypoint
- `examples/ideal/web/styles/editor.css`
- `examples/ideal/web/e2e/structural-editing.spec.ts`
- `examples/ideal/main/view_actions.mbt` for the first migration slice

Out:
- non-Ideal example apps
- `leaf-editor.ts`, `text-nodeview.ts`, and `cm-inline.ts`
- PR #531 status/live-region behavior
- PR #530 overlay error behavior beyond preserving it
- PR #532 shadow stylesheet transport beyond reusing it if a later shadow slice
  needs generated CSS
- unrelated `loom` submodule dirt

## Current State

- `examples/ideal/web/styles/editor.css` is the live light-DOM stylesheet and
  now contains the Tailwind v4 entry, token bridge, and explicit `@source` list.
- `examples/ideal/web/styles/editor-shadow.css` is the live shadow stylesheet and
  is adopted into `<canopy-editor>` shadow roots.
- The action overlay and name prompt are light DOM, not shadow DOM.
- PR #534 installed Tailwind v4.3.0 under `examples/ideal/web` only and migrated
  the action overlay/name-prompt declarations to static `.mbt` utility bundles.
- Tailwind source detection is deliberately narrow today:
  `@source "../../main/view_actions_classes.mbt"`; no broad `main/**/*.mbt` scan
  is enabled yet.
- There are roughly 150 `class=` surfaces in `examples/ideal/main/**/*.mbt`, so
  a broad all-at-once utility rewrite remains unnecessary risk.

## Desired State

Tailwind v4 is adopted for Ideal only, with a narrow first slice that proves the
pipeline and the maintainability model without destabilizing the editor.

The first PR is complete. Continuing desired state for later slices:

- Tailwind v4 remains scoped to the Ideal web Vite build.
- Tailwind scans migrated `.mbt` sources intentionally, not accidentally.
- Core Canopy design tokens stay represented in Tailwind's theme layer while
  preserving the existing CSS custom properties used by shadow CSS and runtime
  integrations.
- Each migrated slice is Tailwind-owned and removes duplicate legacy CSS
  declarations.
- Existing semantic class names remain as stable selectors/test hooks
  (`.action-overlay-panel`, `.action-overlay-item`, `.name-prompt-input`, etc.).
- Reusable style choices move toward an Ideal-local recipe layer, not toward
  shadcn React components, Radix by default, `@apply`, or broad source scanning.

## Design Choices

### 1. Tailwind as a design-system layer, not an instant rewrite

The first slice should keep semantic classes as compatibility anchors and add
Tailwind utilities around them. Example shape:

```moonbit
class="action-overlay-scrim fixed inset-0 z-[50] bg-black/30"
```

This preserves E2E selectors while allowing migrated visual declarations to live
with the view code. Later slices can decide case-by-case whether a semantic
component class remains useful or is only a test hook.

### 2. Token bridge first

Do not duplicate raw color/spacing literals in two systems. Start with the
existing `:root` custom properties as the compatibility source of truth and map
Tailwind theme variables to them. Before implementation, confirm the exact
Tailwind v4 syntax from Context7/current docs, especially whether aliases to CSS
variables require `@theme inline`.

Candidate token families to expose first:

- colors: `canopy-bg`, `canopy-panel`, `canopy-surface`, `canopy-border`,
  `canopy-fg`, `canopy-muted`, `canopy-accent`, `canopy-error-text`
- fonts: `canopy-ui`, `canopy-mono`
- spacing: `canopy-xs`, `canopy-sm`, `canopy-md`, `canopy-lg`, `canopy-xl`
- radii: `canopy-sm`, `canopy-md`, `canopy-lg`
- motion: `duration-canopy-fast`, `ease-canopy-out`

### 3. Avoid broad preflight risk in the first slice

The Ideal stylesheet already has a reset and component-level base rules. The
first implementation must use the current Tailwind v4 docs to decide whether to
import full Tailwind or only the theme/utilities layers. Prefer avoiding
Tailwind preflight in the first slice unless browser verification shows no
regression.

### 4. One migrated owner per declaration

For every migrated declaration moved to Tailwind utilities, delete the same
legacy declaration from CSS. If a declaration must remain in CSS because it is
not meaningfully expressible as a utility (for example a custom keyframe), keep
that CSS as the explicit owner and document why. Do **not** use Tailwind
`@apply`; repeated utility groups should become MoonBit constants or theme
tokens instead.

## Steps

1. **Doc gate before dependencies**
   - Use Context7/current Tailwind docs for:
     - Tailwind v4 + Vite setup,
     - `@source` behavior for non-standard source files,
     - CSS-first theme configuration (`@theme` / `@theme inline`),
     - layer-specific imports if avoiding preflight.
   - Record the exact docs/version in the PR description.

2. **Install Tailwind for Ideal web only**
   - Add Tailwind v4 dev dependencies under `examples/ideal/web` only.
   - Update `examples/ideal/web/package-lock.json` from that directory.
   - Wire the Vite plugin in `examples/ideal/web/vite.config.ts` per docs.
   - Do not touch workspace-level package metadata.

3. **Create the Tailwind entry + token bridge**
   - Keep the existing `/styles/editor.css` light-DOM delivery path unless docs
     require a different Vite-processed entry.
   - Add Tailwind imports and explicit `@source` entries for each migrated
     source file from `examples/ideal/web/styles/editor.css`; the first slice
     starts with `../../main/view_actions_classes.mbt` only.
   - Add the first theme-token bridge to existing `--canopy-*` variables.
   - Add a temporary sentinel utility during local validation only; remove it
     before commit.

4. **Migrate the action overlay/name prompt slice**
   - Update `examples/ideal/main/view_actions.mbt` class strings to include
     Tailwind utilities while preserving semantic classes.
   - Cover:
     - scrim
     - panel sizing/position/surface/border/shadow/animation
     - list layout
     - group labels
     - items including hover/active/danger states
     - mnemonic badge
     - label text
     - name prompt layout/input/focus/placeholder
     - overlay error
     - mobile adjustments currently under `@media (max-width: 768px)`
   - Remove migrated declarations from `editor.css` so the overlay has one live
     owner.

5. **Add style ownership assertions**
   - Extend `examples/ideal/web/e2e/structural-editing.spec.ts` with computed
     style checks for the light-DOM overlay, e.g. background, border color,
     min-width, z-index, and input focus ring.
   - Keep existing behavioral overlay tests unchanged.

6. **Build and browser-verify**
   - Run the validation commands below.
   - Use Playwright CLI for a manual smoke pass if automated style assertions are
     inconclusive.
   - Compare built CSS size before/after; investigate if the first slice grows
     the built CSS by more than about 10 KiB uncompressed.

7. **Prepare later slices only after the first PR is green**
   - Establish the Ideal-local UI recipe layer (`examples/ideal/main/ui/*`) as
     described in `docs/development/ideal-tailwind-style-management.md`.
   - Toolbar/app shell or action-button chrome.
   - Outline panel and tree rows.
   - Inspector panel.
   - Bottom tabs/log panels.
   - History/Incr graph raw-HTML fragments.
   - Shadow-owned structure styles only if the first light-DOM migration proves
     stable and the adopted stylesheet path remains unchanged.

## Acceptance Criteria

- [x] Tailwind v4 is installed only in `examples/ideal/web`.
- [x] The Ideal Vite build generates Tailwind utilities from `.mbt` source.
- [x] Tailwind theme tokens bridge to the existing Canopy CSS custom properties.
- [x] The action overlay/name-prompt visual declarations are Tailwind-owned.
- [x] Existing semantic class selectors used by tests remain valid.
- [x] `editor.css` no longer contains duplicate live declarations for the
      migrated overlay/name-prompt properties.
- [x] `leaf-editor.ts`, `text-nodeview.ts`, `cm-inline.ts`, and `loom` are
      untouched.
- [x] Issue #533 can be updated to say migration is approved and first slice is
      planned/implemented.

## Validation

```bash
git status --short
moon check
moon test
cd examples/ideal/web && npm run build
cd examples/ideal/web && npx playwright test e2e/structural-editing.spec.ts --reporter=line
```

For the PR body, also include:

```bash
cd examples/ideal/web && wc -c dist/assets/*.css
rg -n "tailwind|@tailwindcss/vite|@source|@theme" examples/ideal/web
rg -n "action-overlay|name-prompt" examples/ideal/web/styles/editor.css examples/ideal/main/view_actions.mbt
```

## Rollback Criteria

Rollback the first Tailwind slice completely if any of these hold:

- Tailwind cannot be made to scan `.mbt` source through documented v4 APIs.
- The Vite integration requires changing non-Ideal build infrastructure.
- Overlay behavior or accessibility regresses in Playwright.
- Computed overlay styles differ materially from the pre-migration baseline and
  the difference is not an intentional design-system normalization.
- The first slice causes disproportionate CSS growth (> about 10 KiB
  uncompressed) without a clear explanation.
- Preserving semantic selectors plus utility classes proves less maintainable
  than the existing CSS for this slice.

Rollback means removing Tailwind dependencies, Vite wiring, Tailwind CSS entry
changes, and `.mbt` utility-class edits, returning to the PR #532 foundation.

## Risks

- Tailwind preflight could subtly alter existing form/button/layout defaults;
  avoid or explicitly verify it in the first slice.
- Long utility strings in MoonBit views can become hard to read. Prefer small
  local string constants for repeated utility groups if the slice becomes noisy.
- Tailwind utilities and legacy semantic CSS can fight in the cascade. Delete or
  isolate migrated legacy declarations immediately.
- Dynamic class fragments such as `depth-{depth}` and `kind-{...}` will need
  safelisting or a semantic-class bridge in later slices; do not tackle them in
  the first PR.
- Raw HTML fragments in history/incr/bottom views require a separate audit
  because class strings are embedded inside HTML strings.

## Notes

- This plan supersedes the earlier no-migration rationale: the product decision
  is now to migrate, but incrementally.
- PR #532 remains the baseline. Tailwind must build on the de-dup foundation, not
  reopen shadow stylesheet duplication.
