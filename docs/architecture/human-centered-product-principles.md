# Human-centered product principles

Canopy is a thinking instrument that helps people stay oriented while moving
between thought, structure, and action. These principles govern how the
product behaves toward the person using it. They are the canonical reference;
other documents link here rather than restating the rules.

## Principles

### Human authority

The person decides. The system proposes structure, surfaces context, and
generates changes, but every consequential system-originated transition is
inspectable and governed by explicit human authority or a revocable policy the
person chose. The tool does not override the person's judgment about their own
work.

### Negotiable structure

Structure produced by the system — links, clusters, groupings, projections —
is provisional. It is offered as a revisable hypothesis, not an established
fact. The person can name, correct, suppress, or replace any inferred
structure with their own. Explicit user-authored organization always takes
precedence over inferred organization.

### Legibility and reasons

When the system acts — surfacing context, proposing a link, generating a UI
change — it explains why, in a way the person can read without special
tools. Opaque justifications are not sufficient. The person should be able
to understand and evaluate each proposal before deciding.

### Reversibility and contestability

Every system-originated document or interface change has a reversal path, and
every interpretation can be challenged. An irreversible external effect
requires explicit approval before it occurs. The person must be able to contest
a classification, a link, a generated change, or a resurfaced item without
losing their place.

### Cognitive stability and pacing

The interface must not become cognitively unstable. Changes — especially
generated or inferred ones — must not steal attention, fragment
orientation, or force the person into a reactive loop. The person controls
the pace. Proactive behavior is quiet by default and opt-in.

### Accessible equivalence

Every interaction available through a visual or generated interface must
have an equivalent path through keyboard navigation and screen-reader
accessible controls. Accessibility is not a fallback layer; it is a
design requirement on parity.

### Local ownership and data minimization

The person owns local copies of their data, with peer-to-peer sync that does not
require a central server. The system transmits no more data than the current
action requires and does not depend on external services to preserve the
person's work.

## Anti-goals

The following are explicit non-goals. A feature that introduces any of
these patterns is rejected regardless of its technical merits:

- **Consentless curation** — the system modifying, hiding, or
  reorganizing the person's content without an explicit, reversible
  decision.
- **Attention and engagement optimization** — optimizing for time spent,
  click-through, or return frequency rather than for the person's stated
  task.
- **One machine interpretation as truth** — presenting a single
  algorithmic output as the correct reading of the person's work, without
  alternative views or correction paths.
- **Cognitively unstable UI** — interfaces that change faster than the
  person can orient, or that introduce surprise state transitions without
  clear cause and reversal.
- **Inaccessible fallback** — any interaction path that degrades to a
  non-equivalent experience for keyboard or screen-reader users.
- **Machine-readable but human-unintelligible audit** — logging or
  justification formats that only a tool, not the person, can interpret.
- **Technical safety mistaken for product value** — treating schema
  validation, sandboxing, or deterministic replay as sufficient evidence
  that the product serves the person well.

## Product gates

Every significant product change must pass the applicable agency and inclusion
gates before it can be claimed complete. Adaptive or generated behavior must
pass all three gates:

### Agency and contestability gate

The person can inspect the change, understand its reason, accept or reject it,
and reverse it after the fact. Irreversible external effects require explicit
approval before execution.

### Inclusion and cognitive steady-state gate

The change is accessible through keyboard and screen reader on equal
terms. It does not destabilize orientation, demand attention faster than
the person can process, or create a reactive loop the person cannot
escape.

### Net-value gate

The change produces a measurably better outcome on a named task than a fixed,
deterministic, rules-based alternative. Novelty alone is not justification; the
generated or adaptive behavior must earn its complexity.

## Generative instruments

Canopy's generated surfaces — whether UI, structure, or context — are
instruments the person plays, not outputs the system delivers. A
generated change is meaningful only when it is legible, acceptable or
rejectable, reversible, oriented to the person's current task, equivalent
across input modalities, and accompanied by a reason. Generation that
cannot meet these conditions is not shipped, regardless of its
sophistication.
