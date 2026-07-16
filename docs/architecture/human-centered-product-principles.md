# Human-centered product principles

Canopy is a thinking instrument that helps people stay oriented while moving
between thought, structure, and action. These are the canonical product
invariants; other documents link here rather than restating them.

## Principles

### Human authority

The system proposes structure, surfaces context, and generates changes, but
every consequential system-originated transition is inspectable and governed by
explicit human authority or a revocable policy the person chose. The tool does
not override the person's judgment about their own work.

### Negotiable structure

System-produced structure — links, clusters, groupings, projections — is a
revisable hypothesis, not an established fact. The person can name, correct,
suppress, or replace any inferred structure. Explicit user-authored
organization always takes precedence over inferred organization.

### Legibility and reasons

When the system acts, it explains why in a way the person can read without
special tools. Opaque justifications are not sufficient.

### Reversibility and contestability

Every system-originated change has a reversal path, and every interpretation
can be challenged without displacing the person's current work. An irreversible
external effect requires explicit approval before it occurs.

### Cognitive stability and pacing

Changes must not steal attention, fragment orientation, or force the person
into a reactive loop. The person controls the pace. Proactive behavior is
quiet by default and opt-in.

### Accessible equivalence

Every interaction available through a visual or generated interface must have
an equivalent path through keyboard navigation and screen-reader accessible
controls. Accessibility is a design requirement on parity, not a fallback
layer.

### Local ownership and data minimization

The person owns local copies of their data, with peer-to-peer sync that does
not require a central server. The system transmits no more data than the
current action requires and does not depend on external services to preserve
the person's work.

## Anti-goals

Features that introduce any of these patterns are rejected regardless of
technical merit:

- **Consentless curation** — modifying, hiding, or reorganizing content
  without an explicit, reversible decision.
- **Attention optimization** — optimizing for time spent, click-through, or
  return frequency rather than the person's stated task.
- **One interpretation as truth** — presenting a single algorithmic output as
  the correct reading without alternative views or correction paths.
- **Cognitively unstable UI** — interfaces that change faster than the person
  can orient, or that introduce surprise transitions without clear cause and
  reversal.
- **Inaccessible fallback** — any path that degrades to a non-equivalent
  experience for keyboard or screen-reader users.
- **Machine-unintelligible audit** — logging or justification formats that
  only a tool, not the person, can interpret.
- **Technical safety as product value** — treating schema validation,
  sandboxing, or deterministic replay as sufficient evidence the product
  serves the person.

## Product gates

Every significant product change must pass the applicable gates. Adaptive or
generated behavior must pass all three:

### Agency and contestability

The person can inspect the change, understand its reason, accept or reject it,
and reverse it. Irreversible external effects require explicit approval before
execution.

### Inclusion and cognitive steady-state

The change is accessible through keyboard and screen reader on equal terms. It
does not destabilize orientation or create an inescapable reactive loop.

### Net value

The change produces a measurably better outcome on a named task than a fixed,
deterministic, rules-based alternative. Novelty alone is not justification.

## Generative instruments

Generated surfaces are instruments the person plays, not outputs the system
delivers. A generated change is meaningful only when it is legible, acceptable
or rejectable, reversible, oriented to the person's task, equivalent across
input modalities, and accompanied by a reason. Generation that cannot meet
these conditions is not shipped.
