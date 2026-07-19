# Canopy interaction craft design

**Status:** Executed and verified in PR #913; merge deferred  
**Date:** 2026-07-19  
**Scope:** Strengthen the implementation decisions in `.impeccable.md` without changing the Legible Instrument product direction.

## Problem

The current design context defines the right product invariants and gives timing targets, but it does not tell an implementer when motion should be omitted, how input modality changes feedback, or which animation mechanics preserve responsiveness. An implementer can satisfy the listed durations while still adding frequent, decorative, non-interruptible, or touch-hostile motion.

## Decision

Keep the Product Quality Model, Design Principles, Compositional Design, and causal interaction model unchanged. Replace the loose motion and response-timing guidance in **Visual and Interaction Constraints** with a compact interaction decision framework, then extend **Validation Gates** with observable checks for that framework.

Canopy's interaction personality is **calm, precise, immediate**. Motion explains a causal change or confirms an action; it does not decorate routine work.

## Interaction Decision Framework

Every proposed animation is evaluated in this order. A failed gate means the animation is removed rather than tuned.

### 1. Frequency

- Keyboard-initiated actions and other actions used hundreds of times per day do not animate spatially.
- Actions used tens of times per day omit motion or reduce it to near-immediate state feedback.
- Occasional overlays, disclosures, and notifications may use standard motion.
- Rare or first-time moments may use restrained delight only when it supports comprehension or feedback.

### 2. Purpose

Motion must serve at least one named purpose: spatial consistency, state indication, explanation, input feedback, or preventing a jarring discontinuity. "Looks polished" is not a purpose.

### 3. Input modality

- Pointer press feedback may use a subtle `scale(0.97)` response when scaling does not obscure content or disturb layout.
- Keyboard activation changes state immediately without positional or scale motion. Focus remains visible and stable.
- Hover-only motion is limited to devices matching `(hover: hover) and (pointer: fine)`.
- Touch and keyboard paths expose the same result, authority, and recovery behavior as pointer paths.

### 4. Motion mechanics

- Entering or exiting UI uses `cubic-bezier(0.23, 1, 0.32, 1)`; movement or morphing already on screen uses `cubic-bezier(0.77, 0, 0.175, 1)`; hover and color changes use `ease`; constant motion uses `linear`. UI motion never uses `ease-in`.
- Pointer press feedback targets 100–160 ms, small popovers and tooltips 125–200 ms, and disclosures 150–250 ms. Routine UI motion remains below 300 ms. Exit is no slower than entry and is usually faster; a deliberate hold may be slow, but release returns within 200 ms.
- Retargetable UI uses transitions rather than keyframes so rapid reversal continues from the current state. Stable content does not replay entrance motion.
- Predetermined motion animates `transform` and `opacity`; layout properties are not animated. Programmatic motion must preserve the same off-main-thread behavior when possible.
- Elements do not enter from `scale(0)`. Anchored surfaces transform from their trigger; modal surfaces remain centered.
- After the first tooltip opens, moving among adjacent tooltip triggers reveals the next tooltip immediately without another delay or entrance animation.
- Stagger is reserved for rare explanatory sequences, uses 30–80 ms between items, and never delays interaction.

### 5. Reduced motion

Reduced-motion mode removes position, scale, parallax, and vestibular movement. Immediate state changes plus restrained opacity or color feedback remain when they help explain cause and effect. Reduced motion preserves comprehension rather than deleting all feedback.

## Relationship to Existing Principles

This framework implements, rather than replaces, the existing laws:

- **Cognitive stability:** motion cannot displace focus, selection, scroll position, or artifact identity.
- **One causal response:** one input has one dominant visible consequence; unaffected regions remain still.
- **Human authority:** preview, apply, external execution, and undo remain perceptually distinct.
- **Accessible equivalence:** modality changes the feedback technique, not the available evidence or action.
- **Information parity:** responsive reflow and motion never remove decision-critical content.

## Validation Gates

A significant interaction passes only when direct observation confirms:

1. Repeated keyboard activation updates immediately without spatial animation or focus loss.
2. Rapid pointer reversal or repeated toggling retargets smoothly instead of restarting or queuing motion.
3. Touch devices do not retain hover-only visual states after activation.
4. Reduced-motion mode preserves cause, state, and completion feedback without vestibular movement.
5. Enter, exit, and on-screen movement use the specified easing category and remain below the applicable duration ceiling; exit does not lag behind entry.
6. Adjacent tooltips respond immediately after the first tooltip opens.
7. Animated properties do not cause avoidable layout or paint work.
8. Slow-motion or frame-by-frame inspection shows synchronized properties and the correct transform origin.
9. Motion never implies that preview committed a change or that undo erased history.

## Non-goals

- Defining a component library, renderer API, or motion abstraction.
- Prescribing springs, drag velocity, damping, or gesture physics before a feature needs them.
- Adding celebratory animation to the current workbench.
- Revisiting the palette, typography, spatial laws, or broader Legible Instrument direction.
- Copying a general motion handbook into the repository.

## Acceptance Criteria

- `.impeccable.md` presents frequency, purpose, modality, mechanics, and reduced motion as an ordered decision framework.
- The file gives exact default easing curves, bounded duration ranges, and asymmetric entry and exit behavior without making CSS the product architecture.
- Pointer, keyboard, touch, and reduced-motion behavior are distinct but outcome-equivalent.
- Dynamic UI prefers interruptible transitions; stable content does not replay entrance motion.
- Repeated tooltip navigation becomes immediate after the first tooltip, and decorative stagger never blocks interaction.
- Validation gates cover rapid retargeting, keyboard immediacy, touch hover, reduced motion, performance, transform origin, and authority.
- No existing product-quality, compositional, accessibility, authority, or reversibility rule is weakened or duplicated inconsistently.
