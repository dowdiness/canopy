# Legible Instrument design direction

**Status:** Approved direction; written specification awaiting review  
**Date:** 2026-07-19  
**Scope:** Canopy-wide UI and UX direction

## Decision

Canopy adopts **Legible Instrument** as its design direction.

Canopy is a thinking instrument that helps people understand structure, inspect change, make consequential decisions, and recover from mistakes. Its quality comes from how clearly it communicates state, causality, available action, and the path back from error.

This decision replaces the current design direction in `.impeccable.md` with principles derived from Canopy's purpose and product invariants. Visual and interaction choices are evaluated by how well they preserve orientation, support judgment, and keep the person in control.

## First principles

Usability is defined by reducing five costs:

1. **Translation cost:** converting a human goal into product or implementation terminology.
2. **Orientation-recovery cost:** finding one's place after the interface changes.
3. **Verification cost:** establishing whether a system proposal is correct and appropriate.
4. **Action-uncertainty cost:** predicting what an available action will do.
5. **Recovery cost:** returning to a valid state after a mistake.

A design improvement must reduce at least one cost without materially increasing another. Fewer controls, fewer clicks, or greater visual novelty are not sufficient evidence of better usability.

## Product model

Significant interactions should make this causal sequence legible:

```text
current state
→ new fact or human intent
→ proposed change
→ before/after comparison
→ human acceptance, rejection, or correction
→ traceable new state
```

The interface divides responsibilities into five conceptual regions. Their presentation adapts to the task, available space, and amount of evidence.

- **Context:** object identity, revision, save state, and the event that requires attention.
- **Artifact:** the persistent object being read or edited.
- **Change:** the proposed difference, its reason, confidence where meaningful, and affected scope.
- **Decision:** preview, edit, apply, reject, and undo.
- **Trace:** authorship, sources, causal revision, and history.

Simple tasks show only the regions needed to act. Complexity is disclosed without moving or replacing the artifact unnecessarily.

## Interaction invariants

### Human authority

- Selecting a proposal does not mutate the artifact.
- System-originated changes remain previews until explicitly applied or covered by a revocable policy chosen by the person.
- Generated or inferred structure can be renamed, corrected, suppressed, or replaced.
- Irreversible external effects are separate from local edits and require explicit approval immediately before execution.

### Cognitive stability

- Artifact identity, selection, focus, scroll position, and relevant expansion state survive preview and apply transitions when technically possible.
- New information appears near its cause.
- Updates do not replay entire lists, reset reading position, or reorder unrelated content.
- Inline comparison is preferred over navigation to a separate result page or a modal.

### Legibility and reasons

- Actions use specific result labels rather than generic labels such as “Continue” or “Submit.”
- Proposals show what changes, what remains fixed, why the change is proposed, and which facts support it.
- Alternatives use shared, aligned comparison axes.
- Confidence is shown only when calibrated and meaningful; it never substitutes for evidence.

### Reversibility

- Reversible actions execute without confirmation dialogs and expose immediate undo.
- Undo creates a new traceable revision rather than erasing history.
- Confirmation is reserved for destructive or externally irreversible effects.

### Accessible equivalence

- Visual grouping and semantic grouping match.
- Visual order and DOM order match.
- Native controls are preferred before custom controls.
- Keyboard and screen-reader users can inspect reasons, compare outcomes, apply, reject, edit, and undo on equal terms.
- Focus remains at the causal interaction point after an update unless the task explicitly moves to a new object.

## Visual language

### Color

Canopy uses a light, slightly warm neutral foundation.

- Background: a quiet neutral that supports sustained attention.
- Working surface: a closely related neutral, distinguished by spacing or a fine boundary.
- Primary text: high-contrast neutral.
- Secondary text: a quieter neutral that remains readable at small sizes.
- Boundaries: low-contrast neutral, strengthened only where separation affects comprehension.
- Interactive and selected: a consistent cool accent.
- Warning: amber.
- Error or destructive: red.
- Verified, protected, or complete: green.

Color is semantic, sparse, and redundant with text or shape. A screen normally has one dominant state color. Themes are selected for context, accessibility, and sustained readability rather than treated as product identity.

### Surfaces and hierarchy

- Hierarchy comes from order, spacing, alignment, typography, and fine rules.
- Elevation is used only when elements genuinely overlap or move independently.
- A container earns a visible boundary when it represents a selectable object, separates a distinct responsibility, or must remain coherent while moving.
- Corner radii communicate control boundaries or object identity rather than decorating every region.
- Related content is grouped by proximity before borders or containers are added.
- Large surfaces remain visually quiet so state and content retain priority.

### Typography

- UI uses the platform system font by default.
- Code, identifiers, and syntax use a legible monospace font.
- Large headings use tighter tracking and leading.
- Body copy uses comfortable leading and neutral tracking.
- Small labels may use slightly positive tracking.
- Weight, spacing, and position establish hierarchy before size or color.
- All-caps text is limited to short status labels.
- Layout spacing scales with text; fixed pixel geometry must not break text zoom.

Canopy's visual identity comes from precise alignment, concise language, stable structure, and causal behavior—not a proprietary font or accent color.

## Motion and response

Motion communicates causality; it does not decorate.

- Press feedback begins on pointer-down or key activation.
- Press feedback targets 80–100 ms.
- Selection-state transitions target 120–160 ms.
- Inline disclosure targets approximately 200 ms.
- Large spatial transitions use critically damped, non-overshooting behavior only when continuity requires movement.
- Keyboard focus appears immediately and is not animated.
- List updates preserve stable nodes and animate only the changed element when motion clarifies the change.
- Bounce, parallax, decorative stagger, looping motion, and indiscriminate entrance animation are excluded.
- Springs are reserved for directly manipulated, interruptible gestures. Ordinary state changes use simple, interruptible CSS transitions.

Reduced motion preserves state feedback through color, opacity, or immediate change while removing vestibular movement.

## Responsive behavior

Responsive design preserves decision-critical information rather than preserving desktop geometry.

### Desktop

- Artifact and change can remain visible together for precise comparison.
- Dense tables, trees, outlines, and diffs are appropriate.
- Every workflow supports efficient keyboard operation.
- Hover may reveal supplemental information but never contains required information or the only action path.

### Mobile

- Information follows Context → Artifact → Change → Decision.
- Comparison axes move into each candidate rather than disappearing.
- Primary actions remain close to the affected content and do not obscure it.
- Touch targets are at least 44 CSS pixels.
- Hover is never assumed.
- Progressive disclosure replaces information deletion.

Desktop and mobile must reach equivalent decisions using equivalent evidence.

## Component responsibilities

Components are named for their product responsibility rather than their appearance:

- **Identity header:** object, revision, and save or sync state.
- **Change notice:** new fact, source, timestamp, and urgency.
- **Artifact view:** persistent readable and editable object.
- **Comparison row:** aligned alternative outcomes.
- **Reason block:** rationale, facts, and uncertainty.
- **Decision actions:** preview, edit, apply, and reject.
- **Revision trace:** history, causal source, and undo.
- **Inline diagnostic:** problem, location, consequence, and correction path.

Component abstractions are named for product responsibility and observable behavior. Appearance remains replaceable without changing their contract.

## Language

- Labels describe outcomes: “Apply to itinerary,” not “Continue.”
- Reasons cite observable facts before interpretations.
- Status text answers what happened and whether action is required.
- Error text identifies the problem, its consequence, and the next valid action.
- Technical terminology is progressively disclosed and never required for a basic user goal when a plain-language equivalent exists.

## Validation

A design change is evaluated against observable task outcomes:

- Time to identify the current object and state.
- Time to locate the changed information.
- Accuracy of predicting an action's result before activating it.
- Time and success rate for recovering from an error.
- Preservation of location and focus across updates.
- Information parity across desktop, mobile, keyboard, and screen reader paths.
- Ability to inspect, reject, correct, apply, and reverse system proposals.

A polished appearance does not compensate for failure on these measures.

## Migration boundary

The direction change is implemented in two stages:

1. Replace `.impeccable.md` with the Legible Instrument principles, visual rules, interaction invariants, and validation criteria.
2. Migrate UI surfaces incrementally, beginning with `genui-possibilities`, using it as the reference implementation. Existing screens are not mechanically recolored; each migration must preserve its task, causal structure, and accessibility contract.

A migrated surface must not introduce a second design system beside the new direction. Shared tokens and patterns are extracted only after the reference implementation demonstrates that they generalize.

## Acceptance criteria

- `.impeccable.md` defines Canopy through the five usability costs, causal interaction model, and human-centered product invariants.
- The replacement direction specifies visual hierarchy in terms of attention, comprehension, and task context.
- `genui-possibilities` demonstrates the new direction through stable hierarchy, restrained semantic color, precise comparison, and immediate feedback.
- The demo preserves preview-before-apply, stable artifact identity, explicit reasoning, revision history, and undo.
- Desktop and 390 px mobile layouts retain every decision-critical comparison field.
- Pointer, keyboard, and screen-reader paths expose equivalent actions and evidence.
- Reduced-motion and higher-contrast modes preserve comprehension.
- Browser verification confirms no horizontal overflow, focus loss, hidden comparison field, or action-obscuring feedback.
