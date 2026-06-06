# Ideal editor CSS: de-dup foundation + Tailwind feasibility spike

**Date:** 2026-06-06
**Status:** Foundation shipped in PR #532; Tailwind migration deferred pending product/payoff decision
**Scope:** `examples/ideal/` only. The other four apps (`demo-react`, `codemirror_demo`, `resizable`, `disclosure`) are untouched.

This is a design document: it states *what* to build and *why*. The step-ordered *how* lives in the archived implementation plan (`docs/archive/2026-06-06-ideal-css-dedup-foundation-plan.md`).

## Problem

The Ideal editor maintains the same visual rules twice:

- `examples/ideal/web/styles/editor.css` — light DOM, 1463 lines.
- A `SHADOW_STYLES` template-literal constant in `examples/ideal/web/src/canopy-editor.ts` (definition at line 248, injected via `<style>.textContent` into a `mode: 'open'` shadow root at lines 42–46).

Renaming or editing a shared rule requires touching both, or shadow-rendered elements silently go unstyled. This duplication is documented (`project_ideal_overlay_css_dual_location`) and was caught by Codex in PR #530.

User goals (confirmed): **kill the duplication**, **improve maintainability**, **design-token consistency**. *Not* team-familiarity/DX.

## The reframe: what actually causes the duplication

The duplication is **not** caused by the absence of a utility framework. It is caused by a CSS scoping asymmetry:

- **Custom properties cross the shadow boundary** via inheritance. That is why `SHADOW_STYLES` writes `var(--canopy-bg, fallback)` without redefining the token — the `:root` token defs already reach into the shadow tree. Design-token consistency (goal 3) is therefore *already* solved at the token-definition level.
- **Class-based rules do not cross the shadow boundary.** A `.action-overlay { … }` rule in the light-DOM stylesheet cannot style an element inside the shadow root. So the rules are hand-authored a second time inside `SHADOW_STYLES`.

The minimal fix is therefore: **author the shadow rules once, deliver that one stylesheet into the shadow root** via `adoptedStyleSheets`. This needs no framework.

**Consequence for the Tailwind question:** Tailwind would need this *same* delivery path — its generated sheet must also be adopted into each shadow root. So Tailwind does not dissolve the duplication "for free"; the adopted-stylesheet transport is the real fix, reusable with or without Tailwind. Tailwind's *distinctive* value over plain single-source CSS is only (a) utility colocation in the `.mbt` views and (b) token *enforcement* via `@theme` — and that value costs an unproven `.mbt` content-scanner plus a ~117-site `class="…"` rewrite.

This yields a **foundation-first, spike-gated** approach rather than a committed migration.

## Post-merge correction (PR #532)

Runtime verification corrected one important assumption in the original spike shape: the action overlay and name prompt render in the **light DOM**, not inside `<canopy-editor>`'s shadow root. Their live rules are therefore the existing `editor.css` rules. The duplicate overlay block inside `SHADOW_STYLES` was dead shadow CSS and was deleted with the rest of the template literal; no light-DOM CSS was removed.

The shipped foundation still follows the design's core direction: `editor-shadow.css` is now the single source for shadow-owned rules, delivered via a shared constructable stylesheet with `<style>` fallback. The Tailwind spike also passed the remaining technical question: Tailwind v4 can scan `.mbt` class strings via `@source "../main"`. A broader Tailwind migration is feasible but deferred as a product/payoff decision.

## Direction (chosen): C — foundation-first, spike-gated

### Step 1 — De-dup foundation (ships the duplication fix immediately)

**Files in scope:** `canopy-editor.ts`, `editor.css`, and one new stylesheet file — **not** `leaf-editor.ts`/`text-nodeview.ts`, which inject CodeMirror 6's own styles via `createInlineCm({ root: this.shadowRoot })`, a different mechanism that carries no `SHADOW_STYLES` constant. The audit notes them but Step 1 does not restructure them.

**1. Audit & classify (empirical — read and diff, do not assume).** Partition every rule in `editor.css` and the single `SHADOW_STYLES` block into three buckets:

- **light-only** — `:root` token defs, `body`, the `canopy-editor` host element, scrollbar preflight, media-query/responsive rules. These are coupled to document-level layout and **stay in `editor.css`**. Moving them into a shadow sheet would be inert or leak.
- **shadow-only** — classes emitted only inside the shadow tree (`structure-*`, `drop-*`, peer-cursor decorations) that are **not** present in `editor.css`. These are not duplicated; they simply relocate from the string into the new file.
- **overlap** — the genuine duplication (rules present in both sources). For each overlap rule the audit asks: *does any light-DOM element actually use this class?* If **no**, the light-DOM copy is dead CSS → delete it. If **yes**, it is single-sourced and delivered to both contexts.

**2. Single source for shadow rules.** The shadow-needed set (shadow-only + the shadow side of overlaps) moves into **one new stylesheet file**, which becomes the authoritative source for shadow styling. Token defs remain in `editor.css` and continue to inherit into the shadow.

**3. Delivery via `adoptedStyleSheets`.** Import the new file with Vite `?inline` → construct **one** shared `CSSStyleSheet` → assign it to the shadow root's `adoptedStyleSheets`, deleting the `SHADOW_STYLES` constant. Chosen over the current `<style>.textContent` because a single parsed sheet is shared across all editor instances, and — decisively — it is the exact transport the Tailwind spike reuses. A **feature-detect fallback** to `<style>.textContent` (reusing the same `?inline` string) guarantees no engine loses shadow styling.

**Invariant — relocation, not redesign.** Overlay class names are asserted by exact name in Playwright (`.action-overlay-panel`, `.action-overlay-item[data-active="true"]`, `.name-prompt-container`). All class names and selector semantics are held byte-stable. PR #530 (overlay error fold) and #529 (resizable) behavior is preserved.

### Step 2 — Tailwind v4 feasibility spike (one component, throwaway)

The original cheap experiment targeted the **action overlay** because its classes are generated in `.mbt` (`view_actions.mbt`). After PR #532, the technical questions separate cleanly:

- **Scan:** Can Tailwind v4 extract class strings from `.mbt` source via an `@source` glob over `examples/ideal/**/*.mbt`? Yes — the throwaway spike proved `@source "../main"` picks up `.mbt` class tokens, with a negative control.
- **Deliver:** Can generated CSS land inside the `canopy-editor` shadow root? Yes in the generic sense — PR #532 proves the adopted-stylesheet transport with a computed-style assertion on shadow-rendered `.structure-block`. The overlay itself is light DOM, so it does not need shadow delivery.

**Decision gate (explicit):** a full Tailwind migration should proceed only if the maintainability/token-enforcement payoff justifies the large `class="…"` rewrite. The foundation already delivered the duplication fix, so migration remains optional.

### Step 3 — Broad Tailwind migration (deferred, undesigned)

Not designed here. Gated on the spike passing **and** the maintainability/enforcement payoff justifying the ~117-site `class="…"` rewrite. If pursued: **Ideal first, never all five apps at once.** Step 1 deliberately splits along the light-tokens / shadow-shell boundary, which gives the spike a stable path **without** locking in any Tailwind-specific file layout.

## Testing

- Existing Ideal Playwright e2e suite must stay green through Step 1 (relocation should be behavior-neutral).
- **New computed-style assertion** on a shadow-rendered `.structure-block`. The prior e2e asserted *text*, not *style* — that gap is precisely how the duplication hid. This assertion closes it and guards the de-dup.

## Non-goals / scope fence

- No changes outside `examples/ideal/`.
- No "while we're here" cleanup of PR #530/#529 CSS — those rules move byte-stable.
- No restructuring of the `leaf-editor.ts`/`text-nodeview.ts` CM6 injection path.
- No commitment to Tailwind. Step 1 stands on its own; Tailwind is evaluated, not assumed.

## Validation record

- Codex design review (2026-06-06): verdict `sound-with-caveats`. Core framing (custom-props cross the boundary, class rules do not, `adoptedStyleSheets` is the de-dup transport Tailwind also needs) confirmed correct. Corrections folded in: (1) `SHADOW_STYLES` is `canopy-editor.ts`-only — verified; (2) shadow set is not a clean subset of `editor.css` — `structure-*`/`drop-*`/peer-cursor are shadow-only, so the audit must move the full shadow set, not just overlaps; (3) `adoptedStyleSheets` needs a `<style>` fallback.
- PR #532 shipped the foundation and corrected the overlay ownership assumption: overlay/name-prompt are light DOM; shadow ownership is `:host`, `#editor-root`, `.ProseMirror`, `.structure-*`, and peer-cursor decorations.
