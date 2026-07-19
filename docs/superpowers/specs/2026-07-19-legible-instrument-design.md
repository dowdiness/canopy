# Legible Instrument design direction

**Status:** Executed and verified
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

## Compositional design

Composability means that content and functions can be combined while the resulting interface still forms one coherent experience. Reuse alone is insufficient. A composition succeeds when hierarchy, relationships, reading order, and action priority remain understandable as content, context, and viewport change.

### One focal question

Each screen or bounded workspace has one focal question. Every region has a role in answering it: subject, cause, evidence, alternative, action, or result. A component does not bring its own claim to visual primacy.

For a disruption workspace, the focal question may be “How should this plan change?” The disruption explains why the question exists, the artifact provides the subject, alternatives provide possible answers, and actions commit the decision.

### Relative emphasis

Emphasis belongs to the composition rather than the component. The same content may be primary in one context, supporting in another, and reference material in a third. A workspace has at most one primary region; supporting and reference regions remain available without competing for attention.

Urgency, importance, and visual emphasis are independent properties. Status color communicates state. Position, typography, spacing, and order establish hierarchy.

### Spatial grammar

Canopy uses a small set of layout relationships:

- **Stack:** sequential reading or action.
- **Cluster:** short peers with equal weight, such as metadata or compact actions.
- **Split:** two responsibilities that benefit from simultaneous view, such as artifact and proposed change.
- **Grid:** multiple objects compared on shared axes.
- **Inset:** supporting information attached to a local subject.
- **Overlay:** a short task that must suspend the underlying workflow.

These terms describe relationships rather than fixed components. The composition chooses the relationship; product components supply the content and behavior.

Overlay is reserved for cases where suspending the current task is necessary, such as approval of an irreversible effect. Supplemental detail remains in the flow.

### Relational spacing

Spacing communicates semantic distance:

```text
within element
< within group
< between groups
< between responsibilities
```

The exact values may change with density, text size, and viewport, but the ordering remains stable. Related content is made legible through proximity before an enclosing surface is introduced.

### Shared alignment

Related and comparable information shares a small number of visual anchors. Names, values, times, costs, diagnostics, and actions align across component boundaries when the alignment supports scanning or comparison.

Responsive layouts may transform an alignment axis. A desktop comparison column can become a repeated label/value alignment inside each mobile option. The relationship and comparison axis remain available.

### Boundary economy

A boundary communicates independent identity, responsibility, selection, movement, or overlap. Parent and child regions do not repeat equivalent framing. When spacing is sufficient to communicate grouping, another background or border is not added.

The composition selects the minimum effective combination of spacing, rule, background difference, and elevation. Each additional boundary must communicate a distinct relationship.

### Color budget

Color is a shared attention budget managed by the composition. Components request semantic roles; they do not introduce local accent systems.

- Ordinary content remains neutral.
- Interactive state uses the shared interaction role.
- Warning, error, and success roles appear only when those states are present.
- State colors do not substitute for hierarchy or grouping.
- Simultaneous states remain distinguishable through text, shape, iconography, and control state as well as color.

### Action mapping

Control placement communicates its target. Local actions remain near the object they affect. Workspace actions appear at the end of the decision flow. Preview and apply remain in the same decision region; undo appears with the resulting revision.

Each bounded decision has one primary action. Selection, preview, commit, external execution, and undo remain perceptually distinct even when they occur in sequence.

### Information-preserving reflow

Responsive composition preserves the focal question, evidence, alternatives, action mapping, and reading order. It may change simultaneity, density, columns, and spacing. It does not remove a decision-critical comparison axis merely to preserve a compact layout.

Desktop favors simultaneous comparison. Mobile favors a sequential narrative. Both must support the same informed decision.

### Coordinated motion

Motion belongs to the causal event rather than individual components. One input produces one dominant motion response. Only the source, affected result, or changed relationship moves.

When several regions update, their behavior communicates a single cause. Stable content does not replay entrance motion, and child components do not run unrelated transitions. Interaction type—not component identity—determines timing.

### Design primitives and product components

Design primitives express perceptual relationships: Stack, Cluster, Split, Grid, Inset, Rule, text roles, action groups, and status indicators.

Product components express Canopy responsibilities: identity, artifact, change, comparison, reason, decision, revision, and diagnostic.

Product components compose design primitives without owning an isolated visual language. Their surrounding composition controls emphasis, outer spacing, alignment, and boundaries. Components own their semantic content, internal state, direct affordances, and accessibility contract.

### Composition laws

Every composition preserves:

1. **Focal clarity:** one question remains visually primary.
2. **Relationship fidelity:** spacing, alignment, and boundaries reflect semantic relationships.
3. **Action locality:** a control's target and consequence are apparent from placement and wording.
4. **Information parity:** a reflow retains the evidence required for the same decision.
5. **Identity stability:** the same artifact remains recognizable across preview, update, and projection.
6. **Authority:** composition never turns selection or preview into implicit commit.
7. **Reversibility:** combining reversible operations defines a coherent reversal boundary.
8. **Accessible order:** visual, keyboard, and assistive-technology order express the same relationships.
9. **Negotiability:** inferred grouping, hierarchy, emphasis, and projection remain visibly distinguishable from user-authored organization and can be corrected, suppressed, or replaced.

Semantic interaction models and projection infrastructure exist to preserve these design laws. They support the visual grammar rather than define it.

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
- The replacement direction defines composability through one focal question, relative emphasis, relational spacing, shared alignment, boundary economy, color budget, action mapping, information-preserving reflow, and coordinated motion.
- `genui-possibilities` demonstrates the new direction through stable hierarchy, restrained semantic color, precise comparison, and immediate feedback.
- The demo preserves preview-before-apply, stable artifact identity, explicit reasoning, revision history, and undo.
- Desktop and 390 px mobile layouts retain every decision-critical comparison field.
- Pointer, keyboard, and screen-reader paths expose equivalent actions and evidence.
- Reduced-motion and higher-contrast modes preserve comprehension.
- Browser verification confirms no horizontal overflow, focus loss, hidden comparison field, or action-obscuring feedback.

## Execution evidence

Verified on 2026-07-19 against the `genui-possibilities` reference surface:

- **Canonical direction:** `.impeccable.md` defines the five usability costs, causal interaction model, human-centered invariants, and design-first composability. Review of the replacement text found no retired dark-surface, purple-accent, glass, material-metaphor, or proprietary-font direction.
- **Composition and hierarchy:** `genui-possibilities.html` exposes one primary question and named artifact, comparison, preview, action, and revision regions. The focused browser suite verifies every response exposes response, evidence, arrival, cost, and consequence fields.
- **Authority and reversibility:** `node --test src/genui-journey-state.test.mjs` passed 5/5. The reducer and browser checks verify selection does not mutate the itinerary, apply creates exactly one revision, protected content survives every response, and undo restores prior content as a new revision.
- **Stable identity and focus:** Browser sentinels remain attached to all four itinerary nodes and all three response nodes after apply and undo. Keyboard tests verify roving radio behavior, preview, apply, revision, undo, live status feedback, and focus restoration.
- **Desktop, mobile, pointer, keyboard, and accessibility parity:** `GENUI_POSSIBILITIES_URL=http://localhost:5176/genui-possibilities.html npx playwright test tests/genui-possibilities.spec.ts --project=chromium --reporter=line` passed 7/7. Accessible roles, names, checked and disabled states expose the same actions and decision evidence used by pointer and keyboard paths. Desktop and 390 px checks retain every comparison field with zero horizontal overflow and unobscured actions, preview, revision, and feedback.
- **Motion and contrast:** The browser suite verifies reduced-motion mode removes transition, animation, and smooth-scroll dependencies. Forced-colors mode retains selected state, risk, protected content, consequences, controls, and accessible names without relying on color alone.
- **Build and workspace validation:** `npm run build` passed. `moon test` passed 3,639 wasm-gc tests, 1,937 JavaScript tests, and 70 native tests with zero failures. `moon info && moon fmt` completed successfully with no MoonBit public API change introduced by this HTML/CSS/JavaScript surface.
