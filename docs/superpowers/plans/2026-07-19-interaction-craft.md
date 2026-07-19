# Interaction craft implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `.impeccable.md` an actionable gate for deciding when motion belongs and how to verify it.

**Architecture:** Preserve the Legible Instrument product model, composition laws, and system-change invariants. Add one ordered interaction framework and direct behavioral validation; introduce no runtime API or dependency.

**Tech Stack:** Markdown, Slopless, MoonBit workspace validation.

## Global constraints

- Work only in the isolated `genui-possibility-probes` worktree and modify only `.impeccable.md` during implementation.
- Keep the approved product model, palette, typography, composition laws, preview/apply authority, stable identity, revision trace, and undo unchanged.
- Interaction personality is **calm, precise, immediate**.
- Evaluate motion in this order: frequency, purpose, input modality, mechanics, reduced motion. A failed gate removes the motion rather than tuning it.
- Keyboard activation has no position or scale motion; pointer press may use `scale(0.97)`; hover motion requires `(hover: hover) and (pointer: fine)`.
- Use the approved easing, duration, interruptibility, transform-origin, tooltip, stagger, and reduced-motion rules verbatim from `docs/superpowers/specs/2026-07-19-interaction-craft-design.md`.

---

### Task 1: Strengthen the canonical interaction gate

**Files:** Modify `.impeccable.md:125-168`; reference `docs/superpowers/specs/2026-07-19-interaction-craft-design.md`.

**Interfaces:** Consumes the existing visual constraints and validation gates. Produces repository-wide interaction guidance only; no renderer or component interface.

- [ ] **Step 1: Add the ordered decision framework**
  Replace the loose timing and reduced-motion bullets with concise frequency, purpose, input-modality, mechanics, and reduced-motion rules from the approved specification. Preserve the surrounding foundation, color, typography, focus, touch-target, preview, identity, revision, and undo rules.

- [ ] **Step 2: Add observable interaction gates**
  Extend validation with keyboard immediacy, rapid retargeting, touch-hover behavior, instant adjacent tooltips, reduced-motion comprehension, asymmetric exit timing, transform origin, and layout/paint checks. Keep the existing authority and information-parity questions.

- [ ] **Step 3: Validate the workspace**
  Run `moon check`. Expected: exit 0 and zero errors; existing vendored warnings may remain.

- [ ] **Step 4: Validate the prose**
  Run `mkdir -p .slopless/findings` and `rtk proxy npx slopless .impeccable.md > .slopless/findings/2026-07-19-interaction-craft-implementation.json`. Fix concrete style findings; document technical-vocabulary readability scores without suppressing them.

- [ ] **Step 5: Inspect invariant preservation**
  Confirm the rendered order is `frequency → purpose → input modality → motion mechanics → reduced motion`, and that the causal model, nine composition laws, preview before apply, stable identity, revision trace, and undo remain present.

- [ ] **Step 6: Commit the guidance**
  Run `git add .impeccable.md && git commit -m "docs(design): strengthen interaction craft guidance"`. Expected: one commit containing only `.impeccable.md`.
