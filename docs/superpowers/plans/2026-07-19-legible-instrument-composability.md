# Legible Instrument Composability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make design-first composability part of Canopy’s canonical design direction and prove it through the `genui-possibilities` reference surface.

**Architecture:** `.impeccable.md` becomes the canonical concise design context; the approved specification remains the detailed contract. The reference surface demonstrates the contract using perceptual layout primitives and product-responsibility components, while its state reducer preserves identity, authority, reversibility, and negotiability. Browser tests verify observable composition laws across desktop, mobile, keyboard, accessibility, and motion modes.

**Tech Stack:** Markdown, semantic HTML, CSS, vanilla JavaScript, Node test runner, Playwright.

## Global Constraints

- Design first, architecture second: semantic models and projection infrastructure support the visual grammar rather than define it.
- One bounded workspace has one focal question and at most one primary region.
- Spacing, alignment, boundaries, color, actions, reflow, and motion communicate relationships and causality.
- Desktop and 390 px mobile layouts retain decision-critical evidence and equivalent actions.
- Selection never commits; preview precedes apply; apply creates a revision; undo restores the prior revision.
- Generated or inferred grouping, hierarchy, emphasis, and projection remain distinguishable and negotiable.
- Pointer, keyboard, screen-reader, reduced-motion, higher-contrast, and 200% text-zoom paths preserve comprehension.
- Do not create a second design system or extract shared abstractions before the reference surface demonstrates generality.
- After every file edit, run `moon check` before editing another file.

---

### Task 1: Publish the canonical design context

**Files:**
- Modify: `.impeccable.md`
- Reference: `docs/superpowers/specs/2026-07-19-legible-instrument-design.md`
- Reference: `docs/architecture/human-centered-product-principles.md`

**Interfaces:**
- Consumes: approved Legible Instrument specification and canonical human-centered product invariants.
- Produces: the concise design context used by future UI work; no runtime API.

- [ ] **Step 1: Replace obsolete visual-brand direction**

  Remove dark-mode primacy, deep navy and purple brand identity, night-sky imagery, translucent material, proprietary-font dependence, and external-brand imitation. Preserve no compatibility paragraph for the retired direction.

- [ ] **Step 2: Define the product-quality model**

  State the five usability costs—translation, orientation-recovery, verification, action-uncertainty, and recovery—and the causal interaction model: Context, Artifact, Change, Decision, and Trace. Define accessibility separately as an equivalence invariant, then link to the canonical product principles instead of duplicating them.

- [ ] **Step 3: Define compositional design**

  Record one focal question, relative emphasis, the six spatial relationships, relational spacing, shared alignment, boundary economy, color budget, action mapping, information-preserving reflow, coordinated motion, and negotiability. Keep these as perceptual and interaction rules; do not turn the file into a component API or renderer architecture.

- [ ] **Step 4: Define the visual and interaction constraints**

  Specify the light warm-neutral foundation, semantic color roles, typography roles, focus behavior, touch target minimum, press/selection/disclosure timing, reduced-motion behavior, preview-before-apply, stable artifact identity, revision trace, and undo.

- [ ] **Step 5: Verify the context file**

  Run `moon check` from the worktree root. Expected: zero errors; existing vendored warnings may remain. Search `.impeccable.md` for the retired direction terms and confirm they appear only where explicitly identified as rejected patterns, if at all.

- [ ] **Step 6: Commit the canonical direction**

  Commit `.impeccable.md` separately with a design-context commit message so the direction change can be reviewed independently from the reference implementation.

---

### Task 2: Make the reference surface composition explicit

**Files:**
- Modify: `examples/web/genui-possibilities.html`
- Modify: `examples/web/src/genui-possibilities.css`
- Reference: `docs/superpowers/specs/2026-07-19-legible-instrument-design.md`

**Interfaces:**
- Consumes: existing journey state rendered by `genui-possibilities.js` and the canonical design context from Task 1.
- Produces: stable semantic regions and CSS relationships used by Task 3 behavior and Task 4 browser validation.

- [ ] **Step 1: Name the focal question and responsibility regions**

  Make the workspace’s central question explicit in the visible heading and accessible naming. Ensure disruption context, persistent itinerary artifact, response comparison, decision preview, actions, and revision trace each have one product responsibility and a meaningful heading relationship.

- [ ] **Step 2: Express hierarchy through composition**

  Keep one primary decision region. Make artifact and disruption supporting regions and revision history a reference region. Remove component-local framing that causes nested cards, duplicate radii, repeated backgrounds, or competing headings.

- [ ] **Step 3: Apply the spatial grammar**

  Use a desktop split for persistent artifact and decision work, a grid for shared comparison axes, clusters for compact metadata/actions, stacks for narrative reading, and insets for local rationale. Keep supplemental evidence in flow; do not use overlays for ordinary detail.

- [ ] **Step 4: Preserve shared alignment and relational spacing**

  Align response names, arrival, cost, consequence, and selection/action boundaries across rows. Enforce the spacing order from within-element through between-responsibility spacing. Use spacing before adding visual boundaries.

- [ ] **Step 5: Enforce boundary and color budgets**

  Give each remaining rule, background difference, or emphasis a distinct relationship. Keep ordinary content neutral, interaction in the shared action role, and warning/success colors limited to real state. Ensure selection and success remain distinguishable without color.

- [ ] **Step 6: Implement information-preserving mobile reflow**

  At 390 px, transform comparison columns into repeated label/value relationships inside each option. Preserve arrival, cost, consequence, evidence, selection, preview, apply, and undo. Keep the primary action adjacent to its decision without obscuring content.

- [ ] **Step 7: Check the edited surface**

  After each file edit run `moon check`. Then run the existing web build command from `examples/web`. Expected: a successful Vite production build with no new JavaScript or CSS errors.

- [ ] **Step 8: Commit the composition pass**

  Commit HTML and CSS together because their semantic regions and visual relationships form one reviewable contract.

---

### Task 3: Preserve composition through interaction state

**Files:**
- Modify: `examples/web/src/genui-possibilities.js`
- Reference: `examples/web/src/genui-journey-state.js`
- Test: `examples/web/src/genui-journey-state.test.mjs`
- Test: `examples/web/tests/genui-possibilities.spec.ts`

**Interfaces:**
- Consumes: semantic region IDs/classes from Task 2, fixed-length and fixed-order journey state from `transitionJourney`, and the existing reducer regression tests.
- Produces: persistent itinerary and response DOM nodes whose identity survives selection, preview, apply, revision, and undo.

- [ ] **Step 1: Establish the reducer baseline**

  Run the existing journey-state tests and confirm that selection does not mutate the itinerary, apply preserves `planId` and records one revision, and undo restores the prior plan. Add one table-driven reducer regression covering `early`, `overnight`, and `wait`: after applying each option, the protected `Chichu Art Museum · tomorrow 10:30` item remains unchanged; after undo, it remains unchanged in the restored plan. This test is expected to pass against the current reducer and pins the fixed-length/fixed-order precondition used by Step 2. If it fails, stop and correct the state boundary before changing the renderer.

- [ ] **Step 2: Preserve stable rendered identity**

  Replace collection-wide `innerHTML` updates with explicit persistent-node rendering. Create the four itinerary nodes and three response nodes once during initial render; keep them keyed by itinerary index and `response.id`, respectively. On subsequent renders, mutate only text, classes, `aria-checked`, `tabindex`, and protected/change indicators on those same nodes. The current reducer fixes both collection lengths and order, so this task does not introduce general insertion, removal, reordering, or a reusable DOM-diff abstraction. Keep focus, radio position, revision target, and artifact identity stable across selection, apply, and undo.

- [ ] **Step 3: Keep authority boundaries perceptible**

  Ensure selection changes preview only. Apply remains disabled until a valid preview exists. Applying changes the itinerary and creates a visible revision; undo acts on that revision. No row click, focus movement, or disclosure commits a change.

- [ ] **Step 4: Preserve negotiability**

  Ensure protected or inferred itinerary structure is visibly identified and remains independently addressable by the renderer. Do not bake inferred emphasis or grouping into irreversible markup/state.

- [ ] **Step 5: Coordinate feedback and motion**

  Give press, selection, disclosure, apply, and undo one causal response each. Do not replay entrance animation on stable regions. Preserve immediate keyboard focus and provide a reduced-motion equivalent without spatial movement.

- [ ] **Step 6: Run focused behavior checks**

  Run the journey-state Node test file. Expected: all reducer contracts pass. Run `moon check` after each source edit. Run the web production build after the JavaScript changes. Expected: zero new errors.

- [ ] **Step 7: Commit the behavior pass**

  Commit reducer tests and behavior implementation together as a separate interaction-state change.

---

### Task 4: Prove the composition laws in the browser

**Files:**
- Modify: `examples/web/tests/genui-possibilities.spec.ts`
- Modify if required by the existing dev entry: `examples/web/vite.config.ts`
- Reference: `examples/web/playwright.config.ts`

**Interfaces:**
- Consumes: semantic regions from Task 2 and deterministic interaction states from Task 3.
- Produces: executable evidence for desktop/mobile parity, action locality, authority, reversibility, accessibility, and feedback behavior.

- [ ] **Step 1: Verify focal clarity and action mapping**

  Retain the existing roving-radio and 390 px arrival/cost/overflow tests. Add assertions for the currently uncovered contracts: one accessible primary question, consequence visibility for every mobile response, selection exposing its local preview without changing the itinerary, apply remaining disabled before preview and acting on that preview afterward, and undo appearing beside the created revision. Avoid assertions on private class names when an accessible role/name expresses the contract.

- [ ] **Step 2: Verify desktop comparison**

  At the project desktop viewport, assert every response exposes the same decision-critical comparison fields and that itinerary, decision preview, and actions are simultaneously reachable without horizontal page overflow.

- [ ] **Step 3: Verify 390 px information parity**

  At 390 px, assert every response still exposes arrival, cost, and consequence; the page has no horizontal overflow; and the action area does not obscure the selected option, preview, or revision feedback.

- [ ] **Step 4: Verify keyboard and accessible order**

  Exercise radio roving with Arrow keys plus Home and End, preview, apply, revision, and undo without pointer input. Confirm focus remains visible and lands on the causally relevant control or result. Assert accessible names, roles, checked/disabled states, and live result notification.

- [ ] **Step 5: Verify authority and reversibility**

  Assert selection leaves the itinerary unchanged, apply changes the same itinerary artifact and increments revision exactly once, and undo restores the prior content while retaining traceability.

- [ ] **Step 6: Verify motion and contrast modes**

  Exercise reduced-motion and higher-contrast emulation. Confirm the same state changes and feedback remain available, with no required information encoded solely by animation or color.

- [ ] **Step 7: Run browser verification**

  Build the JS artifacts required by the web example, start the configured Vite server, and run only `tests/genui-possibilities.spec.ts`. Expected: all tests pass in Chromium. Inspect the desktop and 390 px surface in the browser for hierarchy, clipping, focus, and action-obscuring feedback; capture evidence for any visual defect fixed during this task.

- [ ] **Step 8: Run project validation**

  Run the journey-state Node tests, the possibility-score Node tests, the web production build, the focused Playwright suite, `moon check`, and `moon test`. Expected: zero failures. Then run `moon info && moon fmt` and inspect generated interface changes; no MoonBit public API change is expected.

- [ ] **Step 9: Commit browser evidence**

  Commit Playwright coverage and any minimal test-entry configuration together. Keep unrelated generated or vendored changes out of the commit.

---

### Task 5: Close the approved specification

**Files:**
- Modify: `docs/superpowers/specs/2026-07-19-legible-instrument-design.md`

**Interfaces:**
- Consumes: verification evidence from Tasks 1–4.
- Produces: an auditable completion record for the approved design direction.

- [ ] **Step 1: Check every acceptance criterion against evidence**

  Record the exact command or browser observation supporting each criterion: canonical context replacement, compositional laws, reference hierarchy, preview/apply/revision/undo, desktop/mobile parity, pointer/keyboard/screen-reader equivalence, reduced motion, contrast, overflow, focus, comparison completeness, and unobscured feedback.

- [ ] **Step 2: Mark status accurately**

  Change the specification status to executed only if every acceptance criterion has evidence. If any criterion is unverified, retain the current status and name the remaining blocker without weakening or deleting the criterion.

- [ ] **Step 3: Run the final documentation check**

  Run `moon check`. Expected: zero errors. Confirm the specification and `.impeccable.md` agree on design-first composability and that neither reinstates the retired brand direction.

- [ ] **Step 4: Commit specification closure**

  Commit the evidence/status update separately so reviewers can distinguish the design decision, implementation, and verified closure.
