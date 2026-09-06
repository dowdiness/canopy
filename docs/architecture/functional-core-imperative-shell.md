# Functional Core / Imperative Shell

Canopy separates deterministic domain decisions from effects. This document is
the repository's source of truth for that boundary.

Domain transformations, validation, lowering, and state-transition decisions
belong in the functional core. Pass inputs explicitly and return values, next
state, commands, or structured diagnostics. Core decisions must not depend on
the filesystem, network, clock, random sources, DOM, provider clients, or
mutable session state.

The imperative shell owns I/O, scheduling, cancellation, replay cursors,
lifecycle mutation, provider adapters, DOM/session adapters, and persistence.
It translates effects into core inputs and executes the returned decisions.
Keep this wiring thin so domain behavior can be tested without those effects.

Prefer state transitions that compute the next state and decision from the
current state and an event. A mutable facade is acceptable when it remains a
shell around deterministic transition logic.

Validated core results must not expose internal mutable collections. Use
immutable views or defensive copies according to the ownership boundary.
Local builder mutation is permitted in a pure function only when it has no
observable external effect and is justified by the operation being built.

Test the functional core with deterministic unit and property tests. Focus
shell tests on effect wiring, integration boundaries, and a small number of
end-to-end cases.
